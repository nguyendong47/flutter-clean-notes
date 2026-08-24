// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note_reminder_gateway_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(reminderOutboxRepository)
final reminderOutboxRepositoryProvider = ReminderOutboxRepositoryProvider._();

final class ReminderOutboxRepositoryProvider
    extends
        $FunctionalProvider<
          ReminderOutboxRepository,
          ReminderOutboxRepository,
          ReminderOutboxRepository
        >
    with $Provider<ReminderOutboxRepository> {
  ReminderOutboxRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reminderOutboxRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reminderOutboxRepositoryHash();

  @$internal
  @override
  $ProviderElement<ReminderOutboxRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReminderOutboxRepository create(Ref ref) {
    return reminderOutboxRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReminderOutboxRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReminderOutboxRepository>(value),
    );
  }
}

String _$reminderOutboxRepositoryHash() =>
    r'54a17a514e219b9bfeb490a0b8dca6a631b69201';

@ProviderFor(reminderCoordinator)
final reminderCoordinatorProvider = ReminderCoordinatorProvider._();

final class ReminderCoordinatorProvider
    extends
        $FunctionalProvider<
          ReminderSyncCoordinator,
          ReminderSyncCoordinator,
          ReminderSyncCoordinator
        >
    with $Provider<ReminderSyncCoordinator> {
  ReminderCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reminderCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reminderCoordinatorHash();

  @$internal
  @override
  $ProviderElement<ReminderSyncCoordinator> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReminderSyncCoordinator create(Ref ref) {
    return reminderCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReminderSyncCoordinator value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReminderSyncCoordinator>(value),
    );
  }
}

String _$reminderCoordinatorHash() =>
    r'94d196e98f8b295e75c2dca839e0a198dfb5c948';

@ProviderFor(noteReminderGateway)
final noteReminderGatewayProvider = NoteReminderGatewayProvider._();

final class NoteReminderGatewayProvider
    extends
        $FunctionalProvider<
          NoteReminderGateway,
          NoteReminderGateway,
          NoteReminderGateway
        >
    with $Provider<NoteReminderGateway> {
  NoteReminderGatewayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'noteReminderGatewayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$noteReminderGatewayHash();

  @$internal
  @override
  $ProviderElement<NoteReminderGateway> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  NoteReminderGateway create(Ref ref) {
    return noteReminderGateway(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NoteReminderGateway value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NoteReminderGateway>(value),
    );
  }
}

String _$noteReminderGatewayHash() =>
    r'9af8405be7de7b5fcfa86ea0fab6477daafe03e8';
