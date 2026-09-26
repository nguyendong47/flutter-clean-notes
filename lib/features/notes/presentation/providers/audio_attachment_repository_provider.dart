import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:flutter_clean_notes/features/notes/data/repositories/audio_attachment_repository.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/local_note_datasource_provider.dart';

part 'audio_attachment_repository_provider.g.dart';

@Riverpod(keepAlive: true)
AudioAttachmentRepository audioAttachmentRepository(Ref ref) {
  final dataSource = ref.watch(localNoteDataSourceProvider);
  return AudioAttachmentRepositoryImpl(dataSource: dataSource);
}
