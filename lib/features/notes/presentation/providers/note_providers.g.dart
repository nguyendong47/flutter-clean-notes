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

@ProviderFor(getNotesByStatusUsecase)
final getNotesByStatusUsecaseProvider = GetNotesByStatusUsecaseProvider._();

final class GetNotesByStatusUsecaseProvider
    extends
        $FunctionalProvider<
          GetNotesByStatus,
          GetNotesByStatus,
          GetNotesByStatus
        >
    with $Provider<GetNotesByStatus> {
  GetNotesByStatusUsecaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'getNotesByStatusUsecaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$getNotesByStatusUsecaseHash();

  @$internal
  @override
  $ProviderElement<GetNotesByStatus> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GetNotesByStatus create(Ref ref) {
    return getNotesByStatusUsecase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GetNotesByStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GetNotesByStatus>(value),
    );
  }
}

String _$getNotesByStatusUsecaseHash() =>
    r'7cb6bbf43677dbaab35e4cded35bd1ffa89e458e';

@ProviderFor(setNoteStatusUsecase)
final setNoteStatusUsecaseProvider = SetNoteStatusUsecaseProvider._();

final class SetNoteStatusUsecaseProvider
    extends $FunctionalProvider<SetNoteStatus, SetNoteStatus, SetNoteStatus>
    with $Provider<SetNoteStatus> {
  SetNoteStatusUsecaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'setNoteStatusUsecaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$setNoteStatusUsecaseHash();

  @$internal
  @override
  $ProviderElement<SetNoteStatus> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SetNoteStatus create(Ref ref) {
    return setNoteStatusUsecase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SetNoteStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SetNoteStatus>(value),
    );
  }
}

String _$setNoteStatusUsecaseHash() =>
    r'708bc1f73ce3fd7d100cb0947bf787e7cef33237';

@ProviderFor(NoteModeNotifier)
final noteModeProvider = NoteModeNotifierProvider._();

final class NoteModeNotifierProvider
    extends $NotifierProvider<NoteModeNotifier, NoteMode> {
  NoteModeNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'noteModeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$noteModeNotifierHash();

  @$internal
  @override
  NoteModeNotifier create() => NoteModeNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NoteMode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NoteMode>(value),
    );
  }
}

String _$noteModeNotifierHash() => r'7fa3d86568f7938c643daf523ebc4a585da0260b';

abstract class _$NoteModeNotifier extends $Notifier<NoteMode> {
  NoteMode build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<NoteMode, NoteMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<NoteMode, NoteMode>,
              NoteMode,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(SearchQuery)
final searchQueryProvider = SearchQueryProvider._();

final class SearchQueryProvider extends $NotifierProvider<SearchQuery, String> {
  SearchQueryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchQueryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchQueryHash();

  @$internal
  @override
  SearchQuery create() => SearchQuery();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$searchQueryHash() => r'3c36752ee11b18a9f1e545eb1a7209a7222d91c9';

abstract class _$SearchQuery extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(SelectedTag)
final selectedTagProvider = SelectedTagProvider._();

final class SelectedTagProvider
    extends $NotifierProvider<SelectedTag, String?> {
  SelectedTagProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedTagProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedTagHash();

  @$internal
  @override
  SelectedTag create() => SelectedTag();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$selectedTagHash() => r'92447d53e5a3d6776f9c7b886db92c466289f534';

abstract class _$SelectedTag extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(allTags)
final allTagsProvider = AllTagsProvider._();

final class AllTagsProvider
    extends $FunctionalProvider<List<String>, List<String>, List<String>>
    with $Provider<List<String>> {
  AllTagsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'allTagsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$allTagsHash();

  @$internal
  @override
  $ProviderElement<List<String>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<String> create(Ref ref) {
    return allTags(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<String>>(value),
    );
  }
}

String _$allTagsHash() => r'8dc3e8e6a165b2821a560c4825c34f64cc1bc318';

@ProviderFor(filteredNotes)
final filteredNotesProvider = FilteredNotesProvider._();

final class FilteredNotesProvider
    extends $FunctionalProvider<List<Note>, List<Note>, List<Note>>
    with $Provider<List<Note>> {
  FilteredNotesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'filteredNotesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$filteredNotesHash();

  @$internal
  @override
  $ProviderElement<List<Note>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<Note> create(Ref ref) {
    return filteredNotes(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Note> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Note>>(value),
    );
  }
}

String _$filteredNotesHash() => r'75845837ff590b226e06fb341fe4fbf2b2588028';

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

String _$notesNotifierHash() => r'72d67ee44cd5099fc9927267cb676c256893b1f0';

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
