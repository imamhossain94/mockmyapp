/// The one painter behind every app icon pixel: the Icon page's large preview,
/// its home-screen and store mock-ups, the store preview's icon tile, and every
/// file the icon export writes.
///
/// It takes an [IconArt] — the design with its glyph outline and picture
/// already resolved — and a canvas, and nothing else: no `BuildContext`, no
/// theme, no lookups. Every colour it paints is the person's own or a literal
/// written here, so an export made with the app in dark mode is the same file,
/// byte for byte, as one made in light mode (CLAUDE.md, "Exports must not
/// depend on the theme"), and a preview is the export at another size.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../data/assets/element_catalog.dart' show IconDef;
import '../../data/assets/studio_fonts.dart';
import '../engine/pattern_painter.dart';
import '../models/icon_doc.dart';
import '../models/screen_doc.dart';

/// An icon ready to paint: the design, with its glyph's outline parsed and its
/// picture decoded. Built by `resolveIconArt`, which does the waiting, so
/// painting never has to.
class IconArt {
  const IconArt(
    this.doc, {
    this.glyphPath,
    this.image,
    this.imageOpaque = false,
  });

  final IconDoc doc;

  /// The Lucide glyph in the unit box, when the foreground is one and it was
  /// found.
  final Path? glyphPath;

  /// The foreground picture, decoded, when the foreground is one and it could
  /// be read.
  final ui.Image? image;

  /// Whether [image] has no transparency of its own — a photo, say, rather
  /// than a cut-out. Its monochrome and clear forms are then read from its
  /// lightness rather than its outline.
  final bool imageOpaque;
}

/// Which of an icon's appearances to paint.
enum IconTone {
  /// The icon as designed — iOS Default, and every other store's only one.
  standard,

  /// iOS Dark: the foreground alone on a transparent background, which the
  /// system lays on its own dark one; a glyph too dark to read there is
  /// lightened ([darkGlyphColor]).
  dark,

  /// iOS Tinted: grayscale, the foreground light on black, for the system to
  /// tint by lightness.
  tinted,

  /// A white silhouette of the foreground on transparency: Android's themed
  /// icon layer, which the launcher colours by alpha.
  mono,

  /// iOS 26 Clear, light: the foreground as a white silhouette on a frosted
  /// light pane. A reference render — Icon Composer makes the real one from
  /// the layers.
  clearLight,

  /// iOS 26 Clear, dark: the same on a smoked dark pane.
  clearDark,
}

/// Where the design's square sits in the canvas being painted.
enum IconFrame {
  /// The whole canvas: the iOS master, Play, Microsoft, apple-touch.
  fullBleed,

  /// The central 72 of an Android adaptive layer's 108 dp, the viewport the
  /// launcher's mask cuts from; the background runs on to the edge for the
  /// launcher's motion.
  adaptive,

  /// The central 80 % of a PWA maskable icon, whose safe zone is the circle
  /// inside it; the background runs on to the edge.
  maskable,

  /// The central 96 of 128 px with transparent padding, cornered — the Chrome
  /// Web Store's icon art.
  padded,
}

/// The side of the design's square in [frame], as a share of the canvas.
double designShare(IconFrame frame) => switch (frame) {
  IconFrame.fullBleed => 1,
  IconFrame.adaptive => 72 / 108,
  IconFrame.maskable => 0.8,
  IconFrame.padded => 96 / 128,
};

/// The design's square inside a [size] canvas framed as [frame].
Rect designRect(Size size, IconFrame frame) {
  final side = math.min(size.width, size.height) * designShare(frame);
  return Rect.fromCenter(
    center: size.center(Offset.zero),
    width: side,
    height: side,
  );
}

/// Paints [art] into a canvas of [size].
///
/// [background] and [foreground] pick the layers — Icon Composer and Android
/// take them as separate files. [shadow] allows the inner shadow where the
/// tone has one; layers the system shades itself leave it out. [mask] clips
/// the design to a preview shape; exports leave it null, except the web icons
/// a browser shows exactly as drawn. [opaquePlate] puts white under a
/// standard background, so a file promised without alpha never has a
/// translucent pixel to lose.
void paintIcon(
  Canvas canvas,
  Size size,
  IconArt art, {
  IconTone tone = IconTone.standard,
  IconFrame frame = IconFrame.fullBleed,
  bool background = true,
  bool foreground = true,
  bool shadow = true,
  IconCorner? mask,
  bool opaquePlate = false,
}) {
  if (size.isEmpty) return;
  final design = designRect(size, frame);
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  if (mask != null && mask != IconCorner.square) {
    canvas.clipPath(iconMaskPath(mask, design));
  }
  if (frame == IconFrame.padded) {
    canvas.clipRRect(
      RRect.fromRectAndRadius(design, Radius.circular(design.width * 0.18)),
    );
  }
  if (background) {
    _paintBackground(canvas, size, design, art, tone, frame, opaquePlate);
  }
  if (foreground) {
    _paintForeground(canvas, design, art, tone, shadow: shadow);
  }
  canvas.restore();
}

/// The outline a preview clips the design to.
///
/// The iOS shape is a superellipse of exponent five — the usual reading of
/// Apple's continuous corner — rather than a rounded rectangle, whose corners
/// meet the sides with a visible kink at icon sizes. The rounded square is the
/// one Google Play gives a listing's icon: corners a fifth of the side.
Path iconMaskPath(IconCorner corner, Rect rect) {
  switch (corner) {
    case IconCorner.square:
      return Path()..addRect(rect);
    case IconCorner.circle:
      return Path()..addOval(rect);
    case IconCorner.rounded:
      return Path()..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.2)),
      );
    case IconCorner.squircle:
      const n = 5.0;
      const steps = 96;
      final a = rect.width / 2;
      final b = rect.height / 2;
      final c = rect.center;
      final path = Path();
      for (var i = 0; i <= steps * 4; i++) {
        final t = i / (steps * 4) * 2 * math.pi;
        final cos = math.cos(t);
        final sin = math.sin(t);
        final x = c.dx + a * cos.sign * math.pow(cos.abs(), 2 / n);
        final y = c.dy + b * sin.sign * math.pow(sin.abs(), 2 / n);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path..close();
  }
}

// -----------------------------------------------------------------------------
// Background
// -----------------------------------------------------------------------------

void _paintBackground(
  Canvas canvas,
  Size size,
  Rect design,
  IconArt art,
  IconTone tone,
  IconFrame frame,
  bool opaquePlate,
) {
  // Outside the design's square only where the frame runs the background on
  // to the edge; the padded frame keeps its padding clear.
  final fill = frame == IconFrame.padded ? design : Offset.zero & size;
  switch (tone) {
    case IconTone.dark || IconTone.mono:
      return;
    case IconTone.tinted:
      canvas.drawRect(fill, Paint()..color = const Color(0xFF000000));
      return;
    case IconTone.clearLight:
      canvas.drawRect(fill, Paint()..color = const Color(0x52FFFFFF));
      return;
    case IconTone.clearDark:
      canvas.drawRect(fill, Paint()..color = const Color(0x8C000000));
      return;
    case IconTone.standard:
      break;
  }
  if (opaquePlate) {
    canvas.drawRect(fill, Paint()..color = const Color(0xFFFFFFFF));
  }
  switch (art.doc.background) {
    case SolidBackground(:final color):
      canvas.drawRect(fill, Paint()..color = color);
    case final GradientBackground gradient:
      // Measured against the design's square and clamped beyond it, so the
      // part a launcher shows is the ramp as designed and the margin it
      // keeps for motion simply carries the end colours on.
      canvas.drawRect(
        fill,
        Paint()..shader = gradient.toGradient().createShader(design),
      );
    case final PatternBackground pattern:
      _paintPattern(canvas, fill, design, pattern);
    case ImageBackground():
      // Not offered for icons; one read from a file shows as its plate.
      canvas.drawRect(fill, Paint()..color = const Color(0xFFFFFFFF));
  }
}

/// A pattern laid out over the design's square, continued past it mirrored
/// where the frame runs on — so the launcher's viewport shows exactly the
/// composition the iOS master shows, and its margin has no seam.
void _paintPattern(
  Canvas canvas,
  Rect fill,
  Rect design,
  PatternBackground pattern,
) {
  final painter = PatternPainter(pattern);
  if (fill == design) {
    canvas.save();
    canvas.translate(design.left, design.top);
    painter.paint(canvas, design.size);
    canvas.restore();
    return;
  }
  final w = design.width.ceil();
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Size(w.toDouble(), w.toDouble()));
  final tile = recorder.endRecording().toImageSync(w, w);
  final scale = design.width / w;
  final matrix = Matrix4.identity()
    ..translateByDouble(design.left, design.top, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1);
  canvas.drawRect(
    fill,
    Paint()
      ..filterQuality = FilterQuality.high
      ..shader = ImageShader(
        tile,
        TileMode.mirror,
        TileMode.mirror,
        matrix.storage,
      ),
  );
  tile.dispose();
}

// -----------------------------------------------------------------------------
// Foreground
// -----------------------------------------------------------------------------

/// The box the foreground is fitted into, inside the design's square.
Rect foregroundRect(IconDoc doc, Rect design) {
  final side = design.width;
  final box = side * doc.scale.clamp(0.05, 1.5);
  final center =
      design.center + Offset(doc.offset.dx * side, doc.offset.dy * side);
  return Rect.fromCenter(center: center, width: box, height: box);
}

void _paintForeground(
  Canvas canvas,
  Rect design,
  IconArt art,
  IconTone tone, {
  required bool shadow,
}) {
  final doc = art.doc;
  if (doc.foreground == null) return;
  final box = foregroundRect(doc, design);
  final inner = doc.innerShadow;
  if (shadow &&
      inner != null &&
      inner.opacity > 0 &&
      tone == IconTone.standard) {
    // Inside the square only: the shadow is the foreground's on its own
    // background, never one round the icon.
    canvas.save();
    canvas.clipRect(design);
    _paintMark(
      canvas,
      box.shift(Offset(0, inner.distance * design.width)),
      art,
      tone,
      silhouette: inner.color.withValues(alpha: inner.opacity.clamp(0, 1)),
      blur: inner.blur * design.width,
    );
    canvas.restore();
  }
  _paintMark(canvas, box, art, tone);
}

/// The glyph's colour in [tone].
Color glyphColorFor(IconDoc doc, IconTone tone) => switch (tone) {
  IconTone.standard => doc.glyphColor,
  IconTone.dark => darkGlyphColor(doc),
  _ => const Color(0xFFFFFFFF),
};

/// The glyph's colour on a dark home screen: its own when it reads there,
/// otherwise the background's own colour when that does — a black glyph on
/// yellow becomes a yellow one on the dark — and white failing both.
Color darkGlyphColor(IconDoc doc) {
  const ground = Color(0xFF1C1C1E);
  if (_contrast(doc.glyphColor, ground) >= 3) return doc.glyphColor;
  for (final colour in backgroundColors(doc.background)) {
    if (_contrast(colour, ground) >= 3) return colour.withValues(alpha: 1);
  }
  return const Color(0xFFFFFFFF);
}

/// The colours [background] is made of, base first.
List<Color> backgroundColors(Background background) => switch (background) {
  SolidBackground(:final color) => [color],
  final GradientBackground gradient => gradient.colors,
  PatternBackground(:final colors) => colors,
  ImageBackground() => const [Color(0xFFFFFFFF)],
};

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Luminance into every channel, alpha kept: a picture in grayscale.
const _grayscale = ColorFilter.matrix([
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// White, keeping the picture's own alpha: the silhouette of a cut-out.
const _whiteByAlpha = ColorFilter.matrix([
  0, 0, 0, 0, 255, //
  0, 0, 0, 0, 255, //
  0, 0, 0, 0, 255, //
  0, 0, 0, 1, 0, //
]);

/// White, with alpha from the picture's lightness: the silhouette of a
/// picture that has no transparency to take one from.
const _whiteByLightness = ColorFilter.matrix([
  0, 0, 0, 0, 255, //
  0, 0, 0, 0, 255, //
  0, 0, 0, 0, 255, //
  0.2126, 0.7152, 0.0722, 0, 0, //
]);

/// Draws the foreground into [box] — in its colours, or as a blurred
/// [silhouette] of one colour for the shadow under it.
void _paintMark(
  Canvas canvas,
  Rect box,
  IconArt art,
  IconTone tone, {
  Color? silhouette,
  double blur = 0,
}) {
  final doc = art.doc;
  final colour = silhouette ?? glyphColorFor(doc, tone);
  final mask = blur > 0.01 ? MaskFilter.blur(BlurStyle.normal, blur) : null;
  switch (doc.foreground) {
    case null:
      return;
    case IconGlyph():
      final unit = art.glyphPath;
      if (unit == null) return;
      final matrix = Matrix4.identity()
        ..translateByDouble(box.left, box.top, 0, 1)
        ..scaleByDouble(box.width, box.height, 1, 1);
      canvas.drawPath(
        unit.transform(matrix.storage),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth =
              IconDef.stroke *
              box.width *
              doc.stroke.clamp(kMinIconStroke, kMaxIconStroke)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true
          ..color = colour
          ..maskFilter = mask,
      );
    case IconText(:final text, :final fontFamily, :final weight):
      _paintText(canvas, box, text, fontFamily, weight, colour, mask);
    case IconImage():
      final image = art.image;
      if (image == null) return;
      final src = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final dst = _contain(src.size, box);
      final ColorFilter? filter;
      if (silhouette != null) {
        filter = ColorFilter.mode(silhouette, BlendMode.srcIn);
      } else {
        filter = switch (tone) {
          IconTone.standard || IconTone.dark => null,
          IconTone.tinted => _grayscale,
          IconTone.mono || IconTone.clearLight || IconTone.clearDark =>
            art.imageOpaque ? _whiteByLightness : _whiteByAlpha,
        };
      }
      final paint = Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true
        ..colorFilter = filter;
      if (blur > 0.01) {
        canvas.saveLayer(
          dst.inflate(blur * 3),
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: blur,
              sigmaY: blur,
              tileMode: TileMode.decal,
            ),
        );
        canvas.drawImageRect(image, src, dst, paint);
        canvas.restore();
      } else {
        canvas.drawImageRect(image, src, dst, paint);
      }
  }
}

Rect _contain(Size source, Rect box) {
  if (source.isEmpty) return box;
  final scale = math.min(box.width / source.width, box.height / source.height);
  return Rect.fromCenter(
    center: box.center,
    width: source.width * scale,
    height: source.height * scale,
  );
}

/// A monogram fitted into [box]: as tall as the box allows, narrowed to its
/// width, and centred on its capitals rather than on the line box, whose
/// room for descenders would sit it high.
void _paintText(
  Canvas canvas,
  Rect box,
  String text,
  String family,
  FontWeight weight,
  Color colour,
  MaskFilter? mask,
) {
  if (text.trim().isEmpty) return;
  TextPainter layout(double fontSize) => TextPainter(
    text: TextSpan(
      text: text,
      style: StudioFonts.style(
        family,
        fontSize: fontSize,
        fontWeight: weight,
        height: 1,
        foreground: Paint()
          ..color = colour
          ..maskFilter = mask,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  // Capitals are about seven tenths of the type size, so a box-high capital
  // wants type about a third larger than the box.
  var fontSize = box.height * 1.3;
  var painter = layout(fontSize);
  if (painter.width > box.width) {
    fontSize *= box.width / painter.width;
    painter.dispose();
    painter = layout(fontSize);
  }
  final baseline = painter.computeDistanceToActualBaseline(
    TextBaseline.alphabetic,
  );
  final capHeight = fontSize * 0.72;
  painter.paint(
    canvas,
    Offset(
      box.center.dx - painter.width / 2,
      box.center.dy + capHeight / 2 - baseline,
    ),
  );
  painter.dispose();
}

/// Paints an [IconArt] as a widget's content. Equal arts repaint nothing.
class IconPainter extends CustomPainter {
  const IconPainter(
    this.art, {
    this.tone = IconTone.standard,
    this.mask,
    this.background = true,
  });

  final IconArt art;
  final IconTone tone;
  final IconCorner? mask;
  final bool background;

  @override
  void paint(Canvas canvas, Size size) => paintIcon(
    canvas,
    size,
    art,
    tone: tone,
    mask: mask,
    background: background,
  );

  @override
  bool shouldRepaint(IconPainter old) =>
      !identical(old.art, art) ||
      old.tone != tone ||
      old.mask != mask ||
      old.background != background;
}
