import 'dart:math' as math;

import 'package:flutter/material.dart';

enum MascotState { thinking, writing, sleeping }

class Mascot extends StatefulWidget {
  const Mascot({super.key, required this.state, this.size = 36});

  final MascotState state;
  final double size;

  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) {
        final t = _controller.value * 2 * math.pi;
        final scheme = Theme.of(context).colorScheme;
        switch (widget.state) {
          case MascotState.thinking:
            return CustomPaint(
              size: Size.square(widget.size),
              painter: _MascotPainter(
                bob: math.sin(t) * 2,
                eye: 0,
                bubble: true,
                color: scheme.primary,
              ),
            );
          case MascotState.writing:
            return CustomPaint(
              size: Size.square(widget.size),
              painter: _MascotPainter(
                bob: math.sin(t * 3) * 1,
                eye: 1,
                bubble: false,
                color: scheme.primary,
              ),
            );
          case MascotState.sleeping:
            return CustomPaint(
              size: Size.square(widget.size),
              painter: _MascotPainter(
                bob: math.sin(t * 0.5) * 1,
                eye: 2,
                bubble: false,
                color: scheme.outline,
              ),
            );
        }
      },
    );
  }
}

class _MascotPainter extends CustomPainter {
  _MascotPainter({
    required this.bob,
    required this.eye,
    required this.bubble,
    required this.color,
  });

  final double bob;
  final int eye;
  final bool bubble;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final bodyPaint = Paint()..color = color.withValues(alpha: 0.85);
    final facePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.05;

    final center = Offset(s / 2, s / 2 + bob);
    final r = s * 0.38;

    final body = Path()
      ..addOval(Rect.fromCircle(center: center, radius: r));
    canvas.drawPath(body, bodyPaint);

    // ears
    final earPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.06;
    canvas.drawCircle(
      Offset(center.dx - r * 0.75, center.dy - r * 0.85),
      r * 0.28,
      earPaint,
    );
    canvas.drawCircle(
      Offset(center.dx + r * 0.75, center.dy - r * 0.85),
      r * 0.28,
      earPaint,
    );

    // eyes
    final eyeDx = r * 0.34;
    final eyeDy = -r * 0.15;
    for (final dx in <double>[-eyeDx, eyeDx]) {
      final c = Offset(center.dx + dx, center.dy + eyeDy);
      if (eye == 2) {
        // sleeping: closed lines
        canvas.drawLine(
          Offset(c.dx - r * 0.1, c.dy),
          Offset(c.dx + r * 0.1, c.dy),
          facePaint,
        );
      } else {
        final open = eye == 0 ? r * 0.14 : r * 0.11;
        canvas.drawCircle(c, open, facePaint..style = PaintingStyle.fill);
        facePaint.style = PaintingStyle.stroke;
      }
    }

    // mouth
    final mouth = Path()
      ..moveTo(center.dx - r * 0.2, center.dy + r * 0.3)
      ..quadraticBezierTo(
        center.dx,
        center.dy + r * (eye == 2 ? 0.34 : 0.5),
        center.dx + r * 0.2,
        center.dy + r * 0.3,
      );
    canvas.drawPath(mouth, facePaint..style = PaintingStyle.stroke);

    if (bubble) {
      final bPaint = Paint()
        ..color = color.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(center.dx + r * 1.05, center.dy - r * 1.1 + bob * 0.5),
        r * 0.18,
        bPaint,
      );
      canvas.drawCircle(
        Offset(center.dx + r * 1.3, center.dy - r * 1.45 + bob * 0.5),
        r * 0.11,
        bPaint,
      );
    }

    if (eye == 2) {
      // Zzz
      final tp = TextPainter(
        text: TextSpan(
          text: 'z',
          style: TextStyle(
            color: color,
            fontSize: s * 0.22,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(center.dx + r * 0.9, center.dy - r * 1.7 + bob * 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_MascotPainter old) =>
      old.bob != bob || old.eye != eye || old.bubble != bubble;
}
