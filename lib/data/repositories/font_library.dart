import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../services/browser_store.dart';

/// One typeface the user brought in.
@immutable
class UserFont {
  const UserFont({
    required this.id,
    required this.fileName,
    required this.label,
    required this.addedAt,
  });

  /// Opaque, minted at import.
  ///
  /// This — not the label, and not the family name recorded inside the file —
  /// is what a document stores. A label is something the user can end up with
  /// twice, and the name inside a `.ttf` is worse still: two unrelated files
  /// can both call themselves `Roboto`, and one of them would then shadow the
  /// Google family of that name for every caption in the app.
  final String id;

  /// Name inside the fonts folder, `<id><ext>`. Never an absolute path — the
  /// app container moves between installs on iOS, so only the leaf is durable.
  final String fileName;

  /// What the picker shows. Taken from the picked file's name, so it is the
  /// user's own word for the face rather than anything read out of the binary.
  final String label;

  final DateTime addedAt;

  /// The family this face is registered under, and the exact string a caption
  /// stores: `user:<id>`.
  String get family => FontLibrary.familyFor(id);

  /// Absolute path for the current run of the app.
  ///
  /// Empty when there is no fonts folder — the web. Callers must check
  /// [FontLibrary.isAvailable] before turning this into a [File], because there
  /// that constructor throws before any read is attempted.
  String get path => FontLibrary.isAvailable
      ? p.join(FontLibrary.directoryPath, fileName)
      : '';

  File get file => File(path);

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'label': label,
    'addedAt': addedAt.toIso8601String(),
  };

  /// Every key is tolerated missing.
  ///
  /// The index is rewritten on a debounce, so a process killed mid-write can
  /// leave a truncated entry behind. Refusing to parse it would take the whole
  /// library down with it; a face with a stand-in label still renders, and the
  /// user can rename it by re-importing.
  factory UserFont.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String? ?? '';
    return UserFont(
      id: id,
      fileName: j['fileName'] as String? ?? '$id.ttf',
      label: j['label'] as String? ?? 'Untitled font',
      addedAt:
          DateTime.tryParse(j['addedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

final fontLibraryProvider = NotifierProvider<FontLibrary, List<UserFont>>(
  FontLibrary.new,
);

/// The app's own typeface library.
///
/// A twin of `ImageLibrary` in shape — copy the bytes in, keep an `index.json`
/// beside them, hand the rest of the app a stable identifier — and deliberately
/// unlike it in ownership: **this library is app-global.** An image is artwork
/// for one listing, so it belongs to one project; a typeface is a brand asset,
/// and every operation that spreads a caption's styling across a set
/// (`applyStyleToAll`, `copyScreensFrom`) would have to re-import the face to
/// keep it resolvable if it were scoped. So there is no `projectId` here at
/// all — not a nullable one, no per-project filter, and nothing to hand over
/// when a target moves between projects.
///
/// A document never stores a path to a font. It stores `user:<id>`, and the
/// engine is handed the face under that exact string at startup — see
/// [initialize] and `StudioFonts.style`. That is what makes a font reference
/// survive an iOS container move for free: there is no path in the document to
/// go stale, so there is nothing here answering to `ImageLibrary.resolve`.
///
/// **One file is one family is one face.** [FontLoader] has no per-file weight
/// axis — that exists only in `pubspec.yaml`'s `fonts:` block — so bold and
/// italic are synthesised by the engine from whatever single face was uploaded.
/// The alternative, refusing to bold until four files have been supplied, is
/// worse: `CaptionSpec.bold` defaults to true, so a freshly uploaded font would
/// arrive faux-bold with no way out of it. [importBytes] takes an explicit `id`
/// so a later multi-face version can add faces to an existing entry without a
/// format change.
///
/// On the web there is no documents directory and `dart:io` is a stub whose
/// type constructors throw, so an uploaded font lives in [_session] for the
/// length of the browser session and is gone on reload — exactly the lifetime a
/// web-imported image already has, and for the same reason.
///
/// A backup bundle carries the font *file*, which makes redistributing a
/// licensed typeface something a user can do without meaning to. That is a
/// licensing question for them rather than a format question for us: nothing
/// here checks, blocks or phones home, and the upload copy says so in a line.
class FontLibrary extends Notifier<List<UserFont>> {
  static const _uuid = Uuid();
  static const _folderName = 'fonts';
  static const _indexName = 'index.json';

  /// The scheme every user font's family name carries.
  ///
  /// A colon, because no Google family contains one — all 1,709 keys of
  /// `GoogleFonts.asMap()` were checked — so [idOf] is an exact test for "this
  /// one is ours" that cannot collide with a real family, now or after the
  /// catalog grows. It also means no serialisation change was needed anywhere:
  /// a stored `fontFamily` was always a bare string and still is.
  static const familyPrefix = 'user:';

  /// Refused above this. Eight megabytes is a very large single face, and one
  /// that legitimately exceeded it would also blow past what registering every
  /// entry synchronously before the first frame can afford.
  static const maxFontBytes = 8 * 1024 * 1024;

  /// Refused above this many entries. Every one of them is read off disk and
  /// handed to the engine before `runApp`, so this cap is what bounds cold
  /// start — it is not tidiness.
  static const maxFonts = 40;

  /// Absolute path of the fonts folder for the current run. Populated by
  /// [initialize] before `runApp`, so [UserFont.path] can stay synchronous.
  static String _directoryPath = '';

  /// Whether a failure to resolve the folder has already been reported.
  ///
  /// [_load] retries [initialize] whenever the provider rebuilds, so without
  /// this a device that genuinely has no documents directory turned one real
  /// problem into a stream of identical crash reports.
  static bool _reportedFailure = false;

  /// Every entry this launch knows about, keyed by id — including ones whose
  /// file has gone.
  ///
  /// Static rather than notifier state because it answers a *render* question.
  /// `StudioFonts.displayName` is called from inside `build`, on widgets that
  /// are not Consumers, and it has to be able to say "the file behind Brand
  /// Sans is missing" rather than "user:0f3a-…". Keeping the label for a face
  /// that failed to register is exactly why this is held apart from
  /// [_registered] rather than being one map of the two facts.
  static final Map<String, UserFont> _index = <String, UserFont>{};

  /// The ids whose bytes actually reached the engine this launch.
  ///
  /// A subset of [_index]: a backup restored on a device that never had the
  /// file, or a web session reloaded after an upload, leaves an entry behind
  /// with no face under it.
  static final Set<String> _registered = <String>{};

  /// Imported bytes held in memory, keyed by file name — the web's storage.
  static final Map<String, Uint8List> _session = <String, Uint8List>{};

  static Future<void> _ready = Future<void>.value();

  static String get directoryPath => _directoryPath;

  /// Whether this run has a fonts folder on disk at all. False on the web.
  static bool get isAvailable => _directoryPath.isNotEmpty;

  /// Resolves once every face known at startup has been handed to the engine.
  ///
  /// `GoogleFonts.pendingFonts()` is a `Future.wait` over futures that
  /// `getFont` itself registers, so a family registered through [FontLoader] is
  /// invisible to it. Export capture has to wait on both or it rasterises an
  /// uploaded font as the fallback face. Before [initialize] has run — on the
  /// web, and under a test that never calls it — this is an already-completed
  /// future, so awaiting it costs nothing.
  static Future<void> get ready => _ready;

  /// Forgets the resolved folder and everything held in memory.
  ///
  /// For tests, which pump a fresh scratch directory per case and would
  /// otherwise be served the first one for the life of the process.
  @visibleForTesting
  static void debugResetStorage() {
    _directoryPath = '';
    _reportedFailure = false;
    _session.clear();
    _index.clear();
    _registered.clear();
    _ready = Future<void>.value();
  }

  /// The family name [id] is registered under, and stored as.
  static String familyFor(String id) => '$familyPrefix$id';

  /// The id inside [family], or null when it names a Google family.
  static String? idOf(String family) => family.startsWith(familyPrefix)
      ? family.substring(familyPrefix.length)
      : null;

  /// Whether the face behind [family] is loaded and will paint real glyphs.
  static bool isRegistered(String family) {
    final id = idOf(family);
    return id != null && _registered.contains(id);
  }

  /// The user's label for [family], or null when the library has never heard of
  /// it.
  ///
  /// Survives the file going missing, which is what lets the editor name the
  /// broken font instead of showing the caption's raw `user:<id>` string.
  static String? labelFor(String family) {
    final id = idOf(family);
    return id == null ? null : _index[id]?.label;
  }

  /// The indexed entry behind [family], for callers with no `ref` — the backup
  /// bundler, which needs the file name to read the bytes back out.
  static UserFont? entryOf(String family) {
    final id = idOf(family);
    return id == null ? null : _index[id];
  }

  /// Whether [bytes] open with an sfnt signature Flutter can actually render.
  ///
  /// The magic number and not the extension, because the failure this catches
  /// is silent: a `.woff2`, a TrueType *collection*, or a 404 page saved under
  /// a `.ttf` name all load through [FontLoader] without complaint and then
  /// render nothing at all — every caption using them turns into blank space,
  /// on the canvas and in the export. An extension filter cannot see any of
  /// that; four bytes can.
  ///
  /// Accepted: `0x00010000` (TrueType outlines), `OTTO` (CFF/OpenType) and
  /// `true` (legacy Mac TrueType). Everything else is refused, explicitly
  /// including `wOFF`, `wOF2` and `ttcf` — the two web font formats and the
  /// collection container, which are the three a user is most likely to have to
  /// hand and the three that fail invisibly.
  static bool looksLikeFont(Uint8List bytes) {
    // Below this there is not enough of a file to hold a table directory, let
    // alone glyphs: it is a truncated download or an error page.
    if (bytes.length < 1024) return false;
    final tag =
        (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    return tag == 0x00010000 || tag == 0x4F54544F || tag == 0x74727565;
  }

  /// Bytes held from this session's imports, if any. Keyed by leaf name.
  static Uint8List? sessionBytes(String fileName) =>
      _session[p.basename(fileName)];

  /// The bytes behind [fileName], wherever this platform keeps them.
  ///
  /// The session map is checked first, and on every platform rather than only
  /// the web, so the memory path is something a test can exercise without
  /// pretending to be a browser.
  static Future<Uint8List?> bytes(String fileName) async {
    final held = sessionBytes(fileName);
    if (held != null) return held;
    // Before any `File` call, not after: on the web the `dart:io` stub throws
    // from the type constructor, before the existence check would even run.
    if (kIsWeb || !isAvailable) return null;
    try {
      final file = File(p.join(_directoryPath, fileName));
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Resolves the fonts folder and hands every indexed face to the engine.
  /// Awaited once at startup, before the first frame.
  ///
  /// **Eagerly, not lazily.** Every point that resolves a family — the editor
  /// canvas, the home-screen thumbnails, the export raster — sits inside a
  /// `build` method and needs a synchronous answer, and `ScreenThumbnail` has
  /// no readiness barrier of any kind. Registering on first use would mean the
  /// whole project grid painted in the fallback face on every cold launch and
  /// only corrected itself if something happened to rebuild it.
  ///
  /// **Never throws.** It sits between `main` and `runApp`, and an exception
  /// here means no frame is ever painted — which on the web leaves Flutter's
  /// splash on screen forever, because that splash is removed by the first
  /// frame and by nothing else. A device that cannot read its fonts folder
  /// should still get an app it can open; what it loses is uploaded typefaces,
  /// and every caption using one falls back to Roboto.
  static Future<void> initialize() {
    final run = _initialize();
    _ready = run;
    return run;
  }

  /// Where a browser keeps each face's bytes (`font:<file name>`) and the
  /// library's index.
  static const _browserPrefix = 'font:';
  static const _browserIndex = 'fonts.json';

  static Future<void> _initialize() async {
    // A browser keeps uploaded faces in IndexedDB: read back and handed to the
    // engine before the first frame, like a device's fonts folder.
    final browser = browserStore;
    if (browser != null) {
      try {
        _session.addAll(await browser.readAllBytes(_browserPrefix));
        for (final entry in await _readIndex()) {
          _index[entry.id] = entry;
          await _register(entry);
        }
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

      for (final entry in await _readIndex()) {
        _index[entry.id] = entry;
        // Indexed before it is registered, and registered inside its own
        // try/catch, so one corrupt file costs the user that font and not the
        // rest of the library — and still shows up in the picker as a face
        // whose file has gone rather than vanishing without explanation.
        await _register(entry);
      }
    } catch (error, stack) {
      // Reported once, not swallowed silently: losing the font folder is a real
      // degradation, and a crash report is how it gets noticed.
      if (_reportedFailure) return;
      _reportedFailure = true;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'mockmyapp',
          context: ErrorDescription('resolving the font library folder'),
        ),
      );
    }
  }

  /// Hands one face to the engine under its `user:<id>` family name.
  ///
  /// Returns false rather than throwing for every failure — bytes that have
  /// gone, bytes the engine refuses — because both callers want to carry on:
  /// startup registers the next font, and an import declines and tells the user
  /// which format to bring instead.
  static Future<bool> _register(UserFont entry) async {
    try {
      final data = await bytes(entry.fileName);
      if (data == null) return false;
      final loader = FontLoader(entry.family)
        ..addFont(
          Future.value(
            ByteData.view(data.buffer, data.offsetInBytes, data.lengthInBytes),
          ),
        );
      await loader.load();
      _registered.add(entry.id);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<UserFont>> _readIndex() async {
    final browser = browserStore;
    if (browser == null && !isAvailable) return const [];
    try {
      final String text;
      if (browser != null) {
        final stored = await browser.readText(_browserIndex);
        if (stored == null) return const [];
        text = stored;
      } else {
        final file = File(p.join(_directoryPath, _indexName));
        if (!await file.exists()) return const [];
        text = await file.readAsString();
      }
      final raw = jsonDecode(text) as List;
      final entries = <UserFont>[];
      for (final e in raw) {
        final entry = UserFont.fromJson(e as Map<String, dynamic>);
        // An entry with no id names no family and can never be selected. It is
        // the shape a truncated write leaves behind, and keeping it would put a
        // row in the picker that does nothing at all.
        if (entry.id.isEmpty) continue;
        entries.add(entry);
      }
      return entries;
    } catch (_) {
      // A corrupt index is not worth failing a launch over. The files stay on
      // disk and the user simply re-imports.
      return const [];
    }
  }

  Timer? _saveTimer;

  @override
  List<UserFont> build() {
    unawaited(_load());
    ref.onDispose(() => _saveTimer?.cancel());
    return const [];
  }

  Future<void> _load() async {
    try {
      if (!isAvailable) await initialize();
      // Still nothing after initialising means there is no folder to read —
      // and on the web the `dart:io` stub would throw on the first call —
      // unless the browser keeps the library instead.
      if (!isAvailable && browserStore == null) return;
      final entries = await _readIndex();
      for (final entry in entries) {
        // A provider built after startup can meet entries the static index has
        // not seen: a second `ProviderContainer`, or a folder that only became
        // readable later. Registering them here too is what keeps
        // [isRegistered] honest whichever route the entry arrived by.
        if (_index.containsKey(entry.id)) continue;
        _index[entry.id] = entry;
        await _register(entry);
      }

      // Merged into whatever is already held rather than assigned over it.
      // `state` is the empty list this started with — but reading and
      // registering the index is asynchronous, and an import can land inside
      // that gap: restoring a backup reads the provider and imports a font in
      // the same breath, and a wholesale assignment here would drop the font it
      // just took in. Nothing is lost the other way, because a merge of an
      // empty index is the identity.
      if (entries.isEmpty && state.isEmpty) return;
      final held = {for (final entry in state) entry.id};
      final merged = [
        ...state,
        for (final entry in entries)
          if (!held.contains(entry.id)) entry,
      ]..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      state = merged;
    } catch (_) {}
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
      await File(
        p.join(_directoryPath, _indexName),
      ).writeAsString(jsonEncode(state.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  /// Copies [bytes] in, registers the face, and returns the entry — or null
  /// when the bytes are not a font this engine can render.
  ///
  /// Null rather than an exception because every caller has something more
  /// useful to say than a stack trace: the picker can look at the header itself
  /// and name the format the user needs to convert from.
  ///
  /// A refusal leaves **nothing** behind — no file, no index entry, no notifier
  /// state. A half-written entry would be a picker row that can never resolve
  /// and can only be cleared by hand, which is a worse outcome than the import
  /// simply not happening.
  ///
  /// [id] is supplied when restoring a backup, so a font arrives under the id
  /// the documents in that backup already name. Re-importing an id the library
  /// already holds returns the existing entry untouched: restoring the same
  /// backup twice must not leave the same typeface in the picker twice.
  Future<UserFont?> importBytes(
    Uint8List bytes, {
    required String label,
    String extension = '.ttf',
    String? id,
  }) async {
    if (!looksLikeFont(bytes)) return null;
    if (bytes.length > maxFontBytes) return null;

    // Checked before the cap and not after: a restore of a font already held is
    // not a new font, and turning it away at the limit would strand every
    // document reference to a face that is sitting right there.
    if (id != null) {
      final existing = state.where((e) => e.id == id).firstOrNull;
      if (existing != null) return existing;
    }
    if (state.length >= maxFonts) return null;

    if (!isAvailable) await initialize();

    final fontId = id ?? _uuid.v4();
    final entry = UserFont(
      id: fontId,
      fileName: '$fontId$extension',
      label: label.trim().isEmpty ? 'Untitled font' : label.trim(),
      addedAt: DateTime.now(),
    );

    if (isAvailable) {
      try {
        await File(
          p.join(_directoryPath, entry.fileName),
        ).writeAsBytes(bytes, flush: true);
      } catch (_) {
        return null;
      }
    } else {
      // No documents directory — the web. Keeping the bytes is what makes an
      // upload work at all there; without it the `File` constructor alone threw
      // `Unsupported operation: _Namespace`.
      _session[entry.fileName] = bytes;
      // Written through to IndexedDB, so the face survives a refresh.
      await browserStore?.writeBytes('$_browserPrefix${entry.fileName}', bytes);
    }

    _index[entry.id] = entry;
    if (!await _register(entry)) {
      // The engine refused the face. Undo all of it: an entry whose family
      // resolves to nothing is precisely the permanently broken row this method
      // promises never to create.
      _index.remove(entry.id);
      _session.remove(entry.fileName);
      if (isAvailable) {
        try {
          final file = File(p.join(_directoryPath, entry.fileName));
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      return null;
    }

    state = [entry, ...state];
    _scheduleSave();
    return entry;
  }

  /// Deletes an entry and its bytes.
  ///
  /// The engine cannot unload a face, so captions already using it keep
  /// painting in it until the app restarts — after which they fall back to
  /// Roboto, exactly as a document referencing a font this device never had
  /// does. The entry leaves the static index immediately, so the editor stops
  /// offering the face and starts calling it missing straight away.
  Future<void> remove(String id) async {
    final entry = state.where((e) => e.id == id).firstOrNull;
    state = state.where((e) => e.id != id).toList();
    _scheduleSave();
    if (entry == null) return;

    _index.remove(id);
    _registered.remove(id);
    _session.remove(entry.fileName);
    await browserStore?.delete('$_browserPrefix${entry.fileName}');
    if (!isAvailable) return;
    try {
      if (await entry.file.exists()) await entry.file.delete();
    } catch (_) {}
  }

  /// The library entry [family] names, if this library owns it.
  UserFont? entryFor(String family) {
    final id = idOf(family);
    return id == null ? null : state.where((e) => e.id == id).firstOrNull;
  }
}
