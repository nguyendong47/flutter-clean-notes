// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_note_datasource_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(localNoteDataSource)
final localNoteDataSourceProvider = LocalNoteDataSourceProvider._();

final class LocalNoteDataSourceProvider
    extends
        $FunctionalProvider<
          NotesPersistenceDataSource,
          NotesPersistenceDataSource,
          NotesPersistenceDataSource
        >
    with $Provider<NotesPersistenceDataSource> {
  LocalNoteDataSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'localNoteDataSourceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$localNoteDataSourceHash();

  @$internal
  @override
  $ProviderElement<NotesPersistenceDataSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  NotesPersistenceDataSource create(Ref ref) {
    return localNoteDataSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NotesPersistenceDataSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NotesPersistenceDataSource>(value),
    );
  }
}

String _$localNoteDataSourceHash() =>
    r'7bacf1e98cbbafafd49addf254b00dbef6f7d8b9';
