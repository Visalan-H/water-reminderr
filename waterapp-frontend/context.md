# Context Handoff (2026-04-22)

## User Goal
Get the Flutter water reminder app fully working; current logic was not working correctly.

## What I Found
- Project is a single-file app logic in `lib/main.dart`.
- `flutter`/`dart` analysis commands timed out in this environment, so debugging was done by code inspection + plugin docs + build artifacts.
- Foreground/overlay flow had reliability issues:
  - Reminder trigger depended on main-isolate callback (`sendDataToMain -> _onTaskData`) which can fail when app is backgrounded/killed.
  - Service start path set `_running = true` even if service request fails.
  - Interval updates while already running were not robust.
  - UI text had encoding artifacts.
- Android manifest likely has stale/legacy service/receiver entries. Specifically, app manifest uses:
  - `com.pravera.flutter_foreground_task.service.ForegroundTaskService` (likely mismatch for current docs)
  - an old overlay service declaration that duplicates plugin-merged declarations.

## Evidence Collected
- Local merged manifest path:
  - `build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml`
- Current merged manifest shows both manual and plugin-provided overlay services.
- Plugin docs checked:
  - flutter_foreground_task 8.17.0 readme indicates service name `com.pravera.flutter_foreground_task.service.ForegroundService` and warns not to change service name.
  - overlay_pop_up 1.0.6+6 notes service declaration is now auto-handled by plugin.

## Changes Already Made
### `lib/main.dart`
I replaced the file with a more reliable implementation:
- Added explicit background-triggered overlay logic in `WaterTaskHandler.onRepeatEvent` using `OverlayPopUp.showOverlay` directly.
- Added duplicate-overlay guard using `OverlayPopUp.isActive()`.
- Added robust start/update/stop flow:
  - checks overlay + notification permission
  - initializes foreground service consistently
  - uses `startService` vs `updateService` depending on running state
  - syncs `_running` from `FlutterForegroundTask.isRunningService`
  - surfaces service failures via snackbars
- Added slider `onChangeEnd` behavior to apply new interval while running.
- Cleaned UI text/strings to plain ASCII.

## Still Pending (Important)
1. Update `android/app/src/main/AndroidManifest.xml`:
   - Replace likely stale foreground service class with current plugin-required class.
   - Remove stale/duplicate manual overlay service declaration if not needed.
   - Remove legacy boot receiver entry if plugin already merges required receivers.
2. Rebuild + run on device/emulator to confirm:
   - foreground service starts
   - overlay appears at interval while app in background
   - stop works cleanly
3. Run `flutter analyze` once environment allows (commands were timing out).

## Resume Checklist
1. Open `android/app/src/main/AndroidManifest.xml`.
2. Align service/receiver declarations to current package docs + merged manifest behavior.
3. Run:
   - `flutter clean`
   - `flutter pub get`
   - `flutter run`
4. Verify test flow:
   - Grant overlay permission + notifications
   - Start reminder
   - Background app and wait interval
   - Confirm overlay appears repeatedly without duplicates
   - Stop reminder

## Notes
- No git repo was detected in current workspace, so no commit history/checkpoint exists.
