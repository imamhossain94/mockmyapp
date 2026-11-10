import 'package:flutter/widgets.dart';

import '../../data/assets/frame_catalog.dart';
import 'continuous.dart';
import 'scene_view.dart';
import 'video_preset.dart';

/// One frame of a clip as it is encoded: [composed] placed in a frame of
/// [layout]'s size — letterboxed on its bars, cropped, or filling it — the way
/// the export captures it and the export sheet previews it.
///
/// Lays out at the frame's own size in logical pixels; the capture stage
/// shrinks it and the sheet fits it to its box. Literal colours only — the
/// bars come from the document — so a clip filmed in dark mode is the clip
/// filmed in light mode, byte for byte.
class VideoFrameView extends StatelessWidget {
  const VideoFrameView({
    super.key,
    required this.composed,
    required this.catalog,
    required this.layout,
    this.forExport = false,
  });

  final ComposedScreen composed;
  final FrameCatalog catalog;
  final VideoFrameLayout layout;

  /// Whether this is the picture the encoder takes, as [SceneView] means it.
  final bool forExport;

  @override
  Widget build(BuildContext context) {
    final canvas = composed.doc.canvas;
    return SizedBox(
      width: layout.width.toDouble(),
      height: layout.height.toDouble(),
      // A crop runs past the frame; nothing outside it may paint.
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: layout.bars)),
            Positioned.fromRect(
              rect: layout.canvasRect,
              child: FittedBox(
                fit: BoxFit.fill,
                // The canvas at its own size inside, so captions and devices
                // lay out exactly as a still export lays them out, and only
                // then are scaled into the frame.
                child: SizedBox(
                  width: canvas.width,
                  height: canvas.height,
                  child: SceneView.composed(
                    composed,
                    catalog: catalog,
                    forExport: forExport,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
