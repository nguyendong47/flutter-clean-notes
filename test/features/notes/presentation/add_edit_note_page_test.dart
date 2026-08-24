import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/services/reminder_coordinator.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/add_edit_note_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_reminder_gateway_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/editor_formatting_bar.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fake_note_reminder_gateway.dart';
import '../../../helpers/in_memory_note_repository.dart';
import '../../../helpers/note_fixtures.dart';
import '../../../helpers/repository_snooze_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('background snooze survives an unrelated editor save', (
    tester,
  ) async {
    final original = sampleNote.copyWith(
      reminder: DateTime.utc(2030, 1, 15, 11),
    );
    final snoozedAt = DateTime.utc(2030, 1, 15, 11, 15);
    final repository = InMemoryNoteRepository.seeded([original]);
    final coordinator = RepositorySnoozeCoordinator(
      repository: repository,
      snoozedAt: snoozedAt,
    );
    final harness = await _pumpEditor(
      tester,
      note: original,
      repository: repository,
      coordinator: coordinator,
    );

    await harness.container
        .read(notesProvider.notifier)
        .snoozeReminderFromNotification(
          noteId: original.id!,
          expectedGeneration: 17,
          delayMinutes: 15,
        );
    await tester.pump();
    await tester.tap(find.byKey(const Key('editor-metadata-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('11:15 AM'), findsOneWidget);
    await tester.tap(find.byKey(const Key('metadata-apply')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('editor-title-field')),
      'Title edited after snooze',
    );
    await tester.tap(find.byKey(const Key('editor-done-button')));
    await tester.pumpAndSettle();

    expect(repository.notes.single.title, 'Title edited after snooze');
    expect(repository.notes.single.reminder, snoozedAt);
    expect(harness.closeCount.value, 1);
  });

  testWidgets('background snooze alone does not dirty the editor', (
    tester,
  ) async {
    final original = sampleNote.copyWith(
      reminder: DateTime.utc(2030, 1, 15, 11),
    );
    final repository = InMemoryNoteRepository.seeded([original]);
    final harness = await _pumpEditor(
      tester,
      note: original,
      repository: repository,
      coordinator: RepositorySnoozeCoordinator(
        repository: repository,
        snoozedAt: DateTime.utc(2030, 1, 15, 11, 15),
      ),
    );

    await harness.container
        .read(notesProvider.notifier)
        .snoozeReminderFromNotification(
          noteId: original.id!,
          expectedGeneration: 17,
          delayMinutes: 15,
        );
    await tester.pump();
    await tester.tap(find.byKey(const Key('editor-back-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('discard-changes-dialog')), findsNothing);
    expect(harness.closeCount.value, 1);
  });

  testWidgets('local reminder edit wins over a later background snooze', (
    tester,
  ) async {
    final original = sampleNote.copyWith(
      reminder: DateTime.utc(2030, 1, 15, 11),
    );
    final repository = InMemoryNoteRepository.seeded([original]);
    final harness = await _pumpEditor(
      tester,
      note: original,
      repository: repository,
      coordinator: RepositorySnoozeCoordinator(
        repository: repository,
        snoozedAt: DateTime.utc(2030, 1, 15, 11, 15),
      ),
      now: () => DateTime.utc(2030, 1, 15, 10),
    );
    await tester.tap(find.byKey(const Key('editor-metadata-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('metadata-clear-reminder')));
    await tester.tap(find.byKey(const Key('metadata-apply')));
    await tester.pumpAndSettle();

    await harness.container
        .read(notesProvider.notifier)
        .snoozeReminderFromNotification(
          noteId: original.id!,
          expectedGeneration: 17,
          delayMinutes: 15,
        );
    await tester.pump();
    await tester.tap(find.byKey(const Key('editor-metadata-button')));
    await tester.pumpAndSettle();
    expect(find.text('Add reminder'), findsOneWidget);
    await tester.tap(find.byKey(const Key('metadata-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor-done-button')));
    await tester.pumpAndSettle();

    expect(repository.notes.single.reminder, isNull);
    expect(harness.closeCount.value, 1);
  });

  testWidgets('unchanged open metadata sheet preserves a background snooze', (
    tester,
  ) async {
    final original = sampleNote.copyWith(
      reminder: DateTime.utc(2030, 1, 15, 11),
    );
    final snoozedAt = DateTime.utc(2030, 1, 15, 11, 15);
    final repository = InMemoryNoteRepository.seeded([original]);
    final harness = await _pumpEditor(
      tester,
      note: original,
      repository: repository,
      coordinator: RepositorySnoozeCoordinator(
        repository: repository,
        snoozedAt: snoozedAt,
      ),
    );
    await tester.tap(find.byKey(const Key('editor-metadata-button')));
    await tester.pumpAndSettle();

    await harness.container
        .read(notesProvider.notifier)
        .snoozeReminderFromNotification(
          noteId: original.id!,
          expectedGeneration: 17,
          delayMinutes: 15,
        );
    await tester.pump();
    await tester.tap(find.byKey(const Key('metadata-apply')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('editor-title-field')),
      'Edited after sheet closed',
    );
    await tester.tap(find.byKey(const Key('editor-done-button')));
    await tester.pumpAndSettle();

    expect(repository.notes.single.title, 'Edited after sheet closed');
    expect(repository.notes.single.reminder, snoozedAt);
    expect(harness.closeCount.value, 1);
  });

  testWidgets('empty save shows a live inline error and focuses Title', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = await _pumpEditor(tester);

    await tester.tap(find.byKey(const Key('editor-preview-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('editor-preview')), findsOneWidget);

    await tester.tap(find.byKey(const Key('editor-done-button')));
    await tester.pump();

    final validation = find.byKey(const Key('editor-validation'));
    expect(validation, findsOneWidget);
    expect(find.text('Add a title or some content'), findsOneWidget);
    expect(
      tester.getSemantics(validation).flagsCollection.isLiveRegion,
      isTrue,
    );
    expect(find.byKey(const Key('editor-body-field')), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const Key('editor-title-field'))).label,
      contains('Title'),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('editor-body-field'))).label,
      contains('Note content'),
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('editor-title-field')))
          .focusNode
          ?.hasFocus,
      isTrue,
    );
    expect(harness.repository.addCalls, 0);
    expect(harness.closeCount.value, 0);
    semantics.dispose();
  });

  testWidgets('expired reminder error is actionable and refocuses Details', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final initialNow = DateTime.utc(2030, 1, 15, 10, 15);
    var clockReads = 0;
    final repository = _RecordingRepository(const []);
    final harness = await _pumpEditor(
      tester,
      note: Note(
        title: 'Expires during save',
        content: 'Keep this draft open',
        color: 0,
        createdAt: DateTime.utc(2030, 1, 15),
        reminder: initialNow.add(const Duration(minutes: 1)),
      ),
      repository: repository,
      now: () {
        clockReads += 1;
        return clockReads == 1
            ? initialNow
            : initialNow.add(const Duration(minutes: 2));
      },
    );
    await tester.enterText(
      find.byKey(const Key('editor-body-field')),
      'Keep this exact dirty draft',
    );

    await tester.tap(find.byKey(const Key('editor-done-button')));
    await tester.pumpAndSettle();

    const reminderError = 'Open Note details to choose a future reminder.';
    final validation = find.byKey(const Key('editor-validation'));
    expect(find.text(reminderError), findsOneWidget);
    expect(validation, findsOneWidget);
    expect(
      tester.getSemantics(validation).flagsCollection.isLiveRegion,
      isTrue,
    );
    final metadataButton = find.byKey(const Key('editor-metadata-button'));
    expect(
      tester.widget<IconButton>(metadataButton).focusNode?.hasFocus,
      isTrue,
    );
    expect(
      tester.getSemantics(metadataButton).flagsCollection.isFocused,
      Tristate.isTrue,
    );
    expect(find.byType(AddEditNotePage), findsOneWidget);
    expect(repository.addCalls, 0);
    expect(harness.gateway.events, isEmpty);
    expect(harness.closeCount.value, 0);
    expect(_text(tester, 'editor-body-field'), 'Keep this exact dirty draft');

    await tester.tap(find.byKey(const Key('editor-back-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discard-changes-dialog')), findsOneWidget);
    expect(harness.closeCount.value, 0);
    await tester.tap(find.byKey(const Key('keep-editing-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('editor-metadata-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('metadata-clear-reminder')));
    final apply = find.byKey(const Key('metadata-apply'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor-done-button')));
    await tester.pumpAndSettle();

    expect(repository.addCalls, 1);
    expect(repository.notes.single.content, 'Keep this exact dirty draft');
    expect(repository.notes.single.reminder, isNull);
    expect(harness.closeCount.value, 1);
    semantics.dispose();
  });

  testWidgets('past reminder precheck is live and refocuses Details', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var now = DateTime(2030, 1, 15, 10, 15);
    final repository = _RecordingRepository(const []);
    final harness = await _pumpEditor(
      tester,
      note: Note(
        title: 'Past reminder',
        content: 'Unsaved draft',
        color: 0,
        createdAt: DateTime(2030, 1, 15),
      ),
      repository: repository,
      now: () => now,
      size: const Size(320, 640),
      disableAnimations: true,
    );

    await tester.tap(find.byKey(const Key('editor-metadata-button')));
    await tester.pumpAndSettle();
    final reminderButton = find.byKey(const Key('metadata-reminder-button'));
    await tester.ensureVisible(reminderButton);
    await tester.tap(reminderButton);
    await tester.pumpAndSettle();
    Navigator.of(
      tester.element(find.byType(DatePickerDialog)),
    ).pop(DateTime(2030, 1, 15));
    await tester.pumpAndSettle();
    Navigator.of(
      tester.element(find.byType(TimePickerDialog)),
    ).pop(const TimeOfDay(hour: 10, minute: 16));
    await tester.pumpAndSettle();
    final apply = find.byKey(const Key('metadata-apply'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    harness.textScaler.value = const TextScaler.linear(3);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final body = find.byKey(const Key('editor-body-field'));
    tester.widget<TextField>(body).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(body).focusNode!.hasFocus, isTrue);
    final shortScroll = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const Key('editor-short-layout-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    shortScroll.jumpTo(shortScroll.maxScrollExtent);
    await tester.pump();
    expect(
      shortScroll.pixels,
      moreOrLessEquals(shortScroll.maxScrollExtent),
      reason: 'This regression must begin with the focused body revealed',
    );
    now = now.add(const Duration(minutes: 2));
    final save = tester
        .widget<TextButton>(find.byKey(const Key('editor-done-button')))
        .onPressed;
    expect(save, isNotNull);
    save!();
    expect(tester.widget<TextField>(body).focusNode!.hasFocus, isTrue);
    await tester.pumpAndSettle();

    const reminderError = 'Open Note details to choose a future reminder.';
    final validation = find.byKey(const Key('editor-validation'));
    expect(find.text(reminderError), findsOneWidget);
    expect(
      tester.getSemantics(validation).flagsCollection.isLiveRegion,
      isTrue,
    );
    final metadataButton = find.byKey(const Key('editor-metadata-button'));
    expect(
      tester.widget<IconButton>(metadataButton).focusNode?.hasFocus,
      isTrue,
    );
    expect(
      tester.getSemantics(metadataButton).flagsCollection.isFocused,
      Tristate.isTrue,
    );
    final viewport = find.byKey(const Key('editor-short-layout-scroll'));
    expect(
      shortScroll.pixels,
      lessThan(shortScroll.maxScrollExtent),
      reason: 'Reminder feedback must override the pending body reveal',
    );
    expect(
      tester.getRect(validation).intersect(tester.getRect(viewport)).height,
      greaterThan(0),
      reason: 'The actionable live error must remain visibly discoverable',
    );
    expect(repository.addCalls, 0);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('edit save preserves identity, state, pin, color, and metadata', (
    tester,
  ) async {
    final existing = sampleNote.copyWith(status: NoteStatus.archived);
    final repository = _RecordingRepository([existing]);
    final harness = await _pumpEditor(
      tester,
      note: existing,
      repository: repository,
    );
    await tester.enterText(
      find.byKey(const Key('editor-title-field')),
      'Edited title',
    );
    await tester.enterText(
      find.byKey(const Key('editor-body-field')),
      'Edited body',
    );

    await tester.tap(find.byKey(const Key('editor-done-button')));
    await tester.pumpAndSettle();

    final stored = repository.notes.single;
    expect(stored.id, existing.id);
    expect(stored.createdAt, existing.createdAt);
    expect(stored.status, NoteStatus.archived);
    expect(stored.isPinned, isTrue);
    expect(stored.color, existing.color);
    expect(stored.tags, existing.tags);
    expect(stored.reminder, existing.reminder);
    expect(stored.title, 'Edited title');
    expect(stored.content, 'Edited body');
    expect(harness.closeCount.value, 1);
  });

  testWidgets(
    'unsupported gateway hides scheduling but clears a saved reminder and saves metadata',
    (tester) async {
      final existing = sampleNote.copyWith(
        reminder: DateTime.utc(2030, 1, 15, 10, 30),
      );
      final repository = _RecordingRepository([existing]);
      final gateway = FakeNoteReminderGateway(supportsScheduling: false);
      final harness = await _pumpEditor(
        tester,
        note: existing,
        repository: repository,
        gateway: gateway,
        now: () => DateTime.utc(2030, 1, 15, 10),
      );

      await tester.tap(find.byKey(const Key('editor-metadata-button')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Reminders aren\u2019t available on this device.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('metadata-reminder-button')), findsNothing);
      expect(find.byKey(const Key('metadata-clear-reminder')), findsOneWidget);

      await tester.tap(
        find.byKey(
          ValueKey('metadata-tint-${Colors.blue.shade100.toARGB32()}'),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('metadata-tag-field')),
        'offline',
      );
      await tester.tap(find.byKey(const Key('metadata-add-tag')));
      await tester.tap(find.byKey(const Key('metadata-clear-reminder')));
      final apply = find.byKey(const Key('metadata-apply'));
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('editor-done-button')));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, 1);
      expect(repository.notes.single.color, Colors.blue.shade100.toARGB32());
      expect(repository.notes.single.tags, contains('offline'));
      expect(repository.notes.single.reminder, isNull);
      expect(gateway.scheduled, isEmpty);
      expect(gateway.cancelled, [existing.id]);
      expect(find.byKey(const Key('editor-save-error')), findsNothing);
      expect(find.byKey(const Key('editor-retry-button')), findsNothing);
      expect(harness.closeCount.value, 1);
    },
  );

  testWidgets('populated fields expose exact programmatic names', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpEditor(tester, note: sampleNote);

    expect(
      tester.getSemantics(find.byKey(const Key('editor-title-field'))).label,
      'Title',
    );
    expect(
      tester.getSemantics(find.byKey(const Key('editor-body-field'))).label,
      'Note content',
    );
    semantics.dispose();
  });

  testWidgets(
    'dirty new note top Back keeps the exact draft when Keep editing is chosen',
    (tester) async {
      // Mutation caught: closing a dirty editor without waiting for an
      // explicit discard decision.
      final semantics = tester.ensureSemantics();
      final harness = await _pumpEditor(tester);
      const title = 'Unpublished title';
      const body = 'Exact body with trailing space ';
      await tester.enterText(
        find.byKey(const Key('editor-title-field')),
        title,
      );
      await tester.enterText(find.byKey(const Key('editor-body-field')), body);

      await tester.tap(find.byKey(const Key('editor-back-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('discard-changes-dialog')), findsOneWidget);
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.text('Your unsaved changes will be lost.'), findsOneWidget);
      final keepEditing = find.byKey(const Key('keep-editing-button'));
      expect(tester.widget<FilledButton>(keepEditing).autofocus, isTrue);
      expect(tester.getSemantics(keepEditing).label, 'Keep editing');
      expect(
        tester
            .getSemantics(find.byKey(const Key('discard-changes-button')))
            .label,
        'Discard changes',
      );
      expect(harness.closeCount.value, 0);

      await tester.tap(keepEditing);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('discard-changes-dialog')), findsNothing);
      expect(_text(tester, 'editor-title-field'), title);
      expect(_text(tester, 'editor-body-field'), body);
      expect(harness.closeCount.value, 0);
      semantics.dispose();
    },
  );

  testWidgets(
    'dirty existing note system Back closes only after Discard changes',
    (tester) async {
      // Mutation caught: allowing PopScope to pop a changed existing note.
      final repository = _RecordingRepository([sampleNote]);
      final harness = await _pumpEditor(
        tester,
        note: sampleNote,
        repository: repository,
      );
      await tester.enterText(
        find.byKey(const Key('editor-body-field')),
        'Unsaved replacement body',
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('discard-changes-dialog')), findsOneWidget);
      expect(harness.closeCount.value, 0);
      expect(repository.updateCalls, 0);

      await tester.tap(find.byKey(const Key('discard-changes-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('discard-changes-dialog')), findsNothing);
      expect(harness.closeCount.value, 1);
      expect(repository.updateCalls, 0);
      expect(repository.notes.single.content, sampleNote.content);
    },
  );

  for (final metadataChange in _MetadataChange.values) {
    testWidgets(
      '${metadataChange.name} metadata alone requires discard confirmation',
      (tester) async {
        // Mutation caught: omitting one persisted metadata field from the
        // editor's semantic dirty snapshot.
        final harness = await _pumpEditor(tester, note: sampleNote);
        await _applyMetadataChange(tester, metadataChange);

        await tester.tap(find.byKey(const Key('editor-back-button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('discard-changes-dialog')), findsOneWidget);
        expect(harness.closeCount.value, 0);
        await tester.tap(find.byKey(const Key('keep-editing-button')));
        await tester.pumpAndSettle();
        expect(harness.closeCount.value, 0);
      },
    );
  }

  testWidgets('duplicate close and discard actions resolve exactly once', (
    tester,
  ) async {
    // Mutation caught: racing close callbacks creating stacked dialogs or
    // invoking the owning route's close callback more than once.
    final harness = await _pumpEditor(tester);
    await tester.enterText(
      find.byKey(const Key('editor-title-field')),
      'One close only',
    );
    final requestClose = tester
        .widget<BackButton>(find.byKey(const Key('editor-back-button')))
        .onPressed!;

    requestClose();
    requestClose();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('discard-changes-dialog')), findsOneWidget);
    final discard = tester
        .widget<TextButton>(find.byKey(const Key('discard-changes-button')))
        .onPressed!;
    discard();
    discard();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('discard-changes-dialog')), findsNothing);
    expect(harness.closeCount.value, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reverted text is clean and closes without a dialog', (
    tester,
  ) async {
    // Mutation caught: latching dirty state after the draft again equals its
    // initial semantic snapshot.
    final harness = await _pumpEditor(tester, note: sampleNote);
    final title = find.byKey(const Key('editor-title-field'));
    await tester.enterText(title, 'Temporary title');
    await tester.enterText(title, sampleNote.title);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('discard-changes-dialog')), findsNothing);
    expect(harness.closeCount.value, 1);
  });

  testWidgets(
    'compact scaled editor presents one usable unsaved-changes dialog',
    (tester) async {
      // Mutation caught: a custom dialog that overflows or loses its safe
      // default action under mobile accessibility scaling.
      final harness = await _pumpEditor(
        tester,
        size: const Size(320, 640),
        textScaler: const TextScaler.linear(2),
        disableAnimations: true,
      );
      await tester.enterText(
        find.byKey(const Key('editor-body-field')),
        'Scaled draft',
      );

      await tester.tap(find.byKey(const Key('editor-back-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('discard-changes-dialog')), findsOneWidget);
      expect(
        find.byKey(const Key('keep-editing-button')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('discard-changes-button')).hitTestable(),
        findsOneWidget,
      );
      expect(harness.closeCount.value, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('save disables every close path and waits for persistence', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = _DeferredAddRepository();
    final harness = await _pumpEditor(tester, repository: repository);
    await tester.enterText(
      find.byKey(const Key('editor-title-field')),
      'Wait for me',
    );
    await tester.enterText(
      find.byKey(const Key('editor-body-field')),
      'Exact body while saving',
    );

    await tester.tap(find.byKey(const Key('editor-done-button')));
    await repository.entered.future;
    await tester.pump();

    expect(find.byKey(const Key('editor-save-progress')), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('editor-done-button')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<BackButton>(find.byKey(const Key('editor-back-button')))
          .onPressed,
      isNull,
    );
    for (final key in const [
      'editor-preview-toggle',
      'editor-metadata-button',
    ]) {
      expect(tester.widget<IconButton>(find.byKey(Key(key))).onPressed, isNull);
    }
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('editor-title-field')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('editor-body-field')))
          .enabled,
      isFalse,
    );
    final formattingScroll = find.descendant(
      of: find.byKey(const Key('editor-formatting-scroll')),
      matching: find.byType(Scrollable),
    );
    for (final format in const [
      (key: 'bold', buttonType: IconButton),
      (key: 'italic', buttonType: IconButton),
      (key: 'strike', buttonType: IconButton),
      (key: 'code', buttonType: IconButton),
      (key: 'quote', buttonType: IconButton),
      (key: 'h1', buttonType: TextButton),
      (key: 'h2', buttonType: TextButton),
      (key: 'bullet', buttonType: IconButton),
      (key: 'checklist', buttonType: IconButton),
    ]) {
      final control = find.byKey(Key('editor-format-${format.key}'));
      await tester.scrollUntilVisible(
        control,
        120,
        scrollable: formattingScroll,
      );
      final button = find.descendant(
        of: control,
        matching: find.byType(format.buttonType),
      );
      final callback = switch (tester.widget(button)) {
        IconButton(:final onPressed) => onPressed,
        TextButton(:final onPressed) => onPressed,
        _ => throw TestFailure('Unexpected formatting control type'),
      };
      expect(callback, isNull, reason: '${format.key} must be disabled');
      expect(
        tester.getSemantics(button).flagsCollection.isEnabled,
        Tristate.isFalse,
        reason: '${format.key} must announce disabled semantics',
      );
      await tester.tap(control);
      await tester.pump();
    }
    expect(_text(tester, 'editor-body-field'), 'Exact body while saving');
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(harness.closeCount.value, 0);
    expect(find.byType(AddEditNotePage), findsOneWidget);

    repository.release();
    await tester.pumpAndSettle();
    expect(repository.addCalls, 1);
    expect(find.byKey(const Key('editor-save-progress')), findsNothing);
    expect(harness.container.read(notesProvider).error, isNull);
    expect(find.byKey(const Key('editor-save-error')), findsNothing);
    expect(harness.closeCount.value, 1);
    semantics.dispose();
  });

  testWidgets('create stays busy until reminder scheduling completes', (
    tester,
  ) async {
    final scheduleGate = Completer<void>();
    final gateway = FakeNoteReminderGateway()..scheduleGate = scheduleGate;
    final repository = _RecordingRepository(const []);
    final harness = await _pumpEditor(
      tester,
      note: Note(
        title: 'Wait for schedule',
        content: 'Persist before closing',
        color: 0,
        createdAt: DateTime.utc(2026, 8, 23),
        reminder: DateTime.utc(2026, 8, 24),
      ),
      repository: repository,
      gateway: gateway,
      now: () => DateTime.utc(2026, 8, 23, 12),
    );

    await tester.tap(find.byKey(const Key('editor-done-button')));
    await tester.pump();

    expect(gateway.scheduled, hasLength(1));
    expect(repository.addCalls, 1);
    expect(find.byKey(const Key('editor-save-progress')), findsOneWidget);
    expect(find.byType(AddEditNotePage), findsOneWidget);
    expect(harness.closeCount.value, 0);

    scheduleGate.complete();
    await tester.pumpAndSettle();

    expect(harness.closeCount.value, 1);
  });

  testWidgets('edit stays busy until reminder cancellation completes', (
    tester,
  ) async {
    final cancelGate = Completer<void>();
    final gateway = FakeNoteReminderGateway()..cancelGate = cancelGate;
    final repository = _RecordingRepository([sampleNote]);
    final harness = await _pumpEditor(
      tester,
      note: sampleNote,
      repository: repository,
      gateway: gateway,
    );

    await tester.tap(find.byKey(const Key('editor-metadata-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('metadata-clear-reminder')));
    await tester.tap(find.byKey(const Key('metadata-apply')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('editor-done-button')));
    for (var pump = 0; pump < 10 && gateway.cancelled.isEmpty; pump += 1) {
      await tester.pump();
    }
    await tester.pump();
    final cancelled = List<int>.of(gateway.cancelled);
    final updateCalls = repository.updateCalls;
    final progressVisible = find
        .byKey(const Key('editor-save-progress'))
        .evaluate()
        .isNotEmpty;
    final editorVisible = find.byType(AddEditNotePage).evaluate().isNotEmpty;
    final closeCountWhilePending = harness.closeCount.value;

    cancelGate.complete();
    await tester.pumpAndSettle();

    expect(cancelled, [sampleNote.id]);
    expect(updateCalls, 1);
    expect(progressVisible, isTrue);
    expect(editorVisible, isTrue);
    expect(closeCountWhilePending, 0);
    expect(harness.closeCount.value, 1);
  });

  testWidgets('pre-write failure retains the exact draft and Retry succeeds', (
    tester,
  ) async {
    final failure = StateError('insert failed');
    final repository = InMemoryNoteRepository.seeded(const [])
      ..addError = failure;
    final harness = await _pumpEditor(tester, repository: repository);
    const exactTitle = '  Exact title  ';
    const exactBody = 'Body with trailing space ';
    await tester.enterText(
      find.byKey(const Key('editor-title-field')),
      exactTitle,
    );
    await tester.enterText(
      find.byKey(const Key('editor-body-field')),
      exactBody,
    );

    await tester.tap(find.byKey(const Key('editor-done-button')));
    await tester.pumpAndSettle();

    expect(find.text('Couldn’t save note'), findsOneWidget);
    expect(find.byKey(const Key('editor-save-error')), findsOneWidget);
    expect(find.byKey(const Key('editor-retry-button')), findsOneWidget);
    expect(_text(tester, 'editor-title-field'), exactTitle);
    expect(_text(tester, 'editor-body-field'), exactBody);
    expect(harness.closeCount.value, 0);

    repository.addError = null;
    await tester.tap(find.byKey(const Key('editor-retry-button')));
    await tester.pumpAndSettle();
    expect(repository.addCalls, 2);
    expect(repository.notes, hasLength(1));
    expect(harness.closeCount.value, 1);
  });

  testWidgets('save failure from Preview keeps error and Retry visible', (
    tester,
  ) async {
    final repository = InMemoryNoteRepository.seeded(const [])
      ..addError = StateError('insert failed');
    await _pumpEditor(tester, repository: repository);
    await tester.enterText(
      find.byKey(const Key('editor-title-field')),
      'Preview failure',
    );
    await tester.tap(find.byKey(const Key('editor-preview-toggle')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('editor-done-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('editor-preview')), findsOneWidget);
    expect(find.byKey(const Key('editor-save-error')), findsOneWidget);
    expect(find.text('Couldn’t save note'), findsOneWidget);
    expect(find.byKey(const Key('editor-retry-button')), findsOneWidget);
  });

  testWidgets(
    'post-write failure keeps metadata and retries as one update and one close',
    (tester) async {
      final draft = Note(
        title: 'Persist this once',
        content: 'Original draft',
        color: Colors.blue.shade100.toARGB32(),
        createdAt: DateTime.utc(2026, 8, 23, 10),
        isPinned: true,
        tags: const ['work', 'retry'],
        status: NoteStatus.archived,
        reminder: DateTime.now().add(const Duration(days: 1)),
      );
      final repository = _RecordingRepository(const []);
      final gateway = FakeNoteReminderGateway()
        ..scheduleError = StateError('notification failed');
      final harness = await _pumpEditor(
        tester,
        note: draft,
        repository: repository,
        gateway: gateway,
      );

      await tester.tap(find.byKey(const Key('editor-done-button')));
      await tester.pumpAndSettle();

      expect(find.text('Couldn’t finish saving note'), findsOneWidget);
      expect(
        find.text(
          'Your note is saved, but its reminder is not confirmed. '
          'Retry or update the reminder.',
        ),
        findsOneWidget,
      );
      expect(repository.addCalls, 1);
      expect(repository.notes, hasLength(1));
      final allocatedId = repository.notes.single.id;
      expect(allocatedId, isNotNull);
      expect(harness.closeCount.value, 0);
      expect(_text(tester, 'editor-title-field'), draft.title);
      expect(_text(tester, 'editor-body-field'), draft.content);

      await tester.enterText(
        find.byKey(const Key('editor-body-field')),
        'Latest exact draft',
      );
      gateway.scheduleError = null;
      await tester.tap(find.byKey(const Key('editor-retry-button')));
      await tester.pumpAndSettle();

      expect(repository.addCalls, 1);
      expect(repository.updateCalls, 1);
      expect(repository.notes, hasLength(1));
      final stored = repository.notes.single;
      expect(stored.id, allocatedId);
      expect(stored.createdAt, draft.createdAt);
      expect(stored.isPinned, isTrue);
      expect(stored.status, NoteStatus.archived);
      expect(stored.color, draft.color);
      expect(stored.tags, draft.tags);
      expect(stored.reminder, draft.reminder);
      expect(stored.content, 'Latest exact draft');
      expect(gateway.events, [
        'schedule:$allocatedId',
        'schedule:$allocatedId',
      ]);
      expect(harness.closeCount.value, 1);
    },
  );

  testWidgets(
    'post-write refresh failure without a reminder reports saved note state',
    (tester) async {
      final repository = _RecordingRepository(const [])..getErrorAtCall = 4;
      final gateway = FakeNoteReminderGateway();
      final harness = await _pumpEditor(
        tester,
        note: Note(
          title: 'Saved without reminder',
          content: 'Only the list refresh is pending',
          color: 0,
          createdAt: DateTime.utc(2030, 1, 15, 10),
        ),
        repository: repository,
        gateway: gateway,
      );

      await tester.tap(find.byKey(const Key('editor-done-button')));
      await tester.pumpAndSettle();

      expect(find.text('Couldn’t finish saving note'), findsOneWidget);
      expect(
        find.text(
          'Your note is saved, but the note list could not be refreshed. '
          'Retry to finish.',
        ),
        findsOneWidget,
      );
      expect(repository.addCalls, 1);
      expect(repository.notes, hasLength(1));
      expect(gateway.events, isEmpty);
      expect(harness.closeCount.value, 0);

      await tester.tap(find.byKey(const Key('editor-retry-button')));
      await tester.pumpAndSettle();

      expect(repository.addCalls, 1);
      expect(repository.updateCalls, 1);
      expect(gateway.events, isEmpty);
      expect(harness.closeCount.value, 1);
    },
  );

  testWidgets(
    'Retry keeps the editor open when a partially saved reminder has elapsed',
    (tester) async {
      var now = DateTime.utc(2030, 1, 15, 10);
      final reminder = now.add(const Duration(minutes: 5));
      final repository = _RecordingRepository(const []);
      final gateway = FakeNoteReminderGateway()
        ..scheduleError = StateError('notification failed');
      final harness = await _pumpEditor(
        tester,
        note: Note(
          title: 'Reminder retry',
          content: 'Do not silently lose this reminder',
          color: 0,
          createdAt: now,
          reminder: reminder,
        ),
        repository: repository,
        gateway: gateway,
        now: () => now,
      );

      await tester.tap(find.byKey(const Key('editor-done-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor-save-error')), findsOneWidget);
      expect(
        find.text(
          'Your note is saved, but its reminder is not confirmed. '
          'Retry or update the reminder.',
        ),
        findsOneWidget,
      );
      expect(repository.addCalls, 1);

      gateway.scheduleError = null;
      now = reminder;
      await tester.tap(find.byKey(const Key('editor-retry-button')));
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Open Note details to choose a future reminder.'),
        findsOneWidget,
      );
      expect(repository.updateCalls, 0);
      expect(gateway.scheduled, hasLength(1));
      expect(harness.closeCount.value, 0);
      expect(find.byType(AddEditNotePage), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('editor-metadata-button')))
            .focusNode
            ?.hasFocus,
        isTrue,
      );
    },
  );

  for (final systemBack in [false, true]) {
    testWidgets(
      'partial save ${systemBack ? 'system Back' : 'top Back'} refetches one note and closes once',
      (tester) async {
        final repository = _RecordingRepository(const []);
        final gateway = FakeNoteReminderGateway()
          ..scheduleError = StateError('notification failed');
        final harness = await _pumpEditor(
          tester,
          note: Note(
            title: 'Saved before closing',
            content: 'Exact persisted content',
            color: 0,
            createdAt: DateTime.utc(2026, 8, 23),
            reminder: DateTime.utc(2026, 8, 24),
          ),
          repository: repository,
          gateway: gateway,
          now: () => DateTime.utc(2026, 8, 23, 12),
        );

        await tester.tap(find.byKey(const Key('editor-done-button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('editor-save-error')), findsOneWidget);

        Future<void> close() async {
          if (systemBack) {
            await tester.binding.handlePopRoute();
          } else {
            await tester.tap(find.byKey(const Key('editor-back-button')));
          }
          await tester.pumpAndSettle();
        }

        await close();
        await close();

        expect(harness.closeCount.value, 1);
        expect(repository.addCalls, 1);
        expect(repository.notes, hasLength(1));
        expect(harness.container.read(notesProvider).hasError, isFalse);
        expect(harness.container.read(notesProvider).value, hasLength(1));
      },
    );
  }

  testWidgets(
    'Preview removes editors and restores body text and focus intent',
    (tester) async {
      final note = sampleNote.copyWith(content: '**Markdown body**');
      await _pumpEditor(tester, note: note);
      final body = find.byKey(const Key('editor-body-field'));
      await tester.tap(body);
      await tester.enterText(body, '**Latest markdown**');
      expect(tester.widget<TextField>(body).focusNode?.hasFocus, isTrue);

      await tester.tap(find.byKey(const Key('editor-preview-toggle')));
      await tester.pump();

      expect(body, findsNothing);
      expect(find.byKey(const Key('editor-title-field')), findsNothing);
      expect(find.byType(EditorFormattingBar), findsNothing);
      expect(find.byKey(const Key('editor-preview')), findsOneWidget);
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.byKey(const Key('editor-preview-title')), findsOneWidget);

      await tester.tap(find.byKey(const Key('editor-preview-toggle')));
      await tester.pump();
      expect(_text(tester, 'editor-body-field'), '**Latest markdown**');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('editor-body-field')))
            .focusNode
            ?.hasFocus,
        isTrue,
      );
    },
  );

  testWidgets(
    'Preview blocks remote and local Markdown images without leaking targets',
    (tester) async {
      final semantics = tester.ensureSemantics();
      const imageTargets = <String>[
        'https://example.invalid/private.png?token=secret',
        'file:///C:/Users/Owner/private.png',
        'private/relative.png',
      ];
      const altText = <String>[
        'Remote illustration',
        'Local illustration',
        'Relative illustration',
      ];
      final markdown = <String>[
        '**Normal Markdown remains visible.**',
        '[Normal note link](note://Missing)',
        for (var index = 0; index < imageTargets.length; index += 1)
          '![${altText[index]}](${imageTargets[index]})',
      ].join('\n\n');
      await _pumpEditor(tester, note: sampleNote.copyWith(content: markdown));

      await tester.tap(find.byKey(const Key('editor-preview-toggle')));
      await tester.pump();

      final markdownBody = find.byType(MarkdownBody);
      final images = find.descendant(
        of: markdownBody,
        matching: find.byType(Image),
      );
      final placeholders = find.descendant(
        of: markdownBody,
        matching: find.byKey(const Key('editor-markdown-image-placeholder')),
      );
      expect(find.text('Normal Markdown remains visible.'), findsOneWidget);
      expect(find.text('Normal note link', findRichText: true), findsOneWidget);
      expect(placeholders, findsNWidgets(imageTargets.length));
      expect(images, findsNothing);
      expect(
        tester
            .widgetList<Image>(images)
            .where((image) => image.image is NetworkImage),
        isEmpty,
      );
      expect(
        tester
            .widgetList<Image>(images)
            .where((image) => image.image is FileImage),
        isEmpty,
      );
      for (var index = 0; index < imageTargets.length; index += 1) {
        final label = tester.getSemantics(placeholders.at(index)).label;
        expect(label, contains(altText[index]));
        expect(label, isNot(contains(imageTargets[index])));
        expect(find.textContaining(imageTargets[index]), findsNothing);
      }
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'short Preview paints full-width editor and top surfaces inside gutters',
    (tester) async {
      await _pumpEditor(
        tester,
        note: sampleNote.copyWith(title: 'Short', content: 'Tiny note.'),
        size: const Size(390, 844),
        disableAnimations: true,
      );

      await tester.tap(find.byKey(const Key('editor-preview-toggle')));
      await tester.pumpAndSettle();

      final surfaceFinder = find.byKey(const Key('editor-surface'));
      final topBarFinder = find.byKey(const Key('editor-top-bar'));
      final paintedSurface = tester.getRect(
        find
            .descendant(of: surfaceFinder, matching: find.byType(DecoratedBox))
            .first,
      );
      final paintedTopBar = tester.getRect(
        find
            .descendant(of: topBarFinder, matching: find.byType(DecoratedBox))
            .first,
      );
      final preview = tester.getRect(find.byKey(const Key('editor-preview')));
      for (final rect in [paintedSurface, paintedTopBar]) {
        expect(rect.left, moreOrLessEquals(16, epsilon: 0.1));
        expect(rect.right, moreOrLessEquals(374, epsilon: 0.1));
        expect(rect.width, moreOrLessEquals(358, epsilon: 0.1));
      }
      expect(preview.left, moreOrLessEquals(paintedSurface.left, epsilon: 0.1));
      expect(
        preview.right,
        moreOrLessEquals(paintedSurface.right, epsilon: 0.1),
      );
      expect(
        preview.width,
        moreOrLessEquals(paintedSurface.width, epsilon: 0.1),
      );
      expect(paintedTopBar.top, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'note links navigate and missing targets provide useful feedback',
    (tester) async {
      final source = sampleNote.copyWith(
        content: '[Open target](note://Target)\n\n[Missing](note://Missing)',
      );
      final target = sampleNote.copyWith(id: 2, title: 'Target');
      final repository = InMemoryNoteRepository.seeded([source, target]);
      final gateway = FakeNoteReminderGateway();
      final container = ProviderContainer(
        overrides: [
          noteRepositoryProvider.overrideWithValue(repository),
          noteReminderGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      await container.read(notesProvider.future);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                AddEditNotePage(note: source, onClose: () {}),
          ),
          GoRoute(
            path: '/note/:id',
            builder: (context, state) =>
                const Scaffold(key: Key('linked-note-target')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AuroraTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor-preview-toggle')));
      await tester.pump();
      expect(
        container.read(notesProvider).value?.map((note) => note.title),
        contains('Target'),
      );
      expect(
        container
            .read(notesProvider)
            .value
            ?.singleWhere((note) => note.title == 'Target')
            .id,
        2,
      );
      expect(
        GoRouter.of(tester.element(find.byType(AddEditNotePage))),
        same(router),
      );
      await tester.tap(find.text('Open target', findRichText: true));
      await tester.pumpAndSettle();
      expect(
        find.text('Linked note not found. Create it first.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('linked-note-target')), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Missing', findRichText: true));
      await tester.pump();
      expect(
        find.text('Linked note not found. Create it first.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('metadata draft does not write or leak before Apply', (
    tester,
  ) async {
    final repository = _RecordingRepository([sampleNote]);
    await _pumpEditor(tester, note: sampleNote, repository: repository);

    await tester.tap(find.byKey(const Key('editor-metadata-button')));
    await tester.pumpAndSettle();
    expect(repository.updateCalls, 0);
    await tester.tap(
      find.byKey(ValueKey('metadata-tint-${Colors.blue.shade100.toARGB32()}')),
    );
    expect(repository.updateCalls, 0);
    await tester.tap(find.byKey(const Key('metadata-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor-done-button')));
    await tester.pumpAndSettle();

    expect(repository.updateCalls, 1);
    expect(repository.notes.single.color, sampleNote.color);
  });

  for (final theme in <ThemeData>[AuroraTheme.light(), AuroraTheme.dark()]) {
    for (final scale in [1.5, 3.0]) {
      testWidgets(
        'compact ${theme.brightness.name} editor at ${scale}x keeps controls separate',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await _pumpEditor(
            tester,
            note: sampleNote,
            size: const Size(320, 640),
            theme: theme,
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          );

          final controls = [
            find.byKey(const Key('editor-back-button')),
            find.byKey(const Key('editor-preview-toggle')),
            find.byKey(const Key('editor-metadata-button')),
            find.byKey(const Key('editor-done-button')),
          ];
          for (final control in controls) {
            final controlSize = tester.getSize(control);
            expect(controlSize.width, greaterThanOrEqualTo(48));
            expect(controlSize.height, greaterThanOrEqualTo(48));
          }
          for (var index = 1; index < controls.length; index++) {
            expect(
              tester.getRect(controls[index - 1]).right,
              lessThanOrEqualTo(tester.getRect(controls[index]).left),
            );
          }
          expect(
            tester.getSize(find.byKey(const Key('editor-top-bar'))).height,
            56,
          );
          if (scale == 3) {
            final done = find.byKey(const Key('editor-done-button'));
            expect(
              find.descendant(
                of: done,
                matching: find.byIcon(Icons.check_rounded),
              ),
              findsOneWidget,
            );
            final doneSemantics = tester.getSemantics(done);
            expect(doneSemantics.label, 'Done');
            expect(doneSemantics.flagsCollection.isButton, isTrue);
          }
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }

  testWidgets('top bar owns 48dp targets under compact inherited density', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      note: sampleNote,
      size: const Size(320, 640),
      theme: AuroraTheme.light().copyWith(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      disableAnimations: true,
    );

    for (final key in const [
      'editor-back-button',
      'editor-preview-toggle',
      'editor-metadata-button',
      'editor-done-button',
    ]) {
      final size = tester.getSize(find.byKey(Key(key)));
      expect(size.width, greaterThanOrEqualTo(48), reason: '$key width');
      expect(size.height, greaterThanOrEqualTo(48), reason: '$key height');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('640 by 320 landscape editor fits at 3x text', (tester) async {
    await _pumpEditor(
      tester,
      note: sampleNote,
      size: const Size(640, 320),
      textScaler: const TextScaler.linear(3),
      viewPadding: const EdgeInsets.only(top: 20, bottom: 16),
      disableAnimations: true,
    );

    expect(find.byKey(const Key('editor-title-field')), findsOneWidget);
    expect(find.byKey(const Key('editor-body-field')), findsOneWidget);
    expect(find.byKey(const Key('editor-formatting-bar')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('editor-top-bar'))).top,
      greaterThanOrEqualTo(20),
    );
    expect(
      tester.getRect(find.byKey(const Key('editor-formatting-bar'))).bottom,
      lessThanOrEqualTo(304),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '640 by 320 landscape keeps focused content above a 120 keyboard inset',
    (tester) async {
      final harness = await _pumpEditor(
        tester,
        note: sampleNote,
        size: const Size(640, 320),
        textScaler: const TextScaler.linear(2),
        viewPadding: const EdgeInsets.only(top: 20, bottom: 16),
        viewInsets: const EdgeInsets.only(bottom: 120),
        disableAnimations: true,
      );

      final body = find.byKey(const Key('editor-body-field'));
      tester.widget<TextField>(body).focusNode!.requestFocus();
      await tester.pump();
      await tester.pump();

      final shortScroll = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const Key('editor-short-layout-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      expect(
        shortScroll.pixels,
        moreOrLessEquals(shortScroll.maxScrollExtent),
        reason: 'Focused content must reveal the end of the short layout',
      );
      final bodyRect = tester.getRect(body);
      final shortViewport = tester.getRect(
        find.byKey(const Key('editor-short-layout-scroll')),
      );
      final formattingRect = tester.getRect(
        find.byKey(const Key('editor-formatting-bar')),
      );
      final topBarRect = tester.getRect(
        find.byKey(const Key('editor-top-bar')),
      );
      final doneRect = tester.getRect(
        find.byKey(const Key('editor-done-button')),
      );
      expect(topBarRect.top, greaterThanOrEqualTo(20));
      expect(topBarRect.bottom, lessThanOrEqualTo(shortViewport.top));
      expect(doneRect.top, greaterThanOrEqualTo(topBarRect.top));
      expect(doneRect.bottom, lessThanOrEqualTo(topBarRect.bottom));
      expect(
        bodyRect.bottom,
        lessThanOrEqualTo(formattingRect.top),
        reason: 'The focused content field must clear formatting and keyboard',
      );
      expect(
        bodyRect.intersect(shortViewport).height,
        greaterThanOrEqualTo(44),
        reason: 'At least 44px of the focused body must be operable',
      );
      expect(formattingRect.bottom, lessThanOrEqualTo(200.1));
      expect(tester.takeException(), isNull);

      final title = find.byKey(const Key('editor-title-field'));
      tester.widget<TextField>(title).focusNode!.requestFocus();
      await tester.pump();
      await tester.pump();
      final titleRect = tester.getRect(title);
      expect(titleRect.bottom, lessThanOrEqualTo(formattingRect.top));
      expect(
        titleRect.intersect(shortViewport).height,
        greaterThanOrEqualTo(44),
        reason: 'At least 44px of the focused title must be operable',
      );

      harness.viewInsets.value = EdgeInsets.zero;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor-short-layout-scroll')), findsNothing);
      expect(
        tester.getRect(find.byKey(const Key('editor-top-bar'))).top,
        greaterThanOrEqualTo(20),
      );
      expect(
        tester.getRect(find.byKey(const Key('editor-formatting-bar'))).bottom,
        lessThanOrEqualTo(304.1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('768 tablet keeps the editor centered inside 24 gutters', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      note: sampleNote,
      size: const Size(768, 1024),
      textScaler: const TextScaler.linear(1.5),
      disableAnimations: true,
    );

    final topBar = tester.getRect(find.byKey(const Key('editor-top-bar')));
    expect(topBar.left, greaterThanOrEqualTo(24));
    expect(topBar.right, lessThanOrEqualTo(744));
    expect(topBar.width, lessThanOrEqualTo(720));
    expect(tester.takeException(), isNull);
  });

  testWidgets('formatting surface clears a 240 keyboard inset', (tester) async {
    final harness = await _pumpEditor(
      tester,
      note: sampleNote,
      size: const Size(320, 640),
      textScaler: const TextScaler.linear(1.5),
      viewPadding: const EdgeInsets.only(bottom: 34),
      disableAnimations: true,
    );

    final body = find.byKey(const Key('editor-body-field'));
    await tester.tap(body);
    await tester.enterText(body, 'Caret stays visible');
    harness.viewInsets.value = const EdgeInsets.only(bottom: 240);
    await tester.pump();
    expect(tester.widget<TextField>(body).focusNode?.hasFocus, isTrue);
    final keyboardBar = tester.getRect(
      find.byKey(const Key('editor-formatting-bar')),
    );
    expect(tester.getRect(body).bottom, lessThanOrEqualTo(keyboardBar.top));
    expect(keyboardBar.bottom, lessThanOrEqualTo(400.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'portrait keyboard keeps inline save recovery and focused body reachable',
    (tester) async {
      final repository = InMemoryNoteRepository.seeded(const [])
        ..addError = StateError('insert failed');
      await _pumpEditor(
        tester,
        repository: repository,
        size: const Size(320, 640),
        textScaler: const TextScaler.linear(2),
        viewInsets: const EdgeInsets.only(bottom: 240),
        disableAnimations: true,
      );
      await tester.enterText(
        find.byKey(const Key('editor-title-field')),
        'Portrait recovery',
      );
      await tester.enterText(
        find.byKey(const Key('editor-body-field')),
        'Exact body remains reachable',
      );

      final done = find.byKey(const Key('editor-done-button'));
      final save = tester.widget<TextButton>(done).onPressed;
      expect(save, isNotNull);
      save!();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('editor-save-error')), findsOneWidget);
      expect(find.byKey(const Key('editor-retry-button')), findsOneWidget);
      expect(
        find.byKey(const Key('editor-short-layout-scroll')),
        findsOneWidget,
      );
      final body = find.byKey(const Key('editor-body-field'));
      tester.widget<TextField>(body).focusNode!.requestFocus();
      await tester.pump();
      await tester.pump();
      final formatting = tester.getRect(
        find.byKey(const Key('editor-formatting-bar')),
      );
      final bodyRect = tester.getRect(body);
      expect(bodyRect.height, greaterThanOrEqualTo(44));
      expect(bodyRect.bottom, lessThanOrEqualTo(formatting.top));
      expect(formatting.bottom, lessThanOrEqualTo(400.1));

      await tester.ensureVisible(find.byKey(const Key('editor-retry-button')));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const Key('editor-retry-button'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('formatting surface consumes bottom safe area once', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      note: sampleNote,
      size: const Size(320, 640),
      viewPadding: const EdgeInsets.only(bottom: 34),
      disableAnimations: true,
    );
    final safeBar = tester.getRect(
      find.byKey(const Key('editor-formatting-bar')),
    );
    expect(safeBar.bottom, lessThanOrEqualTo(606.1));
    expect(safeBar.bottom, greaterThan(560));
    expect(tester.takeException(), isNull);
  });
}

typedef _EditorHarness = ({
  ProviderContainer container,
  InMemoryNoteRepository repository,
  FakeNoteReminderGateway gateway,
  ValueNotifier<int> closeCount,
  ValueNotifier<TextScaler> textScaler,
  ValueNotifier<EdgeInsets> viewInsets,
});

Future<_EditorHarness> _pumpEditor(
  WidgetTester tester, {
  Note? note,
  InMemoryNoteRepository? repository,
  FakeNoteReminderGateway? gateway,
  ReminderSyncCoordinator? coordinator,
  Size size = const Size(375, 812),
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
  EdgeInsets viewPadding = EdgeInsets.zero,
  EdgeInsets viewInsets = EdgeInsets.zero,
  bool disableAnimations = false,
  DateTime Function()? now,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final resolvedRepository =
      repository ?? InMemoryNoteRepository.seeded(note == null ? [] : [note]);
  final resolvedGateway = gateway ?? FakeNoteReminderGateway();
  final container = ProviderContainer(
    overrides: [
      noteRepositoryProvider.overrideWithValue(resolvedRepository),
      noteReminderGatewayProvider.overrideWithValue(resolvedGateway),
      if (coordinator != null)
        reminderCoordinatorProvider.overrideWithValue(coordinator),
    ],
  );
  await container.read(notesProvider.future);
  final closeCount = ValueNotifier<int>(0);
  final mutableTextScaler = ValueNotifier<TextScaler>(textScaler);
  final mutableViewInsets = ValueNotifier<EdgeInsets>(viewInsets);
  addTearDown(closeCount.dispose);
  addTearDown(mutableTextScaler.dispose);
  addTearDown(mutableViewInsets.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme ?? AuroraTheme.light(),
        home: Builder(
          builder: (context) {
            return ValueListenableBuilder<TextScaler>(
              valueListenable: mutableTextScaler,
              builder: (context, currentTextScaler, child) =>
                  ValueListenableBuilder<EdgeInsets>(
                    valueListenable: mutableViewInsets,
                    builder: (context, currentInsets, child) {
                      final bottomPadding =
                          (viewPadding.bottom - currentInsets.bottom)
                              .clamp(0.0, double.infinity)
                              .toDouble();
                      return MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          textScaler: currentTextScaler,
                          padding: EdgeInsets.only(
                            top: viewPadding.top,
                            bottom: bottomPadding,
                          ),
                          viewPadding: viewPadding,
                          viewInsets: currentInsets,
                          disableAnimations: disableAnimations,
                        ),
                        child: child!,
                      );
                    },
                    child: child,
                  ),
              child: _editorPage(
                note: note,
                onClose: () => closeCount.value += 1,
                now: now,
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  return (
    container: container,
    repository: resolvedRepository,
    gateway: resolvedGateway,
    closeCount: closeCount,
    textScaler: mutableTextScaler,
    viewInsets: mutableViewInsets,
  );
}

Widget _editorPage({
  required Note? note,
  required VoidCallback onClose,
  required DateTime Function()? now,
}) {
  return AddEditNotePage(note: note, onClose: onClose, now: now);
}

String _text(WidgetTester tester, String key) {
  return tester.widget<TextField>(find.byKey(Key(key))).controller!.text;
}

enum _MetadataChange { color, tags, reminder }

Future<void> _applyMetadataChange(
  WidgetTester tester,
  _MetadataChange change,
) async {
  await tester.tap(find.byKey(const Key('editor-metadata-button')));
  await tester.pumpAndSettle();
  switch (change) {
    case _MetadataChange.color:
      await tester.tap(
        find.byKey(
          ValueKey('metadata-tint-${Colors.blue.shade100.toARGB32()}'),
        ),
      );
    case _MetadataChange.tags:
      await tester.enterText(
        find.byKey(const Key('metadata-tag-field')),
        'unsaved',
      );
      await tester.tap(find.byKey(const Key('metadata-add-tag')));
    case _MetadataChange.reminder:
      await tester.tap(find.byKey(const Key('metadata-clear-reminder')));
  }
  final apply = find.byKey(const Key('metadata-apply'));
  await tester.ensureVisible(apply);
  await tester.tap(apply);
  await tester.pumpAndSettle();
}

class _RecordingRepository extends InMemoryNoteRepository {
  _RecordingRepository(super.notes) : super.seeded();

  int updateCalls = 0;

  @override
  Future<int> updateNote(Note note) async {
    updateCalls += 1;
    return super.updateNote(note);
  }
}

class _DeferredAddRepository extends InMemoryNoteRepository {
  _DeferredAddRepository() : super.seeded(const []);

  final entered = Completer<void>();
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<int> addNote(Note note) async {
    if (!entered.isCompleted) entered.complete();
    await _gate.future;
    return super.addNote(note);
  }
}
