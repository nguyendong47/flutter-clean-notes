import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:flutter_clean_notes/features/notes/presentation/services/audio_recording_service.dart';

part 'audio_recording_service_provider.g.dart';

@riverpod
AudioRecordingService audioRecordingService(Ref ref) {
  final service = AudioRecordingService();
  ref.onDispose(service.dispose);
  return service;
}
