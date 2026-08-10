const String backendUrl = String.fromEnvironment('BACKEND_URL');
const String registerSecret = String.fromEnvironment('REGISTER_SECRET');
const String logSecret = String.fromEnvironment('LOG_SECRET');
const String appPackage = 'com.example.waterreminder';

// Set by the FCM background isolate just before it force-launches the reminder
// activity, and consumed by whichever UI isolate comes up. SharedPreferences is
// the only channel between those two isolates, so this is how the launched
// activity learns it should show the reminder rather than the home screen.
const String pendingReminderKey = 'pendingReminder';

const String backgroundActivityDoneKey = 'backgroundActivityDone';
const String legacyBatteryPermissionDoneKey = 'batteryPermissionDone';
const String miuiAlertDoneKey = 'miuiAlertDone';
const String setupIntroDismissedKey = 'setupIntroDismissed';

// Bumped whenever we need a fresh channel (e.g. to escape a stale MIUI
// "Floating" alert-mode that is cached per channel-ID and cannot be cleared
// programmatically).
const String notifChannelId = 'water_reminder_v2';
