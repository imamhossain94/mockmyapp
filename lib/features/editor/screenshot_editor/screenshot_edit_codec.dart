import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

import '../../../data/assets/clipart_catalog.dart';
import '../../../data/repositories/stored_image.dart';
import '../../../data/serialization.dart';
import 'screenshot_edit_ops.dart';

/// Everything the retoucher needs to reopen a finished edit *as an edit*.
///
/// Apply flattens to a PNG and that PNG is what the scene draws and what the
/// export ships — none of that changes, and nothing downstream has to learn
/// about ops. This is the recipe kept beside the result, so opening Retouch
/// again hands back the objects rather than the pixels they became.
///
/// [source] is the capture before any of it. Reopening replays [ops] over that,
/// which is the only arrangement that does not double every edit: replaying
/// over the flattened PNG would paint a second copy of every stroke on top of
/// the first.
@immutable
class ScreenshotEdit {
  const ScreenshotEdit({
    required this.source,
    required this.crop,
    required this.ops,
    this.orientation = ImageOrientation.none,
    this.adjustments = const ImageAdjustments(),
    this.fill = ExpandFill.edge,
    this.fillColor = const Color(0xFF000000),
  });

  /// Library path of the capture as it was before this edit.
  final String source;

  final Rect crop;
  final ImageOrientation orientation;
  final ImageAdjustments adjustments;
  final ExpandFill fill;
  final Color fillColor;

  /// The edits, in draw order.
  ///
  /// A [RemoveBackgroundOp] is never in here. Its mask is a full-resolution
  /// texture produced by an isolate pass, and storing one per op would put a
  /// second copy of the screenshot in the project file for every cut-out. It is
  /// baked into [source] instead — which is honest, because erasing a
  /// background is a destructive edit in a way that moving a sticker is not.
  final List<EditOp> ops;
}

// -----------------------------------------------------------------------------
// Codec
//
// Kept beside the ops rather than in `data/serialization.dart` for the reason
// the ops themselves are not in `domain/`: the document holds this as data it
// does not interpret. `ScreenshotSpec` carries the encoded map and never asks
// what is in it, so the retoucher can grow a new kind of op without the
// document model learning about it.
// -----------------------------------------------------------------------------

Map<String, dynamic> _offset(Offset o) => {'x': o.dx, 'y': o.dy};
Offset _offsetOf(Map<String, dynamic> j) =>
    Offset((j['x'] as num).toDouble(), (j['y'] as num).toDouble());

Map<String, dynamic> _rect(Rect r) => {
  'l': r.left,
  't': r.top,
  'r': r.right,
  'b': r.bottom,
};

Rect _rectOf(Map<String, dynamic> j) => Rect.fromLTRB(
  (j['l'] as num).toDouble(),
  (j['t'] as num).toDouble(),
  (j['r'] as num).toDouble(),
  (j['b'] as num).toDouble(),
);

/// The placement every [PlacedOp] carries, as its own block so the three kinds
/// cannot drift apart.
Map<String, dynamic> _placement(PlacedOp op) => {
  'id': op.id,
  'center': _offset(op.center),
  'w': op.width,
  'h': op.height,
  'rot': op.rotationDeg,
  'opacity': op.opacity,
};

Map<String, dynamic>? editOpToJson(EditOp op) => switch (op) {
  BrushOp(:final points, :final color, :final width, :final marker) => {
    'kind': 'brush',
    // Flattened to a plain number list rather than a list of maps: a freehand
    // stroke is hundreds of points, and the map form roughly triples the size
    // of every project that contains one. Same choice `shapeToJson` made.
    'points': [
      for (final p in points) ...[p.dx, p.dy],
    ],
    'color': color.toARGB32(),
    'width': width,
    if (marker) 'marker': true,
  },
  MarkupOp(:final kind, :final start, :final end, :final color, :final width) =>
    {
      'kind': 'markup',
      'shape': kind.name,
      'from': _offset(start),
      'to': _offset(end),
      'color': color.toARGB32(),
      'width': width,
    },
  HideOp() => {
    'kind': 'hide',
    ..._placement(op),
    'style': op.style.name,
    'shape': op.shape.name,
    if (op.isFreehand)
      'outline': [
        for (final p in op.outline) ...[p.dx, p.dy],
      ],
    'blur': op.blur,
    'block': op.block,
    'color': op.color.toARGB32(),
    if (op.cornerRadius > 0) 'cornerRadius': op.cornerRadius,
  },
  StatusBarOp(
    :final height,
    :final background,
    :final foreground,
    :final style,
    :final time,
  ) =>
    {
      'kind': 'statusBar',
      'height': height,
      'background': background.toARGB32(),
      'foreground': foreground.toARGB32(),
      'style': style.name,
      'time': time,
    },
  NavBarOp(:final height, :final style, :final background, :final foreground) =>
    {
      'kind': 'navBar',
      'height': height,
      'style': style.name,
      'background': background.toARGB32(),
      'foreground': foreground.toARGB32(),
    },
  TextOp() => {
    'kind': 'text',
    ..._placement(op),
    'text': op.text,
    'fontSize': op.fontSize,
    'font': op.fontFamily,
    'bold': op.bold,
    'color': op.color.toARGB32(),
    'align': op.align.name,
    'look': op.look.name,
    'accent': op.accent.toARGB32(),
  },
  ShapeOp(:final spec) => {
    'kind': 'shape',
    ..._placement(op as PlacedOp),
    // The shape's own codec, so every field it grows arrives here for free.
    'spec': shapeToJson(spec),
  },
  ImageOp(:final source, :final flipH, :final cornerRadius) => {
    'kind': 'image',
    ..._placement(op as PlacedOp),
    'source': source,
    'flipH': flipH,
    'cornerRadius': cornerRadius,
    if (op.isCropped) 'crop': _rect(op.crop),
    if (op.borderWidth > 0) ...{
      'borderWidth': op.borderWidth,
      'borderColor': op.borderColor.toARGB32(),
    },
  },
  StickerOp(:final stickerId, :final tint, :final flipH) => {
    'kind': 'sticker',
    ..._placement(op as PlacedOp),
    'sticker': stickerId,
    'tint': tint?.toARGB32(),
    'flipH': flipH,
  },
  // Baked into the source instead — see [ScreenshotEdit.ops]. Null rather than
  // a throw: the caller filters, and an op that cannot be written is a fact
  // about this op, not an error.
  RemoveBackgroundOp() => null,
};

List<Offset> _pointsOf(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (var i = 0; i + 1 < raw.length; i += 2)
      Offset((raw[i] as num).toDouble(), (raw[i + 1] as num).toDouble()),
  ];
}

/// A status bar written as a rect across the picture, before it was a height:
/// that rect's height as a fraction of its own width, which is what the bar is
/// measured in now.
double? _barHeightOf(Map<String, dynamic> j, Size imageSize) {
  final raw = j['rect'];
  if (raw is! Map<String, dynamic> || imageSize.isEmpty) return null;
  final rect = _rectOf(raw);
  if (rect.width <= 0) return null;
  return rect.height * imageSize.height / (rect.width * imageSize.width);
}

/// Rebuilds one op.
///
/// Async because two kinds carry something that has to be loaded: a placed
/// image's texture and a sticker's picture. They are loaded through the caller's
/// banks so a file placed twice is decoded once, exactly as placement does.
///
/// Returns null when the op cannot be rebuilt — a library image that has been
/// deleted, or a sticker id from a later version of the pack. Dropping one
/// object is the right failure: it beats refusing to open the edit at all.
Future<EditOp?> editOpFromJson(
  Map<String, dynamic> j, {
  required Size imageSize,
  required Future<ui.Image?> Function(String source) texture,
  required Future<(ui.Picture, Size)?> Function(String stickerId) sticker,
}) async {
  final id = (j['id'] as num?)?.toInt() ?? 0;
  final center = j['center'] == null
      ? Offset.zero
      : _offsetOf(j['center'] as Map<String, dynamic>);
  final width = (j['w'] as num?)?.toDouble() ?? 0.2;
  final height = (j['h'] as num?)?.toDouble() ?? 0.2;
  final rotation = (j['rot'] as num?)?.toDouble() ?? 0;
  final opacity = (j['opacity'] as num?)?.toDouble() ?? 1;

  switch (j['kind']) {
    case 'brush':
      return BrushOp(
        points: _pointsOf(j['points']),
        color: Color((j['color'] as num?)?.toInt() ?? 0xFF000000),
        width: (j['width'] as num?)?.toDouble() ?? 0.02,
        marker: j['marker'] as bool? ?? false,
      );
    case 'markup':
      return MarkupOp(
        kind: MarkupKind.values.firstWhere(
          (k) => k.name == j['shape'],
          orElse: () => MarkupKind.line,
        ),
        start: _offsetOf(j['from'] as Map<String, dynamic>),
        end: _offsetOf(j['to'] as Map<String, dynamic>),
        color: Color((j['color'] as num?)?.toInt() ?? 0xFF000000),
        width: (j['width'] as num?)?.toDouble() ?? 0.01,
      );
    case 'hide':
      return HideOp(
        id: id,
        center: center,
        width: width,
        height: height,
        rotationDeg: rotation,
        style: HideStyle.values.firstWhere(
          (v) => v.name == j['style'],
          orElse: () => HideStyle.blur,
        ),
        shape: HideShape.values.firstWhere(
          (v) => v.name == j['shape'],
          orElse: () => HideShape.box,
        ),
        outline: _pointsOf(j['outline']),
        blur: (j['blur'] as num?)?.toDouble() ?? 0.03,
        block: (j['block'] as num?)?.toDouble() ?? 0.035,
        color: Color((j['color'] as num?)?.toInt() ?? 0xFF000000),
        cornerRadius: (j['cornerRadius'] as num?)?.toDouble() ?? 0,
      );
    // The two ways of hiding something before a hidden area was an object —
    // a patch or a blur, and a mosaic — each read back as an area over the
    // same rect, so an edit made then can be moved and restyled now.
    case 'redact':
      final rect = _rectOf(j['rect'] as Map<String, dynamic>);
      return HideOp(
        id: 0,
        center: rect.center,
        width: 0,
        height: 0,
        style: j['style'] == 'blur' ? HideStyle.blur : HideStyle.cover,
        blur: (j['blur'] as num?)?.toDouble() ?? 0.02,
        color: Color((j['color'] as num?)?.toInt() ?? 0xFF000000),
        cornerRadius: (j['cornerRadius'] as num?)?.toDouble() ?? 0,
      ).over(rect, imageSize);
    case 'pixelate':
      final rect = _rectOf(j['rect'] as Map<String, dynamic>);
      final cols = (j['cols'] as num?)?.toInt() ?? 0;
      return HideOp(
        id: 0,
        center: rect.center,
        width: 0,
        height: 0,
        style: HideStyle.pixelate,
        // The cells it was cut into, as wide as they were.
        block: cols > 0 ? rect.width / cols : 0.035,
      ).over(rect, imageSize);
    case 'statusBar':
      final style = StatusBarStyle.values.firstWhere(
        (v) => v.name == j['style'],
        orElse: () => StatusBarStyle.ios,
      );
      return StatusBarOp(
        height:
            (j['height'] as num?)?.toDouble() ??
            _barHeightOf(j, imageSize) ??
            style.height,
        background: Color((j['background'] as num?)?.toInt() ?? 0xFFFFFFFF),
        foreground: Color((j['foreground'] as num?)?.toInt() ?? 0xFF000000),
        style: style,
        time: j['time'] as String? ?? '9:41',
      );
    case 'navBar':
      final style = NavBarStyle.values.firstWhere(
        (v) => v.name == j['style'],
        orElse: () => NavBarStyle.gesture,
      );
      return NavBarOp(
        height: (j['height'] as num?)?.toDouble() ?? style.height,
        style: style,
        background: Color((j['background'] as num?)?.toInt() ?? 0x00000000),
        foreground: Color((j['foreground'] as num?)?.toInt() ?? 0xFF000000),
      );
    case 'text':
      final text = j['text'] as String?;
      if (text == null) return null;
      return TextOp(
        id: id,
        text: text,
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 0.08,
        center: center,
        width: width,
        height: height,
        rotationDeg: rotation,
        opacity: opacity,
        fontFamily: j['font'] as String? ?? 'Inter',
        bold: j['bold'] as bool? ?? true,
        color: Color((j['color'] as num?)?.toInt() ?? 0xFFFFFFFF),
        align: TextAlign.values.firstWhere(
          (a) => a.name == j['align'],
          orElse: () => TextAlign.center,
        ),
        look: TextLook.values.firstWhere(
          (l) => l.name == j['look'],
          orElse: () => TextLook.plain,
        ),
        accent: Color((j['accent'] as num?)?.toInt() ?? 0xFF000000),
      );
    case 'shape':
      return ShapeOp(
        id: id,
        spec: shapeFromJson(
          j['spec'] as Map<String, dynamic>,
          canvas: imageSize,
        ),
        center: center,
        width: width,
        height: height,
        rotationDeg: rotation,
        opacity: opacity,
      );
    case 'image':
      final path = j['source'] as String?;
      if (path == null) return null;
      final bitmap = await texture(path);
      if (bitmap == null) return null;
      return ImageOp(
        id: id,
        image: bitmap,
        source: path,
        center: center,
        width: width,
        height: height,
        rotationDeg: rotation,
        opacity: opacity,
        flipH: j['flipH'] as bool? ?? false,
        cornerRadius: (j['cornerRadius'] as num?)?.toDouble() ?? 0,
        crop: switch (j['crop']) {
          final Map<String, dynamic> crop => _rectOf(crop),
          _ => ImageOp.fullCrop,
        },
        borderWidth: (j['borderWidth'] as num?)?.toDouble() ?? 0,
        borderColor: Color((j['borderColor'] as num?)?.toInt() ?? 0xFFFFFFFF),
      );
    case 'sticker':
      final stickerId = j['sticker'] as String?;
      if (stickerId == null) return null;
      final art = await sticker(stickerId);
      if (art == null) return null;
      final tint = (j['tint'] as num?)?.toInt();
      return StickerOp(
        id: id,
        picture: art.$1,
        pictureSize: art.$2,
        stickerId: stickerId,
        center: center,
        width: width,
        height: height,
        rotationDeg: rotation,
        opacity: opacity,
        tint: tint == null ? null : Color(tint),
        flipH: j['flipH'] as bool? ?? false,
      );
    default:
      return null;
  }
}

Map<String, dynamic> _adjustToJson(ImageAdjustments a) => {
  'brightness': a.brightness,
  'contrast': a.contrast,
  'saturation': a.saturation,
  // Only what is set, so a recipe written with three sliders stays three
  // numbers long and an old reader sees exactly what it always did.
  if (a.exposure != 0) 'exposure': a.exposure,
  if (a.highlights != 0) 'highlights': a.highlights,
  if (a.shadows != 0) 'shadows': a.shadows,
  if (a.warmth != 0) 'warmth': a.warmth,
  if (a.tint != 0) 'tint': a.tint,
  if (a.fade != 0) 'fade': a.fade,
  if (a.vignette != 0) 'vignette': a.vignette,
  if (a.blur != 0) 'blur': a.blur,
  if (a.look != PhotoFilter.none) 'look': a.look.name,
  if (a.look != PhotoFilter.none) 'lookStrength': a.lookStrength,
};

ImageAdjustments _adjustOf(Map<String, dynamic>? j) {
  double at(String key) => (j?[key] as num?)?.toDouble() ?? 0;
  return ImageAdjustments(
    brightness: at('brightness'),
    contrast: at('contrast'),
    saturation: at('saturation'),
    exposure: at('exposure'),
    highlights: at('highlights'),
    shadows: at('shadows'),
    warmth: at('warmth'),
    tint: at('tint'),
    fade: at('fade'),
    vignette: at('vignette'),
    blur: at('blur'),
    look: PhotoFilter.values.firstWhere(
      (f) => f.name == j?['look'],
      orElse: () => PhotoFilter.none,
    ),
    lookStrength: (j?['lookStrength'] as num?)?.toDouble() ?? 1,
  );
}

Map<String, dynamic> screenshotEditToJson(ScreenshotEdit edit) => {
  'source': edit.source,
  'crop': _rect(edit.crop),
  'turns': edit.orientation.turns,
  'flipH': edit.orientation.flipH,
  if (edit.orientation.flipV) 'flipV': true,
  if (edit.orientation.angle != 0) 'angle': edit.orientation.angle,
  'adjust': _adjustToJson(edit.adjustments),
  'fill': edit.fill.name,
  'fillColor': edit.fillColor.toARGB32(),
  'ops': [for (final op in edit.ops) ?editOpToJson(op)],
};

/// The stored recipe, with every op rebuilt.
///
/// See [editOpFromJson] for why a single unreadable op is dropped rather than
/// failing the whole edit.
Future<ScreenshotEdit?> screenshotEditFromJson(
  Map<String, dynamic> j, {
  required Size imageSize,
  required Future<ui.Image?> Function(String source) texture,
  required Future<(ui.Picture, Size)?> Function(String stickerId) sticker,
}) async {
  final source = j['source'] as String?;
  if (source == null) return null;

  final ops = <EditOp>[];
  for (final raw in (j['ops'] as List? ?? const [])) {
    final op = await editOpFromJson(
      raw as Map<String, dynamic>,
      imageSize: imageSize,
      texture: texture,
      sticker: sticker,
    );
    if (op != null) ops.add(op);
  }

  // Ids are what selection is keyed on. An area written before hiding was an
  // object has none, and two with the same id would be selected — and
  // edited — as one, so each is given one past the highest in use.
  var next =
      ops.whereType<PlacedOp>().fold(0, (high, op) => math.max(high, op.id)) +
      1;
  final seen = <int>{};
  for (var i = 0; i < ops.length; i++) {
    final op = ops[i];
    if (op is PlacedOp && (op.id <= 0 || !seen.add(op.id))) {
      ops[i] = op.withId(next++);
    }
  }

  return ScreenshotEdit(
    source: source,
    crop: j['crop'] == null
        ? const Rect.fromLTRB(0, 0, 1, 1)
        : _rectOf(j['crop'] as Map<String, dynamic>),
    orientation: ImageOrientation(
      turns: (j['turns'] as num?)?.toInt() ?? 0,
      flipH: j['flipH'] as bool? ?? false,
      flipV: j['flipV'] as bool? ?? false,
      angle: (j['angle'] as num?)?.toDouble() ?? 0,
    ),
    adjustments: _adjustOf(j['adjust'] as Map<String, dynamic>?),
    fill: ExpandFill.values.firstWhere(
      (f) => f.name == j['fill'],
      orElse: () => ExpandFill.edge,
    ),
    fillColor: Color((j['fillColor'] as num?)?.toInt() ?? 0xFF000000),
    ops: ops,
  );
}

/// Re-decodes a placed image from the library.
Future<ui.Image?> loadPlacedTexture(String source) async {
  final bytes = await StoredImage.bytes(source);
  if (bytes == null) return null;
  return decodePlacedImage(bytes);
}

/// Re-loads a sticker's art from the bundled pack.
Future<(ui.Picture, Size)?> loadStickerArt(
  ClipartCatalog catalog,
  String stickerId,
) async {
  final sticker = catalog.byId(stickerId);
  if (sticker == null) return null;
  final info = await loadStickerPicture(sticker);
  return (info.picture, info.size);
}
