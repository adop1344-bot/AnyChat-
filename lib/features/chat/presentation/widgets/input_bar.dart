import 'package:flutter/material.dart';

import '../../../../core/storage/token_estimator.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/ui/atoms.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../providers/domain/model_info.dart';
import '../../domain/models.dart';
import 'attachment_view.dart';

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
    this.onTextChanged,
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
  final ValueChanged<String>? onTextChanged;
  final VoidCallback? onReasoningTap;
  final String reasoningLevel;

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  bool _hasText = false;

  /// Reasoning is on unless the user switched it off: the lamp is lit, not
  /// coloured, so the accent stays for action.
  Color _lampColor(ColorScheme scheme) {
    if (widget.reasoningLevel == 'off') {
      return scheme.onSurfaceVariant.withValues(alpha: 0.4);
    }
    return scheme.onSurfaceVariant;
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
    widget.onTextChanged?.call(widget.controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final remove = widget.onRemoveAttachment;
    final canAttach = !widget.isBusy && widget.onAttach != null;
    final ready = _hasText && !widget.isBusy;
    final tokens = estimateTokens(widget.controller.text);

    final double bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      margin: EdgeInsets.fromLTRB(
        AppSpace.x3,
        AppSpace.x2,
        AppSpace.x3,
        AppSpace.x2 + (bottomInset > 0 ? bottomInset : 0),
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card + 2),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.x3,
                AppSpace.x3,
                AppSpace.x3,
                0,
              ),
              child: Wrap(
                spacing: AppSpace.x2,
                runSpacing: AppSpace.x2,
                children: <Widget>[
                  for (var i = 0; i < widget.attachments.length; i++)
                    AttachmentChip(
                      attachment: widget.attachments[i],
                      onRemove: remove == null ? null : () => remove(i),
                    ),
                ],
              ),
            ),
          TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            minLines: 1,
            maxLines: 6,
            textInputAction: TextInputAction.newline,
            style: theme.textTheme.bodyMedium,
            cursorColor: scheme.primary,
            decoration: InputDecoration(
              hintText: l10n.messageInputHint,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isCollapsed: true,
              contentPadding: const EdgeInsets.fromLTRB(
                AppSpace.x4,
                AppSpace.x3 + 2,
                AppSpace.x4,
                AppSpace.x2,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.x2,
              0,
              AppSpace.x2,
              AppSpace.x1,
            ),
            child: Row(
              children: <Widget>[
                QuietIconButton(
                  icon: Icons.add,
                  tooltip: l10n.attach,
                  onPressed: canAttach ? widget.onAttach : null,
                  box: 34,
                ),
                if (widget.onReasoningTap != null)
                  QuietIconButton(
                    icon: widget.reasoningLevel == 'off'
                        ? Icons.lightbulb_outline
                        : Icons.lightbulb,
                    tooltip: l10n.thinking,
                    onPressed: widget.onReasoningTap,
                    color: _lampColor(scheme),
                    box: 34,
                  ),
                const SizedBox(width: AppSpace.x1),
                if (_hasText)
                  Figure(
                    '~${formatTokenCount(tokens)} tok',
                    size: 10.5,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                const Spacer(),
                _SendButton(
                  busy: widget.isBusy,
                  ready: ready,
                  onSend: widget.onSend,
                  onStop: widget.onStop,
                  sendTooltip: l10n.send,
                  stopTooltip: l10n.stop,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.busy,
    required this.ready,
    required this.onSend,
    required this.onStop,
    required this.sendTooltip,
    required this.stopTooltip,
  });

  final bool busy;
  final bool ready;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final String sendTooltip;
  final String stopTooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color background =
        busy ? scheme.surfaceContainerHighest : (ready ? scheme.primary : scheme.surfaceContainerHigh);
    final Color foreground = busy
        ? scheme.onSurfaceVariant
        : (ready ? scheme.onPrimary : scheme.onSurfaceVariant);
    return Tooltip(
      message: busy ? stopTooltip : sendTooltip,
      child: InkWell(
        onTap: busy ? onStop : (ready ? onSend : null),
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Icon(
            busy ? Icons.stop_rounded : Icons.arrow_upward_rounded,
            size: 18,
            color: foreground,
          ),
        ),
      ),
    );
  }
}
