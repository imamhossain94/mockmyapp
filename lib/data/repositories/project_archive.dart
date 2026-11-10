import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/icon_doc.dart';
import '../../domain/models/project.dart';
import '../../domain/models/screen_doc.dart';
import '../../domain/models/sub_project.dart';
import 'font_library.dart';
import 'image_library.dart';
import 'stored_image.dart';

/// Raised when a file handed to [ProjectArchive.read] is not a backup this app
/// can restore. The message is written to be shown to the user as-is.
class ProjectArchiveException implements Exception {
  const ProjectArchiveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One image travelling inside a bundle.
@immutable
class BundledImage {
  const BundledImage({
    required this.fileName,
    required this.bytes,
    required this.kind,
  });

  /// Leaf name the file had in the source device's library. Documents are
  /// re-pointed by this, not by the absolute path they were saved with.
  final String fileName;

  final Uint8List bytes;
  final LibraryImageKind kind;
}

/// One uploaded typeface travelling inside a bundle.
@immutable
class BundledFont {
  const BundledFont({
    required this.id,
    required this.fileName,
    required this.label,
    required this.bytes,
  });

  /// The id the *source* device minted, and the one this device restores the
  /// font under. Unlike an image's file name this is carried through unchanged
  /// — see [ProjectArchive]'s class comment for why fonts are the exception.
  final String id;

  final String fileName;

  /// The label the source device showed in its picker, so a restored font is
  /// still called what the user called it.
  final String label;

  final Uint8List bytes;
}

/// A backup read back off disk: the document, plus the artwork it needs.
@immutable
class ProjectBundle {
  const ProjectBundle({
    required this.project,
    required this.images,
    this.fonts = const [],
  });

  /// Still carrying the *source* device's image paths. Restoring means writing
  /// [images] into this device's library and running the result through
  /// [ProjectArchive.remapImages].
  final Project project;

  final List<BundledImage> images;

  /// Defaulted, so every existing construction of a bundle — and every test
  /// that builds one — kept compiling when fonts were added.
  final List<BundledFont> fonts;
}

/// Reads and writes project backups.
///
/// A document only ever stores *paths* to its artwork ([ScreenshotSpec.imagePath],
/// [ImageBackground.path]), because the bytes live once in [ImageLibrary] and
/// are shared across every screen of every sub-project. [ImageLibrary.resolve]
/// repairs those paths when the app's container moves, but it does so by
/// finding the same file name in *this* device's library — so a bare JSON
/// backup opened on a second device resolves to nothing and every screenshot
/// falls back to the placeholder.
///
/// The bundle therefore ships the pixels alongside the document:
///
/// ```
/// manifest.json     format + version + the kind of each image + font ids
/// project.json      byte-for-byte what a JSON backup always contained
/// images/<name>     one entry per referenced file, byte-identical copies
/// fonts/<name>      one entry per uploaded typeface the captions use
/// ```
///
/// Version 2 is a project of [SubProject]s, one per store target, each holding
/// its own canvas and its own screens. Version 1 was a single `platform` over
/// one flat screen list, and those bundles still restore untouched: nothing in
/// here has to know the older shape, because [Project.fromJson] folds it into a
/// single sub-project on the way in. That is why the version is only ever
/// checked upwards — a bundle written by a *newer* build is the only one this
/// one has to refuse.
///
/// **The `fonts/` directory did not bump the version, deliberately.** [read]
/// filters entries with `p.dirname(file.name) != _imageDir`, so a build shipped
/// before fonts existed skips the whole directory in silence and restores the
/// project intact, with any caption in an uploaded face falling back to Roboto.
/// Bumping to 3 would instead make every one of those builds refuse the backup
/// outright with "made by a newer version". A missing typeface is cosmetic; a
/// refused restore loses the work.
///
/// **Font ids survive a restore; image file names do not.** An image is
/// re-minted per project on the way in, because a picture belongs to one
/// project and has to be byte-copied so that clearing one project can never
/// blank a screen in another. A typeface is app-global (see [FontLibrary]), so
/// a second reference to the same id is *correct* — and re-minting would drop
/// a duplicate into the font picker every time the same backup was restored.
/// That is why there is no `remapFonts` to match [remapImages]: the ids in
/// `project.json` are already the ids this device will use.
///
/// A plain `.json` file is still accepted by [read] so backups taken before
/// this existed keep importing — without artwork, exactly as they do today.
abstract final class ProjectArchive {
  static const fileExtension = 'zip';
  static const mimeType = 'application/zip';

  static const _format = 'mockmyapp-project';

  /// Every format id a backup may carry. The app shipped as Mockup Studio and
  /// then Mockdeck under the old id, and those backups must keep importing.
  static const _formats = {_format, 'mockup-studio-project'};
  static const _version = 2;
  static const _manifestEntry = 'manifest.json';
  static const _projectEntry = 'project.json';
  static const _imageDir = 'images';
  static const _fontDir = 'fonts';

  /// Packs [project], every image it references and every uploaded typeface its
  /// captions are set in into a zip.
  ///
  /// A reference whose file is gone — the user deleted it from the library —
  /// is skipped rather than failing the backup: the rest of the project is
  /// still worth saving, and that screen was already showing a placeholder.
  static Future<Uint8List> bundle(Project project) async {
    final archive = Archive();
    final manifestImages = <Map<String, dynamic>>[];
    final manifestFonts = <Map<String, dynamic>>[];

    for (final MapEntry(key: storedPath, value: kind) in referencedImages(
      project,
    ).entries) {
      // Through [StoredImage], not `File` directly: where an image's bytes live
      // is a platform question, and on the web the `File` constructor alone
      // threw before a backup could be built at all. A picture that has gone
      // still yields null and is skipped, exactly as a missing file was.
      final bytes = await StoredImage.bytes(storedPath);
      if (bytes == null) continue;
      final fileName = p.basename(storedPath);
      archive.add(ArchiveFile.typedData('$_imageDir/$fileName', bytes));
      manifestImages.add({'fileName': fileName, 'kind': kind.name});
    }

    for (final family in referencedFonts(project)) {
      // Nothing to pack for a face this device never had — a project restored
      // here from someone else's backup, then backed up again. The reference
      // stays in the document, so the day the file does arrive under that id
      // every caption using it resolves again.
      final entry = FontLibrary.entryOf(family);
      if (entry == null) continue;
      final data = await FontLibrary.bytes(entry.fileName);
      if (data == null) continue;
      archive.add(ArchiveFile.typedData('$_fontDir/${entry.fileName}', data));
      manifestFonts.add({
        'id': entry.id,
        'fileName': entry.fileName,
        'label': entry.label,
      });
    }

    archive
      ..add(_jsonEntry(_projectEntry, project.toJson(), pretty: true))
      ..add(
        _jsonEntry(_manifestEntry, {
          'format': _format,
          'version': _version,
          'createdAt': DateTime.now().toIso8601String(),
          'images': manifestImages,
          'fonts': manifestFonts,
        }, pretty: true),
      );

    return ZipEncoder().encodeBytes(archive);
  }

  /// Reads [bytes] as either a bundle or a bare project JSON document.
  ///
  /// Throws [ProjectArchiveException] with a user-facing message for anything
  /// else — including a zip that simply is not one of ours.
  static ProjectBundle read(Uint8List bytes) {
    if (!_looksLikeZip(bytes)) {
      return ProjectBundle(project: _projectFromJson(bytes), images: const []);
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const ProjectArchiveException('That file is not a readable zip.');
    }

    _checkManifest(archive);

    final projectEntry = archive.findFile(_projectEntry);
    if (projectEntry == null) {
      throw const ProjectArchiveException(
        'That zip is not a MockMyApp backup — it has no project.json.',
      );
    }

    final kinds = _kindsFromManifest(archive);
    final images = <BundledImage>[];
    for (final file in archive.files) {
      if (!file.isFile || p.dirname(file.name) != _imageDir) continue;
      final fileName = p.basename(file.name);
      images.add(
        BundledImage(
          fileName: fileName,
          bytes: file.content,
          kind: kinds[fileName] ?? LibraryImageKind.background,
        ),
      );
    }

    final fontMeta = _fontsFromManifest(archive);
    final fonts = <BundledFont>[];
    for (final file in archive.files) {
      if (!file.isFile || p.dirname(file.name) != _fontDir) continue;
      final fileName = p.basename(file.name);
      final meta = fontMeta[fileName];
      // The leaf name is `<id><ext>` by construction, so a bundle whose
      // manifest is missing or unreadable still restores its fonts under the
      // right ids — which is the half that has to be right, because that is
      // what the documents name. Only the label falls back.
      final id = meta?['id'] as String? ?? p.basenameWithoutExtension(fileName);
      fonts.add(
        BundledFont(
          id: id,
          fileName: fileName,
          label:
              meta?['label'] as String? ?? p.basenameWithoutExtension(fileName),
          bytes: file.content,
        ),
      );
    }

    return ProjectBundle(
      project: _projectFromJson(projectEntry.content),
      images: images,
      fonts: fonts,
    );
  }

  /// Every library image [project] points at, across all of its sub-projects,
  /// mapped to what it is used for.
  ///
  /// Screenshot wins when one file is used both ways — it is the picker filter
  /// that would look broken if the asset landed in the other bucket.
  ///
  /// Public, not test-only: duplicating a project reads it to work out which
  /// pictures the copy needs its own of.
  static Map<String, LibraryImageKind> referencedImages(Project project) {
    final found = referencedImagesIn(project.allScreens);
    // The icon's picture travels with the project too: a backup restored
    // without it would export every store's icon without its mark.
    final iconImage = project.icon?.imagePath;
    if (iconImage != null &&
        iconImage.isNotEmpty &&
        !StoredImage.isAsset(iconImage)) {
      found.putIfAbsent(iconImage, () => LibraryImageKind.element);
    }
    return found;
  }

  /// The same, over any run of screens.
  ///
  /// Split out because a target moved or copied into another project takes only
  /// *its* artwork with it, and the project it is leaving keeps the rest.
  static Map<String, LibraryImageKind> referencedImagesIn(
    Iterable<ScreenDoc> screens,
  ) {
    final found = <String, LibraryImageKind>{};
    // A picture that ships inside the app is already on every device a backup
    // can be restored to, so packing it would grow every archive by artwork it
    // already has — and restoring it would write a second copy into the
    // library under a name the templates do not use.
    bool packable(String path) => path.isNotEmpty && !StoredImage.isAsset(path);

    for (final screen in screens) {
      if (screen.background case ImageBackground(
        :final path,
      ) when packable(path)) {
        found.putIfAbsent(path, () => LibraryImageKind.background);
      }
      for (final frame in screen.frames) {
        // Every image the frame carries, not just the one on screen: a backup
        // that bundled only the visible capture would restore a set with its
        // alternates missing.
        for (final path in [
          ...frame.screenshot.images,
          // And every language's own capture.
          ...frame.screenshot.localeImages.values,
        ]) {
          if (!packable(path)) continue;
          found[path] = LibraryImageKind.screenshot;
        }
        // The display's own backdrop, when it is a photo rather than a colour.
        // Filed as a background because that is what it is — the frame's
        // screenshots are the pictures the listing is *of*, and this is what
        // they sit on.
        if (frame.screenshot.fill case ImageBackground(
          :final path,
        ) when packable(path)) {
          found.putIfAbsent(path, () => LibraryImageKind.background);
        }
      }
      // Image layers: a logo or photo placed on the canvas.
      for (final shape in screen.shapes) {
        final path = shape.imagePath;
        if (path == null || !packable(path)) continue;
        found.putIfAbsent(path, () => LibraryImageKind.element);
      }
    }
    return found;
  }

  /// Every uploaded typeface [project] is set in, across all of its
  /// sub-projects, as the `user:<id>` families the documents store.
  ///
  /// Public for the same reason [referencedImages] is: duplicating or moving a
  /// project needs to know what travels with it.
  static Set<String> referencedFonts(Project project) =>
      referencedFontsIn(project.allScreens);

  /// The same, over any run of screens.
  ///
  /// Both captions and every styled run inside them, because a run can override
  /// the family on its own — a headline in the brand face with one word set in
  /// something else is exactly the design this feature exists for, and bundling
  /// only the caption's own family would lose the word.
  ///
  /// Google families are filtered out here rather than at the call site: they
  /// are fetched by name on the restoring device and there is nothing to pack.
  static Set<String> referencedFontsIn(Iterable<ScreenDoc> screens) {
    final found = <String>{};

    void add(CaptionSpec? caption) {
      if (caption == null) return;
      if (FontLibrary.idOf(caption.fontFamily) != null) {
        found.add(caption.fontFamily);
      }
      for (final run in caption.runs) {
        final family = run.fontFamily;
        if (family != null && FontLibrary.idOf(family) != null) {
          found.add(family);
        }
      }
    }

    for (final screen in screens) {
      add(screen.caption);
      add(screen.subCaption);
    }
    return found;
  }

  /// Re-points every image reference in [project] using [pathsByFileName],
  /// which maps a bundled leaf name onto where that file now lives.
  ///
  /// Each sub-project is rebuilt through [SubProject.copyWith] so that only its
  /// screens change. Which target a set was made for, which preset it chose and
  /// what canvas it exports at are properties of the listing slot, not of the
  /// device the artwork happens to be sitting on, and a restore that quietly
  /// re-derived them would move somebody's work to a different store.
  ///
  /// References with no entry are left untouched: they render as the
  /// missing-image placeholder, exactly as they did on the source device.
  static Project remapImages(
    Project project,
    Map<String, String> pathsByFileName,
  ) {
    String? repoint(String? stored) {
      if (stored == null || stored.isEmpty) return stored;
      // A bundled asset resolves against the app, not the container, so there
      // is nothing to repair — and its leaf name is generic enough
      // (`01.webp`) that matching on it would happily swap a template's own
      // artwork for a restored screenshot that happened to share the name.
      if (StoredImage.isAsset(stored)) return stored;
      return pathsByFileName[p.basename(stored)] ?? stored;
    }

    final iconImage = project.icon?.imagePath;
    return project.copyWith(
      icon: iconImage == null
          ? null
          : project.icon!.copyWith(foreground: IconImage(repoint(iconImage)!)),
      subProjects: [
        for (final sub in project.subProjects)
          sub.copyWith(
            screens: [
              for (final screen in sub.screens)
                screen.copyWith(
                  // Through `copyWith`, not a fresh `ImageBackground`: a
                  // backdrop carries a fit, a zoom, a pan, a blur and a wash
                  // alongside its path, and rebuilding it from the path alone
                  // silently reset every one of them on import.
                  background: switch (screen.background) {
                    final ImageBackground image => image.copyWith(
                      path: repoint(image.path)!,
                    ),
                    final other => other,
                  },
                  frames: [
                    for (final frame in screen.frames)
                      frame.copyWith(
                        screenshot: frame.screenshot
                            .mapImages((path) => repoint(path) ?? path)
                            .copyWith(
                              fill: switch (frame.screenshot.fill) {
                                final ImageBackground image => image.copyWith(
                                  path: repoint(image.path)!,
                                ),
                                final other => other,
                              },
                            ),
                      ),
                  ],
                  shapes: [
                    for (final shape in screen.shapes)
                      shape.imagePath == null
                          ? shape
                          : shape.copyWith(imagePath: repoint(shape.imagePath)),
                  ],
                ),
            ],
          ),
      ],
    );
  }

  static ArchiveFile _jsonEntry(
    String name,
    Object value, {
    bool pretty = false,
  }) {
    final text = pretty
        ? const JsonEncoder.withIndent('  ').convert(value)
        : jsonEncode(value);
    return ArchiveFile.typedData(name, utf8.encode(text));
  }

  /// `PK\x03\x04` — cheaper and clearer than letting the decoder throw.
  static bool _looksLikeZip(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07);

  static void _checkManifest(Archive archive) {
    final entry = archive.findFile(_manifestEntry);
    // Absent is tolerated — the project document alone is enough to restore,
    // and the manifest only supplies each image's kind.
    if (entry == null) return;
    final Map<String, dynamic> manifest;
    try {
      manifest = jsonDecode(utf8.decode(entry.content)) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (!_formats.contains(manifest['format'])) {
      throw const ProjectArchiveException(
        'That zip is not a MockMyApp backup.',
      );
    }
    final version = manifest['version'];
    if (version is int && version > _version) {
      throw const ProjectArchiveException(
        'That backup was made by a newer version of MockMyApp.',
      );
    }
  }

  /// The manifest's font rows, keyed by file name.
  ///
  /// Left as raw maps rather than a typed record because the only two fields
  /// either have a value or fall back at the call site, and a manifest written
  /// by a future build may carry more of them.
  static Map<String, Map<String, dynamic>> _fontsFromManifest(Archive archive) {
    final entry = archive.findFile(_manifestEntry);
    if (entry == null) return const {};
    try {
      final manifest =
          jsonDecode(utf8.decode(entry.content)) as Map<String, dynamic>;
      return {
        for (final font in (manifest['fonts'] as List? ?? const []))
          (font as Map<String, dynamic>)['fileName'] as String: font,
      };
    } catch (_) {
      return const {};
    }
  }

  static Map<String, LibraryImageKind> _kindsFromManifest(Archive archive) {
    final entry = archive.findFile(_manifestEntry);
    if (entry == null) return const {};
    try {
      final manifest =
          jsonDecode(utf8.decode(entry.content)) as Map<String, dynamic>;
      return {
        for (final image in (manifest['images'] as List? ?? const []))
          (image as Map<String, dynamic>)['fileName'] as String:
              LibraryImageKind.parse(image['kind']),
      };
    } catch (_) {
      return const {};
    }
  }

  static Project _projectFromJson(List<int> bytes) {
    try {
      return Project.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );
    } catch (_) {
      throw const ProjectArchiveException(
        'That file is not a MockMyApp project.',
      );
    }
  }
}
