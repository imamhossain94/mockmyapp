// A template applied is the template the gallery showed.
//
// Each group pins one of the ways the two used to differ: phones that came
// out grey, a device the preview never showed, a flat band under the
// artwork on tall pages, a two-tone headline gone flat, translations deleted,
// copy that ran into the phone, headlines that followed the OS text size, and
// faces that were only ever a download away.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/assets/studio_fonts.dart';
import 'package:mockmyapp/data/assets/template_catalog.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/data/repositories/stored_image.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/engine/scene_renderer.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/screen_template.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/features/shared/save_actions.dart';

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

ScreenTemplate _byId(String id) =>
    screenTemplates.firstWhere((t) => t.id == id);

/// Where the top of the device lands, as a fraction of the page.
double _frameTop(Transform2D t) =>
    (1 - t.pagePercentage * t.scale) / 2 * (1 + t.align.y) + t.offsetPct.dy;

/// The device's height as a share of the page's.
double _heightPct(Transform2D t) => t.pagePercentage * t.scale;

/// A one-phone page on the iPhone 16, with or without a capture in it.
ScreenDoc _iphoneDoc({
  Size canvas = const Size(1320, 2868),
  bool screenshot = true,
  CaptionSpec? caption,
  CaptionSpec? subCaption,
  Transform2D transform = const Transform2D(),
}) => ScreenDoc(
  id: 'screen',
  canvas: canvas,
  caption: caption ?? const CaptionSpec(text: 'My own words'),
  subCaption: subCaption,
  frames: [
    FramePlacement(
      deviceId: 'apple-iphone-16',
      variantId: '16---ultramarine',
      transform: transform,
      screenshot: ScreenshotSpec(images: screenshot ? const ['/shot.png'] : []),
    ),
  ],
);

/// Every caption face the catalog sets, as (family, weight).
Set<(String, int)> _catalogFaces() => {
  for (final t in screenTemplates)
    for (final s in [
      ...t.screens,
      ...t.landscapeScreens,
      ?t.featureGraphic,
    ]) ...{
      (s.caption.fontFamily, s.caption.bold ? (s.caption.weight ?? 700) : 400),
      // The subcaption a template derives is the same face, unbold.
      (s.caption.fontFamily, 400),
      for (final run in s.caption.runs)
        (
          run.fontFamily ?? s.caption.fontFamily,
          (run.bold ?? s.caption.bold) ? (s.caption.weight ?? 700) : 400,
        ),
    },
};

FontWeight _weight(int w) => FontWeight.values[w ~/ 100 - 1];

/// Loads [faces] the way the app does, through google_fonts, and waits for
/// them: from the bundled assets, since a test has no network.
Future<void> _loadFaces(WidgetTester tester, Iterable<(String, int)> faces) =>
    tester
        .runAsync(() async {
          for (final (family, weight) in faces) {
            GoogleFonts.getFont(family, fontWeight: _weight(weight));
          }
          await GoogleFonts.pendingFonts();
        })
        .then((_) {});

/// The laid-out paragraph painting [text] — a caption, in canvas pixels.
RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == text,
      ),
    );

/// The size [text] is set at: the caption's own span, which `Text.rich` wraps
/// in one carrying the ambient style.
///
/// The first paragraph saying it: an outlined caption paints its words twice,
/// the outline under the fill, and both at the one size.
double _fontSizeOf(WidgetTester tester, String text) {
  final root =
      tester
              .widgetList<RichText>(
                find.byWidgetPredicate(
                  (w) => w is RichText && w.text.toPlainText() == text,
                ),
              )
              .first
              .text
          as TextSpan;
  return (root.children!.first as TextSpan).style!.fontSize!;
}

Widget _host(Widget child, {double textScale = 1, TextStyle? ambient}) =>
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: DefaultTextStyle.merge(
            style: ambient ?? const TextStyle(),
            child: Center(child: child),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FrameCatalog catalog;
  setUpAll(() async => catalog = await loadFrameCatalog());

  group('the store applies what the gallery previews', () {
    late Directory tempDir;
    late ProviderContainer container;
    late ProjectStore store;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('template_fidelity');
      PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
      container = ProviderContainer(
        overrides: [frameCatalogProvider.overrideWith((ref) => catalog)],
      );
      await container.read(frameCatalogProvider.future);
      store = container.read(projectStoreProvider.notifier);
    });

    tearDown(() {
      container.dispose();
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // The store flushes on a debounce; leave the directory to the OS.
      }
    });

    ({String projectId, String subId, List<ScreenDoc> screens}) newSet(
      StoreTarget target,
      ScreenTemplate template, {
      required String device,
      required String variant,
    }) {
      final project = store.createProject(
        name: template.name,
        targets: [(targetId: target.id, presetId: target.defaultPreset.id)],
        initialDeviceId: device,
        initialVariantId: variant,
        templateScreens: template.length,
      );
      final sub = project.subProjects.single;
      return (projectId: project.id, subId: sub.id, screens: sub.screens);
    }

    List<ScreenDoc> screensOf(String projectId, String subId) =>
        store.byId(projectId)!.subProjectById(subId)!.screens;

    test('a new set carries the listing’s app into every phone', () {
      // A fresh project, the new-project form and the AI wizard all apply
      // with the listing's words, and they used to open on a set of grey
      // phones: every screen of the catalog.
      var pictures = 0;
      for (final t in screenTemplates) {
        final set = newSet(
          StoreTargets.androidPhone,
          t,
          device: 'samsung-galaxy-note-10-plus',
          variant: 'aura-black',
        );
        store.applyTemplate(set.projectId, set.subId, t, withCopy: true);
        final after = screensOf(set.projectId, set.subId);
        for (var i = 0; i < t.length; i++) {
          final fill = after[i].frames.first.screenshot.fill;
          final display = t.screens[i].display;
          if (display is! ImageBackground) {
            // A screen whose published pixels were held back wears its
            // sampled tone, never the grey plate.
            expect(fill, same(display), reason: '${t.id}[$i]');
            continue;
          }
          expect(fill, isA<ImageBackground>(), reason: '${t.id}[$i]');
          expect(
            (fill as ImageBackground).path,
            display.path,
            reason: '${t.id}[$i]',
          );
          pictures++;
        }
      }
      expect(pictures, greaterThan(0), reason: 'no listing ships its app');
    });

    test('a set with words of its own wears the listing’s screen colour', () {
      for (final t in screenTemplates) {
        final set = newSet(
          StoreTargets.androidPhone,
          t,
          device: 'samsung-galaxy-note-10-plus',
          variant: 'aura-black',
        );
        store.applyTemplate(set.projectId, set.subId, t);
        final after = screensOf(set.projectId, set.subId);
        for (var i = 0; i < t.length; i++) {
          final fill = after[i].frames.first.screenshot.fill;
          final screen = t.screens[i];
          expect(fill, isNotNull, reason: '${t.id}[$i] came out grey');
          expect(fill, isNot(isA<ImageBackground>()), reason: '${t.id}[$i]');
          // The tone the picture was sampled at — or, on a screen that never
          // had its picture shipped, the tone that is its display.
          expect(
            fill,
            same(
              screen.display is ImageBackground
                  ? screen.displayTone
                  : screen.display,
            ),
            reason: '${t.id}[$i]',
          );
        }
      }
    });

    test('an iPhone set gets the device and placement its preview showed', () {
      // The catalog is all Android listings. On an iPhone set the gallery
      // drew the listing's punch-hole slab while applying kept the iPhone,
      // sized for the slab's proportions. Judged on each listing's first
      // screen that places a phone: an edge-to-edge screen has no slab to
      // withhold, and has its own test below.
      var phones = 0;
      for (final t in screenTemplates) {
        final i = t.screens.indexWhere((s) => !s.fullBleed);
        if (i < 0) continue;
        phones++;
        final set = newSet(
          StoreTargets.iphone,
          t,
          device: 'apple-iphone-16',
          variant: '16---ultramarine',
        );
        final sample = set.screens[i];
        final preview = t.applyTo(
          sample,
          index: i,
          withCopy: true,
          withDisplay: true,
          withFrame: templateWearsFrame(StoreTargets.iphone, t),
          catalog: catalog,
        );
        store.applyTemplate(set.projectId, set.subId, t, withCopy: true);
        final applied = screensOf(set.projectId, set.subId)[i];

        final a = preview.frames.first;
        final b = applied.frames.first;
        expect(b.deviceId, 'apple-iphone-16', reason: t.id);
        expect(a.deviceId, b.deviceId, reason: t.id);
        expect(a.design, isNull, reason: '${t.id}: preview drew the slab');
        expect(b.design, isNull, reason: t.id);
        expect(a.transform.scale, b.transform.scale, reason: t.id);
        expect(a.transform.offsetPct, b.transform.offsetPct, reason: t.id);
        expect(
          (a.screenshot.fill as ImageBackground).path,
          (b.screenshot.fill as ImageBackground).path,
          reason: t.id,
        );
      }
      expect(phones, greaterThan(0), reason: 'no listing places a phone');
    });

    test('an edge-to-edge screen fills the page on any set, as previewed', () {
      // The studio's games publish the game filling the picture under a band.
      // There is no handset to keep or withhold: the app's screen is the page,
      // on an iPhone set exactly as on an Android one, and the listing's
      // picture of its game fills it until a capture covers it.
      var pages = 0;
      for (final t in screenTemplates) {
        for (final (i, screen) in t.screens.indexed) {
          if (!screen.fullBleed || screen.isCover) continue;
          pages++;
          for (final (target, device, variant) in [
            (StoreTargets.iphone, 'apple-iphone-16', '16---ultramarine'),
            (
              StoreTargets.androidPhone,
              'samsung-galaxy-note-10-plus',
              'aura-black',
            ),
          ]) {
            final set = newSet(target, t, device: device, variant: variant);
            final preview = t.applyTo(
              set.screens[i],
              index: i,
              withCopy: true,
              withDisplay: true,
              withFrame: templateWearsFrame(target, t),
              catalog: catalog,
            );
            store.applyTemplate(set.projectId, set.subId, t, withCopy: true);
            final applied = screensOf(set.projectId, set.subId)[i];
            final canvas = applied.canvas;
            for (final placement in [
              preview.frames.first,
              applied.frames.first,
            ]) {
              final where = '${t.id}[$i] on ${target.id}';
              expect(placement.hidden, isFalse, reason: where);
              expect(placement.frameHidden, isTrue, reason: where);
              expect(placement.design!.thickness, 0, reason: where);
              expect(
                placement.design!.aspect,
                closeTo(canvas.width / canvas.height, 1e-9),
                reason: where,
              );
              expect(placement.transform.pagePercentage, 1, reason: where);
              expect(
                placement.screenshot.fill,
                same(screen.display),
                reason: where,
              );
            }
          }
        }
      }
      expect(pages, greaterThan(0), reason: 'no listing is edge to edge');
    });

    test('an Android set wears the listing’s drawn handset, both ways', () {
      final t = _byId('sonary');
      final set = newSet(
        StoreTargets.androidPhone,
        t,
        device: 'samsung-galaxy-note-10-plus',
        variant: 'aura-black',
      );
      store.applyTemplate(set.projectId, set.subId, t, withCopy: true);
      final applied = screensOf(set.projectId, set.subId).first.frames.first;
      expect(applied.design, isNotNull);
      expect(applied.design!.aspect, t.screens.first.frame!.aspect);
    });

    test('the save sheet counts the screens still showing the sample', () {
      final t = _byId('arrowrush');
      final set = newSet(
        StoreTargets.androidPhone,
        t,
        device: 'samsung-galaxy-note-10-plus',
        variant: 'aura-black',
      );
      store.applyTemplate(set.projectId, set.subId, t, withCopy: true);
      var screens = screensOf(set.projectId, set.subId);
      expect(templateSampleCount(screens), t.length);
      expect(
        templateSampleNotice(screens),
        "${t.length} screens still show the template's sample app",
      );

      // A capture covers the sample, so that screen no longer counts.
      final first = screens.first;
      store.updateScreen(
        set.projectId,
        first.copyWith(
          frames: [
            first.frames.first.copyWith(
              screenshot: first.frames.first.screenshot.copyWith(
                images: const ['/mine.png'],
              ),
            ),
          ],
        ),
      );
      screens = screensOf(set.projectId, set.subId);
      expect(templateSampleCount(screens), t.length - 1);

      // Nor does a device that is switched off.
      final second = screens[1];
      expect(templateSampleCount([second]), 1);
      expect(
        templateSampleCount([
          second.copyWith(frames: [second.frames.first.copyWith(hidden: true)]),
        ]),
        0,
      );
      expect(
        templateSampleNotice([second]),
        "1 screen still shows the template's sample app",
      );

      // A set restyled over its own words shows tones, never the sample.
      store.applyTemplate(set.projectId, set.subId, t);
      expect(templateSampleCount(screensOf(set.projectId, set.subId)), isZero);
      expect(templateSampleNotice(const []), isNull);
    });

    group('a phone lowered for the artwork', () {
      // On the 6.9-inch iPhone page a phone showing the listing's artwork
      // sits lower than designed, to keep the artwork's filled-in foot off
      // the page. Once a capture covers the artwork that gap is only a cost.
      late ({String projectId, String subId, List<ScreenDoc> screens}) set;
      final t = _byId('sonary');

      setUp(() {
        set = newSet(
          StoreTargets.iphone,
          t,
          device: 'apple-iphone-16',
          variant: '16---ultramarine',
        );
        store.applyTemplate(set.projectId, set.subId, t, withCopy: true);
      });

      ScreenDoc first() => screensOf(set.projectId, set.subId).first;

      double designedTop(ScreenDoc doc) => _frameTop(
        t.screens.first.transformFor(
          doc.canvas,
          worn: WornFrame.on(doc.frames.first, catalog),
        ),
      );

      ScreenDoc withCapture(ScreenDoc doc, {Transform2D? transform}) =>
          doc.copyWith(
            frames: [
              doc.frames.first.copyWith(
                transform: transform,
                screenshot: doc.frames.first.screenshot.copyWith(
                  images: const ['/mine.png'],
                ),
              ),
            ],
          );

      test('goes back where the listing designed it once a capture covers '
          'the artwork, tilt and all', () {
        final lowered = first();
        expect(
          _frameTop(lowered.frames.first.transform),
          greaterThan(designedTop(lowered) + 0.1),
        );

        // A tilt dialled in first is not a move: the phone still sits where
        // the template put it.
        store.updateScreen(
          set.projectId,
          lowered.copyWith(
            frames: [
              lowered.frames.first.copyWith(
                transform: lowered.frames.first.transform.copyWith(tiltX: 12),
              ),
            ],
          ),
        );
        store.updateScreen(set.projectId, withCapture(first()));
        final covered = first().frames.first;
        expect(
          _frameTop(covered.transform),
          closeTo(designedTop(first()), 1e-9),
        );
        expect(covered.transform.tiltX, 12);
        expect(
          covered.transform.scale,
          lowered.frames.first.transform.scale,
          reason: 'it moves, it does not resize',
        );

        // Taking the capture away shows the artwork again, and lowers it.
        final again = first();
        store.updateScreen(
          set.projectId,
          again.copyWith(
            frames: [
              again.frames.first.copyWith(
                screenshot: again.frames.first.screenshot.copyWith(
                  clearImages: true,
                ),
              ),
            ],
          ),
        );
        expect(
          _frameTop(first().frames.first.transform),
          closeTo(_frameTop(lowered.frames.first.transform), 1e-9),
        );
      });

      test('stays where somebody put it', () {
        final lowered = first();
        final moved = lowered.frames.first.transform.copyWith(
          offsetPct: lowered.frames.first.transform.offsetPct.translate(
            0,
            -0.05,
          ),
        );
        store.updateScreen(
          set.projectId,
          withCapture(lowered, transform: moved),
        );
        expect(first().frames.first.transform.offsetPct, moved.offsetPct);
      });

      test('settles a whole batch of captures', () {
        final screens = screensOf(set.projectId, set.subId);
        store.importScreenshots(set.projectId, set.subId, [
          for (var i = 0; i < screens.length; i++) '/shot$i.png',
        ]);
        for (final (i, doc) in screensOf(set.projectId, set.subId).indexed) {
          expect(
            _frameTop(doc.frames.first.transform),
            closeTo(
              _frameTop(
                t.screens[i].transformFor(
                  doc.canvas,
                  worn: WornFrame.on(doc.frames.first, catalog),
                ),
              ),
              1e-9,
            ),
            reason: 'screen $i',
          );
        }
      });
    });

    test('a capture moves nothing on the page the listing was measured on', () {
      final t = _byId('arrowrush');
      final set = newSet(
        StoreTargets.androidPhone,
        t,
        device: 'samsung-galaxy-note-10-plus',
        variant: 'aura-black',
      );
      store.applyTemplate(set.projectId, set.subId, t, withCopy: true);
      final before = screensOf(set.projectId, set.subId).first;
      store.updateScreen(
        set.projectId,
        before.copyWith(
          frames: [
            before.frames.first.copyWith(
              screenshot: before.frames.first.screenshot.copyWith(
                images: const ['/mine.png'],
              ),
            ),
          ],
        ),
      );
      final after = screensOf(set.projectId, set.subId).first;
      expect(
        after.frames.first.transform.offsetPct,
        before.frames.first.transform.offsetPct,
      );
    });
  });

  group('the device a template places', () {
    test('wears the listing’s frame only on a phone set of its store', () {
      final android = _byId('sonary');
      expect(android.platforms, {TemplatePlatform.android});
      expect(templateWearsFrame(StoreTargets.androidPhone, android), isTrue);
      expect(templateWearsFrame(StoreTargets.iphone, android), isFalse);
      expect(templateWearsFrame(StoreTargets.androidTablet, android), isFalse);
      expect(templateWearsFrame(StoreTargets.appleWatch, android), isFalse);
      expect(templateWearsFrame(StoreTargets.mac, android), isFalse);
    });

    test('is placed by its own proportions when the frame is withheld', () {
      // The listing composed its device at a width of the page; the iPhone 16
      // is wider for its height than the slab, and solving against the slab
      // put it about 3% wider than designed.
      final screen = _byId('sonary').screens.first;
      final out = screen.applyTo(
        _iphoneDoc(),
        withFrame: false,
        catalog: catalog,
      );
      final placement = out.frames.single;
      expect(placement.design, isNull);
      final iphone = catalog.byId('apple-iphone-16');
      final width =
          _heightPct(placement.transform) * iphone.frameAspect * 2868 / 1320;
      expect(width, closeTo(screen.deviceWidthPct, 1e-9));
      expect(
        _frameTop(placement.transform),
        closeTo(screen.deviceTopPct, 1e-9),
      );
    });

    test('falls back to the listing’s proportions with no catalog', () {
      final screen = _byId('sonary').screens.first;
      final out = screen.applyTo(_iphoneDoc(), withFrame: false);
      final width =
          _heightPct(out.frames.single.transform) *
          screen.frame!.aspect *
          2868 /
          1320;
      expect(width, closeTo(screen.deviceWidthPct, 1e-9));
    });

    test('keeps the 3D tilt it was given', () {
      final out = _byId('arrowrush').applyTo(
        _iphoneDoc(transform: const Transform2D(tiltX: 12, tiltY: -28)),
      );
      expect(out.frames.single.transform.tiltX, 12);
      expect(out.frames.single.transform.tiltY, -28);
    });
  });

  group('the artwork’s filled-in foot', () {
    test('every calibrated screen says how far its artwork goes', () {
      for (final t in screenTemplates) {
        for (final (i, s) in t.screens.indexed) {
          if (s.display is! ImageBackground) continue;
          expect(s.displayTone, isNotNull, reason: '${t.id}[$i]');
          expect(
            s.displayVisiblePct,
            inInclusiveRange(0.5, 1.0),
            reason: '${t.id}[$i]',
          );
        }
      }
    });

    test('stays below the page edge on a tall page while the art shows', () {
      // The 6.9-inch iPhone page shows about 94% of a device placed for the
      // 9:16 page, and the artwork is only real down to about 73-77%.
      for (final t in screenTemplates) {
        for (final (i, s) in t.screens.indexed) {
          final visible = s.displayVisiblePct;
          if (visible == null) continue;
          for (final (withFrame, canvas) in const [
            (true, Size(1320, 2868)),
            (false, Size(1320, 2868)),
            (true, Size(1080, 2400)),
          ]) {
            final out = s.applyTo(
              _iphoneDoc(canvas: canvas, screenshot: false),
              withCopy: true,
              withDisplay: true,
              withFrame: withFrame,
              catalog: catalog,
            );
            final placement = out.frames.single;
            final worn = WornFrame.on(placement, catalog)!;
            final top = _frameTop(placement.transform);
            final height = _heightPct(placement.transform);
            final artEnds =
                worn.screenTop + visible * (worn.screenBottom - worn.screenTop);
            expect(
              top + artEnds * height,
              greaterThanOrEqualTo(1 - 1e-9),
              reason: '${t.id}[$i] on $canvas, frame $withFrame',
            );
          }
        }
      }
    });

    test('changes nothing on the page the listing was designed on', () {
      final s = _byId('sonary').screens.first;
      final out = s.applyTo(
        _iphoneDoc(canvas: const Size(1080, 1920), screenshot: false),
        withCopy: true,
        withDisplay: true,
      );
      expect(
        _frameTop(out.frames.single.transform),
        closeTo(s.deviceTopPct, 1e-9),
      );
    });

    test('leaves the device where designed once a capture covers it', () {
      final s = _byId('sonary').screens.first;
      final out = s.applyTo(_iphoneDoc(), withCopy: true, withDisplay: true);
      expect(
        _frameTop(out.frames.single.transform),
        closeTo(s.deviceTopPct, 1e-9),
      );
    });
  });

  group('somebody’s own words', () {
    test('keep their translations, the subcaption’s too', () {
      const de = {'de': CaptionTranslation(text: 'Meine eigenen Worte')};
      final doc = _iphoneDoc(
        caption: const CaptionSpec(text: 'My own words', translations: de),
        subCaption: const CaptionSpec(
          text: 'And more',
          translations: {'de': CaptionTranslation(text: 'Und mehr')},
        ),
      );
      final out = _byId('sonary').applyTo(doc);
      expect(out.caption!.translations['de']!.text, 'Meine eigenen Worte');
      expect(out.subCaption!.translations['de']!.text, 'Und mehr');
      // The listing's own copy is a different headline: its translations
      // would be of words that are no longer there.
      expect(
        _byId('sonary').applyTo(doc, withCopy: true).caption!.translations,
        isEmpty,
      );
    });

    test('take a two-tone listing’s colours line by line', () {
      final t = _byId('arrowrush');
      final out = t.applyTo(
        _iphoneDoc(
          caption: const CaptionSpec(text: 'Your headline\ngoes here.'),
        ),
      );
      final runs = out.caption!.runs;
      expect(runs, hasLength(2));
      expect(runs.map((r) => r.text).join(), 'Your headline\ngoes here.');
      expect(runs.last.color, t.screens.first.caption.runs.last.color);
      expect(runs.first.color, isNot(runs.last.color));
    });

    test('leave the subcaption in one style', () {
      final out = _byId(
        'arrowrush',
      ).applyTo(_iphoneDoc(subCaption: const CaptionSpec(text: 'one\ntwo')));
      expect(out.subCaption!.runs, isEmpty);
      expect(out.subCaption!.fitHeightPct, isNull);
    });
  });

  group('the headline’s fit box', () {
    TemplateScreen measured({
      bool captionAbove = true,
      bool hasDevice = true,
      bool landscape = false,
      double deviceTopPct = 0.24,
      double textTopPct = 0.07,
    }) => TemplateScreen.measured(
      background: const SolidBackground(Color(0xFF000000)),
      display: const SolidBackground(Color(0xFF111111)),
      text: 'Two\nlines',
      textColor: const Color(0xFFFFFFFF),
      sizePct: 0.09,
      lineRatio: 1.1,
      textTopPct: textTopPct,
      textBottomPct: 0.9,
      captionAbove: captionAbove,
      hasDevice: hasDevice,
      landscape: landscape,
      deviceTopPct: deviceTopPct,
    );

    test('is the room above the device, for a headline set above one', () {
      expect(
        measured().caption.fitHeightPct,
        closeTo(0.24 - 0.012 - 0.07, 1e-9),
      );
    });

    test('never shrinks the listing’s own two lines', () {
      // Text butting against the device: the box is what its own copy takes.
      final own = 0.09 * 1.1 * 2 * 1080 / 1920;
      expect(
        measured(deviceTopPct: 0.1).caption.fitHeightPct,
        closeTo(own, 1e-9),
      );
    });

    test('is absent where there is no device under the headline', () {
      expect(measured(captionAbove: false).caption.fitHeightPct, isNull);
      expect(measured(hasDevice: false).caption.fitHeightPct, isNull);
      expect(measured(landscape: true).caption.fitHeightPct, isNull);
    });

    test('is the room down to a band’s foot, where the listing says so', () {
      // An edge-to-edge listing sets its words on a band over the game, and
      // somebody's longer words used to wrap off the band onto the game.
      TemplateScreen banded({double fitBottomPct = 0.17}) =>
          TemplateScreen.measured(
            background: const SolidBackground(Color(0xFF000000)),
            display: const SolidBackground(Color(0xFF111111)),
            text: 'One',
            textColor: const Color(0xFFFFFFFF),
            sizePct: 0.05,
            lineRatio: 1.1,
            textTopPct: 0.03,
            hasDevice: false,
            cover: false,
            fitBottomPct: fitBottomPct,
          );
      expect(banded().caption.fitHeightPct, closeTo(0.17 - 0.03, 1e-9));
      // Never smaller than the listing's own words take.
      final own = 0.05 * 1.1 * 1080 / 1920;
      expect(
        banded(fitBottomPct: 0.04).caption.fitHeightPct,
        closeTo(own, 1e-9),
      );
    });

    test('a band listing keeps its own words inside its band', () {
      for (final t in screenTemplates) {
        for (final (i, s) in t.screens.indexed) {
          if (!s.fullBleed || s.isCover) continue;
          expect(s.caption.fitHeightPct, isNotNull, reason: '${t.id}[$i]');
        }
      }
    });

    test('is saved only when set, and old captions read back without it', () {
      const plain = CaptionSpec(text: 'x');
      expect(captionToJson(plain).containsKey('fitHeightPct'), isFalse);
      final fitted = plain.copyWith(fitHeightPct: 0.15);
      final json = captionToJson(fitted);
      expect(json['fitHeightPct'], 0.15);
      expect(captionFromJson(json).fitHeightPct, 0.15);
      expect(captionFromJson(captionToJson(plain)).fitHeightPct, isNull);

      // A caption without one round-trips byte for byte.
      final encoded = jsonEncode(captionToJson(plain));
      expect(
        jsonEncode(captionToJson(captionFromJson(jsonDecode(encoded)))),
        encoded,
      );
    });

    test('is dropped by a size chosen by hand, and only then', () {
      const fitted = CaptionSpec(text: 'x', fitHeightPct: 0.15);
      expect(fitted.copyWith(text: 'y').fitHeightPct, 0.15);
      expect(fitted.copyWith(clearFitHeightPct: true).fitHeightPct, isNull);
    });

    testWidgets('keeps long copy above the device', (tester) async {
      await _loadFaces(tester, const [('Roboto', 700)]);
      const words = 'A much longer headline that keeps on going and going here';
      ScreenDoc doc(double? fit) => ScreenDoc(
        id: 'fit',
        canvas: const Size(1080, 1920),
        caption: CaptionSpec(
          text: words,
          size: 110,
          lineHeight: 120,
          fitHeightPct: fit,
        ),
      );
      Future<double> heightOf(double? fit) async {
        await tester.pumpWidget(
          _host(
            SizedBox(
              width: 270,
              height: 480,
              child: SceneView(doc: doc(fit), catalog: catalog),
            ),
          ),
        );
        return _paragraph(tester, words).size.height;
      }

      final free = await heightOf(null);
      expect(free, greaterThan(0.12 * 1920), reason: 'guards the guard');
      expect(await heightOf(0.12), lessThanOrEqualTo(0.12 * 1920 + 0.5));
    });

    testWidgets('never sets a headline below 60% of its size', (tester) async {
      await _loadFaces(tester, const [('Roboto', 700)]);
      const words =
          'A headline far too long for the tiny room it has been given';
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 270,
            height: 480,
            child: SceneView(
              doc: const ScreenDoc(
                id: 'floor',
                canvas: Size(1080, 1920),
                caption: CaptionSpec(
                  text: words,
                  size: 100,
                  lineHeight: 110,
                  fitHeightPct: 0.01,
                ),
              ),
              catalog: catalog,
            ),
          ),
        ),
      );
      expect(
        _fontSizeOf(tester, words),
        greaterThanOrEqualTo(0.6 * 100 * 1080 / 1179 - 1e-6),
      );
    });

    testWidgets('leaves every listing’s own copy at its own size', (
      tester,
    ) async {
      // The box exists for somebody else's longer words. The words each
      // listing was measured with fit it on the page it was measured on, and
      // on the taller iPhone page.
      await _loadFaces(tester, _catalogFaces());
      for (final canvas in const [Size(1080, 1920), Size(1320, 2868)]) {
        final sample = _iphoneDoc(canvas: canvas);
        for (final t in screenTemplates) {
          for (var i = 0; i < t.length; i++) {
            final doc = t.applyTo(sample, index: i, withCopy: true);
            final caption = doc.caption!;
            await tester.pumpWidget(
              _host(
                SizedBox(
                  width: 270,
                  height: 270 * canvas.height / canvas.width,
                  child: SceneView(doc: doc, catalog: catalog),
                ),
              ),
            );
            expect(
              _fontSizeOf(tester, caption.renderedText),
              closeTo(caption.size * canvas.width / 1179, 1e-6),
              reason: '${t.id}[$i] on $canvas',
            );
          }
        }
      }
    });
  });

  group('canvas type', () {
    const words = 'DAILY CHALLENGES';
    final doc = ScreenDoc(
      id: 'type',
      canvas: const Size(1080, 1920),
      caption: CaptionSpec(
        text: words,
        size: 110,
        lineHeight: 115,
        fontFamily: 'Archivo Black',
        bold: false,
      ),
    );

    testWidgets('does not follow the OS text size on the canvas', (
      tester,
    ) async {
      await _loadFaces(tester, const [('Archivo Black', 400)]);
      Future<Size> laidOut(double scale) async {
        await tester.pumpWidget(
          _host(
            SizedBox(
              width: 270,
              height: 480,
              child: SceneView(doc: doc, catalog: catalog),
            ),
            textScale: scale,
          ),
        );
        return _paragraph(tester, words).size;
      }

      final plain = await laidOut(1);
      expect(await laidOut(2), plain);
      expect(await laidOut(1.3), plain);
    });

    testWidgets('does not follow it into an export either', (tester) async {
      await _loadFaces(tester, const [('Archivo Black', 400)]);
      Future<Size> captured(double scale) async {
        await tester.pumpWidget(
          _host(
            SizedBox(
              width: 300,
              height: 300,
              // ignore: invalid_use_of_visible_for_testing_member
              child: SceneRenderer.captureStage(
                boundaryKey: GlobalKey(),
                doc: doc,
                catalog: catalog,
              ),
            ),
            textScale: scale,
          ),
        );
        return _paragraph(tester, words).size;
      }

      expect(await captured(2), await captured(1));
    });

    testWidgets('inherits nothing from the app’s text style', (tester) async {
      await _loadFaces(tester, const [('Archivo Black', 400)]);
      Future<Size> laidOut(TextStyle? ambient) async {
        await tester.pumpWidget(
          _host(
            SizedBox(
              width: 270,
              height: 480,
              child: SceneView(doc: doc, catalog: catalog),
            ),
            ambient: ambient,
          ),
        );
        return _paragraph(tester, words).size;
      }

      expect(
        await laidOut(const TextStyle(letterSpacing: 12, wordSpacing: 40)),
        await laidOut(null),
      );
    });
  });

  group('the bundled faces', () {
    test('every face a template sets is a file google_fonts will find', () {
      const parts = {
        400: 'Regular',
        700: 'Bold',
        800: 'ExtraBold',
        900: 'Black',
      };
      final declared = File('pubspec.yaml').readAsStringSync();
      expect(declared, contains('- assets/google_fonts/'));
      for (final (family, weight) in _catalogFaces()) {
        final file =
            'assets/google_fonts/${family.replaceAll(' ', '')}-${parts[weight]}.ttf';
        expect(File(file).existsSync(), isTrue, reason: '$family $weight');
      }
    });

    test('no template asks a single-weight face for a bold it lacks', () {
      for (final t in screenTemplates) {
        for (final (i, s) in t.screens.indexed) {
          if (s.caption.fontFamily != 'Archivo Black') continue;
          expect(s.caption.bold, isFalse, reason: '${t.id}[$i]');
        }
      }
    });

    testWidgets('load offline, the templates’ and the UI’s alike', (
      tester,
    ) async {
      // `pendingFonts` rethrows a failed load, and with runtime fetching off
      // the only place a face can come from is the asset bundle.
      await _loadFaces(tester, {
        ..._catalogFaces(),
        ('Inter', 400),
        ('Inter', 500),
        ('Inter', 600),
        ('Inter', 700),
        ('JetBrains Mono', 500),
      });
    });

    testWidgets('load offline, every face the font picker offers', (
      tester,
    ) async {
      await _loadFaces(tester, {
        for (final font in kBundledFonts)
          for (final weight in font.weights) (font.family, weight.value),
      });
    });

    test('every bundled family carries its licence', () async {
      registerBundledFontLicences();
      final names = <String>{};
      await for (final entry in LicenseRegistry.licenses.handleError((_) {})) {
        names.addAll(entry.packages);
      }
      for (final font in kBundledFonts) {
        expect(names, contains('${font.family} font'));
        expect(
          File('assets/google_fonts/${font.file}-OFL.txt').existsSync(),
          isTrue,
        );
      }
    });
  });

  group('candy lettering', () {
    final outlined = TemplateScreen.measured(
      background: const SolidBackground(Color(0xFF000000)),
      display: const SolidBackground(Color(0xFF111111)),
      text: 'Chain giant\ncombos!',
      textColor: const Color(0xFFFFFFFF),
      sizePct: 0.09,
      textTopPct: 0.03,
      textStrokeWidth: 21.5,
      textStrokeColor: const Color(0xFF5B2A9E),
    );

    test('is the listing’s outline, and somebody’s own words wear it too', () {
      expect(outlined.caption.strokeWidth, 21.5);
      expect(outlined.caption.strokeColor, const Color(0xFF5B2A9E));
      final own = outlined.applyTo(_iphoneDoc());
      expect(own.caption!.text, 'My own words');
      expect(own.caption!.strokeWidth, 21.5);
      expect(own.caption!.strokeColor, const Color(0xFF5B2A9E));
    });

    test('is how the outlined listings set every screen', () {
      final jelly = _byId('jellyfloat');
      for (final (i, s) in jelly.screens.indexed) {
        expect(s.caption.strokeWidth, greaterThan(0), reason: 'jellyfloat[$i]');
      }
    });
  });

  group('a flat rim', () {
    testWidgets('casts its shadow from its round corners, not the screen’s '
        'square ones', (tester) async {
      // A crisp red shadow straight under the device: wherever it shows past
      // the rim, it was cast from the wrong outline. The point sampled is
      // just inside the screen's square corner and outside the rim's round
      // one — 12px in from the body's corner, where a 84px radius has left
      // the body and an 8.4px rim has not reached the screen.
      const canvas = Size(600, 1200);
      final doc = ScreenDoc(
        id: 'rim',
        canvas: canvas,
        background: const SolidBackground(Color(0xFFFFFFFF)),
        caption: const CaptionSpec(text: '', enabled: false),
        frames: const [
          FramePlacement(
            deviceId: 'samsung-galaxy-note-10-plus',
            variantId: 'aura-black',
            transform: Transform2D(pagePercentage: 0.7),
            shadow: ShadowSpec(
              opacity: 1,
              color: Color(0xFFFF0000),
              blur: 0,
              offsetPct: Offset.zero,
            ),
            design: FrameDesign(
              thickness: 0.02,
              cornerRadius: 0.2,
              color: Color(0xFFFFFFFF),
              aspect: 0.5,
              flat: true,
              punchHole: PunchHoleSpec(enabled: false),
              power: SideButtonSpec(enabled: false),
              volume: SideButtonSpec(enabled: false),
            ),
          ),
        ],
      );
      final key = GlobalKey();
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = canvas;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: SizedBox.fromSize(
                size: canvas,
                child: SceneView(doc: doc, catalog: catalog, forExport: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      late List<int> corner;
      late List<int> past;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final bytes = data!.buffer.asUint8List();
        List<int> at(int x, int y) {
          final i = (y * image.width + x) * 4;
          return [bytes[i], bytes[i + 1], bytes[i + 2]];
        }

        // The device is 840 x 420, centred: its corner is at (90, 180).
        corner = at(90 + 12, 180 + 12);
        past = at(90 + 210, 180 + 840 + 6);
        image.dispose();
      });
      expect(corner, [255, 255, 255], reason: 'shadow past the round corner');
      // Nor anywhere else: a shadow with no blur and no offset is the body's
      // own outline, wholly under it.
      expect(past, [255, 255, 255], reason: 'shadow past the foot');
    });
  });

  group('a picture fill', () {
    const path = 'asset:assets/templates/sonary/01.webp';
    const white = Color(0xFFFFFFFF);
    final plate = find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == white,
    );
    const doc = ScreenDoc(
      id: 'fill',
      canvas: Size(600, 1200),
      background: SolidBackground(Color(0xFF000000)),
      frames: [
        FramePlacement(
          deviceId: 'apple-iphone-16',
          variantId: '16---ultramarine',
          screenshot: ScreenshotSpec(fill: ImageBackground(path)),
        ),
      ],
    );

    Widget scene() => _host(
      SizedBox(
        width: 300,
        height: 600,
        child: SceneView(doc: doc, catalog: catalog, forExport: true),
      ),
    );

    testWidgets('paints no white plate before its picture decodes', (
      tester,
    ) async {
      imageCache.clear();
      await tester.pumpWidget(scene());
      expect(plate, findsNothing);
      for (var i = 0; i < 10 && plate.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(plate, findsOneWidget);
    });

    testWidgets('arrives whole on the first frame once cached, as an export '
        'does', (tester) async {
      await tester.runAsync(() async {
        final provider = StoredImage.provider(path)!;
        final stream = provider.resolve(ImageConfiguration.empty);
        final done = Completer<void>();
        late final ImageStreamListener listener;
        listener = ImageStreamListener((_, _) {
          stream.removeListener(listener);
          done.complete();
        }, onError: (_, _) => done.complete());
        stream.addListener(listener);
        await done.future;
      });
      await tester.pumpWidget(scene());
      expect(plate, findsOneWidget);
    });
  });
}
