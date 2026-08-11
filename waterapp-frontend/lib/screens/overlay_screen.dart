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
  /// Beat held after the flower finishes reacting, so the new state actually
  /// registers before the screen starts going away.
  static const Duration _settleDuration = Duration(milliseconds: 600);
  static const Duration _fadeDuration = Duration(milliseconds: 450);

  double _hydration = 0.0;

  /// Set the moment a choice is made — locks out further input so a second tap
  /// can't queue up a competing exit while the first is still playing.
  bool _closing = false;

  /// Set only once the flower has settled; drives the fade-out.
  bool _fadingOut = false;

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

  /// Applies the user's choice, lets the flower play out its reaction, then
  /// fades the screen away. Previously this closed immediately, so the wilt /
  /// bloom the whole screen exists to show was never actually seen.
  Future<void> _respond(Future<double> Function() apply) async {
    if (_closing) return;
    setState(() => _closing = true);

    final h = await apply();
    if (!mounted) return;
    setState(() => _hydration = h);

    await Future<void>.delayed(
        AnimatedFlower.transitionDuration + _settleDuration);
    if (!mounted) return;
    setState(() => _fadingOut = true);

    await Future<void>.delayed(_fadeDuration);
    if (!mounted) return;
    _close();
  }

  void _close() {
    // This screen is the whole app when a reminder launched it, but it's a
    // pushed route when opened from HomePage — popping the app in that case
    // would kill the app out from under the user.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final theme = HydrationTheme.of(_hydration);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedOpacity(
        opacity: _fadingOut ? 0.0 : 1.0,
        duration: _fadeDuration,
        curve: Curves.easeOut,
        // Swallow taps once a choice is made rather than disabling the buttons:
        // Flutter's disabled styling would grey them out mid-animation, which
        // clashes with the themed accent right when the flower is the thing
        // meant to be holding attention. _respond also guards on _closing.
        child: IgnorePointer(
          ignoring: _closing,
          child: Stack(children: [
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
                            hydration: _hydration, width: 300, animate: false)),
                    const SizedBox(height: 20),
                    Center(
                        child: HydrationBadge(
                            theme: theme,
                            hydration: _hydration,
                            percentFontSize: 52)),
                    const Spacer(),
                    SizedBox(
                      height: 58,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          unawaited(_respond(markDrink));
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
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        unawaited(_respond(markDismiss));
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
        ),
      ),
    );
  }
}
