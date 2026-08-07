import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../animation/flower_wilt_animation.dart';
import '../models/flower_state.dart';
import '../painters/flower_painter.dart';

/// The animated flower centerpiece. Feed it a hydration value (0..1) and it
/// eases toward it with a staggered wilt/bloom transition (see
/// [FlowerWiltFrame]); dropping across a mood tier also sheds a couple of
/// falling petals. Set [animate] to false to disable the idle sway (used on
/// the lock-screen overlay to keep things calm).
class AnimatedFlower extends StatefulWidget {
  final double hydration;
  final double width;
  final bool animate;
  const AnimatedFlower({
    super.key,
    required this.hydration,
    this.width = 260,
    this.animate = true,
  });

  @override
  State<AnimatedFlower> createState() => _AnimatedFlowerState();
}

class _AnimatedFlowerState extends State<AnimatedFlower>
    with TickerProviderStateMixin {
  static const Duration _transitionDuration = Duration(milliseconds: 1400);
  static const Duration _swayPeriod = Duration(milliseconds: 6000);

  late final AnimationController _transition;
  late final AnimationController _ambient;
  final math.Random _rng = math.Random();
  final List<FallingPetal> _particles = [];

  double _from = 0;
  double _to = 0;

  @override
  void initState() {
    super.initState();
    _from = widget.hydration;
    _to = widget.hydration;
    _transition =
        AnimationController(vsync: this, duration: _transitionDuration)
          ..value = 1.0;
    _ambient = AnimationController(vsync: this, duration: _swayPeriod);
    if (widget.animate) _ambient.repeat();
  }

  @override
  void didUpdateWidget(covariant AnimatedFlower old) {
    super.didUpdateWidget(old);

    if (widget.hydration != _to) {
      _spawnParticlesIfWilting(_to, widget.hydration);
      // Not tracking the exact interrupted mid-transition value on purpose —
      // starting from the previous target keeps this simple and robust; a
      // rapid double-tap causing a small visual jump is an acceptable trade.
      _from = _to;
      _to = widget.hydration;
      _transition
        ..stop()
        ..forward(from: 0.0);
    }

    if (widget.animate && !_ambient.isAnimating) {
      _ambient.repeat();
    } else if (!widget.animate && _ambient.isAnimating) {
      _ambient.stop();
    }
  }

  void _spawnParticlesIfWilting(double from, double to) {
    if (to >= from) return; // only shed petals while dropping
    final droppedTiers = FlowerState.of(from).tier - FlowerState.of(to).tier;
    if (droppedTiers <= 0) return;
    final count = droppedTiers.clamp(1, 2);
    for (int i = 0; i < count; i++) {
      _particles.add(FallingPetal(
        petalIndex: _rng.nextInt(FlowerWiltFrame.petalCount),
        xDriftSeed: _rng.nextDouble() * 2 - 1,
        rotationSeed: _rng.nextDouble() * 2 - 1,
        spawnedAt: DateTime.now(),
      ));
    }
  }

  @override
  void dispose() {
    _transition.dispose();
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.width * 1.25;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_transition, _ambient]),
        builder: (_, __) {
          final now = DateTime.now();
          _particles.removeWhere((p) => p.isExpired(now));

          final frame = FlowerWiltFrame.at(
            from: _from,
            to: _to,
            progress: _transition.value,
            swayPhase: _ambient.value,
          );

          return CustomPaint(
            size: Size(widget.width, height),
            painter: FlowerPainter(
              frame: frame,
              particles: List.unmodifiable(_particles),
              frameTime: now,
            ),
          );
        },
      ),
    );
  }
}
