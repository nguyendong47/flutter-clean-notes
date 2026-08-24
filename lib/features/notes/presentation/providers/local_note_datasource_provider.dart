import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';

part 'local_note_datasource_provider.g.dart';

@Riverpod(keepAlive: true)
NotesPersistenceDataSource localNoteDataSource(Ref ref) {
  return LocalNoteDataSourceImpl();
}
