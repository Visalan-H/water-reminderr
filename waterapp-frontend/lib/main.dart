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

const String _backendUrl = 'https://water-reminderr.vercel.app';
const String _registerSecret =
    '3d0b192504daa3643a1a7ebc85c21053420bb8f2fa09bbc5ddfc6cb709d832c597777c91dd4d3ed588232a75df77c3b4404c01b59b88a8f057fa10b9a73b0a13';
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

// ─── FCM background handler ─────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (message.data['type'] != 'water_reminder') return;
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
    if (await OverlayPopUp.checkPermission() &&
        !await OverlayPopUp.isActive()) {
      await _showReminderOverlay();
      return;
    }
  } catch (_) {}
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
      autoCancel: true,
    )),
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  HYDRATION THEME
//  Everything — bg, surface, text, borders, blobs — derived from hydration.
// ─────────────────────────────────────────────────────────────────────────
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
  final Color blobA;
  final Color blobB;

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
    required this.blobA,
    required this.blobB,
  });

  // ─── PALETTES ─────────────────────────────────────────

  static const _dry = _Palette(
    bg: Color(0xFF0F0202),
    surface: Color(0xFF1C0505),
    surfaceAlt: Color(0xFF2A0808),
    textPrimary: Color(0xFFFFE4E4),
    textSecondary: Color(0xFFCC6666),
    textMuted: Color(0xFFC86464),
    accent: Color(0xFFFF3B30),
    border: Color(0xFF381412),
    blobA: Color(0xFF41100F),
    blobB: Color(0xFF240A09),
  );

  static const _mid = _Palette(
    bg: Color(0xFFFFF6ED),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFFDE8D6),
    textPrimary: Color(0xFF4A2B12),
    textSecondary: Color(0xFF8C5F36),
    textMuted: Color(0xFFB5845C),
    accent: Color(0xFFFF8C00),
    border: Color(0xFFF5D6B8),
    blobA: Color(0xFFFDE1C8),
    blobB: Color(0xFFFCECDD),
  );

  static const _hydrated = _Palette(
    bg: Color(0xFFF0F6FF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE8F0FE),
    textPrimary: Color(0xFF0D1E3A),
    textSecondary: Color(0xFF4D6FA8),
    textMuted: Color(0xFF3B5C8A),
    accent: Color(0xFF2563EB),
    border: Color(0xFFD4E2F9),
    blobA: Color(0xFFCDE0FD),
    blobB: Color(0xFFE6EFFF),
  );

  // ─── FACTORY (HARD SWITCH — NO GREY EVER) ─────────────

  factory HydrationTheme.of(double hydration) {
    final t = hydration.clamp(0.0, 1.0);

    late _Palette p;

    if (t < 0.30) {
      p = _dry;
    } else if (t < 0.65) {
      p = _mid;
    } else {
      p = _hydrated;
    }

    return HydrationTheme._(
      h: t,
      bg: p.bg,
      surface: p.surface,
      surfaceAlt: p.surfaceAlt,
      textPrimary: p.textPrimary,
      textSecondary: p.textSecondary,
      textMuted: p.textMuted,
      accent: p.accent,
      border: p.border,
      blobA: p.blobA,
      blobB: p.blobB,
    );
  }

  // ─── DERIVED COLORS (unchanged) ───────────────────────

  Color get surfaceBorder => (h < 0.5)
      ? Color.lerp(const Color(0xFF501916), const Color(0xFFF0CBAB), h * 2.0)!
      : Color.lerp(
          const Color(0xFFF0CBAB),
          const Color(0xFFC3D6F7),
          (h - 0.5) * 2.0,
        )!;

  Color get chipSelected => (h < 0.5)
      ? Color.lerp(const Color(0xFF3B1210), const Color(0xFFFFF0E0), h * 2.0)!
      : Color.lerp(
          const Color(0xFFFFF0E0),
          const Color(0xFFE2EAF8),
          (h - 0.5) * 2.0,
        )!;

  Color get chipBorderSelected => (h < 0.5)
      ? Color.lerp(const Color(0xFF75241E), const Color(0xFFFFC080), h * 2.0)!
      : Color.lerp(
          const Color(0xFFFFC080),
          const Color(0xFFAABCED),
          (h - 0.5) * 2.0,
        )!;
}

// ─── INTERNAL PALETTE ───────────────────────────────────

class _Palette {
  final Color bg, surface, surfaceAlt;
  final Color textPrimary, textSecondary, textMuted;
  final Color accent, border, blobA, blobB;

  const _Palette({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.border,
    required this.blobA,
    required this.blobB,
  });
}

// ─── Flower states ───────────────────────────────────────────────────────
class FlowerState {
  final String emoji;
  final String name;
  final String message;
  const FlowerState(this.emoji, this.name, this.message);

  static FlowerState of(double h) {
    if (h >= 0.80)
      return const FlowerState(
          '🌸', 'Flourishing', 'In full bloom — you\'re doing great.');
    if (h >= 0.60)
      return const FlowerState(
          '🌺', 'Blooming', 'Looking beautiful, keep it up.');
    if (h >= 0.40)
      return const FlowerState('🌷', 'Growing', 'Needs a little more water.');
    if (h >= 0.20)
      return const FlowerState(
          '🌱', 'Struggling', 'Getting dry — drink water soon.');
    return const FlowerState(
        '🥀', 'Wilting', 'Urgent. Your flower is dying of thirst.');
  }
}

// ─── Arc painter ─────────────────────────────────────────────────────────
class _ArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;
  _ArcPainter(
      {required this.progress, required this.color, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 7;
    final rect = Rect.fromCircle(center: c, radius: r);

    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = trackColor
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke);

    if (progress < 0.01) return;

    final sweep = 2 * math.pi * progress;

    canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..color = color.withOpacity(0.22)
          ..strokeWidth = 14
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);

    canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..color = color
          ..strokeWidth = 3.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);

    final a = -math.pi / 2 + sweep;
    final dot = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
    canvas.drawCircle(dot, 6, Paint()..color = color);
    canvas.drawCircle(dot, 2.8, Paint()..color = Colors.white.withOpacity(0.9));
  }

  @override
  bool shouldRepaint(_ArcPainter o) =>
      o.progress != progress || o.color != color || o.trackColor != trackColor;
}

// ─── Flower emoji ─────────────────────────────────────────────────────────
class _FlowerEmoji extends StatelessWidget {
  final double hydration;
  final double size;
  const _FlowerEmoji({required this.hydration, required this.size});

  @override
  Widget build(BuildContext context) {
    final emoji = FlowerState.of(hydration).emoji;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 650),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.70, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
          child: child,
        ),
      ),
      child:
          Text(emoji, key: ValueKey(emoji), style: TextStyle(fontSize: size)),
    );
  }
}

// ─── Hydration hero ───────────────────────────────────────────────────────
class HydrationHero extends StatelessWidget {
  final double hydration;
  final HydrationTheme theme;
  const HydrationHero(
      {super.key, required this.hydration, required this.theme});

  @override
  Widget build(BuildContext context) {
    final percent = (hydration * 100).round();

    return TweenAnimationBuilder<double>(
      tween: Tween(end: hydration),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (_, animH, __) {
        final animTheme = HydrationTheme.of(animH);
        final glowOpacity = 0.08 + animH * 0.22;
        final glowBlur = 18.0 + animH * 54.0;
        final emojiSize = 58.0 + animH * 44.0;

        return Column(children: [
          SizedBox(
            width: 260,
            height: 260,
            child: Stack(alignment: Alignment.center, children: [
              CustomPaint(
                size: const Size(260, 260),
                painter: _ArcPainter(
                  progress: animH,
                  color: animTheme.accent,
                  trackColor: animTheme.surfaceAlt,
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                width: 212,
                height: 212,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: animTheme.surface,
                  border: Border.all(
                      color: animTheme.accent.withOpacity(0.18), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: animTheme.accent.withOpacity(glowOpacity),
                      blurRadius: glowBlur,
                    ),
                    BoxShadow(
                      color:
                          Colors.black.withOpacity(0.10 + (1 - animH) * 0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                    child: _FlowerEmoji(hydration: animH, size: emojiSize)),
              ),
            ]),
          ),
          const SizedBox(height: 30),
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: theme.accent),
            duration: const Duration(milliseconds: 800),
            builder: (_, c, __) => Text(
              '$percent%',
              style: TextStyle(
                fontSize: 76,
                fontWeight: FontWeight.w900,
                color: c ?? theme.accent,
                letterSpacing: -6,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: theme.accent.withOpacity(0.65)),
            duration: const Duration(milliseconds: 800),
            builder: (_, c, __) => Text(
              FlowerState.of(hydration).name.toUpperCase(),
              style: TextStyle(
                color: c ?? theme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 3.5,
              ),
            ),
          ),
        ]);
      },
    );
  }
}

// ─── Full-screen background ───────────────────────────────────────────────
class _Bg extends StatelessWidget {
  final HydrationTheme theme;
  const _Bg({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(children: [
        // Base color — animated by parent rebuild
        AnimatedContainer(
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          color: theme.bg,
        ),
        // Top-right bloom
        Positioned(
          top: -80,
          right: -80,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            width: 340,
            height: 340,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: theme.blobA,
                  blurRadius: 140,
                  spreadRadius: 60,
                )
              ],
            ),
          ),
        ),
        // Bottom-left bloom
        Positioned(
          bottom: 60,
          left: -110,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            width: 270,
            height: 270,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: theme.blobB,
                  blurRadius: 110,
                  spreadRadius: 40,
                )
              ],
            ),
          ),
        ),
      ]),
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
        // Full background — uses same _Bg widget, fully opaque
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
                    child: HydrationHero(hydration: _hydration, theme: theme)),
                const SizedBox(height: 24),

                // State card
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
                  decoration: BoxDecoration(
                    color: theme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: theme.border, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: theme.accent.withOpacity(0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.accent.withOpacity(0.12),
                      ),
                      child: Center(
                        child: Text(state.emoji,
                            style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.0, 0.2),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                          child: Text(state.name,
                              key: ValueKey(state.name),
                              style: TextStyle(
                                color: theme.accent,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              )),
                        ),
                        const SizedBox(height: 2),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.0, 0.2),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                          child: Text(state.message,
                              key: ValueKey(state.message),
                              style: TextStyle(
                                color: theme.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              )),
                        ),
                      ],
                    )),
                  ]),
                ),

                const Spacer(),

                // CTA
                SizedBox(
                  height: 60,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final h = await _drink();
                        if (mounted) setState(() => _hydration = h);
                        await OverlayPopUp.closeOverlay();
                      },
                      icon: const Icon(Icons.water_drop_rounded, size: 20),
                      label: const Text('I watered the flower!'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        textStyle: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
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
                        color: theme.textSecondary,
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
    runApp(const MaterialApp(home: HomePage()));
  } catch (e) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Init error: $e')),
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
      if (m.data['type'] == 'water_reminder' && !await OverlayPopUp.isActive())
        await _showReminderOverlay();
    });
    FirebaseMessaging.onMessageOpenedApp.listen((m) async {
      if (m.data['type'] == 'water_reminder' && !await OverlayPopUp.isActive())
        await _showReminderOverlay();
    });
    FirebaseMessaging.instance.getInitialMessage().then((m) async {
      if (m?.data['type'] == 'water_reminder' && !await OverlayPopUp.isActive())
        await _showReminderOverlay();
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
    _snack('Your flower thanks you 🌸');
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
          'intervalMinutes': _intervalMinutes
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
    // Single source of truth — everything reads from this
    final theme = HydrationTheme.of(_hydration);
    final state = FlowerState.of(_hydration);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        // Animated full-screen background
        _Bg(theme: theme),

        SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                sliver: SliverToBoxAdapter(child: _appBar(theme)),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(24, 36, 24, bottom + 48),
                sliver: SliverList(
                    delegate: SliverChildListDelegate([
                  // Hero
                  Center(
                      child:
                          HydrationHero(hydration: _hydration, theme: theme)),
                  const SizedBox(height: 20),

                  // State card
                  _stateCard(theme, state),
                  const SizedBox(height: 40),

                  // Drink CTA
                  _drinkButton(theme),
                  const SizedBox(height: 52),

                  // Interval
                  _sectionLabel('Remind me every', theme),
                  const SizedBox(height: 14),
                  _intervalChips(theme),
                  const SizedBox(height: 12),
                  _startButton(theme),
                  const SizedBox(height: 52),

                  // Setup
                  _sectionLabel('Setup', theme),
                  const SizedBox(height: 14),
                  _permTile(
                    label: 'Display overlay',
                    sub: 'Show reminders over other apps',
                    done: _overlayPermissionDone,
                    onTap: _handleOverlayPermission,
                    theme: theme,
                  ),
                  const SizedBox(height: 10),
                  _permTile(
                    label: 'Background activity',
                    sub: 'Allow autostart and background running',
                    done: _backgroundActivityDone,
                    onTap: _handleBackgroundActivityPermission,
                    theme: theme,
                  ),
                  const SizedBox(height: 10),
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
                      padding: const EdgeInsets.only(top: 20),
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
                ])),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  // ─── Sub-widgets — all accept HydrationTheme ────────────────────────────

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
                      color: t.textSecondary,
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

  Widget _stateCard(HydrationTheme t, FlowerState state) => AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: t.accent.withOpacity(0.10),
              blurRadius: 14,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 48,
            height: 48,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: t.chipSelected),
            child: Center(
                child: Text(state.emoji, style: const TextStyle(fontSize: 24))),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.0, 0.2),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(state.name,
                    key: ValueKey(state.name),
                    style: TextStyle(
                      color: t.accent,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    )),
              ),
              const SizedBox(height: 2),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.0, 0.2),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(state.message,
                    key: ValueKey(state.message),
                    style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          )),
        ]),
      );

  Widget _drinkButton(HydrationTheme t) => SizedBox(
        height: 60,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          child: ElevatedButton.icon(
            onPressed: _markDrink,
            icon: const Icon(Icons.water_drop_rounded, size: 20),
            label: const Text('I watered the flower!'),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: sel ? t.chipSelected : t.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: sel ? t.chipBorderSelected : t.border, width: 1),
                boxShadow: sel
                    ? []
                    : [
                        BoxShadow(
                          color:
                              Colors.black.withOpacity(0.04 + (1 - t.h) * 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        )
                      ],
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          child: OutlinedButton(
            onPressed: _busy ? null : _register,
            style: OutlinedButton.styleFrom(
              foregroundColor: t.accent,
              side: BorderSide(color: t.accent.withOpacity(0.30), width: 1),
              backgroundColor: t.accent.withOpacity(0.07),
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
        ),
      );

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
                color: done ? theme.accent.withOpacity(0.28) : theme.border,
                width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04 + (1 - theme.h) * 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
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
