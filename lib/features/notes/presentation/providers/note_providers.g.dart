// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note_providers.dart';

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
          LocalNoteDataSource,
          LocalNoteDataSource,
          LocalNoteDataSource
        >
    with $Provider<LocalNoteDataSource> {
  LocalNoteDataSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'localNoteDataSourceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$localNoteDataSourceHash();

  @$internal
  @override
  $ProviderElement<LocalNoteDataSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LocalNoteDataSource create(Ref ref) {
    return localNoteDataSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LocalNoteDataSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LocalNoteDataSource>(value),
    );
  }
}

String _$localNoteDataSourceHash() =>
    r'876dddb214c48a561908e64e05959b265c384662';

@ProviderFor(noteRepository)
final noteRepositoryProvider = NoteRepositoryProvider._();

final class NoteRepositoryProvider
    extends $FunctionalProvider<NoteRepository, NoteRepository, NoteRepository>
    with $Provider<NoteRepository> {
  NoteRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'noteRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$noteRepositoryHash();

  @$internal
  @override
  $ProviderElement<NoteRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  NoteRepository create(Ref ref) {
    return noteRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NoteRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NoteRepository>(value),
    );
  }
}

String _$noteRepositoryHash() => r'cc67d822a5fa7e57d98b88b187287dd15eca4610';

@ProviderFor(getNotesUsecase)
final getNotesUsecaseProvider = GetNotesUsecaseProvider._();

final class GetNotesUsecaseProvider
    extends $FunctionalProvider<GetNotes, GetNotes, GetNotes>
    with $Provider<GetNotes> {
  GetNotesUsecaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'getNotesUsecaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$getNotesUsecaseHash();

  @$internal
  @override
  $ProviderElement<GetNotes> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GetNotes create(Ref ref) {
    return getNotesUsecase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GetNotes value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GetNotes>(value),
    );
  }
}

String _$getNotesUsecaseHash() => r'283559bb1356a35c42ca4ad1b11aefd6765b6755';

@ProviderFor(addNoteUsecase)
final addNoteUsecaseProvider = AddNoteUsecaseProvider._();

final class AddNoteUsecaseProvider
    extends $FunctionalProvider<AddNote, AddNote, AddNote>
    with $Provider<AddNote> {
  AddNoteUsecaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'addNoteUsecaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$addNoteUsecaseHash();

  @$internal
  @override
  $ProviderElement<AddNote> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AddNote create(Ref ref) {
    return addNoteUsecase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AddNote value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AddNote>(value),
    );
  }
}

String _$addNoteUsecaseHash() => r'353e7625178786590cf3fa6d17678569049de940';

@ProviderFor(updateNoteUsecase)
final updateNoteUsecaseProvider = UpdateNoteUsecaseProvider._();

final class UpdateNoteUsecaseProvider
    extends $FunctionalProvider<UpdateNote, UpdateNote, UpdateNote>
    with $Provider<UpdateNote> {
  UpdateNoteUsecaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'updateNoteUsecaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$updateNoteUsecaseHash();

  @$internal
  @override
  $ProviderElement<UpdateNote> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  UpdateNote create(Ref ref) {
    return updateNoteUsecase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UpdateNote value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UpdateNote>(value),
    );
  }
}

String _$updateNoteUsecaseHash() => r'cdbdd0b1f2d37280178d6f2b70d2524d6d7decc2';

@ProviderFor(deleteNoteUsecase)
final deleteNoteUsecaseProvider = DeleteNoteUsecaseProvider._();

final class DeleteNoteUsecaseProvider
    extends $FunctionalProvider<DeleteNote, DeleteNote, DeleteNote>
    with $Provider<DeleteNote> {
  DeleteNoteUsecaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deleteNoteUsecaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deleteNoteUsecaseHash();

  @$internal
  @override
  $ProviderElement<DeleteNote> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DeleteNote create(Ref ref) {
    return deleteNoteUsecase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeleteNote value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeleteNote>(value),
    );
  }
}

String _$deleteNoteUsecaseHash() => r'e793c8e8251e35e02ba8ee4073cbc862b16635cf';

@ProviderFor(NotesNotifier)
final notesProvider = NotesNotifierProvider._();

final class NotesNotifierProvider
    extends $AsyncNotifierProvider<NotesNotifier, List<Note>> {
  NotesNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notesNotifierHash();

  @$internal
  @override
  NotesNotifier create() => NotesNotifier();
}

String _$notesNotifierHash() => r'93b6c16ed128bb8e021dd3916c6b117def6be0a2';

abstract class _$NotesNotifier extends $AsyncNotifier<List<Note>> {
  FutureOr<List<Note>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Note>>, List<Note>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Note>>, List<Note>>,
              AsyncValue<List<Note>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
