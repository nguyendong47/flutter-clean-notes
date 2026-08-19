import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/note_fixtures.dart';

void main() {
  group('Note.copyWith', () {
    test('preserves nullable persistence fields when omitted', () {
      final copied = sampleNote.copyWith();

      expect(copied.id, sampleNote.id);
      expect(copied.reminder, sampleNote.reminder);
    });

    test('replaces nullable persistence fields with non-null values', () {
      final reminder = DateTime.utc(2026, 8, 20, 14);

      final copied = sampleNote.copyWith(id: 42, reminder: reminder);

      expect(copied.id, 42);
      expect(copied.reminder, reminder);
    });

    test('clears nullable persistence fields with explicit nulls', () {
      final copied = sampleNote.copyWith(id: null, reminder: null);

      expect(copied.id, isNull);
      expect(copied.reminder, isNull);
    });

    test('changes pin state without changing persistence fields', () {
      final copied = sampleNote.copyWith(isPinned: false);

      expect(copied.isPinned, isFalse);
      expect(copied.id, sampleNote.id);
      expect(copied.reminder, sampleNote.reminder);
    });
  });
}
