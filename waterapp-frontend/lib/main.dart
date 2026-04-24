import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:overlay_pop_up/overlay_pop_up.dart';
import 'package:permission_handler/permission_handler.dart';

const String _overlayNotificationIcon = 'ic_launcher';
const String _overlayNotificationTitle = 'Water Reminder';

// ─── Overlay screen ────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void overlayPopUp() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: OverlayScreen()));
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
                  style: TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('Your body needs hydration.',
                  style: TextStyle(fontSize: 16, color: Colors.lightBlueAccent)),
              const SizedBox(height: 48),
              SizedBox(
                width: 220, height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blue.shade900,
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

// ─── Background task ───────────────────────────────────────────────────────
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(WaterTaskHandler());
}

class WaterTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_showReminderOverlay());
  }

  Future<void> _showReminderOverlay() async {
    try {
      if (await OverlayPopUp.isActive()) return;
      await OverlayPopUp.showOverlay(
        notificationIcon: _overlayNotificationIcon,
        notificationTitle: _overlayNotificationTitle,
        closeWhenTapBackButton: true,
      );
    } catch (error) {
      FlutterForegroundTask.sendDataToMain('overlay_error:$error');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

// ─── Manufacturer-specific battery fix instructions ────────────────────────
Map<String, List<String>> _getBrandSteps(String brand) {
  final b = brand.toLowerCase();
  if (b.contains('xiaomi') || b.contains('redmi') || b.contains('poco')) {
    return {
      '1. Autostart': ['Settings → Apps → Manage apps → Water Reminder → Autostart → ON'],
      '2. Battery saver': ['Settings → Battery → Battery saver → App battery saver → Water Reminder → No restrictions'],
      '3. Lock in recents': ['Open recent apps → swipe down on Water Reminder → tap the 🔒 lock icon'],
    };
  } else if (b.contains('huawei') || b.contains('honor')) {
    return {
      '1. App launch': ['Settings → Battery → App launch → Water Reminder → Disable "Manage automatically" → Enable Auto-launch, Secondary launch, Run in background'],
    };
  } else if (b.contains('samsung')) {
    return {
      '1. Never sleeping': ['Settings → Battery and device care → Battery → Background usage limits → Never sleeping apps → Add Water Reminder'],
      '2. Battery': ['Settings → Apps → Water Reminder → Battery → Unrestricted'],
    };
  } else if (b.contains('oneplus') || b.contains('oppo')) {
    return {
      '1. Battery': ['Settings → Battery → Battery optimization → Water Reminder → Don\'t optimize'],
      '2. Auto-launch': ['Settings → Apps → Auto-launch → Water Reminder → Allow'],
    };
  } else if (b.contains('vivo')) {
    return {
      '1. Background': ['Settings → Battery → Background power consumption → Water Reminder → No restrictions'],
      '2. Auto-start': ['Settings → More settings → Application permissions → Autostart → Water Reminder → ON'],
    };
  } else if (b.contains('realme')) {
    return {
      '1. Battery': ['Settings → Battery → Battery optimization → Water Reminder → Don\'t optimize'],
      '2. Auto-start': ['Settings → Apps → Manage apps → Water Reminder → Auto-start → ON'],
    };
  } else {
    // Stock Android / Google Pixel
    return {
      '1. Battery': ['Settings → Apps → Water Reminder → Battery → Unrestricted'],
    };
  }
}

// ─── App ───────────────────────────────────────────────────────────────────
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  runApp(const MaterialApp(home: HomePage()));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _seconds = 30;
  bool _running = false;
  bool _busy = false;
  String _brand = '';

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    unawaited(_syncRunningState());
    unawaited(_detectBrand());
  }

  Future<void> _detectBrand() async {
    if (!Platform.isAndroid) return;
    final info = await DeviceInfoPlugin().androidInfo;
    if (!mounted) return;
    setState(() => _brand = info.manufacturer);
  }

  void _onTaskData(Object data) {
    if (!mounted) return;
    if (data is String && data.startsWith('overlay_error:')) {
      _showSnack(data.replaceFirst('overlay_error:', ''));
    }
  }

  ForegroundTaskOptions _taskOptions() => ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(_seconds * 1000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
      );

  void _initService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'water',
        channelName: 'Water Reminder',
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.DEFAULT,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: _taskOptions(),
    );
  }

  Future<void> _syncRunningState() async {
    final bool isRunning = await FlutterForegroundTask.isRunningService;
    if (!mounted) return;
    setState(() => _running = isRunning);
  }

  Future<bool> _ensureOverlayPermission() async {
    if (await OverlayPopUp.checkPermission()) return true;
    await OverlayPopUp.requestPermission();
    return OverlayPopUp.checkPermission();
  }

  Future<void> _doAllPermissions() async {
    // 1. Overlay
    await _ensureOverlayPermission();
    // 2. Notification
    await FlutterForegroundTask.requestNotificationPermission();
    // 3. Battery optimization exemption
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    // 4. Exact alarms (for doze-mode self-restart)
    if (!await FlutterForegroundTask.canScheduleExactAlarms) {
      await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
    }
    _showSnack('✅ All permissions set. Now follow the phone-specific steps below.');
  }

  Future<void> _startOrUpdateService() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await _ensureOverlayPermission()) {
        _showSnack('Overlay permission is required.');
        return;
      }
      _initService();
      final bool alreadyRunning = await FlutterForegroundTask.isRunningService;
      final ServiceRequestResult result;
      if (alreadyRunning) {
        result = await FlutterForegroundTask.updateService(
          notificationTitle: 'Water Reminder active',
          notificationText: 'Reminding every $_seconds seconds',
          foregroundTaskOptions: _taskOptions(),
          callback: startCallback,
        );
      } else {
        result = await FlutterForegroundTask.startService(
          serviceId: 1000,
          notificationTitle: 'Water Reminder active',
          notificationText: 'Reminding every $_seconds seconds',
          callback: startCallback,
        );
      }
      await _syncRunningState();
      if (result is ServiceRequestFailure) _showSnack('Failed: ${result.error}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await FlutterForegroundTask.stopService();
      await _syncRunningState();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showOverlayNow() async {
    if (!await _ensureOverlayPermission()) { _showSnack('Overlay permission required.'); return; }
    if (await OverlayPopUp.isActive()) { _showSnack('Already visible.'); return; }
    await OverlayPopUp.showOverlay(
      notificationIcon: _overlayNotificationIcon,
      notificationTitle: _overlayNotificationTitle,
      closeWhenTapBackButton: true,
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final brandSteps = _brand.isNotEmpty ? _getBrandSteps(_brand) : <String, List<String>>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Water Reminder')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status
            Text(_running ? '🟢 Running — every $_seconds sec' : '🔴 Not running',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),

            // Interval
            Text('Interval: $_seconds seconds'),
            Slider(
              value: _seconds.toDouble(), min: 10, max: 120, divisions: 22,
              label: '$_seconds sec',
              onChanged: (v) => setState(() => _seconds = v.round()),
              onChangeEnd: (_) { if (_running) unawaited(_startOrUpdateService()); },
            ),
            const SizedBox(height: 8),

            ElevatedButton(
              onPressed: _busy ? null : _startOrUpdateService,
              child: Text(_running ? 'Update interval' : '▶  Start'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: (_busy || !_running) ? null : _stop,
              child: const Text('⏹  Stop'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _showOverlayNow,
              child: const Text('🧪 Test overlay now'),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),

            // Step 1: permissions button
            const Text('Setup (do this once)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: _doAllPermissions,
              child: const Text('⚡ Grant all permissions', style: TextStyle(color: Colors.white)),
            ),

            // Step 2: brand-specific manual steps
            if (brandSteps.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Manual steps for $_brand (required!)',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const SizedBox(height: 8),
              ...brandSteps.entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ...entry.value.map((step) => Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: Text('→ $step', style: const TextStyle(fontSize: 13)),
                    )),
                  ],
                ),
              )),
            ],

            const SizedBox(height: 8),
            const Text(
              'More device-specific guides: dontkillmyapp.com',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    super.dispose();
  }
}