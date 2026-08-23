// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notes_transfer_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(notesTransferGateway)
final notesTransferGatewayProvider = NotesTransferGatewayProvider._();

final class NotesTransferGatewayProvider
    extends
        $FunctionalProvider<
          NotesTransferGateway,
          NotesTransferGateway,
          NotesTransferGateway
        >
    with $Provider<NotesTransferGateway> {
  NotesTransferGatewayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notesTransferGatewayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notesTransferGatewayHash();

  @$internal
  @override
  $ProviderElement<NotesTransferGateway> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  NotesTransferGateway create(Ref ref) {
    return notesTransferGateway(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NotesTransferGateway value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NotesTransferGateway>(value),
    );
  }
}

String _$notesTransferGatewayHash() =>
    r'7ad41d00d017b44932a2f069e2408840dfc40603';

@ProviderFor(NotesTransfer)
final notesTransferProvider = NotesTransferProvider._();

final class NotesTransferProvider
    extends $AsyncNotifierProvider<NotesTransfer, NotesTransferOutcome?> {
  NotesTransferProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notesTransferProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notesTransferHash();

  @$internal
  @override
  NotesTransfer create() => NotesTransfer();
}

String _$notesTransferHash() => r'79e2134de5cdec00f6165570c5c127436a7b9091';

abstract class _$NotesTransfer extends $AsyncNotifier<NotesTransferOutcome?> {
  FutureOr<NotesTransferOutcome?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<NotesTransferOutcome?>, NotesTransferOutcome?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<NotesTransferOutcome?>,
                NotesTransferOutcome?
              >,
              AsyncValue<NotesTransferOutcome?>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
