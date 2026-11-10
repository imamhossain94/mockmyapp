// Renders turned devices to PNG, for looking at the solid bodies without
// running the app.
//
// Each case is a one-device screen pushed through `SceneRenderer.captureStage`
// — the exporter's own stage, so what lands on disk is what an export would
// ship — with a gradient display fill standing in for a screenshot.
//
// Run from the repo root:
//
//   flutter test tool/render_depth_preview.dart --dart-define=OUT=<dir>
//
// Nothing here is an assertion; the pictures are the output.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/domain/engine/scene_renderer.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

const _out = String.fromEnvironment('OUT', defaultValue: 'build/depth');

/// Renders only the cases whose name contains this, when set — `duo` for
/// the foldables alone.
const _only = String.fromEnvironment('ONLY');

class _Case {
  const _Case(
    this.name,
    this.device,
    this.variant, {
    this.tiltX = 0,
    this.tiltY = 0,
    this.rotation = 0,
    this.depth = const DepthSpec(),
    this.dark = false,
    this.opacity = 1,
    this.design,
  });

  final String name;
  final String device;
  final String variant;
  final double tiltX;
  final double tiltY;
  final double rotation;
  final DepthSpec depth;
  final bool dark;
  final double opacity;
  final FrameDesign? design;
}

const _cases = [
  _Case('iphone_flat', 'apple-iphone-16-pro', '16-pro---natural-titanium'),
  _Case(
    'iphone_left',
    'apple-iphone-16-pro',
    '16-pro---natural-titanium',
    tiltY: -30,
  ),
  _Case(
    'iphone_right',
    'apple-iphone-16-pro',
    '16-pro---natural-titanium',
    tiltY: 30,
  ),
  _Case(
    'iphone_leanback',
    'apple-iphone-16-pro',
    '16-pro---natural-titanium',
    tiltX: 24,
  ),
  _Case(
    'iphone_hero',
    'apple-iphone-16-pro',
    '16-pro---black-titanium',
    tiltX: 10,
    tiltY: -32,
    rotation: -6,
    dark: true,
  ),
  _Case(
    'iphone_iso',
    'apple-iphone-16-pro',
    '16-pro---white-titanium',
    tiltX: 55,
    rotation: 40,
  ),
  _Case(
    'iphone_right_lit',
    'apple-iphone-16-pro',
    '16-pro---natural-titanium',
    tiltY: 30,
    depth: DepthSpec(light: 45),
  ),
  _Case(
    'iphone_glare_flat',
    'apple-iphone-16-pro',
    '16-pro---black-titanium',
    depth: DepthSpec(glare: 0.8),
  ),
  _Case(
    'iphone_glare',
    'apple-iphone-16-pro',
    '16-pro---desert-titanium',
    tiltX: 14,
    tiltY: 24,
    depth: DepthSpec(glare: 0.8),
  ),
  _Case('pixel_right', 'google-pixel-9-pro', 'obsidian', tiltY: 32),
  _Case('s25_left', 'samsung-galaxy-s25', 'navy', tiltY: -32),
  _Case(
    'dynamic_right',
    'studio-iphone-17-pro-max',
    'cosmic-orange',
    tiltY: 30,
    tiltX: 8,
  ),
  _Case('slab_left', 'studio-slab-ios', 'ink', tiltY: -28),
  _Case('ipad_right', 'studio-ipad', 'silver', tiltY: 28),
  _Case('macbook_turn', 'studio-macbook', 'space-black', tiltY: 24),
  // The foldables: shut, open, and open on Android.
  _Case('duo_cover', 'studio-iphone-duo-cover', 'silver'),
  _Case('duo_cover_night', 'studio-iphone-duo-cover', 'black'),
  _Case(
    'duo_cover_turned',
    'studio-iphone-duo-cover',
    'black',
    tiltY: 30,
    tiltX: 8,
  ),
  _Case('duo_open', 'studio-iphone-duo-open', 'silver'),
  _Case(
    'duo_open_turned',
    'studio-iphone-duo-open',
    'black',
    tiltY: -28,
    tiltX: 10,
  ),
  _Case('android_foldable', 'studio-android-foldable', 'navy', tiltY: 26),
  // The corners of the range, where a projection would come apart first.
  _Case(
    'iphone_extreme',
    'apple-iphone-16-pro',
    '16-pro---natural-titanium',
    tiltX: 60,
    tiltY: -60,
  ),
  // Pale finishes, which a light that is too strong turns to plain white.
  _Case(
    's25_silver',
    'samsung-galaxy-s25',
    'silver-shadow',
    tiltX: 12,
    tiltY: 34,
  ),
  _Case(
    'iphone_white_half',
    'apple-iphone-16-pro',
    '16-pro---white-titanium',
    tiltY: -34,
    opacity: 0.5,
  ),
  // A frame the user built, keys on both edges.
  _Case(
    'built_left',
    'studio-custom-ios',
    'design',
    tiltY: -32,
    tiltX: 6,
    design: FrameDesign(
      color: Color(0xFF7A3FD1),
      cornerRadius: 0.12,
      punchHole: PunchHoleSpec(enabled: true),
      power: SideButtonSpec(enabled: true, side: FrameSide.left, top: 0.34),
    ),
  ),
];

void main() {
  // No network under `flutter test`, and nothing here needs the real faces.
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('render turned devices', (tester) async {
    final catalog = (await tester.runAsync(loadFrameCatalog))!;
    Directory(_out).createSync(recursive: true);

    for (final c in _cases) {
      if (_only.isNotEmpty && !c.name.contains(_only)) continue;
      final device = catalog.byId(c.device);
      final variant = device.variants.firstWhere(
        (v) => v.id == c.variant,
        orElse: () => device.variants.first,
      );
      final landscape = device.formFactor == 'desktop';
      // A foldable or a tablet is too wide for a phone's tall canvas: at the
      // same page share it runs off both sides.
      final wide = !landscape && device.frameAspect > 0.62;
      final doc = ScreenDoc(
        id: c.name,
        canvas: landscape
            ? const Size(1600, 1000)
            : wide
            ? const Size(1300, 1500)
            : const Size(800, 1600),
        background: SolidBackground(
          c.dark ? const Color(0xFF15171C) : const Color(0xFFE6E9EF),
        ),
        frames: [
          FramePlacement(
            deviceId: device.id,
            variantId: variant.id,
            transform: Transform2D(
              tiltX: c.tiltX,
              tiltY: c.tiltY,
              rotationDeg: c.rotation,
              pagePercentage: landscape ? 0.6 : 0.72,
            ),
            screenshot: ScreenshotSpec(
              cornerRadiusPct: device.cornerRadiusPct,
              fill: const GradientBackground(
                colorOne: Color(0xFF6A5CFF),
                colorTwo: Color(0xFFFF8A5C),
                midColors: [Color(0xFFE85CFF)],
              ),
            ),
            depth: c.depth,
            opacity: c.opacity,
            design: c.design,
          ),
        ],
      );

      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            // The exporter's own stage, which is only public to tests — and
            // this runs as one.
            // ignore: invalid_use_of_visible_for_testing_member
            child: SceneRenderer.captureStage(
              boundaryKey: key,
              doc: doc,
              catalog: catalog,
            ),
          ),
        ),
      );
      // Artwork decodes off the frame: give it real time, then a frame to
      // paint what arrived.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump();
      }

      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 4);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        File('$_out/${c.name}.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
      // ignore: avoid_print
      print('wrote $_out/${c.name}.png');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
