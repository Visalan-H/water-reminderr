import 'dart:async';
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
  /// How long a hydration change takes to fully play out. Public so callers
  /// that want to wait for the flower to settle before moving on (e.g. the
  /// reminder overlay before it closes itself) don't have to hardcode it.
  static const Duration transitionDuration = Duration(milliseconds: 1400);

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
    with SingleTickerProviderStateMixin {
  static const Duration _swayPeriod = Duration(milliseconds: 6000);
  // Ambient sway is driven by a low-rate Timer rather than a 60fps+
  // AnimationController — the sway is slow and subtle, so an 8fps update
  // is visually indistinguishable while avoiding a screen-refresh-rate
  // repaint loop that runs for as long as the flower is on screen.
  static const Duration _swayTick = Duration(milliseconds: 125);

  late final AnimationController _transition;
  Timer? _swayTimer;
  double _swayPhase = 0;
  final math.Random _rng = math.Random();
  final List<FallingPetal> _particles = [];

  double _from = 0;
  double _to = 0;

  @override
  void initState() {
    super.initState();
    _from = widget.hydration;
    _to = widget.hydration;
    _transition = AnimationController(
        vsync: this, duration: AnimatedFlower.transitionDuration)
      ..value = 1.0;
    if (widget.animate) _startSway();
  }

  void _startSway() {
    _swayTimer ??= Timer.periodic(_swayTick, (_) {
      setState(() {
        _swayPhase = (_swayPhase +
                _swayTick.inMilliseconds / _swayPeriod.inMilliseconds) %
            1.0;
      });
    });
  }

  void _stopSway() {
    _swayTimer?.cancel();
    _swayTimer = null;
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

    if (widget.animate && _swayTimer == null) {
      _startSway();
    } else if (!widget.animate && _swayTimer != null) {
      _stopSway();
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
    _swayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.width * 1.25;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _transition,
        builder: (_, __) {
          final now = DateTime.now();
          _particles.removeWhere((p) => p.isExpired(now));

          final frame = FlowerWiltFrame.at(
            from: _from,
            to: _to,
            progress: _transition.value,
            swayPhase: _swayPhase,
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
