// Renders every built-in template screen and writes a contact sheet per
// listing into build/shots/templates/.
//
//   flutter test integration_test/template_render_test.dart -d windows
//
// Runs the real engine, so the caption typeface is shaped as a device shapes
// it and the device artwork actually rasterises — neither of which
// `flutter test` can do, and both of which are exactly what a template has to
// be judged on.
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
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

const _shots = 'build/shots/templates';

/// One render's width; the height follows the canvas aspect.
const _tile = 300.0;

final _sheet = GlobalKey();

/// Rasterises the contact sheet itself rather than the window.
///
/// The window and the test surface are independent here: the native window is
/// whatever size the OS gave it, so shooting the render view clipped whole
/// columns away and padded the rest with desktop. A boundary around the content
/// is exactly the content, at any surface size.
Future<void> shoot(WidgetTester tester, String name) async {
  final boundary =
      _sheet.currentContext!.findRenderObject() as RenderRepaintBoundary;
  late final ui.Image image;
  await tester.runAsync(() async {
    image = await boundary.toImage(pixelRatio: 1);
  });
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('$_shots/$name.png')..createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
  print('  shot → ${file.path}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('render every template', (tester) async {
    late FrameCatalog catalog;
    await tester.runAsync(() async {
      catalog = await loadFrameCatalog();
      // The whole point of running here rather than in a widget test.
      await GoogleFonts.pendingFonts();
    });

    // Deliberately the iPhone 6.9" canvas, NOT the 9:16 Play page these were
    // measured against. It is the taller aspect that exposed the device
    // overflowing the page, so it is the one worth rendering.
    const canvas = Size(1320, 2868);
    final sample = ScreenDoc(
      id: 'sample',
      canvas: canvas,
      frames: const [
        FramePlacement(
          deviceId: 'samsung-galaxy-note-10-plus',
          variantId: 'aura-black',
        ),
      ],
      caption: const CaptionSpec(text: 'placeholder'),
    );

    final tileH = _tile / (canvas.width / canvas.height);

    // Set once, and never again. The surface is independent of the OS window,
    // and anything past the window's height lays out but never paints — so a
    // per-template resize produced shots with the tiles hanging off the bottom.
    await tester.binding.setSurfaceSize(const Size(980, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final template in screenTemplates) {
      for (var i = 0; i < template.length; i++) {
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: _sheet,
                child: SizedBox(
                  width: _tile,
                  height: tileH,
                  child: SceneView(
                    doc: template.applyTo(sample, index: i, withCopy: true),
                    catalog: catalog,
                  ),
                ),
              ),
            ),
          ),
        );

        // Let the artwork and the typeface actually arrive before rasterising.
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await tester.pumpAndSettle();
        await shoot(
          tester,
          '${template.id}/${(i + 1).toString().padLeft(2, '0')}',
        );
      }
    }
  });
}
