// Builds windows/runner/resources/app_icon.ico (PNG-compressed, 6 sizes) from
// assets/branding/app_icon.webp.  Usage: dart run tool/make_icon.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

void main() {
  final src = img.decodeWebP(File('assets/branding/app_icon.webp').readAsBytesSync());
  if (src == null) throw StateError('cannot decode webp');

  // Square canvas, transparent padding, so the artwork is never stretched.
  final side = src.width > src.height ? src.width : src.height;
  final square = img.Image(width: side, height: side, numChannels: 4);
  img.compositeImage(square, src,
      dstX: (side - src.width) ~/ 2, dstY: (side - src.height) ~/ 2);

  const sizes = [16, 32, 48, 64, 128, 256];
  final pngs = [
    for (final s in sizes)
      img.encodePng(img.copyResize(square,
          width: s, height: s, interpolation: img.Interpolation.cubic)),
  ];

  final out = BytesBuilder();
  final header = ByteData(6)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, sizes.length, Endian.little);
  out.add(header.buffer.asUint8List());
  var offset = 6 + 16 * sizes.length;
  for (var i = 0; i < sizes.length; i++) {
    final e = ByteData(16);
    e.setUint8(0, sizes[i] == 256 ? 0 : sizes[i]);
    e.setUint8(1, sizes[i] == 256 ? 0 : sizes[i]);
    e.setUint16(4, 1, Endian.little); // planes
    e.setUint16(6, 32, Endian.little); // bpp
    e.setUint32(8, pngs[i].length, Endian.little);
    e.setUint32(12, offset, Endian.little);
    out.add(e.buffer.asUint8List());
    offset += pngs[i].length;
  }
  for (final p in pngs) {
    out.add(p);
  }
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(out.toBytes());
  print('wrote app_icon.ico (${out.length} bytes, ${src.width}x${src.height} source)');
}
