import 'package:flutter/material.dart';

import '../theme/hydration_theme.dart';

class SetupItem {
  final String label;
  final String sub;
  final bool done;
  final VoidCallback onTap;
  const SetupItem({
    required this.label,
    required this.sub,
    required this.done,
    required this.onTap,
  });
}

/// The permission setup list. Once every item is done it collapses into a
/// single "Setup complete" row instead of always showing every tile plus a
/// separate status line — returning users (the common case) see one line,
/// not a wall of tiles. Tapping the summary re-expands it.
class SetupChecklist extends StatefulWidget {
  final HydrationTheme theme;
  final List<SetupItem> items;
  const SetupChecklist({super.key, required this.theme, required this.items});

  @override
  State<SetupChecklist> createState() => _SetupChecklistState();
}

class _SetupChecklistState extends State<SetupChecklist> {
  bool? _expandedOverride;

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final allDone = widget.items.isNotEmpty && widget.items.every((i) => i.done);
    final expanded = _expandedOverride ?? !allDone;

    if (allDone && !expanded) {
      return GestureDetector(
        onTap: () => setState(() => _expandedOverride = true),
        child: Row(children: [
          Icon(Icons.check_circle_rounded, color: t.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Setup complete',
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: -0.2,
                )),
          ),
          Icon(Icons.expand_more_rounded, color: t.textMuted, size: 18),
        ]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < widget.items.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _tile(widget.items[i], t),
        ],
        if (allDone) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _expandedOverride = false),
              child: Text('Collapse',
                  style: TextStyle(
                      color: t.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tile(SetupItem item, HydrationTheme t) => GestureDetector(
        onTap: item.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: t.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: item.done ? t.accent.withValues(alpha: 0.28) : t.border,
                width: 1),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: item.done ? t.chipSelected : t.surface,
              ),
              child: Center(
                  child: Icon(
                item.done ? Icons.check_rounded : Icons.lock_outline_rounded,
                color: item.done ? t.accent : t.textMuted,
                size: 17,
              )),
            ),
            const SizedBox(width: 13),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 500),
                  style: TextStyle(
                    color: item.done ? t.textPrimary : t.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: -0.2,
                  ),
                  child: Text(item.label),
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 500),
                  style: TextStyle(
                      color: t.textMuted, fontSize: 12, fontWeight: FontWeight.w500),
                  child: Text(item.sub),
                ),
              ],
            )),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios_rounded, color: t.textMuted, size: 13),
          ]),
        ),
      );
}
