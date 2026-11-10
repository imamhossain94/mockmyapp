import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/features/editor/screenshot_editor/screenshot_edit_ops.dart';
import 'package:mockmyapp/features/editor/screenshot_editor/screenshot_editor_screen.dart';

/// What Done saves is what the photo editor showed.
///
/// A pixelated area is drawn from the photo's pixels, which the composer is
/// handed rather than reads for itself — and the save built its composer
/// without them. The editor showed cells and the listing got a blur, and every
/// test passed, because each drew through a composer it had built itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a pixelated area is saved as cells, not as a blur', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // A ramp, one grey level a pixel across: blurred it is still a ramp,
    // each pixel a level from the next; cut into cells it is flat steps.
    final photo = await tester.runAsync(() async {
      const w = 256, h = 512;
      final pixels = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final o = (y * w + x) * 4;
          pixels[o] = pixels[o + 1] = pixels[o + 2] = x;
          pixels[o + 3] = 255;
        }
      }
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels,
        w,
        h,
        ui.PixelFormat.rgba8888,
        done.complete,
      );
      final image = await done.future;
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final dir = await Directory.systemTemp.createTemp('photo_export');
      final file = File('${dir.path}/ramp.png');
      await file.writeAsBytes(png!.buffer.asUint8List());
      return file.path;
    });

    final library = _SavedPictures();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageLibraryProvider.overrideWith(() => library)],
        child: MaterialApp(
          theme: StudioAppTheme.dark(),
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showScreenshotEditor(
                  context,
                  imagePath: photo!,
                  projectId: null,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await _until(
      tester,
      () => find.byType(RetouchCanvas).evaluate().isNotEmpty,
    );
    // And its pixels read, which the editor does after first paint.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    // The page has finished sliding in.
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text(PhotoTool.hide.label).last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Pixelate'));
    await tester.pump(const Duration(milliseconds: 300));
    final canvas = find.byType(RetouchCanvas);
    await tester.dragFrom(
      tester.getCenter(canvas) - const Offset(70, 40),
      const Offset(140, 80),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final area = tester
        .widget<RetouchCanvas>(canvas)
        .ops
        .whereType<HideOp>()
        .single;
    expect(area.style, HideStyle.pixelate);

    await tester.tap(find.text('Done'));
    await _until(tester, () => library.saved != null);

    final saved = (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(library.saved!);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final width = frame.image.width;
      frame.image.dispose();
      return (data!, width);
    }))!;
    final (rgba, width) = saved;

    // Along the middle row of the area, well inside its edges.
    final y = (area.center.dy * rgba.lengthInBytes / 4 / width).round();
    final from = ((area.center.dx - area.width / 2) * width).round() + 6;
    final to = ((area.center.dx + area.width / 2) * width).round() - 6;
    int grey(int x) => rgba.getUint8((y * width + x) * 4);
    var same = 0;
    for (var x = from; x < to; x++) {
      if (grey(x) == grey(x + 1)) same++;
    }
    expect(
      same / (to - from),
      greaterThan(0.6),
      reason: 'flat cells, not a ramp: $same of ${to - from} pairs equal',
    );
  });
}

/// Waits on the real event loop, a hop at a time, for [done].
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'timed out');
}

/// A library that keeps the first picture it is given — the saved result —
/// instead of writing it to a folder a test does not have.
class _SavedPictures extends ImageLibrary {
  Uint8List? saved;

  @override
  List<LibraryImage> build() => const [];

  @override
  Future<LibraryImage> importBytes(
    Uint8List bytes, {
    required String? projectId,
    LibraryImageKind kind = LibraryImageKind.background,
    String extension = '.png',
  }) async {
    saved ??= bytes;
    return LibraryImage(
      id: 'saved',
      fileName: 'saved$extension',
      kind: kind,
      addedAt: DateTime(2026),
    );
  }
}
