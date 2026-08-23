// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(themeModeStore)
final themeModeStoreProvider = ThemeModeStoreProvider._();

final class ThemeModeStoreProvider
    extends $FunctionalProvider<ThemeModeStore, ThemeModeStore, ThemeModeStore>
    with $Provider<ThemeModeStore> {
  ThemeModeStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'themeModeStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$themeModeStoreHash();

  @$internal
  @override
  $ProviderElement<ThemeModeStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ThemeModeStore create(Ref ref) {
    return themeModeStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeModeStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeModeStore>(value),
    );
  }
}

String _$themeModeStoreHash() => r'893a7f246b4fd34bf5d0d71071301a44bec56aef';

/// Theme mode controller that respects a saved preference.

@ProviderFor(AppTheme)
final appThemeProvider = AppThemeProvider._();

/// Theme mode controller that respects a saved preference.
final class AppThemeProvider
    extends $AsyncNotifierProvider<AppTheme, ThemeMode> {
  /// Theme mode controller that respects a saved preference.
  AppThemeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appThemeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appThemeHash();

  @$internal
  @override
  AppTheme create() => AppTheme();
}

String _$appThemeHash() => r'7481b1783c43851ca0487a2dfbb0f7457a1a479a';

/// Theme mode controller that respects a saved preference.

abstract class _$AppTheme extends $AsyncNotifier<ThemeMode> {
  FutureOr<ThemeMode> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ThemeMode>, ThemeMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ThemeMode>, ThemeMode>,
              AsyncValue<ThemeMode>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
