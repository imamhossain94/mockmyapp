import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../domain/engine/scene_renderer.dart';
import '../services/device_storage.dart';

/// One target's finished artwork and the folder it takes inside an archive.
///
/// The folder is the target's own label — `iPhone`, `Feature graphic` — because
/// that is what the console calls the slot the files are going into, and a
/// reviewer unzipping the bundle is matching folders to slots.
typedef GraphicsSet = ({String folder, List<RenderedScene> scenes});

/// Packs a set of rendered screenshots into one `.zip`.
///
/// Separate from `ProjectArchive`, which bundles a *document* so it can be
/// restored. Nothing here is meant to be read back: this is the finished
/// artwork on its way to a store listing, and the only thing that matters is
/// that a reviewer can unzip it and find files in the order the set is in.
///
/// One flat folder named after the project rather than loose files at the root,
/// because that is what unzips tidily next to whatever else is in a Downloads
/// folder.
abstract final class GraphicsArchive {
  static const fileExtension = 'zip';
  static const mimeType = 'application/zip';

  /// The name to offer for the archive of [projectName].
  static String fileNameFor(String projectName) =>
      '${DeviceStorage.sanitizeFileName(projectName)} graphics.$fileExtension';

  /// Zips [scenes] as PNGs, numbered in set order.
  ///
  /// Store-listing screenshots are ordered, and a zip has no ordering of its
  /// own — so the ordinal goes in the file name, zero-padded, which is what
  /// makes them sort correctly in every file browser.
  static Uint8List bundle({
    required String projectName,
    required List<RenderedScene> scenes,
  }) {
    final safeName = DeviceStorage.sanitizeFileName(projectName);
    final archive = Archive();
    _addSet(archive, folder: safeName, stem: safeName, scenes: scenes);
    return ZipEncoder().encodeBytes(archive);
  }

  /// Zips several targets into one archive, each set in its own folder.
  ///
  /// A project ships more than one set — an App Store listing needs an iPhone
  /// set *and* an iPad set — and each of those is a separate upload at its own
  /// canvas. They cannot share a folder: every set numbers itself from `01`, so
  /// flattening them would have the second set overwrite the first file for
  /// file.
  ///
  /// The file names repeat the folder rather than relying on it, because the
  /// last thing that happens to these files is being dragged *out* of the
  /// folder and into a browser upload field, where the only thing left is the
  /// name.
  static Uint8List bundleSets({
    required String projectName,
    required List<GraphicsSet> sets,
  }) {
    final safeName = DeviceStorage.sanitizeFileName(projectName);
    final archive = Archive();
    for (final set in sets) {
      final safeFolder = DeviceStorage.sanitizeFileName(set.folder);
      _addSet(
        archive,
        folder: '$safeName/$safeFolder',
        stem: '$safeName $safeFolder',
        scenes: set.scenes,
      );
    }
    return ZipEncoder().encodeBytes(archive);
  }

  /// Zips [files] at exactly the paths they name.
  ///
  /// For a layout another tool reads, where the paths are the contract —
  /// fastlane's `screenshots/<locale>/` and `metadata/android/…` (see
  /// `FastlaneLayout`). Nothing is renamed or prefixed here.
  static Uint8List bundleFiles(List<({String path, Uint8List bytes})> files) {
    final archive = Archive();
    for (final file in files) {
      archive.add(ArchiveFile.typedData(file.path, file.bytes));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  static void _addSet(
    Archive archive, {
    required String folder,
    required String stem,
    required List<RenderedScene> scenes,
  }) {
    for (final scene in scenes) {
      archive.add(
        ArchiveFile.typedData(
          '$folder/$stem ${scene.ordinal}.${scene.extension}',
          scene.bytes,
        ),
      );
    }
  }
}
