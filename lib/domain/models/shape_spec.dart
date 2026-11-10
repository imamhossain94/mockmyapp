import 'dart:math' as math;
import 'package:flutter/painting.dart';

import 'stack_order.dart';

// Re-exported so a shape and the scale its [ShapeSpec.z] is measured on
// arrive from one import.
export 'stack_order.dart';

/// The families of shape the canvas can draw.
///
/// Persisted by name, so these may be added to but never renamed. The kind is
/// the only thing that decides which path is built; every other field on
/// [ShapeSpec] is shared, and a kind that has no use for one ignores it.
///
/// Grouped by how the path is produced rather than by how it looks:
///
/// * **Primitives** — a rectangle and an ellipse, the two shapes every mockup
///   actually needs. Square and circle are these two at equal width and height,
///   not separate kinds: they would carry identical geometry and would stop
///   being square the moment a corner handle moved.
/// * **Regular** — a polygon at [ShapeSpec.sides] and a star at
///   [ShapeSpec.sides] points. Triangle is the polygon at three, kept as its own
///   entry only because it is the one people look for by name.
/// * **Open** — a line and an arrow. These have no interior, so they are stroked
///   and never filled; see [ShapeSpec.isOpen].
/// * **Motifs** — fixed paths that would be tedious to build by hand.
/// * **Custom** — whatever the user drew, in [ShapeSpec.points].
/// * **Path** — whatever the user imported, in [ShapeSpec.pathData]. A real
///   outline with sharp corners, holes and a fill rule of its own, which is
///   exactly what [ShapeKind.custom] cannot express: a drawn path is a run of
///   sampled points smoothed through every vertex, so it has no corners, one
///   subpath and no way to say that the middle of an "O" is a hole.
enum ShapeKind {
  rectangle,
  ellipse,
  triangle,
  polygon,
  star,
  line,
  arrow,
  wave,
  heart,
  blob,
  bubble,
  cross,
  chevron,
  drop,
  shield,
  burst,
  custom,
  path;

  /// A shape with no interior: stroked along its path, never filled.
  ///
  /// A custom path is open or closed depending on how it was drawn, which the
  /// kind alone cannot say — [ShapeSpec.isOpen] is the question to ask.
  bool get alwaysOpen => this == line || this == arrow || this == wave;

  /// How the shape is listed in the picker and named in the layer strip.
  String get label => switch (this) {
    ShapeKind.rectangle => 'Rectangle',
    ShapeKind.ellipse => 'Ellipse',
    ShapeKind.triangle => 'Triangle',
    ShapeKind.polygon => 'Polygon',
    ShapeKind.star => 'Star',
    ShapeKind.line => 'Line',
    ShapeKind.arrow => 'Arrow',
    ShapeKind.wave => 'Wave',
    ShapeKind.heart => 'Heart',
    ShapeKind.blob => 'Blob',
    ShapeKind.bubble => 'Bubble',
    ShapeKind.cross => 'Cross',
    ShapeKind.chevron => 'Chevron',
    ShapeKind.drop => 'Drop',
    ShapeKind.shield => 'Shield',
    ShapeKind.burst => 'Burst',
    ShapeKind.custom => 'Custom',
    // An imported SVG, and every Lucide icon: vector outlines both.
    ShapeKind.path => 'Vector',
  };
}

/// How a stroke is laid down along its path.
///
/// Applies to every shape, not just the open ones: a dashed rectangle outline
/// and a dotted circle are the same idea as a dashed line, and making this a
/// property of the stroke rather than of the line kind is what gives all three
/// for the price of one.
///
/// Persisted by name, so these may be added to but never renamed.
enum StrokeStyle {
  solid,

  /// Even dashes, sized off the stroke width so a thick line gets long dashes.
  dashed,

  /// Round dots at a regular pitch. Drawn as near-zero-length dashes under a
  /// round cap, which is what makes each one a circle the width of the stroke.
  dotted;

  String get label => switch (this) {
    StrokeStyle.solid => 'Solid',
    StrokeStyle.dashed => 'Dashed',
    StrokeStyle.dotted => 'Dotted',
  };
}

/// A drop shadow under a shape.
///
/// Deliberately not `ShadowSpec` from `screen_doc.dart`: that one measures its
/// offset as a fraction of the *frame* it belongs to, and a shape has no frame.
/// Everything here is a fraction of the canvas, like the rest of [ShapeSpec].
class ShapeShadow {
  const ShapeShadow({
    this.color = const Color(0xFF000000),
    this.opacity = 0.28,
    this.blur = 0.03,
    this.offset = const Offset(0, 0.012),
  });

  final Color color;

  /// 0 – 1, applied on top of whatever alpha [color] already carries.
  final double opacity;

  /// Gaussian sigma as a fraction of canvas **width**, so preview and export
  /// are the same picture at two scales.
  final double blur;

  /// Displacement as a fraction of canvas width / height.
  final Offset offset;

  ShapeShadow copyWith({
    Color? color,
    double? opacity,
    double? blur,
    Offset? offset,
  }) => ShapeShadow(
    color: color ?? this.color,
    opacity: opacity ?? this.opacity,
    blur: blur ?? this.blur,
    offset: offset ?? this.offset,
  );
}

/// Words drawn on a shape.
///
/// Not [ShapeSpec.name]. That one is chrome — what the layers list calls the
/// row, and null there means "call it after its kind". This is *artwork*: it is
/// composited into the export, it is what the user typed to make a badge say
/// BUS, and no theme may ever substitute for it.
///
/// It exists because a page is not always a phone with a headline over it. A
/// store listing's opening screen is routinely a composed cover — an eyebrow, a
/// headline, a row of pills, a card with a legend on it — and a document that
/// can hold exactly two blocks of type (its caption and its subcaption) cannot
/// describe one. A shape can already be a pill or a card; giving it words is
/// what turns "a rounded rectangle" into "a badge".
///
/// A text layer with no shape around it is just a shape with a transparent
/// fill and no stroke, which is why there is no `ShapeKind.text`: a kind that
/// drew nothing would need an arm in every geometry switch and a tile in the
/// picker with no silhouette to show.
///
/// Every measurement is a fraction of canvas **width**, exactly like
/// [ShapeSpec.strokeWidth] and [ShapeShadow.blur] — *not* the "design px at a
/// 1179-wide canvas" that [CaptionSpec.size] is quoted in. That is what keeps
/// a preview tile and a full export the same picture at two scales.
///
/// The field names deliberately match `TextStyleDef`'s, so a saved text style
/// can be applied to a label later without a migration.
/// A label's words in one other language, with the face and size that
/// language needs where they differ. See `CaptionTranslation`.
class LabelTranslation {
  const LabelTranslation({required this.text, this.fontFamily, this.size});

  final String text;
  final String? fontFamily;
  final double? size;
}

class ShapeLabel {
  const ShapeLabel(
    this.text, {
    this.fontFamily = 'Roboto',
    this.size = 0.03,
    this.color = const Color(0xFFFFFFFF),
    this.bold = false,
    this.weight,
    this.italic = false,
    this.allUpCase = false,
    this.lineHeight = 1.2,
    this.letterSpacing = 0,
    this.align = TextAlign.center,
    this.padding = 0.008,
    this.translations = const {},
  });

  /// The words in other languages, by language code. See
  /// [LabelTranslation].
  final Map<String, LabelTranslation> translations;

  /// The label as it reads in [language].
  ShapeLabel inLanguage(String? language) {
    final t = language == null ? null : translations[language];
    if (t == null) return this;
    return copyWith(text: t.text, fontFamily: t.fontFamily, size: t.size);
  }

  final String text;
  final String fontFamily;

  /// Font size as a fraction of canvas width.
  final double size;
  final Color color;
  final bool bold;

  /// A cut between regular and bold, as a CSS weight from 100 to 900. Null
  /// draws [bold] or regular, as labels always have.
  ///
  /// A listing's small print is very often set at 500 or 600 — the feature
  /// pills on Gesture Volume's banner are Sora SemiBold — and neither regular
  /// nor bold is that face.
  final int? weight;
  final bool italic;
  final bool allUpCase;

  /// Leading as a multiple of [size], the way a text style states it — unlike
  /// [CaptionSpec.lineHeight], which is absolute.
  final double lineHeight;

  /// Tracking as a fraction of canvas width, like [size].
  final double letterSpacing;

  final TextAlign align;

  /// Breathing room inside the shape before the text wraps, as a fraction of
  /// canvas width. A pill whose text ran to its own rounded edge would read as
  /// broken.
  final double padding;

  /// Nothing to draw. Whitespace counts as nothing: a label of spaces would
  /// otherwise reserve a semantics node and a paragraph for no ink.
  bool get isEmpty => text.trim().isEmpty;

  ShapeLabel copyWith({
    String? text,
    String? fontFamily,
    double? size,
    Color? color,
    bool? bold,
    int? weight,

    /// Back to [bold] or regular. Null can't say it — it means "unchanged".
    bool clearWeight = false,
    bool? italic,
    bool? allUpCase,
    double? lineHeight,
    double? letterSpacing,
    TextAlign? align,
    double? padding,
    Map<String, LabelTranslation>? translations,
  }) => ShapeLabel(
    text ?? this.text,
    fontFamily: fontFamily ?? this.fontFamily,
    size: size ?? this.size,
    color: color ?? this.color,
    bold: bold ?? this.bold,
    weight: clearWeight ? null : weight ?? this.weight,
    italic: italic ?? this.italic,
    allUpCase: allUpCase ?? this.allUpCase,
    lineHeight: lineHeight ?? this.lineHeight,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    align: align ?? this.align,
    padding: padding ?? this.padding,
    translations: translations ?? this.translations,
  );
}

/// One vector shape on the canvas.
///
/// Every measurement is a **fraction of the canvas**, never a pixel count — the
/// same rule the rest of the document follows. The editor lays a scene out at a
/// few hundred logical pixels and the exporter lays the same scene out at
/// `doc.canvas`, so an absolute size or stroke width would mean two different
/// pictures.
///
/// Colours here are the user's content and must never be swapped for theme
/// tokens: an export made in dark mode has to be byte-identical to the same
/// export made in light mode.
class ShapeSpec {
  const ShapeSpec({
    required this.kind,
    this.center = Offset.zero,
    this.width = 0.28,
    this.height = 0.28,
    this.rotationDeg = 0,
    this.fill = const Color(0xFFFFFFFF),
    this.fillEnd,
    this.gradientAngle = 90,
    this.gradientRadial = false,
    this.strokeColor = const Color(0xFF11142A),
    this.strokeWidth = 0,
    this.strokeStyle = StrokeStyle.solid,
    this.strokeInBox = false,
    this.dashScale = 1,
    this.opacity = 1,
    this.cornerRadius = 0,
    this.sides = 6,
    this.innerRatio = 0.45,
    this.points = const [],
    this.closed = true,
    this.pathData = '',
    this.evenOdd = false,
    this.shadow,
    this.label,
    this.imagePath,
    this.z = kStackBehindFrames,
    this.name,
    this.hidden = false,
    this.locked = false,
    this.componentId,
    this.instanceId,
    this.slot = 0,
  });

  /// The component this shape is part of, if any.
  ///
  /// A tag, exactly like `CaptionSpec.styleId` and for the same reason: the
  /// shape holds every value it needs and draws identically with the project's
  /// component library missing, moved or unreachable. What the tag buys is the
  /// ability to find this shape again when the master changes.
  final String? componentId;

  /// Which *placement* of [componentId] this shape belongs to.
  ///
  /// Two instances of the same component on one screen are two runs of shapes
  /// carrying the same [componentId] and different ids here. Without it a
  /// master edit could not tell where one instance ended and the next began,
  /// and would collapse both onto the same spot.
  final String? instanceId;

  /// Position within the component, so a master edit knows which shape in the
  /// instance corresponds to which shape in the master.
  final int slot;

  /// True when this shape is part of a placed component.
  bool get isInstance => componentId != null && instanceId != null;

  /// A shape of [kind] at the size, fill and stroke that make it read as itself
  /// the moment it lands on the canvas.
  ///
  /// The per-kind cases are not decoration. A line dropped in with the closed
  /// shapes' defaults — no stroke, because they are filled — would be an
  /// invisible layer the user has to go and find a control for; a star at the
  /// polygon's six sides is a hexagram rather than the five-pointed star anyone
  /// asking for a star means.
  ///
  /// Everything added this way lands at [kStackOverEverything]. A new shape has
  /// to be visible where it was put, and the device frame covers the middle of
  /// the canvas — dropping one behind it looks exactly like the button having
  /// done nothing. Moving it down the stack is one drag in the layers list.
  factory ShapeSpec.of(ShapeKind kind, {Color? fill}) {
    final ink = fill ?? const Color(0xFFFFFFFF);
    return switch (kind) {
      ShapeKind.line || ShapeKind.arrow => ShapeSpec(
        kind: kind,
        width: 0.34,
        height: 0.12,
        strokeColor: ink,
        strokeWidth: 0.008,
        z: kStackOverEverything,
      ),
      // Taller than the straight rules, because a wave with no room to swing
      // in is a straight line drawn the slow way.
      ShapeKind.wave => ShapeSpec(
        kind: kind,
        width: 0.4,
        height: 0.09,
        strokeColor: ink,
        strokeWidth: 0.008,
        sides: 3,
        z: kStackOverEverything,
      ),
      ShapeKind.star => ShapeSpec(
        kind: kind,
        fill: ink,
        sides: 5,
        z: kStackOverEverything,
      ),
      ShapeKind.triangle => ShapeSpec(
        kind: kind,
        fill: ink,
        sides: 3,
        z: kStackOverEverything,
      ),
      ShapeKind.burst => ShapeSpec(
        kind: kind,
        fill: ink,
        sides: 12,
        innerRatio: 0.82,
        z: kStackOverEverything,
      ),
      ShapeKind.rectangle => ShapeSpec(
        kind: kind,
        fill: ink,
        cornerRadius: 0.12,
        z: kStackOverEverything,
      ),
      _ => ShapeSpec(kind: kind, fill: ink, z: kStackOverEverything),
    };
  }

  final ShapeKind kind;

  /// Centre of the shape's box, as a fraction of the canvas measured from the
  /// canvas centre: `(-0.25, 0)` is a quarter of a canvas to the left.
  final Offset center;

  /// Box size, both as fractions of the canvas **width**.
  ///
  /// Both against the same edge, which is the only way equal numbers can mean a
  /// square. Height used to be measured against the canvas *height* — on a
  /// 1179 x 2556 screen that made the default 0.28 x 0.28 paint 330 x 716, so
  /// every circle arrived as a tall ellipse and every square as a portrait
  /// rectangle. The stroke width and the shadow blur were already measured this
  /// way; the box is now consistent with them.
  ///
  /// Still a fraction rather than a pixel count, for the same reason as
  /// everything else in the document: the editor lays a scene out at a few
  /// hundred logical pixels and the exporter lays the same scene out at
  /// `doc.canvas`. The panel shows and accepts pixels, converted against the
  /// canvas on the way in and out.
  final double width;
  final double height;

  final double rotationDeg;

  /// Interior colour. Ignored entirely when [isOpen].
  final Color fill;

  /// Second gradient stop, or null for a flat fill.
  final Color? fillEnd;

  /// Direction of the fill gradient in degrees, clockwise from "up".
  final double gradientAngle;

  /// Whether the gradient runs out from the centre — [fill] at the middle,
  /// [fillEnd] at the rim — rather than across the shape at [gradientAngle].
  ///
  /// What a glow is made of: an orb with a bright core, a halo that fades to
  /// nothing at its edge, a pool of light behind a phone. A linear ramp across
  /// a circle reads as a lit ball, never as light.
  final bool gradientRadial;

  final Color strokeColor;

  /// Outline width as a fraction of canvas **width**. Zero draws no outline —
  /// except on an open shape, where the stroke is the whole shape and a zero
  /// would paint nothing at all.
  final double strokeWidth;

  /// Solid, dashed or dotted.
  final StrokeStyle strokeStyle;

  /// Whether [strokeWidth] is a fraction of the shape's own shorter side
  /// rather than of the canvas.
  ///
  /// For line art — an icon, a laurel, a scribble — whose weight is part of
  /// the drawing: scaled up, it should get bolder with it, the way a picture
  /// does, not stay a hairline the way an outline around a box should. Off for
  /// everything drawn before, which keeps every existing outline as it was.
  final bool strokeInBox;

  /// Stretches the dash pattern, 0.25 – 4.
  ///
  /// The pattern is measured in stroke widths, so it already grows with a
  /// thicker line and needs no control for the common case. This is the one
  /// that separates a dotted rule from a widely spaced one at the same weight,
  /// which no automatic relationship can decide.
  final double dashScale;

  /// Applied to the whole shape, fill and stroke together, so a translucent
  /// shape does not show its own outline through its own interior.
  final double opacity;

  /// Corner rounding, 0 (sharp) to 1 (as round as the box allows).
  ///
  /// Honoured by the rectangle, the polygons and the star. The motif paths are
  /// drawn with the curves they are, and ignore it.
  final double cornerRadius;

  /// How many of whatever the kind repeats: corners on [ShapeKind.polygon],
  /// points on [ShapeKind.star] and [ShapeKind.burst], crests on
  /// [ShapeKind.wave]. Clamped when the path is built — the polygons need at
  /// least three, a wave only one.
  ///
  /// One field for all of them rather than three, because no shape has two of
  /// these at once and the control is the same slider with a different caption.
  final int sides;

  /// How deep a star's or burst's valleys cut, as a fraction of its radius.
  final double innerRatio;

  /// The drawn path for [ShapeKind.custom], in the shape's own box: `(0,0)` is
  /// the box's top-left corner and `(1,1)` its bottom-right.
  ///
  /// Normalised on capture rather than stored as canvas coordinates, so moving
  /// or resizing a drawn shape is the same operation as moving or resizing any
  /// other one.
  final List<Offset> points;

  /// Whether a custom path joins back up. An open one is stroked like a line.
  final bool closed;

  /// The imported outline for [ShapeKind.path], as absolute `M`, `L`, `C` and
  /// `Z` in the shape's own box: `(0,0)` is the box's top-left corner and
  /// `(1,1)` its bottom-right — the same normalisation [points] uses, for the
  /// same reason.
  ///
  /// The *string* rather than the source file, and normalised on import rather
  /// than at paint time. It round-trips through `shapeToJson` byte for byte, it
  /// rebuilds to the same path at a 22px gallery tile and a 1179px export
  /// alike, and it travels inside `project.json` — so a backup carries an
  /// imported logo with no change to the archive format at all, and there is no
  /// library of shape files for anything to own, re-point or garbage-collect. A
  /// path is data; an image is a file.
  ///
  /// Sampling the outline into [points] instead was the obvious alternative and
  /// is wrong five ways over: `_smoothClosed` runs a quadratic through every
  /// vertex, so no imported shape could keep a sharp corner; there is only one
  /// subpath, so no counters and no holes; cubics and arcs would be flattened;
  /// [closed] is the whole of the topology; and the capture limits are tuned for
  /// a finger, not for artwork.
  ///
  /// [closed] is ignored for this kind. An imported outline is a filled
  /// silhouette whose own `Z` commands say where each subpath joins up, and the
  /// Style panel's stroke controls still outline it.
  final String pathData;

  /// Whether [pathData] fills by the even-odd rule; nonzero otherwise, which is
  /// SVG's own default.
  ///
  /// This is the single bit that decides whether the counter of an "O" is a
  /// hole or solid ink, which is why it is worth a field of its own rather than
  /// being inferred from the outline.
  final bool evenOdd;

  final ShapeShadow? shadow;

  /// The words drawn on this shape, if any.
  ///
  /// Distinct from [name] in every way that matters: [name] is the row's title
  /// in the layers list and never leaves the editor, while this is exported
  /// artwork. Renaming a layer must not touch it, and setting it must not
  /// rename the layer.
  final ShapeLabel? label;

  /// A picture filling the shape, cropped to cover it, or null for a colour
  /// fill.
  ///
  /// This is what an image layer is: a logo, a badge or a photo is a rectangle
  /// filled with a picture, and a round avatar is an ellipse filled with one.
  /// A fill rather than a kind of its own for the same reason a text layer is
  /// a label rather than a kind — the box, the stack position, the rotation,
  /// the outline, the shadow and every gesture are already a shape's, and a
  /// separate layer type would need all of them again.
  ///
  /// A *stored* path, like a screenshot's: resolved through `StoredImage`, and
  /// carried by backups and project copies alongside the screenshots.
  final String? imagePath;

  /// Where this shape sits in the screen's stack; see [kStackBehindFrames].
  ///
  /// A free position rather than a band, and measured on the same scale the
  /// devices and the captions use, so "in front of the second phone but behind
  /// the headline" is a thing a shape can actually be. Ties — two shapes at the
  /// same z, which is what a screen that has never been rearranged looks like —
  /// are broken by position in [ScreenDoc.shapes].
  final int z;

  /// What the layers list calls this shape, or null to be named by its kind.
  ///
  /// Null rather than a kind name baked in at creation: a shape renamed by
  /// nobody should still say "Star" after its kind is changed, and storing the
  /// label would leave it saying whatever it was created as.
  final String? name;

  /// Whether the shape is held back from the canvas.
  ///
  /// Kept in the document rather than treated as editor state, because it has
  /// to survive the project being closed and has to reach the export — hiding a
  /// layer and then exporting must produce the artwork you were looking at.
  final bool hidden;

  /// Whether the shape is pinned: drawn and exported as usual, but not picked
  /// or dragged on the canvas, so a backdrop or a finished badge cannot be
  /// nudged by accident while working around it. Unlocked from the layers
  /// list, where it can still be selected.
  final bool locked;

  /// The name the layers list shows.
  ///
  /// A shape the user named is called that. Otherwise, a shape that *says*
  /// something is called by what it says — a row of badges reading "Rectangle,
  /// Rectangle, Rectangle, Rectangle" is a list you have to select every entry
  /// of to read, and the 24px tile beside it cannot help: a text-only shape is
  /// a transparent box, so its thumbnail is blank by construction. Only then
  /// does it fall back to its kind.
  String get displayName {
    final chosen = name?.trim();
    if (chosen != null && chosen.isNotEmpty) return chosen;
    if (hasLabel) {
      final words = label!.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      return words.length <= 24 ? words : '${words.substring(0, 23)}…';
    }
    return kind.label;
  }

  /// Whether this shape is stroked along its path instead of filled.
  bool get isOpen => kind.alwaysOpen || (kind == ShapeKind.custom && !closed);

  /// Whether this shape draws words.
  ///
  /// Asked in one place rather than at each paint site, so "a label of spaces
  /// is no label" is decided once.
  bool get hasLabel => label != null && !label!.isEmpty;

  /// Whether the shape is filled with a picture. See [imagePath].
  bool get hasImage => imagePath != null && imagePath!.isNotEmpty;

  /// Whether this shape is a bare block of type: words with no visible shape
  /// around them.
  ///
  /// The editor treats one as a text layer and gives it text controls — font,
  /// size, weight, alignment, spacing, colour — rather than a shape's. It
  /// stops being one the moment it is given a fill, an outline or a picture,
  /// at which point it is a badge and the shape controls are the right ones.
  bool get isText =>
      label != null &&
      !hasImage &&
      !isOpen &&
      fill.a == 0 &&
      fillEnd == null &&
      strokeWidth <= 0;

  /// A text layer reading [text], ready to drop on the canvas.
  ///
  /// A clear box with a label in it, which is all a text layer is — see
  /// [ShapeLabel]. The box is wide and short, so the words wrap at a sensible
  /// measure, and it lands over everything, like every other new layer.
  factory ShapeSpec.text(
    String text, {
    String fontFamily = 'Inter',
    double size = 0.06,
    Color color = const Color(0xFFFFFFFF),
    bool bold = true,
  }) => ShapeSpec(
    kind: ShapeKind.rectangle,
    width: 0.8,
    height: size * 2.2,
    fill: const Color(0x00000000),
    label: ShapeLabel(
      text,
      fontFamily: fontFamily,
      size: size,
      color: color,
      bold: bold,
      padding: 0,
    ),
    z: kStackOverEverything,
  );

  /// An image layer showing [path], sized to the picture's own [aspect]
  /// (width over height) so it never arrives stretched.
  factory ShapeSpec.image(String path, {double aspect = 1}) {
    const box = 0.42;
    final safe = aspect <= 0 ? 1.0 : aspect;
    return ShapeSpec(
      kind: ShapeKind.rectangle,
      width: safe >= 1 ? box : box * safe,
      height: safe >= 1 ? box / safe : box,
      fill: const Color(0x00000000),
      imagePath: path,
      z: kStackOverEverything,
    );
  }

  /// Whether the box is square. Both edges are fractions of the same thing, so
  /// this needs no canvas.
  bool get isSquare => (width - height).abs() < 0.0005;

  /// The stroke a shape actually paints. An open shape with no width set would
  /// otherwise be an invisible layer with controls that appear to do nothing.
  double get effectiveStrokeWidth =>
      isOpen && strokeWidth <= 0 ? 0.004 : strokeWidth;

  /// The stroke in pixels, for a shape drawn [box] big on a canvas
  /// [canvasWidth] wide. See [strokeInBox].
  double strokePixels(double canvasWidth, Size box) => strokeInBox
      ? strokeWidth * math.min(box.width, box.height)
      : effectiveStrokeWidth * canvasWidth;

  ShapeSpec copyWith({
    String? componentId,
    String? instanceId,
    int? slot,

    /// Cuts the shape loose from its component, so a later master edit leaves
    /// it alone. What "detach instance" does.
    bool clearComponent = false,
    ShapeKind? kind,
    Offset? center,
    double? width,
    double? height,
    double? rotationDeg,
    Color? fill,
    Color? fillEnd,
    bool clearFillEnd = false,
    double? gradientAngle,
    bool? gradientRadial,
    Color? strokeColor,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    bool? strokeInBox,
    double? dashScale,
    double? opacity,
    double? cornerRadius,
    int? sides,
    double? innerRatio,
    List<Offset>? points,
    bool? closed,
    String? pathData,
    bool? evenOdd,
    ShapeShadow? shadow,
    bool clearShadow = false,
    ShapeLabel? label,
    bool clearLabel = false,
    String? imagePath,
    bool clearImage = false,
    int? z,
    String? name,
    bool clearName = false,
    bool? hidden,
    bool? locked,
  }) => ShapeSpec(
    kind: kind ?? this.kind,
    center: center ?? this.center,
    width: width ?? this.width,
    height: height ?? this.height,
    rotationDeg: rotationDeg ?? this.rotationDeg,
    fill: fill ?? this.fill,
    // The same flag idiom the rest of the document uses: a null argument
    // already means "leave this alone", so turning a gradient or a shadow
    // *off* has to be said explicitly.
    fillEnd: clearFillEnd ? null : (fillEnd ?? this.fillEnd),
    gradientAngle: gradientAngle ?? this.gradientAngle,
    gradientRadial: gradientRadial ?? this.gradientRadial,
    strokeColor: strokeColor ?? this.strokeColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeStyle: strokeStyle ?? this.strokeStyle,
    strokeInBox: strokeInBox ?? this.strokeInBox,
    dashScale: dashScale ?? this.dashScale,
    opacity: opacity ?? this.opacity,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    sides: sides ?? this.sides,
    innerRatio: innerRatio ?? this.innerRatio,
    points: points ?? this.points,
    closed: closed ?? this.closed,
    // No clear flags for these two: `''` and `false` already mean absent, so
    // the flag idiom the gradient and the shadow need has nothing to express.
    pathData: pathData ?? this.pathData,
    evenOdd: evenOdd ?? this.evenOdd,
    shadow: clearShadow ? null : (shadow ?? this.shadow),
    label: clearLabel ? null : (label ?? this.label),
    imagePath: clearImage ? null : (imagePath ?? this.imagePath),
    z: z ?? this.z,
    name: clearName ? null : (name ?? this.name),
    hidden: hidden ?? this.hidden,
    locked: locked ?? this.locked,
    componentId: clearComponent ? null : (componentId ?? this.componentId),
    instanceId: clearComponent ? null : (instanceId ?? this.instanceId),
    slot: clearComponent ? 0 : (slot ?? this.slot),
  );
}
