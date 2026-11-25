import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/style_tokens.dart';

/// A 1px rule. Dividers carry grouping in this app, so they are used where a
/// card border would otherwise be invented.
class Hairline extends StatelessWidget {
  const Hairline({
    super.key,
    this.indent = 0,
    this.endIndent = 0,
    this.color,
  });

  final double indent;
  final double endIndent;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final StyleTokens tokens = StyleTokens.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color resolved = color ??
        (tokens.hairlineChrome
            ? scheme.outlineVariant
            : scheme.outlineVariant.withValues(alpha: 0.6));
    return Container(
      height: 1,
      margin: EdgeInsets.only(left: indent, right: endIndent),
      color: resolved,
    );
  }
}

/// Small quiet caption above a group of rows.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.x4,
        AppSpace.x6,
        AppSpace.x4,
        AppSpace.x2,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Monospaced figure text: token counts, percentages, timings, model ids.
class Figure extends StatelessWidget {
  const Figure(
    this.text, {
    super.key,
    this.size = 11.5,
    this.weight = FontWeight.w400,
    this.color,
  });

  final String text;
  final double size;
  final FontWeight weight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color resolved = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final StyleTokens tokens = StyleTokens.of(context);
    if (tokens.monoFigures) {
      return Text(
        text,
        style: AppType.figure(size, weight: weight, color: resolved),
      );
    }
    return Text(
      text,
      style: TextStyle(
        fontSize: size + 0.5,
        fontWeight: weight,
        height: 1.4,
        letterSpacing: 0,
        color: resolved,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }
}

/// The signature of the app: a thin instrument track that fills with context.
class Meter extends StatelessWidget {
  const Meter({
    super.key,
    required this.ratio,
    this.height = 3,
    this.color,
    this.track,
    this.width,
  });

  final double ratio;
  final double height;
  final Color? color;
  final Color? track;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final StyleTokens tokens = StyleTokens.of(context);
    final double value = ratio.isNaN ? 0 : ratio.clamp(0.0, 1.0);
    final double thickness = tokens.instrument ? height : (height + 2);
    return SizedBox(
      width: width,
      height: thickness,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(thickness / 2),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: value),
          duration: AppMotion.slow,
          curve: AppMotion.curve,
          builder: (BuildContext context, double shown, Widget? child) {
            final int filled = (shown * 1000).round();
            final int empty = 1000 - filled;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (filled > 0)
                  Expanded(
                    flex: filled,
                    child: ColoredBox(color: color ?? scheme.primary),
                  ),
                if (empty > 0)
                  Expanded(
                    flex: empty,
                    child: ColoredBox(
                      color: track ??
                          (tokens.instrument
                              ? scheme.surfaceContainerHighest
                              : scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.9)),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Live status: a filled dot, never a glow or a pulse.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 6});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Keycap used for shortcuts and command hints.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: AppType.figure(
          10.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Square, quiet icon button used in app bars and row trailing slots.
class QuietIconButton extends StatelessWidget {
  const QuietIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 18,
    this.box = 36,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double box;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final StyleTokens tokens = StyleTokens.of(context);
    final Widget button = InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(
        tokens.instrument ? AppRadius.control - 2 : box / 2,
      ),
      child: SizedBox(
        width: box,
        height: box,
        child: Icon(
          icon,
          size: size,
          color: onPressed == null
              ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
              : (color ?? scheme.onSurfaceVariant),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
