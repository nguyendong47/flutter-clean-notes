# Privacy and Data Flow

> **Non-legal technical draft.** This document describes the checked-in
> implementation for engineering and release review. It is not a privacy policy
> or legal advice. Product, legal, and release owners must resolve every item in
> [Owner decisions](#owner-decisions) before publishing a contractual statement.

## Current technical behavior

| Flow | Data | Boundary and trigger |
| --- | --- | --- |
| Note storage | ID, title, content, color, creation time, pin state, tags, status, optional reminder time, and an internal reminder generation | Stored in the app's local `notes_database.db` SQLite database. Schema v7 also stores pending generation-tagged schedule/cancel commands in `reminder_outbox`. Desktop uses the application-support directory and sqflite FFI. Web uses `databaseFactoryFfiWeb` with the shipped `sqflite_sw.js` worker and `sqlite3.wasm`, persisting the database in same-origin IndexedDB. Android and Apple mobile targets use the regular sqflite database path. |
| Theme preference | System, light, or dark selection | Stored locally through platform shared preferences and resolved before the first app frame. A missing, invalid, or unreadable value falls back to the system setting. |
| Markdown preview | User-authored note body and embedded image/link URIs | Rendered locally with `flutter_markdown_plus 1.0.12`. Every image is replaced by an inert accessible placeholder, and only the internal `note://` scheme is handled. Preview content does not open or fetch network, file, data, or other external URIs. |
| Text export | Titles, content, and tags from Active and Archive notes only | Started only after **Export text**. Native targets hand text to the OS share surface. Web shares or downloads a generated `notes.txt`; mail fallback is disabled. Trash is excluded. The selected share target or downloaded file controls subsequent handling. |
| Markdown export | Titles, content, and tags from Active and Archive notes only | Started only after **Export Markdown**. Native targets hand `notes.md` to the OS share surface; Web uses Web Share when available or downloads the file. Mail fallback is disabled. Trash is excluded. |
| JSON backup | IDs, titles, content, tags, color, creation time, pin state, status, and reminder time from Active, Archive, and Trash | Started only after **Backup JSON**. Native targets hand `notes_backup.json` to the OS share surface; Web uses Web Share when available or downloads the file. Mail fallback is disabled. Creation fails before platform handoff if the UTF-8 output exceeds 10 MiB or any semantic/structural limit. |
| JSON import | The fields accepted by the JSON backup format | The user selects one `.json` file through the platform file picker. The app accepts at most 10 MiB of valid UTF-8 (with an optional BOM), validates semantic field bounds and JSON depth/complexity before one SQLite transaction, and rejects unsupported nested data. Import is not a byte-for-byte restore: entries are appended as copies. Title, content, tags, color, creation time, and pin state are retained, while each copy receives a fresh ID, active status, and no reminder. |
| Android managed backup | App-private files, databases, preferences, and related storage domains | The main manifest disables Android managed backup, and Android 12+ data-extraction rules exclude every supported domain from both cloud backup and device-to-device transfer. Manual JSON export is the app-supported recovery path. OEM transfer behavior still requires physical-device evidence. |
| Reminders | Opaque local note ID, internal generation, and generic notification copy | New scheduling is available on Android, iOS, and macOS. Web, Windows, and Linux do not offer **Add reminder**; they disclose that reminders are unavailable and still allow a stored reminder to be cleared. Scheduling hands the generic title **Clean Notes**, generic body **Open Clean Notes to view your reminder.**, and an opaque `note:v2:<id>:<generation>` payload to the platform notification service. The app does not put note title or content in those fields, and Android requests private notification visibility. Android and Apple code paths handle tap/open. Snooze actions are Android-only; Apple targets have no Darwin snooze categories unless a future release adds them. Optional initialization failure does not block startup. Durable commands are retried by later reminder work or the selective startup audit. Permission, delivery, action, process-death, and reboot behavior still require device verification. |
| Offline privacy disclosure | The implemented storage, reminder, transfer, retention, and network summary | The bundled `/privacy` route is opened from More and, once the app is loaded, requires no additional network request. It is an in-app technical disclosure, not the owner-approved public privacy/support URL required for store submission. |

The current app source and primary platform configuration contain no app-owned
HTTP client, remote API, analytics SDK, crash-reporting SDK, or telemetry
pipeline. Android debug/profile manifests include development-only Internet
permission for Flutter tooling; the main Android manifest does not declare it.
The canonical Web release uses `--no-web-resources-cdn`, so Flutter engine assets
are served with the app instead of fetched from a third-party CDN. It bundles the
official Roboto variable font and redirects Flutter's dynamic fallback base to
the deployment origin, where five Noto WOFF2 shards cover the editor/QA sample.
The fallback-base configuration prevents a Google font request. The bundle is not
a complete Unicode corpus: an unbundled glyph can return a same-origin 404 and
render as tofu, but cannot trigger cross-origin fallback. See the
[Roboto provenance](../assets/fonts/README.md) and
[fallback provenance](../web/fallback_fonts/README.md). A Web user still reaches
the app and same-origin SQLite worker/WASM through the chosen deployment server;
this is not a promise of offline first installation.
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

JSON creation and restoration share the same resource contract: at most 10 MiB
of UTF-8, 10,000 notes, 32 fields per note, 32 Ki UTF-16 code units in a title,
5 Mi UTF-16 code units in a body, 256 tags per note, 50,000 tags in total, and
1,024 UTF-16 code units per tag. Field names are capped at 128 code units; JSON
nesting is capped at 64 and structural tokens are bounded. Unknown scalar fields
remain forward-compatible, while unknown list/map fields are rejected so compact
input cannot hide unbounded nested data.

## Retention and deletion

- Notes remain in SQLite while active, archived, or in Trash.
- The visible Trash flow allows restore or confirmed permanent deletion. Permanent
  deletion removes the database row and writes a cancellation command in the
  same SQLite transaction. If native cancellation fails, the note stays deleted,
  the durable command remains pending, and the UI may also offer a sanitized,
  coalesced cancellation-only retry. Retrying does not recreate or delete the
  note again.
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
- Web storage is scoped to the complete browser origin. A different scheme,
  host, or port sees a different IndexedDB store; clearing site data, browser
  eviction, or private-session teardown can remove the browser copy. The app
  does not provide cloud synchronization, so retain a JSON export before
  clearing browser storage when recovery is required.
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

The SQLite transaction and platform notification side effect cannot be one OS-
level atomic operation. Schema v7 closes the process-death gap by committing a
reminder-bearing add, reminder-changing update/clear, permanent delete/cleanup,
or accepted snooze with one current generation-tagged outbox command. Other note
mutations do not create reminder commands. The
serialized coordinator cancels before schedule, rechecks supersession, and
acknowledges only the exact current generation after successful native work.
Failure leaves that command durable. After launch, a selective audit compares
pending native notifications with SQLite and drains missing, stale, orphaned, or
expired v2/outbox work without globally resetting notifications or requesting
permission.

Version-2 generations guard pending-schedule audit and snooze. Open routes by note
ID for v2, v1, and older payloads. A legacy snooze is accepted only when the note
is still generation 0 and still has a reminder; stale or cleared legacy actions
cannot resurrect it. Startup conservatively preserves a pending legacy/v1
notification only while its SQLite note remains generation 0 and its reminder is
non-null, even when that timestamp is expired, because the native generation is
unknowable. An advanced note is reconciled from its current SQLite generation/
reminder state. These invariants have automated process-restart and
migration coverage, but plugin/OS persistence, permission, force-stop, reboot,
and OEM behavior still require signed physical-device evidence before release.

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
- **[OWNER: Engineering/Product/Release] Reminder platform validation:** attach
  signed physical-device evidence that durable reconciliation, permission,
  process-death, reboot, open, and Android snooze behavior matches this technical
  contract on every supported shipping platform.
- **[OWNER: Product/Legal] No-network language:** choose whether to make any
  contractual no-network/no-tracking claim. Require a release-build network and
  dependency audit before approving one.

Re-audit this document whenever storage fields, transfer formats, notifications,
platform targets, dependencies, analytics, or network behavior change.
