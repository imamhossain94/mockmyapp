import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/assets/clipart_catalog.dart';
import 'package:mockmyapp/features/editor/screenshot_editor/screenshot_edit_ops.dart';

/// The bundled clip-art pack, read off disk rather than through the asset
/// bundle so a sticker that was generated but never registered in
/// `pubspec.yaml` still fails here rather than at runtime.
ClipartCatalog _catalog() => ClipartCatalog.fromJson(
  jsonDecode(File('assets/clipart/manifest.json').readAsStringSync())
      as Map<String, dynamic>,
);

void main() {
  final catalog = _catalog();

  test('the pack is not empty and every category has art in it', () {
    expect(catalog.stickers, isNotEmpty);
    expect(catalog.categories, isNotEmpty);
    for (final category in catalog.categories) {
      expect(catalog.inCategory(category), isNotEmpty, reason: category);
    }
  });

  test('every sticker file exists on disk', () {
    // The manifest is generated from the same loop that writes the files, so
    // this can only fail if one was deleted by hand — which is exactly the
    // case worth catching, because the app would show an empty tile.
    for (final sticker in catalog.stickers) {
      expect(
        File(sticker.asset).existsSync(),
        isTrue,
        reason: '${sticker.id} -> ${sticker.asset}',
      );
    }
  });

  test('every sticker is registered in pubspec', () {
    // Flutter does not recurse into asset directories, so each category folder
    // needs its own line. A new category that nobody added is invisible until
    // someone opens that tab in the app.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final category in catalog.categories) {
      expect(
        pubspec.contains('assets/clipart/${category.toLowerCase()}/'),
        isTrue,
        reason: 'category "$category" is not declared in pubspec.yaml',
      );
    }
  });

  test('ids are unique', () {
    final ids = catalog.stickers.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('an unknown id answers null rather than substituting art', () {
    expect(catalog.byId('no-such-sticker'), isNull);
    expect(catalog.byId(catalog.stickers.first.id), isNotNull);
  });

  test('only single-colour art declares itself tintable', () {
    // Recolouring multi-colour art collapses it: a speech bubble whose fill and
    // outline are set to one value is a blank rectangle. The rule is checked
    // against the drawing itself rather than trusted from the manifest.
    for (final sticker in catalog.stickers) {
      if (!sticker.tintable) continue;
      final svg = File(sticker.asset).readAsStringSync();
      final colours = RegExp(
        r'(?:fill|stroke)="(#[0-9A-Fa-f]{6})"',
      ).allMatches(svg).map((m) => m.group(1)!.toUpperCase()).toSet();
      expect(
        colours.length,
        lessThanOrEqualTo(1),
        reason: '${sticker.id} is marked tintable but uses $colours',
      );
    }
  });

  group('placing a sticker', () {
    /// The centre pixel of a sticker composited over a white capture.
    Future<List<int>> render(WidgetTester tester, {Color? tint}) async {
      final sticker = catalog.byId('arrow-right')!;
      late List<int> rgb;

      await tester.runAsync(() async {
        final art = await loadStickerPicture(sticker);

        final capture = ui.PictureRecorder();
        Canvas(capture).drawRect(
          const Rect.fromLTWH(0, 0, 200, 200),
          Paint()..color = const Color(0xFFFFFFFF),
        );
        final white = await capture.endRecording().toImage(200, 200);

        final composer = ScreenshotComposer(
          image: white,
          crop: const Rect.fromLTRB(0, 0, 1, 1),
          ops: [
            StickerOp(
              id: 1,
              picture: art.picture,
              pictureSize: art.size,
              stickerId: sticker.id,
              center: const Offset(0.5, 0.5),
              width: 0.8,
              height: 0.8,
              tint: tint,
            ),
          ],
        );

        final recorder = ui.PictureRecorder();
        composer.paint(Canvas(recorder), const Rect.fromLTWH(0, 0, 200, 200));
        final out = await recorder.endRecording().toImage(200, 200);
        final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
        final at = (100 * 200 + 100) * 4;
        rgb = [
          data!.getUint8(at),
          data.getUint8(at + 1),
          data.getUint8(at + 2),
        ];

        out.dispose();
        white.dispose();
        art.picture.dispose();
      });
      return rgb;
    }

    testWidgets('the art draws, in its own colours', (tester) async {
      // Through the composer, which is the same paint path the export uses —
      // and through `ui.Picture`, not a rasterisation, because two thirds of
      // the pack is multi-path and multi-colour and a single-outline import
      // would erase it.
      final rgb = await render(tester);
      // The arrow's ink is #1E2233 — dark, and nothing like the white capture.
      expect(rgb[0], lessThan(90), reason: 'got $rgb');
      expect(rgb[2], lessThan(120), reason: 'got $rgb');
    });

    testWidgets('a tint recolours it without covering it', (tester) async {
      // srcIn keeps the art's own alpha and replaces its colour. A tint that
      // painted a rectangle would make the whole box red instead of the arrow.
      final rgb = await render(tester, tint: const Color(0xFFFF0000));
      expect(rgb[0], greaterThan(200), reason: 'got $rgb');
      expect(rgb[1], lessThan(60), reason: 'got $rgb');
    });
  });
}
