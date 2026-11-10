// Measures, for every device in `assets/frames/manifest.json`, what a frame's
// artwork does not otherwise declare, and writes it back in:
//
//   bodyRect    the opaque chassis inside the asset's canvas
//   cutoutRect  the camera island inside the screen aperture
//   keys        the side keys standing proud of the chassis
//
// and repairs the one field it does declare but never measured: every traced
// Apple and Pixel variant carries `frameColor: #000000`, a placeholder from
// before anything read it. A built frame takes its body colour from there, so
// left alone a Desert Titanium iPhone would come out black.
//
// WHY
// ===
// `screenRect` is a share of the asset's *canvas*, and those canvases carry
// transparent margin around the body — an iPhone's is ~3% a side, a Pixel 8's
// nearly 12%. That margin is harmless while the artwork is painted whole, but
// the frame builder draws a body edge to edge, so reading `screenRect.x` as a
// bezel counts the margin as bezel. `bodyRect` is what lets a built frame
// reproduce the real border instead. See `frameDesignForDevice`.
//
// `cutoutRect` is the same idea for the camera: the manifest says `punch` or
// `notch`, which is a shape but not a size or a position.
//
// `keys` is for a device turned out of the page. The artwork paints each key
// as a sliver in the plane of the screen, which a turned phone would wear as a
// fin; the solid body draws them on its side wall instead, and needs to know
// where the artwork put them. See `FrameKey`.
//
// HOW
// ===
// Both rects are measured off pixels rather than parsed out of the SVG, for
// the same reason `measure_screen_rects.py` rasterises: the assets come from
// Figma masks, Sketch even-odd rings and three different generators, and the
// only thing all of them agree on is what they draw.
//
// The body is NOT the alpha bounding box — side keys stand proud of the
// chassis, and a bounding box counts them as body. Each row's opaque span is
// collected instead and the **median** taken: the straight sides span most
// rows, while keys and corners are each a small minority, so the median lands
// on the chassis edge and ignores both.
//
// Re-run this after regenerating any artwork. The two rects are idempotent;
// the colour repair is not, by design — it only touches variants still on the
// #000000 placeholder, so a run cannot walk a measured colour away from where
// the last one put it.
//
// Run from the repo root:  flutter test tool/measure_body_rects.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// Anything at or under this is canvas, not artwork.
const _alphaEmpty = 24;

/// The camera island is solid; the curved-edge glass band the Note 10 and Edge
/// 50 Ultra paint across their apertures tops out around 0.36 alpha, and the
/// traced Apple and Pixel frames lay near-opaque specular sheens over theirs.
/// Only a genuinely solid pixel should register as a cut-out.
const _alphaSolid = 252;

/// How far down the aperture a camera can sit. A notch hangs off the top edge
/// and a punch hole rides just under it; nothing else is a camera.
const _cutoutBand = 0.22;

/// No camera island is anything like this share of the screen. A measurement
/// past either is glass the threshold above did not filter, not hardware, and
/// is reported as unmeasured rather than written into the manifest.
const _cutoutMaxWidth = 0.6;
const _cutoutMaxHeight = 0.2;

/// Below this luminance a rail column is display border rather than chassis.
/// A Space Black iPhone's rail face still measures around 41.
const _railFloor = 16.0;

/// Long edge to rasterise at. Big enough that a hairline bezel is several
/// pixels, small enough that 32 devices measure in seconds.
const _raster = 1400;

/// How far past the chassis edge a row has to reach, in raster pixels, to be
/// part of a key. The edge is anti-aliased, so a row can overshoot the median
/// by a pixel on its own; the thinnest key in the catalog, the iPhone 16 Pro
/// Max's, stands three proud at this raster.
const _keyMinProud = 1.5;

/// Anything shorter than this share of the canvas height is not a key — a
/// speck of anti-aliasing, or an antenna line catching the threshold. The
/// shortest real one, an iPhone's Action button, is about four times it.
const _keyMinLength = 0.01;

Future<ui.Image> _rasterise(String asset) async {
  if (asset.toLowerCase().endsWith('.svg')) {
    final info = await vg.loadPicture(SvgAssetLoader(asset), null);
    final size = info.size;
    final scale = _raster / size.height;
    final w = (size.width * scale).round();
    final h = (size.height * scale).round();

    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..scale(scale)
      ..drawPicture(info.picture);
    final image = await recorder.endRecording().toImage(w, h);
    info.picture.dispose();
    return image;
  }

  final bytes = await rootBundle.load(asset);
  final codec = await ui.instantiateImageCodec(
    bytes.buffer.asUint8List(),
    targetHeight: _raster,
  );
  return (await codec.getNextFrame()).image;
}

/// The raw pixels and the alpha plane pulled out of them, row-major.
Future<(Uint8List, Uint8List, int, int)> _pixels(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final rgba = data!.buffer.asUint8List();
  final w = image.width;
  final h = image.height;
  final alpha = Uint8List(w * h);
  for (var i = 0; i < alpha.length; i++) {
    alpha[i] = rgba[i * 4 + 3];
  }
  return (rgba, alpha, w, h);
}

double _median(List<int> values) {
  values.sort();
  final mid = values.length ~/ 2;
  return values.length.isOdd
      ? values[mid].toDouble()
      : (values[mid - 1] + values[mid]) / 2;
}

/// The chassis, as fractions of the canvas.
Map<String, double> _bodyRect(Uint8List a, int w, int h) {
  final lefts = <int>[];
  final rights = <int>[];
  for (var y = 0; y < h; y++) {
    var first = -1;
    var last = -1;
    for (var x = 0; x < w; x++) {
      if (a[y * w + x] > _alphaEmpty) {
        if (first < 0) first = x;
        last = x;
      }
    }
    if (first >= 0) {
      lefts.add(first);
      rights.add(last);
    }
  }

  final tops = <int>[];
  final bottoms = <int>[];
  for (var x = 0; x < w; x++) {
    var first = -1;
    var last = -1;
    for (var y = 0; y < h; y++) {
      if (a[y * w + x] > _alphaEmpty) {
        if (first < 0) first = y;
        last = y;
      }
    }
    if (first >= 0) {
      tops.add(first);
      bottoms.add(last);
    }
  }

  final x0 = _median(lefts);
  final x1 = _median(rights) + 1;
  final y0 = _median(tops);
  final y1 = _median(bottoms) + 1;
  return {'x': x0 / w, 'y': y0 / h, 'w': (x1 - x0) / w, 'h': (y1 - y0) / h};
}

/// The camera island inside [screen], as fractions of the canvas, or null when
/// the aperture is clean.
///
/// Only the top strip of the aperture is searched, and only clear of its own
/// edges. Both restrictions are load-bearing, and each was put in by a wrong
/// answer:
///
/// * `screenRect` is the *bounding box* of a rounded hole, so on a phone with
///   generously curved corners the bezel intrudes into that box at all four
///   corners. Scanning the raw box reported a cut-out the size of the whole
///   screen on every device except the square-cornered Samsungs.
/// * Some traced frames paint a fully opaque edge treatment down both sides of
///   the aperture — the iPhone 17 Pro Max does — which reads as a cut-out
///   spanning the display from left to right.
///
/// A front camera lives in the top of the display and never at the edge of it,
/// so restricting the search says what is true rather than patching around
/// each artwork in turn.
Map<String, double>? _cutoutRect(
  Uint8List a,
  int w,
  int h,
  Map<String, dynamic> screen,
  double cornerRadiusPct,
) {
  final sw = (screen['w'] as num).toDouble() * w;
  final sh = (screen['h'] as num).toDouble() * h;
  // Pull in off the aperture's own edge: it is anti-aliased against the bezel,
  // and one stray half-covered pixel there would read as a cut-out.
  final pad = sw * 0.006;
  final screenLeft = (screen['x'] as num).toDouble() * w;
  final screenTop = (screen['y'] as num).toDouble() * h;
  final r = cornerRadiusPct * sw;

  // Clear of the corner arcs, and of any edge treatment drawn inside the
  // aperture. The corner radius is itself the best available measure of how
  // far in a curved edge reaches, with a floor for the flat-sided phones.
  final margin = math.max(r, sw * 0.05);
  final left = screenLeft + margin;
  final right = screenLeft + sw - margin;
  final top = screenTop + pad;
  final bottom = screenTop + sh * _cutoutBand;

  var x0 = w, x1 = -1, y0 = h, y1 = -1;
  for (var y = top.ceil(); y < bottom; y++) {
    for (var x = left.ceil(); x < right; x++) {
      if (a[y * w + x] >= _alphaSolid) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) return null;
  if ((x1 + 1 - x0) > sw * _cutoutMaxWidth ||
      (y1 + 1 - y0) > sh * _cutoutMaxHeight) {
    return null;
  }
  return {
    'x': x0 / w,
    'y': y0 / h,
    'w': (x1 + 1 - x0) / w,
    'h': (y1 + 1 - y0) / h,
  };
}

/// The chassis colour, sampled off the side rail.
///
/// The rail is the only part of a handset's own finish visible head-on: the
/// brow and chin are black display border on every device in the catalog, so a
/// patch taken anywhere but the edge returns black for a Desert Titanium
/// iPhone as surely as for a Black Titanium one.
///
/// Reading one column of the side inset does not work, and neither does taking
/// its brightest. Profiling an iPhone 14 Pro Max across the 56px inset shows
/// what is actually there: two columns of dark silhouette outline, five of
/// specular chamfer highlight, ten of the rail's own face, then the black
/// display border for the remaining forty. The highlight is what "brightest"
/// finds, and it reports Space Black as #DFDFDF — lighter than Silver's own
/// rail face. A fixed fraction of the inset lands in the border instead and
/// reports Blue and Starlight as the same grey.
///
/// So: drop the columns that are display border — everything near black — and
/// take the median of what is left. The rail face is the widest surviving run
/// on every device, so the median lands on it, and the few highlight columns
/// beside it cannot outvote it.
int? _railColor(
  Uint8List rgba,
  int w,
  int h,
  Map<String, double> body,
  Map<String, dynamic> screen,
) {
  final bodyLeft = body['x']! * w;
  final screenLeft = (screen['x'] as num).toDouble() * w;
  final inset = screenLeft - bodyLeft;
  if (inset < 3) return null;

  final from = bodyLeft.round();
  final to = screenLeft.round();
  // The middle of the body, where no camera bar, key or antenna line reaches.
  final top = ((body['y']! + body['h']! * 0.42) * h).round();
  final bottom = ((body['y']! + body['h']! * 0.58) * h).round();

  final reds = <int>[], greens = <int>[], blues = <int>[];
  for (var x = from; x < to; x++) {
    final r = <int>[], g = <int>[], b = <int>[];
    for (var y = top; y < bottom; y++) {
      final i = (y * w + x) * 4;
      if (rgba[i + 3] < _alphaSolid) continue;
      r.add(rgba[i]);
      g.add(rgba[i + 1]);
      b.add(rgba[i + 2]);
    }
    if (r.isEmpty) continue;
    final cr = _median(r), cg = _median(g), cb = _median(b);
    if (0.2126 * cr + 0.7152 * cg + 0.0722 * cb < _railFloor) continue;
    reds.add(cr.round());
    greens.add(cg.round());
    blues.add(cb.round());
  }
  if (reds.isEmpty) return null;
  return 0xFF000000 |
      (_median(reds).round() << 16) |
      (_median(greens).round() << 8) |
      _median(blues).round();
}

/// The side keys standing proud of [body], as fractions of the canvas.
///
/// A key is a run of rows whose opaque span reaches past the chassis edge.
/// That edge is the *median* span `_bodyRect` found, which is exactly what
/// makes this work: the keys were the minority the median ignored, so what
/// sticks out past it is them and nothing else. Corners sit inside it, and the
/// brow and chin rows are never wider than the body.
List<Map<String, Object>> _keys(
  Uint8List a,
  int w,
  int h,
  Map<String, double> body,
) {
  final left = body['x']! * w;
  final right = (body['x']! + body['w']!) * w;
  final top = (body['y']! * h).ceil();
  final bottom = ((body['y']! + body['h']!) * h).floor();

  final keys = <Map<String, Object>>[];
  for (final side in const ['left', 'right']) {
    final proud = List<double>.filled(h, 0);
    for (var y = top; y < bottom; y++) {
      var first = -1;
      var last = -1;
      for (var x = 0; x < w; x++) {
        if (a[y * w + x] > _alphaEmpty) {
          if (first < 0) first = x;
          last = x;
        }
      }
      if (first < 0) continue;
      proud[y] = side == 'left' ? left - first : last + 1 - right;
    }

    var y = top;
    while (y < bottom) {
      if (proud[y] < _keyMinProud) {
        y++;
        continue;
      }
      final start = y;
      while (y < bottom && proud[y] >= _keyMinProud) {
        y++;
      }
      if (y - start < h * _keyMinLength) continue;
      final run = proud.sublist(start, y)..sort();
      keys.add({
        'side': side,
        'top': _round(start / h),
        'length': _round((y - start) / h),
        // The median, not the peak: a key's rounded ends taper, and one bright
        // anti-aliased pixel is not how far the metal stands out.
        'protrusion': _round(run[run.length ~/ 2] / w),
      });
    }
  }
  return keys;
}

double _round(double v) => (v * 10000).roundToDouble() / 10000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'measure every frame body and cut-out',
    () async {
      final file = File('assets/frames/manifest.json');
      final manifest =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

      for (final device
          in (manifest['devices'] as List).cast<Map<String, dynamic>>()) {
        final asset = (device['variants'] as List).first['asset'] as String;
        if (asset.isEmpty) continue;

        final image = await _rasterise(asset);
        final (_, a, w, h) = await _pixels(image);
        image.dispose();

        final screen = device['screenRect'] as Map<String, dynamic>;
        final body = _bodyRect(a, w, h);
        final cutout = _cutoutRect(
          a,
          w,
          h,
          screen,
          (device['cornerRadiusPct'] as num).toDouble(),
        );

        device['bodyRect'] = body.map((k, v) => MapEntry(k, _round(v)));
        if (cutout == null) {
          device.remove('cutoutRect');
        } else {
          device['cutoutRect'] = cutout.map((k, v) => MapEntry(k, _round(v)));
        }
        // Off the unrounded body, so a key a pixel proud is measured against
        // the edge the median actually found.
        final keys = _keys(a, w, h, body);
        if (keys.isEmpty) {
          device.remove('keys');
        } else {
          device['keys'] = keys;
        }

        // ignore: avoid_print
        print(
          '${device['id']}  body=${body.map((k, v) => MapEntry(k, _round(v)))}  '
          'cutout=${cutout?.map((k, v) => MapEntry(k, _round(v)))}  '
          'keys=${keys.length}',
        );

        // Only the placeholders are repaired. The generated brands carry
        // hand-picked retail colourways that are the point of the variant, and
        // a sampled rail — lit by a specular gradient — is not an improvement
        // on a deliberate #CFA88D "Mystic Bronze".
        for (final variant
            in (device['variants'] as List).cast<Map<String, dynamic>>()) {
          if (variant['frameColor'] != '#000000') continue;
          final v = await _rasterise(variant['asset'] as String);
          final (vRgba, _, vw, vh) = await _pixels(v);
          v.dispose();
          final colour = _railColor(vRgba, vw, vh, body, screen);
          if (colour == null) continue;
          variant['frameColor'] =
              '#${colour.toRadixString(16).substring(2).toUpperCase()}';
          // ignore: avoid_print
          print('    ${variant['id']} -> ${variant['frameColor']}');
        }
      }

      file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
