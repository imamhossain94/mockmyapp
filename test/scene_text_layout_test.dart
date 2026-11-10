import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

/// The shipped frame manifest, read straight off disk — see
/// `screens_smoke_test.dart` for why this is not `rootBundle`.
final FrameCatalog catalog = frameCatalogFromManifest(
  jsonDecode(File('assets/frames/manifest.json').readAsStringSync())
      as Map<String, dynamic>,
);

/// A document whose caption is long enough that where it breaks is decided by
/// the width it is measured at — which is the whole point.
ScreenDoc docWith(String text) {
  final device = catalog.devices.first;
  return ScreenDoc(
    id: 'test',
    canvas: const Size(1284, 2778),
    background: const SolidBackground(Color(0xFF1E1F22)),
    caption: CaptionSpec(text: text, size: 64, lineHeight: 74),
    frames: [
      FramePlacement(deviceId: device.id, variantId: device.variants.first.id),
    ],
  );
}

/// How the caption came out: the lines it broke into, and the width it was
/// measured against in its own coordinate space.
typedef CaptionLayout = ({int lines, double measuredWidth});

/// Pumps [doc] into a box [width] wide and reports how the caption laid out.
Future<CaptionLayout> captionLayout(
  WidgetTester tester,
  ScreenDoc doc,
  double width,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [frameCatalogProvider.overrideWith((ref) => catalog)],
      child: MaterialApp(
        theme: StudioAppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: width / (doc.canvas.width / doc.canvas.height),
              child: SceneView(doc: doc, catalog: catalog),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }

  final paragraphs = tester
      .renderObjectList<RenderParagraph>(find.byType(RichText))
      .where((p) => p.text.toPlainText().contains('headline'))
      .toList();
  expect(paragraphs, isNotEmpty, reason: 'the caption is on the canvas');

  // Distinct box tops across the whole run is the line count.
  final paragraph = paragraphs.first;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: paragraph.text.toPlainText().length,
    ),
  );
  return (
    lines: boxes.map((b) => b.top.round()).toSet().length,
    measuredWidth: paragraph.size.width,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a caption breaks the same way at every display size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Long enough to wrap, and close enough to the edge that a few pixels of
    // rounding decide it.
    final doc = docWith('A rather long store headline that has to wrap');

    // Laying the scene out at display size with a proportionally scaled font
    // *looks* equivalent and is not: glyph advances round to the pixel, so the
    // same caption fitted one line in a big preview and two in a small one.
    final big = await captionLayout(tester, doc, 1000);
    final medium = await captionLayout(tester, doc, 500);
    final small = await captionLayout(tester, doc, 220);

    expect(big.lines, greaterThan(1), reason: 'the caption really does wrap');
    expect(medium.lines, big.lines, reason: '500dp breaks where 1000dp does');
    expect(small.lines, big.lines, reason: '220dp breaks where 1000dp does');

    // The assertion that does not depend on the test font. A widget test lays
    // out in Ahem, whose advances scale perfectly linearly, so counting lines
    // alone could pass even with the old display-space layout. This says the
    // text was measured against the *document* — the same measure at every
    // display size — which is the property that makes the line count stable
    // with a real font, and makes the editor agree with the export.
    expect(big.measuredWidth, closeTo(medium.measuredWidth, 0.01));
    expect(big.measuredWidth, closeTo(small.measuredWidth, 0.01));
    expect(
      big.measuredWidth,
      greaterThan(1000),
      reason: 'measured in canvas pixels, not in the 220–1000dp box',
    );
  });

  testWidgets('and a single-line caption stays on one line everywhere', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final doc = docWith('Short headline');

    expect((await captionLayout(tester, doc, 1000)).lines, 1);
    expect((await captionLayout(tester, doc, 220)).lines, 1);
  });

  testWidgets('the scene still fills the box it is given', (tester) async {
    tester.view.physicalSize = const Size(2400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final doc = docWith('Short headline');
    await captionLayout(tester, doc, 400);

    // Rendering at canvas resolution and scaling must not change what the
    // scene occupies on screen — the exporter and the thumbnails have always
    // worked this way, and the editor now matches them.
    final clip = tester.getRect(
      find
          .descendant(
            of: find.byType(SceneView),
            matching: find.byType(ClipRect),
          )
          .first,
    );
    expect(clip.width, closeTo(400, 0.5));
    expect(
      clip.height,
      closeTo(400 / (doc.canvas.width / doc.canvas.height), 0.5),
    );
  });
}
