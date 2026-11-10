import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../data/assets/frame_catalog.dart';
import '../../data/repositories/font_library.dart';
import '../../data/repositories/stored_image.dart';
import '../../data/services/video_encoder.dart';
import '../../features/shared/friendly_error.dart';
import '../../features/shared/widgets/widgets.dart';
import '../models/screen_doc.dart';
import 'continuous.dart';
import 'device_motion.dart';
import 'export_settings.dart';
import 'scene_view.dart';
import 'video_frame_view.dart';

/// One finished raster, at exactly `doc.canvas` pixels.
@immutable
class RenderedScene {
  const RenderedScene({
    required this.index,
    required this.doc,
    required this.bytes,
    this.format = ExportFormat.png,
  });

  final int index;
  final ScreenDoc doc;
  final Uint8List bytes;

  /// What [bytes] is: a PNG, or a JPG. See [ExportSettings].
  final ExportFormat format;

  /// `png` or `jpg`, for the file name.
  String get extension => format.extension;

  /// `01`, `02`, … — the numbering used in exported file names.
  String get ordinal => '${index + 1}'.padLeft(2, '0');
}

/// Rasterises [ScreenDoc]s at their exact canvas resolution, off the visible
/// layout.
///
/// The editor's on-screen canvas cannot be used for this: it is letterboxed
/// inside whatever space the phone happens to have, so capturing it bakes the
/// surrounding margins into the PNG and makes the output size a function of the
/// device. Everything here is driven by the document instead — the boundary is
/// laid out at `canvas / _kDivisor` under unbounded constraints and captured at
/// `pixelRatio: _kDivisor`, which yields exactly `canvas.width x canvas.height`
/// pixels on every device, with no editor chrome inside the frame.
abstract final class SceneRenderer {
  /// Downscale factor applied to the laid-out boundary, undone by the capture's
  /// pixel ratio. Keeps the render layer small in logical pixels while the
  /// rasterised result stays 1:1 with the document.
  static const double _kDivisor = 4;

  /// Renders every entry of [screens] and returns them in order.
  ///
  /// Presents a modal progress dialog because the widgets have to be mounted to
  /// be painted; the dialog is what hosts them. Returns null if the user backs
  /// out, and throws nothing — failures for individual screens are skipped and
  /// reflected by a short result list.
  static Future<List<RenderedScene>?> render(
    BuildContext context, {
    required List<ScreenDoc> screens,
    required FrameCatalog catalog,
    String title = 'Rendering',
    bool continuous = false,
    ExportSettings settings = const ExportSettings(),
  }) {
    if (screens.isEmpty) return Future.value(const <RenderedScene>[]);
    return showDialog<List<RenderedScene>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SceneRenderDialog(
        screens: screens,
        catalog: catalog,
        title: title,
        continuous: continuous,
        settings: settings,
      ),
    );
  }

  /// Convenience wrapper for a single document.
  ///
  /// [set] and [index] place the document in a continuous set, so a single
  /// panel of a panorama exports with the parts of its neighbours that reach
  /// into it. Without them the screen renders alone.
  static Future<Uint8List?> renderOne(
    BuildContext context, {
    required ScreenDoc doc,
    required FrameCatalog catalog,
    String title = 'Rendering',
    List<ScreenDoc>? set,
    int? index,
    ExportSettings settings = const ExportSettings(),
  }) async {
    final continuous = set != null && index != null && set.length > 1;
    final result = await showDialog<List<RenderedScene>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SceneRenderDialog(
        screens: continuous ? set : [doc],
        only: continuous ? index : null,
        catalog: catalog,
        title: title,
        continuous: continuous,
        settings: settings,
      ),
    );
    if (result == null || result.isEmpty) return null;
    return result.first.bytes;
  }

  /// Films [composed] — one screen as it sits in its set — with its devices
  /// moving in [settings]' motion, and encodes the frames with [sink].
  ///
  /// Each frame is the picture Save would have written at that pose, placed
  /// in the clip's frame: scaled to fill it
  /// for a free-size clip, letterboxed or cropped into a store preset's exact
  /// size. Resolves to the encoded clip, or null when the user stopped it or
  /// the encoder failed — the dialog has said which.
  static Future<Uint8List?> renderVideo(
    BuildContext context, {
    required ComposedScreen composed,
    required FrameCatalog catalog,
    required VideoSettings settings,
    required VideoSink sink,
  }) => showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _VideoRenderDialog(
      composed: composed,
      catalog: catalog,
      settings: settings,
      sink: sink,
    ),
  );

  /// The subtree a video frame is captured from, on its own for the tests,
  /// like [captureStage].
  @visibleForTesting
  static Widget videoStage({
    required GlobalKey boundaryKey,
    required ComposedScreen composed,
    required FrameCatalog catalog,
    required VideoFrameLayout layout,
  }) => _VideoStage(
    boundaryKey: boundaryKey,
    composed: composed,
    catalog: catalog,
    layout: layout,
  );

  /// The pixel ratio a [videoStage] is captured at, which turns its layout
  /// into exactly the frame's pixels.
  @visibleForTesting
  static const double videoCaptureRatio = _kDivisor;

  /// The subtree the capture reads from, on its own so a test can assert the
  /// geometry without driving the dialog (`toImage` needs `runAsync`, which
  /// cannot pump frames).
  @visibleForTesting
  static Widget captureStage({
    required GlobalKey boundaryKey,
    required ScreenDoc doc,
    required FrameCatalog catalog,
  }) => _CaptureStage(boundaryKey: boundaryKey, doc: doc, catalog: catalog);

  /// Warms the image cache for everything [doc] paints, so the capture never
  /// races a still-decoding file.
  static Future<void> precacheAssets(
    BuildContext context,
    ScreenDoc doc,
  ) async {
    final futures = <Future<void>>[];

    void add(String? path) {
      final provider = StoredImage.provider(path);
      if (provider == null) return;
      futures.add(precacheImage(provider, context).catchError((_) {}));
    }

    if (doc.background case ImageBackground(:final path)) add(path);
    for (final frame in doc.frames) {
      add(frame.screenshot.imagePath);
      // A display fill is a backdrop like any other and can be a photo, so it
      // needs the same barrier: the capture is one frame, and an undecoded
      // image in it is a blank screen in the export.
      if (frame.screenshot.fill case ImageBackground(:final path)) add(path);
    }
    // Image layers, for the same reason: a logo still decoding at capture time
    // is a hole in the export.
    for (final shape in doc.shapes) {
      if (!shape.hidden) add(shape.imagePath);
    }

    // Captions are Google Fonts; an unresolved font would rasterise as the
    // fallback face.
    futures.add(GoogleFonts.pendingFonts().then((_) {}).catchError((_) {}));

    // And uploaded fonts need their own barrier. `pendingFonts()` is a
    // `Future.wait` over futures that `GoogleFonts.getFont` registers as it
    // goes, so it knows nothing about a family handed to the engine through
    // `FontLoader` — waiting on it alone would let a capture of a caption set
    // in a user font rasterise in Roboto.
    futures.add(FontLibrary.ready.catchError((_) {}));

    if (futures.isEmpty) return;
    await Future.wait(futures);
  }
}

class _SceneRenderDialog extends StatefulWidget {
  const _SceneRenderDialog({
    required this.screens,
    required this.catalog,
    required this.title,
    this.continuous = false,
    this.only,
    this.settings = const ExportSettings(),
  });

  /// Format and resolution of what is written.
  final ExportSettings settings;

  final List<ScreenDoc> screens;
  final FrameCatalog catalog;
  final String title;

  /// Whether [screens] are the panels of one continuous set.
  final bool continuous;

  /// Render only this index of [screens], which are there as its set.
  final int? only;

  @override
  State<_SceneRenderDialog> createState() => _SceneRenderDialogState();
}

class _SceneRenderDialogState extends State<_SceneRenderDialog> {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<RenderedScene> _rendered = [];

  bool _running = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  List<int> get _indices => switch (widget.only) {
    final only? => [only],
    null => [for (var i = 0; i < widget.screens.length; i++) i],
  };

  ComposedScreen _composed(int i) =>
      composeScreen(widget.screens, i, continuous: widget.continuous);

  late int _index = _indices.first;

  Future<void> _runAll() async {
    for (final i in _indices) {
      if (!mounted || !_running) break;
      if (i != _index) {
        setState(() => _index = i);
      }
      final bytes = await _captureCurrent(_composed(i).doc);
      if (bytes != null) {
        _rendered.add(
          RenderedScene(
            index: i,
            doc: widget.screens[i],
            bytes: bytes,
            format: widget.settings.format,
          ),
        );
      }
    }
    if (mounted) Navigator.of(context).pop(_rendered);
  }

  Future<Uint8List?> _captureCurrent(ScreenDoc doc) async {
    try {
      // Mounted, then decoded, then painted — in that order — before the layer
      // is rasterised. Skipping any step yields a blank or half-drawn export.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return null;
      await SceneRenderer.precacheAssets(context, doc);
      if (!mounted) return null;
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 32));
      if (!mounted) return null;

      final boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;

      // At the canvas's own pixels times the chosen scale: the boundary is
      // laid out at canvas / divisor, so the ratio carries both.
      final image = await boundary.toImage(
        pixelRatio: SceneRenderer._kDivisor * widget.settings.scale,
      );
      final bytes = await encodeExport(image, widget.settings);
      image.dispose();
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final doc = widget.screens[_index];
    final total = _indices.length;
    final position = _indices.indexOf(_index);

    return StudioDialog(
      title: widget.title,
      icon: StudioIcons.export,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            total == 1
                ? '${doc.canvas.width.round()} × ${doc.canvas.height.round()} px'
                : 'Screen ${position + 1} of $total  ·  '
                      '${doc.canvas.width.round()} × ${doc.canvas.height.round()} px',
            style: StudioText.mono(context).copyWith(color: s.textSecondary),
          ),
          SizedBox(height: StudioSpace.m),
          StudioProgressBar(value: (position + 1) / total),
          SizedBox(height: StudioSpace.xl),
          SizedBox(
            height: 260,
            child: _CaptureStage(
              boundaryKey: _boundaryKey,
              doc: doc,
              composed: _composed(_index),
              catalog: widget.catalog,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _running = false;
    super.dispose();
  }
}

/// Hosts the capture boundary at document scale and shows a shrunk preview of
/// it inside whatever box the dialog has.
///
/// The geometry here is load-bearing. [OverflowBox] hands the boundary
/// unbounded constraints so it always measures exactly `canvas / divisor`,
/// independent of the phone. The outer [Transform.scale] only affects what is
/// drawn on screen: `RenderRepaintBoundary.toImage` rasterises the boundary's
/// own layer in its own coordinate space, so ancestor transforms cannot reach
/// the captured pixels.
///
/// Inside the boundary the shrink has to be a [FittedBox], not a
/// [Transform.scale]. `Transform` forwards the parent's constraints untouched,
/// so the scene's [SizedBox] would be squashed to the boundary's own
/// `canvas / divisor` box and *then* scaled down again — laying the whole scene
/// into the top-left corner of the export at 1/divisor². `FittedBox` lays the
/// child out unbounded, so it measures a true `canvas`, and `BoxFit.fill` maps
/// that exactly onto the boundary.
class _CaptureStage extends StatelessWidget {
  const _CaptureStage({
    required this.boundaryKey,
    required this.doc,
    required this.catalog,
    this.composed,
  });

  /// The screen as composed into its set, or null to render [doc] alone.
  final ComposedScreen? composed;

  final GlobalKey boundaryKey;
  final ScreenDoc doc;
  final FrameCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final captureWidth = doc.canvas.width / SceneRenderer._kDivisor;
    final captureHeight = doc.canvas.height / SceneRenderer._kDivisor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewScale = math.min(
          constraints.maxWidth / captureWidth,
          constraints.maxHeight / captureHeight,
        );
        return ClipRect(
          child: Center(
            child: OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Transform.scale(
                scale: previewScale,
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: SizedBox(
                    width: captureWidth,
                    height: captureHeight,
                    child: FittedBox(
                      fit: BoxFit.fill,
                      // Inside the canvas-space box, not the divided one, so
                      // one logical pixel here is one pixel in the export: the
                      // FittedBox's 1/_kDivisor downscale and the capture's
                      // matching `pixelRatio` cancel exactly, and the mark
                      // rasterises at effective scale 1.0 with no resampling.
                      //
                      // Composed into the scene rather than stamped onto the
                      // captured image on purpose. Stamping needs a second
                      // full-size surface — ~33MB of RGBA held twice at the
                      // 3840x2160 preset, on top of a pipeline already
                      // capturing at pixelRatio 4 — and `_captureCurrent`
                      // swallows exceptions and returns null, so an OOM there
                      // would present as an export that silently produced
                      // nothing.
                      child: SizedBox(
                        width: doc.canvas.width,
                        height: doc.canvas.height,
                        child: SceneView.composed(
                          composed ?? ComposedScreen.alone(doc),
                          catalog: catalog,
                          forExport: true,
                        ),
                      ),
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
}

/// [rgba], [width] by [height], cut or padded to exactly [toWidth] by
/// [toHeight] from the top left.
///
/// A capture's size is the canvas times a ratio, rounded by the engine, so it
/// can come out a pixel either side of the size the encoder was opened at —
/// and an encoder, or a GIF's first frame, fixes the size for good.
Uint8List fitRgba(
  Uint8List rgba,
  int width,
  int height,
  int toWidth,
  int toHeight,
) {
  if (width == toWidth && height == toHeight) return rgba;
  final out = Uint8List(toWidth * toHeight * 4);
  final rowBytes = math.min(width, toWidth) * 4;
  for (var y = 0; y < math.min(height, toHeight); y++) {
    out.setRange(
      y * toWidth * 4,
      y * toWidth * 4 + rowBytes,
      rgba,
      y * width * 4,
    );
  }
  return out;
}

class _VideoRenderDialog extends StatefulWidget {
  const _VideoRenderDialog({
    required this.composed,
    required this.catalog,
    required this.settings,
    required this.sink,
  });

  final ComposedScreen composed;
  final FrameCatalog catalog;
  final VideoSettings settings;
  final VideoSink sink;

  @override
  State<_VideoRenderDialog> createState() => _VideoRenderDialogState();
}

/// Hosts a video frame's capture boundary, as [_CaptureStage] hosts a still's:
/// laid out at the frame's size over [SceneRenderer._kDivisor] and captured
/// at that ratio, so the image is exactly the frame's pixels, while a shrunk
/// copy shows in whatever box the dialog has.
class _VideoStage extends StatelessWidget {
  const _VideoStage({
    required this.boundaryKey,
    required this.composed,
    required this.catalog,
    required this.layout,
  });

  final GlobalKey boundaryKey;
  final ComposedScreen composed;
  final FrameCatalog catalog;
  final VideoFrameLayout layout;

  @override
  Widget build(BuildContext context) {
    final captureWidth = layout.width / SceneRenderer._kDivisor;
    final captureHeight = layout.height / SceneRenderer._kDivisor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewScale = math.min(
          constraints.maxWidth / captureWidth,
          constraints.maxHeight / captureHeight,
        );
        return ClipRect(
          child: Center(
            child: OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Transform.scale(
                scale: previewScale,
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: SizedBox(
                    width: captureWidth,
                    height: captureHeight,
                    // A FittedBox, not a Transform, for the reason
                    // [_CaptureStage] gives: the frame must lay out at its
                    // true size before it is shrunk.
                    child: FittedBox(
                      fit: BoxFit.fill,
                      child: VideoFrameView(
                        composed: composed,
                        catalog: catalog,
                        layout: layout,
                        forExport: true,
                      ),
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
}

class _VideoRenderDialogState extends State<_VideoRenderDialog> {
  final GlobalKey _boundaryKey = GlobalKey();

  /// What is filmed: the length and frame rate held to the purpose's rules —
  /// 15 to 30 seconds at 30 fps at most for an App Store preview. A GIF never
  /// takes a store preset's size; it is small and slow on purpose.
  late final VideoSettings _settings =
      (widget.sink is GifVideoSink
              ? widget.settings.copyWith(clearPreset: true, resetAudio: true)
              : widget.settings)
          .normalized;
  late final int _fps = widget.sink.fpsFor(_settings.clipFps);
  late final int _frames = _settings.clipSeconds * _fps;
  late final VideoFrameLayout _layout = _settings.layoutFor(
    widget.composed.doc.canvas,
    background: widget.composed.doc.background,
    maxLongSide: widget.sink.longSideFor(_settings.longSide),
  );

  int _frame = 0;
  bool _stopping = false;
  bool _encoding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _film());
  }

  /// The screen at frame [i]: every device, its own and its neighbours',
  /// moved to that point of the loop.
  ComposedScreen _at(int i) {
    final c = widget.composed;
    return ComposedScreen(
      doc: _settings.motion.apply(c.doc, i / _frames),
      ownShapes: c.ownShapes,
      ownFrames: c.ownFrames,
      backgroundSlice: c.backgroundSlice,
    );
  }

  Future<void> _film() async {
    final sink = widget.sink;
    final width = _layout.width, height = _layout.height;
    try {
      await sink.start(
        width: width,
        height: height,
        fps: _fps,
        frames: _frames,
        bitrate: _settings.bitrateFor(width, height, _fps),
        audio: _settings.wantsAudio,
      );

      for (var i = 0; i < _frames; i++) {
        if (!mounted || _stopping) {
          await sink.cancel();
          if (mounted) Navigator.of(context).pop();
          return;
        }
        if (i != _frame) setState(() => _frame = i);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        if (i == 0) {
          // Everything the scene paints decoded before the first frame; after
          // that only the pose changes.
          await SceneRenderer.precacheAssets(context, widget.composed.doc);
          if (!mounted) return;
          await WidgetsBinding.instance.endOfFrame;
          await Future<void>.delayed(const Duration(milliseconds: 32));
          if (!mounted) return;
        }

        final boundary =
            _boundaryKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary == null) {
          throw const VideoEncoderException('The frame could not be drawn.');
        }
        final image = await boundary.toImage(
          pixelRatio: SceneRenderer._kDivisor,
        );
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final w = image.width, h = image.height;
        image.dispose();
        if (data == null) {
          throw const VideoEncoderException('The frame could not be read.');
        }
        await sink.add(
          fitRgba(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            w,
            h,
            width,
            height,
          ),
          width: width,
          height: height,
        );
      }

      if (mounted) setState(() => _encoding = true);
      final bytes = await sink.finish();
      if (mounted) Navigator.of(context).pop(bytes);
    } on VideoEncoderException catch (e) {
      await sink.cancel();
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      await sink.cancel();
      // The raw error names the bug, not the problem; it goes to the log.
      debugPrint('Video export failed: $e');
      if (mounted) {
        setState(
          () => _error = 'The video could not be made. ${friendlyError(e)}',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final error = _error;
    final shown = _at(_frame);
    return StudioDialog(
      title: error != null
          ? 'Video not saved'
          : (_encoding ? 'Finishing video' : 'Filming'),
      icon: StudioIcons.export,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            error ??
                '${_settings.motion.label} · ${_layout.width} × '
                    '${_layout.height} · frame ${_frame + 1} of $_frames',
            style: error == null
                ? StudioText.mono(context).copyWith(color: s.textSecondary)
                : StudioText.caption(context).copyWith(color: s.danger),
          ),
          SizedBox(height: StudioSpace.m),
          StudioProgressBar(value: (_frame + 1) / _frames),
          SizedBox(height: StudioSpace.xl),
          SizedBox(
            height: 260,
            child: _VideoStage(
              boundaryKey: _boundaryKey,
              composed: shown,
              catalog: widget.catalog,
              layout: _layout,
            ),
          ),
        ],
      ),
      actions: [
        StudioButton(
          label: error != null ? 'Close' : (_stopping ? 'Stopping…' : 'Stop'),
          variant: StudioButtonVariant.ghost,
          onPressed: error != null
              ? () => Navigator.of(context).pop()
              : (_stopping || _encoding
                    ? null
                    : () => setState(() => _stopping = true)),
        ),
      ],
    );
  }
}
