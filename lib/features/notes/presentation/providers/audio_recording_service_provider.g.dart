// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audio_recording_service_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(audioRecordingService)
final audioRecordingServiceProvider = AudioRecordingServiceProvider._();

final class AudioRecordingServiceProvider
    extends
        $FunctionalProvider<
          AudioRecordingService,
          AudioRecordingService,
          AudioRecordingService
        >
    with $Provider<AudioRecordingService> {
  AudioRecordingServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'audioRecordingServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$audioRecordingServiceHash();

  @$internal
  @override
  $ProviderElement<AudioRecordingService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AudioRecordingService create(Ref ref) {
    return audioRecordingService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AudioRecordingService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AudioRecordingService>(value),
    );
  }
}

String _$audioRecordingServiceHash() =>
    r'fb9ff4238e8db47087482199288a122152bc59f6';
