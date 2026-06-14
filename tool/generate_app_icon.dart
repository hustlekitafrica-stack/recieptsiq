// Generates the ReceiptIQ launcher icons (no external designer needed).
//
// Run:  dart run tool/generate_app_icon.dart
// Then: dart run flutter_launcher_icons
//
// Produces:
//   assets/icon/icon.png             (full icon, indigo background)
//   assets/icon/icon_foreground.png  (transparent fg for Android adaptive)
import 'dart:io';

import 'package:image/image.dart' as img;

const int size = 1024;
final indigo = img.ColorRgba8(79, 70, 229, 255); // #4F46E5
final indigoDark = img.ColorRgba8(55, 48, 163, 255); // #3730A3
final white = img.ColorRgba8(255, 255, 255, 255);

void _drawReceiptGlyph(img.Image image) {
  // White "receipt paper" rounded rectangle, centred.
  const cx = size ~/ 2;
  const cy = size ~/ 2;
  const halfW = 190;
  const halfH = 250;
  img.fillRect(
    image,
    x1: cx - halfW,
    y1: cy - halfH,
    x2: cx + halfW,
    y2: cy + halfH,
    radius: 36,
    color: white,
  );

  // Indigo "text lines" on the paper.
  const lineLeft = cx - 130;
  final widths = [260, 260, 260, 180];
  final ys = [cy - 150, cy - 70, cy + 10, cy + 90];
  for (var i = 0; i < ys.length; i++) {
    img.fillRect(
      image,
      x1: lineLeft,
      y1: ys[i],
      x2: lineLeft + widths[i],
      y2: ys[i] + 34,
      radius: 17,
      color: indigo,
    );
  }

  // A small accent "total" bar near the bottom.
  img.fillRect(
    image,
    x1: lineLeft,
    y1: cy + 165,
    x2: lineLeft + 150,
    y2: cy + 205,
    radius: 20,
    color: indigoDark,
  );
}

void main() {
  Directory('assets/icon').createSync(recursive: true);

  // Full icon: indigo background + glyph.
  final full = img.Image(width: size, height: size, numChannels: 4);
  img.fill(full, color: indigo);
  _drawReceiptGlyph(full);
  File('assets/icon/icon.png').writeAsBytesSync(img.encodePng(full));

  // Adaptive foreground: transparent background + glyph.
  final fg = img.Image(width: size, height: size, numChannels: 4);
  img.fill(fg, color: img.ColorRgba8(0, 0, 0, 0));
  _drawReceiptGlyph(fg);
  File('assets/icon/icon_foreground.png').writeAsBytesSync(img.encodePng(fg));

  stdout.writeln('Generated assets/icon/icon.png and icon_foreground.png');
}
