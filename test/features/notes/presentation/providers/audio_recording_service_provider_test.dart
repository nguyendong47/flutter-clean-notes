import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_clean_notes/features/notes/presentation/providers/audio_recording_service_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/audio_recording_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'provides an AudioRecordingService and disposes it when the container is disposed',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(audioRecordingServiceProvider);
      container.listen(audioRecordingServiceProvider, (_, _) {});

      expect(service, isA<AudioRecordingService>());
      expect(service.currentState, AudioRecordingState.idle);

      container.dispose();

      expect(() => service.stateStream.listen((_) {}), throwsStateError);
    },
  );
}
