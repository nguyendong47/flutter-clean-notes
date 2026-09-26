import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:flutter_clean_notes/features/notes/presentation/services/dictation_service.dart';

part 'dictation_service_provider.g.dart';

@riverpod
DictationService dictationService(Ref ref) {
  final service = DictationService();
  ref.onDispose(service.dispose);
  return service;
}
