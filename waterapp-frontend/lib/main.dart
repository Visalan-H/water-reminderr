import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'core/notifications.dart';
import 'screens/home_page.dart';
import 'screens/overlay_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // initLocalNotifications() must run first — getNotificationAppLaunchDetails()
  // needs the plugin initialised to return anything useful.
  await initLocalNotifications();

  // If the app was launched by a notification (full-screen intent on the lock
  // screen, or the user tapping the notification shade), skip Firebase entirely
  // and show the overlay screen directly.
  // Two ways we can end up here for a reminder: the OS fired the full-screen
  // intent (lock screen / screen off), or the background isolate force-started
  // this activity itself because the screen was on. The latter sets a flag in
  // SharedPreferences since it bypasses the notification entirely.
  final launch = await localNotifications.getNotificationAppLaunchDetails();
  final pendingReminder = await consumePendingReminder();
  if (launch?.didNotificationLaunchApp == true || pendingReminder) {
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OverlayScreen(),
    ));
    // Render the overlay first, then re-arm the background handler off the
    // critical path. Without this, a user whose only launches are via
    // reminders would never re-register it — the handle is persisted natively,
    // but it is dropped whenever the app's data/registration is reset, and
    // this path used to return before ever registering.
    unawaited(() async {
      try {
        await Firebase.initializeApp();
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      } catch (_) {}
    }());
    return;
  }

  // Normal launch — full Firebase initialisation.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
            alert: false, badge: false, sound: false);
    runApp(MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: const HomePage(),
    ));
  } catch (e) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Init error: $e')),
      ),
    ));
  }
}
