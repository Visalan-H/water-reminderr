/// The flower's qualitative mood, derived from a hydration level in [0, 1].
class FlowerState {
  final String name;
  final String message;

  /// 0 (driest / SOS) .. 6 (healthiest / Thriving). Lets callers detect when
  /// hydration has dropped across a tier boundary (e.g. to trigger a
  /// falling-petal moment) without hard-coding the thresholds again.
  final int tier;

  const FlowerState._(this.name, this.message, this.tier);

  static FlowerState of(double h) {
    if (h >= 0.85) return const FlowerState._('Thriving', 'Growing well', 6);
    if (h >= 0.70) return const FlowerState._('Happy', 'Feeling fresh', 5);
    if (h >= 0.55) return const FlowerState._('Content', 'Doing okay', 4);
    if (h >= 0.40) {
      return const FlowerState._('Thirsty', 'Could use some water', 3);
    }
    if (h >= 0.25) return const FlowerState._('Wilting', "Not doing so great", 2);
    if (h >= 0.12) return const FlowerState._('Drying', 'I need water badly', 1);
    return const FlowerState._('SOS', "Water required urgently", 0);
  }
}
