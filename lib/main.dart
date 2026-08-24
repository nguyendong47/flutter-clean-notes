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
import 'package:flutter_clean_notes/features/notes/domain/services/reminder_coordinator.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_reminder_gateway_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';

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
  final container = (createContainer ?? _createAppContainer)(notifications);
  var handedOff = false;
  try {
    final reminderCoordinator = container.read(reminderCoordinatorProvider);
    notifications.attachSnoozeHandler(({
      required noteId,
      required expectedGeneration,
      required delayMinutes,
    }) async {
      final notesSubscription = container.listen(
        notesProvider,
        (_, _) {},
        fireImmediately: true,
      );
      try {
        try {
          await container.read(notesProvider.future);
        } catch (_) {
          // The snooze transaction must still run. Its refresh below gets an
          // independent chance to recover the presentation cache.
        }
        return await container
            .read(notesProvider.notifier)
            .snoozeReminderFromNotification(
              noteId: noteId,
              expectedGeneration: expectedGeneration,
              delayMinutes: delayMinutes,
            );
      } finally {
        notesSubscription.close();
      }
    });
    await notifications.init();
    await container.read(appThemeProvider.future);
    (runApplication ?? runApp)(
      UncontrolledProviderScope(container: container, child: const MyApp()),
    );
    handedOff = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        synchronizeRemindersAfterStartup(
          notifications: notifications,
          reminderCoordinator: reminderCoordinator,
        ).onError((error, stackTrace) {
          _reportReminderReconciliationFailure(error, stackTrace);
        }),
      );
    });
  } finally {
    if (!handedOff) container.dispose();
  }
}

@visibleForTesting
Future<void> synchronizeRemindersAfterStartup({
  required NotificationService notifications,
  required ReminderSyncCoordinator reminderCoordinator,
}) async {
  try {
    await notifications.init();
    await reminderCoordinator.reconcileAtStartup();
  } finally {
    // A coordinator-triggered recovery waits only for native readiness so it
    // cannot deadlock on a cold action queued behind that coordinator. Once
    // reconciliation releases the lock, finish that action before allowing
    // the startup task to complete.
    await notifications.waitForCurrentInitialization();
  }
}

void _reportReminderReconciliationFailure(Object? error, StackTrace _) {
  if (error is NotificationUnavailableException) return;
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: const _ReminderReconciliationFailure(),
      stack: StackTrace.current,
      library: 'reminder reconciliation',
      context: ErrorDescription('while reconciling durable reminders'),
      informationCollector: () => <DiagnosticsNode>[
        StringProperty('Native failure type', error.runtimeType.toString()),
      ],
    ),
  );
}

final class _ReminderReconciliationFailure implements Exception {
  const _ReminderReconciliationFailure();

  @override
  String toString() => 'Reminder reconciliation will retry later.';
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
