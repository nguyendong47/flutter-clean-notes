# Flutter Clean Notes — Aurora Glass Redesign

| Metadata | Value |
| --- | --- |
| Approved | 2026-08-17 |
| Status | Approved design contract |
| Canonical role | Product, interaction, visual, accessibility, and acceptance contract for the Aurora redesign |
| Update rule | Change approved requirements or the task-to-design-surface mapping only through an explicit design decision; record operational status in the Project Sync |

Operational status and evidence live in the [Project Sync / Handoff](../handoff.md). Ordered implementation details live in the [Aurora implementation plan](../plans/2026-08-17-aurora-glass-redesign.md).

This specification owns stable product, interaction, visual, accessibility, and
acceptance requirements. The implementation plan is a historical recipe; the
Project Sync owns volatile progress and evidence. Technical data disclosure
lives in [Privacy and Data Flow](../../privacy.md), identity assets live in
[Branding](../../branding.md), repeatable checks live in [QA](../../qa.md), and
production gates live in [Release readiness](../../release.md).

## Implementation mapping

| Task | Design surface |
| --- | --- |
| 0 | Clean Flutter baseline |
| 1 | Aurora theme, background, and glass primitives |
| 2 | Reliable all-status note collections and mutation state |
| 3 | Notes home, glass note cards, masonry, and stable states |
| 4 | Focused Search experience |
| 5 | Archive and Trash Library |
| 6 | More sheet, tag management, and safe transfer |
| 7 | Mobile navigation shell and deep links |
| 8 | Distraction-free editor |
| 9 | Cross-screen accessibility, responsive, visual, and regression pass |

This stable table maps planned tasks to design surfaces; it does not record completion state. Follow the linked plan for implementation instructions and the Project Sync for the latest checkpoint.

## Objective

Redesign Flutter Clean Notes as a beautiful, mobile-first productivity app using an Aurora Glass visual language. The redesign covers the complete interface and interaction flow while preserving every existing capability: note creation and editing, Markdown, linked notes, tags, colors, pinning, reminders, search, sorting, archive, trash, restore, deletion, theme selection, and import/export.

The result must feel premium without sacrificing legibility, responsiveness, accessibility, or offline reliability. Light and dark themes are equal design targets.

## Product principles

1. Content remains the visual priority. Glass effects frame notes but never compete with them.
2. Primary actions stay within comfortable thumb reach on mobile.
3. Common actions are immediately discoverable; secondary utilities are progressively disclosed.
4. Every asynchronous action communicates loading, success, and failure without destabilizing the page.
5. Motion explains spatial relationships and state changes. It is brief, optional, and never decorative noise.
6. Existing domain, repository, database, and notification behavior remains intact unless a presentation flow requires a narrowly scoped correction.

## Visual system

### Aurora Glass language

The interface uses soft indigo, lilac, and mint light fields behind restrained frosted surfaces. Dark mode translates those fields into deep navy, violet, and teal. The visual hierarchy comes from opacity, blur, borders, and tonal contrast rather than heavy shadows.

Glass is appropriate for navigation, search, note cards, filters, dialogs, and bottom sheets. Long-form editor surfaces use a more opaque treatment so reading and writing remain comfortable. Glass must not be stacked repeatedly; nested surfaces use solid or near-solid fills.

### Color tokens

The exact Flutter `ColorScheme` values may be contrast-adjusted during implementation, but their roles are fixed:

| Role | Light direction | Dark direction | Purpose |
| --- | --- | --- | --- |
| Primary | Indigo | Luminous violet-indigo | Main actions, active navigation, focus |
| Secondary | Mint-teal | Cyan-teal | Supporting highlights and tags |
| Background field | Mist blue, lilac, mint | Navy, violet, teal | Aurora backdrop |
| Glass surface | Translucent white | Translucent blue-black | Cards, navigation, sheets |
| Text | Ink navy | Near-white | Primary content |
| Muted text | Slate | Blue-gray | Metadata and supporting copy |
| Destructive | Accessible red | Accessible coral-red | Permanent deletion and errors |

Text and icon contrast must meet at least 4.5:1 for normal text and 3:1 for large text and non-text controls. Transparency is reduced whenever a background field would compromise those ratios.

### Surface and shape tokens

- Backdrop blur: 16–20 logical pixels on major glass surfaces.
- Glass border: one logical pixel with theme-aware luminosity.
- Control radius: 16 logical pixels.
- Note-card radius: 20 logical pixels.
- Major sheet and navigation radius: 28 logical pixels.
- Spacing: an 8-point base grid with 4-point increments for compact alignment.
- Shadows: one soft ambient shadow per elevated surface; no stacked hard shadows.

### Typography

Use Flutter's native platform typography for speed, offline reliability, and a familiar mobile feel. Hierarchy is established through size, weight, line height, and spacing:

- Page heading: 28/32, weight 700.
- Section heading: 18/24, weight 650–700.
- Card title: 16/22, weight 600.
- Body and editor text: 16/24, weight 400.
- Supporting text: 14/20, weight 400–500.
- Labels and metadata: 12/16, weight 500–600.

## Information architecture

The mobile shell uses a floating bottom navigation bar with four destinations:

1. **Notes** — the daily home view.
2. **Search** — focused discovery and filtering.
3. **Library** — archived and trashed notes.
4. **More** — secondary management and application settings.

A raised central **New note** control sits between Search and Library. It opens the editor as a primary action and is not a fifth navigation destination.

The bottom navigation stays within safe areas and never obscures scrollable content. `go_router` remains responsible for navigation and deep links. Reselecting the current shell destination preserves that branch's query, filters, nested location, and scroll state. Back behavior follows platform expectations: the editor returns to its source view, nested sheets dismiss before routes, and a clean editor preserves the native iOS edge-back gesture. A dirty editor synchronously vetoes route pop and requires an explicit discard decision.

## Screen designs

### Notes home

The home screen contains:

- A compact greeting/date header and theme control.
- A prominent glass search field that enters the focused Search destination.
- Horizontally scrollable tag chips with clear selected states.
- A pinned-notes section when pinned content exists.
- Remaining notes in a mobile masonry layout that becomes one column at very narrow widths.
- The floating bottom navigation and central New note action.

Each note card shows title, a short content preview, relevant tags, updated/created metadata, reminder status, and pin state. Contextual actions remain available without covering the card's primary tap target. Note color influences a restrained tint rather than filling the entire card with saturated color.

### Search

Search is a dedicated, focused experience rather than a crowded home-screen mode. It provides:

- Immediate focus and live local results.
- Query matching across title, content, and tags.
- Tag and sort filters exposed as chips or a compact filter sheet.
- Helpful empty states that suggest clearing filters or trying another term.
- Clear separation between no notes, no query, and no matching results.

Search state continues to use Riverpod and the existing local notes collection. No remote search service is introduced.

### Library

Library uses a segmented control for **Archived** and **Trash**. Archive supports restore and trash actions. Trash supports restore and permanent deletion, with permanent deletion always confirmed. Empty states explain the destination and provide a useful next action.

Automatic trash cleanup remains a domain capability; surfacing or scheduling it must not silently remove notes without the product's documented retention rule.

### More sheet

The More destination opens a major glass bottom sheet rather than a full navigation screen. It groups:

- Light, dark, and system theme selection.
- Tag management.
- JSON backup and import.
- Text and Markdown export/share.

Each row includes an icon, visible label, short supporting description when needed, and semantic accessibility information.

### Note editor

The editor is a distraction-free full-screen route with:

- A calm, more opaque writing surface.
- A compact translucent top bar with Back, Preview, and Done actions.
- A title field followed by the body editor.
- A formatting bar positioned above the keyboard when editing.
- A metadata action that opens a sheet for color, tags, and reminders.
- Markdown preview and linked-note navigation using existing behavior.

The Done action awaits persistence before closing. While saving, it is disabled and displays progress. A failed save keeps the editor open, preserves typed content, and presents an inline error with Retry. Empty notes remain blocked with a nearby validation message.

Unsaved-change detection compares one semantic snapshot containing title, body,
color, tags in order, and reminder. Top-bar Back, system Back, and direct route
pop all use the same guard. When dirty, the editor offers **Discard changes** and
the autofocus safe default **Keep editing**; no exit occurs until discard is
explicit. When clean, normal platform navigation remains unobstructed, including
the native iOS edge-back gesture.

## Component boundaries

The existing large presentation files should be divided into focused widgets without changing domain boundaries. Proposed UI units are:

- `AuroraBackground` — theme-aware aurora field and performance fallback.
- `GlassSurface` — centralized blur, opacity, border, shadow, and fallback behavior.
- `NotesShell` — bottom navigation, central creation action, safe-area handling, and destination switching.
- `NotesHomeView` — greeting, tags, pinned notes, and note collection.
- `NotesSearchView` — search input, filter controls, results, and empty states.
- `NotesLibraryView` — archive/trash segmented content.
- `MoreActionsSheet` — theme, tags, import, and export actions.
- `GlassNoteCard` — note summary and contextual actions.
- `NoteEditorPage` — editor orchestration.
- `EditorFormattingBar` and `NoteMetadataSheet` — focused editor controls.
- Reusable loading, empty, and error-state components.

Each unit receives data and callbacks through a narrow public interface. Feature wiring remains in Riverpod providers, and the domain layer continues to depend only on repository abstractions.

## State and data flow

`NotesNotifier` remains the source of truth for persisted note collections. Existing use cases and `NoteRepository` continue to mediate database changes. Small presentation-only providers may be added for shell destination, search/filter state, editor preview state, and temporary sheet selections.

The primary flow remains:

```text
Widget interaction
  → Riverpod notifier/provider
  → domain use case
  → NoteRepository abstraction
  → NoteRepositoryImpl
  → local SQLite datasource
  → refreshed provider state
  → stable UI update
```

Presentation state must not leak into domain entities.

The persisted theme is part of startup, not a post-frame correction. Bootstrap
creates one `ProviderContainer`, awaits `appThemeProvider.future`, and gives that
same container to `UncontrolledProviderScope`. The provider stays alive, and a
missing, invalid, or failed preference read resolves to `ThemeMode.system`; the
first rendered frame therefore uses the resolved mode without a light/dark
flash.

## Content, transfer, and notification boundaries

- Markdown preview is pinned to `flutter_markdown_plus 1.0.12`. Its
  `imageBuilder` renders an inert accessible placeholder for every authored
  image. Only internal `note://` links are handled; network, file, data, and
  other external URI schemes are neither opened nor fetched from note content.
- Text and Markdown exports include Active and Archive notes and exclude Trash.
  JSON backup includes Active, Archive, and Trash. The More sheet discloses that
  scope before platform work begins. Import validates the typed JSON boundary
  and appends every accepted entry as an Active copy with a fresh ID and cleared
  reminder; it never replaces the existing collection.
- `NoteExportFormatter` owns validated `Note` encoding/decoding,
  `NotesTransferGateway` owns picker/share platform types, the Riverpod transfer
  controller owns operation state and status filtering, and `ImportNotes` owns
  normalization plus the repository transaction. Platform values do not enter
  domain entities.
- Android reminder notifications use the dedicated monochrome
  `ic_stat_clean_notes` small icon retained by `res/raw/keep.xml`, not a launcher
  asset. Permanent deletion commits the database removal first. If reminder
  cancellation then fails, the deleted note stays deleted and only a sanitized,
  coalesced cancellation retry is offered; retry never recreates the note or
  repeats the database delete.

## Loading, feedback, and errors

- Initial note loading uses stable skeleton cards with reserved layout space.
- Item actions show progress locally where possible instead of replacing the entire collection with a spinner.
- Archive, trash, restore, and pin transitions provide immediate feedback.
- Reversible archive and trash actions offer Undo through a floating message.
- Permanent deletion uses a confirmation dialog with explicit destructive wording.
- Import validates file selection and JSON shape, reports malformed backups clearly, and never discards existing notes implicitly.
- Export and share actions report failures without blocking navigation.
- Editor save failures preserve unsaved text and keep the route open.

## Motion

Motion durations generally stay between 180 and 260 milliseconds. Navigation selection, filter changes, note insertion/removal, sheets, and contextual menus use easing appropriate to their spatial relationship. Large list-wide entrance choreography is avoided after initial load.

Reduced-motion preferences disable non-essential translation and scale effects. Blur and gradients must not animate continuously. Motion never delays input or persistence.

## Accessibility and responsive behavior

- Interactive controls provide at least a 44×44 logical-pixel target, preferably 48×48.
- Icon-only controls receive tooltips and semantic labels.
- Focus order follows visual order, and focus indicators remain visible.
- Selected tags, destinations, archive state, and errors are not communicated by color alone.
- Text scaling is supported without clipped controls or horizontal page scrolling.
- The layout is designed at compact mobile widths first and verified at 360, 375, and 390 logical pixels.
- At tablet widths, content gains breathing room and additional columns without changing navigation concepts.
- Desktop remains usable through centered maximum-width content and pointer/keyboard states, but mobile is the primary target.
- Aurora fields and glass opacity adapt for high contrast and constrained rendering conditions.

## Testing strategy

Widget tests should cover public behavior rather than implementation details:

1. Bottom navigation switches between Notes, Search, Library, and More.
2. New note opens the editor from the central action.
3. Editor validation blocks an empty save.
4. Successful saves wait for completion before closing.
5. Failed saves preserve content and offer retry.
6. Search and tag filters produce correct results and useful empty states.
7. Archive, trash, restore, Undo, and permanent-delete confirmation behave correctly.
8. Light and dark themes render the same hierarchy and semantic states.
9. Compact widths and large text scales do not overflow.
10. Important icon buttons and navigation elements expose semantic labels.
11. The first frame uses the persisted theme, with system fallback on read error.
12. Every dirty editor field triggers one discard guard while a clean iOS edge
    swipe remains native.
13. Markdown images stay inert and non-`note://` links cannot cross the app
    boundary.
14. Text/Markdown, JSON backup, and import use their documented status scopes.
15. Reminder cancellation retry is cancellation-only and overlap is coalesced.

### Implementation verification gate

At every task boundary, completion requires all of the following:

- Task-focused tests, the existing notification-service tests, and the full
  host-side `flutter test --concurrency=1` suite pass. Platform integration
  smoke tests remain separate device gates owned by QA.
- The tracked `pubspec.lock` resolves unchanged with
  `flutter pub get --enforce-lockfile`; plain `flutter pub get` is reserved for
  an intentional dependency update whose lockfile diff is reviewed and
  committed.
- `flutter analyze` passes, and annotated Riverpod changes include regenerated and reviewed `.g.dart` output.
- Presentation, domain, repository, SQLite, notification, and routing boundaries remain intact unless the plan records a narrowly scoped correction with regression coverage.
- Every code-symbol edit has the repository-required GitNexus impact check, and the task commit has staged change detection.
- High-value light/dark and responsive states are inspected through stable golden tests when practical, or through widget assertions plus rendered browser/device inspection.

## Scope boundaries

This redesign does not introduce accounts, cloud synchronization, collaboration, remote search, new database entities, or a new state-management framework. It does not replace Riverpod, `go_router`, Clean Architecture, or SQLite. Any discovered behavioral defect that blocks the approved interactions must be reported and handled as a narrowly scoped fix with tests.

## Acceptance criteria

- All current product features remain accessible in the redesigned interface.
- The home, search, library, more, and editor experiences match the Aurora Glass system.
- Light and dark themes are equally complete and readable.
- Mobile interaction is comfortable at common compact widths.
- Navigation and system back behavior are predictable.
- Async actions provide loading, success, failure, and retry/undo feedback where applicable.
- Accessibility targets, semantics, contrast, reduced motion, and text scaling are addressed.
