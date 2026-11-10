part of '../editor_screen.dart';

/// A floating zoom readout with reset, for a phone once it has been pinched
/// away from fit. The side layouts have the full [_CanvasToolbar] instead.
class _ZoomDock extends StatelessWidget {
  const _ZoomDock({required this.scale, required this.onReset});

  final double scale;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final atRest = (scale - 1).abs() < 0.001;

    return Container(
      height: StudioSizes.button,
      padding: EdgeInsets.symmetric(horizontal: StudioSpace.xs),
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(StudioRadius.sm),
        border: Border.all(color: s.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: StudioSpace.s),
            child: Text(
              '${(scale * 100).round()}%',
              style: StudioText.mono(context).copyWith(color: s.textPrimary),
            ),
          ),
          StudioIconButton(
            icon: StudioIcons.reset,
            iconSize: 13,
            tooltip: 'Reset zoom',
            onPressed: atRest ? null : onReset,
          ),
        ],
      ),
    );
  }
}

/// Makes whatever it wraps sampleable by the eyedropper.
///
/// Wraps the canvas in a [RepaintBoundary] and, while a pick is armed, covers
/// it with a crosshair layer that reads the colour under the pointer.
///
/// The boundary sits *outside* the zoom transform on purpose: the sample is
/// taken from the pixels as painted, so a tap maps one-to-one onto the captured
/// image with no coordinate maths, and — more to the point — the colour you get
/// is the colour you were looking at, blur, opacity, shadow and all.
class _PickableCanvas extends ConsumerStatefulWidget {
  const _PickableCanvas({required this.child});

  final Widget child;

  @override
  ConsumerState<_PickableCanvas> createState() => _PickableCanvasState();
}

class _PickableCanvasState extends ConsumerState<_PickableCanvas> {
  final _boundary = GlobalKey();

  /// The canvas as painted, captured once when the pick is armed.
  ///
  /// Sampled per pointer move, so re-capturing on every hover would rasterise
  /// the whole workspace at pointer frequency. Nothing can change the canvas
  /// while a pick is in flight — the panels are behind the crosshair layer —
  /// so one snapshot stays correct for the life of the pick.
  ByteData? _pixels;
  int _width = 0;
  int _height = 0;

  /// The same capture kept as an image, for the loupe to magnify.
  ///
  /// Disposed with the rest of the snapshot: a `ui.Image` is native memory and
  /// dropping the reference alone would not release the canvas-sized bitmap.
  ui.Image? _image;

  /// Device pixels per logical pixel in [_pixels].
  ///
  /// The capture is taken at the display's real ratio rather than at 1.0, so a
  /// sample is the exact pixel that was on screen. At 1.0 Flutter rasterises
  /// the whole workspace *downscaled*, which resamples — every colour then
  /// comes back blended with its neighbours, and picking off anything with an
  /// edge in it (a caption, a device bezel, a pattern) returned a colour that
  /// was nowhere in the artwork.
  double _ratio = 1;

  /// The colour under the pointer, for the readout chip and the loupe.
  Color? _hovered;

  /// Where the pointer is, in this widget's coordinates, or null before it has
  /// entered the canvas. Drives the loupe.
  Offset? _pointer;

  /// Held rather than read on demand: `ref` is off limits once the widget is
  /// disposed, and withdrawing the offer is exactly a teardown step.
  late final ScenePickController _pick;

  @override
  void initState() {
    super.initState();
    _pick = ref.read(scenePickProvider.notifier);
    _pick.attach();
  }

  @override
  void dispose() {
    _pick.detach();
    _image?.dispose();
    super.dispose();
  }

  /// The capture in flight, so a click that arrives mid-capture waits for the
  /// one already running instead of starting a second.
  Future<void>? _capturing;

  Future<void> _capture() {
    return _capturing ??= _runCapture().whenComplete(() => _capturing = null);
  }

  Future<void> _runCapture() async {
    final object = _boundary.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return;
    // At the display's real ratio, so the buffer holds the pixels that were
    // actually lit rather than a downscale of them — see [_ratio].
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final image = await object.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _pixels = data;
      _width = image.width;
      _height = image.height;
      _ratio = ratio;
      _image?.dispose();
      _image = image;
    });
  }

  void _clearCapture() {
    _image?.dispose();
    _image = null;
    _pixels = null;
    _width = 0;
    _height = 0;
    _hovered = null;
    _pointer = null;
  }

  /// The colour at [local], which is in this widget's logical coordinates.
  Color? _sample(Offset local) {
    final data = _pixels;
    if (data == null || _width == 0 || _height == 0) return null;
    // Logical in, device out: the buffer is [_ratio] times denser than the
    // coordinates the pointer arrives in.
    final x = (local.dx * _ratio).round().clamp(0, _width - 1);
    final y = (local.dy * _ratio).round().clamp(0, _height - 1);
    final offset = (y * _width + x) * 4;
    if (offset < 0 || offset + 3 >= data.lengthInBytes) return null;
    return Color.fromARGB(
      255,
      data.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
    );
  }

  /// Tracks the pointer for both the readout and the loupe.
  void _track(Offset local) {
    final color = _sample(local);
    if (color == _hovered && local == _pointer) return;
    setState(() {
      _hovered = color;
      _pointer = local;
    });
  }

  Future<void> _commit(Offset local) async {
    // Arming the eyedropper and clicking with it are usually one gesture, and
    // the snapshot costs a frame plus a raster round-trip to land. Without this
    // the first click — the one everybody makes — falls in that window, finds
    // no pixels, and does nothing at all.
    if (_pixels == null) await _capture();
    if (!mounted) return;

    final color = _sample(local);
    if (color == null) return;
    HapticFeedback.selectionClick();
    _pick.complete(color);
  }

  @override
  Widget build(BuildContext context) {
    final picking = ref.watch(
      scenePickProvider.select((state) => state.picking),
    );

    // Arming and disarming both happen outside this build; the capture is
    // scheduled here because it needs the boundary to have painted.
    if (picking && _pixels == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(scenePickProvider).picking) _capture();
      });
    } else if (!picking && _pixels != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_clearCapture);
      });
    }

    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(key: _boundary, child: widget.child),
        ),
        if (picking)
          Positioned.fill(
            child: MouseRegion(
              // No system cursor: the loupe *is* the cursor, and leaving the
              // crosshair under it puts two aiming marks on the same point.
              cursor: SystemMouseCursors.none,
              onHover: (event) => _track(event.localPosition),
              onExit: (_) => setState(() => _pointer = null),
              child: Listener(
                // Raw pointer, so a tap commits without entering the gesture
                // arena the scene's own drag handles compete in.
                onPointerDown: (event) => _track(event.localPosition),
                // Touch has no hover, so a finger has to drag to aim. The
                // colour is taken on release, which is what makes the loupe
                // usable with a fingertip: you slide until the swatch is right
                // and then lift, instead of committing wherever you first
                // landed and hoping.
                onPointerMove: (event) => _track(event.localPosition),
                onPointerUp: (event) => _commit(event.localPosition),
                child: const ColoredBox(color: StudioInk.transparent),
              ),
            ),
          ),
        if (picking && _pointer != null && _image != null)
          _PickLoupe(
            image: _image!,
            ratio: _ratio,
            pointer: _pointer!,
            color: _hovered,
          ),
        if (picking)
          Positioned(
            left: 0,
            right: 0,
            top: StudioSpace.l,
            child: Center(child: _PickHint(color: _hovered)),
          ),
      ],
    );
  }
}

/// The magnifier that rides under the pointer while the eyedropper is armed.
///
/// A colour picker that only tells you the answer after you have committed to
/// it is a guessing game — at screen scale a caption's stroke or a pattern's
/// hairline is a pixel or two wide, and the pointer covers it. The loupe shows
/// the neighbourhood magnified with the target pixel ringed, so aiming is
/// something you can see rather than something you find out afterwards.
///
/// It is also what makes touch work at all: a fingertip covers roughly forty
/// pixels, so without a magnifier offset away from the contact point there is
/// no way to know what is under it.
class _PickLoupe extends StatelessWidget {
  const _PickLoupe({
    required this.image,
    required this.ratio,
    required this.pointer,
    required this.color,
  });

  /// The captured canvas, in device pixels.
  final ui.Image image;

  /// Device pixels per logical pixel in [image].
  final double ratio;

  /// Pointer position in the canvas's logical coordinates.
  final Offset pointer;

  /// The colour under the pointer, for the rim and the readout.
  final Color? color;

  /// Diameter of the glass.
  static const double _size = 116;

  /// How many logical pixels across the glass shows. Eleven is odd on purpose:
  /// an odd count has a true centre cell, so the ringed pixel is the sampled
  /// one rather than one of four sharing the middle.
  static const double _window = 11;

  /// How far above the pointer the glass floats, so a fingertip does not cover
  /// the thing it is aiming with.
  static const double _lift = 78;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;

    return Positioned(
      left: pointer.dx - _size / 2,
      top: pointer.dy - _size / 2 - _lift,
      width: _size,
      height: _size,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // The rim wears the sampled colour, so the answer is readable even
            // at the edge of vision while the eye is on the artwork.
            border: Border.all(color: color ?? s.border, width: 4),
            boxShadow: [
              BoxShadow(
                color: StudioInk.scrim,
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipOval(
            child: CustomPaint(
              painter: _LoupePainter(
                image: image,
                ratio: ratio,
                pointer: pointer,
                window: _window,
                grid: s.border,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoupePainter extends CustomPainter {
  const _LoupePainter({
    required this.image,
    required this.ratio,
    required this.pointer,
    required this.window,
    required this.grid,
  });

  final ui.Image image;
  final double ratio;
  final Offset pointer;
  final double window;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(pointer.dx * ratio, pointer.dy * ratio);
    final src = Rect.fromCenter(
      center: centre,
      width: window * ratio,
      height: window * ratio,
    );

    // `FilterQuality.none`, so the magnified pixels stay squares. Smoothing
    // them would invent colours that are not in the artwork — the exact fault
    // the loupe exists to expose.
    canvas.drawImageRect(
      image,
      src,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.none,
    );

    // The target cell, ringed dark-over-light so it reads on any artwork.
    final cell = size.width / window;
    final target = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: cell,
      height: cell,
    );
    canvas.drawRect(
      target.inflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x99000000),
    );
    canvas.drawRect(
      target,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFFFFFFF),
    );

    // Off the edge of the capture the source rect is empty, which would leave
    // the glass showing whatever was in the buffer before. Mark it instead.
    if (centre.dx < 0 ||
        centre.dy < 0 ||
        centre.dx > image.width ||
        centre.dy > image.height) {
      canvas.drawRect(Offset.zero & size, Paint()..color = grid);
    }
  }

  @override
  bool shouldRepaint(_LoupePainter old) =>
      old.image != image || old.pointer != pointer || old.ratio != ratio;
}

/// The banner shown while the eyedropper is armed.
class _PickHint extends StatelessWidget {
  const _PickHint({required this.color});

  /// The colour under the pointer, or null before it has moved over the canvas.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Container(
      height: StudioSizes.button,
      padding: EdgeInsets.symmetric(horizontal: StudioSpace.l),
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(StudioRadius.sm),
        border: Border.all(color: s.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (color != null) ...[
            StudioSwatch(color: color!, size: 18),
            SizedBox(width: StudioSpace.m),
          ],
          Text(
            color == null
                ? 'Pick a colour from the canvas'
                : '#${color!.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
            style: color == null
                ? StudioText.caption(context).copyWith(color: s.textSecondary)
                : StudioText.mono(context).copyWith(color: s.textPrimary),
          ),
          SizedBox(width: StudioSpace.l),
          Text(
            'Esc to cancel',
            style: StudioText.micro(context).copyWith(color: s.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Pointer-driven zoom and pan over the editable canvas.
///
/// Deliberately built on [Listener] rather than [GestureDetector]: the scene
/// underneath owns real drag gestures (move the frame, move a caption), and a
/// gesture-arena competitor would fight them for every drag. Raw pointer
/// listeners observe without competing, so the two coexist.
///
/// That leaves zoom on the inputs a pointer user has and touch does not —
/// wheel, middle-drag, space-drag — which is exactly the intent: on a
/// touchscreen a pinch still belongs to the scene, where it scales the selected
/// element.
class _CanvasViewport extends StatefulWidget {
  const _CanvasViewport({
    super.key,
    required this.child,
    required this.onScaleChanged,
    required this.hasSelection,
    this.contentWidth,
  });

  final Widget child;
  final ValueChanged<double> onScaleChanged;

  /// Whether the scene has something selected.
  ///
  /// This is what decides who owns a two-finger pinch. With a frame or a
  /// caption selected the pinch is the artwork's — that is what you selected it
  /// for — and the viewport keeps its hands off. With nothing selected there is
  /// no artwork to resize, so the pinch zooms the workspace.
  ///
  /// A rule, not a mode: nothing to toggle, nothing to remember, and the
  /// selection outline on screen already says which one you are about to get.
  final bool hasSelection;

  /// Width of the content when it is wider than the viewport, or null for
  /// content laid out at the viewport's own size.
  ///
  /// The screen strip is the case this exists for: every screen of a set side
  /// by side, far wider than any window. The content is laid out at its full
  /// width *before* the zoom transform, so a screen scrolled in from the right
  /// is hit-testable like one that started on screen — laying it out at the
  /// viewport's width and letting it overflow would paint it but drop every
  /// tap past the viewport's right edge.
  final double? contentWidth;

  @override
  State<_CanvasViewport> createState() => _CanvasViewportState();
}

class _CanvasViewportState extends State<_CanvasViewport>
    with SingleTickerProviderStateMixin {
  double _scale = 1;
  Offset _offset = Offset.zero;

  /// True while the space bar is down, which turns the whole canvas into a pan
  /// surface and locks the scene out of the gesture.
  bool _spaceHeld = false;

  bool get _panMode => _spaceHeld;

  /// True while a pan is actually in flight, for the cursor.
  bool _panning = false;

  Size _viewport = Size.zero;

  /// Low enough for "fit every screen" to show a long set with both side
  /// panels open: at 0.25 an eight-screen listing in a 1440px window stopped
  /// short, the first screen cut off at one edge and the add tile at the other.
  static const double _minScale = 0.1;
  static const double _maxScale = 8;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _glide.dispose();
    super.dispose();
  }

  /// Tracks the space bar without consuming it.
  ///
  /// Always returns false: space is also "activate" for whatever has focus, and
  /// swallowing it here would break that everywhere else on the screen.
  bool _onKey(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.space) return false;
    final held = event is! KeyUpEvent;
    if (held != _spaceHeld) setState(() => _spaceHeld = held);
    return false;
  }

  /// Resets to fit.
  void reset() {
    setState(() {
      _scale = 1;
      _offset = Offset.zero;
    });
    widget.onScaleChanged(1);
  }

  /// Zooms about the centre of the viewport.
  void zoomBy(double factor) =>
      _zoomAbout(_scale * factor, _viewport.center(Offset.zero));

  /// Zooms to [target], keeping [focal] pinned to the same canvas point.
  void _zoomAbout(double target, Offset focal) {
    _glide.stop();
    final next = target.clamp(_minScale, _maxScale);
    if (next == _scale) return;
    setState(() {
      // The canvas point under the cursor is (focal - offset) / scale; solving
      // for the offset that keeps it there at the new scale gives this.
      _offset = focal - (focal - _offset) * (next / _scale);
      _scale = next;
    });
    widget.onScaleChanged(next);
  }

  void _panBy(Offset delta) {
    _glide.stop();
    setState(() => _offset = _bounded(_offset + delta));
  }

  /// [offset], held where some of the artwork is still on screen.
  ///
  /// Free panning could scroll every screen out of the window, leaving an
  /// empty canvas and no clue which way the work went. At least [margin] of
  /// the content stays in view on each axis.
  Offset _bounded(Offset offset) {
    if (_viewport.isEmpty) return offset;
    final width = (widget.contentWidth ?? _viewport.width) * _scale;
    final height = _viewport.height * _scale;
    final margin = math.min(160.0, _viewport.shortestSide / 3);
    return Offset(
      offset.dx.clamp(margin - width, _viewport.width - margin),
      offset.dy.clamp(margin - height, _viewport.height - margin),
    );
  }

  /// Moves the view to [offset] as part of a rebuild already under way.
  ///
  /// For the editor's stage, which lays this viewport out again in the same
  /// pass that notices the canvas changed size: the new offset is read by that
  /// very build, so the view never spends a frame in the wrong place — which a
  /// later `setState` would, on every frame of a sheet's rise.
  void moveWhileRebuilding(Offset offset) {
    _glide.stop();
    _offset = offset;
  }

  /// The viewport's size as of the last layout, or [Size.zero] before one.
  Size get viewportSize => _viewport;

  /// Current zoom, where 1 is the content at its laid-out size.
  double get scale => _scale;

  // ---------------------------------------------------------------------------
  // Glide
  //
  // Moving the view to a screen is animated, so the eye can follow where it
  // went: jumping straight to the fourth screen of eight reads as the canvas
  // having been replaced, not scrolled.
  // ---------------------------------------------------------------------------

  late final AnimationController _glide = AnimationController(
    vsync: this,
    duration: StudioDuration.slow,
  )..addListener(_onGlide);

  Offset _glideFromOffset = Offset.zero;
  Offset _glideToOffset = Offset.zero;
  double _glideFromScale = 1;
  double _glideToScale = 1;

  void _onGlide() {
    final t = Curves.easeOutCubic.transform(_glide.value);
    setState(() {
      _offset = Offset.lerp(_glideFromOffset, _glideToOffset, t)!;
      _scale = ui.lerpDouble(_glideFromScale, _glideToScale, t)!;
    });
    widget.onScaleChanged(_scale);
  }

  /// Moves the view so [rect], in content coordinates, sits in the middle of
  /// the viewport at [scale].
  void focus(Rect rect, {double scale = 1, bool animate = true}) {
    if (_viewport.isEmpty) return;
    final next = scale.clamp(_minScale, _maxScale);
    var dx = _viewport.width / 2 - rect.center.dx * next;
    // Never glide past either end of wide content: centring the first screen
    // of a strip would otherwise leave half a window of empty canvas to its
    // left, which reads as the strip having lost something. Content narrower
    // than the window is centred as a whole instead.
    final width = widget.contentWidth;
    if (width != null) {
      final span = width * next;
      dx = span <= _viewport.width
          ? (_viewport.width - span) / 2
          : dx.clamp(_viewport.width - span, 0.0);
    }
    final offset = Offset(dx, _viewport.height / 2 - rect.center.dy * next);
    // Reduced motion jumps, like an unanimated move does.
    if (!animate || context.reduceMotion) {
      _glide.stop();
      setState(() {
        _offset = offset;
        _scale = next;
      });
      widget.onScaleChanged(next);
      return;
    }
    _glideFromOffset = _offset;
    _glideFromScale = _scale;
    _glideToOffset = offset;
    _glideToScale = next;
    _glide.forward(from: 0);
  }

  /// The zoom at the start of a trackpad gesture.
  ///
  /// `PointerPanZoomUpdateEvent.scale` is cumulative from the start of the
  /// gesture rather than incremental, so it has to be applied against the scale
  /// the gesture began at — multiplying the *current* scale by it every frame
  /// compounds and the canvas runs away.
  double? _gestureScale;

  /// A trackpad gesture: two-finger scroll to pan, pinch to zoom.
  ///
  /// This is the path a Mac actually uses. A trackpad does not emit
  /// [PointerScrollEvent] — that is a mouse wheel — it emits pan/zoom events,
  /// and because nothing here listened for them, two-finger scrolling the
  /// canvas did nothing at all.
  ///
  /// Still not a gesture-arena competitor: these arrive on [Listener] like any
  /// other raw pointer event, so the scene's own drag handles are untouched and
  /// a pinch on a *touchscreen* still scales the selected element.
  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _gestureScale = _scale;
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final start = _gestureScale;
    if (start == null) return;
    // Content follows the fingers, so the pan is applied as given rather than
    // negated the way a wheel's scrollDelta is.
    if (event.panDelta != Offset.zero) _panBy(event.panDelta);
    if ((event.scale - 1).abs() > 0.001) {
      _zoomAbout(start * event.scale, event.localPosition);
    }
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent event) => _gestureScale = null;

  // ---------------------------------------------------------------------------
  // Touch pinch
  //
  // A phone has no wheel, no trackpad and no space bar, so before this the edit
  // canvas could not be zoomed at all — the only magnification on mobile was
  // Preview mode, which is read-only. Two fingers zoom the workspace; one still
  // belongs to the scene, so dragging the frame or a caption is unchanged.
  //
  // Tracked by hand off raw pointers rather than through a ScaleGestureRecognizer
  // for the reason the whole class exists: a recogniser would enter the arena
  // and fight the scene's own drag handles for every touch.
  // ---------------------------------------------------------------------------

  final Map<int, Offset> _touches = {};
  double? _pinchStartScale;
  double? _pinchStartSpan;
  Offset? _pinchStartFocal;

  /// Distance and midpoint between the first two fingers down.
  (double, Offset)? get _span {
    if (_touches.length < 2) return null;
    final points = _touches.values.toList();
    final a = points[0];
    final b = points[1];
    return ((a - b).distance, (a + b) / 2);
  }

  void _touchDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    // The artwork owns the pinch whenever there is artwork selected.
    if (widget.hasSelection) return;
    _touches[event.pointer] = event.localPosition;
    final span = _span;
    if (span != null) {
      setState(() {
        _pinchStartSpan = span.$1;
        _pinchStartFocal = span.$2;
        _pinchStartScale = _scale;
      });
    }
  }

  void _touchMove(PointerMoveEvent event) {
    if (!_touches.containsKey(event.pointer)) return;
    _touches[event.pointer] = event.localPosition;
    final span = _span;
    final startSpan = _pinchStartSpan;
    final startScale = _pinchStartScale;
    final startFocal = _pinchStartFocal;
    if (span == null || startSpan == null || startScale == null) return;
    if (startSpan < 1) return;

    // The midpoint drifting is a two-finger pan, and it has to be applied
    // before the zoom so the zoom's focal point is where the fingers are now.
    if (startFocal != null && span.$2 != startFocal) {
      _panBy(span.$2 - startFocal);
      _pinchStartFocal = span.$2;
    }
    _zoomAbout(startScale * (span.$1 / startSpan), span.$2);
  }

  void _touchUp(PointerEvent event) {
    if (_touches.remove(event.pointer) == null) return;
    if (_touches.length < 2) {
      setState(() {
        _pinchStartSpan = null;
        _pinchStartFocal = null;
        _pinchStartScale = null;
      });
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    // Trackpad pinch on the platforms that report it as a signal rather than as
    // a pan/zoom gesture — the web, mainly. Desktop comes through
    // [_onPanZoomUpdate] instead.
    if (event is PointerScaleEvent) {
      _zoomAbout(_scale * event.scale, event.localPosition);
      return;
    }
    if (event is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed) {
      // Wheel notches are ~±100; the exponent turns that into a smooth
      // multiplicative zoom instead of a fixed step.
      final factor = math.exp(-event.scrollDelta.dy / 250);
      _zoomAbout(_scale * factor, event.localPosition);
    } else if (keys.isShiftPressed) {
      // Shift+wheel is horizontal scroll on every platform's convention.
      _panBy(Offset(-event.scrollDelta.dy, 0));
    } else {
      _panBy(-event.scrollDelta);
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _touchDown(event);
    final middle = event.buttons & kMiddleMouseButton != 0;
    if (middle || _panMode) setState(() => _panning = true);
  }

  void _onPointerMove(PointerMoveEvent event) {
    _touchMove(event);
    if (!_panning) return;
    _panBy(event.delta);
  }

  void _onPointerUp(PointerEvent event) {
    _touchUp(event);
    if (_panning) setState(() => _panning = false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        _viewport = size;

        final transform = Matrix4.identity()
          ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
          ..scaleByDouble(_scale, _scale, _scale, 1);
        final contentWidth = widget.contentWidth;

        // The zoom, for the scene's resize handles — see [SceneZoom].
        final child = SceneZoom(zoom: _scale, child: widget.child);
        Widget canvas = contentWidth == null
            ? Transform(transform: transform, child: child)
            // Laid out at full width first and transformed after — see
            // [_CanvasViewport.contentWidth] for why the order matters.
            : OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                child: Transform(
                  transform: transform,
                  child: SizedBox(
                    width: contentWidth,
                    height: constraints.maxHeight,
                    child: child,
                  ),
                ),
              );

        if (_panMode) canvas = IgnorePointer(child: canvas);

        return MouseRegion(
          cursor: _panning
              ? SystemMouseCursors.grabbing
              : (_panMode ? SystemMouseCursors.grab : MouseCursor.defer),
          child: Listener(
            // Opaque, not the default `deferToChild`.
            //
            // This is why space-dragging did nothing: pan mode wraps the whole
            // child in an [IgnorePointer], so nothing under the listener could
            // be hit, and a `deferToChild` listener that hits nothing receives
            // nothing. The one state that most needed pointer events was the
            // one state guaranteed not to get them.
            behavior: HitTestBehavior.opaque,
            onPointerSignal: _onPointerSignal,
            onPointerPanZoomStart: _onPanZoomStart,
            onPointerPanZoomUpdate: _onPanZoomUpdate,
            onPointerPanZoomEnd: _onPanZoomEnd,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerUp,
            // Hard-edged: a zoomed scene must not spill over the rail or the
            // inspector, both of which stay interactive.
            child: ClipRect(child: canvas),
          ),
        );
      },
    );
  }
}
