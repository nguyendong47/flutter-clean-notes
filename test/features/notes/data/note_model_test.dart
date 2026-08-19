import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/note_fixtures.dart';

void main() {
  group('NoteModel.toJson', () {
    test('includes a null reminder so persistence updates can clear it', () {
      final entity = sampleNote.copyWith(reminder: null);

      final json = NoteModel.fromEntity(entity).toJson();

      expect(json, containsPair('reminder', isNull));
    });

    test('encodes a non-null reminder as ISO 8601 text', () {
      final json = NoteModel.fromEntity(sampleNote).toJson();

      expect(json['reminder'], sampleNote.reminder!.toIso8601String());
    });
  });
}
