import 'package:shared_preferences/shared_preferences.dart';

const String hydrationLevelKey = 'hydrationLevel';
const String hydrationUpdatedAtKey = 'hydrationUpdatedAt';
const double drinkBoost = 0.22;
const double dismissDrop = 0.08;

double clamp01(double v) => v.clamp(0.0, 1.0);

Future<double> readHydration() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final saved = prefs.getDouble(hydrationLevelKey);
  if (saved != null) return clamp01(saved);
  final now = DateTime.now().millisecondsSinceEpoch;
  await prefs.setDouble(hydrationLevelKey, 1.0);
  await prefs.setInt(hydrationUpdatedAtKey, now);
  await prefs.setInt('lastDrinkTime', now);
  return 1.0;
}

Future<double> changeHydration(double delta, {bool markDrink = false}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final current = clamp01(prefs.getDouble(hydrationLevelKey) ?? 1.0);
  final updated = clamp01(current + delta);
  final now = DateTime.now().millisecondsSinceEpoch;
  await prefs.setDouble(hydrationLevelKey, updated);
  await prefs.setInt(hydrationUpdatedAtKey, now);
  if (markDrink) await prefs.setInt('lastDrinkTime', now);
  return updated;
}

Future<double> markDrink() => changeHydration(drinkBoost, markDrink: true);
Future<double> markDismiss() => changeHydration(-dismissDrop);

/// Sets hydration to an absolute value, bypassing the drink/dismiss deltas.
/// Used by the debug slider to preview UI at arbitrary hydration levels.
Future<double> setHydration(double value) async {
  final prefs = await SharedPreferences.getInstance();
  final clamped = clamp01(value);
  await prefs.setDouble(hydrationLevelKey, clamped);
  await prefs.setInt(hydrationUpdatedAtKey, DateTime.now().millisecondsSinceEpoch);
  return clamped;
}

bool isQuietHours() {
  final hour = DateTime.now().hour;
  return hour >= 22 || hour < 6;
}
