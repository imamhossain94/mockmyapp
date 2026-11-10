// A locked layer stays where it is — and so does everything under it.
//
// Locking used to hand a layer the treatment a guest from a neighbouring screen
// gets: drawn, and invisible to the pointer. So a drag that started on a locked
// badge sailed straight through it and moved the phone underneath, leaving the
// badge behind — the one thing locking it was meant to prevent.

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

  /// A phone with a big square in front of it, over its middle.
  ScreenDoc doc({required bool locked}) => ScreenDoc(
    id: 's1',
    canvas: const Size(1200, 2600),
    background: const SolidBackground(Color(0xFFEEEEEE)),
    frames: const [
      FramePlacement(
        deviceId: 'apple-iphone-16',
        variantId: '16---ultramarine',
      ),
    ],
    shapes: [
      ShapeSpec.of(
        ShapeKind.rectangle,
      ).copyWith(width: 0.4, height: 0.4, z: kStackOverFrames, locked: locked),
    ],
  );

  final moved = <SceneSelection>[];
  final selectedTargets = <SceneSelection?>[];
  final lockedTaps = <SceneSelection>[];

  Future<void> pump(WidgetTester tester, {required bool locked}) async {
    moved.clear();
    selectedTargets.clear();
    lockedTaps.clear();
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
              height: 866,
              child: SceneView(
                doc: doc(locked: locked),
                catalog: catalog,
                onSelect: selectedTargets.add,
                onTransform: (target, _) => moved.add(target),
                onLockedTap: lockedTaps.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The middle of the scene, which is the middle of the square and of the
  /// phone behind it.
  Offset middle(WidgetTester tester) =>
      tester.getCenter(find.byType(SceneView));

  testWidgets('a drag on a locked layer moves nothing under it', (
    tester,
  ) async {
    await pump(tester, locked: true);
    await tester.dragFrom(middle(tester), const Offset(60, 80));
    await tester.pumpAndSettle();

    expect(moved, isEmpty, reason: 'not the square, and not the phone');
    expect(
      selectedTargets.where((t) => t != null && t.isFrame),
      isEmpty,
      reason: 'the phone under it is not even picked up',
    );
  });

  testWidgets('a tap on a locked layer says so rather than selecting', (
    tester,
  ) async {
    await pump(tester, locked: true);
    await tester.tapAt(middle(tester));
    await tester.pump(const Duration(milliseconds: 400));

    expect(lockedTaps, [SceneSelection.shape(0)]);
    expect(selectedTargets, isEmpty);
  });

  testWidgets('the same layer unlocked is dragged as before', (tester) async {
    await pump(tester, locked: false);
    await tester.dragFrom(middle(tester), const Offset(60, 80));
    await tester.pumpAndSettle();

    expect(moved, isNotEmpty);
    expect(moved.toSet(), {SceneSelection.shape(0)});
    expect(lockedTaps, isEmpty);
  });
}
