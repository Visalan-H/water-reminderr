import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_constants.dart';
import '../core/device_permissions.dart';
import '../core/hydration_store.dart';
import '../core/notifications.dart';
import '../core/remote_log.dart';
import '../theme/hydration_theme.dart';
import '../widgets/animated_flower.dart';
import '../widgets/app_background.dart';
import '../widgets/hydration_badge.dart';
import '../widgets/interval_selector.dart';
import '../widgets/section_card.dart';
import '../widgets/setup_checklist.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const List<int> _intervals = [1, 10, 30, 45, 60, 90, 120, 180, 240];

  int _intervalMinutes = 60;
  bool _registered = false;
  bool _busy = false;
  bool _overlayPermissionDone = false;
  bool _batteryLimitDone = false;
  bool _backgroundActivityDone = false;
  bool _miuiAlertDone = false;
  bool _setupIntroDismissed = false;
  String _status = 'Waking up...';
  String _brand = '';
  double _hydration = 1.0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_init());
    _ticker = Timer.periodic(
        const Duration(seconds: 5), (_) => unawaited(_pullHydration()));

    FirebaseMessaging.onMessage.listen((m) async {
      if (m.data['type'] == 'water_reminder' && !isQuietHours()) {
        await showReminderOverlay(
          title: m.data['title'] ?? 'Time to water your flower',
          body: m.data['body'] ?? 'Tap to log a drink',
        );
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((m) async {
      if (m.data['type'] == 'water_reminder' && !isQuietHours()) {
        await showReminderOverlay(
          title: m.data['title'] ?? 'Time to water your flower',
          body: m.data['body'] ?? 'Tap to log a drink',
        );
      }
    });
    FirebaseMessaging.instance.getInitialMessage().then((m) async {
      if (m?.data['type'] == 'water_reminder' && !isQuietHours()) {
        await showReminderOverlay(
          title: m!.data['title'] ?? 'Time to water your flower',
          body: m.data['body'] ?? 'Tap to log a drink',
        );
      }
    });

    // The backend keeps serving whatever token it was last given — if FCM
    // rotates the token (reinstall, device restore, routine refresh) without
    // this, reminders silently stop with no error anywhere.
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      unawaited(remoteLog('fcm_token_refreshed'));
      if (!_registered) return;
      final res = await _postRegister(newToken);
      unawaited(remoteLog(res != null && res.statusCode == 200
          ? 'fcm_token_reregistered'
          : 'fcm_token_reregister_failed'));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_pullHydration());
      unawaited(_refreshPermissions());
    }
  }

  Future<void> _setHydrationDebug(double value) async {
    setState(() => _hydration = value);
    await setHydration(value);
  }

  Future<void> _pullHydration() async {
    final h = await readHydration();
    if (!mounted) return;
    setState(() => _hydration = h);
  }

  Future<void> _markDrink() async {
    HapticFeedback.mediumImpact();
    final h = await markDrink();
    if (!mounted) return;
    setState(() => _hydration = h);
    const msgs = [
      'Refreshing.',
      'Your flower is hydrated.',
      'Hydration complete.',
    ];
    _snack(msgs[DateTime.now().second % msgs.length]);
  }

  Future<void> _init() async {
    await requestNotificationPermissions();
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (mounted) setState(() => _brand = info.manufacturer);
    }
    // Notification-launch detection is handled in main() before runApp(),
    // so there is nothing to check here.
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('intervalMinutes');
    final wasReg = prefs.getBool('registered') ?? false;
    final fullScreenPermDone = await isFullScreenIntentGranted();
    final batteryLimitDone = await isBatteryLimitDone();
    final backgroundActivityDone = prefs.getBool(backgroundActivityDoneKey) ??
        prefs.getBool(legacyBatteryPermissionDoneKey) ??
        false;
    final miuiAlertDone = prefs.getBool(miuiAlertDoneKey) ?? false;
    final setupIntroDismissed = prefs.getBool(setupIntroDismissedKey) ?? false;
    final savedH = await readHydration();

    if (mounted) {
      setState(() {
        if (saved != null && _intervals.contains(saved)) {
          _intervalMinutes = saved;
        }
        _registered = wasReg;
        _overlayPermissionDone = fullScreenPermDone;
        _batteryLimitDone = batteryLimitDone;
        _backgroundActivityDone = backgroundActivityDone;
        _miuiAlertDone = miuiAlertDone;
        _setupIntroDismissed = setupIntroDismissed;
        _hydration = savedH;
        _status = wasReg
            ? 'Watering every $_intervalMinutes min'
            : 'Tap Start to bloom';
      });
    }
  }

  Future<void> _register() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Registering...';
    });
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        setState(() => _status = 'Failed to get FCM token.');
        return;
      }

      final res = await _postRegister(token);
      if (res != null && res.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('intervalMinutes', _intervalMinutes);
        await prefs.setBool('registered', true);
        if (mounted) {
          setState(() {
            _registered = true;
            _status = 'Watering every $_intervalMinutes min';
          });
        }
      } else {
        if (mounted) {
          setState(() => _status = res != null
              ? 'Server error: ${res.body}'
              : 'Network error, try again.');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shared by the explicit "Start reminders" flow and the silent
  /// token-refresh listener. Returns null (rather than throwing) on network
  /// failure so callers can decide how noisy to be about it.
  Future<http.Response?> _postRegister(String fcmToken) async {
    try {
      final deviceId = await FirebaseInstallations.instance.getId();
      return await http.post(
        Uri.parse('$backendUrl/api/register'),
        headers: {
          'Content-Type': 'application/json',
          'x-register-secret': registerSecret,
        },
        body: jsonEncode({
          'deviceId': deviceId,
          'fcmToken': fcmToken,
          'intervalMinutes': _intervalMinutes,
          'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
        }),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final fullScreenPermDone = await isFullScreenIntentGranted();
    final batteryLimitDone = await isBatteryLimitDone();
    final backgroundActivityDone = prefs.getBool(backgroundActivityDoneKey) ??
        prefs.getBool(legacyBatteryPermissionDoneKey) ??
        false;
    final miuiAlertDone = prefs.getBool(miuiAlertDoneKey) ?? false;
    if (!mounted) return;
    setState(() {
      _overlayPermissionDone = fullScreenPermDone;
      _batteryLimitDone = batteryLimitDone;
      _backgroundActivityDone = backgroundActivityDone;
      _miuiAlertDone = miuiAlertDone;
    });
  }

  Future<void> _dismissSetupIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(setupIntroDismissedKey, true);
    if (mounted) setState(() => _setupIntroDismissed = true);
  }

  Future<void> _handleOverlayPermission() async {
    // On Android 14+ the system needs explicit permission for full-screen intents.
    // On older versions this is a no-op (already granted).
    try {
      final impl = localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await (impl as dynamic).requestFullScreenIntentPermission();
    } catch (_) {
      // Fallback: open app notification settings
      await AndroidIntent(
        action: 'android.settings.APP_NOTIFICATION_SETTINGS',
        arguments: {'android.provider.extra.APP_PACKAGE': appPackage},
      ).launch();
    }
    await _refreshPermissions();
    if (_overlayPermissionDone) _snack('Full-screen reminders enabled ✓');
  }

  Future<void> _handleMiuiAlertStyle() async {
    // Opens the system notification-channel settings screen for our channel.
    // On MIUI / HyperOS the user needs to change "Alert type" from the
    // default "Floating" (MIUI bubble popup) to "Banners" or "Priority",
    // otherwise full-screen intents are intercepted and shown as a tiny
    // top-of-screen card even when the screen is locked.
    //
    // Standard ACTION_CHANNEL_NOTIFICATION_SETTINGS works on all Android
    // versions >= 8 including MIUI; it opens directly to the right channel.
    try {
      await AndroidIntent(
        action: 'android.settings.CHANNEL_NOTIFICATION_SETTINGS',
        arguments: {
          'android.provider.extra.APP_PACKAGE': appPackage,
          'android.provider.extra.CHANNEL_ID': notifChannelId,
        },
      ).launch();
    } catch (_) {
      // Fallback: open generic app notification settings
      await AndroidIntent(
        action: 'android.settings.APP_NOTIFICATION_SETTINGS',
        arguments: {'android.provider.extra.APP_PACKAGE': appPackage},
      ).launch();
    }
    // Show a bottom-sheet explaining what to do, then let user confirm.
    if (!mounted) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Change alert style',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              'In the channel settings that just opened:\n\n'
              '1. Find "Alert type" or "Notification style"\n'
              '2. Change it from "Floating" to "Banners" or "Priority"\n'
              '3. Return here and tap Done\n\n'
              'This lets the full-screen reminder appear over the lock screen '
              'instead of as a small popup.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Not yet'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(miuiAlertDoneKey, true);
      await _refreshPermissions();
      _snack('Alert style updated ✓');
    }
  }

  Future<void> _handleBatteryLimitPermission() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      if (!status.isGranted) {
        await AndroidIntent(
                action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS')
            .launch();
      }
    } catch (_) {
      await openAppSettings();
    }

    await _refreshPermissions();
    if (_batteryLimitDone) {
      _snack('Battery limit disabled ✓');
    } else {
      _snack('Set battery use to unrestricted, then return here.');
    }
  }

  Future<void> _handleBackgroundActivityPermission() async {
    try {
      if (isXiaomiBrand(_brand)) {
        await openMiuiPermissionEditor();
      } else {
        await AndroidIntent(
          action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
          data: 'package:$appPackage',
        ).launch();
      }
    } catch (_) {
      await openAppSettings();
    }
    if (!mounted) return;

    final theme = HydrationTheme.of(_hydration);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        final bt = HydrationTheme.of(_hydration);
        return Padding(
          padding: EdgeInsets.fromLTRB(
              24, 12, 24, MediaQuery.of(ctx).padding.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                  child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: bt.surfaceAlt,
                  borderRadius: BorderRadius.circular(2),
                ),
              )),
              Text('Background activity done?',
                  style: TextStyle(
                    color: bt.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  )),
              const SizedBox(height: 8),
              Text(
                  'After allowing autostart or background activity, mark it done.',
                  style: TextStyle(
                      color: bt.textSecondary, fontSize: 14, height: 1.5)),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: bt.accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  child: const Text('Mark as done'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Not yet',
                    style: TextStyle(
                        color: bt.textSecondary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(backgroundActivityDoneKey, true);
      await _refreshPermissions();
      _snack('Background activity enabled ✓');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    final theme = HydrationTheme.of(_hydration);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style:
              TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w600)),
      backgroundColor: theme.surface,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      duration: const Duration(seconds: 4),
    ));
  }

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final theme = HydrationTheme.of(_hydration);

    final setupItems = <SetupItem>[
      SetupItem(
        label: 'Full-screen reminders',
        sub: 'Show reminders even on lock screen',
        done: _overlayPermissionDone,
        onTap: _handleOverlayPermission,
      ),
      SetupItem(
        label: 'Background activity',
        sub: 'Allow autostart and background running',
        done: _backgroundActivityDone,
        onTap: _handleBackgroundActivityPermission,
      ),
      SetupItem(
        label: 'Battery limit',
        sub: 'Set battery use to unrestricted',
        done: _batteryLimitDone,
        onTap: _handleBatteryLimitPermission,
      ),
      if (isXiaomiBrand(_brand))
        SetupItem(
          label: 'Alert style (MIUI)',
          sub: 'Change from Floating to Banners so reminders show full-screen',
          done: _miuiAlertDone,
          onTap: _handleMiuiAlertStyle,
        ),
    ];
    final allSetupDone = setupItems.every((i) => i.done);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        AppBackground(theme: theme),
        SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(24, 16, 24, bottom + 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _appBar(theme),
                const SizedBox(height: 28),

                // The flower — centerpiece
                Center(child: AnimatedFlower(hydration: _hydration, width: 260)),
                const SizedBox(height: 20),

                Center(child: HydrationBadge(theme: theme, hydration: _hydration)),
                const SizedBox(height: 28),

                if (kDebugMode) ...[
                  SectionCard(theme: theme, child: _debugHydrationSlider(theme)),
                  const SizedBox(height: 16),
                ],

                _waterButton(theme),
                const SizedBox(height: 24),

                SectionCard(
                  theme: theme,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionLabel('Remind me every', theme),
                      const SizedBox(height: 12),
                      IntervalSelector(
                        theme: theme,
                        intervals: _intervals,
                        selected: _intervalMinutes,
                        onSelect: (min) =>
                            setState(() => _intervalMinutes = min),
                      ),
                      const SizedBox(height: 14),
                      _startButton(theme),
                      const SizedBox(height: 12),
                      _quietHoursIndicator(theme),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                SectionCard(
                  theme: theme,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_setupIntroDismissed && !allSetupDone) ...[
                        _setupIntro(theme),
                        const SizedBox(height: 14),
                      ],
                      _sectionLabel('Setup', theme),
                      const SizedBox(height: 12),
                      SetupChecklist(theme: theme, items: setupItems),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ─── Sub-widgets ───────────────────────────────────────────────────────

  Widget _appBar(HydrationTheme t) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 600),
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                  child: const Text('Flora'),
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 600),
                  style: TextStyle(
                      color: t.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                  child: Text(_status),
                ),
              ]),
          const Spacer(),
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _registered ? t.chipSelected : t.surfaceAlt,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: _registered ? t.chipBorderSelected : t.border,
                  width: 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _registered ? t.accent : t.textMuted,
                ),
              ),
              const SizedBox(width: 7),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 600),
                style: TextStyle(
                  color: _registered ? t.accent : t.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
                child: Text(_registered ? 'Hydrated' : 'Dry'),
              ),
            ]),
          ),
        ],
      );

  Widget _waterButton(HydrationTheme t) => SizedBox(
        height: 58,
        child: ElevatedButton.icon(
          onPressed: _markDrink,
          icon: const Icon(Icons.water_drop_rounded, size: 20),
          label: const Text('I drank water!'),
          style: ElevatedButton.styleFrom(
            backgroundColor: t.accent,
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
      );

  Widget _sectionLabel(String text, HydrationTheme t) =>
      AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 600),
        style: TextStyle(
          color: t.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.5,
        ),
        child: Text(text.toUpperCase()),
      );

  Widget _startButton(HydrationTheme t) => SizedBox(
        height: 52,
        child: OutlinedButton(
          onPressed: _busy ? null : _register,
          style: OutlinedButton.styleFrom(
            foregroundColor: t.accent,
            side: BorderSide(color: t.accent.withValues(alpha: 0.30), width: 1),
            backgroundColor: t.accent.withValues(alpha: 0.07),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 400),
            style: TextStyle(
              color: t.accent,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
            child: Text(_busy
                ? 'Please wait...'
                : _registered
                    ? 'Update interval'
                    : 'Start reminders'),
          ),
        ),
      );

  Widget _setupIntro(HydrationTheme t) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A few permissions keep reminders showing up even when your '
              'phone is locked or Flora is closed.',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _dismissSetupIntro,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('Got it',
                    style: TextStyle(
                        color: t.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );

  /// Debug-only: lets you drag hydration to any level to preview the theme,
  /// flower, and badge without waiting on real drink/dismiss actions. Never
  /// shown in release builds (gated on kDebugMode at the call site).
  Widget _debugHydrationSlider(HydrationTheme t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _sectionLabel('Debug hydration', t),
            const Spacer(),
            Text(
              '${(_hydration * 100).round()}%',
              style: TextStyle(
                color: t.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: t.accent,
            inactiveTrackColor: t.surfaceAlt,
            thumbColor: t.accent,
            overlayColor: t.accent.withValues(alpha: 0.15),
          ),
          child: Slider(
            value: _hydration,
            min: 0.0,
            max: 1.0,
            onChanged: (v) => unawaited(_setHydrationDebug(v)),
          ),
        ),
      ],
    );
  }

  Widget _quietHoursIndicator(HydrationTheme t) {
    final quiet = isQuietHours();
    final message = quiet
        ? 'Reminders paused until 6:00 AM'
        : 'Active from 6 AM – 10 PM';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border, width: 1),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: quiet ? t.textMuted : t.accent,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}
