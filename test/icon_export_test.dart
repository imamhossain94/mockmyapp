// The icon export's renderer, held to every file's rules: the exact pixel
// size, whether the PNG has an alpha channel (the iOS master must not; the
// Dark render and the foreground layers must, and use it), grayscale where
// promised, the Play icon's 1024 KB cap even for the busiest artwork, the
// foreground inside Android's 66 dp safe zone and the maskable safe circle,
// and the archive's and fastlane's paths.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:mockmyapp/data/assets/element_catalog.dart';
import 'package:mockmyapp/domain/icons/icon_art.dart';
import 'package:mockmyapp/domain/icons/icon_export.dart';
import 'package:mockmyapp/domain/icons/icon_painter.dart';
import 'package:mockmyapp/domain/icons/lucide_glyphs.dart';
import 'package:mockmyapp/domain/models/icon_doc.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

/// The bundled Lucide set, read from disk the way the other catalog tests do.
List<IconDef> readLucide() {
  final json =
      jsonDecode(File('assets/icons/lucide.json').readAsStringSync())
          as Map<String, dynamic>;
  return [
    for (final i in json['icons'] as List)
      IconDef.fromJson(i as Map<String, dynamic>),
  ];
}

const glyphIcon = IconDoc(
  background: GradientBackground(
    colorOne: Color(0xFF0B3D4C),
    colorTwo: Color(0xFF1E7A8C),
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  foreground: IconGlyph('compass'),
  glyphColor: Color(0xFFFFD166),
  stroke: 1.4,
  innerShadow: IconInnerShadow(),
);

img.Image decode(Uint8List png) => img.decodePng(png)!;

/// Every pixel's alpha.
Iterable<int> alphas(img.Image image) sync* {
  for (final p in image) {
    yield p.a.toInt();
  }
}

/// The pixels whose alpha is above [threshold], as offsets.
List<math.Point<int>> inked(img.Image image, {int threshold = 8}) => [
  for (final p in image)
    if (p.a > threshold) math.Point(p.x, p.y),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => LucideGlyphs.debugUse(readLucide()));

  group('every file', () {
    late Map<String, Uint8List> files;

    setUpAll(() async {
      final art = await resolveIconArt(glyphIcon);
      expect(art.glyphPath, isNotNull, reason: 'compass is a Lucide glyph');
      files = {
        for (final f in await renderIconFiles(art, appName: 'Wayfare'))
          f.path: f.bytes,
      };
    });

    test('is the exact size its store asks for', () {
      for (final spec in IconExport.files) {
        final header = pngHeader(files[spec.path]!)!;
        expect(
          (header.width, header.height),
          (spec.size, spec.size),
          reason: spec.label,
        );
      }
      expect(IconExport.iosMaster.size, 1024);
      expect(IconExport.play.size, 512);
      expect(IconExport.adaptiveForeground.size, 432);
      expect(IconExport.favicon.size, 32);
      expect(IconExport.web192.size, 192);
      expect(IconExport.maskable.size, 512);
      expect(IconExport.appleTouch.size, 180);
      expect(IconExport.microsoft.size, 300);
      expect(IconExport.chrome.size, 128);
    });

    test('passes its own rules', () {
      for (final spec in IconExport.files) {
        expect(iconFileProblem(spec, files[spec.path]!), isNull);
      }
    });

    test('the iOS master has no alpha channel at all', () {
      final header = pngHeader(files[IconExport.iosMaster.path]!)!;
      expect(header.colorType, 2, reason: 'RGB, not RGBA');
      for (final spec in IconExport.files) {
        if (spec.alpha == IconAlpha.none) {
          expect(
            pngHeader(files[spec.path]!)!.colorType,
            anyOf(0, 2),
            reason: spec.label,
          );
        }
      }
    });

    test('the Dark render keeps alpha: clear round the glyph, solid on it', () {
      final dark = decode(files[IconExport.iosDark.path]!);
      expect(dark.numChannels, 4);
      expect(dark.getPixel(0, 0).a, 0, reason: 'no background');
      expect(dark.getPixel(512, 30).a, 0);
      expect(alphas(dark).any((a) => a == 255), isTrue, reason: 'the glyph');
      expect(alphas(dark).where((a) => a == 0).length, greaterThan(500000));
    });

    test('foreground and monochrome layers are transparent round the mark', () {
      for (final spec in [
        IconExport.composerForeground,
        IconExport.adaptiveForeground,
        IconExport.adaptiveMonochrome,
      ]) {
        final layer = decode(files[spec.path]!);
        expect(layer.getPixel(1, 1).a, 0, reason: spec.label);
        expect(alphas(layer).any((a) => a > 200), isTrue, reason: spec.label);
      }
      // The monochrome layer is white wherever it has ink.
      final mono = decode(files[IconExport.adaptiveMonochrome.path]!);
      for (final p in mono) {
        if (p.a > 250) {
          expect((p.r, p.g, p.b), (255, 255, 255));
        }
      }
    });

    test('the Tinted render is grayscale and opaque', () {
      final tinted = decode(files[IconExport.iosTinted.path]!);
      expect(pngHeader(files[IconExport.iosTinted.path]!)!.colorType, 2);
      for (final p in tinted) {
        expect(p.r == p.g && p.g == p.b, isTrue);
      }
      // Light mark on black.
      expect(tinted.getPixel(4, 4).r, 0);
      expect(tinted.any((p) => p.r > 240), isTrue);
    });

    test('the Icon Composer layers carry no inner shadow', () {
      // The foreground layer's only ink is the glyph's colour (antialiased);
      // a shadow would add dark translucent pixels below it.
      final layer = decode(files[IconExport.composerForeground.path]!);
      final dark = layer.where((p) => p.a > 30 && p.r < 120).length;
      expect(dark, 0);
    });

    test('Chrome\'s icon is 96 of art in 16 px of transparent padding', () {
      final chrome = decode(files[IconExport.chrome.path]!);
      for (final (x, y) in [(4, 4), (8, 64), (64, 8), (123, 64), (64, 123)]) {
        expect(chrome.getPixel(x, y).a, 0, reason: '($x, $y) is padding');
      }
      expect(chrome.getPixel(64, 20).a, 255, reason: 'inside the art');
    });

    test('the web icons have rounded, transparent corners', () {
      for (final spec in [
        IconExport.favicon,
        IconExport.web192,
        IconExport.web512,
      ]) {
        final icon = decode(files[spec.path]!);
        expect(icon.getPixel(0, 0).a, 0, reason: spec.label);
        expect(
          icon.getPixel(spec.size ~/ 2, spec.size ~/ 2).a,
          255,
          reason: spec.label,
        );
      }
    });

    test('the text files say what Xcode, Android and a manifest need', () {
      final contents =
          jsonDecode(utf8.decode(files[IconExport.contentsJsonPath]!))
              as Map<String, dynamic>;
      final images = contents['images'] as List;
      expect(
        [for (final i in images) i['filename']],
        [
          'AppIcon-1024.png',
          'AppIcon-1024-dark.png',
          'AppIcon-1024-tinted.png',
        ],
      );
      expect(
        utf8.decode(files[IconExport.adaptiveXmlPath]!),
        contains('@mipmap/ic_launcher_monochrome'),
      );
      final manifest =
          jsonDecode(utf8.decode(files[IconExport.manifestPath]!))
              as Map<String, dynamic>;
      expect(
        (manifest['icons'] as List).where((i) => i['purpose'] == 'maskable'),
        hasLength(1),
      );
      expect(
        utf8.decode(files[IconExport.readmePath]!),
        startsWith('Wayfare app icons'),
      );
    });
  });

  group('safe zones', () {
    test('a default glyph sits inside Android\'s 66 dp circle', () async {
      final art = await resolveIconArt(
        const IconDoc(
          background: SolidBackground(Color(0xFF111111)),
          foreground: IconGlyph('square'),
        ),
      );
      final layer = decode(
        await renderIconFile(art, IconExport.adaptiveForeground),
      );
      // 66 of 108 dp across 432 px: a radius of 132 px about the centre.
      for (final p in inked(layer)) {
        final d = math.sqrt(math.pow(p.x - 216, 2) + math.pow(p.y - 216, 2));
        expect(d, lessThan(132), reason: '(${p.x}, ${p.y}) left the zone');
      }
    });

    test('and inside the maskable icon\'s safe circle', () async {
      final art = await resolveIconArt(
        const IconDoc(
          background: SolidBackground(Color(0xFF111111)),
          foreground: IconGlyph('square'),
          glyphColor: Color(0xFFFF0000),
        ),
      );
      final icon = decode(await renderIconFile(art, IconExport.maskable));
      // The safe zone is the circle of 40 % radius: 204.8 px about the centre.
      for (final p in icon) {
        if (p.r > 200 && p.g < 60) {
          final d = math.sqrt(math.pow(p.x - 256, 2) + math.pow(p.y - 256, 2));
          expect(d, lessThan(204.8));
        }
      }
    });

    test('the adaptive background runs to the edge for the launcher', () async {
      final art = await resolveIconArt(
        const IconDoc(
          background: PatternBackground(
            style: PatternStyle.mesh,
            colors: [Color(0xFF0B3D4C), Color(0xFFFF6B5A), Color(0xFFFFD166)],
          ),
        ),
      );
      final layer = decode(
        await renderIconFile(art, IconExport.adaptiveBackground),
      );
      expect(alphas(layer).every((a) => a == 255), isTrue);
    });
  });

  test('the Play icon stays under 1024 KB for the busiest artwork', () async {
    // Noise is the worst case PNG can meet: nothing to compress.
    final random = math.Random(7);
    final noise = img.Image(width: 1024, height: 1024);
    for (final p in noise) {
      p
        ..r = random.nextInt(256)
        ..g = random.nextInt(256)
        ..b = random.nextInt(256);
    }
    final picture = await decodeIconImage(img.encodePng(noise));
    final art = IconArt(
      const IconDoc(
        background: PatternBackground(
          style: PatternStyle.confetti,
          colors: [Color(0xFF101828), Color(0xFFFF6B5A), Color(0xFF22D3EE)],
          scale: 0.4,
        ),
        foreground: IconImage('noise.png'),
        scale: 1,
      ),
      image: picture,
      imageOpaque: true,
    );
    final play = await renderIconFile(art, IconExport.play);
    expect(play.length, lessThanOrEqualTo(IconExport.maxPlayIconBytes));
    expect(iconFileProblem(IconExport.play, play), isNull);
  });

  test('a file that breaks its rule is caught', () {
    final rgba = img.encodePng(
      img.Image(width: 1024, height: 1024, numChannels: 4),
    );
    expect(
      iconFileProblem(IconExport.iosMaster, rgba),
      contains('alpha channel'),
    );
    final small = img.encodePng(img.Image(width: 500, height: 500));
    expect(iconFileProblem(IconExport.play, small), contains('500 × 500'));
    expect(
      iconFileProblem(IconExport.play, Uint8List.fromList([1, 2, 3])),
      contains('not a PNG'),
    );
    final big = IconFileSpec(
      path: 'x.png',
      size: 500,
      label: 'Capped',
      maxBytes: 10,
    );
    expect(iconFileProblem(big, small), contains('over the 10 allowed'));
  });

  test('a picture foreground in grayscale and as a silhouette', () async {
    final logo = img.Image(width: 64, height: 64, numChannels: 4)
      ..clear(img.ColorRgba8(0, 0, 0, 0));
    img.fillCircle(
      logo,
      x: 32,
      y: 32,
      radius: 20,
      color: img.ColorRgba8(230, 60, 40, 255),
    );
    final picture = await decodeIconImage(img.encodePng(logo));
    expect(await isOpaqueImage(picture!), isFalse);
    final art = IconArt(
      const IconDoc(
        background: SolidBackground(Color(0xFF2244AA)),
        foreground: IconImage('logo.png'),
      ),
      image: picture,
    );
    final tinted = decode(await renderIconFile(art, IconExport.iosTinted));
    for (final p in tinted) {
      expect(p.r == p.g && p.g == p.b, isTrue);
    }
    final mono = decode(
      await renderIconFile(art, IconExport.adaptiveMonochrome),
    );
    expect(mono.getPixel(216, 216).a, 255);
    expect(mono.getPixel(216, 216).r, 255);
    expect(mono.getPixel(10, 10).a, 0);
  });

  test('a monogram is drawn in its typeface', () async {
    final art = await resolveIconArt(
      const IconDoc(
        background: SolidBackground(Color(0xFF111827)),
        foreground: IconText('W'),
      ),
    );
    final master = decode(await renderIconFile(art, IconExport.iosMaster));
    // White letter ink at the centre of a dark square.
    expect(
      master.where((p) => p.r > 240 && p.g > 240).length,
      greaterThan(1000),
    );
    expect(master.getPixel(10, 10).r, 0x11);
  });

  group('the archive', () {
    test('lays every file out under one folder named for the project', () {
      final files = [
        for (final spec in IconExport.files)
          IconFile(spec.path, Uint8List.fromList([1])),
        IconFile(IconExport.contentsJsonPath, Uint8List.fromList([2])),
      ];
      final zip = ZipDecoder().decodeBytes(
        buildIconArchive('Wayfare: Trips', files),
      );
      final names = [for (final f in zip.files) f.name];
      expect(
        names,
        contains('Wayfare Trips icons/ios/AppIcon.appiconset/AppIcon-1024.png'),
      );
      expect(
        names,
        containsAll([
          for (final _ in files) startsWith('Wayfare Trips icons/'),
        ]),
      );
      expect(names.toSet(), {
        for (final f in files) 'Wayfare Trips icons/${f.path}',
      });
      expect(iconArchiveName('Wayfare: Trips'), 'Wayfare Trips icons.zip');
    });

    test('fastlane takes the Play icon in every language', () {
      final icon = Uint8List.fromList([9]);
      final files = fastlanePlayIcons(icon, ['en-US', 'zh-Hans', 'en-US']);
      expect(
        [for (final f in files) f.path],
        [
          'fastlane/metadata/android/en-US/images/icon.png',
          'fastlane/metadata/android/zh-CN/images/icon.png',
        ],
      );
    });
  });

  test('the same design paints the same pixels every time', () async {
    final art = await resolveIconArt(glyphIcon);
    final a = await renderIconFile(art, IconExport.iosMaster);
    final b = await renderIconFile(art, IconExport.iosMaster);
    // listEquals, not expect(a, b): the deep matcher walks a few megabytes of
    // PNG element by element and takes minutes.
    expect(listEquals(a, b), isTrue);
  });

  test('the dark appearance lightens a glyph the dark would hide', () {
    const blackOnYellow = IconDoc(
      background: SolidBackground(Color(0xFFFFD000)),
      foreground: IconGlyph('zap'),
      glyphColor: Color(0xFF000000),
    );
    expect(darkGlyphColor(blackOnYellow), const Color(0xFFFFD000));
    const whiteOnBlue = IconDoc(
      background: SolidBackground(Color(0xFF2244AA)),
      foreground: IconGlyph('zap'),
    );
    expect(darkGlyphColor(whiteOnBlue), const Color(0xFFFFFFFF));
    const navyOnNavy = IconDoc(
      background: SolidBackground(Color(0xFF0A0A20)),
      foreground: IconGlyph('zap'),
      glyphColor: Color(0xFF101030),
    );
    expect(darkGlyphColor(navyOnNavy), const Color(0xFFFFFFFF));
  });

  test('the preview masks are the shapes they claim', () {
    const rect = Rect.fromLTWH(0, 0, 100, 100);
    final squircle = iconMaskPath(IconCorner.squircle, rect);
    // Fuller than a circle at the corners, inside the square.
    expect(squircle.contains(const Offset(12, 12)), isTrue);
    expect(squircle.contains(const Offset(1, 1)), isFalse);
    expect(
      iconMaskPath(IconCorner.circle, rect).contains(const Offset(12, 12)),
      isFalse,
    );
    expect(
      iconMaskPath(IconCorner.square, rect).contains(const Offset(1, 1)),
      isTrue,
    );
  });

  test('encoding gray and flat is exact', () {
    final rgba = Uint8List.fromList([
      10, 200, 30, 255, // opaque green
      0, 0, 0, 0, // fully transparent: white shows through
    ]);
    expect(flattenRgba(rgba), [10, 200, 30, 255, 255, 255, 255, 255]);
    final gray = flattenRgba(rgba, grayscale: true);
    expect(gray[0], gray[1]);
    expect(gray[1], gray[2]);
  });

  test('a picture that cannot be read decodes to nothing', () async {
    expect(await decodeIconImage(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('pixels are painted from literal colours only', () async {
    // The painter takes no context at all; this pins the claim by drawing
    // the same art into two separate recordings and comparing raw pixels.
    final art = await resolveIconArt(glyphIcon);
    Future<Uint8List> raw() async {
      final recorder = ui.PictureRecorder();
      paintIcon(Canvas(recorder), const Size.square(64), art);
      final image = await recorder.endRecording().toImage(64, 64);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    }

    expect(listEquals(await raw(), await raw()), isTrue);
  });
}
