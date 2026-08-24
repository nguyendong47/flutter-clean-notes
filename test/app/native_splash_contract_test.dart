import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

const _lightCanvas = '#F4F6FF';
const _darkCanvas = '#0B1020';
const _markPath = 'assets/branding/aurora_launcher_foreground.png';
const _android12MarkPath = 'assets/branding/aurora_splash_mark.png';
const _markSha256 =
    'AA04546D2638D7D6EC8E7D021DB58073392295FAA2DB39833E125983B74A216B';
const _android12MarkSha256 =
    '6514C99920A02A5EE984CC2F670CE66F70D0BB964F9BD211874C52DB995EAA94';
const _androidNamespace = 'http://schemas.android.com/apk/res/android';

void main() {
  group('native splash contract', () {
    test('pins a build-time-only generator and disables web generation', () {
      // Mutation caught: moving the generator into runtime dependencies,
      // drifting its output version, or allowing it to rewrite Web startup.
      final pubspec = _yamlMap(loadYaml(_read('pubspec.yaml')));
      final dependencies = _yamlMap(pubspec['dependencies']);
      final devDependencies = _yamlMap(pubspec['dev_dependencies']);
      final config = _yamlMap(
        _yamlMap(
          loadYaml(_read('flutter_native_splash.yaml')),
        )['flutter_native_splash'],
      );
      final android12 = _yamlMap(config['android_12']);

      expect(dependencies.containsKey('flutter_native_splash'), isFalse);
      expect(devDependencies['flutter_native_splash'], '2.4.7');
      expect(config, containsPair('color', _lightCanvas));
      expect(config, containsPair('color_dark', _darkCanvas));
      expect(config, containsPair('image', _markPath));
      expect(config, containsPair('image_dark', _markPath));
      expect(config, containsPair('android', isTrue));
      expect(config, containsPair('ios', isTrue));
      expect(config, containsPair('web', isFalse));
      expect(config, containsPair('android_gravity', 'center'));
      expect(config, containsPair('ios_content_mode', 'center'));
      expect(config, containsPair('fullscreen', isFalse));
      expect(android12, containsPair('color', _lightCanvas));
      expect(android12, containsPair('color_dark', _darkCanvas));
      expect(android12, containsPair('image', _android12MarkPath));
      expect(android12, containsPair('image_dark', _android12MarkPath));
      expect(android12.containsKey('icon_background_color'), isFalse);
      expect(android12.containsKey('icon_background_color_dark'), isFalse);
    });

    test('uses the approved transparent Aurora mark at source resolution', () {
      // Mutation caught: replacing the reviewed mark with a low-resolution,
      // opaque, or otherwise unapproved source image.
      final mark = File(_markPath);
      expect(mark.existsSync(), isTrue);
      final bytes = mark.readAsBytesSync();
      final png = _pngInfo(bytes);

      expect(sha256.convert(bytes).toString().toUpperCase(), _markSha256);
      expect((png.width, png.height), (1254, 1254));
      expect(png.bitDepth, 8);
      expect(png.colorType, 6, reason: 'The launch mark must retain alpha.');
    });

    test('Android 12 mark fits the platform no-background circular mask', () {
      // Mutation caught: using the launcher foreground directly or scaling it
      // beyond Android's 192dp safe circle inside the 288dp icon canvas.
      final file = File(_android12MarkPath);
      expect(file.existsSync(), isTrue);
      final bytes = file.readAsBytesSync();
      final png = _pngInfo(bytes);
      final decoded = image.decodePng(bytes);

      expect(
        sha256.convert(bytes).toString().toUpperCase(),
        _android12MarkSha256,
      );
      expect((png.width, png.height), (1152, 1152));
      expect(png.colorType, 6);
      expect(decoded, isNotNull);
      var maxVisibleRadius = 0.0;
      const center = 575.5;
      for (final pixel in decoded!) {
        if (pixel.a < 16) continue;
        final dx = pixel.x - center;
        final dy = pixel.y - center;
        final radius = math.sqrt(dx * dx + dy * dy);
        if (radius > maxVisibleRadius) maxVisibleRadius = radius;
      }
      expect(
        maxVisibleRadius,
        lessThanOrEqualTo(384),
        reason: 'Meaningful pixels must stay inside Android 12 safe circle.',
      );
    });

    test('Android resources cover legacy, dark, and Android 12 startup', () {
      // Mutation caught: dropping a density, dark qualifier, centered mark,
      // or Android 12 theme mapping while regenerating splash resources.
      for (final path in <String>[
        'android/app/src/main/res/drawable/launch_background.xml',
        'android/app/src/main/res/drawable-v21/launch_background.xml',
        'android/app/src/main/res/drawable-night/launch_background.xml',
        'android/app/src/main/res/drawable-night-v21/launch_background.xml',
      ]) {
        final document = XmlDocument.parse(_read(path));
        final bitmaps = document.findAllElements('bitmap').toList();
        expect(bitmaps, hasLength(2), reason: path);
        expect(_androidAttribute(bitmaps[0], 'gravity'), 'fill', reason: path);
        expect(
          _androidAttribute(bitmaps[0], 'src'),
          '@drawable/background',
          reason: path,
        );
        expect(
          _androidAttribute(bitmaps[1], 'gravity'),
          'center',
          reason: path,
        );
        expect(
          _androidAttribute(bitmaps[1], 'src'),
          '@drawable/splash',
          reason: path,
        );
      }

      _expectAndroidImages('drawable', 'splash.png', _legacyDensitySizes);
      _expectAndroidImages('drawable-night', 'splash.png', _legacyDensitySizes);
      _expectAndroidImages(
        'drawable',
        'android12splash.png',
        _android12DensitySizes,
      );
      _expectAndroidImages(
        'drawable-night',
        'android12splash.png',
        _android12DensitySizes,
      );

      _expectAndroid12Theme(
        'android/app/src/main/res/values-v31/styles.xml',
        _lightCanvas,
      );
      _expectAndroid12Theme(
        'android/app/src/main/res/values-night-v31/styles.xml',
        _darkCanvas,
      );
    });

    test('iOS launch storyboard centers light and dark Aurora assets', () {
      // Mutation caught: losing the centered content mode, edge constraints,
      // or luminosity-aware image/background variants in the asset catalog.
      final storyboard = XmlDocument.parse(
        _read('ios/Runner/Base.lproj/LaunchScreen.storyboard'),
      );
      final launchImage = storyboard
          .findAllElements('imageView')
          .singleWhere(
            (element) => element.getAttribute('image') == 'LaunchImage',
          );
      final launchBackground = storyboard
          .findAllElements('imageView')
          .singleWhere(
            (element) => element.getAttribute('image') == 'LaunchBackground',
          );
      final constraintIds = storyboard
          .findAllElements('constraint')
          .map((element) => element.getAttribute('id'))
          .whereType<String>()
          .toSet();

      expect(launchImage.getAttribute('contentMode'), 'center');
      expect(launchBackground.getAttribute('contentMode'), 'scaleToFill');
      expect(
        constraintIds,
        containsAll(<String>{
          '3T2-ad-Qdv',
          'RPx-PI-7Xg',
          'SdS-ul-q2q',
          'Swv-Gf-Rwn',
          'TQA-XW-tRk',
          'duK-uY-Gun',
          'kV7-tw-vXt',
          'xPn-NY-SIU',
        }),
      );

      final launchContents = _jsonMap(
        _read('ios/Runner/Assets.xcassets/LaunchImage.imageset/Contents.json'),
      );
      final launchImages = _jsonMaps(launchContents['images']);
      expect(
        launchImages
            .map((image) => image['filename'])
            .whereType<String>()
            .toSet(),
        <String>{
          'LaunchImage.png',
          'LaunchImage@2x.png',
          'LaunchImage@3x.png',
          'LaunchImageDark.png',
          'LaunchImageDark@2x.png',
          'LaunchImageDark@3x.png',
        },
      );
      expect(launchImages.where(_hasDarkAppearance), hasLength(3));

      final backgroundContents = _jsonMap(
        _read(
          'ios/Runner/Assets.xcassets/LaunchBackground.imageset/Contents.json',
        ),
      );
      final backgrounds = _jsonMaps(backgroundContents['images']);
      expect(
        backgrounds
            .map((image) => image['filename'])
            .whereType<String>()
            .toSet(),
        {'background.png', 'darkbackground.png'},
      );
      expect(backgrounds.where(_hasDarkAppearance), hasLength(1));

      _expectPngDimensions(
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png',
        313,
      );
      _expectPngDimensions(
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png',
        627,
      );
      _expectPngDimensions(
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png',
        940,
      );
    });
  });
}

const _legacyDensitySizes = <String, int>{
  'mdpi': 313,
  'hdpi': 470,
  'xhdpi': 627,
  'xxhdpi': 940,
  'xxxhdpi': 1254,
};

const _android12DensitySizes = <String, int>{
  'mdpi': 288,
  'hdpi': 432,
  'xhdpi': 576,
  'xxhdpi': 864,
  'xxxhdpi': 1152,
};

void _expectAndroidImages(
  String prefix,
  String fileName,
  Map<String, int> sizes,
) {
  for (final MapEntry(key: density, value: size) in sizes.entries) {
    _expectPngDimensions(
      'android/app/src/main/res/$prefix-$density/$fileName',
      size,
    );
  }
}

void _expectAndroid12Theme(String path, String expectedColor) {
  final document = XmlDocument.parse(_read(path));
  final launchTheme = document
      .findAllElements('style')
      .singleWhere((style) => style.getAttribute('name') == 'LaunchTheme');
  final items = <String, String>{
    for (final item in launchTheme.findElements('item'))
      item.getAttribute('name')!: item.innerText,
  };

  expect(items['android:windowSplashScreenBackground'], expectedColor);
  expect(
    items['android:windowSplashScreenAnimatedIcon'],
    '@drawable/android12splash',
  );
  expect(
    items.containsKey('android:windowSplashScreenIconBackgroundColor'),
    isFalse,
  );
  expect(items['android:windowFullscreen'], 'false');
  expect(items['android:windowDrawsSystemBarBackgrounds'], 'false');
  expect(items['android:windowLayoutInDisplayCutoutMode'], 'shortEdges');
}

void _expectPngDimensions(String path, int size) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: path);
  final png = _pngInfo(file.readAsBytesSync());
  expect((png.width, png.height), (size, size), reason: path);
}

({int width, int height, int bitDepth, int colorType}) _pngInfo(
  Uint8List bytes,
) {
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  expect(bytes.length, greaterThanOrEqualTo(26));
  expect(bytes.sublist(0, signature.length), signature);
  expect(ascii.decode(bytes.sublist(12, 16)), 'IHDR');
  final data = ByteData.sublistView(bytes);
  return (
    width: data.getUint32(16),
    height: data.getUint32(20),
    bitDepth: bytes[24],
    colorType: bytes[25],
  );
}

YamlMap _yamlMap(Object? value) {
  expect(value, isA<YamlMap>());
  return value! as YamlMap;
}

Map<String, Object?> _jsonMap(String source) =>
    (jsonDecode(source) as Map).cast<String, Object?>();

List<Map<String, Object?>> _jsonMaps(Object? value) => (value! as List)
    .map((entry) => (entry as Map).cast<String, Object?>())
    .toList(growable: false);

bool _hasDarkAppearance(Map<String, Object?> image) {
  final appearances = image['appearances'];
  if (appearances is! List) return false;
  return appearances.whereType<Map>().any(
    (appearance) =>
        appearance['appearance'] == 'luminosity' &&
        appearance['value'] == 'dark',
  );
}

String? _androidAttribute(XmlElement element, String name) =>
    element.getAttribute(name, namespaceUri: _androidNamespace);

String _read(String path) => File(path).readAsStringSync();
