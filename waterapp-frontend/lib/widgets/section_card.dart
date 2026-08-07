import 'package:flutter/material.dart';

import '../theme/hydration_theme.dart';

/// A bordered container used to group related controls (interval picker,
/// setup checklist) into a visually distinct section instead of a flat
/// stack of labels and widgets.
class SectionCard extends StatelessWidget {
  final HydrationTheme theme;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SectionCard({
    super.key,
    required this.theme,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.surfaceBorder, width: 1),
      ),
      child: child,
    );
  }
}
