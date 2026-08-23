# Privacy and Data Flow

> **Non-legal technical draft.** This document describes the checked-in
> implementation for engineering and release review. It is not a privacy policy
> or legal advice. Product, legal, and release owners must resolve every item in
> [Owner decisions](#owner-decisions) before publishing a contractual statement.

## Current technical behavior

| Flow | Data | Boundary and trigger |
| --- | --- | --- |
| Note storage | ID, title, content, color, creation time, pin state, tags, status, and optional reminder time | Stored in the app's local `notes_database.db` SQLite database. Desktop uses the application-support directory and sqflite FFI; other targets use the sqflite database path. |
| Theme preference | System, light, or dark selection | Stored locally through platform shared preferences. |
| Text export | Note titles, content, and tags | Sent to the operating-system share sheet only after the user selects **Export text**. The destination selected in that sheet controls subsequent handling. |
| Markdown export | Note titles, content, and tags | A generated `notes.md` file is sent to the operating-system share sheet only after the user selects **Export Markdown**. |
| JSON backup | Note IDs, titles, content, tags, color, creation time, pin state, status, and reminder time | A generated `notes_backup.json` file is sent to the operating-system share sheet only after the user selects **Backup JSON**. |
| JSON import | The same note fields accepted by the JSON backup format | The user selects one `.json` file through the platform file picker. The app rejects an empty selection and payloads over 10 MB, validates the JSON, then imports the notes in a SQLite transaction. |
| Reminders | Notification title, body, and payload derived from the note | Scheduling hands data to the platform notification service. The current notification title includes the note title, the body includes note content, and the payload includes ID, title, content, color, creation time, and reminder time. Notification actions can open the note or snooze it. |

The current app source and primary platform configuration contain no app-owned
HTTP client, remote API, analytics SDK, crash-reporting SDK, or telemetry
pipeline. Android debug/profile manifests include development-only Internet
permission for Flutter tooling; the main Android manifest does not declare it.
This code review is not a contractual guarantee that no data leaves a device:
the OS share/file-picker services, notification service, selected share target,
platform backups, and future dependencies remain separate boundaries.

## Retention and deletion

- Notes remain in SQLite while active, archived, or in Trash.
- The visible Trash flow allows restore or confirmed permanent deletion. Permanent
  deletion removes the database row and asks the notification plugin to cancel
  that note's reminder.
- A repository cleanup operation exists for trashed rows whose original
  `createdAt` is more than 30 days old, but no production UI invocation is
  currently wired. Do not promise automatic 30-day deletion from this code.
- Shared exports and imported source files are outside the app's deletion
  control. Platform or device backups may retain app data according to OS and
  user settings.
- No application-level encryption-at-rest layer is implemented. Storage may
  still inherit device- or platform-level protection.

## Notification disclosure

Reminder notifications may expose a note title and content on the lock screen,
notification center, connected wearables, or other platform surfaces, depending
on OS settings and implementation behavior. Permission prompts, preview settings,
exact-alarm eligibility, and delivery behavior require physical-device evidence;
see [QA](qa.md#reminders-and-notifications) and
[release readiness](release.md#notifications-and-platform-permissions).

## Owner decisions

Each decision is complete only when an accountable owner, decision, and approval
date are recorded in the release record and the public-facing disclosure is
updated to match.

- **[OWNER: Product/Legal] Contact:** choose the privacy/support contact and public URL.
- **[OWNER: Product/Legal] Retention and deletion:** define Trash retention,
  whether automatic cleanup is intended, how original creation time affects it,
  and what users are told about exports and platform backups.
- **[OWNER: Security/Product] Encryption at rest:** decide whether platform
  protection is sufficient or an app-managed encryption design is required.
- **[OWNER: Release/Product] Supported platforms:** name the platforms that ship;
  validate this disclosure and storage paths on each one.
- **[OWNER: Product/Legal] Lock-screen disclosure:** decide whether notification
  title/content previews are acceptable, configurable, or must be redacted.
- **[OWNER: Product/Legal] No-network language:** choose whether to make any
  contractual no-network/no-tracking claim. Require a release-build network and
  dependency audit before approving one.

Re-audit this document whenever storage fields, transfer formats, notifications,
platform targets, dependencies, analytics, or network behavior change.
