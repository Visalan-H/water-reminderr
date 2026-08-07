package com.example.waterreminder

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

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
