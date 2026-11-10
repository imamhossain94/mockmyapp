// Several devices on one screen — see `ScreenDoc.frames`.
//
// The list has always been a list and `SceneView` has always drawn all of it.
// What was missing was an index: every frame reported the same
// `SceneSelection.frame`, so tapping the second device selected, dragged and
// edited the first, and the layers list showed one row that reached only the
// first. A composition the model supported and the editor could edit a third of.

import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/layer_stack.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:flutter/material.dart';

ScreenDoc docWith(int devices) => ScreenDoc(
  id: 's1',
  canvas: const Size(1200, 2600),
  background: const SolidBackground(Color(0xFF101010)),
  frames: [
    for (var i = 0; i < devices; i++)
      FramePlacement(deviceId: 'device-$i', variantId: 'v'),
  ],
);

void main() {
  group('the selection names which device', () {
    test('two frame selections are not the same selection', () {
      expect(
        SceneSelection.frameAt(0),
        isNot(equals(SceneSelection.frameAt(1))),
      );
    });

    test('the first frame is still the plain constant', () {
      // Most of the app addresses "the frame" and means the only one there is.
      expect(SceneSelection.frameAt(0), SceneSelection.frame);
    });

    test('a frame selection knows it is one', () {
      expect(SceneSelection.frameAt(2).isFrame, isTrue);
      expect(SceneSelection.frameAt(2).isShape, isFalse);
      expect(SceneSelection.caption.isFrame, isFalse);
    });

    test('it says which one when described', () {
      expect(SceneSelection.frameAt(1).toString(), 'frame 1');
      expect(SceneSelection.shape(3).toString(), 'shape 3');
      expect(SceneSelection.caption.toString(), 'caption');
    });
  });

  group('adding and removing devices', () {
    test('a device is added in front', () {
      // `frames` paints in order, so the newest sits on top — which is where
      // someone who just added one is looking for it.
      final doc = docWith(
        1,
      ).addFrame(const FramePlacement(deviceId: 'new', variantId: 'v'));
      expect(doc.frames, hasLength(2));
      expect(doc.frames.last.deviceId, 'new');
    });

    test('removing takes the one named', () {
      final doc = docWith(3).removeFrame(1);
      expect(doc.frames.map((f) => f.deviceId), ['device-0', 'device-2']);
    });

    test('the last device cannot be removed', () {
      // A screen with no frame has no screenshot, no device panel and nothing
      // for the frame tools to edit. Hiding it is what "no phone on this
      // screen" means.
      final doc = docWith(1);
      expect(doc.removeFrame(0).frames, hasLength(1));
    });

    test('an out-of-range removal is a no-op', () {
      expect(docWith(2).removeFrame(5).frames, hasLength(2));
      expect(docWith(2).removeFrame(-1).frames, hasLength(2));
    });

    test('updateFrame edits only the one named', () {
      final doc = docWith(3).updateFrame(1, (f) => f.copyWith(opacity: 0.5));
      expect(doc.frames.map((f) => f.opacity), [1.0, 0.5, 1.0]);
    });
  });

  group('the layers list', () {
    test('shows one row per device, front first', () {
      final rows = LayerStack.of(docWith(3)).rows.whereType<FrameLayerRow>();
      expect(rows, hasLength(3));
      expect(
        rows.map((r) => r.index),
        [2, 1, 0],
        reason: 'front first, like every other band in the list',
      );
    });

    test('a one-device screen still shows exactly one row', () {
      final rows = LayerStack.of(docWith(1)).rows.whereType<FrameLayerRow>();
      expect(rows, hasLength(1));
      expect(rows.single.index, 0);
    });

    test('a screen with no device keeps its boundary row', () {
      // The row is the divider between "behind the device" and "in front of
      // it". Dropping it would take the behind-the-device position with it.
      final rows = LayerStack.of(
        docWith(0),
      ).rows.whereType<FrameLayerRow>().toList();
      expect(rows, hasLength(1));
      expect(rows.single.placement, isNull);
    });

    test('each row carries its own placement', () {
      final doc = docWith(2).updateFrame(0, (f) => f.copyWith(hidden: true));
      final rows = LayerStack.of(doc).rows.whereType<FrameLayerRow>().toList();
      // Front first, so row 0 is frame 1 and row 1 is frame 0.
      expect(rows[0].placement!.hidden, isFalse);
      expect(rows[1].placement!.hidden, isTrue);
    });
  });

  group('a multi-device screen survives a save', () {
    test('every device round-trips, in order', () {
      final doc = docWith(3);
      final back = screenDocFromJson(screenDocToJson(doc));
      expect(back.frames, hasLength(3));
      expect(back.frames.map((f) => f.deviceId), [
        'device-0',
        'device-1',
        'device-2',
      ]);
    });
  });
}
