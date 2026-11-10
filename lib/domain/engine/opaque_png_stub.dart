import 'dart:typed_data';

/// Encodes opaque [rgba] pixels as an RGB PNG, or returns null where the
/// platform has no encoder of its own to do it with. Off the web, always null:
/// the caller encodes in Dart on a background isolate instead.
Future<Uint8List?> encodeOpaquePng(
  Uint8List rgba,
  int width,
  int height,
) async => null;
