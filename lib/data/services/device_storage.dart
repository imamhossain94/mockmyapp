import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'file_download.dart';

/// Where a byte payload should land on the user's device.
enum SaveTarget {
  /// The system photo gallery (Android `MediaStore.Images`, iOS Photos).
  gallery,

  /// The public Downloads folder (Android `MediaStore.Downloads`). On platforms
  /// with no such concept the app's shared documents folder is used instead.
  downloads,
}

/// Where a file actually ended up, for reporting back to the user.
@immutable
class SavedLocation {
  const SavedLocation({required this.displayPath, this.filePath});

  /// A short, human-readable location such as `Pictures/MockMyApp/x.png`.
  /// This is what gets shown in a confirmation snackbar.
  final String displayPath;

  /// The real filesystem path, when the platform exposes one. Android
  /// MediaStore inserts on API 29+ have no readable path, so this is null there.
  final String? filePath;

  @override
  String toString() => displayPath;
}

/// Thrown when a save could not be completed. Carries a message already
/// phrased for the user.
class DeviceStorageException implements Exception {
  const DeviceStorageException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Writes exported artwork and project backups to user-visible storage.
///
/// Android and iOS go through the `mockmyapp/storage` method channel (see
/// `MediaStoreBridge.kt` / `MediaStoreBridge.swift`) so that images land in the
/// gallery and documents land in `Download/`, using scoped storage APIs that
/// need no runtime permission on API 29+. Desktop targets fall back to
/// `path_provider`'s downloads directory.
///
/// Every entry point takes raw bytes: nothing here knows about PNGs, JSON or
/// the document model, which keeps the editor and project screens free to
/// compose whatever they like before handing it over.
abstract final class DeviceStorage {
  static const MethodChannel _channel = MethodChannel('mockmyapp/storage');

  /// Sub-folder created inside Pictures/ and Download/ so the user's own
  /// folders stay tidy.
  static const String folder = 'MockMyApp';

  static bool get _hasNativeBridge =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Saves [bytes] as an image, either to the gallery or to Downloads.
  static Future<SavedLocation> saveImage(
    Uint8List bytes, {
    required String fileName,
    SaveTarget target = SaveTarget.gallery,
    String mimeType = 'image/png',
    String? subFolder,
  }) {
    return _save(
      bytes,
      fileName: fileName,
      mimeType: mimeType,
      target: target,
      isImage: true,
      subFolder: subFolder,
    );
  }

  /// Saves [bytes] as a video to the gallery — `Movies/MockMyApp` on Android,
  /// the MockMyApp album in Photos on iOS.
  ///
  /// Its own route rather than [saveImage] with a video type: Android files
  /// video in a different MediaStore collection, and Photos imports a clip
  /// from a file rather than from bytes.
  static Future<SavedLocation> saveVideo(
    Uint8List bytes, {
    required String fileName,
    String mimeType = 'video/mp4',
    String? subFolder,
  }) {
    return _save(
      bytes,
      fileName: fileName,
      mimeType: mimeType,
      target: SaveTarget.gallery,
      isImage: false,
      isVideo: true,
      subFolder: subFolder,
    );
  }

  /// Saves [bytes] as a document (project backup, manifest…) to Downloads.
  static Future<SavedLocation> saveDocument(
    Uint8List bytes, {
    required String fileName,
    String mimeType = 'application/json',
    String? subFolder,
  }) {
    return _save(
      bytes,
      fileName: fileName,
      mimeType: mimeType,
      target: SaveTarget.downloads,
      isImage: false,
      subFolder: subFolder,
    );
  }

  static Future<SavedLocation> _save(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    required SaveTarget target,
    required bool isImage,
    bool isVideo = false,
    String? subFolder,
  }) async {
    final safeName = sanitizeFileName(fileName);
    final safeSubFolder = subFolder == null || subFolder.trim().isEmpty
        ? null
        : sanitizeFileName(subFolder);

    if (kIsWeb) {
      // A browser has no directory to be written into — the file is handed to
      // it and the user's own download settings decide where it lands. There is
      // no path to report back, and no sub-folder either: the flat name has to
      // carry everything, so the folder becomes a prefix rather than being
      // dropped on the floor.
      //
      // Unless the name already starts with it: every export is named after
      // its project, and "Gesture Volume Gesture Volume 01.png" said so twice.
      final name = safeSubFolder == null || safeName.startsWith(safeSubFolder)
          ? safeName
          : '$safeSubFolder $safeName';
      try {
        await downloadBytes(bytes, fileName: name, mimeType: mimeType);
      } catch (e) {
        throw DeviceStorageException('The browser refused the download: $e');
      }
      return SavedLocation(displayPath: 'your downloads', filePath: null);
    }

    if (_hasNativeBridge) {
      try {
        final result = await _channel.invokeMapMethod<String, dynamic>(
          target != SaveTarget.gallery
              ? 'saveDownload'
              : (isVideo
                    ? 'saveVideo'
                    : (isImage ? 'saveImage' : 'saveDownload')),
          <String, dynamic>{
            'bytes': bytes,
            'fileName': safeName,
            'mimeType': mimeType,
            'folder': safeSubFolder == null ? folder : '$folder/$safeSubFolder',
          },
        );
        if (result == null) {
          throw const DeviceStorageException('The system rejected the save.');
        }
        return SavedLocation(
          displayPath: result['displayPath'] as String? ?? safeName,
          filePath: result['filePath'] as String?,
        );
      } on PlatformException catch (e) {
        throw DeviceStorageException(e.message ?? 'Could not save the file.');
      } on MissingPluginException {
        // Fall through to the filesystem path below — this only happens on a
        // stale install that predates the native bridge.
      }
    }

    return _saveToFilesystem(
      bytes,
      fileName: safeName,
      subFolder: safeSubFolder,
    );
  }

  /// Desktop (and last-resort) path: write straight into the platform's
  /// downloads directory, or the documents directory when there isn't one.
  static Future<SavedLocation> _saveToFilesystem(
    Uint8List bytes, {
    required String fileName,
    String? subFolder,
  }) async {
    Directory? base;
    try {
      base = await getDownloadsDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();

    final dir = Directory(
      subFolder == null
          ? p.join(base.path, folder)
          : p.join(base.path, folder, subFolder),
    );
    await dir.create(recursive: true);

    final file = File(_uniquePath(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return SavedLocation(displayPath: file.path, filePath: file.path);
  }

  /// Appends ` (2)`, ` (3)`… until the name is free, so a second export never
  /// silently overwrites the first.
  static String _uniquePath(String dirPath, String fileName) {
    final ext = p.extension(fileName);
    final stem = p.basenameWithoutExtension(fileName);
    var candidate = p.join(dirPath, fileName);
    var n = 2;
    while (File(candidate).existsSync()) {
      candidate = p.join(dirPath, '$stem ($n)$ext');
      n++;
    }
    return candidate;
  }

  /// Strips characters that are illegal in a file name on any of our targets
  /// and collapses the result to something readable.
  static String sanitizeFileName(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'Untitled';
    if (cleaned.length <= 120) return cleaned;

    // Trim the stem, never the extension. A long project name would otherwise
    // produce `Very long name back` — and a backup that lost its `.zip` cannot
    // be picked back up by the importer, which filters on extension.
    final extension = p.extension(cleaned);
    if (extension.isEmpty || extension.length >= 120) {
      return cleaned.substring(0, 120).trim();
    }
    return '${cleaned.substring(0, 120 - extension.length).trim()}$extension';
  }
}
