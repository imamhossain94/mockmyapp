import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../services/browser_store.dart';

/// What an imported asset is used for. Purely a filter for the picker UI —
/// nothing stops a background being reused as a screenshot.
enum LibraryImageKind {
  background,
  screenshot,

  /// A picture placed on the canvas as a layer of its own — a logo, a badge,
  /// a photo — rather than behind it or inside a device.
  element;

  /// Reads a persisted name, falling back to [background] for anything
  /// unknown: the kind every entry was before the library was split.
  static LibraryImageKind parse(Object? name) => switch (name) {
    'screenshot' => screenshot,
    'element' => element,
    _ => background,
  };
}

/// One asset owned by the app.
@immutable
class LibraryImage {
  const LibraryImage({
    required this.id,
    required this.fileName,
    required this.kind,
    required this.addedAt,
    this.projectId,
  });

  final String id;

  /// The project this image was imported for.
  ///
  /// Null only on entries written before the library was split per project.
  /// Those stay visible everywhere — orphaning somebody's existing artwork to
  /// tidy up a data model is not a trade worth making — while everything
  /// imported since belongs to exactly one project. See [ImageLibrary.forProject].
  final String? projectId;

  /// Name inside the library directory. Never an absolute path — the container
  /// directory moves between installs on iOS, so only the leaf is durable.
  final String fileName;

  final LibraryImageKind kind;
  final DateTime addedAt;

  /// Absolute path for rendering. Valid for the current run of the app.
  String get path => p.join(ImageLibrary.directoryPath, fileName);

  File get file => File(path);

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'kind': kind.name,
    'addedAt': addedAt.toIso8601String(),
    'projectId': projectId,
  };

  factory LibraryImage.fromJson(Map<String, dynamic> j) => LibraryImage(
    id: j['id'] as String,
    fileName: j['fileName'] as String,
    kind: LibraryImageKind.parse(j['kind']),
    addedAt: DateTime.tryParse(j['addedAt'] as String? ?? '') ?? DateTime.now(),
    // Absent on every entry written before the library was split per project.
    projectId: j['projectId'] as String?,
  );
}

final imageLibraryProvider = NotifierProvider<ImageLibrary, List<LibraryImage>>(
  ImageLibrary.new,
);

/// The app's own picture library.
///
/// Every image the user brings in — a background, a raw screenshot, a retouched
/// screenshot coming out of the photo editor — is **copied** in here rather than
/// being referenced where the picker left it. That matters for two reasons:
///
/// * `image_picker` hands back a file in a cache directory the OS is free to
///   purge, so a project that referenced it directly would lose its artwork.
/// * The user gets a reusable library instead of having to re-pick the same
///   background for every screen in a set.
///
/// Paths are stored in documents as absolute strings for backwards
/// compatibility, and [resolve] repairs them when the app container has moved
/// (which happens on every iOS reinstall).
class ImageLibrary extends Notifier<List<LibraryImage>> {
  static const _uuid = Uuid();
  static const _folderName = 'library';
  static const _indexName = 'index.json';

  /// Absolute path of the library folder for the current run. Populated by
  /// [initialize] before `runApp`, so [LibraryImage.path] and [resolve] can stay
  /// synchronous and be used inside `build` methods.
  static String _directoryPath = '';

  /// Whether a failure to resolve the folder has already been reported.
  ///
  /// [_load] retries [initialize] whenever the provider rebuilds, so without
  /// this a device that genuinely has no documents directory turned one real
  /// problem into a stream of identical crash reports. The *retry* is worth
  /// keeping — a transient failure should be recoverable — the noise is not.
  static bool _reportedFailure = false;

  static String get directoryPath => _directoryPath;

  /// Forgets the resolved folder and everything held in memory.
  ///
  /// For tests, which pump a fresh scratch directory per case and would
  /// otherwise be served the first one for the life of the process.
  @visibleForTesting
  static void debugResetStorage() {
    _directoryPath = '';
    _reportedFailure = false;
    _session.clear();
  }

  /// Whether this run has a library folder on disk at all.
  ///
  /// False on the web, where there is no application documents directory and
  /// `dart:io` is a stub that throws on every operation. Callers that touch
  /// files must check this first; [resolve] and [_load] already do.
  static bool get isAvailable => _directoryPath.isNotEmpty;

  /// Imported bytes held in memory, keyed by file name.
  ///
  /// The web's storage. There is no documents directory to write to and
  /// `dart:io` throws on construction, so an import that would be a file
  /// everywhere else stays in the heap for the length of the session — which
  /// is exactly as long as the projects referencing it last, since those have
  /// nowhere to persist to either.
  static final Map<String, Uint8List> _session = <String, Uint8List>{};

  /// Bytes for [storedPath] held from this session's imports, if any.
  ///
  /// Keyed by leaf name so a document that stored an absolute path on a device
  /// and was carried to a browser still finds its picture.
  static Uint8List? sessionBytes(String storedPath) =>
      _session[p.basename(storedPath)];

  /// Resolves the library folder. Awaited once at startup, before the first
  /// frame.
  ///
  /// **Never throws.** It is the last thing between `main` and `runApp`, and an
  /// exception here means no frame is ever painted — which on the web leaves
  /// the splash on screen forever, because that splash is removed by Flutter's
  /// first frame and by nothing else. A device with no writable documents
  /// directory should still get an app it can open; what it loses is
  /// persistence, and [isAvailable] is how the rest of the code knows.
  /// Where a browser keeps each picture's bytes (`img:<file name>`) and the
  /// library's index.
  static const _browserPrefix = 'img:';
  static const _browserIndex = 'images.json';

  static Future<void> initialize() async {
    // A browser has no documents directory, but it has IndexedDB: every
    // picture is read back into the session map before the first frame, so
    // resolving one stays the synchronous lookup the canvas needs.
    final browser = browserStore;
    if (browser != null) {
      try {
        _session.addAll(await browser.readAllBytes(_browserPrefix));
      } catch (_) {}
      return;
    }

    // The web has no documents directory, and `path_provider` ships no
    // implementation for it — asking throws `MissingPluginException` rather
    // than returning empty.
    if (kIsWeb) return;

    // Already resolved — nothing to redo.
    if (isAvailable) return;

    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, _folderName));
      if (!await dir.exists()) await dir.create(recursive: true);
      _directoryPath = dir.path;
    } catch (error, stack) {
      // Reported once, not swallowed silently: losing the picture folder is a
      // real degradation, and a crash report is how it gets noticed.
      if (_reportedFailure) return;
      _reportedFailure = true;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'mockmyapp',
          context: ErrorDescription('resolving the image library folder'),
        ),
      );
    }
  }

  /// Maps a stored image path onto a file that exists right now.
  ///
  /// Returns [stored] untouched when it is still valid. When it is not, and the
  /// file's name is present in the library folder, the current absolute path is
  /// returned instead — this is what keeps projects intact after an iOS
  /// reinstall gives the app a new container UUID.
  static String resolve(String stored) {
    if (stored.isEmpty) return stored;
    // Before any `File` call, not after: with no library folder there is
    // nothing to repair a path against, and on the web the `dart:io` stub
    // would throw on the existence check itself.
    if (!isAvailable) return stored;
    if (File(stored).existsSync()) return stored;
    final candidate = p.join(_directoryPath, p.basename(stored));
    return File(candidate).existsSync() ? candidate : stored;
  }

  Timer? _saveTimer;

  @override
  List<LibraryImage> build() {
    unawaited(_load());
    ref.onDispose(() => _saveTimer?.cancel());
    return const [];
  }

  File get _indexFile => File(p.join(_directoryPath, _indexName));

  Future<void> _load() async {
    final browser = browserStore;
    if (browser != null) {
      try {
        final raw = await browser.readText(_browserIndex);
        if (raw == null) return;
        final entries =
            [
                for (final e in jsonDecode(raw) as List)
                  LibraryImage.fromJson(e as Map<String, dynamic>),
              ].where((e) => _session.containsKey(e.fileName)).toList()
              ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
        // Merged with anything imported while the index was loading.
        final held = {for (final e in state) e.id};
        state = [
          ...state,
          for (final e in entries)
            if (!held.contains(e.id)) e,
        ];
      } catch (_) {}
      return;
    }
    try {
      if (!isAvailable) await initialize();
      // Still nothing after initialising means there is no folder to read —
      // building `_indexFile` from an empty path would join to the index name
      // alone and, on the web, throw on the first `dart:io` call.
      if (!isAvailable) return;
      if (!await _indexFile.exists()) return;
      final raw = jsonDecode(await _indexFile.readAsString()) as List;
      final entries = raw
          .map((e) => LibraryImage.fromJson(e as Map<String, dynamic>))
          .where((e) => e.file.existsSync())
          .toList();
      entries.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      state = entries;
    } catch (_) {
      // A corrupt index — or a platform with no documents directory at all —
      // is not worth failing a launch over. The files stay on disk and the user
      // simply re-imports.
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), _saveNow);
  }

  Future<void> _saveNow() async {
    final browser = browserStore;
    if (browser != null) {
      await browser.writeText(
        _browserIndex,
        jsonEncode(state.map((e) => e.toJson()).toList()),
      );
      return;
    }
    // Nothing to write the index *into*. Without this the empty directory path
    // joins to the bare file name and the index lands in the process's working
    // directory — which during a test run is the repository root.
    if (!isAvailable) return;
    try {
      await _indexFile.writeAsString(
        jsonEncode(state.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  /// Everything imported for [projectId], newest first.
  ///
  /// Entries from before the library was split per project carry no owner and
  /// appear in every project — they predate the rule rather than break it, and
  /// hiding them would strand artwork the user already has.
  List<LibraryImage> forProject(String? projectId, LibraryImageKind kind) => [
    for (final entry in state)
      if (entry.kind == kind &&
          (entry.projectId == null || entry.projectId == projectId))
        entry,
  ];

  /// Copies [source] into the library and returns the managed entry.
  Future<LibraryImage> importFile(
    File source, {
    required String? projectId,
    LibraryImageKind kind = LibraryImageKind.background,
  }) async {
    final ext = p.extension(source.path).toLowerCase();
    return importBytes(
      await source.readAsBytes(),
      projectId: projectId,
      kind: kind,
      extension: ext.isEmpty ? '.png' : ext,
    );
  }

  /// Writes [bytes] into the library and returns the managed entry.
  Future<LibraryImage> importBytes(
    Uint8List bytes, {
    required String? projectId,
    LibraryImageKind kind = LibraryImageKind.background,
    String extension = '.png',
  }) async {
    if (!isAvailable) await initialize();
    final id = _uuid.v4();
    final fileName = '$id$extension';

    if (isAvailable) {
      await File(
        p.join(_directoryPath, fileName),
      ).writeAsBytes(bytes, flush: true);
    } else {
      // No documents directory — the web. Keeping the bytes is what makes an
      // import work at all there; without this the `File` constructor alone
      // threw `Unsupported operation: _Namespace`.
      _session[fileName] = bytes;
      // And written through to IndexedDB, so it is still there after a
      // refresh.
      await browserStore?.writeBytes('$_browserPrefix$fileName', bytes);
    }

    final entry = LibraryImage(
      id: id,
      fileName: fileName,
      kind: kind,
      addedAt: DateTime.now(),
      projectId: projectId,
    );
    state = [entry, ...state];
    _scheduleSave();
    return entry;
  }

  /// Hands every entry backing one of [paths] to [projectId].
  ///
  /// What a target *moved* between projects does with its artwork. The bytes do
  /// not move — the file is already in the one library this app has, and the
  /// documents still name it — so all that changes is which project's picker
  /// offers it, which is the only thing ownership decides.
  ///
  /// Only for pictures the old project has stopped referencing. A file both
  /// projects still use has to be copied rather than handed over, or clearing
  /// one project's library later would blank a screen in the other; the caller
  /// makes that split.
  ///
  /// Entries from before the library was split per project are deliberately
  /// left ownerless: they appear in every project already, and claiming one for
  /// a single project would take it away from the rest.
  void reassign(Iterable<String> paths, String projectId) {
    final names = {for (final path in paths) p.basename(path)};
    if (names.isEmpty) return;

    var changed = false;
    final next = [
      for (final entry in state)
        if (names.contains(entry.fileName) &&
            entry.projectId != null &&
            entry.projectId != projectId)
          () {
            changed = true;
            return LibraryImage(
              id: entry.id,
              fileName: entry.fileName,
              kind: entry.kind,
              addedAt: entry.addedAt,
              projectId: projectId,
            );
          }()
        else
          entry,
    ];
    if (!changed) return;
    state = next;
    _scheduleSave();
  }

  /// Deletes an entry and its bytes. Documents still pointing at it fall back to
  /// the "no screenshot" placeholder, exactly as they would for a missing file.
  Future<void> remove(String id) async {
    final entry = state.where((e) => e.id == id).firstOrNull;
    state = state.where((e) => e.id != id).toList();
    _scheduleSave();
    if (entry == null) return;

    _session.remove(entry.fileName);
    await browserStore?.delete('$_browserPrefix${entry.fileName}');
    if (!isAvailable) return;
    try {
      if (await entry.file.exists()) await entry.file.delete();
    } catch (_) {}
  }

  /// The entry whose file backs [path], if the library owns it.
  LibraryImage? entryForPath(String? path) {
    if (path == null || path.isEmpty) return null;
    final name = p.basename(path);
    return state.where((e) => e.fileName == name).firstOrNull;
  }
}
