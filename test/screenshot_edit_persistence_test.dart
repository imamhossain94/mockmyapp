import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/screenshot_editor/screenshot_edit_codec.dart';
import 'package:mockmyapp/features/editor/screenshot_editor/screenshot_edit_ops.dart';

/// A retouch is reopenable as an edit rather than as pixels.
///
/// Apply still flattens to a PNG — that is what the scene draws and the export
/// ships, and none of it learns that ops exist. This is the recipe kept beside
/// it, and the round trip is the whole contract: what goes in comes out, or a
/// sticker moved last week cannot be moved again.
void main() {
  const imageSize = Size(1080, 2340);

  Future<ui.Image> solid(int w, int h) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFF00FF00),
    );
    return recorder.endRecording().toImage(w, h);
  }

  Future<ScreenshotEdit?> roundTrip(
    ScreenshotEdit edit, {
    ui.Image? texture,
    (ui.Picture, Size)? art,
  }) => screenshotEditFromJson(
    screenshotEditToJson(edit),
    imageSize: imageSize,
    texture: (_) async => texture,
    sticker: (_) async => art,
  );

  test(
    'a shape survives the round trip with its placement and its paint',
    () async {
      final edit = ScreenshotEdit(
        source: 'lib/capture.png',
        crop: const Rect.fromLTRB(0.1, 0.2, 0.9, 0.8),
        ops: [
          ShapeOp(
            id: 3,
            spec: ShapeSpec.of(ShapeKind.star, fill: const Color(0xFFFF0000)),
            center: const Offset(0.4, 0.6),
            width: 0.25,
            height: 0.3,
            rotationDeg: 42,
            opacity: 0.5,
          ),
        ],
      );

      final back = await roundTrip(edit);
      expect(back, isNotNull);
      expect(back!.source, 'lib/capture.png');
      expect(back.crop, edit.crop);

      final op = back.ops.single as ShapeOp;
      expect(op.id, 3);
      expect(op.center, const Offset(0.4, 0.6));
      expect(op.width, closeTo(0.25, 1e-9));
      expect(op.height, closeTo(0.3, 1e-9));
      expect(op.rotationDeg, closeTo(42, 1e-9));
      expect(op.opacity, closeTo(0.5, 1e-9));
      // Through the shape's own codec, so its paint comes back too.
      expect(op.spec.kind, ShapeKind.star);
      expect(op.spec.fill.toARGB32(), 0xFFFF0000);
    },
  );

  test('brush and hidden area come back as themselves', () async {
    final edit = ScreenshotEdit(
      source: 'lib/capture.png',
      crop: const Rect.fromLTRB(0, 0, 1, 1),
      ops: const [
        BrushOp(
          points: [Offset(0.1, 0.1), Offset(0.2, 0.25)],
          color: Color(0xFF112233),
          width: 0.03,
        ),
        HideOp(
          id: 4,
          center: Offset(0.5, 0.04),
          width: 1,
          height: 0.17,
          rotationDeg: 12,
          blur: 0.04,
        ),
      ],
    );

    final back = (await roundTrip(edit))!;
    final brush = back.ops[0] as BrushOp;
    expect(brush.points, hasLength(2));
    expect(brush.points[1].dy, closeTo(0.25, 1e-9));
    expect(brush.color.toARGB32(), 0xFF112233);

    final area = back.ops[1] as HideOp;
    expect(area.id, 4);
    expect(area.style, HideStyle.blur);
    expect(area.blur, closeTo(0.04, 1e-9));
    expect(area.center.dy, closeTo(0.04, 1e-9));
    expect(area.height, closeTo(0.17, 1e-9));
    expect(area.rotationDeg, closeTo(12, 1e-9));
  });

  test('a placed image is rebuilt from its library path', () async {
    final texture = await solid(40, 20);
    final edit = ScreenshotEdit(
      source: 'lib/capture.png',
      crop: const Rect.fromLTRB(0, 0, 1, 1),
      ops: [
        ImageOp(
          id: 9,
          image: texture,
          source: 'lib/logo.png',
          center: const Offset(0.5, 0.5),
          width: 0.4,
          height: 0.2,
          flipH: true,
          cornerRadius: 0.05,
        ),
      ],
    );

    final back = (await roundTrip(edit, texture: texture))!;
    final op = back.ops.single as ImageOp;
    expect(op.source, 'lib/logo.png');
    expect(op.flipH, isTrue);
    expect(op.cornerRadius, closeTo(0.05, 1e-9));
    expect(op.image, same(texture), reason: 'reloaded through the bank');
    texture.dispose();
  });

  test('a sticker keeps its id and its tint', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 10, 10),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final picture = recorder.endRecording();

    final edit = ScreenshotEdit(
      source: 'lib/capture.png',
      crop: const Rect.fromLTRB(0, 0, 1, 1),
      ops: [
        StickerOp(
          id: 4,
          picture: picture,
          pictureSize: const Size(100, 100),
          stickerId: 'arrow-right',
          center: const Offset(0.3, 0.3),
          width: 0.3,
          height: 0.3,
          tint: const Color(0xFF00FF00),
        ),
      ],
    );

    final back = (await roundTrip(edit, art: (picture, const Size(100, 100))))!;
    final op = back.ops.single as StickerOp;
    expect(op.stickerId, 'arrow-right');
    expect(op.tint?.toARGB32(), 0xFF00FF00);
    picture.dispose();
  });

  test('an op whose art has gone is dropped, not fatal', () async {
    // A deleted library image or a sticker id from a later pack. Losing one
    // object beats refusing to open the edit at all.
    final edit = ScreenshotEdit(
      source: 'lib/capture.png',
      crop: const Rect.fromLTRB(0, 0, 1, 1),
      ops: const [
        BrushOp(
          points: [Offset(0.1, 0.1)],
          color: Color(0xFF000000),
          width: 0.02,
        ),
      ],
    );
    final json = screenshotEditToJson(edit);
    (json['ops'] as List).add({
      'kind': 'sticker',
      'id': 2,
      'sticker': 'no-such-sticker',
      'center': {'x': 0.5, 'y': 0.5},
      'w': 0.3,
      'h': 0.3,
    });

    final back = await screenshotEditFromJson(
      json,
      imageSize: imageSize,
      texture: (_) async => null,
      sticker: (_) async => null,
    );
    expect(back!.ops, hasLength(1));
    expect(back.ops.single, isA<BrushOp>());
  });

  test('a background removal is never written — it is baked instead', () async {
    // Its mask is a full-resolution texture from an isolate pass, so storing
    // one per op would put a second copy of the screenshot in the project file
    // for every cut-out.
    final mask = await solid(8, 8);
    final json = screenshotEditToJson(
      ScreenshotEdit(
        source: 'lib/capture.png',
        crop: const Rect.fromLTRB(0, 0, 1, 1),
        ops: [RemoveBackgroundOp(mask: mask, tolerance: 24)],
      ),
    );
    expect(json['ops'], isEmpty);
    mask.dispose();
  });

  group('the document', () {
    test('carries the recipe through a save and a load', () {
      const spec = ScreenshotSpec(
        images: ['a.png'],
        edits: {
          'a.png': {'source': 'raw.png', 'ops': []},
        },
      );
      final back = screenshotFromJson(screenshotToJson(spec));
      expect(back.edits['a.png']?['source'], 'raw.png');
    });

    test('a project written before edits existed still loads', () {
      final json = screenshotToJson(const ScreenshotSpec(images: ['a.png']))
        ..remove('edits');
      expect(screenshotFromJson(json).edits, isEmpty);
    });

    test('a recipe cannot outlive the picture it describes', () {
      // Replacing the image prunes the recipe, so it cannot silently reattach
      // to a later picture that happens to land on the same path.
      const spec = ScreenshotSpec(
        images: ['a.png'],
        edits: {
          'a.png': {'source': 'raw.png'},
        },
      );
      expect(spec.copyWith(imagePath: 'b.png').edits, isEmpty);
    });
  });
}
