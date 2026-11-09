import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../providers/domain/model_info.dart';
import '../../domain/models.dart';
import 'attachment_view.dart';
import 'context_circle.dart';

class InputBar extends StatefulWidget {
  const InputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isBusy,
    required this.onSend,
    required this.onStop,
    this.attachments = const <ChatAttachment>[],
    this.supportedModalities = const <ModelModality>{},
    this.onAttach,
    this.onRemoveAttachment,
    this.contextUsed,
    this.contextLimit,
    this.onContextTap,
    this.onReasoningTap,
    this.reasoningLevel = '',
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isBusy;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final List<ChatAttachment> attachments;
  final Set<ModelModality> supportedModalities;
  final VoidCallback? onAttach;
  final ValueChanged<int>? onRemoveAttachment;
  final int? contextUsed;
  final int? contextLimit;
  final VoidCallback? onContextTap;
  final VoidCallback? onReasoningTap;
  final String reasoningLevel;

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  bool _hasText = false;

  Color? _lampColor(BuildContext context, String level) {
    final scheme = Theme.of(context).colorScheme;
    if (level == 'off') return scheme.outlineVariant;
    if (level.isEmpty || level == 'auto') return scheme.onSurfaceVariant;
    return scheme.primary;
  }

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final remove = widget.onRemoveAttachment;
    final canAttach = !widget.isBusy && widget.onAttach != null;
    final sendReady = _hasText && !widget.isBusy;

    final showContext = widget.contextUsed != null &&
        widget.contextLimit != null &&
        widget.onContextTap != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (var i = 0; i < widget.attachments.length; i++)
                    AttachmentChip(
                      attachment: widget.attachments[i],
                      onRemove: remove == null ? null : () => remove(i),
                    ),
                ],
              ),
            ),
          Stack(
            children: <Widget>[
              TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: l10n.messageInputHint,
                  filled: true,
                  fillColor: scheme.surfaceContainerHigh,
                  contentPadding: EdgeInsets.fromLTRB(
                    4,
                    12,
                    showContext ? 84 : 52,
                    12,
                  ),
                  prefixIcon: SizedBox(
                    width: widget.onReasoningTap == null ? 48 : 96,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: IconButton(
                            icon: const Icon(Icons.add),
                            tooltip: l10n.attach,
                            onPressed: canAttach ? widget.onAttach : null,
                          ),
                        ),
                        if (widget.onReasoningTap != null)
                          Expanded(
                            child: IconButton(
                              icon: Icon(
                                widget.reasoningLevel == 'off'
                                    ? Icons.lightbulb_outline
                                    : Icons.lightbulb,
                              ),
                              color: _lampColor(
                                context,
                                widget.reasoningLevel,
                              ),
                              tooltip: 'Раздумья',
                              onPressed: widget.onReasoningTap,
                            ),
                          ),
                      ],
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (showContext)
                Positioned(
                  right: 50,
                  bottom: 9,
                  child: ContextCircle(
                    used: widget.contextUsed!,
                    limit: widget.contextLimit!,
                    onTap: widget.onContextTap,
                  ),
                ),
              Positioned(
                right: 6,
                bottom: 4,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: widget.isBusy
                      ? IconButton(
                          onPressed: widget.onStop,
                          tooltip: l10n.stop,
                          icon: const Icon(Icons.stop),
                          padding: EdgeInsets.zero,
                          style: IconButton.styleFrom(
                            backgroundColor: scheme.error,
                            foregroundColor: scheme.onError,
                          ),
                        )
                      : IconButton(
                          onPressed: widget.onSend,
                          tooltip: l10n.send,
                          icon: const Icon(Icons.arrow_upward),
                          padding: EdgeInsets.zero,
                          style: IconButton.styleFrom(
                            backgroundColor: sendReady
                                ? scheme.primary
                                : scheme.surfaceContainerHighest,
                            foregroundColor: sendReady
                                ? scheme.onPrimary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
