import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:android_intent_plus/android_intent.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/overlay_screen.dart';
import 'app_constants.dart';
import 'hydration_store.dart';
import 'remote_log.dart';

final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();

/// The single ID every reminder notification is posted under.
///
/// Reusing one ID is deliberate (we only ever want one reminder pending), but
/// it makes [cancelReminderNotification] mandatory before each post — see the
/// comment in [showReminderOverlay].
const int reminderNotificationId = 0;

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
    // Alarm category is what the framework (and OEM skins) look at when
    // deciding whether a full-screen intent is "important enough" to honour.
    category: AndroidNotificationCategory.alarm,
    additionalFlags: Int32List.fromList([0x00000080]), // FLAG_HIGH_PRIORITY
  );
  // Cancel before showing. Posting to an ID that is still live in the shade
  // is an *update*, not a new notification, and Android does not re-fire a
  // full-screen intent for an update — so without this, only the very first
  // reminder ever goes full-screen and every later one silently degrades to
  // a shade entry.
  await localNotifications.cancel(reminderNotificationId);
  await localNotifications.show(
    reminderNotificationId,
    title,
    body,
    NotificationDetails(android: androidDetails),
  );
}

/// Marks that a reminder is waiting to be shown, so the UI isolate that comes
/// up next renders [OverlayScreen] instead of the home screen.
Future<void> setPendingReminder(bool pending) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(pendingReminderKey, pending);
}

Future<bool> consumePendingReminder() async {
  final prefs = await SharedPreferences.getInstance();
  final pending = prefs.getBool(pendingReminderKey) ?? false;
  if (pending) await prefs.setBool(pendingReminderKey, false);
  return pending;
}

/// Drags the reminder screen in front of whatever the user is doing.
///
/// A full-screen intent is not enough on its own: Android only honours it when
/// the device is locked or the screen is off. While the user is actively using
/// the phone the framework deliberately downgrades it to a heads-up banner, and
/// there is no notification flag that overrides that.
///
/// The one supported escape hatch is the background-activity-start exemption
/// granted to apps holding SYSTEM_ALERT_WINDOW ("Display over other apps") — so
/// we start the activity ourselves. android_intent_plus is a pub plugin, which
/// means it is registered in this background isolate too (firebase_messaging
/// builds its background engine with `new FlutterEngine(applicationContext)`,
/// which auto-registers plugins), and with no Activity attached it falls back
/// to `applicationContext.startActivity()` with FLAG_ACTIVITY_NEW_TASK.
///
/// Without the overlay permission this call is simply refused by the system and
/// we still have the notification as the fallback, so it is safe to always try.
Future<void> forceReminderToForeground() async {
  await setPendingReminder(true);
  await const AndroidIntent(
    action: 'android.intent.action.MAIN',
    package: appPackage,
    componentName: '$appPackage.MainActivity',
    flags: <int>[
      0x10000000, // FLAG_ACTIVITY_NEW_TASK — required from a non-Activity context
      0x04000000, // FLAG_ACTIVITY_CLEAR_TOP — reuse the task, don't stack copies
      0x00040000, // FLAG_ACTIVITY_NO_USER_ACTION — this isn't a user-initiated launch
    ],
  ).launch();
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
    // Same reason as in showReminderOverlay: re-posting over a live
    // notification is an update and won't re-fire the full-screen intent.
    // This path is the one that matters when the app has been swiped away,
    // and it previously also lacked autoCancel — so the first reminder's
    // notification stayed in the shade forever and permanently suppressed
    // full-screen delivery for every reminder after it.
    await plugin.cancel(reminderNotificationId);
    await plugin.show(
      reminderNotificationId,
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
        autoCancel: true,
        category: AndroidNotificationCategory.alarm,
      )),
    );
    unawaited(remoteLog('notification_shown', deviceId: deviceId,
        meta: {'ts': DateTime.now().toIso8601String()}));
  } catch (e) {
    unawaited(remoteLog('notification_failed', deviceId: deviceId,
        meta: {'error': e.toString(), 'ts': DateTime.now().toIso8601String()}));
  }

  // Then drag the reminder in front of the user. The notification above stays
  // as the fallback for when this is refused (no overlay permission, or an OEM
  // that blocks it anyway).
  try {
    await forceReminderToForeground();
    unawaited(remoteLog('force_foreground_ok', deviceId: deviceId,
        meta: {'ts': DateTime.now().toIso8601String()}));
  } catch (e) {
    unawaited(remoteLog('force_foreground_failed', deviceId: deviceId,
        meta: {'error': e.toString(), 'ts': DateTime.now().toIso8601String()}));
  }
}
