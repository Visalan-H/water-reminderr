# Water Reminder

Android app that tracks hydration and sends push notifications to drink water at custom intervals.

## Features

- **Full-screen overlay notifications** - Reminders appear over other apps
- **Hydration tracking** - Visual flower that responds to hydration level
- **Custom intervals** - Set reminder frequency (10m to 4h)
- **Firebase Cloud Messaging** - Backend-driven push notifications
- **Local storage** - Persistent hydration state via SharedPreferences
- **Minimal footprint** - ~25 MB optimized APK

## Flower States

- **Wilting** (0-20%) - Critical, needs water now
- **Struggling** (20-40%) - Drying out
- **Growing** (40-60%) - Moderate hydration
- **Blooming** (60-80%) - Healthy
- **Flourishing** (80-100%) - Thriving

## Setup

### Prerequisites
- Flutter 3.0+
- Android SDK 21+
- Firebase project with Messaging enabled

### Installation

```bash
cd waterapp-frontend
flutter pub get
```

### Configure Firebase

1. Replace `google-services.json` with your Firebase config
2. Update `_backendUrl` in `lib/main.dart` with your backend endpoint
3. Update `_registerSecret` for authentication

### Permissions Required

- Display overlay (to show reminders over other apps)
- Notification permissions
- Background activity (to allow OS to run reminders in background)


## Backend

The app registers with a backend endpoint on first run:

```
POST /api/register
{
  "deviceId": "...",
  "fcmToken": "...",
  "intervalMinutes": 60
}
```

The backend then sends FCM messages at the configured interval.

## Architecture

- **UI**: Animated hydration theme that shifts from dark red (dehydrated) to light blue (hydrated)
- **Storage**: SharedPreferences for local state
- **Notifications**: Firebase Messaging + FlutterLocalNotifications
- **Overlay**: AndroidIntentPlus for full-screen overlay display
