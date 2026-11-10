import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/engine/localize.dart';
import '../../domain/models/caption_runs.dart';
import '../../domain/models/icon_doc.dart';
import '../../domain/models/listing_brief.dart';
import '../../domain/models/project.dart';
import '../../domain/models/screen_doc.dart';
import '../../domain/models/screen_template.dart';
import '../../domain/models/store_copy.dart';
import '../../domain/models/style_library.dart';
import '../../domain/models/store_target.dart';
import '../../domain/models/sub_project.dart';
import '../assets/default_frames.dart';
import '../assets/frame_catalog.dart';
import '../assets/template_catalog.dart';
import '../services/browser_store.dart';
import 'font_library.dart';
import 'image_library.dart';
import 'project_archive.dart';
import 'stored_image.dart';

/// One target a new project should be created for.
typedef TargetChoice = ({String targetId, String presetId});

/// The handset a new set is created wearing.
typedef DeviceChoice = ({
  String deviceId,
  String variantId,
  double cornerRadiusPct,
});

final _uuid = const Uuid();

final projectStoreProvider = NotifierProvider<ProjectStore, List<Project>>(
  ProjectStore.new,
);

class ProjectStore extends Notifier<List<Project>> {
  Timer? _saveTimer;

  @override
  List<Project> build() {
    _load();
    ref.onDispose(() => _saveTimer?.cancel());
    return const [];
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'projects.json'));
  }

  /// Where the web keeps `projects.json`, having no documents folder.
  static const _browserKey = 'projects.json';

  Future<void> _load() async {
    // In a browser, IndexedDB instead of a file. See [browserStore].
    final browser = browserStore;
    if (browser != null) {
      try {
        final raw = await browser.readText(_browserKey);
        if (raw != null) {
          state = (jsonDecode(raw) as List)
              .map((e) => Project.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {
        // Corrupt entry — start empty, as a corrupt file does.
      }
      return;
    }
    try {
      final f = await _file();
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List;
        state = list
            .map((e) => Project.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      // Corrupt/absent file — start empty.
    }
  }

  /// Debounced disk write — edits update in-memory state instantly and the
  /// file is flushed shortly after the user stops interacting.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveNow);
  }

  /// Writes any pending change now instead of on the debounce.
  ///
  /// For tests. Waiting out a 400ms timer in every test that cares whether
  /// something was persisted is either slow or flaky, and usually both.
  @visibleForTesting
  Future<void> debugFlush() async {
    _saveTimer?.cancel();
    await _saveNow();
  }

  Future<void> _saveNow() async {
    final browser = browserStore;
    if (browser != null) {
      await browser.writeText(
        _browserKey,
        jsonEncode(state.map((e) => e.toJson()).toList()),
      );
      return;
    }
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(state.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Project? byId(String id) {
    for (final p in state) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Creates a project with one sub-project per chosen target.
  ///
  /// Every sub-project is seeded with its own copies of the same starter
  /// screens, laid out at its own canvas — so a project created for iPhone,
  /// iPad and Android opens with three sets that look alike and are already
  /// independent. Nothing links them afterwards; see [copyScreensFrom] for the
  /// deliberate re-sync.
  ///
  /// The frame arguments are the catalog device the framed targets start on.
  /// They are nullable because a project can be desktop-only, and a Mac or
  /// feature-graphic set never had a device to pick.
  Project createProject({
    required String name,
    required List<TargetChoice> targets,
    String? initialDeviceId,
    String? initialVariantId,
    double initialCornerRadiusPct = 0,

    /// A handset per target id, for the sets that should not wear the initial
    /// one — an App Store set and a Google Play set each on their own store's
    /// phone. A target missing from it falls back to the initial device.
    Map<String, DeviceChoice> devicesByTarget = const {},

    /// How many designs the listing template about to be applied carries, or
    /// null when the project is being created plain.
    ///
    /// Each set is seeded at that length rather than at the usual three, so an
    /// eight-screen listing arrives as eight screens wearing its eight designs.
    /// Seeding three and then applying meant five of them were never built —
    /// the template's own screens beyond the third simply had nowhere to land.
    /// See [StoreTarget.screenCountFor] for the two exceptions.
    int? templateScreens,
  }) {
    final project = Project(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? 'Untitled' : name.trim(),
      subProjects: [
        for (final choice in targets)
          if (devicesByTarget[choice.targetId] case final device?)
            _seedSubProject(
              choice,
              deviceId: device.deviceId,
              variantId: device.variantId,
              cornerRadiusPct: device.cornerRadiusPct,
              templateScreens: templateScreens,
            )
          else
            _seedSubProject(
              choice,
              deviceId: initialDeviceId,
              variantId: initialVariantId,
              cornerRadiusPct: initialCornerRadiusPct,
              templateScreens: templateScreens,
            ),
      ],
      createdAt: DateTime.now(),
    );

    state = [project, ...state];
    _scheduleSave();
    return project;
  }

  /// One sub-project with its starter screens on it.
  SubProject _seedSubProject(
    TargetChoice choice, {
    String? deviceId,
    String? variantId,
    double cornerRadiusPct = 0,
    int? templateScreens,
  }) {
    final target = StoreTargets.resolve(choice.targetId);
    final preset = target.resolvePreset(choice.presetId);

    return SubProject(
      id: _uuid.v4(),
      targetId: target.id,
      presetId: preset.id,
      canvas: preset.size,
      screens: starterScreens(
        target,
        preset.size,
        newId: _uuid.v4,
        deviceId: deviceId,
        variantId: variantId,
        cornerRadiusPct: cornerRadiusPct,
        screenCount: target.screenCountFor(templateScreens),
      ),
    );
  }

  /// Adds a target to an existing project, seeded like a new one.
  ///
  /// Silently does nothing if the project already has that target — two
  /// sub-projects for the same device class would export two folders the store
  /// has one slot for.
  SubProject? addTarget(String projectId, TargetChoice choice) {
    final project = byId(projectId);
    if (project == null) return null;
    if (project.subProjects.any((s) => s.targetId == choice.targetId)) {
      return null;
    }

    // Inherit the handset the project's other sets are already wearing, so a
    // target added later matches the ones added at creation.
    //
    // Only from the sets that wear a handset. A target that names its own body
    // — an iPad, a MacBook, a browser window — is not a source of one, and
    // before this filter existed, adding an iPhone to a Mac-only project
    // inherited the MacBook and put a laptop on the App Store listing.
    final existing = project.subProjects
        .where((sub) => sub.target.defaultFrame == null)
        .expand((sub) => sub.screens)
        .expand((screen) => screen.frames)
        .where((f) => !f.frameHidden)
        .firstOrNull;

    final sub = _seedSubProject(
      choice,
      deviceId: existing?.deviceId,
      variantId: existing?.variantId,
      cornerRadiusPct: existing?.screenshot.cornerRadiusPct ?? 0,
    );
    _mutateProject(
      projectId,
      (pr) => pr.copyWith(subProjects: [...pr.subProjects, sub]),
    );
    return sub;
  }

  /// Drops a target and every screen on it.
  ///
  /// Refuses to remove the last one: a project with no targets has no canvas,
  /// nowhere to add a screen, and no way back through the UI.
  void removeTarget(String projectId, String subId) {
    _mutateProject(projectId, (pr) {
      if (pr.subProjects.length <= 1) return pr;
      return pr.copyWith(
        subProjects: pr.subProjects.where((s) => s.id != subId).toList(),
      );
    });
  }

  /// Moves one sub-project onto a different canvas, resizing all its screens.
  ///
  /// Safe to do at any point in a project's life, and that is a property of the
  /// document rather than of this method: every measurement in a [ScreenDoc] is
  /// already a fraction of the canvas — frame size is a share of its height,
  /// positions are `offsetPct`, the image backdrop's blur and pan are fractions
  /// of its width, and patterns and gradients are resolution-independent by
  /// construction. So a screen keeps its composition through a resize with
  /// nothing to remap.
  ///
  /// What it does NOT keep is proportion. Presets differ in aspect as well as
  /// size (1320x2868 is 0.46; 1080x1920 is 0.56), and frame size keys off canvas
  /// height while caption size keys off canvas width — so their relationship
  /// shifts and a layout tuned for one canvas wants a look after landing on
  /// another. Callers should say so when the aspect changes.
  ///
  /// The project's other sub-projects are untouched. That is the whole point of
  /// them: changing the iPhone set's canvas is not a statement about the iPad
  /// set.
  ///
  /// Device frames are deliberately left alone. The picker has never filtered
  /// by target, so a frame from "the wrong" store was always reachable and is a
  /// choice rather than a mistake to correct.
  void changeCanvasPreset(String projectId, String subId, String presetId) {
    _mutateProject(projectId, (project) {
      final sub = project.subProjectById(subId);
      if (sub == null) return project;
      final preset = sub.target.presetById(presetId);
      if (preset == null || preset.size == sub.canvas) return project;

      return project.withSubProject(
        subId,
        (s) => s.copyWith(
          presetId: preset.id,
          canvas: preset.size,
          // Per screen as well as on the sub-project: `ScreenDoc.canvas` is what
          // the renderer and the exporter actually read.
          screens: [
            for (final screen in s.screens)
              screen.copyWith(canvas: preset.size),
          ],
        ),
      );
    });
  }

  /// Moves one sub-project onto a canvas of the user's own [size], resizing
  /// all its screens as [changeCanvasPreset] does.
  ///
  /// A size that is one of the target's presets lands on that preset rather
  /// than on a custom canvas that happens to match it, so the picker ticks the
  /// row the user would recognise. Sides are rounded to whole pixels and kept
  /// within [CanvasPreset.customMin]–[CanvasPreset.customMax].
  void changeCanvasCustom(String projectId, String subId, Size size) {
    _mutateProject(projectId, (project) {
      final sub = project.subProjectById(subId);
      if (sub == null) return project;
      double side(double v) => v
          .roundToDouble()
          .clamp(
            CanvasPreset.customMin.toDouble(),
            CanvasPreset.customMax.toDouble(),
          )
          .toDouble();
      final canvas = Size(side(size.width), side(size.height));
      final preset = sub.target.presets
          .where((p) => p.size == canvas)
          .firstOrNull;
      final presetId = preset?.id ?? kCustomPresetId;
      if (canvas == sub.canvas && presetId == sub.presetId) return project;

      return project.withSubProject(
        subId,
        (s) => s.copyWith(
          presetId: presetId,
          canvas: canvas,
          screens: [
            for (final screen in s.screens) screen.copyWith(canvas: canvas),
          ],
        ),
      );
    });
  }

  /// Replaces [toSubId]'s screens with copies of [fromSubId]'s, at its canvas.
  ///
  /// The manual re-sync that stands in for linked sets. Fresh screen ids on
  /// every copy, so the two remain independent afterwards — this is a snapshot,
  /// not a link, and editing the copy never reaches back into the original.
  void copyScreensFrom(String projectId, String fromSubId, String toSubId) {
    if (fromSubId == toSubId) return;
    _mutateProject(projectId, (project) {
      final source = project.subProjectById(fromSubId);
      final destination = project.subProjectById(toSubId);
      if (source == null || destination == null) return project;

      return project.withSubProject(
        toSubId,
        (s) => s.copyWith(
          screens: [
            for (final screen in source.screens)
              screen.copyWith(id: _uuid.v4(), canvas: destination.canvas),
          ],
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Moving work between projects
  // ---------------------------------------------------------------------------

  /// Whether [toProjectId] has room for a set of [targetId].
  ///
  /// It does not when it already holds that target: the store has one upload
  /// slot per device class, and two sets for it would export two folders into
  /// one. The UI checks this before offering a destination rather than
  /// reporting a failure afterwards.
  bool canReceiveTarget(String targetId, String toProjectId) {
    final destination = byId(toProjectId);
    if (destination == null) return false;
    return !destination.subProjects.any((s) => s.targetId == targetId);
  }

  /// Copies one target, with everything drawn on it, into another project.
  ///
  /// A copy in every sense: fresh ids for the set and every screen on it, and
  /// fresh copies of the artwork owned by the receiving project. Nothing links
  /// the two afterwards, which is the same promise [copyScreensFrom] makes one
  /// level down — editing either leaves the other exactly as it is.
  ///
  /// The source project is untouched. Returns the new set, or null when the
  /// destination cannot take it.
  Future<SubProject?> copyTargetTo({
    required String fromProjectId,
    required String subId,
    required String toProjectId,
  }) async {
    final sub = byId(fromProjectId)?.subProjectById(subId);
    if (sub == null) return null;
    if (fromProjectId == toProjectId) return null;
    if (!canReceiveTarget(sub.targetId, toProjectId)) return null;

    final copy = await _copyOfSubProject(sub, toProjectId);
    // Re-read rather than close over the earlier lookup: copying the artwork is
    // asynchronous, and the destination may have been edited — or deleted —
    // while it ran.
    if (byId(toProjectId) == null) return null;
    _mutateProject(
      toProjectId,
      (project) =>
          project.copyWith(subProjects: [...project.subProjects, copy]),
    );
    return copy;
  }

  /// Moves one target, with everything drawn on it, into another project.
  ///
  /// The set keeps its id — it is the same set, in a different project — and so
  /// do its screens, so the editor route to a document still opens it. What
  /// changes hands is the artwork: pictures only this set used are re-owned by
  /// the receiving project, and pictures the old project still uses elsewhere
  /// are copied instead, so neither project can later blank the other by
  /// clearing its own library.
  ///
  /// Returns false when the destination already has that target, or when this
  /// is the source project's last one — a project with no targets has no
  /// canvas, nowhere to add a screen, and no way back through the UI, which is
  /// the rule [removeTarget] already enforces.
  Future<bool> moveTargetTo({
    required String fromProjectId,
    required String subId,
    required String toProjectId,
  }) async {
    final source = byId(fromProjectId);
    final sub = source?.subProjectById(subId);
    if (source == null || sub == null) return false;
    if (fromProjectId == toProjectId) return false;
    if (source.subProjects.length <= 1) return false;
    if (!canReceiveTarget(sub.targetId, toProjectId)) return false;

    final moved = await _handOverArtwork(sub, source, toProjectId);
    if (byId(fromProjectId) == null || byId(toProjectId) == null) return false;

    state = [
      for (final project in state)
        if (project.id == fromProjectId)
          project.copyWith(
            subProjects: project.subProjects
                .where((s) => s.id != subId)
                .toList(),
          )
        else if (project.id == toProjectId)
          project.copyWith(subProjects: [...project.subProjects, moved])
        else
          project,
    ];
    _scheduleSave();
    return true;
  }

  /// A second copy of [id], sitting directly under it in the library.
  ///
  /// Everything is duplicated: every target, every screen, and the artwork,
  /// which is copied into the new project rather than shared with the old one.
  /// Sharing would be cheaper and is the wrong trade — the two diverge from the
  /// first edit, and the reason to duplicate a project is usually to try
  /// something on the copy.
  ///
  /// Directly under the original rather than at the top of the list, because a
  /// duplicate is only ever read next to the thing it was made from.
  Future<Project?> duplicateProject(String id) async {
    final source = byId(id);
    if (source == null) return null;

    final projectId = _uuid.v4();
    final artwork = await _copyArtwork(
      ProjectArchive.referencedImages(source),
      projectId,
    );

    final at = state.indexWhere((p) => p.id == id);
    // Deleted while the artwork was being copied. The copies are left in the
    // library rather than chased down: they are unreferenced bytes at worst,
    // and the alternative is a delete path racing a project the user still has
    // open.
    if (at == -1) return null;

    final duplicate = Project(
      id: projectId,
      name: _copyOfName(source.name),
      createdAt: DateTime.now(),
      // Words, not artwork: nothing in them points at a file, so the copy
      // takes them as they are.
      languages: source.languages,
      brief: source.brief,
      storeCopy: source.storeCopy,
      // The icon's picture is artwork like any other: the copy points at its
      // own copy of the file.
      icon: _repointIcon(source.icon, artwork),
      subProjects: [
        for (final sub in source.subProjects)
          SubProject(
            id: _uuid.v4(),
            targetId: sub.targetId,
            presetId: sub.presetId,
            canvas: sub.canvas,
            screens: [
              for (final screen in _repoint(sub.screens, artwork))
                screen.copyWith(id: _uuid.v4()),
            ],
          ),
      ],
    );

    state = [...state.take(at + 1), duplicate, ...state.skip(at + 1)];
    _scheduleSave();
    return duplicate;
  }

  /// "Name copy", then "Name copy 2", and so on — the first nothing else in the
  /// library already answers to.
  /// [name], or [name] with the lowest number after it no project here has.
  String _unusedName(String name) {
    final taken = {for (final project in state) project.name};
    if (!taken.contains(name)) return name;
    for (var i = 2; ; i++) {
      if (!taken.contains('$name $i')) return '$name $i';
    }
  }

  String _copyOfName(String name) {
    final taken = {for (final project in state) project.name};
    final base = '$name copy';
    if (!taken.contains(base)) return base;
    for (var i = 2; ; i++) {
      if (!taken.contains('$base $i')) return '$base $i';
    }
  }

  /// [sub] rebuilt with fresh ids and its own copies of the artwork.
  Future<SubProject> _copyOfSubProject(
    SubProject sub,
    String toProjectId,
  ) async {
    final artwork = await _copyArtwork(
      ProjectArchive.referencedImagesIn(sub.screens),
      toProjectId,
    );
    return SubProject(
      id: _uuid.v4(),
      targetId: sub.targetId,
      presetId: sub.presetId,
      canvas: sub.canvas,
      screens: [
        for (final screen in _repoint(sub.screens, artwork))
          screen.copyWith(id: _uuid.v4()),
      ],
    );
  }

  /// [sub] with its artwork made to belong to [toProjectId].
  ///
  /// A picture only this set uses simply changes hands — the bytes are already
  /// in the one library the app has, and re-owning is the whole of what moves
  /// it between the two projects' pickers. A picture the rest of [from] still
  /// uses is copied instead, because ownership is single and handing it over
  /// would take it out of a project that is still drawing with it.
  Future<SubProject> _handOverArtwork(
    SubProject sub,
    Project from,
    String toProjectId,
  ) async {
    final mine = ProjectArchive.referencedImagesIn(sub.screens);
    if (mine.isEmpty) return sub;

    final elsewhere = ProjectArchive.referencedImagesIn(
      from.subProjects.where((s) => s.id != sub.id).expand((s) => s.screens),
    );
    final shared = {
      for (final MapEntry(key: path, value: kind) in mine.entries)
        if (elsewhere.containsKey(path)) path: kind,
    };

    ref
        .read(imageLibraryProvider.notifier)
        .reassign(
          mine.keys.where((path) => !shared.containsKey(path)),
          toProjectId,
        );

    final artwork = await _copyArtwork(shared, toProjectId);
    return artwork.isEmpty
        ? sub
        : sub.copyWith(screens: _repoint(sub.screens, artwork));
  }

  /// Fresh copies of [sources] in [toProjectId]'s library, old path to new.
  ///
  /// The rule [importProject] already restores a backup under: a copy gets its
  /// own file rather than a second reference to one, so clearing a picture out
  /// of one project can never blank a screen in another.
  ///
  /// A reference whose bytes have gone is skipped and left pointing where it
  /// pointed — the copy shows the same missing-image placeholder the original
  /// was already showing, which is more use than failing the whole duplicate.
  Future<Map<String, String>> _copyArtwork(
    Map<String, LibraryImageKind> sources,
    String toProjectId,
  ) async {
    if (sources.isEmpty) return const {};
    final library = ref.read(imageLibraryProvider.notifier);
    final copied = <String, String>{};

    for (final MapEntry(key: path, value: kind) in sources.entries) {
      final bytes = await StoredImage.bytes(path);
      if (bytes == null) continue;
      final extension = p.extension(path);
      final entry = await library.importBytes(
        bytes,
        projectId: toProjectId,
        kind: kind,
        extension: extension.isEmpty ? '.png' : extension,
      );
      copied[path] = entry.path;
    }
    return copied;
  }

  /// [screens] with every reference named in [artwork] pointed at its copy.
  /// [icon] with its picture pointed at the copy [artwork] made of it.
  IconDoc? _repointIcon(IconDoc? icon, Map<String, String> artwork) {
    final path = icon?.imagePath;
    if (icon == null || path == null || !artwork.containsKey(path)) {
      return icon;
    }
    return icon.copyWith(foreground: IconImage(artwork[path]!));
  }

  List<ScreenDoc> _repoint(
    List<ScreenDoc> screens,
    Map<String, String> artwork,
  ) {
    if (artwork.isEmpty) return screens;
    return [
      for (final screen in screens)
        screen.copyWith(
          background: switch (screen.background) {
            final ImageBackground image when artwork.containsKey(image.path) =>
              image.copyWith(path: artwork[image.path]),
            final other => other,
          },
          frames: [
            for (final frame in screen.frames)
              frame.copyWith(
                screenshot: frame.screenshot.mapImages(
                  (path) => artwork[path] ?? path,
                ),
              ),
          ],
          shapes: [
            for (final shape in screen.shapes)
              shape.imagePath == null
                  ? shape
                  : shape.copyWith(
                      imagePath: artwork[shape.imagePath] ?? shape.imagePath,
                    ),
          ],
        ),
    ];
  }

  void renameProject(String id, String name) {
    state = [
      for (final p in state)
        if (p.id == id) p.copyWith(name: name.trim()) else p,
    ];
    _scheduleSave();
  }

  void deleteProject(String id) {
    state = state.where((p) => p.id != id).toList();
    _scheduleSave();
  }

  /// Moves the project at [from] to [to] in the library's order.
  ///
  /// The list *is* the order — there is no sort key to write, and the home
  /// screen shows projects in exactly this sequence — so a reorder is a move
  /// and nothing else.
  ///
  /// [to] is the index the project ends up at once the move is done, not the
  /// one it was dropped over. That is what `ReorderableListView.onReorderItem`
  /// reports, and the only one of the two conventions that means the same thing
  /// whichever direction the drag went.
  void reorderProjects(int from, int to) {
    if (from < 0 || from >= state.length) return;
    final target = to.clamp(0, state.length - 1);
    if (target == from) return;
    final next = [...state];
    next.insert(target, next.removeAt(from));
    state = next;
    _scheduleSave();
  }

  /// Moves the project with [id] one place toward the front or the back.
  ///
  /// Alongside [reorderProjects] because dragging is not always available: the
  /// grid tiles projects into a wrap where there is no single axis to drag
  /// along, and a keyboard user has no drag at all.
  void moveProject(String id, int delta) {
    final at = state.indexWhere((p) => p.id == id);
    if (at < 0) return;
    reorderProjects(at, (at + delta).clamp(0, state.length - 1));
  }

  /// Restores a backup — a `.zip` bundle, or a bare `.json` document from
  /// before bundles existed.
  ///
  /// Artwork inside a bundle is copied into this device's [ImageLibrary] under
  /// fresh names, and the document is re-pointed at those copies. Fresh names
  /// rather than the originals, so importing the same backup twice cannot make
  /// two projects share — and fight over — one file on disk.
  ///
  /// Typefaces go in under the ids they arrived with, and are **not** re-pointed
  /// at all. The two rules look inconsistent and are not: an image belongs to
  /// one project, so a copy has to get its own file or clearing one project
  /// would blank a screen in another, whereas the font library is app-global —
  /// a second project referencing the same face is the normal case, and minting
  /// a fresh id would put a duplicate in the picker on every restore.
  ///
  /// Throws [ProjectArchiveException], whose message is safe to show the user.
  Future<Project> importProject(Uint8List bytes) async {
    final bundle = ProjectArchive.read(bytes);

    // Minted before the artwork is restored, not after: the images belong to
    // this project, and the library needs to be told which one that is as it
    // takes each of them in.
    final projectId = _uuid.v4();

    final library = ref.read(imageLibraryProvider.notifier);
    final restoredPaths = <String, String>{};
    for (final image in bundle.images) {
      final extension = p.extension(image.fileName);
      final entry = await library.importBytes(
        image.bytes,
        projectId: projectId,
        kind: image.kind,
        extension: extension.isEmpty ? '.png' : extension,
      );
      restoredPaths[image.fileName] = entry.path;
    }

    final fonts = ref.read(fontLibraryProvider.notifier);
    for (final font in bundle.fonts) {
      final extension = p.extension(font.fileName);
      // A refusal — bytes the engine will not take, or a library already at its
      // cap — returns null and is dropped on the floor on purpose. The document
      // keeps naming the face, so the caption falls back to Roboto and the
      // editor tells the user its file is missing, which is a far better
      // outcome than refusing to restore the project over a typeface.
      await fonts.importBytes(
        font.bytes,
        label: font.label,
        extension: extension.isEmpty ? '.ttf' : extension,
        id: font.id,
      );
    }

    final source = ProjectArchive.remapImages(bundle.project, restoredPaths);
    final project = Project(
      id: projectId,
      // Numbered when the name is already in the library — restoring a
      // backup of a project that is still here otherwise left two cards of
      // the same name and no way to tell which was which.
      name: _unusedName(source.name),
      subProjects: source.subProjects,
      createdAt: source.createdAt,
      // The listing's words travel with its pictures: a backup is how a
      // project moves to another device, and one restored without its
      // languages, brief or store copy would arrive with half its listing.
      languages: source.languages,
      brief: source.brief,
      storeCopy: source.storeCopy,
      icon: source.icon,
    );
    state = [project, ...state];
    _scheduleSave();
    return project;
  }

  /// Creates a new screen in [subProjectId], copying styling from its last one.
  ///
  // ── Shared styles ───────────────────────────────────────────────────────
  //
  // Styles push. Editing one rewrites every caption tagged with it here and
  // now, and the documents go on holding concrete values — see [StyleLibrary],
  // which explains why a caption that could not be drawn without its project
  // would break screen transfer, archives and the offscreen exporter.

  /// Saves [style], adding it or replacing the one with its id.
  ///
  /// Replacing pushes: every caption in the project already tagged with this id
  /// is rewritten to match, which is the whole point of a shared style.
  void saveTextStyle(String projectId, TextStyleDef style) {
    _mutateProject(projectId, (project) {
      final pushed = project.copyWith(styles: project.styles.withText(style));
      if (project.styles.textById(style.id) == null) return pushed;
      return _restyleCaptions(pushed, style);
    });
  }

  /// Renames [styleId] without touching a single caption.
  void renameTextStyle(String projectId, String styleId, String name) {
    _mutateProject(projectId, (project) {
      final existing = project.styles.textById(styleId);
      if (existing == null) return project;
      return project.copyWith(
        styles: project.styles.withText(existing.copyWith(name: name)),
      );
    });
  }

  /// Forgets [styleId] and unties every caption wearing it.
  ///
  /// The captions keep the look — they already hold the values — and simply
  /// stop answering to a style that no longer exists. Deleting a style is not a
  /// way to un-format a screen.
  void deleteTextStyle(String projectId, String styleId) {
    _mutateProject(projectId, (project) {
      CaptionSpec? untag(CaptionSpec? c) => c == null || c.styleId != styleId
          ? c
          : c.copyWith(clearStyleId: true);
      return project.copyWith(
        styles: project.styles.withoutText(styleId),
        subProjects: [
          for (final sub in project.subProjects)
            sub.copyWith(
              screens: [
                for (final screen in sub.screens)
                  screen.copyWith(
                    caption: untag(screen.caption),
                    subCaption: untag(screen.subCaption),
                  ),
              ],
            ),
        ],
      );
    });
  }

  /// Saves [component], adding it or replacing the one with its id.
  ///
  /// Replacing pushes: every placement of it, on every screen, is rewritten to
  /// the new shapes — in place. An instance keeps where it was put, which is
  /// the one thing about it the master does not own.
  void saveComponent(String projectId, ComponentDef component) {
    _mutateProject(projectId, (project) {
      final saved = project.copyWith(
        styles: project.styles.withComponent(component),
      );
      if (project.styles.componentById(component.id) == null) return saved;
      return _restampInstances(saved, component);
    });
  }

  /// Forgets [componentId] and cuts every placement loose.
  ///
  /// The shapes stay exactly as they are and simply stop answering to a master
  /// that no longer exists. Deleting a component is not a way to clear screens.
  void deleteComponent(String projectId, String componentId) {
    _mutateProject(projectId, (project) {
      final forgotten = project.copyWith(
        styles: project.styles.withoutComponent(componentId),
      );
      return _mapShapes(
        forgotten,
        (shape) => shape.componentId == componentId
            ? shape.copyWith(clearComponent: true)
            : shape,
      );
    });
  }

  /// [project] with every placement of [component] rewritten to match it.
  ///
  /// Each instance is re-stamped at its own anchor — the centre its slot-0
  /// shape currently sits at — so the group keeps its place on the screen while
  /// everything about the shapes themselves comes from the master.
  Project _restampInstances(Project project, ComponentDef component) {
    List<ShapeSpec> rebuild(List<ShapeSpec> shapes) {
      final instances = <String, int>{};
      for (var i = 0; i < shapes.length; i++) {
        final shape = shapes[i];
        if (shape.componentId != component.id || shape.instanceId == null) {
          continue;
        }
        // The first shape of each run is where that placement starts, and its
        // slot-0 member is the anchor the master was measured against.
        instances.putIfAbsent(shape.instanceId!, () => i);
      }
      if (instances.isEmpty) return shapes;

      final anchors = <String, Offset>{};
      // Where each placement sits in the stack, which is the screen's business
      // and not the master's: a master edit rewrites what the shapes *are*, and
      // must leave a placement exactly as far forward as the user put it.
      final bases = <String, int>{};
      for (final shape in shapes) {
        if (shape.componentId != component.id) continue;
        final instance = shape.instanceId;
        if (instance == null) continue;
        final base = bases[instance];
        if (base == null || shape.z < base) bases[instance] = shape.z;
        if (shape.slot == 0) anchors[instance] = shape.center;
      }

      final out = <ShapeSpec>[];
      final done = <String>{};
      for (final shape in shapes) {
        final instance = shape.componentId == component.id
            ? shape.instanceId
            : null;
        if (instance == null) {
          out.add(shape);
          continue;
        }
        // The whole run is replaced at the position of its first member, and
        // the rest of the old run is dropped as it is met.
        if (!done.add(instance)) continue;
        out.addAll(
          component.stamp(
            at: anchors[instance] ?? shape.center,
            instanceId: instance,
            base: bases[instance] ?? shape.z,
          ),
        );
      }
      return out;
    }

    return _mapScreens(
      project,
      (screen) => screen.copyWith(shapes: rebuild(screen.shapes)),
    );
  }

  /// [project] with [fn] applied to every shape on every screen.
  Project _mapShapes(Project project, ShapeSpec Function(ShapeSpec) fn) =>
      _mapScreens(
        project,
        (screen) => screen.copyWith(shapes: screen.shapes.map(fn).toList()),
      );

  /// [project] with [fn] applied to every screen in every target.
  Project _mapScreens(Project project, ScreenDoc Function(ScreenDoc) fn) =>
      project.copyWith(
        subProjects: [
          for (final sub in project.subProjects)
            sub.copyWith(screens: sub.screens.map(fn).toList()),
        ],
      );

  void saveColorStyle(String projectId, ColorStyle style) {
    _mutateProject(
      projectId,
      (project) => project.copyWith(styles: project.styles.withColor(style)),
    );
  }

  void deleteColorStyle(String projectId, String styleId) {
    _mutateProject(
      projectId,
      (project) =>
          project.copyWith(styles: project.styles.withoutColor(styleId)),
    );
  }

  /// [project] with every caption tagged [style] rewritten to match it.
  Project _restyleCaptions(Project project, TextStyleDef style) {
    CaptionSpec? restyle(CaptionSpec? caption) =>
        caption == null || caption.styleId != style.id
        ? caption
        : style.applyTo(caption);

    return project.copyWith(
      subProjects: [
        for (final sub in project.subProjects)
          sub.copyWith(
            screens: [
              for (final screen in sub.screens)
                screen.copyWith(
                  caption: restyle(screen.caption),
                  subCaption: restyle(screen.subCaption),
                ),
            ],
          ),
      ],
    );
  }

  /// Lays [paths] across the set's screens that have no screenshot yet, one
  /// per screen, in order — growing the set when there are more captures than
  /// screens waiting for one. A screen that already has its picture keeps it.
  ///
  /// This is the shape a store listing actually arrives in: six captures, taken
  /// in the order they are meant to be seen, destined for six screens that
  /// share one treatment. Doing it by hand is six trips through the picker plus
  /// however many screens have to be created first, and every one of those is a
  /// chance to drop a capture or put two in the wrong order.
  ///
  /// Existing screens keep everything except the picture: their caption,
  /// backdrop, device and framing are the point of having set them up. The one
  /// exception is a phone a template lowered to show its artwork, which goes
  /// back where the listing designed it once the artwork is covered (see
  /// [settleTemplateArt]). A screen created to receive an overflow capture
  /// inherits the set's look the same way [addScreen] does, because it goes
  /// through it.
  ///
  /// Returns the screens that received one, in order, so the caller can open the
  /// first. Empty when [paths] is.
  List<ScreenDoc> importScreenshots(
    String projectId,
    String subProjectId,
    List<String> paths,
  ) {
    if (paths.isEmpty) return const [];
    final project = byId(projectId);
    if (project == null) throw Exception('Project not found');
    if (project.subProjectById(subProjectId) == null) {
      throw Exception('Target not found');
    }

    // The screens still waiting for a picture take the batch, in order. It
    // used to start at the first screen whatever was on it, so importing three
    // captures into a set whose first screen was done replaced that one and
    // left the empty fourth alone.
    List<int> waiting(List<ScreenDoc> screens) => [
      for (final (i, screen) in screens.indexed)
        if (screen.frames.isNotEmpty &&
            screen.frames.first.screenshot.imagePath == null)
          i,
    ];

    // Grow first, in a separate pass. Assigning and creating in one pass means
    // reading a sub-project that the previous iteration has already replaced,
    // and `addScreen` re-reads the store every call. A new screen arrives
    // without a picture, so it joins the ones waiting.
    final target = project.subProjectById(subProjectId)!;
    final open = waiting(target.screens).length;
    // Never past one screen on a feature graphic: the store takes one.
    if (target.target.formFactor != TargetFormFactor.graphic) {
      for (var i = open; i < paths.length; i++) {
        addScreen(projectId, subProjectId);
      }
    }

    final touched = <ScreenDoc>[];
    _mutateSubProject(projectId, subProjectId, (sub) {
      final screens = [...sub.screens];
      final slots = waiting(screens);
      for (var k = 0; k < paths.length && k < slots.length; k++) {
        final i = slots[k];
        final screen = screens[i];
        final next = _settleTemplateArt(
          screen,
          screen.copyWith(
            frames: [
              // The first frame only: a screen with two devices on it is a
              // composition somebody arranged, and guessing which of them a
              // batch was meant for would be worse than leaving the second one
              // alone.
              screen.frames.first.copyWith(
                screenshot: screen.frames.first.screenshot.copyWith(
                  imagePath: paths[k],
                ),
              ),
              ...screen.frames.skip(1),
            ],
          ),
        );
        screens[i] = next;
        touched.add(next);
      }
      return sub.copyWith(screens: screens);
    });
    return touched;
  }

  /// The only screen mutator that takes a target: the others are addressed by a
  /// screen that already exists and can find its own set, but a new screen has
  /// to be told which one it joins.
  ScreenDoc addScreen(String projectId, String subProjectId) {
    final project = byId(projectId);
    if (project == null) throw Exception('Project not found');
    final sub = project.subProjectById(subProjectId);
    if (sub == null) throw Exception('Target not found');

    final screen = _screenAfter(sub, caption: 'New screen');
    _mutateSubProject(
      projectId,
      subProjectId,
      (s) => s.copyWith(screens: [...s.screens, screen]),
    );
    return screen;
  }

  /// A fresh screen shaped like the end of [sub] — its look and its devices,
  /// none of its pictures.
  ///
  /// Shared by [addScreen] and by the padding a longer template asks for, so a
  /// screen that arrives either way arrives wearing the same things.
  ScreenDoc _screenAfter(SubProject sub, {required String caption}) {
    // Inherit from last screen, or use defaults
    final lastScreen = sub.screens.isNotEmpty ? sub.screens.last : null;

    return ScreenDoc(
      id: _uuid.v4(),
      // The set's canvas, not the last screen's: they agree in every ordinary
      // case, and where they do not the sub-project is the one that is right.
      canvas: sub.canvas,
      // A new screen inherits the set's look; only the first one in an empty
      // target falls back to the defaults.
      background: lastScreen?.background ?? kDefaultBackground,
      // The last headline's style with new words. Its runs go — a two-tone
      // headline kept them, so the "new" screen said what the last one said —
      // and so do its translations, which were translations of other words.
      caption:
          lastScreen?.caption?.copyWith(
            text: caption,
            runs: lastScreen.caption!.runs.isEmpty
                ? const []
                : CaptionSpec.runsByLine(lastScreen.caption!.runs, caption),
            translations: const {},
          ) ??
          CaptionSpec(
            text: caption,
            size: 64,
            lineHeight: 74,
            color: kDefaultCaptionColor,
          ),
      subCaption: lastScreen?.subCaption?.copyWith(
        text: 'Say what this screen shows',
        runs: const [],
        translations: const {},
      ),
      isCaptionAbove: lastScreen?.isCaptionAbove ?? true,
      // The backdrop too — the washes and shapes behind the device are part of
      // the set's look, the way "Apply to all" treats them. What stands in
      // front, and anything with words on it, belongs to the screen it is on.
      shapes: [
        for (final shape in lastScreen?.shapes ?? const <ShapeSpec>[])
          if (shape.z <= kStackBehindFrames && !shape.hasLabel) shape,
      ],
      // Every device the last screen had, not just the first. A set whose
      // screens are two phones side by side is a composition the user arranged
      // once and expects the next screen to join — handing them a single
      // device means rebuilding it by hand on every screen after the first.
      frames: lastScreen != null && lastScreen.frames.isNotEmpty
          ? [
              for (final frame in lastScreen.frames)
                frame.copyWith(
                  // `clearImages`, not `imagePath: null` — which was a no-op,
                  // so a new screen arrived wearing the previous screen's
                  // capture. The framing is inherited; the picture is not.
                  screenshot: frame.screenshot.copyWith(clearImages: true),
                ),
            ]
          // An empty target still gets whatever its own target calls for,
          // rather than a screen with nothing in it.
          : [starterFrame(sub.target, sub.canvas)],
    );
  }

  void updateScreen(String projectId, ScreenDoc screen) {
    _mutateOwnerOf(projectId, screen.id, (sub) {
      return sub.copyWith(
        screens: [
          for (final s in sub.screens)
            if (s.id == screen.id) _settleTemplateArt(s, screen) else s,
        ],
      );
    });
  }

  /// [after] with any device a template lowered for its artwork moved to where
  /// that template wants it, now that this edit has covered or uncovered the
  /// artwork. See [settleTemplateArt].
  ///
  /// Here, at the two places a capture enters a screen, so every way of adding
  /// one (a pick, a drop, a batch, the AI wizard) settles the device alike.
  /// Cheap for every other edit: a drag or a keystroke leaves each device's
  /// capture as it was, and the check stops there.
  ScreenDoc _settleTemplateArt(ScreenDoc before, ScreenDoc after) =>
      settleTemplateArt(
        before,
        after,
        templates: screenTemplates,
        catalog: ref.read(frameCatalogProvider).valueOrNull,
      );

  void deleteScreen(String projectId, String screenId) {
    _mutateOwnerOf(projectId, screenId, (sub) {
      return sub.copyWith(
        screens: sub.screens.where((s) => s.id != screenId).toList(),
      );
    });
  }

  void duplicateScreen(String projectId, String screenId) {
    _mutateOwnerOf(projectId, screenId, (sub) {
      final index = sub.screens.indexWhere((s) => s.id == screenId);
      if (index == -1) return sub;
      final duplicate = sub.screens[index].copyWith(id: _uuid.v4());
      final newScreens = List<ScreenDoc>.from(sub.screens)
        ..insert(index + 1, duplicate);
      return sub.copyWith(screens: newScreens);
    });
  }

  void moveScreenLeft(String projectId, String screenId) {
    _mutateOwnerOf(projectId, screenId, (sub) {
      final index = sub.screens.indexWhere((s) => s.id == screenId);
      if (index <= 0) return sub;
      final newScreens = List<ScreenDoc>.from(sub.screens);
      final screen = newScreens.removeAt(index);
      newScreens.insert(index - 1, screen);
      return sub.copyWith(screens: newScreens);
    });
  }

  void moveScreenRight(String projectId, String screenId) {
    _mutateOwnerOf(projectId, screenId, (sub) {
      final index = sub.screens.indexWhere((s) => s.id == screenId);
      if (index == -1 || index >= sub.screens.length - 1) return sub;
      final newScreens = List<ScreenDoc>.from(sub.screens);
      final screen = newScreens.removeAt(index);
      newScreens.insert(index + 1, screen);
      return sub.copyWith(screens: newScreens);
    });
  }

  /// Copies the visual style of [sourceScreenId] onto every other screen in the
  /// **same target** — background, frame device/colour/transform/shadow,
  /// screenshot framing, caption + subcaption styling and layout.
  ///
  /// Scoped to one sub-project rather than the whole project. The other targets
  /// are different canvases at different aspects, and a look tuned for a 9:20
  /// phone is not automatically the look their 13-inch iPad set wants; pushing
  /// it there is [copyScreensFrom]'s job, which the user asks for by name.
  ///
  /// Style only. Every screen keeps the three things that make it *that*
  /// screen: its screenshot image, its caption and subcaption text, and its
  /// backdrop photo. The rule is the same in all three cases — the source
  /// supplies the treatment, the target supplies the content — so applying a
  /// design across a set never silently overwrites work that cannot be
  /// recovered by re-applying from somewhere else.
  ///
  /// Returns the set exactly as it was, or null when nothing was changed. It is
  /// one action across every screen in a target with no per-screen confirmation
  /// in front of it, so the caller can offer a single Undo that puts all of
  /// them back — see [restoreSubProject]. Style is not content, but "restyle
  /// eight screens" is still the largest single edit in the app, and the answer
  /// to doing it by accident cannot be re-tuning eight screens by hand.
  SubProject? applyStyleToAll(String projectId, String sourceScreenId) {
    final project = byId(projectId);
    if (project == null) return null;
    final owner = project.subProjectOf(sourceScreenId);
    if (owner == null) return null;
    ScreenDoc? source;
    for (final s in owner.screens) {
      if (s.id == sourceScreenId) source = s;
    }
    if (source == null || source.frames.isEmpty) return null;
    final src = source;

    /// The source's [i]th device, wearing the target's own pictures.
    ///
    /// Paired by position rather than collapsed to one. A screen holding two
    /// phones side by side is a composition, and a look applied across the set
    /// used to replace every target's `frames` with a single frame — throwing
    /// away the second device on every other screen as a side effect of
    /// restyling them.
    FramePlacement restyleFrame(int i, ScreenDoc target) {
      final srcFrame = src.frames[i];
      final targetFrame = i < target.frames.length ? target.frames[i] : null;
      return FramePlacement(
        deviceId: srcFrame.deviceId,
        variantId: srcFrame.variantId,
        transform: srcFrame.transform,
        opacity: srcFrame.opacity,
        frameHidden: srcFrame.frameHidden,
        cutoutHidden: srcFrame.cutoutHidden,
        shadow: srcFrame.shadow,
        // A built frame is the design, not content. It was the one part of the
        // frame this skipped, so applying a style across a set moved the device
        // and its transform but left every other screen still wearing the
        // catalog artwork — the bezel, corners and colours the whole look was
        // built on did not travel.
        design: srcFrame.design,
        // This screen keeps its own pictures and adopts the source's framing.
        //
        // The whole set of them, not just the one showing: a frame carries
        // several captures now, and copying only the active one would quietly
        // drop the alternates off every screen the look was applied to.
        screenshot: targetFrame == null
            ? srcFrame.screenshot.copyWith(clearImages: true)
            : srcFrame.screenshot.copyWith(
                images: targetFrame.screenshot.images,
                index: targetFrame.screenshot.activeIndex,
              ),
      );
    }

    ScreenDoc restyle(ScreenDoc target) {
      if (target.id == src.id) return target;
      return target.copyWith(
        background: _restyleBackground(src.background, target.background),
        isCaptionAbove: src.isCaptionAbove,
        frames: [
          for (var i = 0; i < src.frames.length; i++) restyleFrame(i, target),
        ],
        // Shapes are treatment, not content: they carry no text and no image,
        // so there is nothing of the target's own for them to overwrite. The
        // badge, the blob behind the phone and the underline beneath the
        // headline are exactly the parts of a look that has to reach the rest
        // of the set, and re-applying from another screen puts them back.
        shapes: src.shapes,
        caption: _restyleCaption(src.caption, target.caption),
        subCaption: _restyleCaption(src.subCaption, target.subCaption),
      );
    }

    _mutateSubProject(
      projectId,
      owner.id,
      (sub) => sub.copyWith(screens: sub.screens.map(restyle).toList()),
    );
    return owner;
  }

  /// Sets the languages [projectId] is made in. The first is the default.
  ///
  /// Moving a different language to the front is a change of default, which
  /// swaps each caption's own words with that language's translation — see
  /// [swapDefaultLanguage] — so no words are lost or relabelled.
  void setLanguages(String projectId, List<String> languages) {
    if (languages.isEmpty) return;
    _mutateProject(projectId, (pr) {
      final from = pr.defaultLanguage;
      final to = languages.first;
      if (from == to) return pr.copyWith(languages: languages);
      return pr.copyWith(
        languages: languages,
        subProjects: [
          for (final sub in pr.subProjects)
            sub.copyWith(
              screens: [
                for (final screen in sub.screens)
                  swapDefaultLanguage(screen, from: from, to: to),
              ],
            ),
        ],
      );
    });
  }

  /// Replaces what [projectId] says about the app: the brief its store copy
  /// is drafted from.
  void setListingBrief(String projectId, ListingBrief brief) =>
      _mutateProject(projectId, (pr) => pr.copyWith(brief: brief));

  /// Changes [projectId]'s store copy through [change], applied to the copy as
  /// it stands at that moment.
  ///
  /// A function rather than a value because store copy is written from more
  /// than one place at once: a translation lands a language at a time while
  /// the person keeps typing in another field, and a value read before either
  /// would put back whatever the other had just written.
  void updateStoreCopy(
    String projectId,
    StoreCopy Function(StoreCopy copy) change,
  ) => _mutateProject(
    projectId,
    (pr) => pr.copyWith(storeCopy: change(pr.storeCopy)),
  );

  /// Replaces [projectId]'s store copy outright — what Undo puts back.
  void setStoreCopy(String projectId, StoreCopy copy) =>
      updateStoreCopy(projectId, (_) => copy);

  /// Sets [projectId]'s app icon, or takes it away with null — after which
  /// the project saves exactly as it did before it had one.
  void setIcon(String projectId, IconDoc? icon) => _mutateProject(
    projectId,
    (pr) =>
        icon == null ? pr.copyWith(clearIcon: true) : pr.copyWith(icon: icon),
  );

  /// Changes [projectId]'s icon through [change], applied to the icon as it
  /// stands at that moment — for a result that lands while the person goes on
  /// editing. Nothing happens when the project has no icon.
  void updateIcon(String projectId, IconDoc Function(IconDoc icon) change) =>
      _mutateProject(projectId, (pr) {
        final icon = pr.icon;
        return icon == null ? pr : pr.copyWith(icon: change(icon));
      });

  /// Turns one set's continuous canvas on or off. See [SubProject.continuous].
  ///
  /// Turning it on gives every screen the background of [backgroundFrom] — the
  /// screen the user was on — so the one background the set now shows is the
  /// one they were looking at, and turning it off again leaves each screen
  /// holding a whole copy of it rather than a slice.
  void setContinuous(
    String projectId,
    String subId, {
    required bool on,
    String? backgroundFrom,
  }) {
    _mutateProject(
      projectId,
      (pr) => pr.copyWith(
        subProjects: [
          for (final sub in pr.subProjects)
            if (sub.id != subId)
              sub
            else
              _continuous(sub, on: on, backgroundFrom: backgroundFrom),
        ],
      ),
    );
  }

  static SubProject _continuous(
    SubProject sub, {
    required bool on,
    String? backgroundFrom,
  }) {
    if (!on) {
      // Separate pictures again, each keeping what it showed: a panorama — a
      // pattern or a picture — leaves every screen on its own slice of it, as
      // the continuous set drew it, rather than on the one slice they all
      // stored, or the whole picture squeezed into each.
      final shared = sub.screens.firstOrNull?.background;
      if (shared == null || !isPanorama(shared)) {
        return sub.copyWith(continuous: false);
      }
      final count = sub.screens.length;
      return sub.copyWith(
        continuous: false,
        screens: [
          for (final (i, screen) in sub.screens.indexed)
            screen.copyWith(
              background: panoramaAt(shared, index: i, count: count),
            ),
        ],
      );
    }
    final source =
        sub.screens.where((s) => s.id == backgroundFrom).firstOrNull ??
        sub.screens.firstOrNull;
    if (source == null) return sub.copyWith(continuous: true);
    return sub.copyWith(
      continuous: true,
      screens: [
        for (final screen in sub.screens)
          screen.copyWith(background: source.background),
      ],
    );
  }

  /// Puts a set back exactly as [snapshot] had it.
  ///
  /// The whole of undo for the bulk actions on the project screen. A
  /// [SubProject] is immutable and holds every screen in the set, so keeping
  /// one before the change and writing it back afterwards restores the screens,
  /// their order and every document on them without the store having to model
  /// what any individual action did.
  void restoreSubProject(String projectId, SubProject snapshot) {
    _mutateProject(
      projectId,
      (pr) => pr.copyWith(
        subProjects: [
          for (final sub in pr.subProjects)
            if (sub.id == snapshot.id) snapshot else sub,
        ],
      ),
    );
  }

  /// Dresses every screen in one target in [template].
  ///
  /// The set rather than a screen, because that is the unit a look is chosen
  /// for: a listing whose five screens share a backdrop and a headline setting
  /// reads as one product, and five screens that each picked their own read as
  /// five apps. The editor applies the same template to a single document
  /// through [ScreenTemplate.applyTo] and its own undo stack.
  ///
  /// Non-destructive to what is already there — the template carries no words,
  /// no screenshots and no shapes, so everything on these screens survives it.
  /// [withCopy] is for a set whose words are placeholders: it takes the
  /// listing's copy and its sample app UI as well, the UI as a display fill
  /// that any screenshot covers.
  ///
  /// It does **grow** a set that is shorter than the listing, which is the one
  /// change it makes that is not purely visual; [restoreSubProject] undoes the
  /// whole thing, and the returned snapshot is what to hand it.
  ///
  /// Null when nothing changed: no such set, or a listing with no design for
  /// it — a feature graphic, which no listing designs today.
  SubProject? applyTemplate(
    String projectId,
    String subId,
    ScreenTemplate template, {
    bool withCopy = false,
  }) {
    final before = byId(projectId)?.subProjectById(subId);
    if (before == null) return null;

    // Only the project knows what this set *is*: a banner and a handset laid on
    // its side are the same shape, and the template has a different design for
    // each.
    final banner = before.target.formFactor == TargetFormFactor.graphic;
    final canvas =
        before.screens.firstOrNull?.canvas ?? before.target.defaultPreset.size;
    // The listing's drawn handset only where the gallery previewed it, and the
    // set's own device, placed by its own proportions, everywhere else.
    final withFrame = templateWearsFrame(before.target, template);
    final catalog = ref.read(frameCatalogProvider).valueOrNull;

    // A listing with nothing designed for this set — a feature graphic, from a
    // listing without a banner — leaves it alone, and says so by returning
    // nothing to undo.
    final length = template.lengthFor(canvas, banner: banner);
    if (length == 0) return null;

    _mutateSubProject(projectId, subId, (sub) {
      final screens = _padTo(sub, length);
      return sub.copyWith(
        screens: [
          for (var i = 0; i < screens.length; i++)
            // Screen *i* of the set takes screen *i* of the listing. A template
            // is a set of designs rather than one repeated — the opener, the
            // feature screens and the closing card are different pictures — so
            // pairing them by position is what makes an applied template read
            // the way the listing it came from does.
            //
            // The listing's app UI travels with its words. A set taking the
            // listing's copy is a fresh one (a new project, the AI wizard), and
            // it opens looking like the preview it was chosen from rather than
            // as a row of grey phones; the first screenshot dropped in covers
            // the artwork. A set with words of its own keeps them and its
            // phones take the listing's screen colour instead.
            template.applyTo(
              screens[i],
              index: i,
              withCopy: withCopy,
              withDisplay: withCopy,
              banner: banner,
              withFrame: withFrame,
              catalog: catalog,
            ),
        ],
      );
    });
    return before;
  }

  /// [sub]'s screens, grown to [count] if it is shorter.
  ///
  /// Applying an eight-screen listing to a three-screen set used to dress three
  /// screens and drop the other five designs on the floor. The set grows to
  /// meet the listing instead, so choosing a template shows the whole of it.
  ///
  /// Only ever grows. A set of ten that takes a six-screen listing keeps all
  /// ten and wraps — deleting somebody's screens to match a *look* would be the
  /// destructive reading of a restyle.
  List<ScreenDoc> _padTo(SubProject sub, int count) {
    // A banner is exactly one image whatever the listing it borrows a look from
    // happens to do, which is the same rule `screenCountFor` applies at
    // creation.
    if (sub.target.formFactor == TargetFormFactor.graphic) return sub.screens;

    final wanted = count.clamp(1, StoreTarget.maxStarterScreens);
    if (sub.screens.length >= wanted) return sub.screens;

    final screens = [...sub.screens];
    while (screens.length < wanted) {
      screens.add(
        // Through a sub-project carrying the screens built so far, so each new
        // screen inherits the one before it rather than all of them inheriting
        // the original last screen.
        _screenAfter(
          sub.copyWith(screens: screens),
          caption: 'Highlight feature ${screens.length + 1}',
        ),
      );
    }
    return screens;
  }

  /// The source's backdrop treatment over the target's own picture.
  ///
  /// A photo backdrop is content, exactly like the screenshot in the frame: the
  /// set is five different shots of the app, and pushing one screen's photo
  /// across all of them destroys four. So an image backdrop hands over its
  /// *treatment* — the fit, the zoom, the pan, the blur, the wash — and the
  /// target keeps its own [ImageBackground.path].
  ///
  /// A target with no picture of its own is left alone rather than given a
  /// backdrop that points at someone else's file. Solid, gradient and pattern
  /// fills carry no content and copy across whole.
  Background _restyleBackground(Background source, Background target) {
    if (source is! ImageBackground) return source;
    if (target is! ImageBackground) return target;
    // How the target's own picture is laid across the set travels with the
    // picture, not with the treatment: a panorama's slicing handed to a
    // screen holding one ordinary photo would cut that photo into strips.
    return source.copyWith(
      path: target.path,
      slices: target.slices,
      slice: target.slice,
    );
  }

  /// Gives every screen of [subId] the one background [background]: a
  /// panorama spread across the set, each screen on its own slice of it, and
  /// anything else as it is.
  ///
  /// What a generated panorama lands with. Through [_mutateSubProject] like
  /// every other edit, so one undo puts the whole set back.
  void spreadBackground(String projectId, String subId, Background background) {
    _mutateSubProject(projectId, subId, (sub) {
      final count = sub.screens.length;
      return sub.copyWith(
        screens: [
          for (final (i, screen) in sub.screens.indexed)
            screen.copyWith(
              background: panoramaAt(background, index: i, count: count),
            ),
        ],
      );
    });
  }

  /// The source's caption styling over the target's own words.
  CaptionSpec? _restyleCaption(CaptionSpec? source, CaptionSpec? target) {
    if (source == null) return target;
    return source.copyWith(
      text: target?.plainText ?? source.text,
      // Rich captions carry their words *inside* the run list, so adopting the
      // source's runs wholesale would push the source's text across the set
      // through the back door — the flat `text` above is not the only place a
      // caption keeps what it says.
      runs: _restyleRuns(source.runs, target),
      clearBackgroundColor: source.backgroundColor == null,
    );
  }

  /// Per-run styling from [sourceRuns], words from [target].
  ///
  /// The mapping itself is [CaptionRuns.restyleLike] — positional by line and,
  /// within a line, by character, with both extending rather than resetting
  /// when the target has more of either. What is decided here is only whether
  /// to map at all.
  List<CaptionRun> _restyleRuns(
    List<CaptionRun> sourceRuns,
    CaptionSpec? target,
  ) {
    final targetRuns = target?.runs ?? const <CaptionRun>[];
    // The target was never rich, so it stays plain: `text` already holds
    // everything it says, and splitting it into runs here would be a structural
    // edit rather than a restyle.
    if (targetRuns.isEmpty) return const <CaptionRun>[];
    // Nothing to take. The target keeps the runs it has rather than being
    // flattened by a source that simply never used them.
    if (sourceRuns.isEmpty) return targetRuns;
    return CaptionRuns.restyleLike(sourceRuns, targetRuns);
  }

  void _mutateProject(String projectId, Project Function(Project) fn) {
    state = [
      for (final p in state)
        if (p.id == projectId) fn(p) else p,
    ];
    _scheduleSave();
  }

  void _mutateSubProject(
    String projectId,
    String subId,
    SubProject Function(SubProject) fn,
  ) => _mutateProject(projectId, (pr) => pr.withSubProject(subId, fn));

  /// Applies [fn] to whichever sub-project owns [screenId].
  ///
  /// This is what lets every screen mutator keep its `(projectId, screenId)`
  /// signature through the move to targets. Screen ids are uuids, so the owner
  /// is unambiguous, and the editor never has to carry a target in its route to
  /// save a document.
  void _mutateOwnerOf(
    String projectId,
    String screenId,
    SubProject Function(SubProject) fn,
  ) {
    final owner = byId(projectId)?.subProjectOf(screenId);
    if (owner == null) return;
    _mutateSubProject(projectId, owner.id, fn);
  }
}

// ---------------------------------------------------------------------------
// Starter screens
// ---------------------------------------------------------------------------

/// The screens a target opens with, before the user has touched anything.
///
/// Top-level rather than a method on the store because the new-project form
/// needs one too: its template picker previews the look on the screen the
/// project is about to be created with, and a second, hand-rolled copy of this
/// in the form is exactly how a preview stops matching what gets made.
///
/// [newId] supplies each screen id, so the store can hand in its uuid generator
/// and a caller that is only going to draw the result can hand in anything.
List<ScreenDoc> starterScreens(
  StoreTarget target,
  Size canvas, {
  required String Function() newId,
  String? deviceId,
  String? variantId,
  double cornerRadiusPct = 0,

  /// How many to make. Defaults to the target's own starter count; a project
  /// created with a listing template asks for that listing's length instead.
  int? screenCount,
}) => [
  for (var i = 0; i < (screenCount ?? target.starterScreenCount); i++)
    ScreenDoc(
      id: newId(),
      canvas: canvas,
      background: kDefaultBackground,
      caption: CaptionSpec(
        // A banner is one image with one line across it; the two-line
        // opener belongs to a set, where it has a whole screenshot's
        // height of room above the device.
        text: target.formFactor == TargetFormFactor.graphic
            ? 'Your headline here'
            : i == 0
            ? 'Your headline\ngoes here.'
            : 'Highlight feature ${i + 1}',
        size: 64,
        lineHeight: 74,
        color: kDefaultCaptionColor,
      ),
      frames: [
        starterFrame(
          target,
          canvas,
          deviceId: deviceId,
          variantId: variantId,
          cornerRadiusPct: cornerRadiusPct,
        ),
      ],
    ),
];

/// What a starter screen puts around its screenshot.
///
/// Three cases, in order. A target that names its own frame gets it: an iPad
/// set opens in an iPad and a Mac set in a MacBook, whatever handset the
/// new-project form happened to resolve, because that picker is a handset
/// picker and has nothing useful to say about either. A handset target gets
/// the device the user actually picked. And a target with neither — the Play
/// feature graphic, which is a banner rather than a device shot — gets a bare
/// screenshot: a hidden frame over a zero-thickness [FrameDesign] whose aspect
/// is the canvas's own, which is what makes the aperture full-bleed and
/// correctly proportioned rather than phone-shaped.
FramePlacement starterFrame(
  StoreTarget target,
  Size canvas, {
  String? deviceId,
  String? variantId,
  double cornerRadiusPct = 0,
}) {
  const shadow = ShadowSpec(opacity: 0.28, blur: 32);
  final isLandscape = canvas.width > canvas.height;

  final own = target.defaultFrame;
  if (own != null) {
    return FramePlacement(
      deviceId: own.$1,
      variantId: own.$2,
      // The drawn bodies carry their own aperture radius in the catalog, so
      // the handset pick's radius would be describing a different screen.
      screenshot: const ScreenshotSpec(),
      shadow: shadow,
      // No rotation: these bodies are already the shape of their canvas —
      // a laptop is landscape because a laptop is landscape.
      transform: const Transform2D(),
    );
  }

  if (target.wearsDeviceFrame) {
    // A framed target always ends up framed, even when the caller had no
    // device to offer — adding an iPhone target to a Mac-only project, or to
    // one whose every set is deliberately frameless, should still hand back a
    // phone. Only a target the catalog cannot serve falls through.
    // Only reached when nothing else supplied a device — the new-project form
    // resolves one through the live catalog and passes it in. Both ids are
    // resolved leniently downstream (`byId` falls back to the first device,
    // and an unknown finish to the device's first), so a catalog that ships
    // without the default costs the default rather than the screen.
    final fallback = defaultHandsetFor(target.catalogPlatform);
    return FramePlacement(
      deviceId: deviceId ?? fallback.deviceId,
      variantId: deviceId == null
          ? fallback.variantId
          : (variantId ?? fallback.variantId),
      screenshot: ScreenshotSpec(cornerRadiusPct: cornerRadiusPct),
      shadow: shadow,
      transform: Transform2D(rotationDeg: isLandscape ? -90 : 0),
    );
  }

  return FramePlacement(
    // The design supplies every dimension the renderer reads, so this id only
    // decides which half of the catalog the frame picker opens on if the user
    // later goes looking for a real device.
    deviceId:
        '$kCustomFrameIdPrefix-'
        '${target.catalogPlatform == FramePlatform.ios ? 'ios' : 'android'}',
    variantId: 'design',
    frameHidden: true,
    design: FrameDesign(
      thickness: 0,
      topThickness: 0,
      bottomThickness: 0,
      aspect: canvas.width / canvas.height,
    ),
    // A share of the shortest side rather than a fixed radius, so the corners
    // read the same on a 640-wide web shot and a 3840-wide 4K one.
    screenshot: const ScreenshotSpec(cornerRadiusPct: 0.02),
    shadow: shadow,
    // Smaller than the framed default's 0.7, because the aperture matches the
    // canvas's own aspect: at 0.7 the screenshot is 70% of the height *and*
    // 70% of the width, leaving a 15% band for a caption whose size is a
    // share of a canvas that is now very wide. Two lines of the starter
    // headline do not fit in it. 0.58 leaves 21%, which they do.
    transform: const Transform2D(pagePercentage: 0.58),
  );
}
