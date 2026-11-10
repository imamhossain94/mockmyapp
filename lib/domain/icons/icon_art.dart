import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Path;
import 'package:google_fonts/google_fonts.dart';

import '../../data/assets/studio_fonts.dart';
import '../../data/repositories/stored_image.dart';
import '../models/icon_doc.dart';
import 'icon_painter.dart';
import 'lucide_glyphs.dart';

/// Gets everything [doc] needs before it can be painted: its glyph's outline,
/// its picture decoded, its monogram's typeface loaded.
///
/// The waiting lives here so the painter never waits. A glyph that is not in
/// the set, or a picture that has gone from the library, resolves to nothing
/// drawn for the foreground rather than an error: the background still makes
/// an icon, and the page says the picture is missing.
Future<IconArt> resolveIconArt(IconDoc doc) async {
  final glyph = switch (doc.glyph) {
    final name? => await LucideGlyphs.resolve(name),
    null => null,
  };

  ui.Image? image;
  var opaque = false;
  if (doc.imagePath case final path?) {
    final bytes = await StoredImage.bytes(path);
    if (bytes != null) {
      image = await decodeIconImage(bytes);
      if (image != null) opaque = await isOpaqueImage(image);
    }
  }

  if (doc.foreground case IconText(:final fontFamily, :final weight)) {
    // Asking for the style is what starts google_fonts loading the bundled
    // face; the painter then finds it registered.
    StudioFonts.style(fontFamily, fontWeight: weight);
    try {
      await GoogleFonts.pendingFonts();
    } catch (error) {
      debugPrint('Monogram typeface did not load: $error');
    }
  }

  return IconArt(doc, glyphPath: glyph, image: image, imageOpaque: opaque);
}

/// [bytes] decoded at their own size, or null when they are not a picture.
Future<ui.Image?> decodeIconImage(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } catch (error) {
    debugPrint('Icon picture did not decode: $error');
    return null;
  }
}

/// Whether [image] is opaque all over — no pixel in a coarse sample of it
/// lets anything through. A cut-out has transparency at its corners at the
/// very least; a photo has none.
Future<bool> isOpaqueImage(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return true;
  final pixels = data.buffer.asUint8List();
  final w = image.width;
  final h = image.height;
  final stepX = (w / 48).ceil().clamp(1, w);
  final stepY = (h / 48).ceil().clamp(1, h);
  for (var y = 0; y < h; y += stepY) {
    for (var x = 0; x < w; x += stepX) {
      if (pixels[(y * w + x) * 4 + 3] < 250) return false;
    }
  }
  // The corners, which the grid can step over and a cut-out always clears.
  for (final (x, y) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]) {
    if (pixels[(y * w + x) * 4 + 3] < 250) return false;
  }
  return true;
}

/// Decoded pictures and loaded typefaces, kept for the previews, so dragging a
/// slider on an icon with a picture repaints from memory instead of decoding
/// the file on every frame.
///
/// The export does not use it: it resolves afresh, so a file on disk that
/// changed is the file exported.
abstract final class IconArtCache {
  static final Map<String, ({ui.Image image, bool opaque})> _images = {};
  static final Map<String, Future<({ui.Image image, bool opaque})?>> _decoding =
      {};
  static final Set<String> _families = {};

  /// How many pictures are kept decoded; the oldest goes first.
  static const _keep = 12;

  /// [doc]'s art when everything it needs is already at hand — the glyphs
  /// loaded, its picture decoded, its typeface loaded — or null when
  /// [resolve] has to wait for something first.
  static IconArt? peek(IconDoc doc) {
    Path? glyph;
    if (doc.glyph case final name?) {
      if (LucideGlyphs.loaded == null) return null;
      glyph = LucideGlyphs.pathOf(name);
    }
    ({ui.Image image, bool opaque})? picture;
    if (doc.imagePath case final path?) {
      picture = _images[path];
      if (picture == null) return null;
    }
    if (doc.foreground case IconText(:final fontFamily)) {
      if (!_families.contains(fontFamily)) return null;
    }
    return IconArt(
      doc,
      glyphPath: glyph,
      image: picture?.image,
      imageOpaque: picture?.opaque ?? false,
    );
  }

  /// [doc]'s art, waiting for whatever [peek] lacked.
  static Future<IconArt> resolve(IconDoc doc) async {
    final ready = peek(doc);
    if (ready != null) return ready;
    if (doc.glyph != null) await LucideGlyphs.load();
    if (doc.imagePath case final path?) await _decode(path);
    if (doc.foreground case IconText(:final fontFamily, :final weight)) {
      StudioFonts.style(fontFamily, fontWeight: weight);
      try {
        await GoogleFonts.pendingFonts();
      } catch (error) {
        debugPrint('Monogram typeface did not load: $error');
      }
      _families.add(fontFamily);
    }
    return peek(doc) ??
        IconArt(
          doc,
          glyphPath: doc.glyph == null ? null : LucideGlyphs.pathOf(doc.glyph!),
        );
  }

  static Future<({ui.Image image, bool opaque})?> _decode(String path) =>
      _decoding[path] ??= () async {
        final bytes = await StoredImage.bytes(path);
        final image = bytes == null ? null : await decodeIconImage(bytes);
        if (image == null) {
          _decoding.remove(path);
          return null;
        }
        final entry = (image: image, opaque: await isOpaqueImage(image));
        _images[path] = entry;
        while (_images.length > _keep) {
          final oldest = _images.keys.first;
          _images.remove(oldest);
          _decoding.remove(oldest);
        }
        return entry;
      }();

  /// Forgets [path]'s picture — after it was replaced on disk.
  static void forget(String path) {
    _images.remove(path);
    _decoding.remove(path);
  }
}
