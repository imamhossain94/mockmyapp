import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'shape_spec.dart';

// Re-exported so a `ScreenDoc` and the shapes on it arrive from one import, the
// way `FramePlacement` and `Background` already do. Shapes live in their own
// file only because this one is long enough.
export 'shape_spec.dart';

class Align2D {
  const Align2D(this.x, this.y);

  final double x;
  final double y;

  static const center = Align2D(0, 0);
}

class Transform2D {
  const Transform2D({
    this.align = Align2D.center,
    this.offsetPct = Offset.zero,
    this.rotationDeg = 0,
    this.scale = 1,
    this.pagePercentage = 0.7,
    this.tiltX = 0,
    this.tiltY = 0,
  });

  final Align2D align;
  final Offset offsetPct;
  final double rotationDeg;
  final double scale;
  final double pagePercentage;

  /// Tilt towards or away from the viewer about the horizontal axis, in
  /// degrees: positive leans the top back. Zero is flat, as every device was
  /// before tilt existed.
  final double tiltX;

  /// Turn about the vertical axis, in degrees: positive brings the right edge
  /// towards the viewer, so the screen faces left and the right-hand side of
  /// the body comes into view. With [tiltX], the perspective store listings use
  /// to make a phone look held rather than pasted.
  final double tiltY;

  /// Whether the device is turned out of the page at all.
  bool get isTilted => tiltX != 0 || tiltY != 0;

  Transform2D copyWith({
    Align2D? align,
    Offset? offsetPct,
    double? rotationDeg,
    double? scale,
    double? pagePercentage,
    double? tiltX,
    double? tiltY,
  }) => Transform2D(
    align: align ?? this.align,
    offsetPct: offsetPct ?? this.offsetPct,
    rotationDeg: rotationDeg ?? this.rotationDeg,
    scale: scale ?? this.scale,
    pagePercentage: pagePercentage ?? this.pagePercentage,
    tiltX: tiltX ?? this.tiltX,
    tiltY: tiltY ?? this.tiltY,
  );
}

/// How a device turned out of the page reads as a solid object.
///
/// A tilt on its own turns a *picture* of a phone: a card with the handset
/// printed on it, which is why past about 30 degrees it stopped looking like
/// hardware. With a depth the body has sides — a metal band with its keys on
/// it, lit from one direction — and the device can be turned as far as a real
/// one would be held.
///
/// Nothing here moves the device; [Transform2D] still owns where it points.
/// These are the material: how deep it is, where the light comes from, and how
/// much of the studio the glass reflects.
class DepthSpec {
  const DepthSpec({this.thickness = 1, this.light = -40, this.glare = 0});

  /// The body's depth against the real device's: 0 is the flat card every
  /// tilted device was before this existed, 1 is life size, 2 is twice it.
  ///
  /// A multiplier rather than a measurement because a document is not told how
  /// thick its handset is — a phone and a tablet share this number and are
  /// drawn at their own proportions of it.
  final double thickness;

  /// Where the key light stands, in degrees round the front of the device:
  /// 0 is overhead, -90 full left, 90 full right.
  ///
  /// Up and to the left by default, because that is the side every frame's
  /// artwork already lights its rail from — a body lit from the other side
  /// would disagree with its own front.
  final double light;

  /// How strongly the glass reflects the studio, 0 (not at all) to 1.
  ///
  /// Off by default: it is painted over the user's screenshot, and a
  /// reflection nobody asked for is a smudge on the thing being sold.
  final double glare;

  /// Whether the device has no depth to draw.
  bool get isFlat => thickness <= 0;

  DepthSpec copyWith({double? thickness, double? light, double? glare}) =>
      DepthSpec(
        thickness: thickness ?? this.thickness,
        light: light ?? this.light,
        glare: glare ?? this.glare,
      );

  // A value type, so the codec can leave the default out of the file and a
  // painter can tell whether anything it draws from actually changed.
  @override
  bool operator ==(Object other) =>
      other is DepthSpec &&
      other.thickness == thickness &&
      other.light == light &&
      other.glare == glare;

  @override
  int get hashCode => Object.hash(thickness, light, glare);
}

class ShadowSpec {
  const ShadowSpec({
    this.opacity = 0.25,
    this.color = const Color(0xFF000000),
    this.blur = 20,
    this.offsetPct = const Offset(0, 0.01),
  });

  final double opacity;
  final Color color;
  final double blur;
  final Offset offsetPct;
}

class ScreenshotSpec {
  const ScreenshotSpec({
    this.images = const [],
    this.index = 0,
    this.cornerRadiusPct = 0.0,
    this.strokeWidthPct = 0.0,
    this.strokeColor = const Color(0xFF000000),
    this.scale = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.edits = const {},
    this.fill,
    this.localeImages = const {},
  });

  /// A frame holding exactly one screenshot, which is most of them.
  factory ScreenshotSpec.of(
    String? path, {
    double cornerRadiusPct = 0.0,
    double strokeWidthPct = 0.0,
    Color strokeColor = const Color(0xFF000000),
    double scale = 1.0,
    double offsetX = 0.0,
    double offsetY = 0.0,
    Background? fill,
  }) => ScreenshotSpec(
    images: path == null || path.isEmpty ? const [] : [path],
    cornerRadiusPct: cornerRadiusPct,
    strokeWidthPct: strokeWidthPct,
    strokeColor: strokeColor,
    scale: scale,
    offsetX: offsetX,
    offsetY: offsetY,
    fill: fill,
  );

  /// Every screenshot this frame carries, in the order they were added.
  ///
  /// A frame used to hold one. It holds a set now because a store listing is a
  /// set — the same device, the same framing, five different captures — and
  /// swapping between them by re-picking from the library each time meant
  /// losing the crop, the corner radius and the offset that had been dialled in
  /// around whichever one was showing. Those settings belong to the *frame*,
  /// not to the picture inside it, which is exactly why they sit out here.
  final List<String> images;

  /// The screenshot to show instead in another language, by language code.
  ///
  /// A listing localised for Germany shows the app in German: the frame, its
  /// crop and its corners stay the frame's, and only the picture inside it is
  /// swapped. A language with no entry here shows [images] like any other.
  final Map<String, String> localeImages;

  /// Which of [images] is composited.
  ///
  /// Clamped rather than trusted on read: a document can lose an image to a
  /// failed library repair, and an index pointing past the end of a shortened
  /// list must degrade to "show the last one" rather than throw inside a
  /// paint.
  final int index;

  /// The screenshot actually drawn, or null when the frame has none.
  ///
  /// Every renderer and exporter reads this, so a frame carrying five images
  /// composites exactly as a frame carrying one always did.
  String? get imagePath =>
      images.isEmpty ? null : images[index.clamp(0, images.length - 1)];

  /// Where [imagePath] sits in [images], clamped into range.
  int get activeIndex => images.isEmpty ? 0 : index.clamp(0, images.length - 1);

  /// True when there is more than one to switch between.
  bool get hasAlternates => images.length > 1;

  /// The retoucher's recipe for each edited image, keyed by that image's path.
  ///
  /// Deliberately opaque here. The document stores it and never asks what is in
  /// it, so the retoucher can grow a new kind of edit without the document
  /// model — or its codec, or every test that builds one — learning about it.
  /// The typed form lives with the editor, in `ScreenshotEdit`.
  ///
  /// Keyed by path rather than held as a single value because a frame can carry
  /// a set of screenshots and each one is edited on its own.
  ///
  /// Its presence is what makes an edit reopenable: the flattened PNG stays the
  /// thing the scene draws and the export ships, and this is the recipe kept
  /// beside it so Retouch can hand back the objects rather than the pixels they
  /// became.
  final Map<String, Map<String, dynamic>> edits;

  /// What the display shows underneath the screenshot.
  ///
  /// The whole [Background] type rather than a bare colour, so a display can
  /// wear the same solid, gradient, pattern or photo the canvas behind it can —
  /// and so it costs no new painting code, no new codec and no new picker: the
  /// scene already knows how to draw every one of them.
  ///
  /// Null is the historical behaviour and still the default: an empty frame
  /// shows the neutral "drop a screenshot here" plate. A template sets one so
  /// the set reads as a finished design before a single capture has been
  /// imported — which is the whole point of choosing a look first and shooting
  /// the app second.
  ///
  /// It sits *under* the picture rather than replacing it, so it survives a
  /// screenshot being added and shows through a capture with transparency
  /// instead of letting the bezel's black show through.
  final Background? fill;

  final double cornerRadiusPct;
  final double strokeWidthPct;
  final Color strokeColor;
  final double scale;
  final double offsetX;
  final double offsetY;

  /// [clearImages] is how a frame's screenshots are removed.
  ///
  /// Passing `imagePath: null` cannot mean "take it away" — null is already how
  /// every other field says "leave this alone" — which is why the flag exists
  /// and why `ProjectStore.addScreen` quietly kept the previous screen's
  /// screenshot for as long as it asked for `imagePath: null`. Same pattern as
  /// [FramePlacement.clearShadow].
  ///
  /// [imagePath] replaces the *active* image and leaves the rest of the set
  /// alone, which is what every existing caller means by it: retouching a
  /// screenshot, or choosing a different one for the slot on screen.
  ScreenshotSpec copyWith({
    String? imagePath,
    List<String>? images,
    int? index,
    bool clearImages = false,
    double? cornerRadiusPct,
    double? strokeWidthPct,
    Color? strokeColor,
    double? scale,
    double? offsetX,
    double? offsetY,
    Map<String, Map<String, dynamic>>? edits,
    Background? fill,
    bool clearFill = false,
    Map<String, String>? localeImages,
  }) {
    var nextImages = clearImages ? const <String>[] : (images ?? this.images);
    final nextLocaleImages = localeImages ?? this.localeImages;
    var nextIndex = clearImages ? 0 : (index ?? this.index);

    if (!clearImages && imagePath != null) {
      if (nextImages.isEmpty) {
        nextImages = [imagePath];
        nextIndex = 0;
      } else {
        final slot = nextIndex.clamp(0, nextImages.length - 1);
        nextImages = [...nextImages]..[slot] = imagePath;
        nextIndex = slot;
      }
    }

    return ScreenshotSpec(
      images: nextImages,
      index: nextIndex,
      // Pruned to the images that still exist, so a recipe cannot outlive the
      // picture it describes and quietly reattach to a later one at the same
      // path.
      edits: {
        for (final entry in (edits ?? this.edits).entries)
          if (nextImages.contains(entry.key) ||
              nextLocaleImages.containsValue(entry.key))
            entry.key: entry.value,
      },
      localeImages: nextLocaleImages,
      cornerRadiusPct: cornerRadiusPct ?? this.cornerRadiusPct,
      strokeWidthPct: strokeWidthPct ?? this.strokeWidthPct,
      strokeColor: strokeColor ?? this.strokeColor,
      scale: scale ?? this.scale,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      // Turned off with the flag, for the reason every other nullable field
      // here has one: `fill: null` is how a caller says "leave it alone".
      fill: clearFill ? null : (fill ?? this.fill),
    );
  }

  /// Adds [paths] to the set, skipping any already in it, and shows the first
  /// genuinely new one.
  ///
  /// Duplicates are dropped rather than appended because the library hands back
  /// the same path for the same file, and a set with the same capture twice is
  /// a set the user has to clean up by hand.
  ScreenshotSpec withImagesAdded(Iterable<String> paths) {
    final next = [...images];
    var firstNew = -1;
    for (final path in paths) {
      if (path.isEmpty || next.contains(path)) continue;
      if (firstNew < 0) firstNew = next.length;
      next.add(path);
    }
    if (next.length == images.length) return this;
    return copyWith(images: next, index: firstNew < 0 ? activeIndex : firstNew);
  }

  /// Every image in the set with [repoint] applied, keeping the active slot.
  ///
  /// The one way to rewrite these paths. A backup restore and a target copy
  /// both have to move artwork to its new home, and both used to reach for
  /// `copyWith(imagePath:)` — which now touches only the image on screen, so a
  /// frame's alternates would have survived the copy still pointing at files
  /// that no longer exist.
  ScreenshotSpec mapImages(String Function(String path) repoint) =>
      images.isEmpty && localeImages.isEmpty
      ? this
      : copyWith(
          images: [for (final path in images) repoint(path)],
          localeImages: {
            for (final e in localeImages.entries) e.key: repoint(e.value),
          },
        );

  /// Drops the image at [at], keeping the view on a neighbour.
  ScreenshotSpec withImageRemoved(int at) {
    if (at < 0 || at >= images.length) return this;
    final next = [...images]..removeAt(at);
    if (next.isEmpty) return copyWith(clearImages: true);
    // Stay where we are if something still follows; otherwise step back, so
    // removing the last one does not leave the index off the end.
    return copyWith(images: next, index: activeIndex.clamp(0, next.length - 1));
  }
}

/// Which end of the device a punch hole or a side button sits at.
enum FrameSide { left, center, right }

/// How a rounded corner turns.
///
/// Persisted by name, so these must not be renamed.
enum CornerStyle {
  /// A circular arc — an ordinary rounded rectangle.
  round,

  /// A continuous, superelliptical corner: the curvature eases in rather than
  /// starting abruptly at the tangent. This is how the traced Edge 50 Ultra
  /// and Galaxy Note 10+ frames draw their bodies, and why their corners read
  /// softer than a same-radius rounded rectangle.
  smooth,
}

/// The border shape [style] describes at [radius].
///
/// Flutter's continuous corner is visibly shallower than a circular one of the
/// same radius, so the smooth case is fed roughly double to land on a similar
/// silhouette. It is an approximation of the SVGs' hand-fitted cubics, not a
/// reproduction of them.
ShapeBorder cornerShape(
  CornerStyle style,
  double radius, {
  BorderSide side = BorderSide.none,
}) => style == CornerStyle.smooth
    ? ContinuousRectangleBorder(
        borderRadius: BorderRadius.circular(radius * 2),
        side: side,
      )
    : RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: side,
      );

/// [cornerShape] with a radius of its own at each corner — a book-style
/// foldable's body, square on the spine and round on the free edge.
ShapeBorder cornerShapeWith(
  CornerStyle style,
  BorderRadius radii, {
  BorderSide side = BorderSide.none,
}) => style == CornerStyle.smooth
    ? ContinuousRectangleBorder(borderRadius: radii * 2, side: side)
    : RoundedRectangleBorder(borderRadius: radii, side: side);

/// The fold a book-style foldable closes on, seen from the front of its cover.
///
/// A folded phone is not a candy bar with a hinge painted on. Its spine side is
/// near-square where the free side is round — the two halves meet along a
/// straight edge — and the hinge cover stands as its own strip down that edge,
/// in a matte finish against the polished frame. Those two cues, far more than
/// the screen's proportions, are what read as "a foldable, shut". Off for every
/// ordinary phone, which is every design written before this existed.
class HingeSpec {
  const HingeSpec({
    this.enabled = false,
    this.side = FrameSide.left,
    this.width = 0.022,
    this.cornerRadius = 0.01,
    this.inset = 0.028,
  });

  final bool enabled;

  /// Which long edge the device folds on. [FrameSide.center] is meaningless
  /// here and is treated as [FrameSide.left].
  final FrameSide side;

  /// The hinge cover's width, as a fraction of frame width. It is added to
  /// that side's bezel: the screen sits inside the cover half, not under the
  /// hinge.
  final double width;

  /// The outer corner radius on the hinge side, as a fraction of frame width.
  final double cornerRadius;

  /// How far short of the top and bottom the cover stops, as a fraction of
  /// frame width. It ends in rounded caps rather than running into the corners.
  final double inset;

  bool get onLeft => side != FrameSide.right;

  HingeSpec copyWith({
    bool? enabled,
    FrameSide? side,
    double? width,
    double? cornerRadius,
    double? inset,
  }) => HingeSpec(
    enabled: enabled ?? this.enabled,
    side: side ?? this.side,
    width: width ?? this.width,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    inset: inset ?? this.inset,
  );
}

/// The camera cut-out on a built frame.
///
/// A punch and a pill are the same rounded rectangle at different proportions,
/// so there is one spec rather than a shape enum: square it off for a punch,
/// stretch [width] for a pill, drop [cornerRadius] to zero for a slot.
class PunchHoleSpec {
  const PunchHoleSpec({
    this.enabled = false,
    this.align = FrameSide.center,
    this.width = 0.055,
    this.height = 0.055,
    this.cornerRadius = 0.5,
    this.top = 0.022,
    this.inset = 0.06,
    this.color = const Color(0xFF050505),
    this.borderColor = const Color(0xFF2A2A2A),
    this.borderWidth = 0.0,
  });

  final bool enabled;

  /// Which side of the screen the hole hugs; [FrameSide.center] ignores
  /// [inset].
  final FrameSide align;

  /// Fractions of the **frame width**, so the hole keeps its proportions when
  /// the frame is resized.
  final double width;
  final double height;

  /// Corner rounding as a fraction of the hole's own shortest side. 0.5 is a
  /// full pill/circle; 0 is a hard rectangle.
  final double cornerRadius;

  /// Distance from the top of the screen, as a fraction of frame width.
  final double top;

  /// Distance from the near edge when [align] is left or right, as a fraction
  /// of frame width.
  final double inset;

  final Color color;
  final Color borderColor;

  /// Fraction of frame width. Zero draws no rim.
  final double borderWidth;

  PunchHoleSpec copyWith({
    bool? enabled,
    FrameSide? align,
    double? width,
    double? height,
    double? cornerRadius,
    double? top,
    double? inset,
    Color? color,
    Color? borderColor,
    double? borderWidth,
  }) => PunchHoleSpec(
    enabled: enabled ?? this.enabled,
    align: align ?? this.align,
    width: width ?? this.width,
    height: height ?? this.height,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    top: top ?? this.top,
    inset: inset ?? this.inset,
    color: color ?? this.color,
    borderColor: borderColor ?? this.borderColor,
    borderWidth: borderWidth ?? this.borderWidth,
  );
}

/// One group of side buttons — the power key, or the volume rocker.
class SideButtonSpec {
  const SideButtonSpec({
    this.enabled = false,
    this.side = FrameSide.right,
    this.top = 0.22,
    this.length = 0.06,
    // Thicker than a real handset's key, on purpose: at the size a frame is
    // previewed the physically accurate 0.008 is a single pixel, so switching
    // the group on would look like it had done nothing.
    this.thickness = 0.014,
    this.gap = 0.02,
    this.count = 1,
    this.onTop = false,
  });

  final bool enabled;

  /// Which edge the group rides. [FrameSide.center] is meaningless here and is
  /// treated as [FrameSide.right]. Ignored when [onTop].
  final FrameSide side;

  /// Whether the group rides the **top** edge instead of a side — the iPhone
  /// Duo's volume keys, which sit on the top of the cover beside the hinge.
  ///
  /// [top], [length] and [gap] then run along the top edge and are fractions
  /// of frame **width**, measured from the left.
  final bool onTop;

  /// Where the group starts, as a fraction of frame **height**.
  final double top;

  /// Each key's length as a fraction of frame height, and how far it stands
  /// proud of the body as a fraction of frame width.
  final double length;
  final double thickness;

  /// Space between keys in a multi-key group, as a fraction of frame height.
  final double gap;

  /// How many keys the group has — 1 for a power key, 2 for a volume rocker.
  final int count;

  SideButtonSpec copyWith({
    bool? enabled,
    FrameSide? side,
    double? top,
    double? length,
    double? thickness,
    double? gap,
    int? count,
    bool? onTop,
  }) => SideButtonSpec(
    enabled: enabled ?? this.enabled,
    side: side ?? this.side,
    top: top ?? this.top,
    length: length ?? this.length,
    thickness: thickness ?? this.thickness,
    gap: gap ?? this.gap,
    count: count ?? this.count,
    onTop: onTop ?? this.onTop,
  );
}

/// A device frame built from numbers instead of picked from the catalog.
///
/// Every measurement is a fraction of the frame's own width (or height, where
/// noted), so a frame designed at editor scale exports identically. Set
/// [thickness] to zero for a frameless screenshot with nothing but a corner
/// radius.
class FrameDesign {
  const FrameDesign({
    this.thickness = 0.012,
    this.topThickness,
    this.bottomThickness,
    this.edgeCurve = 0,
    this.cornerRadius = 0.085,
    this.cornerStyle = CornerStyle.round,
    this.color = const Color(0xFF11142A),
    this.rimColor = const Color(0x29FFFFFF),
    this.rimWidth = 0.004,
    this.screenColor = const Color(0xFF000000),
    this.punchHole = const PunchHoleSpec(),
    this.power = const SideButtonSpec(),
    this.volume = const SideButtonSpec(
      side: FrameSide.left,
      top: 0.20,
      length: 0.04,
      count: 2,
    ),
    this.hinge = const HingeSpec(),
    this.aspect = 0.4743,
    this.flat = false,
  });

  /// Bezel thickness down the **left and right** edges, as a fraction of frame
  /// width. Zero is frameless.
  ///
  /// Also the fallback for the other two edges, which is why it is still called
  /// `thickness`: a design that only ever set this one value — every design
  /// written before the top and bottom could differ — keeps an even bezel all
  /// round, exactly as it did.
  final double thickness;

  /// The forehead, when it should not match the sides. Null matches them.
  final double? topThickness;

  /// The chin, when it should not match the sides. Null matches them.
  ///
  /// Phones wear a thinner chin than their sides more often than not, and a
  /// frame built for store art usually wants it thinner still.
  final double? bottomThickness;

  /// The forehead actually drawn.
  double get top => topThickness ?? thickness;

  /// The chin actually drawn.
  double get bottom => bottomThickness ?? thickness;

  /// How hard the display appears to curve away at its left and right edges,
  /// 0 (flat) to 1.
  ///
  /// A waterfall screen has no extra geometry — what reads as curvature is a
  /// bright specular band down the near edge and a shadow down the far one.
  /// The Edge 50 Ultra and Galaxy Note 10+ frames get theirs from a single
  /// horizontal gradient across the glass, and so does this.
  final double edgeCurve;

  /// Outer corner radius as a fraction of frame width.
  final double cornerRadius;

  /// Whether those corners turn on a circular arc or ease continuously.
  final CornerStyle cornerStyle;

  /// The bezel body.
  final Color color;

  /// The hairline just inside the outer edge that reads as glass rather than
  /// as a flat hole. [rimWidth] is a fraction of frame width; zero omits it.
  final Color rimColor;
  final double rimWidth;

  /// Shows through wherever the screenshot does not cover the screen.
  final Color screenColor;

  final PunchHoleSpec punchHole;
  final SideButtonSpec power;
  final SideButtonSpec volume;

  /// The fold, for a book-style foldable shown shut. See [HingeSpec].
  final HingeSpec hinge;

  /// The bezel actually drawn down the left edge — the sides, plus the hinge
  /// cover when the device folds on that edge.
  double get left =>
      thickness + (hinge.enabled && hinge.onLeft ? hinge.width : 0);

  /// The bezel actually drawn down the right edge.
  double get right =>
      thickness + (hinge.enabled && !hinge.onLeft ? hinge.width : 0);

  /// The body's outer corner radii for a frame [frameWidth] wide: [cornerRadius]
  /// all round, except on a hinge's side, which is near-square.
  BorderRadius outerRadii(double frameWidth) {
    final round = Radius.circular(frameWidth * cornerRadius.clamp(0.0, 0.5));
    if (!hinge.enabled) return BorderRadius.all(round);
    final spine = Radius.circular(
      frameWidth * hinge.cornerRadius.clamp(0.0, 0.5),
    );
    return hinge.onLeft
        ? BorderRadius.only(
            topLeft: spine,
            bottomLeft: spine,
            topRight: round,
            bottomRight: round,
          )
        : BorderRadius.only(
            topLeft: round,
            bottomLeft: round,
            topRight: spine,
            bottomRight: spine,
          );
  }

  /// Width / height of the whole frame. Drives how tall the device draws for a
  /// given page percentage.
  final double aspect;

  /// Whether the body is drawn as one flat colour instead of as hardware.
  ///
  /// A built frame normally reads as a phone: a lit metal rail, a black
  /// display border inside it, an outline against the page. Store art often
  /// wants none of that — a plain white rim round the screen, the way Gesture
  /// Volume's listing frames its shots — and the rail and border drawn over
  /// such a rim turned it into a different, heavier mockup. Flat paints
  /// [color] edge to edge between the outer corners and the screen's.
  final bool flat;

  FrameDesign copyWith({
    double? thickness,
    double? topThickness,
    bool clearTopThickness = false,
    double? bottomThickness,
    bool clearBottomThickness = false,
    double? edgeCurve,
    double? cornerRadius,
    CornerStyle? cornerStyle,
    Color? color,
    Color? rimColor,
    double? rimWidth,
    Color? screenColor,
    PunchHoleSpec? punchHole,
    SideButtonSpec? power,
    SideButtonSpec? volume,
    HingeSpec? hinge,
    double? aspect,
    bool? flat,
  }) => FrameDesign(
    thickness: thickness ?? this.thickness,
    topThickness: clearTopThickness
        ? null
        : (topThickness ?? this.topThickness),
    bottomThickness: clearBottomThickness
        ? null
        : (bottomThickness ?? this.bottomThickness),
    edgeCurve: edgeCurve ?? this.edgeCurve,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    cornerStyle: cornerStyle ?? this.cornerStyle,
    color: color ?? this.color,
    rimColor: rimColor ?? this.rimColor,
    rimWidth: rimWidth ?? this.rimWidth,
    screenColor: screenColor ?? this.screenColor,
    punchHole: punchHole ?? this.punchHole,
    power: power ?? this.power,
    volume: volume ?? this.volume,
    hinge: hinge ?? this.hinge,
    aspect: aspect ?? this.aspect,
    flat: flat ?? this.flat,
  );
}

class FramePlacement {
  const FramePlacement({
    required this.deviceId,
    required this.variantId,
    this.transform = const Transform2D(),
    this.screenshot = const ScreenshotSpec(),
    this.opacity = 1.0,
    this.frameHidden = false,
    this.hidden = false,
    this.cutoutHidden = false,
    this.shadow = const ShadowSpec(),
    this.design,
    this.z = kStackFrames,
    this.depth = const DepthSpec(),
  });

  final String deviceId;
  final String variantId;
  final Transform2D transform;
  final ScreenshotSpec screenshot;
  final double opacity;

  /// Drops the bezel and draws the screenshot on its own — a frameless
  /// mockup, which still has a device layer on the screen.
  ///
  /// Deliberately not the same thing as [hidden]: this one is a *style*, and
  /// the screenshot it reveals is usually the point of choosing it.
  final bool frameHidden;

  /// Takes the whole device layer — bezel and screenshot together — off the
  /// screen and out of the export.
  ///
  /// The layers list's eye, and the only way to compose a screen that is
  /// backdrop, shapes and type with no device on it at all. Kept on the
  /// placement rather than dropped from `frames`, so the device, its
  /// screenshot and everything else about it survive being switched back on.
  final bool hidden;

  /// Takes the camera cut-out off the front of the device.
  ///
  /// Only artwork frames need this. A built frame already owns its camera
  /// outright — [FrameDesign.punchHole] says whether it has one at all — but a
  /// traced device wears its punch hole or Dynamic Island *in the pixels*, so
  /// there is nothing to switch off. What happens instead is that the hole is
  /// covered with the screenshot that was already showing through the rest of
  /// the aperture, using the island's measured bounds — see
  /// `FrameDevice.cutoutRect` and `SceneView`.
  ///
  /// Kept on the placement rather than on [design] so the setting survives
  /// building a frame and going back to the artwork, and so it means the same
  /// thing on a device the user has never opened the builder on.
  final bool cutoutHidden;

  final ShadowSpec? shadow;

  /// Set when the user is building their own frame rather than using the
  /// catalog device's artwork. Null means "draw the picked device".
  final FrameDesign? design;

  /// Where this device sits in the screen's stack; see [kStackBehindFrames].
  ///
  /// A device is a component like any other now, so it competes for a position
  /// with the shapes and the captions rather than occupying a reserved slot
  /// between them. Ties are broken by position in [ScreenDoc.frames], which is
  /// what makes a screen nobody has rearranged paint its devices in the order
  /// they were added.
  final int z;

  /// The body's depth and lighting once it is turned out of the page.
  ///
  /// Only drawn while [Transform2D.isTilted]: head-on, a phone's sides are
  /// edge-on to the viewer, so a device nobody has turned looks exactly as it
  /// always did. Life size by default, which is what makes every tilted device
  /// in an existing project solid without a migration.
  final DepthSpec depth;

  /// [clearShadow] is how the shadow is turned **off**.
  ///
  /// Passing `shadow: null` cannot mean "remove it" — null is already how every
  /// other field says "leave this alone", so a null shadow argument is
  /// indistinguishable from not passing one at all. The same flag pattern as
  /// [ScreenDoc.copyWith]'s `clearSubCaption`.
  FramePlacement copyWith({
    String? deviceId,
    String? variantId,
    Transform2D? transform,
    ScreenshotSpec? screenshot,
    double? opacity,
    bool? frameHidden,
    bool? hidden,
    bool? cutoutHidden,
    ShadowSpec? shadow,
    bool clearShadow = false,
    FrameDesign? design,
    bool clearDesign = false,
    int? z,
    DepthSpec? depth,
  }) => FramePlacement(
    deviceId: deviceId ?? this.deviceId,
    variantId: variantId ?? this.variantId,
    transform: transform ?? this.transform,
    screenshot: screenshot ?? this.screenshot,
    opacity: opacity ?? this.opacity,
    frameHidden: frameHidden ?? this.frameHidden,
    hidden: hidden ?? this.hidden,
    cutoutHidden: cutoutHidden ?? this.cutoutHidden,
    shadow: clearShadow ? null : (shadow ?? this.shadow),
    design: clearDesign ? null : (design ?? this.design),
    z: z ?? this.z,
    depth: depth ?? this.depth,
  );
}

sealed class Background {
  const Background();
}

class SolidBackground extends Background {
  const SolidBackground(this.color);
  final Color color;
}

class GradientBackground extends Background {
  const GradientBackground({
    required this.colorOne,
    required this.colorTwo,
    this.begin = const Alignment(0, -1),
    this.end = const Alignment(0, 1),
    this.midColors = const [],
    this.radial = false,
  });

  final Color colorOne;
  final Color colorTwo;
  final Alignment begin;
  final Alignment end;

  /// Colours between [colorOne] and [colorTwo], spaced evenly along the ramp.
  ///
  /// Empty for the two-colour gradient every background was before these
  /// existed, which is still the common case — so the two ends stay fields of
  /// their own rather than becoming the first and last of one list.
  final List<Color> midColors;

  /// Whether the ramp runs out from the centre — [colorOne] in the middle,
  /// [colorTwo] at the corners — rather than across the canvas from [begin] to
  /// [end].
  final bool radial;

  /// Every colour, first to last.
  List<Color> get colors => [colorOne, ...midColors, colorTwo];

  /// The gradient to paint, linear or radial.
  ///
  /// One place for it, so the canvas, the panel's preview and the preset tiles
  /// cannot disagree about what a background looks like.
  Gradient toGradient() => radial
      // Out to the far corner: a radius measured to the short edge leaves the
      // corners of a tall canvas in flat rim colour.
      ? RadialGradient(radius: 1.12, colors: colors)
      : LinearGradient(begin: begin, end: end, colors: colors);

  GradientBackground copyWith({
    Color? colorOne,
    Color? colorTwo,
    Alignment? begin,
    Alignment? end,
    List<Color>? midColors,
    bool? radial,
  }) => GradientBackground(
    colorOne: colorOne ?? this.colorOne,
    colorTwo: colorTwo ?? this.colorTwo,
    begin: begin ?? this.begin,
    end: end ?? this.end,
    midColors: midColors ?? this.midColors,
    radial: radial ?? this.radial,
  );
}

/// How an image backdrop maps onto the canvas before any pan or zoom.
enum ImageBackgroundFit {
  /// Fills the canvas, cropping the overflow. The default and the only one that
  /// guarantees no bare canvas.
  cover,

  /// Shows the whole picture, letterboxing what is left over.
  contain,

  /// Stretches to the canvas, ignoring the picture's own proportions.
  fill,
}

/// A photo backdrop, plus the handful of adjustments that make an arbitrary
/// picture work behind a device frame.
///
/// Every measurement here is a **fraction of the canvas**, never a pixel count.
/// The editor lays the scene out at a few hundred logical pixels and the
/// exporter lays the same scene out at `doc.canvas` — an absolute blur radius
/// or pan distance would mean two different pictures.
class ImageBackground extends Background {
  const ImageBackground(
    this.path, {
    this.fit = ImageBackgroundFit.cover,
    this.scale = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.blur = 0.0,
    this.overlayColor = const Color(0xFF000000),
    this.overlayOpacity = 0.0,
    this.slices = 1,
    this.slice = 0,
  });

  final String path;

  /// How many screens one picture is spread across, and which of them this
  /// is — a panorama, exactly as [PatternBackground.slices] is for a pattern.
  ///
  /// At the default of one the picture fills its own screen and [slice] means
  /// nothing. Above one the backdrop is laid out [slices] screens wide, every
  /// adjustment below measured against that wide canvas, and only slice
  /// [slice] of it is shown. That is what lets one generated panorama survive
  /// the set being made separate again, or "Apply to all": every screen keeps
  /// its own part of the one picture instead of the whole of it squeezed into
  /// one canvas.
  ///
  /// Two plain numbers rather than a cut-up file per screen, for the reason
  /// [panoramaAt] gives: a stored slice goes stale when the set is reordered,
  /// a position cannot. Written to disk only when above one, so every image
  /// backdrop saved before panoramas existed reads and writes exactly as it
  /// did.
  final int slices;
  final int slice;

  final ImageBackgroundFit fit;

  /// Zoom about the canvas centre. 1 is the untouched [fit].
  final double scale;

  /// Pan, as a fraction of canvas width / height.
  final double offsetX;
  final double offsetY;

  /// Gaussian sigma as a fraction of canvas **width**.
  ///
  /// The usual reason a photo works behind a mockup at all: blurred back, it
  /// stops competing with the screenshot for attention.
  final double blur;

  /// A flat wash over the picture — the standard way to buy contrast for a
  /// caption sitting on a busy photo.
  final Color overlayColor;

  /// Strength of [overlayColor], 0 (off) to 1.
  final double overlayOpacity;

  ImageBackground copyWith({
    String? path,
    ImageBackgroundFit? fit,
    double? scale,
    double? offsetX,
    double? offsetY,
    double? blur,
    Color? overlayColor,
    double? overlayOpacity,
    int? slices,
    int? slice,
  }) => ImageBackground(
    path ?? this.path,
    fit: fit ?? this.fit,
    scale: scale ?? this.scale,
    offsetX: offsetX ?? this.offsetX,
    offsetY: offsetY ?? this.offsetY,
    blur: blur ?? this.blur,
    overlayColor: overlayColor ?? this.overlayColor,
    overlayOpacity: overlayOpacity ?? this.overlayOpacity,
    slices: slices ?? this.slices,
    slice: slice ?? this.slice,
  );
}

/// The families of backdrop the app can draw from nothing but numbers.
///
/// Append-only: a style is persisted by `name`, so reordering is free but
/// renaming or removing one silently rewrites every project that used it.
enum PatternStyle {
  /// Overlapping soft radial fields — the "mesh gradient" look.
  mesh,

  /// A few large organic shapes with soft edges.
  blobs,

  /// Stacked sine bands over a vertical ramp.
  waves,

  /// A fan of tapered beams from an off-canvas origin.
  rays,

  /// A regular field of soft dots.
  dots,

  /// Fine graph-paper ruling.
  grid,

  /// Wide diagonal bands.
  stripes,

  /// Tall soft curtains of light — the northern-lights look.
  aurora,

  /// Out-of-focus discs with a brighter rim.
  bokeh,

  /// Concentric rings spreading from one point.
  rings,

  /// Nested contour lines, like a map's height curves.
  topography,

  /// A two-tone checkerboard.
  checkers,

  /// A staggered lattice of filled diamonds.
  diamonds,

  /// A triangle tessellation in alternating tones.
  triangles,

  /// An outlined honeycomb.
  hexagons,

  /// A staggered lattice of small plus signs.
  crosses,

  /// Right-angled traces and pads — the circuit-board look.
  circuit,

  /// Small rotated capsules scattered across the canvas.
  confetti,

  /// Outlined circles at mixed sizes.
  bubbles,

  /// Stacked chevron rows.
  zigzag,

  /// Overlapping arcs, like fish scales or roof tiles.
  scales,

  /// Two sets of diagonal hairlines crossing.
  crosshatch,

  /// A dot field whose dots shrink across the canvas.
  halftone,

  /// One soft pool of light with a vignette around it.
  spotlight,

  /// Alternating wedges radiating from one point.
  sunburst,

  /// Spiral arms winding out from one point.
  swirl,

  /// Layered ridge silhouettes over a sky ramp.
  terrain,

  /// Crossing translucent bands — a tartan.
  plaid,

  /// Nebula glow with a scatter of stars.
  starfield,

  /// Overlapping translucent shards.
  prism,

  /// A grid of three-faced isometric cubes.
  isometric,

  /// A saturated poster ramp under ghost rounded squares and a dot mist —
  /// the bold single-colour store-panel look.
  poster,

  /// A near-black stage lit by a cool ambient wash high up and a single
  /// colour bloom at centre — the dark store-panel look.
  stage,

  /// Diagonal light beams over a poster ramp, with a corner flare, ghost
  /// arrows, sparkles and a light swoosh across the foot.
  beams,

  // ---------------------------------------------------------------------------
  // Icon motif — a scattered field of chosen symbols.
  //
  // This began as twenty styles, one per glyph: `notes`, `hearts`, `wifi` and
  // so on. They were the same painter twenty times over, differing only in
  // which path got stamped, and the enum was the only way to choose — so a
  // listing that wanted hearts *and* stars could not have both, and a gallery
  // that showed all twenty spent a third of itself on one idea.
  //
  // Now the glyph is data. [PatternBackground.symbols] says which to stamp,
  // and count, opacity and centre are the user's to set. Documents written by
  // the older build are migrated on read: `hearts` becomes this style with
  // [PatternSymbol.heart] selected, so nothing loses its artwork.
  // ---------------------------------------------------------------------------

  /// A scattered field of one or more chosen symbols.
  symbols,

  // ---------------------------------------------------------------------------
  // Second wave of atmospherics — variants of the families that earned their
  // keep, kept deliberately more minimal than the originals.
  // ---------------------------------------------------------------------------

  /// Concentric soft halos around one origin — a glow with structure.
  aura,

  /// Cracks radiating from an impact point, with the facets between them
  /// catching the light.
  broken,

  /// A jittered triangular tessellation shaded along one axis — the low-poly
  /// wallpaper look.
  facets,

  /// Two or three big smooth crests hanging from the top edge.
  crestTop,

  /// The same crests rising from the foot.
  crestBottom,

  /// Crests crossing the middle of the canvas.
  crestFull,

  /// Layered ridge silhouettes, cut back to three clean layers.
  ridges,

  /// Soft rolling hills with rounded crests.
  dunes,

  /// Parallel wavy bands running across the canvas — a cut-away of strata.
  strata,

  /// Contours around two centres, like a weather map's high and low.
  isobars,
}

/// The glyphs [PatternStyle.symbols] can stamp.
///
/// Persisted by name, so these may be added to but never renamed or reordered.
/// The names double as the migration key for the twenty icon styles this
/// replaced — `hearts` the old style maps to [heart] the symbol.
enum PatternSymbol {
  note,
  waveform,
  heart,
  download,
  wifi,
  network,
  sparkle,
  chat,
  play,
  shield,
  cloud,
  pin,
  star,
  bolt,
  aperture,
  orbit,
  bell,
  bug,
  hash,
  at,
}

/// A backdrop generated on the device instead of downloaded.
///
/// Everything needed to reproduce the artwork is in these few numbers, which is
/// what makes it cheap: nothing is fetched, nothing is cached, nothing expires,
/// and the same spec repaints identically at a 120px thumbnail and a 2778px
/// export. [seed] drives every "random" placement through a seeded generator,
/// so shuffling gives a new composition and re-rendering never gives a
/// different one.
///
/// Colours here are the user's content, so they are plain literals and must
/// never be swapped for theme tokens.
class PatternBackground extends Background {
  const PatternBackground({
    required this.style,
    required this.colors,
    this.seed = 1,
    this.scale = 1,
    this.angle = 0,
    this.intensity = 1,
    this.slices = 1,
    this.slice = 0,
    this.symbols = const [PatternSymbol.heart],
    this.symbolCount = 26,
    this.symbolOpacity = 0.8,
    this.symbolCenter = Offset.zero,
  });

  final PatternStyle style;

  /// Two to four stops. The first is the base fill; the rest paint the motif.
  final List<Color> colors;

  /// Drives the pseudo-random placement. Same seed, same picture.
  final int seed;

  /// Motif size / density multiplier, 0.4 – 2.5.
  final double scale;

  /// Motif rotation in degrees, 0 – 360.
  final double angle;

  /// How strongly the motif reads against the base, 0 – 1.
  final double intensity;

  /// How many screens one composition is spread across, and which of them this
  /// is — the panorama.
  ///
  /// At the default of one, a pattern fills its own screen and [slice] means
  /// nothing. Above one the painter lays the composition out [slices] screens
  /// wide and shows only slice [slice] of it, so applying slices 0…7 to eight
  /// screens gives one artwork running behind the whole listing rather than
  /// eight unrelated backdrops.
  ///
  /// It is two plain numbers rather than a shared parent object on purpose: a
  /// screen owns its own backdrop, and a slice has to survive being copied,
  /// reordered or exported on its own.
  final int slices;
  final int slice;

  // --- [PatternStyle.symbols] only ------------------------------------------

  /// Which glyphs to stamp, cycled one per symbol the way [colors] is.
  ///
  /// Never empty in practice — the panel will not let the last one be turned
  /// off — but the painter falls back to a single heart rather than drawing
  /// nothing if a hand-edited file manages it.
  final List<PatternSymbol> symbols;

  /// Roughly how many symbols cover the canvas. Drives the lattice spacing,
  /// so it is a target rather than an exact count: the field is overscanned
  /// and rotated, and some of what it lays down falls outside the frame.
  final int symbolCount;

  /// How strongly the symbols read against the ground, 0 – 1. Separate from
  /// [intensity] because a symbol field wants its glyphs solid and its ground
  /// untouched, which one number cannot say.
  final double symbolOpacity;

  /// Where the field is centred, as a fraction of the canvas from the middle:
  /// `(-0.5, 0)` is half a canvas to the left. Lets the symbols be pushed off
  /// the device or out from behind a headline.
  final Offset symbolCenter;

  PatternBackground copyWith({
    PatternStyle? style,
    List<Color>? colors,
    int? seed,
    double? scale,
    double? angle,
    double? intensity,
    int? slices,
    int? slice,
    List<PatternSymbol>? symbols,
    int? symbolCount,
    double? symbolOpacity,
    Offset? symbolCenter,
  }) => PatternBackground(
    style: style ?? this.style,
    colors: colors ?? this.colors,
    seed: seed ?? this.seed,
    scale: scale ?? this.scale,
    angle: angle ?? this.angle,
    intensity: intensity ?? this.intensity,
    slices: slices ?? this.slices,
    slice: slice ?? this.slice,
    symbols: symbols ?? this.symbols,
    symbolCount: symbolCount ?? this.symbolCount,
    symbolOpacity: symbolOpacity ?? this.symbolOpacity,
    symbolCenter: symbolCenter ?? this.symbolCenter,
  );

  /// Colour at [index], falling back through the list so a painter can ask for
  /// a stop the user has not supplied.
  Color colorAt(int index) {
    if (colors.isEmpty) return const Color(0xFF6D7BFF);
    return colors[index % colors.length];
  }
}

/// Whether [background] is a panorama: one artwork laid out across several
/// screens, a pattern or a picture, of which each screen shows its own slice.
bool isPanorama(Background background) => switch (background) {
  PatternBackground(:final slices) => slices > 1,
  ImageBackground(:final slices) => slices > 1,
  SolidBackground() || GradientBackground() => false,
};

/// [background] as screen [index] of a set of [count] screens shows it.
///
/// Only a panorama changes: a pattern or a picture laid out across several
/// screens is laid out across exactly this set — [count] screens wide, with
/// slice [index] in view. Anything else, and a set of one, comes back
/// untouched.
///
/// Worked out from the screen's place rather than trusted from the slice each
/// screen stores. One background given to a whole set arrives on every screen
/// with the *same* slice — which is how a continuous set showed one eighth of
/// its panorama on every screen — and a set is reordered, grown and cut
/// besides. A stored slice number goes stale; a position cannot.
Background panoramaAt(
  Background background, {
  required int index,
  required int count,
}) {
  if (!isPanorama(background) || count < 2) return background;
  final slice = index.clamp(0, count - 1);
  return switch (background) {
    final PatternBackground pattern => pattern.copyWith(
      slices: count,
      slice: slice,
    ),
    final ImageBackground image => image.copyWith(slices: count, slice: slice),
    _ => background,
  };
}

/// One line of a caption, with whatever it wants to override.
///
/// A store headline is rarely one uniform block: "UNIQUE" sits white and large
/// over "MAZE SHAPES" in yellow, and both belong to the same caption. Each line
/// is its own string with its own optional styling, which is also what makes
/// editing one line leave the others alone — the previous run-based model
/// concatenated everything into a single string and re-split it on every
/// keystroke, which is what made typing and colouring fight each other.
///
/// Every override is nullable and null means "use the caption's". A line that
/// has chosen nothing is styled exactly like the block it belongs to.
/// One run of caption text that shares a single set of overrides.
///
/// A caption is a list of these rather than a list of lines. The rich text
/// editor styles whatever the user selected, and a selection is a character
/// range — it stops mid-word as readily as it covers three whole lines. So the
/// run is the unit: its [text] may hold no newline, one, or several, and what
/// the caption says is the runs' [text] concatenated in order.
///
/// Every override is nullable and null means "inherit from the [CaptionSpec]".
/// That is what keeps styling the caption as a whole working — raising
/// [CaptionSpec.size] still lifts every run that never asked for its own, and
/// recolouring the caption still recolours everything the user did not paint by
/// hand.
/// A caption's words in one other language.
///
/// Only what a translation can change: the words — as plain [text] and, for a
/// rich caption, its [runs] — and, when that language needs them, its own
/// [fontFamily] and [size]. A script the default face cannot set, or German
/// that runs a line longer than English, are why those two are here. The
/// caption's colour, position and effects stay the caption's, in every
/// language, which is what keeps a localised set the same design.
class CaptionTranslation {
  const CaptionTranslation({
    required this.text,
    this.runs = const [],
    this.fontFamily,
    this.size,
  });

  final String text;
  final List<CaptionRun> runs;

  /// This language's face, or null for the caption's own.
  final String? fontFamily;

  /// This language's size, or null for the caption's own.
  final double? size;
}

class CaptionRun {
  const CaptionRun(
    this.text, {
    this.color,
    this.sizeScale,
    this.bold,
    this.italic,
    this.underline,
    this.fontFamily,
  });

  final String text;

  final Color? color;

  /// Multiplier on [CaptionSpec.size], so a run stays in proportion when the
  /// caption is resized as a whole.
  final double? sizeScale;

  final bool? bold;
  final bool? italic;
  final bool? underline;
  final String? fontFamily;

  /// Whether [other] would paint identically — the test that lets two adjacent
  /// runs be merged back into one after an edit.
  ///
  /// Text is deliberately not part of it: this asks whether the *styling*
  /// matches, which is the only thing that decides whether a boundary between
  /// two runs still means anything.
  bool sameStyleAs(CaptionRun other) =>
      color == other.color &&
      sizeScale == other.sizeScale &&
      bold == other.bold &&
      italic == other.italic &&
      underline == other.underline &&
      fontFamily == other.fontFamily;

  /// This run's styling over [text] — the copy made when a range is split.
  CaptionRun withText(String text) => CaptionRun(
    text,
    color: color,
    sizeScale: sizeScale,
    bold: bold,
    italic: italic,
    underline: underline,
    fontFamily: fontFamily,
  );

  CaptionRun copyWith({
    String? text,
    Color? color,
    bool clearColor = false,
    double? sizeScale,
    bool clearSizeScale = false,
    bool? bold,
    bool clearBold = false,
    bool? italic,
    bool clearItalic = false,
    bool? underline,
    bool clearUnderline = false,
    String? fontFamily,
    bool clearFontFamily = false,
  }) => CaptionRun(
    text ?? this.text,
    color: clearColor ? null : (color ?? this.color),
    sizeScale: clearSizeScale ? null : (sizeScale ?? this.sizeScale),
    bold: clearBold ? null : (bold ?? this.bold),
    italic: clearItalic ? null : (italic ?? this.italic),
    underline: clearUnderline ? null : (underline ?? this.underline),
    fontFamily: clearFontFamily ? null : (fontFamily ?? this.fontFamily),
  );
}

class CaptionSpec {
  const CaptionSpec({
    this.enabled = true,
    this.text = '',
    this.fontFamily = 'Roboto',
    this.size = 50,
    this.lineHeight = 60,
    this.color = const Color(0xFF1A1A1A),
    this.align = const Align2D(0, 0),
    this.allUpCase = false,
    this.bold = true,
    this.weight,
    this.italic = false,
    this.underline = false,
    this.offsetPct = Offset.zero,
    this.backgroundColor,
    this.backgroundPaddingX = 12,
    this.backgroundPaddingY = 6,
    this.letterSpacing = 0,
    this.strokeWidth = 0,
    this.strokeColor = const Color(0xFF000000),
    this.shadowBlur = 0,
    this.shadowOffsetY = 0,
    this.shadowColor = const Color(0x4D000000),
    this.glowBlur = 0,
    this.glowColor = const Color(0xFFFFFFFF),
    this.backgroundRadius = 8,
    this.backgroundBorderColor,
    this.backgroundBorderWidth = 0,
    this.runs = const [],
    this.cornerStyle = CornerStyle.round,
    this.styleId,
    this.translations = const {},
    this.fitHeightPct,
  });

  /// The caption in other languages, by language code. The caption's own
  /// words are the project's default language. See [CaptionTranslation].
  final Map<String, CaptionTranslation> translations;

  /// This caption as it reads in [language]: its own words when there is no
  /// translation, the translation's words — and font and size, where set —
  /// otherwise.
  ///
  /// A translation typed as plain words keeps this caption's styling, line by
  /// line: a two-tone headline — the second line in the accent colour — used
  /// to come out of every other language in one colour.
  CaptionSpec inLanguage(String? language) {
    final t = language == null ? null : translations[language];
    if (t == null) return this;
    return copyWith(
      text: t.text,
      runs: t.runs.isNotEmpty || runs.isEmpty
          ? t.runs
          : runsByLine(runs, t.text),
      fontFamily: t.fontFamily,
      size: t.size,
    );
  }

  /// [text] styled after [source], a line at a time: its line n takes the
  /// style of [source]'s line n — the style of that line's first visible
  /// words — and any line past the last takes the last one's.
  static List<CaptionRun> runsByLine(List<CaptionRun> source, String text) {
    final styles = <CaptionRun?>[null];
    for (final run in source) {
      final parts = run.text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) styles.add(null);
        if (styles.last == null && parts[i].trim().isNotEmpty) {
          styles[styles.length - 1] = run;
        }
      }
    }
    // A blank line borrows the style above it, so its break is not left bare.
    for (var i = 1; i < styles.length; i++) {
      styles[i] ??= styles[i - 1];
    }

    final lines = text.split('\n');
    return [
      for (var i = 0; i < lines.length; i++)
        switch (styles[math.min(i, styles.length - 1)]) {
          null => CaptionRun(_line(lines, i)),
          final style => style.copyWith(text: _line(lines, i)),
        },
    ];
  }

  static String _line(List<String> lines, int i) =>
      i < lines.length - 1 ? '${lines[i]}\n' : lines[i];

  final bool enabled;
  final String text;
  final String fontFamily;
  final double size;
  final double lineHeight;
  final Color color;
  final Align2D align;
  final bool allUpCase;
  final bool bold;

  /// The cut [bold] type is set in — 800 or 900 for a face that has a heavier
  /// one than its bold — or null for the bold itself.
  ///
  /// Display headlines are routinely set heavier than 700, and a face's Bold
  /// standing in for its ExtraBold is a visibly thinner, narrower headline —
  /// a wordmark set in Inter at 800, or Roboto at 900. Unbold text ignores
  /// it.
  final int? weight;
  final bool italic;

  /// Underline under every glyph the caption paints. A run can opt out of it
  /// the same way it can opt out of [bold].
  final bool underline;
  final Offset offsetPct;
  final Color? backgroundColor;
  final double backgroundPaddingX;
  final double backgroundPaddingY;

  /// Tracking in the same "design px at a 1179-wide canvas" units as [size].
  /// Negative values tighten a heavy headline the way poster type is set.
  final double letterSpacing;

  /// Outline drawn *under* the fill (a second stroked text layer), same units
  /// as [size]. Zero means no outline layer at all.
  final double strokeWidth;
  final Color strokeColor;

  /// Soft drop shadow under the glyphs, same units as [size]. Zero blur and
  /// zero offset means no shadow entry.
  final double shadowBlur;
  final double shadowOffsetY;
  final Color shadowColor;

  /// Zero-offset halo behind the glyphs — the "neon" treatment. Zero means
  /// no glow entry.
  final double glowBlur;
  final Color glowColor;

  /// Chip corner radius in the same raw logical px as the padding fields.
  /// 8 reproduces the pre-field rendering; large values make a pill.
  final double backgroundRadius;

  /// Optional rim around the chip, raw logical px like the padding fields.
  final Color? backgroundBorderColor;
  final double backgroundBorderWidth;

  /// The caption's styled runs, in order.
  ///
  /// Empty is the plain case: [text] is painted as one block in the caption's
  /// own type. When it is not empty the runs *are* the caption — [text] mirrors
  /// what they say so anything reading a bare string still agrees, but every
  /// glyph is painted from the run it belongs to.
  ///
  /// A run boundary is wherever the styling changes, not where a line ends, so
  /// one run may carry several lines and one line may be made of several runs.
  /// See `caption_runs.dart` for the operations the rich text editor drives
  /// them with.
  final List<CaptionRun> runs;

  /// Whether this caption is styled run by run rather than as one block.
  bool get isRich => runs.isNotEmpty;

  /// Whether the plate behind the text turns on a circular arc or eases
  /// continuously, matching the frame's own corner styles.
  final CornerStyle cornerStyle;

  /// The saved text style this caption was last given, if any.
  ///
  /// A tag, not a source of truth: the caption already holds every value the
  /// style set, so it draws identically with the project's style library
  /// missing, moved to another project, or opened by an exporter that was
  /// handed a document and nothing else. What the tag buys is the ability to
  /// find this caption again when the style is edited — see
  /// `ProjectStore.updateTextStyle`.
  final String? styleId;

  /// The most of the page's height the words may take before they are set
  /// smaller, or null to set them at [size] however tall they run.
  ///
  /// A template's headline is sized to its own copy, and the room it leaves
  /// above the device is part of the design. Somebody's longer headline at
  /// that size wrapped onto a third line and ran into the phone, so a caption
  /// a template set carries the room it was given, and the renderer shrinks
  /// the type (leading and tracking with it) just far enough to stay inside.
  /// Never below 60%, past which a headline stops reading as one.
  ///
  /// Resizing the caption by hand clears it: a size somebody chose is not one
  /// to quietly take back.
  final double? fitHeightPct;

  /// The characters this caption paints, before [allUpCase] is applied.
  String get plainText => runs.isEmpty ? text : runs.map((r) => r.text).join();

  /// [plainText] with the case rule applied — what actually reaches the glyphs.
  String get renderedText => allUpCase ? plainText.toUpperCase() : plainText;

  CaptionSpec copyWith({
    String? styleId,

    /// Drops the style tag — for a caption edited away from the style it was
    /// given, where keeping the tag would let a later style edit overwrite the
    /// change.
    bool clearStyleId = false,
    bool? enabled,
    String? text,
    String? fontFamily,
    double? size,
    double? lineHeight,
    Color? color,
    Align2D? align,
    bool? allUpCase,
    bool? bold,
    int? weight,
    bool clearWeight = false,
    bool? italic,
    bool? underline,
    Offset? offsetPct,
    Color? backgroundColor,
    bool clearBackgroundColor = false,
    double? backgroundPaddingX,
    double? backgroundPaddingY,
    double? letterSpacing,
    double? strokeWidth,
    Color? strokeColor,
    double? shadowBlur,
    double? shadowOffsetY,
    Color? shadowColor,
    double? glowBlur,
    Color? glowColor,
    double? backgroundRadius,
    Color? backgroundBorderColor,
    bool clearBackgroundBorderColor = false,
    double? backgroundBorderWidth,
    List<CaptionRun>? runs,
    CornerStyle? cornerStyle,
    Map<String, CaptionTranslation>? translations,
    double? fitHeightPct,

    /// Drops [fitHeightPct], for a caption somebody has sized themselves.
    bool clearFitHeightPct = false,
  }) => CaptionSpec(
    enabled: enabled ?? this.enabled,
    text: text ?? this.text,
    fontFamily: fontFamily ?? this.fontFamily,
    size: size ?? this.size,
    lineHeight: lineHeight ?? this.lineHeight,
    color: color ?? this.color,
    align: align ?? this.align,
    allUpCase: allUpCase ?? this.allUpCase,
    bold: bold ?? this.bold,
    weight: clearWeight ? null : (weight ?? this.weight),
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    offsetPct: offsetPct ?? this.offsetPct,
    backgroundColor: clearBackgroundColor
        ? null
        : (backgroundColor ?? this.backgroundColor),
    backgroundPaddingX: backgroundPaddingX ?? this.backgroundPaddingX,
    backgroundPaddingY: backgroundPaddingY ?? this.backgroundPaddingY,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeColor: strokeColor ?? this.strokeColor,
    shadowBlur: shadowBlur ?? this.shadowBlur,
    shadowOffsetY: shadowOffsetY ?? this.shadowOffsetY,
    shadowColor: shadowColor ?? this.shadowColor,
    glowBlur: glowBlur ?? this.glowBlur,
    glowColor: glowColor ?? this.glowColor,
    backgroundRadius: backgroundRadius ?? this.backgroundRadius,
    backgroundBorderColor: clearBackgroundBorderColor
        ? null
        : (backgroundBorderColor ?? this.backgroundBorderColor),
    backgroundBorderWidth: backgroundBorderWidth ?? this.backgroundBorderWidth,
    runs: runs ?? this.runs,
    cornerStyle: cornerStyle ?? this.cornerStyle,
    styleId: clearStyleId ? null : (styleId ?? this.styleId),
    translations: translations ?? this.translations,
    fitHeightPct: clearFitHeightPct
        ? null
        : (fitHeightPct ?? this.fitHeightPct),
  );
}

/// What a screen starts life with.
///
/// A flat fill, not a gradient: a solid backdrop is what most store listings
/// actually ship, it keeps the device frame and the caption as the only things
/// competing for attention, and it is the one starting point a user can restyle
/// in a single tap. A gradient is a deliberate choice, so it is offered rather
/// than assumed.
///
/// The colour is the leading stop of the first gradient in the background
/// panel's gallery, not the near-white it used to be. A white canvas behind a
/// white-bezelled phone under black text is a screenshot that looks unstyled —
/// it reads as a page that has not been designed yet rather than as a starting
/// point, and the first thing every user did was change it. Opening on the
/// gallery's own first colour means a new screen already looks like the tool
/// made it, and the one tap to a full gradient is the neighbouring swatch.
///
/// Deliberately literal colours: this is the user's *content*, not chrome, and
/// must be identical whatever theme the app is in when the screen is created.
const Background kDefaultBackground = SolidBackground(Color(0xFF5B5FEF));

/// Caption ink that reads against [kDefaultBackground]. The two are defined
/// together because changing one without the other produces invisible text —
/// which is exactly what moving the canvas off near-white would have done had
/// this stayed near-black.
const Color kDefaultCaptionColor = Color(0xFFFFFFFF);

class ScreenDoc {
  const ScreenDoc({
    required this.id,
    this.canvas = const Size(1179, 2556),
    this.background = kDefaultBackground,
    this.frames = const [],
    this.shapes = const [],
    this.caption,
    this.subCaption,
    this.isCaptionAbove = true,
    this.captionsZ = kStackCaptions,
  });

  final String id;
  final Size canvas;
  final Background background;
  final List<FramePlacement> frames;

  /// Vector shapes drawn on this screen.
  ///
  /// Deliberately **not** in paint order. Where a shape sits in the stack is
  /// [ShapeSpec.z], and this list's order is only the tie-break between shapes
  /// that share one — so rearranging the layers list rewrites z values and
  /// leaves every index alone, which is what stops a drag from invalidating a
  /// selection, an undo entry or a component instance that points here.
  final List<ShapeSpec> shapes;

  final CaptionSpec? caption;
  final CaptionSpec? subCaption;
  final bool isCaptionAbove;

  /// Where the caption and subcaption sit in the stack; see [kStackCaptions].
  ///
  /// One position for both, because they are one layer: they are typeset as a
  /// block, the layers list shows them as one anchor, and there is nothing that
  /// could sit between a headline and its own second line.
  ///
  /// Kept on the screen rather than on [CaptionSpec] so the position survives
  /// the captions being empty. A screen with no headline yet still has a place
  /// where the headline will go, and shapes arranged around that place must not
  /// jump the moment one is typed.
  final int captionsZ;

  ScreenDoc copyWith({
    String? id,
    Size? canvas,
    Background? background,
    List<FramePlacement>? frames,
    List<ShapeSpec>? shapes,
    CaptionSpec? caption,
    bool clearCaption = false,
    CaptionSpec? subCaption,
    bool clearSubCaption = false,
    bool? isCaptionAbove,
    int? captionsZ,
  }) => ScreenDoc(
    id: id ?? this.id,
    canvas: canvas ?? this.canvas,
    background: background ?? this.background,
    frames: frames ?? this.frames,
    shapes: shapes ?? this.shapes,
    caption: clearCaption ? null : (caption ?? this.caption),
    subCaption: clearSubCaption ? null : (subCaption ?? this.subCaption),
    isCaptionAbove: isCaptionAbove ?? this.isCaptionAbove,
    captionsZ: captionsZ ?? this.captionsZ,
  );

  /// This screen with [placement] added on top of the devices already on it.
  ///
  /// Given the frontmost device's own z and appended, so the list tie-break
  /// puts it one place in front of that device — and *only* of that device.
  /// Taking the whole screen's maximum instead would drop a new phone on top of
  /// the headline, which is not what "add a device" means; matching the devices
  /// already there is what keeps a new one where a user who just added it is
  /// looking for it.
  ScreenDoc addFrame(FramePlacement placement) => copyWith(
    frames: [
      ...frames,
      if (frames.isEmpty)
        placement
      else
        placement.copyWith(
          z: frames.map((f) => f.z).reduce((a, b) => a > b ? a : b),
        ),
    ],
  );

  /// This screen without the device at [index].
  ///
  /// The last device is kept. A screen with no frame at all has no screenshot,
  /// no device panel and nothing for the frame tools to edit — and every way
  /// into that state is a slip rather than an intention. Hiding the device,
  /// which [FramePlacement.hidden] does, is what "a screen with no phone on it"
  /// actually means.
  ScreenDoc removeFrame(int index) {
    if (frames.length <= 1 || index < 0 || index >= frames.length) return this;
    return copyWith(frames: [...frames]..removeAt(index));
  }

  /// Rewrites the device at [index], or returns the document untouched if
  /// there is no such device.
  ///
  /// Guarded for the same reason `updateShape` below is, and it became the same
  /// reason only recently: the index used to be a hard-coded zero, and is now
  /// whatever the frame selection says. A selection outlives what it points at
  /// every time an undo puts back a document with fewer devices on it, and a
  /// range error thrown out of a panel rebuild is a crash rather than a
  /// no-op.
  ScreenDoc updateFrame(
    int index,
    FramePlacement Function(FramePlacement) update,
  ) {
    if (index < 0 || index >= frames.length) return this;
    final next = [...frames];
    next[index] = update(next[index]);
    return copyWith(frames: next);
  }

  /// The frontmost position anything on this screen occupies.
  ///
  /// What "on top of everything" resolves to, for the one caller that has to
  /// name a position rather than move an existing one: dropping a component.
  int get topZ => [
    for (final s in shapes) s.z,
    for (final f in frames) f.z,
    captionsZ,
  ].reduce(math.max);

  /// Rewrites the shape at [index], or returns the document untouched if there
  /// is no such shape.
  ///
  /// Guarded rather than throwing because the index comes from a selection, and
  /// a selection can outlive the shape it points at — deleting the last shape
  /// while its controls are on screen would otherwise crash the editor.
  ScreenDoc updateShape(int index, ShapeSpec Function(ShapeSpec) update) {
    if (index < 0 || index >= shapes.length) return this;
    final next = [...shapes];
    next[index] = update(next[index]);
    return copyWith(shapes: next);
  }
}
