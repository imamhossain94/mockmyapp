import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../app/layout/studio_layout.dart';
import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../data/assets/studio_fonts.dart';
import '../../data/assets/frame_catalog.dart';
import '../../data/repositories/fastlane_layout.dart';
import '../../data/repositories/image_library.dart';
import '../../data/repositories/project_store.dart';
import '../../data/repositories/stored_image.dart';
import '../../data/services/device_storage.dart';
import '../../data/services/on_device_ai.dart';
import '../../data/services/video_encoder.dart';
import '../../domain/ai_backgrounds/design_palette.dart' show paletteOf;
import '../../domain/providers/editor_language_provider.dart';
import '../../domain/providers/on_device_ai_provider.dart';
import '../../domain/providers/video_settings_provider.dart';
import '../../domain/engine/continuous.dart';
import '../../domain/engine/export_settings.dart';
import '../../domain/engine/localize.dart';
import '../../domain/engine/scene_renderer.dart';
import '../../domain/engine/scene_view.dart';
import '../../domain/engine/undo_stack.dart';
import '../../domain/models/locales.dart';
import '../../domain/models/caption_runs.dart';
import '../../domain/models/layer_stack.dart';
import '../../domain/models/project.dart';
import '../../domain/models/screen_doc.dart';
import '../../domain/models/style_library.dart';
import '../../domain/models/screen_template.dart';
import '../../domain/models/store_target.dart';
import '../../domain/models/sub_project.dart';
import '../ai_backgrounds/ai_background_panel.dart';
import '../../domain/store_copy/copy_export.dart';
import '../../domain/store_copy/store_limits.dart';
import '../project/project_actions.dart';
import '../shared/friendly_error.dart';
import '../shared/image_library_view.dart';
import '../shared/project_scope.dart';
import '../shared/save_actions.dart';
import '../shared/template_sheet.dart';
import '../shared/widgets/widgets.dart';
import 'panels/background_panel.dart';
import 'panels/caption_panel.dart';
import 'panels/frame_layout_panel.dart';
import 'panels/image_layer_panel.dart';
import 'panels/layers_panel.dart';
import 'panels/screenshot_panel.dart';
import 'panels/shape_panel.dart';
import 'panels/text_layer_panel.dart';
import 'widgets/caption_ideas_sheet.dart';
import 'widgets/device_picker_sheet.dart';
import 'widgets/element_library.dart';
import 'widgets/rich_caption_editor.dart'
    show captionBackdropOf, showRichCaptionEditor;
import 'widgets/scene_pick.dart';
import 'widgets/store_preview.dart';
import 'widgets/shape_gallery.dart';
import 'widgets/svg_shape_import.dart';
import 'widgets/tool_sheet_height.dart';
import 'widgets/video_export_sheet.dart';

part 'workspace/canvas.dart';
part 'workspace/chrome.dart';
part 'workspace/languages.dart';
part 'workspace/library.dart';
part 'workspace/panels.dart';
part 'workspace/strip.dart';

/// The studio: one project, one store target at a time, every screen of it
/// side by side.
///
/// This is the whole app once a project is open. It used to be two pages — a
/// grid of screen thumbnails, and an editor for one screen reached by tapping a
/// thumbnail — and the round trip between them was most of what editing a
/// listing felt like. A listing is read as a strip, in the store and by the
/// person designing it, so it is edited as one: the screens sit next to each
/// other on a single canvas, one of them is active, and everything around the
/// canvas acts on it.
///
/// Around the canvas:
///
/// * a top bar with the project, the target, history and **Download**;
/// * a rail of libraries on the left — Templates, Devices, Elements, Text,
///   Background, Uploads, AI — each opening a panel of things to add;
/// * a properties panel on the right for whatever is selected;
/// * a floating toolbar under the canvas for its size and zoom.
///
/// A phone held upright has no room for side panels, so the rail becomes a tab
/// bar along the bottom and both kinds of panel share one sheet above it.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.projectId, this.screenId});

  final String projectId;

  /// The screen to open on, or null for the first screen of the first target.
  ///
  /// The target is whichever one owns this screen, so a link to a screen is a
  /// link to its set.
  final String? screenId;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

/// The libraries on the rail, in display order.
enum _Library {
  templates('Templates', StudioIcons.palette, 560),
  devices('Devices', StudioIcons.devices, 460),
  elements('Elements', StudioIcons.shapes, 420),
  text('Text', StudioIcons.text, 280),
  background('Background', StudioIcons.background, 400),
  uploads('Uploads', StudioIcons.upload, 440),

  /// AI backgrounds: art direction, generated pictures and panoramas, and the
  /// jobs on their way. Last, so the shortcuts 1–6 keep their libraries.
  ai('AI', StudioIcons.ai, 600);

  const _Library(this.label, this.icon, this.sheetHeight);

  final String label;
  final StudioIconData icon;

  /// How tall this library wants the phone sheet, excluding the home
  /// indicator. A ceiling rather than a promise; the sheet caps it against the
  /// screen and the panel scrolls.
  final double sheetHeight;
}

/// Which of the two side panels was asked for last.
///
/// Only matters where there is room for one of them at a time — a desktop
/// window shows both — and there it decides which one is showing.
enum _Pane { library, properties }

class _EditorScreenState extends ConsumerState<EditorScreen>
    with ProjectActions<EditorScreen> {
  // ---------------------------------------------------------------------------
  // Where we are
  // ---------------------------------------------------------------------------

  /// The target being shown, or null for the project's first.
  String? _subId;

  /// The screen being edited, or null for the target's first.
  String? _screenId;

  @override
  String get projectId => widget.projectId;

  ProjectStore get _store => ref.read(projectStoreProvider.notifier);

  Project? get _project => _store.byId(widget.projectId);

  /// The target on show, falling back to the project's first.
  ///
  /// The fallback is what covers "Remove target" and a target moved to another
  /// project: an id that no longer names anything is not an error, it simply
  /// is not the active set any more.
  SubProject? get _sub {
    final project = _project;
    if (project == null) return null;
    final id = _subId;
    return (id == null ? null : project.subProjectById(id)) ??
        project.subProjects.firstOrNull;
  }

  /// The document being edited, straight from the store.
  ///
  /// Never a private copy. Every edit is written through to the store as it
  /// happens, so the store *is* the working state — and reading it back means a
  /// template applied to the set, an undo that restores it, or a screen deleted
  /// beside this one all land here without having to be told.
  ScreenDoc? get doc => switch (_baseDoc) {
    final base? => localizeScreen(base, _lang),
    null => null,
  };

  /// The language being edited, or null for the project's default.
  ///
  /// Remembered per project on this device, so the editor reopens on it.
  String? get _language => ref.read(editorLanguagesProvider)[widget.projectId];

  /// [_language] if it is still one of the project's, and not its default —
  /// which is edited as the screens' own words, with no lens at all.
  String? get _lang {
    final project = _project;
    final language = _language;
    if (project == null || language == null) return null;
    if (language == project.defaultLanguage) return null;
    return project.languages.contains(language) ? language : null;
  }

  /// The screens of [sub] as they read in the language being edited.
  List<ScreenDoc> _shown(SubProject sub) => [
    for (final s in sub.screens) localizeScreen(s, _lang),
  ];

  /// The active screen's background as the canvas shows it, or null where
  /// that is simply its own.
  ///
  /// In a continuous set every screen shows the set's one background — the
  /// first screen's — and a panorama shows this screen's slice of it (see
  /// [panoramaAt]), not the slice the screen happens to store.
  Background? get _shownBackground {
    final sub = _sub;
    final base = _baseDoc;
    if (sub == null || base == null || !sub.continuous) return null;
    final index = sub.screens.indexWhere((s) => s.id == base.id);
    if (index < 0) return null;
    return panoramaAt(
      sub.screens.first.background,
      index: index,
      count: sub.screens.length,
    );
  }

  /// The active screen as stored: every language's shared design, with the
  /// default language's words.
  ScreenDoc? get _baseDoc {
    final screens = _sub?.screens ?? const <ScreenDoc>[];
    final id = _screenId;
    if (id != null) {
      for (final screen in screens) {
        if (screen.id == id) return screen;
      }
    }
    return screens.firstOrNull;
  }

  // ---------------------------------------------------------------------------
  // Selection and panels
  // ---------------------------------------------------------------------------

  /// What is selected on the active screen, or null for nothing.
  SceneSelection? _selected;

  /// Whether the freehand shape tool is armed. See [SceneView.drawing].
  bool _drawing = false;

  bool _preview = false;
  bool _busy = false;
  ScreenDoc? _transformBaseDoc;

  /// The open library, or null with the library panel closed.
  ///
  /// Starts open on Templates in a desktop window, which has the room, and
  /// closed everywhere else, where the canvas needs it more.
  _Library? _library;

  /// The library a phone's tab bar is showing. A phone always has one, because
  /// its tab bar always has a tab selected even with the sheet collapsed.
  _Library _phoneLibrary = _Library.templates;

  /// Whether the properties panel is showing the whole layer stack rather than
  /// the selected layer's controls.
  bool _layers = false;

  /// Whether a selected text or image layer is showing the Shape tool — its
  /// size, position and shadow — rather than its own tool. Set by that tool's
  /// "Position, layer order and shadow" button; any fresh selection clears it.
  bool _shapeTools = false;

  /// The panel asked for last. See [_Pane].
  _Pane _pane = _Pane.library;

  /// Whether the properties panel has been dismissed for the current
  /// selection. Cleared by the next selection.
  bool _propertiesDismissed = false;

  bool _sheetExpanded = false;

  /// The height the sheet's current section asked for, or null for its
  /// default. See [ToolSheetHeightRequest].
  double? _sheetHeightRequest;

  /// Whether a phone's canvas keeps its size while the sheet opens, the sheet
  /// riding over it instead of squeezing it.
  bool _canvasLocked = false;

  double? _libraryWidth;
  double? _propertiesWidth;

  /// The canvas zoom, for the toolbar's readout.
  final _zoom = ValueNotifier<double>(1);

  /// Snapshots of the whole target, not of one screen.
  ///
  /// With every screen on one canvas, a history per screen would be a lie: you
  /// duplicate screen 2, recolour screen 3, and undo would have to know which
  /// screen you were thinking of. A target is immutable and holds every screen
  /// in the set, so one stack of them undoes edits, reorders, additions and
  /// deletions alike, in the order they happened.
  /// Undo history, one per target — see [_showTarget].
  final _histories = <String, UndoStack<SubProject>>{};

  UndoStack<SubProject> _historyOf(String subId) =>
      _histories.putIfAbsent(subId, UndoStack<SubProject>.new);

  /// The history of the target on show.
  UndoStack<SubProject> get _undoStack => _historyOf(_sub?.id ?? '');

  final _viewport = GlobalKey<_CanvasViewportState>();

  /// Whether the canvas has been brought to the active screen yet. Done once,
  /// after the first layout, when the viewport knows how big it is.
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_keepKeyboard);
    final id = widget.screenId;
    if (id != null) {
      _screenId = id;
      _subId = _project?.subProjectOf(id)?.id;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decided once, on the first frame that knows the window. A desktop window
    // opens a fresh set with Templates showing, because that is the first
    // thing worth doing to it. A set already under way opens on the canvas:
    // the gallery open on every visit was one stray click from restyling all
    // eight screens of finished work. Anything smaller opens on the canvas.
    if (!_openedLibrary) {
      _openedLibrary = true;
      final fresh = !(_sub?.screens ?? const <ScreenDoc>[]).any(
        (screen) => screen.frames.any((f) => f.screenshot.imagePath != null),
      );
      if (context.layout.isDesktop && fresh) _library = _Library.templates;
    }
  }

  bool _openedLibrary = false;

  @override
  void dispose() {
    FocusManager.instance.removeListener(_keepKeyboard);
    _zoom.dispose();
    _keyboard.dispose();
    _stageSettle?.cancel();
    super.dispose();
  }

  /// The canvas's size as last laid out, and a check on the active screen
  /// once a change of it has settled — see [_keepActiveInView].
  Size? _stageSize;
  Timer? _stageSettle;

  /// Keeps the active screen where it was in the window as the canvas changes
  /// size under it — a panel sliding in beside it, or a phone's sheet rising
  /// under it.
  ///
  /// The view's offset is in window pixels and the strip is laid out against
  /// the canvas's height, so a sheet rising shrank every screen under an
  /// offset that stayed put: the screen just selected slid off the left edge,
  /// and the tools that opened for it were editing something out of sight.
  /// The screen's centre keeps its share of the window instead, so a zoomed
  /// view stays zoomed on the same part of it.
  void _anchorActive(Size from, Size to) {
    final viewport = _viewport.currentState;
    final sub = _sub;
    final before = _geometry(from);
    final after = _geometry(to);
    if (viewport == null || sub == null || before == null || after == null) {
      return;
    }
    final index = sub.screens.indexWhere((s) => s.id == doc?.id);
    if (index < 0) return;
    final scale = viewport.scale;
    final was = before.focusRect(index).center * scale + viewport._offset;
    final share = Offset(was.dx / from.width, was.dy / from.height);
    final rect = after.focusRect(index);
    var offset =
        Offset(share.dx * to.width, share.dy * to.height) - rect.center * scale;
    // Then kept whole, where it fits. Its share alone left a screen near the
    // side of the canvas with its edge under the rail once a panel narrowed
    // the canvas — seven pixels of it, but the one being edited.
    double inside(double start, double end, double room) {
      final size = end - start;
      if (size > room) return 0;
      final margin = math.min(StudioSpace.m, (room - size) / 2);
      if (start < margin) return margin - start;
      if (end > room - margin) return room - margin - end;
      return 0;
    }

    offset += Offset(
      inside(
        rect.left * scale + offset.dx,
        rect.right * scale + offset.dx,
        to.width,
      ),
      inside(
        rect.top * scale + offset.dy,
        rect.bottom * scale + offset.dy,
        to.height,
      ),
    );
    viewport.moveWhileRebuilding(offset);
  }

  /// Brings the active screen back into view when a change of the canvas's
  /// width — a panel opening or closing beside it, the window resizing — has
  /// left it mostly hidden. At tablet width a panel sliding in covered half
  /// the screen being edited. The zoom is kept; only the view moves, and only
  /// when it has to.
  void _keepActiveInView() {
    if (!mounted) return;
    final viewport = _viewport.currentState;
    final geometry = _geometry(viewport?.viewportSize);
    final sub = _sub;
    if (viewport == null || geometry == null || sub == null) return;
    final index = sub.screens.indexWhere((s) => s.id == doc?.id);
    if (index < 0) return;
    final rect = geometry.focusRect(index);
    final scale = viewport.scale;
    final left = rect.left * scale + viewport._offset.dx;
    final right = rect.right * scale + viewport._offset.dx;
    final width = viewport.viewportSize.width;
    final shown = math.min(right, width) - math.max(left, 0.0);
    if (right > left && shown / (right - left) < 0.6) {
      viewport.focus(rect, scale: scale);
    }
  }

  // ---------------------------------------------------------------------------
  // ProjectActions hooks
  // ---------------------------------------------------------------------------

  @override
  void onActiveTargetChanged(String? subId) => _showTarget(subId);

  /// A context under the [StudioBottomChrome] the layouts publish, captured
  /// as they build. The state's own context is above it, and a toast shown
  /// from there would not know the floating toolbar or the phone's tab bar
  /// is at the bottom of the window, and would cover it.
  BuildContext? _chromeContext;

  @override
  BuildContext get snackContext {
    final chrome = _chromeContext;
    return chrome != null && chrome.mounted ? chrome : context;
  }

  @override
  void willChangeTarget(SubProject sub) => _historyOf(sub.id).push(sub);

  // ---------------------------------------------------------------------------
  // Documents and history
  // ---------------------------------------------------------------------------

  /// Takes an undo checkpoint of the whole target as it stands.
  void _checkpoint() {
    final sub = _sub;
    if (sub == null) return;
    _historyOf(sub.id).push(sub);
    // A toast's Undo steps back one change — the latest. Once another has
    // been made it would revert that instead of the one it names ("Deleted
    // screen 1 · Undo" put back a screen moved since), so it goes.
    ScaffoldMessenger.maybeOf(snackContext)?.hideCurrentSnackBar();
  }

  void _setDoc(ScreenDoc d, {bool isDragging = false}) {
    if (!isDragging) _checkpoint();
    // In another language the edit was made to the translated view: its words
    // go to that language, everything else to the shared design.
    final language = _lang;
    final base = _baseDoc;
    final written = language == null || base == null || base.id != d.id
        ? d
        : delocalizeEdit(base: base, edited: d, language: language);
    _store.updateScreen(widget.projectId, written);
    setState(() {});
  }

  void _undo() => _travel(_undoStack.undo);

  void _redo() => _travel(_undoStack.redo);

  void _travel(SubProject? Function(SubProject current) step) {
    // A toast's Undo can outlive the editor by a few seconds.
    if (!mounted) return;
    final current = _sub;
    if (current == null) return;
    final target = step(current);
    if (target == null) return;
    _store.restoreSubProject(widget.projectId, target);
    setState(_dropStaleSelection);
  }

  /// Clears a selection that no longer points at anything — after an undo
  /// that removed the shape, say. A panel asked to edit shape 4 of 3 would
  /// throw.
  void _dropStaleSelection() {
    final d = doc;
    final selected = _selected;
    if (d == null || selected == null) return;
    final stale = switch (selected.handle) {
      SceneHandle.shape => selected.index >= d.shapes.length,
      SceneHandle.frame ||
      SceneHandle.screenshot => selected.index >= d.frames.length,
      SceneHandle.caption => d.caption == null,
      SceneHandle.subCaption => d.subCaption == null,
      SceneHandle.canvas => false,
    };
    if (stale) _selected = null;
  }

  // ---------------------------------------------------------------------------
  // Targets and screens
  // ---------------------------------------------------------------------------

  /// Shows another target, starting on its first screen.
  ///
  /// History is per target: the sets are separate deliverables at separate
  /// canvases, and an undo that reached back into the iPad set while you look
  /// at the iPhone one would edit it invisibly. Each keeps its own, so going
  /// to look at the other set and coming back loses nothing — clearing it on
  /// the way, as this once did, threw away every step made so far.
  void _showTarget(String? subId) {
    setState(() {
      _subId = subId;
      _screenId = null;
      _selected = null;
      _drawing = false;
    });
    _refocus(animate: false);
  }

  /// Makes [screenId] the active screen and brings it to the middle.
  void _activate(String screenId) {
    if (screenId == doc?.id) return;
    HapticFeedback.selectionClick();
    setState(() {
      _screenId = screenId;
      _selected = null;
      _drawing = false;
    });
    _refocus();
  }

  /// Centres the active screen on the canvas at fit zoom, once it is laid out.
  void _refocus({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final viewport = _viewport.currentState;
      final geometry = _geometry(viewport?.viewportSize);
      final sub = _sub;
      if (viewport == null || geometry == null || sub == null) return;
      final index = sub.screens.indexWhere((s) => s.id == doc?.id);
      final rect = geometry.focusRect(index < 0 ? 0 : index);
      viewport.focus(
        rect,
        // Whole, however wide: a feature graphic laid out at the strip's
        // height is wider than most windows, and "back to the screen" showed
        // its left two thirds.
        scale: math.min(1, (viewport.viewportSize.width - 48) / rect.width),
        animate: animate,
      );
    });
    // From a keyboard shortcut nothing else asks for a frame, and the
    // callback above waited for the mouse to move before it ran.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Zooms out until the whole set fits across the canvas.
  void _fitAll() {
    final viewport = _viewport.currentState;
    final geometry = _geometry(viewport?.viewportSize);
    if (viewport == null || geometry == null) return;
    final size = viewport.viewportSize;
    viewport.focus(
      Rect.fromLTWH(0, 0, geometry.contentWidth, size.height),
      scale: math.min(1, (size.width - 48) / geometry.contentWidth),
    );
  }

  _StripGeometry? _geometry(Size? viewport) {
    final sub = _sub;
    if (viewport == null || viewport.isEmpty || sub == null) return null;
    return _StripGeometry(
      viewport: viewport,
      canvases: [for (final s in sub.screens) s.canvas],
      compact: context.layout.isPhone,
      withAddTile: !_preview && _canAddScreens,
      continuous: sub.continuous,
      toolbar: !context.layout.docksToBottom && !_preview,
    );
  }

  /// Whether the active set takes more screens: not a feature graphic, which
  /// the store has exactly one slot for.
  bool get _canAddScreens =>
      _sub?.target.formFactor != TargetFormFactor.graphic;

  void _addScreen({int? after}) {
    final sub = _sub;
    if (sub == null || !_canAddScreens) return;
    _checkpoint();
    final added = _store.addScreen(widget.projectId, sub.id);
    // Added at the end, then walked back to sit after [after] — the store only
    // appends, and "add a screen here" is the one that means something on a
    // strip.
    if (after != null) {
      for (var i = sub.screens.length - 1; i > after; i--) {
        _store.moveScreenLeft(widget.projectId, added.id);
      }
    }
    setState(() {
      _screenId = added.id;
      _selected = null;
    });
    _refocus();
  }

  void _screenAction(_ScreenAction action, ScreenDoc screen) {
    final sub = _sub;
    if (sub == null) return;
    final index = sub.screens.indexWhere((s) => s.id == screen.id);
    if (index < 0) return;
    _checkpoint();
    switch (action) {
      case _ScreenAction.addAfter:
        _addScreen(after: index);
        return;
      case _ScreenAction.duplicate:
        _store.duplicateScreen(widget.projectId, screen.id);
        final copy = _sub?.screens.elementAtOrNull(index + 1);
        if (copy != null) {
          setState(() => _screenId = copy.id);
          _refocus();
        }
      case _ScreenAction.moveLeft:
        _store.moveScreenLeft(widget.projectId, screen.id);
        _refocus();
      case _ScreenAction.moveRight:
        _store.moveScreenRight(widget.projectId, screen.id);
        _refocus();
      case _ScreenAction.delete:
        if (sub.screens.length < 2) return;
        // Hand the canvas to a neighbour first, so it is never pointed at a
        // screen that no longer exists.
        if (screen.id == doc?.id) {
          _screenId = sub.screens[index == 0 ? 1 : index - 1].id;
          _selected = null;
        }
        _store.deleteScreen(widget.projectId, screen.id);
        showStudioSnack(
          snackContext,
          'Deleted screen ${index + 1}',
          actionLabel: 'Undo',
          onAction: _undo,
        );
        _refocus();
    }
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------------

  /// A tap on the canvas.
  ///
  /// Selecting a layer brings up its properties; tapping the artboard itself
  /// opens the Background library, because the background is what the
  /// artboard *is*.
  ///
  /// A tap on a row in the Layers list comes here too, so a row and the layer
  /// it names open the same tool.
  void _selectHandle(SceneSelection? selection) {
    setState(() {
      // A fresh pick gets the layer's own tool. The same layer tapped again —
      // grabbed to drag it while its size and position are showing — keeps
      // the tool that is up.
      if (selection != _selected) _shapeTools = false;
      _selected = selection;
      _propertiesDismissed = false;
      // On a phone the properties live in the bottom sheet, and a selection
      // that left it tucked away showed nothing but its name: the tools for
      // the thing just tapped were there, one gesture away that nobody knew.
      if (selection != null &&
          selection.handle != SceneHandle.canvas &&
          context.layout.docksToBottom) {
        _sheetExpanded = true;
      }
      switch (selection?.handle) {
        case null:
          break;
        case SceneHandle.canvas:
          _layers = false;
          _showLibrary(_Library.background);
        case SceneHandle.shape:
          _layers = false;
          _pane = _Pane.properties;
          _phoneLibrary = _Library.elements;
        case SceneHandle.frame:
          _layers = false;
          _pane = _Pane.properties;
          _phoneLibrary = _Library.devices;
        case SceneHandle.screenshot:
          _layers = false;
          _pane = _Pane.properties;
          _phoneLibrary = _Library.uploads;
        case SceneHandle.caption || SceneHandle.subCaption:
          _layers = false;
          _pane = _Pane.properties;
          _phoneLibrary = _Library.text;
      }
      _sheetHeightRequest = null;
    });
  }

  /// Selects a layer without moving the workspace off the panel it is on — a
  /// pick in the layer list or inside a panel, as opposed to on the canvas.
  void _selectLayer(SceneSelection? selection) {
    setState(() {
      _selected = selection;
      _propertiesDismissed = false;
    });
  }

  /// Which device the device-related panels act on: the selected one, or the
  /// first on the screen.
  int get _deviceIndex {
    final frames = doc?.frames ?? const [];
    if (frames.isEmpty) return 0;
    return (_selected?.deviceIndex ?? 0).clamp(0, frames.length - 1);
  }

  /// The properties the right-hand panel shows, or null for none.
  _EditorTab? get _propertiesTab {
    if (_layers) return _EditorTab.layers;
    if (_propertiesDismissed) return null;
    return switch (_selected?.handle) {
      SceneHandle.frame => _EditorTab.frame,
      SceneHandle.screenshot => _EditorTab.screenshot,
      SceneHandle.caption => _EditorTab.caption,
      SceneHandle.subCaption => _EditorTab.subcaption,
      SceneHandle.shape => switch (_selectedShape) {
        // A selection an undo has left pointing past the end of the list.
        null => _EditorTab.layers,
        _ when _shapeTools => _EditorTab.shape,
        final shape when shape.isText => _EditorTab.text,
        final shape when shape.hasImage => _EditorTab.image,
        _ => _EditorTab.shape,
      },
      SceneHandle.canvas || null => null,
    };
  }

  /// The selected shape, if the selection is one that exists.
  ShapeSpec? get _selectedShape {
    final selected = _selected;
    if (selected == null || !selected.isShape) return null;
    return doc?.shapes.elementAtOrNull(selected.index);
  }

  /// Deletes the selected layer — the Delete key's job. A screen's last
  /// device stays: every screen has one to hold its screenshot.
  void _deleteSelectedShape() {
    final current = doc;
    final selected = _selected;
    if (current == null || selected == null) return;
    final ScreenDoc? next = switch (selected.handle) {
      SceneHandle.shape when selected.index < current.shapes.length =>
        current.copyWith(shapes: [...current.shapes]..removeAt(selected.index)),
      SceneHandle.frame || SceneHandle.screenshot
          when current.frames.length > 1 &&
              selected.index < current.frames.length =>
        current.removeFrame(selected.index),
      SceneHandle.caption => current.copyWith(clearCaption: true),
      SceneHandle.subCaption => current.copyWith(clearSubCaption: true),
      _ => null,
    };
    if (next == null) return;
    _setDoc(next);
    setState(() => _selected = null);
  }

  // ---------------------------------------------------------------------------
  // Keyboard editing: nudge, copy, paste
  // ---------------------------------------------------------------------------

  /// Moves the selected layer by [pixels] of the canvas.
  void _nudge(Offset pixels) {
    final current = doc;
    final selected = _selected;
    if (current == null || selected == null || _typing) return;
    final step = Offset(
      pixels.dx / current.canvas.width,
      pixels.dy / current.canvas.height,
    );
    final i = selected.index;
    final ScreenDoc? next = switch (selected.handle) {
      // A locked layer stays where it is, however it came to be selected.
      SceneHandle.shape
          when i < current.shapes.length && !current.shapes[i].locked =>
        current.updateShape(i, (s) => s.copyWith(center: s.center + step)),
      SceneHandle.frame || SceneHandle.screenshot
          when i < current.frames.length =>
        current.updateFrame(
          i,
          (f) => f.copyWith(
            transform: f.transform.copyWith(
              offsetPct: f.transform.offsetPct + step,
            ),
          ),
        ),
      SceneHandle.caption when current.caption != null => current.copyWith(
        caption: current.caption!.copyWith(
          offsetPct: current.caption!.offsetPct + step,
        ),
      ),
      SceneHandle.subCaption when current.subCaption != null =>
        current.copyWith(
          subCaption: current.subCaption!.copyWith(
            offsetPct: current.subCaption!.offsetPct + step,
          ),
        ),
      _ => null,
    };
    // Through the ordinary path, whose undo coalesces a run of key presses
    // into one step.
    if (next != null) _setDoc(next);
  }

  /// The copied layer: a shape (text, image, element or icon) or a device.
  /// Kept across screens and targets, so a badge made on one screen can be
  /// pasted onto the next.
  Object? _copied;

  Object? get _selectedLayer {
    final current = doc;
    final selected = _selected;
    if (current == null || selected == null) return null;
    return switch (selected.handle) {
      SceneHandle.shape => current.shapes.elementAtOrNull(selected.index),
      SceneHandle.frame ||
      SceneHandle.screenshot => current.frames.elementAtOrNull(selected.index),
      _ => null,
    };
  }

  void _copy() {
    if (_typing) return;
    final layer = _selectedLayer;
    if (layer == null) return;
    _copied = layer;
    showStudioSnack(snackContext, 'Copied');
  }

  void _cut() {
    if (_typing) return;
    final layer = _selectedLayer;
    if (layer == null) return;
    _copied = layer;
    _deleteSelectedShape();
  }

  /// Puts [layer] on the active screen, a step down and to the right when it
  /// would otherwise land exactly on the one it was copied from.
  void _place(Object layer) {
    final current = doc;
    if (current == null) return;
    const step = Offset(0.03, 0.02);
    switch (layer) {
      case final ShapeSpec shape:
        final clash = current.shapes.any((s) => s.center == shape.center);
        _addShape(
          shape.copyWith(
            center: clash ? shape.center + step : shape.center,
            z: current.topZ + 1,
            locked: false,
          ),
        );
      case final FramePlacement frame:
        final clash = current.frames.any(
          (f) => f.transform.offsetPct == frame.transform.offsetPct,
        );
        _setDoc(
          current.addFrame(
            clash
                ? frame.copyWith(
                    transform: frame.transform.copyWith(
                      offsetPct: frame.transform.offsetPct + step,
                    ),
                  )
                : frame,
          ),
        );
        _selectLayer(SceneSelection.frameAt(current.frames.length));
    }
  }

  /// Pastes the copied layer — or, with none, a picture on the system
  /// clipboard, as an image layer.
  Future<void> _paste() async {
    if (_typing) return;
    final copied = _copied;
    if (copied != null) {
      _place(copied);
      return;
    }
    try {
      final bytes = await Pasteboard.image;
      if (bytes == null || !mounted) return;
      final image = await ref
          .read(imageLibraryProvider.notifier)
          .importBytes(
            bytes,
            projectId: widget.projectId,
            kind: LibraryImageKind.element,
          );
      if (mounted) await _addImageLayer(image);
    } catch (_) {
      // Nothing pasteable: the clipboard held text, or nothing at all.
    }
  }

  void _duplicate() {
    if (_typing) return;
    final layer = _selectedLayer;
    if (layer != null) _place(layer);
  }

  // ---------------------------------------------------------------------------
  // The layer context menu
  // ---------------------------------------------------------------------------

  /// A tap on a locked layer, which stays put: say so, and offer the way out.
  void _lockedTap(SceneSelection target) {
    final shape = doc?.shapes.elementAtOrNull(target.index);
    if (shape == null) return;
    HapticFeedback.selectionClick();
    if (_selected != null) setState(() => _selected = null);
    showStudioSnack(
      snackContext,
      '${shape.displayName} is locked',
      actionLabel: 'Unlock',
      onAction: () => _unlock(target),
    );
  }

  /// Unlocks [target] and selects it, ready to be moved.
  void _unlock(SceneSelection target) {
    final current = doc;
    if (current == null || target.index >= current.shapes.length) return;
    _setDoc(
      current.updateShape(target.index, (s) => s.copyWith(locked: false)),
    );
    setState(() => _selected = target);
  }

  /// A right-click or long press on a layer: select it, and offer what can be
  /// done to it.
  Future<void> _contextMenu(SceneSelection target, Offset at) async {
    final current = doc;
    if (current == null) return;
    final shape = target.isShape
        ? current.shapes.elementAtOrNull(target.index)
        : null;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    // A locked layer is not selected, and has one thing to offer.
    if (shape != null && shape.locked) {
      final choice = await showMenu<_LayerMenu>(
        context: context,
        clipBehavior: Clip.antiAlias,
        position: RelativeRect.fromRect(
          at & const Size(1, 1),
          Offset.zero & overlayBox.size,
        ),
        items: const [
          PopupMenuItem(
            value: _LayerMenu.unlock,
            child: MenuEntry(icon: StudioIcons.lockOpen, label: 'Unlock'),
          ),
        ],
      );
      if (choice == _LayerMenu.unlock && mounted) _unlock(target);
      return;
    }
    _selectHandle(target);
    final isDevice =
        target.handle == SceneHandle.frame ||
        target.handle == SceneHandle.screenshot;
    final choice = await showMenu<_LayerMenu>(
      context: context,
      clipBehavior: Clip.antiAlias,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlayBox.size,
      ),
      items: [
        if (shape != null || isDevice) ...[
          const PopupMenuItem(
            value: _LayerMenu.copy,
            child: MenuEntry(icon: StudioIcons.duplicate, label: 'Copy'),
          ),
          const PopupMenuItem(
            value: _LayerMenu.duplicate,
            child: MenuEntry(icon: StudioIcons.duplicate, label: 'Duplicate'),
          ),
        ],
        if (_copied != null)
          const PopupMenuItem(
            value: _LayerMenu.paste,
            child: MenuEntry(icon: StudioIcons.import, label: 'Paste'),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _LayerMenu.front,
          child: MenuEntry(
            icon: StudioIcons.bringForward,
            label: 'Bring to front',
          ),
        ),
        const PopupMenuItem(
          value: _LayerMenu.forward,
          child: MenuEntry(
            icon: StudioIcons.bringForward,
            label: 'Bring forward',
          ),
        ),
        const PopupMenuItem(
          value: _LayerMenu.backward,
          child: MenuEntry(
            icon: StudioIcons.sendBackward,
            label: 'Send backward',
          ),
        ),
        const PopupMenuItem(
          value: _LayerMenu.back,
          child: MenuEntry(
            icon: StudioIcons.sendBackward,
            label: 'Send to back',
          ),
        ),
        const PopupMenuDivider(),
        if (shape != null)
          const PopupMenuItem(
            value: _LayerMenu.lock,
            child: MenuEntry(icon: StudioIcons.lock, label: 'Lock'),
          ),
        if (shape != null || isDevice)
          const PopupMenuItem(
            value: _LayerMenu.hide,
            child: MenuEntry(icon: StudioIcons.layerHidden, label: 'Hide'),
          ),
        const PopupMenuItem(
          value: _LayerMenu.delete,
          child: MenuEntry(
            icon: StudioIcons.delete,
            label: 'Delete',
            danger: true,
          ),
        ),
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _LayerMenu.copy:
        _copy();
      case _LayerMenu.duplicate:
        _duplicate();
      case _LayerMenu.paste:
        await _paste();
      case _LayerMenu.front:
        _restack(target, toFront: true);
      case _LayerMenu.forward:
        _restack(target, by: -1);
      case _LayerMenu.backward:
        _restack(target, by: 1);
      case _LayerMenu.back:
        _restack(target, toBack: true);
      case _LayerMenu.lock:
        _setDoc(
          current.updateShape(target.index, (s) => s.copyWith(locked: true)),
        );
        setState(() => _selected = null);
        showStudioSnack(
          snackContext,
          'Locked. Unlock it from the layers list.',
          actionLabel: 'Undo',
          onAction: _undo,
        );
      case _LayerMenu.unlock:
        _unlock(target);
      case _LayerMenu.hide:
        _setDoc(
          isDevice
              ? current.updateFrame(
                  target.index,
                  (f) => f.copyWith(hidden: true),
                )
              : current.updateShape(
                  target.index,
                  (s) => s.copyWith(hidden: true),
                ),
        );
        setState(() => _selected = null);
        showStudioSnack(
          snackContext,
          'Hidden. Show it again from the layers list.',
          actionLabel: 'Undo',
          onAction: _undo,
        );
      case _LayerMenu.delete:
        _deleteSelectedShape();
    }
  }

  /// Moves [target] in the stack: to the front or the back, or [by] one
  /// place (negative is forward). The layers list's own reordering, reused.
  void _restack(
    SceneSelection target, {
    bool toFront = false,
    bool toBack = false,
    int by = 0,
  }) {
    final current = doc;
    if (current == null) return;
    final stack = LayerStack.of(current);
    final row = switch (target.handle) {
      SceneHandle.shape => stack.rowOfShape(target.index),
      SceneHandle.frame ||
      SceneHandle.screenshot => stack.rowOfFrame(target.index),
      SceneHandle.caption || SceneHandle.subCaption => stack.rowOfCaptions,
      SceneHandle.canvas => null,
    };
    if (row == null) return;
    final to = toFront
        ? 0
        : toBack
        ? stack.rows.length - 1
        : stack.nudgeTarget(row, by);
    if (to == null) return;
    final next = stack.reorder(row, to);
    if (next != null) _setDoc(next);
  }

  void _showLibrary(_Library library) {
    _library = library;
    _phoneLibrary = library;
    _pane = _Pane.library;
  }

  /// A tap on the rail or the phone's tab bar.
  ///
  /// Re-picking the open library closes it, which is the one interaction the
  /// side panel and the phone sheet share.
  void _onLibrary(_Library library, {required bool phone}) {
    HapticFeedback.selectionClick();
    setState(() {
      _sheetHeightRequest = null;
      if (phone) {
        final showingIt = _phoneLibrary == library && _pane == _Pane.library;
        if (showingIt) {
          _sheetExpanded = !_sheetExpanded;
        } else {
          _sheetExpanded = true;
        }
        _showLibrary(library);
      } else if (_library == library && _pane == _Pane.library) {
        _library = null;
      } else {
        _showLibrary(library);
      }
      if (library == _Library.background) _selected = SceneSelection.canvas;
      if (library != _Library.elements) _drawing = false;
    });
  }

  void _toggleLayers() {
    HapticFeedback.selectionClick();
    setState(() {
      _layers = !(_layers && _pane == _Pane.properties);
      _shapeTools = false;
      _pane = _Pane.properties;
      _propertiesDismissed = false;
    });
  }

  /// The Layers tab on the phone's tab bar. Like a library tab, a second tap
  /// tucks the sheet away rather than closing what it shows.
  void _onPhoneLayers() {
    HapticFeedback.selectionClick();
    setState(() {
      _sheetHeightRequest = null;
      final showingIt = _layers && _pane == _Pane.properties;
      _sheetExpanded = showingIt ? !_sheetExpanded : true;
      _layers = true;
      _shapeTools = false;
      _pane = _Pane.properties;
      _propertiesDismissed = false;
    });
  }

  void _closeProperties() {
    setState(() {
      _layers = false;
      _shapeTools = false;
      _propertiesDismissed = true;
      _pane = _Pane.library;
    });
  }

  // ---------------------------------------------------------------------------
  // Direct manipulation
  // ---------------------------------------------------------------------------

  void _transformStartHandle(SceneSelection target) {
    _checkpoint();
    _transformBaseDoc = doc;
    _dragRaw = null;
  }

  // ---------------------------------------------------------------------------
  // Snapping
  // ---------------------------------------------------------------------------

  /// Where the dragged layer would be with no snapping, as the gesture has
  /// moved it so far.
  ///
  /// Kept apart from where it is drawn so that a snap never sticks: the drag
  /// goes on accumulating from the unsnapped position, and the layer lets go
  /// of a line as soon as the pointer is past it.
  Offset? _dragRaw;

  /// The alignment lines currently shown on the active screen.
  List<SnapGuide> _guides = const [];

  /// The active screen's width on screen at zoom 1, for turning a snap
  /// distance in screen points into a fraction of the canvas.
  double _screenPx = 0;

  /// How close, in screen points, a layer has to come to a line to snap.
  static const double _snapDistance = 7;

  /// [target]'s position in [d]: a shape's centre, or a device's or caption's
  /// offset — the value a drag changes.
  static Offset? _positionOf(SceneSelection target, ScreenDoc d) =>
      switch (target.handle) {
        SceneHandle.shape => d.shapes.elementAtOrNull(target.index)?.center,
        SceneHandle.frame || SceneHandle.screenshot =>
          d.frames.elementAtOrNull(target.index)?.transform.offsetPct,
        SceneHandle.caption => d.caption?.offsetPct,
        SceneHandle.subCaption => d.subCaption?.offsetPct,
        SceneHandle.canvas => null,
      };

  /// [raw] pulled onto the nearest alignment within reach, and the lines that
  /// pulled it.
  ///
  /// Shapes line up with the canvas's centre and edges and with every other
  /// shape's centre; devices and captions with the canvas's centre. Holding
  /// Alt drags freely, the convention every design tool shares.
  (Offset, List<SnapGuide>) _snap(
    SceneSelection target,
    Offset raw,
    ScreenDoc d,
  ) {
    final px = _screenPx * _zoom.value;
    if (px <= 0 || HardwareKeyboard.instance.isAltPressed) return (raw, []);
    final canvas = d.canvas;
    final reachX = _snapDistance / px;
    final reachY = _snapDistance / (px * canvas.height / canvas.width);

    // (value to snap to, where its guide is drawn)
    final xs = <(double, double)>[(0, 0.5)];
    final ys = <(double, double)>[];

    switch (target.handle) {
      case SceneHandle.shape:
        final shape = d.shapes.elementAtOrNull(target.index);
        if (shape == null) return (raw, []);
        final halfW = shape.width / 2;
        final halfH = shape.height * canvas.width / canvas.height / 2;
        xs
          ..add((-0.5 + halfW, 0))
          ..add((0.5 - halfW, 1));
        ys
          ..add((0, 0.5))
          ..add((-0.5 + halfH, 0))
          ..add((0.5 - halfH, 1));
        for (final (i, other) in d.shapes.indexed) {
          if (i == target.index || other.hidden) continue;
          xs.add((other.center.dx, 0.5 + other.center.dx));
          ys.add((other.center.dy, 0.5 + other.center.dy));
        }
      case SceneHandle.frame || SceneHandle.screenshot:
        final frame = d.frames.elementAtOrNull(target.index);
        // Offsets are measured from the device's alignment spot; only a
        // centred device has the canvas centre at zero.
        if (frame == null || frame.transform.align.x != 0) return (raw, []);
        if (frame.transform.align.y == 0) ys.add((0, 0.5));
      case SceneHandle.caption || SceneHandle.subCaption:
        break;
      case SceneHandle.canvas:
        return (raw, []);
    }

    (double, double?) nearest(
      double value,
      List<(double, double)> lines,
      double reach,
    ) {
      (double, double?) best = (value, null);
      var bestGap = reach;
      for (final (at, guide) in lines) {
        final gap = (value - at).abs();
        if (gap <= bestGap) {
          bestGap = gap;
          best = (at, guide);
        }
      }
      return best;
    }

    final (x, gx) = nearest(raw.dx, xs, reachX);
    final (y, gy) = nearest(raw.dy, ys, reachY);
    return (
      Offset(x, y),
      [
        if (gx != null) SnapGuide.vertical(gx),
        if (gy != null) SnapGuide.horizontal(gy),
      ],
    );
  }

  void _transformHandle(SceneSelection target, ScaleUpdateDetails d) {
    final current = doc;
    if (current == null) return;

    final base = _transformBaseDoc ?? current;

    // focalPointDelta is the delta since the LAST frame, so it applies to the
    // current doc; scale and rotation are deltas since the START of the
    // gesture, so they apply to the doc captured when it began.
    //
    // Divided by the document's own canvas, and by nothing else. The scene is
    // laid out at canvas resolution and scaled to fit (see [SceneView]), so a
    // gesture arriving at a layer inside it has already had that scale — and
    // the canvas zoom above it — undone: the delta is in canvas pixels.
    final canvas = current.canvas;
    final dx = d.focalPointDelta.dx / canvas.width;
    final dy = d.focalPointDelta.dy / canvas.height;

    // The unsnapped position, moved by this frame's delta, then snapped. See
    // [_dragRaw].
    final from = _dragRaw ?? _positionOf(target, current) ?? Offset.zero;
    final raw = from + Offset(dx, dy);
    _dragRaw = raw;
    final (snapped, guides) = _snap(target, raw, current);
    if (!listEquals(guides, _guides)) _guides = guides;

    switch (target.handle) {
      case SceneHandle.canvas:
        return;
      // Selecting the picture inside a device and then dragging moves the
      // device: the screenshot has no position of its own on the canvas.
      case SceneHandle.screenshot:
      case SceneHandle.frame:
        final at = target.index.clamp(0, current.frames.length - 1);
        if (at >= base.frames.length) return;
        final baseFrame = base.frames[at];
        _setDoc(
          current.updateFrame(
            at,
            (f) => f.copyWith(
              transform: f.transform.copyWith(
                offsetPct: snapped,
                scale: (baseFrame.transform.scale * d.scale).clamp(0.4, 2.5),
                rotationDeg:
                    baseFrame.transform.rotationDeg +
                    (d.rotation * 180 / math.pi),
              ),
            ),
          ),
          isDragging: true,
        );
      case SceneHandle.caption:
        final currentCaption = current.caption;
        final baseCaption = base.caption;
        if (currentCaption != null && baseCaption != null) {
          _setDoc(
            current.copyWith(
              caption: currentCaption.copyWith(
                offsetPct: snapped,
                size: (baseCaption.size * d.scale).clamp(10.0, 200.0),
                // The leading with it, or the lines of a grown headline run
                // into each other.
                lineHeight:
                    baseCaption.lineHeight *
                    (baseCaption.size * d.scale).clamp(10.0, 200.0) /
                    baseCaption.size,
                // A pinch is somebody choosing a size, which a template's fit
                // box would otherwise quietly take back as soon as the words
                // outgrew it. A drag alone (no scale) is only a move.
                clearFitHeightPct: d.scale != 1,
              ),
            ),
            isDragging: true,
          );
        }
      case SceneHandle.subCaption:
        final currentSubCaption = current.subCaption;
        final baseSubCaption = base.subCaption;
        if (currentSubCaption != null && baseSubCaption != null) {
          _setDoc(
            current.copyWith(
              subCaption: currentSubCaption.copyWith(
                offsetPct: snapped,
                size: (baseSubCaption.size * d.scale).clamp(10.0, 200.0),
                lineHeight:
                    baseSubCaption.lineHeight *
                    (baseSubCaption.size * d.scale).clamp(10.0, 200.0) /
                    baseSubCaption.size,
              ),
            ),
            isDragging: true,
          );
        }
      case SceneHandle.shape:
        final index = target.index;
        if (index < 0 || index >= current.shapes.length) return;
        if (index >= base.shapes.length) return;
        final baseShape = base.shapes[index];
        // Both axes take the same factor, so a pinch resizes the shape rather
        // than reproportioning it.
        final scale = d.scale.clamp(0.05, 20.0);
        _setDoc(
          current.updateShape(
            index,
            (s) => s.copyWith(
              center: snapped,
              width: (baseShape.width * scale).clamp(0.01, 4.0),
              height: (baseShape.height * scale).clamp(0.01, 4.0),
              rotationDeg: baseShape.rotationDeg + (d.rotation * 180 / math.pi),
            ),
          ),
          isDragging: true,
        );
    }
  }

  void _transformEndHandle(SceneSelection target) {
    _transformBaseDoc = null;
    _dragRaw = null;
    if (_guides.isNotEmpty) setState(() => _guides = const []);
  }

  // ---------------------------------------------------------------------------
  // Adding things
  // ---------------------------------------------------------------------------

  /// A colour that reads on the current screen, for a layer that arrives
  /// without one of its own.
  ///
  /// Every new shape and text layer used to be white, which vanished on the
  /// light backgrounds most listings use. The headline's colour is the
  /// design's own ink, so a new layer matches it; a screen with no headline
  /// gets near-black or white, whichever its background needs.
  Color _inkFor(ScreenDoc screen) {
    final caption = screen.caption;
    if (caption != null && caption.plainText.trim().isNotEmpty) {
      return caption.color;
    }
    final backdrop = captionBackdropOf(screen.background);
    // Content colours, never theme tokens: the layer is exported artwork.
    return backdrop.computeLuminance() > 0.5
        ? const Color(0xFF11142A)
        : const Color(0xFFFFFFFF);
  }

  /// Adds [spec] to the top of the stack and selects it.
  void _addShape(ShapeSpec spec) {
    final current = doc;
    if (current == null) return;
    final shapes = [...current.shapes, spec];
    _setDoc(current.copyWith(shapes: shapes));
    _selectHandle(SceneSelection.shape(shapes.length - 1));
  }

  /// A pick from the Elements library.
  Future<void> _pickShape(ShapeKind kind) async {
    // Inherits the selected shape's fill, so building a set in one colour is
    // not a trip to the picker per shape.
    final selected = _selected;
    final shapes = doc?.shapes ?? const <ShapeSpec>[];
    final current = doc;
    final fill =
        (selected != null && selected.isShape
            ? shapes.elementAtOrNull(selected.index)?.fill
            : null) ??
        (current == null ? null : _inkFor(current));

    switch (kind) {
      case ShapeKind.custom:
        if (!_drawing) _toggleDrawing();
      case ShapeKind.path:
        final shape = await pickSvgShape(
          context,
          fill: fill ?? kShapeSwatches.first,
          projectId: widget.projectId,
        );
        if (shape != null && mounted) _addShape(shape);
      default:
        _addShape(ShapeSpec.of(kind, fill: fill ?? kShapeSwatches.first));
    }
  }

  /// Turns a traced path into a shape and drops it on the canvas.
  ///
  /// [points] arrive as fractions of the canvas; a shape stores its outline
  /// inside its own box, so the path's bounds become the box and the points are
  /// re-expressed against it. That is what makes a drawn shape movable and
  /// resizable afterwards by exactly the same controls as every other one.
  ///
  /// A stroke that ends near where it began is closed and filled; anything else
  /// stays an open, stroked path.
  void _addDrawnShape(List<Offset> points) {
    final canvas = doc?.canvas;
    if (points.length < 3 || canvas == null) return;

    var minX = points.first.dx, maxX = points.first.dx;
    var minY = points.first.dy, maxY = points.first.dy;
    for (final p in points) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }

    // A perfectly straight stroke has zero extent on one axis, which would be a
    // box nothing can be drawn in and a handle nothing can grab.
    const minExtent = 0.02;
    final width = math.max(maxX - minX, minExtent);
    final height = math.max(maxY - minY, minExtent);

    final normalised = [
      for (final p in points)
        Offset((p.dx - minX) / width, (p.dy - minY) / height),
    ];

    // A shape's box is two fractions of the canvas *width*, so the vertical
    // extent is converted rather than copied.
    final heightFraction = canvas.width <= 0
        ? height
        : height * canvas.height / canvas.width;

    final closed = (normalised.last - normalised.first).distance < 0.18;
    final ink = doc == null ? const Color(0xFFFFFFFF) : _inkFor(doc!);

    setState(() => _drawing = false);
    _addShape(
      ShapeSpec(
        kind: ShapeKind.custom,
        center: Offset(minX + width / 2 - 0.5, minY + height / 2 - 0.5),
        width: width,
        height: heightFraction,
        points: normalised,
        closed: closed,
        // Content colours, never theme tokens: the shape is part of the
        // exported artwork, and an export made in dark mode has to match one
        // made in light mode byte for byte.
        fill: ink,
        strokeColor: ink,
        strokeWidth: closed ? 0 : 0.006,
        z: kStackOverEverything,
      ),
    );
  }

  void _toggleDrawing() {
    setState(() {
      _drawing = !_drawing;
      // Nothing on the canvas is being edited while the pen is out, and leaving
      // a marquee up would suggest the next drag moves that layer.
      if (_drawing) _selected = null;
    });
  }

  /// A pick from the Devices library: the selected device becomes it.
  void _pickDevice(DeviceSelection pick, FrameCatalog catalog) {
    final current = doc;
    if (current == null || current.frames.isEmpty) return;
    final at = _deviceIndex;
    _setDoc(
      current.updateFrame(
        at,
        (f) => placementWithDevice(catalog, f, catalog.byId(pick.$1), pick.$2),
      ),
    );
    setState(() => _selected = SceneSelection.frameAt(at));
  }

  /// Puts the active screen's device on every screen of the set.
  void _deviceToAll(FrameCatalog catalog) {
    final current = _baseDoc;
    final sub = _sub;
    if (current == null || sub == null || current.frames.isEmpty) return;
    final at = _deviceIndex;
    final source = current.frames[at];
    final model = catalog.byId(source.deviceId);
    _checkpoint();
    for (final screen in sub.screens) {
      if (screen.id == current.id || at >= screen.frames.length) continue;
      _store.updateScreen(
        widget.projectId,
        screen.updateFrame(
          at,
          (f) => placementWithDevice(catalog, f, model, source.variantId),
        ),
      );
    }
    setState(() {});
    showStudioSnack(
      snackContext,
      '${model.model} on every screen',
      actionLabel: 'Undo',
      onAction: _undo,
    );
  }

  /// Turns the continuous canvas on or off for the set on show.
  ///
  /// On, the screen being edited lends its background to the whole set, since
  /// one background now runs across all of them; off, every screen keeps a
  /// whole copy of it. Undoable like any other change to the set.
  void _toggleContinuous() {
    final sub = _sub;
    if (sub == null) return;
    HapticFeedback.selectionClick();
    _checkpoint();
    final on = !sub.continuous;
    _store.setContinuous(
      widget.projectId,
      sub.id,
      on: on,
      backgroundFrom: doc?.id,
    );
    setState(() {});
    _refocus();
    showStudioSnack(
      snackContext,
      on
          ? 'Continuous canvas: layers and the background run across '
                '${sub.screens.length} screens'
          : 'Screens are separate pictures again',
      actionLabel: 'Undo',
      onAction: _undo,
    );
  }

  /// Applies [background] to the active screen — or, in a continuous set, to
  /// every screen, because they all show the one background.
  void _setBackground(Background background) {
    final current = doc;
    final sub = _sub;
    if (current == null || sub == null) return;
    if (!sub.continuous) {
      _setDoc(current.copyWith(background: background));
      return;
    }
    _checkpoint();
    for (final screen in sub.screens) {
      _store.updateScreen(
        widget.projectId,
        screen.copyWith(background: background),
      );
    }
    setState(() {});
  }

  /// Gives every screen of the set the active screen's background — its fill
  /// and the backdrop layers painted behind the device.
  void _backgroundToAll() {
    final current = _baseDoc;
    final sub = _sub;
    if (current == null || sub == null) return;
    final backdrop = [
      for (final s in current.shapes)
        if (s.z <= kStackBehindFrames) s,
    ];
    // A panorama — a pattern or a picture — goes out as one artwork across the
    // set, each screen its own slice of it, this one included. Copied as it
    // was, every screen showed the same slice, or the whole picture squeezed
    // into one screen. Anything else is copied as it is (see [panoramaAt]).
    final background = current.background;
    final panorama = isPanorama(background);
    final count = sub.screens.length;
    _checkpoint();
    for (final (i, screen) in sub.screens.indexed) {
      final slice = panoramaAt(background, index: i, count: count);
      if (screen.id == current.id) {
        if (panorama) {
          _store.updateScreen(
            widget.projectId,
            screen.copyWith(background: slice),
          );
        }
        continue;
      }
      _store.updateScreen(
        widget.projectId,
        screen.copyWith(
          background: slice,
          shapes: [
            ...backdrop,
            for (final s in screen.shapes)
              if (s.z > kStackBehindFrames) s,
          ],
        ),
      );
    }
    setState(() {});
    showStudioSnack(
      snackContext,
      panorama
          ? 'Panorama spread across all $count screens'
          : 'Background applied to all $count screens',
      actionLabel: 'Undo',
      onAction: _undo,
    );
  }

  /// Spreads [background] across the set on show — each screen on its own
  /// slice of a panorama, anything else as it is — as one undoable change.
  void _spreadBackground(Background background) {
    final sub = _sub;
    if (sub == null) return;
    _checkpoint();
    _store.spreadBackground(widget.projectId, sub.id, background);
    setState(() {});
    final count = sub.screens.length;
    showStudioSnack(
      snackContext,
      isPanorama(background)
          ? 'Panorama spread across all $count screens'
          : 'Background applied to all $count screens',
      actionLabel: 'Undo',
      onAction: _undo,
    );
  }

  /// What the AI tools need to dress the active screen, or null with no
  /// screen to dress.
  AiBackgroundHost? _aiHost(SubProject sub) {
    final project = _project;
    final base = _baseDoc;
    final shown = doc;
    if (project == null || base == null || shown == null) return null;
    final background = _shownBackground ?? base.background;
    return AiBackgroundHost(
      projectId: widget.projectId,
      projectName: project.name,
      screenId: base.id,
      screenCount: sub.screens.length,
      canvas: base.canvas,
      continuous: sub.continuous,
      current: background,
      palette: paletteOf(shown.copyWith(background: background)),
      onApply: _setBackground,
      onSpread: _spreadBackground,
    );
  }

  /// A tap on a caption or a layer with words that was already selected: its
  /// words, in the editor for them.
  ///
  /// The words were three steps from the canvas — the panel, then its Content
  /// box, then the editor — and double-clicking the headline did nothing.
  Future<void> _editTextOf(SceneSelection target) async {
    final current = doc;
    if (current == null) return;
    switch (target.handle) {
      case SceneHandle.caption || SceneHandle.subCaption:
        final isSub = target.handle == SceneHandle.subCaption;
        CaptionSpec? now() => isSub ? doc?.subCaption : doc?.caption;
        void write(CaptionSpec next) {
          final d = doc;
          if (d == null) return;
          _setDoc(
            isSub ? d.copyWith(subCaption: next) : d.copyWith(caption: next),
          );
        }

        final spec = now();
        if (spec == null) return;
        final title = isSub ? 'Subtitle text' : 'Headline text';
        if (spec.isRich) {
          await showRichCaptionEditor(
            context,
            title: title,
            spec: spec,
            backdrop: captionBackdropOf(current.background),
            onChanged: (runs) {
              if (now() case final caption?) write(caption.withRuns(runs));
            },
          );
        } else {
          final controller = TextEditingController(text: spec.text);
          await showStudioTextEditor(
            context,
            title: title,
            controller: controller,
            hint: isSub ? 'Type your subtitle…' : 'Type your headline…',
            onChanged: (v) {
              if (now() case final caption?) write(caption.copyWith(text: v));
            },
          );
          controller.dispose();
        }
      case SceneHandle.shape:
        final label = current.shapes.elementAtOrNull(target.index)?.label;
        if (label == null) return;
        final controller = TextEditingController(text: label.text);
        await showStudioTextEditor(
          context,
          title: 'Text',
          controller: controller,
          onChanged: (v) {
            final d = doc;
            if (d == null || target.index >= d.shapes.length) return;
            _setDoc(
              d.updateShape(target.index, (s) {
                final next = s.copyWith(label: s.label?.copyWith(text: v));
                // A text layer's box follows its words; a badge keeps its size.
                return next.isText
                    ? next.copyWith(height: fittedTextHeight(next, d.canvas))
                    : next;
              }),
            );
          },
        );
        controller.dispose();
      case SceneHandle.canvas || SceneHandle.frame || SceneHandle.screenshot:
        return;
    }
  }

  /// A tap on an empty device: pick the picture that goes in it.
  ///
  /// The recent-screenshots sheet rather than the gallery straight away, so a
  /// capture already imported for another screen is one tap away; importing a
  /// single new one from the sheet drops it straight in.
  Future<void> _chooseScreenshot(int deviceIndex) async {
    final image = await showImageLibrarySheet(
      context,
      kind: LibraryImageKind.screenshot,
      projectId: widget.projectId,
      title: 'Choose a screenshot',
    );
    if (image == null || !mounted) return;
    final current = doc;
    if (current == null || deviceIndex >= current.frames.length) return;
    _setDoc(
      current.updateFrame(
        deviceIndex,
        (f) => f.copyWith(
          screenshot: f.screenshot.copyWith(imagePath: image.path),
        ),
      ),
    );
    setState(() => _selected = SceneSelection.screenshotAt(deviceIndex));
  }

  /// A pick from the Uploads library: the image goes into the selected device.
  void _pickUpload(LibraryImage image) {
    final current = doc;
    if (current == null || current.frames.isEmpty) return;
    final at = _deviceIndex;
    _setDoc(
      current.updateFrame(
        at,
        (f) => f.copyWith(
          screenshot: f.screenshot.copyWith(imagePath: image.path),
        ),
      ),
    );
    setState(() => _selected = SceneSelection.screenshotAt(at));
  }

  /// Several picks at once from Uploads: one per screen, in order.
  void _pickUploads(List<LibraryImage> images) {
    final sub = _sub;
    if (sub == null || images.isEmpty) return;
    _checkpoint();
    final touched = _store.importScreenshots(widget.projectId, sub.id, [
      for (final image in images) image.path,
    ]);
    if (touched.isEmpty) return;
    setState(() {
      _screenId = touched.first.id;
      _selected = null;
    });
    _refocus();
    final n = touched.length;
    showStudioSnack(
      snackContext,
      'Placed $n screenshot${n == 1 ? '' : 's'}, one per screen',
      actionLabel: 'Undo',
      onAction: _undo,
    );
  }

  /// Adds a free text layer, its box fitted to its words.
  void _addTextLayer(ShapeSpec preset) {
    final current = doc;
    if (current == null) return;
    final label = preset.label;
    _addShape(
      preset.copyWith(
        height: fittedTextHeight(preset, current.canvas),
        label: label?.copyWith(color: _inkFor(current)),
      ),
    );
  }

  /// Adds [image] as a layer of its own, at the picture's own proportions.
  ///
  /// The size is read from the decoded picture rather than guessed: a wide
  /// logo dropped in a square box would arrive squashed or cropped.
  Future<void> _addImageLayer(LibraryImage image) async {
    final provider = StoredImage.provider(image.path);
    var aspect = 1.0;
    if (provider != null) {
      aspect = await _aspectOf(provider) ?? 1.0;
    }
    if (!mounted) return;
    _addShape(ShapeSpec.image(image.path, aspect: aspect));
  }

  static Future<double?> _aspectOf(ImageProvider provider) {
    final done = Completer<double?>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        final w = info.image.width, h = info.image.height;
        if (!done.isCompleted) done.complete(h == 0 ? null : w / h);
        stream.removeListener(listener);
      },
      onError: (_, _) {
        if (!done.isCompleted) done.complete(null);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return done.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
  }

  /// A pick from the Text library: the headline or subtitle, added if the
  /// screen has none, then selected.
  void _pickText({required bool sub}) {
    final current = doc;
    if (current == null) return;
    if (sub && current.subCaption == null) {
      _setDoc(
        current.copyWith(
          subCaption: const CaptionSpec(
            text: 'Supporting detail goes here',
            size: 34,
            lineHeight: 42,
            bold: false,
          ),
        ),
      );
    } else if (!sub && current.caption == null) {
      _setDoc(
        current.copyWith(
          caption: const CaptionSpec(text: 'Your headline goes here.'),
        ),
      );
    }
    _selectHandle(sub ? SceneSelection.subCaption : SceneSelection.caption);
  }

  // ---------------------------------------------------------------------------
  // Output
  // ---------------------------------------------------------------------------

  /// Renders the active screen at full canvas resolution and lets the user say
  /// where it goes: gallery, Downloads, or another app.
  /// The screen on show as a short loop of its devices moving.
  ///
  /// The same shape as [_saveImage]: choose, choose where, render, deliver —
  /// with the motion chosen first, on a live preview, because what the clip
  /// does is the decision and where it goes is the formality.
  Future<void> _saveVideo() async {
    final current = doc;
    final project = _project;
    final sub = _sub;
    final catalog = ref.read(frameCatalogProvider).valueOrNull;
    if (current == null ||
        project == null ||
        sub == null ||
        catalog == null ||
        _busy) {
      return;
    }

    final index = sub.screens.indexWhere((s) => s.id == current.id);
    // A panel of a continuous set films with its neighbours' reach, exactly
    // as it exports.
    final composed = sub.continuous && index >= 0
        ? composeScreen(_shown(sub), index, continuous: true)
        : ComposedScreen.alone(current);
    final sink = await resolveVideoSink();
    // The last settings used, remembered between launches, so a second clip
    // starts where the first was made.
    final remembered = await ref.read(videoSettingsProvider.notifier).settled();
    if (!mounted) return;
    final gif = sink is GifVideoSink;

    final settings = await showVideoExportSheet(
      context,
      composed: composed,
      catalog: catalog,
      gif: gif,
      audio: sink.supportsAudio,
      target: sub.target,
      initial: gif
          ? remembered.copyWith(
              seconds: remembered.seconds > 6 ? 6 : remembered.seconds,
            )
          : remembered,
    );
    if (settings == null || !mounted) return;
    // A GIF's settings are this machine's fallback, not a choice worth
    // keeping over the MP4 ones.
    if (!gif) unawaited(ref.read(videoSettingsProvider.notifier).set(settings));

    final safeName = DeviceStorage.sanitizeFileName(project.name);
    final fileName =
        '$safeName ${'${index + 1}'.padLeft(2, '0')}.${sink.extension}';
    final choice = await askSaveDestination(
      context,
      title: gif ? 'Save GIF' : 'Save video',
      notice: templateSampleNotice([current]),
      fileName: fileName,
      video: !gif,
    );
    if (choice == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final bytes = await SceneRenderer.renderVideo(
        context,
        composed: composed,
        catalog: catalog,
        settings: settings,
        sink: sink,
      );
      if (bytes == null || !mounted) return;
      await deliver(
        snackContext,
        choice: choice,
        bytes: bytes,
        fileName: fileName,
        mimeType: sink.mimeType,
        subFolder: safeName,
        shareSubject: project.name,
        sharePositionOrigin: shareOriginOf(context),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveImage() async {
    final current = doc;
    final project = _project;
    final sub = _sub;
    final catalog = ref.read(frameCatalogProvider).valueOrNull;
    if (current == null ||
        project == null ||
        sub == null ||
        catalog == null ||
        _busy) {
      return;
    }

    final index = sub.screens.indexWhere((s) => s.id == current.id);
    final settings = ref.read(exportSettingsProvider);
    final safeName = DeviceStorage.sanitizeFileName(project.name);
    final fileName =
        '$safeName ${'${index + 1}'.padLeft(2, '0')}.'
        '${settings.format.extension}';

    final choice = await askSaveDestination(
      context,
      title: 'Save screenshot',
      notice: templateSampleNotice([current]),
      fileName: fileName,
    );
    if (choice == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final bytes = await SceneRenderer.renderOne(
        context,
        doc: current,
        catalog: catalog,
        title: 'Rendering screenshot',
        settings: settings,
        // A panel of a continuous set exports with its neighbours' reach.
        set: sub.continuous ? _shown(sub) : null,
        index: sub.continuous ? index : null,
      );
      if (bytes == null || !mounted) return;

      await deliver(
        snackContext,
        choice: choice,
        bytes: bytes,
        fileName: fileName,
        mimeType: settings.format.mimeType,
        subFolder: safeName,
        shareSubject: project.name,
        sharePositionOrigin: shareOriginOf(context),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Puts the active screen on the clipboard, at 1× as a PNG, for pasting
  /// straight into a design review, a chat or a console upload field.
  Future<void> _copyImage() async {
    final current = doc;
    final sub = _sub;
    final catalog = ref.read(frameCatalogProvider).valueOrNull;
    if (current == null || sub == null || catalog == null || _busy) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      showStudioSnack(
        snackContext,
        'This platform cannot put images on the clipboard. Use Download.',
      );
      return;
    }
    final index = sub.screens.indexWhere((s) => s.id == current.id);
    setState(() => _busy = true);
    try {
      final bytes = await SceneRenderer.renderOne(
        context,
        doc: current,
        catalog: catalog,
        title: 'Copying screenshot',
        set: sub.continuous ? _shown(sub) : null,
        index: sub.continuous ? index : null,
      );
      if (bytes == null || !mounted) return;
      await Pasteboard.writeImage(bytes);
      // A copy has no save sheet to carry the template-sample notice, so the
      // toast carries it: a paste lands straight in a console upload field.
      final sample = templateSampleCount([current]) > 0;
      if (mounted) {
        showStudioSnack(
          snackContext,
          sample
              ? "Screen ${index + 1} copied. It still shows the template's "
                    'sample app'
              : 'Screen ${index + 1} copied',
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorSnack(snackContext, 'Could not copy that screen.', e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportOptions() async {
    final next = await _showExportOptions(
      context,
      ref.read(exportSettingsProvider),
    );
    if (next != null) {
      await ref.read(exportSettingsProvider.notifier).set(next);
    }
  }

  void _download(_Download what) {
    final project = _project;
    final sub = _sub;
    if (project == null || sub == null) return;
    switch (what) {
      case _Download.screen:
        _saveImage();
      case _Download.video:
        _saveVideo();
      case _Download.target:
        exportTarget(project, sub, language: _lang);
      case _Download.targetZip:
        exportTargetZip(project, sub, language: _lang);
      case _Download.allZip:
        exportAllTargetsZip(project, language: _lang);
      case _Download.everyLanguage:
        exportEveryLanguageZip(project, sub);
      case _Download.everything:
        exportEverythingZip(project);
      case _Download.fastlane:
        exportFastlaneZip(project);
      case _Download.copy:
        _copyImage();
      case _Download.options:
        _exportOptions();
    }
  }

  void _projectAction(_ProjectMenu action) {
    final project = _project;
    final sub = _sub;
    if (project == null || sub == null) return;
    switch (action) {
      case _ProjectMenu.rename:
        renameProject(project);
      case _ProjectMenu.duplicate:
        duplicateProject(project);
      case _ProjectMenu.backup:
        backupProject(project);
      case _ProjectMenu.delete:
        deleteProject();
      case _ProjectMenu.lockCanvas:
        setState(() => _canvasLocked = !_canvasLocked);
      case _ProjectMenu.preview:
        _togglePreview();
      case _ProjectMenu.shortcuts:
        _showShortcuts(context);
      case _ProjectMenu.storePreview:
        _storePreview();
      case _ProjectMenu.storeCopy:
        context.push('/project/${widget.projectId}/store-copy');
      case _ProjectMenu.appIcon:
        context.push('/project/${widget.projectId}/icon');
      case _ProjectMenu.languages:
        _languageSheet();
      case _ProjectMenu.translate:
        _translate();
      case _ProjectMenu.translateAll:
        _translateAll();
      case _ProjectMenu.continuous:
        _toggleContinuous();
    }
  }

  void _targetAction(_TargetMenu action) {
    final project = _project;
    final sub = _sub;
    if (project == null || sub == null) return;
    switch (action) {
      case _TargetMenu.add:
        addTarget(project);
      case _TargetMenu.canvas:
        changeCanvas(sub);
      case _TargetMenu.copyScreens:
        copyScreensFrom(project, sub);
      case _TargetMenu.move:
        transferTarget(project, sub, move: true);
      case _TargetMenu.copy:
        transferTarget(project, sub, move: false);
      case _TargetMenu.remove:
        removeTarget(sub);
    }
  }

  /// Shows the set in [language].
  void _useLanguage(String language) {
    HapticFeedback.selectionClick();
    final project = _project;
    ref
        .read(editorLanguagesProvider.notifier)
        .set(
          widget.projectId,
          language == project?.defaultLanguage ? null : language,
        );
    setState(() => _selected = null);
    if (project != null && language != project.defaultLanguage) {
      showStudioSnack(
        snackContext,
        'Editing ${localeFor(language).name}: words you change are this '
        "language's; everything else changes in every language.",
      );
    }
  }

  /// A phone's language chip: which language to edit, and the way into
  /// adding more.
  Future<void> _languageSheet() async {
    final project = _project;
    if (project == null) return;
    const manage = '\u0000manage';
    final current = _lang ?? project.defaultLanguage;
    final pick = await showStudioSheet<String>(
      context,
      title: 'Language',
      child: Builder(
        builder: (sheet) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, code) in project.languages.indexed)
              StudioListRow(
                title: localeFor(code).name,
                subtitle: i == 0 ? 'Default' : code,
                selected: code == current,
                onTap: () => Navigator.pop(sheet, code),
              ),
            StudioListRow(
              icon: StudioIcons.add,
              title: 'Add or remove languages…',
              onTap: () => Navigator.pop(sheet, manage),
            ),
            SizedBox(height: StudioSpace.m),
          ],
        ),
      ),
    );
    if (pick == null || !mounted) return;
    if (pick == manage) {
      await _manageLanguages();
    } else {
      _useLanguage(pick);
    }
  }

  Future<void> _manageLanguages() async {
    final project = _project;
    if (project == null) return;
    final chosen = await _showLanguagesSheet(context, project.languages);
    if (chosen == null || !mounted) return;
    _checkpoint();
    _store.setLanguages(widget.projectId, chosen);
    // The language on show may have been removed, or made the default.
    final language = _language;
    if (language != null &&
        (!chosen.contains(language) || chosen.first == language)) {
      ref.read(editorLanguagesProvider.notifier).set(widget.projectId, null);
    }
    setState(() {});

    // A language just added has nothing in it yet. Offered, not done: the
    // user may want to write this one by hand, and a translation run over a
    // whole listing is not something to start behind anyone's back.
    final added = chosen.skip(1).where((c) => !project.languages.contains(c));
    if (added.isNotEmpty) {
      final status = await ref
          .read(translatorProvider)
          .translationStatus(from: chosen.first, to: added.first);
      if (!mounted || !status.usable) return;
      showStudioSnack(
        snackContext,
        added.length == 1
            ? '${localeFor(added.first).name} added. Translate it on this '
                  'device?'
            : '${added.length} languages added. Translate them on this '
                  'device?',
        icon: StudioIcons.web,
        actionLabel: 'Translate',
        onAction: _translateAll,
      );
    }
  }

  /// The translation table for the language on show, or — from the default —
  /// for the project's first other language.
  Future<void> _translate() async {
    final project = _project;
    final sub = _sub;
    if (project == null || sub == null) return;
    final language = _lang ?? project.languages.skip(1).firstOrNull;
    if (language == null) {
      await _manageLanguages();
      return;
    }
    _checkpoint();
    final items = _translatablesOf(sub.screens, language);
    final translator = ref.read(translatorProvider);
    final from = project.defaultLanguage;
    await showStudioSheet<void>(
      context,
      title: 'Translate into ${localeFor(language).name}',
      child: SizedBox(
        height: context.layout.modalContentHeight(0.86),
        child: _TranslateTable(
          language: language,
          items: items,
          status: () => translator.translationStatus(from: from, to: language),
          translate: (sources) async {
            final out = await translator.translate(
              sources,
              from: from,
              to: language,
            );
            return [
              for (final (i, text) in out.indexed)
                rebreakLines(sources[i], text),
            ];
          },
          onChanged: (item, text) {
            final screen = _sub?.screens.elementAtOrNull(item.screenIndex);
            if (screen == null) return;
            _store.updateScreen(widget.projectId, item.write(screen, text));
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Every missing translation in every language, in every set, filled in on
  /// the device.
  ///
  /// Only what is missing: a translation somebody typed, or corrected after a
  /// machine wrote it, is theirs and is never overwritten. Languages the device
  /// cannot translate are named up front rather than discovered one failure at
  /// a time, and a run can be stopped — what finished is kept, and one undo
  /// takes the whole run back.
  Future<void> _translateAll() async {
    final project = _project;
    if (project == null) return;
    final from = project.defaultLanguage;
    final languages = project.languages.skip(1).toList();
    if (languages.isEmpty) {
      await _manageLanguages();
      return;
    }

    final translator = ref.read(translatorProvider);
    final statuses = {
      for (final to in languages)
        to: await translator.translationStatus(from: from, to: to),
    };
    if (!mounted) return;
    final doable = [
      for (final to in languages)
        if (statuses[to]!.usable) to,
    ];
    final skipped = [
      for (final to in languages)
        if (!statuses[to]!.usable) localeFor(to).name,
    ];
    if (doable.isEmpty) {
      showStudioSnack(
        snackContext,
        statuses.values.first.reason ??
            'None of these languages can be translated on this device.',
        danger: true,
      );
      return;
    }

    bool isMissing(_Translatable item) =>
        (item.translation ?? '').trim().isEmpty;
    final total = [
      for (final to in doable)
        for (final sub in project.subProjects)
          ..._translatablesOf(sub.screens, to).where(isMissing),
    ].length;
    if (total == 0) {
      showStudioSnack(snackContext, 'Every language is already translated.');
      return;
    }

    final downloads = [
      for (final to in doable)
        if (statuses[to]!.state == ModelState.needsDownload) localeFor(to).name,
    ];
    final go = await showStudioConfirm(
      context,
      title: 'Translate $total ${total == 1 ? 'text' : 'texts'}?',
      message: [
        'Into ${doable.map((c) => localeFor(c).name).join(', ')}, on this '
            'device with ${statuses[doable.first]!.engine.label}. Translations '
            'that are already there are kept.',
        if (downloads.isNotEmpty)
          'Language packs download once first: ${downloads.join(', ')}.',
        if (skipped.isNotEmpty)
          'Not available here: ${skipped.join(', ')}. Use Translate texts for '
              'those.',
      ].join('\n\n'),
      confirmLabel: 'Translate',
      icon: StudioIcons.filters,
    );
    if (!go || !mounted) return;

    _checkpoint();
    final subIds = [for (final s in project.subProjects) s.id];
    final done = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TranslateAllDialog(
        total: total,
        run: (progress, cancelled) async {
          var count = 0;
          for (final to in doable) {
            for (final subId in subIds) {
              if (cancelled()) return count;
              final sub = _store.byId(widget.projectId)?.subProjectById(subId);
              if (sub == null) continue;
              final items = _translatablesOf(
                sub.screens,
                to,
              ).where(isMissing).toList();
              // In batches small enough that Stop is prompt, and that a
              // device's model is never asked for a whole listing at once.
              for (var start = 0; start < items.length; start += 12) {
                if (cancelled()) return count;
                final batch = items.skip(start).take(12).toList();
                final out = await translator.translate(
                  [for (final item in batch) item.source],
                  from: from,
                  to: to,
                );
                for (final (k, item) in batch.indexed) {
                  // Re-read every time: each write replaces the screen, and a
                  // stale copy would undo the translation before it.
                  final latest = _store
                      .byId(widget.projectId)
                      ?.subProjectById(subId)
                      ?.screens
                      .elementAtOrNull(item.screenIndex);
                  if (latest == null) continue;
                  _store.updateScreen(
                    widget.projectId,
                    item.write(latest, rebreakLines(item.source, out[k])),
                  );
                }
                count += batch.length;
                progress(count, localeFor(to).name);
              }
            }
          }
          return count;
        },
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (done != null && done > 0) {
      showStudioSnack(
        snackContext,
        done == total
            ? 'Translated $done ${done == 1 ? 'text' : 'texts'}. Read them '
                  'over in Translate texts before you ship.'
            : 'Translated $done of $total. The rest keep the default words.',
      );
    }
  }

  /// The set as a shopper meets it: inside a store listing, in the language
  /// on show.
  void _storePreview() {
    final project = _project;
    final sub = _sub;
    final catalog = ref.read(frameCatalogProvider).valueOrNull;
    if (project == null || sub == null || catalog == null) return;
    List<ComposedScreen> composed(SubProject set) {
      final shown = _shown(set);
      return [
        for (var i = 0; i < shown.length; i++)
          composeScreen(shown, i, continuous: set.continuous),
      ];
    }

    // Each store's page shows that store's set: the Google Play tab of an
    // iPhone set used to be a Play listing full of iPhones, with the
    // project's own Android set a menu away. The set on show wins on its own
    // store, unless it is a graphic — a feature graphic is not screenshots —
    // and otherwise the first set of the kind the store's page shows.
    SubProject? setFor(StoreKind store, Set<TargetFormFactor> forms) {
      if (sub.target.store == store &&
          sub.target.formFactor != TargetFormFactor.graphic &&
          sub.screens.isNotEmpty) {
        return sub;
      }
      return project.subProjects
          .where(
            (set) =>
                set.target.store == store &&
                forms.contains(set.target.formFactor) &&
                set.screens.isNotEmpty,
          )
          .firstOrNull;
    }

    const handset = {TargetFormFactor.phone};
    const desktop = {TargetFormFactor.desktop};
    final sets = <StorePreviewStyle, SubProject?>{
      StorePreviewStyle.appStore: setFor(StoreKind.appStore, handset),
      StorePreviewStyle.googlePlay: setFor(StoreKind.playStore, handset),
      StorePreviewStyle.macAppStore: setFor(StoreKind.macAppStore, desktop),
      StorePreviewStyle.microsoftStore: setFor(
        StoreKind.microsoftStore,
        desktop,
      ),
      // Samsung takes the Play phone set as it is, so that is what shows.
      StorePreviewStyle.galaxyStore: setFor(StoreKind.playStore, handset),
      StorePreviewStyle.appGallery:
          setFor(StoreKind.huaweiAppGallery, handset) ??
          setFor(StoreKind.playStore, handset),
      StorePreviewStyle.chromeWebStore: setFor(
        StoreKind.chromeWebStore,
        desktop,
      ),
    };

    // The project's own icon artwork, when it has an icon set: what the
    // listing will actually carry, rather than a stand-in.
    final iconSet = project.subProjects
        .where(
          (set) =>
              set.targetId == StoreTargets.playIcon.id &&
              set.screens.isNotEmpty,
        )
        .firstOrNull;
    final appStoreSet = sets[StorePreviewStyle.appStore] ?? sub;

    // The App Store subtitle the store copy page saved, in the language on
    // show, and the opening headline only until there is one.
    final savedSubtitle = [
      project.storeCopy.text(
        CopyStore.appStore,
        _lang ?? project.defaultLanguage,
        'subtitle',
      ),
      project.storeCopy.text(
        CopyStore.appStore,
        project.defaultLanguage,
        'subtitle',
      ),
    ].firstWhere((s) => s.trim().isNotEmpty, orElse: () => '');
    showStorePreview(
      context,
      appName: project.name,
      subtitle: savedSubtitle.isNotEmpty
          ? savedSubtitle
          : previewSubtitleFrom(_shown(appStoreSet)),
      icon: iconSet == null ? null : composed(iconSet).first,
      // The icon designed on the Icon page, when there is one, wins over the
      // Play icon set's artwork and the stand-in.
      appIcon: project.icon,
      catalog: catalog,
      screens: composed(sub),
      screensFor: {
        for (final MapEntry(key: style, value: set) in sets.entries)
          if (set != null) style: composed(set),
      },
      initial: StorePreviewStyle.forStore(sub.target.store),
    );
  }

  void _togglePreview() {
    HapticFeedback.selectionClick();
    setState(() {
      _preview = !_preview;
      if (_preview) _drawing = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Keyboard
  // ---------------------------------------------------------------------------

  /// Whether a text field currently owns the keyboard.
  ///
  /// Bare-key shortcuts must stand down while a caption is being typed,
  /// otherwise "1" switches library instead of entering a digit.
  static bool get _typing {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _zoomBy(double factor) => _viewport.currentState?.zoomBy(factor);

  /// Closes the innermost thing open in the workspace, and says whether there
  /// was one: the eyedropper, then the pen, then preview, then the selection,
  /// then the panels.
  ///
  /// Escape walks this list, and so does Android's back button — which used
  /// to leave the editor outright, from the middle of a selection with its
  /// tools up.
  bool _dismissInnermost(StudioLayout layout) {
    if (ref.read(scenePickProvider).picking) {
      ref.read(scenePickProvider.notifier).cancel();
    } else if (_drawing) {
      _toggleDrawing();
    } else if (_preview) {
      _togglePreview();
    } else if (_selected != null) {
      setState(() => _selected = null);
    } else if (layout.docksToBottom && _sheetExpanded) {
      setState(() => _sheetExpanded = false);
    } else if (!layout.docksToBottom && _library != null) {
      setState(() => _library = null);
    } else {
      return false;
    }
    return true;
  }

  /// Whether back has something to close before it leaves the editor.
  ///
  /// Called from build, and watches the eyedropper so arming it rebuilds the
  /// back handler along with everything else.
  bool _hasSomethingOpen(StudioLayout layout) =>
      ref.watch(scenePickProvider.select((p) => p.picking)) ||
      _drawing ||
      _preview ||
      _selected != null ||
      (layout.docksToBottom ? _sheetExpanded : false);

  /// The editor's keyboard, handed every key nothing inside it took.
  ///
  /// Not a `CallbackShortcuts`: that reports every key it has a binding for as
  /// handled, even when the binding then does nothing because a text field is
  /// focused — and on the web a handled key is cancelled before the browser
  /// puts it in the field. Digits, "p", Backspace and Delete never reached
  /// the Arrange fields, so typing a width of 450 set it to 3. While a field
  /// has the keyboard every key is left to it; Escape hands the keyboard back.
  KeyEventResult _onKey(FocusNode node, KeyEvent event, StudioLayout layout) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (_typing) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _claimKeyboard();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    for (final MapEntry(key: activator, value: callback) in _shortcuts(
      layout,
    ).entries) {
      if (activator.accepts(event, HardwareKeyboard.instance)) {
        callback();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Takes the keyboard back for the canvas, from a text field in a panel.
  ///
  /// On a desktop a field keeps focus when the mouse goes elsewhere, so after
  /// one click in the icon search the shortcuts stayed with the field — dead
  /// for the rest of the session. A press anywhere on the canvas brings them
  /// back, the way it does in every design tool.
  void _claimKeyboard() {
    // After the press has been handled everywhere: a field's own "tapped
    // outside" handling runs on the same press and hands focus to the page,
    // and asked first, the editor lost to it.
    scheduleMicrotask(() {
      if (mounted && !_keyboard.hasPrimaryFocus) _keyboard.requestFocus();
    });
  }

  /// Takes the keyboard whenever it falls back to the page itself — a field
  /// that let go of it, a panel closed with a field in it — so the shortcuts
  /// are never left with nobody listening. Focus in a dialog or a menu is in
  /// a scope of its own and is left alone.
  void _keepKeyboard() {
    final primary = FocusManager.instance.primaryFocus;
    if (!mounted || primary == null || primary == _keyboard) return;
    if (primary is FocusScopeNode && _keyboard.ancestors.contains(primary)) {
      _keyboard.requestFocus();
    }
  }

  final FocusNode _keyboard = FocusNode(debugLabel: 'editor keyboard');

  Map<ShortcutActivator, VoidCallback> _shortcuts(StudioLayout layout) {
    void library(_Library l) {
      if (_preview) return;
      _onLibrary(l, phone: layout.docksToBottom);
    }

    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ): _redo,
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
          _redo,
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveImage,
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveImage,
      const SingleActivator(LogicalKeyboardKey.digit0, control: true): _refocus,
      const SingleActivator(LogicalKeyboardKey.digit0, meta: true): _refocus,
      const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
          _zoomBy(1.25),
      const SingleActivator(LogicalKeyboardKey.equal, meta: true): () =>
          _zoomBy(1.25),
      const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
          _zoomBy(1 / 1.25),
      const SingleActivator(LogicalKeyboardKey.minus, meta: true): () =>
          _zoomBy(1 / 1.25),
      const SingleActivator(LogicalKeyboardKey.digit1, shift: true): _fitAll,
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          _dismissInnermost(layout),
      const SingleActivator(LogicalKeyboardKey.keyP): _togglePreview,
      const SingleActivator(LogicalKeyboardKey.delete): _deleteSelectedShape,
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
          _nudge(const Offset(-1, 0)),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
          _nudge(const Offset(1, 0)),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
          _nudge(const Offset(0, -1)),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
          _nudge(const Offset(0, 1)),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): () =>
          _nudge(const Offset(-10, 0)),
      const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): () =>
          _nudge(const Offset(10, 0)),
      const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): () =>
          _nudge(const Offset(0, -10)),
      const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): () =>
          _nudge(const Offset(0, 10)),
      for (final meta in const [false, true]) ...{
        SingleActivator(LogicalKeyboardKey.keyC, meta: meta, control: !meta):
            _copy,
        SingleActivator(LogicalKeyboardKey.keyX, meta: meta, control: !meta):
            _cut,
        SingleActivator(LogicalKeyboardKey.keyV, meta: meta, control: !meta):
            _paste,
        SingleActivator(LogicalKeyboardKey.keyD, meta: meta, control: !meta):
            _duplicate,
      },
      // The character, not the key: on a web page Shift+/ arrives as "?",
      // and a slash-with-shift activator never matched it.
      const CharacterActivator('?'): () => _showShortcuts(context),
      const SingleActivator(LogicalKeyboardKey.backspace): _deleteSelectedShape,
      for (final l in _Library.values)
        SingleActivator(_digitKeys[l.index]): () => library(l),
    };
  }

  static const _digitKeys = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
  ];

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) => ProjectScope(
    // Published once, here, so every panel and sheet below can ask which
    // project it is in without being handed the id — see [ProjectScope].
    projectId: widget.projectId,
    child: Builder(builder: _build),
  );

  Widget _build(BuildContext context) {
    final catalogAsync = ref.watch(frameCatalogProvider);
    // The language remembered for this project arrives from storage after the
    // first frame; watched so the canvas turns to it when it does.
    ref.watch(editorLanguagesProvider.select((m) => m[widget.projectId]));
    final s = context.studio;
    // The project, watched: every edit is written to the store, so this is
    // what rebuilds the canvas as the user works.
    final project = ref.watch(
      projectStoreProvider.select(
        (list) => list.where((p) => p.id == widget.projectId).firstOrNull,
      ),
    );

    if (project == null) {
      return Scaffold(
        backgroundColor: s.canvas,
        appBar: AppBar(),
        body: const StudioEmptyState(
          icon: StudioIcons.warning,
          title: 'Project not found',
          message: 'This project may have been deleted.',
        ),
      );
    }

    final sub = _sub;
    if (sub == null) {
      return Scaffold(
        backgroundColor: s.canvas,
        appBar: AppBar(title: Text(project.name)),
        body: StudioEmptyState(
          icon: StudioIcons.warning,
          title: 'No targets',
          message:
              'This project has no store targets left. Add one to start '
              'composing screenshots again.',
          primaryAction: StudioButton(
            label: 'Add target',
            icon: StudioIcons.add,
            variant: StudioButtonVariant.primary,
            onPressed: () => addTarget(project),
          ),
        ),
      );
    }

    final layout = context.layout;

    if (!_focused) {
      _focused = true;
      _refocus(animate: false);
    }

    return PopScope(
      // Back closes what is open first — see [_dismissInnermost] — and only
      // leaves the editor once there is nothing left to close. The side
      // panels on a wide window are part of the layout, not something open.
      canPop: !_hasSomethingOpen(layout),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismissInnermost(layout);
      },
      child: _scaffold(context, catalogAsync, project, sub, layout),
    );
  }

  Widget _scaffold(
    BuildContext context,
    AsyncValue<FrameCatalog> catalogAsync,
    Project project,
    SubProject sub,
    StudioLayout layout,
  ) {
    final s = context.studio;
    return Scaffold(
      backgroundColor: _workAreaColor(context),
      // The keyboard must not resize the workspace. Text is edited in a sheet
      // that rides above it (see `CaptionPanel`), so the only thing a resize
      // here would achieve is shrinking the canvas and moving the composition
      // the user is typing against.
      resizeToAvoidBottomInset: false,
      // Focus without stealing it: the editor takes the keyboard when nothing
      // else wants it, and hands it straight back the moment a field asks.
      body: Focus(
        focusNode: _keyboard,
        autofocus: true,
        onKeyEvent: (node, event) => _onKey(node, event, layout),
        child: catalogAsync.when(
          loading: () => ColoredBox(
            color: s.canvas,
            child: Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: s.accentText,
                ),
              ),
            ),
          ),
          // The frames ship with the app, so this is a damaged install or a
          // storage hiccup rather than anything the user did. The exception
          // goes to the log; the screen says what to do.
          error: (e, st) {
            debugPrint('Could not load device frames: $e');
            return ColoredBox(
              color: s.canvas,
              child: StudioEmptyState(
                icon: StudioIcons.error,
                title: 'Could not load device frames',
                message:
                    'The frames that ship with MockMyApp did not load. Try '
                    'again; if it keeps happening, restart the app.',
                primaryAction: StudioButton(
                  label: 'Try again',
                  icon: StudioIcons.reset,
                  variant: StudioButtonVariant.primary,
                  onPressed: () => ref.invalidate(frameCatalogProvider),
                ),
              ),
            );
          },
          data: (catalog) => layout.docksToBottom
              ? _buildPhone(context, catalog, layout, project, sub)
              : _buildSides(context, catalog, layout, project, sub),
        ),
      ),
    );
  }

  /// The surface behind the screens. Follows the theme, a step off the panel
  /// tone so a white screenshot still reads against it.
  Color _workAreaColor(BuildContext context) {
    if (context.isDark) return StudioColors.dark.canvas;
    return Color.alphaBlend(
      StudioColors.light.hoverBg,
      StudioColors.light.panel,
    );
  }

  _TopBar _topBar(
    BuildContext context,
    Project project,
    SubProject sub, {
    required bool compact,
  }) => _TopBar(
    project: project,
    sub: sub,
    compact: compact,
    preview: _preview,
    busy: _busy,
    canUndo: _undoStack.canUndo,
    canRedo: _undoStack.canRedo,
    canvasLocked: _canvasLocked,
    lockable: context.layout.docksToBottom,
    roomy: context.layout.isDesktop,
    onBack: () => context.canPop() ? context.pop() : context.go('/'),
    onUndo: _undo,
    onRedo: _redo,
    onTogglePreview: _togglePreview,
    onSelectTarget: _showTarget,
    onTargetAction: _targetAction,
    onProjectAction: _projectAction,
    onDownload: _download,
    exportSummary: ref.watch(exportSettingsProvider).summary,
    language: _lang ?? project.defaultLanguage,
    onLanguage: _useLanguage,
    onManageLanguages: _manageLanguages,
    onTranslate: _translate,
    onTranslateAll: _translateAll,
    hasOtherProjects: ref.watch(
      projectStoreProvider.select((list) => list.length > 1),
    ),
  );

  /// The canvas: every screen of the target, side by side.
  Widget _stage(
    BuildContext context,
    FrameCatalog catalog,
    SubProject sub, {
    required bool showToolbar,
  }) {
    final layout = context.layout;
    final active = doc;
    return _PickableCanvas(
      // A raw listener, so it takes no part in the gestures below: any press
      // on the canvas takes the keyboard back from a panel's text field.
      child: Listener(
        onPointerDown: (_) => _claimKeyboard(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final previous = _stageSize;
            if (previous != null && size != previous && !previous.isEmpty) {
              _anchorActive(previous, size);
              _stageSettle?.cancel();
              _stageSettle = Timer(
                StudioDuration.slow + const Duration(milliseconds: 60),
                _keepActiveInView,
              );
            }
            _stageSize = size;
            final shown = _shown(sub);
            final geometry = _StripGeometry(
              viewport: constraints.biggest,
              canvases: [for (final s in sub.screens) s.canvas],
              compact: layout.isPhone,
              withAddTile: !_preview && _canAddScreens,
              continuous: sub.continuous,
              toolbar: showToolbar && !_preview,
            );
            final activeIndex = active == null
                ? -1
                : sub.screens.indexWhere((s) => s.id == active.id);
            _screenPx = activeIndex < 0 ? 0 : geometry.widths[activeIndex];
            return Stack(
              key: const ValueKey('canvas-stage'),
              children: [
                Positioned.fill(
                  child: _CanvasViewport(
                    key: _viewport,
                    onScaleChanged: (v) => _zoom.value = v,
                    hasSelection: _selected != null && !_preview,
                    contentWidth: geometry.contentWidth,
                    child: _ScreenStrip(
                      geometry: geometry,
                      screens: shown,
                      activeId: active?.id,
                      catalog: catalog,
                      preview: _preview,
                      hover: layout.hasPointer,
                      continuous: sub.continuous,
                      activeScene: active == null || activeIndex < 0
                          ? null
                          : SceneView.composed(
                              composeScreen(
                                shown,
                                activeIndex,
                                continuous: sub.continuous,
                              ),
                              key: const ValueKey('active-scene'),
                              catalog: catalog,
                              selected: _preview ? null : _selected,
                              onSelect: _preview ? null : _selectHandle,
                              onTransformStart: _preview
                                  ? null
                                  : _transformStartHandle,
                              onTransform: _preview ? null : _transformHandle,
                              onTransformEnd: _preview
                                  ? null
                                  : _transformEndHandle,
                              drawing: _drawing && !_preview,
                              onPathDrawn: _addDrawnShape,
                              guides: _preview ? const [] : _guides,
                              onContextMenu: _preview ? null : _contextMenu,
                              onEmptyScreenTap: _preview
                                  ? null
                                  : _chooseScreenshot,
                              onEditText: _preview ? null : _editTextOf,
                              onLockedTap: _preview ? null : _lockedTap,
                            ),
                      onActivate: _activate,
                      onAction: _screenAction,
                      onAdd: () => _addScreen(),
                      canAdd: _canAddScreens,
                      onBackgroundTap: () {
                        if (_selected != null) setState(() => _selected = null);
                      },
                      onPan: (delta) {
                        final viewport = _viewport.currentState;
                        viewport?._panBy(delta * viewport.scale);
                      },
                    ),
                  ),
                ),
                // The floating toolbar is laid over the whole workspace, not
                // here — see [_ToolbarPlacement].
                if (!showToolbar)
                  ValueListenableBuilder<double>(
                    valueListenable: _zoom,
                    builder: (context, zoom, _) {
                      if ((zoom - 1).abs() < 0.001) {
                        return const SizedBox.shrink();
                      }
                      return Positioned(
                        right: StudioSpace.l,
                        bottom: StudioSpace.l,
                        child: _ZoomDock(scale: zoom, onReset: _refocus),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The floating canvas toolbar: zoom, fit, canvas size, the store preview.
  ///
  /// Scaled rather than clipped when the room for it is narrower than the bar
  /// — a tablet with a panel open, or a window mid-resize.
  Widget _canvasToolbar(SubProject sub) => FittedBox(
    fit: BoxFit.scaleDown,
    child: ValueListenableBuilder<double>(
      valueListenable: _zoom,
      builder: (context, zoom, _) => _CanvasToolbar(
        canvas: sub.canvas,
        zoom: zoom,
        onCanvas: () => changeCanvas(sub),
        onZoomIn: () => _zoomBy(1.25),
        onZoomOut: () => _zoomBy(1 / 1.25),
        onFit: _fitAll,
        onReset: _refocus,
        continuous: sub.continuous,
        onContinuous: sub.screens.length < 2 ? null : _toggleContinuous,
        onStorePreview: _storePreview,
      ),
    ),
  );

  /// The library panel's body for [library].
  Widget _libraryBody(
    _Library library,
    FrameCatalog catalog,
    SubProject sub, {
    required EdgeInsets padding,
  }) => _LibraryBody(
    library: library,
    projectId: widget.projectId,
    sub: sub,
    doc: doc,
    aiHost: _aiHost(sub),
    shownBackground: _shownBackground,
    catalog: catalog,
    deviceIndex: _deviceIndex,
    padding: padding,
    templateId: templateIdFor(sub.id),
    drawing: _drawing,
    onTemplate: (t) => applyTemplateTo(sub, chosen: t),
    onDevice: (pick) => _pickDevice(pick, catalog),
    onDeviceToAll: () => _deviceToAll(catalog),
    onShape: _pickShape,
    onText: (isSub) => _pickText(sub: isSub),
    onBackground: _setBackground,
    onBackdrop: (bg, decor) {
      final current = doc;
      if (current == null) return;
      // A template backdrop replaces what is behind the device and nothing
      // else: anything the user put in front is their composition.
      _setDoc(
        current.copyWith(
          shapes: [
            ...decor,
            for (final shape in current.shapes)
              if (shape.z > kStackBehindFrames) shape,
          ],
        ),
      );
      _setBackground(bg);
    },
    onBackgroundToAll: _backgroundToAll,
    onUpload: _pickUpload,
    onUploads: _pickUploads,
    onTextLayer: _addTextLayer,
    onImageLayer: _addImageLayer,
    onElement: _addShape,
  );

  /// The properties panel's body, or null when nothing selected has any.
  Widget? _propertiesBody(FrameCatalog catalog, {required EdgeInsets padding}) {
    final tab = _propertiesTab;
    final current = doc;
    if (tab == null || current == null) return null;
    return _ToolPanelBody(
      tab: tab.index,
      doc: current,
      catalog: catalog,
      onDocChanged: _setDoc,
      padding: padding,
      projectId: widget.projectId,
      selection: _selected,
      onSelectLayer: _selectLayer,
      drawing: _drawing,
      onToggleDrawing: _toggleDrawing,
      onOpenLayers: () => setState(() {
        _layers = true;
        _shapeTools = false;
        _pane = _Pane.properties;
        _propertiesDismissed = false;
      }),
      onOpenLayer: _selectHandle,
      onOpenShapeTools: () => setState(() {
        _layers = false;
        _shapeTools = true;
        _pane = _Pane.properties;
        _propertiesDismissed = false;
      }),
    );
  }

  /// Every window that is not a phone held upright: rail and library on the
  /// left, the canvas, properties on the right.
  ///
  /// A desktop window shows both panels at once. Anything narrower shows one,
  /// whichever was asked for last, because two 300dp panels either side of a
  /// tablet's canvas leave it the width of a thumbnail.
  Widget _buildSides(
    BuildContext context,
    FrameCatalog catalog,
    StudioLayout layout,
    Project project,
    SubProject sub,
  ) {
    final both = layout.isDesktop;
    final panelPadding = EdgeInsets.fromLTRB(
      StudioSpace.l,
      StudioSpace.m,
      StudioSpace.l,
      0,
    );
    final properties = _preview
        ? null
        : _propertiesBody(catalog, padding: panelPadding);
    final library = _preview ? null : _library;

    final showLibrary =
        library != null &&
        (both || _pane == _Pane.library || properties == null);
    final showProperties =
        properties != null &&
        (both || _pane == _Pane.properties || !showLibrary);

    final libraryWidth = (_libraryWidth ?? layout.inspectorWidth).clamp(
      layout.inspectorMinWidth,
      layout.inspectorMaxWidth,
    );
    final propertiesWidth = (_propertiesWidth ?? layout.inspectorWidth).clamp(
      layout.inspectorMinWidth,
      layout.inspectorMaxWidth,
    );
    final railWidth = layout.isDesktop ? 72.0 : layout.railWidth;

    return StudioBottomChrome(
      // The floating canvas toolbar's band, so a toast lands above it rather
      // than on top of the zoom and the store preview.
      height: StudioSizes.button + StudioSpace.l * 2,
      child: Builder(
        builder: (chrome) {
          _chromeContext = chrome;
          return Column(
            children: [
              _topBar(context, project, sub, compact: layout.isPhoneLandscape),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!_preview)
                            StudioToolRail(
                              items: [
                                for (final l in _Library.values)
                                  StudioTabItem(l.icon, l.label),
                              ],
                              currentIndex: showLibrary ? library.index : -1,
                              showLabels: layout.isDesktop,
                              width: railWidth,
                              onChanged: (i) =>
                                  _onLibrary(_Library.values[i], phone: false),
                              trailing: StudioIconButton(
                                icon: StudioIcons.layers,
                                iconSize: 18,
                                selected: _layers && showProperties,
                                tooltip: 'Layers',
                                onPressed: _toggleLayers,
                              ),
                            ),
                          _SlidePane(
                            open: showLibrary,
                            width: libraryWidth,
                            edge: _PaneEdge.leading,
                            divider: StudioPaneDivider(
                              onDrag: (d) => setState(
                                () => _libraryWidth = (libraryWidth + d).clamp(
                                  layout.inspectorMinWidth,
                                  layout.inspectorMaxWidth,
                                ),
                              ),
                              onDoubleTap: () =>
                                  setState(() => _libraryWidth = null),
                            ),
                            child: _SidePanel(
                              title: (library ?? _Library.templates).label,
                              onClose: () => setState(() => _library = null),
                              // One library rises in as the last fades, rather
                              // than the pane cutting between them.
                              child: StudioSwitcher(
                                child: library == null
                                    ? const SizedBox.shrink()
                                    : KeyedSubtree(
                                        key: ValueKey(
                                          'library-${library.name}',
                                        ),
                                        child: _libraryBody(
                                          library,
                                          catalog,
                                          sub,
                                          padding: panelPadding,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _stage(
                              context,
                              catalog,
                              sub,
                              showToolbar: true,
                            ),
                          ),
                          _SlidePane(
                            open: showProperties,
                            width: propertiesWidth,
                            edge: _PaneEdge.trailing,
                            divider: StudioPaneDivider(
                              onDrag: (d) => setState(
                                () => _propertiesWidth = (propertiesWidth - d)
                                    .clamp(
                                      layout.inspectorMinWidth,
                                      layout.inspectorMaxWidth,
                                    ),
                              ),
                              onDoubleTap: () =>
                                  setState(() => _propertiesWidth = null),
                            ),
                            child: _SidePanel(
                              title: _propertiesTitle,
                              onClose: _closeProperties,
                              child: StudioSwitcher(
                                child: KeyedSubtree(
                                  key: ValueKey(
                                    'properties-${_propertiesTab?.name}',
                                  ),
                                  child: properties ?? const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_preview)
                      Positioned.fill(
                        child: CustomSingleChildLayout(
                          delegate: _ToolbarPlacement(
                            start: railWidth,
                            left:
                                railWidth +
                                (showLibrary
                                    ? libraryWidth + StudioPaneDivider.width
                                    : 0),
                            right: showProperties
                                ? propertiesWidth + StudioPaneDivider.width
                                : 0,
                          ),
                          child: _canvasToolbar(sub),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String get _propertiesTitle => switch (_propertiesTab) {
    _EditorTab.frame => 'Device',
    _EditorTab.screenshot => 'Screenshot',
    _EditorTab.caption => 'Headline',
    _EditorTab.subcaption => 'Subtitle',
    _EditorTab.layers => 'Layers',
    _EditorTab.text => 'Text',
    _EditorTab.image => 'Image',
    _EditorTab.shape => 'Shape',
    _EditorTab.background || null => 'Properties',
  };

  /// A phone held upright: top bar, the canvas, and one sheet over a tab bar.
  Widget _buildPhone(
    BuildContext context,
    FrameCatalog catalog,
    StudioLayout layout,
    Project project,
    SubProject sub,
  ) {
    final media = MediaQuery.of(context);
    final bottomInset = media.padding.bottom;
    final topChrome = media.padding.top + layout.toolbarHeight;

    final padding = EdgeInsets.fromLTRB(
      StudioSpace.xxl,
      StudioSpace.xs,
      StudioSpace.xxl,
      0,
    );
    final properties = _pane == _Pane.properties
        ? _propertiesBody(catalog, padding: padding)
        : null;
    final showsProperties = properties != null;
    // The layers list keeps the tab bar, where it is one of the tabs; a tool
    // swaps the bar for its own title and a way back.
    final showsLayers = showsProperties && _layers;

    // Each panel asks for its own height, never at the cost of the canvas: on
    // a short phone the sheet is capped at 70% and the panel scrolls.
    final available = math.max(media.size.height - topChrome, 1.0);
    final asked =
        _sheetHeightRequest ??
        (showsProperties
            ? _propertiesSheetHeight(_propertiesTab!)
            : _phoneLibrary.sheetHeight);
    final wanted = asked.clamp(StudioSizes.tabStrip * 3, 720.0) + bottomInset;
    final expandedHeight = math.min(wanted, available * 0.7);
    final collapsedHeight = StudioSizes.tabStrip + bottomInset;
    final sheetHeight = _sheetExpanded ? expandedHeight : collapsedHeight;
    final bottomChrome = _preview
        ? 0.0
        : (_canvasLocked ? collapsedHeight : sheetHeight);

    return StudioBottomChrome(
      height: _preview ? 0 : collapsedHeight,
      child: Builder(
        builder: (chrome) {
          _chromeContext = chrome;
          return SizedBox.expand(
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: context.motion(StudioDuration.slow),
                  curve: Curves.easeOutCubic,
                  left: 0,
                  right: 0,
                  top: topChrome,
                  bottom: bottomChrome,
                  child: _stage(context, catalog, sub, showToolbar: false),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: _topBar(context, project, sub, compact: true),
                ),
                if (!_preview)
                  AnimatedPositioned(
                    duration: context.motion(StudioDuration.slow),
                    curve: Curves.easeOutCubic,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: sheetHeight,
                    child: ClipRect(
                      // Laid out at its full height and clipped from the top when
                      // collapsed, so the panel never reflows mid-animation.
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        reverse: true,
                        child: SizedBox(
                          height: expandedHeight,
                          child: NotificationListener<ToolSheetHeightRequest>(
                            onNotification: (request) {
                              if (request.height != _sheetHeightRequest) {
                                setState(
                                  () => _sheetHeightRequest = request.height,
                                );
                              }
                              return true;
                            },
                            child: _PhoneSheet(
                              library: _phoneLibrary,
                              onLibrary: (l) => _onLibrary(l, phone: true),
                              propertiesTitle: showsProperties && !showsLayers
                                  ? _propertiesTitle
                                  : null,
                              onCloseProperties: _closeProperties,
                              onLayers: _toggleLayers,
                              layersSelected: showsLayers,
                              onLayersTab: _onPhoneLayers,
                              expanded: _sheetExpanded,
                              onToggleExpanded: () => setState(
                                () => _sheetExpanded = !_sheetExpanded,
                              ),
                              // The sheet's tools rise in as the last fade, so
                              // a tab change reads as a change of page rather
                              // than as the sheet flickering.
                              child: StudioSwitcher(
                                child: KeyedSubtree(
                                  key: ValueKey(
                                    properties != null
                                        ? 'properties-${_propertiesTab?.name}'
                                        : 'library-${_phoneLibrary.name}',
                                  ),
                                  child:
                                      properties ??
                                      _libraryBody(
                                        _phoneLibrary,
                                        catalog,
                                        sub,
                                        padding: padding,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static double _propertiesSheetHeight(_EditorTab tab) => switch (tab) {
    _EditorTab.frame => 460,
    _EditorTab.layers => 480,
    _EditorTab.screenshot => 380,
    _EditorTab.caption || _EditorTab.subcaption => 360,
    _EditorTab.background => 380,
    _EditorTab.text => 440,
    _EditorTab.image => 420,
    _EditorTab.shape => 520,
  };
}
