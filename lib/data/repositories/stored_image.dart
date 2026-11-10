import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'image_library.dart';

/// The one way to turn a stored image path into pixels.
///
/// Every screen used to reach for `File(ImageLibrary.resolve(path))` directly.
/// That is a `dart:io` call, and on the web `dart:io` is a stub whose *type
/// constructors* already throw — `Unsupported operation: _Namespace` before any
/// read is attempted. So a single missing platform turned into a failure at
/// seven unrelated call sites, each with its own error handling.
///
/// Routing them all through here means the platform question is asked once. On
/// a device the answer is a file; on the web it is the bytes [ImageLibrary]
/// kept from the import, because there is nowhere to put a file.
abstract final class StoredImage {
  /// Marks a path that names a picture shipped inside the app bundle rather
  /// than one in the user's library.
  ///
  /// The built-in templates need real artwork to show — a listing's design is
  /// half its screenshots — and that artwork is compiled in rather than
  /// imported, so it has no library entry, no file on disk and nothing to
  /// repoint when the app container moves. A scheme rather than a bare
  /// `assets/` prefix so nothing a user imports can ever be mistaken for one.
  static const assetScheme = 'asset:';

  /// Whether [stored] names a bundled asset.
  ///
  /// Every path that leaves the app — a backup's manifest, a library sweep —
  /// has to ask this, because a bundled asset must not be packed into an
  /// archive (it is already in every copy of the app) and must not be
  /// repointed on the way back in (there is no file to point at).
  static bool isAsset(String? stored) =>
      stored != null && stored.startsWith(assetScheme);

  /// An image provider for [stored], or null when there is nothing to show.
  ///
  /// Null rather than a throwing provider: every caller already has a fallback
  /// for a picture that has gone — the empty screen, a placeholder glyph — and
  /// a missing image should reach that, not an error box baked into an export.
  static ImageProvider? provider(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    if (isAsset(stored)) {
      return AssetImage(stored.substring(assetScheme.length));
    }

    // Bytes held from an import come first, and are checked on every platform
    // rather than only on the web: it makes the memory path something a test
    // can exercise without pretending to be a browser.
    final held = ImageLibrary.sessionBytes(stored);
    if (held != null) return MemoryImage(held);

    // Only the web has no filesystem at all. A document can legitimately name
    // an absolute path outside the library folder — one restored from a backup,
    // say — so "the library folder never resolved" is not a reason to refuse to
    // look.
    if (kIsWeb) return null;
    return FileImage(File(ImageLibrary.resolve(stored)));
  }

  /// The raw bytes behind [stored], or null when it cannot be read.
  static Future<Uint8List?> bytes(String? stored) async {
    if (stored == null || stored.isEmpty) return null;
    if (isAsset(stored)) {
      try {
        final data = await rootBundle.load(
          stored.substring(assetScheme.length),
        );
        return data.buffer.asUint8List();
      } catch (_) {
        return null;
      }
    }

    final held = ImageLibrary.sessionBytes(stored);
    if (held != null) return held;

    if (kIsWeb) return null;
    try {
      return await File(ImageLibrary.resolve(stored)).readAsBytes();
    } catch (_) {
      return null;
    }
  }
}
