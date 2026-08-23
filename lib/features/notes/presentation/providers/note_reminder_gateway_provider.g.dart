// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note_reminder_gateway_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

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
    r'183789424a435e194c226c57e664d9a2d7f1e656';
