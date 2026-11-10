import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/services/on_device_ai.dart';
import 'package:mockmyapp/domain/engine/continuous.dart';
import 'package:mockmyapp/domain/engine/device_motion.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/providers/on_device_ai_provider.dart';
import 'package:mockmyapp/features/editor/widgets/caption_ideas_sheet.dart';
import 'package:mockmyapp/features/editor/widgets/video_export_sheet.dart';

class _FakeWriter implements CaptionWriter {
  CaptionBrief? asked;

  @override
  Future<EngineStatus> writerStatus() async =>
      const EngineStatus(AiEngine.appleIntelligence, ModelState.ready);

  @override
  Future<List<CaptionIdea>> write(CaptionBrief brief) async {
    asked = brief;
    return const [
      CaptionIdea(
        'Budgets that build themselves',
        subtitle: 'Every penny, sorted',
      ),
      CaptionIdea('Spend with confidence'),
    ];
  }
}

class _FakeReader implements ScreenReader {
  int reads = 0;

  @override
  Future<bool> get canRead async => true;

  @override
  Future<String> read(Uint8List image) async {
    reads++;
    return 'Monthly budget\nGroceries';
  }
}

/// Pumps an app whose home opens [open] from a button, and returns a way to
/// read what the sheet resolved to.
Future<T? Function()> _host<T>(
  WidgetTester tester,
  Future<T?> Function(BuildContext context) open, {
  List<Override> overrides = const [],
  bool settles = true,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(430, 932);
  addTearDown(tester.view.reset);
  T? result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: StudioAppTheme.dark(),
        builder: StudioLayoutScope.wrap,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => result = await open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // A sheet with a looping preview never goes idle; it is given a second of
  // frames to open instead.
  if (settles) {
    await tester.pumpAndSettle();
  } else {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  return () => result;
}

void main() {
  testWidgets('caption ideas: read the screen, suggest, pick one', (
    tester,
  ) async {
    final writer = _FakeWriter();
    final reader = _FakeReader();
    final result = await _host<CaptionIdeaChoice>(
      tester,
      (context) => showCaptionIdeasSheet(
        context,
        appName: 'Pocket',
        language: 'en-US',
        current: 'Your headline goes here.',
        screenshot: () async => Uint8List(8),
        hasSubCaption: false,
      ),
      overrides: [
        captionWriterProvider.overrideWithValue(writer),
        screenReaderProvider.overrideWithValue(reader),
      ],
    );

    // The engine is named, with the promise that goes with it.
    expect(find.textContaining('Apple Intelligence'), findsOneWidget);
    expect(find.textContaining('never uploaded'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Track spending');
    await tester.tap(find.text('Premium'));
    await tester.tap(find.text('Suggest'));
    await tester.pumpAndSettle();

    expect(reader.reads, 1);
    expect(writer.asked?.about, 'Track spending');
    expect(writer.asked?.tone, CaptionTone.premium);
    expect(writer.asked?.screenText, contains('Monthly budget'));
    expect(writer.asked?.appName, 'Pocket');

    // Subtitles start off on a screen without a subcaption.
    expect(find.text('Every penny, sorted'), findsNothing);
    await tester.tap(find.text('Include subtitles'));
    await tester.pumpAndSettle();
    expect(find.text('Every penny, sorted'), findsOneWidget);

    await tester.tap(find.text('Budgets that build themselves'));
    await tester.pumpAndSettle();
    final picked = result();
    expect(picked?.idea.headline, 'Budgets that build themselves');
    expect(picked?.withSubtitle, isTrue);
  });

  testWidgets('video: pick a motion and a length, get the settings back', (
    tester,
  ) async {
    final catalog = FrameCatalog([
      FrameDevice(
        id: 'd',
        brand: 'Studio',
        series: 'Test',
        model: 'Slab',
        platform: FramePlatform.ios,
        releaseYear: 2026,
        screenAspect: 0.46,
        frameAspect: 0.4743,
        screenRect: const ScreenRect(x: 0.025, y: 0.0119, w: 0.95, h: 0.9763),
        cornerRadiusPct: 0.07,
        cutout: 'none',
        frameStyle: 'slab',
        variants: const [FrameVariant(id: 'ink', name: 'Ink', asset: '')],
      ),
    ]);
    const doc = ScreenDoc(
      id: 's',
      canvas: Size(1320, 2868),
      frames: [FramePlacement(deviceId: 'd', variantId: 'ink')],
    );
    final result = await _host<VideoSettings>(
      tester,
      (context) => showVideoExportSheet(
        context,
        composed: ComposedScreen.alone(doc),
        catalog: catalog,
        gif: false,
      ),
      settles: false,
    );

    // MP4 at 1080p: 884 by 1920 for a 6.9-inch canvas.
    expect(find.textContaining('884 × 1920'), findsOneWidget);
    await tester.tap(find.text('Orbit'));
    await tester.tap(find.text('15 s'));
    await tester.tap(find.text('720p'));
    await tester.pump();
    expect(find.textContaining('590 × 1280'), findsOneWidget);

    await tester.ensureVisible(find.text('Film video'));
    await tester.pump();
    await tester.tap(find.text('Film video'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      result(),
      const VideoSettings(
        motion: DeviceMotion.orbit,
        seconds: 15,
        longSide: 1280,
      ),
    );
  });

  testWidgets('video without an encoder offers a short GIF and says why', (
    tester,
  ) async {
    const doc = ScreenDoc(id: 's', canvas: Size(1080, 1920));
    await _host<VideoSettings>(
      tester,
      (context) => showVideoExportSheet(
        context,
        composed: ComposedScreen.alone(doc),
        catalog: const FrameCatalog([]),
        gif: true,
        initial: const VideoSettings(seconds: 6),
      ),
      settles: false,
    );
    expect(find.text('Make GIF'), findsOneWidget);
    expect(find.text('30 s'), findsNothing);
    expect(find.text('1080p'), findsNothing);
    expect(find.textContaining('no video encoder'), findsOneWidget);
  });
}
