import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/hydration_store.dart';
import '../core/notifications.dart';
import '../theme/hydration_theme.dart';
import '../widgets/animated_flower.dart';
import '../widgets/app_background.dart';
import '../widgets/hydration_badge.dart';

class OverlayScreen extends StatefulWidget {
  const OverlayScreen({super.key});
  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen> {
  double _hydration = 0.0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // The reminder has been delivered — clear it so it can't sit in the shade
    // and suppress the full-screen intent for the next one (see
    // reminderNotificationId).
    unawaited(localNotifications.cancel(reminderNotificationId));
  }

  Future<void> _load() async {
    final h = await readHydration();
    if (!mounted) return;
    setState(() => _hydration = h);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final theme = HydrationTheme.of(_hydration);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        AppBackground(theme: theme),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, bottom + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Center(
                    child: AnimatedFlower(
                        hydration: _hydration, width: 200, animate: false)),
                const SizedBox(height: 20),
                Center(
                    child: HydrationBadge(
                        theme: theme, hydration: _hydration, percentFontSize: 52)),
                const Spacer(),
                SizedBox(
                  height: 58,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      HapticFeedback.mediumImpact();
                      final h = await markDrink();
                      if (mounted) setState(() => _hydration = h);
                      SystemNavigator.pop();
                    },
                    icon: const Icon(Icons.water_drop_rounded, size: 20),
                    label: const Text('I drank water!'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    final h = await markDismiss();
                    if (mounted) setState(() => _hydration = h);
                    SystemNavigator.pop();
                  },
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text('Let it wither',
                      style: TextStyle(
                        color: theme.textMuted,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      )),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
