import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_clean_notes/features/notes/presentation/providers/dictation_service_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/dictation_service.dart';

void main() {
  test(
    'provides a DictationService and disposes it when the container is disposed',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(dictationServiceProvider);
      container.listen(dictationServiceProvider, (_, _) {});

      expect(service, isA<DictationService>());
      expect(service.currentState, DictationState.idle);

      container.dispose();

      // A disposed DictationService closes its streams; listening after
      // dispose must throw, proving dispose() actually ran via ref.onDispose.
      expect(
        () => service.recognizedTextStream.listen((_) {}),
        throwsStateError,
      );
    },
  );
}
