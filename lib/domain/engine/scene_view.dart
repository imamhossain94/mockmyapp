import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';
import '../../data/assets/drawn_iphones.dart';
import '../../data/assets/frame_catalog.dart';
import '../../data/assets/studio_fonts.dart';
import '../../data/assets/studio_frames.dart';
import '../../data/repositories/stored_image.dart';
import '../../features/editor/widgets/custom_device_frame.dart';
import '../../features/editor/widgets/drawn_iphone_frame.dart';
import '../../features/editor/widgets/frame_artwork.dart';
import '../../features/editor/widgets/programmatic_frame.dart';
import '../models/layer_stack.dart';
import '../models/screen_doc.dart';
import 'device_depth.dart';
import 'pattern_painter.dart';
import 'continuous.dart';
import 'localize.dart';
import 'shape_painter.dart';

/// The kinds of thing on the canvas the user can select and drag.
/// The kinds of thing a screen is made of.
///
/// Everything on the canvas is one of these, including the two that were not
/// selectable until now. The artboard was only ever a place to tap to deselect,
/// and the screenshot could only be reached through a tab — so the two parts
/// users spend the most time on were the two the canvas could not point at.
enum SceneHandle { canvas, frame, screenshot, caption, subCaption, shape }

/// What is currently selected: the kind of layer, and which one where there can
/// be more than one.
///
/// A plain [SceneHandle] was enough while every layer was a singleton. Shapes
/// broke that — a screen can carry a dozen — so the handle needs an index
/// travelling with it, and it has to be one value rather than two parallel
/// fields: a handle and an index that could disagree is exactly how a drag ends
/// up moving a shape the user is not looking at.
@immutable
class SceneSelection {
  const SceneSelection(this.handle, [this.index = 0]);

  /// The artboard itself: its size, its backdrop, everything under the
  /// content. Selectable like anything else — tapping the empty space around
  /// the device now selects the thing you tapped rather than selecting nothing.
  static const canvas = SceneSelection(SceneHandle.canvas);

  /// The first device on the screen, which for a one-device screen is the
  /// only one. Kept as a constant because most of the app addresses "the
  /// frame" and means exactly this.
  static const frame = SceneSelection(SceneHandle.frame);
  static const caption = SceneSelection(SceneHandle.caption);
  static const subCaption = SceneSelection(SceneHandle.subCaption);

  /// A device selection by position in [ScreenDoc.frames].
  ///
  /// A screen has always been able to hold several devices — `frames` is a
  /// list, and `SceneView` has always drawn all of them — but every one of them
  /// reported this same selection with no index on it, so tapping the second
  /// device selected, transformed and edited the first. Which is to say the
  /// model supported a composition the editor could only ever edit one third of.
  const SceneSelection.frameAt(int index) : this(SceneHandle.frame, index);

  /// The picture inside the device at [index] — a component in its own right,
  /// with its own crop, framing and set of captures.
  ///
  /// Nested rather than parallel: a screenshot belongs to a device the way a
  /// caption belongs to a screen, so it is addressed by the device's index and
  /// selecting it selects something *inside* the frame.
  const SceneSelection.screenshotAt(int index)
    : this(SceneHandle.screenshot, index);

  /// A shape selection by position in [ScreenDoc.shapes].
  const SceneSelection.shape(int index) : this(SceneHandle.shape, index);

  final SceneHandle handle;

  /// Position in [ScreenDoc.frames] or [ScreenDoc.shapes]; meaningless for the
  /// captions, which there is only ever one of.
  final int index;

  bool get isShape => handle == SceneHandle.shape;
  bool get isFrame => handle == SceneHandle.frame;
  bool get isScreenshot => handle == SceneHandle.screenshot;

  /// Which device this points at or into, for the two handles that name one.
  int? get deviceIndex => isFrame || isScreenshot ? index : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SceneSelection &&
          other.handle == handle &&
          other.index == index);

  @override
  int get hashCode => Object.hash(handle, index);

  @override
  String toString() => switch (handle) {
    SceneHandle.shape => 'shape $index',
    SceneHandle.frame => 'frame $index',
    SceneHandle.screenshot => 'screenshot $index',
    final other => other.name,
  };
}

/// How far the workspace around a scene is zoomed, for chrome that has to
/// stay one size on screen — the resize handles — whatever the zoom.
///
/// Published by the editor's canvas viewport. It notifies only on a real
/// change of scale, a step at a time, so a pinch does not rebuild the scene
/// on every frame for the sake of a few squares at its corners.
class SceneZoom extends InheritedWidget {
  const SceneZoom({super.key, required this.zoom, required super.child});

  final double zoom;

  /// The zoom above [context], or 1 where nothing publishes one.
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SceneZoom>()?.zoom ?? 1;

  @override
  bool updateShouldNotify(SceneZoom old) =>
      old.zoom <= 0 || (zoom / old.zoom - 1).abs() > 0.12;
}

/// Renders a [ScreenDoc] at any pixel size — reused by the editor canvas,
/// thumbnails, and (later) the offscreen exporter. All geometry in the doc is
/// percentage-of-canvas, so this widget is the single source of layout truth.
///
/// When [onSelect]/[onDrag] are provided it becomes interactive: tapping an
/// element selects it, dragging moves it (reported as a fraction of the canvas
/// so the editor can add it straight onto the element's `offsetPct`).
class SceneView extends StatelessWidget {
  const SceneView({
    super.key,
    required this.doc,
    required this.catalog,
    this.selected,
    this.onSelect,
    this.onTransformStart,
    this.onTransform,
    this.onTransformEnd,
    this.drawing = false,
    this.onPathDrawn,
    this.ownShapes,
    this.ownFrames,
    this.backgroundSlice,
    this.guides = const [],
    this.onContextMenu,
    this.onEmptyScreenTap,
    this.onEditText,
    this.onLockedTap,
    this.forExport = false,
  });

  /// A screen as composed into its set — see [composeScreen].
  SceneView.composed(
    ComposedScreen composed, {
    Key? key,
    required FrameCatalog catalog,
    SceneSelection? selected,
    ValueChanged<SceneSelection?>? onSelect,
    void Function(SceneSelection target)? onTransformStart,
    void Function(SceneSelection target, ScaleUpdateDetails details)?
    onTransform,
    void Function(SceneSelection target)? onTransformEnd,
    bool drawing = false,
    ValueChanged<List<Offset>>? onPathDrawn,
    List<SnapGuide> guides = const [],
    void Function(SceneSelection target, Offset globalPosition)? onContextMenu,
    ValueChanged<int>? onEmptyScreenTap,
    ValueChanged<SceneSelection>? onEditText,
    ValueChanged<SceneSelection>? onLockedTap,
    bool forExport = false,
  }) : this(
         key: key,
         doc: composed.doc,
         catalog: catalog,
         selected: selected,
         onSelect: onSelect,
         onTransformStart: onTransformStart,
         onTransform: onTransform,
         onTransformEnd: onTransformEnd,
         drawing: drawing,
         onPathDrawn: onPathDrawn,
         ownShapes: composed.ownShapes,
         ownFrames: composed.ownFrames,
         backgroundSlice: composed.backgroundSlice,
         guides: guides,
         onContextMenu: onContextMenu,
         onEmptyScreenTap: onEmptyScreenTap,
         onEditText: onEditText,
         onLockedTap: onLockedTap,
         forExport: forExport,
       );

  final ScreenDoc doc;
  final FrameCatalog catalog;

  /// How many of [doc]'s shapes, and of its devices, belong to this screen.
  ///
  /// The rest are guests from neighbouring screens in a continuous set: drawn,
  /// but not selectable or draggable here, because they are edited on the
  /// screen that owns them. Null means every layer is this screen's own.
  final int? ownShapes;
  final int? ownFrames;

  /// The part of a background spread across the set that this screen shows,
  /// or null to paint the background whole.
  final BackgroundSlice? backgroundSlice;

  /// Alignment lines to draw while a layer is being dragged into a snap.
  /// Editor chrome: drawn only on an interactive scene.
  final List<SnapGuide> guides;

  /// A right-click, or a long press on touch, on a layer — the context menu.
  final void Function(SceneSelection target, Offset globalPosition)?
  onContextMenu;

  /// A tap on a device that has no picture in it yet, by the device's index.
  ///
  /// The empty screen is drawn with an "add a picture" glyph, and a tap on it
  /// did nothing but select the frame — the picture was two taps and a panel
  /// away. With this set, that tap selects the device and hands over to the
  /// editor to choose one. Dragging still moves the device.
  final ValueChanged<int>? onEmptyScreenTap;

  /// A tap on a caption, or on a layer with words in it, that is already
  /// selected: open its words for editing. The first tap selects, the way the
  /// second tap on a device goes into its picture.
  final ValueChanged<SceneSelection>? onEditText;

  /// A tap on a locked layer, which neither selects nor moves — the editor's
  /// cue to say why nothing happened.
  final ValueChanged<SceneSelection>? onLockedTap;

  /// Whether this is the picture that becomes the file: the exporter's scene,
  /// as against the editor's, a thumbnail's or a preview's.
  ///
  /// An empty device shows an "add a picture" glyph everywhere else, as the
  /// prompt to go and add one. In a file it was editor furniture shipped to a
  /// store listing; there the display is left a plain, neutral plate.
  final bool forExport;
  final SceneSelection? selected;
  final ValueChanged<SceneSelection?>? onSelect;
  final void Function(SceneSelection target)? onTransformStart;
  final void Function(SceneSelection target, ScaleUpdateDetails details)?
  onTransform;
  final void Function(SceneSelection target)? onTransformEnd;

  /// Whether the freehand shape tool is armed.
  ///
  /// While it is, an overlay takes every pointer on the canvas: dragging traces
  /// a path instead of moving whatever happens to be under the finger.
  final bool drawing;

  /// Fires once with the traced path, as fractions of the canvas.
  ///
  /// Reported in canvas coordinates rather than as a finished [ShapeSpec]
  /// because the scene does not own the document — turning a path into a shape,
  /// giving it a colour and adding it to the screen is the editor's decision.
  final ValueChanged<List<Offset>>? onPathDrawn;

  bool get _interactive => onSelect != null;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasAspect = doc.canvas.width / doc.canvas.height;
        final availAspect = constraints.maxWidth / constraints.maxHeight;
        final size = availAspect > canvasAspect
            ? Size(constraints.maxHeight * canvasAspect, constraints.maxHeight)
            : Size(constraints.maxWidth, constraints.maxWidth / canvasAspect);

        final belowCaption = doc.isCaptionAbove ? null : doc.caption;
        final aboveCaption = doc.isCaptionAbove ? doc.caption : null;

        // Which device is current, whether the selection names the device
        // itself or the picture inside it. Read once here because the closures
        // below cannot promote a nullable field.
        final selectedDevice = selected?.deviceIndex;

        // Every layer is laid out against the document's own canvas, never
        // against the box it happens to be shown in, and the whole thing is
        // scaled to fit afterwards.
        //
        // Laying out at display size with proportionally-scaled font sizes
        // *looks* equivalent and is not: glyph advances round to the pixel, so
        // a caption that fits one line at 32pt can wrap to two at 16pt. That
        // made the editor disagree with itself between a large preview and a
        // small one, and disagree with the export — which has always rendered
        // this way (see `SceneRenderer`, and `ScreenThumbnail`). Wrapping is a
        // property of the document now, not of the window.
        final canvas = doc.canvas;

        // A comfortable fingertip, expressed in canvas pixels.
        //
        // The scene is laid out at canvas resolution and scaled to fit, so a
        // fixed dp figure means different things inside it depending on how big
        // the preview is: 44dp is 148 canvas px on a phone showing a 1179-wide
        // document at 350dp, and 44 of them on a desktop showing it 1:1. This
        // is the one place both numbers are in hand. Zero when the scene is not
        // interactive, so an export or a thumbnail builds exactly the tree it
        // always did.
        final minTouch = _interactive && size.width > 0
            ? kMinInteractiveDimension * canvas.width / size.width
            : 0.0;

        // One screen pixel in canvas pixels, zoom included: what the resize
        // handles are measured in, so they stay a grabbable size whether the
        // scene fills the window or is a thumbnail of itself. Zero off the
        // editor's canvas, where there are no handles.
        final handleUnit = _interactive && size.width > 0
            ? canvas.width / size.width / SceneZoom.of(context)
            : 0.0;

        return Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            // No drop shadow, and deliberately no border either. This box is
            // inside the editor's export RepaintBoundary, so anything painted
            // here — a soft shadow, a themed hairline — is baked into the
            // exported PNG as chrome the user never asked for. Separation from
            // the work area is provided by the work-area colour step the editor
            // computes (see `_workAreaColor` in editor_screen.dart), which is
            // the spec's surface-tone idiom and lives outside the mockup.
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox(
                  width: canvas.width,
                  height: canvas.height,
                  // Type on the canvas is artwork, not interface. The OS text
                  // size (Android's font scale, iOS Dynamic Type, a browser's
                  // zoom on text) used to reach every headline in the editor,
                  // the gallery and the exported PNGs, so the same document
                  // exported differently from one phone to the next, and an
                  // accessibility setting broke "DAILY CHALLENGES" mid-word.
                  //
                  // The empty default style is a replacement, not a merge, so
                  // nothing of the app's theme (Inter, its tracking, its
                  // locale) leaks into a caption field the document leaves
                  // unset: an export in one theme matches one in the other.
                  child: _CanvasType(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Painted straight off the layer stack, back to front.
                        //
                        // The order the user arranges in the layers list and the
                        // order this paints in are now the same list read two
                        // ways, rather than a fixed spine here and a description
                        // of it there. They used to be able to disagree, and the
                        // only reason they did not was that neither could
                        // express anything the other could not.
                        for (final row in LayerStack.of(doc).rows.reversed)
                          ..._layerWidgets(
                            row,
                            canvas: canvas,
                            minTouch: minTouch,
                            handleUnit: handleUnit,
                            selectedDevice: selectedDevice,
                            aboveCaption: aboveCaption,
                            belowCaption: belowCaption,
                          ),
                        if (_interactive && guides.isNotEmpty)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _GuidePainter(
                                  guides,
                                  // A hairline on screen, whatever the zoom.
                                  width: size.width <= 0
                                      ? 1
                                      : canvas.width / size.width,
                                ),
                              ),
                            ),
                          ),
                        if (drawing)
                          Positioned.fill(
                            child: _DrawOverlay(
                              canvasSize: canvas,
                              onDrawn: onPathDrawn,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// What one row of the layer stack paints.
  ///
  /// A row is not always a widget: a screenshot is drawn by the device it sits
  /// inside, a hidden layer is skipped outright, and the captions row is up to
  /// three pieces of type that share one position in the stack. So this returns
  /// a list, and the stack above splices them all together in order.
  ///
  /// Hidden layers are skipped rather than drawn transparent. They have to be
  /// absent from the export, and painting an invisible layer would still cost a
  /// path build or a screenshot decode on every frame of the editor.
  List<Widget> _layerWidgets(
    LayerRow row, {
    required Size canvas,
    required double minTouch,
    required double handleUnit,
    required int? selectedDevice,
    required CaptionSpec? aboveCaption,
    required CaptionSpec? belowCaption,
  }) => switch (row) {
    CanvasLayerRow() => [_backgroundLayer(canvas)],
    ShapeLayerRow(:final index, :final spec) =>
      spec.hidden
          ? const []
          : [
              _shapeLayer(
                index,
                spec,
                canvas,
                minTouch: minTouch,
                handleUnit: handleUnit,
              ),
            ],
    // Drawn by its own device, which is the only thing that knows where the
    // aperture is.
    ScreenshotLayerRow() => const [],
    FrameLayerRow(:final placement, :final index) =>
      placement == null || placement.hidden
          ? const []
          : [_frameLayer(placement, index, canvas, selectedDevice)],
    CaptionsLayerRow() => [
      if (aboveCaption != null && aboveCaption.enabled)
        _captionLayer(
          aboveCaption,
          canvas,
          topHalf: true,
          handleUnit: handleUnit,
        ),
      if (belowCaption != null && belowCaption.enabled)
        _captionLayer(
          belowCaption,
          canvas,
          topHalf: false,
          handleUnit: handleUnit,
        ),
      if (doc.subCaption case final sub? when sub.enabled)
        _captionLayer(
          sub,
          canvas,
          topHalf: doc.isCaptionAbove,
          isSub: true,
          handleUnit: handleUnit,
        ),
    ],
  };

  Widget _backgroundLayer(Size canvas) {
    final slice = backgroundSlice;
    final Widget layer;
    if (slice == null || slice.count < 2) {
      layer = _BackgroundLayer(background: doc.background, canvasSize: canvas);
    } else {
      // Painted at the width of the whole set and slid so this screen's part
      // is the part in view. The scene clips at its own canvas, so the rest
      // never shows.
      final wide = Size(canvas.width * slice.count, canvas.height);
      layer = ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: wide.width,
          maxWidth: wide.width,
          child: Transform.translate(
            offset: Offset(-slice.index * canvas.width, 0),
            child: SizedBox(
              width: wide.width,
              height: wide.height,
              child: _BackgroundLayer(
                background: doc.background,
                canvasSize: wide,
              ),
            ),
          ),
        ),
      );
    }
    if (!_interactive) return layer;
    return Positioned.fill(
      // Named, because it is the whole canvas and a screen reader met it
      // first: an unlabelled tap target the size of the artwork, with no hint
      // of what tapping it does.
      child: Semantics(
        button: true,
        selected: selected == SceneSelection.canvas,
        label: 'Artboard',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Selects the artboard rather than clearing the selection. Tapping a
          // thing should select that thing; the empty space around the device
          // is the artboard, and it has properties of its own to edit.
          onTap: () => onSelect?.call(SceneSelection.canvas),
          child: layer,
        ),
      ),
    );
  }

  /// One device.
  ///
  /// A hidden device is skipped by the caller rather than drawn transparent: it
  /// has to be absent from the export, and its screenshot is the most expensive
  /// thing on the screen to lay out for nothing.
  Widget _frameLayer(
    FramePlacement placement,
    int index,
    Size canvas,
    int? selectedDevice,
  ) {
    // A guest from a neighbouring screen: drawn, never handled here.
    if (index >= (ownFrames ?? doc.frames.length)) {
      return _FrameLayer(
        placement: placement,
        catalog: catalog,
        canvasSize: canvas,
        forExport: forExport,
      );
    }
    return _ownFrameLayer(placement, index, canvas, selectedDevice);
  }

  Widget _ownFrameLayer(
    FramePlacement placement,
    int index,
    Size canvas,
    int? selectedDevice,
  ) => _FrameLayer(
    placement: placement,
    catalog: catalog,
    canvasSize: canvas,
    forExport: forExport,
    // The device reads as current whether the device or the picture inside it
    // is selected: one is inside the other, and a marquee that vanished on
    // drilling in would say the user had left the device rather than entered
    // it.
    selected: selectedDevice == index,
    // Tap selects the device; tap it again to drill into its screenshot, the
    // way selecting a group then clicking again selects what is in it. Tapping
    // any other device starts over on that one rather than jumping straight to
    // its picture.
    onTap: _interactive
        ? () {
            final shot = placement.screenshot;
            final empty = shot.imagePath == null && shot.fill == null;
            if (empty && onEmptyScreenTap != null) {
              onSelect?.call(SceneSelection.frameAt(index));
              onEmptyScreenTap!(index);
              return;
            }
            onSelect?.call(
              selected == SceneSelection.frameAt(index)
                  ? SceneSelection.screenshotAt(index)
                  : SceneSelection.frameAt(index),
            );
          }
        : null,
    // A drag takes the device as it is: selected if it was not, but neither
    // drilled into its picture nor sent off to choose one — both are what a
    // tap asks for, and the drag that reused the tap did them too.
    onGrab: _interactive
        ? () {
            if (selectedDevice == index) return;
            onSelect?.call(SceneSelection.frameAt(index));
          }
        : null,
    onTransformStart: _interactive
        ? () => onTransformStart?.call(SceneSelection.frameAt(index))
        : null,
    onTransform: _interactive
        ? (d) => onTransform?.call(SceneSelection.frameAt(index), d)
        : null,
    onTransformEnd: _interactive
        ? () => onTransformEnd?.call(SceneSelection.frame)
        : null,
    onContextMenu: _interactive && onContextMenu != null
        ? (at) => onContextMenu!(SceneSelection.frameAt(index), at)
        : null,
  );

  Widget _captionLayer(
    CaptionSpec spec,
    Size canvas, {
    required bool topHalf,
    bool isSub = false,
    double handleUnit = 0,
  }) {
    final target = isSub ? SceneSelection.subCaption : SceneSelection.caption;
    return _CaptionLayer(
      spec: spec,
      canvasSize: canvas,
      topHalf: topHalf,
      isSubCaption: isSub,
      handleUnit: handleUnit,
      selected: selected == target,
      onTap: _interactive ? () => _tapText(target) : null,
      onGrab: _interactive ? () => _grab(target) : null,
      onTransformStart: _interactive
          ? () => onTransformStart?.call(target)
          : null,
      onTransform: _interactive ? (d) => onTransform?.call(target, d) : null,
      onTransformEnd: _interactive ? () => onTransformEnd?.call(target) : null,
      onContextMenu: _interactive && onContextMenu != null
          ? (at) => onContextMenu!(target, at)
          : null,
    );
  }

  /// A tap on a layer with words: selects it, or opens its words when it
  /// already was.
  void _tapText(SceneSelection target) {
    if (selected == target && onEditText != null) {
      onEditText!(target);
    } else {
      onSelect?.call(target);
    }
  }

  /// A drag or pinch taking hold of [target]: selected if it was not, and
  /// nothing else — a drag is not a second tap.
  void _grab(SceneSelection target) {
    if (selected != target) onSelect?.call(target);
  }

  /// One shape.
  ///
  /// [index] is the shape's position in [ScreenDoc.shapes], which is not its
  /// position in the stack: a selection has to survive the shape being dragged
  /// from behind the phone to in front of it, and that move changes nothing but
  /// [ShapeSpec.z].
  Widget _shapeLayer(
    int index,
    ShapeSpec spec,
    Size canvas, {
    required double minTouch,
    double handleUnit = 0,
  }) {
    // A guest from a neighbouring screen: drawn, never handled here.
    if (index >= (ownShapes ?? doc.shapes.length)) {
      return _ShapeLayer(spec: spec, canvasSize: canvas, minTouch: 0);
    }
    final target = SceneSelection.shape(index);
    // A locked layer: drawn, and still in the way. Passed through like a
    // guest, a drag on it went on to whatever was underneath — usually the
    // phone — and moved that instead. It stops a tap now, and says why nothing
    // moves; a drag or a pinch on it goes to the canvas, as on the backdrop.
    if (spec.locked) {
      return _ShapeLayer(
        spec: spec,
        canvasSize: canvas,
        minTouch: minTouch,
        locked: true,
        onTap: _interactive ? () => onLockedTap?.call(target) : null,
        onContextMenu: _interactive && onContextMenu != null
            ? (at) => onContextMenu!(target, at)
            : null,
      );
    }
    return _ShapeLayer(
      spec: spec,
      canvasSize: canvas,
      minTouch: minTouch,
      handleUnit: handleUnit,
      selected: selected == target,
      onTap: _interactive
          ? (spec.hasLabel
                ? () => _tapText(target)
                : () => onSelect?.call(target))
          : null,
      onGrab: _interactive ? () => _grab(target) : null,
      onTransformStart: _interactive
          ? () => onTransformStart?.call(target)
          : null,
      onTransform: _interactive ? (d) => onTransform?.call(target, d) : null,
      onTransformEnd: _interactive ? () => onTransformEnd?.call(target) : null,
      onContextMenu: _interactive && onContextMenu != null
          ? (at) => onContextMenu!(target, at)
          : null,
    );
  }
}

/// One alignment line: vertical at [at] of the canvas width, or horizontal at
/// [at] of its height.
@immutable
class SnapGuide {
  const SnapGuide.vertical(this.at) : vertical = true;
  const SnapGuide.horizontal(this.at) : vertical = false;

  final bool vertical;

  /// 0 at the left or top edge, 1 at the right or bottom.
  final double at;

  @override
  bool operator ==(Object other) =>
      other is SnapGuide && other.vertical == vertical && other.at == at;

  @override
  int get hashCode => Object.hash(vertical, at);
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter(this.guides, {required this.width});

  final List<SnapGuide> guides;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF3EA5)
      ..strokeWidth = width;
    for (final g in guides) {
      if (g.vertical) {
        final x = g.at * size.width;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      } else {
        final y = g.at * size.height;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) =>
      !listEquals(old.guides, guides) || old.width != width;
}

/// Photoshop-style selection chrome: a 1px accent marquee with small square
/// accent handles pinned to the four corners.
///
/// This is editor chrome only. It is drawn exclusively under `if (selected)`
/// and is wrapped in an [IgnorePointer], so it never participates in layout or
/// hit testing.
///
/// It DOES, however, sit inside the editor's export [RepaintBoundary]: the
/// boundary wraps the live [SceneView], not a separate offscreen copy. Any
/// caller that captures that boundary must therefore clear `selected` and pump
/// a frame first, or the marquee and its corner handles are baked into the
/// exported PNG. `_exportImage` in `editor_screen.dart` does exactly that; the
/// thumbnail and batch-export paths never pass `selected` at all.
///
/// The handles carry an [StudioColors.onAccent] hairline because the surface
/// underneath is the user's own artwork and can be any colour; accent-on-accent
/// would otherwise disappear against a blue background.
class _SelectionChrome extends StatelessWidget {
  const _SelectionChrome({this.handle = 8, this.corners = true});

  /// Edge length of each corner square, in logical pixels.
  final double handle;

  /// Whether to draw the corner squares. Off where [_CornerHandle]s stand in
  /// for them — the live ones on the editor's canvas.
  final bool corners;

  @override
  Widget build(BuildContext context) {
    final colors = context.studio;
    final double inset = -handle / 2;

    Widget corner() => DecoratedBox(
      decoration: BoxDecoration(
        color: colors.accent,
        border: Border.all(color: colors.onAccent, width: 1),
      ),
      child: SizedBox.square(dimension: handle),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: colors.accent, width: 1),
              borderRadius: BorderRadius.circular(StudioRadius.xs),
            ),
          ),
        ),
        if (corners) ...[
          Positioned(left: inset, top: inset, child: corner()),
          Positioned(right: inset, top: inset, child: corner()),
          Positioned(left: inset, bottom: inset, child: corner()),
          Positioned(right: inset, bottom: inset, child: corner()),
        ],
      ],
    );
  }
}

/// How far a resize handle reaches from its corner, and how big its square
/// is drawn, in screen pixels.
const double _kHandleReach = 12;
const double _kHandleSize = 9;

/// The four corner handles that resize a selected layer about its centre.
///
/// [box] is the layer's own box in the coordinates of the stack the handles
/// are laid out in; null puts them at that stack's corners, for a stack that
/// is exactly the layer and the handles' reach around it. [unit] is one screen
/// pixel in canvas pixels.
List<Widget> _cornerHandles(
  Rect? box, {
  required double unit,
  required ValueChanged<ScaleUpdateDetails> onScale,
  VoidCallback? onStart,
  VoidCallback? onEnd,
}) {
  final reach = _kHandleReach * unit;
  Widget handle(MouseCursor cursor) => _CornerHandle(
    size: _kHandleSize * unit,
    hairline: unit,
    cursor: cursor,
    onStart: onStart,
    onScale: onScale,
    onEnd: onEnd,
  );
  const falling = SystemMouseCursors.resizeUpLeftDownRight;
  const rising = SystemMouseCursors.resizeUpRightDownLeft;
  if (box == null) {
    return [
      Positioned(
        left: 0,
        top: 0,
        width: reach * 2,
        height: reach * 2,
        child: handle(falling),
      ),
      Positioned(
        right: 0,
        top: 0,
        width: reach * 2,
        height: reach * 2,
        child: handle(rising),
      ),
      Positioned(
        left: 0,
        bottom: 0,
        width: reach * 2,
        height: reach * 2,
        child: handle(rising),
      ),
      Positioned(
        right: 0,
        bottom: 0,
        width: reach * 2,
        height: reach * 2,
        child: handle(falling),
      ),
    ];
  }
  return [
    for (final (corner, cursor) in [
      (box.topLeft, falling),
      (box.topRight, rising),
      (box.bottomLeft, rising),
      (box.bottomRight, falling),
    ])
      Positioned(
        left: corner.dx - reach,
        top: corner.dy - reach,
        width: reach * 2,
        height: reach * 2,
        child: handle(cursor),
      ),
  ];
}

/// One corner of a selected layer: drag it away from the middle to grow the
/// layer, towards it to shrink it.
///
/// The corners used to be painted and nothing more — a drag on one fell
/// through to whatever was underneath and moved the phone instead — so on a
/// desktop a shape could only be resized with the Arrange sliders. The factor
/// is the pointer's distance from the layer's centre over its distance when
/// the drag began, which is the same cumulative scale a pinch reports, and it
/// goes through the same transform the pinch does.
class _CornerHandle extends StatefulWidget {
  const _CornerHandle({
    required this.size,
    required this.hairline,
    required this.cursor,
    required this.onScale,
    this.onStart,
    this.onEnd,
  });

  /// Edge of the square drawn, in canvas pixels.
  final double size;

  /// One screen pixel, in canvas pixels, for the square's outline.
  final double hairline;
  final MouseCursor cursor;
  final VoidCallback? onStart;
  final ValueChanged<ScaleUpdateDetails> onScale;
  final VoidCallback? onEnd;

  @override
  State<_CornerHandle> createState() => _CornerHandleState();
}

class _CornerHandleState extends State<_CornerHandle> {
  /// The layer's centre on screen, while a drag is under way.
  Offset? _centre;
  double _from = 0;

  /// The middle of the stack the handles stand in, on screen — which is the
  /// middle of the layer, since the stack is the layer with the same reach
  /// added on every side.
  Offset? _stackCentre() {
    final parent = context.findRenderObject()?.parent;
    if (parent is! RenderBox || !parent.hasSize) return null;
    return parent.localToGlobal(parent.size.center(Offset.zero));
  }

  void _start(DragStartDetails d) {
    final centre = _stackCentre();
    if (centre == null) return;
    final from = (d.globalPosition - centre).distance;
    if (from < 1) return;
    _centre = centre;
    _from = from;
    widget.onStart?.call();
  }

  void _update(DragUpdateDetails d) {
    final centre = _centre;
    if (centre == null) return;
    widget.onScale(
      ScaleUpdateDetails(scale: (d.globalPosition - centre).distance / _from),
    );
  }

  void _end() {
    if (_centre == null) return;
    _centre = null;
    widget.onEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.studio;
    return MouseRegion(
      cursor: widget.cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _start,
        onPanUpdate: _update,
        onPanEnd: (_) => _end(),
        onPanCancel: _end,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.accent,
              border: Border.all(
                color: colors.onAccent,
                width: widget.hairline,
              ),
            ),
            child: SizedBox.square(dimension: widget.size),
          ),
        ),
      ),
    );
  }
}

/// The canvas's text environment: no OS text scaling, no inherited style.
///
/// See where [SceneView] builds its stack. `MediaQuery.withNoTextScaling`
/// asserts there is a [MediaQuery] above it, and a scene is also built where
/// there is none (an offscreen render, a bare widget test), so it is only
/// asked for where there is one; anywhere else nothing scales text anyway.
class _CanvasType extends StatelessWidget {
  const _CanvasType({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final typed = DefaultTextStyle(style: const TextStyle(), child: child);
    if (MediaQuery.maybeTextScalerOf(context) == null) return typed;
    return MediaQuery.withNoTextScaling(child: typed);
  }
}

class _BackgroundLayer extends StatelessWidget {
  const _BackgroundLayer({required this.background, required this.canvasSize});

  final Background background;

  /// The laid-out canvas. Only the image backdrop needs it, to turn its
  /// fractional blur and pan into pixels at whatever size the scene is being
  /// rendered — preview and export are the same picture, at two scales.
  final Size canvasSize;

  @override
  Widget build(BuildContext context) {
    return switch (background) {
      SolidBackground(:final color) => ColoredBox(color: color),
      final GradientBackground gradient => DecoratedBox(
        decoration: BoxDecoration(gradient: gradient.toGradient()),
      ),
      // Generated on the spot from the spec's few numbers — no asset, no
      // network, and identical at thumbnail and export size.
      PatternBackground() => CustomPaint(
        painter: PatternPainter(background as PatternBackground),
        size: Size.infinite,
      ),
      // A panorama paints its own slice, as a pattern panorama does inside
      // its painter: laid out the whole set wide, every fraction measured
      // against that, and slid so this screen's part is the part in view.
      // So a screen of a set that is no longer continuous — or a thumbnail,
      // or an export of one screen — still shows its own part of the picture.
      final ImageBackground image when image.slices > 1 => _PanoramaWindow(
        slices: image.slices,
        slice: image.slice,
        canvasSize: canvasSize,
        builder: (wide) => _ImageBackdrop(
          spec: image.copyWith(slices: 1, slice: 0),
          canvasSize: wide,
        ),
      ),
      ImageBackground() => _ImageBackdrop(
        spec: background as ImageBackground,
        canvasSize: canvasSize,
      ),
    };
  }
}

/// One screen's window onto a backdrop laid out [slices] screens wide.
///
/// The same geometry the scene uses to slide a shared background across a
/// continuous set (see [SceneView.backgroundSlice]), owned by the backdrop
/// instead, so it holds wherever the backdrop is drawn. The scene clips at its
/// own canvas, and so does this, so the rest of the picture never shows.
class _PanoramaWindow extends StatelessWidget {
  const _PanoramaWindow({
    required this.slices,
    required this.slice,
    required this.canvasSize,
    required this.builder,
  });

  final int slices;
  final int slice;
  final Size canvasSize;

  /// The backdrop, laid out at the wide size it is handed.
  final Widget Function(Size wide) builder;

  @override
  Widget build(BuildContext context) {
    final wide = Size(canvasSize.width * slices, canvasSize.height);
    final index = slice.clamp(0, slices - 1);
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: wide.width,
        maxWidth: wide.width,
        minHeight: wide.height,
        maxHeight: wide.height,
        child: Transform.translate(
          offset: Offset(-index * canvasSize.width, 0),
          child: SizedBox.fromSize(size: wide, child: builder(wide)),
        ),
      ),
    );
  }
}

/// A photo backdrop with its fit, pan, zoom, blur and wash applied.
///
/// Layered bottom to top: a white plate, the picture, then the wash. The plate
/// only ever shows through under [ImageBackgroundFit.contain] (or a zoom below
/// 1), and it exists so the exported PNG is never part-transparent where the
/// letterbox falls.
class _ImageBackdrop extends StatelessWidget {
  const _ImageBackdrop({required this.spec, required this.canvasSize});

  final ImageBackground spec;
  final Size canvasSize;

  @override
  Widget build(BuildContext context) {
    // Resolved through [StoredImage] because where the pixels live is a
    // platform question — a file on a device, session bytes in a browser — and
    // paths need repairing besides: an app container is handed a new absolute
    // prefix on reinstall. A background that has gone for good degrades to
    // white rather than a red error box inside an export.
    final provider = StoredImage.provider(spec.path);

    // The picture with its zoom, pan and blur on it.
    Widget placed(Widget picture) {
      // Zoom inside the translate, so a pan is a true fraction of the canvas
      // rather than a fraction scaled by whatever zoom happens to be set.
      if (spec.scale != 1.0) {
        picture = Transform.scale(scale: spec.scale, child: picture);
      }
      if (spec.offsetX != 0.0 || spec.offsetY != 0.0) {
        picture = Transform.translate(
          offset: Offset(
            spec.offsetX * canvasSize.width,
            spec.offsetY * canvasSize.height,
          ),
          child: picture,
        );
      }

      final sigma = spec.blur * canvasSize.width;
      if (sigma > 0.05) {
        picture = ImageFiltered(
          // Clamp, not decal: decal fades the outermost pixels to transparent
          // and the white plate reads as a halo all the way round the canvas.
          imageFilter: ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          ),
          child: picture,
        );
      }
      return picture;
    }

    // The plate under the picture, which only ever shows where it letterboxes.
    Widget plated(Widget picture) => Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFFFFFFFF)),
        picture,
      ],
    );

    final Widget backdrop = provider == null
        ? plated(const SizedBox.expand())
        : Image(
            image: provider,
            fit: switch (spec.fit) {
              ImageBackgroundFit.cover => BoxFit.cover,
              ImageBackgroundFit.contain => BoxFit.contain,
              ImageBackgroundFit.fill => BoxFit.fill,
            },
            errorBuilder: (_, _, _) => plated(const SizedBox.expand()),
            // Nothing until the picture has decoded, plate included. The plate
            // painted on its own first, so every template tile in the gallery
            // flashed a white screen before its app appeared, and on a dark
            // listing that flash was the loudest thing on the page. Never
            // exported: the renderer precaches every picture, and a cached one
            // arrives synchronously, plate and all, on the very first frame.
            frameBuilder: (_, child, frame, sync) => frame == null && !sync
                ? const SizedBox.expand()
                : plated(placed(child)),
          );

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          backdrop,
          if (spec.overlayOpacity > 0)
            ColoredBox(
              color: spec.overlayColor.withValues(alpha: spec.overlayOpacity),
            ),
        ],
      ),
    );
  }
}

/// One vector shape, placed and rotated on the canvas.
///
/// The box is the shape's own bounds and nothing more. A shadow paints outside
/// them, which is allowed — a [CustomPaint] does not clip to its size, and the
/// only clip in the scene is the canvas edge, where a shadow *should* stop.
class _ShapeLayer extends StatelessWidget {
  const _ShapeLayer({
    required this.spec,
    required this.canvasSize,
    required this.minTouch,
    this.handleUnit = 0,
    this.selected = false,
    this.locked = false,
    this.onTap,
    this.onGrab,
    this.onTransformStart,
    this.onTransform,
    this.onTransformEnd,
    this.onContextMenu,
  });

  final ShapeSpec spec;
  final Size canvasSize;

  /// The smallest box worth hit-testing precisely, in **canvas** pixels.
  ///
  /// A shape smaller than this is grabbed by a plain rectangle around it
  /// instead of by its own outline. Zero switches that off — which is what the
  /// exporter and the thumbnails pass, since neither is touched.
  final double minTouch;

  /// One screen pixel in canvas pixels, for the resize handles a selected
  /// shape wears on the editor's canvas; zero for none.
  final double handleUnit;

  final bool selected;

  /// Takes taps, which [onTap] answers, but no drags or pinches: those go on
  /// to the canvas behind, so a locked layer can neither be moved nor move
  /// what is under it.
  final bool locked;
  final VoidCallback? onTap;

  /// See [_FrameLayer.onGrab].
  final VoidCallback? onGrab;
  final VoidCallback? onTransformStart;
  final ValueChanged<ScaleUpdateDetails>? onTransform;
  final VoidCallback? onTransformEnd;

  /// A right-click or a long press: the layer's context menu, at the pointer.
  final ValueChanged<Offset>? onContextMenu;

  @override
  Widget build(BuildContext context) {
    // Both against the canvas width, so equal fractions paint a square. See
    // [ShapeSpec.width].
    final width = spec.width * canvasSize.width;
    final height = spec.height * canvasSize.width;
    if (width <= 0 || height <= 0) return const SizedBox.shrink();

    // A small shape gets a bigger box to be caught by, centred on it. Picking
    // by the outline is right for anything you can see the edges of, and wrong
    // the moment the whole shape is smaller than a fingertip: a 60px dot on a
    // 1179 canvas is under 18dp on a phone, and asking someone to land inside
    // its circle is asking them to fail.
    final hitWidth = math.max(width, minTouch);
    final hitHeight = math.max(height, minTouch);
    final grabbedByBox = hitWidth > width || hitHeight > height;

    final left =
        (canvasSize.width - width) / 2 + spec.center.dx * canvasSize.width;
    final top =
        (canvasSize.height - height) / 2 + spec.center.dy * canvasSize.height;

    final box = Size(width, height);
    final picture = spec.hasImage ? StoredImage.provider(spec.imagePath) : null;

    Widget content = CustomPaint(
      painter: ShapePainter(
        spec: spec,
        canvasWidth: canvasSize.width,
        boxSize: box,
        pass: picture == null ? ShapePaintPass.all : ShapePaintPass.under,
      ),
      // An image layer's outline goes over its picture, not under it.
      foregroundPainter: picture == null
          ? null
          : ShapePainter(
              spec: spec,
              canvasWidth: canvasSize.width,
              boxSize: box,
              pass: ShapePaintPass.over,
            ),
      size: box,
      // The painter draws under its child, which is the order wanted: a badge's
      // word sits on its pill, not behind it.
      //
      // Here rather than in `ShapePainter` because everything a label needs is
      // already true of this box. It is inside the `Transform.rotate` below, so
      // a turned card turns its legend with it; it is one widget in the layer
      // stack, so it z-orders with the shape and vanishes with it; and it is
      // above the `Opacity` wrap, so a faded shape fades its words. Painting
      // glyphs in the `CustomPainter` instead would mean laying out a
      // paragraph on every drag tick, and a typeface that finished downloading
      // afterwards would never trigger the repaint that swapped it in.
      //
      // The cost is three paths that drive `ShapePainter` on a bare canvas and
      // so never see a label: the 24px layer-row tile and the 22px picker tile
      // in `shape_gallery.dart`, and `ScreenshotComposer` in the retoucher.
      // The first two show a shape's silhouette at a size where type would be
      // one pixel tall; the layers list names a labelled row after its words
      // instead. The third is deliberate and recorded in `ShapeOp`'s own list
      // of fields it does not adapt.
      child: picture == null
          ? (spec.hasLabel
                ? _ShapeLabelText(spec: spec, canvas: canvasSize)
                : null)
          : Stack(
              fit: StackFit.expand,
              children: [
                // Cropped to cover the shape and clipped to its outline, so a
                // picture takes whatever form the shape has.
                ClipPath(
                  clipper: ShapeClipper(spec),
                  child: Image(
                    image: picture,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: Color(0x33808080)),
                  ),
                ),
                if (spec.hasLabel)
                  _ShapeLabelText(spec: spec, canvas: canvasSize),
              ],
            ),
    );

    // Opacity is applied to the composited shape rather than to each paint, so
    // a translucent outlined shape does not show its own stroke through its own
    // fill where the two overlap.
    if (spec.opacity < 1) {
      content = Opacity(opacity: spec.opacity.clamp(0.0, 1.0), child: content);
    }

    final handles = selected && onTransform != null && handleUnit > 0;
    if (selected) {
      content = Stack(
        clipBehavior: Clip.none,
        children: [
          content,
          Positioned(
            left: -6,
            top: -6,
            right: -6,
            bottom: -6,
            child: IgnorePointer(
              child: _SelectionChrome(handle: 7, corners: !handles),
            ),
          ),
        ],
      );
    }

    if (onTap != null) {
      content = GestureDetector(
        // Ordinarily defers to the painter, whose `hitTest` tests the path
        // itself: a tap inside a circle's bounding box but outside the circle
        // falls through to whatever is behind it, which is what makes
        // overlapping shapes pickable at all.
        //
        // A shape too small to aim at takes the opposite rule and swallows its
        // whole grab box. It has to — there is nothing behind it that a finger
        // could have been aiming at more precisely.
        behavior: grabbedByBox
            ? HitTestBehavior.opaque
            : HitTestBehavior.deferToChild,
        onTap: onTap,
        onScaleStart: locked
            ? null
            : (_) {
                (onGrab ?? onTap)?.call();
                onTransformStart?.call();
              },
        onScaleUpdate: locked ? null : onTransform,
        onScaleEnd: locked ? null : (_) => onTransformEnd?.call(),
        onSecondaryTapDown: onContextMenu == null
            ? null
            : (d) => onContextMenu!(d.globalPosition),
        onLongPressStart: onContextMenu == null
            ? null
            : (d) => onContextMenu!(d.globalPosition),
        // Centred in the grab box, which is the shape's own box unless that was
        // too small to catch. Painting is unchanged either way: the box only
        // ever grows around the shape, never moves it.
        child: SizedBox(
          width: hitWidth,
          height: hitHeight,
          child: Center(
            child: SizedBox(width: width, height: height, child: content),
          ),
        ),
      );
      // Outside the gesture detector, so the label cannot disturb the
      // hit-test behaviour chosen just above it — and merged, which is what
      // makes it exist at all.
      //
      // A bare `Semantics` here produced no node whatsoever. It annotates
      // rather than creating one, and an annotation attaches to a node its
      // subtree already has: the frame layer has one from its artwork, a
      // caption has one from its `Text`, and a shape is a `CustomPaint` with
      // no semantics of its own. The only node in reach was the gesture
      // detector's, and annotations do not flow *down* into one — so the label
      // and the selected flag were silently dropped and the shape appeared in
      // the tree as nothing at all.
      content = MergeSemantics(
        child: Semantics(
          button: true,
          selected: selected,
          label: locked ? '${spec.displayName}, locked' : spec.displayName,
          child: content,
        ),
      );
    }

    Widget placed = onTap == null
        // Without handlers the layer must not take the pointer at all: a
        // guest from a neighbouring screen would otherwise swallow the tap
        // meant for the artboard under it.
        ? IgnorePointer(
            child: Center(
              child: SizedBox(width: width, height: height, child: content),
            ),
          )
        : content;

    // The handles' reach is added on every side, so the whole of each one is
    // inside the layer's box and can be hit — a child outside its parent's box
    // is painted but never hit-tested.
    //
    // The stack is there whenever the layer could be selected, not only once
    // it is: a drag selects as it takes hold, and a wrapper appearing above
    // the gesture detector at that moment rebuilt the detector and dropped
    // the drag it was in the middle of.
    final reach = handles ? _kHandleReach * handleUnit : 0.0;
    if (onTap != null && onTransform != null && handleUnit > 0) {
      placed = Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(padding: EdgeInsets.all(reach), child: placed),
          if (handles)
            ..._cornerHandles(
              Rect.fromLTWH(
                reach + (hitWidth - width) / 2,
                reach + (hitHeight - height) / 2,
                width,
                height,
              ),
              unit: handleUnit,
              onStart: onTransformStart,
              onScale: onTransform!,
              onEnd: onTransformEnd,
            ),
        ],
      );
    }

    return Positioned(
      left: left - (hitWidth - width) / 2 - reach,
      top: top - (hitHeight - height) / 2 - reach,
      width: hitWidth + reach * 2,
      height: hitHeight + reach * 2,
      child: Transform.rotate(
        angle: spec.rotationDeg * math.pi / 180,
        child: placed,
      ),
    );
  }
}

/// A shape's own words, laid out inside its box.
///
/// Sized off the canvas, never off the box: a label whose size grew with its
/// shape would change weight every time the shape was pinched, and the whole
/// point of `ShapeLabel.size` being a fraction of canvas width is that a
/// thumbnail and a full-resolution export are the same picture at two scales.
class _ShapeLabelText extends StatelessWidget {
  const _ShapeLabelText({required this.spec, required this.canvas});

  final ShapeSpec spec;
  final Size canvas;

  @override
  Widget build(BuildContext context) {
    final label = spec.label!;
    final size = label.size * canvas.width;
    return
    // Never hit-testable. The gesture detector above this runs with
    // `deferToChild` so that a shape is picked by its outline rather than by
    // its bounding box; a live `RenderParagraph` in here would quietly restore
    // box-picking for every labelled shape.
    IgnorePointer(
      // The layer already announces itself as `spec.displayName`, and a `Text`
      // merges its words into that node — turning "Star" into "Star Buy now".
      // The words are artwork, not the layer's name.
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(label.padding * canvas.width),
          child: Align(
            alignment: switch (label.align) {
              TextAlign.left || TextAlign.start => Alignment.centerLeft,
              TextAlign.right || TextAlign.end => Alignment.centerRight,
              _ => Alignment.center,
            },
            child: Text(
              label.allUpCase ? label.text.toUpperCase() : label.text,
              textAlign: label.align,
              style: StudioFonts.style(
                label.fontFamily,
                fontSize: size,
                height: label.lineHeight,
                // Always stated, zero included: a null here inherits
                // whatever tracking the surrounding style carries.
                letterSpacing: label.letterSpacing * canvas.width,
                color: label.color,
                fontWeight: switch (label.weight) {
                  null => label.bold ? FontWeight.bold : FontWeight.normal,
                  final w => FontWeight.values[(w.clamp(100, 900) ~/ 100) - 1],
                },
                fontStyle: label.italic ? FontStyle.italic : FontStyle.normal,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The freehand shape tool's capture surface.
///
/// Takes every pointer on the canvas while it is mounted and traces the drag,
/// painting the in-progress stroke so the gesture is visible as it happens.
/// Points are reported as fractions of the canvas, which is the only form that
/// survives the scene being laid out at one size and exported at another.
class _DrawOverlay extends StatefulWidget {
  const _DrawOverlay({required this.canvasSize, required this.onDrawn});

  final Size canvasSize;
  final ValueChanged<List<Offset>>? onDrawn;

  @override
  State<_DrawOverlay> createState() => _DrawOverlayState();
}

class _DrawOverlayState extends State<_DrawOverlay> {
  final List<Offset> _points = [];

  /// Minimum travel before a sample is kept, as a fraction of the canvas.
  ///
  /// A drag arrives at pointer resolution — hundreds of samples for a short
  /// stroke, most of them a fraction of a pixel apart at canvas scale. They cost
  /// file size and path-build time and change nothing that can be seen.
  static const double _minStep = 0.004;

  /// Above this the stroke is a scribble rather than a shape, and the guard
  /// keeps a slow, long drag from growing without bound.
  static const int _maxPoints = 600;

  void _add(Offset local) {
    final point = Offset(
      (local.dx / widget.canvasSize.width).clamp(-0.5, 1.5),
      (local.dy / widget.canvasSize.height).clamp(-0.5, 1.5),
    );
    if (_points.isNotEmpty) {
      if ((point - _points.last).distance < _minStep) return;
      if (_points.length >= _maxPoints) return;
    }
    setState(() => _points.add(point));
  }

  void _finish() {
    final drawn = List<Offset>.unmodifiable(_points);
    setState(_points.clear);
    // Two points are a line the user probably did not mean; a tap is certainly
    // not a shape. Dropping them silently leaves the tool armed for another go,
    // which is better than adding a degenerate layer to the document.
    if (drawn.length >= 3) widget.onDrawn?.call(drawn);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => _add(d.localPosition),
      onPanUpdate: (d) => _add(d.localPosition),
      onPanEnd: (_) => _finish(),
      onPanCancel: _finish,
      child: CustomPaint(
        painter: _DrawTrailPainter(
          points: _points,
          canvasSize: widget.canvasSize,
          // Chrome, and only ever on screen while the tool is armed. Nothing
          // here can reach an export: the exporter renders its own SceneView
          // with `drawing` left at false, so this overlay is never mounted
          // inside a capture boundary.
          color: s.accent,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _DrawTrailPainter extends CustomPainter {
  const _DrawTrailPainter({
    required this.points,
    required this.canvasSize,
    required this.color,
  });

  final List<Offset> points;
  final Size canvasSize;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = Path()
      ..moveTo(points.first.dx * size.width, points.first.dy * size.height);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx * size.width, p.dy * size.height);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        // Scaled off the canvas, like everything else in the scene: the trail is
        // drawn in canvas space and shown at whatever the preview's fit is, so a
        // fixed width would be a hairline on a 1179-wide document.
        ..strokeWidth = canvasSize.width * 0.005
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_DrawTrailPainter old) =>
      old.points.length != points.length || old.color != color;
}

/// The window the camera cut-out is painted out through.
///
/// Both rects arrive as fractions of the frame box; the clip is stated in the
/// coordinates of the screenshot's own box, which is the aperture, so the
/// aperture's own origin comes off both.
///
/// Public because it is the whole of the feature's geometry, and testing it
/// through a pumped scene would only ever assert that a `ClipRect` exists.
class CutoutPatchClipper extends CustomClipper<Rect> {
  const CutoutPatchClipper({
    required this.cutout,
    required this.screen,
    required this.frameWidth,
    required this.frameHeight,
  });

  final ScreenRect cutout;
  final ScreenRect screen;
  final double frameWidth;
  final double frameHeight;

  @override
  Rect getClip(Size size) {
    // The measured island stops where its solid pixels stop, which is one side
    // of an anti-aliased edge; without a little bleed the hole keeps a faint
    // ring of itself. Growing the patch costs nothing — it paints the same
    // picture the pixels under it are already painting — so this errs wide.
    final bleed = size.width * 0.006;
    final rect = Rect.fromLTWH(
      (cutout.x - screen.x) * frameWidth - bleed,
      (cutout.y - screen.y) * frameHeight - bleed,
      cutout.w * frameWidth + bleed * 2,
      cutout.h * frameHeight + bleed * 2,
    );
    // Clamped to the aperture, which is what keeps a notch honest: its island
    // hangs off the top border, so bleeding upward would paint screenshot over
    // the bezel above the screen.
    return rect.intersect(Offset.zero & size);
  }

  @override
  bool shouldReclip(CutoutPatchClipper old) =>
      old.frameWidth != frameWidth ||
      old.frameHeight != frameHeight ||
      old.cutout != cutout ||
      old.screen != screen;
}

class _FrameLayer extends StatelessWidget {
  const _FrameLayer({
    required this.placement,
    required this.catalog,
    required this.canvasSize,
    this.forExport = false,
    this.selected = false,
    this.onTap,
    this.onGrab,
    this.onTransformStart,
    this.onTransform,
    this.onTransformEnd,
    this.onContextMenu,
  });

  final FramePlacement placement;
  final FrameCatalog catalog;
  final Size canvasSize;

  /// See [SceneView.forExport].
  final bool forExport;
  final bool selected;
  final VoidCallback? onTap;

  /// Fired as a drag or pinch takes hold, before it transforms: selects the
  /// device without doing what a tap does. Null falls back to [onTap].
  final VoidCallback? onGrab;
  final VoidCallback? onTransformStart;
  final ValueChanged<ScaleUpdateDetails>? onTransform;
  final VoidCallback? onTransformEnd;

  /// A right-click or a long press: the layer's context menu, at the pointer.
  final ValueChanged<Offset>? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final device = catalog.byId(placement.deviceId);
    final variant = device.variants.firstWhere(
      (v) => v.id == placement.variantId,
      orElse: () => device.variants.first,
    );
    final t = placement.transform;

    // A built frame supplies its own proportions and its own aperture; the
    // catalog device is only still consulted for the picker's sake.
    //
    // Falling back to the catalog's own design is what makes the dynamic
    // handsets work: they ship a `FrameDesign` instead of artwork, so a
    // placement that has never been edited still draws a real phone. A design
    // the user has actually built always wins.
    final design =
        placement.design ?? studioDesignFor(device.id, placement.variantId);
    final frameAspect = design?.aspect ?? device.frameAspect;
    final rect = design == null
        ? device.screenRect
        : () {
            final r = CustomDeviceFrame.screenRectFor(design, frameAspect);
            return ScreenRect(x: r.left, y: r.top, w: r.width, h: r.height);
          }();

    final frameHeight = canvasSize.height * t.pagePercentage * t.scale;
    final frameWidth = frameHeight * frameAspect;

    final dx =
        (canvasSize.width - frameWidth) / 2 * (1 + t.align.x) +
        t.offsetPct.dx * canvasSize.width;
    final dy =
        (canvasSize.height - frameHeight) / 2 * (1 + t.align.y) +
        t.offsetPct.dy * canvasSize.height;

    final screenW = rect.w * frameWidth;
    final radius = screenW * placement.screenshot.cornerRadiusPct;
    final strokeW = screenW * placement.screenshot.strokeWidthPct;

    // The body this frame stands for, when it is a slab that has one. Worked
    // out whether or not the device is turned, because the glass over it
    // reflects either way; the sides are only drawn once it is turned —
    // head-on they are edge-on, and a device nobody has tilted draws exactly
    // as it always did.
    final body = placement.frameHidden
        ? null
        : deviceSolidFor(
            device: device,
            variant: variant,
            design: design,
            depth: placement.depth,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
          );
    final solid = t.isTilted && !placement.depth.isFlat ? body : null;

    // EXPORTED PIXELS — NOT CHROME. DELIBERATELY NOT TOKENISED.
    //
    // This "no screenshot yet" placeholder is composited *inside* the device
    // screen, i.e. it is part of the user's artwork and is captured by every
    // export/thumbnail RepaintBoundary. Its colours must be theme-independent:
    // an export made in dark mode has to be byte-identical to the same export
    // made in light mode, so `context.studio` tokens must never leak in here.
    // Likewise the glyph is a Material icon on purpose — swapping it for a
    // StudioIcon would change the bytes of every PNG exported from a screen
    // with no screenshot assigned.
    //
    // Icon/colour audits: this is the one sanctioned exception in lib/.
    // Changing it is a product decision about user output, not a redesign.
    // (0xFFBDBDBD is the literal value of the former `Colors.grey.shade400`,
    // spelled out so no Material palette reference remains.)
    final Widget emptyScreen = Container(
      color: const Color(0xFFEFEFF2),
      alignment: Alignment.center,
      // The plate without its glyph in a file: see [SceneView.forExport].
      child: forExport
          ? null
          : Icon(
              Icons.add_photo_alternate_outlined,
              color: const Color(0xFFBDBDBD),
              size: screenW * 0.2,
            ),
    );

    // The display's own backdrop, when the frame carries one.
    //
    // It stands in for the placeholder rather than sitting behind it: the plate
    // is an instruction to go and add a picture, and a display that has been
    // deliberately coloured is not waiting for one.
    final fill = placement.screenshot.fill;
    final Widget? fillLayer = fill == null
        ? null
        : _BackgroundLayer(
            background: fill,
            // The display, not the page. An image fill's blur and pan are
            // fractions of the box it is drawn in, and handing this the canvas
            // would scale both by the wrong number.
            canvasSize: Size(screenW, rect.h * frameHeight),
          );

    final screenshotProvider = StoredImage.provider(
      placement.screenshot.imagePath,
    );
    final Widget? picture = screenshotProvider == null
        ? null
        : Image(
            image: screenshotProvider,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            // A screenshot whose file has gone falls back to the neutral
            // placeholder rather than painting a debug error box into an
            // export — or to the display's own colour, when it has one.
            errorBuilder: (_, _, _) => fillLayer ?? emptyScreen,
            // Until it has decoded, the plate without its "add" glyph: an
            // undecoded picture paints nothing, and the home screen's cards
            // showed a row of switched-off black phones while a set loaded.
            // Never exported — the renderer precaches every picture first,
            // and a cached one arrives on the very first frame.
            frameBuilder: (_, child, frame, _) => frame == null
                ? fillLayer ?? const ColoredBox(color: Color(0xFFEFEFF2))
                : child,
          );

    // The picture with the frame's pan and zoom on it.
    Widget panned(Widget child) => Transform.translate(
      offset: Offset(
        screenW * placement.screenshot.offsetX,
        (rect.h * frameHeight) * placement.screenshot.offsetY,
      ),
      child: Transform.scale(scale: placement.screenshot.scale, child: child),
    );

    // Three cases, and the pan and zoom belong to the picture in every one of
    // them. They are the frame's controls for placing a *capture* inside the
    // aperture, so a fill under one stays put and fills the display, and a
    // display wearing nothing but a fill is not panned at all — dragging a
    // screenshot that is not there must not slide a colour off its own screen.
    final Widget screenshot = switch ((fillLayer, picture)) {
      (null, _) => panned(picture ?? emptyScreen),
      (final layer?, null) => layer,
      (final layer?, final image?) => Stack(
        fit: StackFit.expand,
        children: [layer, panned(image)],
      ),
    };

    // Rotation in the page, then — when the device is tilted — a turn out of
    // it seen through a perspective. Shared with the solid's sides, which are
    // projected through this same matrix: see [deviceTurn].
    final spin = deviceTurn(t, frameHeight);

    final face = Transform(
      alignment: Alignment.center,
      transform: spin,
      child: SizedBox(
        width: frameWidth,
        height: frameHeight,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none, // <--- ALLOW SHADOWS TO BLEED PAST THE FRAME
          children: [
            // A solid casts its shadow from its whole silhouette, behind its
            // sides; this one is painted in the plane of the face and would
            // land on top of them.
            if (placement.shadow != null && solid == null)
              Positioned(
                left: rect.x * frameWidth,
                top: rect.y * frameHeight,
                width: screenW,
                height: rect.h * frameHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // A foldable shut has a screen square on the hinge side
                    // and round on the other, and a shadow cast from one
                    // radius would stick out past the round corners. Every
                    // other frame keeps the screenshot's own radius, exactly
                    // as it always has.
                    borderRadius: design != null && design.hinge.enabled
                        ? CustomDeviceFrame.apertureRadii(design, frameWidth)
                        : BorderRadius.circular(radius),
                    boxShadow: [
                      BoxShadow(
                        color: placement.shadow!.color.withValues(
                          alpha: placement.shadow!.opacity,
                        ),
                        // Read as "px at a 1179-wide canvas", like every
                        // other blur in the scene. It used to be raw logical
                        // px while its own offset was a fraction of the
                        // frame, so in the editor — where the device is a
                        // couple of hundred pixels wide — the default 20
                        // painted a dark band across the bottom of the
                        // screen that looked like a chin no frame control
                        // could shift. Exports barely move: their canvas is
                        // already about 1179 wide.
                        blurRadius:
                            placement.shadow!.blur * (canvasSize.width / 1179),
                        offset: Offset(
                          placement.shadow!.offsetPct.dx * frameWidth,
                          placement.shadow!.offsetPct.dy * frameHeight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!placement.frameHidden) ...[
              if (design != null) ...[
                CustomDeviceFrame(
                  frameWidth: frameWidth,
                  frameHeight: frameHeight,
                  design: design,
                  screenshot: screenshot,
                  showCutout: !placement.cutoutHidden,
                  // A solid wears its keys on its side wall, not as slivers
                  // in the plane of the glass.
                  showKeys: solid == null,
                ),
              ] else if (variant.asset.isNotEmpty) ...[
                Positioned(
                  left: rect.x * frameWidth,
                  top: rect.y * frameHeight,
                  width: screenW,
                  height: rect.h * frameHeight,
                  child: Container(
                    decoration: strokeW > 0
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(radius),
                            border: Border.all(
                              color: placement.screenshot.strokeColor,
                              width: strokeW,
                            ),
                          )
                        : null,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        math.max(radius - strokeW, 0),
                      ),
                      child: screenshot,
                    ),
                  ),
                ),
                if (solid == null)
                  FrameArtwork(variant: variant)
                else
                  // The artwork's keys are slivers standing a few pixels proud
                  // of the chassis, painted flat in the plane of the screen —
                  // fins, on a turned phone. Trimmed off just outside the
                  // chassis, on corners squarer than the artwork's own so not
                  // a pixel of its traced silhouette is lost; the solid draws
                  // the same keys on its side wall.
                  ClipRRect(
                    clipper: _ChassisClipper(
                      body: solid.body.inflate(frameWidth * 0.0015),
                      radius: solid.radius * 0.6,
                    ),
                    child: FrameArtwork(variant: variant),
                  ),
                // A traced device wears its camera in the pixels, so the
                // only way to take one off is to cover it with what was
                // already behind it. The same screenshot widget is laid out
                // in the same box a second time and clipped to the island's
                // measured bounds, so the patch is the picture that was
                // showing through the rest of the aperture — continuous with
                // it by construction, at any pan, zoom or export size.
                if (placement.cutoutHidden && device.cutoutRect != null)
                  Positioned(
                    left: rect.x * frameWidth,
                    top: rect.y * frameHeight,
                    width: screenW,
                    height: rect.h * frameHeight,
                    child: ClipRect(
                      clipper: CutoutPatchClipper(
                        cutout: device.cutoutRect!,
                        screen: rect,
                        frameWidth: frameWidth,
                        frameHeight: frameHeight,
                      ),
                      child: screenshot,
                    ),
                  ),
              ] else if (drawnIPhoneFor(device.id) case final iphone?) ...[
                // A drawn iPhone stands where its traced artwork did, so it
                // takes the picture the way the artwork did too: outlined, when
                // the placement asks for an outline, before the glass clips it.
                DrawnIPhoneFrame(
                  spec: iphone,
                  frameColor: Color(variant.frameColor),
                  frameWidth: frameWidth,
                  frameHeight: frameHeight,
                  screenshot: strokeW > 0
                      ? Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(radius),
                            border: Border.all(
                              color: placement.screenshot.strokeColor,
                              width: strokeW,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              math.max(radius - strokeW, 0),
                            ),
                            child: screenshot,
                          ),
                        )
                      : screenshot,
                  showCutout: !placement.cutoutHidden,
                  // A solid wears its keys on its side wall.
                  showKeys: solid == null,
                ),
              ] else ...[
                ProgrammaticDeviceFrame(
                  frameWidth: frameWidth,
                  frameHeight: frameHeight,
                  screenshot: screenshot,
                  // The drawn bodies take the camera off by simply not being
                  // asked for one.
                  cutout: placement.cutoutHidden ? 'none' : device.cutout,
                  frameColor: Color(variant.frameColor),
                  style: device.frameStyle,
                  variantId: variant.id,
                  castShadow: solid == null,
                  showKeys: solid == null,
                ),
              ],
              // The studio reflected in the glass, over everything on the
              // face. Across the whole front on a slab, which is glass edge to
              // edge; across the display alone on a laptop or a monitor.
              if (placement.depth.glare > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: GlassGlarePainter(
                        transform: t,
                        frameSize: Size(frameWidth, frameHeight),
                        outline:
                            body?.outline ??
                            (Path()..addRRect(
                              RRect.fromRectAndRadius(
                                Rect.fromLTWH(
                                  rect.x * frameWidth,
                                  rect.y * frameHeight,
                                  screenW,
                                  rect.h * frameHeight,
                                ),
                                Radius.circular(radius),
                              ),
                            )),
                        lightDeg: placement.depth.light,
                        strength: placement.depth.glare,
                      ),
                    ),
                  ),
                ),
            ] else ...[
              Positioned(
                left: rect.x * frameWidth,
                top: rect.y * frameHeight,
                width: screenW,
                height: rect.h * frameHeight,
                child: Container(
                  decoration: strokeW > 0
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(radius),
                          border: Border.all(
                            color: placement.screenshot.strokeColor,
                            width: strokeW,
                          ),
                        )
                      : null,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      math.max(radius - strokeW, 0),
                    ),
                    child: screenshot,
                  ),
                ),
              ),
            ],
            if (selected)
              const Positioned(
                left: -8,
                top: -8,
                right: -8,
                bottom: -8,
                child: IgnorePointer(child: _SelectionChrome()),
              ),
          ],
        ),
      ),
    );

    Widget content = Opacity(
      opacity: placement.opacity,
      // A flat device is the face alone, exactly the tree it always was. A
      // solid puts its sides, keys and shadow behind the face, in the same
      // box, through the same matrix — and under the same opacity, so a
      // half-faded phone does not show its own band through its glass.
      child: solid == null
          ? face
          : Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: DeviceSolidPainter(
                      solid: solid,
                      transform: t,
                      frameSize: Size(frameWidth, frameHeight),
                      lightDeg: placement.depth.light,
                      shadow: placement.shadow,
                      shadowBlurScale: canvasSize.width / 1179,
                    ),
                  ),
                ),
                face,
              ],
            ),
    );

    if (onTap != null) {
      // Named and selectable. The canvas is the one surface in the app where
      // what you are editing is a picture rather than a control, so without
      // this a screen reader found a tappable region with nothing to say about
      // it — and no way to tell the selected device from the one behind it.
      content = Semantics(
        button: true,
        selected: selected,
        label: device.model,
        child: GestureDetector(
          onTap: onTap,
          onScaleStart: (_) {
            (onGrab ?? onTap)?.call();
            onTransformStart?.call();
          },
          onScaleUpdate: onTransform,
          onScaleEnd: (_) => onTransformEnd?.call(),
          onSecondaryTapDown: onContextMenu == null
              ? null
              : (d) => onContextMenu!(d.globalPosition),
          onLongPressStart: onContextMenu == null
              ? null
              : (d) => onContextMenu!(d.globalPosition),
          child: content,
        ),
      );
    }

    // Without handlers, pointer-transparent — see the same rule on shapes.
    if (onTap == null) content = IgnorePointer(child: content);

    return Positioned(
      left: dx,
      top: dy,
      width: frameWidth,
      height: frameHeight,
      child: content,
    );
  }
}

/// A traced chassis with its key slivers trimmed off.
class _ChassisClipper extends CustomClipper<RRect> {
  const _ChassisClipper({required this.body, required this.radius});

  final Rect body;
  final double radius;

  @override
  RRect getClip(Size size) =>
      RRect.fromRectAndRadius(body, Radius.circular(math.max(radius, 0)));

  @override
  bool shouldReclip(_ChassisClipper old) =>
      old.body != body || old.radius != radius;
}

class _CaptionLayer extends StatelessWidget {
  const _CaptionLayer({
    required this.spec,
    required this.canvasSize,
    required this.topHalf,
    this.isSubCaption = false,
    this.handleUnit = 0,
    this.selected = false,
    this.onTap,
    this.onGrab,
    this.onTransformStart,
    this.onTransform,
    this.onTransformEnd,
    this.onContextMenu,
  });

  final CaptionSpec spec;
  final Size canvasSize;
  final bool topHalf;
  final bool isSubCaption;

  /// See [_ShapeLayer.handleUnit]. A caption's handles size its type.
  final double handleUnit;
  final bool selected;
  final VoidCallback? onTap;

  /// See [_FrameLayer.onGrab].
  final VoidCallback? onGrab;
  final VoidCallback? onTransformStart;
  final ValueChanged<ScaleUpdateDetails>? onTransform;
  final VoidCallback? onTransformEnd;

  /// A right-click or a long press: the layer's context menu, at the pointer.
  final ValueChanged<Offset>? onContextMenu;

  @override
  Widget build(BuildContext context) {
    // A fitted caption is measured here, in build, and a face that finishes
    // loading afterwards only lays the paragraph out again. So the size worked
    // out against the fallback face on a first run or a fresh web session
    // would stay, too small or too big for the real one. Rebuilding when the
    // engine's fonts change measures it again; a caption set at its own size
    // has nothing to measure and skips the listener.
    if (spec.fitHeightPct == null && translatedFrom(spec) == null) {
      return _layout(context);
    }
    return ListenableBuilder(
      listenable: PaintingBinding.instance.systemFonts,
      builder: (context, _) => _layout(context),
    );
  }

  Widget _layout(BuildContext context) {
    // A translation set no taller than the words it replaces, and then any
    // caption a template sized kept inside the room it was given; see
    // [_fitTranslation] and [_fitBox].
    final spec = _fitBox(switch (translatedFrom(this.spec)) {
      final base? => _fitTranslation(this.spec, base, canvasSize),
      null => this.spec,
    }, canvasSize);
    final dx = spec.offsetPct.dx * canvasSize.width;
    final dy = spec.offsetPct.dy * canvasSize.height;
    final baseTop = isSubCaption
        ? 0.14 * canvasSize.height
        : 0.045 * canvasSize.height;

    // Sizes are "design px at a 1179-wide canvas"; every effect measurement
    // scales by the same factor as the font so preview, thumbnail and export
    // stay one picture.
    final widthScale = canvasSize.width / 1179;
    final textAlign = _captionAlign(spec);

    // Glow first so a drop shadow paints over it — both sit under the glyphs.
    final shadows = <Shadow>[
      if (spec.glowBlur > 0)
        Shadow(color: spec.glowColor, blurRadius: spec.glowBlur * widthScale),
      if (spec.shadowBlur > 0 || spec.shadowOffsetY != 0)
        Shadow(
          color: spec.shadowColor,
          blurRadius: spec.shadowBlur * widthScale,
          offset: Offset(0, spec.shadowOffsetY * widthScale),
        ),
    ];

    final hasStroke = spec.strokeWidth > 0;

    Paint strokePaint() => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = spec.strokeWidth * widthScale
      ..strokeJoin = StrokeJoin.round
      ..color = spec.strokeColor;

    Text paragraph({Paint? foreground, List<Shadow>? sh}) => Text.rich(
      _captionSpan(spec, widthScale, foreground: foreground, shadows: sh),
      textAlign: textAlign,
    );

    // Shadows ride the bottom-most copy — the outline when there is one, the
    // fill otherwise — because putting them on both double-darkens.
    final fill = paragraph(sh: hasStroke || shadows.isEmpty ? null : shadows);

    Widget textWidget = hasStroke
        ? Stack(
            children: [
              paragraph(
                foreground: strokePaint(),
                sh: shadows.isEmpty ? null : shadows,
              ),
              fill,
            ],
          )
        : fill;

    if (spec.backgroundColor != null) {
      final rim =
          spec.backgroundBorderColor != null && spec.backgroundBorderWidth > 0
          ? BorderSide(
              color: spec.backgroundBorderColor!,
              width: spec.backgroundBorderWidth,
            )
          : BorderSide.none;
      textWidget = DecoratedBox(
        decoration: ShapeDecoration(
          color: spec.backgroundColor,
          shape: cornerShape(
            spec.cornerStyle,
            spec.backgroundRadius,
            side: rim,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spec.backgroundPaddingX,
            vertical: spec.backgroundPaddingY,
          ),
          child: textWidget,
        ),
      );
    }

    final handles = selected && onTransform != null && handleUnit > 0;
    if (selected) {
      // The marquee is pushed OUTSIDE the text with a negative inset, exactly
      // as the frame's chrome is. It used to pad the text by 4 on every side,
      // which took 8px of width away from it — so selecting a caption re-wrapped
      // it and deselecting wrapped it back. Chrome must never change the thing
      // it is drawn around.
      textWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          textWidget,
          Positioned(
            left: -4,
            top: -4,
            right: -4,
            bottom: -4,
            child: IgnorePointer(
              child: _SelectionChrome(handle: 6, corners: !handles),
            ),
          ),
        ],
      );
    }

    if (onTap != null) {
      textWidget = GestureDetector(
        onTap: onTap,
        onScaleStart: (_) {
          (onGrab ?? onTap)?.call();
          onTransformStart?.call();
        },
        onScaleUpdate: onTransform,
        onScaleEnd: (_) => onTransformEnd?.call(),
        onSecondaryTapDown: onContextMenu == null
            ? null
            : (d) => onContextMenu!(d.globalPosition),
        onLongPressStart: onContextMenu == null
            ? null
            : (d) => onContextMenu!(d.globalPosition),
        child: textWidget,
      );
      // Names the layer, not its contents. The words are already in the tree
      // as text and merge into this node, so repeating them here had a screen
      // reader read the headline out twice.
      textWidget = Semantics(
        button: true,
        selected: selected,
        label: isSubCaption ? 'Subtitle' : 'Headline',
        child: textWidget,
      );
    }

    // Room for the handles on every side, taken back out of the position so
    // the words stay exactly where they were and wrap at the same width —
    // the same rule as the marquee above.
    final reach = handles ? _kHandleReach * handleUnit : 0.0;
    // Always there on the editor's canvas — see the same rule on shapes.
    if (onTap != null && onTransform != null && handleUnit > 0) {
      textWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(padding: EdgeInsets.all(reach), child: textWidget),
          if (handles)
            ..._cornerHandles(
              null,
              unit: handleUnit,
              onStart: onTransformStart,
              onScale: onTransform!,
              onEnd: onTransformEnd,
            ),
        ],
      );
    }

    return Positioned(
      left: 24 + dx - reach,
      right: 24 - dx - reach,
      top: topHalf ? baseTop + dy - reach : null,
      bottom: topHalf ? null : baseTop - dy - reach,
      child: Align(
        alignment: spec.align.x < 0
            ? Alignment.centerLeft
            : spec.align.x > 0
            ? Alignment.centerRight
            : Alignment.center,
        child: textWidget,
      ),
    );
  }
}

/// How a caption's lines sit across its box.
TextAlign _captionAlign(CaptionSpec spec) => spec.align.x < 0
    ? TextAlign.left
    : spec.align.x > 0
    ? TextAlign.right
    : TextAlign.center;

/// One run's type, or the caption's own when [run] is null.
///
/// Color and foreground are mutually exclusive on TextStyle; everything else
/// must be identical between the stroke and fill copies or their metrics
/// diverge and the outline drifts off the letterforms. Size is a multiplier so
/// a run keeps its proportion when the caption is resized as a whole.
TextStyle _captionStyle(
  CaptionSpec spec,
  double widthScale, {
  Color? color,
  Paint? foreground,
  List<Shadow>? shadows,
  CaptionRun? run,
}) {
  final size = spec.size * (run?.sizeScale ?? 1);
  return StudioFonts.style(
    run?.fontFamily ?? spec.fontFamily,
    fontSize: size * widthScale,
    // lineHeight is stored absolute against `spec.size`; keeping the ratio is
    // what stops a scaled run from crashing into its neighbour.
    height: spec.lineHeight / spec.size,
    // Always stated, zero included: a null here inherits whatever tracking
    // the surrounding style carries, which on the editor's canvas was the
    // app theme's.
    letterSpacing: spec.letterSpacing * widthScale,
    color: color,
    foreground: foreground,
    // A caption that names a heavier cut is set in it wherever it is bold;
    // see [CaptionSpec.weight].
    fontWeight: (run?.bold ?? spec.bold)
        ? switch (spec.weight) {
            null => FontWeight.bold,
            final w => FontWeight.values[(w.clamp(100, 900) ~/ 100) - 1],
          }
        : FontWeight.normal,
    fontStyle: (run?.italic ?? spec.italic)
        ? FontStyle.italic
        : FontStyle.normal,
    decoration: (run?.underline ?? spec.underline)
        ? TextDecoration.underline
        : TextDecoration.none,
    // Null follows the paint, which is what makes the rule under an outlined
    // caption get outlined with it rather than drawn flat.
    decorationColor: foreground == null ? color : null,
    shadows: shadows,
  );
}

/// The whole caption as one paragraph — what the layer paints and what a
/// translation is measured with, so the two cannot disagree.
///
/// One paragraph rather than a row per line, even when the caption is split
/// into runs: a run is a character range and stops mid-line as readily as it
/// covers three, so the runs cannot each be given a box of their own. Painting
/// them as spans is also what restores ordinary wrapping to a styled caption —
/// the per-line editor it replaced could not wrap at all.
TextSpan _captionSpan(
  CaptionSpec spec,
  double widthScale, {
  Paint? foreground,
  List<Shadow>? shadows,
}) {
  TextStyle styleFor(CaptionRun? run) => _captionStyle(
    spec,
    widthScale,
    // Only ever one of the two, and the stroke copy is the one that takes the
    // paint — so a run's own ink is a fill-copy concern.
    color: foreground == null ? (run?.color ?? spec.color) : null,
    foreground: foreground,
    shadows: shadows,
    run: run,
  );

  final text = spec.renderedText;
  // An empty caption paints a space either way, so it keeps a row and deleting
  // the last character of one does not collapse the layout under it.
  if (spec.runs.isEmpty || text.isEmpty) {
    return TextSpan(text: text.isEmpty ? ' ' : text, style: styleFor(null));
  }
  return TextSpan(
    style: styleFor(null),
    children: [
      for (final run in spec.runs)
        TextSpan(
          text: spec.allUpCase ? run.text.toUpperCase() : run.text,
          style: styleFor(run),
        ),
    ],
  );
}

/// How tall [spec]'s words set on [canvas]: across the width between the
/// caption's margins, less its plate's padding, as the layer lays them out.
double _captionHeight(CaptionSpec spec, Size canvas) {
  final width =
      canvas.width -
      48 -
      (spec.backgroundColor == null ? 0 : 2 * spec.backgroundPaddingX);
  final painter = TextPainter(
    text: _captionSpan(spec, canvas.width / 1179),
    textAlign: _captionAlign(spec),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(1.0, width));
  final height = painter.height;
  painter.dispose();
  return height;
}

/// [spec], a translation of [base], set no taller than [base] on [canvas].
///
/// A translation keeps the design's size and place, and a longer language
/// wraps onto more lines — German onto a third where the English had two,
/// running into the subtitle under it on every screen of the set. So one that
/// would take more height than the words it replaces is set smaller, its
/// leading and tracking with it, just far enough to fit. Never below half,
/// which is past the point of reading; a translation given a size of its own
/// is never passed here.
CaptionSpec _fitTranslation(CaptionSpec spec, CaptionSpec base, Size canvas) =>
    _shrinkToFit(spec, _captionHeight(base, canvas), canvas, floor: 0.5);

/// [spec] set no taller than its [CaptionSpec.fitHeightPct] of [canvas]'s
/// height, when it carries one.
///
/// The same shrink as a translation's, with a higher floor: a translation is
/// one language among several and may give a little more, while this is the
/// headline itself, and below 60% it stops reading as one.
CaptionSpec _fitBox(CaptionSpec spec, Size canvas) {
  final box = spec.fitHeightPct;
  if (box == null) return spec;
  return _shrinkToFit(spec, box * canvas.height, canvas, floor: 0.6);
}

/// [spec] set smaller, its leading and tracking with it, just far enough to
/// take no more than [room] of height on [canvas], and never below [floor] of
/// its own size.
CaptionSpec _shrinkToFit(
  CaptionSpec spec,
  double room,
  Size canvas, {
  required double floor,
}) {
  // Half a pixel of slack, so a caption measured at exactly the room is not
  // shrunk by rounding.
  final limit = room + 0.5;
  if (_captionHeight(spec, canvas) <= limit) return spec;
  CaptionSpec at(double k) => spec.copyWith(
    size: spec.size * k,
    lineHeight: spec.lineHeight * k,
    letterSpacing: spec.letterSpacing * k,
  );
  var fits = floor, overflows = 1.0;
  for (var i = 0; i < 7; i++) {
    final k = (fits + overflows) / 2;
    if (_captionHeight(at(k), canvas) <= limit) {
      fits = k;
    } else {
      overflows = k;
    }
  }
  return at(fits);
}
