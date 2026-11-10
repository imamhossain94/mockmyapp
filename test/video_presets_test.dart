import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/services/video_encoder.dart';
import 'package:mockmyapp/domain/engine/continuous.dart';
import 'package:mockmyapp/domain/engine/device_motion.dart';
import 'package:mockmyapp/domain/engine/scene_renderer.dart';
import 'package:mockmyapp/domain/engine/video_frame_view.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/domain/providers/video_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App Store Connect's accepted preview sizes (checked 2026-10-02) and Play's
/// 1080p, portrait then landscape; null where the slot has no portrait.
const _specs = {
  VideoPreset.appStoreIphone: ((886, 1920), (1920, 886)),
  VideoPreset.appStoreIphone55: ((1080, 1920), (1920, 1080)),
  VideoPreset.appStoreIpad: ((1200, 1600), (1600, 1200)),
  VideoPreset.appStoreMacTv: (null, (1920, 1080)),
  VideoPreset.appStoreVisionPro: (null, (3840, 2160)),
  VideoPreset.playPromo: ((1080, 1920), (1920, 1080)),
};

void main() {
  group('preset sizes', () {
    test('every preset is listed, with its exact sizes', () {
      expect(_specs.keys.toSet(), VideoPreset.values.toSet());
    });

    // Every canvas any target offers, in every preset: the frame is always
    // the store's exact size, never the canvas scaled — so the 1320 × 2868
    // canvas that used to film at 884 × 1920 now films at 886 × 1920.
    final canvases = {
      for (final target in StoreTargets.all)
        for (final preset in target.presets) preset.size,
    };
    for (final preset in VideoPreset.values) {
      test('${preset.name} is exact for every canvas', () {
        final (portrait, landscape) = _specs[preset]!;
        for (final canvas in canvases) {
          final size = preset.sizeFor(canvas);
          final wide = canvas.width > canvas.height;
          final want = wide || portrait == null ? landscape : portrait;
          expect((size.width, size.height), want, reason: '$canvas');
          final layout = VideoSettings(preset: preset).layoutFor(canvas);
          expect((layout.width, layout.height), want, reason: '$canvas');
        }
      });
    }

    test('the iPhone default films at 886 × 1920, not 884', () {
      const canvas = Size(1320, 2868);
      expect(videoSizeFor(canvas, 1920), (width: 884, height: 1920));
      final layout = const VideoSettings(
        preset: VideoPreset.appStoreIphone,
      ).layoutFor(canvas);
      expect((layout.width, layout.height), (886, 1920));
    });

    test('a free-size clip is still its canvas scaled, filling the frame', () {
      final layout = const VideoSettings().layoutFor(const Size(1320, 2868));
      expect((layout.width, layout.height), (884, 1920));
      expect(layout.canvasRect, const Rect.fromLTWH(0, 0, 884, 1920));
      // Held to the encoder's own limit.
      final capped = const VideoSettings(
        longSide: 3840,
      ).layoutFor(const Size(3840, 2160), maxLongSide: 1920);
      expect((capped.width, capped.height), (1920, 1080));
    });
  });

  group('letterbox and crop', () {
    void expectFit(
      Size canvas,
      int w,
      int h,
      VideoFit fit, {
      required Rect expected,
    }) {
      final r = fitCanvas(canvas, w, h, fit);
      expect(r.left, closeTo(expected.left, 0.01));
      expect(r.top, closeTo(expected.top, 0.01));
      expect(r.width, closeTo(expected.width, 0.01));
      expect(r.height, closeTo(expected.height, 0.01));
    }

    test('a 6.9" canvas in 886 × 1920', () {
      const canvas = Size(1320, 2868);
      // Height-bound: 1920 / 2868 of 1320 is 883.68 wide, 1.16 each side.
      expectFit(
        canvas,
        886,
        1920,
        VideoFit.letterbox,
        expected: const Rect.fromLTWH(1.16, 0, 883.68, 1920),
      );
      // Width-bound: 886 / 1320 of 2868 is 1925.04 tall, 2.52 off each end.
      expectFit(
        canvas,
        886,
        1920,
        VideoFit.crop,
        expected: const Rect.fromLTWH(0, -2.52, 886, 1925.036),
      );
    });

    test('a 16:10 Mac canvas in 1920 × 1080', () {
      const canvas = Size(2880, 1800);
      expectFit(
        canvas,
        1920,
        1080,
        VideoFit.letterbox,
        expected: const Rect.fromLTWH(96, 0, 1728, 1080),
      );
      expectFit(
        canvas,
        1920,
        1080,
        VideoFit.crop,
        expected: const Rect.fromLTWH(0, -60, 1920, 1200),
      );
    });

    test('a 3:4 iPad canvas fits 1200 × 1600 exactly either way', () {
      for (final fit in VideoFit.values) {
        expectFit(
          const Size(2064, 2752),
          1200,
          1600,
          fit,
          expected: const Rect.fromLTWH(0, 0, 1200, 1600),
        );
      }
    });

    test('a 9:20 Android canvas in the Play promo 1080 × 1920', () {
      const canvas = Size(1080, 2400);
      expectFit(
        canvas,
        1080,
        1920,
        VideoFit.letterbox,
        expected: const Rect.fromLTWH(108, 0, 864, 1920),
      );
      expectFit(
        canvas,
        1080,
        1920,
        VideoFit.crop,
        expected: const Rect.fromLTWH(0, -240, 1080, 2400),
      );
    });

    test('for every canvas: centred, in proportion, inside or covering', () {
      final canvases = {
        for (final target in StoreTargets.all)
          for (final preset in target.presets) preset.size,
      };
      for (final preset in VideoPreset.values) {
        for (final canvas in canvases) {
          final (:width, :height) = preset.sizeFor(canvas);
          final box = fitCanvas(canvas, width, height, VideoFit.letterbox);
          final cut = fitCanvas(canvas, width, height, VideoFit.crop);
          for (final r in [box, cut]) {
            expect(r.center.dx, closeTo(width / 2, 1e-6));
            expect(r.center.dy, closeTo(height / 2, 1e-6));
            expect(
              r.width / r.height,
              closeTo(canvas.width / canvas.height, 1e-9),
            );
          }
          // Letterboxed: inside the frame, touching two opposite edges.
          expect(box.left, greaterThanOrEqualTo(-1e-6));
          expect(box.top, greaterThanOrEqualTo(-1e-6));
          expect(
            (box.width - width).abs() < 1e-6 ||
                (box.height - height).abs() < 1e-6,
            isTrue,
          );
          // Cropped: covering the frame, touching two opposite edges.
          expect(cut.left, lessThanOrEqualTo(1e-6));
          expect(cut.top, lessThanOrEqualTo(1e-6));
          expect(
            (cut.width - width).abs() < 1e-6 ||
                (cut.height - height).abs() < 1e-6,
            isTrue,
          );
        }
      }
    });

    test("the bars take the page's background colour", () {
      expect(
        letterboxColorFor(const SolidBackground(Color(0xFF123456))),
        const Color(0xFF123456),
      );
      final blend = letterboxColorFor(
        const GradientBackground(
          colorOne: Color(0xFF000000),
          colorTwo: Color(0xFFFFFFFF),
        ),
      );
      expect(blend.r, closeTo(0.5, 1e-6));
      expect(blend.a, 1.0);
      expect(
        letterboxColorFor(
          const PatternBackground(
            style: PatternStyle.mesh,
            colors: [Color(0xFF0A0B0C), Color(0xFFFFFFFF)],
          ),
        ),
        const Color(0xFF0A0B0C),
        reason: 'the base fill',
      );
      expect(
        letterboxColorFor(const ImageBackground('a.png')),
        const Color(0xFF000000),
      );
      final layout = const VideoSettings(preset: VideoPreset.appStoreMacTv)
          .layoutFor(
            const Size(2880, 1800),
            background: const SolidBackground(Color(0xFF5B5FEF)),
          );
      expect(layout.bars, const Color(0xFF5B5FEF));
    });
  });

  group('which App Store slot a set is filmed for', () {
    VideoPreset forTarget(String id, {int preset = 0}) {
      final target = StoreTargets.byId(id)!;
      return VideoPreset.appStoreFor(target, target.presets[preset].size);
    }

    test('the set names it, where it is an Apple device class', () {
      expect(forTarget('ios-iphone'), VideoPreset.appStoreIphone);
      expect(forTarget('ios-ipad'), VideoPreset.appStoreIpad);
      expect(forTarget('mac'), VideoPreset.appStoreMacTv);
      expect(forTarget('apple-tv'), VideoPreset.appStoreMacTv);
      expect(forTarget('vision-pro'), VideoPreset.appStoreVisionPro);
      expect(forTarget('ios-iphone-duo-inner'), VideoPreset.appStoreIphone);
    });

    test('otherwise the nearest proportions, upright for an upright set', () {
      // The 5.5" canvas is 16:9.
      final iphone = StoreTargets.byId('ios-iphone')!;
      final five = iphone.presets.firstWhere((p) => p.id == 'iphone-5-5');
      expect(
        VideoPreset.appStoreFor(iphone, five.size),
        VideoPreset.appStoreIphone55,
      );
      expect(
        VideoPreset.appStoreFor(null, const Size(1080, 1920)),
        VideoPreset.appStoreIphone55,
      );
      expect(
        VideoPreset.appStoreFor(null, const Size(1200, 1600)),
        VideoPreset.appStoreIpad,
      );
      // Never a landscape-only slot for an upright canvas.
      expect(
        VideoPreset.appStoreFor(null, const Size(1000, 1000)).landscapeOnly,
        isFalse,
      );
    });
  });

  group('length, frame rate, bitrate and sound', () {
    test('an App Store preview runs 15 to 30 s at 30 fps at most', () {
      const preview = VideoSettings(
        preset: VideoPreset.appStoreIphone,
        seconds: 6,
        fps: 60,
      );
      expect(preview.clipSeconds, 15);
      expect(preview.clipFps, 30);
      expect(preview.frameCount, 450);
      expect(preview.copyWith(seconds: 45).clipSeconds, 30);
      expect(preview.normalized.seconds, 15);
      expect(preview.normalized.fps, 30);
      for (final seconds in VideoPurpose.appStore.lengths) {
        expect(seconds, inInclusiveRange(15, 30));
      }
    });

    test('a social clip or a Play promo keeps its length and rate', () {
      const social = VideoSettings(seconds: 6, fps: 60);
      expect(social.clipSeconds, 6);
      expect(social.clipFps, 60);
      expect(identical(social.normalized, social), isTrue);
      const play = VideoSettings(preset: VideoPreset.playPromo, fps: 60);
      expect(play.clipFps, 60);
      expect(const VideoSettings(fps: 240).clipFps, 60);
    });

    test('a store preset is encoded at 10 to 12 Mbit/s', () {
      for (final preset in VideoPreset.values) {
        final s = VideoSettings(preset: preset);
        for (final canvas in const [Size(1320, 2868), Size(2880, 1800)]) {
          final layout = s.layoutFor(canvas);
          final rate = s.bitrateFor(layout.width, layout.height, s.clipFps);
          expect(rate, inInclusiveRange(10000000, 12000000), reason: '$preset');
        }
      }
      // A free-size clip keeps the old rate: 0.12 bits a pixel a frame.
      expect(const VideoSettings().bitrateFor(886, 1920, 30), 6124032);
      expect(const VideoSettings().bitrateFor(320, 240, 10), 2000000);
    });

    test('the silent track is on for the presets and off for social', () {
      expect(const VideoSettings().wantsAudio, isFalse);
      for (final preset in VideoPreset.values) {
        expect(VideoSettings(preset: preset).wantsAudio, isTrue);
      }
      expect(
        const VideoSettings(
          preset: VideoPreset.playPromo,
          audio: false,
        ).wantsAudio,
        isFalse,
      );
      expect(const VideoSettings(audio: true).wantsAudio, isTrue);
      expect(
        const VideoSettings(audio: true).copyWith(resetAudio: true).audio,
        isNull,
      );
    });

    test('the silence ends three AAC frames or more before the picture', () {
      for (final (frames, fps) in [(450, 30), (900, 30), (720, 24), (45, 30)]) {
        final samples = silentSamplesFor(frames, fps);
        expect(samples % 1024, 0);
        final short = frames * 48000 / fps - samples;
        expect(short, greaterThanOrEqualTo(3 * 1024), reason: '$frames@$fps');
        expect(short, lessThan(4 * 1024), reason: '$frames@$fps');
      }
      expect(silentSamplesFor(900, 30), 1403 * 1024);
      expect(silentSamplesFor(0, 30), 0);
      expect(silentSamplesFor(2, 30), 0, reason: 'too short for any');
      expect(silentSamplesFor(3, 30), 1024);
    });
  });

  group('saved settings', () {
    const examples = [
      VideoSettings(),
      VideoSettings(motion: DeviceMotion.orbit, seconds: 15, longSide: 1280),
      VideoSettings(preset: VideoPreset.appStoreIpad, seconds: 20),
      VideoSettings(
        preset: VideoPreset.appStoreVisionPro,
        fit: VideoFit.crop,
        audio: false,
        seconds: 30,
      ),
      VideoSettings(preset: VideoPreset.playPromo, audio: true, fps: 60),
      VideoSettings(motion: DeviceMotion.float, audio: true),
    ];

    test('every setting reads back as it was written', () {
      for (final s in examples) {
        final raw = jsonEncode(s.toJson());
        final back = VideoSettings.fromJson(
          (jsonDecode(raw) as Map).cast<String, Object?>(),
        );
        expect(back, s, reason: raw);
        expect(jsonEncode(back.toJson()), raw, reason: 'byte for byte');
      }
    });

    test('settings without presets are the four fields they always were', () {
      const raw = '{"motion":"reveal","seconds":10,"fps":30,"longSide":1920}';
      final s = VideoSettings.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
      expect(s.preset, isNull);
      expect(s.fit, VideoFit.letterbox);
      expect(s.audio, isNull);
      expect(jsonEncode(s.toJson()), raw);
    });

    test('anything unreadable falls back to its default', () {
      final s = VideoSettings.fromJson({
        'motion': 'spin',
        'seconds': 900,
        'fps': 'thirty',
        'longSide': -1,
        'preset': 'appStoreWatch',
        'fit': 'stretch',
        'audio': 'yes',
      });
      expect(s, const VideoSettings());
    });

    test('remembered between launches, through the preferences', () async {
      SharedPreferences.setMockInitialValues({});
      final first = ProviderContainer();
      addTearDown(first.dispose);
      const chosen = VideoSettings(
        preset: VideoPreset.appStoreIphone,
        seconds: 25,
        fit: VideoFit.crop,
      );
      await first.read(videoSettingsProvider.notifier).settled();
      await first.read(videoSettingsProvider.notifier).set(chosen);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(VideoSettingsNotifier.storageKey),
        jsonEncode(chosen.toJson()),
      );

      final second = ProviderContainer();
      addTearDown(second.dispose);
      expect(
        await second.read(videoSettingsProvider.notifier).settled(),
        chosen,
      );
    });

    test('a store that cannot be read leaves the defaults', () async {
      final open = VideoSettingsNotifier.openStore;
      VideoSettingsNotifier.openStore = () async => throw StateError('no');
      addTearDown(() => VideoSettingsNotifier.openStore = open);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        await container.read(videoSettingsProvider.notifier).settled(),
        const VideoSettings(),
      );
      // And a choice still holds for the session.
      await container
          .read(videoSettingsProvider.notifier)
          .set(const VideoSettings(seconds: 30));
      expect(container.read(videoSettingsProvider).seconds, 30);
    });
  });

  group('a filmed frame', () {
    // A red 100 × 100 canvas in a 120 × 80 frame: letterboxed it sits in the
    // middle 80 px with green bars either side; cropped it fills the frame.
    const doc = ScreenDoc(
      id: 's',
      canvas: Size(100, 100),
      background: SolidBackground(Color(0xFFFF0000)),
    );

    Future<Uint8List> capture(
      WidgetTester tester,
      VideoFrameLayout layout, {
      ThemeData? theme,
    }) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: VideoFrameView(
                composed: ComposedScreen.alone(doc),
                catalog: const FrameCatalog([]),
                layout: layout,
                forExport: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final bytes = await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      return bytes!;
    }

    List<int> at(Uint8List rgba, int x, int y) =>
        rgba.sublist((y * 120 + x) * 4, (y * 120 + x) * 4 + 3);

    VideoFrameLayout layout(VideoFit fit) => VideoFrameLayout(
      width: 120,
      height: 80,
      canvasRect: fitCanvas(doc.canvas, 120, 80, fit),
      bars: const Color(0xFF00FF00),
    );

    testWidgets('letterboxed: bars either side, the canvas between', (
      tester,
    ) async {
      final rgba = await capture(tester, layout(VideoFit.letterbox));
      expect(rgba.length, 120 * 80 * 4);
      expect(at(rgba, 8, 40), [0, 255, 0], reason: 'left bar');
      expect(at(rgba, 60, 40), [255, 0, 0], reason: 'canvas');
      expect(at(rgba, 111, 40), [0, 255, 0], reason: 'right bar');
    });

    testWidgets('cropped: the canvas fills the frame', (tester) async {
      final rgba = await capture(tester, layout(VideoFit.crop));
      for (final (x, y) in [(1, 1), (60, 40), (118, 78)]) {
        expect(at(rgba, x, y), [255, 0, 0], reason: '($x, $y)');
      }
    });

    testWidgets('the same in the dark theme as in the light, byte for byte', (
      tester,
    ) async {
      final dark = await capture(
        tester,
        layout(VideoFit.letterbox),
        theme: StudioAppTheme.dark(),
      );
      final light = await capture(
        tester,
        layout(VideoFit.letterbox),
        theme: StudioAppTheme.light(),
      );
      expect(listEquals(dark, light), isTrue);
    });

    testWidgets(
      'the capture stage is the frame at a quarter, whatever its box',
      (tester) async {
        final frame = const VideoSettings(
          preset: VideoPreset.appStoreIphone,
        ).layoutFor(const Size(1320, 2868));
        for (final box in const [Size(300, 260), Size(120, 500)]) {
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox(
                  width: box.width,
                  height: box.height,
                  child: SceneRenderer.videoStage(
                    boundaryKey: key,
                    composed: ComposedScreen.alone(
                      const ScreenDoc(id: 'p', canvas: Size(1320, 2868)),
                    ),
                    catalog: const FrameCatalog([]),
                    layout: frame,
                  ),
                ),
              ),
            ),
          );
          final size = tester.getSize(find.byKey(key));
          expect(
            size * SceneRenderer.videoCaptureRatio,
            const Size(886, 1920),
            reason: 'in a $box box',
          );
        }
      },
    );
  });
}
