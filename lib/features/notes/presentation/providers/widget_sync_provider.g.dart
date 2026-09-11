// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'widget_sync_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(widgetSyncGateway)
final widgetSyncGatewayProvider = WidgetSyncGatewayProvider._();

final class WidgetSyncGatewayProvider
    extends
        $FunctionalProvider<
          WidgetSyncGateway,
          WidgetSyncGateway,
          WidgetSyncGateway
        >
    with $Provider<WidgetSyncGateway> {
  WidgetSyncGatewayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'widgetSyncGatewayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$widgetSyncGatewayHash();

  @$internal
  @override
  $ProviderElement<WidgetSyncGateway> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WidgetSyncGateway create(Ref ref) {
    return widgetSyncGateway(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WidgetSyncGateway value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WidgetSyncGateway>(value),
    );
  }
}

String _$widgetSyncGatewayHash() => r'5cf1c26c7f757fead441370ea592e10cc29d2010';

@ProviderFor(widgetSyncService)
final widgetSyncServiceProvider = WidgetSyncServiceProvider._();

final class WidgetSyncServiceProvider
    extends
        $FunctionalProvider<
          WidgetSyncService,
          WidgetSyncService,
          WidgetSyncService
        >
    with $Provider<WidgetSyncService> {
  WidgetSyncServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'widgetSyncServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$widgetSyncServiceHash();

  @$internal
  @override
  $ProviderElement<WidgetSyncService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WidgetSyncService create(Ref ref) {
    return widgetSyncService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WidgetSyncService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WidgetSyncService>(value),
    );
  }
}

String _$widgetSyncServiceHash() => r'd91d9318cf2ba45ec71103f38501a30a371fe9d8';
