import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/assets/template_catalog.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/data/repositories/stored_image.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/screen_template.dart';
import 'package:mockmyapp/domain/models/sub_project.dart';

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// A two-screen listing whose every field is recognisable, so a test can tell
/// what travelled from what merely survived.
final _look = ScreenTemplate(
  id: 'test-look',
  name: 'Test Look',
  blurb: 'For tests',
  screens: [
    TemplateScreen.measured(
      background: const SolidBackground(Color(0xFF102030)),
      display: const SolidBackground(Color(0xFF40A0FF)),
      text: 'Screen one copy',
      textColor: const Color(0xFFFFEE00),
      sizePct: 0.06,
      bold: false,
      upper: true,
      textTopPct: 0.08,
      textBottomPct: 0.18,
      deviceTopPct: 0.24,
      deviceWidthPct: 0.9,
    ),
    TemplateScreen.measured(
      background: const SolidBackground(Color(0xFF204060)),
      display: const SolidBackground(Color(0xFF80FF40)),
      text: 'Screen two copy',
      textColor: const Color(0xFFFFFFFF),
      sizePct: 0.05,
      textTopPct: 0.06,
      textBottomPct: 0.14,
      deviceTopPct: 0.30,
      deviceWidthPct: 0.7,
    ),
  ],
);

/// A listing longer than the three screens a set is seeded with.
///
/// Each design names its own index, so a test can prove which screen took which
/// design rather than only that something was applied.
final _sixScreens = ScreenTemplate(
  id: 'test-six',
  name: 'Six Screens',
  blurb: 'For tests',
  screens: [
    for (var i = 0; i < 6; i++)
      TemplateScreen.measured(
        background: SolidBackground(Color(0xFF100000 + i)),
        display: const SolidBackground(Color(0xFF40A0FF)),
        text: 'Design $i',
        textColor: const Color(0xFFFFFFFF),
        sizePct: 0.06,
        textTopPct: 0.08,
        textBottomPct: 0.18,
        deviceTopPct: 0.24,
        deviceWidthPct: 0.9,
      ),
  ],
);

ScreenDoc _doc({
  Size canvas = const Size(1320, 2868),
  int frames = 1,
  CaptionSpec? caption,
}) => ScreenDoc(
  id: 'screen',
  canvas: canvas,
  caption: caption ?? const CaptionSpec(text: 'My own words'),
  frames: [
    for (var i = 0; i < frames; i++)
      FramePlacement(
        deviceId: 'apple-iphone-16',
        variantId: '16---ultramarine',
        transform: Transform2D(offsetPct: Offset(0.1 * i, 0)),
        screenshot: const ScreenshotSpec(images: ['/shot.png']),
      ),
  ],
);

/// Where the top of the device lands, as a fraction of the page — the same
/// arithmetic `SceneView` does when it lays a frame out.
double _frameTop(Transform2D t) =>
    (1 - t.pagePercentage * t.scale) / 2 * (1 + t.align.y) + t.offsetPct.dy;

/// Half the horizontal span of a device [widthPct] of the page wide and
/// [heightPct] of a 9:16 page tall, turned [rotationDeg] — in page widths.
double _halfSpan(double widthPct, double heightPct, double rotationDeg) {
  final t = rotationDeg * math.pi / 180;
  final h = heightPct * 1920 / 1080;
  return (widthPct / 2) * math.cos(t).abs() + (h / 2) * math.sin(t).abs();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the catalog', () {
    test('every listing is uniquely identified, named and non-empty', () {
      expect(screenTemplates, isNotEmpty);
      expect(
        screenTemplates.map((t) => t.id).toSet(),
        hasLength(screenTemplates.length),
      );
      for (final t in screenTemplates) {
        expect(t.id, isNotEmpty, reason: t.name);
        expect(t.name, isNotEmpty, reason: t.id);
        expect(t.blurb, isNotEmpty, reason: t.id);
        expect(t.screens, isNotEmpty, reason: t.id);
      }
    });

    test('every screen colours the display', () {
      // The whole reason a template is worth applying to an empty project: the
      // set reads as a design before a screenshot exists.
      for (final t in screenTemplates) {
        for (var i = 0; i < t.length; i++) {
          expect(t.screens[i].display, isNotNull, reason: '${t.id}[$i]');
        }
      }
    });

    test('every device stays on the page it is placed on', () {
      for (final t in screenTemplates) {
        for (var i = 0; i < t.length; i++) {
          final s = t.screens[i];
          final where = '${t.id}[$i]';
          final tr = s.transformFor(const Size(1080, 1920));
          // A device may be cropped, but it may not be so big or so far down
          // that nothing of it is on the page.
          expect(
            tr.pagePercentage * tr.scale,
            inInclusiveRange(0.3, 2.0),
            reason: where,
          );
          // The device must actually fit the page it is placed on — the fault
          // that shipped: a height-relative size spilled to 109% of the width
          // of a taller canvas.
          expect(s.deviceWidthPct, inInclusiveRange(0.2, 1.2), reason: where);
          expect(_frameTop(tr), inInclusiveRange(-0.6, 0.95), reason: where);
          // Sideways, the rule is *visibility*, not a fixed bound on the
          // offset. A panorama listing cuts one handset across two screens on
          // purpose, pushing a device most of the way off the page to do it, so
          // an offset limit was measuring the wrong thing. What has to hold is
          // that a slice of the device is still on the page to see — measured
          // across its *rotated* box. The unrotated width understated the
          // span of a tilted phone: a narrow handset leaning 26°, whose
          // corner plainly reaches across the seam, read as off the page.
          final centre = 0.5 + tr.offsetPct.dx;
          final half = _halfSpan(
            s.deviceWidthPct,
            tr.pagePercentage * tr.scale,
            s.rotationDeg,
          );
          expect(centre + half, greaterThan(0.04), reason: where);
          expect(centre - half, lessThan(0.96), reason: where);
          // The other phones on the page answer to the same rules.
          for (final (j, extra) in s.extraDevices.indexed) {
            final at = '$where+$j';
            final et = s.transformForExtra(extra, const Size(1080, 1920));
            expect(
              et.pagePercentage * et.scale,
              inInclusiveRange(0.3, 2.0),
              reason: at,
            );
            expect(
              extra.deviceWidthPct,
              inInclusiveRange(0.2, 1.2),
              reason: at,
            );
            expect(_frameTop(et), inInclusiveRange(-0.6, 0.95), reason: at);
            final c = 0.5 + et.offsetPct.dx;
            final eh = _halfSpan(
              extra.deviceWidthPct,
              et.pagePercentage * et.scale,
              extra.rotationDeg,
            );
            expect(c + eh, greaterThan(0.04), reason: at);
            expect(c - eh, lessThan(0.96), reason: at);
          }
          // Up to a third of the page wide: a cover can set one word at 28%
          // of the width, which is enormous and exactly as published.
          expect(s.caption.size, inInclusiveRange(20, 360), reason: where);
          // Leading may be tighter than the type is tall — that is exactly what
          // big display headlines do, and several of these listings set theirs
          // that way. What it may not be is collapsed or absurd.
          expect(
            s.caption.lineHeight / s.caption.size,
            inInclusiveRange(0.8, 2.0),
            reason: where,
          );
        }
      }
    });

    test('every bundled display asset exists and is declared', () {
      // A template's artwork is compiled in, so a path that never made it into
      // `pubspec.yaml` fails as a *blank display* at runtime rather than as a
      // build error — silently, on the one screen a user opened the gallery
      // to look at. Two things have to line up: the file, and the directory
      // pubspec ships.
      final declared = File('pubspec.yaml')
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.startsWith('- assets/'))
          .map((l) => l.substring(2))
          .toList();

      var found = 0;
      for (final t in screenTemplates) {
        for (var i = 0; i < t.length; i++) {
          final screen = t.screens[i];
          for (final (j, fill) in [
            screen.display,
            // A second phone's artwork is shipped the same way and fails the
            // same silent way when it is not.
            for (final extra in screen.extraDevices) extra.display,
          ].indexed) {
            if (fill is! ImageBackground) continue;
            final where = '${t.id}[$i]${j == 0 ? '' : '+${j - 1}'}';
            expect(
              fill.path,
              startsWith(StoredImage.assetScheme),
              reason: '$where names a file on disk, which no install has',
            );
            final asset = fill.path.substring(StoredImage.assetScheme.length);
            expect(
              File(asset).existsSync(),
              isTrue,
              reason: '$where -> $asset',
            );
            expect(
              declared.any(
                (d) => d == asset || (d.endsWith('/') && asset.startsWith(d)),
              ),
              isTrue,
              reason: '$where -> $asset is not shipped by pubspec.yaml',
            );
            found++;
          }
        }
      }
      // Guards the guard: a catalog that stopped emitting artwork entirely
      // would pass every assertion above by having nothing to check.
      expect(found, greaterThan(0));
    });

    test('every headline sits on the page', () {
      for (final t in screenTemplates) {
        for (var i = 0; i < t.length; i++) {
          expect(
            t.screens[i].caption.offsetPct.dy.abs(),
            lessThan(0.95),
            reason: '${t.id}[$i]',
          );
        }
      }
    });
  });

  group('measuring a screen', () {
    test('puts the device exactly where the listing had it', () {
      // 0.24 down the page and 90% of its width — a phone cropped at the
      // bottom, which is most of them.
      final s = TemplateScreen.measured(
        background: const SolidBackground(Color(0xFF000000)),
        display: const SolidBackground(Color(0xFF111111)),
        text: 'x',
        textColor: const Color(0xFFFFFFFF),
        sizePct: 0.06,
        textTopPct: 0.08,
        deviceTopPct: 0.24,
        deviceWidthPct: 0.9,
        frame: const FrameDesign(aspect: 0.4846),
      );

      // Its top lands where the listing put it, on every canvas...
      for (final canvas in const [
        Size(1080, 1920),
        Size(1320, 2868),
        Size(2048, 2732),
      ]) {
        final t = s.transformFor(canvas);
        expect(_frameTop(t), closeTo(0.24, 1e-9), reason: '$canvas');
        // ...and so does its width, which is the number a listing is composed
        // against and the one that used to drift.
        final heightPct = t.pagePercentage * t.scale;
        final widthPct = heightPct * 0.4846 * (canvas.height / canvas.width);
        expect(widthPct, closeTo(0.9, 1e-9), reason: '$canvas');
      }
    });

    test('puts a headline set above exactly where it was', () {
      final s = TemplateScreen.measured(
        background: const SolidBackground(Color(0xFF000000)),
        display: const SolidBackground(Color(0xFF111111)),
        text: 'x',
        textColor: const Color(0xFFFFFFFF),
        sizePct: 0.06,
        textTopPct: 0.08,
      );
      // `SceneView` anchors a top caption 4.5% down and adds the offset.
      expect(0.045 + s.caption.offsetPct.dy, closeTo(0.08, 1e-9));
    });

    test('puts a headline set below exactly where it was', () {
      final s = TemplateScreen.measured(
        background: const SolidBackground(Color(0xFF000000)),
        display: const SolidBackground(Color(0xFF111111)),
        text: 'x',
        textColor: const Color(0xFFFFFFFF),
        sizePct: 0.06,
        captionAbove: false,
        textTopPct: 0.84,
        textBottomPct: 0.92,
      );
      // A bottom caption is anchored from the bottom, and the offset moves it
      // the other way: `bottom: 0.045 - dy`.
      expect(1 - (0.045 - s.caption.offsetPct.dy), closeTo(0.92, 1e-9));
    });

    test('quotes the font size against the reference canvas', () {
      final s = TemplateScreen.measured(
        background: const SolidBackground(Color(0xFF000000)),
        display: const SolidBackground(Color(0xFF111111)),
        text: 'x',
        textColor: const Color(0xFFFFFFFF),
        sizePct: 0.08,
        lineRatio: 1.2,
        textTopPct: 0.08,
      );
      expect(s.caption.size, closeTo(0.08 * kCaptionReferenceWidth, 1e-9));
      expect(s.caption.lineHeight, closeTo(s.caption.size * 1.2, 1e-9));
    });
  });

  group('applying a listing', () {
    test('pairs screen n with design n, and wraps past the end', () {
      expect(_look.screenAt(0), same(_look.screens[0]));
      expect(_look.screenAt(1), same(_look.screens[1]));
      expect(_look.screenAt(2), same(_look.screens[0]));
      expect(_look.screenAt(5), same(_look.screens[1]));
    });

    test('takes the backdrop and the placement', () {
      final dressed = _look.applyTo(_doc(), index: 1);
      final frame = dressed.frames.single;

      expect(
        (dressed.background as SolidBackground).color.toARGB32(),
        0xFF204060,
      );
      expect(_frameTop(frame.transform), closeTo(0.30, 1e-9));
    });

    test('a set keeping its own words takes the screen colour, not the app', () {
      // The listing's artwork is a picture of *an app*. A set with words of
      // its own is somebody's work being restyled, so it takes the listing's
      // screen colour, sampled from that artwork. It used to take nothing,
      // which drew the grey "add a picture" plate in every phone and read as a
      // template that had failed to load.
      ScreenTemplate withArt({Background? tone}) => ScreenTemplate(
        id: 'art',
        name: 'Art',
        blurb: 'For tests',
        screens: [
          TemplateScreen.measured(
            background: const SolidBackground(Color(0xFF101010)),
            display: const ImageBackground('asset:assets/templates/x/01.webp'),
            displayTone: tone,
            text: 'x',
            textColor: const Color(0xFFFFFFFF),
            sizePct: 0.06,
            textTopPct: 0.08,
          ),
        ],
      );
      const tone = SolidBackground(Color(0xFF1F2334));
      expect(
        withArt(tone: tone).applyTo(_doc()).frames.single.screenshot.fill,
        same(tone),
      );
      // A listing that never sampled one has nothing to stand in.
      expect(withArt().applyTo(_doc()).frames.single.screenshot.fill, isNull);
      // Its words are the listing's too, and so is its app.
      expect(
        withArt(
          tone: tone,
        ).applyTo(_doc(), withDisplay: true).frames.single.screenshot.fill,
        isA<ImageBackground>(),
      );
    });

    test('keeps a display that is a colour rather than a picture', () {
      // A tone is part of the palette, not a screenshot — and it is the whole
      // of a full-bleed cover, which has no device to put a picture in.
      final dressed = _look.applyTo(_doc(), index: 1);
      expect(
        (dressed.frames.single.screenshot.fill as SolidBackground).color
            .toARGB32(),
        0xFF80FF40,
      );
    });

    test('shows the display when the caller is drawing a preview', () {
      // The gallery is the one place it belongs: a tile with an empty device
      // shows the layout and not the design, which is what it exists to show.
      final dressed = _look.applyTo(_doc(), index: 1, withDisplay: true);
      expect(
        (dressed.frames.single.screenshot.fill as SolidBackground).color
            .toARGB32(),
        0xFF80FF40,
      );
    });

    test('replaces artwork left by a preview with the screen colour', () {
      // Not just "does not add one". A document that went through the gallery
      // carries the listing's picture, and restyling it for real has to take
      // that away or the preview artwork outlives the preview.
      const tone = SolidBackground(Color(0xFF1F2334));
      final art = ScreenTemplate(
        id: 'art',
        name: 'Art',
        blurb: 'For tests',
        screens: [
          TemplateScreen.measured(
            background: const SolidBackground(Color(0xFF101010)),
            display: const ImageBackground('asset:assets/templates/x/01.webp'),
            displayTone: tone,
            text: 'x',
            textColor: const Color(0xFFFFFFFF),
            sizePct: 0.06,
            textTopPct: 0.08,
          ),
        ],
      );

      final previewed = art.applyTo(_doc(), withDisplay: true);
      expect(previewed.frames.single.screenshot.fill, isA<ImageBackground>());

      expect(art.applyTo(previewed).frames.single.screenshot.fill, same(tone));
    });

    test('takes the typography and leaves the words alone', () {
      final dressed = _look.applyTo(_doc());
      final caption = dressed.caption!;

      expect(caption.text, 'My own words');
      expect(caption.color, const Color(0xFFFFEE00));
      expect(caption.bold, isFalse);
      expect(caption.allUpCase, isTrue);
      expect(caption.size, closeTo(0.06 * kCaptionReferenceWidth, 1e-9));
    });

    test('takes the words too when the caller asks for the copy', () {
      final dressed = _look.applyTo(_doc(), withCopy: true);
      expect(dressed.caption!.text, 'Screen one copy');
    });

    test('keeps the screenshots already in the frame', () {
      expect(_look.applyTo(_doc()).frames.single.screenshot.images, [
        '/shot.png',
      ]);
    });

    test('keeps a rich caption saying what it said', () {
      const rich = CaptionSpec(
        text: 'Two lines',
        runs: [
          CaptionRun('Two ', color: Color(0xFFFF0000)),
          CaptionRun('lines'),
        ],
      );
      final dressed = _look.applyTo(_doc(caption: rich));

      expect(dressed.caption!.plainText, 'Two lines');
      expect(dressed.caption!.runs.first.color, const Color(0xFFFF0000));
    });

    test('drops rich runs when it brings its own copy', () {
      // The runs hold the words; keeping them would mean the copy never
      // actually arrived.
      const rich = CaptionSpec(
        text: 'Two lines',
        runs: [CaptionRun('Two lines')],
      );
      final dressed = _look.applyTo(_doc(caption: rich), withCopy: true);

      expect(dressed.caption!.runs, isEmpty);
      expect(dressed.caption!.plainText, 'Screen one copy');
    });

    test('leaves a two-device composition where the user put it', () {
      final dressed = _look.applyTo(_doc(frames: 2));

      expect(dressed.frames[0].transform.offsetPct, Offset.zero);
      expect(dressed.frames[1].transform.offsetPct, const Offset(0.1, 0));
      // The look still reaches both — only the geometry is off limits.
      expect(
        (dressed.background as SolidBackground).color.toARGB32(),
        0xFF102030,
      );
      final preview = _look.applyTo(_doc(frames: 2), withDisplay: true);
      expect(preview.frames[0].screenshot.fill, isNotNull);
      expect(preview.frames[1].screenshot.fill, isNotNull);
    });

    test('leaves the placement alone on a landscape canvas', () {
      // A desktop or web shot: landscape, but not a banner.
      final dressed = _look.applyTo(_doc(canvas: const Size(1280, 800)));

      expect(dressed.frames.single.transform.scale, 1.0);
      expect(
        (dressed.background as SolidBackground).color.toARGB32(),
        0xFF102030,
      );
    });

    test('a feature graphic takes nothing from a listing without a banner', () {
      // A screenshot's design stretched across a 1024 x 500 banner is not a
      // design, so the page is left exactly as it was.
      final banner = _doc(canvas: const Size(1024, 500));
      expect(_look.featureGraphic, isNull);
      expect(_look.lengthFor(banner.canvas), 0);
      expect(_look.applyTo(banner), same(banner));
    });

    test('leaves a screen with no caption without one', () {
      final bare = ScreenDoc(id: 'bare', frames: _doc().frames);
      expect(_look.applyTo(bare).caption, isNull);
    });

    test('a listing that names a frame puts it on the device', () {
      // The whole point of the frame field: these listings are designed around
      // a plain black slab, and a template that named none inherited whatever
      // handset the project happened to carry.
      final framed = ScreenTemplate(
        id: 'framed',
        name: 'Framed',
        blurb: 'Black slab',
        screens: [
          TemplateScreen.measured(
            background: const SolidBackground(Color(0xFF101010)),
            display: const SolidBackground(Color(0xFF222222)),
            text: 'x',
            textColor: const Color(0xFFFFFFFF),
            sizePct: 0.07,
            textTopPct: 0.08,
            frame: const FrameDesign(thickness: 0.02, cornerRadius: 0.12),
          ),
        ],
      );

      final frame = framed.applyTo(_doc()).frames.single;
      expect(frame.design, isNotNull);
      expect(frame.design!.thickness, 0.02);
      expect(frame.design!.cornerRadius, 0.12);
      // A set that was frameless before must actually grow the bezel.
      expect(frame.frameHidden, isFalse);
    });

    test('a listing that names no frame keeps the device you picked', () {
      final frame = _look.applyTo(_doc()).frames.single;
      expect(frame.design, isNull);
      expect(frame.deviceId, 'apple-iphone-16');
      expect(frame.variantId, '16---ultramarine');
    });

    test('a full-bleed screen fills the page with no bezel', () {
      final full = ScreenTemplate(
        id: 'fb',
        name: 'Full bleed',
        blurb: 'Edge to edge',
        screens: [
          TemplateScreen.measured(
            background: const SolidBackground(Color(0xFF000000)),
            display: const SolidBackground(Color(0xFF222222)),
            text: 'Over the top',
            textColor: const Color(0xFFFFFFFF),
            sizePct: 0.07,
            textTopPct: 0.6,
            hasDevice: false,
          ),
        ],
      );

      final frame = full.applyTo(_doc()).frames.single;
      expect(frame.frameHidden, isTrue);
      expect(frame.design, isNotNull);
      expect(frame.design!.thickness, 0);
      // The aperture takes the canvas's own proportions, which is what makes it
      // full-bleed rather than phone-shaped.
      expect(frame.design!.aspect, closeTo(1320 / 2868, 1e-9));
      expect(frame.transform.pagePercentage, 1);
      expect(frame.screenshot.cornerRadiusPct, 0);
    });
  });

  group('a screen with a second handset', () {
    final paired = ScreenTemplate(
      id: 'paired',
      name: 'Paired',
      blurb: 'Two phones',
      screens: [
        TemplateScreen.measured(
          background: const SolidBackground(Color(0xFF101010)),
          display: const ImageBackground('asset:assets/templates/x/01.webp'),
          text: 'x',
          textColor: const Color(0xFFFFFFFF),
          sizePct: 0.06,
          textTopPct: 0.08,
          deviceTopPct: 0.30,
          deviceWidthPct: 0.55,
          offsetXPct: 0.15,
          frame: const FrameDesign(aspect: 0.468),
          extraDevices: const [
            TemplateDevice(
              display: ImageBackground('asset:assets/templates/x/01b.webp'),
              deviceTopPct: 0.19,
              deviceWidthPct: 0.57,
              offsetXPct: -0.13,
            ),
          ],
        ),
      ],
    );

    test('grows the missing device, empty, behind the first', () {
      final out = paired.applyTo(_doc());
      expect(out.frames, hasLength(2));

      final back = out.frames[1];
      expect(_frameTop(back.transform), closeTo(0.19, 1e-9));
      expect(back.transform.offsetPct.dx, closeTo(-0.13, 1e-9));
      expect(back.z, lessThan(out.frames.first.z));
      // In the listing's handset, not a copy of the user's capture, and not
      // wearing the listing's picture of somebody else's app either.
      expect(back.design?.aspect, 0.468);
      expect(back.screenshot.images, isEmpty);
      expect(back.screenshot.fill, isNull);
      expect(out.frames.first.screenshot.images, ['/shot.png']);
    });

    test('shows each device its own artwork in a preview', () {
      final out = paired.applyTo(_doc(), withDisplay: true);
      expect(
        (out.frames[0].screenshot.fill as ImageBackground).path,
        endsWith('01.webp'),
      );
      expect(
        (out.frames[1].screenshot.fill as ImageBackground).path,
        endsWith('01b.webp'),
      );
    });

    test('puts a matching pair back in place rather than growing a third', () {
      final once = paired.applyTo(_doc());
      final moved = once.copyWith(
        frames: [
          once.frames[0],
          once.frames[1].copyWith(
            transform: const Transform2D(),
            screenshot: const ScreenshotSpec(images: ['/b.png']),
          ),
        ],
      );

      final again = paired.applyTo(moved);
      expect(again.frames, hasLength(2));
      expect(_frameTop(again.frames[1].transform), closeTo(0.19, 1e-9));
      expect(again.frames[1].screenshot.images, ['/b.png']);
    });

    test('leaves a composition of any other size where it was', () {
      final out = paired.applyTo(_doc(frames: 3));
      expect(out.frames, hasLength(3));
      expect(out.frames[2].transform.offsetPct, const Offset(0.2, 0));
    });

    test('grows nothing on a landscape page', () {
      final out = paired.applyTo(_doc(canvas: const Size(1024, 500)));
      expect(out.frames, hasLength(1));
    });
  });

  group('the gallery shelves', () {
    test('every listing is filed under a category and a platform', () {
      for (final t in screenTemplates) {
        expect(t.category, isNotNull, reason: t.id);
        expect(t.platforms, isNotEmpty, reason: t.id);
      }
    });

    /// Every listing in the catalog is a real Play listing, so the shelf is
    /// Android's. This used to assert that both stores were represented, which
    /// was true only while the catalog also carried original designs filed
    /// under iOS; it is an inventory claim rather than a behaviour, and what
    /// matters is that a listing reaches a shelf at all.
    test('every listing reaches a shelf, and none carries a banner', () {
      expect(
        screenTemplates.any(
          (t) => t.platforms.contains(TemplatePlatform.android),
        ),
        isTrue,
      );
      // Feature graphics were taken out of the templates: a listing designs
      // screenshots, and the banner is designed on its own canvas.
      for (final t in screenTemplates) {
        expect(t.featureGraphic, isNull, reason: t.id);
      }
    });

    test('every banner is a landscape design that stays on its page', () {
      for (final t in screenTemplates) {
        final banner = t.featureGraphic;
        if (banner == null) continue;
        expect(banner.landscape, isTrue, reason: t.id);
        if (banner.fullBleed) continue;
        final tr = banner.transformFor(kFeatureGraphicCanvas);
        final centre = 0.5 + tr.offsetPct.dx;
        expect(centre, inInclusiveRange(0.0, 1.0), reason: t.id);
        expect(_frameTop(tr), inInclusiveRange(-0.2, 0.8), reason: t.id);
        for (final extra in banner.extraDevices) {
          final et = banner.transformForExtra(extra, kFeatureGraphicCanvas);
          expect(
            0.5 + et.offsetPct.dx,
            inInclusiveRange(0.0, 1.0),
            reason: t.id,
          );
        }
      }
    });

    test('every banner artwork file exists', () {
      for (final t in screenTemplates) {
        final banner = t.featureGraphic;
        if (banner == null) continue;
        for (final fill in [
          banner.display,
          for (final extra in banner.extraDevices) extra.display,
        ]) {
          if (fill is! ImageBackground) continue;
          final asset = fill.path.substring(StoredImage.assetScheme.length);
          expect(File(asset).existsSync(), isTrue, reason: '${t.id} -> $asset');
        }
      }
    });
  });

  group('a feature graphic', () {
    final portrait = TemplateScreen.measured(
      background: const SolidBackground(Color(0xFF101010)),
      display: const SolidBackground(Color(0xFF222222)),
      text: 'Screen',
      textColor: const Color(0xFFFFFFFF),
      sizePct: 0.07,
      textTopPct: 0.06,
      deviceTopPct: 0.25,
      deviceWidthPct: 0.7,
    );
    final banner = TemplateScreen.measured(
      background: const SolidBackground(Color(0xFF3355FF)),
      display: const SolidBackground(Color(0xFF222222)),
      text: 'Banner',
      textColor: const Color(0xFFFFFFFF),
      sizePct: 0.07,
      textTopPct: 0.3,
      deviceTopPct: 0.1,
      deviceWidthPct: 0.24,
      offsetXPct: 0.27,
      rotationDeg: 10,
      landscape: true,
      frame: const FrameDesign(aspect: 0.462),
    );
    final listing = ScreenTemplate(
      id: 'with-banner',
      name: 'With banner',
      blurb: 'For tests',
      screens: [portrait, portrait],
      featureGraphic: banner,
    );

    ScreenDoc graphic() => ScreenDoc(
      id: 'fg',
      canvas: kFeatureGraphicCanvas,
      caption: const CaptionSpec(text: 'Mine'),
      frames: const [
        FramePlacement(
          deviceId: 'custom-android',
          variantId: 'design',
          frameHidden: true,
        ),
      ],
    );

    test('takes the banner design, whatever its index', () {
      for (final i in [0, 1, 5]) {
        final out = listing.applyTo(graphic(), index: i);
        expect(
          (out.background as SolidBackground).color.toARGB32(),
          0xFF3355FF,
          reason: 'index $i',
        );
      }
    });

    test('puts the banner phone on the page, framed', () {
      final frame = listing.applyTo(graphic()).frames.single;
      expect(frame.frameHidden, isFalse);
      expect(frame.design?.aspect, 0.462);
      expect(frame.transform.rotationDeg, 10);
      expect(frame.transform.offsetPct.dx, closeTo(0.27, 1e-9));
      expect(_frameTop(frame.transform), closeTo(0.1, 1e-9));
    });

    test('a portrait design leaves a banner where it is', () {
      final plain = ScreenTemplate(
        id: 'no-banner',
        name: 'No banner',
        blurb: 'For tests',
        screens: [portrait],
      );
      final before = graphic().frames.single;
      final out = plain.applyTo(graphic()).frames.single;
      expect(out.transform.offsetPct, before.transform.offsetPct);
      expect(out.frameHidden, isTrue);
    });

    test('a banner design leaves a portrait screen alone', () {
      final out = banner.applyTo(_doc());
      expect(out.frames.single.transform.offsetPct, Offset.zero);
    });

    test('counts one design for a banner page and every screen otherwise', () {
      expect(listing.lengthFor(kFeatureGraphicCanvas), 1);
      expect(listing.lengthFor(const Size(1080, 1920)), 2);
    });

    test('previews on a banner page that carries the chosen handset', () {
      final sample = featureGraphicSample(_doc());
      expect(sample.canvas, kFeatureGraphicCanvas);
      expect(sample.frames.single.deviceId, 'apple-iphone-16');
    });
  });

  group('a radial fill', () {
    test('survives the codec, and older shapes read back as linear', () {
      final orb = ShapeSpec.of(ShapeKind.ellipse).copyWith(
        fill: const Color(0xCCFF8A3D),
        fillEnd: const Color(0x00FF8A3D),
        gradientRadial: true,
      );
      const canvas = Size(1080, 1920);
      final back = shapeFromJson(shapeToJson(orb), canvas: canvas);
      expect(back.gradientRadial, isTrue);
      expect(back.fillEnd, const Color(0x00FF8A3D));

      final legacy = shapeToJson(orb)..remove('gradientRadial');
      expect(shapeFromJson(legacy, canvas: canvas).gradientRadial, isFalse);
    });

    /// A panorama is one generated composition spread across a set, each screen
    /// showing its own slice of it. No listing in the catalog is composed that
    /// way at the moment — the ones that were have been retired — so this is
    /// the invariant without the inventory: whichever listing takes it up next
    /// has to slice the composition in order and across its whole length.
    test('a panorama listing slices one backdrop across its whole set', () {
      final glows = [
        for (final t in screenTemplates)
          if (t.screens.first.background is PatternBackground) t,
      ];
      for (final t in glows) {
        for (final (i, s) in t.screens.indexed) {
          final bg = s.background as PatternBackground;
          // One composition, sliced a screen at a time.
          expect(bg.slices, t.length, reason: '${t.id}[$i]');
          expect(bg.slice, i, reason: '${t.id}[$i]');
        }
        // The phone glows rather than casting shade: no offset, a colour.
        final shadow = t.screens.first.shadow!;
        expect(shadow.offsetPct, Offset.zero, reason: t.id);
        expect(shadow.color, isNot(const Color(0xFF000000)), reason: t.id);
      }
    });
  });

  group('a heavier headline cut', () {
    test('travels from the listing and survives the codec', () {
      final screen = TemplateScreen.measured(
        background: const SolidBackground(Color(0xFF101010)),
        display: const SolidBackground(Color(0xFF222222)),
        text: 'Heavy',
        textColor: const Color(0xFFFFFFFF),
        sizePct: 0.09,
        textTopPct: 0.05,
        weight: 800,
      );
      expect(screen.caption.weight, 800);
      final back = captionFromJson(captionToJson(screen.caption));
      expect(back.weight, 800);
    });

    test('reads back as the plain bold from a caption written before it', () {
      final legacy = captionToJson(const CaptionSpec(text: 'x'))
        ..remove('weight');
      expect(captionFromJson(legacy).weight, isNull);
    });
  });

  group('a headline set line by line', () {
    ScreenTemplate lined(List<TemplateLine>? lines) => ScreenTemplate(
      id: 'lined',
      name: 'Lined',
      blurb: 'Two sizes',
      screens: [
        TemplateScreen.measured(
          background: const SolidBackground(Color(0xFF101010)),
          display: const SolidBackground(Color(0xFF222222)),
          text: 'SCAN\nto PDF and Word',
          textColor: const Color(0xFFFFFFFF),
          sizePct: 0.1,
          textTopPct: 0.08,
          lines: lines,
        ),
      ],
    );

    test('carries each line at its own size and colour', () {
      final caption = lined(const [
        TemplateLine(),
        TemplateLine(sizeScale: 0.34, color: Color(0xFFFF0000)),
      ]).screens.single.caption;

      expect(caption.runs, hasLength(2));
      // The newline stays on the first run, so the runs still say what the
      // caption says.
      expect(caption.plainText, caption.text);
      expect(caption.runs.first.sizeScale, isNull);
      expect(caption.runs[1].sizeScale, 0.34);
      expect(caption.runs[1].color, const Color(0xFFFF0000));
    });

    test('stays a plain block when no line asks for anything', () {
      expect(lined(null).screens.single.caption.runs, isEmpty);
      expect(
        lined(const [
          TemplateLine(),
          TemplateLine(),
        ]).screens.single.caption.runs,
        isEmpty,
      );
    });

    test('ignores a line list that does not match the text', () {
      expect(
        lined(const [TemplateLine(sizeScale: 0.5)]).screens.single.caption.runs,
        isEmpty,
      );
    });
  });

  group('the display fill', () {
    test('survives a round trip through the codec', () {
      const spec = ScreenshotSpec(
        fill: GradientBackground(
          colorOne: Color(0xFF112233),
          colorTwo: Color(0xFF445566),
        ),
      );
      final fill =
          screenshotFromJson(screenshotToJson(spec)).fill as GradientBackground;
      expect(fill.colorOne, const Color(0xFF112233));
      expect(fill.colorTwo, const Color(0xFF445566));
    });

    test('is absent from the json of a frame that has none', () {
      expect(
        screenshotToJson(const ScreenshotSpec()).containsKey('fill'),
        isFalse,
      );
    });

    test('reads back as null from a document written before it existed', () {
      final legacy = screenshotToJson(const ScreenshotSpec())..remove('fill');
      expect(screenshotFromJson(legacy).fill, isNull);
    });

    test('is cleared with the flag, not with a null argument', () {
      const spec = ScreenshotSpec(fill: SolidBackground(Color(0xFF00FF00)));
      expect(spec.copyWith(scale: 2).fill, isNotNull);
      expect(spec.copyWith(clearFill: true).fill, isNull);
    });
  });

  group('the scene draws the display fill', () {
    late FrameCatalog catalog;

    setUpAll(() async => catalog = await loadFrameCatalog());

    Future<void> pump(WidgetTester tester, ScreenshotSpec screenshot) async {
      final doc = ScreenDoc(
        id: 'filled',
        canvas: const Size(600, 1200),
        background: const SolidBackground(Color(0xFFFFFFFF)),
        frames: [
          FramePlacement(
            deviceId: 'apple-iphone-16',
            variantId: '16---ultramarine',
            screenshot: screenshot,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 600,
              child: SceneView(doc: doc, catalog: catalog),
            ),
          ),
        ),
      );
    }

    // The "add a screenshot" plate, which is the thing a fill replaces.
    final placeholder = find.byIcon(Icons.add_photo_alternate_outlined);
    final blueFill = find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == const Color(0xFF40A0FF),
    );

    testWidgets('an empty display still asks for a screenshot', (tester) async {
      await pump(tester, const ScreenshotSpec());
      expect(placeholder, findsOneWidget);
    });

    testWidgets('a filled display paints the colour instead', (tester) async {
      await pump(
        tester,
        const ScreenshotSpec(fill: SolidBackground(Color(0xFF40A0FF))),
      );
      expect(placeholder, findsNothing);
      expect(blueFill, findsOneWidget);
    });

    testWidgets('the fill is not dragged by the screenshot pan', (
      tester,
    ) async {
      // The pan and zoom place a capture inside the aperture. With no capture
      // to place, moving them must leave the colour filling the display —
      // otherwise dragging a screenshot that is not there slides a solid colour
      // off its own screen and shows the bezel underneath.
      await pump(
        tester,
        const ScreenshotSpec(fill: SolidBackground(Color(0xFF40A0FF))),
      );
      final still = tester.getRect(blueFill);

      await pump(
        tester,
        const ScreenshotSpec(
          fill: SolidBackground(Color(0xFF40A0FF)),
          scale: 0.4,
          offsetX: 0.3,
          offsetY: -0.2,
        ),
      );
      expect(tester.getRect(blueFill), still);
    });
  });

  group('a two-tone headline', () {
    final screen = TemplateScreen.measured(
      background: const SolidBackground(Color(0xFF3F5AD9)),
      display: const SolidBackground(Color(0xFF111111)),
      text: 'ARROW RUSH\nFREE THEM',
      textColor: const Color(0xFFFFFFFF),
      sizePct: 0.1,
      textTopPct: 0.07,
      lines: const [
        TemplateLine(color: Color(0xFFFFFFFF)),
        TemplateLine(color: Color(0xFFFFD84D)),
      ],
    );

    ScreenDoc target({List<CaptionRun> runs = const []}) => ScreenDoc(
      id: 's',
      canvas: const Size(1080, 1920),
      caption: CaptionSpec(text: 'mine\nalso mine', runs: runs),
    );

    test('keeps its own colours when its copy is taken', () {
      // The bug this pins: `withCopy` cleared the runs it had just supplied
      // the words for, so every preview of a two-tone listing — the one place
      // the design is meant to be visible before you commit to it — rendered
      // flat. Both of these listings sell on that second colour.
      final out = screen.applyTo(target(), withCopy: true);
      expect(out.caption!.text, 'ARROW RUSH\nFREE THEM');
      expect(out.caption!.runs, hasLength(2));
      expect(out.caption!.runs.last.color, const Color(0xFFFFD84D));
      // The runs still concatenate back into the text, newline and all.
      expect(out.caption!.runs.map((r) => r.text).join(), out.caption!.text);
    });

    test('sets the user’s words in its own line colours', () {
      // A template says "two-tone" only as runs over its own words, so keeping
      // the user's runs as they were set the yellow second line flat the
      // moment the listing met somebody else's copy. Their words stay; the
      // listing's line styling is laid over them, line for line.
      const mine = [
        CaptionRun('mine\n', color: Color(0xFF00FF00)),
        CaptionRun('also mine'),
      ];
      final out = screen.applyTo(target(runs: mine), withCopy: false);
      expect(out.caption!.plainText, 'mine\nalso mine');
      expect(out.caption!.runs, hasLength(2));
      expect(out.caption!.runs.first.color, const Color(0xFFFFFFFF));
      expect(out.caption!.runs.last.color, const Color(0xFFFFD84D));
    });

    test('a plain caption takes the listing’s line colours too', () {
      final out = screen.applyTo(target(), withCopy: false);
      expect(out.caption!.runs.map((r) => r.text).join(), 'mine\nalso mine');
      expect(out.caption!.runs.last.color, const Color(0xFFFFD84D));
    });
  });

  group('a listing’s decorations', () {
    final badge = ShapeSpec.of(
      ShapeKind.rectangle,
    ).copyWith(label: const ShapeLabel('BUS'));
    final cover = TemplateScreen(
      background: const SolidBackground(Color(0xFFFFFFFF)),
      display: const SolidBackground(Color(0xFF111111)),
      caption: const CaptionSpec(text: 'Every way'),
      decor: [badge],
    );

    ScreenDoc docWith(List<ShapeSpec> shapes) => ScreenDoc(
      id: 's',
      canvas: const Size(1080, 1920),
      shapes: shapes,
      caption: const CaptionSpec(text: 'mine'),
    );

    test('land on a screen that has none', () {
      final out = cover.applyTo(docWith(const []));
      expect(out.shapes, hasLength(1));
      expect(out.shapes.single.label?.text, 'BUS');
    });

    test('never overwrite work already on the screen', () {
      // The one that matters. This runs across a whole set at once and the
      // project screen has no undo behind it, so replacing somebody's
      // annotations with a listing's badges would be a deletion, not a
      // restyle.
      final mine = ShapeSpec.of(ShapeKind.star).copyWith(name: 'my note');
      final out = cover.applyTo(docWith([mine]));
      expect(out.shapes.single.name, 'my note');
    });

    test('replace placeholder decoration when the copy is taken too', () {
      // `withCopy` is only ever passed where the content is the store's own
      // placeholder — a preview tile, or a freshly seeded project.
      final mine = ShapeSpec.of(ShapeKind.star).copyWith(name: 'seeded');
      final out = cover.applyTo(docWith([mine]), withCopy: true);
      expect(out.shapes.single.label?.text, 'BUS');
    });

    test('a listing with no decorations leaves the screen alone', () {
      final plain = TemplateScreen(
        background: const SolidBackground(Color(0xFFFFFFFF)),
        display: const SolidBackground(Color(0xFF111111)),
        caption: const CaptionSpec(text: 'x'),
      );
      final mine = ShapeSpec.of(ShapeKind.star).copyWith(name: 'my note');
      expect(
        plain.applyTo(docWith([mine]), withCopy: true).shapes.single.name,
        'my note',
      );
    });
  });

  group('applying a listing to a target', () {
    late Directory tempDir;
    late ProviderContainer container;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('templates_test');
      PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // The store flushes on a debounce; leave the directory to the OS.
      }
    });

    test('leaves a feature-graphic set alone, one banner and all', () {
      // It used to grow the store's single banner into as many banners as the
      // listing has screens, each wearing a phone screenshot's design.
      final store = container.read(projectStoreProvider.notifier);
      final project = store.createProject(
        name: 'Listing',
        targets: const [
          (
            targetId: 'android-feature-graphic',
            presetId: 'play-feature-graphic',
          ),
        ],
        initialDeviceId: 'apple-iphone-16',
        initialVariantId: '16---ultramarine',
      );
      final banner = project.subProjects.single;
      final before = banner.screens.single;

      for (final template in screenTemplates) {
        expect(
          store.applyTemplate(project.id, banner.id, template),
          isNull,
          reason: '${template.name} has nothing for a banner',
        );
      }
      final after = container
          .read(projectStoreProvider)
          .firstWhere((p) => p.id == project.id)
          .subProjectById(banner.id)!
          .screens;
      expect(after, hasLength(1));
      expect(after.single.background, before.background);
    });

    test('dresses every screen in the set and no other set', () {
      final store = container.read(projectStoreProvider.notifier);
      final project = store.createProject(
        name: 'Listing',
        targets: const [
          (targetId: 'ios-iphone', presetId: 'iphone-6-5'),
          (targetId: 'android-phone', presetId: 'android-phone-9-16'),
        ],
        initialDeviceId: 'apple-iphone-16',
        initialVariantId: '16---ultramarine',
      );

      final iphone = project.subProjects.first;
      final android = project.subProjects.last;
      store.applyTemplate(project.id, iphone.id, _look);

      final saved = container
          .read(projectStoreProvider)
          .firstWhere((p) => p.id == project.id);

      final dressed = saved.subProjectById(iphone.id)!.screens;
      expect(dressed, isNotEmpty);
      // Screen n takes design n, wrapping — the two-screen look alternates.
      for (var i = 0; i < dressed.length; i++) {
        expect(
          (dressed[i].background as SolidBackground).color.toARGB32(),
          i.isEven ? 0xFF102030 : 0xFF204060,
          reason: 'screen $i',
        );
        // `_look`'s displays are colours, so they travel — a tone is part of
        // the palette. A listing shipping artwork is covered above.
        expect(dressed[i].frames.single.screenshot.fill, isNotNull);
      }

      for (final screen in saved.subProjectById(android.id)!.screens) {
        expect(screen.frames.single.screenshot.fill, isNull);
      }
    });

    test('leaves each screen saying what it said', () {
      final store = container.read(projectStoreProvider.notifier);
      final project = store.createProject(
        name: 'Listing',
        targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
        initialDeviceId: 'apple-iphone-16',
        initialVariantId: '16---ultramarine',
      );
      final sub = project.subProjects.single;
      final before = sub.screens.map((s) => s.caption!.plainText).toList();

      store.applyTemplate(project.id, sub.id, _look);

      final after = container
          .read(projectStoreProvider)
          .firstWhere((p) => p.id == project.id)
          .subProjects
          .single
          .screens
          .map((s) => s.caption!.plainText)
          .toList();

      expect(after, before);
    });

    test('takes the copy when the caller asks for it', () {
      final store = container.read(projectStoreProvider.notifier);
      final project = store.createProject(
        name: 'Listing',
        targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
        initialDeviceId: 'apple-iphone-16',
        initialVariantId: '16---ultramarine',
      );
      final sub = project.subProjects.single;

      store.applyTemplate(project.id, sub.id, _look, withCopy: true);

      final after = container
          .read(projectStoreProvider)
          .firstWhere((p) => p.id == project.id)
          .subProjects
          .single
          .screens
          .map((s) => s.caption!.plainText)
          .toList();

      expect(after.first, 'Screen one copy');
      expect(after[1], 'Screen two copy');
    });

    test('creates a screen for every design in the listing', () {
      // The whole point of choosing a template at creation. Seeding the usual
      // three and then applying a six-screen listing dressed three screens and
      // dropped the other three designs on the floor, which is what "only three
      // screens" looked like from the outside.
      final store = container.read(projectStoreProvider.notifier);
      final project = store.createProject(
        name: 'Listing',
        targets: const [
          (targetId: 'ios-iphone', presetId: 'iphone-6-5'),
          (
            targetId: 'android-feature-graphic',
            presetId: 'play-feature-graphic',
          ),
        ],
        initialDeviceId: 'apple-iphone-16',
        initialVariantId: '16---ultramarine',
        templateScreens: _sixScreens.length,
      );

      expect(project.subProjects.first.screens, hasLength(6));
      // A banner is exactly one image whatever listing it borrows a look from.
      expect(project.subProjects.last.screens, hasLength(1));
    });

    test('never seeds fewer screens than the plain starter would', () {
      final store = container.read(projectStoreProvider.notifier);
      final project = store.createProject(
        name: 'Listing',
        targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
        templateScreens: _look.length,
      );

      // A two-screen listing is a reason to repeat its designs, not to hand
      // over a smaller project than the form would otherwise have made.
      expect(project.subProjects.single.screens, hasLength(3));
    });

    test('grows a short set to the length of the listing', () {
      final store = container.read(projectStoreProvider.notifier);
      final project = store.createProject(
        name: 'Listing',
        targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
        initialDeviceId: 'apple-iphone-16',
        initialVariantId: '16---ultramarine',
      );
      final sub = project.subProjects.single;
      expect(sub.screens, hasLength(3));

      store.applyTemplate(project.id, sub.id, _sixScreens, withCopy: true);

      final after = container
          .read(projectStoreProvider)
          .firstWhere((p) => p.id == project.id)
          .subProjects
          .single
          .screens;

      expect(after, hasLength(6));
      // Every design landed, including the three that had nowhere to go.
      for (var i = 0; i < after.length; i++) {
        expect(after[i].caption!.plainText, 'Design $i', reason: 'screen $i');
      }
      // The grown screens are real screens, on the set's own canvas and device.
      for (final screen in after) {
        expect(screen.canvas, const Size(1284, 2778));
        expect(screen.frames, isNotEmpty);
      }
    });

    test('never shrinks a set to match a shorter listing', () {
      final store = container.read(projectStoreProvider.notifier);
      final project = store.createProject(
        name: 'Listing',
        targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
        templateScreens: _sixScreens.length,
      );
      final sub = project.subProjects.single;

      store.applyTemplate(project.id, sub.id, _look);

      // Deleting somebody's screens to match a *look* would be the destructive
      // reading of a restyle.
      expect(
        container
            .read(projectStoreProvider)
            .firstWhere((p) => p.id == project.id)
            .subProjects
            .single
            .screens,
        hasLength(6),
      );
    });

    test('hands back a snapshot that undoes the whole application', () {
      final store = container.read(projectStoreProvider.notifier);
      final project = store.createProject(
        name: 'Listing',
        targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
      );
      final sub = project.subProjects.single;

      final before = store.applyTemplate(project.id, sub.id, _sixScreens);
      expect(before, isNotNull);
      expect(before!.screens, hasLength(3));

      store.restoreSubProject(project.id, before);

      final after = container
          .read(projectStoreProvider)
          .firstWhere((p) => p.id == project.id)
          .subProjects
          .single;

      // The screens it added are gone and the ones it restyled are back.
      expect(after.screens, hasLength(3));
      expect(after.screens.map((s) => s.id), before.screens.map((s) => s.id));
      expect(after.screens.first.background, isA<SolidBackground>());
      expect(
        (after.screens.first.background as SolidBackground).color,
        (before.screens.first.background as SolidBackground).color,
      );
    });

    test('applying a style across a target is undoable too', () {
      final store = container.read(projectStoreProvider.notifier);
      final project = store.createProject(
        name: 'Listing',
        targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
        initialDeviceId: 'apple-iphone-16',
        initialVariantId: '16---ultramarine',
      );
      final sub = project.subProjects.single;

      // Give the first screen a look worth pushing across the set.
      store.updateScreen(
        project.id,
        sub.screens.first.copyWith(
          background: const SolidBackground(Color(0xFFAB12CD)),
        ),
      );

      SubProject read() => container
          .read(projectStoreProvider)
          .firstWhere((p) => p.id == project.id)
          .subProjects
          .single;

      final untouched = read().screens[1].background;
      final before = store.applyStyleToAll(project.id, sub.screens.first.id);
      expect(before, isNotNull);

      expect(
        (read().screens[1].background as SolidBackground).color.toARGB32(),
        0xFFAB12CD,
      );

      store.restoreSubProject(project.id, before!);

      expect(
        (read().screens[1].background as SolidBackground).color,
        (untouched as SolidBackground).color,
      );
    });
  });
}
