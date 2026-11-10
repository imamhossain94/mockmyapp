import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart' show PictureInfo;
import 'package:google_fonts/google_fonts.dart';

import '../../../app/layout/studio_layout.dart';
import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../../data/assets/clipart_catalog.dart';
import '../../../data/assets/studio_fonts.dart';
import '../../../data/repositories/image_library.dart';
import '../../../data/repositories/stored_image.dart';
import '../../../domain/models/shape_spec.dart';
import '../../shared/friendly_error.dart';
import '../../shared/image_library_view.dart';
import '../../shared/save_actions.dart';
import '../../shared/widgets/widgets.dart';
import '../widgets/clipart_sheet.dart';
import '../widgets/element_library.dart';
import '../widgets/svg_shape_import.dart';
import '../widgets/font_picker_sheet.dart';
import '../widgets/hsv_color_picker.dart';
import '../widgets/scene_pick.dart';
import 'screenshot_edit_codec.dart';
import 'screenshot_edit_ops.dart';
import 'stage_transform.dart';

part 'editor_chrome.dart';
part 'editor_panels.dart';
part 'retouch_canvas.dart';

/// How far apart two luminances are, as a contrast ratio: 1 for none, 21 for
/// black on white. Three is where words start to read.
double _contrastOf(double a, double b) =>
    (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);

/// Black or white, whichever reads on [background].
Color _inkOn(Color background) => background.computeLuminance() > 0.5
    ? const Color(0xFF000000)
    : const Color(0xFFFFFFFF);

/// The photo editor's tools, in the order the tool bar shows them.
///
/// One tool at a time, each with one small panel. Everything a tool does is in
/// its panel or is a gesture on the photo it states in its hint — nothing is
/// hidden behind a second level of menus.
enum PhotoTool {
  crop('Crop', StudioIcons.crop),
  adjust('Adjust', StudioIcons.adjust),
  filters('Filters', StudioIcons.filters),
  draw('Draw', StudioIcons.draw),
  text('Text', StudioIcons.text),
  stickers('Stickers', StudioIcons.stickers),
  hide('Hide', StudioIcons.layerHidden),
  cutout('Cutout', StudioIcons.cutout);

  const PhotoTool(this.label, this.icon);

  final String label;
  final StudioIconData icon;
}

/// A selected picture's settings, one at a time in the Stickers panel.
enum _ImageProperty {
  crop('Crop', StudioIcons.crop),
  corners('Corners', StudioIcons.cornerRadius),
  border('Border', StudioIcons.border),
  borderColour('Border colour', StudioIcons.palette),
  opacity('Opacity', StudioIcons.opacity);

  const _ImageProperty(this.label, this.icon);

  final String label;
  final StudioIconData icon;
}

/// What a drag in the Draw tool lays down.
enum DrawTool {
  pen('Pen', StudioIcons.pen),
  marker('Marker', StudioIcons.marker),
  arrow('Arrow', StudioIcons.markupArrow),
  line('Line', StudioIcons.shapeLine),
  box('Box', StudioIcons.shapeRectangle),
  oval('Circle', StudioIcons.shapeCircle),
  eraser('Eraser', StudioIcons.eraser);

  const DrawTool(this.label, this.icon);

  final String label;
  final StudioIconData icon;

  MarkupKind? get markup => switch (this) {
    DrawTool.arrow => MarkupKind.arrow,
    DrawTool.line => MarkupKind.line,
    DrawTool.box => MarkupKind.box,
    DrawTool.oval => MarkupKind.oval,
    _ => null,
  };
}

/// What the Hide tool is working on: areas of the photo, or a clean bar along
/// its top or bottom edge.
enum _HidePage {
  areas('Hide areas', StudioIcons.layerHidden),
  statusBar('Status bar', StudioIcons.statusBar),
  navBar('Nav bar', StudioIcons.navBar);

  const _HidePage(this.label, this.icon);

  final String label;
  final StudioIconData icon;
}

extension on HideStyle {
  String get label => switch (this) {
    HideStyle.blur => 'Blur',
    HideStyle.pixelate => 'Pixelate',
    HideStyle.cover => 'Cover',
  };

  StudioIconData get icon => switch (this) {
    HideStyle.blur => StudioIcons.blur,
    HideStyle.pixelate => StudioIcons.pixelate,
    HideStyle.cover => StudioIcons.solidFill,
  };
}

extension on HideShape {
  String get label => switch (this) {
    HideShape.box => 'Box',
    HideShape.oval => 'Oval',
    HideShape.freehand => 'Freehand',
  };

  StudioIconData get icon => switch (this) {
    HideShape.box => StudioIcons.shapeRectangle,
    HideShape.oval => StudioIcons.shapeCircle,
    HideShape.freehand => StudioIcons.draw,
  };
}

extension on StatusBarStyle {
  String get label => switch (this) {
    StatusBarStyle.ios => 'iPhone',
    StatusBarStyle.android => 'Android',
    StatusBarStyle.samsung => 'Samsung',
  };
}

extension on NavBarStyle {
  String get label => switch (this) {
    NavBarStyle.gesture => 'Gesture',
    NavBarStyle.ios => 'iPhone',
    NavBarStyle.buttons => '3 buttons',
    NavBarStyle.samsung => 'Samsung',
  };
}

/// One slider of the Adjust tool.
enum AdjustControl {
  brightness('Brightness', StudioIcons.brightness),
  contrast('Contrast', StudioIcons.contrast),
  exposure('Exposure', StudioIcons.exposure),
  highlights('Highlights', StudioIcons.highlights),
  shadows('Shadows', StudioIcons.shadows),
  saturation('Saturation', StudioIcons.saturation),
  warmth('Warmth', StudioIcons.warmth),
  tint('Tint', StudioIcons.tint),
  fade('Fade', StudioIcons.fade),
  vignette('Vignette', StudioIcons.vignette),
  blur('Blur', StudioIcons.blur);

  const AdjustControl(this.label, this.icon);

  final String label;
  final StudioIconData icon;

  /// Fade and blur only go one way; everything else is either side of zero.
  double get min => this == fade || this == blur ? 0 : -1;

  double of(ImageAdjustments a) => switch (this) {
    brightness => a.brightness,
    contrast => a.contrast,
    exposure => a.exposure,
    highlights => a.highlights,
    shadows => a.shadows,
    saturation => a.saturation,
    warmth => a.warmth,
    tint => a.tint,
    fade => a.fade,
    vignette => a.vignette,
    blur => a.blur,
  };

  ImageAdjustments set(ImageAdjustments a, double v) => switch (this) {
    brightness => a.copyWith(brightness: v),
    contrast => a.copyWith(contrast: v),
    exposure => a.copyWith(exposure: v),
    highlights => a.copyWith(highlights: v),
    shadows => a.copyWith(shadows: v),
    saturation => a.copyWith(saturation: v),
    warmth => a.copyWith(warmth: v),
    tint => a.copyWith(tint: v),
    fade => a.copyWith(fade: v),
    vignette => a.copyWith(vignette: v),
    blur => a.copyWith(blur: v),
  };
}

/// What a finished edit hands back: the flattened picture, and the recipe
/// that made it.
///
/// Two values rather than one because they serve different readers. [path] is
/// what the scene draws and the export ships — a plain PNG, so nothing
/// downstream has to know ops exist. [edit] is what lets the editor be opened
/// again on the same picture and find its sliders, filter and objects rather
/// than pixels.
@immutable
class ScreenshotEditResult {
  const ScreenshotEditResult({
    required this.path,
    required this.edit,
    this.size,
  });

  final String path;

  /// The picture's size in pixels, for a caller whose box should follow the
  /// crop's new shape — an image layer.
  final Size? size;

  /// Null when there is nothing worth reopening — see `_apply`.
  final Map<String, dynamic>? edit;
}

/// Opens the photo editor and returns the flattened result, or null if the
/// user cancelled.
///
/// [screenAspect] is the device screen's width/height: the crop starts locked
/// to it so what the user edits is exactly what lands inside the frame. Null
/// for a picture with no frame to fill — an image layer — which starts at its
/// own shape instead.
///
/// [edit] is a recipe from a previous pass, if this picture came from one.
/// Given it, the editor opens the *source* and replays it, so the objects are
/// objects and the sliders are where they were left.
///
/// [statusBarStyle] offers the clean-status-bar fix, drawn as that phone's
/// bar; null for a picture that is not a phone screenshot.
Future<ScreenshotEditResult?> showScreenshotEditor(
  BuildContext context, {
  required String imagePath,
  double? screenAspect,
  required String? projectId,
  String deviceLabel = 'Device screen',
  Map<String, dynamic>? edit,
  StatusBarStyle? statusBarStyle,
}) {
  return Navigator.of(context).push<ScreenshotEditResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ScreenshotEditorScreen(
        imagePath: imagePath,
        screenAspect: screenAspect,
        projectId: projectId,
        deviceLabel: deviceLabel,
        edit: edit,
        statusBarStyle: statusBarStyle,
      ),
    ),
  );
}

/// The photo editor: crop, adjust, filter, draw, write, decorate, hide and
/// cut out — one screen for everything a screenshot or a backdrop photo needs
/// before it goes into a listing.
class ScreenshotEditorScreen extends ConsumerStatefulWidget {
  const ScreenshotEditorScreen({
    super.key,
    required this.imagePath,
    required this.screenAspect,
    required this.projectId,
    this.edit,
    this.deviceLabel = 'Device screen',
    this.statusBarStyle,
  });

  final String imagePath;
  final double? screenAspect;

  /// The project the edited result is imported back into, so it lands in that
  /// project's library rather than everyone's.
  final String? projectId;

  /// A recipe from a previous pass; see [showScreenshotEditor].
  final Map<String, dynamic>? edit;

  final String deviceLabel;
  final StatusBarStyle? statusBarStyle;

  @override
  ConsumerState<ScreenshotEditorScreen> createState() =>
      _ScreenshotEditorScreenState();
}

/// Everything an undo puts back, in one value.
///
/// A snapshot of the whole edit rather than of the op list alone: a crop, a
/// straighten, a filter and a slider are edits too, and an undo that skipped
/// them — as the retoucher's did — undid the stroke before the slider the user
/// had just moved.
@immutable
class _EditState {
  const _EditState({
    required this.crop,
    required this.orientation,
    required this.ops,
    required this.adjust,
    required this.expand,
    required this.fill,
    required this.fillColor,
    required this.aspectOverride,
    required this.cropLocked,
  });

  final Rect crop;
  final ImageOrientation orientation;
  final List<EditOp> ops;
  final ImageAdjustments adjust;
  final bool expand;
  final ExpandFill fill;
  final Color fillColor;
  final double? aspectOverride;
  final bool cropLocked;

  bool sameAs(_EditState o) =>
      o.crop == crop &&
      o.orientation == orientation &&
      identical(o.ops, ops) &&
      o.adjust == adjust &&
      o.expand == expand &&
      o.fill == fill &&
      o.fillColor == fillColor &&
      o.aspectOverride == aspectOverride &&
      o.cropLocked == cropLocked;
}

/// What the eyedropper's next tap is picking a colour for.
enum _PickFor { draw, cover, text, object, statusBar, navBar }

class _ScreenshotEditorScreenState
    extends ConsumerState<ScreenshotEditorScreen> {
  ui.Image? _image;
  PixelSampler? _sampler;
  Object? _loadError;

  // ---------------------------------------------------------------------------
  // The edit — everything in [_EditState]
  // ---------------------------------------------------------------------------

  Rect _crop = const Rect.fromLTRB(0, 0, 1, 1);

  /// How the capture is turned. Everything else in this screen — the crop, the
  /// strokes, the redactions — is stated against the turned result, so this is
  /// read wherever the image's own dimensions used to be.
  ImageOrientation _orientation = ImageOrientation.none;
  List<EditOp> _ops = const [];
  ImageAdjustments _adjust = const ImageAdjustments();

  /// Whether the crop may be pulled outside the artwork, generating the
  /// surplus rather than refusing the drag.
  bool _expand = false;
  ExpandFill _fill = ExpandFill.edge;
  Color _fillColor = const Color(0xFF000000);

  /// A ratio the user picked instead of the frame's own. Null means the frame
  /// decides, which is the default and the right answer nearly always: the
  /// crop exists to fill a phone screen.
  double? _aspectOverride;

  /// Whether corner drags keep the ratio. Off is the Free chip.
  bool _cropLocked = true;

  _EditState get _state => _EditState(
    crop: _crop,
    orientation: _orientation,
    ops: _ops,
    adjust: _adjust,
    expand: _expand,
    fill: _fill,
    fillColor: _fillColor,
    aspectOverride: _aspectOverride,
    cropLocked: _cropLocked,
  );

  void _restoreState(_EditState s) {
    _crop = s.crop;
    _orientation = s.orientation;
    _ops = s.ops;
    _adjust = s.adjust;
    _expand = s.expand;
    _fill = s.fill;
    _fillColor = s.fillColor;
    _aspectOverride = s.aspectOverride;
    _cropLocked = s.cropLocked;
  }

  // ---------------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------------

  final List<_EditState> _undo = [];
  final List<_EditState> _redo = [];

  /// The state a continuous change — a slider, a crop drag — started from,
  /// until it ends and becomes one undo step.
  _EditState? _liveStart;

  /// Marks the start of a discrete change.
  void _record() {
    _flushLive();
    _undo.add(_state);
    _redo.clear();
  }

  /// Marks a continuous change as under way. Idempotent: every frame of a
  /// drag may call it, and only the first one counts.
  void _beginLive() => _liveStart ??= _state;

  /// Closes a continuous change as one undo step, if it changed anything.
  void _flushLive() {
    final start = _liveStart;
    if (start == null) return;
    _liveStart = null;
    if (!start.sameAs(_state)) {
      _undo.add(start);
      _redo.clear();
    }
  }

  bool get _dirty => _undo.isNotEmpty || _liveStart != null;

  void _undoOnce() {
    _flushLive();
    if (_undo.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _redo.add(_state);
      _restoreState(_undo.removeLast());
      _draft = null;
      _objectDraft = null;
    });
  }

  void _redoOnce() {
    _flushLive();
    if (_redo.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _undo.add(_state);
      _restoreState(_redo.removeLast());
      _draft = null;
      _objectDraft = null;
    });
  }

  /// Replaces the op list as one undo step.
  void _commit(List<EditOp> next) {
    setState(() {
      _record();
      _ops = next;
      _draft = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Tools
  // ---------------------------------------------------------------------------

  /// The open tool, or null for none — the tool bar alone, and the photo as
  /// large as it goes.
  PhotoTool? _tool;

  /// Whether the Text tool's swatches set the box or outline colour rather
  /// than the letters'. Only means anything for a look that has one.
  bool _textAccent = false;

  DrawTool _drawTool = DrawTool.pen;

  /// Paint colours, not chrome — literal on purpose.
  Color _drawColor = const Color(0xFFEF4444);
  double _drawWidth = 0.012;

  _HidePage _hidePage = _HidePage.areas;
  HideStyle _hideStyle = HideStyle.blur;
  HideShape _hideShape = HideShape.box;
  double _blurStrength = 0.03;
  double _pixelSize = 0.035;
  Color _coverColor = const Color(0xFF000000);

  /// The path of a freehand Hide drag in flight, which its area is drawn
  /// round.
  final List<Offset> _lasso = [];

  AdjustControl _adjustControl = AdjustControl.brightness;

  /// The eyedropper, armed: the next tap on the photo picks a colour for this.
  _PickFor? _picking;

  /// Held down: the photo as it was, for comparison.
  bool _comparing = false;

  /// Live op being dragged out, painted on top of [_ops] but not committed
  /// until the gesture ends — so a cancelled drag leaves no undo entry.
  EditOp? _draft;

  /// Ops the eraser has passed over during the drag in flight.
  final Set<EditOp> _erasing = Set.identity();

  bool _saving = false;
  bool _removingBackground = false;

  /// Decoded textures for every placed image, keyed by library path.
  ///
  /// One decode per file however many times it is placed, and one owner for the
  /// dispose. An op cannot own its pixels: the same instance is carried by
  /// reference into every history snapshot, so freeing per occurrence would
  /// double-free.
  ///
  /// Entries are held for the life of the screen rather than reference-counted
  /// against `_ops`, because undo can bring a dropped op back — nothing any
  /// snapshot still refers to is ever safe to free early.
  final Map<String, ui.Image> _placedImages = {};

  /// Loaded sticker art, keyed by catalog id. Same borrow-never-own rule as
  /// [_placedImages], and the same single owner for the dispose.
  final Map<String, PictureInfo> _stickerArt = {};

  /// Source of [PlacedOp.id]. Monotonic and session-scoped.
  int _nextOpId = 1;

  /// The placed object being worked on, by id. Resolved lazily against the
  /// op list, so undoing past an object's creation hides its chrome and a redo
  /// brings the same selection back.
  int? _selectedId;

  /// A placed object mid-transform, substituted for its committed self while
  /// the gesture runs, so a drag is one undo entry rather than one per frame.
  PlacedOp? _objectDraft;

  /// A small render of the cropped photo, for the filter swatches, and the
  /// crop and turn it was made for.
  ui.Image? _thumb;
  (Rect, ImageOrientation)? _thumbFor;

  /// The op list as the canvas should draw it: the draft in the dragged
  /// object's own place, never on top of the stack, and anything the eraser
  /// is passing over already gone.
  List<EditOp> get _visibleOps {
    final draft = _objectDraft;
    return [
      for (final op in _ops)
        if (_erasing.contains(op))
          ...const <EditOp>[]
        else if (draft != null && op is PlacedOp && op.id == draft.id)
          draft
        else
          op,
    ];
  }

  PlacedOp? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final op in _visibleOps) {
      if (op is PlacedOp && op.id == id) return op;
    }
    return null;
  }

  /// The shape the frame would have the picture be.
  double get _frameAspect {
    final aspect = widget.screenAspect;
    if (aspect != null && aspect.isFinite && aspect > 0) return aspect;
    final image = _image;
    if (image == null) return 0.46;
    final size = _orientedSizeOf(image);
    return size.width / size.height;
  }

  double get _targetAspect => _aspectOverride ?? _frameAspect;

  /// What the Crop tool's own-shape chip is called.
  String get _frameLabel => widget.screenAspect == null ? 'Original' : 'Screen';

  /// The workspace's eyedropper channel, held so [dispose] can restore it.
  ///
  /// This screen is pushed full-screen over the editor, which stays mounted
  /// underneath and so goes on advertising a canvas nobody can see. Its own
  /// colour picker would then offer to sample it and appear to do nothing, so
  /// the offer is withdrawn while this screen covers it.
  late final ScenePickController _scenePick;

  final FocusNode _keys = FocusNode(debugLabel: 'photo editor');

  @override
  void initState() {
    super.initState();
    _scenePick = ref.read(scenePickProvider.notifier);
    _scenePick.suppress();
    _load();
  }

  @override
  void dispose() {
    _scenePick.unsuppress();
    _keys.dispose();
    _sampler?.dispose();
    _image?.dispose();
    _thumb?.dispose();
    for (final texture in _placedImages.values) {
      texture.dispose();
    }
    for (final art in _stickerArt.values) {
      art.picture.dispose();
    }
    // Cutout masks are full-resolution images living in the op snapshots, and
    // one op sits in many snapshots — swept by identity, so each is freed
    // exactly once.
    final freed = Set<Object>.identity();
    for (final state in [_state, ..._undo, ..._redo, ?_liveStart]) {
      for (final op in state.ops.whereType<RemoveBackgroundOp>()) {
        if (freed.add(op.mask)) op.mask.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // The recipe's source, not the flattened result. Replaying the edit over
      // the flattened picture would paint a second copy of it on top.
      final recipe = widget.edit;
      final from = recipe?['source'] as String? ?? widget.imagePath;

      final bytes = await StoredImage.bytes(from);
      if (bytes == null) throw StateError('that picture is not readable');
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      final sampler = PixelSampler(frame.image);
      setState(() {
        _image = frame.image;
        _sampler = sampler;
        _crop = coverCrop(
          imageAspect: frame.image.width / frame.image.height,
          aspect: _targetAspect,
        );
      });

      if (recipe != null) await _restore(recipe, frame.image);
      // Only needed by the eyedropper, the mosaic and the one-tap fixes, so it
      // must not hold up first paint.
      await sampler.prepare();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  /// Puts a stored recipe back on the canvas.
  ///
  /// Every op that carries something loadable — a placed image's texture, a
  /// sticker's art — is rebuilt through the same banks placement uses, so a
  /// file used twice is decoded once and the dispose still has one owner.
  Future<void> _restore(Map<String, dynamic> recipe, ui.Image image) async {
    final catalog = await ref.read(clipartCatalogProvider.future);
    if (!mounted) return;
    _clipart = catalog;

    final orientation = ImageOrientation(
      turns: (recipe['turns'] as num?)?.toInt() ?? 0,
    );
    final edit = await screenshotEditFromJson(
      recipe,
      imageSize: orientation.sizeOf(
        Size(image.width.toDouble(), image.height.toDouble()),
      ),
      texture: (source) async {
        final held = _placedImages[source];
        if (held != null) return held;
        final loaded = await loadPlacedTexture(source);
        if (loaded != null) _placedImages[source] = loaded;
        return loaded;
      },
      sticker: (id) async {
        final held = _stickerArt[id];
        if (held != null) return (held.picture, held.size);
        final sticker = catalog.byId(id);
        if (sticker == null) return null;
        final info = await loadStickerPicture(sticker);
        _stickerArt[id] = info;
        return (info.picture, info.size);
      },
    );
    if (edit == null || !mounted) return;

    setState(() {
      _crop = edit.crop;
      _orientation = edit.orientation;
      _adjust = edit.adjustments;
      _fill = edit.fill;
      _fillColor = edit.fillColor;
      _expand = _outside(edit.crop);
      _ops = edit.ops;
      // Past every id already in use, so a new object cannot collide with a
      // restored one — ids are what selection is keyed on.
      _nextOpId =
          edit.ops.whereType<PlacedOp>().fold(
            0,
            (highest, op) => math.max(highest, op.id),
          ) +
          1;
    });
  }

  static bool _outside(Rect crop) =>
      crop.left < -1e-6 ||
      crop.top < -1e-6 ||
      crop.right > 1 + 1e-6 ||
      crop.bottom > 1 + 1e-6;

  // ---------------------------------------------------------------------------
  // Geometry
  // ---------------------------------------------------------------------------

  /// The decoded capture as the user is looking at it. A quarter turn stands
  /// it on its side, and every rect on this screen is a fraction of *this*.
  Size _orientedSizeOf(ui.Image image) => _orientation.sizeOf(
    Size(image.width.toDouble(), image.height.toDouble()),
  );

  Size get _frameSize {
    final image = _image;
    return image == null ? Size.zero : _orientedSizeOf(image);
  }

  /// The middle of the finished picture, normalised — where new things land.
  Offset get _viewCentre => _crop.center;

  /// The colour of the photo under [normalised], or null before the pixels are
  /// read.
  Color? _colourAt(Offset normalised) =>
      _sampler?.at(_orientation.toSource(normalised, frame: _frameSize));

  // ---------------------------------------------------------------------------
  // Crop and turn
  // ---------------------------------------------------------------------------

  /// Re-fits the crop to [aspect], or back to the frame's own when null.
  void _setAspect(double? aspect) {
    final image = _image;
    if (image == null) return;
    setState(() {
      _record();
      _aspectOverride = aspect;
      final size = _orientedSizeOf(image);
      _crop = coverCrop(
        imageAspect: size.width / size.height,
        aspect: _targetAspect,
      );
      _cropLocked = true;
    });
    HapticFeedback.selectionClick();
  }

  void _setFreeCrop() {
    if (!_cropLocked) return;
    setState(() {
      _record();
      _cropLocked = false;
    });
    HapticFeedback.selectionClick();
  }

  /// Turns the capture and re-fits the crop. The crop is rebuilt rather than
  /// carried across: a quarter turn swaps the aspect it was solved against.
  void _reorient(ImageOrientation next) {
    final image = _image;
    if (image == null) return;
    final refit = next.turns != _orientation.turns;
    setState(() {
      _record();
      _orientation = next;
      if (refit) {
        final size = _orientedSizeOf(image);
        _crop = coverCrop(
          imageAspect: size.width / size.height,
          aspect: _targetAspect,
        );
        _cropLocked = true;
      }
    });
    HapticFeedback.selectionClick();
  }

  void _straighten(double degrees) {
    _beginLive();
    setState(() => _orientation = _orientation.copyWith(angle: degrees));
  }

  void _resetCrop() {
    final image = _image;
    if (image == null) return;
    setState(() {
      _record();
      _orientation = ImageOrientation.none;
      _aspectOverride = null;
      final size = _orientedSizeOf(image);
      _crop = coverCrop(
        imageAspect: size.width / size.height,
        aspect: _targetAspect,
      );
      _expand = false;
      _cropLocked = true;
    });
  }

  void _setExpand(bool on) {
    setState(() {
      _record();
      _expand = on;
      // Leaving expand mode has to pull the crop back inside, or the canvas
      // would keep showing generated pixels the maths no longer allows.
      if (!on) _crop = clampCrop(_crop);
    });
  }

  // ---------------------------------------------------------------------------
  // Adjust and filters
  // ---------------------------------------------------------------------------

  void _setAdjust(ImageAdjustments next) {
    _beginLive();
    setState(() => _adjust = next);
  }

  void _setAdjustNow(ImageAdjustments next) {
    setState(() {
      _record();
      _adjust = next;
    });
  }

  void _autoEnhance() {
    final auto = _sampler?.autoEnhance();
    if (auto == null) {
      showStudioSnack(
        context,
        _sampler?.isReady ?? false
            ? 'This photo already looks balanced'
            : 'Still reading the photo — try again in a moment',
      );
      return;
    }
    HapticFeedback.mediumImpact();
    _setAdjustNow(
      auto.copyWith(look: _adjust.look, lookStrength: _adjust.lookStrength),
    );
  }

  /// Renders the swatch the filter strip shows every look on, when the crop or
  /// the turn has moved since the last one.
  Future<void> _prepareThumb() async {
    final image = _image;
    if (image == null) return;
    final key = (_crop, _orientation);
    if (_thumbFor == key && _thumb != null) return;
    final composer = ScreenshotComposer(
      image: image,
      crop: _crop,
      ops: const [],
      orientation: _orientation,
      fill: _fill,
      fillColor: _fillColor,
    );
    final full = composer.exportSize;
    const target = 160.0;
    final scale = target / math.max(full.width, full.height);
    final size = Size(
      math.max(1, (full.width * scale).roundToDouble()),
      math.max(1, (full.height * scale).roundToDouble()),
    );
    final recorder = ui.PictureRecorder();
    composer.paint(Canvas(recorder), Offset.zero & size);
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(
      size.width.round(),
      size.height.round(),
    );
    picture.dispose();
    if (!mounted) {
      rendered.dispose();
      return;
    }
    setState(() {
      _thumb?.dispose();
      _thumb = rendered;
      _thumbFor = key;
    });
  }

  // ---------------------------------------------------------------------------
  // Drawing, hiding and the eyedropper
  // ---------------------------------------------------------------------------

  void _paintStart(Offset normalised) {
    final picking = _picking;
    if (picking != null) {
      _pickColour(picking, normalised);
      return;
    }
    switch (_tool) {
      case PhotoTool.draw:
        final markup = _drawTool.markup;
        if (_drawTool == DrawTool.eraser) {
          _eraseAt(normalised);
        } else if (markup != null) {
          setState(
            () => _draft = MarkupOp(
              kind: markup,
              start: normalised,
              end: normalised,
              color: _drawColor,
              width: _drawWidth,
            ),
          );
        } else {
          setState(
            () => _draft = BrushOp(
              points: [normalised],
              color: _drawColor,
              width: _drawTool == DrawTool.marker
                  ? _drawWidth * 2.4
                  : _drawWidth,
              marker: _drawTool == DrawTool.marker,
            ),
          );
        }
      case PhotoTool.hide:
        _lasso
          ..clear()
          ..add(normalised);
        setState(() => _draft = _hideDraft(normalised, normalised));
      default:
        break;
    }
  }

  void _paintUpdate(Offset normalised, Offset start) {
    if (_picking != null) {
      _pickColour(_picking!, normalised);
      return;
    }
    final current = _draft;
    switch (_tool) {
      case PhotoTool.draw:
        if (_drawTool == DrawTool.eraser) {
          _eraseAt(normalised);
        } else if (current is BrushOp) {
          setState(() => _draft = current.extend(normalised));
        } else if (current is MarkupOp) {
          setState(() => _draft = current.withEnd(normalised));
        }
      case PhotoTool.hide:
        // Thinned: a point for every pointer event is hundreds for a slow
        // circle, and the outline is saved with the edit.
        if ((normalised - _lasso.last).distance > 0.002) _lasso.add(normalised);
        setState(() => _draft = _hideDraft(start, normalised));
      default:
        break;
    }
  }

  /// The area a Hide drag from [a] to [b] draws — or, freehand, the area
  /// round the path the finger took.
  ///
  /// Id 0 until it is kept: a drag given up on should not use one up.
  HideOp _hideDraft(Offset a, Offset b) {
    final style = _hideStyle;
    final area = HideOp(
      id: 0,
      center: a,
      width: 0,
      height: 0,
      style: style,
      shape: _hideShape,
      blur: _blurStrength,
      block: _pixelSize,
      color: _coverColor,
      cornerRadius: style == HideStyle.cover ? 0.006 : 0,
    );
    return _hideShape == HideShape.freehand
        ? area.around(_lasso, _frameSize)
        : area.over(Rect.fromPoints(a, b), _frameSize);
  }

  /// Turns Hide to [page]. A bar has no area to keep hold of, so the one
  /// selected is let go.
  void _setHidePage(_HidePage page) {
    if (_hidePage == page) return;
    setState(() {
      _hidePage = page;
      _picking = null;
      if (page != _HidePage.areas) _selectedId = null;
    });
  }

  /// How the next area hides what it covers — and the selected one, now.
  void _setHideStyle(HideStyle style) {
    final area = _selected;
    setState(() => _hideStyle = style);
    if (area is HideOp && area.style != style) {
      _editSelected((o) => o is HideOp ? o.copyWith(style: style) : o);
    }
  }

  /// The outline the next area is drawn with. A box or an oval reshapes the
  /// selected area too; freehand has to be drawn, so picking it lets go of the
  /// selection, ready to draw one.
  void _setHideShape(HideShape shape) {
    final area = _selected;
    setState(() {
      _hideShape = shape;
      if (shape == HideShape.freehand) _selectedId = null;
    });
    if (shape != HideShape.freehand && area is HideOp && area.shape != shape) {
      _editSelected(
        (o) => o is HideOp ? o.copyWith(shape: shape, outline: const []) : o,
      );
    }
  }

  /// A Hide slider moved: the strength of the next area, and of the selected
  /// one as the slider goes — one undo step for the drag.
  void _setHideStrength({double? blur, double? block}) {
    setState(() {
      if (blur != null) _blurStrength = blur;
      if (block != null) _pixelSize = block;
    });
    if (_selected is HideOp) {
      _editSelectedLive(
        (o) => o is HideOp ? o.copyWith(blur: blur, block: block) : o,
      );
    }
  }

  void _setCoverColour(Color colour) {
    setState(() => _coverColor = colour);
    if (_selected is HideOp) _recolourSelected(colour);
  }

  /// Drops the draft without touching the undo stack.
  void _paintCancel() {
    if (_draft == null && _erasing.isEmpty) return;
    setState(() {
      _draft = null;
      _erasing.clear();
    });
  }

  void _paintEnd() {
    if (_picking != null) {
      setState(() => _picking = null);
      return;
    }
    if (_erasing.isNotEmpty) {
      final gone = Set<EditOp>.identity()..addAll(_erasing);
      _erasing.clear();
      _commit([
        for (final op in _ops)
          if (!gone.contains(op)) op,
      ]);
      HapticFeedback.selectionClick();
      return;
    }
    final draft = _draft;
    if (draft == null) return;
    // A tap rather than a drag leaves an area or a shape with no size — an
    // invisible op, and an undo entry for something that never appeared.
    final tiny = switch (draft) {
      HideOp(:final width, :final height, :final shape, :final isFreehand) =>
        width < 0.004 ||
            height < 0.004 ||
            (shape == HideShape.freehand && !isFreehand),
      MarkupOp(:final start, :final end) => (end - start).distance < 0.006,
      _ => false,
    };
    if (tiny) {
      setState(() => _draft = null);
      return;
    }
    if (draft is HideOp) {
      // Kept selected, so it can be nudged onto what it was for, stretched
      // or restyled straight away.
      final area = draft.withId(_nextOpId++);
      _commit([..._ops, area]);
      setState(() => _selectedId = area.id);
    } else {
      _commit([..._ops, draft]);
    }
    HapticFeedback.selectionClick();
  }

  /// Marks every stroke and markup under [normalised] for erasing.
  void _eraseAt(Offset normalised) {
    final size = _frameSize;
    if (size.isEmpty) return;
    Offset px(Offset n) => Offset(n.dx * size.width, n.dy * size.height);
    final at = px(normalised);
    final reach = math.max(12.0, size.width * 0.02);

    double toSegment(Offset p, Offset a, Offset b) {
      final ab = b - a;
      final length = ab.distanceSquared;
      if (length == 0) return (p - a).distance;
      final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / length).clamp(
        0.0,
        1.0,
      );
      return (p - (a + ab * t)).distance;
    }

    var changed = false;
    for (final op in _ops) {
      if (_erasing.contains(op)) continue;
      final hit = switch (op) {
        BrushOp(:final points, :final width) => () {
          final slack = reach + width * size.width / 2;
          if (points.length == 1) {
            return (px(points.first) - at).distance < slack;
          }
          for (var i = 1; i < points.length; i++) {
            if (toSegment(at, px(points[i - 1]), px(points[i])) < slack) {
              return true;
            }
          }
          return false;
        }(),
        MarkupOp(:final start, :final end, :final kind, :final width) => () {
          final slack = reach + width * size.width / 2;
          final a = px(start), b = px(end);
          if (kind == MarkupKind.arrow || kind == MarkupKind.line) {
            return toSegment(at, a, b) < slack;
          }
          final r = Rect.fromPoints(a, b);
          // The outline, not the inside: a box is erased by rubbing its edge.
          return r.inflate(slack).contains(at) &&
              !r.deflate(slack).contains(at);
        }(),
        _ => false,
      };
      if (hit) {
        _erasing.add(op);
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  void _pickColour(_PickFor target, Offset normalised) {
    final picked = _colourAt(normalised);
    if (picked == null) return;
    setState(() {
      switch (target) {
        case _PickFor.draw:
          _drawColor = picked;
        case _PickFor.cover:
          _coverColor = picked;
        case _PickFor.text:
        case _PickFor.object:
        case _PickFor.statusBar:
        case _PickFor.navBar:
          break;
      }
    });
    switch (target) {
      case _PickFor.text:
        _styleText((o) => _recolourText(o, picked));
      case _PickFor.object:
        _recolourSelected(picked);
      case _PickFor.cover:
        // The area being worked on takes it as well as the next one drawn.
        if (_selected is HideOp) _recolourSelected(picked);
      case _PickFor.statusBar:
        _editOp<StatusBarOp>(
          (bar) => bar.copyWith(background: picked, foreground: _inkOn(picked)),
        );
      case _PickFor.navBar:
        _editOp<NavBarOp>(
          (bar) => bar.copyWith(background: picked, foreground: _inkOn(picked)),
        );
      case _PickFor.draw:
        break;
    }
  }

  void _armPicker(_PickFor target) {
    HapticFeedback.selectionClick();
    setState(() => _picking = _picking == target ? null : target);
  }

  // ---------------------------------------------------------------------------
  // The one-tap fixes
  // ---------------------------------------------------------------------------

  /// Rewrites every op of type [T] in place — there is one of each bar.
  ///
  /// [live] for a slider: one undo step for the whole drag, taken when it
  /// ends.
  void _editOp<T extends EditOp>(T Function(T op) update, {bool live = false}) {
    final next = [
      for (final op in _ops)
        if (op is T) update(op) else op,
    ];
    if (!live) {
      _commit(next);
      return;
    }
    _beginLive();
    setState(() => _ops = next);
  }

  StatusBarOp? get _statusBar => _ops.whereType<StatusBarOp>().firstOrNull;
  NavBarOp? get _navBar => _ops.whereType<NavBarOp>().firstOrNull;

  /// The finished picture's width in pixels, which a bar's height is a
  /// fraction of.
  double get _pictureWidth => _crop.width * _frameSize.width;

  /// Draws a clean status bar in [style] over the captured one — or, with
  /// one already there, redraws it in [style].
  void _setStatusBar(StatusBarStyle style) {
    final current = _statusBar;
    if (current != null) {
      if (current.style != style) {
        _editOp<StatusBarOp>((bar) => bar.copyWith(style: style));
      }
      return;
    }
    final size = _frameSize;
    if (_image == null || size.isEmpty || _pictureWidth <= 0) return;
    // The captured bar, measured from its row of clock and icons as a share
    // of the capture's height, and turned into the bar's own measure.
    final sampler = _sampler;
    final measured = sampler != null && sampler.isReady
        ? sampler.statusBarHeight(fallback: 0)
        : 0.0;
    final top = _crop.top.clamp(0.0, 1.0);
    final double height;
    if (measured > 0) {
      final bottom = math.max(measured, top + measured * 0.6);
      height = (bottom - top) * size.height / _pictureWidth;
    } else {
      height = style.height;
    }
    // The bar's own colour, from its middle: an iPhone's is empty there, and
    // an Android phone's is between the clock and the icons.
    final background =
        _colourAt(
          Offset(
            _crop.center.dx,
            top + height * _pictureWidth / size.height * 0.5,
          ),
        ) ??
        const Color(0xFFFFFFFF);
    _commit([
      for (final op in _ops)
        if (op is! StatusBarOp) op,
      StatusBarOp(
        height: height,
        background: background,
        foreground: _inkOn(background),
        style: style,
      ),
    ]);
    HapticFeedback.mediumImpact();
  }

  void _removeStatusBar() => _commit([
    for (final op in _ops)
      if (op is! StatusBarOp) op,
  ]);

  /// Draws a navigation bar in [style] along the bottom — or, with one
  /// already there, redraws it in [style] at that style's height.
  void _setNavBar(NavBarStyle style) {
    final current = _navBar;
    if (current != null) {
      if (current.style != style) {
        _editOp<NavBarOp>(
          (bar) => bar.copyWith(
            style: style,
            height: style.height,
            // The home indicator sits over the app; see [_underNavBar].
            background: style == NavBarStyle.ios
                ? const Color(0x00000000)
                : (bar.background.a == 0 ? _underNavBar(style) : null),
          ),
        );
      }
      return;
    }
    if (_image == null) return;
    final under = _underNavBar(style);
    _commit([
      for (final op in _ops)
        if (op is! NavBarOp) op,
      NavBarOp(
        height: style.height,
        style: style,
        // An iPhone's home indicator is drawn over the app, not on a bar; the
        // others on a bar the colour of whatever is along the bottom now.
        background: style == NavBarStyle.ios ? const Color(0x00000000) : under,
        foreground: _inkOn(under),
      ),
    ]);
    HapticFeedback.mediumImpact();
  }

  /// The colour along the bottom of the picture, where a bar in [style] goes
  /// — read near the left edge, clear of any buttons the capture already has.
  Color _underNavBar(NavBarStyle style) {
    final size = _frameSize;
    final band = size.isEmpty
        ? 0.0
        : style.height * _pictureWidth / size.height;
    return _colourAt(
          Offset(
            _crop.left + _crop.width * 0.05,
            _crop.bottom.clamp(0.0, 1.0) - band * 0.5,
          ),
        ) ??
        const Color(0xFFFFFFFF);
  }

  void _removeNavBar() => _commit([
    for (final op in _ops)
      if (op is! NavBarOp) op,
  ]);

  /// Erases the flat page behind the subject. Any previous removal is replaced
  /// rather than stacked, so repeated taps never double-feather the edge.
  Future<void> _removeBackground() async {
    final image = _image;
    if (image == null || _removingBackground) return;
    setState(() => _removingBackground = true);
    try {
      final mask = await buildBorderFloodMask(image);
      if (!mounted) return;
      _commit([
        ..._ops.where((op) => op is! RemoveBackgroundOp),
        RemoveBackgroundOp(mask: mask, tolerance: 90),
      ]);
      HapticFeedback.mediumImpact();
    } finally {
      if (mounted) setState(() => _removingBackground = false);
    }
  }

  bool get _hasCutout => _ops.any((op) => op is RemoveBackgroundOp);

  void _restoreBackground() => _commit([
    for (final op in _ops)
      if (op is! RemoveBackgroundOp) op,
  ]);

  // ---------------------------------------------------------------------------
  // Objects: text, shapes, clip art, images
  // ---------------------------------------------------------------------------

  /// Rewrites the selected object in place, as one undo entry.
  void _editSelected(PlacedOp Function(PlacedOp) update) {
    final current = _selected;
    if (current == null) return;
    _commit([
      for (final op in _ops)
        if (op is PlacedOp && op.id == current.id) update(op) else op,
    ]);
  }

  /// The same, for a continuous control — one undo step for the whole drag.
  void _editSelectedLive(PlacedOp Function(PlacedOp) update) {
    final current = _selected;
    if (current == null) return;
    _beginLive();
    setState(() {
      _ops = [
        for (final op in _ops)
          if (op is PlacedOp && op.id == current.id) update(op) else op,
      ];
    });
  }

  void _deleteSelected() {
    final current = _selected;
    if (current == null) return;
    _commit([
      for (final op in _ops)
        if (!(op is PlacedOp && op.id == current.id)) op,
    ]);
    setState(() => _selectedId = null);
  }

  void _duplicateSelected() {
    final current = _selected;
    if (current == null) return;
    final id = _nextOpId++;
    final copy = current
        .withPlacement(center: current.center + const Offset(0.04, 0.03))
        .withId(id);
    _commit([..._ops, copy]);
    setState(() => _selectedId = id);
  }

  /// Moves the selected object to one end of the stack.
  void _restackSelected({required bool toFront}) {
    final current = _selected;
    if (current == null) return;
    final rest = [
      for (final op in _ops)
        if (!(op is PlacedOp && op.id == current.id)) op,
    ];
    _commit(toFront ? [...rest, current] : [current, ...rest]);
  }

  void _flipSelected() => _editSelected(
    (o) => switch (o) {
      ImageOp() => o.copyWith(flipH: !o.flipH),
      StickerOp() => o.copyWith(flipH: !o.flipH),
      _ => o,
    },
  );

  void _recolourSelected(Color colour) => _editSelected(
    (o) => switch (o) {
      // Stroke follows the fill, as it does when a shape is first created: an
      // open shape has no interior, so a fill-only change would leave a line
      // the colour it started as.
      ShapeOp() => o.copyWith(
        spec: o.spec.copyWith(fill: colour, strokeColor: colour),
      ),
      StickerOp() => o.copyWith(tint: colour),
      TextOp() => o.copyWith(color: colour),
      // A picture's colour is its rim's; picking one for a picture with no
      // rim gives it one.
      ImageOp() => o.copyWith(
        borderColor: colour,
        borderWidth: o.borderWidth > 0
            ? null
            : math.min(o.width, o.height) * 0.04,
      ),
      HideOp() => o.copyWith(color: colour),
    },
  );

  /// Adds [op], selected, and opens the tool it belongs to.
  void _place(PlacedOp op, PhotoTool tool) {
    _commit([..._ops, op]);
    setState(() {
      _selectedId = op.id;
      _tool = tool;
    });
  }

  /// The Elements library — every shape, badge, callout and icon the main
  /// editor has — and the one chosen placed on the photo.
  ///
  /// The same library, not a smaller one of its own: the photo editor used to
  /// offer sixteen shapes, and everything else a screen could have was a trip
  /// back to the main editor.
  Future<void> _placeElement() async {
    if (_image == null) return;
    final height = math.min(600.0, MediaQuery.sizeOf(context).height * 0.72);
    final choice = await showStudioSheet<(ShapeSpec?, String?)>(
      context,
      title: 'Elements',
      child: Builder(
        builder: (sheet) => SizedBox(
          height: height,
          child: ElementLibrary(
            padding: EdgeInsets.symmetric(horizontal: StudioSpace.xl),
            onPick: (spec) => Navigator.pop(sheet, (spec, null)),
            onDraw: () => Navigator.pop(sheet, (null, 'draw')),
            onImportSvg: () => Navigator.pop(sheet, (null, 'svg')),
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case (final ShapeSpec spec, _):
        _placeShapeSpec(spec);
      case (_, 'draw'):
        // The Draw tool is this editor's pen.
        _selectTool(PhotoTool.draw);
      case (_, 'svg'):
        final spec = await pickSvgShape(
          context,
          fill: _drawColor,
          projectId: widget.projectId,
        );
        if (spec == null || !mounted) return;
        if (spec.imagePath case final path?) {
          await _placeImagePath(path);
        } else {
          _placeShapeSpec(spec);
        }
    }
  }

  /// [spec] on the photo at its own proportions, a third of the way across.
  ///
  /// Line art — an icon — is drawn in whichever of white and near-black shows
  /// on the photo under it: the library draws its icons white, which vanished
  /// into a light screenshot.
  void _placeShapeSpec(ShapeSpec spec) {
    final aspect = spec.height <= 0 ? 1.0 : spec.width / spec.height;
    const across = 0.34;
    final width = aspect >= 1 ? across : across * aspect;
    var op = ShapeOp(
      id: _nextOpId++,
      spec: spec,
      center: _viewCentre,
      width: width,
      height: width / aspect,
    );
    // The library draws its elements in white, which vanishes on a light
    // photo — a white badge on a white settings screen is a hole in the
    // picture with handles round it. So an element in the photo's own tone
    // arrives in the ink that reads on it instead.
    final behind = _luminanceUnder(op);
    if (behind != null) {
      const white = Color(0xFFFFFFFF), dark = Color(0xFF111111);
      final ink = behind < 0.18 ? white : dark;
      final lineArt = spec.fill.a == 0 && spec.strokeWidth > 0;
      if (lineArt) {
        if (_contrastOf(spec.strokeColor.computeLuminance(), behind) < 2) {
          op = op.copyWith(spec: spec.copyWith(strokeColor: ink));
        }
      } else if (spec.fillEnd == null &&
          spec.fill.a > 0 &&
          _contrastOf(spec.fill.computeLuminance(), behind) < 1.6) {
        // Its words, if it has any, kept readable on the new fill.
        final label = spec.label;
        final words = ink == white ? dark : white;
        op = op.copyWith(
          spec: spec.copyWith(
            fill: ink,
            strokeColor: spec.strokeColor == spec.fill ? ink : null,
            label:
                label != null &&
                    _contrastOf(
                          label.color.computeLuminance(),
                          ink.computeLuminance(),
                        ) <
                        3
                ? label.copyWith(color: words)
                : null,
          ),
        );
      }
    }
    _place(op, PhotoTool.stickers);
  }

  Future<void> _placeImage() async {
    if (_image == null) return;
    final entry = await showImageLibrarySheet(
      context,
      kind: LibraryImageKind.screenshot,
      projectId: widget.projectId,
      title: 'Add an image',
    );
    if (entry == null || !mounted) return;
    await _placeImagePath(entry.path);
  }

  /// The stored picture at [path], placed on the photo at its own shape.
  Future<void> _placeImagePath(String path) async {
    var texture = _placedImages[path];
    if (texture == null) {
      final bytes = await StoredImage.bytes(path);
      if (bytes == null || !mounted) return;
      texture = await decodePlacedImage(bytes);
      if (!mounted) {
        texture.dispose();
        return;
      }
      _placedImages[path] = texture;
    }
    const width = 0.4;
    _place(
      ImageOp(
        id: _nextOpId++,
        image: texture,
        source: path,
        center: _viewCentre,
        width: width,
        height: ImageOp.heightFor(texture, width),
      ),
      PhotoTool.stickers,
    );
  }

  Future<void> _placeSticker() async {
    if (_image == null) return;
    final sticker = await showClipartSheet(context);
    if (sticker == null || !mounted) return;
    _clipart ??= await ref.read(clipartCatalogProvider.future);
    if (!mounted) return;

    var art = _stickerArt[sticker.id];
    if (art == null) {
      art = await loadStickerPicture(sticker);
      if (!mounted) {
        art.picture.dispose();
        return;
      }
      _stickerArt[sticker.id] = art;
    }
    const width = 0.3;
    final size = art.size;
    var op = StickerOp(
      id: _nextOpId++,
      picture: art.picture,
      pictureSize: size,
      stickerId: sticker.id,
      center: _viewCentre,
      width: width,
      height: size.width <= 0 ? width : width * size.height / size.width,
    );
    // Art in one colour takes whichever of white and near-black shows on the
    // photo under it — but only when its own colour would not: a navy arrow
    // on a dark screenshot was placed, selected and invisible.
    if (sticker.tintable) {
      final behind = _luminanceUnder(op);
      final ink = await _inkLuminance(art.picture, size);
      if (!mounted) return;
      if (behind != null && ink != null && _contrastOf(ink, behind) < 2) {
        op = op.copyWith(
          tint: behind < 0.18
              ? const Color(0xFFFFFFFF)
              : const Color(0xFF111111),
        );
      }
    }
    _place(op, PhotoTool.stickers);
  }

  /// The average luminance of [picture]'s ink, 0–1, read off a thumbnail of
  /// it — null for art with nothing drawn.
  Future<double?> _inkLuminance(ui.Picture picture, Size size) async {
    if (size.isEmpty) return null;
    const side = 24;
    final k = side / math.max(size.width, size.height);
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..scale(k)
      ..drawPicture(picture);
    final thumbnail = recorder.endRecording();
    final image = await thumbnail.toImage(side, side);
    thumbnail.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) return null;
    var sum = 0.0;
    var count = 0;
    for (var i = 0; i < data.lengthInBytes; i += 4) {
      final alpha = data.getUint8(i + 3);
      if (alpha < 128) continue;
      // Premultiplied: back to the colour before judging it.
      double channel(int c) => data.getUint8(i + c) * 255 / alpha;
      sum += Color.fromARGB(
        255,
        channel(0).round().clamp(0, 255),
        channel(1).round().clamp(0, 255),
        channel(2).round().clamp(0, 255),
      ).computeLuminance();
      count++;
    }
    return count == 0 ? null : sum / count;
  }

  /// Whether [op] is art the catalog lets be recoloured.
  bool _isTintable(StickerOp op) =>
      _clipart?.byId(op.stickerId)?.tintable ?? false;

  // --- text ------------------------------------------------------------------

  TextOp? get _selectedText => switch (_selected) {
    final TextOp op => op,
    _ => null,
  };

  /// Adds a text layer and opens its words for typing.
  Future<void> _addText() async {
    if (_image == null) return;
    // Legible on whatever is behind the middle of the picture.
    final behind = _colourAt(_viewCentre);
    final dark = behind != null && behind.computeLuminance() > 0.55;
    final op = TextOp(
      id: _nextOpId++,
      text: 'Your text',
      fontSize: 0.075,
      center: _viewCentre,
      color: dark ? const Color(0xFF111111) : const Color(0xFFFFFFFF),
      accent: dark ? const Color(0xFFFFFFFF) : const Color(0xFF111111),
    ).fitted();
    _place(op, PhotoTool.text);
    await _editWords(op, isNew: true);
  }

  /// Opens [op]'s words in a text field, live on the photo as they are typed.
  Future<void> _editWords(TextOp op, {bool isNew = false}) async {
    final controller = TextEditingController(text: op.text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: op.text.length);
    _beginLive();
    await showStudioTextEditor(
      context,
      title: isNew ? 'Add text' : 'Edit text',
      controller: controller,
      hint: 'Type something',
      onChanged: (words) {
        if (!mounted) return;
        setState(() {
          _ops = [
            for (final o in _ops)
              if (o is TextOp && o.id == op.id) o.copyWith(text: words) else o,
          ];
        });
      },
    );
    controller.dispose();
    if (!mounted) return;
    // Emptied out: the layer goes, and so does the step that made it.
    final now = _ops.whereType<TextOp>().where((o) => o.id == op.id);
    if (now.isNotEmpty && now.first.text.trim().isEmpty) {
      setState(() {
        _ops = [
          for (final o in _ops)
            if (!(o is TextOp && o.id == op.id)) o,
        ];
        _selectedId = null;
      });
    }
    _flushLive();
    setState(() {});
  }

  void _styleText(TextOp Function(TextOp) update) =>
      _editSelected((o) => o is TextOp ? update(o) : o);

  /// Whether the swatches are on [op]'s box or outline just now.
  bool _onAccent(TextOp op) => _textAccent && op.look.hasAccent;

  /// [op] with [colour] wherever the swatches are pointed.
  TextOp _recolourText(TextOp op, Color colour) =>
      _onAccent(op) ? op.copyWith(accent: colour) : op.copyWith(color: colour);

  /// [op] in [look], in colours that let the look be seen.
  ///
  /// A box is there to stand out from the picture, so one that would not —
  /// a black plate on a dark screenshot — is made light on a dark picture and
  /// dark on a light one, and the letters change too if they would then
  /// vanish into it. An outline rings the letters in whichever of black and
  /// white they are not. A colour already chosen that does its job is kept.
  TextOp _withLook(TextOp op, TextLook look) {
    const ink = Color(0xFF111111), paper = Color(0xFFFFFFFF);
    double lum(Color c) => c.computeLuminance();
    const contrast = _contrastOf;

    var accent = op.accent;
    var color = op.color;
    switch (look) {
      case TextLook.box:
        final behind = _luminanceUnder(op);
        if (behind != null && contrast(lum(accent), behind) < 1.6) {
          accent = behind < 0.18 ? paper : ink;
        }
        if (contrast(lum(color), lum(accent)) < 3) {
          color = lum(accent) > 0.18 ? ink : paper;
        }
      case TextLook.outline:
        if (contrast(lum(color), lum(accent)) < 3) {
          accent = lum(color) > 0.18 ? ink : paper;
        }
      case TextLook.plain || TextLook.shadow:
        break;
    }
    return op.copyWith(look: look, accent: accent, color: color);
  }

  /// The average luminance of the photo under [op]'s box, 0–1 — null before
  /// the photo has been read.
  double? _luminanceUnder(PlacedOp op) {
    final image = _image;
    if (image == null) return null;
    final size = _orientedSizeOf(image);
    // Both of the box's sides are fractions of the width.
    final halfWidth = op.width / 2;
    final halfHeight = op.height * size.width / size.height / 2;
    var sum = 0.0;
    var count = 0;
    for (final fy in const [-0.6, 0.0, 0.6]) {
      for (final fx in const [-0.8, -0.4, 0.0, 0.4, 0.8]) {
        final colour = _colourAt(
          op.center + Offset(fx * halfWidth, fy * halfHeight),
        );
        if (colour == null) continue;
        sum += colour.computeLuminance();
        count++;
      }
    }
    return count == 0 ? null : sum / count;
  }

  Future<void> _pickFont() async {
    final op = _selectedText;
    if (op == null) return;
    final family = await showFontPicker(context, current: op.fontFamily);
    if (family == null || !mounted) return;
    _styleText((o) => o.copyWith(fontFamily: family));
    // A downloaded face arrives after the pick; measure again once it has.
    await GoogleFonts.pendingFonts();
    if (!mounted) return;
    setState(() {
      _ops = [
        for (final o in _ops)
          if (o is TextOp && o.id == op.id) o.fitted() else o,
      ];
    });
  }

  // ---------------------------------------------------------------------------
  // Output
  // ---------------------------------------------------------------------------

  /// Whether the edit changes anything at all.
  bool get _changed {
    final image = _image;
    if (image == null) return false;
    final size = _orientedSizeOf(image);
    final untouchedCrop = coverCrop(
      imageAspect: size.width / size.height,
      aspect: _frameAspect,
    );
    return _ops.isNotEmpty ||
        !_adjust.isIdentity ||
        !_orientation.isIdentity ||
        (_crop.left - untouchedCrop.left).abs() > 1e-4 ||
        (_crop.top - untouchedCrop.top).abs() > 1e-4 ||
        (_crop.right - untouchedCrop.right).abs() > 1e-4 ||
        (_crop.bottom - untouchedCrop.bottom).abs() > 1e-4;
  }

  Future<void> _apply() async {
    _flushLive();
    final image = _image;
    if (image == null || _saving) return;
    setState(() {
      _saving = true;
      _selectedId = null;
      _picking = null;
    });
    try {
      // Text is set in downloaded faces; the export must not beat them here.
      if (_ops.any((op) => op is TextOp)) await GoogleFonts.pendingFonts();
      // Nor a mosaic its pixels: without them it is drawn as a blur.
      await _sampler?.prepare();

      final composer = ScreenshotComposer(
        image: image,
        crop: _crop,
        ops: _ops,
        fill: _fill,
        fillColor: _fillColor,
        adjustments: _adjust,
        orientation: _orientation,
        pixels: _sampler,
      );
      final bytes = await composer.toPng();
      if (bytes == null) throw Exception('the canvas produced no pixels');

      final library = ref.read(imageLibraryProvider.notifier);
      final entry = await library.importBytes(
        bytes,
        projectId: widget.projectId,
        kind: LibraryImageKind.screenshot,
      );

      // The recipe, so this can be opened again as an edit rather than as a
      // picture: sliders where they were left, objects as objects.
      Map<String, dynamic>? recipe;
      if (_changed) {
        // The source is what the edit replays over. A background removal is
        // not stored as an op and so has to be *in* the source, which means
        // writing a second picture: the capture with the cut-out applied and
        // nothing else.
        var source = widget.edit?['source'] as String? ?? widget.imagePath;
        final cutouts = _ops.whereType<RemoveBackgroundOp>().toList();
        if (cutouts.isNotEmpty) {
          final baked = await ScreenshotComposer(
            image: image,
            crop: const Rect.fromLTRB(0, 0, 1, 1),
            ops: cutouts,
            orientation: ImageOrientation(turns: _orientation.turns),
          ).toPng();
          if (baked != null) {
            final base = await library.importBytes(
              baked,
              projectId: widget.projectId,
              kind: LibraryImageKind.screenshot,
            );
            source = base.path;
          }
        }
        recipe = screenshotEditToJson(
          ScreenshotEdit(
            source: source,
            crop: _crop,
            // A baked cut-out already carries the quarter turn; the recipe
            // keeps what is left of the orientation.
            orientation: cutouts.isEmpty
                ? _orientation
                : _orientation.copyWith(turns: 0),
            adjustments: _adjust,
            fill: _fill,
            fillColor: _fillColor,
            ops: [
              for (final op in _ops)
                if (op is! RemoveBackgroundOp) op,
            ],
          ),
        );
      }

      if (mounted) {
        Navigator.of(context).pop(
          ScreenshotEditResult(
            path: entry.path,
            edit: recipe,
            size: composer.exportSize,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showErrorSnack(context, 'Could not save the edit.', e);
      }
    }
  }

  Future<void> _close() async {
    _flushLive();
    if (!_dirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final discard = await showStudioConfirm(
      context,
      title: 'Discard changes?',
      message: 'Your edits to this photo will be lost.',
      confirmLabel: 'Discard',
      danger: true,
      icon: StudioIcons.warning,
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  Future<void> _customColour(Color current, ValueChanged<Color> onPicked) =>
      showStudioSheet<void>(
        context,
        title: 'Colour',
        child: SingleChildScrollView(
          padding: EdgeInsets.all(StudioSpace.xl),
          child: HsvColorPicker(color: current, onChanged: onPicked),
        ),
      );

  // ---------------------------------------------------------------------------

  void _selectTool(PhotoTool tool) {
    HapticFeedback.selectionClick();
    _flushLive();
    // Tapping the open tool again tucks its panel away, for the whole height
    // to work in — the tool stays on, so a drag still draws — and tapping it
    // once more brings the panel back.
    if (_tool == tool) {
      setState(() => _collapsed = !_collapsed);
      return;
    }
    setState(() {
      _tool = tool;
      _collapsed = false;
      _draft = null;
      _picking = null;
      final selected = _selected;
      if (selected != null) {
        final keep = switch (_tool) {
          PhotoTool.text => selected is TextOp,
          PhotoTool.stickers => selected is! TextOp && selected is! HideOp,
          PhotoTool.hide => selected is HideOp,
          _ => false,
        };
        if (!keep) _selectedId = null;
      }
    });
    if (_tool == PhotoTool.filters) _prepareThumb();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final primary = FocusManager.instance.primaryFocus;
    if (primary != _keys) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final command = keys.isMetaPressed || keys.isControlPressed;
    final key = event.logicalKey;
    if (command && key == LogicalKeyboardKey.keyZ) {
      keys.isShiftPressed ? _redoOnce() : _undoOnce();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyY) {
      _redoOnce();
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace) &&
        _selected != null) {
      _deleteSelected();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _stepBack();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// One step out — the eyedropper, then the selection, then the open tool,
  /// and only then the editor. Escape and Android's back both do this, so
  /// backing out of a tool never lands on "Discard changes?".
  void _stepBack() {
    final tool = _tool;
    if (_picking != null) {
      setState(() => _picking = null);
    } else if (_selected != null) {
      setState(() => _selectedId = null);
    } else if (tool != null) {
      _flushLive();
      setState(() {
        _tool = null;
        _collapsed = false;
        _draft = null;
      });
    } else {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final image = _image;
    final media = MediaQuery.of(context);
    final margin = context.layout.canvasMargin;
    final topBar = StudioSizes.toolbar + media.padding.top;
    // A fixed floor for the dock — the tool bar and one panel's height —
    // whatever tool is open, so opening a tool never re-fits the photo out
    // from under the judgement being made about it. Only a panel that grows
    // past it (Extend's fill choices, a large text size) lifts it, because the
    // alternative is covering the photo's bottom edge and the crop handles on
    // it.
    final floor = _Dock.floor(media.padding, collapsed: _collapsed);
    // Past the floor by a whole pixel, not by rounding: a re-fit resets the
    // zoom, so it has to be one the photo actually needs.
    final dockFloor = _dockHeight > floor + 1 ? _dockHeight : floor;

    // A phone held upright docks the tools under the photo; anything wider —
    // a phone on its side, a tablet, a desktop window — has the height to
    // keep and the width to spend, so they go either side of it instead.
    // The same rule the main editor lays itself out by.
    final side = !context.layout.docksToBottom;
    final railWidth = _ToolRail.width + media.padding.left;
    final panelWidth = _collapsed
        ? _PanelTab.width + media.padding.right
        : context.layout.inspectorWidth + media.padding.right;
    final chrome = side
        ? EdgeInsets.fromLTRB(
            railWidth + margin,
            topBar + margin,
            panelWidth + margin,
            media.padding.bottom + margin,
          )
        : EdgeInsets.fromLTRB(
            margin,
            topBar + margin,
            margin,
            dockFloor + margin,
          );

    final comparing = _comparing;
    final tool = _tool;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stepBack();
      },
      child: Focus(
        focusNode: _keys,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: s.canvas,
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  // Any press on the photo takes the keyboard back from a
                  // field, so the shortcuts keep working.
                  onPointerDown: (_) {
                    if (!_keys.hasPrimaryFocus) _keys.requestFocus();
                  },
                  child: _loadError != null
                      ? StudioEmptyState(
                          icon: StudioIcons.error,
                          title: 'Could not open the photo',
                          message: '$_loadError',
                        )
                      : image == null
                      ? Center(
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: s.accent,
                            ),
                          ),
                        )
                      : RetouchCanvas(
                          chromeInsets: chrome,
                          image: image,
                          crop: _crop,
                          ops: comparing ? const [] : _visibleOps,
                          draft: comparing ? null : _draft,
                          cropMode: tool == PhotoTool.crop && !comparing,
                          targetAspect: _targetAspect,
                          lockAspect: _cropLocked,
                          expand: _expand,
                          fill: _fill,
                          fillColor: _fillColor,
                          adjustments: comparing
                              ? const ImageAdjustments()
                              : _adjust,
                          orientation: _orientation,
                          selection: _objectTool && !comparing
                              ? _selected
                              : null,
                          objectMode: _objectTool && _picking == null,
                          paints:
                              _picking != null ||
                              tool == PhotoTool.draw ||
                              _drawsAreas,
                          pans: true,
                          selectable: (op) =>
                              (tool == PhotoTool.hide) == (op is HideOp),
                          pixels: _sampler,
                          onSelectObject: (id) {
                            if (_selectedId == id) return;
                            HapticFeedback.selectionClick();
                            setState(() {
                              _selectedId = id;
                              // The strip shows how the area picked up hides,
                              // so the controls under it are its own.
                              final picked = _selected;
                              if (picked is HideOp) {
                                _hideStyle = picked.style;
                                _hideShape = picked.shape;
                              }
                            });
                          },
                          onObjectChanged: (next) =>
                              setState(() => _objectDraft = next),
                          onObjectCommitted: () {
                            final draft = _objectDraft;
                            if (draft == null) return;
                            setState(() => _objectDraft = null);
                            _editSelected((_) => draft);
                          },
                          onObjectTap: (id) {
                            final op = _selectedText;
                            if (op != null && op.id == id) _editWords(op);
                          },
                          onCropStart: _beginLive,
                          onCropEnd: () => setState(_flushLive),
                          onCropChanged: (r) => setState(() => _crop = r),
                          onPaintStart: _paintStart,
                          onPaintUpdate: _paintUpdate,
                          onPaintEnd: _paintEnd,
                          onPaintCancel: _paintCancel,
                        ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                // Painted behind the phone's own status bar too: zoomed in, the
                // photo ran up under the clock and the battery.
                child: ColoredBox(
                  color: s.panel,
                  child: SafeArea(
                    bottom: false,
                    child: _TopBar(
                      subtitle: image == null
                          ? widget.deviceLabel
                          : '${(_crop.width * _orientedSizeOf(image).width).round()} × '
                                '${(_crop.height * _orientedSizeOf(image).height).round()} px',
                      canUndo: _undo.isNotEmpty || _liveStart != null,
                      canRedo: _redo.isNotEmpty,
                      canCompare: _changed,
                      busy: _saving,
                      onClose: _close,
                      onUndo: _undoOnce,
                      onRedo: _redoOnce,
                      onCompare: (on) => setState(() => _comparing = on),
                      onDone: image == null ? null : _apply,
                    ),
                  ),
                ),
              ),
              if (comparing)
                Positioned(
                  top: topBar + StudioSpace.l,
                  left: side ? railWidth : 0,
                  right: side ? panelWidth : 0,
                  child: const Center(child: _Badge(label: 'Original')),
                ),
              if (_picking != null)
                Positioned(
                  top: topBar + StudioSpace.l,
                  left: side ? railWidth : 0,
                  right: side ? panelWidth : 0,
                  child: const Center(
                    child: _Badge(
                      label: 'Tap the photo to pick a colour',
                      icon: StudioIcons.colorPicker,
                    ),
                  ),
                ),
              if (image != null && side) ...[
                Positioned(
                  left: 0,
                  top: topBar,
                  bottom: 0,
                  width: railWidth,
                  child: _ToolRail(selected: tool, onTool: _selectTool),
                ),
                if (!_collapsed)
                  Positioned(
                    right: 0,
                    top: topBar,
                    bottom: 0,
                    width: panelWidth,
                    child: _SidePanel(
                      tool: tool,
                      panel: tool == null ? null : _panelFor(tool),
                      onCollapse: () => setState(() => _collapsed = true),
                    ),
                  )
                else if (tool != null)
                  Positioned(
                    right: media.padding.right,
                    top: topBar,
                    bottom: 0,
                    child: Center(
                      child: _PanelTab(
                        tool: tool,
                        onOpen: () => setState(() => _collapsed = false),
                      ),
                    ),
                  ),
              ],
              if (image != null && !side)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _HeightReporter(
                    onHeight: (h) {
                      if (mounted && (h - _dockHeight).abs() > 0.5) {
                        setState(() => _dockHeight = h);
                      }
                    },
                    child: _Dock(
                      tool: tool,
                      onTool: _selectTool,
                      collapsed: _collapsed,
                      onCollapsed: (v) => setState(() => _collapsed = v),
                      panel: tool == null ? null : _panelFor(tool),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _objectTool =>
      _tool == PhotoTool.text || _tool == PhotoTool.stickers || _drawsAreas;

  /// Whether a drag on the photo draws a hidden area — Hide, on one of its
  /// three ways of hiding rather than on a bar.
  bool get _drawsAreas =>
      _tool == PhotoTool.hide && _hidePage == _HidePage.areas;

  /// `setState` for the panels, which are built in an extension and may not
  /// call the protected member themselves.
  void _update(VoidCallback change) => setState(change);

  /// The clip art pack, once it has been needed — which stickers may be
  /// recoloured is its answer, not the op's.
  ClipartCatalog? _clipart;

  /// Whether the open tool's panel is tucked away for a bigger photo.
  bool _collapsed = false;

  /// Which of a selected picture's settings the Stickers panel is showing.
  _ImageProperty _imageProperty = _ImageProperty.crop;

  /// The dock as last laid out, safe area included.
  double _dockHeight = 0;
}
