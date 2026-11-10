import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Encodes opaque [rgba] pixels as an RGB PNG with the browser's encoder, or
/// returns null when the browser would not leave the alpha channel out.
Future<Uint8List?> encodeOpaquePng(
  Uint8List rgba,
  int width,
  int height,
) async {
  final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
    ..width = width
    ..height = height;
  final context =
      canvas.getContext('2d', {'alpha': false}.jsify())
          as web.CanvasRenderingContext2D?;
  if (context == null) return null;
  context.putImageData(
    web.ImageData(Uint8ClampedList.sublistView(rgba).toJS, width, height.toJS),
    0,
    0,
  );

  final done = Completer<web.Blob?>();
  canvas.toBlob(((web.Blob? blob) => done.complete(blob)).toJS, 'image/png');
  final blob = await done.future;
  if (blob == null) return null;
  final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();

  // Byte 25 is the colour type in the IHDR chunk: 2 is RGB. A browser whose
  // encoder writes RGBA regardless (6) is no better than the engine.
  if (bytes.length < 26 || bytes[25] != 2) return null;
  return bytes;
}
