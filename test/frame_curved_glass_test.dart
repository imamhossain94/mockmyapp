import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';

/// One rasterised frame, plus the colour that was painted underneath it.
class _Render {
  _Render(this.rgba, this.width, this.height, this.behind);

  final ByteData rgba;
  final int width;
  final int height;
  final int behind;

  /// 0-255 luma at a point, so a dark rim and a bright specular can be compared
  /// on one scale.
  int lumaAt(int x, int y) {
    final o = (y * width + x) * 4;
    return (0.2126 * rgba.getUint8(o) +
            0.7152 * rgba.getUint8(o + 1) +
            0.0722 * rgba.getUint8(o + 2))
        .round();
  }
}

/// Rasterises [asset] through the real flutter_svg pipeline, over a flat fill
/// standing in for the user's screenshot.
///
/// Going through `vg.loadPicture` rather than a raw XML parse is the point: it
/// is the same path the app takes, so anything flutter_svg silently drops —
/// `<filter>` famously — shows up here as a missing effect rather than in a
/// user's export.
///
/// Rendered at the artwork's own size, never resampled to a fixed width:
/// scaling puts the left and right aperture edges on different sub-pixel
/// phases whenever the canvas width does not divide evenly, which reads as
/// false asymmetry. The Find X7 Ultra's 790 px canvas forced to 746 was out by
/// 8 luma on artwork that is symmetric by construction.
Future<_Render> _rasterise(String asset, {required Color behind}) async {
  final info = await vg.loadPicture(SvgAssetLoader(asset), null);
  final width = info.size.width.round();
  final height = info.size.height.round();

  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..drawColor(behind, BlendMode.src)
    ..drawPicture(info.picture);
  final picture = recorder.endRecording();

  final image = await picture.toImage(width, height);
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  picture.dispose();
  image.dispose();

  final luma =
      (0.2126 * (behind.r * 255) +
              0.7152 * (behind.g * 255) +
              0.0722 * (behind.b * 255))
          .round();
  return _Render(rgba, width, height, luma);
}

Future<FrameDevice> _device(String id) async {
  final catalog = await loadFrameCatalog();
  return catalog.devices.firstWhere((d) => d.id == id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fill = Color(0xFF808080);

  /// Luma along the horizontal centreline of the display, from the aperture's
  /// left edge to its right edge.
  ///
  /// The first and last few pixels are dropped: that is the anti-aliased seam
  /// where the black bezel meets the aperture, and it is dark on every device,
  /// curved or flat. Sampling it would let any frame pass the "has a dark rim"
  /// check and would fail the flat-panel check for a reason that is a
  /// rasteriser artefact rather than artwork.
  const seam = 3;

  List<int> screenRow(_Render r, FrameDevice device) {
    final rect = device.screenRect;
    final y = ((rect.y + rect.h / 2) * r.height).round();
    final x0 = (rect.x * r.width).round() + seam;
    final x1 = ((rect.x + rect.w) * r.width).round() - seam;
    return [for (var x = x0; x < x1; x++) r.lumaAt(x, y)];
  }

  // Every device that opts into `curved_glass`. Kept as a list rather than one
  // exemplar because the treatment is per-device data, and a device that quietly
  // loses its entry would otherwise still pass a Note-10-only suite.
  const curvedEdged = [
    'samsung-galaxy-note-10',
    'samsung-galaxy-note-10-plus',
    'motorola-edge-50-ultra',
    'oneplus-12',
    'oppo-find-x7-ultra',
    'oppo-find-x8-pro',
    'vivo-x100-ultra',
    'vivo-x200-pro',
    // The narrowest band in the catalogue — OnePlus made the 13's micro-curve
    // the headline difference from the 12 — so if the thresholds below are ever
    // loosened into meaninglessness, this is the device that stops noticing.
    'oneplus-13',
  ];

  for (final id in curvedEdged) {
    group('$id curved edge', () {
      late FrameDevice device;
      late _Render render;

      setUpAll(() async {
        device = await _device(id);
        render = await _rasterise(device.variants.first.asset, behind: fill);
      });

      test('flutter_svg keeps the glass band — both sides carry it', () async {
        final row = screenRow(render, device);
        final band = (row.length * 0.09).round();

        for (final (name, slice) in [
          ('left', row.sublist(0, band)),
          ('right', row.sublist(row.length - band)),
        ]) {
          final darkest = slice.reduce((a, b) => a < b ? a : b);
          final brightest = slice.reduce((a, b) => a > b ? a : b);

          // A curved edge turns away from the light at the rim and swings back
          // through it just inside — one without the other is a painted stripe.
          expect(
            darkest,
            lessThan(render.behind - 25),
            reason: '$name edge has no dark rim (behind=${render.behind})',
          );
          expect(
            brightest,
            greaterThan(render.behind + 12),
            reason: '$name edge has no specular line',
          );
        }
      });

      test('the band stays at the edges — the screenshot is not washed', () {
        final row = screenRow(render, device);
        // The middle 60% must be exactly what was painted underneath.
        final from = (row.length * 0.2).round();
        final to = (row.length * 0.8).round();
        for (var i = from; i < to; i++) {
          expect(
            row[i],
            render.behind,
            reason:
                'glass reaches ${(i / row.length * 100).round()}% across '
                'the display; it must stay near the edges',
          );
        }
      });

      test('the effect is symmetric', () {
        final row = screenRow(render, device);
        final band = (row.length * 0.09).round();
        final left = row.sublist(0, band);
        final right = row.sublist(row.length - band).reversed.toList();

        for (var i = 0; i < band; i++) {
          expect(
            (left[i] - right[i]).abs(),
            lessThanOrEqualTo(6),
            reason: 'left and right edges disagree at offset $i',
          );
        }
      });
    });
  }

  test('a flat-panel device gets no glass at all', () async {
    // The treatment is opt-in. If it ever leaks into the shared path, the S25 —
    // a flat phone — is where it would show up first.
    final s25 = await _device('samsung-galaxy-s25');
    final render = await _rasterise(s25.variants.first.asset, behind: fill);
    final row = screenRow(render, s25);

    for (var i = 0; i < row.length; i++) {
      expect(
        row[i],
        render.behind,
        reason:
            'flat panel is tinted at ${(i / row.length * 100).round()}% '
            'across the display',
      );
    }
  });
}
