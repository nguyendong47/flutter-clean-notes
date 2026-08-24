import 'dart:io';

import 'package:image/image.dart' as image;

const _sourcePath = 'assets/branding/aurora_launcher_foreground.png';
const _targetPath = 'assets/branding/aurora_splash_mark.png';
const _sourceSize = 1254;
const _markSize = 960;
const _canvasSize = 1152;

void main() {
  final sourceFile = File(_sourcePath);
  if (!sourceFile.existsSync()) {
    throw StateError('Aurora source mark not found at $_sourcePath.');
  }

  final source = image.decodePng(sourceFile.readAsBytesSync());
  if (source == null ||
      source.width != _sourceSize ||
      source.height != _sourceSize ||
      source.numChannels < 4) {
    throw StateError(
      'Aurora source mark must be a ${_sourceSize}x$_sourceSize RGBA PNG.',
    );
  }

  final mark = image.copyResize(
    source,
    width: _markSize,
    height: _markSize,
    interpolation: image.Interpolation.average,
  );
  final canvas = image.Image(
    width: _canvasSize,
    height: _canvasSize,
    numChannels: 4,
  );
  image.fill(canvas, color: image.ColorRgba8(0, 0, 0, 0));
  image.compositeImage(canvas, mark, center: true);

  File(_targetPath).writeAsBytesSync(
    image.encodePng(canvas, level: 6, filter: image.PngFilter.paeth),
    flush: true,
  );
}
