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
        await OverlayPopUp.showOverlay(
          notificationIcon: _overlayIcon,
          notificationTitle: _overlayTitle,
          closeWhenTapBackButton: true,
        );
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
          await OverlayPopUp.showOverlay(
            notificationIcon: _overlayIcon,
            notificationTitle: _overlayTitle,
            closeWhenTapBackButton: true,
          );
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
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OverlayScreen(),
  ));
}

class OverlayScreen extends StatefulWidget {
  const OverlayScreen({super.key});
  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen> {
  @override
  void initState() {
    super.initState();
    OverlayPopUp.initializeOverlayHandler();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.blue.shade900.withValues(alpha: 0.97),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('💧', style: TextStyle(fontSize: 80)),
              const SizedBox(height: 24),
              const Text('Drink Water!',
                  style: TextStyle(
                      fontSize: 32,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('Your body needs hydration.',
                  style:
                      TextStyle(fontSize: 16, color: Colors.lightBlueAccent)),
              const SizedBox(height: 48),
              SizedBox(
                width: 220,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blue.shade900,
                    textStyle: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  onPressed: OverlayPopUp.closeOverlay,
                  child: const Text('✓  I drank water'),
                ),
              ),
            ],
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
      // If both fail the user will see the snack message in _doAllPermissions
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

    runApp(const MaterialApp(home: HomePage()));
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

class _HomePageState extends State<HomePage> {
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
  String _status = 'Setting up...';
  String _brand = '';

  @override
  void initState() {
    super.initState();
    unawaited(_init());

    // ── Foreground FCM ──────────────────────────────────────────────────────
    // App is open and visible — show overlay directly.
    FirebaseMessaging.onMessage.listen((message) async {
      if (message.data['type'] == 'water_reminder') {
        if (!await OverlayPopUp.isActive()) {
          await OverlayPopUp.showOverlay(
            notificationIcon: _overlayIcon,
            notificationTitle: _overlayTitle,
            closeWhenTapBackButton: true,
          );
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
          await OverlayPopUp.showOverlay(
            notificationIcon: _overlayIcon,
            notificationTitle: _overlayTitle,
            closeWhenTapBackButton: true,
          );
        }
      }
    });

    // ── Terminated FCM tap ──────────────────────────────────────────────────
    // getInitialMessage returns the message that cold-started the app from a
    // tray notification tap (null if launched normally).
    FirebaseMessaging.instance.getInitialMessage().then((message) async {
      if (message?.data['type'] == 'water_reminder') {
        if (!await OverlayPopUp.isActive()) {
          await OverlayPopUp.showOverlay(
            notificationIcon: _overlayIcon,
            notificationTitle: _overlayTitle,
            closeWhenTapBackButton: true,
          );
        }
      }
    });
  }

  Future<void> _init() async {
    if (!await OverlayPopUp.checkPermission()) {
      await OverlayPopUp.requestPermission();
    }

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
        await OverlayPopUp.showOverlay(
          notificationIcon: _overlayIcon,
          notificationTitle: _overlayTitle,
          closeWhenTapBackButton: true,
        );
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('intervalMinutes');
    final wasRegistered = prefs.getBool('registered') ?? false;

    if (mounted) {
      setState(() {
        if (saved != null && _intervalOptions.contains(saved)) {
          _intervalMinutes = saved;
        }
        _registered = wasRegistered;
        _status = wasRegistered
            ? '🟢 Active — reminding every $_intervalMinutes min'
            : 'Tap Start to activate reminders';
      });
    }
  }

  Future<void> _register() async {
    if (_busy) return;

    if (_intervalMinutes < 10) {
      setState(() => _status = '❌ Minimum interval is 10 minutes.');
      return;
    }

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

  Future<void> _doAllPermissions() async {
    // 1. Standard overlay permission (SYSTEM_ALERT_WINDOW)
    if (!await OverlayPopUp.checkPermission()) {
      await OverlayPopUp.requestPermission();
    }

    // 2. FCM + notification permission
    await _requestNotificationPermissions();

    // 3. Xiaomi only: open MIUI permission editor for the second overlay gate
    //    ("Display pop-up windows while running in background"). This is the
    //    cause of the "assignParent to null" crash seen in the logs — standard
    //    SYSTEM_ALERT_WINDOW is not enough on MIUI.
    if (_isXiaomiBrand(_brand)) {
      try {
        await _openMiuiPermissionEditor();
        _showSnack(
            '✅ Find "Display pop-up windows while running in background" → turn it ON');
      } catch (_) {
        _showSnack('⚠️ Could not open MIUI settings automatically. '
            'Go to Settings → Apps → Water Reminder → Other permissions manually.');
      }
    } else {
      _showSnack('✅ Done. Now follow the steps below for your phone.');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
  }

  @override
  Widget build(BuildContext context) {
    final brandSteps =
        _brand.isNotEmpty ? _getBrandSteps(_brand) : <String, List<String>>{};
    final isXiaomi = _isXiaomiBrand(_brand);

    return Scaffold(
      appBar: AppBar(title: const Text('💧 Water Reminder')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 24),

            const Text('Remind me every:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _intervalOptions
                  .map((min) => ChoiceChip(
                        label: Text(min < 60
                            ? '${min}m'
                            : '${min ~/ 60}h${min % 60 != 0 ? ' ${min % 60}m' : ''}'),
                        selected: _intervalMinutes == min,
                        onSelected: (_) =>
                            setState(() => _intervalMinutes = min),
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
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () async {
                if (!await OverlayPopUp.isActive()) {
                  await OverlayPopUp.showOverlay(
                    notificationIcon: _overlayIcon,
                    notificationTitle: _overlayTitle,
                    closeWhenTapBackButton: true,
                  );
                }
              },
              child: const Text('🧪 Test overlay now'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () async {
                await _showFullScreenNotification();
              },
              child: const Text('🧪 Test full-screen notification'),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),

            const Text('Setup (do once)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),

            // Standard permissions button
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: _doAllPermissions,
              child: const Text('⚡ Grant all permissions',
                  style: TextStyle(color: Colors.white)),
            ),

            // Separate prominent button for the MIUI-specific permission that is
            // the confirmed root cause of overlay failure on Xiaomi devices.
            if (isXiaomi) ...[
              const SizedBox(height: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  try {
                    await _openMiuiPermissionEditor();
                    _showSnack(
                        '👆 Find "Display pop-up windows while running in background" → turn it ON');
                  } catch (_) {
                    _showSnack(
                        '⚠️ Open Settings → Apps → Water Reminder → Other permissions manually.');
                  }
                },
                child: const Text('🔴 Grant MIUI pop-up permission',
                    style: TextStyle(color: Colors.white)),
              ),
            ],

            if (brandSteps.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Manual steps for $_brand (required!)',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const SizedBox(height: 8),
              ...brandSteps.entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.key,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        ...entry.value.map((step) => Padding(
                              padding: const EdgeInsets.only(left: 8, top: 4),
                              child: Text('→ $step',
                                  style: const TextStyle(fontSize: 13)),
                            )),
                      ],
                    ),
                  )),
            ],

            const SizedBox(height: 8),
            const Text(
              'More device guides: dontkillmyapp.com',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
