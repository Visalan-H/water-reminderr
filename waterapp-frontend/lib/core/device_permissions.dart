import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_constants.dart';
import 'notifications.dart';

bool isXiaomiBrand(String brand) {
  final b = brand.toLowerCase();
  return b.contains('xiaomi') || b.contains('redmi') || b.contains('poco');
}

Future<void> openMiuiPermissionEditor() async {
  try {
    await AndroidIntent(
      action: 'miui.intent.action.APP_PERM_EDITOR',
      package: 'com.miui.securitycenter',
      componentName:
          'com.miui.permcenter.permissions.PermissionsEditorActivity',
      arguments: {'extra_pkgname': appPackage},
    ).launch();
  } catch (_) {
    try {
      await AndroidIntent(
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
  // On earlier versions it's auto-granted.
  try {
    final impl = localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await (impl as dynamic).canUseFullScreenIntent() as bool?;
    return granted ?? true;
  } catch (_) {
    return true; // assume granted on older APIs
  }
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
