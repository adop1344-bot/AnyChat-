import '../../l10n/app_localizations.dart';
import 'api_error.dart';

/// Turns an [ApiError] into a localized, human-readable message.
///
/// The raw provider payload ([ApiError.raw]) is never shown as-is: markup and
/// JSON envelopes are reduced to the sentence inside them, and the length is
/// capped. The full original stays in the debug log.
String localizeApiError(AppLocalizations l10n, ApiError error) {
  final body = _errorBody(l10n, error);
  return '$body\n\n${_agentVoice(l10n, error.type)}';
}

String _agentVoice(AppLocalizations l10n, ApiErrorType type) {
  return switch (type) {
    ApiErrorType.authError => l10n.errAgentAuth,
    ApiErrorType.rateLimit => l10n.errAgentRateLimit,
    ApiErrorType.quotaExceeded => l10n.errAgentQuota,
    ApiErrorType.modelNotFound => l10n.errAgentModelNotFound,
    ApiErrorType.contextLengthExceeded => l10n.errAgentContextLength,
    ApiErrorType.invalidRequest => l10n.errAgentInvalidRequest,
    ApiErrorType.networkError => l10n.errAgentNetwork,
    ApiErrorType.timeout => l10n.errAgentTimeout,
    ApiErrorType.serverError => l10n.errAgentServer,
    ApiErrorType.unknown => l10n.errAgentUnknown,
  };
}

String _errorBody(AppLocalizations l10n, ApiError error) {
  switch (error.type) {
    case ApiErrorType.authError:
      return l10n.errAuth;
    case ApiErrorType.rateLimit:
      return l10n.errRateLimit(error.retryAfter ?? 30);
    case ApiErrorType.quotaExceeded:
      return l10n.errQuota;
    case ApiErrorType.modelNotFound:
      return l10n.errModelNotFound;
    case ApiErrorType.contextLengthExceeded:
      return l10n.errContextLength;
    case ApiErrorType.invalidRequest:
      return l10n.errInvalidRequest(
        readablePayload(error.details ?? error.raw, fallback: 'без пояснения'),
      );
    case ApiErrorType.networkError:
      return l10n.errNetwork;
    case ApiErrorType.timeout:
      return l10n.errTimeout;
    case ApiErrorType.serverError:
      return l10n.errServer;
    case ApiErrorType.unknown:
      return l10n.errUnknown(readablePayload(error.raw, fallback: 'пустой ответ'));
  }
}

/// Reduces a raw provider payload to one readable line.
String readablePayload(String value, {required String fallback}) {
  var text = value.replaceAll(RegExp(r'<[^>]*>'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return fallback;
  if (text.startsWith('{') || text.startsWith('[')) {
    final quoted = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(text);
    if (quoted == null) return fallback;
    text = quoted.group(1)!;
  }
  if (text.length <= 200) return text;
  return '${text.substring(0, 200)}…';
}
