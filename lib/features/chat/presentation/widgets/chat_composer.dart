import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../providers/domain/model_info.dart';
import '../../../settings/app_settings.dart';
import '../../../settings/state/settings_controller.dart';
import '../../domain/models.dart';
import 'attachment_sheet.dart';
import 'input_bar.dart';

class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({
    super.key,
    required this.isBusy,
    required this.onStop,
    required this.onSend,
    this.contextUsed,
    this.contextLimit,
    this.onContextTap,
  });

  final bool isBusy;
  final VoidCallback onStop;
  final Future<void> Function(String text, List<ChatAttachment> attachments)
      onSend;
  final int? contextUsed;
  final int? contextLimit;
  final VoidCallback? onContextTap;

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  static const int _maxAttachmentBytes = 20 * 1024 * 1024;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  final List<ChatAttachment> _pending = <ChatAttachment>[];

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Set<ModelModality> _supportedFor(AppSettings settings) {
    final modelId = settings.selectedModelId ?? '';
    return mediaModalitiesFor(modelId, declared: settings.modelModalities);
  }

  Set<ModelModality> _supportedNow() {
    final settings = ref.read(settingsControllerProvider).when(
          data: (AppSettings value) => value,
          loading: () => const AppSettings(),
          error: (Object error, StackTrace stack) => const AppSettings(),
        );
    return _supportedFor(settings);
  }

  static String? _mimeForExtension(String extension) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      default:
        return null;
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _pickFiles() async {
    final l10n = AppLocalizations.of(context);
    final extensions = <String>{};
    if (supported.contains(ModelModality.image)) {
      extensions.addAll(const <String>['jpg', 'jpeg', 'png', 'webp', 'gif']);
    }
    if (supported.contains(ModelModality.video)) {
      extensions.addAll(const <String>['mp4', 'mov', 'webm']);
    }
    if (supported.contains(ModelModality.audio)) {
      extensions.addAll(const <String>['mp3', 'wav']);
    }
    if (extensions.isEmpty) {
      extensions.addAll(const <String>[
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'mp3',
        'wav',
        'mp4',
        'mov',
        'webm',
      ]);
    }

    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions.toList(),
        dialogTitle: l10n.attach,
      );
    } catch (e) {
      if (mounted) _snack(l10n.errUnknown('$e'));
      return;
    }
    if (files.isEmpty) return;
    final file = files.first;
    final size = await file.length();
    if (!mounted) return;
    if (size == null || size > _maxAttachmentBytes) {
      _snack(l10n.attachmentTooBig);
      return;
    }
    final Uint8List fileBytes;
    try {
      fileBytes = await file.readAsBytes();
    } catch (e) {
      if (mounted) _snack(l10n.errUnknown('$e'));
      return;
    }
    if (!mounted) return;
    final mime = _mimeForExtension((file.extension ?? '').toLowerCase());
    if (mime == null) return;
    setState(() {
      _pending.add(
        ChatAttachment.fromBytes(
          mimeType: mime,
          name: file.name,
          bytes: fileBytes,
        ),
      );
    });
  }

  Future<void> _openAttachSheet() async {
    final supported = _supportedNow();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => AttachmentSheet(
        onAttach: (ChatAttachment attachment) =>
            setState(() => _pending.add(attachment)),
        onPickFiles: _pickFiles,
        warnUnsupported: !supported.contains(ModelModality.image),
      ),
    );
  }

  void _removePending(int index) {
    setState(() {
      if (index >= 0 && index < _pending.length) {
        _pending.removeAt(index);
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text;
    final attachments = List<ChatAttachment>.of(_pending);
    if (text.trim().isEmpty && attachments.isEmpty) return;
    _controller.clear();
    if (_pending.isNotEmpty) {
      setState(_pending.clear);
    }
    await widget.onSend(text, attachments);
    if (!mounted) return;
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider).when(
          data: (AppSettings value) => value,
          loading: () => const AppSettings(),
          error: (Object error, StackTrace stack) => const AppSettings(),
        );
    return InputBar(
      controller: _controller,
      focusNode: _focus,
      isBusy: widget.isBusy,
      onSend: _send,
      onStop: widget.onStop,
      attachments: _pending,
      supportedModalities: _supportedFor(settings),
      onAttach: _openAttachSheet,
      onRemoveAttachment: _removePending,
      contextUsed: widget.contextUsed,
      contextLimit: widget.contextLimit,
      onContextTap: widget.onContextTap,
    );
  }
}
