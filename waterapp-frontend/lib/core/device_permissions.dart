import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_constants.dart';

const MethodChannel _fullScreenIntentChannel =
    MethodChannel('com.example.waterreminder/fullscreen_intent');

bool isXiaomiBrand(String brand) {
  final b = brand.toLowerCase();
  return b.contains('xiaomi') || b.contains('redmi') || b.contains('poco');
}

Future<void> openMiuiPermissionEditor() async {
  try {
    await const AndroidIntent(
      action: 'miui.intent.action.APP_PERM_EDITOR',
      package: 'com.miui.securitycenter',
      componentName:
          'com.miui.permcenter.permissions.PermissionsEditorActivity',
      arguments: {'extra_pkgname': appPackage},
    ).launch();
  } catch (_) {
    try {
      await const AndroidIntent(
        action: 'miui.intent.action.APP_PERM_EDITOR',
        package: 'com.miui.securitycenter',
        componentName:
            'com.miui.permcenter.permissions.AppPermissionsEditorActivity',
        arguments: {'extra_pkgname': appPackage},
      ).launch();
    } catch (_) {
      rethrow;
    }
  }
}

Future<bool> isFullScreenIntentGranted() async {
  if (!Platform.isAndroid) return true;
  // On Android 14+ (API 34), USE_FULL_SCREEN_INTENT requires explicit grant.
  // flutter_local_notifications 17.2.4 only exposes a request method (which
  // opens Settings as a side effect when not granted) — no check-only Dart
  // API — so a native MethodChannel (see MainActivity.kt) queries
  // NotificationManager.canUseFullScreenIntent() directly.
  try {
    final granted = await _fullScreenIntentChannel
        .invokeMethod<bool>('canUseFullScreenIntent');
    return granted ?? true;
  } catch (_) {
    return true; // assume granted on older APIs
  }
}

/// Whether "Display over other apps" is granted.
///
/// The app never draws an overlay with it. Holding it is what exempts the app
/// from Android's background-activity-start restrictions, and that exemption is
/// the only supported way to put the reminder on screen while the phone is
/// unlocked and in use — a full-screen intent alone is downgraded to a banner
/// in that situation.
Future<bool> isOverlayPermissionGranted() async {
  if (!Platform.isAndroid) return true;
  try {
    final granted =
        await _fullScreenIntentChannel.invokeMethod<bool>('canDrawOverlays');
    return granted ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> requestOverlayPermission() async {
  if (!Platform.isAndroid) return;
  try {
    await _fullScreenIntentChannel.invokeMethod('requestOverlayPermission');
  } catch (_) {}
}

Future<bool> isBatteryLimitDone() async {
  if (!Platform.isAndroid) return true;
  try {
    final status = await Permission.ignoreBatteryOptimizations.status;
    return status.isGranted;
  } catch (_) {
    return false;
  }
}
