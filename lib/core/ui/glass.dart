import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/style_tokens.dart';

/// The colour field Liquid Glass floats over. Three soft blobs and a vertical
/// gradient: enough depth for the blur to have something to chew on, quiet
/// enough that text stays legible.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: <Widget>[
        Positioned.fill(child: _Field(isDark: isDark)),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color top = isDark
        ? Color.alphaBlend(scheme.primary.withValues(alpha: 0.30),
            const Color(0xFF0B0D12))
        : Color.alphaBlend(scheme.primary.withValues(alpha: 0.16),
            const Color(0xFFF4F6FB));
    final Color bottom = isDark
        ? Color.alphaBlend(scheme.tertiary.withValues(alpha: 0.26),
            const Color(0xFF101319))
        : Color.alphaBlend(scheme.tertiary.withValues(alpha: 0.14),
            const Color(0xFFEDF1F8));

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[top, bottom],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -120,
            left: -80,
            child: _Blob(color: scheme.primary, size: 380, alpha: 0.42),
          ),
          Positioned(
            top: 240,
            right: -140,
            child: _Blob(color: scheme.tertiary, size: 420, alpha: 0.34),
          ),
          Positioned(
            bottom: -160,
            left: 40,
            child: _Blob(color: scheme.secondary, size: 360, alpha: 0.28),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required this.color,
    required this.size,
    required this.alpha,
  });

  final Color color;
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// A frosted panel: blurs what is behind it, tints it slightly, and draws the
/// thin bright edge that reads as glass. Falls back to a flat surface when the
/// active style is not glass, so it can wrap every surface unconditionally.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius,
    this.blur = 22,
    this.padding,
    this.margin,
    this.border = true,
    this.tint,
  });

  final Widget child;
  final double? radius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool border;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final StyleTokens tokens = StyleTokens.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double r = radius ?? tokens.cardRadius;
    final BorderRadius shape = BorderRadius.circular(r);

    if (!tokens.glass) {
      return Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: tint ?? scheme.surfaceContainerLow,
          borderRadius: shape,
          border: tokens.hairlineChrome
              ? Border.all(color: scheme.outlineVariant)
              : null,
        ),
        child: child,
      );
    }

    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: shape,
              // A hair of fill plus a diagonal sheen: the classic glass read.
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Colors.white.withValues(alpha: isDark ? 0.17 : 0.58),
                  Colors.white.withValues(alpha: isDark ? 0.05 : 0.26),
                ],
              ),
            ),
            foregroundDecoration: border
                ? BoxDecoration(
                    borderRadius: shape,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: isDark ? 0.22 : 0.62),
                      width: 1,
                    ),
                  )
                : null,
            child: Stack(
              children: <Widget>[
                // Specular line riding the top edge, fading out at both ends.
                if (border)
                  Positioned(
                    left: r * 0.5,
                    right: r * 0.5,
                    top: 0,
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: isDark ? 0.55 : 0.95),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The specular highlight along the top edge of a glass control.
class GlassSheen extends StatelessWidget {
  const GlassSheen({super.key, this.height = 1});

  final double height;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: isDark ? 0.5 : 0.9),
              Colors.white.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
