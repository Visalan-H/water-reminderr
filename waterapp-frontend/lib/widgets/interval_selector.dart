import 'package:flutter/material.dart';

import '../theme/hydration_theme.dart';

class IntervalSelector extends StatelessWidget {
  final HydrationTheme theme;
  final List<int> intervals;
  final int selected;
  final ValueChanged<int> onSelect;

  const IntervalSelector({
    super.key,
    required this.theme,
    required this.intervals,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: intervals.map((min) {
        final sel = selected == min;
        final label = min < 60
            ? '${min}m'
            : '${min ~/ 60}h${min % 60 != 0 ? ' ${min % 60}m' : ''}';
        return GestureDetector(
          onTap: () => onSelect(min),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: sel ? theme.chipSelected : theme.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: sel ? theme.chipBorderSelected : theme.border,
                  width: 1),
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 400),
              style: TextStyle(
                color: sel ? theme.accent : theme.textSecondary,
                fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                fontSize: 14,
                letterSpacing: -0.2,
              ),
              child: Text(label),
            ),
          ),
        );
      }).toList(),
    );
  }
}
