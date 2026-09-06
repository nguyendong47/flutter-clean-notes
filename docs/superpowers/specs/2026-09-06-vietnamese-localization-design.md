# Flutter Clean Notes — Vietnamese Localization

| Metadata | Value |
| --- | --- |
| Approved | 2026-09-06 |
| Status | Approved design contract |
| Canonical role | Product and technical contract for adding a switchable English/Vietnamese UI language |
| Update rule | Change approved requirements only through an explicit design decision |

Operational status and evidence live in [Project Sync / Handoff](../handoff.md) once implementation starts. Ordered implementation details live in the implementation plan (to be written via `writing-plans` after this spec is approved).

## Objective

Add a Vietnamese UI language option alongside the existing English UI, covering every user-facing string, with automatic system-locale detection and a manual override the user can set or clear from the More sheet. The app has no cloud sync; this is a pure client-side presentation feature. Domain, repository, database, and notification behavior are unaffected — only how their user-facing text renders.

## Non-goals

- Translating user-authored note content (titles/bodies) — never touched. Only app chrome (navigation, buttons, empty states, dialogs, error/status messages, accessibility labels) is localized.
- Supporting any language beyond English and Vietnamese in this pass. The chosen architecture (`easy_localization`) makes adding a third language later a matter of adding one more JSON file plus a `supportedLocales` entry, but that is out of scope now.
- Changing the app's default language for existing users beyond what their device locale already implies (an English-device user sees no change; a Vietnamese-device user now sees Vietnamese where before they saw English).

## Architecture decision

**Chosen: `easy_localization`** (JSON translation files, `.tr()` extension, automatic locale persistence).

Considered and rejected:
- **`flutter_localizations` + ARB + `flutter gen-l10n`** — the more conventional Flutter-native approach (type-safe generated accessors, no async init in tests). Rejected in favor of `easy_localization` per explicit product decision: JSON files are simpler to hand-edit for translation, and there is no separate `gen-l10n` build step to remember before every build. Trade-off accepted: `easy_localization` requires `EasyLocalization.ensureInitialized()` (async) before `runApp`, and every existing widget test that mounts a localized widget tree needs a test-harness update to also initialize/wrap with `EasyLocalization`.
- **Hand-rolled `Map<Locale, Map<String, String>>`** — no third-party dependency, but no tooling to catch missing keys, no automatic locale-aware date/number formatting, and reinvents what `easy_localization`/`intl` already solve. Rejected.

## Locale selection behavior

- **Default:** on first launch (and whenever no manual override is stored), the app follows the device's system locale. If the system locale is Vietnamese (`vi`), the app shows Vietnamese; any other system locale falls back to English (`fallbackLocale`).
- **Manual override:** the More sheet gets a new **"Ngôn ngữ / Language"** row, opening a bottom sheet with three options: **Hệ thống / System**, **Tiếng Việt**, **English**. Selecting Tiếng Việt/English calls `context.setLocale(...)`, which `easy_localization` persists internally (its own `SharedPreferences` key) and restores on every subsequent launch, bypassing system-locale detection until cleared. Selecting **System** calls `context.resetLocale()`, which clears the stored override and reverts to system-locale detection.
- No separate Riverpod provider is introduced to mirror this state (unlike `appThemeProvider`) — `easy_localization` already exposes `context.locale` as an `InheritedWidget` and persists it itself, so a parallel provider would be redundant. The More sheet reads `context.locale` directly to show the current selection.

## Components touched

- **`pubspec.yaml`** — add `easy_localization` dependency; declare `assets/translations/` in the `flutter.assets` list.
- **`assets/translations/en.json`, `assets/translations/vi.json`** — flat-namespaced keys grouped by screen: `home.*`, `editor.*`, `search.*`, `library.*`, `more.*`, `privacy.*`, `common.*` (shared strings like button labels, confirmation dialogs).
- **`lib/main.dart`** — call `await EasyLocalization.ensureInitialized()` alongside the existing Flutter-binding/sqflite-FFI bootstrap, before `runApp`. Wrap the root widget in `EasyLocalization(supportedLocales: [Locale('en'), Locale('vi')], path: 'assets/translations', fallbackLocale: Locale('en'), child: ...)`.
- **`MaterialApp` construction site** — add `localizationsDelegates: context.localizationDelegates`, `supportedLocales: context.supportedLocales`, `locale: context.locale`.
- **More sheet (`lib/features/notes/presentation/**`)** — add the Language row and its picker bottom sheet, following the existing theme-picker's bottom-sheet pattern.
- **Every presentation-layer widget with a user-facing string literal** — replace with `'namespaced.key'.tr()`. This includes Home, Search, Library, Editor, More, the bundled Privacy route, snackbars/error messages, confirmation dialogs (discard changes, permanent delete), empty states, and accessibility semantic labels.
- **Date formatting** (e.g. the Home header's "Saturday, September 5") — keep using `intl`'s `DateFormat`, passing `context.locale.toString()` as the locale argument so it renders "Thứ Bảy, 5 tháng 9" automatically when Vietnamese is active. No manual date-string translation needed.

## Error handling

- Unsupported system locale (anything other than `en`/`vi`) silently falls back to `en` via `fallbackLocale` — no error surfaced to the user.
- A missing translation key renders the raw key string in debug builds (default `easy_localization` behavior), which is the signal to catch during the translation-authoring pass (Task C) before merge — not a runtime error condition to handle in production code.

## Testing strategy

- Add a shared test helper (e.g. `test/support/localization_test_wrapper.dart`) that initializes `easy_localization` in test mode and wraps a widget under test, defaulting to the `en` locale.
- Update existing widget tests to use this wrapper wherever they currently mount a `MaterialApp`/screen directly. Because the default test locale stays English and the English JSON values match today's literal strings, the large majority of the existing 637 tests' text assertions (e.g. `find.text('Good afternoon')`) keep passing unchanged — only the mounting/wrapper code changes.
- Add a new, deliberately small smoke-test suite that mounts the Home, Editor, and More screens with the `vi` locale and asserts a representative Vietnamese string renders on each — this is coverage that the plumbing works, not a duplicate of the full English suite.
- Add a focused test that the Home header date renders through `intl` with the active locale (e.g. asserts a Vietnamese month name appears when locale is `vi`).

## Implementation sequencing

Mirrors the task-based structure of the original Aurora plan; each task gets its own GitNexus `detect_changes` check and commit per `CLAUDE.md`'s Always-Do rules.

| Task | Scope |
| --- | --- |
| A | `easy_localization` infra: dependency, JSON scaffolding, `main.dart`/`MaterialApp` wiring, and the full string-literal extraction sweep into `en.json` — no visible behavior change (English output stays identical, only its source moves from literal to `.tr()` lookup). Largest, most mechanical task; touches the most files. |
| B | Language row + picker in the More sheet; System/Tiếng Việt/English selection wired to `setLocale`/`resetLocale`. |
| C | Author `vi.json` — translate every key extracted in Task A. Content work; benefits from native-speaker review before merge. |
| D | Test-harness updates (wrapper helper, existing test migration) + new Vietnamese smoke tests + the locale-aware date-formatting test. |

## Acceptance criteria

- Every user-facing string in the app (chrome, dialogs, empty states, errors, accessibility labels) has both an English and a Vietnamese translation; none falls back to a raw key in either locale.
- A device set to Vietnamese shows the Vietnamese UI on first launch with no manual action.
- The More sheet's Language picker correctly switches to Vietnamese, switches to English, and reverts to System, with the choice persisting across app restarts (until changed again).
- Home header dates render in the active locale's format and month/weekday names.
- The full test suite (existing + new) passes serially; no existing test needed a text-assertion change, only harness/mounting changes, except where a test now needs an explicit non-default locale.
- `flutter analyze --fatal-infos --fatal-warnings` is clean and `dart run build_runner build` (unaffected by this feature, but run as part of the standard gate) shows no unexpected drift.
