# Privacy and Data Flow

> **Non-legal technical draft.** This document describes the checked-in
> implementation for engineering and release review. It is not a privacy policy
> or legal advice. Product, legal, and release owners must resolve every item in
> [Owner decisions](#owner-decisions) before publishing a contractual statement.

## Current technical behavior

| Flow | Data | Boundary and trigger |
| --- | --- | --- |
| Note storage | ID, title, content, color, creation time, pin state, tags, status, and optional reminder time | Stored in the app's local `notes_database.db` SQLite database. Desktop uses the application-support directory and sqflite FFI; other targets use the sqflite database path. |
| Theme preference | System, light, or dark selection | Stored locally through platform shared preferences and resolved before the first app frame. A missing, invalid, or unreadable value falls back to the system setting. |
| Markdown preview | User-authored note body and embedded image/link URIs | Rendered locally with `flutter_markdown_plus 1.0.12`. Every image is replaced by an inert accessible placeholder, and only the internal `note://` scheme is handled. Preview content does not open or fetch network, file, data, or other external URIs. |
| Text export | Titles, content, and tags from Active and Archive notes only | Sent to the operating-system share sheet only after the user selects **Export text**. Trash is excluded. The destination selected in that sheet controls subsequent handling. |
| Markdown export | Titles, content, and tags from Active and Archive notes only | A generated `notes.md` file is sent to the operating-system share sheet only after the user selects **Export Markdown**. Trash is excluded. |
| JSON backup | IDs, titles, content, tags, color, creation time, pin state, status, and reminder time from Active, Archive, and Trash | A generated `notes_backup.json` file containing every status is sent to the operating-system share sheet only after the user selects **Backup JSON**. |
| JSON import | The fields accepted by the JSON backup format | The user selects one `.json` file through the platform file picker. The app rejects an empty selection and payloads over 10 MB, validates the JSON, then imports the notes in one SQLite transaction. Import is not a byte-for-byte restore: entries are appended as copies. Title, content, tags, color, creation time, and pin state are retained, while each copy receives a fresh ID, active status, and no reminder. |
| Android managed backup | App-private files, databases, preferences, and related storage domains | The main manifest disables Android managed backup, and Android 12+ data-extraction rules exclude every supported domain from both cloud backup and device-to-device transfer. Manual JSON export is the app-supported recovery path. OEM transfer behavior still requires physical-device evidence. |
| Reminders | Opaque local note ID and generic notification copy | Scheduling hands the generic title **Clean Notes**, generic body **Open Clean Notes to view your reminder.**, and an opaque `note:v1:<id>` payload to the platform notification service. The app does not put note title or content in those fields, and Android requests private notification visibility. Android and Apple code paths handle tap/open. Snooze actions are Android-only; Apple targets have no Darwin snooze categories unless a future release adds them. Permission, delivery, action, process-death, and reboot behavior require device verification. |

The current app source and primary platform configuration contain no app-owned
HTTP client, remote API, analytics SDK, crash-reporting SDK, or telemetry
pipeline. Android debug/profile manifests include development-only Internet
permission for Flutter tooling; the main Android manifest does not declare it.
This code review is not a contractual guarantee that no data leaves a device:
the OS share/file-picker services, notification service, selected share target,
managed backup behavior on non-Android targets, OEM transfer implementations,
and future dependencies remain separate boundaries.

The More sheet displays these scopes before starting platform share or file
picker work: readable exports exclude Trash, JSON backup includes every status,
and import appends Active copies with reminders cleared.

The transfer implementation keeps each boundary typed and testable:
`NoteExportFormatter` validates and serializes `Note` values,
`NotesTransferGateway` owns platform picker/share values, the Riverpod controller
owns operation state and selects the status-appropriate collection, and the
`ImportNotes` use case normalizes imported copies before one repository
transaction. Platform objects do not cross into the domain model.

## Retention and deletion

- Notes remain in SQLite while active, archived, or in Trash.
- The visible Trash flow allows restore or confirmed permanent deletion. Permanent
  deletion removes the database row and asks the notification plugin to cancel
  that note's reminder. If cancellation fails after the database commit, the
  note stays deleted and the UI offers a sanitized, coalesced cancellation-only
  retry. Retrying does not recreate or delete the note again.
- A repository cleanup operation exists for trashed rows whose original
  `createdAt` is more than 30 days old, but no production UI invocation is
  currently wired. Do not promise automatic 30-day deletion from this code.
- Shared exports and imported source files are outside the app's deletion
  control. File sharing uses in-memory `XFile.fromData` inputs; the platform or
  sharing plugin may materialize a copy in temporary/cache storage. The app has
  no explicit cleanup job for those copies, so OS/plugin lifecycle and the
  selected destination control their retention. This is a known low-severity
  residual risk.
- Android managed cloud backup and device transfer are disabled and excluded by
  checked-in rules. Clearing app storage, uninstalling, or losing the device can
  therefore remove the only app-private copy unless the user exported JSON and
  retained that file somewhere recoverable. Backup behavior on other shipping
  platforms remains a release-verification and disclosure decision.
- No application-level encryption-at-rest layer is implemented. Storage may
  still inherit device- or platform-level protection.

## Notification disclosure

App-supplied reminder fields use generic copy and an opaque local ID rather than
note title or content. The OS can still expose the app name, generic reminder
copy, timing, and action labels on the lock screen, notification center,
connected wearables, or other platform surfaces; platform settings may override
preview behavior. Permission prompts, delivery after process death or reboot,
and action behavior require physical-device evidence; see
[QA](qa.md#reminders-and-notifications) and
[release readiness](release.md#notifications-and-platform-permissions).

The current release plan assumes no earlier public or beta population has
pending reminders created with legacy notification payload/copy. The parser can
still open a delivered legacy payload, but the app does not migrate pending
legacy schedules. If any earlier build was distributed, upgrade-device testing
and a reviewed migration or explicit cleanup plan become release blockers;
clear or uninstall old internal QA builds before first-release evidence.

## Owner decisions

Each decision is complete only when an accountable owner, decision, and approval
date are recorded in the release record and the public-facing disclosure is
updated to match.

- **[OWNER: Product/Legal] Contact:** choose and publish an active
  privacy/support contact and URL. Keep the release blocked rather than shipping
  a placeholder or unreachable destination.
- **[OWNER: Product/Legal] Retention and deletion:** define Trash retention,
  whether automatic cleanup is intended, how original creation time affects it,
  and what users are told about exports, Android's manual-recovery model, and
  managed backups on other platforms.
- **[OWNER: Security/Product] Encryption at rest:** decide whether platform
  protection is sufficient or an app-managed encryption design is required.
- **[OWNER: Release/Product] Supported platforms:** name the platforms that ship;
  validate this disclosure and storage paths on each one.
- **[OWNER: Product/Legal] Lock-screen disclosure:** approve the generic reminder
  preview and action labels, including platform overrides and connected devices.
- **[OWNER: Product/Legal] No-network language:** choose whether to make any
  contractual no-network/no-tracking claim. Require a release-build network and
  dependency audit before approving one.

Re-audit this document whenever storage fields, transfer formats, notifications,
platform targets, dependencies, analytics, or network behavior change.
