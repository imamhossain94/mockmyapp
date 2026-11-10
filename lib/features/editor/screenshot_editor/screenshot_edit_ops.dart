import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../../../data/assets/studio_fonts.dart';
import '../../../domain/engine/shape_painter.dart';
import '../../../domain/models/shape_spec.dart';
import 'photo_color.dart';
import 'status_bar_painter.dart';

export 'photo_color.dart';

/// One destructive edit applied on top of a screenshot.
///
/// Every coordinate is stored **normalised against the full source image**
/// (0..1 on each axis), never against the visible canvas. That is what lets the
/// crop window be moved after the fact without dragging the paint along with
/// it, and lets the same op list be replayed at preview scale and at full export
/// resolution from a single mapping function.
@immutable
sealed class EditOp {
  const EditOp();
}

/// Something laid over the screenshot at a place the user chose.
///
/// A base rather than a set of unrelated ops, because the *placement* is the
/// part the editor manipulates: one hit test, one set of selection chrome and
/// one geometry panel serve a shape, a sticker and a photograph alike, and the
/// subclass only decides what gets drawn inside the box.
///
/// Unlike a brush stroke, a placed object stays editable after it is laid
/// down — which is why it carries an [id] and a placement rather than being
/// baked into a path the moment the finger lifts.
@immutable
sealed class PlacedOp extends EditOp {
  const PlacedOp({
    required this.id,
    required this.center,
    required this.width,
    required this.height,
    this.rotationDeg = 0,
    this.opacity = 1,
  });

  /// Identity across edits, minted by the screen and unique within a session.
  ///
  /// Selection is by id rather than by position, because every path on this
  /// screen replaces the op list wholesale — a commit swaps it, a background
  /// removal filters it, undo and redo hand back a different list entirely. An
  /// index does not go out of range when that happens; it quietly comes to
  /// mean a different object, which is the worse failure of the two.
  final int id;

  /// Centre of the box, normalised against the **oriented source image** — the
  /// same top-left 0..1 convention [BrushOp.points] and [MarkupOp.start] use, so
  /// the crop can be re-dragged afterwards without taking the object with it.
  ///
  /// Deliberately not [ShapeSpec.center]'s convention, which measures from the
  /// canvas centre. Mixing the two is exactly the class of bug this file's
  /// header exists to prevent.
  final Offset center;

  /// Box size, both as fractions of the source image's **width**.
  ///
  /// Both against the same edge, because that is the only way equal numbers can
  /// mean a square. Measuring height against the image's height is the mistake
  /// [ShapeSpec.height] documents having already made once, where it turned
  /// every circle on a 9:19.5 canvas into a tall ellipse.
  final double width;
  final double height;

  final double rotationDeg;

  /// 0..1, applied to the whole object rather than to its parts.
  final double opacity;

  /// The same object moved, resized, turned or faded.
  ///
  /// Placement only — the contents are untouched — so a drag handler can move a
  /// shape and a photograph through one call without knowing which it has.
  PlacedOp withPlacement({
    Offset? center,
    double? width,
    double? height,
    double? rotationDeg,
    double? opacity,
  });

  /// The same object under another [id] — a duplicate, or one read back from
  /// a recipe written before it had one.
  ///
  /// Each kind copies itself, beside its own fields, so a field added to one
  /// cannot be left behind by a copy written somewhere else. A duplicated
  /// picture lost its crop and its rim exactly that way.
  PlacedOp withId(int id);

  /// The box in source pixels, centred on the origin: the space the rotation is
  /// applied in.
  Rect localBox(Size imageSize) => Rect.fromCenter(
    center: Offset.zero,
    width: width * imageSize.width,
    // Against the width, like [width] — see the field's own note.
    height: height * imageSize.width,
  );

  /// Whether [normalised] lands inside this object's rotated box.
  ///
  /// The un-rotation happens in **pixel** space, never in normalised space.
  /// Normalised x and y are divided by different edges, so a rotation applied
  /// there is a shear rather than a turn, and a hit test done there misses a
  /// rotated object by more the further the capture is from square.
  bool hitTest(Offset normalised, Size imageSize) {
    final d = Offset(
      (normalised.dx - center.dx) * imageSize.width,
      (normalised.dy - center.dy) * imageSize.height,
    );
    final a = -rotationDeg * math.pi / 180;
    final local = Offset(
      d.dx * math.cos(a) - d.dy * math.sin(a),
      d.dx * math.sin(a) + d.dy * math.cos(a),
    );
    return localBox(imageSize).contains(local);
  }

  /// The four corners of the rotated box, normalised, for the selection chrome.
  ///
  /// Clockwise from the top-left of the un-rotated box, so the caller can treat
  /// consecutive pairs as edges without sorting them.
  List<Offset> corners(Size imageSize) {
    final box = localBox(imageSize);
    final a = rotationDeg * math.pi / 180;
    final cos = math.cos(a);
    final sin = math.sin(a);
    return [
      for (final c in [
        box.topLeft,
        box.topRight,
        box.bottomRight,
        box.bottomLeft,
      ])
        Offset(
          center.dx + (c.dx * cos - c.dy * sin) / imageSize.width,
          center.dy + (c.dx * sin + c.dy * cos) / imageSize.height,
        ),
    ];
  }
}

/// A vector shape laid over the screenshot.
///
/// Carries a whole [ShapeSpec] rather than a second set of fill, stroke and
/// shadow fields that would have to be kept in step with it. That is what makes
/// `ShapeGeometry`, `ShapePainter`, the shape gallery and every style control
/// the main editor already has work here for nothing.
///
/// The adaptation is exactly one thing: the spec's own *placement* is ignored —
/// [ShapeSpec.center], [ShapeSpec.width], [ShapeSpec.height] and
/// [ShapeSpec.rotationDeg], because [PlacedOp] is the placement; [ShapeSpec.z]
/// and [ShapeSpec.hidden], because the op list is the stack; and
/// [ShapeSpec.opacity], because [PlacedOp.opacity] is the one that applies.
@immutable
class ShapeOp extends PlacedOp {
  const ShapeOp({
    required super.id,
    required this.spec,
    required super.center,
    required super.width,
    required super.height,
    super.rotationDeg,
    super.opacity,
  });

  final ShapeSpec spec;

  ShapeOp copyWith({
    ShapeSpec? spec,
    Offset? center,
    double? width,
    double? height,
    double? rotationDeg,
    double? opacity,
  }) => ShapeOp(
    id: id,
    spec: spec ?? this.spec,
    center: center ?? this.center,
    width: width ?? this.width,
    height: height ?? this.height,
    rotationDeg: rotationDeg ?? this.rotationDeg,
    opacity: opacity ?? this.opacity,
  );

  @override
  ShapeOp withPlacement({
    Offset? center,
    double? width,
    double? height,
    double? rotationDeg,
    double? opacity,
  }) => copyWith(
    center: center,
    width: width,
    height: height,
    rotationDeg: rotationDeg,
    opacity: opacity,
  );

  @override
  ShapeOp withId(int id) => ShapeOp(
    id: id,
    spec: spec,
    center: center,
    width: width,
    height: height,
    rotationDeg: rotationDeg,
    opacity: opacity,
  );
}

/// Another bitmap laid over the screenshot — a logo, a second capture, a photo.
///
/// The decode happens once, at placement time, exactly the way
/// [RemoveBackgroundOp]'s mask is built once at commit time. The op carries a
/// decoded [ui.Image] and [ScreenshotComposer.paint] stays synchronous, which is
/// what keeps undo, redo and every frame of a drag free of a `Future`.
///
/// The pixels are **borrowed, never owned**. One `ui.Image` is referenced by
/// every history snapshot that contains this op, and by every other placement
/// of the same file, so disposing it with the op would hand undo a disposed
/// texture — the same trap `dispose()` already fell into with cutout masks. The
/// screen keeps a bank of them and disposes each exactly once.
@immutable
class ImageOp extends PlacedOp {
  const ImageOp({
    required super.id,
    required this.image,
    required this.source,
    required super.center,
    required super.width,
    required super.height,
    super.rotationDeg,
    super.opacity,
    this.flipH = false,
    this.cornerRadius = 0,
    this.crop = fullCrop,
    this.borderWidth = 0,
    this.borderColor = const Color(0xFFFFFFFF),
  });

  /// Every pixel of the image.
  static const fullCrop = Rect.fromLTRB(0, 0, 1, 1);

  final ui.Image image;

  /// The part of [image] shown, as fractions of its own width and height.
  ///
  /// Dragged in from a side handle, or set to a ratio from the panel. The box
  /// keeps the shown pixels' own shape, so cropping never stretches them.
  final Rect crop;

  /// The rim drawn round the image, as a fraction of the photo's width like
  /// [cornerRadius]. Zero for none.
  final double borderWidth;
  final Color borderColor;

  /// Whether any of [image] is cropped away.
  bool get isCropped => crop != fullCrop;

  /// Where the pixels came from.
  ///
  /// Kept so the op can name itself, so two placements of one file share a
  /// single decode, and so a serialised op could be rebuilt without the bitmap
  /// travelling with it — the same reason [RemoveBackgroundOp] keeps the
  /// tolerance its mask was built at.
  final String source;

  /// Mirrored left to right about the box's centre, after the rotation.
  ///
  /// The one transform a pasted arrow actually needs, and the same pair
  /// [ImageOrientation] settled on for the capture itself.
  final bool flipH;

  /// Fraction of the source image's width. Zero for hard corners.
  final double cornerRadius;

  /// The height that keeps the bitmap's own pixel aspect at [width], stated in
  /// width-fractions like everything else on a [PlacedOp].
  ///
  /// Exact rather than a function of the capture's shape, which is the point of
  /// measuring both edges against one: a 16:9 logo is 16:9 on a tall phone
  /// capture and on a square one.
  static double heightFor(
    ui.Image image,
    double width, [
    Rect crop = fullCrop,
  ]) => width * (crop.height * image.height) / (crop.width * image.width);

  ImageOp copyWith({
    Offset? center,
    double? width,
    double? height,
    double? rotationDeg,
    double? opacity,
    bool? flipH,
    double? cornerRadius,
    Rect? crop,
    double? borderWidth,
    Color? borderColor,
  }) => ImageOp(
    id: id,
    image: image,
    source: source,
    center: center ?? this.center,
    width: width ?? this.width,
    height: height ?? this.height,
    rotationDeg: rotationDeg ?? this.rotationDeg,
    opacity: opacity ?? this.opacity,
    flipH: flipH ?? this.flipH,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    crop: crop ?? this.crop,
    borderWidth: borderWidth ?? this.borderWidth,
    borderColor: borderColor ?? this.borderColor,
  );

  /// Cropped to [aspect] (width over height, in the image's own pixels) about
  /// the middle of what is shown now — or back to every pixel for null. The
  /// box keeps its width and takes the new shape.
  ImageOp croppedTo(double? aspect) {
    if (aspect == null) {
      return copyWith(crop: fullCrop, height: heightFor(image, width));
    }
    final w = image.width.toDouble(), h = image.height.toDouble();
    // The largest rect of [aspect] inside the whole image, centred on the
    // middle of the current crop and kept inside the pixels.
    var cw = w, ch = w / aspect;
    if (ch > h) {
      ch = h;
      cw = h * aspect;
    }
    final c = Offset(crop.center.dx * w, crop.center.dy * h);
    final left = (c.dx - cw / 2).clamp(0.0, w - cw);
    final top = (c.dy - ch / 2).clamp(0.0, h - ch);
    final next = Rect.fromLTWH(left / w, top / h, cw / w, ch / h);
    return copyWith(crop: next, height: heightFor(image, width, next));
  }

  @override
  ImageOp withPlacement({
    Offset? center,
    double? width,
    double? height,
    double? rotationDeg,
    double? opacity,
  }) => copyWith(
    center: center,
    width: width,
    height: height,
    rotationDeg: rotationDeg,
    opacity: opacity,
  );

  @override
  ImageOp withId(int id) => ImageOp(
    id: id,
    image: image,
    source: source,
    center: center,
    width: width,
    height: height,
    rotationDeg: rotationDeg,
    opacity: opacity,
    flipH: flipH,
    cornerRadius: cornerRadius,
    crop: crop,
    borderWidth: borderWidth,
    borderColor: borderColor,
  );
}

/// A bundled sticker laid over the screenshot.
///
/// Carries the decoded [ui.Picture] rather than a rasterised bitmap, so the art
/// stays vector-crisp at 12x zoom and at full export resolution from the same
/// record — which is the whole reason the pack ships as SVG. Loaded once at
/// placement time, the discipline [RemoveBackgroundOp] and [ImageOp] already
/// follow, so `paint` stays synchronous.
///
/// Like [ImageOp], the picture is borrowed and never owned: one record serves
/// every placement of the sticker and every history snapshot holding one.
@immutable
class StickerOp extends PlacedOp {
  const StickerOp({
    required super.id,
    required this.picture,
    required this.pictureSize,
    required this.stickerId,
    required super.center,
    required super.width,
    required super.height,
    super.rotationDeg,
    super.opacity,
    this.tint,
    this.flipH = false,
  });

  final ui.Picture picture;

  /// The SVG's own viewBox, which the box is scaled from.
  final Size pictureSize;

  /// The catalog id, for naming the layer and for a future serialisation.
  final String stickerId;

  /// Recolour, or null to draw the art as it was made.
  ///
  /// Only ever set for art the catalog marks tintable — that is, drawn in one
  /// colour. Recolouring a speech bubble would set its fill and its outline to
  /// the same value and erase the drawing, which is why the catalog answers
  /// this rather than the editor guessing from the file.
  final Color? tint;

  final bool flipH;

  StickerOp copyWith({
    Offset? center,
    double? width,
    double? height,
    double? rotationDeg,
    double? opacity,
    Color? tint,
    bool clearTint = false,
    bool? flipH,
  }) => StickerOp(
    id: id,
    picture: picture,
    pictureSize: pictureSize,
    stickerId: stickerId,
    center: center ?? this.center,
    width: width ?? this.width,
    height: height ?? this.height,
    rotationDeg: rotationDeg ?? this.rotationDeg,
    opacity: opacity ?? this.opacity,
    tint: clearTint ? null : (tint ?? this.tint),
    flipH: flipH ?? this.flipH,
  );

  @override
  StickerOp withPlacement({
    Offset? center,
    double? width,
    double? height,
    double? rotationDeg,
    double? opacity,
  }) => copyWith(
    center: center,
    width: width,
    height: height,
    rotationDeg: rotationDeg,
    opacity: opacity,
  );

  @override
  StickerOp withId(int id) => StickerOp(
    id: id,
    picture: picture,
    pictureSize: pictureSize,
    stickerId: stickerId,
    center: center,
    width: width,
    height: height,
    rotationDeg: rotationDeg,
    opacity: opacity,
    tint: tint,
    flipH: flipH,
  );
}

/// How a text layer stands off the photo behind it.
enum TextLook {
  /// The letters alone.
  plain,

  /// On a rounded plate of [TextOp.accent].
  box,

  /// Ringed in [TextOp.accent], which is what keeps white type legible on a
  /// busy photo.
  outline,

  /// With a soft drop shadow.
  shadow;

  /// Whether the look has a second colour, [TextOp.accent].
  bool get hasAccent => this == box || this == outline;
}

/// Words laid over the photo.
///
/// Its size is [fontSize] — a fraction of the photo's width, like every other
/// measurement here — and the box is derived from the words at that size by
/// [fitted], never set on its own. So resizing a text layer scales its type,
/// and editing the words re-shapes the box around them.
@immutable
class TextOp extends PlacedOp {
  const TextOp({
    required super.id,
    required this.text,
    required this.fontSize,
    required super.center,
    super.width = 0,
    super.height = 0,
    super.rotationDeg,
    super.opacity,
    this.fontFamily = 'Inter',
    this.bold = true,
    this.color = const Color(0xFFFFFFFF),
    this.align = TextAlign.center,
    this.look = TextLook.plain,
    this.accent = const Color(0xFF000000),
  });

  final String text;

  /// Type size as a fraction of the photo's width.
  final double fontSize;
  final String fontFamily;
  final bool bold;
  final Color color;
  final TextAlign align;
  final TextLook look;

  /// The plate behind [TextLook.box], or the ring of [TextLook.outline].
  final Color accent;

  /// The size the words are laid out at before being scaled into the box, so
  /// the layout — and so the wrapping and the box's shape — is the same at
  /// preview size and at export size.
  static const double reference = 100;

  EdgeInsets get _padding => switch (look) {
    TextLook.box => const EdgeInsets.symmetric(horizontal: 34, vertical: 16),
    TextLook.outline => const EdgeInsets.all(14),
    TextLook.shadow => const EdgeInsets.all(12),
    TextLook.plain => const EdgeInsets.all(8),
  };

  TextStyle _style({Paint? foreground}) => StudioFonts.style(
    fontFamily,
    fontSize: reference,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    height: 1.15,
    color: foreground == null ? color : null,
    foreground: foreground,
    shadows: look == TextLook.shadow && foreground == null
        ? const [
            Shadow(
              color: Color(0x99000000),
              offset: Offset(0, 4),
              blurRadius: 10,
            ),
          ]
        : null,
  );

  /// The words laid out at [reference] size. The caller disposes it.
  TextPainter layout({Paint? foreground}) => TextPainter(
    text: TextSpan(
      text: text.isEmpty ? ' ' : text,
      style: _style(foreground: foreground),
    ),
    textAlign: align,
    textDirection: TextDirection.ltr,
  )..layout();

  /// The box at [reference] size: the words and the padding their look adds.
  Size _referenceBox(TextPainter painter) => Size(
    painter.width + _padding.horizontal,
    painter.height + _padding.vertical,
  );

  /// This layer with its box re-measured around its words.
  TextOp fitted() {
    final painter = layout();
    final box = _referenceBox(painter);
    painter.dispose();
    final k = fontSize / reference;
    return _copy(width: box.width * k, height: box.height * k);
  }

  /// Paints the layer into a box of [size] with its top-left at the origin.
  void paintInto(Canvas canvas, Size size) {
    final painter = layout();
    final box = _referenceBox(painter);
    if (box.width <= 0) {
      painter.dispose();
      return;
    }
    // One uniform scale from the width: a box measured with a font that had
    // not finished loading may be a touch off in height, and stretching the
    // words to it would be worse than a hair of slack.
    final k = size.width / box.width;
    canvas.save();
    canvas.scale(k, k);
    final origin = Offset(_padding.left, _padding.top);
    switch (look) {
      case TextLook.box:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Offset.zero & box,
            const Radius.circular(reference * 0.28),
          ),
          Paint()..color = accent,
        );
      case TextLook.outline:
        final ring = layout(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = reference * 0.12
            ..strokeJoin = StrokeJoin.round
            ..color = accent,
        );
        ring.paint(canvas, origin);
        ring.dispose();
      case TextLook.plain:
      case TextLook.shadow:
        break;
    }
    painter.paint(canvas, origin);
    painter.dispose();
    canvas.restore();
  }

  TextOp _copy({
    String? text,
    double? fontSize,
    Offset? center,
    double? width,
    double? height,
    double? rotationDeg,
    double? opacity,
    String? fontFamily,
    bool? bold,
    Color? color,
    TextAlign? align,
    TextLook? look,
    Color? accent,
  }) => TextOp(
    id: id,
    text: text ?? this.text,
    fontSize: fontSize ?? this.fontSize,
    center: center ?? this.center,
    width: width ?? this.width,
    height: height ?? this.height,
    rotationDeg: rotationDeg ?? this.rotationDeg,
    opacity: opacity ?? this.opacity,
    fontFamily: fontFamily ?? this.fontFamily,
    bold: bold ?? this.bold,
    color: color ?? this.color,
    align: align ?? this.align,
    look: look ?? this.look,
    accent: accent ?? this.accent,
  );

  /// The words or their styling changed, and the box re-measured to match.
  TextOp copyWith({
    String? text,
    double? fontSize,
    String? fontFamily,
    bool? bold,
    Color? color,
    TextAlign? align,
    TextLook? look,
    Color? accent,
    double? opacity,
  }) => _copy(
    text: text,
    fontSize: fontSize,
    fontFamily: fontFamily,
    bold: bold,
    color: color,
    align: align,
    look: look,
    accent: accent,
    opacity: opacity,
  ).fitted();

  /// Moved, turned or faded — or resized, which for text means the type: a new
  /// width scales [fontSize] by the same factor, and the height with it.
  @override
  TextOp withPlacement({
    Offset? center,
    double? width,
    double? height,
    double? rotationDeg,
    double? opacity,
  }) {
    final factor = width == null || this.width <= 0 ? 1.0 : width / this.width;
    return _copy(
      center: center,
      fontSize: fontSize * factor,
      width: this.width * factor,
      height: this.height * factor,
      rotationDeg: rotationDeg,
      opacity: opacity,
    );
  }

  @override
  TextOp withId(int id) => TextOp(
    id: id,
    text: text,
    fontSize: fontSize,
    center: center,
    width: width,
    height: height,
    rotationDeg: rotationDeg,
    opacity: opacity,
    fontFamily: fontFamily,
    bold: bold,
    color: color,
    align: align,
    look: look,
    accent: accent,
  );
}

/// Decodes bytes into the texture an [ImageOp] carries.
///
/// The mirror of [buildBorderFloodMask]: expensive, awaited once, and kept off
/// the paint path so the composer stays synchronous.
Future<ui.Image> decodePlacedImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

/// A freehand stroke. [width] is a fraction of the source image's width.
@immutable
class BrushOp extends EditOp {
  const BrushOp({
    required this.points,
    required this.color,
    required this.width,
    this.marker = false,
  });

  final List<Offset> points;
  final Color color;
  final double width;

  /// A highlighter rather than a pen: translucent, with a flat end, so the
  /// text under it still reads.
  final bool marker;

  BrushOp extend(Offset point) => BrushOp(
    points: [...points, point],
    color: color,
    width: width,
    marker: marker,
  );
}

/// The straight-line markup a drag draws.
enum MarkupKind { arrow, line, box, oval }

/// An arrow, a line, a box or an oval dragged from [start] to [end].
///
/// Points are normalised against the oriented source image like every other
/// op; [width] is a fraction of the image's width, like a brush stroke's.
@immutable
class MarkupOp extends EditOp {
  const MarkupOp({
    required this.kind,
    required this.start,
    required this.end,
    required this.color,
    required this.width,
  });

  final MarkupKind kind;
  final Offset start;
  final Offset end;
  final Color color;
  final double width;

  MarkupOp withEnd(Offset next) =>
      MarkupOp(kind: kind, start: start, end: next, color: color, width: width);
}

/// A mosaic of part of the photo: a grid of square cells and the colour of
/// each, read from the pixels.
///
/// Carried as colours because there is no pixelate filter to ask the GPU for.
/// That keeps the composer synchronous and the cells the same on every
/// renderer.
@immutable
class Mosaic {
  const Mosaic({
    required this.rect,
    required this.cols,
    required this.rows,
    required this.colors,
  });

  /// The grid's outer edge, normalised against the photo.
  final Rect rect;
  final int cols;
  final int rows;

  /// ARGB, row by row, `cols * rows` of them.
  final List<int> colors;
}

/// How a hidden area hides what is under it.
enum HideStyle {
  /// The same part of the photo, blurred past legibility.
  ///
  /// Reads as "something was here" rather than as a patch laid over the
  /// artwork, which is what a chat list or an account page usually wants. Not
  /// a security guarantee at low strengths and not sold as one: the strength
  /// floor is set where text stops being recoverable by eye.
  blur,

  /// Square cells of the photo's own colours.
  pixelate,

  /// An opaque patch. Nothing survives it, and sampled from the surrounding
  /// UI it disappears into the design.
  cover,
}

/// The outline of a hidden area.
enum HideShape { box, oval, freehand }

/// A part of the photo hidden from view — a name, a face, a number.
///
/// Placed like a sticker rather than baked in like a stroke, so it can be
/// selected, moved, stretched from a side and restyled after it is drawn. The
/// rectangle it replaced could not be: one dragged a few pixels short of the
/// name it was for had to be undone and drawn again.
///
/// A pixelated area carries no cells. They are read from the photo under it,
/// wherever it is now, through [ScreenshotComposer.pixels] — so an area moved
/// across the photo pixelates what it has been moved over rather than
/// carrying a copy of what it used to cover.
///
/// Never see-through: [opacity] is always 1, whatever a placement asks, because
/// a hidden area that shows a little of what it hides has not hidden it.
@immutable
class HideOp extends PlacedOp {
  const HideOp({
    required super.id,
    required super.center,
    required super.width,
    required super.height,
    super.rotationDeg,
    this.style = HideStyle.blur,
    this.shape = HideShape.box,
    this.outline = const [],
    this.blur = 0.03,
    this.block = 0.035,
    this.color = const Color(0xFF000000),
    this.cornerRadius = 0,
  });

  final HideStyle style;
  final HideShape shape;

  /// A freehand area's edge, as points in its box from -0.5 to 0.5 across and
  /// down — so the outline stretches and turns with the box.
  final List<Offset> outline;

  /// The blur's sigma, as a fraction of the photo's width.
  final double blur;

  /// A mosaic cell's edge, as a fraction of the photo's width.
  final double block;

  /// What a cover is filled with.
  final Color color;

  /// A box's corner radius, as a fraction of the photo's width.
  final double cornerRadius;

  /// Whether this has an edge of its own to draw. A freehand area drawn with
  /// too few points to enclose anything falls back to its box.
  bool get isFreehand => shape == HideShape.freehand && outline.length >= 3;

  /// The area's edge inside [box], a rect in pixels. [radius] rounds a box.
  Path outlineIn(Rect box, {double radius = 0}) {
    if (isFreehand) {
      final path = Path();
      for (final (i, p) in outline.indexed) {
        final at = box.center + Offset(p.dx * box.width, p.dy * box.height);
        if (i == 0) {
          path.moveTo(at.dx, at.dy);
        } else {
          path.lineTo(at.dx, at.dy);
        }
      }
      return path..close();
    }
    if (shape == HideShape.oval) return Path()..addOval(box);
    return Path()
      ..addRRect(RRect.fromRectAndRadius(box, Radius.circular(radius)));
  }

  /// This area spread over [rect], normalised against a photo of [imageSize]
  /// — how a box or an oval is dragged out.
  HideOp over(Rect rect, Size imageSize) => copyWith(
    center: rect.center,
    width: rect.width,
    // Against the width, like every placed box.
    height: rect.height * imageSize.height / imageSize.width,
    rotationDeg: 0,
  );

  /// This area drawn round [points], normalised against a photo of
  /// [imageSize] — how a freehand one is.
  HideOp around(List<Offset> points, Size imageSize) {
    if (points.isEmpty) return this;
    var left = points.first.dx, right = left;
    var top = points.first.dy, bottom = top;
    for (final p in points) {
      left = math.min(left, p.dx);
      right = math.max(right, p.dx);
      top = math.min(top, p.dy);
      bottom = math.max(bottom, p.dy);
    }
    final bounds = Rect.fromLTRB(left, top, right, bottom);
    final w = math.max(bounds.width, 1e-9), h = math.max(bounds.height, 1e-9);
    return over(bounds, imageSize).copyWith(
      shape: HideShape.freehand,
      outline: [
        for (final p in points)
          Offset((p.dx - bounds.center.dx) / w, (p.dy - bounds.center.dy) / h),
      ],
    );
  }

  HideOp copyWith({
    Offset? center,
    double? width,
    double? height,
    double? rotationDeg,
    HideStyle? style,
    HideShape? shape,
    List<Offset>? outline,
    double? blur,
    double? block,
    Color? color,
    double? cornerRadius,
  }) => HideOp(
    id: id,
    center: center ?? this.center,
    width: width ?? this.width,
    height: height ?? this.height,
    rotationDeg: rotationDeg ?? this.rotationDeg,
    style: style ?? this.style,
    shape: shape ?? this.shape,
    outline: outline ?? this.outline,
    blur: blur ?? this.blur,
    block: block ?? this.block,
    color: color ?? this.color,
    cornerRadius: cornerRadius ?? this.cornerRadius,
  );

  @override
  HideOp withPlacement({
    Offset? center,
    double? width,
    double? height,
    double? rotationDeg,
    double? opacity,
  }) => copyWith(
    center: center,
    width: width,
    height: height,
    rotationDeg: rotationDeg,
  );

  @override
  HideOp withId(int id) => HideOp(
    id: id,
    center: center,
    width: width,
    height: height,
    rotationDeg: rotationDeg,
    style: style,
    shape: shape,
    outline: outline,
    blur: blur,
    block: block,
    color: color,
    cornerRadius: cornerRadius,
  );
}

/// Which phone's status bar a clean one is drawn as.
enum StatusBarStyle {
  ios,
  android,
  samsung;

  /// A bar's usual height in this style, as a fraction of the screen's width.
  double get height => switch (this) {
    StatusBarStyle.ios => 0.13,
    StatusBarStyle.android || StatusBarStyle.samsung => 0.1,
  };
}

/// A tidy status bar over the captured one: the time a store listing shows,
/// full signal, full battery — in place of whatever the phone happened to say.
///
/// Across the top of the finished picture rather than at a place on the photo,
/// so a crop changed afterwards takes the bar with it: a phone's status bar is
/// at the top of its screen, and the crop is the screen.
@immutable
class StatusBarOp extends EditOp {
  const StatusBarOp({
    required this.height,
    required this.background,
    required this.foreground,
    required this.style,
    this.time = '9:41',
  });

  /// As a fraction of the picture's width, so the bar keeps its proportion to
  /// the screen whatever the capture's resolution.
  final double height;
  final Color background;
  final Color foreground;
  final StatusBarStyle style;
  final String time;

  StatusBarOp copyWith({
    double? height,
    Color? background,
    Color? foreground,
    StatusBarStyle? style,
    String? time,
  }) => StatusBarOp(
    height: height ?? this.height,
    background: background ?? this.background,
    foreground: foreground ?? this.foreground,
    style: style ?? this.style,
    time: time ?? this.time,
  );
}

/// Which phone's navigation a clean bar is drawn as.
enum NavBarStyle {
  /// Android's gesture handle: a short pill.
  gesture,

  /// An iPhone's home indicator: a longer, thinner pill near the edge.
  ios,

  /// Android's three buttons: back, home and recent apps.
  buttons,

  /// A Samsung phone's three buttons, the other way round: recent apps, home
  /// and back.
  samsung;

  /// A bar's usual height in this style, as a fraction of the screen's width.
  double get height => switch (this) {
    NavBarStyle.gesture => 0.058,
    NavBarStyle.ios => 0.087,
    NavBarStyle.buttons || NavBarStyle.samsung => 0.117,
  };
}

/// A navigation bar across the bottom of the finished picture — a gesture
/// handle, a home indicator or three buttons. Anchored like [StatusBarOp].
@immutable
class NavBarOp extends EditOp {
  const NavBarOp({
    required this.height,
    required this.style,
    required this.background,
    required this.foreground,
  });

  /// As a fraction of the picture's width.
  final double height;
  final NavBarStyle style;

  /// Transparent for a handle drawn straight over the app, which is how an
  /// iPhone's home indicator sits.
  final Color background;
  final Color foreground;

  NavBarOp copyWith({
    double? height,
    NavBarStyle? style,
    Color? background,
    Color? foreground,
  }) => NavBarOp(
    height: height ?? this.height,
    style: style ?? this.style,
    background: background ?? this.background,
    foreground: foreground ?? this.foreground,
  );
}

/// Whole-image tone, colour and look.
///
/// Not an [EditOp]: these apply to the photo underneath everything, not as
/// another layer stacked in op order, and there is only ever one set of them.
/// Stored on the composer beside the crop for the same reason.
///
/// Every slider value is centred on zero meaning "untouched", so [isIdentity]
/// is the question the painter asks to skip the work entirely. The colour
/// controls all multiply into one [ColorMatrix]; [vignette] and [blur] are the
/// two that are not colour transforms and are painted by the composer itself.
@immutable
class ImageAdjustments {
  const ImageAdjustments({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.exposure = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.warmth = 0,
    this.tint = 0,
    this.fade = 0,
    this.vignette = 0,
    this.blur = 0,
    this.look = PhotoFilter.none,
    this.lookStrength = 1,
  });

  /// -1 – 1. Lifts or lowers the picture through its middle.
  final double brightness;

  /// -1 – 1. Scales each channel about mid-grey.
  final double contrast;

  /// -1 – 1, where -1 is fully grey and 1 is roughly double.
  final double saturation;

  /// -1 – 1, a stop either way.
  final double exposure;

  /// -1 – 1. Positive brightens the bright end, negative pulls it back.
  final double highlights;

  /// -1 – 1. Positive lifts the dark end, negative deepens it.
  final double shadows;

  /// -1 – 1. Positive warmer, negative cooler.
  final double warmth;

  /// -1 – 1. Positive magenta, negative green.
  final double tint;

  /// 0 – 1. A matte lift of the blacks.
  final double fade;

  /// -1 – 1. Negative darkens the corners, positive lightens them.
  final double vignette;

  /// 0 – 1. Softens the whole photo — a backdrop behind a device, mostly.
  final double blur;

  /// The one-tap look under the sliders, and how much of it.
  final PhotoFilter look;
  final double lookStrength;

  bool get isIdentity =>
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      exposure == 0 &&
      highlights == 0 &&
      shadows == 0 &&
      warmth == 0 &&
      tint == 0 &&
      fade == 0 &&
      vignette == 0 &&
      blur == 0 &&
      (look == PhotoFilter.none || lookStrength <= 0);

  /// Whether anything changes a pixel's colour — the question the painter asks
  /// before putting a colour filter on the image paint.
  bool get changesColor => !matrix.isIdentity;

  ImageAdjustments copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? exposure,
    double? highlights,
    double? shadows,
    double? warmth,
    double? tint,
    double? fade,
    double? vignette,
    double? blur,
    PhotoFilter? look,
    double? lookStrength,
  }) => ImageAdjustments(
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    exposure: exposure ?? this.exposure,
    highlights: highlights ?? this.highlights,
    shadows: shadows ?? this.shadows,
    warmth: warmth ?? this.warmth,
    tint: tint ?? this.tint,
    fade: fade ?? this.fade,
    vignette: vignette ?? this.vignette,
    blur: blur ?? this.blur,
    look: look ?? this.look,
    lookStrength: lookStrength ?? this.lookStrength,
  );

  /// The same sliders with no look under them — what Reset in the Adjust tool
  /// leaves behind when a filter is still wanted, and vice versa.
  ImageAdjustments withoutSliders() =>
      ImageAdjustments(look: look, lookStrength: lookStrength);

  /// Every colour control as one matrix: the look first, then the sliders
  /// that fine-tune it, in the order a photographer reads them — light, then
  /// tone, then colour, then finish.
  ColorMatrix get matrix => look.matrix
      .strength(lookStrength)
      .then(Tone.exposure(exposure))
      .then(Tone.highlights(highlights))
      .then(Tone.shadows(shadows))
      .then(Tone.contrast(contrast))
      .then(Tone.brightness(brightness))
      .then(Tone.saturation(saturation))
      .then(Tone.warmth(warmth))
      .then(Tone.tint(tint))
      .then(Tone.fade(fade));

  /// [matrix] as the filter an image paint takes.
  ColorFilter get filter => matrix.toFilter();

  /// The vignette actually painted: the slider's plus the look's own.
  double get totalVignette =>
      (vignette + look.vignette * lookStrength.clamp(0.0, 1.0)).clamp(
        -1.0,
        1.0,
      );

  @override
  bool operator ==(Object other) =>
      other is ImageAdjustments &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation &&
      other.exposure == exposure &&
      other.highlights == highlights &&
      other.shadows == shadows &&
      other.warmth == warmth &&
      other.tint == tint &&
      other.fade == fade &&
      other.vignette == vignette &&
      other.blur == blur &&
      other.look == look &&
      other.lookStrength == lookStrength;

  @override
  int get hashCode => Object.hash(
    brightness,
    contrast,
    saturation,
    exposure,
    highlights,
    shadows,
    warmth,
    tint,
    fade,
    vignette,
    blur,
    look,
    lookStrength,
  );
}

/// Erases the screenshot's flat page background so the subject floats on
/// transparency — the treatment that turns a captured game board into store
/// art.
///
/// The per-pixel work happens once, at commit time, in [buildBorderFloodMask];
/// the op itself only carries the resulting source-resolution mask, which is
/// what keeps [ScreenshotComposer.paint] synchronous and undo/redo free. The
/// mask erases the *image layer only*: brush and redact ops paint on top of
/// the cutout untouched, whichever order they were committed in.
@immutable
class RemoveBackgroundOp extends EditOp {
  const RemoveBackgroundOp({required this.mask, required this.tolerance});

  /// Opaque where the background was, transparent over the subject, partial
  /// on the one-pixel feather ring. Drawn over the artwork with
  /// [BlendMode.dstOut].
  final ui.Image mask;

  /// The summed per-channel RGB distance the flood fill used, kept so the op
  /// can describe itself and a redo can be rebuilt if ever needed.
  final int tolerance;
}

/// Builds the mask [RemoveBackgroundOp] carries.
///
/// A border flood fill, not chroma keying: the page colour is sampled from the
/// four corners and everything *reachable from the image edge* within
/// [tolerance] (summed |ΔR|+|ΔG|+|ΔB|) is background. Enclosed regions the
/// fill cannot reach stay part of the subject, exactly as they read visually.
/// Two refinements ported from real store-art production:
///
/// * **Island sweep** — after the fill, any surviving foreground blob except
///   the largest one is background too. This is what removes a floating
///   button's anti-aliased rim without the tolerance having to reach it.
/// * **Feather** — the outermost kept pixel ring goes half-transparent so the
///   tolerance cliff doesn't read as a stairstepped edge once scaled.
///
/// A phone screenshot is a couple of million pixels and this walks all of them
/// several times, so the pixel work runs on a background isolate; only the
/// decode has to come back to the UI thread.
Future<ui.Image> buildBorderFloodMask(
  ui.Image image, {
  int tolerance = 90,
}) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final mask = await compute(_floodMaskBytes, (
    data!.buffer.asUint8List(),
    image.width,
    image.height,
    tolerance,
  ));

  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    mask,
    image.width,
    image.height,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}

/// The pixel half of [buildBorderFloodMask], as a top-level function so it can
/// be handed to an isolate. Typed arrays throughout: at 1080x2400 the state,
/// label and stack buffers are eight megabytes as `Uint8List`/`Uint32List` and
/// several times that as boxed `List<int>`.
Uint8List _floodMaskBytes((Uint8List, int, int, int) request) {
  final (px, w, h, tolerance) = request;
  final count = w * h;

  // The page colour, averaged over the four corners.
  var bgR = 0, bgG = 0, bgB = 0;
  for (final (cx, cy) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]) {
    final o = (cy * w + cx) * 4;
    bgR += px[o];
    bgG += px[o + 1];
    bgB += px[o + 2];
  }
  bgR ~/= 4;
  bgG ~/= 4;
  bgB ~/= 4;

  bool isBg(int i) =>
      (px[i * 4] - bgR).abs() +
          (px[i * 4 + 1] - bgG).abs() +
          (px[i * 4 + 2] - bgB).abs() <
      tolerance;

  // 0 = untouched, 1 = visited-not-background, 2 = background.
  final state = Uint8List(count);
  final queue = Uint32List(count);
  var tail = 0;

  void seed(int x, int y) {
    final i = y * w + x;
    if (state[i] == 0) {
      if (isBg(i)) {
        state[i] = 2;
        queue[tail++] = i;
      } else {
        state[i] = 1;
      }
    }
  }

  for (var x = 0; x < w; x++) {
    seed(x, 0);
    seed(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    seed(0, y);
    seed(w - 1, y);
  }
  for (var head = 0; head < tail; head++) {
    final i = queue[head];
    final x = i % w, y = i ~/ w;
    if (x > 0) seed(x - 1, y);
    if (x < w - 1) seed(x + 1, y);
    if (y > 0) seed(x, y - 1);
    if (y < h - 1) seed(x, y + 1);
  }

  final comp = Uint32List(count);
  final stack = Uint32List(count);

  // Pockets: page-coloured pixels the fill could not reach because something
  // closes them in — the inside of an "o", the gap in a "4". Small ones are
  // page too. A big one is more likely the subject's own (a white shirt with
  // a dark outline), so it stays.
  final pocketLimit = math.max(4, (count * 0.002).round());
  final pockets = <int>[0];
  for (var start = 0; start < count; start++) {
    if (state[start] == 2 || comp[start] != 0 || !isBg(start)) continue;
    final label = pockets.length;
    pockets.add(0);
    comp[start] = label;
    var top = 0;
    stack[top++] = start;
    var size = 0;
    while (top > 0) {
      final j = stack[--top];
      size++;
      final x = j % w, y = j ~/ w;
      for (final n in [
        if (x > 0) j - 1,
        if (x < w - 1) j + 1,
        if (y > 0) j - w,
        if (y < h - 1) j + w,
      ]) {
        if (state[n] != 2 && comp[n] == 0 && isBg(n)) {
          comp[n] = label;
          stack[top++] = n;
        }
      }
    }
    pockets[label] = size;
  }
  for (var i = 0; i < count; i++) {
    final label = comp[i];
    if (label != 0 && pockets[label] < pocketLimit) state[i] = 2;
  }
  comp.fillRange(0, count, 0);

  // Island sweep: label every kept component and drop the specks — a few
  // pixels of noise the fill could not reach. Everything bigger stays. Keeping
  // only the largest island, as this once did, cut a wordmark down to its
  // biggest letter and a screenshot down to one button.
  final sizes = <int>[0];
  for (var start = 0; start < count; start++) {
    if (state[start] == 2 || comp[start] != 0) continue;
    final label = sizes.length;
    sizes.add(0);
    comp[start] = label;
    var top = 0;
    stack[top++] = start;
    var size = 0;
    while (top > 0) {
      final j = stack[--top];
      size++;
      final x = j % w, y = j ~/ w;
      if (x > 0 && state[j - 1] != 2 && comp[j - 1] == 0) {
        comp[j - 1] = label;
        stack[top++] = j - 1;
      }
      if (x < w - 1 && state[j + 1] != 2 && comp[j + 1] == 0) {
        comp[j + 1] = label;
        stack[top++] = j + 1;
      }
      if (y > 0 && state[j - w] != 2 && comp[j - w] == 0) {
        comp[j - w] = label;
        stack[top++] = j - w;
      }
      if (y < h - 1 && state[j + w] != 2 && comp[j + w] == 0) {
        comp[j + w] = label;
        stack[top++] = j + w;
      }
    }
    sizes[label] = size;
  }
  final speck = math.max(8, count ~/ 400000);
  for (var i = 0; i < count; i++) {
    if (state[i] != 2 && sizes[comp[i]] < speck) state[i] = 2;
  }

  // Mask bytes: opaque white erases, transparent keeps, the feather ring
  // half-erases. decodeImageFromPixels expects premultiplied RGBA, so the
  // feather's colour channels carry its alpha.
  final mask = Uint8List(count * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (state[i] == 2) {
        mask[i * 4] = 255;
        mask[i * 4 + 1] = 255;
        mask[i * 4 + 2] = 255;
        mask[i * 4 + 3] = 255;
      } else {
        final bare =
            (x > 0 && state[i - 1] == 2) ||
            (x < w - 1 && state[i + 1] == 2) ||
            (y > 0 && state[i - w] == 2) ||
            (y < h - 1 && state[i + w] == 2);
        if (bare) {
          mask[i * 4] = 115;
          mask[i * 4 + 1] = 115;
          mask[i * 4 + 2] = 115;
          mask[i * 4 + 3] = 115;
        }
      }
    }
  }
  return mask;
}

/// How the area outside the source image is filled when the crop is expanded
/// past the artwork's own edges.
///
/// True content-aware fill means a diffusion model, which is not something to
/// run on a phone. For app screenshots it is also not needed: the region just
/// outside a capture is almost always a flat status-bar colour, a nav-bar, or
/// a smooth background gradient, and continuing those outward is exactly what
/// an ML fill would have produced anyway. These four cover it.
enum ExpandFill {
  /// Smear the outermost row/column of pixels outward. The default, and the
  /// closest thing to content-aware for flat and gradient UI edges.
  edge,

  /// Reflect the image across each edge. Best when the border has texture or
  /// structure the eye expects to continue.
  mirror,

  /// Edge-extended, then heavily softened, so nothing reads as a hard streak.
  blur,

  /// A flat fill — the eyedropper colour. Exact when the border really is one
  /// colour, and the honest choice when nothing else looks right.
  solid,
}

/// Renders the source image plus its ops into a destination rect.
///
/// Shared verbatim by the on-screen painter and the exporter, so the pixels the
/// user is looking at while editing are the pixels that get written out.

/// How the source image is turned before anything else happens to it.
///
/// Everything else in the retoucher — the crop, the brush strokes, the
/// redactions, the zoom — works in *oriented* space: what the user is looking
/// at. Only the image itself, and the masks that erase parts of it, have to be
/// un-turned on the way to the canvas, which is why this is the one transform
/// that lives down here with the compositor rather than up in the editor.
///
/// Screenshots arrive axis-aligned, so there is no arbitrary-angle straighten:
/// a capture is never crooked, and an angle that is not a quarter turn cannot
/// fill its own crop without a zoom-and-resample that would cost sharpness for
/// a case that does not exist. Quarter turns and a mirror are the operations a
/// screenshot actually needs — a landscape capture going into a portrait frame,
/// and the occasional right-to-left mock-up.
class ImageOrientation {
  const ImageOrientation({
    this.turns = 0,
    this.flipH = false,
    this.flipV = false,
    this.angle = 0,
  });

  /// Quarter turns clockwise, 0–3.
  final int turns;

  /// Mirrored left-to-right, applied after [turns].
  final bool flipH;

  /// Mirrored top-to-bottom, applied after [turns].
  final bool flipV;

  /// Straighten, in degrees clockwise, -45–45.
  ///
  /// A photo taken a few degrees off level is common where a screenshot never
  /// is, and this editor edits both. The turned picture is enlarged just enough
  /// to still cover its own frame (see [coverScale]), so straightening never
  /// shows an empty corner and never changes the frame's shape — the crop, and
  /// every stroke and sticker stated against it, stays where it was.
  final double angle;

  static const none = ImageOrientation();

  bool get isIdentity => turns == 0 && !flipH && !flipV && angle == 0;

  /// True when the turn swaps width for height.
  bool get isQuarter => turns.isOdd;

  ImageOrientation copyWith({
    int? turns,
    bool? flipH,
    bool? flipV,
    double? angle,
  }) => ImageOrientation(
    turns: ((turns ?? this.turns) % 4 + 4) % 4,
    flipH: flipH ?? this.flipH,
    flipV: flipV ?? this.flipV,
    angle: (angle ?? this.angle).clamp(-45.0, 45.0),
  );

  /// One more quarter turn in [by]'s direction.
  ImageOrientation rotated(int by) => copyWith(turns: turns + by);

  /// [source] as the user now sees it.
  Size sizeOf(Size source) =>
      isQuarter ? Size(source.height, source.width) : source;

  /// How much a picture of [frame]'s shape is enlarged so that, turned by
  /// [angle], it still covers the whole of [frame].
  ///
  /// The frame turned the other way has to fit inside the enlarged picture:
  /// its bounding box is `w·cos + h·sin` by `w·sin + h·cos`.
  double coverScale(Size frame) {
    if (angle == 0 || frame.isEmpty) return 1;
    final a = angle.abs() * math.pi / 180;
    final c = math.cos(a), s = math.sin(a);
    final w = frame.width, h = frame.height;
    return math.max((w * c + h * s) / w, (w * s + h * c) / h);
  }

  /// An oriented normalised point, back in the source image's own coordinates.
  ///
  /// The pixel sampler reads the decoded image, which never turns, so an
  /// eyedropper tapped on a rotated view has to ask about the pixel that is
  /// really under the finger rather than the one that would be if nothing had
  /// moved.
  ///
  /// [frame] is the oriented picture's size, which the straighten needs to undo
  /// a turn in pixels — a turn applied to fractions of a non-square picture is
  /// a shear. Without it a straightened orientation maps as if level.
  Offset toSource(Offset oriented, {Size? frame}) {
    var p = oriented;
    if (angle != 0 && frame != null && !frame.isEmpty) {
      // Undo the straighten about the centre, in pixels, and the enlargement
      // that went with it.
      final a = -angle * math.pi / 180;
      final k = coverScale(frame);
      final d = Offset((p.dx - 0.5) * frame.width, (p.dy - 0.5) * frame.height);
      final r = Offset(
        d.dx * math.cos(a) - d.dy * math.sin(a),
        d.dx * math.sin(a) + d.dy * math.cos(a),
      );
      p = Offset(0.5 + r.dx / k / frame.width, 0.5 + r.dy / k / frame.height);
    }
    if (flipH) p = Offset(1 - p.dx, p.dy);
    if (flipV) p = Offset(p.dx, 1 - p.dy);
    // A quarter turn clockwise maps (x, y) to (1 - y, x); this undoes one.
    for (var i = 0; i < turns; i++) {
      p = Offset(p.dy, 1 - p.dx);
    }
    return p;
  }

  /// Sets [canvas] up so that drawing the source image into the returned rect
  /// lands it inside [oriented], turned, mirrored and straightened. Call inside
  /// a save/restore pair.
  Rect prepare(Canvas canvas, Rect oriented) {
    if (isIdentity) return oriented;
    final c = oriented.center;
    canvas.translate(c.dx, c.dy);
    if (angle != 0) {
      final k = coverScale(oriented.size);
      canvas
        ..rotate(angle * math.pi / 180)
        ..scale(k, k);
    }
    canvas
      ..scale(flipH ? -1.0 : 1.0, flipV ? -1.0 : 1.0)
      ..rotate(turns * math.pi / 2)
      ..translate(-c.dx, -c.dy);
    return isQuarter
        ? Rect.fromCenter(
            center: c,
            width: oriented.height,
            height: oriented.width,
          )
        : oriented;
  }

  @override
  bool operator ==(Object other) =>
      other is ImageOrientation &&
      other.turns == turns &&
      other.flipH == flipH &&
      other.flipV == flipV &&
      other.angle == angle;

  @override
  int get hashCode => Object.hash(turns, flipH, flipV, angle);
}

class ScreenshotComposer {
  const ScreenshotComposer({
    required this.image,
    required this.crop,
    required this.ops,
    this.fill = ExpandFill.edge,
    this.fillColor = const Color(0xFF000000),
    this.adjustments = const ImageAdjustments(),
    this.orientation = ImageOrientation.none,
    this.frame,
    this.pixels,
  });

  /// The decoded source screenshot.
  final ui.Image image;

  /// [image]'s pixels, which a pixelated [HideOp]'s cells are read from.
  ///
  /// Null, or not read yet, draws a pixelated area as a blur instead — hidden
  /// either way, which is the part that matters.
  final PixelSampler? pixels;

  /// The finished picture's own edges, normalised, when [crop] is only the part
  /// of it on screen — the editor zoomed in. The vignette darkens the corners
  /// of the *picture*, not of whatever slice of it is being looked at. Null
  /// means [crop] is the whole picture, which is what an export always asks.
  final Rect? frame;

  /// Visible region of [image], normalised. `Rect.fromLTRB(0,0,1,1)` is "all".
  ///
  /// May extend **outside** the unit square: negative left/top and right/bottom
  /// past 1 mean the user has pulled the crop beyond the artwork, and the
  /// surplus is generated by [fill].
  final Rect crop;

  /// Ops in draw order.
  final List<EditOp> ops;

  /// How to manufacture pixels outside the source image.
  final ExpandFill fill;

  /// The colour used by [ExpandFill.solid].
  final Color fillColor;

  /// Tone adjustments applied to the screenshot itself.
  ///
  /// The image layer only — the annotations on top keep the colours they were
  /// drawn in, which is what a highlight or a redaction patch has to do if it
  /// is going to stay legible against a darkened screenshot.
  final ImageAdjustments adjustments;

  /// How the source image is turned. Everything else here — [crop], [ops] —
  /// is stated against the turned result.
  final ImageOrientation orientation;

  /// Whether the crop currently reaches outside the artwork.
  bool get isExpanded =>
      crop.left < -1e-6 ||
      crop.top < -1e-6 ||
      crop.right > 1 + 1e-6 ||
      crop.bottom > 1 + 1e-6;

  /// The image as the user sees it, which a quarter turn stands on its side.
  ///
  /// Every rect in this class is against this rather than against the decoded
  /// image, so a crop dragged over a turned screenshot means what it looks like
  /// it means.
  Size get imageSize =>
      orientation.sizeOf(Size(image.width.toDouble(), image.height.toDouble()));

  /// The crop expressed in source pixels.
  Rect get sourceRect => Rect.fromLTRB(
    crop.left * imageSize.width,
    crop.top * imageSize.height,
    crop.right * imageSize.width,
    crop.bottom * imageSize.height,
  );

  /// Pixel dimensions a full-resolution export would have.
  Size get exportSize => Size(
    math.max(1, sourceRect.width.roundToDouble()),
    math.max(1, sourceRect.height.roundToDouble()),
  );

  /// Paints everything into [dest].
  void paint(Canvas canvas, Rect dest) {
    canvas.save();
    canvas.clipRect(dest);

    // One unit of normalised image width, measured in destination pixels.
    final scale = dest.width / math.max(sourceRect.width, 1);

    // Where the artwork itself lands inside `dest`. When the crop has been
    // pulled outside the image this is smaller than `dest`, and the margins
    // around it are what the fill has to manufacture.
    final artwork = Rect.fromLTRB(
      dest.left + (0 - sourceRect.left) * scale,
      dest.top + (0 - sourceRect.top) * scale,
      dest.left + (imageSize.width - sourceRect.left) * scale,
      dest.top + (imageSize.height - sourceRect.top) * scale,
    );

    if (isExpanded) {
      _paintExpansion(canvas, dest, artwork);
    }

    final colour = adjustments.changesColor ? adjustments.filter : null;
    _paintPhoto(canvas, artwork, colour: colour);

    Offset map(Offset normalised) => Offset(
      dest.left + (normalised.dx * imageSize.width - sourceRect.left) * scale,
      dest.top + (normalised.dy * imageSize.height - sourceRect.top) * scale,
    );

    // One unit of normalised image WIDTH, in destination pixels. Stroke widths,
    // corner radii, blur sigmas and placed boxes are all fractions of the
    // image's width, so this single multiply is what keeps preview and export
    // the same picture at two scales.
    final unit = imageSize.width * scale;

    _paintVignette(canvas, map, artwork);

    // The finished picture's edges on the stage — the crop, even when only
    // part of it is on screen. The bars are drawn across its top and bottom.
    final edges = frame ?? crop;
    final picture = Rect.fromPoints(map(edges.topLeft), map(edges.bottomRight));

    for (final op in ops) {
      switch (op) {
        case BrushOp(:final points, :final color, :final width, :final marker):
          if (points.isEmpty) continue;
          final paint = Paint()
            ..color = marker ? color.withValues(alpha: color.a * 0.42) : color
            ..style = PaintingStyle.stroke
            // A highlighter's nib is flat; a pen's is round.
            ..strokeCap = marker ? StrokeCap.square : StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = math.max(1, width * imageSize.width * scale);
          if (points.length == 1) {
            canvas.drawPoints(ui.PointMode.points, [map(points.first)], paint);
          } else {
            final path = Path()
              ..moveTo(map(points.first).dx, map(points.first).dy);
            for (var i = 1; i < points.length; i++) {
              final p = map(points[i]);
              path.lineTo(p.dx, p.dy);
            }
            canvas.drawPath(path, paint);
          }
        case MarkupOp():
          _paintMarkup(canvas, op, map(op.start), map(op.end), unit);
        case HideOp():
          _paintHidden(canvas, op, map, unit, artwork);
        case StatusBarOp(
          :final height,
          :final style,
          :final background,
          :final foreground,
          :final time,
        ):
          paintCleanStatusBar(
            canvas,
            Rect.fromLTWH(
              picture.left,
              picture.top,
              picture.width,
              height * picture.width,
            ),
            style: style,
            background: background,
            foreground: foreground,
            time: time,
          );
        case NavBarOp(
          :final height,
          :final style,
          :final background,
          :final foreground,
        ):
          paintCleanNavBar(
            canvas,
            Rect.fromLTRB(
              picture.left,
              picture.bottom - height * picture.width,
              picture.right,
              picture.bottom,
            ),
            style: style,
            background: background,
            foreground: foreground,
          );
        case ShapeOp(:final spec):
          // Painted in op order, deliberately unlike the background masks
          // above: a shape laid down after a redaction has to sit on top of
          // it, and hoisting placed objects into a pre-pass would silently
          // reorder the user's own stack.
          final box = Size(op.width * unit, op.height * unit);
          if (box.isEmpty) continue;

          final at = map(op.center);
          canvas.save();
          canvas.translate(at.dx, at.dy);
          if (op.rotationDeg != 0) {
            canvas.rotate(op.rotationDeg * math.pi / 180);
          }

          final faded = op.opacity < 1;
          if (faded) {
            // Null bounds rather than the box: a shape's shadow reaches
            // outside the shape casting it, and a layer sized to the box would
            // clip the shadow off at the edge.
            canvas.saveLayer(
              null,
              Paint()
                ..color = Color.fromRGBO(0, 0, 0, op.opacity.clamp(0.0, 1.0)),
            );
          }

          canvas.translate(-box.width / 2, -box.height / 2);
          // `unit` as the canvas width, because every width-ish number on a
          // spec — the stroke, the shadow's blur and its offset — is a
          // fraction of the canvas it was measured against, and the canvas a
          // retouch op is measured against is the capture itself.
          ShapePainter(
            spec: spec,
            canvasWidth: unit,
            boxSize: box,
          ).paint(canvas, box);
          _paintShapeLabel(canvas, spec, box, unit, op.width);

          if (faded) canvas.restore();
          canvas.restore();
        case TextOp():
          final box = Size(op.width * unit, op.height * unit);
          if (box.isEmpty) continue;
          final at = map(op.center);
          canvas.save();
          canvas.translate(at.dx, at.dy);
          if (op.rotationDeg != 0) {
            canvas.rotate(op.rotationDeg * math.pi / 180);
          }
          final faded = op.opacity < 1;
          if (faded) {
            canvas.saveLayer(
              null,
              Paint()
                ..color = Color.fromRGBO(0, 0, 0, op.opacity.clamp(0.0, 1.0)),
            );
          }
          canvas.translate(-box.width / 2, -box.height / 2);
          op.paintInto(canvas, box);
          if (faded) canvas.restore();
          canvas.restore();
        case ImageOp(image: final bitmap, :final flipH, :final cornerRadius):
          final box = Size(op.width * unit, op.height * unit);
          if (box.isEmpty) continue;

          final at = map(op.center);
          canvas.save();
          canvas.translate(at.dx, at.dy);
          if (op.rotationDeg != 0) {
            canvas.rotate(op.rotationDeg * math.pi / 180);
          }
          // After the rotation, about the box's own centre, so a mirrored and
          // turned image reads as the same object seen from the other side
          // rather than as one turned the other way.
          if (flipH) canvas.scale(-1, 1);
          canvas.translate(-box.width / 2, -box.height / 2);

          final target = Offset.zero & box;
          if (cornerRadius > 0) {
            canvas.save();
            canvas.clipRRect(
              RRect.fromRectAndRadius(
                target,
                Radius.circular(cornerRadius * unit),
              ),
            );
          }
          final shown = op.crop;
          canvas.drawImageRect(
            bitmap,
            Rect.fromLTRB(
              shown.left * bitmap.width,
              shown.top * bitmap.height,
              shown.right * bitmap.width,
              shown.bottom * bitmap.height,
            ),
            target,
            Paint()
              ..filterQuality = FilterQuality.high
              // Alpha folded into the paint rather than a `saveLayer`: a single
              // `drawImageRect` modulates by paint alpha for nothing, and a
              // layer would cost a full surface on every frame of a slider
              // drag.
              //
              // The photo's tone adjustments are deliberately NOT applied
              // here: a placed logo keeps the colours it was made in, for the
              // same reason a redaction patch does.
              ..color = Color.fromRGBO(0, 0, 0, op.opacity.clamp(0.0, 1.0)),
          );
          if (cornerRadius > 0) canvas.restore();
          if (op.borderWidth > 0) {
            // Inside the edge, so a thick rim does not grow the image past
            // the box its handles are on.
            final stroke = op.borderWidth * unit;
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                target.deflate(stroke / 2),
                Radius.circular(math.max(0, cornerRadius * unit - stroke / 2)),
              ),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = stroke
                ..color = op.borderColor.withValues(
                  alpha: op.borderColor.a * op.opacity.clamp(0.0, 1.0),
                ),
            );
          }
          canvas.restore();
        case StickerOp(
          :final picture,
          :final pictureSize,
          :final tint,
          :final flipH,
        ):
          final box = Size(op.width * unit, op.height * unit);
          if (box.isEmpty || pictureSize.isEmpty) continue;

          final at = map(op.center);
          canvas.save();
          canvas.translate(at.dx, at.dy);
          if (op.rotationDeg != 0) {
            canvas.rotate(op.rotationDeg * math.pi / 180);
          }
          if (flipH) canvas.scale(-1, 1);
          canvas.translate(-box.width / 2, -box.height / 2);

          // Bounded to the picture's own rect, unlike a shape's null bounds: a
          // sticker casts no shadow reaching outside itself, so an unbounded
          // layer would just be a bigger surface for the same result.
          final bounds = Offset.zero & pictureSize;
          final faded = op.opacity < 1;
          final tinted = tint != null;
          canvas.scale(
            box.width / pictureSize.width,
            box.height / pictureSize.height,
          );
          if (faded) {
            canvas.saveLayer(
              bounds,
              Paint()
                ..color = Color.fromRGBO(0, 0, 0, op.opacity.clamp(0.0, 1.0)),
            );
          }
          if (tinted) canvas.saveLayer(bounds, Paint());
          canvas.drawPicture(picture);
          if (tinted) {
            // srcIn keeps the art's own alpha and replaces its colour, which is
            // what makes a one-colour sticker recolour cleanly rather than
            // being covered by a rectangle.
            canvas.drawColor(tint, BlendMode.srcIn);
            canvas.restore();
          }
          if (faded) canvas.restore();
          canvas.restore();
        case RemoveBackgroundOp():
          // Applied with the image layer above, not in op order.
          break;
      }
    }

    canvas.restore();
  }

  /// The photo itself: turned, straightened, toned, softened, and with any
  /// cut-out applied.
  void _paintPhoto(Canvas canvas, Rect artwork, {ColorFilter? colour}) {
    // Background-removal masks erase the image layer only, so image + masks
    // composite inside their own layer: dstOut against the shared canvas would
    // punch through the expansion bands (and the editor's backdrop) instead of
    // leaving honest transparency.
    final masks = ops.whereType<RemoveBackgroundOp>();
    final straightened = orientation.angle != 0;

    // A straightened photo is enlarged past its frame; the surplus is clipped
    // to the frame rather than left to spill into an expansion's margin.
    if (straightened) {
      canvas.save();
      canvas.clipRect(artwork);
    }

    // The whole-photo blur, in destination pixels so it is the same softness
    // at preview size and at export size.
    final soften = adjustments.blur.clamp(0.0, 1.0);
    final blurred = soften > 0;
    if (blurred) {
      final sigma = math.max(0.5, soften * 0.025 * artwork.width);
      canvas.saveLayer(
        artwork,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          ),
      );
    }

    if (masks.isNotEmpty) canvas.saveLayer(artwork.inflate(1), Paint());
    // The turn applies to the picture and to the masks that erase parts of it,
    // and to nothing else: a brush stroke drawn on a sideways screenshot was
    // drawn where the user saw it, and turning it again would move it.
    canvas.save();
    final upright = orientation.prepare(canvas, artwork);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      upright,
      Paint()
        ..filterQuality = FilterQuality.high
        // Straight onto the image paint rather than through a layer: a colour
        // filter on a single `drawImageRect` costs nothing, and a `saveLayer`
        // over the whole photo on every frame of a slider drag costs a
        // full-canvas surface each time.
        ..colorFilter = colour,
    );
    for (final op in masks) {
      canvas.drawImageRect(
        op.mask,
        Rect.fromLTWH(
          0,
          0,
          op.mask.width.toDouble(),
          op.mask.height.toDouble(),
        ),
        upright,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..filterQuality = FilterQuality.high,
      );
    }
    canvas.restore();
    if (masks.isNotEmpty) canvas.restore();
    if (blurred) canvas.restore();
    if (straightened) canvas.restore();
  }

  /// A hidden area: its outline clipped out of the stage, turned with it, and
  /// the photo under it covered, blurred or cut into cells.
  void _paintHidden(
    Canvas canvas,
    HideOp op,
    Offset Function(Offset) map,
    double unit,
    Rect artwork,
  ) {
    final box = Rect.fromCenter(
      center: Offset.zero,
      width: op.width * unit,
      height: op.height * unit,
    );
    if (box.isEmpty) return;

    // How far the turned area reaches, normalised and on the stage: the
    // bounds a blur's layer and a mosaic's cells are laid over.
    final corners = op.corners(imageSize);
    final reach = Rect.fromLTRB(
      corners.map((c) => c.dx).reduce(math.min),
      corners.map((c) => c.dy).reduce(math.min),
      corners.map((c) => c.dx).reduce(math.max),
      corners.map((c) => c.dy).reduce(math.max),
    );
    final bounds = Rect.fromPoints(map(reach.topLeft), map(reach.bottomRight));

    final at = map(op.center);
    final turn = op.rotationDeg * math.pi / 180;
    canvas.save();
    // Clipped in the area's own frame, then back on the stage's: the clip
    // stays where it was put, and the photo under it is drawn upright.
    canvas.translate(at.dx, at.dy);
    if (turn != 0) canvas.rotate(turn);
    canvas.clipPath(op.outlineIn(box, radius: op.cornerRadius * unit));
    if (turn != 0) canvas.rotate(-turn);
    canvas.translate(-at.dx, -at.dy);

    switch (op.style) {
      case HideStyle.cover:
        canvas.drawPaint(Paint()..color = op.color);
      case HideStyle.blur:
        _paintBlurred(canvas, bounds, math.max(0.5, op.blur * unit), artwork);
      case HideStyle.pixelate:
        final mosaic = pixels?.mosaic(
          reach,
          block: op.block,
          orientation: orientation,
          frame: imageSize,
        );
        if (mosaic == null) {
          // Until the pixels are read, a blur about as coarse as the cells.
          _paintBlurred(
            canvas,
            bounds,
            math.max(0.5, op.block * unit * 0.6),
            artwork,
          );
        } else {
          _paintMosaic(canvas, mosaic, map);
        }
    }
    canvas.restore();
  }

  /// The photo redrawn through a blur, over [bounds] on the stage.
  ///
  /// Not a backdrop filter: `BackdropFilter` is a widget and this paints into
  /// whatever canvas it is handed, including the exporter's. Redrawing the
  /// image is also what makes the blur identical at preview and export scale —
  /// the sigma is a fraction of the source width, multiplied by the same
  /// `scale` every other measurement here uses.
  void _paintBlurred(Canvas canvas, Rect bounds, double sigma, Rect artwork) {
    canvas.saveLayer(
      bounds,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          // Clamp, not decal: decal fades the area's own edges to transparent
          // and the hiding reads as a soft hole.
          tileMode: TileMode.clamp,
        ),
    );
    // Turned, mirrored and straightened like the photo itself — drawn
    // upright, a blur over a rotated photo blurred the wrong part of it.
    canvas.save();
    final upright = orientation.prepare(canvas, artwork);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      upright,
      Paint()
        ..filterQuality = FilterQuality.high
        ..colorFilter = adjustments.changesColor ? adjustments.filter : null,
    );
    canvas.restore();
    canvas.restore();
  }

  void _paintMosaic(Canvas canvas, Mosaic mosaic, Offset Function(Offset) map) {
    final Mosaic(:rect, :cols, :rows, :colors) = mosaic;
    if (cols <= 0 || rows <= 0 || colors.length < cols * rows) return;
    final cellW = rect.width / cols;
    final cellH = rect.height / rows;
    // Hard-edged cells: anti-aliasing puts a faint seam down every join.
    final cell = Paint()
      ..isAntiAlias = false
      ..colorFilter = adjustments.changesColor ? adjustments.filter : null;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        cell.color = Color(colors[row * cols + col]);
        canvas.drawRect(
          Rect.fromPoints(
            map(Offset(rect.left + col * cellW, rect.top + row * cellH)),
            map(
              Offset(
                rect.left + (col + 1) * cellW,
                rect.top + (row + 1) * cellH,
              ),
            ),
          ),
          cell,
        );
      }
    }
  }

  /// Darkens — or, negative, lightens — the corners of the finished picture.
  void _paintVignette(
    Canvas canvas,
    Offset Function(Offset) map,
    Rect artwork,
  ) {
    final amount = adjustments.totalVignette;
    if (amount == 0) return;
    final edges = frame ?? crop;
    final picture = Rect.fromPoints(map(edges.topLeft), map(edges.bottomRight));
    if (picture.isEmpty) return;
    // Negative darkens, which is what nearly everyone means by a vignette.
    final shade = amount < 0
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
    final strength = amount.abs() * 0.85;
    final radius = picture.size.longestSide * 0.75;
    canvas.save();
    // Over the photo only: a vignette on an expansion's manufactured margin
    // would mark where the real picture ends.
    canvas.clipRect(picture.intersect(artwork));
    canvas.drawRect(
      picture,
      Paint()
        ..shader = ui.Gradient.radial(
          picture.center,
          radius,
          [
            shade.withValues(alpha: 0),
            shade.withValues(alpha: 0),
            shade.withValues(alpha: strength),
          ],
          const [0, 0.45, 1],
          TileMode.clamp,
          // Stretched to the picture's shape about its centre, so a tall phone
          // screenshot darkens all four corners rather than just the top and
          // bottom.
          (Matrix4.identity()
                ..translateByDouble(picture.center.dx, picture.center.dy, 0, 1)
                ..scaleByDouble(
                  picture.width / picture.size.longestSide,
                  picture.height / picture.size.longestSide,
                  1,
                  1,
                )
                ..translateByDouble(
                  -picture.center.dx,
                  -picture.center.dy,
                  0,
                  1,
                ))
              .storage,
        ),
    );
    canvas.restore();
  }

  /// An arrow, line, box or oval between two destination points.
  /// A shape's words — a badge's "NEW!", a laurel's "#1" — laid out in its box
  /// the way the scene's label layer lays them out.
  ///
  /// Sized against the box the shape is placed at here, not against the canvas
  /// the element was drawn for: the words of a badge made bigger grow with it.
  void _paintShapeLabel(
    Canvas canvas,
    ShapeSpec spec,
    Size box,
    double unit,
    double placedWidth,
  ) {
    final label = spec.label;
    if (label == null || label.text.trim().isEmpty) return;
    final k = spec.width <= 0 ? 1.0 : placedWidth / spec.width;
    final pad = label.padding * unit * k;
    final painter = TextPainter(
      text: TextSpan(
        text: label.allUpCase ? label.text.toUpperCase() : label.text,
        style: StudioFonts.style(
          label.fontFamily,
          fontSize: label.size * unit * k,
          height: label.lineHeight,
          letterSpacing: label.letterSpacing == 0
              ? null
              : label.letterSpacing * unit * k,
          color: label.color,
          fontWeight: switch (label.weight) {
            null => label.bold ? FontWeight.bold : FontWeight.normal,
            final w => FontWeight.values[(w.clamp(100, 900) ~/ 100) - 1],
          },
          fontStyle: label.italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textAlign: label.align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(0, box.width - pad * 2));
    final dx = switch (label.align) {
      TextAlign.left || TextAlign.start => pad,
      TextAlign.right || TextAlign.end => box.width - pad - painter.width,
      _ => (box.width - painter.width) / 2,
    };
    painter.paint(canvas, Offset(dx, (box.height - painter.height) / 2));
    painter.dispose();
  }

  void _paintMarkup(
    Canvas canvas,
    MarkupOp op,
    Offset from,
    Offset to,
    double unit,
  ) {
    final width = math.max(1.0, op.width * unit);
    final stroke = Paint()
      ..color = op.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (op.kind) {
      case MarkupKind.line:
        canvas.drawLine(from, to, stroke);
      case MarkupKind.arrow:
        final d = to - from;
        final length = d.distance;
        if (length < 0.5) return;
        final dir = d / length;
        // The head grows with the stroke, and never outgrows the arrow.
        final head = math.min(width * 4.2, length * 0.6);
        final back = to - dir * head;
        final side = Offset(-dir.dy, dir.dx) * head * 0.55;
        // The shaft stops inside the head so its round cap cannot poke out of
        // the point.
        canvas.drawLine(from, to - dir * head * 0.5, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(to.dx, to.dy)
            ..lineTo(back.dx + side.dx, back.dy + side.dy)
            ..lineTo(back.dx - side.dx, back.dy - side.dy)
            ..close(),
          Paint()
            ..color = op.color
            ..style = PaintingStyle.fill
            ..strokeJoin = StrokeJoin.round,
        );
      case MarkupKind.box:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromPoints(from, to),
            Radius.circular(width * 0.8),
          ),
          stroke,
        );
      case MarkupKind.oval:
        canvas.drawOval(Rect.fromPoints(from, to), stroke);
    }
  }

  /// Manufactures the pixels outside the artwork.
  void _paintExpansion(Canvas canvas, Rect dest, Rect artwork) {
    switch (fill) {
      case ExpandFill.solid:
        canvas.drawRect(dest, Paint()..color = fillColor);
      case ExpandFill.mirror:
        _paintMirrorTiles(canvas, artwork);
      case ExpandFill.edge:
        _paintEdgeExtend(canvas, dest, artwork, _bandPaint());
      case ExpandFill.blur:
        // Blur the manufactured region as ONE layer, not band by band —
        // blurring each band separately fades its own edges and leaves seams
        // exactly where the bands meet. The bands are drawn past `dest` so the
        // blur has material at the visible border instead of fading out into
        // transparency there; the clip in `paint` trims the overdraw.
        final sigma = math.max(2.0, _expansion(dest, artwork) * 0.35);
        canvas.saveLayer(
          dest,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: sigma,
              sigmaY: sigma,
              tileMode: TileMode.clamp,
            ),
        );
        _paintEdgeExtend(
          canvas,
          dest.inflate(sigma * 3),
          artwork,
          _bandPaint(),
        );
        canvas.restore();
    }
  }

  /// Bilinear, deliberately not cubic.
  ///
  /// The edge bands sample a source rect one pixel thick. Cubic filtering
  /// reaches beyond that rect for its neighbouring taps, so the row *behind*
  /// the border bleeds into the fill — a measurable wrong colour, not a
  /// rounding artefact. Bilinear clamps inside the rect and is exact here.
  Paint _bandPaint() => Paint()..filterQuality = FilterQuality.medium;

  /// The widest margin between the artwork and the crop, in destination px.
  double _expansion(Rect dest, Rect artwork) => math.max(
    0,
    math.max(
      math.max(artwork.left - dest.left, artwork.top - dest.top),
      math.max(dest.right - artwork.right, dest.bottom - artwork.bottom),
    ),
  );

  /// Stretches the image's outermost row/column outward to fill `bounds`.
  ///
  /// Nine-slice thinking: four edge bands from a 1px source line, four corners
  /// from a single pixel. Stretching a 1px source is what makes this cheap —
  /// no per-pixel work and no second decode, just eight `drawImageRect` calls
  /// the GPU already knows how to do.
  void _paintEdgeExtend(Canvas canvas, Rect bounds, Rect artwork, Paint paint) {
    final w = image.width.toDouble();
    final h = image.height.toDouble();

    // Run each band a pixel *under* the artwork. The band samples the image's
    // outermost texel while the artwork is drawn with its own filtering, and
    // the two disagree by a fraction at the join — visible as a hairline seam.
    // The artwork is painted after this, so the overlap is simply covered.
    const overlap = 1.0;
    final inner = Rect.fromLTRB(
      artwork.left + overlap,
      artwork.top + overlap,
      artwork.right - overlap,
      artwork.bottom - overlap,
    );

    void band(Rect src, Rect dst) {
      if (dst.width <= 0 || dst.height <= 0) return;
      canvas.drawImageRect(image, src, dst, paint);
    }

    band(
      Rect.fromLTWH(0, 0, w, 1),
      Rect.fromLTRB(artwork.left, bounds.top, artwork.right, inner.top),
    );
    band(
      Rect.fromLTWH(0, h - 1, w, 1),
      Rect.fromLTRB(artwork.left, inner.bottom, artwork.right, bounds.bottom),
    );
    band(
      Rect.fromLTWH(0, 0, 1, h),
      Rect.fromLTRB(bounds.left, artwork.top, inner.left, artwork.bottom),
    );
    band(
      Rect.fromLTWH(w - 1, 0, 1, h),
      Rect.fromLTRB(inner.right, artwork.top, bounds.right, artwork.bottom),
    );

    band(
      const Rect.fromLTWH(0, 0, 1, 1),
      Rect.fromLTRB(bounds.left, bounds.top, inner.left, inner.top),
    );
    band(
      Rect.fromLTWH(w - 1, 0, 1, 1),
      Rect.fromLTRB(inner.right, bounds.top, bounds.right, inner.top),
    );
    band(
      const Rect.fromLTWH(0, 0, 1, 1).translate(0, h - 1),
      Rect.fromLTRB(bounds.left, inner.bottom, inner.left, bounds.bottom),
    );
    band(
      Rect.fromLTWH(w - 1, h - 1, 1, 1),
      Rect.fromLTRB(inner.right, inner.bottom, bounds.right, bounds.bottom),
    );
  }

  /// Tiles the image mirrored around `artwork`, one ring of eight neighbours.
  ///
  /// Each tile is flipped about its OWN centre, which is what makes adjacent
  /// tiles share an identical edge row — the join is invisible. One ring is
  /// always enough: the crop cannot be dragged more than a full frame past the
  /// artwork on any side.
  void _paintMirrorTiles(Canvas canvas, Rect artwork) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final paint = Paint()..filterQuality = FilterQuality.high;

    for (var sx = -1; sx <= 1; sx++) {
      for (var sy = -1; sy <= 1; sy++) {
        if (sx == 0 && sy == 0) continue;
        final dst = artwork.translate(artwork.width * sx, artwork.height * sy);
        canvas.save();
        canvas.translate(dst.center.dx, dst.center.dy);
        canvas.scale(sx == 0 ? 1.0 : -1.0, sy == 0 ? 1.0 : -1.0);
        canvas.translate(-dst.center.dx, -dst.center.dy);
        canvas.drawImageRect(image, src, dst, paint);
        canvas.restore();
      }
    }
  }

  /// Flattens the result to PNG bytes at full source resolution.
  Future<Uint8List?> toPng() async {
    final size = exportSize;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    paint(canvas, Rect.fromLTWH(0, 0, size.width, size.height));
    final picture = recorder.endRecording();
    try {
      final rendered = await picture.toImage(
        size.width.round(),
        size.height.round(),
      );
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      return data?.buffer.asUint8List();
    } finally {
      picture.dispose();
    }
  }
}

/// Random-access pixel reads for the eyedropper.
///
/// Decoding the whole image to RGBA costs `w * h * 4` bytes, so it is done once
/// on first use and kept for the life of the editor session.
class PixelSampler {
  PixelSampler(this._image);

  final ui.Image _image;
  ByteData? _rgba;

  Future<void> prepare() async {
    _rgba ??= await _image.toByteData(format: ui.ImageByteFormat.rawRgba);
  }

  /// Reads the colour at a normalised image coordinate, or null if the pixel
  /// data is not available yet.
  Color? at(Offset normalised) {
    final data = _rgba;
    if (data == null) return null;
    final x = (normalised.dx * _image.width).round().clamp(0, _image.width - 1);
    final y = (normalised.dy * _image.height).round().clamp(
      0,
      _image.height - 1,
    );
    final offset = (y * _image.width + x) * 4;
    if (offset < 0 || offset + 3 >= data.lengthInBytes) return null;
    return Color.fromARGB(
      255,
      data.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
    );
  }

  /// Whether the pixels have been read yet. Everything below needs them.
  bool get isReady => _rgba != null;

  int _pixel(int x, int y) {
    final data = _rgba!;
    final o = (y * _image.width + x) * 4;
    return (data.getUint8(o) << 16) |
        (data.getUint8(o + 1) << 8) |
        data.getUint8(o + 2);
  }

  /// Mosaics already read, newest last, so a still area costs nothing to
  /// repaint and a dragged one only what it has moved onto.
  final Map<(Rect, double, ImageOrientation, Size), Mosaic> _mosaics = {};

  /// A mosaic covering [bounds] — a region of the photo as the user sees it,
  /// turned by [orientation] into a picture of [frame]'s size — in square
  /// cells [block] of the picture's width across. Null until the pixels are
  /// read, or for a region so large the cells would not be worth reading.
  ///
  /// The cells sit on one grid anchored at the photo's corner, not at the
  /// region's. So an area dragged across the photo does not re-cut everything
  /// under it at every step, and two areas side by side meet in whole cells.
  Mosaic? mosaic(
    Rect bounds, {
    required double block,
    required ImageOrientation orientation,
    required Size frame,
  }) {
    if (_rgba == null || bounds.isEmpty || frame.isEmpty) return null;
    final key = (bounds, block, orientation, frame);
    final held = _mosaics.remove(key);
    if (held != null) return _mosaics[key] = held;

    final cellPx = math.max(4.0, block * frame.width);
    final cellX = cellPx / frame.width;
    final cellY = cellPx / frame.height;
    final firstCol = (bounds.left / cellX).floor();
    final firstRow = (bounds.top / cellY).floor();
    final cols = math.max(1, (bounds.right / cellX).ceil() - firstCol);
    final rows = math.max(1, (bounds.bottom / cellY).ceil() - firstRow);
    // A mosaic of a whole photo at the finest cell is ~10,000 cells; nine
    // samples each is still far below one frame's budget.
    if (cols * rows > 12000) return null;

    final colors = <int>[];
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        var r = 0, g = 0, b = 0, n = 0;
        for (var sy = 0; sy < 3; sy++) {
          for (var sx = 0; sx < 3; sx++) {
            final at = orientation.toSource(
              Offset(
                (firstCol + col + (sx + 0.5) / 3) * cellX,
                (firstRow + row + (sy + 0.5) / 3) * cellY,
              ),
              frame: frame,
            );
            final x = (at.dx * _image.width).floor().clamp(0, _image.width - 1);
            final y = (at.dy * _image.height).floor().clamp(
              0,
              _image.height - 1,
            );
            final p = _pixel(x, y);
            r += (p >> 16) & 0xFF;
            g += (p >> 8) & 0xFF;
            b += p & 0xFF;
            n++;
          }
        }
        colors.add(0xFF000000 | (r ~/ n) << 16 | (g ~/ n) << 8 | (b ~/ n));
      }
    }
    final mosaic = Mosaic(
      rect: Rect.fromLTWH(
        firstCol * cellX,
        firstRow * cellY,
        cols * cellX,
        rows * cellY,
      ),
      cols: cols,
      rows: rows,
      colors: colors,
    );
    _mosaics[key] = mosaic;
    if (_mosaics.length > 48) _mosaics.remove(_mosaics.keys.first);
    return mosaic;
  }

  /// A one-tap fix: stretch the photo's tones to fill the range, and give
  /// flat colour a little life. Null until the pixels are ready, or when the
  /// photo is already well spread — a screenshot of an app, usually.
  ImageAdjustments? autoEnhance() {
    final data = _rgba;
    if (data == null) return null;
    final histogram = List<int>.filled(256, 0);
    var saturationSum = 0.0;
    var count = 0;
    // Every pixel is not needed to find where the tones sit; a sparse grid of
    // ~40,000 is the same answer at a fraction of the time.
    final step = math
        .max(1, math.sqrt(_image.width * _image.height / 40000))
        .floor();
    for (var y = 0; y < _image.height; y += step) {
      for (var x = 0; x < _image.width; x += step) {
        final p = _pixel(x, y);
        final r = (p >> 16) & 0xFF, g = (p >> 8) & 0xFF, b = p & 0xFF;
        final luma = (0.299 * r + 0.587 * g + 0.114 * b).round();
        histogram[luma.clamp(0, 255)]++;
        final hi = math.max(r, math.max(g, b));
        final lo = math.min(r, math.min(g, b));
        if (hi > 0) saturationSum += (hi - lo) / hi;
        count++;
      }
    }
    if (count == 0) return null;
    int percentile(double q) {
      final target = count * q;
      var seen = 0;
      for (var i = 0; i < 256; i++) {
        seen += histogram[i];
        if (seen >= target) return i;
      }
      return 255;
    }

    final low = percentile(0.01), high = percentile(0.99);
    final spread = math.max(1, high - low);
    final mid = (low + high) / 2;
    // Exposure first: it takes the middle of the tones most of the way to
    // mid-grey, and it multiplies, so black stays black. Then contrast — which
    // pivots on mid-grey, where the middle now nearly is — widens what is
    // left towards the full range. Only widens: the stretch is capped, since
    // a big stretch of a photo taken in the dark is noise made visible.
    //
    // Contrast alone, as this once was, pivoted a dark photo's middle further
    // into the dark, and no amount of brightness pulled it back.
    final gain = ((mid + (128 - mid) * 0.6) / math.max(1.0, mid)).clamp(
      0.5,
      2.0,
    );
    final exposure = math.log(gain) / math.ln2;
    final wanted = math.min(spread * 1.6, math.max(245.0, spread.toDouble()));
    final contrast = (wanted / (spread * gain) - 1).clamp(0.0, 0.6);
    final meanSaturation = saturationSum / count;
    final saturation = meanSaturation < 0.25 ? 0.15 : 0.06;
    if (contrast < 0.02 && exposure.abs() < 0.02) return null;
    return ImageAdjustments(
      exposure: double.parse(exposure.toStringAsFixed(2)),
      contrast: double.parse(contrast.toStringAsFixed(2)),
      saturation: saturation,
    );
  }

  /// Where the captured status bar ends, as a fraction of the capture's
  /// height — found from the row of clock and icons near the top, which sits
  /// in the middle of the bar. [fallback] when there is no such row.
  double statusBarHeight({double fallback = 0.055}) {
    if (_rgba == null) return fallback;
    final w = _image.width, h = _image.height;
    final limit = (h * 0.09).round();
    bool inky(int y) {
      final background = _pixel(1, y);
      var ink = 0;
      for (var i = 0; i < 96; i++) {
        final x = ((i + 0.5) / 96 * w).floor().clamp(0, w - 1);
        final p = _pixel(x, y);
        final d =
            (((p >> 16) & 0xFF) - ((background >> 16) & 0xFF)).abs() +
            (((p >> 8) & 0xFF) - ((background >> 8) & 0xFF)).abs() +
            ((p & 0xFF) - (background & 0xFF)).abs();
        if (d > 90) ink++;
      }
      return ink >= 2;
    }

    var first = -1;
    for (var y = 2; y < limit; y++) {
      if (inky(y)) {
        first = y;
        break;
      }
    }
    if (first < 0) return fallback;
    var last = first;
    while (last + 1 < limit && inky(last + 1)) {
      last++;
    }
    // The glyphs are centred in the bar: the gap above them is the gap below.
    final bar = (last + first) / h;
    return bar.clamp(0.025, 0.085);
  }

  void dispose() {
    _rgba = null;
    _mosaics.clear();
  }
}

/// The largest rect of [aspect] (width / height) that fits inside a normalised
/// 1x1 image of [imageAspect], centred — i.e. exactly the region `BoxFit.cover`
/// would show inside a device screen of that shape.
Rect coverCrop({required double imageAspect, required double aspect}) {
  if (!aspect.isFinite ||
      aspect <= 0 ||
      !imageAspect.isFinite ||
      imageAspect <= 0) {
    return const Rect.fromLTRB(0, 0, 1, 1);
  }
  if (imageAspect > aspect) {
    // Source is wider than the target: trim the sides.
    final width = aspect / imageAspect;
    return Rect.fromLTWH((1 - width) / 2, 0, width, 1);
  }
  // Source is taller: trim top and bottom.
  final height = imageAspect / aspect;
  return Rect.fromLTWH(0, (1 - height) / 2, 1, height);
}

/// How far outside the image a crop may reach, as a fraction of the image.
///
/// 35% a side. Two things pin it: the crop stage shows exactly this much
/// margin, so the reachable area and the visible area are the same thing —
/// you can drag as far as you can see and no further — and a bigger view would
/// shrink the artwork itself to make room for space that is mostly unused.
/// It is also well inside what one ring of mirrored tiles can serve.
const double kMaxExpand = 0.35;

/// Smallest crop edge, as a fraction of the image. Below this the marquee is
/// smaller than its own corner handles and becomes impossible to grab back.
const double kMinCrop = 0.05;

/// Clamps [rect] to the region a crop is allowed to occupy.
///
/// When [expand] is false this is the unit square: the classic behaviour, where
/// the crop can only ever *lose* pixels. When it is true the crop may reach up
/// to [kMaxExpand] outside on every side, and the surplus is manufactured by
/// [ScreenshotComposer]'s fill.
Rect clampCrop(Rect rect, {bool expand = false}) {
  final limit = expand ? kMaxExpand : 0.0;
  final span = 1 + limit * 2;
  final width = rect.width.clamp(kMinCrop, span);
  final height = rect.height.clamp(kMinCrop, span);
  final left = rect.left.clamp(-limit, 1 + limit - width);
  final top = rect.top.clamp(-limit, 1 + limit - height);
  return Rect.fromLTWH(left, top, width, height);
}

/// Reshapes [crop] back onto [targetAspect] about its own centre.
///
/// Used when the ratio lock is turned back on after a free-form drag: the width
/// is kept and the height re-derived, unless that would not fit, in which case
/// the height is capped and the width follows instead. The result is clamped,
/// so re-locking can never leave the crop outside its allowed region.
Rect lockCropToAspect(
  Rect crop, {
  required Size imageSize,
  required double targetAspect,
  bool expand = false,
}) {
  if (imageSize.isEmpty || targetAspect <= 0 || !targetAspect.isFinite) {
    return crop;
  }
  final span = 1 + (expand ? kMaxExpand : 0.0) * 2;

  double heightFor(double w) =>
      w * imageSize.width / (targetAspect * imageSize.height);
  double widthFor(double h) =>
      h * targetAspect * imageSize.height / imageSize.width;

  var width = crop.width.clamp(kMinCrop, span);
  var height = heightFor(width);
  if (height > span) {
    height = span;
    width = widthFor(height);
  }
  return clampCrop(
    Rect.fromCenter(center: crop.center, width: width, height: height),
    expand: expand,
  );
}

/// Grab points on the crop window, in the order the canvas hit-tests them.
///
/// The four corners come first because they win a tie: on a small marquee the
/// corner and edge hit zones overlap, and a corner is the more specific intent.
/// The four edges resize a single axis — the whole point of pulling one is that
/// the *other* axis stays where it was put.
enum CropHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  left,
  top,
  right,
  bottom,
}

extension CropHandleGeometry on CropHandle {
  /// True for the four corners; false for the four edge grips.
  bool get isCorner =>
      this == CropHandle.topLeft ||
      this == CropHandle.topRight ||
      this == CropHandle.bottomLeft ||
      this == CropHandle.bottomRight;

  /// An edge grip that moves the left or right side, so the drag reads on x.
  bool get isSideEdge => this == CropHandle.left || this == CropHandle.right;

  /// An edge grip that moves the top or bottom side, so the drag reads on y.
  bool get isEndEdge => this == CropHandle.top || this == CropHandle.bottom;

  /// Whether the grabbed geometry includes the left edge (so the right is the
  /// anchor).
  bool get grabsLeft =>
      this == CropHandle.topLeft ||
      this == CropHandle.bottomLeft ||
      this == CropHandle.left;

  /// Whether the grabbed geometry includes the top edge (so the bottom is the
  /// anchor).
  bool get grabsTop =>
      this == CropHandle.topLeft ||
      this == CropHandle.topRight ||
      this == CropHandle.top;
}

/// Resizes [base] by dragging [handle] to [pointer], keeping the crop's **pixel**
/// aspect pinned to [targetAspect].
///
/// The opposite corner stays put and the width follows the finger; the height is
/// always derived, so the crop can never drift away from the device screen's
/// shape. Growth is bounded by how much room the anchor has on each axis, which
/// is what stops a drag from pushing the rect off the image and being silently
/// reshaped by [clampCrop].
///
/// Returns [base] unchanged when there is no room left to resize into.
///
/// With [expand] the room extends [kMaxExpand] past the image on every side, so
/// the same drag that used to stop dead at the edge keeps going and the extra
/// area gets filled instead.
///
/// With [lockAspect] false the pinning is released: each axis follows the finger
/// on its own, so the crop takes any shape the drag describes. The frame will
/// still `cover` whatever comes out, so a free crop can be re-cropped a second
/// time on the canvas — that is the trade the caller is making, and
/// [lockCropToAspect] is how it is undone.
///
/// The four edge handles resize one axis. Unlocked that is all they do — the
/// other axis keeps both of its edges exactly where they were, which is what
/// makes a side grip worth having over a corner. Locked, the derived axis has
/// to move, and it grows about the crop's own centre so the marquee stays put
/// rather than drifting toward one side.
Rect resizeCropFromCorner({
  required Rect base,
  required CropHandle handle,
  required Offset pointer,
  required Size imageSize,
  required double targetAspect,
  bool expand = false,
  bool lockAspect = true,
}) {
  if (imageSize.isEmpty) return base;
  if (lockAspect && (targetAspect <= 0 || !targetAspect.isFinite)) return base;

  // Normalised height that keeps `(w * imageW) / (h * imageH) == targetAspect`,
  // and its inverse.
  double heightFor(double width) =>
      width * imageSize.width / (targetAspect * imageSize.height);
  double widthFor(double height) =>
      height * targetAspect * imageSize.height / imageSize.width;

  final grabbedLeft = handle.grabsLeft;
  final grabbedTop = handle.grabsTop;

  final anchor = Offset(
    grabbedLeft ? base.right : base.left,
    grabbedTop ? base.bottom : base.top,
  );

  final limit = expand ? kMaxExpand : 0.0;
  final low = -limit;
  final high = 1 + limit;

  /// Room a centred axis has: symmetric growth stops as soon as the nearer side
  /// runs out, so this is twice the smaller half.
  double centredRoom(double centre) =>
      2 * math.min(centre - low, high - centre);

  final availableWidth = grabbedLeft ? anchor.dx - low : high - anchor.dx;
  final availableHeight = grabbedTop ? anchor.dy - low : high - anchor.dy;

  double width;
  double height;
  double left;
  double top;

  if (handle.isCorner) {
    if (lockAspect) {
      final maxWidth = math.min(availableWidth, widthFor(availableHeight));
      if (maxWidth <= kMinCrop) return base;
      width = (pointer.dx - anchor.dx).abs().clamp(kMinCrop, maxWidth);
      height = heightFor(width);
    } else {
      // Unpinned: neither axis constrains the other, so each one only has to
      // clear the minimum and stay inside the room its own anchor has left.
      if (availableWidth <= kMinCrop || availableHeight <= kMinCrop) {
        return base;
      }
      width = (pointer.dx - anchor.dx).abs().clamp(kMinCrop, availableWidth);
      height = (pointer.dy - anchor.dy).abs().clamp(kMinCrop, availableHeight);
    }
    left = grabbedLeft ? anchor.dx - width : anchor.dx;
    top = grabbedTop ? anchor.dy - height : anchor.dy;
  } else if (handle.isSideEdge) {
    final centre = base.center.dy;
    if (lockAspect) {
      final maxWidth = math.min(availableWidth, widthFor(centredRoom(centre)));
      if (maxWidth <= kMinCrop) return base;
      width = (pointer.dx - anchor.dx).abs().clamp(kMinCrop, maxWidth);
      height = heightFor(width);
      top = centre - height / 2;
    } else {
      if (availableWidth <= kMinCrop) return base;
      width = (pointer.dx - anchor.dx).abs().clamp(kMinCrop, availableWidth);
      height = base.height;
      top = base.top;
    }
    left = grabbedLeft ? anchor.dx - width : anchor.dx;
  } else {
    final centre = base.center.dx;
    if (lockAspect) {
      final maxHeight = math.min(
        availableHeight,
        heightFor(centredRoom(centre)),
      );
      if (maxHeight <= kMinCrop) return base;
      height = (pointer.dy - anchor.dy).abs().clamp(kMinCrop, maxHeight);
      width = widthFor(height);
      left = centre - width / 2;
    } else {
      if (availableHeight <= kMinCrop) return base;
      height = (pointer.dy - anchor.dy).abs().clamp(kMinCrop, availableHeight);
      width = base.width;
      left = base.left;
    }
    top = grabbedTop ? anchor.dy - height : anchor.dy;
  }

  return clampCrop(Rect.fromLTWH(left, top, width, height), expand: expand);
}
