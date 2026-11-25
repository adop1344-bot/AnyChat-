import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// The two shipped looks, shown as live miniatures. Tapping one cross-fades
/// the whole app: MaterialApp animates the theme swap itself.
class StylePicker extends StatelessWidget {
  const StylePicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.labelInstrument,
    required this.labelMaterial,
  });

  final AppUiStyle value;
  final ValueChanged<AppUiStyle> onChanged;
  final String labelInstrument;
  final String labelMaterial;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _StyleCard(
            label: labelInstrument,
            selected: value == AppUiStyle.instrument,
            onTap: () => onChanged(AppUiStyle.instrument),
            preview: const _InstrumentPreview(),
          ),
        ),
        const SizedBox(width: AppSpace.x3),
        Expanded(
          child: _StyleCard(
            label: labelMaterial,
            selected: value == AppUiStyle.material,
            onTap: () => onChanged(AppUiStyle.material),
            preview: const _MaterialPreview(),
          ),
        ),
      ],
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.preview,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.curve,
        padding: const EdgeInsets.all(AppSpace.x2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
          color: selected
              ? scheme.primary.withValues(alpha: 0.06)
              : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control - 2),
              child: SizedBox(height: 62, child: preview),
            ),
            const SizedBox(height: AppSpace.x2),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: selected
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                AnimatedScale(
                  duration: AppMotion.fast,
                  curve: AppMotion.curve,
                  scale: selected ? 1 : 0,
                  child: Icon(Icons.check, size: 14, color: scheme.primary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Ink surfaces, hairlines, one copper needle.
class _InstrumentPreview extends StatelessWidget {
  const _InstrumentPreview();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppRamp.dark.background,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              height: 3,
              width: 26,
              decoration: BoxDecoration(
                color: const Color(0xFFC2703A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            for (final double w in <double>[44, 36, 40])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  height: 2,
                  width: w,
                  color: AppRamp.dark.borderStrong,
                ),
              ),
            const Spacer(),
            Container(height: 1, color: AppRamp.dark.border),
          ],
        ),
      ),
    );
  }
}

/// Seeded surfaces, pill controls, tonal fills.
class _MaterialPreview extends StatelessWidget {
  const _MaterialPreview();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Container(
              height: 10,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 10,
              width: 44,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
