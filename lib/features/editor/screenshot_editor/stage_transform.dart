import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;

/// Where the artwork sits on the retouch stage, and how big.
///
/// A pure value rather than a handful of fields on a `State`, and that is the
/// whole point of the file. Every line of viewport maths on this screen used to
/// be private state, which is exactly why none of it was tested: the op model
/// beside it is pure and carries hundreds of lines of tests, and the viewport —
/// the part a finger touches on every single interaction — carried none.
///
/// Two spaces meet here and must never be confused:
///
/// * **document** — normalised against the oriented source image, the same
///   0..1 convention every `EditOp` uses. `Rect.fromLTRB(0, 0, 1, 1)` is the
///   whole capture; the crop may reach outside it.
/// * **stage** — logical pixels of the widget the user is looking at.
///
/// The model is a scale and an offset rather than a sub-rect of the document,
/// which is the change that makes "fully zoomable" possible at all. A window
/// narrowed inside a fixed letterbox can only ever magnify *within* the space
/// the layout already gave it: it cannot zoom below fit, cannot overscroll, and
/// cannot use the room that chrome is not currently occupying.
class StageTransform {
  const StageTransform({
    required this.document,
    required this.viewport,
    required this.scale,
    required this.offset,
    this.chromeInsets = EdgeInsets.zero,
  });

  /// The region of the capture the stage is framing, normalised.
  ///
  /// Not the zoom window — that is [scale] and [offset]. This is what the mode
  /// is *about*: the crop while painting, the whole reachable area while
  /// cropping.
  final Rect document;

  /// The widget's own size, in logical pixels.
  final Size viewport;

  /// Stage pixels per unit of [document] width.
  final double scale;

  /// Where the document's top-left lands on the stage, in stage pixels.
  final Offset offset;

  /// What the chrome covers on each edge.
  ///
  /// Used for fitting and for clamping the pan, and deliberately never for
  /// clipping: the artwork bleeds under a translucent tool dock rather than
  /// stopping at it, which is what makes the stage feel like the whole screen
  /// rather than a letterbox with furniture around it.
  final EdgeInsets chromeInsets;

  /// The rectangle the artwork is fitted into: the viewport less the chrome.
  Rect get safeBox {
    final box = Rect.fromLTWH(
      chromeInsets.left,
      chromeInsets.top,
      math.max(viewport.width - chromeInsets.horizontal, 1),
      math.max(viewport.height - chromeInsets.vertical, 1),
    );
    return box;
  }

  /// The document's aspect, as width / height in stage terms.
  ///
  /// The document is normalised against the image's own edges, so a rect that
  /// is square in normalised space is only square on screen if the image is.
  double aspectOf(Size imageSize) =>
      (document.width * imageSize.width) /
      math.max(document.height * imageSize.height, 1e-9);

  /// The scale at which the document exactly fills [safeBox].
  double fitScale(Size imageSize) {
    final box = safeBox;
    final aspect = aspectOf(imageSize);
    final byWidth = box.width;
    final byHeight = box.height * aspect;
    return math.min(byWidth, byHeight);
  }

  /// The artwork's size on the stage at the current [scale].
  Size contentSize(Size imageSize) =>
      Size(scale, scale / math.max(aspectOf(imageSize), 1e-9));

  /// Where the artwork is painted, in stage pixels.
  Rect contentRect(Size imageSize) {
    final size = contentSize(imageSize);
    return Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
  }

  /// A stage point as a point in the document.
  Offset toDocument(Offset stagePoint, Size imageSize) {
    final rect = contentRect(imageSize);
    return Offset(
      document.left +
          (stagePoint.dx - rect.left) /
              math.max(rect.width, 1e-9) *
              document.width,
      document.top +
          (stagePoint.dy - rect.top) /
              math.max(rect.height, 1e-9) *
              document.height,
    );
  }

  /// A document point as a point on the stage.
  Offset toStage(Offset documentPoint, Size imageSize) {
    final rect = contentRect(imageSize);
    return Offset(
      rect.left +
          (documentPoint.dx - document.left) /
              math.max(document.width, 1e-9) *
              rect.width,
      rect.top +
          (documentPoint.dy - document.top) /
              math.max(document.height, 1e-9) *
              rect.height,
    );
  }

  /// The part of the document currently visible, normalised.
  ///
  /// This is what the composer is handed as its crop, so the raster it builds
  /// never exceeds the viewport however far in the user has zoomed.
  Rect visibleDocument(Size imageSize) => Rect.fromPoints(
    toDocument(Offset.zero, imageSize),
    toDocument(Offset(viewport.width, viewport.height), imageSize),
  );

  StageTransform copyWith({
    Rect? document,
    Size? viewport,
    double? scale,
    Offset? offset,
    EdgeInsets? chromeInsets,
  }) => StageTransform(
    document: document ?? this.document,
    viewport: viewport ?? this.viewport,
    scale: scale ?? this.scale,
    offset: offset ?? this.offset,
    chromeInsets: chromeInsets ?? this.chromeInsets,
  );

  /// Fitted to the safe box and centred in it.
  StageTransform fitted(Size imageSize) {
    final next = fitScale(imageSize);
    final size = copyWith(scale: next).contentSize(imageSize);
    final box = safeBox;
    return copyWith(
      scale: next,
      offset: Offset(
        box.left + (box.width - size.width) / 2,
        box.top + (box.height - size.height) / 2,
      ),
    );
  }

  /// Zoomed to [target], keeping [focal] pinned to the same point of the
  /// artwork.
  ///
  /// The offset solve is the same one the main editor's canvas uses: the
  /// document point under the cursor is `(focal - offset) / scale`, and solving
  /// for the offset that leaves it there at the new scale gives this.
  StageTransform zoomAbout(double target, Offset focal, Size imageSize) {
    final fit = fitScale(imageSize);
    final next = target.clamp(minScale(fit), maxScale(fit));
    if (next == scale) return this;
    return copyWith(
      offset: focal - (focal - offset) * (next / scale),
      scale: next,
    ).clamped(imageSize);
  }

  StageTransform panned(Offset delta, Size imageSize) =>
      copyWith(offset: offset + delta).clamped(imageSize);

  /// Bounds relative to fit, so they mean the same thing on every screen size.
  ///
  /// Below fit as well as above it: the old model could not express it at all,
  /// and being able to pull the artwork smaller than the window is what lets
  /// you see a whole expanded crop with its margins.
  static double minScale(double fit) => 0.25 * fit;
  static double maxScale(double fit) => 12 * fit;

  /// The offset pulled back until the artwork still overlaps the safe box.
  ///
  /// Deliberately not "kept inside the document": that is what made zooming
  /// below fit impossible before. The rule is only that some of the artwork has
  /// to remain reachable — and on an axis where the artwork is smaller than the
  /// box, it is centred rather than clamped, so a small picture sits in the
  /// middle instead of sticking to an edge.
  StageTransform clamped(Size imageSize) {
    final box = safeBox;
    final size = contentSize(imageSize);
    double axis(double value, double content, double boxStart, double boxSize) {
      if (content <= boxSize) return boxStart + (boxSize - content) / 2;
      final overlap = math.min(content, boxSize);
      final lowest = boxStart + boxSize - overlap;
      final highest = boxStart + overlap - content;
      return value.clamp(math.min(lowest, highest), math.max(lowest, highest));
    }

    return copyWith(
      offset: Offset(
        axis(offset.dx, size.width, box.left, box.width),
        axis(offset.dy, size.height, box.top, box.height),
      ),
    );
  }
}
