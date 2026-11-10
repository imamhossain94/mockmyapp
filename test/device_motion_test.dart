import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/services/video_encoder.dart';
import 'package:mockmyapp/domain/engine/device_motion.dart';
import 'package:mockmyapp/domain/engine/scene_renderer.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

void main() {
  group('motions', () {
    const poses = [
      Transform2D(),
      Transform2D(tiltX: 10, tiltY: -28, rotationDeg: -5),
      Transform2D(offsetPct: Offset(0.1, -0.05), scale: 0.8, rotationDeg: 12),
    ];

    for (final motion in DeviceMotion.values) {
      test('${motion.name} loops without a jump', () {
        for (final base in poses) {
          // Within a hundredth of a degree: `Curves.easeInOutCubic` is a
          // bezier solved to 0.001, which is 0.002 of a degree at the seam —
          // far under what one frame can show.
          final start = motion.at(base, 0);
          final end = motion.at(base, 0.999999);
          expect(end.tiltX, closeTo(start.tiltX, 1e-2));
          expect(end.tiltY, closeTo(start.tiltY, 1e-2));
          expect(end.rotationDeg, closeTo(start.rotationDeg, 1e-2));
          expect(end.offsetPct.dy, closeTo(start.offsetPct.dy, 1e-5));
          // What a motion does not touch, it leaves alone.
          expect(end.scale, base.scale);
          expect(end.align, base.align);
        }
      });
    }

    test('reveal starts face-on and turns to a hero angle', () {
      const flat = Transform2D();
      final start = DeviceMotion.reveal.at(flat, 0);
      expect(start.isTilted, isFalse);
      final held = DeviceMotion.reveal.at(flat, 0.5);
      expect(held.tiltY, -28);
      expect(held.tiltX, 10);
      // A posed device reveals its own pose.
      const posed = Transform2D(tiltX: 5, tiltY: 20);
      expect(DeviceMotion.reveal.at(posed, 0.5).tiltY, 20);
    });

    test('every device on the screen moves', () {
      const doc = ScreenDoc(
        id: 's',
        frames: [
          FramePlacement(deviceId: 'a', variantId: 'x'),
          FramePlacement(
            deviceId: 'b',
            variantId: 'y',
            transform: Transform2D(tiltY: 10),
          ),
        ],
      );
      final moved = DeviceMotion.turn.apply(doc, 0.25);
      expect(moved.frames[0].transform.tiltY, closeTo(24, 1e-9));
      expect(moved.frames[1].transform.tiltY, closeTo(34, 1e-9));
    });
  });

  group('video size', () {
    test('scales the long side down to the request, keeping even sides', () {
      final size = videoSizeFor(const Size(1320, 2868), 1920);
      expect(size.height, 1920);
      expect(size.width.isEven, isTrue);
      expect(size.width, closeTo(884, 2));
    });

    test('never scales up', () {
      final size = videoSizeFor(const Size(1024, 500), 1920);
      expect(size.width, 1024);
      expect(size.height, 500);
    });

    test('a 3:2 search canvas films at 3:2', () {
      final size = videoSizeFor(const Size(3840, 2560), 1920);
      expect(size.width, 1920);
      expect(size.height, 1280);
    });
  });

  group('frames', () {
    test('a frame a pixel too big is cut, one too small is padded', () {
      // 3 x 2, every pixel numbered in its red channel.
      final source = Uint8List.fromList([
        for (var i = 0; i < 6; i++) ...[i, 0, 0, 255],
      ]);
      final cut = fitRgba(source, 3, 2, 2, 2);
      expect(cut.length, 2 * 2 * 4);
      expect([cut[0], cut[4], cut[8], cut[12]], [0, 1, 3, 4]);

      final padded = fitRgba(source, 3, 2, 4, 3);
      expect(padded.length, 4 * 3 * 4);
      // The new column and row are empty.
      expect(padded.sublist(12, 16), [0, 0, 0, 0]);
      expect(padded.sublist(32), everyElement(0));
      // And the same size is handed back untouched.
      expect(identical(fitRgba(source, 3, 2, 3, 2), source), isTrue);
    });

    test(
      'a GIF sink writes a looping GIF, small and slow on purpose',
      () async {
        final sink = GifVideoSink();
        expect(sink.longSideFor(1920), 480);
        expect(sink.fpsFor(30), 10);
        await sink.start(width: 4, height: 4, fps: 10);
        for (var f = 0; f < 3; f++) {
          await sink.add(
            Uint8List.fromList([
              for (var i = 0; i < 16; i++) ...[f * 80, 40, 200, 255],
            ]),
            width: 4,
            height: 4,
          );
        }
        final gif = await sink.finish();
        expect(String.fromCharCodes(gif.sublist(0, 6)), 'GIF89a');
        expect(gif.length, greaterThan(40));
      },
    );
  });
}
