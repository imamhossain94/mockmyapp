// Everything on a screen is a component you can point at.
//
// Two of them could not be pointed at before: the artboard was only a place to
// tap to *clear* the selection, and the screenshot could only be reached
// through a tab, which meant the two parts users spend the most time in were
// the two the canvas could not select. Both are now handles like any other, and
// selecting one opens its inspector.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/layer_stack.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FrameCatalog catalog;

  setUpAll(() async {
    catalog = await loadFrameCatalog();
  });

  ScreenDoc doc({int devices = 1}) => ScreenDoc(
    id: 's1',
    canvas: const Size(1200, 2600),
    background: const SolidBackground(Color(0xFFEEEEEE)),
    caption: const CaptionSpec(text: 'Track every workout'),
    frames: [
      for (var i = 0; i < devices; i++)
        FramePlacement(
          deviceId: 'apple-iphone-16',
          variantId: '16---ultramarine',
          screenshot: ScreenshotSpec.of('/shot$i.png'),
        ),
    ],
  );

  group('the selection model', () {
    test('the artboard is a component', () {
      expect(SceneSelection.canvas.handle, SceneHandle.canvas);
      expect(SceneSelection.canvas.toString(), 'canvas');
    });

    test('a screenshot names the device it lives inside', () {
      // Nested, not parallel: a screenshot has no position of its own and
      // belongs to a device the way a caption belongs to a screen.
      const sel = SceneSelection.screenshotAt(2);
      expect(sel.isScreenshot, isTrue);
      expect(sel.deviceIndex, 2);
      expect(sel.toString(), 'screenshot 2');
    });

    test('both handles that name a device report it', () {
      expect(SceneSelection.frameAt(1).deviceIndex, 1);
      expect(SceneSelection.screenshotAt(1).deviceIndex, 1);
      expect(SceneSelection.canvas.deviceIndex, isNull);
      expect(SceneSelection.caption.deviceIndex, isNull);
      expect(SceneSelection.shape(3).deviceIndex, isNull);
    });

    test('a device and its screenshot are different selections', () {
      expect(
        SceneSelection.frameAt(0),
        isNot(equals(const SceneSelection.screenshotAt(0))),
      );
    });
  });

  group('the layers list is the component tree', () {
    test('the screenshot sits directly under its own device', () {
      final rows = LayerStack.of(doc(devices: 2)).rows;
      final frames = <int>[];
      for (var i = 0; i < rows.length; i++) {
        if (rows[i] is FrameLayerRow) frames.add(i);
      }
      for (final at in frames) {
        expect(
          rows[at + 1],
          isA<ScreenshotLayerRow>(),
          reason: 'a device is immediately followed by what is inside it',
        );
        expect(
          (rows[at + 1] as ScreenshotLayerRow).index,
          (rows[at] as FrameLayerRow).index,
          reason: 'and it is that device\'s own picture',
        );
      }
    });

    test('a screen with no device has no screenshot row', () {
      final rows = LayerStack.of(const ScreenDoc(id: 'a')).rows;
      expect(rows.whereType<ScreenshotLayerRow>(), isEmpty);
      expect(
        rows.whereType<FrameLayerRow>(),
        hasLength(1),
        reason: 'the frame row stays as the band boundary',
      );
    });

    test('a screenshot row is not draggable', () {
      // It has no place in the paint order independent of its device.
      final row = LayerStack.of(
        doc(),
      ).rows.whereType<ScreenshotLayerRow>().single;
      expect(row.draggable, isFalse);
    });
  });

  group('on the canvas', () {
    Future<void> pump(
      WidgetTester tester,
      SceneSelection? selected,
      ValueChanged<SceneSelection?> onSelect, {
      int devices = 1,
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
                  doc: doc(devices: devices),
                  catalog: catalog,
                  selected: selected,
                  onSelect: onSelect,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('tapping the artboard selects it rather than nothing', (
      tester,
    ) async {
      SceneSelection? got = SceneSelection.caption;
      await pump(tester, null, (sel) => got = sel);

      // The very top of the canvas is backdrop on any layout.
      await tester.tapAt(const Offset(300, 200));
      await tester.pump();

      expect(got, SceneSelection.canvas);
    });

    testWidgets('the device is marked current for either handle', (
      tester,
    ) async {
      // Drilling into the picture must not look like leaving the device.
      final handle = tester.ensureSemantics();
      await pump(tester, SceneSelection.frameAt(0), (_) {});
      var node = tester.getSemantics(find.bySemanticsLabel('iPhone 16'));
      expect(node.getSemanticsData().flagsCollection.isSelected.name, 'isTrue');

      await pump(tester, const SceneSelection.screenshotAt(0), (_) {});
      node = tester.getSemantics(find.bySemanticsLabel('iPhone 16'));
      expect(node.getSemanticsData().flagsCollection.isSelected.name, 'isTrue');
      handle.dispose();
    });

    testWidgets('only the selected device is marked, not its neighbour', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        const SceneSelection.screenshotAt(1),
        (_) {},
        devices: 2,
      );

      // Both devices are the same phone, so they carry the same label; what
      // tells them apart is which one is flagged.
      final devices = <SemanticsNode>[];
      void walk(SemanticsNode n) {
        if (n.label == 'iPhone 16') devices.add(n);
        n.visitChildren((c) {
          walk(c);
          return true;
        });
      }

      walk(tester.binding.rootElement!.renderObject!.debugSemantics!);
      expect(devices, hasLength(2));
      final flags = devices
          .map((n) => n.getSemanticsData().flagsCollection.isSelected.name)
          .toList();
      expect(
        flags.where((f) => f == 'isTrue'),
        hasLength(1),
        reason: 'exactly one device is current',
      );
      handle.dispose();
    });
  });
}
