import 'package:flutter/material.dart';

import '../models/flower_state.dart';
import '../theme/hydration_theme.dart';

/// The hydration readout: percentage (quantity) + the flavor message beneath.
class HydrationBadge extends StatelessWidget {
  final HydrationTheme theme;
  final double hydration;
  final double percentFontSize;

  const HydrationBadge({
    super.key,
    required this.theme,
    required this.hydration,
    this.percentFontSize = 64,
  });

  @override
  Widget build(BuildContext context) {
    final state = FlowerState.of(hydration);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: hydration),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeOutCubic,
          builder: (_, h, __) {
            final p = (h * 100).round();
            return Text(
              '$p%',
              style: TextStyle(
                fontSize: percentFontSize,
                fontWeight: FontWeight.w900,
                color: theme.accent,
                letterSpacing: -4,
                height: 1.0,
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
                      .animate(anim),
              child: child,
            ),
          ),
          child: Text(
            state.message,
            key: ValueKey(state.message),
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
