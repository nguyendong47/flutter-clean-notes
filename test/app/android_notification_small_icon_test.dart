import 'dart:io';

import 'package:flutter_clean_notes/app/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _androidNamespace = 'http://schemas.android.com/apk/res/android';
const _toolsNamespace = 'http://schemas.android.com/tools';
const _iconResourceName = 'ic_stat_clean_notes';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'notification initialization uses the dedicated drawable icon',
    () async {
      final plugin = _InitializationCapturePlugin();

      await NotificationService(plugin: plugin).init();

      final icon = plugin.settings?.android?.defaultIcon;
      expect(icon, _iconResourceName);
      expect(icon, isNot(contains('ic_launcher')));
      expect(icon, isNot(startsWith('@')));
    },
  );

  test('notification icon is a transparent monochrome 24dp vector', () {
    final iconFile = File(
      'android/app/src/main/res/drawable/$_iconResourceName.xml',
    );
    expect(iconFile.existsSync(), isTrue, reason: 'Missing notification icon');

    final vector = XmlDocument.parse(iconFile.readAsStringSync()).rootElement;
    expect(vector.name.local, 'vector');
    expect(
      vector.getAttribute('width', namespaceUri: _androidNamespace),
      '24dp',
    );
    expect(
      vector.getAttribute('height', namespaceUri: _androidNamespace),
      '24dp',
    );
    expect(
      vector.getAttribute('viewportWidth', namespaceUri: _androidNamespace),
      '24',
    );
    expect(
      vector.getAttribute('viewportHeight', namespaceUri: _androidNamespace),
      '24',
    );

    final paths = vector.findElements('path').toList(growable: false);
    expect(paths, hasLength(greaterThanOrEqualTo(3)));

    final fillColors = paths
        .map(
          (path) =>
              path.getAttribute('fillColor', namespaceUri: _androidNamespace),
        )
        .whereType<String>()
        .toList(growable: false);
    final strokeColors = paths
        .map(
          (path) =>
              path.getAttribute('strokeColor', namespaceUri: _androidNamespace),
        )
        .whereType<String>()
        .toList(growable: false);
    expect(fillColors, contains('#00000000'));
    expect(fillColors, contains('#FFFFFFFF'));
    expect(
      [...fillColors, ...strokeColors],
      everyElement(anyOf('#00000000', '#FFFFFFFF')),
      reason: 'Status icons must use only transparent and opaque white pixels',
    );

    final coordinatePattern = RegExp(r'-?\d+(?:\.\d+)?');
    final pathCoordinates = paths
        .map(
          (path) =>
              path.getAttribute('pathData', namespaceUri: _androidNamespace),
        )
        .whereType<String>()
        .expand(coordinatePattern.allMatches)
        .map((match) => double.parse(match.group(0)!))
        .toList(growable: false);
    expect(pathCoordinates, isNotEmpty);
    expect(
      pathCoordinates,
      everyElement(inInclusiveRange(1.5, 22.5)),
      reason: 'Icon geometry must stay inside the viewport safety margin',
    );

    final coordinatePairPattern = RegExp(
      r'(?:M|L)\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?)',
    );
    final opaquePaths = paths.where(
      (path) =>
          path.getAttribute('fillColor', namespaceUri: _androidNamespace) ==
          '#FFFFFFFF',
    );
    for (final path in opaquePaths) {
      final pathData = path.getAttribute(
        'pathData',
        namespaceUri: _androidNamespace,
      )!;
      final coordinatePairs = coordinatePairPattern
          .allMatches(pathData)
          .map(
            (match) => (
              x: double.parse(match.group(1)!),
              y: double.parse(match.group(2)!),
            ),
          )
          .toList(growable: false);
      expect(coordinatePairs, hasLength(greaterThanOrEqualTo(3)));

      final xCoordinates = coordinatePairs.map((pair) => pair.x).toList()
        ..sort();
      final yCoordinates = coordinatePairs.map((pair) => pair.y).toList()
        ..sort();
      final coversMostOfViewport =
          xCoordinates.last - xCoordinates.first >= 19.2 &&
          yCoordinates.last - yCoordinates.first >= 19.2;
      expect(
        coversMostOfViewport,
        isFalse,
        reason: 'Opaque icon paths must not form a full-background tile',
      );
    }
  });

  test('release resource rules keep the string-referenced icon', () {
    final keepFile = File('android/app/src/main/res/raw/keep.xml');
    expect(
      keepFile.existsSync(),
      isTrue,
      reason: 'Missing resource keep rules',
    );

    final resources = XmlDocument.parse(
      keepFile.readAsStringSync(),
    ).rootElement;
    expect(resources.name.local, 'resources');
    expect(
      resources.getAttribute('keep', namespaceUri: _toolsNamespace),
      '@drawable/$_iconResourceName',
    );
  });
}

class _InitializationCapturePlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  InitializationSettings? settings;

  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    settings = initializationSettings;
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async {
    return const NotificationAppLaunchDetails(false);
  }
}
