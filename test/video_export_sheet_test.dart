import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/domain/engine/continuous.dart';
import 'package:mockmyapp/domain/engine/device_motion.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/features/editor/widgets/video_export_sheet.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';

/// A phone held upright (390 × 844) and a desktop window (1440 × 900).
const _phone = (Size(1170, 2532), 3.0);
const _desktop = (Size(2880, 1800), 2.0);

const _iphoneCanvas = ScreenDoc(id: 's', canvas: Size(1320, 2868));

/// Opens the sheet on a surface of [surface], and returns a way to read what
/// it resolved to.
Future<VideoSettings? Function()> _open(
  WidgetTester tester, {
  required (Size, double) surface,
  ScreenDoc doc = _iphoneCanvas,
  String target = 'ios-iphone',
  bool gif = false,
  bool audio = true,
  VideoSettings initial = const VideoSettings(),
}) async {
  tester.view
    ..physicalSize = surface.$1
    ..devicePixelRatio = surface.$2;
  addTearDown(tester.view.reset);
  VideoSettings? result;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: StudioAppTheme.dark(),
        builder: StudioLayoutScope.wrap,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => result = await showVideoExportSheet(
                  context,
                  composed: ComposedScreen.alone(doc),
                  catalog: const FrameCatalog([]),
                  gif: gif,
                  audio: audio,
                  target: StoreTargets.byId(target),
                  initial: initial,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // The preview loops for ever, so the sheet never settles; a few frames
  // bring it in.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return () => result;
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 100));
}

bool _selected(WidgetTester tester, String label) =>
    tester.widget<StudioChip>(find.widgetWithText(StudioChip, label)).selected;

bool _audioOn(WidgetTester tester) =>
    tester.widget<Switch>(find.byType(Switch)).value;

void main() {
  for (final (name, surface) in [('390px', _phone), ('desktop', _desktop)]) {
    group('at $name', () {
      testWidgets('a social clip by default, labelled for what it is', (
        tester,
      ) async {
        await _open(tester, surface: surface);
        expect(
          find.text('3D-motion clip · Social / website / Play promo video'),
          findsOneWidget,
        );
        for (final label in [
          'Social & web',
          'Play promo',
          'App Store preview',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        expect(_selected(tester, 'Social & web'), isTrue);
        expect(find.textContaining('884 × 1920'), findsOneWidget);
        expect(find.text('Silent audio track'), findsOneWidget);
        expect(_audioOn(tester), isFalse);
        expect(find.text('Not a screen recording'), findsNothing);
        expect(find.text('Film video'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'an App Store preview: exact size, 15–30 s, honest about it',
        (tester) async {
          final result = await _open(tester, surface: surface);
          await _tap(tester, 'App Store preview');

          for (final device in [
            'iPhone',
            'iPhone 5.5"',
            'iPad',
            'Mac & Apple TV',
            'Vision Pro',
          ]) {
            expect(find.text(device), findsOneWidget);
          }
          expect(_selected(tester, 'iPhone'), isTrue);
          expect(find.textContaining('886 × 1920'), findsWidgets);
          expect(find.textContaining('884 × 1920'), findsNothing);
          // Apple's lengths only, the old 6 s snapped up to 15.
          for (final seconds in ['15 s', '20 s', '25 s', '30 s']) {
            expect(find.text(seconds), findsOneWidget);
          }
          expect(find.text('6 s'), findsNothing);
          expect(_selected(tester, '15 s'), isTrue);
          expect(find.textContaining('30 fps'), findsOneWidget);
          expect(find.text('1080p'), findsNothing, reason: 'the size is exact');
          // The sound is on for a preset.
          expect(_audioOn(tester), isTrue);
          expect(find.textContaining('silent stereo AAC'), findsOneWidget);
          // Plainly: Apple takes screen recordings only.
          expect(find.text('Not a screen recording'), findsOneWidget);
          expect(find.textContaining('Guideline 2.3.4'), findsOneWidget);
          expect(find.text('Film anyway'), findsOneWidget);
          expect(find.text('Film video'), findsNothing);
          expect(tester.takeException(), isNull);

          await _tap(tester, 'Crop');
          await _tap(tester, '25 s');
          await _tap(tester, 'Film anyway');
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(
            result(),
            const VideoSettings(
              preset: VideoPreset.appStoreIphone,
              seconds: 25,
              fit: VideoFit.crop,
            ),
          );
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('a Play promo: 1080p, its own lengths, sound on', (
        tester,
      ) async {
        await _open(tester, surface: surface);
        await _tap(tester, 'Play promo');
        expect(find.textContaining('1080 × 1920'), findsWidgets);
        for (final seconds in ['10 s', '15 s', '30 s']) {
          expect(find.text(seconds), findsOneWidget);
        }
        expect(_selected(tester, '10 s'), isTrue, reason: 'nearest to 6 s');
        expect(_audioOn(tester), isTrue);
        expect(find.text('Not a screen recording'), findsNothing);
        expect(find.text('Film video'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('an iPad set opens on the iPad size', (tester) async {
        await _open(
          tester,
          surface: surface,
          doc: const ScreenDoc(id: 'p', canvas: Size(2064, 2752)),
          target: 'ios-ipad',
          // The last clip was an iPhone preview: the purpose is remembered,
          // the device follows the set.
          initial: const VideoSettings(preset: VideoPreset.appStoreIphone),
        );
        expect(_selected(tester, 'iPad'), isTrue);
        expect(find.textContaining('1200 × 1600'), findsWidgets);
        expect(
          find.text('The screen already fits this size exactly.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('where the sound cannot be added, the sheet says so', (
        tester,
      ) async {
        await _open(
          tester,
          surface: surface,
          audio: false,
          initial: const VideoSettings(preset: VideoPreset.appStoreIphone),
        );
        expect(find.text("This device can't add one."), findsOneWidget);
        expect(
          find.text(
            'App Store Connect may refuse a preview without an audio track.',
          ),
          findsOneWidget,
        );
        expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
        expect(_audioOn(tester), isFalse);
        expect(find.textContaining('silent stereo AAC'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a GIF offers no store sizes and no sound', (tester) async {
        await _open(
          tester,
          surface: surface,
          gif: true,
          initial: const VideoSettings(
            preset: VideoPreset.appStoreIphone,
            seconds: 6,
          ),
        );
        expect(find.text('App Store preview'), findsNothing);
        expect(find.text('Silent audio track'), findsNothing);
        expect(find.text('Make GIF'), findsOneWidget);
        expect(find.textContaining('animated GIF'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
