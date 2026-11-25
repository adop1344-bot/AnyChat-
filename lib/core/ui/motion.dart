import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Fade + small rise when something enters the screen. Short, and it never
/// replays while the widget stays mounted.
class Appear extends StatefulWidget {
  const Appear({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.rise = 8,
    this.duration = AppMotion.base,
  });

  final Widget child;
  final Duration delay;
  final double rise;
  final Duration duration;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.curve,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (BuildContext context, Widget? child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _curve.value) * widget.rise),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Keeps streaming text from snapping: every new chunk dims the block a touch
/// and lets it settle back. Only opacity animates, the child is not rebuilt.
class StreamFade extends StatefulWidget {
  const StreamFade({
    super.key,
    required this.trigger,
    required this.child,
    this.from = 0.55,
    this.duration = const Duration(milliseconds: 150),
  });

  final Object trigger;
  final Widget child;
  final double from;
  final Duration duration;

  @override
  State<StreamFade> createState() => _StreamFadeState();
}

class _StreamFadeState extends State<StreamFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: widget.from,
    end: 1,
  ).animate(CurvedAnimation(parent: _controller, curve: AppMotion.curve));

  @override
  void didUpdateWidget(StreamFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}

/// Cross-fades between two short widgets without moving the layout.
class SoftSwap extends StatelessWidget {
  const SoftSwap({
    super.key,
    required this.child,
    this.duration = AppMotion.base,
    this.alignment = Alignment.centerLeft,
  });

  final Widget child;
  final Duration duration;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
      layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
        alignment: alignment,
        children: <Widget>[
          ...previous,
          if (current != null) current,
        ],
      ),
      transitionBuilder: (Widget child, Animation<double> animation) =>
          FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
