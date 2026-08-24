import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter_clean_notes/app/app_providers.dart';
import 'package:flutter_clean_notes/app/notification_service.dart';
import 'package:flutter_clean_notes/app/router.dart';
import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';

Future<void> main() => bootstrapApplication();

@visibleForTesting
Future<void> bootstrapApplication({
  NotificationService? notificationService,
  FutureOr<void> Function()? initializeDatabase,
  ProviderContainer Function(NotificationService notificationService)?
  createContainer,
  void Function(Widget app)? runApplication,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final databaseInitializer = initializeDatabase;
  if (databaseInitializer == null) {
    _initializeDatabase();
  } else {
    await Future<void>.sync(databaseInitializer);
  }

  final notifications = notificationService ?? NotificationService();
  await notifications.init();

  final container = (createContainer ?? _createAppContainer)(notifications);
  var handedOff = false;
  try {
    await container.read(appThemeProvider.future);
    (runApplication ?? runApp)(
      UncontrolledProviderScope(container: container, child: const MyApp()),
    );
    handedOff = true;
  } finally {
    if (!handedOff) container.dispose();
  }
}

void _initializeDatabase() {
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

ProviderContainer _createAppContainer(NotificationService notificationService) {
  return ProviderContainer(
    overrides: [
      notificationServiceProvider.overrideWithValue(notificationService),
    ],
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeProvider).value ?? ThemeMode.system;

    return MaterialApp.router(
      title: 'Clean Notes',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      theme: AuroraTheme.light(),
      darkTheme: AuroraTheme.dark(),
      themeMode: themeMode,
    );
  }
}
