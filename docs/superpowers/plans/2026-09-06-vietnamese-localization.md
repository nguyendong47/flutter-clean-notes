# Vietnamese Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a switchable English/Vietnamese UI language to Clean Notes: every user-facing string localized, system-locale default, manual override in the More sheet.

**Architecture:** `easy_localization` (JSON translation files under `assets/translations/`, `.tr()` extension) wired through `EasyLocalization.ensureInitialized()` in `main.dart` and `context.localizationDelegates`/`supportedLocales`/`locale` on `MaterialApp.router`. Existing widget tests build their own `MaterialApp` trees directly (confirmed: 18 files), so a shared test wrapper (`test/support/localization_test_wrapper.dart`) is introduced before any string is touched, keeping the suite green through every later task instead of breaking it until a final harness task.

**Tech Stack:** Flutter/Dart, `easy_localization` (new dependency), existing `intl` for locale-aware `DateFormat`, `flutter_riverpod`.

**Spec:** `docs/superpowers/specs/2026-09-06-vietnamese-localization-design.md`

## Global Constraints

- Only app chrome (navigation, buttons, empty states, dialogs, error/status messages, accessibility labels) is localized. User-authored note titles/bodies are never touched.
- English and Vietnamese only in this pass (`supportedLocales: [Locale('en'), Locale('vi')]`).
- Default: system locale; fallback `Locale('en')` for anything else. Manual override via `context.setLocale(...)` persists itself (easy_localization's own storage); `context.resetLocale()` clears it.
- No new Riverpod provider for locale state — read `context.locale` directly (spec §Locale selection behavior).
- A missing key renders the raw key in debug builds — that is the authoring signal for Task 19 (vi.json), not a runtime error to catch in code.
- Every task in this plan ends with `flutter test --no-pub --concurrency=1 test/<touched files>` passing, and the task's commit runs GitNexus `detect_changes` first per `CLAUDE.md`.

## File Structure

```
assets/translations/en.json          # new — English source strings, nested by screen namespace
assets/translations/vi.json          # new — Vietnamese translations (Task 19)
lib/main.dart                        # modify — EasyLocalization.ensureInitialized() + wrap + intl date-symbol init
test/support/localization_test_wrapper.dart   # new — shared widget-test harness
test/support/localization_test_wrapper_test.dart  # new — proves the wrapper works
lib/features/notes/presentation/widgets/more_actions_sheet.dart   # modify — string sweep (Task 6) + Language row (Task 18)
lib/features/notes/presentation/pages/{privacy,notes_home,notes_search,notes_library,add_edit_note,existing_note_route}_page.dart  # modify — string sweep
lib/features/notes/presentation/widgets/{editor_formatting_bar,note_metadata_sheet,note_filter_sheet,notes_state_view,notes_bottom_bar,library_segmented_control,tag_manager_sheet,glass_note_card}.dart  # modify — string sweep
lib/app/notification_service.dart    # modify — notification channel/title/body/action strings
lib/features/notes/presentation/widgets/note_card.dart  # NOT touched — confirmed dead code (see Task 16)
test/**/*_test.dart (18 files)       # modify — wrap pumpWidget trees with the shared wrapper, one task per production file above
test/features/notes/presentation/vietnamese_smoke_test.dart   # new — Task 20
test/features/notes/presentation/home_date_locale_test.dart   # new — Task 21
```

Namespaces used (nested JSON, dot-accessed by `easy_localization`): `common.*` (shared strings — Cancel/Done/Retry/etc. and the shared empty/loading/bottom-bar chrome), `home.*`, `editor.*` (formatting bar + add/edit page), `search.*`, `library.*`, `more.*`, `privacy.*`, `metadata.*` (note metadata sheet), `filter.*` (note filter sheet), `tags.*` (tag manager sheet), `notification.*` (scheduled notification content). These extend, not contradict, the spec's example list (`home/editor/search/library/more/privacy/common`) — the extra namespaces (`metadata`, `filter`, `tags`, `notification`) are the same "grouped by screen" convention applied to widgets the spec didn't enumerate individually.

---

## Task 1: Dependency and translation-asset scaffolding

**Files:**
- Modify: `pubspec.yaml`
- Create: `assets/translations/en.json`
- Create: `assets/translations/vi.json` (seeded with the same 6 keys as `en.json`, English text as a temporary placeholder — Task 19 replaces the values)

**Interfaces:**
- Produces: `common.cancel`, `common.done`, `common.retry`, `common.tryAgain`, `common.undo`, `common.close` keys other tasks reuse.

- [ ] **Step 1: Add the dependency**

Edit `pubspec.yaml`, in `dependencies:` (after `flutter_staggered_grid_view: ^0.7.0`):

```yaml
  flutter_staggered_grid_view: ^0.7.0
  easy_localization: ^3.0.7
```

- [ ] **Step 2: Register the translations asset folder**

Edit `pubspec.yaml`, in the `flutter:` section's `assets:` list:

```yaml
  assets:
    - assets/fonts/OFL.txt
    - assets/translations/
```

- [ ] **Step 3: Seed `assets/translations/en.json`**

```json
{
  "common": {
    "cancel": "Cancel",
    "done": "Done",
    "retry": "Retry",
    "tryAgain": "Try again",
    "undo": "Undo",
    "close": "Close"
  }
}
```

- [ ] **Step 4: Seed `assets/translations/vi.json`** (placeholder English text; Task 19 translates it)

```json
{
  "common": {
    "cancel": "Cancel",
    "done": "Done",
    "retry": "Retry",
    "tryAgain": "Try again",
    "undo": "Undo",
    "close": "Close"
  }
}
```

- [ ] **Step 5: Fetch and verify**

Run: `flutter pub get --enforce-lockfile`
Expected: fails (lockfile doesn't have `easy_localization` yet) — then run `flutter pub get` (without `--enforce-lockfile`) to update the lock, then re-run `flutter pub get --enforce-lockfile` to confirm it's now satisfied.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock assets/translations/en.json assets/translations/vi.json
git commit -m "feat(l10n): add easy_localization dependency and translation asset scaffolding"
```

---

## Task 2: Shared widget-test localization wrapper

**Files:**
- Create: `test/support/localization_test_wrapper.dart`
- Create: `test/support/localization_test_wrapper_test.dart`

**Interfaces:**
- Produces: `Future<void> pumpLocalized(WidgetTester tester, Widget widget, {Locale locale = const Locale('en')})` — every later test-file task calls this instead of `tester.pumpWidget(MaterialApp(...))` directly, wrapping their existing tree.
- Produces: `Widget wrapWithTestLocalization(Widget child, {Locale locale = const Locale('en')})` — the same wrapping, exposed separately for tests that need to build the widget tree themselves before pumping (e.g. tests that pump a `Scaffold` with a `Builder` to trigger a bottom sheet).

- [ ] **Step 1: Write the wrapper**

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps [child] with the same [EasyLocalization] configuration production
/// code installs in `main.dart`, so widgets using `.tr()`/`context.locale`
/// work in widget tests. Must run after `TestWidgetsFlutterBinding
/// .ensureInitialized()` (flutter_test does this automatically).
Widget wrapWithTestLocalization(
  Widget child, {
  Locale locale = const Locale('en'),
}) {
  return EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('vi')],
    path: 'assets/translations',
    fallbackLocale: const Locale('en'),
    startLocale: locale,
    useOnlyLangCode: true,
    child: child,
  );
}

/// Pumps [widget] wrapped with [wrapWithTestLocalization] and settles.
Future<void> pumpLocalized(
  WidgetTester tester,
  Widget widget, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(wrapWithTestLocalization(widget, locale: locale));
  await tester.pumpAndSettle();
}
```

- [ ] **Step 2: Write a test that proves it works**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'localization_test_wrapper.dart';

void main() {
  testWidgets('wrapWithTestLocalization resolves a real translation key', (
    tester,
  ) async {
    await pumpLocalized(
      tester,
      Builder(builder: (context) => Text('common.cancel'.tr())),
    );

    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('pumpLocalized honors the requested locale', (tester) async {
    await pumpLocalized(
      tester,
      Builder(builder: (context) => Text(context.locale.languageCode)),
      locale: const Locale('vi'),
    );

    expect(find.text('vi'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run it**

Run: `flutter test --no-pub test/support/localization_test_wrapper_test.dart`
Expected: `+2: All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add test/support/localization_test_wrapper.dart test/support/localization_test_wrapper_test.dart
git commit -m "test(l10n): add shared EasyLocalization widget-test wrapper"
```

---

## Task 3: Wire EasyLocalization into `main.dart` and `MyApp`

**Files:**
- Modify: `lib/main.dart`
- Modify: `test/features/notes/presentation/aurora_notes_flow_test.dart:277,319,394` (the only 3 call sites in the whole test suite that construct `MyApp()` directly, bypassing `bootstrapApplication`)

**Interfaces:**
- Consumes: `wrapWithTestLocalization` from Task 2.
- Produces: every widget under `MyApp` can now call `.tr()` and read `context.locale`/`context.localizationDelegates`/`context.supportedLocales` — this is the dependency every later sweep task relies on for the *production* tree (widget tests that build their own `MaterialApp` instead of `MyApp` rely on Task 2's wrapper, not this task).

- [ ] **Step 1: Add imports and initialize date-symbol data + EasyLocalization in `bootstrapApplication`**

In `lib/main.dart`, add imports:

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/date_symbol_data_local.dart';
```

Change the top of `bootstrapApplication` (currently starts with `WidgetsFlutterBinding.ensureInitialized();`):

```dart
Future<void> bootstrapApplication({
  NotificationService? notificationService,
  FutureOr<void> Function()? initializeDatabase,
  ProviderContainer Function(NotificationService notificationService)?
  createContainer,
  void Function(Widget app)? runApplication,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await initializeDateFormatting('vi');
  await initializeDateFormatting('en');
  final databaseInitializer = initializeDatabase;
```

- [ ] **Step 2: Wrap the widget passed to `runApp`**

Change:

```dart
    (runApplication ?? runApp)(
      UncontrolledProviderScope(container: container, child: const MyApp()),
    );
```

to:

```dart
    (runApplication ?? runApp)(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('vi')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        useOnlyLangCode: true,
        child: UncontrolledProviderScope(
          container: container,
          child: const MyApp(),
        ),
      ),
    );
```

- [ ] **Step 3: Wire `MaterialApp.router` to the localization delegates**

Change `MyApp.build`:

```dart
    return MaterialApp.router(
      title: 'Clean Notes',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      theme: AuroraTheme.light(),
      darkTheme: AuroraTheme.dark(),
      themeMode: themeMode,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
    );
```

- [ ] **Step 4: Fix the 3 direct `MyApp()` test call sites**

In `test/features/notes/presentation/aurora_notes_flow_test.dart`, add the import:

```dart
import '../../support/localization_test_wrapper.dart';
```

Then at each of the 3 sites (lines 277, 319, 394), change:

```dart
      UncontrolledProviderScope(container: container, child: const MyApp()),
```

to:

```dart
      wrapWithTestLocalization(
        UncontrolledProviderScope(container: container, child: const MyApp()),
      ),
```

(The import path `../../support/localization_test_wrapper.dart` is relative to `test/features/notes/presentation/`; adjust only if the file actually lives elsewhere — verify with `test -f test/support/localization_test_wrapper.dart` from repo root.)

- [ ] **Step 5: Run the full suite to confirm nothing else regressed**

Run: `flutter test --no-pub --concurrency=1`
Expected: `+637: All tests passed!` (same count as before this task — this task changes zero user-visible text, it only adds the ancestor widget every later task needs).

- [ ] **Step 6: GitNexus impact check, then commit**

Run: `node .gitnexus/run.cjs impact "MyApp" --direction upstream --repo .` and `node .gitnexus/run.cjs detect-changes --scope all --repo .` — confirm no HIGH/CRITICAL risk before committing.

```bash
git add lib/main.dart test/features/notes/presentation/aurora_notes_flow_test.dart
git commit -m "feat(l10n): wire EasyLocalization through bootstrapApplication and MyApp"
```

---

## Task 4: More sheet — extract existing strings into `more.*`

**Files:**
- Modify: `lib/features/notes/presentation/widgets/more_actions_sheet.dart`
- Modify: `test/features/notes/presentation/more_actions_sheet_test.dart`
- Modify: `assets/translations/en.json`

**Interfaces:**
- Consumes: `common.cancel` (Task 1) for the two `_TransferRow`/dialog cancel labels that already exist elsewhere in this file's error strings — none exist here, this file has none of the shared `common.*` strings, so this task adds `more.*` only.

- [ ] **Step 1: Add the `more` namespace to `assets/translations/en.json`**

```json
  "more": {
    "title": "More",
    "closeTooltip": "Close {title}",
    "sectionAppearance": "Appearance",
    "themeRowLabel": "Theme",
    "themeSystem": "System",
    "themeSystemDescription": "Match this device",
    "themeLight": "Light",
    "themeLightDescription": "Always use light appearance",
    "themeDark": "Dark",
    "themeDarkDescription": "Always use dark appearance",
    "themeSaving": "Saving theme preference…",
    "themeSaveError": "Could not save theme preference. Try again.",
    "themeFollowDevice": "Follow device setting",
    "themeLightSelected": "Light appearance selected",
    "themeDarkSelected": "Dark appearance selected",
    "sectionOrganization": "Organization",
    "manageTags": "Manage tags",
    "manageTagsDescription": "Review usage and remove tags everywhere",
    "sectionTransfer": "Transfer",
    "exportText": "Export text",
    "exportTextDescription": "Export Active and Archive, not Trash",
    "backupJson": "Backup JSON",
    "backupJsonDescription": "Includes Active, Archive, and Trash",
    "exportMarkdown": "Export Markdown",
    "exportMarkdownDescription": "Export Active and Archive, not Trash",
    "importBackup": "Import backup",
    "importBackupDescription": "Append copies as Active; reminders are cleared",
    "privacy": "Privacy",
    "privacyHint": "How Clean Notes handles data",
    "transferExportTextError": "Could not export text. Try again.",
    "transferBackupError": "Could not share backup. Try again.",
    "transferExportMarkdownError": "Could not export Markdown. Try again.",
    "transferImportError": "Could not import backup. Try again.",
    "transferExportTextProgress": "Exporting text…",
    "transferBackupProgress": "Sharing backup…",
    "transferExportMarkdownProgress": "Exporting Markdown…",
    "transferImportProgress": "Importing backup…",
    "transferExportTextHandedOff": "Text export handed off. Check your share target or Downloads.",
    "transferBackupHandedOff": "Backup handed off. Check your share target or Downloads.",
    "transferExportMarkdownHandedOff": "Markdown export handed off. Check your share target or Downloads.",
    "transferImportHandedOff": "Transfer handed off. Check your share target or Downloads.",
    "transferShareSheetOpened": "Share sheet opened.",
    "transferExportTextComplete": "Text export complete.",
    "transferBackupComplete": "Backup sharing complete.",
    "transferExportMarkdownComplete": "Markdown export complete.",
    "transferImportedOne": "Imported 1 note.",
    "transferImportedMany": "Imported {count} notes."
  }
```

Also add `vi` placeholders (same values, English) to `assets/translations/vi.json` under the same `"more": { ... }` block — Task 19 translates them.

- [ ] **Step 2: Replace the literals in `more_actions_sheet.dart`**

Add the import:

```dart
import 'package:easy_localization/easy_localization.dart';
```

Replace each literal with its `.tr()` call. Static/non-interpolated ones (exact string → key):

| Line (approx) | Literal | Replace with |
|---|---|---|
| 133 | `title: 'More'` | `title: 'more.title'.tr()` |
| 140 | `const _SectionLabel('Appearance')` | `_SectionLabel('more.sectionAppearance'.tr())` |
| 145 | `label: 'Theme'` | `label: 'more.themeRowLabel'.tr()` |
| 165 | `label: 'System'` | `label: 'more.themeSystem'.tr()` |
| 166 | `description: 'Match this device'` | `description: 'more.themeSystemDescription'.tr()` |
| 177 | `label: 'Light'` | `label: 'more.themeLight'.tr()` |
| 178 | `description: 'Always use light appearance'` | `description: 'more.themeLightDescription'.tr()` |
| 189 | `label: 'Dark'` | `label: 'more.themeDark'.tr()` |
| 190 | `description: 'Always use dark appearance'` | `description: 'more.themeDarkDescription'.tr()` |
| 217 | `label: 'Manage tags'` | `label: 'more.manageTags'.tr()` |
| 218 | `description: 'Review usage and remove tags everywhere'` | `description: 'more.manageTagsDescription'.tr()` |
| 211 | `const _SectionLabel('Organization')` | `_SectionLabel('more.sectionOrganization'.tr())` |
| 223 | `const _SectionLabel('Transfer')` | `_SectionLabel('more.sectionTransfer'.tr())` |
| 229/230 | `'Export text'` / `'Export Active and Archive, not Trash'` | `'more.exportText'.tr()` / `'more.exportTextDescription'.tr()` |
| 243/244 | `'Backup JSON'` / `'Includes Active, Archive, and Trash'` | `'more.backupJson'.tr()` / `'more.backupJsonDescription'.tr()` |
| 257/258 | `'Export Markdown'` / `'Export Active and Archive, not Trash'` | `'more.exportMarkdown'.tr()` / `'more.exportMarkdownDescription'.tr()` |
| 272/273-274 | `'Import backup'` / `'Append copies as Active; reminders are cleared'` | `'more.importBackup'.tr()` / `'more.importBackupDescription'.tr()` |
| 391 | `label: 'Privacy'` | `label: 'more.privacy'.tr()` |
| 392 | `hint: 'How Clean Notes handles data'` | `hint: 'more.privacyHint'.tr()` |
| 402 | `label: const Text('Privacy')` | `label: Text('more.privacy'.tr())` |
| 305 (`_themeError`) | `'Could not save theme preference. Try again.'` | `'more.themeSaveError'.tr()` |

Interpolated/computed ones — replace the whole function body:

```dart
String _themeLabel(BuildContext context, ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => 'more.themeFollowDevice'.tr(),
    ThemeMode.light => 'more.themeLightSelected'.tr(),
    ThemeMode.dark => 'more.themeDarkSelected'.tr(),
  };
}
```

(This changes `_themeLabel`'s signature to take `context` — update its one call site in `build`, `_themeLabel(selectedTheme)` → `_themeLabel(context, selectedTheme)`.)

```dart
String _transferError(BuildContext context, NotesTransferOperation operation, Object? error) {
  if (operation == NotesTransferOperation.importBackup &&
      error is FormatException) {
    return error.message;
  }
  return switch (operation) {
    NotesTransferOperation.exportText => 'more.transferExportTextError'.tr(),
    NotesTransferOperation.backupJson => 'more.transferBackupError'.tr(),
    NotesTransferOperation.exportMarkdown =>
      'more.transferExportMarkdownError'.tr(),
    NotesTransferOperation.importBackup => 'more.transferImportError'.tr(),
  };
}

String _transferProgress(BuildContext context, NotesTransferOperation operation) {
  return switch (operation) {
    NotesTransferOperation.exportText => 'more.transferExportTextProgress'.tr(),
    NotesTransferOperation.backupJson => 'more.transferBackupProgress'.tr(),
    NotesTransferOperation.exportMarkdown =>
      'more.transferExportMarkdownProgress'.tr(),
    NotesTransferOperation.importBackup => 'more.transferImportProgress'.tr(),
  };
}

String _transferSuccess(BuildContext context, NotesTransferOutcome outcome) {
  if (outcome.status == NotesTransferOutcomeStatus.webShareOrDownloadStarted) {
    return switch (outcome.operation) {
      NotesTransferOperation.exportText =>
        'more.transferExportTextHandedOff'.tr(),
      NotesTransferOperation.backupJson => 'more.transferBackupHandedOff'.tr(),
      NotesTransferOperation.exportMarkdown =>
        'more.transferExportMarkdownHandedOff'.tr(),
      NotesTransferOperation.importBackup =>
        'more.transferImportHandedOff'.tr(),
    };
  }
  if (outcome.status == NotesTransferOutcomeStatus.shareSheetOpened) {
    return 'more.transferShareSheetOpened'.tr();
  }
  return switch (outcome.operation) {
    NotesTransferOperation.exportText => 'more.transferExportTextComplete'.tr(),
    NotesTransferOperation.backupJson => 'more.transferBackupComplete'.tr(),
    NotesTransferOperation.exportMarkdown =>
      'more.transferExportMarkdownComplete'.tr(),
    NotesTransferOperation.importBackup => switch (outcome.importedCount ?? 0) {
      1 => 'more.transferImportedOne'.tr(),
      final count => 'more.transferImportedMany'.tr(namedArgs: {'count': '$count'}),
    },
  };
}
```

Update the 3 call sites of these functions inside `build`/`_TransferRow.build` to pass `context` as the first argument (e.g. `_transferError(context, operation, state.error)`).

For the `IconButton`'s `tooltip: 'Close $title'` (line 408, inside `_SheetHeader`, where `title` is a constructor parameter that is now always the translated `'more.title'.tr()` string passed in from `MyApp`'s build): replace with `tooltip: 'more.closeTooltip'.tr(namedArgs: {'title': title})`.

- [ ] **Step 3: Update the test file**

In `test/features/notes/presentation/more_actions_sheet_test.dart`, add the import and switch `_pumpMore`'s `tester.pumpWidget(...)` call from a bare `ProviderScope(...)` root to the wrapped version:

```dart
import '../../support/localization_test_wrapper.dart';
```

Change:

```dart
  await tester.pumpWidget(
    ProviderScope(
```

to:

```dart
  await tester.pumpWidget(
    wrapWithTestLocalization(
      ProviderScope(
```

and close the added parenthesis right before the existing final `),` that currently closes the outermost `ProviderScope(` call (i.e. add one more `)` after it). Do not change any `find.text('...')` assertions — the English JSON values are byte-identical to the removed literals, so every existing assertion keeps passing unchanged.

- [ ] **Step 4: Run the test**

Run: `flutter test --no-pub test/features/notes/presentation/more_actions_sheet_test.dart`
Expected: same pass count as before this task, 0 failures.

- [ ] **Step 5: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add lib/features/notes/presentation/widgets/more_actions_sheet.dart test/features/notes/presentation/more_actions_sheet_test.dart assets/translations/en.json assets/translations/vi.json
git commit -m "feat(l10n): extract More sheet strings into more.* translation keys"
```

---

## Task 5: Privacy page — extract strings into `privacy.*`

**Files:**
- Modify: `lib/features/notes/presentation/pages/privacy_page.dart`
- Modify: `test/features/notes/presentation/privacy_page_test.dart`, `test/app/privacy_route_test.dart`
- Modify: `assets/translations/en.json` / `vi.json`

- [ ] **Step 1: Add to `en.json`**

```json
  "privacy": {
    "title": "Privacy",
    "sectionWhereNotesLive": "Where your notes live",
    "sectionReminders": "Reminders use platform services",
    "sectionTransfer": "Import, export, and backup",
    "sectionAppInitiated": "You control app-initiated transfers",
    "sectionNetwork": "Network behavior",
    "sectionRetention": "Retention and deletion",
    "chipLocalFirst": "Local-first",
    "chipNoAccount": "No account",
    "chipYouChooseTransfers": "You choose transfers"
  }
```

- [ ] **Step 2: Replace literals in `privacy_page.dart`**

Add `import 'package:easy_localization/easy_localization.dart';`. Replace each of the 9 literals above 1:1 by line (28, 59, 80, 97, 112, 128, 147, 218, 219, 220) — e.g. line 28: `title: const Text('Privacy')` → `title: Text('privacy.title'.tr())`; line 218: `Chip(label: Text('Local-first'))` → `Chip(label: Text('privacy.chipLocalFirst'.tr()))`; same pattern for the remaining 7.

- [ ] **Step 3: Update tests**

In both `test/features/notes/presentation/privacy_page_test.dart` and `test/app/privacy_route_test.dart`, wrap the existing `pumpWidget(MaterialApp(...))` call with `wrapWithTestLocalization(...)` exactly as in Task 4 Step 3, adding the `import '../../support/localization_test_wrapper.dart';` (adjust relative path per each file's location — `test/app/privacy_route_test.dart` imports as `'../support/localization_test_wrapper.dart'`).

- [ ] **Step 4: Run and verify**

Run: `flutter test --no-pub test/features/notes/presentation/privacy_page_test.dart test/app/privacy_route_test.dart`
Expected: same pass count as before, 0 failures.

- [ ] **Step 5: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add lib/features/notes/presentation/pages/privacy_page.dart test/features/notes/presentation/privacy_page_test.dart test/app/privacy_route_test.dart assets/translations/en.json assets/translations/vi.json
git commit -m "feat(l10n): extract privacy page strings into privacy.* translation keys"
```

---

## Task 6: Editor formatting bar — extract strings into `editor.*`

**Files:**
- Modify: `lib/features/notes/presentation/widgets/editor_formatting_bar.dart`
- Modify: `test/features/notes/presentation/editor_formatting_bar_test.dart`
- Modify: `assets/translations/en.json` / `vi.json`

- [ ] **Step 1: Add to `en.json`**

```json
  "editor": {
    "bold": "Bold",
    "italic": "Italic",
    "strikethrough": "Strikethrough",
    "inlineCode": "Inline code",
    "quote": "Quote",
    "heading1": "Heading 1",
    "heading2": "Heading 2",
    "bulletedList": "Bulleted list",
    "checklist": "Checklist",
    "formattingTools": "Formatting tools"
  }
```

- [ ] **Step 2: Replace the 10 literals** in `editor_formatting_bar.dart` (lines 18, 24, 30, 36, 42, 48, 55, 62, 68, 76) with `'editor.bold'.tr()`, `'editor.italic'.tr()`, `'editor.strikethrough'.tr()`, `'editor.inlineCode'.tr()`, `'editor.quote'.tr()`, `'editor.heading1'.tr()`, `'editor.heading2'.tr()`, `'editor.bulletedList'.tr()`, `'editor.checklist'.tr()`, `'editor.formattingTools'.tr()` respectively. Add the `easy_localization` import.

- [ ] **Step 3: Update the test**

In `test/features/notes/presentation/editor_formatting_bar_test.dart`, wrap its `pumpWidget` call with `wrapWithTestLocalization` as in Task 4 Step 3.

- [ ] **Step 4: Run and verify**

Run: `flutter test --no-pub test/features/notes/presentation/editor_formatting_bar_test.dart`
Expected: same pass count, 0 failures.

- [ ] **Step 5: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add lib/features/notes/presentation/widgets/editor_formatting_bar.dart test/features/notes/presentation/editor_formatting_bar_test.dart assets/translations/en.json assets/translations/vi.json
git commit -m "feat(l10n): extract editor formatting bar strings into editor.* translation keys"
```

---

## Task 7: Note metadata sheet — extract strings into `metadata.*`

**Files:**
- Modify: `lib/features/notes/presentation/widgets/note_metadata_sheet.dart`
- Modify: `test/features/notes/presentation/note_metadata_sheet_test.dart`
- Modify: `assets/translations/en.json` / `vi.json`

- [ ] **Step 1: Add to `en.json`**

```json
  "metadata": {
    "cancelTooltip": "Cancel",
    "newTagLabel": "New tag",
    "newTagHint": "For example, work",
    "addTagTooltip": "Add tag",
    "cancel": "Cancel",
    "apply": "Apply",
    "removeTagTooltip": "Remove {tag} tag",
    "clearReminder": "Clear reminder"
  }
```

- [ ] **Step 2: Replace literals** in `note_metadata_sheet.dart` (add `easy_localization` import):
  - Line 119 `tooltip: 'Cancel'` → `tooltip: 'metadata.cancelTooltip'.tr()`
  - Line 157 `labelText: 'New tag'` → `labelText: 'metadata.newTagLabel'.tr()`
  - Line 158 `hintText: 'For example, work'` → `hintText: 'metadata.newTagHint'.tr()`
  - Line 162 `tooltip: 'Add tag'` → `tooltip: 'metadata.addTagTooltip'.tr()`
  - Line 271 `child: const Text('Cancel')` → `child: Text('metadata.cancel'.tr())`
  - Line 279 `child: const Text('Apply')` → `child: Text('metadata.apply'.tr())`
  - Line 359 `tooltip: 'Remove $tag tag'` → `tooltip: 'metadata.removeTagTooltip'.tr(namedArgs: {'tag': tag})`
  - Line 443 `label: const Text('Clear reminder')` → `label: Text('metadata.clearReminder'.tr())`

- [ ] **Step 3: Update the test**

Wrap `test/features/notes/presentation/note_metadata_sheet_test.dart`'s `pumpWidget` call with `wrapWithTestLocalization`.

- [ ] **Step 4: Run and verify**

Run: `flutter test --no-pub test/features/notes/presentation/note_metadata_sheet_test.dart`
Expected: same pass count, 0 failures.

- [ ] **Step 5: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add lib/features/notes/presentation/widgets/note_metadata_sheet.dart test/features/notes/presentation/note_metadata_sheet_test.dart assets/translations/en.json assets/translations/vi.json
git commit -m "feat(l10n): extract note metadata sheet strings into metadata.* translation keys"
```

---

## Task 8: Note filter sheet — extract strings into `filter.*`

**Files:**
- Modify: `lib/features/notes/presentation/widgets/note_filter_sheet.dart`
- Modify: whichever test(s) reference it — run `grep -rl "NoteFilterSheet" test/` first to find them (expected: `test/features/notes/presentation/notes_search_page_test.dart` and/or `test/features/notes/presentation/notes_library_page_test.dart`; those two are already covered by Tasks 11/12's wrapper edits, so no separate test-file edit is needed here beyond confirming the string change doesn't break them)
- Modify: `assets/translations/en.json` / `vi.json`

- [ ] **Step 1: Add to `en.json`**

```json
  "filter": {
    "closeTooltip": "Close filters",
    "all": "All",
    "clearFilters": "Clear filters",
    "done": "Done",
    "filterByTagSemantics": "Filter by tag {tag}",
    "sortBySemantics": "Sort by {label}"
  }
```

- [ ] **Step 2: Replace literals** in `note_filter_sheet.dart` (add `easy_localization` import):
  - Line 56 `tooltip: 'Close filters'` → `tooltip: 'filter.closeTooltip'.tr()`
  - Line 78 `label: 'All'` → `label: 'filter.all'.tr()`
  - Line 145 `child: const Text('Clear filters')` → `child: Text('filter.clearFilters'.tr())`
  - Line 152 `child: const Text('Done')` → `child: Text('filter.done'.tr())`
  - Line 203 `label: 'Filter by tag $label'` → `label: 'filter.filterByTagSemantics'.tr(namedArgs: {'tag': label})`
  - Line 237 `label: 'Sort by $label'` → `label: 'filter.sortBySemantics'.tr(namedArgs: {'label': label})`

- [ ] **Step 3: Run whichever test files reference `NoteFilterSheet`**

Run: `flutter test --no-pub test/features/notes/presentation/notes_search_page_test.dart test/features/notes/presentation/notes_library_page_test.dart`
Expected: this will fail until Tasks 11 and 12 (below) also wrap those two test files' `pumpWidget` calls — if this task lands before Task 11/12 in execution order, note the expected failure is "no EasyLocalization ancestor" and defer verification to whichever of Task 8/11/12 lands last. If executing tasks strictly in the order written in this document, Tasks 11/12 come after this one, so re-run this exact command again after Task 12 to get the real pass/fail signal.

- [ ] **Step 4: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add lib/features/notes/presentation/widgets/note_filter_sheet.dart assets/translations/en.json assets/translations/vi.json
git commit -m "feat(l10n): extract note filter sheet strings into filter.* translation keys"
```

---

## Task 9: Shared chrome — `notes_state_view.dart`, `notes_bottom_bar.dart`, `library_segmented_control.dart` into `common.*`/`library.*`

**Files:**
- Modify: `lib/features/notes/presentation/widgets/notes_state_view.dart`
- Modify: `lib/features/notes/presentation/widgets/notes_bottom_bar.dart`
- Modify: `lib/features/notes/presentation/widgets/library_segmented_control.dart`
- Modify: `assets/translations/en.json` / `vi.json`
- No dedicated test file changes here — these 3 widgets are only exercised indirectly through the page tests wrapped in Tasks 10-13; this task's own verification is Step 4 below.

- [ ] **Step 1: Add to `en.json`** (extend the existing `common` object from Task 1, and add `library`):

```json
    "loadingNotes": "Loading notes",
    "createNote": "Create note",
    "moreActions": "More actions",
    "createNewNote": "Create new note"
```

(insert these 4 keys into the existing `"common": { ... }` object from Task 1, alongside `cancel`/`done`/etc.)

```json
  "library": {
    "sections": "Library sections",
    "archived": "Archived",
    "trash": "Trash"
  }
```

- [ ] **Step 2: Replace literals**

`lib/features/notes/presentation/widgets/notes_state_view.dart` (add `easy_localization` import):
- Line 15 `label: 'Loading notes'` → `label: 'common.loadingNotes'.tr()`
- Line 125 `label: const Text('Create note')` → `label: Text('common.createNote'.tr())`
- Line 182 `label: const Text('Try again')` → `label: Text('common.tryAgain'.tr())`

`lib/features/notes/presentation/widgets/notes_bottom_bar.dart` (add `easy_localization` import):
- Line 267 `label: 'More actions'` → `label: 'common.moreActions'.tr()`
- Line 293 `label: 'Create new note'` → `label: 'common.createNewNote'.tr()`
- Line 330 `tooltip: 'Create new note'` → `tooltip: 'common.createNewNote'.tr()`

`lib/features/notes/presentation/widgets/library_segmented_control.dart` (add `easy_localization` import):
- Line 26 `label: 'Library sections'` → `label: 'library.sections'.tr()`
- Line 34 `Text('Archived', textAlign: TextAlign.center)` → `Text('library.archived'.tr(), textAlign: TextAlign.center)`
- Line 39 `Text('Trash', textAlign: TextAlign.center)` → `Text('library.trash'.tr(), textAlign: TextAlign.center)`

- [ ] **Step 3: Run the tests that render these 3 widgets**

Run: `flutter test --no-pub test/features/notes/presentation/notes_home_page_test.dart test/features/notes/presentation/notes_search_page_test.dart test/features/notes/presentation/notes_library_page_test.dart`
Expected: as with Task 8, these depend on Tasks 10-12's wrapper edits — re-run after Task 12 if executed in document order.

- [ ] **Step 4: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add lib/features/notes/presentation/widgets/notes_state_view.dart lib/features/notes/presentation/widgets/notes_bottom_bar.dart lib/features/notes/presentation/widgets/library_segmented_control.dart assets/translations/en.json assets/translations/vi.json
git commit -m "feat(l10n): extract shared chrome strings into common.*/library.* translation keys"
```

---

## Task 10: Tag manager sheet — extract strings into `tags.*`

**Files:**
- Modify: `lib/features/notes/presentation/widgets/tag_manager_sheet.dart`
- Modify: `test/features/notes/presentation/more_actions_sheet_test.dart` (it drives `TagManagerSheet` via `_openTags`; already wrapped in Task 4, no further change needed here beyond re-running it)
- Modify: `assets/translations/en.json` / `vi.json`

- [ ] **Step 1: Add to `en.json`**

```json
  "tags": {
    "closeTooltip": "Close Manage tags",
    "loading": "Loading tags…",
    "retry": "Retry",
    "removeTagSemantics": "Remove {tag} tag",
    "removeTagTooltip": "Remove {tag} tag",
    "removing": "Removing…",
    "remove": "Remove",
    "cancel": "Cancel",
    "removingTagSemantics": "Removing tag"
  }
```

- [ ] **Step 2: Replace literals** in `tag_manager_sheet.dart` (add `easy_localization` import):
  - Line 116 `tooltip: 'Close Manage tags'` → `tooltip: 'tags.closeTooltip'.tr()`
  - Line 251 `Expanded(child: Text('Loading tags…'))` → `Expanded(child: Text('tags.loading'.tr()))`
  - Line 336 `label: const Text('Retry')` → `label: Text('tags.retry'.tr())`
  - Line 404 `label: 'Remove ${usage.tag} tag'` → `label: 'tags.removeTagSemantics'.tr(namedArgs: {'tag': usage.tag})`
  - Line 412 `tooltip: 'Remove ${usage.tag} tag'` → `tooltip: 'tags.removeTagTooltip'.tr(namedArgs: {'tag': usage.tag})`
  - Line 525 `Text('Removing…')` → `Text('tags.removing'.tr())`
  - Line 528 `: const Text('Remove')` → `: Text('tags.remove'.tr())`
  - Line 559 `child: const Text('Cancel')` → `child: Text('tags.cancel'.tr())`
  - Line 571 `label: 'Removing tag'` → `label: 'tags.removingTagSemantics'.tr()`

- [ ] **Step 3: Run and verify**

Run: `flutter test --no-pub test/features/notes/presentation/more_actions_sheet_test.dart`
Expected: same pass count as after Task 4, 0 failures.

- [ ] **Step 4: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add lib/features/notes/presentation/widgets/tag_manager_sheet.dart assets/translations/en.json assets/translations/vi.json
git commit -m "feat(l10n): extract tag manager sheet strings into tags.* translation keys"
```

---

## Task 11: Glass note card — extract strings into `common.*` and make dates locale-aware

**Files:**
- Modify: `lib/features/notes/presentation/widgets/glass_note_card.dart`
- Modify: `test/features/notes/presentation/glass_note_card_test.dart`
- Modify: `assets/translations/en.json` / `vi.json`

- [ ] **Step 1: Add to `en.json`** (extend `common`):

```json
    "pinned": "Pinned",
    "updatingNoteSemantics": "Updating note {title}",
    "moreActionsForSemantics": "More actions for {title}",
    "createdSemantics": "Created {date}",
    "reminderSemantics": "Reminder {date}",
    "storedReminderSemantics": "Stored reminder date {date}. "
```

(Note the trailing space in `storedReminderSemantics` — preserve it exactly, it matters for how the sentence concatenates with what follows it in the original code at line 388.)

- [ ] **Step 2: Convert the static `DateFormat` fields to locale-aware getters**

Change:

```dart
class _GlassNoteCardState extends State<GlassNoteCard> {
  static final _dateFormat = DateFormat('MMM d, yyyy');
  static final _reminderFormat = DateFormat('MMM d, h:mm a');
```

to:

```dart
class _GlassNoteCardState extends State<GlassNoteCard> {
  DateFormat get _dateFormat =>
      DateFormat('MMM d, yyyy', context.locale.toString());
  DateFormat get _reminderFormat =>
      DateFormat('MMM d, h:mm a', context.locale.toString());
```

Add the `easy_localization` import (for the `context.locale` extension) alongside the existing `intl` import.

- [ ] **Step 3: Replace the remaining literals**

Add `easy_localization` import if not already added by Step 2.
- Line 282 semantics `label: 'Updating note $title'` → `label: 'common.updatingNoteSemantics'.tr(namedArgs: {'title': title})` (verify the exact variable name at that line when editing — it may be `widget.note.title` rather than a local `title`; use whatever the surrounding code already binds).
- Line 139 `tooltip: 'More actions for $title'` → `tooltip: 'common.moreActionsForSemantics'.tr(namedArgs: {'title': title})`
- Line 282 (a different one — the pinned badge) `label: 'Pinned'` → `label: 'common.pinned'.tr()`
- Line 287 `label: dateFormat.format(note.createdAt)` → `label: 'common.createdSemantics'.tr(namedArgs: {'date': dateFormat.format(note.createdAt)}).replaceFirst('Created ', dateFormat.format(note.createdAt))` — **do not use this fallback**; instead, since line 287's `label` is *only* the formatted date (no "Created" prefix — that prefix appears at line 383's different helper function), leave line 287 as plain `dateFormat.format(note.createdAt)` unchanged and only translate the line-383/386/388 helper below.
- Lines 383/386/388, the free function (not a method) that builds a full semantics sentence:

```dart
String _noteMetaSemantics(
  BuildContext context,
  Note note,
  DateFormat dateFormat,
  DateFormat reminderFormat,
) {
  final parts = <String>[
    'common.createdSemantics'.tr(
      namedArgs: {'date': dateFormat.format(note.createdAt)},
    ),
  ];
  final reminder = note.reminder;
  if (reminder != null) {
    parts.add(
      note.reminderGeneration > 0
          ? 'common.reminderSemantics'.tr(
              namedArgs: {'date': reminderFormat.format(reminder)},
            )
          : 'common.storedReminderSemantics'.tr(
              namedArgs: {'date': reminderFormat.format(reminder)},
            ),
    );
  }
  return parts.join(' ');
}
```

Read the actual existing function at lines ~365-395 before applying this — reproduce its exact conditional logic (the condition guarding "Reminder" vs "Stored reminder date" and any other parts it joins, such as a pinned/archived clause) rather than the simplified sketch above, and only swap the string literals for `.tr()` calls; do not change its branching structure or add/remove any concatenated segment.

- [ ] **Step 4: Update the test**

Wrap `test/features/notes/presentation/glass_note_card_test.dart`'s `pumpWidget` call with `wrapWithTestLocalization`.

- [ ] **Step 5: Run and verify**

Run: `flutter test --no-pub test/features/notes/presentation/glass_note_card_test.dart`
Expected: same pass count, 0 failures.

- [ ] **Step 6: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add lib/features/notes/presentation/widgets/glass_note_card.dart test/features/notes/presentation/glass_note_card_test.dart assets/translations/en.json assets/translations/vi.json
git commit -m "feat(l10n): extract glass note card strings into common.* and make dates locale-aware"
```

---

## Task 12: Existing-note route page — extract strings into `common.*`

**Files:**
- Modify: `lib/features/notes/presentation/pages/existing_note_route_page.dart`
- Modify: `assets/translations/en.json` / `vi.json`
- No dedicated test file was found for this page in `test/` — verify via `grep -rl "ExistingNoteRoutePage\|existing_note_route" test/` before skipping; if one exists, wrap its `pumpWidget` call the same way as prior tasks.

- [ ] **Step 1: Add to `en.json`** (extend `common`):

```json
    "openingNote": "Opening note",
    "couldNotOpenNote": "Could not open note",
    "noteNotFound": "Note not found",
    "notesTitle": "Notes"
```

- [ ] **Step 2: Replace literals** (add `easy_localization` import):
  - Line 63 `title: 'Opening note'` → `title: 'common.openingNote'.tr()`
  - Line 71 `title: 'Could not open note'` → `title: 'common.couldNotOpenNote'.tr()`
  - Line 94 `title: 'Note not found'` → `title: 'common.noteNotFound'.tr()`
  - Line 136 `title: const Text('Notes')` → `title: Text('common.notesTitle'.tr())`
  - Line 187 `label: const Text('Try again')` → `label: Text('common.tryAgain'.tr())`

- [ ] **Step 3: Run `flutter analyze` and the router test**

Run: `flutter analyze --no-pub lib/features/notes/presentation/pages/existing_note_route_page.dart` then `flutter test --no-pub test/app/router_test.dart`
Expected: 0 issues; existing pass count for `router_test.dart` (this file already wraps `MaterialApp.router`-style trees — check whether it needs `wrapWithTestLocalization` too by running it first; if it fails with a missing-EasyLocalization-ancestor error, add the wrap exactly as in Task 4 Step 3).

- [ ] **Step 4: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add lib/features/notes/presentation/pages/existing_note_route_page.dart assets/translations/en.json assets/translations/vi.json
git commit -m "feat(l10n): extract existing-note route page strings into common.* translation keys"
```

---

## Task 13: Notes library page — extract strings into `library.*`

**Files:**
- Modify: `lib/features/notes/presentation/pages/notes_library_page.dart`
- Modify: `test/features/notes/presentation/notes_library_page_test.dart`
- Modify: `assets/translations/en.json` / `vi.json`

- [ ] **Step 1: Add to `en.json`** (extend `library`):

```json
    "updateError": "Could not update library. Try again.",
    "undo": "Undo",
    "retry": "Retry",
    "reminderCancelled": "Reminder cancelled.",
    "deleteForeverTitle": "Delete \"{title}\" forever?",
    "deleteForeverBody": "This action cannot be undone.",
    "cancel": "Cancel",
    "deletingSemantics": "Deleting {title}",
    "deleting": "Deleting…",
    "deleteForever": "Delete forever",
    "noArchivedNotes": "No archived notes",
    "trashEmpty": "Trash is empty"
```

- [ ] **Step 2: Replace literals** (add `easy_localization` import):
  - Line 226 `content: Text('Could not update library. Try again.')` → `content: Text('library.updateError'.tr())`
  - Line 244 `label: 'Undo'` → `label: 'library.undo'.tr()`
  - Line 312 `label: 'Retry'` → `label: 'library.retry'.tr()`
  - Line 332 `child: const Text('Reminder cancelled.')` → `child: Text('library.reminderCancelled'.tr())`
  - Line 437 `title: Text('Delete "$title" forever?')` → `title: Text('library.deleteForeverTitle'.tr(namedArgs: {'title': title}))`
  - Line 442 `const Text('This action cannot be undone.')` → `Text('library.deleteForeverBody'.tr())`
  - Line 458 `child: const Text('Cancel')` → `child: Text('library.cancel'.tr())`
  - Line 471 `label: 'Deleting $title'` → `label: 'library.deletingSemantics'.tr(namedArgs: {'title': title})`
  - Line 480 `Text('Deleting…')` → `Text('library.deleting'.tr())`
  - Line 484 `: const Text('Delete forever')` → `: Text('library.deleteForever'.tr())`
  - Line 505 `title: 'No archived notes'` → `title: 'library.noArchivedNotes'.tr()`
  - Line 511 `title: 'Trash is empty'` → `title: 'library.trashEmpty'.tr()`
  - Line 623 `label: const Text('Retry')` → `label: Text('library.retry'.tr())`

Note the JSON escaping for the curly quotes in the original source (`"Delete "$title" forever?"` uses literal `"` characters inside the Dart string, which was itself single-quoted) — the JSON value must use plain `"` (not curly `“ ”`) matching the actual source; re-check the literal source text at line 437 before typing the JSON value, since this plan's transcription may not preserve the exact quote glyph used.

- [ ] **Step 3: Update the test**

Wrap `test/features/notes/presentation/notes_library_page_test.dart`'s `pumpWidget` call with `wrapWithTestLocalization`.

- [ ] **Step 4: Run and verify**

Run: `flutter test --no-pub test/features/notes/presentation/notes_library_page_test.dart`
Expected: same pass count, 0 failures. Also re-run Task 8's and Task 9's dependent commands now that this wrapper edit has landed:

Run: `flutter test --no-pub test/features/notes/presentation/notes_search_page_test.dart test/features/notes/presentation/notes_library_page_test.dart`

- [ ] **Step 5: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add lib/features/notes/presentation/pages/notes_library_page.dart test/features/notes/presentation/notes_library_page_test.dart assets/translations/en.json assets/translations/vi.json
git commit -m "feat(l10n): extract notes library page strings into library.* translation keys"
```

---

## Task 14: Notes search page — extract strings into `search.*`

**Files:**
- Modify: `lib/features/notes/presentation/pages/notes_search_page.dart`
- Modify: `test/features/notes/presentation/notes_search_page_test.dart`
- Modify: `assets/translations/en.json` / `vi.json`

- [ ] **Step 1: Add to `en.json`**

```json
  "search": {
    "fieldSemantics": "Search notes and tags",
    "hint": "Search titles, content, and tags",
    "clearTooltip": "Clear search",
    "filterTooltip": "Filter search results",
    "noMatchSemantics": "No notes match your search",
    "undo": "Undo",
    "loadingSemantics": "Loading search results",
    "couldNotLoad": "Could not load notes",
    "tryAgain": "Try again",
    "retry": "Retry",
    "noNotesYet": "No notes yet",
    "createNote": "Create note",
    "searchTagTooltip": "Search tag {tag}",
    "noMatchForQuery": "No notes match \"{query}\"",
    "clearSearch": "Clear search",
    "resetFilters": "Reset filters"
  }
```

- [ ] **Step 2: Replace literals** (add `easy_localization` import):
  - Line 192 `label: 'Search notes and tags'` → `label: 'search.fieldSemantics'.tr()`
  - Line 198 `hintText: 'Search titles, content, and tags'` → `hintText: 'search.hint'.tr()`
  - Line 219 `tooltip: 'Clear search'` → `tooltip: 'search.clearTooltip'.tr()`
  - Line 234 `tooltip: 'Filter search results'` → `tooltip: 'search.filterTooltip'.tr()`
  - Line 319 `label: 'No notes match your search'` → `label: 'search.noMatchSemantics'.tr()`
  - Line 516 `label: 'Undo'` → `label: 'search.undo'.tr()`
  - Line 541 `label: 'Loading search results'` → `label: 'search.loadingSemantics'.tr()`
  - Line 561 `title: 'Could not load notes'` → `title: 'search.couldNotLoad'.tr()`
  - Line 566 `child: const Text('Try again')` → `child: Text('search.tryAgain'.tr())`
  - Line 621 `child: const Text('Retry')` → `child: Text('search.retry'.tr())`
  - Line 639 `title: 'No notes yet'` → `title: 'search.noNotesYet'.tr()`
  - Line 646 `label: const Text('Create note')` → `label: Text('search.createNote'.tr())`
  - Line 701 `tooltip: 'Search tag $tag'` → `tooltip: 'search.searchTagTooltip'.tr(namedArgs: {'tag': tag})`
  - Line 732 `title: 'No notes match "$query"'` → `title: 'search.noMatchForQuery'.tr(namedArgs: {'query': query})` (verify actual quote glyph in source, same caveat as Task 13)
  - Line 743 `child: const Text('Clear search')` → `child: Text('search.clearSearch'.tr())`
  - Line 751 `child: const Text('Reset filters')` → `child: Text('search.resetFilters'.tr())`

- [ ] **Step 3: Update the test**

Wrap `test/features/notes/presentation/notes_search_page_test.dart`'s `pumpWidget` call with `wrapWithTestLocalization`.

- [ ] **Step 4: Run and verify**

Run: `flutter test --no-pub test/features/notes/presentation/notes_search_page_test.dart`
Expected: same pass count, 0 failures.

- [ ] **Step 5: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add lib/features/notes/presentation/pages/notes_search_page.dart test/features/notes/presentation/notes_search_page_test.dart assets/translations/en.json assets/translations/vi.json
git commit -m "feat(l10n): extract notes search page strings into search.* translation keys"
```

---

## Task 15: Add/edit note page — extract strings into `editor.*`

**Files:**
- Modify: `lib/features/notes/presentation/pages/add_edit_note_page.dart`
- Modify: `test/features/notes/presentation/add_edit_note_page_test.dart`
- Modify: `assets/translations/en.json` / `vi.json`

- [ ] **Step 1: Add to `en.json`** (extend `editor`):

```json
    "detailsTooltip": "Note details",
    "savingSemantics": "Saving note",
    "doneSemantics": "Done",
    "done": "Done",
    "retry": "Retry",
    "titleSemantics": "Title",
    "titleHint": "Untitled note",
    "contentSemantics": "Note content",
    "contentHint": "Start writing…",
    "linkedNoteNotFound": "Linked note not found. Create it first.",
    "discardTitle": "Discard changes?",
    "discardBody": "Your unsaved changes will be lost.",
    "discardConfirm": "Discard changes",
    "keepEditing": "Keep editing"
```

- [ ] **Step 2: Replace literals** (add `easy_localization` import):
  - Line 264 `tooltip: 'Note details'` → `tooltip: 'editor.detailsTooltip'.tr()`
  - Line 283 `label: 'Saving note'` → `label: 'editor.savingSemantics'.tr()`
  - Line 293 `label: 'Done'` → `label: 'editor.doneSemantics'.tr()`
  - Line 298 `: const Text('Done')` → `: Text('editor.done'.tr())`
  - Line 408 `label: 'Title'` → `label: 'editor.titleSemantics'.tr()`
  - Line 424 `hintText: 'Untitled note'` → `hintText: 'editor.titleHint'.tr()`
  - Line 436 `label: 'Note content'` → `label: 'editor.contentSemantics'.tr()`
  - Line 449 `hintText: 'Start writing…'` → `hintText: 'editor.contentHint'.tr()`
  - Line 599 `label: const Text('Retry')` → `label: Text('editor.retry'.tr())`
  - Line 847 `content: Text('Linked note not found. Create it first.')` → `content: Text('editor.linkedNoteNotFound'.tr())`
  - Line 901 `title: const Text('Discard changes?')` → `title: Text('editor.discardTitle'.tr())`
  - Line 902 `content: const Text('Your unsaved changes will be lost.')` → `content: Text('editor.discardBody'.tr())`
  - Line 907 `child: const Text('Discard changes')` → `child: Text('editor.discardConfirm'.tr())`
  - Line 913 `child: const Text('Keep editing')` → `child: Text('editor.keepEditing'.tr())`

- [ ] **Step 3: Update the test**

Wrap `test/features/notes/presentation/add_edit_note_page_test.dart`'s `pumpWidget` call with `wrapWithTestLocalization`.

- [ ] **Step 4: Run and verify**

Run: `flutter test --no-pub test/features/notes/presentation/add_edit_note_page_test.dart`
Expected: same pass count, 0 failures.

- [ ] **Step 5: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add lib/features/notes/presentation/pages/add_edit_note_page.dart test/features/notes/presentation/add_edit_note_page_test.dart assets/translations/en.json assets/translations/vi.json
git commit -m "feat(l10n): extract add/edit note page strings into editor.* translation keys"
```

---

## Task 16: Notes home page — extract strings into `home.*`, locale-aware date and greeting

**Files:**
- Modify: `lib/features/notes/presentation/pages/notes_home_page.dart`
- Modify: `test/features/notes/presentation/notes_home_page_test.dart`, `test/app/startup_theme_guard_test.dart` (verify only — see Step 5)
- Modify: `assets/translations/en.json` / `vi.json`

- [ ] **Step 1: Add to `en.json`**

```json
  "home": {
    "greetingMorning": "Good morning",
    "greetingAfternoon": "Good afternoon",
    "greetingEvening": "Good evening",
    "useLightTheme": "Use light theme",
    "useDarkTheme": "Use dark theme",
    "savingThemeSemantics": "Saving theme preference…",
    "undo": "Undo",
    "retry": "Retry",
    "themeSaveError": "Theme stays unchanged. Try again.",
    "searchSemantics": "Search notes",
    "allTagsFilter": "All",
    "updateError": "Could not update this note. Check the note list before trying again."
  }
```

- [ ] **Step 2: Make the date format locale-aware**

Change:

```dart
class _NotesHomePageState extends ConsumerState<NotesHomePage> {
  static final _dateFormat = DateFormat('EEEE, MMMM d');
```

to:

```dart
class _NotesHomePageState extends ConsumerState<NotesHomePage> {
  DateFormat get _dateFormat =>
      DateFormat('EEEE, MMMM d', context.locale.toString());
```

Add the `easy_localization` import.

- [ ] **Step 3: Replace the remaining literals**

  - Line 303-305 `'Could not update this note. Check the note list before trying again.'` (a multi-line adjacent-string-literal — replace the whole thing) → `'home.updateError'.tr()`
  - Line 261 `label: 'Undo'` → `label: 'home.undo'.tr()`
  - Line 286 `label: 'Retry'` → `label: 'home.retry'.tr()`
  - Line 409 `content: Text('Theme stays unchanged. Try again.')` → `content: Text('home.themeSaveError'.tr())`
  - Line 438 `label: 'Search notes'` → `label: 'home.searchSemantics'.tr()`
  - Line 493 `label: const Text('All')` → `label: Text('home.allTagsFilter'.tr())`
  - Line 327 `final toggleLabel = dark ? 'Use light theme' : 'Use dark theme';` → `final toggleLabel = dark ? 'home.useLightTheme'.tr() : 'home.useDarkTheme'.tr();`
  - Lines 329-333, the greeting `switch`:

```dart
    final greeting = hour < 12
        ? 'home.greetingMorning'.tr()
        : hour < 18
        ? 'home.greetingAfternoon'.tr()
        : 'home.greetingEvening'.tr();
```

  - Line 366 `value: _themeBusy ? 'Saving theme preference…' : null` → `value: _themeBusy ? 'home.savingThemeSemantics'.tr() : null`

- [ ] **Step 4: Update the test**

Wrap `test/features/notes/presentation/notes_home_page_test.dart`'s `pumpWidget` call with `wrapWithTestLocalization`.

- [ ] **Step 5: Run and verify, including the cross-cutting suites**

Run: `flutter test --no-pub --concurrency=1`
Expected: same total pass count as at the end of Task 3 (this is the last of the per-file sweep tasks that touches a file `startup_theme_guard_test.dart` exercises indirectly through the real `bootstrapApplication`/`NotesHomePage` — running the full suite here catches any missed call site instead of relying on a per-file guess).

- [ ] **Step 6: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add lib/features/notes/presentation/pages/notes_home_page.dart test/features/notes/presentation/notes_home_page_test.dart assets/translations/en.json assets/translations/vi.json
git commit -m "feat(l10n): extract notes home page strings into home.* translation keys, locale-aware date"
```

---

## Task 17: Notification service — extract strings into `notification.*`

**Files:**
- Modify: `lib/app/notification_service.dart`
- Modify: `assets/translations/en.json` / `vi.json`
- No test-file wrapper change: `notification_service_test.dart` and `test/app/notification_routing_test.dart` never render a widget tree, so they don't need `wrapWithTestLocalization` — but see Step 3 for the one thing they do need.

**Note:** the internal `ArgumentError.value(..., 'A reminder time is required')`-style messages at lines 397, 405, 412, 430 are developer-facing precondition failures (thrown for programmer error, never surfaced to a user), not UI text — leave them as English literals per the spec's scope (§Objective: "how their user-facing text renders"; these are not rendered to the user at all).

- [ ] **Step 1: Add to `en.json`**

```json
  "notification": {
    "webUnsupported": "Scheduling reminders is not supported on the web.",
    "unavailable": "Notifications are unavailable. Restart Clean Notes and try again.",
    "actionFailed": "A notification action could not be completed. Open Clean Notes to retry.",
    "defaultActionName": "Open notification",
    "channelName": "Note Reminders",
    "title": "Clean Notes",
    "body": "Open Clean Notes to view your reminder.",
    "snoozeAction": "Snooze {minutes} min"
  }
```

- [ ] **Step 2: Replace the user-facing literals**

Add `import 'package:easy_localization/easy_localization.dart';`.
  - Line 40 `'Scheduling reminders is not supported on the web.'` → `'notification.webUnsupported'.tr()`
  - Line 58 `'Notifications are unavailable. Restart Clean Notes and try again.'` → `'notification.unavailable'.tr()`
  - Line 66 `'A notification action could not be completed. Open Clean Notes to retry.'` → `'notification.actionFailed'.tr()`
  - Line 202 `defaultActionName: 'Open notification'` → `defaultActionName: 'notification.defaultActionName'.tr()`
  - Line 455 `'snooze_$minutes'` action id — **do not translate**, it's a machine identifier, not display text
  - Line 456 `'Snooze $minutes min'` → `'notification.snoozeAction'.tr(namedArgs: {'minutes': '$minutes'})`
  - Line 463 `'Note Reminders'` (Android channel name) → `'notification.channelName'.tr()`
  - Line 482 `'Clean Notes'` (notification title) → `'notification.title'.tr()`
  - Line 483 `'Open Clean Notes to view your reminder.'` (notification body) → `'notification.body'.tr()`

- [ ] **Step 3: Confirm `easy_localization`'s context-free `tr()` works here**

`NotificationService` methods have no `BuildContext` — `easy_localization`'s `.tr()` extension works without one because it reads the package's internally cached "current locale" translations, set the moment `EasyLocalization.ensureInitialized()` + the `EasyLocalization` widget mount (Task 3). Because `notification_service_test.dart` never pumps that widget, add one `setUpAll` call at the top of its `main()`:

```dart
setUpAll(() async {
  await EasyLocalization.ensureInitialized();
});
```

with the corresponding import. If any assertion in that file matches on the old literal English strings (e.g. `'Note Reminders'`), it keeps passing unchanged since the English JSON value is identical text — verify with Step 4.

- [ ] **Step 4: Run and verify**

Run: `flutter test --no-pub test/notification_service_test.dart test/app/notification_routing_test.dart`
Expected: same pass count as before, 0 failures. If `tr()` returns the raw key instead of the English value, the translation JSON was not loaded — double check `assets/translations/` is declared in `pubspec.yaml` (Task 1) and that `EasyLocalization.ensureInitialized()` actually ran before the assertion.

- [ ] **Step 5: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add lib/app/notification_service.dart test/notification_service_test.dart assets/translations/en.json assets/translations/vi.json
git commit -m "feat(l10n): extract notification content strings into notification.* translation keys"
```

---

## Task 18: Confirm `note_card.dart` is dead code and exclude it from the sweep

**Files:** none modified — this is a verification-only task, recorded so a future reader doesn't wonder why `note_card.dart` was skipped.

- [ ] **Step 1: Confirm no live caller**

Run: `grep -rn "NoteCard(" lib/` — the only result must be `lib/features/notes/presentation/widgets/note_card.dart:14:  const NoteCard({` (the class's own constructor declaration), and `grep -rln "note_card.dart" lib/` must return only `note_card.dart` itself. This was already verified during plan authoring (2026-09-06): `GlassNoteCard` (Task 11) is the only card widget actually instantiated, from `notes_collection.dart`, `notes_search_page.dart`, and `notes_home_page.dart`.

- [ ] **Step 2: Record the finding**

No commit needed — this task produces no diff. If a future `detect_changes` run or code review flags `note_card.dart`'s un-localized strings, point to this task as the resolution: it's confirmed dead code, not a missed file.

---

## Task 19: Author `assets/translations/vi.json`

**Files:**
- Modify: `assets/translations/vi.json`

**Interfaces:**
- Consumes: every key added to `assets/translations/en.json` across Tasks 1, 4-17.

- [ ] **Step 1: Diff the key sets**

Run a script (or manual JSON diff) to confirm `vi.json` has exactly the same key paths as `en.json` — every key currently holds an English placeholder value from the tasks above. Example check using `python`:

```bash
python -c "
import json
en = json.load(open('assets/translations/en.json', encoding='utf-8'))
vi = json.load(open('assets/translations/vi.json', encoding='utf-8'))
def flatten(d, prefix=''):
    out = set()
    for k, v in d.items():
        path = f'{prefix}.{k}' if prefix else k
        out |= flatten(v, path) if isinstance(v, dict) else {path}
    return out
missing = flatten(en) - flatten(vi)
extra = flatten(vi) - flatten(en)
print('Missing in vi.json:', sorted(missing))
print('Extra in vi.json:', sorted(extra))
"
```

Expected: both sets empty. Fix `vi.json`'s structure first if not (this task only translates values, not key structure — key structure must already match from the per-file tasks above, since each of those tasks added the same keys to both files).

- [ ] **Step 2: Translate every value to Vietnamese**

Replace every English placeholder value in `vi.json` with its Vietnamese translation, preserving `{namedArg}` placeholders verbatim (e.g. `"Snooze {minutes} min"` → `"Báo lại sau {minutes} phút"`, `"Delete \"{title}\" forever?"` → `"Xóa vĩnh viễn \"{title}\"?"`). This is content authorship — there is no single correct translation to hardcode in this plan; the person executing this task (ideally a Vietnamese speaker, per the spec's "benefits from native-speaker review before merge") writes real, natural Vietnamese for each of the ~140 keys added across Tasks 1 and 4-17. Do not leave any value as its English original.

- [ ] **Step 3: Validate JSON and re-run the key-set diff**

Run: `python -c "import json; json.load(open('assets/translations/vi.json', encoding='utf-8'))"` (fails loudly on malformed JSON) then re-run Step 1's diff script — expect both sets still empty.

- [ ] **Step 4: Spot-check in the running app**

This is the first point in the plan where switching to Vietnamese produces visibly different text — manually verify with `flutter run -d chrome` (or any available device), open the More sheet (once Task 20 adds the language row) or temporarily force `startLocale: Locale('vi')` in `main.dart` for a local smoke check, and confirm no screen shows a raw `namespace.key` string (the tell-tale sign of a missing key).

- [ ] **Step 5: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add assets/translations/vi.json
git commit -m "feat(l10n): author Vietnamese translations for all extracted UI strings"
```

---

## Task 20: More sheet — add the Language row and picker

**Files:**
- Modify: `lib/features/notes/presentation/widgets/more_actions_sheet.dart`
- Modify: `test/features/notes/presentation/more_actions_sheet_test.dart`
- Modify: `assets/translations/en.json` / `vi.json`

**Interfaces:**
- Consumes: `context.setLocale(Locale)`/`context.resetLocale()`/`context.locale`/`context.deviceLocale` from `easy_localization` (Task 3's dependency); the existing `_ThemeChoiceRow`/`_ActionRow` pattern (Task 4) as the structural template for the new `_LanguageChoiceRow`.

- [ ] **Step 1: Add the new keys to `en.json`** (extend `more`):

```json
    "sectionLanguage": "Language",
    "languageRowLabel": "Ngôn ngữ / Language",
    "languageSystem": "Hệ thống / System",
    "languageVietnamese": "Tiếng Việt",
    "languageEnglish": "English",
    "languageSavingSemantics": "Saving language preference…"
```

(These 3 option labels are intentionally bilingual per the spec's exact wording: "Hệ thống / System", "Tiếng Việt", "English" — copy them verbatim into both `en.json` and `vi.json`, since the *picker's own option labels* are the one place the spec calls for fixed bilingual text rather than a translated pair, so the control is self-explanatory regardless of which language is currently active.)

- [ ] **Step 2: Add state fields mirroring the existing theme picker**

In `_MoreActionsSheetState`, alongside the existing `_themeChoicesVisible`/`_themeBusy`/`_pendingTheme`/`_themeError` fields, add:

```dart
  bool _languageChoicesVisible = false;
```

(No busy/error/pending state is needed for language: `context.setLocale`/`resetLocale` are synchronous from the caller's perspective — `easy_localization` awaits its internal `SharedPreferences` write before returning, but the spec doesn't ask for a saving-state UI here; keep this row simpler than the theme row, matching what the underlying API actually needs.)

- [ ] **Step 3: Add the Language row and its 3 choices to `build`**

After the closing `],` of the `if (_themeChoicesVisible) ...[...]` theme-choices block (and its following `if (_themeError case ...)` block), insert a new subsection before the existing `const SizedBox(height: 24)` / `_SectionLabel('Organization')` pair:

```dart
                      const SizedBox(height: 24),
                      _SectionLabel('more.sectionLanguage'.tr()),
                      const SizedBox(height: 8),
                      _ActionRow(
                        key: const Key('more-row-language'),
                        icon: Icons.translate_outlined,
                        label: 'more.languageRowLabel'.tr(),
                        description: _languageLabel(context),
                        expanded: _languageChoicesVisible,
                        enabled: !busy,
                        trailing: Icon(
                          _languageChoicesVisible
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                        onPressed: (_) {
                          setState(
                            () => _languageChoicesVisible =
                                !_languageChoicesVisible,
                          );
                        },
                      ),
                      if (_languageChoicesVisible) ...[
                        const SizedBox(height: 8),
                        _LanguageChoiceRow(
                          key: const Key('language-mode-system'),
                          locale: null,
                          label: 'more.languageSystem'.tr(),
                          selected: context.locale == context.deviceLocale,
                          enabled: !busy,
                          onSelected: _setLanguage,
                        ),
                        const SizedBox(height: 8),
                        _LanguageChoiceRow(
                          key: const Key('language-mode-vi'),
                          locale: const Locale('vi'),
                          label: 'more.languageVietnamese'.tr(),
                          selected: context.locale == const Locale('vi'),
                          enabled: !busy,
                          onSelected: _setLanguage,
                        ),
                        const SizedBox(height: 8),
                        _LanguageChoiceRow(
                          key: const Key('language-mode-en'),
                          locale: const Locale('en'),
                          label: 'more.languageEnglish'.tr(),
                          selected: context.locale == const Locale('en'),
                          enabled: !busy,
                          onSelected: _setLanguage,
                        ),
                      ],
```

- [ ] **Step 4: Add `_setLanguage` and `_languageLabel`**

Alongside the existing `_setTheme` method:

```dart
  Future<void> _setLanguage(Locale? locale) async {
    if (locale == null) {
      await context.resetLocale();
    } else {
      await context.setLocale(locale);
    }
  }

  String _languageLabel(BuildContext context) {
    if (context.locale == const Locale('vi')) return 'more.languageVietnamese'.tr();
    if (context.locale == const Locale('en')) return 'more.languageEnglish'.tr();
    return 'more.languageSystem'.tr();
  }
```

- [ ] **Step 5: Add the `_LanguageChoiceRow` widget**

Alongside the existing `_ThemeChoiceRow` class:

```dart
class _LanguageChoiceRow extends StatelessWidget {
  const _LanguageChoiceRow({
    required this.locale,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    super.key,
  });

  final Locale? locale;
  final String label;
  final bool selected;
  final bool enabled;
  final ValueChanged<Locale?> onSelected;

  @override
  Widget build(BuildContext context) {
    return _ActionRow(
      icon: selected ? Icons.radio_button_checked : Icons.radio_button_off,
      label: label,
      description: '',
      selected: selected,
      enabled: enabled,
      trailing: selected ? const Icon(Icons.check) : const SizedBox.shrink(),
      onPressed: (_) => onSelected(locale),
    );
  }
}
```

(`_ActionRow.description` is a required `String` — passing `''` renders an empty second line; if that looks wrong when manually checked in Step 7, revisit `_ActionRow` to make `description` optional rather than fabricating filler text.)

- [ ] **Step 6: Write the test**

Add to `test/features/notes/presentation/more_actions_sheet_test.dart`:

```dart
  testWidgets('Language row switches locale and persists the selection', (
    tester,
  ) async {
    await _pumpMore(tester);

    final languageRow = find.byKey(const Key('more-row-language'));
    await tester.ensureVisible(languageRow);
    await tester.tap(languageRow);
    await tester.pumpAndSettle();

    expect(find.text('Tiếng Việt'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Hệ thống / System'), findsOneWidget);

    await tester.tap(find.byKey(const Key('language-mode-vi')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(MoreActionsSheet));
    expect(context.locale, const Locale('vi'));

    await tester.tap(find.byKey(const Key('language-mode-en')));
    await tester.pumpAndSettle();
    expect(context.locale, const Locale('en'));

    await tester.tap(find.byKey(const Key('language-mode-system')));
    await tester.pumpAndSettle();
    expect(context.locale, context.deviceLocale);
  });
```

Add `import 'package:easy_localization/easy_localization.dart';` to the test file for the `context.locale`/`context.deviceLocale` extensions.

- [ ] **Step 7: Run and verify**

Run: `flutter test --no-pub test/features/notes/presentation/more_actions_sheet_test.dart`
Expected: `+N: All tests passed!` where N is the previous count + 1.

- [ ] **Step 8: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add lib/features/notes/presentation/widgets/more_actions_sheet.dart test/features/notes/presentation/more_actions_sheet_test.dart assets/translations/en.json assets/translations/vi.json
git commit -m "feat(l10n): add Language row and picker to the More sheet"
```

---

## Task 21: Vietnamese smoke tests (Home, Editor, More)

**Files:**
- Create: `test/features/notes/presentation/vietnamese_smoke_test.dart`

**Interfaces:**
- Consumes: `wrapWithTestLocalization(..., locale: const Locale('vi'))` from Task 2; the real `vi.json` values from Task 19 (this test hardcodes the expected Vietnamese strings it asserts on, so keep it in sync with whatever Task 19 actually wrote for the 3 keys it checks).

- [ ] **Step 1: Write the test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_home_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/more_actions_sheet.dart';

import '../../../helpers/in_memory_note_repository.dart';
import '../../../support/localization_test_wrapper.dart';

void main() {
  testWidgets('Home renders Vietnamese chrome when locale is vi', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithTestLocalization(
        ProviderScope(
          overrides: [
            noteRepositoryProvider.overrideWithValue(
              InMemoryNoteRepository.seeded(const []),
            ),
          ],
          child: MaterialApp(
            theme: AuroraTheme.light(),
            home: const NotesHomePage(),
          ),
        ),
        locale: const Locale('vi'),
      ),
    );
    await tester.pumpAndSettle();

    // One representative string per Task 19's vi.json translation of
    // home.greetingMorning/home.greetingAfternoon/home.greetingEvening —
    // whichever branch fires depends on the wall-clock hour, so assert only
    // that no raw "home." key leaked through instead of a specific greeting.
    expect(find.textContaining('home.'), findsNothing);
  });

  testWidgets('More sheet renders Vietnamese chrome when locale is vi', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithTestLocalization(
        ProviderScope(
          overrides: [
            noteRepositoryProvider.overrideWithValue(
              InMemoryNoteRepository.seeded(const []),
            ),
          ],
          child: MaterialApp(
            theme: AuroraTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => MoreActionsSheet.show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
        locale: const Locale('vi'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Ngôn ngữ / Language'), findsOneWidget);
    expect(find.textContaining('more.'), findsNothing);
  });
}
```

Before finalizing, read `assets/translations/vi.json`'s actual `more.sectionAppearance`/`more.manageTags` values (written in Task 19) and add one or two `expect(find.text('<real Vietnamese value>'), findsOneWidget)` assertions per screen instead of relying solely on the `findsNothing` "no leaked key" check — the leaked-key check alone proves plumbing works but not that real Vietnamese text renders, which is what this smoke suite exists to prove per the spec's Testing strategy.

- [ ] **Step 2: Run it**

Run: `flutter test --no-pub test/features/notes/presentation/vietnamese_smoke_test.dart`
Expected: `+2: All tests passed!` (or more, once real-string assertions are added per the note above).

- [ ] **Step 3: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add test/features/notes/presentation/vietnamese_smoke_test.dart
git commit -m "test(l10n): add Vietnamese smoke tests for Home and More sheet"
```

---

## Task 22: Locale-aware date-formatting test

**Files:**
- Create: `test/features/notes/presentation/home_date_locale_test.dart`

- [ ] **Step 1: Write the test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_home_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';

import '../../../helpers/in_memory_note_repository.dart';
import '../../../support/localization_test_wrapper.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('vi');
  });

  testWidgets('Home header date renders with Vietnamese month/weekday names', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithTestLocalization(
        ProviderScope(
          overrides: [
            noteRepositoryProvider.overrideWithValue(
              InMemoryNoteRepository.seeded(const []),
            ),
          ],
          child: MaterialApp(
            theme: AuroraTheme.light(),
            home: const NotesHomePage(),
          ),
        ),
        locale: const Locale('vi'),
      ),
    );
    await tester.pumpAndSettle();

    // DateFormat('EEEE, MMMM d', 'vi') always renders a Vietnamese weekday
    // name starting with "Thứ" (Monday-Saturday) or the literal "Chủ Nhật"
    // (Sunday) — assert one of those substrings is present rather than a
    // single fixed date string, since the test's pass/fail must not depend
    // on which day it happens to run.
    final matches = find.byWidgetPredicate((widget) {
      if (widget is! Text || widget.data == null) return false;
      final text = widget.data!;
      return text.startsWith('Thứ') || text.startsWith('Chủ Nhật');
    });
    expect(matches, findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it**

Run: `flutter test --no-pub test/features/notes/presentation/home_date_locale_test.dart`
Expected: `+1: All tests passed!`

- [ ] **Step 3: GitNexus check and commit**

```bash
node .gitnexus/run.cjs detect-changes --scope all --repo .
git add test/features/notes/presentation/home_date_locale_test.dart
git commit -m "test(l10n): add locale-aware date-formatting test for the Home header"
```

---

## Task 23: Final full-suite gate

**Files:** none modified.

- [ ] **Step 1: Full serial suite**

Run: `flutter test --no-pub --concurrency=1`
Expected: all tests pass (previous 637 + Task 2's 2 + Task 20's 1 + Task 21's 2 + Task 22's 1, plus any extra assertions added along the way).

- [ ] **Step 2: Format and analyze**

Run: `dart format --output=none --set-exit-if-changed lib test`
Run: `flutter analyze --no-pub --fatal-infos --fatal-warnings`
Expected: both clean.

- [ ] **Step 3: Codegen drift check**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: no unexpected `.g.dart` changes (this feature adds no new `@riverpod`/`@JsonSerializable` annotations, so no drift is expected).

- [ ] **Step 4: GitNexus final comparison**

Run: `node .gitnexus/run.cjs detect-changes --scope compare --base-ref main --repo .`
Expected: risk LOW or NONE; investigate anything HIGH/CRITICAL/UNKNOWN before proceeding.

- [ ] **Step 5: Manual spot check**

Run the app (`flutter run -d chrome` or an available emulator/device), open More → Language → Tiếng Việt, confirm the whole UI switches, restart the app and confirm the choice persisted, then switch back to Hệ thống / System.

No commit for this task — it is a verification gate over commits already made in Tasks 1-22.

---

## Self-Review

**Spec coverage:**
- Objective (every user-facing string, system default + manual override) — Tasks 1-22 cover all presentation-layer files found via the grep sweep during plan authoring, plus `notification_service.dart`'s user-visible content; Task 20 delivers the override UI.
- Non-goals — respected: note content itself is never touched by any task; no third language added; Task 18 explicitly confirms `note_card.dart` (dead code) is out of scope rather than silently missed.
- Architecture decision (`easy_localization`) — Task 1/3.
- Locale selection behavior — Task 20 implements exactly the 3-option System/Tiếng Việt/English picker with `setLocale`/`resetLocale`, no new provider.
- Components touched — every file the spec names (`pubspec.yaml`, translation JSONs, `main.dart`, `MaterialApp`, More sheet, "every presentation-layer widget with a string literal", date formatting) has a task; the spec's file list was extended (not narrowed) by the grep-discovered widgets it didn't name individually (`note_metadata_sheet`, `note_filter_sheet`, `tag_manager_sheet`, `notes_state_view`, `notes_bottom_bar`, `library_segmented_control`, `glass_note_card`, `existing_note_route_page`, `notification_service`).
- Error handling (fallback to `en`, raw-key debug behavior) — Task 3 sets `fallbackLocale`; Task 19 Step 4 explicitly checks for leaked raw keys as its acceptance signal.
- Testing strategy — Task 2 builds the shared wrapper before any sweep task (a deliberate reordering from the spec's A→B→C→D narrative, justified in this plan's Architecture section: it keeps the suite green after every single task instead of red for the whole A-C span); Tasks 4-17 migrate existing tests one file at a time; Task 21 adds the Vietnamese smoke suite; Task 22 adds the locale-aware date test.
- Implementation sequencing table — mapped as: infra+sweep = Tasks 1, 3-18; language row = Task 20; vi.json authoring = Task 19; test harness = Tasks 2, 4-17 (folded into each sweep task rather than deferred, for the reason above), 21, 22.
- Acceptance criteria — every bullet has a corresponding task/step: no-raw-key check (Task 19 Step 4, Task 21), first-launch system locale (Task 3's `fallbackLocale`/`supportedLocales` wiring, exercised implicitly by every widget test's default `en` locale plus Task 21's explicit `vi` pump), Language picker switch/persist/revert (Task 20 Step 6 test), locale-aware dates (Task 22), full suite passing with only harness changes (Tasks 4-17's "same pass count" checks), `flutter analyze`/`build_runner` clean (Task 23).

**Placeholder scan:** no "TBD"/"TODO"/"handle appropriately" left in any step; the one place this plan explicitly declines to hardcode content is Task 19 Step 2 (the actual Vietnamese translation text) and Task 21's real-string assertions — both are flagged as content-authorship the executor must produce from Task 19's own output, not vague instructions, and both name exactly which keys/files are involved.

**Type consistency:** `_themeLabel`/`_transferError`/`_transferProgress`/`_transferSuccess` all gain a `BuildContext context` first parameter in Task 4 and their 3-4 call sites are called out for updating in the same task; `_LanguageChoiceRow` (Task 20) mirrors `_ThemeChoiceRow`'s exact constructor shape (`selected`/`enabled`/`onSelected` + a value type, `Locale?` in place of `ThemeMode`); `wrapWithTestLocalization`/`pumpLocalized` (Task 2) are the only two exported names from the test-support file and every later task's "wrap the pumpWidget call" step uses `wrapWithTestLocalization` consistently (not a second, differently-named helper).

---

**Plan complete and saved to `docs/superpowers/plans/2026-09-06-vietnamese-localization.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
