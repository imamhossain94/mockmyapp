import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

import 'support/project_fixture.dart';

void main() {
  ScreenDoc sampleDoc(String id) => ScreenDoc(
    id: id,
    background: const GradientBackground(
      colorOne: Color(0xFF6D7BFF),
      colorTwo: Color(0xFF9B6DFF),
    ),
    caption: const CaptionSpec(
      text: 'Hello',
      fontFamily: 'Poppins',
      size: 60,
      color: Color(0xFFFFFFFF),
      allUpCase: true,
      offsetPct: Offset(0.1, -0.05),
      backgroundColor: Color(0x22000000),
    ),
    subCaption: const CaptionSpec(text: 'Sub', size: 30, bold: false),
    frames: [
      FramePlacement(
        deviceId: 'apple-iphone-16-pro',
        variantId: 'black-titanium',
        transform: const Transform2D(
          offsetPct: Offset(0.05, 0.1),
          scale: 1.2,
          rotationDeg: -8,
        ),
        screenshot: const ScreenshotSpec(
          images: ['/tmp/shot.png'],
          cornerRadiusPct: 0.09,
          strokeWidthPct: 0.01,
        ),
        shadow: const ShadowSpec(opacity: 0.3, blur: 24),
      ),
    ],
  );

  test('ScreenDoc survives a JSON round-trip', () {
    final original = sampleDoc('s1');
    final restored = screenDocFromJson(
      jsonDecode(jsonEncode(screenDocToJson(original))) as Map<String, dynamic>,
    );

    expect(restored.id, original.id);
    expect(restored.caption!.text, 'Hello');
    expect(restored.caption!.fontFamily, 'Poppins');
    expect(restored.caption!.allUpCase, true);
    expect(restored.caption!.offsetPct, const Offset(0.1, -0.05));
    expect(restored.caption!.backgroundColor, const Color(0x22000000));
    expect(restored.subCaption!.text, 'Sub');
    expect(restored.background, isA<GradientBackground>());
    final frame = restored.frames.single;
    expect(frame.deviceId, 'apple-iphone-16-pro');
    expect(frame.transform.scale, 1.2);
    expect(frame.transform.rotationDeg, -8);
    expect(frame.screenshot.imagePath, '/tmp/shot.png');
    expect(frame.screenshot.cornerRadiusPct, closeTo(0.09, 1e-9));
    expect(frame.shadow!.opacity, closeTo(0.3, 1e-9));
  });

  test('an adjusted image backdrop survives a JSON round-trip', () {
    final original = sampleDoc('s2').copyWith(
      background: const ImageBackground(
        '/tmp/backdrop.jpg',
        fit: ImageBackgroundFit.contain,
        scale: 1.8,
        offsetX: -0.15,
        offsetY: 0.2,
        blur: 0.04,
        overlayColor: Color(0xFF1E3A8A),
        overlayOpacity: 0.35,
      ),
    );

    final restored = screenDocFromJson(
      jsonDecode(jsonEncode(screenDocToJson(original))) as Map<String, dynamic>,
    );

    final background = restored.background as ImageBackground;
    expect(background.path, '/tmp/backdrop.jpg');
    expect(background.fit, ImageBackgroundFit.contain);
    expect(background.scale, closeTo(1.8, 1e-9));
    expect(background.offsetX, closeTo(-0.15, 1e-9));
    expect(background.offsetY, closeTo(0.2, 1e-9));
    expect(background.blur, closeTo(0.04, 1e-9));
    expect(background.overlayColor, const Color(0xFF1E3A8A));
    expect(background.overlayOpacity, closeTo(0.35, 1e-9));
  });

  test('a backdrop written before the adjustments opens untouched', () {
    // Exactly what older builds wrote: a type and a path, nothing else.
    final restored = backgroundFromJson(<String, dynamic>{
      'type': 'image',
      'path': '/tmp/old.png',
    });

    expect(restored, isA<ImageBackground>());
    final background = restored as ImageBackground;
    expect(background.path, '/tmp/old.png');
    expect(background.fit, ImageBackgroundFit.cover);
    expect(background.scale, 1.0);
    expect(background.offsetX, 0.0);
    expect(background.offsetY, 0.0);
    expect(background.blur, 0.0);
    expect(background.overlayOpacity, 0.0);
  });

  test('caption text effects survive a JSON round-trip', () {
    final original = sampleDoc('s3').copyWith(
      caption: const CaptionSpec(
        text: 'ARROW RUSH',
        letterSpacing: -1.8,
        strokeWidth: 4.5,
        strokeColor: Color(0xFF0A0E22),
        shadowBlur: 12,
        shadowOffsetY: 5,
        shadowColor: Color(0x66000000),
        glowBlur: 30,
        glowColor: Color(0xFF4DE9FF),
        backgroundColor: Color(0xFF2645D4),
        backgroundRadius: 40,
        backgroundBorderColor: Color(0xFFFFFFFF),
        backgroundBorderWidth: 2.5,
      ),
    );

    final restored = screenDocFromJson(
      jsonDecode(jsonEncode(screenDocToJson(original))) as Map<String, dynamic>,
    );

    final caption = restored.caption!;
    expect(caption.letterSpacing, closeTo(-1.8, 1e-9));
    expect(caption.strokeWidth, closeTo(4.5, 1e-9));
    expect(caption.strokeColor, const Color(0xFF0A0E22));
    expect(caption.shadowBlur, closeTo(12, 1e-9));
    expect(caption.shadowOffsetY, closeTo(5, 1e-9));
    expect(caption.shadowColor, const Color(0x66000000));
    expect(caption.glowBlur, closeTo(30, 1e-9));
    expect(caption.glowColor, const Color(0xFF4DE9FF));
    expect(caption.backgroundRadius, closeTo(40, 1e-9));
    expect(caption.backgroundBorderColor, const Color(0xFFFFFFFF));
    expect(caption.backgroundBorderWidth, closeTo(2.5, 1e-9));
  });

  test('a caption written before the effects opens with them off', () {
    // Exactly what older builds wrote — no effect keys at all. Anything but
    // "off" here would silently restyle every caption in every saved project.
    final restored = captionFromJson(<String, dynamic>{
      'enabled': true,
      'text': 'Hello',
      'fontFamily': 'Poppins',
      'size': 50.0,
      'lineHeight': 60.0,
      'color': 0xFF18181B,
      'align': {'x': 0.0, 'y': 0.0},
      'allUpCase': false,
      'bold': true,
      'offsetPct': {'dx': 0.0, 'dy': 0.0},
      'backgroundColor': null,
      'backgroundPaddingX': 12.0,
      'backgroundPaddingY': 6.0,
    });

    expect(restored.letterSpacing, 0);
    expect(restored.strokeWidth, 0);
    expect(restored.shadowBlur, 0);
    expect(restored.shadowOffsetY, 0);
    expect(restored.glowBlur, 0);
    expect(restored.backgroundBorderWidth, 0);
    expect(restored.backgroundBorderColor, isNull);
    // 8 is the radius the chip was hard-coded to before it became a field.
    expect(restored.backgroundRadius, 8);
  });

  test('clearBackgroundBorderColor is the only way to unset the chip rim', () {
    const spec = CaptionSpec(backgroundBorderColor: Color(0xFFFFFFFF));
    expect(
      spec.copyWith(backgroundBorderColor: null).backgroundBorderColor,
      isNotNull,
    );
    expect(
      spec.copyWith(clearBackgroundBorderColor: true).backgroundBorderColor,
      isNull,
    );
  });

  test('a built frame survives a JSON round-trip', () {
    final original = sampleDoc('s4').copyWith(
      frames: [
        const FramePlacement(
          deviceId: 'studio-custom-ios',
          variantId: 'design',
          design: FrameDesign(
            thickness: 0.04,
            cornerRadius: 0.2,
            color: Color(0xFF223344),
            rimColor: Color(0x80FFFFFF),
            rimWidth: 0.006,
            screenColor: Color(0xFF101010),
            aspect: 0.52,
            punchHole: PunchHoleSpec(
              enabled: true,
              align: FrameSide.left,
              width: 0.18,
              height: 0.05,
              cornerRadius: 0.5,
              top: 0.03,
              inset: 0.08,
              color: Color(0xFF000000),
              borderColor: Color(0xFF445566),
              borderWidth: 0.003,
            ),
            power: SideButtonSpec(
              enabled: true,
              side: FrameSide.right,
              top: 0.3,
              length: 0.07,
              thickness: 0.01,
              count: 1,
            ),
            volume: SideButtonSpec(
              enabled: true,
              side: FrameSide.left,
              count: 2,
              gap: 0.03,
            ),
          ),
        ),
      ],
    );

    final restored = screenDocFromJson(
      jsonDecode(jsonEncode(screenDocToJson(original))) as Map<String, dynamic>,
    );

    final design = restored.frames.single.design!;
    expect(design.thickness, closeTo(0.04, 1e-9));
    expect(design.cornerRadius, closeTo(0.2, 1e-9));
    expect(design.color, const Color(0xFF223344));
    expect(design.rimWidth, closeTo(0.006, 1e-9));
    expect(design.screenColor, const Color(0xFF101010));
    expect(design.aspect, closeTo(0.52, 1e-9));

    expect(design.punchHole.enabled, isTrue);
    expect(design.punchHole.align, FrameSide.left);
    expect(design.punchHole.width, closeTo(0.18, 1e-9));
    expect(design.punchHole.borderColor, const Color(0xFF445566));

    expect(design.power.side, FrameSide.right);
    expect(design.volume.count, 2);
    expect(design.volume.gap, closeTo(0.03, 1e-9));
  });

  test('a frame written before built frames opens on its catalog device', () {
    final restored = framePlacementFromJson(<String, dynamic>{
      'deviceId': 'apple-iphone-16',
      'variantId': '16---ultramarine',
      'transform': transformToJson(const Transform2D()),
      'screenshot': screenshotToJson(const ScreenshotSpec()),
      'opacity': 1.0,
      'frameHidden': false,
      'shadow': null,
    });

    // Null design is what "draw the picked device" means; anything else would
    // silently replace every existing project's frame with a built one.
    expect(restored.design, isNull);
  });

  test('an unknown frame side degrades instead of throwing', () {
    final hole = punchHoleFromJson(<String, dynamic>{
      'enabled': true,
      'align': 'diagonal',
    });
    expect(hole.align, FrameSide.center);

    final button = sideButtonFromJson(<String, dynamic>{'side': 'top'});
    expect(button.side, FrameSide.right);
  });

  test('individually styled caption runs survive a round-trip', () {
    const spec = CaptionSpec(
      text: 'UNIQUE\nMAZE SHAPES',
      color: Color(0xFF111111),
      cornerStyle: CornerStyle.smooth,
      runs: [
        CaptionRun('UNIQUE\n', color: Color(0xFFFFFFFF), sizeScale: 1.4),
        CaptionRun(
          'MAZE SHAPES',
          color: Color(0xFFFFD84D),
          bold: true,
          italic: true,
          underline: true,
          fontFamily: 'Montserrat',
        ),
      ],
    );

    final restored = captionFromJson(
      jsonDecode(jsonEncode(captionToJson(spec))) as Map<String, dynamic>,
    );

    expect(restored.runs, hasLength(2));
    expect(restored.runs.first.text, 'UNIQUE\n');
    expect(restored.runs.first.color, const Color(0xFFFFFFFF));
    expect(restored.runs.first.sizeScale, closeTo(1.4, 1e-9));
    expect(restored.runs.last.bold, isTrue);
    expect(restored.runs.last.italic, isTrue);
    expect(restored.runs.last.underline, isTrue);
    expect(restored.runs.last.fontFamily, 'Montserrat');
    expect(restored.cornerStyle, CornerStyle.smooth);

    // The runs are the text: everything reading a plain string agrees.
    expect(restored.plainText, 'UNIQUE\nMAZE SHAPES');
  });

  test('a run that overrides nothing keeps the caption defaults', () {
    const spec = CaptionSpec(
      text: 'A\nB',
      color: Color(0xFF112233),
      runs: [
        CaptionRun('A\n'),
        CaptionRun('B', color: Color(0xFFFF0000)),
      ],
    );
    expect(spec.runs.first.color, isNull);
    expect(spec.runs.first.sizeScale, isNull);
    expect(spec.runs.first.bold, isNull);
    expect(spec.runs.first.italic, isNull);
    expect(spec.runs.last.color, const Color(0xFFFF0000));
  });

  test('caption case applies to the runs, not just the plain text', () {
    const spec = CaptionSpec(
      text: 'ignored',
      allUpCase: true,
      runs: [CaptionRun('go the\n'), CaptionRun('distance')],
    );
    expect(spec.renderedText, 'GO THE\nDISTANCE');
  });

  test(
    'a caption written before rich text existed opens as one plain block',
    () {
      final restored = captionFromJson(<String, dynamic>{
        'enabled': true,
        'text': 'Hello',
        'fontFamily': 'Poppins',
        'size': 50.0,
        'lineHeight': 60.0,
        'color': 0xFF18181B,
        'align': {'x': 0.0, 'y': 0.0},
        'allUpCase': false,
        'bold': true,
        'offsetPct': {'dx': 0.0, 'dy': 0.0},
      });

      expect(restored.runs, isEmpty);
      expect(restored.italic, isFalse);
      expect(restored.underline, isFalse);
      expect(restored.plainText, 'Hello');
      expect(restored.cornerStyle, CornerStyle.round);
    },
  );

  test('a caption stored as styled lines migrates into runs', () {
    // What every document on disk looks like: the per-line editor's shape,
    // which the rich text editor replaced. Each line becomes one run carrying
    // the newline that ended it, so the migration is lossless and the caption
    // opens saying exactly what it said.
    final restored = captionFromJson(<String, dynamic>{
      'enabled': true,
      'text': 'UNIQUE\nMAZE SHAPES',
      'fontFamily': 'Poppins',
      'size': 50.0,
      'lineHeight': 60.0,
      'color': 0xFF18181B,
      'align': {'x': 0.0, 'y': 0.0},
      'allUpCase': false,
      'bold': true,
      'offsetPct': {'dx': 0.0, 'dy': 0.0},
      'lines': [
        {'text': 'UNIQUE', 'color': 0xFFFFFFFF, 'sizeScale': 1.4},
        {'text': 'MAZE SHAPES', 'bold': true, 'fontFamily': 'Montserrat'},
      ],
    });

    expect(restored.runs, hasLength(2));
    expect(restored.runs.first.text, 'UNIQUE\n');
    expect(restored.runs.first.color, const Color(0xFFFFFFFF));
    expect(restored.runs.first.sizeScale, closeTo(1.4, 1e-9));
    expect(restored.runs.last.text, 'MAZE SHAPES');
    expect(restored.runs.last.bold, isTrue);
    expect(restored.runs.last.fontFamily, 'Montserrat');
    expect(restored.plainText, 'UNIQUE\nMAZE SHAPES');
  });

  test('clearDesign is the only way to go back to the catalog device', () {
    const placement = FramePlacement(
      deviceId: 'studio-custom-ios',
      variantId: 'design',
      design: FrameDesign(),
    );
    expect(placement.copyWith(design: null).design, isNotNull);
    expect(placement.copyWith(clearDesign: true).design, isNull);
  });

  test('clearShadow is the only way to turn a drop shadow off', () {
    const placement = FramePlacement(
      deviceId: 'apple-iphone-16-pro',
      variantId: 'black-titanium',
    );
    expect(placement.shadow, isNotNull);

    // A null argument means "leave it alone", exactly like every other field.
    expect(placement.copyWith(shadow: null).shadow, isNotNull);
    expect(placement.copyWith(clearShadow: true).shadow, isNull);
  });

  test('Project survives a JSON round-trip with multiple screens', () {
    final project = projectOf(
      [sampleDoc('a'), sampleDoc('b')],
      id: 'p1',
      name: 'My App',
      createdAt: DateTime.parse('2026-07-14T12:00:00.000'),
    );

    final restored = Project.fromJson(
      jsonDecode(jsonEncode(project.toJson())) as Map<String, dynamic>,
    );

    expect(restored.id, 'p1');
    expect(restored.name, 'My App');
    expect(restored.allScreens.length, 2);
    expect(restored.allScreens.map((s) => s.id), ['a', 'b']);

    // The target the screens belong to survives the trip too. A round-trip that
    // kept every pixel but lost which listing slot they were for would pass
    // every assertion above and still have broken the document.
    expect(restored.subProjects.single.targetId, 'ios-iphone');
    expect(
      restored.subProjects.single.canvas,
      project.subProjects.single.canvas,
    );
    expect(restored.createdAt, project.createdAt);
  });
}
