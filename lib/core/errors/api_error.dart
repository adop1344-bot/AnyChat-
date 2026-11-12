import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../network/api_format.dart';

/// Human-readable categories of API failures.
enum ApiErrorType {
  authError,
  rateLimit,
  quotaExceeded,
  modelNotFound,
  contextLengthExceeded,
  invalidRequest,
  networkError,
  timeout,
  serverError,
  unknown,
}

/// A normalized API error. The user only ever sees a localized message built
/// from [type]; [raw] keeps the original body for the debug log.
class ApiError implements Exception {
  const ApiError({
    required this.type,
    this.statusCode,
    this.retryAfter,
    this.details,
    this.raw = '',
    this.cause,
  });

  final ApiErrorType type;
  final int? statusCode;

  /// Seconds to wait before retrying, when the provider reported it.
  final int? retryAfter;

  /// Provider-provided detail (used for `invalidRequest`).
  final String? details;

  /// Original response body / transport message. Never shown to the user.
  final String raw;

  final Object? cause;

  bool get isAuth => type == ApiErrorType.authError;

  @override
  String toString() {
    final code = statusCode == null ? '' : ' (HTTP $statusCode)';
    final why = details ?? (raw.isEmpty ? '' : raw);
    return why.isEmpty ? '${type.name}$code' : '${type.name}$code: $why';
  }

  /// Builds an error from an HTTP response body for the given wire format.
  factory ApiError.fromResponse({
    required int statusCode,
    required String body,
    required ApiFormat format,
    Map<String, List<String>>? headers,
  }) {
    final info = _extractInfo(format, body);
    final message = info.message;
    final lower = message.toLowerCase();
    final code = info.code.toLowerCase();
    final reason = info.reason.toLowerCase();
    final all = '$lower $code $reason';

    final retryAfter = _extractRetryAfter(headers, info);

    // Quota problems outrank the generic 429 rate-limit bucket.
    if (all.contains('insufficient_quota') ||
        all.contains('exceeded your current quota') ||
        all.contains('quota exceeded') ||
        all.contains('exceeded your quota') ||
        all.contains('quota_exceeded') ||
        all.contains('billing') ||
        all.contains('payment required')) {
      return ApiError(
        type: ApiErrorType.quotaExceeded,
        statusCode: statusCode,
        raw: body,
      );
    }

    if (all.contains('context_length_exceeded') ||
        all.contains('context length') ||
        all.contains('context_length') ||
        all.contains('prompt is too long') ||
        all.contains('maximum context') ||
        all.contains('reduce the length') ||
        (all.contains('input token count') && all.contains('exceed')) ||
        (all.contains('total token count') && all.contains('exceed')) ||
        all.contains('too many tokens')) {
      return ApiError(
        type: ApiErrorType.contextLengthExceeded,
        statusCode: statusCode,
        raw: body,
      );
    }

    if (all.contains('model_not_found') ||
        all.contains('model not found') ||
        all.contains('not_found_error') ||
        (all.contains('model') &&
            (all.contains('not found') ||
                all.contains('does not exist') ||
                all.contains('unknown model') ||
                all.contains('is not found')))) {
      return ApiError(
        type: ApiErrorType.modelNotFound,
        statusCode: statusCode,
        details: message.isEmpty ? null : message,
        raw: body,
      );
    }

    if (statusCode == 401 || statusCode == 403) {
      return ApiError(
        type: ApiErrorType.authError,
        statusCode: statusCode,
        raw: body,
      );
    }

    if (statusCode == 429) {
      return ApiError(
        type: ApiErrorType.rateLimit,
        statusCode: statusCode,
        retryAfter: retryAfter,
        raw: body,
      );
    }

    if (statusCode == 404) {
      return ApiError(
        type: ApiErrorType.modelNotFound,
        statusCode: statusCode,
        details: message.isEmpty ? null : message,
        raw: body,
      );
    }

    if (statusCode == 408 || statusCode == 504) {
      return ApiError(
        type: ApiErrorType.timeout,
        statusCode: statusCode,
        raw: body,
      );
    }

    if (statusCode >= 500) {
      return ApiError(
        type: ApiErrorType.serverError,
        statusCode: statusCode,
        raw: body,
      );
    }

    if (all.contains('overloaded') ||
        all.contains('temporarily unavailable') ||
        all.contains('service unavailable') ||
        all.contains('internal server error')) {
      return ApiError(
        type: ApiErrorType.serverError,
        statusCode: statusCode,
        raw: body,
      );
    }

    if (statusCode >= 400) {
      return ApiError(
        type: ApiErrorType.invalidRequest,
        statusCode: statusCode,
        details: message.isEmpty ? body : message,
        raw: body,
      );
    }

    return ApiError(
      type: ApiErrorType.unknown,
      statusCode: statusCode,
      raw: body,
    );
  }

  /// Rebuilds a displayable error from a persisted type name and details
  /// (see [Message.errorType] in the chat schema).
  factory ApiError.fromStored(String? typeName, {String? details}) {
    ApiErrorType type = ApiErrorType.unknown;
    for (final candidate in ApiErrorType.values) {
      if (candidate.name == typeName) {
        type = candidate;
        break;
      }
    }
    return ApiError(type: type, details: details, retryAfter: 30);
  }

  /// Converts a transport-level [DioException] into a normalized error.
  ///
  /// Callers should filter `DioExceptionType.cancel` (user pressed Stop)
  /// before calling this method.
  factory ApiError.fromDio(DioException exception, ApiFormat format) {
    switch (exception.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ApiError(
          type: ApiErrorType.timeout,
          raw: exception.message ?? exception.toString(),
          cause: exception,
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
        return ApiError(
          type: ApiErrorType.networkError,
          raw: exception.message ?? exception.toString(),
          cause: exception,
        );
      case DioExceptionType.badResponse:
        return ApiError.fromResponse(
          statusCode: exception.response?.statusCode ?? 0,
          body: '${exception.response?.data ?? exception.message ?? ''}',
          format: format,
          headers: exception.response?.headers.map,
        );
      case DioExceptionType.cancel:
        return ApiError(
          type: ApiErrorType.unknown,
          raw: exception.toString(),
          cause: exception,
        );
      default:
        final error = exception.error;
        if (error is SocketException || error is HttpException) {
          return ApiError(
            type: ApiErrorType.networkError,
            raw: '${error.runtimeType}: $error',
            cause: exception,
          );
        }
        return ApiError(
          type: ApiErrorType.unknown,
          raw: '${exception.message ?? ''} ${error ?? ''}',
          cause: exception,
        );
    }
  }

  static int? _extractRetryAfter(
    Map<String, List<String>>? headers,
    _BodyInfo info,
  ) {
    final headerValues = headers?['retry-after'] ?? headers?['Retry-After'];
    if (headerValues != null && headerValues.isNotEmpty) {
      final parsed = int.tryParse(headerValues.first.trim());
      if (parsed != null && parsed >= 0) return parsed;
    }
    return info.retryAfter ?? 30;
  }

  static _BodyInfo _extractInfo(ApiFormat format, String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      decoded = null;
    }

    var message = '';
    var code = '';
    var type = '';
    var reason = '';
    int? retryAfter;

    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map) {
        message = '${error['message'] ?? ''}';
        code = '${error['code'] ?? ''}';
        type = '${error['type'] ?? ''}';
        final innerStatus = error['status'];
        if (innerStatus != null) reason = '$innerStatus';
        final details = error['details'];
        if (details is List) {
          for (final item in details) {
            if (item is Map && item['reason'] != null) {
              reason = '$reason ${item['reason']}';
            }
          }
        }
        retryAfter = _parseRetryValue(
          error['retry_delay'] ?? error['retryAfter'],
        );
      } else if (error is String) {
        message = error;
      }
      if (message.isEmpty && decoded['message'] is String) {
        message = decoded['message'] as String;
      }
      if (decoded['type'] is String && '${decoded['type']}' != 'error') {
        type = '${decoded['type']}';
      }
      if (decoded['retryDelay'] != null) {
        retryAfter = retryAfter ?? _parseRetryValue(decoded['retryDelay']);
      }
      if (message.isEmpty && decoded['error_message'] is String) {
        message = decoded['error_message'] as String;
      }
    } else if (decoded is String) {
      message = decoded;
    } else if (body.isNotEmpty && decoded == null) {
      message = body;
    }

    // Anthropic puts the machine-readable kind in `error.type`.
    if (format == ApiFormat.anthropic && type.isNotEmpty) {
      code = code.isEmpty ? type : code;
    }

    return _BodyInfo(
      message: message,
      code: code,
      reason: reason,
      retryAfter: retryAfter,
    );
  }

  static int? _parseRetryValue(Object? value) {
    if (value == null) return null;
    if (value is num) return value.ceil();
    final text = value.toString();
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final seconds = int.tryParse(digits);
    if (seconds != null && seconds < 86400) return seconds;
    return null;
  }
}

class _BodyInfo {
  const _BodyInfo({
    required this.message,
    required this.code,
    required this.reason,
    required this.retryAfter,
  });

  final String message;
  final String code;
  final String reason;
  final int? retryAfter;
}
