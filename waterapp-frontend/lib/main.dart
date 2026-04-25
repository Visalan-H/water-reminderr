import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:overlay_pop_up/overlay_pop_up.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _backendUrl = 'https://6pwng25f-3000.inc1.devtunnels.ms';
const String _registerSecret =
    '3d0b192504daa3643a1a7ebc85c21053420bb8f2fa09bbc5ddfc6cb709d832c597777c91dd4d3ed588232a75df77c3b4404c01b59b88a8f057fa10b9a73b0a13';
const String _overlayIcon = 'ic_launcher';
const String _overlayTitle = 'Water Reminder';
const String _appPackage =
    'com.example.waterreminder'; // ← update if your package name differs
const int _matchParent = -1;

// ─── Local notifications ───────────────────────────────────────────────────
final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

Future<void> _initLocalNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  await _localNotifications.initialize(
    const InitializationSettings(android: androidSettings),
    // Fires when user taps a local notification while app is alive (foreground
    // or background-but-not-killed). For the terminated-state tap we use
    // getNotificationAppLaunchDetails() inside _init().
    onDidReceiveNotificationResponse: (_) async {
      if (!await OverlayPopUp.isActive()) {
        await _showReminderOverlay();
      }
    },
  );

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'water_reminder',
    'Water Reminder',
    description: 'Water drinking reminders',
    importance: Importance.max,
    enableVibration: true,
    playSound: true,
    showBadge: true,
  );

  await _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

Future<void> _showFullScreenNotification({
  String title = '💧 Drink Water!',
  String body = 'Your body needs hydration.',
}) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'water_reminder',
    'Water Reminder',
    channelDescription: 'Water drinking reminders',
    importance: Importance.max,
    priority: Priority.max,
    fullScreenIntent: true,
    visibility: NotificationVisibility.public,
    enableVibration: true,
    playSound: true,
    autoCancel: true,
  );

  await _localNotifications.show(
    0,
    title,
    body,
    const NotificationDetails(android: androidDetails),
  );
}

Future<void> _requestNotificationPermissions() async {
  await FirebaseMessaging.instance.requestPermission();
  await Permission.notification.request();

  if (!Platform.isAndroid) return;

  final androidLocalNotifications =
      _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  if (androidLocalNotifications == null) return;

  // Newer Android versions may gate full-screen notifications separately.
  try {
    await (androidLocalNotifications as dynamic)
        .requestFullScreenIntentPermission();
  } catch (_) {
    // Older plugin/API levels may not expose this call.
  }
}

Future<void> _showReminderOverlay() async {
  await OverlayPopUp.showOverlay(
    width: _matchParent,
    height: _matchParent,
    backgroundBehavior: OverlayFlag.focusable,
    closeWhenTapBackButton: true,
    notificationIcon: _overlayIcon,
    notificationTitle: _overlayTitle,
  );
}

const String _hydrationLevelKey = 'hydrationLevel';
const String _hydrationUpdatedAtKey = 'hydrationUpdatedAt';
const double _drinkHydrationBoost = 0.22;
const double _dismissHydrationDrop = 0.08;

double _normalizeHydration(double value) {
  return value.clamp(0.0, 1.0).toDouble();
}

Future<double> _readHydrationValue() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final savedHydration = prefs.getDouble(_hydrationLevelKey);
  if (savedHydration != null) {
    return _normalizeHydration(savedHydration);
  }

  final now = DateTime.now().millisecondsSinceEpoch;
  await prefs.setDouble(_hydrationLevelKey, 1.0);
  await prefs.setInt(_hydrationUpdatedAtKey, now);
  await prefs.setInt('lastDrinkTime', now);
  return 1.0;
}

Future<double> _changeHydration(double delta,
    {bool markAsDrink = false}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final currentHydration = _normalizeHydration(
    prefs.getDouble(_hydrationLevelKey) ?? 1.0,
  );
  final updatedHydration = _normalizeHydration(currentHydration + delta);
  final now = DateTime.now().millisecondsSinceEpoch;

  await prefs.setDouble(_hydrationLevelKey, updatedHydration);
  await prefs.setInt(_hydrationUpdatedAtKey, now);
  if (markAsDrink) {
    await prefs.setInt('lastDrinkTime', now);
  }

  return updatedHydration;
}

Future<double> _recordDrinkAction() async {
  return _changeHydration(_drinkHydrationBoost, markAsDrink: true);
}

Future<double> _recordDismissAction() async {
  return _changeHydration(-_dismissHydrationDrop);
}

// ─── FCM background handler ────────────────────────────────────────────────
// Runs in a separate isolate when the app is background or killed.
// We first try to show the overlay directly. If that fails on a device/ROM,
// we fall back to a high-priority full-screen local notification.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  if (message.data['type'] == 'water_reminder') {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(android: androidSettings),
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'water_reminder',
      'Water Reminder',
      description: 'Water drinking reminders',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      showBadge: true,
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    try {
      final overlayPermission = await OverlayPopUp.checkPermission();
      if (overlayPermission) {
        final isActive = await OverlayPopUp.isActive();
        if (!isActive) {
          await _showReminderOverlay();
          return;
        }
      }
    } catch (_) {
      // Fall back to notification path below.
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'water_reminder',
      'Water Reminder',
      channelDescription: 'Water drinking reminders',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      enableVibration: true,
      playSound: true,
      autoCancel: true,
    );

    await flutterLocalNotificationsPlugin.show(
      0,
      message.data['title'] ?? '💧 Drink Water!',
      message.data['body'] ?? 'Your body needs hydration.',
      const NotificationDetails(android: androidDetails),
    );
  }
}

// ─── Overlay screen ────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void overlayPopUp() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: appTheme,
    home: const OverlayScreen(),
  ));
}

class AppColors {
  static const Color background = Color(0xFFEAF3FF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color primary = Color(0xFF1463D8);
  static const Color secondary = Color(0xFF9DC8FF);
  static const Color textPrimary = Color(0xFF0E2A4A);
  static const Color textSecondary = Color(0xFF4F6E90);
  static const Color error = Color(0xFFD15050);
  static const Color panelBlue = Color(0xFFD9E9FF);
}

final ThemeData appTheme = ThemeData(
  scaffoldBackgroundColor: AppColors.background,
  primaryColor: AppColors.primary,
  colorScheme: const ColorScheme.light(
    primary: AppColors.primary,
    secondary: AppColors.secondary,
    surface: AppColors.surface,
    error: AppColors.error,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    elevation: 0,
    centerTitle: true,
  ),
  chipTheme: ChipThemeData(
    backgroundColor: Colors.white,
    selectedColor: AppColors.primary.withOpacity(0.14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    side: BorderSide(color: AppColors.secondary.withOpacity(0.85)),
    labelStyle: const TextStyle(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w500,
    ),
    secondaryLabelStyle: const TextStyle(
      color: AppColors.primary,
      fontWeight: FontWeight.w600,
    ),
  ),
  textTheme: const TextTheme(
    headlineMedium: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 28,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.5),
    titleLarge: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w400),
    bodyMedium: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 14,
        fontWeight: FontWeight.w400),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      textStyle: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 0.5),
    ),
  ),
);

// ─── Widgets ───────────────────────────────────────────────────────────────
class FlowerWidget extends StatelessWidget {
  final double hydration;

  const FlowerWidget({super.key, required this.hydration});

  @override
  Widget build(BuildContext context) {
    String emoji = '🥀';
    double size = 92;
    double opacity = 0.72;

    if (hydration >= 0.85) {
      emoji = '🌸';
      size = 150;
      opacity = 1.0;
    } else if (hydration >= 0.65) {
      emoji = '🌺';
      size = 138;
      opacity = 0.98;
    } else if (hydration >= 0.45) {
      emoji = '🌷';
      size = 120;
      opacity = 0.9;
    } else if (hydration >= 0.25) {
      emoji = '🌼';
      size = 100;
      opacity = 0.82;
    }

    return AnimatedContainer(
      duration: const Duration(seconds: 2),
      curve: Curves.easeInOut,
      height: 200,
      alignment: Alignment.center,
      child: Container(
        width: 210,
        height: 210,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [Colors.white, AppColors.panelBlue],
            radius: 0.88,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.16),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 800),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Text(
              emoji,
              key: ValueKey(emoji),
              style: TextStyle(
                  fontSize: size,
                  color: AppColors.primary.withOpacity(opacity)),
            ),
          ),
        ),
      ),
    );
  }
}

class StatusCard extends StatelessWidget {
  final double hydration;

  const StatusCard({super.key, required this.hydration});

  @override
  Widget build(BuildContext context) {
    final hydrationPercent = (hydration.clamp(0.0, 1.0) * 100).round();

    String title = "Your plant is dry.";
    String subtitle = "It needs multiple drinks to recover.";

    if (hydration >= 0.85) {
      title = "Fully blooming.";
      subtitle = "Excellent hydration and growth.";
    } else if (hydration >= 0.65) {
      title = "Healthy bloom.";
      subtitle = "Keep drinking regularly.";
    } else if (hydration >= 0.45) {
      title = "Stable flower.";
      subtitle = "It is okay, but needs more water soon.";
    } else if (hydration >= 0.25) {
      title = "Wilting started.";
      subtitle = "Dismissed reminders are drying the flower.";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: hydration.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: AppColors.panelBlue,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$hydrationPercent% hydrated',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  const PrimaryButton({super.key, required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      child: Text(text),
    );
  }
}

class OverlayScreen extends StatefulWidget {
  const OverlayScreen({super.key});
  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen> {
  double _overlayHydration = 1.0;

  @override
  void initState() {
    super.initState();
    OverlayPopUp.initializeOverlayHandler();
    unawaited(_loadOverlayHydration());
  }

  Future<void> _loadOverlayHydration() async {
    final hydration = await _readHydrationValue();
    if (!mounted) return;
    setState(() {
      _overlayHydration = hydration;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF6FF),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFCCE3FF), Color(0xFFEFF6FF)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(height: 4),
                Column(
                  children: [
                    FlowerWidget(hydration: _overlayHydration),
                    const SizedBox(height: 20),
                    Text(
                      'Your flower needs water.',
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Drink now to bring it back to life.',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: PrimaryButton(
                        onPressed: () async {
                          final updatedHydration = await _recordDrinkAction();
                          if (mounted) {
                            setState(() {
                              _overlayHydration = updatedHydration;
                            });
                          }
                          await OverlayPopUp.closeOverlay();
                        },
                        text: 'I drank water',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () async {
                        final updatedHydration = await _recordDismissAction();
                        if (mounted) {
                          setState(() {
                            _overlayHydration = updatedHydration;
                          });
                        }
                        await OverlayPopUp.closeOverlay();
                      },
                      child: const Text(
                        'Dismiss',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── MIUI background popup permission ─────────────────────────────────────
// On Xiaomi/Redmi/POCO, SYSTEM_ALERT_WINDOW alone is not enough. MIUI adds a
// second separate gate: "Display pop-up windows while running in background".
// Without it, WindowManager rejects the overlay view immediately after creation
// — which is exactly what the "assignParent to null" log warning means.
// This intent opens the MIUI permission editor directly on the right page.
bool _isXiaomiBrand(String brand) {
  final b = brand.toLowerCase();
  return b.contains('xiaomi') || b.contains('redmi') || b.contains('poco');
}

Future<void> _openMiuiPermissionEditor() async {
  try {
    final intent = AndroidIntent(
      action: 'miui.intent.action.APP_PERM_EDITOR',
      package: 'com.miui.securitycenter',
      componentName:
          'com.miui.permcenter.permissions.PermissionsEditorActivity',
      arguments: {'extra_pkgname': _appPackage},
    );
    await intent.launch();
  } catch (_) {
    // Fallback: older MIUI versions use a different activity name
    try {
      final intent = AndroidIntent(
        action: 'miui.intent.action.APP_PERM_EDITOR',
        package: 'com.miui.securitycenter',
        componentName:
            'com.miui.permcenter.permissions.AppPermissionsEditorActivity',
        arguments: {'extra_pkgname': _appPackage},
      );
      await intent.launch();
    } catch (_) {
      // If both fail the caller shows a fallback message.
      rethrow;
    }
  }
}

// ─── Brand-specific battery steps ─────────────────────────────────────────
Map<String, List<String>> _getBrandSteps(String brand) {
  final b = brand.toLowerCase();
  if (b.contains('xiaomi') || b.contains('redmi') || b.contains('poco')) {
    return {
      // Step 0 is the critical MIUI-specific overlay permission — tap the button
      // above first, then manually confirm "Display pop-up windows while running
      // in background" is ON in the page that opens.
      '0. ⚠️ MIUI pop-up permission (CRITICAL)': [
        'Tap "Grant MIUI pop-up permission" button above',
        'In the page that opens, find "Display pop-up windows while running in background" → turn it ON',
        'Without this, the overlay will always silently fail on Xiaomi/Redmi/POCO',
      ],
      '1. Autostart': [
        'Settings → Apps → Manage apps → Water Reminder → Autostart → ON',
      ],
      '2. Battery': [
        'Settings → Battery → Battery saver → App battery saver → Water Reminder → No restrictions',
      ],
      '3. Lock in recents': [
        'Open recent apps → swipe down on Water Reminder → tap the 🔒 lock icon',
      ],
    };
  } else if (b.contains('huawei') || b.contains('honor')) {
    return {
      '1. App launch': [
        'Settings → Battery → App launch → Water Reminder → Disable "Manage automatically" → Enable Auto-launch, Secondary launch, Run in background',
      ],
    };
  } else if (b.contains('samsung')) {
    return {
      '1. Never sleeping': [
        'Settings → Battery and device care → Battery → Background usage limits → Never sleeping apps → Add Water Reminder',
      ],
      '2. Battery': [
        'Settings → Apps → Water Reminder → Battery → Unrestricted',
      ],
    };
  } else if (b.contains('oneplus') || b.contains('oppo')) {
    return {
      '1. Battery': [
        'Settings → Battery → Battery optimization → Water Reminder → Don\'t optimize',
      ],
      '2. Auto-launch': [
        'Settings → Apps → Auto-launch → Water Reminder → Allow',
      ],
    };
  } else if (b.contains('vivo')) {
    return {
      '1. Background': [
        'Settings → Battery → Background power consumption → Water Reminder → No restrictions',
      ],
      '2. Auto-start': [
        'Settings → More settings → Application permissions → Autostart → Water Reminder → ON',
      ],
    };
  } else if (b.contains('realme')) {
    return {
      '1. Battery': [
        'Settings → Battery → Battery optimization → Water Reminder → Don\'t optimize',
      ],
      '2. Auto-start': [
        'Settings → Apps → Manage apps → Water Reminder → Auto-start → ON',
      ],
    };
  } else {
    return {
      '1. Battery': [
        'Settings → Apps → Water Reminder → Battery → Unrestricted',
      ],
    };
  }
}

// ─── Main ─────────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 🔴 MUST be first
    await Firebase.initializeApp();

    // 🔴 MUST be registered BEFORE runApp and as early as possible
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 🔴 Prevent OS from auto-showing notifications (gives you full control)
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );

    // 🔴 Init local notifications once (main isolate only)
    await _initLocalNotifications();

    runApp(MaterialApp(theme: appTheme, home: const HomePage()));
  } catch (e) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'Init error: $e',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ),
    ));
  }
}

// ─── Home ─────────────────────────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const List<int> _intervalOptions = [
    10,
    1,
    30,
    45,
    60,
    90,
    120,
    180,
    240
  ];

  int _intervalMinutes = 60;
  bool _registered = false;
  bool _busy = false;
  bool _overlayPermissionDone = false;
  bool _batteryPermissionDone = false;
  String _status = 'Setting up...';
  String _brand = '';
  double _hydration = 1.0;
  Timer? _hydrationTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_init());
    _hydrationTicker = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_updateHydrationFromClock()),
    );

    // ── Foreground FCM ──────────────────────────────────────────────────────
    // App is open and visible — show overlay directly.
    FirebaseMessaging.onMessage.listen((message) async {
      if (message.data['type'] == 'water_reminder') {
        if (!await OverlayPopUp.isActive()) {
          await _showReminderOverlay();
        }
      }
    });

    // ── Background FCM tap ──────────────────────────────────────────────────
    // Fires when user taps a tray notification that arrived while app was
    // backgrounded (only matters if a notification-type message ever slips
    // through; kept as a safety net).
    FirebaseMessaging.onMessageOpenedApp.listen((message) async {
      if (message.data['type'] == 'water_reminder') {
        if (!await OverlayPopUp.isActive()) {
          await _showReminderOverlay();
        }
      }
    });

    // ── Terminated FCM tap ──────────────────────────────────────────────────
    // getInitialMessage returns the message that cold-started the app from a
    // tray notification tap (null if launched normally).
    FirebaseMessaging.instance.getInitialMessage().then((message) async {
      if (message?.data['type'] == 'water_reminder') {
        if (!await OverlayPopUp.isActive()) {
          await _showReminderOverlay();
        }
      }
    });
  }

  @override
  void dispose() {
    _hydrationTicker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncHydrationFromPrefs());
    }
  }

  Future<void> _updateHydrationFromClock() async {
    final latestHydration = await _readHydrationValue();

    if (!mounted) return;
    setState(() {
      _hydration = latestHydration;
    });
  }

  Future<void> _syncHydrationFromPrefs() async {
    final latestHydration = await _readHydrationValue();
    if (!mounted) return;
    setState(() {
      _hydration = latestHydration;
    });
  }

  Future<void> _markDrinkNow() async {
    final updatedHydration = await _recordDrinkAction();
    if (!mounted) return;
    setState(() {
      _hydration = updatedHydration;
    });
    _showSnack('Nice! Hydration increased. Keep it going to fully bloom.');
  }

  Future<void> _init() async {
    await _requestNotificationPermissions();

    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (mounted) setState(() => _brand = info.manufacturer);
    }

    // ── Terminated local notification tap ───────────────────────────────────
    // onDidReceiveNotificationResponse only fires when the app is already alive.
    // For terminated-state taps we need this separate check.
    final launchDetails =
        await _localNotifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      if (!await OverlayPopUp.isActive()) {
        await _showReminderOverlay();
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('intervalMinutes');
    final wasRegistered = prefs.getBool('registered') ?? false;
    final overlayDone = await OverlayPopUp.checkPermission();
    final batteryDone = prefs.getBool('batteryPermissionDone') ?? false;
    final savedHydration = await _readHydrationValue();

    if (mounted) {
      setState(() {
        if (saved != null && _intervalOptions.contains(saved)) {
          _intervalMinutes = saved;
        }
        _registered = wasRegistered;
        _overlayPermissionDone = overlayDone;
        _batteryPermissionDone = batteryDone;
        _hydration = savedHydration;
        _status = wasRegistered
            ? '🟢 Active — reminding every $_intervalMinutes min'
            : 'Tap Start to activate reminders';
      });
    }
  }

  Future<void> _register() async {
    if (_busy) return;

    // if (_intervalMinutes < 10) {
    //   setState(() => _status = '❌ Minimum interval is 10 minutes.');
    //   return;
    // }

    setState(() {
      _busy = true;
      _status = 'Registering...';
    });

    try {
      final deviceId = await FirebaseInstallations.instance.getId();
      final fcmToken = await FirebaseMessaging.instance.getToken();

      if (fcmToken == null) {
        setState(
            () => _status = '❌ Failed to get FCM token. Check Firebase setup.');
        return;
      }

      final res = await http.post(
        Uri.parse('$_backendUrl/api/register'),
        headers: {
          'Content-Type': 'application/json',
          'x-register-secret': _registerSecret,
        },
        body: jsonEncode({
          'deviceId': deviceId,
          'fcmToken': fcmToken,
          'intervalMinutes': _intervalMinutes,
        }),
      );

      if (res.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('intervalMinutes', _intervalMinutes);
        await prefs.setBool('registered', true);
        if (mounted) {
          setState(() {
            _registered = true;
            _status = '🟢 Active — reminding every $_intervalMinutes min';
          });
        }
      } else {
        if (mounted) setState(() => _status = '❌ Server error: ${res.body}');
      }
    } catch (err) {
      if (mounted) setState(() => _status = '❌ Error: $err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshPermissionState() async {
    final prefs = await SharedPreferences.getInstance();
    final overlayDone = await OverlayPopUp.checkPermission();
    final batteryDone = prefs.getBool('batteryPermissionDone') ?? false;
    if (!mounted) return;
    setState(() {
      _overlayPermissionDone = overlayDone;
      _batteryPermissionDone = batteryDone;
    });
  }

  Future<void> _handleOverlayPermission() async {
    final alreadyGranted = await OverlayPopUp.checkPermission();
    if (!alreadyGranted) {
      await OverlayPopUp.requestPermission();
    }
    await _refreshPermissionState();
    if (_overlayPermissionDone) {
      _showSnack('✅ Display overlay permission enabled');
    }
  }

  Future<void> _handleBatteryPermission() async {
    try {
      if (_isXiaomiBrand(_brand)) {
        await _openMiuiPermissionEditor();
      } else {
        final intent = AndroidIntent(
          action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
        );
        await intent.launch();
      }
    } catch (_) {
      await openAppSettings();
    }

    if (!mounted) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Battery permission completed?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'After enabling unrestricted background or battery settings, mark this as done.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Mark as done'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not yet'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('batteryPermissionDone', true);
      await _refreshPermissionState();
      _showSnack('✅ Battery permissions marked as done');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
  }

  Widget _buildPermissionButton({
    required String label,
    required bool done,
    required VoidCallback onPressed,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: done ? AppColors.primary.withOpacity(0.12) : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color:
              done ? AppColors.primary.withOpacity(0.35) : AppColors.secondary,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        trailing: Icon(
          done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          color: done ? AppColors.primary : AppColors.textSecondary,
        ),
        onTap: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      appBar: AppBar(title: const Text('💧 Water Reminder')),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFD8EAFF), AppColors.background],
          ),
        ),
        child: SafeArea(
          top: false,
          bottom: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        'My Water Plant',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      FlowerWidget(hydration: _hydration),
                      const SizedBox(height: 8),
                      StatusCard(hydration: _hydration),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _markDrinkNow,
                          icon: const Icon(Icons.local_drink_rounded),
                          label: const Text('I drank now'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Remind me every:',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _intervalOptions
                      .map((min) => ChoiceChip(
                            label: Text(min < 60
                                ? '${min}m'
                                : '${min ~/ 60}h${min % 60 != 0 ? ' ${min % 60}m' : ''}'),
                            labelStyle: TextStyle(
                              color: _intervalMinutes == min
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                            backgroundColor: Colors.white,
                            selectedColor: AppColors.primary.withOpacity(0.18),
                            checkmarkColor: AppColors.primary,
                            selected: _intervalMinutes == min,
                            onSelected: (_) {
                              setState(() {
                                _intervalMinutes = min;
                              });
                            },
                          ))
                      .toList(),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _busy ? null : _register,
                  child: Text(_busy
                      ? 'Please wait...'
                      : _registered
                          ? 'Update interval'
                          : '▶  Start reminders'),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Permissions',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 12),
                _buildPermissionButton(
                  label: 'Display overlay permission',
                  done: _overlayPermissionDone,
                  onPressed: _handleOverlayPermission,
                ),
                const SizedBox(height: 10),
                _buildPermissionButton(
                  label: 'Battery permissions',
                  done: _batteryPermissionDone,
                  onPressed: _handleBatteryPermission,
                ),
                const SizedBox(height: 16),
                if (_overlayPermissionDone && _batteryPermissionDone)
                  const Text(
                    'All required permissions are set',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
