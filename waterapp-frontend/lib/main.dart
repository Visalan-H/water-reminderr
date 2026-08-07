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
  final launch = await localNotifications.getNotificationAppLaunchDetails();
  if (launch?.didNotificationLaunchApp == true) {
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OverlayScreen(),
    ));
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
