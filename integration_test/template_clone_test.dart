// Renders one listing's template at the exact size its reference screenshots
// were published at, so the clone can be diffed against the original.
//
//   flutter test integration_test/template_clone_test.dart -d windows
//   python tool/diff_template_clone.py sonary
//
// Distinct from `template_render_test.dart`, which renders every template on
// the *iPhone* canvas to prove the geometry survives a change of aspect. This
// one renders on the 1080x1920 Play page and nothing else, because a diff is
// only meaningful against the page the reference was measured on.
//
// Which template it renders comes from `--dart-define=slug=`, defaulting to
// the one being calibrated.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/assets/template_catalog.dart';
import 'package:mockmyapp/domain/engine/scene_renderer.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/screen_template.dart';

const _out = 'build/shots/clone';
const _slug = String.fromEnvironment('slug', defaultValue: 'sonary');

/// The Play page the reference screenshots are published at.
const _page = Size(1080, 1920);

/// What the surface can actually paint. Rendering at 1080x1920 directly would
/// run off the bottom of the OS window and come back half blank, so the scene
/// is laid out at the page's own aspect at a size that fits and scaled up in
/// the capture.
const _tile = Size(450, 800);

final _key = GlobalKey();

const _pixelRatio = 1080 / 450;

/// The banner, laid out at its own aspect and captured at 1024 wide.
const _bannerTile = Size(800, 800 * 500 / 1024);

/// A desktop or web page, captured at 1280 wide.
const _wideTile = Size(800, 800 * 800 / 1280);

Future<void> shoot(
  WidgetTester tester,
  String name, {
  required String slug,
  double pixelRatio = _pixelRatio,
}) async {
  final boundary =
      _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  late final ui.Image image;
  await tester.runAsync(() async {
    // Captured at the page's own resolution: the diff compares glyph edges and
    // a bezel a couple of pixels wide, and neither survives a downscale.
    image = await boundary.toImage(pixelRatio: pixelRatio);
  });
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('$_out/$slug/$name.png')..createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
  print('  shot -> ${file.path}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A comma-separated list renders several templates in one launch — the
  // whole shelf of originals, say — rather than one app start per template.
  for (final slug in _slug.split(',')) {
    testWidgets('render $slug against its reference page', (tester) async {
      late FrameCatalog catalog;
      await tester.runAsync(() async {
        catalog = await loadFrameCatalog();
        await GoogleFonts.pendingFonts();
      });

      final template = screenTemplates.firstWhere((t) => t.id == slug);
      final sample = ScreenDoc(
        id: 'sample',
        canvas: _page,
        frames: const [
          FramePlacement(
            deviceId: 'samsung-galaxy-note-10-plus',
            variantId: 'aura-black',
          ),
        ],
        caption: const CaptionSpec(text: 'placeholder'),
      );

      await tester.binding.setSurfaceSize(const Size(900, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (var i = 0; i < template.length; i++) {
        final doc = template.applyTo(
          sample,
          index: i,
          withCopy: true,
          withDisplay: true,
        );
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: _key,
                child: SizedBox(
                  width: _tile.width,
                  height: _tile.height,
                  child: SceneView(doc: doc, catalog: catalog),
                ),
              ),
            ),
          ),
        );
        // The display artwork is a bundled asset and the headline is a Google
        // font; an undecoded one of either rasterises as a blank screen or as
        // Roboto, and both would read as a geometry error in the diff.
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => SceneRenderer.precacheAssets(_key.currentContext!, doc),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pumpAndSettle();
        await shoot(tester, (i + 1).toString().padLeft(2, '0'), slug: slug);
      }

      // Its landscape designs — a Mac, Windows or web shot — on a page of
      // that shape, in whatever frame the target wears.
      for (final (i, _) in template.landscapeScreens.indexed) {
        final doc = template.applyTo(
          landscapeSample(sample),
          index: i,
          withCopy: true,
          withDisplay: true,
          banner: false,
        );
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: _key,
                child: SizedBox(
                  width: _wideTile.width,
                  height: _wideTile.height,
                  child: SceneView(doc: doc, catalog: catalog),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => SceneRenderer.precacheAssets(_key.currentContext!, doc),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pumpAndSettle();
        await shoot(
          tester,
          'w${i + 1}',
          slug: slug,
          pixelRatio: 1280 / _wideTile.width,
        );
      }

      // And its feature graphic, when it has one.
      if (template.featureGraphic != null) {
        final doc = template.applyTo(
          featureGraphicSample(sample),
          withCopy: true,
          withDisplay: true,
        );
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: _key,
                child: SizedBox(
                  width: _bannerTile.width,
                  height: _bannerTile.height,
                  child: SceneView(doc: doc, catalog: catalog),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => SceneRenderer.precacheAssets(_key.currentContext!, doc),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pumpAndSettle();
        await shoot(
          tester,
          'fg',
          slug: slug,
          pixelRatio: 1024 / _bannerTile.width,
        );
      }
    });
  }
}
