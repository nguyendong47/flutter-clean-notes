// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audio_attachment_repository_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(audioAttachmentRepository)
final audioAttachmentRepositoryProvider = AudioAttachmentRepositoryProvider._();

final class AudioAttachmentRepositoryProvider
    extends
        $FunctionalProvider<
          AudioAttachmentRepository,
          AudioAttachmentRepository,
          AudioAttachmentRepository
        >
    with $Provider<AudioAttachmentRepository> {
  AudioAttachmentRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'audioAttachmentRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$audioAttachmentRepositoryHash();

  @$internal
  @override
  $ProviderElement<AudioAttachmentRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AudioAttachmentRepository create(Ref ref) {
    return audioAttachmentRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AudioAttachmentRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AudioAttachmentRepository>(value),
    );
  }
}

String _$audioAttachmentRepositoryHash() =>
    r'4574d6d2895c985d617ae5d8c8fb999aa465d714';
