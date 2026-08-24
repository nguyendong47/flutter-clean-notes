import 'package:flutter/foundation.dart';
import 'package:flutter_clean_notes/app/notification_service.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/note_reminder_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_note_reminder_gateway.dart';

void main() {
  final platformCases =
      <({String name, bool isWeb, TargetPlatform platform, bool supported})>[
        (
          name: 'Android',
          isWeb: false,
          platform: TargetPlatform.android,
          supported: true,
        ),
        (
          name: 'iOS',
          isWeb: false,
          platform: TargetPlatform.iOS,
          supported: true,
        ),
        (
          name: 'macOS',
          isWeb: false,
          platform: TargetPlatform.macOS,
          supported: true,
        ),
        (
          name: 'Windows',
          isWeb: false,
          platform: TargetPlatform.windows,
          supported: false,
        ),
        (
          name: 'Linux',
          isWeb: false,
          platform: TargetPlatform.linux,
          supported: false,
        ),
        (
          name: 'Fuchsia',
          isWeb: false,
          platform: TargetPlatform.fuchsia,
          supported: false,
        ),
        (
          name: 'Web on Android host',
          isWeb: true,
          platform: TargetPlatform.android,
          supported: false,
        ),
        (
          name: 'Web on macOS host',
          isWeb: true,
          platform: TargetPlatform.macOS,
          supported: false,
        ),
      ];

  for (final testCase in platformCases) {
    test('${testCase.name} reminder scheduling support is explicit', () {
      expect(
        supportsReminderSchedulingOn(
          isWeb: testCase.isWeb,
          platform: testCase.platform,
        ),
        testCase.supported,
      );
    });
  }

  test('concrete gateway exposes the service platform capability', () {
    final gateway = NotificationNoteReminderGateway(
      NotificationService(now: DateTime.now),
    );
    try {
      for (final testCase in platformCases.where(
        (testCase) => !testCase.isWeb,
      )) {
        debugDefaultTargetPlatformOverride = testCase.platform;
        expect(
          gateway.supportsScheduling,
          testCase.supported,
          reason: testCase.platform.name,
        );
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('fake gateway defaults supported and can model unsupported targets', () {
    expect(FakeNoteReminderGateway().supportsScheduling, isTrue);
    expect(
      FakeNoteReminderGateway(supportsScheduling: false).supportsScheduling,
      isFalse,
    );
  });
}
