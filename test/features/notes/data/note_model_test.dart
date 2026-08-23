import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/note_fixtures.dart';

void main() {
  group('NoteModel.toJson', () {
    test('round-trips JSON tag storage without splitting commas in a tag', () {
      final entity = sampleNote.copyWith(
        tags: const ['finance,2026', 'roadmap'],
      );

      final json = NoteModel.fromEntity(entity).toJson();
      final restored = NoteModel.fromJson(json);

      expect(json['tags'], '["finance,2026","roadmap"]');
      expect(restored.tags, ['finance,2026', 'roadmap']);
    });

    test('continues to decode legacy comma-delimited tag rows', () {
      final json = NoteModel.fromEntity(sampleNote).toJson()
        ..['tags'] = 'legacy, work';

      expect(NoteModel.fromJson(json).tags, ['legacy', 'work']);
    });

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
