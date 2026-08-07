import 'package:flutter/material.dart';

/// Every color is derived by interpolating through three anchors — red
/// (dehydrated) → amber (neutral) → green (hydrated) — so the whole UI
/// shifts as one continuous gradient rather than jumping between discrete
/// states.
class HydrationTheme {
  final double h;
  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color border;

  const HydrationTheme._({
    required this.h,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.border,
  });

  static Color _lerp3(Color a, Color b, Color c, double t) {
    if (t < 0.5) return Color.lerp(a, b, t * 2.0)!;
    return Color.lerp(b, c, (t - 0.5) * 2.0)!;
  }

  factory HydrationTheme.of(double hydration) {
    final t = hydration.clamp(0.0, 1.0);

    return HydrationTheme._(
      h: t,
      bg: _lerp3(
        const Color(0xFF110808),
        const Color(0xFF111008),
        const Color(0xFF081109),
        t,
      ),
      surface: _lerp3(
        const Color(0xFF1E1212),
        const Color(0xFF1E1A12),
        const Color(0xFF121E16),
        t,
      ),
      surfaceAlt: _lerp3(
        const Color(0xFF281818),
        const Color(0xFF282218),
        const Color(0xFF182820),
        t,
      ),
      textPrimary: _lerp3(
        const Color(0xFFF5E0E0),
        const Color(0xFFF5EFE0),
        const Color(0xFFE0F5E8),
        t,
      ),
      textSecondary: _lerp3(
        const Color(0xFFBB8888),
        const Color(0xFFBBA888),
        const Color(0xFF88BB98),
        t,
      ),
      textMuted: _lerp3(
        const Color(0xFF886666),
        const Color(0xFF887E66),
        const Color(0xFF668878),
        t,
      ),
      accent: _lerp3(
        const Color(0xFFE85454),
        const Color(0xFFD4A846),
        const Color(0xFF42CC88),
        t,
      ),
      border: _lerp3(
        const Color(0xFF382020),
        const Color(0xFF383020),
        const Color(0xFF203828),
        t,
      ),
    );
  }

  /// Accent-tinted border used to frame grouped sections (see `SectionCard`).
  Color get surfaceBorder => Color.lerp(border, accent, 0.25)!;
  Color get chipSelected => Color.lerp(surface, accent, 0.18)!;
  Color get chipBorderSelected => accent.withValues(alpha: 0.45);
}
