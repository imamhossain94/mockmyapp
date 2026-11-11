import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../domain/models/screen_doc.dart';
import '../domain/models/style_library.dart';

// --- primitives -----------------------------------------------------------

Map<String, double> _offset(Offset o) => {'dx': o.dx, 'dy': o.dy};
Offset _offsetOf(Map<String, dynamic> j) =>
    Offset((j['dx'] as num).toDouble(), (j['dy'] as num).toDouble());

double _d(Object? v) => (v as num).toDouble();

// --- Align2D --------------------------------------------------------------

Map<String, dynamic> align2dToJson(Align2D a) => {'x': a.x, 'y': a.y};
Align2D align2dFromJson(Map<String, dynamic> j) =>
    Align2D(_d(j['x']), _d(j['y']));

// --- Transform2D ----------------------------------------------------------

Map<String, dynamic> transformToJson(Transform2D t) => {
  'align': align2dToJson(t.align),
  'offsetPct': _offset(t.offsetPct),
  'rotationDeg': t.rotationDeg,
  'scale': t.scale,
  'pagePercentage': t.pagePercentage,
  // Written only when set, so a flat device's JSON is what it always was.
  if (t.tiltX != 0) 'tiltX': t.tiltX,
  if (t.tiltY != 0) 'tiltY': t.tiltY,
};

Transform2D transformFromJson(Map<String, dynamic> j) => Transform2D(
  align: align2dFromJson(j['align'] as Map<String, dynamic>),
  offsetPct: _offsetOf(j['offsetPct'] as Map<String, dynamic>),
  rotationDeg: _d(j['rotationDeg']),
  scale: _d(j['scale']),
  pagePercentage: _d(j['pagePercentage']),
  tiltX: _d(j['tiltX'] ?? 0.0),
  tiltY: _d(j['tiltY'] ?? 0.0),
);

// --- DepthSpec ------------------------------------------------------------

Map<String, dynamic> depthToJson(DepthSpec d) => {
  'thickness': d.thickness,
  'light': d.light,
  'glare': d.glare,
};

/// Field by field against the defaults, so a file that only ever set one of
/// them — or one written by a later build that knows a fourth — still reads.
DepthSpec depthFromJson(Map<String, dynamic> j) => DepthSpec(
  thickness: _d(j['thickness'] ?? 1.0),
  light: _d(j['light'] ?? -40.0),
  glare: _d(j['glare'] ?? 0.0),
);

// --- ShadowSpec -----------------------------------------------------------

Map<String, dynamic> shadowToJson(ShadowSpec s) => {
  'opacity': s.opacity,
  'color': s.color.toARGB32(),
  'blur': s.blur,
  'offsetPct': _offset(s.offsetPct),
};

ShadowSpec shadowFromJson(Map<String, dynamic> j) => ShadowSpec(
  opacity: _d(j['opacity']),
  color: Color(j['color'] as int),
  blur: _d(j['blur']),
  offsetPct: _offsetOf(j['offsetPct'] as Map<String, dynamic>),
);

// --- ScreenshotSpec -------------------------------------------------------

Map<String, dynamic> screenshotToJson(ScreenshotSpec s) => {
  'images': s.images,
  // Passed through untouched — see [ScreenshotSpec.edits]. This codec must not
  // learn what an edit contains, or every new kind of retouch op would need a
  // change here as well as where it is used.
  'edits': s.edits,
  'index': s.activeIndex,
  // Still written, and deliberately: a project opened by a build from before a
  // frame could hold a set finds the screenshot that was showing rather than
  // an empty slot. It is the active one, so what it names is always true.
  'imagePath': s.imagePath,
  'cornerRadiusPct': s.cornerRadiusPct,
  'strokeWidthPct': s.strokeWidthPct,
  'strokeColor': s.strokeColor.toARGB32(),
  'scale': s.scale,
  'offsetX': s.offsetX,
  'offsetY': s.offsetY,
  // Through the backdrop codec, because it is a backdrop — one that happens to
  // be inside the device rather than behind it. Omitted entirely when unset, so
  // a project written by this build and opened by an older one differs from
  // what it wrote by nothing at all.
  if (s.fill case final fill?) 'fill': backgroundToJson(fill),
  if (s.localeImages.isNotEmpty) 'localeImages': s.localeImages,
};

ScreenshotSpec screenshotFromJson(Map<String, dynamic> j) => ScreenshotSpec(
  edits: {
    for (final e in (j['edits'] as Map? ?? const {}).entries)
      e.key as String: Map<String, dynamic>.from(e.value as Map),
  },
  // Absent on every project written before a frame could hold more than one,
  // where the single `imagePath` is the whole set.
  images: switch (j['images']) {
    final List raw => [
      for (final path in raw.cast<String>())
        if (path.isNotEmpty) path,
    ],
    _ => [if (j['imagePath'] case final String path when path.isNotEmpty) path],
  },
  index: (j['index'] as num?)?.toInt() ?? 0,
  cornerRadiusPct: _d(j['cornerRadiusPct']),
  strokeWidthPct: _d(j['strokeWidthPct']),
  strokeColor: Color(j['strokeColor'] as int),
  scale: _d(j['scale'] ?? 1.0),
  offsetX: _d(j['offsetX'] ?? 0.0),
  offsetY: _d(j['offsetY'] ?? 0.0),
  fill: switch (j['fill']) {
    final Map<String, dynamic> raw => backgroundFromJson(raw),
    _ => null,
  },
  localeImages: {
    for (final e in ((j['localeImages'] as Map?) ?? const {}).entries)
      e.key as String: e.value as String,
  },
);

// --- Styles ---------------------------------------------------------------

Map<String, dynamic> colorStyleToJson(ColorStyle c) => {
  'id': c.id,
  'name': c.name,
  'color': c.color.toARGB32(),
};

ColorStyle colorStyleFromJson(Map<String, dynamic> j) => ColorStyle(
  id: j['id'] as String,
  name: (j['name'] as String?) ?? 'Colour',
  color: Color((j['color'] as int?) ?? 0xFF000000),
);

Map<String, dynamic> textStyleToJson(TextStyleDef t) => {
  'id': t.id,
  'name': t.name,
  'fontFamily': t.fontFamily,
  'size': t.size,
  'lineHeight': t.lineHeight,
  'letterSpacing': t.letterSpacing,
  'color': t.color.toARGB32(),
  'bold': t.bold,
  'italic': t.italic,
  'allUpCase': t.allUpCase,
};

TextStyleDef textStyleFromJson(Map<String, dynamic> j) => TextStyleDef(
  id: j['id'] as String,
  name: (j['name'] as String?) ?? 'Style',
  fontFamily: (j['fontFamily'] as String?) ?? 'Roboto',
  size: _d(j['size'] ?? 50),
  lineHeight: _d(j['lineHeight'] ?? 60),
  letterSpacing: _d(j['letterSpacing'] ?? 0),
  color: Color((j['color'] as int?) ?? 0xFF1A1A1A),
  bold: j['bold'] as bool? ?? true,
  italic: j['italic'] as bool? ?? false,
  allUpCase: j['allUpCase'] as bool? ?? false,
);

Map<String, dynamic> componentToJson(ComponentDef c) => {
  'id': c.id,
  'name': c.name,
  'shapes': c.shapes.map(shapeToJson).toList(),
};

ComponentDef componentFromJson(
  Map<String, dynamic> j, {
  required Size canvas,
}) => ComponentDef(
  id: j['id'] as String,
  name: (j['name'] as String?) ?? 'Component',
  shapes: [
    for (final sh in (j['shapes'] as List? ?? const []))
      shapeFromJson(sh as Map<String, dynamic>, canvas: canvas),
  ],
);

Map<String, dynamic> styleLibraryToJson(StyleLibrary l) => {
  'colors': l.colors.map(colorStyleToJson).toList(),
  'texts': l.texts.map(textStyleToJson).toList(),
  'components': l.components.map(componentToJson).toList(),
};

/// Absent on every project written before styles existed, which is exactly
/// what "this project has none" means.
StyleLibrary styleLibraryFromJson(Map<String, dynamic>? j) => j == null
    ? StyleLibrary.empty
    : StyleLibrary(
        colors: [
          for (final c in (j['colors'] as List? ?? const []))
            colorStyleFromJson(c as Map<String, dynamic>),
        ],
        texts: [
          for (final t in (j['texts'] as List? ?? const []))
            textStyleFromJson(t as Map<String, dynamic>),
        ],
        components: [
          for (final c in (j['components'] as List? ?? const []))
            // A component's shapes are stored in the same normalised space
            // every shape is, so the canvas only matters for the few sizes
            // that are absolute. The library is project-wide and its screens
            // can differ, so a nominal canvas is the honest answer here.
            componentFromJson(
              c as Map<String, dynamic>,
              canvas: const Size(1179, 2556),
            ),
        ],
      );

// --- FrameDesign ----------------------------------------------------------

/// Enums persist by name so the on-disk value survives reordering, and an
/// unknown one degrades to the sensible middle rather than throwing.
FrameSide _sideOf(Object? v, FrameSide fallback) =>
    FrameSide.values.firstWhere((s) => s.name == v, orElse: () => fallback);

/// Absent or unrecognised means the plain circular corner every document had
/// before continuous corners existed.
CornerStyle _cornerStyleOf(Object? v) => CornerStyle.values.firstWhere(
  (s) => s.name == v,
  orElse: () => CornerStyle.round,
);

Map<String, dynamic> punchHoleToJson(PunchHoleSpec p) => {
  'enabled': p.enabled,
  'align': p.align.name,
  'width': p.width,
  'height': p.height,
  'cornerRadius': p.cornerRadius,
  'top': p.top,
  'inset': p.inset,
  'color': p.color.toARGB32(),
  'borderColor': p.borderColor.toARGB32(),
  'borderWidth': p.borderWidth,
};

PunchHoleSpec punchHoleFromJson(Map<String, dynamic> j) => PunchHoleSpec(
  enabled: j['enabled'] as bool? ?? false,
  align: _sideOf(j['align'], FrameSide.center),
  width: _d(j['width'] ?? 0.055),
  height: _d(j['height'] ?? 0.055),
  cornerRadius: _d(j['cornerRadius'] ?? 0.5),
  top: _d(j['top'] ?? 0.022),
  inset: _d(j['inset'] ?? 0.06),
  color: Color((j['color'] as int?) ?? 0xFF050505),
  borderColor: Color((j['borderColor'] as int?) ?? 0xFF2A2A2A),
  borderWidth: _d(j['borderWidth'] ?? 0.0),
);

Map<String, dynamic> sideButtonToJson(SideButtonSpec b) => {
  'enabled': b.enabled,
  'side': b.side.name,
  'top': b.top,
  'length': b.length,
  'thickness': b.thickness,
  'gap': b.gap,
  'count': b.count,
  // Written only when set, so a design saved before keys could ride the top
  // edge — every one of them — round-trips byte for byte.
  if (b.onTop) 'onTop': true,
};

SideButtonSpec sideButtonFromJson(Map<String, dynamic> j) => SideButtonSpec(
  enabled: j['enabled'] as bool? ?? false,
  side: _sideOf(j['side'], FrameSide.right),
  top: _d(j['top'] ?? 0.22),
  length: _d(j['length'] ?? 0.06),
  thickness: _d(j['thickness'] ?? 0.014),
  gap: _d(j['gap'] ?? 0.02),
  count: (j['count'] as num?)?.toInt() ?? 1,
  onTop: j['onTop'] as bool? ?? false,
);

Map<String, dynamic> hingeToJson(HingeSpec h) => {
  'enabled': h.enabled,
  'side': h.side.name,
  'width': h.width,
  'cornerRadius': h.cornerRadius,
  'inset': h.inset,
};

HingeSpec hingeFromJson(Map<String, dynamic> j) => HingeSpec(
  enabled: j['enabled'] as bool? ?? false,
  side: _sideOf(j['side'], FrameSide.left),
  width: _d(j['width'] ?? 0.022),
  cornerRadius: _d(j['cornerRadius'] ?? 0.01),
  inset: _d(j['inset'] ?? 0.028),
);

Map<String, dynamic> frameDesignToJson(FrameDesign d) => {
  'thickness': d.thickness,
  'topThickness': d.topThickness,
  'bottomThickness': d.bottomThickness,
  'edgeCurve': d.edgeCurve,
  'cornerRadius': d.cornerRadius,
  'cornerStyle': d.cornerStyle.name,
  'color': d.color.toARGB32(),
  'rimColor': d.rimColor.toARGB32(),
  'rimWidth': d.rimWidth,
  'screenColor': d.screenColor.toARGB32(),
  'punchHole': punchHoleToJson(d.punchHole),
  'power': sideButtonToJson(d.power),
  'volume': sideButtonToJson(d.volume),
  // Only for a foldable: every other design is written exactly as before.
  if (d.hinge.enabled) 'hinge': hingeToJson(d.hinge),
  'aspect': d.aspect,
  // Only for a flat rim: every other design is written exactly as before.
  if (d.flat) 'flat': true,
};

FrameDesign frameDesignFromJson(Map<String, dynamic> j) => FrameDesign(
  thickness: _d(j['thickness'] ?? 0.012),
  edgeCurve: _d(j['edgeCurve'] ?? 0.0),
  // Null means "match the sides", so an absent key is right — which is also
  // what makes a document saved before these two existed reload with the even
  // bezel it was drawn with.
  topThickness: j['topThickness'] == null ? null : _d(j['topThickness']),
  bottomThickness: j['bottomThickness'] == null
      ? null
      : _d(j['bottomThickness']),
  cornerRadius: _d(j['cornerRadius'] ?? 0.085),
  cornerStyle: _cornerStyleOf(j['cornerStyle']),
  color: Color((j['color'] as int?) ?? 0xFF11142A),
  rimColor: Color((j['rimColor'] as int?) ?? 0x29FFFFFF),
  rimWidth: _d(j['rimWidth'] ?? 0.004),
  screenColor: Color((j['screenColor'] as int?) ?? 0xFF000000),
  punchHole: j['punchHole'] == null
      ? const PunchHoleSpec()
      : punchHoleFromJson(j['punchHole'] as Map<String, dynamic>),
  power: j['power'] == null
      ? const SideButtonSpec()
      : sideButtonFromJson(j['power'] as Map<String, dynamic>),
  volume: j['volume'] == null
      ? const SideButtonSpec(
          side: FrameSide.left,
          top: 0.20,
          length: 0.04,
          count: 2,
        )
      : sideButtonFromJson(j['volume'] as Map<String, dynamic>),
  hinge: j['hinge'] == null
      ? const HingeSpec()
      : hingeFromJson(j['hinge'] as Map<String, dynamic>),
  aspect: _d(j['aspect'] ?? 0.4743),
  flat: j['flat'] == true,
);

// --- FramePlacement -------------------------------------------------------

Map<String, dynamic> framePlacementToJson(FramePlacement f) => {
  'deviceId': f.deviceId,
  'variantId': f.variantId,
  'transform': transformToJson(f.transform),
  'screenshot': screenshotToJson(f.screenshot),
  'opacity': f.opacity,
  'frameHidden': f.frameHidden,
  'hidden': f.hidden,
  'cutoutHidden': f.cutoutHidden,
  'shadow': f.shadow == null ? null : shadowToJson(f.shadow!),
  'design': f.design == null ? null : frameDesignToJson(f.design!),
  'z': f.z,
  // Written only when changed, so a device nobody gave a depth to writes the
  // JSON it always did — the same rule as the tilt it goes with.
  if (f.depth != const DepthSpec()) 'depth': depthToJson(f.depth),
};

FramePlacement framePlacementFromJson(Map<String, dynamic> j) => FramePlacement(
  deviceId: j['deviceId'] as String,
  variantId: j['variantId'] as String,
  transform: transformFromJson(j['transform'] as Map<String, dynamic>),
  screenshot: screenshotFromJson(j['screenshot'] as Map<String, dynamic>),
  opacity: _d(j['opacity']),
  frameHidden: j['frameHidden'] as bool,
  // Absent on every project written before the device could be switched off,
  // which is exactly what "it is on" means.
  hidden: j['hidden'] as bool? ?? false,
  // Same again for the camera: absent means the device wears the one its
  // artwork draws.
  cutoutHidden: j['cutoutHidden'] as bool? ?? false,
  shadow: j['shadow'] == null
      ? null
      : shadowFromJson(j['shadow'] as Map<String, dynamic>),
  // Absent on every project written before built frames existed, which is
  // exactly what "use the catalog device's artwork" means.
  design: j['design'] == null
      ? null
      : frameDesignFromJson(j['design'] as Map<String, dynamic>),
  // Absent on every project written while the stack was a fixed spine, which
  // is exactly what the default means: devices sit between the shapes behind
  // them and the shapes over them, the way the spine hard-coded.
  z: j['z'] as int? ?? kStackFrames,
  // Absent on every project written before devices had sides, and on every
  // one since that left them at life size — the two mean the same thing.
  depth: j['depth'] == null
      ? const DepthSpec()
      : depthFromJson(j['depth'] as Map<String, dynamic>),
);

// --- ShapeSpec ------------------------------------------------------------

Map<String, dynamic> shapeShadowToJson(ShapeShadow s) => {
  'color': s.color.toARGB32(),
  'opacity': s.opacity,
  'blur': s.blur,
  'offset': _offset(s.offset),
};

ShapeShadow shapeShadowFromJson(Map<String, dynamic> j) => ShapeShadow(
  color: Color((j['color'] as int?) ?? 0xFF000000),
  opacity: _d(j['opacity'] ?? 0.28),
  blur: _d(j['blur'] ?? 0.03),
  offset: j['offset'] == null
      ? const Offset(0, 0.012)
      : _offsetOf(j['offset'] as Map<String, dynamic>),
);

Map<String, dynamic> shapeLabelToJson(ShapeLabel l) => {
  'text': l.text,
  'fontFamily': l.fontFamily,
  'size': l.size,
  'color': l.color.toARGB32(),
  'bold': l.bold,
  if (l.weight != null) 'weight': l.weight,
  'italic': l.italic,
  'allUpCase': l.allUpCase,
  'lineHeight': l.lineHeight,
  'letterSpacing': l.letterSpacing,
  'align': l.align.name,
  'padding': l.padding,
  if (l.translations.isNotEmpty)
    'translations': {
      for (final e in l.translations.entries)
        e.key: {
          'text': e.value.text,
          if (e.value.fontFamily != null) 'fontFamily': e.value.fontFamily,
          if (e.value.size != null) 'size': e.value.size,
        },
    },
};

ShapeLabel shapeLabelFromJson(Map<String, dynamic> j) => ShapeLabel(
  j['text'] as String? ?? '',
  fontFamily: j['fontFamily'] as String? ?? 'Roboto',
  size: _d(j['size'] ?? 0.03),
  color: Color((j['color'] as int?) ?? 0xFFFFFFFF),
  bold: j['bold'] as bool? ?? false,
  weight: (j['weight'] as num?)?.toInt(),
  italic: j['italic'] as bool? ?? false,
  allUpCase: j['allUpCase'] as bool? ?? false,
  lineHeight: _d(j['lineHeight'] ?? 1.2),
  letterSpacing: _d(j['letterSpacing'] ?? 0),
  align: TextAlign.values.firstWhere(
    (a) => a.name == j['align'],
    orElse: () => TextAlign.center,
  ),
  padding: _d(j['padding'] ?? 0.008),
  translations: {
    for (final e in ((j['translations'] as Map?) ?? const {}).entries)
      e.key as String: LabelTranslation(
        text: (e.value as Map)['text'] as String,
        fontFamily: e.value['fontFamily'] as String?,
        size: e.value['size'] == null ? null : _d(e.value['size']),
      ),
  },
);

Map<String, dynamic> shapeToJson(ShapeSpec s) => {
  'kind': s.kind.name,
  'componentId': s.componentId,
  'instanceId': s.instanceId,
  'slot': s.slot,
  'center': _offset(s.center),
  'width': s.width,
  'height': s.height,
  // Marks the height as a fraction of the canvas *width*. Absent on documents
  // written while it was a fraction of the canvas height; see [shapeFromJson].
  'heightRef': 'width',
  'rotationDeg': s.rotationDeg,
  'fill': s.fill.toARGB32(),
  'fillEnd': s.fillEnd?.toARGB32(),
  'gradientAngle': s.gradientAngle,
  'gradientRadial': s.gradientRadial,
  'strokeColor': s.strokeColor.toARGB32(),
  'strokeWidth': s.strokeWidth,
  'strokeStyle': s.strokeStyle.name,
  if (s.strokeInBox) 'strokeInBox': true,
  'dashScale': s.dashScale,
  'opacity': s.opacity,
  'cornerRadius': s.cornerRadius,
  'sides': s.sides,
  'innerRatio': s.innerRatio,
  // Flattened to a plain number list rather than a list of `{dx, dy}` maps: a
  // freehand path is hundreds of points, and the map form roughly triples the
  // size of every project file that contains one.
  'points': [
    for (final p in s.points) ...[p.dx, p.dy],
  ],
  'closed': s.closed,
  // Written as the app emitted it — absolute `M`/`L`/`C`/`Z` in the unit box —
  // rather than as the source file spelled it, so what reopens is exactly what
  // was imported and no SVG parser is needed to read a project back.
  'pathData': s.pathData,
  'evenOdd': s.evenOdd,
  'shadow': s.shadow == null ? null : shapeShadowToJson(s.shadow!),
  'label': s.label == null ? null : shapeLabelToJson(s.label!),
  if (s.imagePath != null) 'image': s.imagePath,
  'z': s.z,
  'name': s.name,
  'hidden': s.hidden,
  if (s.locked) 'locked': true,
};

/// The flat `[x0, y0, x1, y1, …]` list read back into points. An odd trailing
/// value is dropped rather than throwing — half a point is not a coordinate.
List<Offset> _pointsFromJson(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (var i = 0; i + 1 < raw.length; i += 2)
      Offset(_d(raw[i]), _d(raw[i + 1])),
  ];
}

/// Reads one shape.
///
/// [canvas] is needed only to migrate documents written while [ShapeSpec.height]
/// was a fraction of the canvas *height* rather than of its width: converting
/// between the two is exactly the canvas's own aspect. Without it a shape saved
/// on a 1179 x 2556 screen would come back less than half as tall as it was
/// drawn.
ShapeSpec shapeFromJson(
  Map<String, dynamic> j, {
  required Size canvas,
}) => ShapeSpec(
  // Absent on every shape written before components existed, which is exactly
  // what "this one is not part of a component" means.
  componentId: j['componentId'] as String?,
  instanceId: j['instanceId'] as String?,
  slot: (j['slot'] as num?)?.toInt() ?? 0,
  // An unknown kind means the file was written by a newer build. Falling back
  // to a rectangle keeps the shape's colour, size and position, which is a
  // recognisable stand-in; throwing would make one added enum value enough to
  // stop a whole project opening.
  kind: ShapeKind.values.firstWhere(
    (k) => k.name == j['kind'],
    orElse: () => ShapeKind.rectangle,
  ),
  center: j['center'] == null
      ? Offset.zero
      : _offsetOf(j['center'] as Map<String, dynamic>),
  width: _d(j['width'] ?? 0.28),
  height: _shapeHeightOf(j, canvas),
  rotationDeg: _d(j['rotationDeg'] ?? 0.0),
  fill: Color((j['fill'] as int?) ?? 0xFFFFFFFF),
  fillEnd: j['fillEnd'] == null ? null : Color(j['fillEnd'] as int),
  gradientAngle: _d(j['gradientAngle'] ?? 90.0),
  // Absent on every shape written before radial fills existed: a linear ramp.
  gradientRadial: j['gradientRadial'] as bool? ?? false,
  strokeColor: Color((j['strokeColor'] as int?) ?? 0xFF11142A),
  strokeWidth: _d(j['strokeWidth'] ?? 0.0),
  // Absent, or written by a newer build with a style this one cannot draw, is
  // the plain unbroken stroke every shape had before line styles existed.
  strokeStyle: StrokeStyle.values.firstWhere(
    (s) => s.name == j['strokeStyle'],
    orElse: () => StrokeStyle.solid,
  ),
  strokeInBox: j['strokeInBox'] as bool? ?? false,
  dashScale: _d(j['dashScale'] ?? 1.0),
  opacity: _d(j['opacity'] ?? 1.0),
  cornerRadius: _d(j['cornerRadius'] ?? 0.0),
  sides: (j['sides'] as num?)?.toInt() ?? 6,
  innerRatio: _d(j['innerRatio'] ?? 0.45),
  points: _pointsFromJson(j['points']),
  closed: j['closed'] as bool? ?? true,
  // Absent on every document written before shape import existed, and the
  // defaults are exactly what that means: no outline, and SVG's own fill rule.
  // No marker field is needed the way `heightRef` was — nothing about the
  // meaning of these two has ever changed, they were simply not there.
  pathData: j['pathData'] as String? ?? '',
  evenOdd: j['evenOdd'] as bool? ?? false,
  shadow: j['shadow'] == null
      ? null
      : shapeShadowFromJson(j['shadow'] as Map<String, dynamic>),
  // Absent on every shape written before shapes could carry words, which is
  // exactly what "this shape draws none" means. No marker field needed.
  label: j['label'] == null
      ? null
      : shapeLabelFromJson(j['label'] as Map<String, dynamic>),
  // Absent on every shape written before image layers, which is exactly "no
  // picture". Written only when present, so older documents stay byte-stable.
  imagePath: j['image'] as String?,
  z: _shapeZOf(j),
  name: j['name'] as String?,
  hidden: j['hidden'] as bool? ?? false,
  locked: j['locked'] as bool? ?? false,
);

/// The shape's height as a fraction of the canvas **width**.
///
/// `heightRef` marks a document that already stores it that way. Without the
/// marker the value is a fraction of the canvas *height*, from the build where
/// the two edges were measured against different things — the bug that made
/// every default circle a tall ellipse. Multiplying by the canvas aspect is
/// exactly the conversion, so a shape reopens at the size it was drawn even
/// though the number under it has changed meaning.
double _shapeHeightOf(Map<String, dynamic> j, Size canvas) {
  final stored = _d(j['height'] ?? 0.28);
  if (j['heightRef'] == 'width') return stored;
  if (canvas.width <= 0) return stored;
  return stored * canvas.height / canvas.width;
}

/// Where a shape sits in the stack, across three generations of saying it.
///
/// Newest first: `z` is the free position every component carries now. Before
/// that a shape had one of three bands named by `depth`, fixed relative to a
/// device and a caption it could not be reordered against; before *that*, a
/// boolean `inFront`, which is the two positions that model could express.
///
/// Both older forms map onto the default z scale exactly — that is what the
/// spacing in `stack_order.dart` is for — so an old document reopens looking
/// the way it was drawn rather than falling through to a default that would
/// drop every sticker to the bottom of its own screen.
int _shapeZOf(Map<String, dynamic> j) {
  final z = j['z'];
  if (z is int) return z;
  return switch (j['depth']) {
    'foreground' => kStackOverEverything,
    'overFrame' => kStackOverFrames,
    'background' => kStackBehindFrames,
    // An unknown band degrades to the back rather than throwing, and a
    // document older than bands says the same thing with a boolean.
    _ =>
      (j['inFront'] as bool? ?? false)
          ? kStackOverEverything
          : kStackBehindFrames,
  };
}

// --- Background -----------------------------------------------------------

Map<String, dynamic> backgroundToJson(Background b) => switch (b) {
  SolidBackground(:final color) => {'type': 'solid', 'color': color.toARGB32()},
  GradientBackground(
    :final colorOne,
    :final colorTwo,
    :final begin,
    :final end,
    :final midColors,
    :final radial,
  ) =>
    {
      'type': 'gradient',
      'colorOne': colorOne.toARGB32(),
      'colorTwo': colorTwo.toARGB32(),
      'begin': {'x': begin.x, 'y': begin.y},
      'end': {'x': end.x, 'y': end.y},
      // Only when used, so a two-colour ramp's JSON is what it always was.
      if (midColors.isNotEmpty)
        'midColors': [for (final c in midColors) c.toARGB32()],
      if (radial) 'radial': true,
    },
  ImageBackground(
    :final path,
    :final fit,
    :final scale,
    :final offsetX,
    :final offsetY,
    :final blur,
    :final overlayColor,
    :final overlayOpacity,
    :final slices,
    :final slice,
  ) =>
    {
      'type': 'image',
      'path': path,
      'fit': fit.name,
      'scale': scale,
      'offsetX': offsetX,
      'offsetY': offsetY,
      'blur': blur,
      'overlayColor': overlayColor.toARGB32(),
      'overlayOpacity': overlayOpacity,
      // Only for a panorama, unlike a pattern's pair (written always, below):
      // every image backdrop saved before panoramas existed has to come back
      // out byte for byte as it went in.
      if (slices > 1) ...{'slices': slices, 'slice': slice},
    },
  PatternBackground(
    :final style,
    :final colors,
    :final seed,
    :final scale,
    :final angle,
    :final intensity,
    :final slices,
    :final slice,
    :final symbols,
    :final symbolCount,
    :final symbolOpacity,
    :final symbolCenter,
  ) =>
    {
      'type': 'pattern',
      'style': style.name,
      'colors': colors.map((c) => c.toARGB32()).toList(),
      'seed': seed,
      'scale': scale,
      'angle': angle,
      'intensity': intensity,
      // Written unconditionally, even at the default of one: a panorama that
      // silently loses its slice on a round trip is eight screens of the same
      // corner of one picture.
      'slices': slices,
      'slice': slice,
      'symbols': symbols.map((s) => s.name).toList(),
      'symbolCount': symbolCount,
      'symbolOpacity': symbolOpacity,
      'symbolCenterX': symbolCenter.dx,
      'symbolCenterY': symbolCenter.dy,
    },
};

/// The twenty icon styles [PatternStyle.symbols] replaced, and the glyph each
/// one becomes.
///
/// Kept as strings rather than as removed enum values, because that is exactly
/// what a file written by the older build contains. Without this a project
/// using `hearts` would fall through the unknown-style branch and open as a
/// mesh gradient — the artwork silently gone, which is worse than failing.
const _migratedIconStyles = <String, PatternSymbol>{
  'notes': PatternSymbol.note,
  'waveform': PatternSymbol.waveform,
  'hearts': PatternSymbol.heart,
  'download': PatternSymbol.download,
  'wifi': PatternSymbol.wifi,
  'network': PatternSymbol.network,
  'sparkles': PatternSymbol.sparkle,
  'chat': PatternSymbol.chat,
  'play': PatternSymbol.play,
  'shields': PatternSymbol.shield,
  'clouds': PatternSymbol.cloud,
  'pins': PatternSymbol.pin,
  'stars': PatternSymbol.star,
  'bolts': PatternSymbol.bolt,
  'aperture': PatternSymbol.aperture,
  'orbit': PatternSymbol.orbit,
  'bells': PatternSymbol.bell,
  'bug': PatternSymbol.bug,
  'hash': PatternSymbol.hash,
  'at': PatternSymbol.at,
  // `equalizer` was removed outright rather than merged — it was `waveform`
  // with the bars rooted at a baseline. It lands on the waveform glyph, which
  // is the nearest thing that still exists.
  'equalizer': PatternSymbol.waveform,
};

/// The chosen glyphs, or the single one a migrated icon style implies.
///
/// Unknown names are dropped rather than defaulting, so a file from a newer
/// build loses the symbols this one cannot draw and keeps the rest. An empty
/// result falls back to one heart: a symbol field with nothing in it is a flat
/// colour, which reads as the style having failed.
List<PatternSymbol> _symbolsFromJson(Map<String, dynamic> j) {
  final migrated = _migratedIconStyles[j['style']];
  if (migrated != null) return [migrated];

  final raw = j['symbols'] as List?;
  if (raw == null) return const [PatternSymbol.heart];
  final parsed = [
    for (final name in raw)
      for (final symbol in PatternSymbol.values)
        if (symbol.name == name) symbol,
  ];
  return parsed.isEmpty ? const [PatternSymbol.heart] : parsed;
}

Background backgroundFromJson(Map<String, dynamic> j) => switch (j['type']) {
  'gradient' => GradientBackground(
    colorOne: Color(j['colorOne'] as int),
    colorTwo: Color(j['colorTwo'] as int),
    begin: Alignment(
      _d((j['begin'] as Map)['x']),
      _d((j['begin'] as Map)['y']),
    ),
    end: Alignment(_d((j['end'] as Map)['x']), _d((j['end'] as Map)['y'])),
    midColors: [
      for (final c in (j['midColors'] as List? ?? const []))
        if (c is int) Color(c),
    ],
    radial: j['radial'] as bool? ?? false,
  ),
  // Every adjustment defaults to "untouched", so a project written before they
  // existed opens as the plain cover-fit backdrop it was.
  'image' => ImageBackground(
    j['path'] as String,
    fit: ImageBackgroundFit.values.firstWhere(
      (f) => f.name == j['fit'],
      orElse: () => ImageBackgroundFit.cover,
    ),
    scale: _d(j['scale'] ?? 1.0),
    offsetX: _d(j['offsetX'] ?? 0.0),
    offsetY: _d(j['offsetY'] ?? 0.0),
    blur: _d(j['blur'] ?? 0.0),
    overlayColor: Color((j['overlayColor'] as int?) ?? 0xFF000000),
    overlayOpacity: _d(j['overlayOpacity'] ?? 0.0),
    // Absent on everything but a panorama: one picture on one screen.
    slices: math.max(1, (j['slices'] as num?)?.toInt() ?? 1),
    slice: math.max(0, (j['slice'] as num?)?.toInt() ?? 0),
  ),
  'pattern' => PatternBackground(
    // An unknown style name means the file was written by a newer build; fall
    // back rather than throw, so one added enum value cannot make a whole
    // project unopenable.
    style: _migratedIconStyles.containsKey(j['style'])
        ? PatternStyle.symbols
        : PatternStyle.values.firstWhere(
            (s) => s.name == j['style'],
            orElse: () => PatternStyle.mesh,
          ),
    colors: [
      for (final c in (j['colors'] as List? ?? const [])) Color(c as int),
    ],
    seed: (j['seed'] as num?)?.toInt() ?? 1,
    scale: _d(j['scale'] ?? 1.0),
    angle: _d(j['angle'] ?? 0.0),
    intensity: _d(j['intensity'] ?? 1.0),
    slices: (j['slices'] as num?)?.toInt() ?? 1,
    slice: (j['slice'] as num?)?.toInt() ?? 0,
    symbols: _symbolsFromJson(j),
    symbolCount: (j['symbolCount'] as num?)?.toInt() ?? 26,
    symbolOpacity: _d(j['symbolOpacity'] ?? 0.8),
    symbolCenter: Offset(
      _d(j['symbolCenterX'] ?? 0.0),
      _d(j['symbolCenterY'] ?? 0.0),
    ),
  ),
  _ => SolidBackground(Color(j['color'] as int)),
};

// --- CaptionSpec ----------------------------------------------------------

Map<String, dynamic> captionToJson(CaptionSpec c) => {
  'enabled': c.enabled,
  'text': c.text,
  'fontFamily': c.fontFamily,
  'size': c.size,
  'lineHeight': c.lineHeight,
  'color': c.color.toARGB32(),
  'align': align2dToJson(c.align),
  'allUpCase': c.allUpCase,
  'bold': c.bold,
  'weight': c.weight,
  'italic': c.italic,
  'underline': c.underline,
  'offsetPct': _offset(c.offsetPct),
  'backgroundColor': c.backgroundColor?.toARGB32(),
  'backgroundPaddingX': c.backgroundPaddingX,
  'backgroundPaddingY': c.backgroundPaddingY,
  'letterSpacing': c.letterSpacing,
  'strokeWidth': c.strokeWidth,
  'strokeColor': c.strokeColor.toARGB32(),
  'shadowBlur': c.shadowBlur,
  'shadowOffsetY': c.shadowOffsetY,
  'shadowColor': c.shadowColor.toARGB32(),
  'glowBlur': c.glowBlur,
  'glowColor': c.glowColor.toARGB32(),
  'backgroundRadius': c.backgroundRadius,
  'backgroundBorderColor': c.backgroundBorderColor?.toARGB32(),
  'backgroundBorderWidth': c.backgroundBorderWidth,
  'runs': [
    for (final r in c.runs)
      {
        'text': r.text,
        'color': r.color?.toARGB32(),
        'sizeScale': r.sizeScale,
        'bold': r.bold,
        'italic': r.italic,
        'underline': r.underline,
        'fontFamily': r.fontFamily,
      },
  ],
  'cornerStyle': c.cornerStyle.name,
  'styleId': c.styleId,
  // Only where a template set one, so every caption written before the field
  // existed, and every caption sized by hand, saves byte for byte as before.
  if (c.fitHeightPct != null) 'fitHeightPct': c.fitHeightPct,
  if (c.translations.isNotEmpty)
    'translations': {
      for (final e in c.translations.entries)
        e.key: {
          'text': e.value.text,
          if (e.value.runs.isNotEmpty)
            'runs': [for (final r in e.value.runs) _captionRunToJson(r)],
          if (e.value.fontFamily != null) 'fontFamily': e.value.fontFamily,
          if (e.value.size != null) 'size': e.value.size,
        },
    },
};

Map<String, dynamic> _captionRunToJson(CaptionRun r) => {
  'text': r.text,
  'color': r.color?.toARGB32(),
  'sizeScale': r.sizeScale,
  'bold': r.bold,
  'italic': r.italic,
  'underline': r.underline,
  'fontFamily': r.fontFamily,
};

CaptionSpec captionFromJson(Map<String, dynamic> j) => CaptionSpec(
  // Absent on every caption written before styles existed, which is exactly
  // what "this one was never given a style" means.
  styleId: j['styleId'] as String?,
  enabled: j['enabled'] as bool,
  text: j['text'] as String,
  fontFamily: j['fontFamily'] as String,
  size: _d(j['size']),
  lineHeight: _d(j['lineHeight']),
  color: Color(j['color'] as int),
  align: align2dFromJson(j['align'] as Map<String, dynamic>),
  allUpCase: j['allUpCase'] as bool,
  bold: j['bold'] as bool,
  // Absent on every caption written before it existed: the plain bold.
  weight: j['weight'] as int?,
  italic: j['italic'] as bool? ?? false,
  underline: j['underline'] as bool? ?? false,
  offsetPct: _offsetOf(j['offsetPct'] as Map<String, dynamic>),
  backgroundColor: j['backgroundColor'] == null
      ? null
      : Color(j['backgroundColor'] as int),
  backgroundPaddingX: _d(j['backgroundPaddingX'] ?? 12.0),
  backgroundPaddingY: _d(j['backgroundPaddingY'] ?? 6.0),
  // Every effect defaults to "off", so a project written before they existed
  // renders exactly as it always did.
  letterSpacing: _d(j['letterSpacing'] ?? 0.0),
  strokeWidth: _d(j['strokeWidth'] ?? 0.0),
  strokeColor: Color((j['strokeColor'] as int?) ?? 0xFF000000),
  shadowBlur: _d(j['shadowBlur'] ?? 0.0),
  shadowOffsetY: _d(j['shadowOffsetY'] ?? 0.0),
  shadowColor: Color((j['shadowColor'] as int?) ?? 0x4D000000),
  glowBlur: _d(j['glowBlur'] ?? 0.0),
  glowColor: Color((j['glowColor'] as int?) ?? 0xFFFFFFFF),
  backgroundRadius: _d(j['backgroundRadius'] ?? 8.0),
  backgroundBorderColor: j['backgroundBorderColor'] == null
      ? null
      : Color(j['backgroundBorderColor'] as int),
  backgroundBorderWidth: _d(j['backgroundBorderWidth'] ?? 0.0),
  runs: _captionRuns(j),
  cornerStyle: _cornerStyleOf(j['cornerStyle']),
  // Absent on every caption written before it existed: set at its own size
  // however tall it runs, which is how those captions always rendered.
  fitHeightPct: j['fitHeightPct'] == null ? null : _d(j['fitHeightPct']),
  translations: {
    for (final e in ((j['translations'] as Map?) ?? const {}).entries)
      e.key as String: CaptionTranslation(
        text: (e.value as Map)['text'] as String,
        runs: e.value['runs'] == null
            ? const []
            : _captionRuns({'runs': e.value['runs']}),
        fontFamily: e.value['fontFamily'] as String?,
        size: e.value['size'] == null ? null : _d(e.value['size']),
      ),
  },
);

/// A caption's styled runs, reading both the current shape and the one before
/// it.
///
/// Before the rich text editor a caption was styled a whole line at a time and
/// persisted a `lines` array. Those documents are on disk and inside every
/// backup taken up to now, so each stored line becomes one run carrying the
/// newline that ended it — which is exactly the run list the editor would build
/// if the same design were drawn today, and makes the migration lossless in
/// both directions.
List<CaptionRun> _captionRuns(Map<String, dynamic> j) {
  final runs = j['runs'] as List?;
  if (runs != null) {
    return [
      for (final r in runs)
        CaptionRun(
          (r as Map<String, dynamic>)['text'] as String,
          color: r['color'] == null ? null : Color(r['color'] as int),
          sizeScale: r['sizeScale'] == null ? null : _d(r['sizeScale']),
          bold: r['bold'] as bool?,
          italic: r['italic'] as bool?,
          underline: r['underline'] as bool?,
          fontFamily: r['fontFamily'] as String?,
        ),
    ];
  }

  final lines = j['lines'] as List? ?? const [];
  return [
    for (var i = 0; i < lines.length; i++)
      CaptionRun(
        ((lines[i] as Map<String, dynamic>)['text'] as String) +
            (i == lines.length - 1 ? '' : '\n'),
        color: lines[i]['color'] == null
            ? null
            : Color(lines[i]['color'] as int),
        sizeScale: lines[i]['sizeScale'] == null
            ? null
            : _d(lines[i]['sizeScale']),
        bold: lines[i]['bold'] as bool?,
        fontFamily: lines[i]['fontFamily'] as String?,
      ),
  ];
}

// --- ScreenDoc ------------------------------------------------------------

Map<String, dynamic> screenDocToJson(ScreenDoc d) => {
  'id': d.id,
  'canvas': {'w': d.canvas.width, 'h': d.canvas.height},
  'background': backgroundToJson(d.background),
  'frames': d.frames.map(framePlacementToJson).toList(),
  'shapes': d.shapes.map(shapeToJson).toList(),
  'caption': d.caption == null ? null : captionToJson(d.caption!),
  'subCaption': d.subCaption == null ? null : captionToJson(d.subCaption!),
  'isCaptionAbove': d.isCaptionAbove,
  'captionsZ': d.captionsZ,
};

ScreenDoc screenDocFromJson(Map<String, dynamic> j) => _screenDocFromJson(
  j,
  Size(_d((j['canvas'] as Map)['w']), _d((j['canvas'] as Map)['h'])),
);

/// Split out so the canvas is read once and handed to the readers that need it
/// — shapes carry sizes that are only interpretable against it.
ScreenDoc _screenDocFromJson(Map<String, dynamic> j, Size canvas) => ScreenDoc(
  id: j['id'] as String,
  canvas: canvas,
  background: backgroundFromJson(j['background'] as Map<String, dynamic>),
  frames: (j['frames'] as List)
      .map((e) => framePlacementFromJson(e as Map<String, dynamic>))
      .toList(),
  // Absent on every project written before shapes existed, which is exactly
  // what "this screen has none" means.
  shapes: [
    for (final s in (j['shapes'] as List? ?? const []))
      shapeFromJson(s as Map<String, dynamic>, canvas: canvas),
  ],
  caption: j['caption'] == null
      ? null
      : captionFromJson(j['caption'] as Map<String, dynamic>),
  subCaption: j['subCaption'] == null
      ? null
      : captionFromJson(j['subCaption'] as Map<String, dynamic>),
  isCaptionAbove: j['isCaptionAbove'] as bool,
  // Absent on every project written while the captions were a fixed anchor —
  // and the default is where that anchor was: over the devices, under the
  // shapes that were called stickers.
  captionsZ: j['captionsZ'] as int? ?? kStackCaptions,
);
