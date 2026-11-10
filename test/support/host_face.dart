import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:mockmyapp/data/repositories/font_library.dart';

/// A real typeface read off the machine running the tests, or null when there
/// is none this process can read.
///
/// Deliberately not a binary committed to the repository. Registration is the
/// one part of the font pipeline `flutter test` can exercise end to end —
/// `FontLoader` needs no network, unlike everything that goes through
/// google_fonts — and half a megabyte of `.ttf` in version control to prove it
/// is a bad trade. A machine with no readable system fonts should skip the
/// groups that need one rather than fail them, so this returns null instead of
/// throwing and every caller guards on it.
Uint8List? readHostFace() {
  const roots = [
    'C:/Windows/Fonts',
    '/System/Library/Fonts',
    '/Library/Fonts',
    '/usr/share/fonts',
    '/usr/local/share/fonts',
  ];
  for (final root in roots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    var seen = 0;
    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        // Bounded, because `/usr/share/fonts` on a well-stocked Linux box is
        // thousands of files and this is a fixture, not a search.
        if (seen++ > 400) break;
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (ext != '.ttf' && ext != '.otf') continue;
        try {
          final bytes = entity.readAsBytesSync();
          // Filtered through the app's own check, so the fixture can never be
          // something the library would refuse — a `.ttc` under a `.ttf` name,
          // or a stub the OS keeps as a placeholder.
          if (bytes.length <= FontLibrary.maxFontBytes &&
              FontLibrary.looksLikeFont(bytes)) {
            return bytes;
          }
        } catch (_) {
          // Unreadable — a font file the OS has locked. Try the next one.
        }
      }
    } catch (_) {
      // A root that cannot be listed. Try the next one.
    }
  }
  return null;
}
