# Firebase & Google Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Flutter's embedding references Play Core split-install classes for deferred
# components (dynamic feature modules). This app doesn't use deferred
# components and doesn't depend on Play Core, so those classes don't exist
# for R8 to resolve — silence rather than keep (keeping would pull in a
# dependency we don't have and defeat shrinking for no benefit).
-dontwarn com.google.android.play.core.**

# Android Intent Plus
-keep class com.android.intent.** { *; }

# Device Info Plus
-keep class com.android.device.** { *; }

# Permission Handler
-keep class com.baseflow.permissionhandler.** { *; }

# Shared Preferences
-keep class android.content.SharedPreferences { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep Parcelable implementations
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Reduce logging (optional - comment out if you need logs for debugging)
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
}

