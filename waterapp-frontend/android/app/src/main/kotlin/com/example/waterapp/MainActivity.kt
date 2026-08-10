package com.example.waterreminder

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.example.waterreminder/fullscreen_intent"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // flutter_local_notifications 17.2.4 doesn't expose a check-only
        // Dart API for the Android 14+ USE_FULL_SCREEN_INTENT permission —
        // only a request method that opens Settings as a side effect. This
        // channel lets the Dart side query the current grant state without
        // triggering any UI, so the setup checklist can show an accurate
        // status instead of assuming "granted" whenever the plugin call fails.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canUseFullScreenIntent" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val nm =
                                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            result.success(nm.canUseFullScreenIntent())
                        } else {
                            result.success(true)
                        }
                    }
                    // "Display over other apps". We never draw an overlay with
                    // it — holding it is what exempts the app from background
                    // activity-start limits, which is the only supported way to
                    // put the reminder on screen while the phone is in use.
                    "canDrawOverlays" -> result.success(Settings.canDrawOverlays(this))
                    "requestOverlayPermission" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                        )
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Set window flags so this activity can appear over the lock screen
        // and wake the display when launched by a full-screen-intent notification.
        //
        // Official flutter_local_notifications recommendation:
        //   https://pub.dev/packages/flutter_local_notifications
        //   "add android:showWhenLocked and android:turnScreenOn to the activity"
        //
        // The manifest already declares these attributes, but several OEM Android
        // skins (notably MIUI, HyperOS, OxygenOS) ignore manifest-level window
        // attributes and only respect the programmatic Activity API calls below.
        // Setting them unconditionally — not just on notification launches — is
        // the safest approach: it covers the full-screen-intent path without
        // relying on any internal plugin constants.
        //
        // API 27+: Activity-level methods, must be called BEFORE super.onCreate()
        //          so Flutter's surface is created with the flags already set.
        // API < 27: Window flags, only available AFTER super.onCreate() attaches
        //           the window — set them immediately after.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }

        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }
}
