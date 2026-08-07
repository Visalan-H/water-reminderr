import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../screens/overlay_screen.dart';
import 'app_constants.dart';
import 'hydration_store.dart';
import 'remote_log.dart';

final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();

// Navigator key so notification taps (foreground) can push OverlayScreen
// onto whatever route is currently showing, without posting a new notification.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  notifChannelId,
  'Water Reminder',
  description: 'Water drinking reminders',
  importance: Importance.max,
  enableVibration: true,
  playSound: true,
  showBadge: true,
);

Future<void> initLocalNotifications() async {
  await localNotifications.initialize(
    const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    // Tapping the notification while it's in the shade (not full-screen)
    // also opens the reminder screen, just like the full-screen path.
    onDidReceiveNotificationResponse: (_) {
      // App is already running — push OverlayScreen on top of whatever is
      // showing rather than posting another notification.
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const OverlayScreen()),
      );
    },
  );
  await localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_channel);
}

Future<void> requestNotificationPermissions() async {
  await FirebaseMessaging.instance.requestPermission();
  await Permission.notification.request();
  if (!Platform.isAndroid) return;
  final impl = localNotifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  try {
    await (impl as dynamic).requestFullScreenIntentPermission();
  } catch (_) {}
}

/// Posts a local notification with fullScreenIntent: true.
/// On the lock screen or when the app is in the background, Android fires
/// the full-screen intent which launches MainActivity.  MainActivity.kt
/// sets showWhenLocked + turnScreenOn so the screen wakes and the overlay
/// is visible.
/// When the app is in the foreground, this appears as a heads-up notification;
/// tapping it triggers onDidReceiveNotificationResponse which navigates
/// directly to OverlayScreen via navigatorKey.
Future<void> showReminderOverlay({
  String title = 'Time to water your flower',
  String body = 'Tap to log a drink',
}) async {
  final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    notifChannelId,
    'Water Reminder',
    channelDescription: 'Water drinking reminders',
    importance: Importance.max,
    priority: Priority.max,
    fullScreenIntent: true,
    visibility: NotificationVisibility.public,
    enableVibration: true,
    playSound: true,
    autoCancel: true,
    additionalFlags: Int32List.fromList([0x00000080]), // FLAG_HIGH_PRIORITY
  );
  await localNotifications.show(
    0, title, body, NotificationDetails(android: androidDetails),
  );
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (message.data['type'] != 'water_reminder') return;

  String? deviceId;
  try {
    deviceId = await FirebaseInstallations.instance.getId();
  } catch (_) {}

  final quietHours = isQuietHours();
  unawaited(remoteLog('bg_handler_fired', deviceId: deviceId, meta: {
    'quietHours': quietHours,
    'messageId': message.messageId,
    'ts': DateTime.now().toIso8601String(),
  }));

  if (quietHours) return;

  // Full-screen intent notification — same mechanism as alarm clocks.
  // Does not require SYSTEM_ALERT_WINDOW, never gets stuck in "isActive",
  // and works reliably across every subsequent FCM.
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_channel);

  try {
    await plugin.show(
      0,
      message.data['title'] ?? 'Water your flower',
      message.data['body'] ?? 'Flowers need water and so do you',
      const NotificationDetails(
          android: AndroidNotificationDetails(
        notifChannelId,
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
    unawaited(remoteLog('notification_shown', deviceId: deviceId,
        meta: {'ts': DateTime.now().toIso8601String()}));
  } catch (e) {
    unawaited(remoteLog('notification_failed', deviceId: deviceId,
        meta: {'error': e.toString(), 'ts': DateTime.now().toIso8601String()}));
  }
}
