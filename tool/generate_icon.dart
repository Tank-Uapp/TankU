// Builds the TankU launcher icon and in-app brand mark from the source artwork
// — a clownfish wearing a graduation cap (Tank University) — and writes:
//   assets/icon/tanku_icon.png        full-bleed blue gradient + fish (iOS/web/legacy)
//   assets/icon/tanku_foreground.png  transparent + fish, sized for the Android
//                                     adaptive-icon safe zone
//   assets/icon/tanku_mark.png        transparent, tightly trimmed fish for the
//                                     in-app brand header
//
// The fish is lifted off its flat blue background with a blue-key flood fill
// from the canvas edges, so the cap's navy, the fish's orange, and the white
// outline are all preserved while the background and its drop shadow drop out.
//
// Run after `flutter pub get`:
//   dart run tool/generate_icon.dart
// then `dart run flutter_launcher_icons` to slice the icons per platform.

import 'dart:io';

import 'package:image/image.dart' as img;

const _size = 1024;
const _source = 'assets/icon/tanku_source.png';

int _lerp(int a, int b, double t) => (a + (b - a) * t).round();

/// Diagonal cyan → deep-blue water gradient across the whole canvas.
void _fillGradient(img.Image image) {
  for (var y = 0; y < _size; y++) {
    for (var x = 0; x < _size; x++) {
      final t = ((x + y) / (2 * _size)).clamp(0.0, 1.0);
      image.setPixelRgba(
        x,
        y,
        _lerp(0x4F, 0x02, t), // R: 4F..02
        _lerp(0xC3, 0x77, t), // G: C3..77
        _lerp(0xF7, 0xBD, t), // B: F7..BD
        255,
      );
    }
  }
}

/// True for the artwork's flat blue background and its drop shadow: blue/cyan
/// dominant, never matching the fish's orange, white outline, or navy cap.
bool _isBackground(img.Pixel px) {
  final r = px.r, g = px.g, b = px.b;
  return r < 150 && b > 150 && g > 95 && b >= g;
}

/// Returns a copy of [src] with the connected background region (reached by a
/// flood fill seeded from every edge pixel) made fully transparent.
img.Image _removeBackground(img.Image src) {
  final w = src.width, h = src.height;
  final out = src.convert(numChannels: 4);
  final seen = List<bool>.filled(w * h, false);
  final stack = <int>[];

  void seed(int x, int y) {
    final i = y * w + x;
    if (!seen[i] && _isBackground(src.getPixel(x, y))) {
      seen[i] = true;
      stack.add(i);
    }
  }

  for (var x = 0; x < w; x++) {
    seed(x, 0);
    seed(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    seed(0, y);
    seed(w - 1, y);
  }

  final clear = img.ColorRgba8(0, 0, 0, 0);
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final x = i % w, y = i ~/ w;
    out.setPixel(x, y, clear);
    if (x > 0) seed(x - 1, y);
    if (x < w - 1) seed(x + 1, y);
    if (y > 0) seed(x, y - 1);
    if (y < h - 1) seed(x, y + 1);
  }
  return out;
}

/// Tight bounding box of the non-transparent pixels in [image].
img.Image _trim(img.Image image) {
  var minX = image.width, minY = image.height, maxX = -1, maxY = -1;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (image.getPixel(x, y).a > 8) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return image;
  return img.copyCrop(image,
      x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
}

/// Centers [mark] onto a [_size]² canvas, scaled so its longest side covers
/// [coverage] of the canvas.
img.Image _place(img.Image mark, double coverage) {
  final target = _size * coverage;
  final scale = target / (mark.width > mark.height ? mark.width : mark.height);
  final resized = img.copyResize(
    mark,
    width: (mark.width * scale).round(),
    height: (mark.height * scale).round(),
    interpolation: img.Interpolation.cubic,
  );
  final canvas = img.Image(width: _size, height: _size, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  img.compositeImage(
    canvas,
    resized,
    dstX: ((_size - resized.width) / 2).round(),
    dstY: ((_size - resized.height) / 2).round(),
  );
  return canvas;
}

void _write(String path, img.Image image) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
  stdout.writeln('wrote $path');
}

void main() {
  final source = img.decodePng(File(_source).readAsBytesSync());
  if (source == null) {
    stderr.writeln('could not read $_source');
    exit(1);
  }
  final fish = _trim(_removeBackground(source));

  // Full-bleed icon: fish over the brand water gradient.
  final icon = img.Image(width: _size, height: _size, numChannels: 4);
  _fillGradient(icon);
  final fishLayer = _place(fish, 0.82);
  img.compositeImage(icon, fishLayer);
  _write('assets/icon/tanku_icon.png', icon);

  // Adaptive foreground: transparent, fish scaled into the central safe zone.
  _write('assets/icon/tanku_foreground.png', _place(fish, 0.66));

  // In-app brand mark: transparent, tightly trimmed fish.
  _write('assets/icon/tanku_mark.png', _place(fish, 0.92));
}
