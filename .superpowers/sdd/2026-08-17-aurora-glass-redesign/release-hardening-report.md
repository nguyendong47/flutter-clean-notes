# Aurora Release Hardening Report

## Result

- Branch: `fix/aurora-release-hardening`
- Exact base: `0d348d6185ed984eb20fc1963ebeb92a70369f63`
- Commit: this report's containing commit; its exact SHA is recorded in the final handoff.
- Scope stayed inside notification service/tests, Android notification declarations, macOS import entitlements, and this report. No notifier, provider/generated provider, router, domain, data, UI, dependency, package-ID, signing, or `.claude/skills` file was changed.

## Impact and Review

The supplied pre-edit GitNexus assessment classified the aggregate `NotificationService` as CRITICAL (17 direct dependents, six processes), while the approved target methods and constructor were LOW. A fresh worktree lookup against the current workspace index reported the class as HIGH (eight direct dependents, three processes) and each targeted method/constructor as LOW. Both assessments supported the same ruling: retain the approved narrow method-level change and exhaustively exercise notification, routing, notifier, and editor behavior.

Pre-commit `detect_changes(scope: all)` against the explicit linked worktree reported four changed symbols, zero affected execution flows, and LOW risk. The mapper counted six tracked code/config/test files; the ignored documentation report was force-staged separately.

The required two-axis review found no documented-standard violations and no spec mismatch in the notification, manifest, entitlement, or preservation behavior. Its medium judgement-call concern was the sentinel `Note` used for ID-only routing. That bridge is intentionally retained because the existing callback contract is `OnNotificationTap(Note, BuildContext)`, the spec requires reconstructing only the minimum routing value, and router/domain changes were prohibited. Generated `jni` registrant churn produced by dependency setup/build was inspected and restored; it is not in the final diff.

## TDD Record

### RED

- Cold initialization tests failed because all three Darwin request flags were `true` instead of `false`.
- Permission tests initially failed to compile because the injectable `requestPermission` seam and `NotificationPermissionDeniedException` did not exist.
- Privacy tests failed on the note title/body preview, legacy six-field payload, public visibility defaults, exact alarm mode, and `showsUserInterface: false`.
- Opaque payload Snooze failed because `note:v1:<id>` was not parsed; invalid legacy IDs `0` and `-1` incorrectly scheduled work.
- The pinned-plugin correction added a static manifest test that failed until `ActionBroadcastReceiver` was explicitly registered.

### GREEN

- Cold initialization now suppresses alert, badge, and sound prompts.
- Granted permission schedules once; denial throws the typed neutral exception before `zonedSchedule`; invalid input and unsupported platforms perform zero permission/schedule work as applicable.
- Initial and Snoozed reminders use a generic preview, private Android visibility, `inexactAllowWhileIdle`, foreground/UI Snooze actions, and the opaque `note:v1:<id>` payload.
- Opaque and legacy six-part payloads both Open/Snooze by a validated positive ID; stale legacy note content is not routed or rescheduled.
- The action receiver exists with `exported="false"`, while initialization still supplies no Dart background callback.

## Plugin 17.2.4 API Evidence

Dependency resolution selected `flutter_local_notifications 17.2.4`. The installed package source was inspected before implementation and confirmed these exact APIs and values:

- `DarwinInitializationSettings.requestAlertPermission`, `requestBadgePermission`, and `requestSoundPermission`;
- `AndroidFlutterLocalNotificationsPlugin.requestNotificationsPermission()`;
- `IOSFlutterLocalNotificationsPlugin.requestPermissions(...)` and `MacOSFlutterLocalNotificationsPlugin.requestPermissions(...)`;
- `AndroidNotificationAction.showsUserInterface`;
- `NotificationVisibility.private`;
- `AndroidScheduleMode.inexactAllowWhileIdle`.

The pinned README requires `ActionBroadcastReceiver` for notification actions. `showsUserInterface: true` selects the foreground/UI response path; it does not remove the receiver requirement. No `onDidReceiveBackgroundNotificationResponse` callback is registered.

## Android Manifest Evidence

`flutter build apk --debug` generated `build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml`. Inspection of that merged artifact confirmed:

- `POST_NOTIFICATIONS` and `RECEIVE_BOOT_COMPLETED` each present;
- `ActionBroadcastReceiver`, `ScheduledNotificationReceiver`, and `ScheduledNotificationBootReceiver` present with `android:exported="false"`;
- boot receiver filters for `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, Android `QUICKBOOT_POWERON`, and HTC `QUICKBOOT_POWERON`;
- zero `SCHEDULE_EXACT_ALARM` or `USE_EXACT_ALARM` matches.

The built APK was `build/app/outputs/flutter-apk/app-debug.apk` (165,132,796 bytes).

## Backup Policy Blocker

The optional `android:allowBackup="false"` change was not made. The merged debug manifest has no `allowBackup` attribute, so existing platform-default backup behavior remains. Disabling backup affects user recovery/migration and needs an owner-approved data policy plus restore/migration testing; that evidence was not available in this bounded correction.

## Verification

- Focused notification/routing/editor gate: 78/78 passed before the action-receiver correction; the corrected notification service file then passed 23/23.
- Notifier persistence/partial-save gate: 33/33 passed.
- `flutter analyze`: no issues.
- `flutter test --concurrency=1`: 328/328 passed in 3 minutes 22 seconds.
- `flutter build apk --debug`: passed in 238.8 seconds.
- Merged-manifest inspection: required permissions/receivers/filters present; exact-alarm permissions absent.
- Both macOS entitlement plists parse and contain `com.apple.security.files.user-selected.read-only` with a true value.
- `dart format --output=none --set-exit-if-changed` on changed Dart files: zero changes.
- `git diff --check`: passed before staging.
- Final protected/generated audit: no `.claude/skills`, registrant, generated provider/router, notifier, domain, data, UI, package-ID, signing, or dependency churn.

## Changed Files

- `android/app/src/main/AndroidManifest.xml`
- `lib/app/notification_service.dart`
- `macos/Runner/DebugProfile.entitlements`
- `macos/Runner/Release.entitlements`
- `test/app/notification_routing_test.dart`
- `test/notification_service_test.dart`
- `.superpowers/sdd/2026-08-17-aurora-glass-redesign/release-hardening-report.md`
