import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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

const String _backendUrl = String.fromEnvironment('BACKEND_URL');
const String _registerSecret = String.fromEnvironment('REGISTER_SECRET');
const String _logSecret = String.fromEnvironment('LOG_SECRET');
const String _overlayIcon = 'ic_launcher';
const String _overlayTitle = 'Water Reminder';
const String _appPackage = 'com.example.waterreminder';
const int _matchParent = -1;
const String _backgroundActivityDoneKey = 'backgroundActivityDone';
const String _legacyBatteryPermissionDoneKey = 'batteryPermissionDone';

// ─── Local notifications ────────────────────────────────────────────────
final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

Future<void> _initLocalNotifications() async {
  await _localNotifications.initialize(
    const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    onDidReceiveNotificationResponse: (_) async {
      if (!await OverlayPopUp.isActive()) await _showReminderOverlay();
    },
  );
  await _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(const AndroidNotificationChannel(
        'water_reminder',
        'Water Reminder',
        description: 'Water drinking reminders',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
        showBadge: true,
      ));
}

Future<void> _requestNotificationPermissions() async {
  await FirebaseMessaging.instance.requestPermission();
  await Permission.notification.request();
  if (!Platform.isAndroid) return;
  final impl = _localNotifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  try {
    await (impl as dynamic).requestFullScreenIntentPermission();
  } catch (_) {}
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

// ─── Hydration storage ───────────────────────────────────────────────────
const String _hydrationLevelKey = 'hydrationLevel';
const String _hydrationUpdatedAtKey = 'hydrationUpdatedAt';
const double _drinkBoost = 0.22;
const double _dismissDrop = 0.08;

double _clamp01(double v) => v.clamp(0.0, 1.0);

Future<double> _readHydration() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final saved = prefs.getDouble(_hydrationLevelKey);
  if (saved != null) return _clamp01(saved);
  final now = DateTime.now().millisecondsSinceEpoch;
  await prefs.setDouble(_hydrationLevelKey, 1.0);
  await prefs.setInt(_hydrationUpdatedAtKey, now);
  await prefs.setInt('lastDrinkTime', now);
  return 1.0;
}

Future<double> _changeHydration(double delta, {bool markDrink = false}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final current = _clamp01(prefs.getDouble(_hydrationLevelKey) ?? 1.0);
  final updated = _clamp01(current + delta);
  final now = DateTime.now().millisecondsSinceEpoch;
  await prefs.setDouble(_hydrationLevelKey, updated);
  await prefs.setInt(_hydrationUpdatedAtKey, now);
  if (markDrink) await prefs.setInt('lastDrinkTime', now);
  return updated;
}

Future<double> _drink() => _changeHydration(_drinkBoost, markDrink: true);
Future<double> _dismiss() => _changeHydration(-_dismissDrop);

bool _isQuietHours() {
  final hour = DateTime.now().hour;
  return hour >= 22 || hour < 6;
}

// ─── Remote logging ────────────────────────────────────────────────────
Future<void> _remoteLog(String event, {String? deviceId, Map<String, dynamic>? meta}) async {
  try {
    await http.post(
      Uri.parse('$_backendUrl/api/log'),
      headers: {'Content-Type': 'application/json', 'x-log-secret': _logSecret},
      body: jsonEncode({'event': event, 'deviceId': deviceId, 'meta': meta ?? {}}),
    ).timeout(const Duration(seconds: 6));
  } catch (_) {}
}

// ─── FCM background handler ─────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (message.data['type'] != 'water_reminder') return;

  String? deviceId;
  try { deviceId = await FirebaseInstallations.instance.getId(); } catch (_) {}

  final quietHours = _isQuietHours();
  await _remoteLog('bg_handler_fired', deviceId: deviceId, meta: {
    'quietHours': quietHours,
    'messageId': message.messageId,
    'ts': DateTime.now().toIso8601String(),
  });

  if (quietHours) return;

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(const AndroidNotificationChannel(
        'water_reminder',
        'Water Reminder',
        description: 'Water drinking reminders',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
        showBadge: true,
      ));

  try {
    await plugin.show(
      0,
      message.data['title'] ?? '💧 Drink Water!',
      message.data['body'] ?? 'Your body needs hydration.',
      const NotificationDetails(
          android: AndroidNotificationDetails(
        'water_reminder',
        'Water Reminder',
        channelDescription: 'Water drinking reminders',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
        enableVibration: true,
        playSound: true,
      )),
    );
    await _remoteLog('notification_shown', deviceId: deviceId, meta: {'ts': DateTime.now().toIso8601String()});
  } catch (e) {
    await _remoteLog('notification_failed', deviceId: deviceId, meta: {'error': e.toString(), 'ts': DateTime.now().toIso8601String()});
  }

  try {
    final hasPermission = await OverlayPopUp.checkPermission();
    final isActive = hasPermission ? await OverlayPopUp.isActive() : false;
    if (hasPermission && !isActive) {
      await _showReminderOverlay();
      await _remoteLog('overlay_shown', deviceId: deviceId, meta: {'ts': DateTime.now().toIso8601String()});
    } else {
      await _remoteLog('overlay_skipped', deviceId: deviceId, meta: {
        'hasPermission': hasPermission,
        'isActive': isActive,
        'ts': DateTime.now().toIso8601String(),
      });
    }
  } catch (e) {
    await _remoteLog('overlay_failed', deviceId: deviceId, meta: {'error': e.toString(), 'ts': DateTime.now().toIso8601String()});
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  VISUAL LAYER — everything below until "main()" is the redesigned UI
// ═══════════════════════════════════════════════════════════════════════════

// ─── Theme: smooth continuous interpolation ──────────────────────────────

class HydrationTheme {
  final double h;
  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color border;

  const HydrationTheme._({
    required this.h,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.border,
  });

  static Color _lerp3(Color a, Color b, Color c, double t) {
    if (t < 0.5) return Color.lerp(a, b, t * 2.0)!;
    return Color.lerp(b, c, (t - 0.5) * 2.0)!;
  }

  factory HydrationTheme.of(double hydration) {
    final t = hydration.clamp(0.0, 1.0);

    return HydrationTheme._(
      h: t,
      bg: _lerp3(
        const Color(0xFF110808),
        const Color(0xFF111008),
        const Color(0xFF081109),
        t,
      ),
      surface: _lerp3(
        const Color(0xFF1E1212),
        const Color(0xFF1E1A12),
        const Color(0xFF121E16),
        t,
      ),
      surfaceAlt: _lerp3(
        const Color(0xFF281818),
        const Color(0xFF282218),
        const Color(0xFF182820),
        t,
      ),
      textPrimary: _lerp3(
        const Color(0xFFF5E0E0),
        const Color(0xFFF5EFE0),
        const Color(0xFFE0F5E8),
        t,
      ),
      textSecondary: _lerp3(
        const Color(0xFFBB8888),
        const Color(0xFFBBA888),
        const Color(0xFF88BB98),
        t,
      ),
      textMuted: _lerp3(
        const Color(0xFF886666),
        const Color(0xFF887E66),
        const Color(0xFF668878),
        t,
      ),
      accent: _lerp3(
        const Color(0xFFE85454),
        const Color(0xFFD4A846),
        const Color(0xFF42CC88),
        t,
      ),
      border: _lerp3(
        const Color(0xFF382020),
        const Color(0xFF383020),
        const Color(0xFF203828),
        t,
      ),
    );
  }

  Color get surfaceBorder => Color.lerp(border, accent, 0.25)!;
  Color get chipSelected => Color.lerp(surface, accent, 0.18)!;
  Color get chipBorderSelected => accent.withValues(alpha: 0.45);
}

// ─── Flower state: personality ───────────────────────────────────────────

class FlowerState {
  final String name;
  final String message;
  const FlowerState._(this.name, this.message);

  static FlowerState of(double h) {
    if (h >= 0.85) return const FlowerState._('Thriving!', "Living my best life ✨");
    if (h >= 0.70) return const FlowerState._('Happy', 'Feeling fresh and fabulous~');
    if (h >= 0.55) return const FlowerState._('Content', 'Doing okay! A sip soon?');
    if (h >= 0.40) return const FlowerState._('Thirsty', 'Could use some water 👀');
    if (h >= 0.25) return const FlowerState._('Wilting', "Not doing so great...");
    if (h >= 0.12) return const FlowerState._('Dying', 'I need water badly! 😰');
    return const FlowerState._('SOS', "I'M LITERALLY DYING 💀");
  }
}

// ─── Flower painter ──────────────────────────────────────────────────────

class FlowerPainter extends CustomPainter {
  final double hydration;
  final double sway;
  FlowerPainter({required this.hydration, required this.sway});

  // Quadratic bezier helpers
  static Offset _qBez(Offset p0, Offset p1, Offset p2, double t) {
    final u = 1 - t;
    return Offset(
      u * u * p0.dx + 2 * u * t * p1.dx + t * t * p2.dx,
      u * u * p0.dy + 2 * u * t * p1.dy + t * t * p2.dy,
    );
  }

  static Offset _qBezTan(Offset p0, Offset p1, Offset p2, double t) {
    final u = 1 - t;
    return Offset(
      2 * u * (p1.dx - p0.dx) + 2 * t * (p2.dx - p1.dx),
      2 * u * (p1.dy - p0.dy) + 2 * t * (p2.dy - p1.dy),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final h = hydration.clamp(0.0, 1.0);
    final w = size.width;
    final ht = size.height;
    final cx = w / 2;

    // ── Layout proportions ──
    final potW = w * 0.34;
    final potH = ht * 0.11;
    final potRimH = ht * 0.024;
    final potTopY = ht * 0.83;
    final potBotY = potTopY + potH;

    // Stem endpoints
    final stemBaseX = cx;
    final stemBaseY = potTopY - 2;
    final stemTopBaseY = ht * 0.30;

    // Droop increases as hydration drops
    final droopX = (1.0 - h) * w * 0.18;
    final droopY = (1.0 - h) * ht * 0.10;
    final stemTopX = cx + droopX;
    final stemTopY = stemTopBaseY + droopY;

    // Control point for the stem curve
    final stemCtrlX = cx + droopX * 0.55;
    final stemCtrlY = (stemBaseY + stemTopY) / 2 + droopY * 0.2;

    final stemP0 = Offset(stemBaseX, stemBaseY);
    final stemP1 = Offset(stemCtrlX, stemCtrlY);
    final stemP2 = Offset(stemTopX, stemTopY);

    // ── Colors ──
    final potColor =
        Color.lerp(const Color(0xFF6A4535), const Color(0xFFB5694E), h)!;
    final potRimColor =
        Color.lerp(const Color(0xFF503028), const Color(0xFF8B5040), h)!;
    final soilColor =
        Color.lerp(const Color(0xFF3E2E20), const Color(0xFF2E2018), h)!;
    final stemColor =
        Color.lerp(const Color(0xFF6B5B3A), const Color(0xFF3D8B50), h)!;
    final leafColor =
        Color.lerp(const Color(0xFF7A6B3A), const Color(0xFF4CAF50), h)!;
    final petalColor =
        Color.lerp(const Color(0xFF8B6B5A), const Color(0xFFFF6B9D), h)!;
    final petalInner =
        Color.lerp(const Color(0xFF9B7B6A), const Color(0xFFFF8DB5), h)!;
    final centerColor =
        Color.lerp(const Color(0xFF6B4A2A), const Color(0xFFFFD54F), h)!;

    // ── Apply sway rotation around stem base ──
    canvas.save();
    final swayAngle = sway * (0.012 + h * 0.025);
    canvas.translate(cx, stemBaseY);
    canvas.rotate(swayAngle);
    canvas.translate(-cx, -stemBaseY);

    // ── Draw pot ──
    // Body (tapered trapezoid)
    final potPath = Path()
      ..moveTo(cx - potW / 2, potTopY + potRimH)
      ..lineTo(cx - potW * 0.37, potBotY)
      ..quadraticBezierTo(cx, potBotY + 4, cx + potW * 0.37, potBotY)
      ..lineTo(cx + potW / 2, potTopY + potRimH)
      ..close();
    canvas.drawPath(potPath, Paint()..color = potColor);

    // Pot rim
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            cx - potW / 2 - 3, potTopY, potW + 6, potRimH + 2),
        Radius.circular(potRimH / 2),
      ),
      Paint()..color = potRimColor,
    );

    // Soil fill
    canvas.drawRect(
      Rect.fromLTWH(cx - potW / 2 + 4, potTopY + potRimH - 1, potW - 8, 5),
      Paint()..color = soilColor,
    );

    // Decorative stripe on pot
    final stripeY = (potTopY + potRimH + potBotY) / 2;
    canvas.drawLine(
      Offset(cx - potW * 0.26, stripeY),
      Offset(cx + potW * 0.26, stripeY),
      Paint()
        ..color = potRimColor.withValues(alpha: 0.5)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );

    // ── Draw stem ──
    final stemPath = Path()
      ..moveTo(stemP0.dx, stemP0.dy)
      ..quadraticBezierTo(stemP1.dx, stemP1.dy, stemP2.dx, stemP2.dy);
    canvas.drawPath(
        stemPath,
        Paint()
          ..color = stemColor
          ..strokeWidth = w * 0.02
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);

    // ── Draw leaves ──
    _drawLeaf(canvas, stemP0, stemP1, stemP2, 0.45, leafColor,
        w * 0.10, true, h);
    _drawLeaf(canvas, stemP0, stemP1, stemP2, 0.60, leafColor,
        w * 0.085, false, h);

    // ── Draw petals ──
    const petalCount = 6;
    final petalLen = w * 0.115 * (0.50 + h * 0.50);
    final petalWid = w * 0.058 * (0.35 + h * 0.65);

    for (int i = 0; i < petalCount; i++) {
      final baseAngle = (i * 2 * math.pi / petalCount) - math.pi / 2;
      final droopFactor = (1.0 - h) * 0.70;
      // Each petal droops toward pointing downward
      final angle = baseAngle + (math.pi / 2 - baseAngle) * droopFactor;

      _drawPetal(
        canvas,
        Offset(stemTopX, stemTopY),
        angle,
        petalLen,
        petalWid,
        petalColor,
        petalInner,
      );
    }

    // ── Draw center ──
    final centerR = w * 0.038 * (0.65 + h * 0.35);
    canvas.drawCircle(
        Offset(stemTopX, stemTopY), centerR, Paint()..color = centerColor);
    // Highlight
    canvas.drawCircle(
      Offset(stemTopX - centerR * 0.25, stemTopY - centerR * 0.25),
      centerR * 0.35,
      Paint()..color = Colors.white.withValues(alpha: 0.10 + h * 0.15),
    );

    canvas.restore();
  }

  void _drawPetal(Canvas canvas, Offset center, double angle, double length,
      double width, Color color, Color innerColor) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final path = Path()
      ..moveTo(0, 0)
      ..cubicTo(
        width, -length * 0.25,
        width * 0.55, -length * 0.85,
        0, -length,
      )
      ..cubicTo(
        -width * 0.55, -length * 0.85,
        -width, -length * 0.25,
        0, 0,
      );

    canvas.drawPath(path, Paint()..color = color);

    // Inner lighter layer for depth
    canvas.save();
    canvas.scale(0.60, 0.60);
    canvas.drawPath(path, Paint()..color = innerColor.withValues(alpha: 0.35));
    canvas.restore();

    canvas.restore();
  }

  void _drawLeaf(
      Canvas canvas,
      Offset p0,
      Offset p1,
      Offset p2,
      double t,
      Color color,
      double leafSize,
      bool leftSide,
      double hydration) {
    final pos = _qBez(p0, p1, p2, t);
    final tan = _qBezTan(p0, p1, p2, t);
    final stemAngle = math.atan2(tan.dy, tan.dx);

    final leafBaseAngle =
        leftSide ? stemAngle - math.pi / 2 : stemAngle + math.pi / 2;
    final droopAmt = (1.0 - hydration) * math.pi * 0.35;
    final leafAngle =
        leftSide ? leafBaseAngle - droopAmt : leafBaseAngle + droopAmt;
    final curLeafSize = leafSize * (0.6 + hydration * 0.4);

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(leafAngle);

    final leafPath = Path()
      ..moveTo(0, 0)
      ..cubicTo(
        curLeafSize * 0.45, -curLeafSize * 0.15,
        curLeafSize * 0.30, -curLeafSize * 0.55,
        0, -curLeafSize,
      )
      ..cubicTo(
        -curLeafSize * 0.30, -curLeafSize * 0.55,
        -curLeafSize * 0.45, -curLeafSize * 0.15,
        0, 0,
      );

    canvas.drawPath(leafPath, Paint()..color = color);

    // Vein
    canvas.drawLine(
      Offset.zero,
      Offset(0, -curLeafSize * 0.65),
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..strokeWidth = 0.8,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(FlowerPainter old) =>
      old.hydration != hydration || old.sway != sway;
}

// ─── Animated flower widget ──────────────────────────────────────────────

class AnimatedFlower extends StatefulWidget {
  final double hydration;
  final double width;
  const AnimatedFlower({super.key, required this.hydration, this.width = 260});

  @override
  State<AnimatedFlower> createState() => _AnimatedFlowerState();
}

class _AnimatedFlowerState extends State<AnimatedFlower>
    with SingleTickerProviderStateMixin {
  late AnimationController _swayCtrl;

  @override
  void initState() {
    super.initState();
    _swayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();
  }

  @override
  void dispose() {
    _swayCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.width * 1.25;

    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.hydration),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeInOutCubic,
      builder: (_, h, __) {
        return AnimatedBuilder(
          animation: _swayCtrl,
          builder: (_, __) {
            return CustomPaint(
              size: Size(widget.width, height),
              painter: FlowerPainter(
                hydration: h,
                sway: math.sin(_swayCtrl.value * 2 * math.pi),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Background ──────────────────────────────────────────────────────────

class _Bg extends StatelessWidget {
  final HydrationTheme theme;
  const _Bg({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutCubic,
            color: theme.bg,
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.35),
                radius: 1.0,
                colors: [
                  theme.accent.withValues(alpha: 0.07),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Overlay entry point ─────────────────────────────────────────────────
@pragma('vm:entry-point')
void overlayPopUp() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OverlayScreen(),
  ));
}

// ─── Overlay screen ───────────────────────────────────────────────────────

class OverlayScreen extends StatefulWidget {
  const OverlayScreen({super.key});
  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen> {
  double _hydration = 1.0;

  @override
  void initState() {
    super.initState();
    OverlayPopUp.initializeOverlayHandler();
    unawaited(_load());
  }

  Future<void> _load() async {
    // Clear the heads-up notification once the overlay is visible
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.cancel(0);
    
    final h = await _readHydration();
    if (!mounted) return;
    setState(() => _hydration = h);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final theme = HydrationTheme.of(_hydration);
    final state = FlowerState.of(_hydration);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        _Bg(theme: theme),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, bottom + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Center(
                    child:
                        AnimatedFlower(hydration: _hydration, width: 200)),
                const SizedBox(height: 20),
                Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: _hydration),
                    duration: const Duration(milliseconds: 1100),
                    curve: Curves.easeOutCubic,
                    builder: (_, animH, __) {
                      final p = (animH * 100).round();
                      return Text(
                        '$p%',
                        style: TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.w900,
                          color: theme.accent,
                          letterSpacing: -3,
                          height: 1.0,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
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
                ),
                const Spacer(),
                SizedBox(
                  height: 58,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final h = await _drink();
                      if (mounted) setState(() => _hydration = h);
                      await OverlayPopUp.closeOverlay();
                    },
                    icon: const Icon(Icons.water_drop_rounded, size: 20),
                    label: const Text('Water me!'),
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
                    final h = await _dismiss();
                    if (mounted) setState(() => _hydration = h);
                    await OverlayPopUp.closeOverlay();
                  },
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text('Not now',
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

// ─── MIUI helpers ────────────────────────────────────────────────────────
bool _isXiaomiBrand(String brand) {
  final b = brand.toLowerCase();
  return b.contains('xiaomi') || b.contains('redmi') || b.contains('poco');
}

Future<void> _openMiuiPermissionEditor() async {
  try {
    await AndroidIntent(
      action: 'miui.intent.action.APP_PERM_EDITOR',
      package: 'com.miui.securitycenter',
      componentName:
          'com.miui.permcenter.permissions.PermissionsEditorActivity',
      arguments: {'extra_pkgname': _appPackage},
    ).launch();
  } catch (_) {
    try {
      await AndroidIntent(
        action: 'miui.intent.action.APP_PERM_EDITOR',
        package: 'com.miui.securitycenter',
        componentName:
            'com.miui.permcenter.permissions.AppPermissionsEditorActivity',
        arguments: {'extra_pkgname': _appPackage},
      ).launch();
    } catch (_) {
      rethrow;
    }
  }
}

// ─── Main ─────────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
            alert: false, badge: false, sound: false);
    await _initLocalNotifications();
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    ));
  } catch (e) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Init error: $e')),
      ),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  HOME PAGE
// ═══════════════════════════════════════════════════════════════════════════

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const List<int> _intervals = [10, 30, 45, 60, 90, 120, 180, 240];

  int _intervalMinutes = 60;
  bool _registered = false;
  bool _busy = false;
  bool _overlayPermissionDone = false;
  bool _batteryLimitDone = false;
  bool _backgroundActivityDone = false;
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
      if (m.data['type'] == 'water_reminder' &&
          !_isQuietHours() &&
          !await OverlayPopUp.isActive()) {
        await _showReminderOverlay();
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((m) async {
      if (m.data['type'] == 'water_reminder' &&
          !_isQuietHours() &&
          !await OverlayPopUp.isActive()) {
        await _showReminderOverlay();
      }
    });
    FirebaseMessaging.instance.getInitialMessage().then((m) async {
      if (m?.data['type'] == 'water_reminder' &&
          !_isQuietHours() &&
          !await OverlayPopUp.isActive()) {
        await _showReminderOverlay();
      }
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

  Future<void> _pullHydration() async {
    final h = await _readHydration();
    if (!mounted) return;
    setState(() => _hydration = h);
  }

  Future<void> _markDrink() async {
    final h = await _drink();
    if (!mounted) return;
    setState(() => _hydration = h);
    const msgs = [
      'Ahhh, refreshing! 💧',
      'Your flower loves you! 🌸',
      'Hydration = happiness ✨',
    ];
    _snack(msgs[DateTime.now().second % msgs.length]);
  }

  Future<void> _init() async {
    await _requestNotificationPermissions();
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (mounted) setState(() => _brand = info.manufacturer);
    }
    final launch = await _localNotifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        !await OverlayPopUp.isActive()) await _showReminderOverlay();

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('intervalMinutes');
    final wasReg = prefs.getBool('registered') ?? false;
    final overlayDone = await OverlayPopUp.checkPermission();
    final batteryLimitDone = await _isBatteryLimitDone();
    final backgroundActivityDone = prefs.getBool(_backgroundActivityDoneKey) ??
        prefs.getBool(_legacyBatteryPermissionDoneKey) ??
        false;
    final savedH = await _readHydration();

    if (mounted)
      setState(() {
        if (saved != null && _intervals.contains(saved))
          _intervalMinutes = saved;
        _registered = wasReg;
        _overlayPermissionDone = overlayDone;
        _batteryLimitDone = batteryLimitDone;
        _backgroundActivityDone = backgroundActivityDone;
        _hydration = savedH;
        _status = wasReg
            ? 'Watering every $_intervalMinutes min'
            : 'Tap Start to bloom';
      });
  }

  Future<void> _register() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Registering...';
    });
    try {
      final deviceId = await FirebaseInstallations.instance.getId();
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        setState(() => _status = 'Failed to get FCM token.');
        return;
      }

      final res = await http.post(
        Uri.parse('$_backendUrl/api/register'),
        headers: {
          'Content-Type': 'application/json',
          'x-register-secret': _registerSecret
        },
        body: jsonEncode({
          'deviceId': deviceId,
          'fcmToken': token,
          'intervalMinutes': _intervalMinutes,
          'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
        }),
      );
      if (res.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('intervalMinutes', _intervalMinutes);
        await prefs.setBool('registered', true);
        if (mounted)
          setState(() {
            _registered = true;
            _status = 'Watering every $_intervalMinutes min';
          });
      } else {
        if (mounted) setState(() => _status = 'Server error: ${res.body}');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final overlayDone = await OverlayPopUp.checkPermission();
    final batteryLimitDone = await _isBatteryLimitDone();
    final backgroundActivityDone = prefs.getBool(_backgroundActivityDoneKey) ??
        prefs.getBool(_legacyBatteryPermissionDoneKey) ??
        false;
    if (!mounted) return;
    setState(() {
      _overlayPermissionDone = overlayDone;
      _batteryLimitDone = batteryLimitDone;
      _backgroundActivityDone = backgroundActivityDone;
    });
  }

  Future<bool> _isBatteryLimitDone() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleOverlayPermission() async {
    if (!await OverlayPopUp.checkPermission())
      await OverlayPopUp.requestPermission();
    await _refreshPermissions();
    if (_overlayPermissionDone) _snack('Display overlay enabled ✓');
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
      if (_isXiaomiBrand(_brand)) {
        await _openMiuiPermissionEditor();
      } else {
        await AndroidIntent(
          action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
          data: 'package:$_appPackage',
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
      await prefs.setBool(_backgroundActivityDoneKey, true);
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
    final state = FlowerState.of(_hydration);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        _Bg(theme: theme),
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
                Center(
                    child:
                        AnimatedFlower(hydration: _hydration, width: 260)),
                const SizedBox(height: 20),

                // Percentage
                Center(child: _percentDisplay(theme)),
                const SizedBox(height: 4),

                // Status message
                Center(child: _statusDisplay(theme, state)),
                const SizedBox(height: 28),

                // Water button
                _waterButton(theme),
                const SizedBox(height: 32),

                // Interval section
                _sectionLabel('Remind me every', theme),
                const SizedBox(height: 12),
                _intervalChips(theme),
                const SizedBox(height: 12),
                _startButton(theme),
                const SizedBox(height: 12),
                _quietHoursIndicator(theme),
                const SizedBox(height: 48),

                // Setup section
                _sectionLabel('Setup', theme),
                const SizedBox(height: 12),
                _permTile(
                  label: 'Display overlay',
                  sub: 'Show reminders over other apps',
                  done: _overlayPermissionDone,
                  onTap: _handleOverlayPermission,
                  theme: theme,
                ),
                const SizedBox(height: 8),
                _permTile(
                  label: 'Background activity',
                  sub: 'Allow autostart and background running',
                  done: _backgroundActivityDone,
                  onTap: _handleBackgroundActivityPermission,
                  theme: theme,
                ),
                const SizedBox(height: 8),
                _permTile(
                  label: 'Battery limit',
                  sub: 'Set battery use to unrestricted',
                  done: _batteryLimitDone,
                  onTap: _handleBatteryLimitPermission,
                  theme: theme,
                ),
                if (_overlayPermissionDone &&
                    _backgroundActivityDone &&
                    _batteryLimitDone)
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Center(
                        child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle, color: theme.accent)),
                        const SizedBox(width: 8),
                        Text('All systems active',
                            style: TextStyle(
                              color: theme.accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            )),
                      ],
                    )),
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
                  child: const Text('Oasis'),
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
                child: Text(_registered ? 'Blooming' : 'Dormant'),
              ),
            ]),
          ),
        ],
      );

  Widget _percentDisplay(HydrationTheme t) =>
      TweenAnimationBuilder<double>(
        tween: Tween(end: _hydration),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (_, h, __) {
          final p = (h * 100).round();
          return Text(
            '$p%',
            style: TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w900,
              color: t.accent,
              letterSpacing: -4,
              height: 1.0,
            ),
          );
        },
      );

  Widget _statusDisplay(HydrationTheme t, FlowerState state) =>
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
            color: t.textSecondary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      );

  Widget _waterButton(HydrationTheme t) => SizedBox(
        height: 58,
        child: ElevatedButton.icon(
          onPressed: _markDrink,
          icon: const Icon(Icons.water_drop_rounded, size: 20),
          label: const Text('Water me!'),
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

  Widget _intervalChips(HydrationTheme t) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _intervals.map((min) {
          final sel = _intervalMinutes == min;
          final label = min < 60
              ? '${min}m'
              : '${min ~/ 60}h${min % 60 != 0 ? ' ${min % 60}m' : ''}';
          return GestureDetector(
            onTap: () => setState(() => _intervalMinutes = min),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: sel ? t.chipSelected : t.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: sel ? t.chipBorderSelected : t.border, width: 1),
              ),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 400),
                style: TextStyle(
                  color: sel ? t.accent : t.textSecondary,
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

  Widget _quietHoursIndicator(HydrationTheme t) {
    final quiet = _isQuietHours();
    final message = quiet
        ? '🌙 Reminders paused until 6:00 AM'
        : '💧 Active from 6 AM – 10 PM';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.surface,
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

  Widget _permTile({
    required String label,
    required String sub,
    required bool done,
    required VoidCallback onTap,
    required HydrationTheme theme,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: done ? theme.accent.withValues(alpha: 0.28) : theme.border,
                width: 1),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? theme.chipSelected : theme.surfaceAlt,
              ),
              child: Center(
                  child: Icon(
                done ? Icons.check_rounded : Icons.lock_outline_rounded,
                color: done ? theme.accent : theme.textMuted,
                size: 18,
              )),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 500),
                  style: TextStyle(
                    color: done ? theme.textPrimary : theme.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: -0.2,
                  ),
                  child: Text(label),
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 500),
                  style: TextStyle(
                      color: theme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                  child: Text(sub),
                ),
              ],
            )),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios_rounded,
                color: theme.textMuted, size: 13),
          ]),
        ),
      );
}
