// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_focus_request.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SearchFocusRequest)
final searchFocusRequestProvider = SearchFocusRequestProvider._();

final class SearchFocusRequestProvider
    extends $NotifierProvider<SearchFocusRequest, int> {
  SearchFocusRequestProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchFocusRequestProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchFocusRequestHash();

  @$internal
  @override
  SearchFocusRequest create() => SearchFocusRequest();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$searchFocusRequestHash() =>
    r'442c1f00f51c2914d776de51e460749b8cdb5bec';

abstract class _$SearchFocusRequest extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
