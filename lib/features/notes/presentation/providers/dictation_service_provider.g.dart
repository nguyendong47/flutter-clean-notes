// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dictation_service_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(dictationService)
final dictationServiceProvider = DictationServiceProvider._();

final class DictationServiceProvider
    extends
        $FunctionalProvider<
          DictationService,
          DictationService,
          DictationService
        >
    with $Provider<DictationService> {
  DictationServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dictationServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dictationServiceHash();

  @$internal
  @override
  $ProviderElement<DictationService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DictationService create(Ref ref) {
    return dictationService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DictationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DictationService>(value),
    );
  }
}

String _$dictationServiceHash() => r'368031b1ffc3d56d2feef381e3ea8567b8378f56';
