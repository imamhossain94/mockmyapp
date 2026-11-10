part of 'screenshot_editor_screen.dart';

// -----------------------------------------------------------------------------
// Canvas
// -----------------------------------------------------------------------------

/// The interactive stage.
///
/// Two presentations share one widget because they share one coordinate system:
/// in paint mode the canvas *is* the device screen (the crop region at the
/// device's aspect), and in crop mode it zooms out to the whole source image so
/// the crop window can be dragged around inside it.
class RetouchCanvas extends StatefulWidget {
  const RetouchCanvas({
    super.key,
    required this.image,
    required this.orientation,
    required this.crop,
    required this.ops,
    required this.draft,
    required this.cropMode,
    required this.targetAspect,
    required this.onCropChanged,
    required this.onPaintStart,
    required this.onPaintUpdate,
    required this.onPaintEnd,
    required this.onPaintCancel,
    this.expand = false,
    this.fill = ExpandFill.edge,
    this.fillColor = const Color(0xFF000000),
    this.lockAspect = true,
    this.adjustments = const ImageAdjustments(),
    this.selection,
    this.chromeInsets = EdgeInsets.zero,
    // Required, not optional-with-a-default. They WERE optional, and the screen
    // silently failed to pass a single one of them: the canvas compiled, the
    // tests passed — they construct it directly and pass them — and every
    // object gesture was dead in the app. Required turns that into a compile
    // error, which is the only check that could have caught it.
    required this.paints,
    required this.objectMode,
    required this.onSelectObject,
    required this.onObjectChanged,
    required this.onObjectCommitted,
    this.pans = false,
    this.selectable,
    this.pixels,
    this.onObjectTap,
    this.onCropStart,
    this.onCropEnd,
  });

  /// Which placed objects the open tool picks up; null for all of them.
  ///
  /// Hide picks up only hidden areas and the other tools everything else, so
  /// a blur over a name is never dragged off it while a sticker is being
  /// placed beside it.
  final bool Function(PlacedOp op)? selectable;

  /// The photo's pixels, for the cells of a pixelated area.
  final PixelSampler? pixels;

  /// Whether one finger slides the photo around, for the tools that do nothing
  /// else with a drag — Adjust, Filters, Cutout, and no tool at all. Without
  /// it a zoomed-in photo could only be moved with two fingers.
  final bool pans;

  /// A tap on the object that was already selected — how the words of a text
  /// layer are opened for editing.
  final ValueChanged<int>? onObjectTap;

  /// A crop drag began and ended: the screen's cue to take one undo step for
  /// the whole drag rather than one per frame.
  final VoidCallback? onCropStart;
  final VoidCallback? onCropEnd;

  final ui.Image image;
  final Rect crop;
  final List<EditOp> ops;
  final EditOp? draft;

  /// The placed object to outline, or null for none. Chrome only — it is drawn
  /// over the composite and never reaches an export.
  final PlacedOp? selection;

  /// What the surrounding chrome covers on each edge.
  ///
  /// Used to fit the artwork and to clamp the pan, never to clip: the capture
  /// bleeds under a translucent tool dock rather than stopping at it, which is
  /// the difference between a stage that is the screen and one that is a
  /// letterbox with furniture around it.
  final EdgeInsets chromeInsets;

  /// Whether a pointer down lays something on the artwork.
  ///
  /// Distinct from [objectMode]: the crop and eyedropper tools paint nothing
  /// either, but only a brush or a redaction leaves a mark a stray tap would
  /// have to be undone.
  final bool paints;

  /// Whether a pointer on a placed object grabs it rather than paints.
  ///
  /// A mode rather than "whatever is under the finger", because a brush stroke
  /// across a sticker has to be able to cross it. Which tool you are in decides
  /// what the canvas is for; the geometry only decides what you grabbed.
  ///
  /// With [paints] as well — Hide — a press on an object grabs it and a press
  /// anywhere else draws a new one.
  final bool objectMode;

  /// Reports the object under a tap, or null for empty space.
  final ValueChanged<int?>? onSelectObject;

  /// Fires continuously while an object is being moved, scaled or turned. The
  /// caller holds it as a draft rather than committing every frame — a drag is
  /// one undo entry, not sixty.
  final ValueChanged<PlacedOp>? onObjectChanged;

  /// The transform is finished and may be written to history.
  final VoidCallback? onObjectCommitted;
  final bool cropMode;
  final double targetAspect;

  /// Tone adjustments, forwarded to the composer so the canvas shows the
  /// screenshot the export will contain.
  final ImageAdjustments adjustments;

  /// How the capture is turned. Rects here are fractions of the turned
  /// picture, so this has to travel with them.
  final ImageOrientation orientation;

  /// Whether a corner drag keeps [targetAspect]. False resizes each axis alone.
  final bool lockAspect;

  final bool expand;
  final ExpandFill fill;
  final Color fillColor;
  final ValueChanged<Rect> onCropChanged;
  final ValueChanged<Offset> onPaintStart;
  final void Function(Offset current, Offset start) onPaintUpdate;
  final VoidCallback onPaintEnd;

  /// Throws the stroke in flight away instead of committing it.
  ///
  /// What a second finger landing means: the gesture was a pinch all along, so
  /// the dab the first finger had already laid down was never intended. Ending
  /// it instead — which is what this did at first — leaves a stray dot on the
  /// artwork every time you zoom.
  final VoidCallback onPaintCancel;

  @override
  State<RetouchCanvas> createState() => _RetouchCanvasState();
}

class _RetouchCanvasState extends State<RetouchCanvas> {
  /// Which crop handle the current drag grabbed, or null for a whole-rect move.
  CropHandle? _handle;
  int? _pointer;
  Offset _dragStartNorm = Offset.zero;
  Rect _cropAtDragStart = Rect.zero;

  static const double _handleHitRadius = 28;

  /// Tighter than a corner's, so the two zones on a short edge do not swallow
  /// the corners either side of them.
  static const double _edgeHandleHitRadius = 20;

  /// The whole reachable area, before any zoom.
  ///
  /// Normally just the image. With expand on it opens out by [kMaxExpand] on
  /// every side, so the reachable area and the visible area are the same thing
  /// — you can drag exactly as far as you can see, and the fill is previewed
  /// live in the margin rather than appearing only on Apply.
  Rect get _base => widget.expand
      ? const Rect.fromLTRB(
          -kMaxExpand,
          -kMaxExpand,
          1 + kMaxExpand,
          1 + kMaxExpand,
        )
      : const Rect.fromLTRB(0, 0, 1, 1);

  /// Where the artwork sits on the stage, and how big.
  ///
  /// Null until the first layout, because a fit needs a viewport to fit into.
  ///
  /// This replaced a normalised sub-rect of the document — a "window" narrowed
  /// to magnify. That model could not express the two things the stage most
  /// needed: it could not go below fit, because a sub-rect cannot be bigger
  /// than the thing it is a sub-rect of, and it could not use the room the
  /// chrome was not occupying, because the artwork was letterboxed into a fixed
  /// box and zoom only ever narrowed the window inside it. The stage rect was
  /// identical at 1x and at 12x.
  StageTransform? _t;

  /// The capture as the user sees it, in pixels.
  Size get _imageSize => widget.orientation.sizeOf(
    Size(widget.image.width.toDouble(), widget.image.height.toDouble()),
  );

  /// What the stage frames, which differs by mode.
  ///
  /// In crop mode it is the whole reachable area, because that is what the
  /// marquee is dragged around inside. While drawing it is the *crop* — the
  /// pixels that will actually survive — so there is nothing on screen that
  /// will not be in the result.
  Rect get _documentRect => widget.cropMode ? _base : widget.crop;

  /// The transform, re-fitted to [box] if the layout or the mode has moved
  /// under it since last time.
  StageTransform _fitTo(Size box, EdgeInsets chrome) {
    final current = _t;
    if (current != null &&
        current.viewport == box &&
        current.chromeInsets == chrome &&
        current.document == _documentRect) {
      return current;
    }
    // Re-fitted rather than carried over. Switching mode changes what the stage
    // is *about*, and the deliberate zoom-out that crop mode has always done is
    // this fit rather than a special case anywhere else.
    final next = StageTransform(
      document: _documentRect,
      viewport: box,
      scale: 1,
      offset: Offset.zero,
      chromeInsets: chrome,
    ).fitted(_imageSize);
    // Assigned outside setState on purpose: this runs inside build, and the
    // value is derived from the constraints build was already handed.
    _t = next;
    return next;
  }

  /// How far in the stage is, relative to fit — which is what the badge shows
  /// and what "1x" means to someone looking at it.
  double get _zoomRatio {
    final t = _t;
    if (t == null) return 1;
    final fit = t.fitScale(_imageSize);
    return fit <= 0 ? 1 : t.scale / fit;
  }

  /// Zooms to [target] stage-pixels-per-document-width, pinning [local].
  void _zoomAbout(double target, Offset local) {
    final t = _t;
    if (t == null) return;
    final next = t.zoomAbout(target, local, _imageSize);
    if (identical(next, t)) return;
    setState(() => _t = next);
  }

  /// Zooms by a factor of the *current* magnification.
  void _zoomBy(double factor, Offset local) {
    final t = _t;
    if (t == null) return;
    _zoomAbout(t.scale * factor, local);
  }

  /// Slides the artwork by a stage-space delta.
  ///
  /// No "only when zoomed in" guard any more. A stage that is bigger than the
  /// artwork is the normal case now, and being able to slide the picture
  /// out from under the tool dock to see what is behind it is the point.
  void _panBy(Offset delta) {
    final t = _t;
    if (t == null) return;
    setState(() => _t = t.panned(delta, _imageSize));
  }

  /// The zoom a trackpad gesture began at. See the note on the canvas
  /// viewport's own copy: `scale` on a pan/zoom update is cumulative, so
  /// applying it to the live zoom every frame compounds.
  double? _gestureZoom;

  /// A trackpad gesture over the stage: two-finger scroll pans, pinch zooms.
  ///
  /// The path a Mac actually uses — a trackpad emits pan/zoom events, not
  /// [PointerScrollEvent], which is a mouse wheel. Handled on [Listener]
  /// alongside the brush's raw pointer events rather than through a recogniser,
  /// so zooming never takes the gesture the brush needs.
  void _onStagePanZoomStart(PointerPanZoomStartEvent event) {
    _gestureZoom = _t?.scale ?? 1;
  }

  void _onStagePanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final start = _gestureZoom;
    if (start == null) return;
    // Negated: `_panBy` takes a stage-space drag of the *content*, and dragging
    // two fingers right should bring the artwork on the left into view.
    if (event.panDelta != Offset.zero) _panBy(-event.panDelta);
    if ((event.scale - 1).abs() > 0.001) {
      _zoomAbout(start * event.scale, event.localPosition);
    }
  }

  void _onStagePanZoomEnd(PointerPanZoomEndEvent event) => _gestureZoom = null;

  // ---------------------------------------------------------------------------
  // Touch pinch
  //
  // The retoucher runs on a phone more than anywhere else — a screenshot is
  // taken on the device and tidied up on it — and a phone has no wheel and no
  // trackpad, so the desktop paths above reach none of it. Without this, "zoom
  // in to paint accurately" was a feature only a desktop user had.
  //
  // Two fingers zoom and pan; one still paints. The brush owns raw pointers on
  // this surface, so the second finger is arbitrated here by hand rather than
  // by a recogniser that would take the gesture away from it.
  // ---------------------------------------------------------------------------

  final Map<int, Offset> _touches = {};
  double? _pinchStartZoom;
  double? _pinchStartSpan;
  Offset? _pinchStartFocal;

  bool get _pinching => _touches.length >= 2;

  (double, Offset)? get _span {
    if (_touches.length < 2) return null;
    final points = _touches.values.toList();
    return ((points[0] - points[1]).distance, (points[0] + points[1]) / 2);
  }

  /// Adopts [event] as a pinch finger. Returns true once two are down, which is
  /// the caller's signal to stop treating the gesture as a stroke.
  bool _pinchDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return false;
    _touches[event.pointer] = event.localPosition;
    final span = _span;
    if (span == null) return false;
    setState(() {
      _pinchStartSpan = span.$1;
      _pinchStartFocal = span.$2;
      _pinchStartZoom = _t?.scale ?? 1;
    });
    // Anchor an object transform here, the moment the second finger lands,
    // rather than on the first move. Waiting for a move throws away whatever
    // the fingers did between touching down and being noticed, so a quick
    // pinch scaled by less than it looked like it should.
    if (_objectAtStart != null) {
      final points = _touches.values.toList();
      final delta = points[0] - points[1];
      _objectStartSpan = delta.distance;
      _objectStartAngle = math.atan2(delta.dy, delta.dx);
    }
    return true;
  }

  void _pinchMove(PointerMoveEvent event) {
    if (!_touches.containsKey(event.pointer)) return;
    _touches[event.pointer] = event.localPosition;

    // Two fingers on a grabbed object scale and turn the object, not the
    // stage. This is the arbitration the whole mode enum exists for: the same
    // two-finger gesture means different things depending on what the first
    // finger landed on, and deciding that at pinch time — rather than by
    // adding a recogniser, which would not arbitrate at all against an
    // ancestor Listener — is what keeps it predictable.
    final grabbed = _objectAtStart;
    if (grabbed != null) {
      _objectPinch(grabbed);
      return;
    }

    final span = _span;
    final startSpan = _pinchStartSpan;
    final startZoom = _pinchStartZoom;
    final startFocal = _pinchStartFocal;
    if (span == null || startSpan == null || startZoom == null) return;
    if (startSpan < 1) return;

    // Pan from the midpoint drifting, before the zoom, so the zoom's focal
    // point is where the fingers are now rather than where they started.
    if (startFocal != null && span.$2 != startFocal) {
      _panBy(span.$2 - startFocal);
      _pinchStartFocal = span.$2;
    }
    _zoomAbout(startZoom * (span.$1 / startSpan), span.$2);
  }

  /// Scales and turns the grabbed object from the finger span and angle.
  void _objectPinch(PlacedOp grabbed) {
    final points = _touches.values.toList();
    if (points.length < 2) return;
    final delta = points[0] - points[1];
    final span = delta.distance;
    final angle = math.atan2(delta.dy, delta.dx);

    final startSpan = _objectStartSpan ??= span;
    final startAngle = _objectStartAngle ??= angle;
    if (startSpan < 1) return;

    final turn = (angle - startAngle) * 180 / math.pi;
    final factor = span / startSpan;
    widget.onObjectChanged?.call(
      grabbed.withPlacement(
        width: (grabbed.width * factor).clamp(0.02, 4.0),
        height: (grabbed.height * factor).clamp(0.02, 4.0),
        rotationDeg: grabbed.rotationDeg + turn,
      ),
    );
  }

  void _pinchUp(PointerEvent event) {
    if (_touches.remove(event.pointer) == null) return;
    if (_touches.length < 2) {
      setState(() {
        _pinchStartSpan = null;
        _pinchStartFocal = null;
        _pinchStartZoom = null;
      });
      // An object transform ends when the pinch does. `onPointerUp` reaches
      // `_onEnd` only for the pointer it is tracking, and a two-finger gesture
      // has already released that one — so without this the edit would sit in
      // the draft for ever and never reach history.
      _endObjectGesture(commit: true);
    }
  }

  /// Back to fit, for the zoom readout's tap target.
  void _resetZoom() {
    final t = _t;
    if (t == null) return;
    setState(() => _t = t.fitted(_imageSize));
  }

  void _onStageSignal(PointerSignalEvent event) {
    // Trackpad pinch on the platforms that report it as a signal; desktop
    // comes through [_onStagePanZoomUpdate] instead.
    if (event is PointerScaleEvent) {
      _zoomBy(event.scale, event.localPosition);
      return;
    }
    if (event is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed) {
      _zoomBy(math.exp(-event.scrollDelta.dy / 250), event.localPosition);
    } else {
      _panBy(-event.scrollDelta);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;

    return LayoutBuilder(
      builder: (context, constraints) {
        final box = Size(constraints.maxWidth, constraints.maxHeight);
        final t = _fitTo(box, widget.chromeInsets);
        final imageSize = _imageSize;

        // Where the artwork actually lands, and how much of it the viewport can
        // see. The raster is built for the visible part only, so a 12x zoom
        // costs no more to paint than a 1x one.
        final content = t.contentRect(imageSize);
        final visible = content.intersect(Offset.zero & box);
        final hasContent = visible.width > 0.5 && visible.height > 0.5;
        final crop = hasContent
            ? Rect.fromPoints(
                t.toDocument(visible.topLeft, imageSize),
                t.toDocument(visible.bottomRight, imageSize),
              )
            : t.document;

        // Raw pointer events over the WHOLE viewport, not over a box the size
        // of the artwork. That is what lets a pinch start anywhere, a pan reach
        // the far side of a zoomed-in capture, and the picture be slid out from
        // under the tool dock.
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: _onStageSignal,
          onPointerPanZoomStart: _onStagePanZoomStart,
          onPointerPanZoomUpdate: _onStagePanZoomUpdate,
          onPointerPanZoomEnd: _onStagePanZoomEnd,
          onPointerDown: (e) {
            // A second finger turns the gesture into a pinch. The stroke in
            // flight is discarded rather than ended: the gesture was a pinch
            // all along, so the dab the first finger laid down was never meant
            // to be there.
            if (_pinchDown(e)) {
              // A second finger on a GRABBED OBJECT turns the drag into a
              // scale and a turn of that object, so the grab is kept.
              // Cancelling is right for a brush — the dab the first finger
              // laid down was never meant to be there — but an object was
              // deliberately taken hold of, and dropping it because a second
              // finger arrived is what made pinch-to-resize impossible.
              if (_objectAtStart != null) {
                _pointer = null;
                return;
              }
              if (_pointer != null) {
                _pointer = null;
                _onCancel();
              }
              return;
            }
            if (_pointer != null) return;
            _pointer = e.pointer;
            _onStart(e.localPosition);
          },
          onPointerMove: (e) {
            if (_pinching) {
              _pinchMove(e);
              return;
            }
            if (_pointer != e.pointer) return;
            _onUpdate(e.localPosition);
          },
          onPointerUp: (e) {
            _pinchUp(e);
            if (_pointer != e.pointer) return;
            _pointer = null;
            _onEnd();
            _maybeDoubleTap(e);
          },
          onPointerCancel: (e) {
            _pinchUp(e);
            if (_pointer != e.pointer) return;
            _pointer = null;
            // Cancelled, not finished. A system cancel — a call arriving, the
            // app going to the background, the gesture being stolen — used to
            // run the same path as lifting a finger, which committed the
            // half-drawn op to history and left a stray mark on the artwork.
            _onCancel();
          },
          child: Stack(
            children: [
              // The work surface, filling everything. It is a surface rather
              // than nothing so the stage still reads as a place while the
              // image decodes and wherever the capture is transparent.
              Positioned.fill(child: ColoredBox(color: s.canvas)),
              if (hasContent)
                Positioned.fromRect(
                  rect: visible,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: s.well),
                    child: CustomPaint(
                      painter: _RetouchPainter(
                        selection: widget.selection,
                        imageSize: imageSize,
                        image: widget.image,
                        orientation: widget.orientation,
                        // The visible slice in both modes, so what the composer
                        // rasterises is exactly what fits on screen.
                        crop: crop,
                        view: crop,
                        ops: [...widget.ops, ?widget.draft],
                        frame: widget.crop,
                        cropOverlay: widget.cropMode ? widget.crop : null,
                        fill: widget.fill,
                        fillColor: widget.fillColor,
                        adjustments: widget.adjustments,
                        accent: s.accent,
                        onAccent: s.onAccent,
                        pixels: widget.pixels,
                      ),
                    ),
                  ),
                ),
              // Only once it is off fit. At fit there is nothing to say and
              // nothing to undo, and a permanent badge over the artwork is one
              // more thing between the user and the pixels being retouched.
              if ((_zoomRatio - 1).abs() > 0.01)
                Positioned(
                  right: StudioSpace.l,
                  // Under the top bar, not above the dock. The bottom inset
                  // reserves only the dock's COLLAPSED height — deliberately,
                  // so opening a panel does not re-fit the artwork — which
                  // means an expanded panel sits over anything placed against
                  // it. The badge went straight behind the tool strip.
                  top: widget.chromeInsets.top + StudioSpace.l,
                  child: _StageZoomBadge(zoom: _zoomRatio, onReset: _resetZoom),
                ),
            ],
          ),
        );
      },
    );
  }

  /// The object being transformed, as it was when the gesture began.
  ///
  /// Held rather than read back each frame because a scale is relative to where
  /// the fingers started: reading the live value would compound, and a slow
  /// pinch would accelerate away.
  PlacedOp? _objectAtStart;

  /// Where inside the object the finger landed, in document space, so a drag
  /// moves it from the point that was grabbed rather than snapping its centre
  /// to the finger.
  Offset _objectGrab = Offset.zero;

  /// The finger span and angle a two-finger object gesture began at.
  double? _objectStartSpan;
  double? _objectStartAngle;

  /// The topmost placed object under [normalised], or null.
  ///
  /// Searched back to front so the one you can actually see at that point is
  /// the one that answers.
  PlacedOp? _placedUnder(Offset normalised) {
    final selectable = widget.selectable;
    for (final op in widget.ops.reversed) {
      if (op is PlacedOp &&
          (selectable == null || selectable(op)) &&
          op.hitTest(normalised, _imageSize)) {
        return op;
      }
    }
    return null;
  }

  /// The last tap, for the double-tap that toggles fit and 1:1.
  ///
  /// Timed by hand rather than with a `DoubleTapGestureRecognizer`, for the
  /// reason this whole canvas uses raw pointers: a recogniser claims the
  /// touch-down the brush needs, with no slop threshold, and a paint tool that
  /// waits to find out whether you meant to double-tap does not feel like a
  /// paint tool.
  Duration? _lastTapAt;
  Offset? _lastTapPoint;

  void _maybeDoubleTap(PointerUpEvent event) {
    // Not while painting. The first tap's dab is committed by the time the
    // second arrives — deliberately, because a paint tool that waits to find
    // out whether you meant to double-tap does not feel like one — so a
    // double-tap to zoom in Draw or Hide would leave two marks behind as well
    // as zooming. Two taps with a brush means two dots, and it should.
    // Nor on objects, where a second tap opens a text layer's words.
    if (widget.paints || widget.objectMode) return;
    final t = _t;
    if (t == null) return;
    final at = event.timeStamp;
    final was = _lastTapAt;
    final wasAt = _lastTapPoint;
    if (was != null &&
        wasAt != null &&
        at - was < kDoubleTapTimeout &&
        (event.localPosition - wasAt).distance < kDoubleTapSlop) {
      _lastTapAt = null;
      _lastTapPoint = null;
      final fit = t.fitScale(_imageSize);
      // Toggle: away from fit goes back to fit, at fit goes to 1:1 with the
      // capture's own pixels, which is the magnification a retoucher wants.
      final oneToOne = _imageSize.width / math.max(t.document.width, 1e-9);
      final target = (t.scale / fit - 1).abs() < 0.01 ? oneToOne : fit;
      _zoomAbout(target, event.localPosition);
      return;
    }
    _lastTapAt = at;
    _lastTapPoint = event.localPosition;
  }

  /// Canvas-local position → normalised source-image coordinate.
  /// Where on the artwork a point on the stage lands.
  ///
  /// Both modes map through [_view], which is the rect the painter was handed
  /// (see the `_RetouchPainter` call above, `crop: view, view: view`). They did
  /// not: draw mode mapped through `widget.crop` instead, so the moment zoom
  /// narrowed the view the finger and the paint disagreed — at 4x a stroke
  /// landed about four times as far from the cursor as it should, and further
  /// the more you had panned.
  ///
  /// That is the same defect the comment on [_view] describes being fixed for
  /// the painter. Only half of it was: the painter was moved onto the view and
  /// the pointer was left behind. One rect for both is what stops it returning
  /// a third time.
  Offset _toImage(Offset local) {
    final t = _t;
    if (t == null) return Offset.zero;
    final at = t.toDocument(local, _imageSize);
    final x = at.dx;
    final y = at.dy;
    final view = t.document;

    if (widget.cropMode) {
      // Clamped to what is on screen: a marquee dragged off the stage should
      // stop at the edge of the visible area, which is the thing being
      // dragged around in.
      return Offset(
        x.clamp(view.left, view.right),
        y.clamp(view.top, view.bottom),
      );
    }
    // Clamped to the artwork instead: a stroke that runs off the stage stops
    // at the edge of the document rather than painting into space that is not
    // part of it.
    return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
  }

  void _onStart(Offset local) {
    final normalised = _toImage(local);
    _dragStartNorm = normalised;
    _downLocal = local;
    _tapCandidate = null;

    if (widget.objectMode && !widget.cropMode) {
      // A grip on the selected object first: it sits on the object's edge,
      // where a plain hit test would find the object — or whatever is under
      // the corner — and start a move instead of a resize.
      final grip = _gripUnder(local);
      if (grip != null) {
        _gripDrag = grip;
        return;
      }
      // Selection and the grab are one decision, taken here rather than split
      // between the screen and the canvas: the canvas is what knows the
      // geometry, and a selection that arrived a frame later would make the
      // first few pixels of every drag move the wrong thing.
      final hit = _placedUnder(normalised);
      if (hit != null && hit.id == widget.selection?.id) _tapCandidate = hit.id;
      widget.onSelectObject?.call(hit?.id);
      if (hit != null) {
        _objectAtStart = hit;
        _objectGrab = normalised - hit.center;
        return;
      }
      // Nothing there to grab: a tool that draws its objects draws one.
      if (!widget.paints) return;
    }

    if (widget.pans && !widget.paints && !widget.cropMode) {
      _panFrom = local;
      return;
    }

    if (!widget.cropMode) {
      _painting = true;
      widget.onPaintStart(normalised);
      return;
    }

    _cropAtDragStart = widget.crop;
    _handle = _handleUnder(local);
    widget.onCropStart?.call();
  }

  void _onUpdate(Offset local) {
    final normalised = _toImage(local);
    if ((local - _downLocal).distance > kTouchSlop) _tapCandidate = null;

    final grip = _gripDrag;
    if (grip != null) {
      _dragGrip(grip, local);
      return;
    }

    final from = _panFrom;
    if (from != null) {
      _panBy(local - from);
      _panFrom = local;
      return;
    }

    final grabbed = _objectAtStart;
    if (grabbed != null) {
      widget.onObjectChanged?.call(
        grabbed.withPlacement(center: normalised - _objectGrab),
      );
      return;
    }

    if (widget.objectMode && !widget.paints && !widget.cropMode) return;

    if (!widget.cropMode) {
      widget.onPaintUpdate(normalised, _dragStartNorm);
      return;
    }

    final delta = normalised - _dragStartNorm;

    if (_handle == null) {
      widget.onCropChanged(
        clampCrop(_cropAtDragStart.shift(delta), expand: widget.expand),
      );
      return;
    }

    widget.onCropChanged(
      resizeCropFromCorner(
        base: _cropAtDragStart,
        handle: _handle!,
        pointer: normalised,
        // The picture as the user sees it: a quarter turn swaps its sides,
        // and the ratio maths against the file's own would lock the crop to
        // the wrong shape.
        imageSize: _imageSize,
        targetAspect: widget.targetAspect,
        expand: widget.expand,
        lockAspect: widget.lockAspect,
      ),
    );
  }

  /// Abandons the gesture in flight. See [_RetouchCanvas.onPaintCancel].
  void _onCancel() {
    _tapCandidate = null;
    _panFrom = null;
    _painting = false;
    if (_endGripDrag(commit: false)) return;
    if (_endObjectGesture(commit: false)) return;
    if (widget.cropMode) {
      _handle = null;
      widget.onCropEnd?.call();
    } else {
      widget.onPaintCancel();
    }
  }

  void _onEnd() {
    final tapped = _tapCandidate;
    _tapCandidate = null;
    if (_panFrom != null) {
      _panFrom = null;
      return;
    }
    if (_endGripDrag(commit: true)) return;
    if (_endObjectGesture(commit: true)) {
      if (tapped != null) widget.onObjectTap?.call(tapped);
      return;
    }
    if (widget.cropMode) {
      _handle = null;
      widget.onCropEnd?.call();
    } else if (_painting) {
      _painting = false;
      widget.onPaintEnd();
    }
  }

  // ---------------------------------------------------------------------------
  // Object grips: the four corners resize, the knob above the top edge turns.
  // ---------------------------------------------------------------------------

  /// Where the finger went down, for telling a tap from a drag.
  Offset _downLocal = Offset.zero;

  /// The already-selected object a tap landed on, until the finger moves far
  /// enough to make it a drag.
  int? _tapCandidate;

  /// The last point of a one-finger pan, while one is running.
  Offset? _panFrom;

  /// Whether the gesture in flight is drawing — and so owes the screen an end
  /// or a cancel. A drag that grabbed an object ends as an object gesture,
  /// and ending a stroke that never began would be a second, empty one.
  bool _painting = false;

  _GripDrag? _gripDrag;

  static const double _gripHitRadius = 24;

  /// How far the turn knob stands off the top edge, in screen pixels.
  static const double knobOffset = 30;

  /// The selected object's corners on the stage, or null for no selection.
  List<Offset>? _selectionOnStage() {
    final selection = widget.selection;
    final t = _t;
    if (selection == null || t == null || !widget.objectMode) return null;
    return [
      for (final c in selection.corners(_imageSize)) t.toStage(c, _imageSize),
    ];
  }

  _GripDrag? _gripUnder(Offset local) {
    final corners = _selectionOnStage();
    final selection = widget.selection;
    if (corners == null || selection == null) return null;
    final centre = (corners[0] + corners[2]) / 2;
    final knob = turnKnob(corners);
    if (knob != null && (knob - local).distance <= _gripHitRadius) {
      return _GripDrag.turn(selection, centre, local);
    }
    // Inside a small object a press is a move unless it is right on a grip.
    // At full reach the grips of an area over one line of text — fifteen
    // pixels tall at fit — covered all of it, and it could be stretched but
    // never picked up. Outside the object the grips keep their whole reach,
    // since nothing else there could have been meant.
    final inside = _within(corners, local);
    final wide = (corners[1] - corners[0]).distance;
    final tall = (corners[3] - corners[0]).distance;
    double reach(double across) =>
        inside ? math.min(_gripHitRadius, across / 3) : _gripHitRadius;
    final cornerReach = reach(math.min(wide, tall));
    for (final corner in corners) {
      if ((corner - local).distance <= cornerReach) {
        return _GripDrag.resize(selection, centre, local);
      }
    }
    if (hasSideGrips(selection)) {
      for (var side = 0; side < 4; side++) {
        final length = (corners[(side + 1) % 4] - corners[side]).distance;
        // Only where a bar is drawn: an invisible grip is a trap.
        if (length < minSideForGrip) continue;
        final mid = (corners[side] + corners[(side + 1) % 4]) / 2;
        // Top and bottom are pulled across the height, the others the width.
        if ((mid - local).distance <= reach(side.isEven ? tall : wide)) {
          return _GripDrag.side(selection, centre, local, side, corners);
        }
      }
    }
    return null;
  }

  /// A side shorter than this has no grip of its own — there is no room for
  /// one between the corners.
  static const double minSideForGrip = 36;

  /// Whether [point] is inside the quad with these [corners], in order.
  static bool _within(List<Offset> corners, Offset point) {
    var sign = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = corners[i], b = corners[(i + 1) % 4];
      final cross =
          (b.dx - a.dx) * (point.dy - a.dy) - (b.dy - a.dy) * (point.dx - a.dx);
      if (cross == 0) continue;
      if (sign == 0) {
        sign = cross.sign;
      } else if (cross.sign != sign) {
        return false;
      }
    }
    return true;
  }

  /// Whether [op] has grips on its sides as well as its corners.
  ///
  /// Not text, whose size is its type: a side pulled out would either stretch
  /// the letters or change nothing that could be seen.
  static bool hasSideGrips(PlacedOp op) => op is! TextOp;

  /// The turn knob for a box with these stage corners, or null when the box is
  /// too small to have a top edge worth pointing away from.
  static Offset? turnKnob(List<Offset> corners) {
    final centre = (corners[0] + corners[2]) / 2;
    final top = (corners[0] + corners[1]) / 2;
    final away = top - centre;
    final length = away.distance;
    if (length < 1) return null;
    return top + away / length * knobOffset;
  }

  void _dragGrip(_GripDrag grip, Offset local) {
    final object = grip.object;
    switch (grip.kind) {
      case _GripKind.resize:
        final from = (grip.start - grip.centre).distance;
        if (from < 1) return;
        final factor = ((local - grip.centre).distance / from).clamp(
          0.05,
          20.0,
        );
        widget.onObjectChanged?.call(
          object.withPlacement(
            width: (object.width * factor).clamp(0.01, 4.0),
            height: (object.height * factor).clamp(0.01, 4.0),
          ),
        );
      case _GripKind.turn:
        final a0 = math.atan2(
          grip.start.dy - grip.centre.dy,
          grip.start.dx - grip.centre.dx,
        );
        final a1 = math.atan2(
          local.dy - grip.centre.dy,
          local.dx - grip.centre.dx,
        );
        var degrees = object.rotationDeg + (a1 - a0) * 180 / math.pi;
        // Settles on the square angles, which is nearly always what a small
        // miss meant.
        final nearest = (degrees / 90).round() * 90;
        if ((degrees - nearest).abs() < 4) degrees = nearest.toDouble();
        widget.onObjectChanged?.call(
          object.withPlacement(rotationDeg: degrees),
        );
      case _GripKind.side:
        _dragSide(grip, local);
    }
  }

  /// A side pulled in or out: the opposite side stays where it is and this one
  /// follows the finger, along the object's own axis however it is turned.
  ///
  /// A picture is cropped rather than stretched — the side moves through its
  /// pixels, as far as there are pixels to show — and everything else takes
  /// the new shape.
  void _dragSide(_GripDrag grip, Offset local) {
    final t = _t;
    final c = grip.corners;
    if (t == null || c == null) return;
    final across = c[1] - c[0];
    final down = c[3] - c[0];
    final wide = across.distance, tall = down.distance;
    if (wide < 1 || tall < 1) return;
    final u = across / wide, v = down / tall;
    // Sides run top, right, bottom, left.
    final side = grip.side;
    final (Offset fixed, Offset axis, double start) = switch (side) {
      0 => ((c[3] + c[2]) / 2, -v, tall),
      1 => ((c[0] + c[3]) / 2, u, wide),
      2 => ((c[0] + c[1]) / 2, v, tall),
      _ => ((c[1] + c[2]) / 2, -u, wide),
    };
    final along = local - fixed;
    final reach = math.max(12.0, along.dx * axis.dx + along.dy * axis.dy);
    var ratio = reach / start;
    final horizontal = side.isOdd;
    final object = grip.object;

    PlacedOp next;
    if (object is ImageOp) {
      final crop = object.crop;
      // A mirrored picture shows its source's left side on the box's right.
      final sourceSide = object.flipH && horizontal
          ? (side == 1 ? 3 : 1)
          : side;
      final maxRatio = switch (sourceSide) {
        0 => crop.bottom / crop.height,
        1 => (1 - crop.left) / crop.width,
        2 => (1 - crop.top) / crop.height,
        _ => crop.right / crop.width,
      };
      ratio = ratio.clamp(0.05, maxRatio);
      final shown = switch (sourceSide) {
        0 => Rect.fromLTRB(
          crop.left,
          crop.bottom - crop.height * ratio,
          crop.right,
          crop.bottom,
        ),
        1 => Rect.fromLTRB(
          crop.left,
          crop.top,
          crop.left + crop.width * ratio,
          crop.bottom,
        ),
        2 => Rect.fromLTRB(
          crop.left,
          crop.top,
          crop.right,
          crop.top + crop.height * ratio,
        ),
        _ => Rect.fromLTRB(
          crop.right - crop.width * ratio,
          crop.top,
          crop.right,
          crop.bottom,
        ),
      };
      next = object.copyWith(crop: shown);
    } else {
      ratio = ratio.clamp(0.02, 50.0);
      next = object;
    }
    final centre = t.toDocument(fixed + axis * (start * ratio / 2), _imageSize);
    widget.onObjectChanged?.call(
      next.withPlacement(
        center: centre,
        width: horizontal ? object.width * ratio : null,
        height: horizontal ? null : object.height * ratio,
      ),
    );
  }

  bool _endGripDrag({required bool commit}) {
    final grip = _gripDrag;
    if (grip == null) return false;
    _gripDrag = null;
    if (commit) {
      widget.onObjectCommitted?.call();
    } else {
      widget.onObjectChanged?.call(grip.object);
    }
    return true;
  }

  /// Closes an object transform, if one was running. Returns whether it was.
  bool _endObjectGesture({required bool commit}) {
    final started = _objectAtStart;
    if (started == null) return false;
    _objectAtStart = null;
    _objectStartSpan = null;
    _objectStartAngle = null;
    if (commit) {
      widget.onObjectCommitted?.call();
    } else {
      // Put the object back where the gesture found it. Reporting the original
      // is cheaper and clearer than asking the caller to unwind a draft, and it
      // is the one value that is definitely correct.
      widget.onObjectChanged?.call(started);
    }
    return true;
  }

  /// The crop grip under [local], or null when the drag should move the whole
  /// window instead.
  ///
  /// Corners are tested before edges. On a small marquee the two zones overlap,
  /// and grabbing a corner is the more specific intent — an edge is what you
  /// reach for when you deliberately want one axis to stay put.
  CropHandle? _handleUnder(Offset local) {
    final t = _t;
    if (t == null) return null;
    double sx(double x) => t.toStage(Offset(x, 0), _imageSize).dx;
    double sy(double y) => t.toStage(Offset(0, y), _imageSize).dy;
    final r = Rect.fromLTRB(
      sx(widget.crop.left),
      sy(widget.crop.top),
      sx(widget.crop.right),
      sy(widget.crop.bottom),
    );
    final grips = <CropHandle, Offset>{
      CropHandle.topLeft: r.topLeft,
      CropHandle.topRight: r.topRight,
      CropHandle.bottomLeft: r.bottomLeft,
      CropHandle.bottomRight: r.bottomRight,
      CropHandle.left: Offset(r.left, r.center.dy),
      CropHandle.right: Offset(r.right, r.center.dy),
      CropHandle.top: Offset(r.center.dx, r.top),
      CropHandle.bottom: Offset(r.center.dx, r.bottom),
    };
    for (final entry in grips.entries) {
      final radius = entry.key.isCorner
          ? _handleHitRadius
          : _edgeHandleHitRadius;
      if ((entry.value - local).distance <= radius) return entry.key;
    }
    return null;
  }
}

class _RetouchPainter extends CustomPainter {
  _RetouchPainter({
    required this.image,
    required this.crop,
    required this.frame,
    required this.view,
    required this.adjustments,
    required this.orientation,
    required this.ops,
    required this.cropOverlay,
    required this.fill,
    required this.fillColor,
    required this.accent,
    required this.onAccent,
    required this.selection,
    required this.imageSize,
    this.pixels,
  }) : pixelsReady = pixels?.isReady ?? false;

  final ui.Image image;
  final Rect crop;

  /// The photo's pixels, for a pixelated area's cells, and whether they had
  /// been read when this was built — a repaint is due the moment they are.
  final PixelSampler? pixels;
  final bool pixelsReady;

  /// The finished picture's edges, for the vignette — see
  /// [ScreenshotComposer.frame].
  final Rect frame;

  /// The placed object to outline, or null when nothing is selected.
  final PlacedOp? selection;

  /// The oriented capture's size in pixels, which the selection's own geometry
  /// is stated against.
  final Size imageSize;

  /// The region of image space the canvas covers. Equal to [crop] in crop mode;
  /// used to place the marquee, which is in image space while the canvas is in
  /// view space.
  final Rect view;

  final List<EditOp> ops;

  /// When set, the whole view is shown and this normalised rect is the bright
  /// window inside the dimmed surround.
  final Rect? cropOverlay;

  final ExpandFill fill;
  final Color fillColor;
  final ImageAdjustments adjustments;

  /// How the capture is turned. Rects here are fractions of the turned
  /// picture, so this has to travel with them.
  final ImageOrientation orientation;
  final Color accent;
  final Color onAccent;

  @override
  void paint(Canvas canvas, Size size) {
    final dest = Offset.zero & size;

    if (ops.any((op) => op is RemoveBackgroundOp)) _paintChecker(canvas, dest);

    ScreenshotComposer(
      image: image,
      crop: crop,
      ops: ops,
      fill: fill,
      fillColor: fillColor,
      adjustments: adjustments,
      orientation: orientation,
      frame: frame,
      pixels: pixels,
    ).paint(canvas, dest);

    _paintSelection(canvas, size);

    final overlay = cropOverlay;
    if (overlay == null) return;

    double sx(double x) => (x - view.left) / view.width * size.width;
    double sy(double y) => (y - view.top) / view.height * size.height;
    final window = Rect.fromLTRB(
      sx(overlay.left),
      sy(overlay.top),
      sx(overlay.right),
      sy(overlay.bottom),
    );

    // Dim everything outside the window with a single even-odd fill.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(dest),
        Path()..addRect(window),
      ),
      Paint()..color = const Color(0x99000000),
    );

    // Marquee + rule of thirds.
    final line = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(window, line);

    final guide = Paint()
      ..color = onAccent.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final dx = window.left + window.width * i / 3;
      final dy = window.top + window.height * i / 3;
      canvas.drawLine(Offset(dx, window.top), Offset(dx, window.bottom), guide);
      canvas.drawLine(Offset(window.left, dy), Offset(window.right, dy), guide);
    }

    // Grips: a square at each corner, and a bar at the middle of each side.
    //
    // The side bars are drawn as bars rather than squares on purpose — the
    // shape states which way it moves, so a grip that stretches only the width
    // does not look like a grip that resizes both axes.
    const grip = 14.0;
    const barThickness = 5.0;
    const barLength = 26.0;
    final gripFill = Paint()..color = accent;
    final ring = Paint()
      ..color = onAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final corner in [
      window.topLeft,
      window.topRight,
      window.bottomLeft,
      window.bottomRight,
    ]) {
      final r = Rect.fromCenter(center: corner, width: grip, height: grip);
      canvas.drawRect(r, gripFill);
      canvas.drawRect(r, ring);
    }

    // Only worth painting where the side is long enough to hold a bar that is
    // not longer than the edge it sits on.
    void sideGrip(Offset centre, {required bool vertical}) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: centre,
          width: vertical ? barThickness : barLength,
          height: vertical ? barLength : barThickness,
        ),
        const Radius.circular(barThickness / 2),
      );
      canvas.drawRRect(r, gripFill);
      canvas.drawRRect(r, ring);
    }

    if (window.height > barLength + grip) {
      sideGrip(Offset(window.left, window.center.dy), vertical: true);
      sideGrip(Offset(window.right, window.center.dy), vertical: true);
    }
    if (window.width > barLength + grip) {
      sideGrip(Offset(window.center.dx, window.top), vertical: false);
      sideGrip(Offset(window.center.dx, window.bottom), vertical: false);
    }
  }

  /// The selected object's outline and grips.
  ///
  /// Chrome, not content: drawn after the composer, so none of it can reach an
  /// export — the composer is what a PNG gets and everything below this line
  /// exists only while the screen is on. In the same accent as the crop marquee
  /// so the two read as one editor rather than two.
  void _paintSelection(Canvas canvas, Size size) {
    final op = selection;
    if (op == null) return;

    double sx(double x) => (x - view.left) / view.width * size.width;
    double sy(double y) => (y - view.top) / view.height * size.height;

    final corners = [
      for (final c in op.corners(imageSize)) Offset(sx(c.dx), sy(c.dy)),
    ];

    // The outline follows the rotated box as a path rather than a rect, which
    // is the whole reason `corners` exists: a turned object outlined with its
    // bounding rect reads as a selection of something else.
    final outline = Path()..addPolygon(corners, true);
    canvas.drawPath(
      outline,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Grips are a screen size, not a document one: a handle has to stay the
    // same number of millimetres under the finger at every zoom, so it is sized
    // here in destination pixels and never stored normalised.
    const grip = 12.0;
    final gripFill = Paint()..color = accent;
    final ring = Paint()
      ..color = onAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final corner in corners) {
      final r = Rect.fromCenter(center: corner, width: grip, height: grip);
      canvas.drawRect(r, gripFill);
      canvas.drawRect(r, ring);
    }

    // A bar on each side, along it, where the object has side grips.
    if (_RetouchCanvasState.hasSideGrips(op)) {
      for (var side = 0; side < 4; side++) {
        final a = corners[side], b = corners[(side + 1) % 4];
        final edge = b - a;
        if (edge.distance < _RetouchCanvasState.minSideForGrip) continue;
        canvas.save();
        canvas.translate((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        canvas.rotate(math.atan2(edge.dy, edge.dx));
        final bar = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 18, height: 6),
          const Radius.circular(3),
        );
        canvas.drawRRect(bar, gripFill);
        canvas.drawRRect(bar, ring);
        canvas.restore();
      }
    }

    // The turn knob, on a stalk from the middle of the top edge.
    final knob = _RetouchCanvasState.turnKnob(corners);
    if (knob != null) {
      final top = (corners[0] + corners[1]) / 2;
      canvas.drawLine(
        top,
        knob,
        Paint()
          ..color = accent
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(knob, 8, gripFill);
      canvas.drawCircle(knob, 8, ring);
    }
  }

  /// The grey-and-white squares behind a photo with its background removed,
  /// so what is now transparent reads as transparent rather than as the
  /// stage's own grey — the same squares every image editor uses for it.
  static void _paintChecker(Canvas canvas, Rect rect) {
    const cell = 8.0;
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = const Color(0xFFF2F2F2));
    final dark = Path();
    var row = 0;
    for (var y = rect.top; y < rect.bottom; y += cell, row++) {
      for (
        var x = rect.left + (row.isOdd ? cell : 0);
        x < rect.right;
        x += cell * 2
      ) {
        dark.addRect(Rect.fromLTWH(x, y, cell, cell));
      }
    }
    canvas.drawPath(dark, Paint()..color = const Color(0xFFD9D9D9));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RetouchPainter old) =>
      old.image != image ||
      old.crop != crop ||
      old.frame != frame ||
      old.adjustments != adjustments ||
      old.orientation != orientation ||
      old.view != view ||
      old.ops != ops ||
      old.cropOverlay != cropOverlay ||
      old.fill != fill ||
      old.fillColor != fillColor ||
      old.selection != selection ||
      old.imageSize != imageSize ||
      old.pixelsReady != pixelsReady ||
      old.accent != accent;
}

/// The magnification readout over the retouch stage.
///
/// Doubles as the way back: pinching to 6x to clean up one edge is easy, and
/// pinching precisely back to 1:1 is not, so the badge that tells you where you
/// are is also the control that returns you to fit.
class _StageZoomBadge extends StatelessWidget {
  const _StageZoomBadge({required this.zoom, required this.onReset});

  final double zoom;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Material(
      color: s.panel,
      borderRadius: BorderRadius.circular(StudioRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onReset();
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: StudioSpace.m,
            vertical: StudioSpace.s,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${zoom.toStringAsFixed(1)}×',
                style: StudioText.mono(context).copyWith(color: s.textPrimary),
              ),
              SizedBox(width: StudioSpace.s),
              StudioIcon(StudioIcons.reset, size: 12, color: s.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

enum _GripKind { resize, turn, side }

/// A corner, a side or the turn knob taken hold of, with what it started from.
class _GripDrag {
  _GripDrag.resize(this.object, this.centre, this.start)
    : kind = _GripKind.resize,
      side = -1,
      corners = null;
  _GripDrag.turn(this.object, this.centre, this.start)
    : kind = _GripKind.turn,
      side = -1,
      corners = null;
  _GripDrag.side(this.object, this.centre, this.start, this.side, this.corners)
    : kind = _GripKind.side;

  final _GripKind kind;
  final PlacedOp object;

  /// Which side, for a side grip: top, right, bottom, left.
  final int side;

  /// The object's corners on the stage when the side was taken hold of.
  final List<Offset>? corners;

  /// The object's centre and the point grabbed, on the stage.
  final Offset centre;
  final Offset start;
}
