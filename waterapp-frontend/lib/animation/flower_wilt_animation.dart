import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// A single detached petal, spawned when hydration drops across a mood tier,
/// that drifts down and fades out over [lifetime].
class FallingPetal {
  final int petalIndex;
  final double xDriftSeed; // -1..1, horizontal drift direction/strength
  final double rotationSeed; // -1..1, tumble direction/strength
  final DateTime spawnedAt;

  const FallingPetal({
    required this.petalIndex,
    required this.xDriftSeed,
    required this.rotationSeed,
    required this.spawnedAt,
  });

  static const Duration lifetime = Duration(milliseconds: 1200);

  double progressAt(DateTime now) {
    final ms = now.difference(spawnedAt).inMilliseconds;
    return (ms / lifetime.inMilliseconds).clamp(0.0, 1.0);
  }

  bool isExpired(DateTime now) => progressAt(now) >= 1.0;
}

/// The staggered, per-part "effective hydration" values that drive
/// [FlowerPainter] for a single animation frame.
///
/// Rather than one flat lerp applied to every part of the flower at once,
/// each part reads the shared transition progress through its own
/// [Interval], so a change reads as a sequence: the stem sags first, petals
/// droop one after another, and color lags slightly behind the geometry
/// ("wilts, then browns"). Reviving runs the same sequence with an
/// [Curves.easeOutBack] overshoot so the flower looks like it perks back up
/// rather than simply rewinding.
class FlowerWiltFrame {
  final double stemH;
  final double leafH;
  final List<double> petalH;
  final double colorH;

  /// Final sway rotation for this frame (radians, amplitude already applied).
  final double sway;

  const FlowerWiltFrame({
    required this.stemH,
    required this.leafH,
    required this.petalH,
    required this.colorH,
    required this.sway,
  });

  static const int petalCount = 6;

  static Curve _curveFor(bool reviving) =>
      reviving ? Curves.easeOutBack : Curves.easeInOutCubic;

  static double _partValue(
    double from,
    double to,
    double p,
    double start,
    double end,
    Curve curve,
  ) {
    final t = Interval(start, end, curve: curve).transform(p);
    return from + (to - from) * t;
  }

  /// Builds the per-part values for a transition from [from] to [to]
  /// hydration, [progress] of the way through (0..1), with ambient sway
  /// driven by [swayPhase] (0..1, looping).
  factory FlowerWiltFrame.at({
    required double from,
    required double to,
    required double progress,
    required double swayPhase,
  }) {
    final reviving = to > from;
    final curve = _curveFor(reviving);

    final stemH = _partValue(from, to, progress, 0.00, 0.70, curve);
    final leafH = _partValue(from, to, progress, 0.10, 0.85, curve);
    final colorH = _partValue(from, to, progress, 0.20, 1.00, curve);

    final petalH = List<double>.generate(petalCount, (i) {
      final start = 0.05 + i * 0.06;
      final end = 0.75 + i * 0.04;
      return _partValue(from, to, progress, start, end, curve);
    });

    // Sway grows heavier/slower at low hydration, livelier when thriving.
    final swayAmplitude = 0.012 + to * 0.025;
    final sway = math.sin(swayPhase * 2 * math.pi) * swayAmplitude;

    return FlowerWiltFrame(
      stemH: stemH,
      leafH: leafH,
      petalH: petalH,
      colorH: colorH,
      sway: sway,
    );
  }
}
