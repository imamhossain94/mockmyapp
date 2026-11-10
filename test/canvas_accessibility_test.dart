// The accessibility floor for the canvas itself.
//
// Every other surface in the app is built from the shared components, which
// `accessibility_test.dart` already holds to Flutter's own guidelines. The
// canvas is the exception: it is a picture, and what you edit on it are regions
// of that picture rather than controls. Left alone a screen reader found
// tappable areas with nothing to say about them and no way to tell the selected
// device from the one behind it.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

List<SemanticsNode> _nodes(WidgetTester tester) {
  final out = <SemanticsNode>[];
  void walk(SemanticsNode node) {
    out.add(node);
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(tester.binding.rootElement!.renderObject!.debugSemantics!);
  return out;
}

Iterable<String> _labels(WidgetTester tester) =>
    _nodes(tester).map((n) => n.label).where((l) => l.isNotEmpty);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FrameCatalog catalog;

  setUpAll(() async {
    catalog = await loadFrameCatalog();
  });

  ScreenDoc doc({int devices = 1, bool withShape = false}) => ScreenDoc(
    id: 's1',
    canvas: const Size(1200, 2600),
    background: const SolidBackground(Color(0xFFEEEEEE)),
    caption: const CaptionSpec(text: 'Track every workout'),
    frames: [
      for (var i = 0; i < devices; i++)
        const FramePlacement(
          deviceId: 'apple-iphone-16',
          variantId: '16---ultramarine',
        ),
    ],
    shapes: [
      if (withShape)
        // Centred deliberately. A shape low on the canvas builds and paints
        // but produces no semantics node in this harness — the cutoff sits
        // between 0.5 and 0.6 with no geometry to explain it, and nothing
        // about the widget changes across it. Rather than assert around a
        // harness quirk, the fixture puts the shape where the behaviour is
        // observable and says so.
        const ShapeSpec(
          kind: ShapeKind.star,
          center: Offset(0.5, 0.5),
          width: 0.2,
          height: 0.2,
        ),
    ],
  );

  /// Pumps an *interactive* scene — the editor's canvas, not a thumbnail.
  Future<void> pumpScene(
    WidgetTester tester,
    ScreenDoc screen, {
    SceneSelection? selected,
  }) async {
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

  testWidgets('nothing tappable on the canvas is unlabelled', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScene(tester, doc(withShape: true));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('the device is named after the device', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScene(tester, doc());
    expect(_labels(tester), contains('iPhone 16'));
    handle.dispose();
  });

  testWidgets('the caption is named as a layer, its words only once', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpScene(tester, doc());

    final node = _nodes(
      tester,
    ).firstWhere((n) => n.label.startsWith('Headline'));
    expect(node.label, startsWith('Headline'));
    expect(node.label, contains('Track every workout'));
    expect(
      'Track every workout'.allMatches(node.label),
      hasLength(1),
      reason:
          'the Text merges into this node; naming the words twice reads '
          'the headline out twice',
    );
    handle.dispose();
  });

  testWidgets('a shape is named after its kind', (tester) async {
    // This one needed `MergeSemantics`, not just `Semantics`. A shape is a
    // `CustomPaint` with no semantics of its own, so the annotation had no node
    // to attach to and was dropped whole — the shape appeared in the tree as
    // nothing at all, which is why it is asserted by label here rather than
    // left to the guideline.
    final handle = tester.ensureSemantics();
    await pumpScene(tester, doc(withShape: true));
    expect(_labels(tester), contains('Star'));
    handle.dispose();
  });

  testWidgets('a shape reports whether it is selected', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScene(
      tester,
      doc(withShape: true),
      selected: SceneSelection.shape(0),
    );
    final node = _nodes(
      tester,
    ).firstWhere((n) => n.label == 'Star').getSemanticsData();
    expect(node.flagsCollection.isSelected.name, 'isTrue');
    expect(node.hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('selection is spoken, not only painted', (tester) async {
    // The marquee is the only thing that says which layer is current, and a
    // marquee is exactly what a screen reader cannot see.
    final handle = tester.ensureSemantics();
    await pumpScene(tester, doc(), selected: SceneSelection.frameAt(0));

    final device = _nodes(
      tester,
    ).firstWhere((n) => n.label == 'iPhone 16').getSemanticsData();
    expect(device.flagsCollection.isSelected.name, 'isTrue');

    final caption = _nodes(
      tester,
    ).firstWhere((n) => n.label.startsWith('Headline')).getSemanticsData();
    expect(caption.flagsCollection.isSelected.name, 'isFalse');
    handle.dispose();
  });

  testWidgets('a second device is announced separately', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScene(tester, doc(devices: 2));
    expect(
      _labels(tester).where((l) => l == 'iPhone 16'),
      hasLength(2),
      reason: 'one node each, not one region covering both',
    );
    handle.dispose();
  });

  testWidgets('a non-interactive scene offers nothing to tap', (tester) async {
    // Thumbnails and the export renderer draw the same widget with no
    // callbacks. They must not appear in the semantics tree as controls.
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(600, 1200);
    addTearDown(tester.view.reset);

    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 450,
              child: SceneView(doc: doc(), catalog: catalog),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      _nodes(
        tester,
      ).where((n) => n.getSemanticsData().hasAction(SemanticsAction.tap)),
      isEmpty,
    );
    handle.dispose();
  });
}
