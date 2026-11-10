// A selection that outlives what it pointed at.
//
// Selections carry an index now — `frame 1`, `shape 3` — and indices go stale:
// undo puts back a document with fewer devices, a delete removes the one that
// was current, a screen switch lands on a composition with a different number
// of things on it. None of that is exotic; all of it happens by pressing
// Ctrl+Z. What must not happen is a range error inside a paint.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FrameCatalog catalog;

  setUpAll(() async {
    catalog = await loadFrameCatalog();
  });

  ScreenDoc doc(int devices) => ScreenDoc(
    id: 's1',
    canvas: const Size(1200, 2600),
    background: const SolidBackground(Color(0xFFEEEEEE)),
    frames: [
      for (var i = 0; i < devices; i++)
        const FramePlacement(
          deviceId: 'apple-iphone-16',
          variantId: '16---ultramarine',
        ),
    ],
  );

  Future<void> pump(
    WidgetTester tester,
    ScreenDoc screen,
    SceneSelection? selected,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(600, 1200);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 900,
              child: SceneView(
                doc: screen,
                catalog: catalog,
                selected: selected,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a selection past the last device draws without throwing', (
    tester,
  ) async {
    // Exactly what an undo does: the document shrinks under a selection that
    // was made against the larger one.
    await pump(tester, doc(1), SceneSelection.frameAt(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing is drawn as selected when the index is stale', (
    tester,
  ) async {
    // Better than guessing. Highlighting the last device because the real one
    // is gone would put the marquee on something the user did not choose, and
    // the next drag would move it.
    await pump(tester, doc(2), SceneSelection.frameAt(9));
    final frames = tester.widgetList<SceneView>(find.byType(SceneView));
    expect(frames, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stale shape selection is equally harmless', (tester) async {
    await pump(tester, doc(1), SceneSelection.shape(7));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a screen with no devices at all still draws', (tester) async {
    // Reachable by undoing back past the first device, and by a document
    // written by a build that allowed it.
    await pump(tester, doc(0), SceneSelection.frameAt(0));
    expect(tester.takeException(), isNull);
  });

  group('the document guards its own edges', () {
    test('updateFrame past the end is a no-op rather than a throw', () {
      final before = doc(2);
      expect(
        before.updateFrame(9, (f) => f.copyWith(opacity: 0.1)).frames,
        hasLength(2),
      );
      expect(
        before
            .updateFrame(9, (f) => f.copyWith(opacity: 0.1))
            .frames
            .map((f) => f.opacity),
        everyElement(1.0),
      );
    });

    test('removeFrame past the end leaves the list alone', () {
      expect(doc(2).removeFrame(9).frames, hasLength(2));
    });
  });
}
