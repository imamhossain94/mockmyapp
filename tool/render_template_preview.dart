// Renders every built-in template to PNG contact sheets, for checking that
// what the gallery previews is what applying it builds, without running the
// app.
//
// Each sheet is one listing, a row of screens per case:
//
//   A  the gallery's preview on an Android set (1080 x 1920, Galaxy Note 10+)
//   B  that set after the listing is applied the way a new project applies it
//   C  the gallery's preview on an iPhone set (1320 x 2868, iPhone 16)
//   D  that set after applying
//   E  the Android set applied over words of its own, two of them long, with a
//      German translation on the first screen (shown in German)
//   F  the iPhone set of D once a batch of captures (a plain stand-in drawn
//      here) has arrived
//
// A and C are built exactly as `TemplateGallery` builds its tiles; B, D, E and
// F go through `ProjectStore`, the path the new-project form, the AI wizard and
// the gallery's own Apply take. So A should equal B and C should equal D. On
// the tall iPhone page the phones in C and D sit lower than designed, keeping
// the artwork's filled-in foot off the page; in F the captures cover the
// artwork and the phones are back where the listing put them. A second sheet
// per listing, `<slug>_textscale.png`, sets the first three previews at the
// system's 1.0 and 1.3 text scale side by side; the two halves should be
// identical, since canvas type must not follow the OS.
//
// The template faces are bundled under `assets/google_fonts/`, so captions
// render in the real type with no font plumbing here.
//
// Run from the repo root:
//
//   flutter test tool/render_template_preview.dart --dart-define=OUT=<dir>
//   flutter test tool/render_template_preview.dart --dart-define=OUT=<dir> \
//     --dart-define=ONLY=arrowrush
//
// Nothing here is an assertion; the pictures are the output.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/assets/template_catalog.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/engine/localize.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/screen_template.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _out = String.fromEnvironment('OUT', defaultValue: 'build/templates');

/// Renders only the listing whose id contains this, when set.
const _only = String.fromEnvironment('ONLY');

/// How wide each screen is drawn on a sheet, in logical pixels.
const _tile = 200.0;

/// Somewhere for the store to write its debounced save, which this never
/// reads back.
class _ScratchPaths extends PathProviderPlatform {
  _ScratchPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

Widget _scene(ScreenDoc doc, FrameCatalog catalog, {double textScale = 1}) {
  final height = _tile * doc.canvas.height / doc.canvas.width;
  return Padding(
    padding: const EdgeInsets.all(4),
    child: SizedBox(
      width: _tile,
      height: height,
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: SceneView(doc: doc, catalog: catalog, forExport: true),
        ),
      ),
    ),
  );
}

Widget _label(String text) => Padding(
  padding: const EdgeInsets.fromLTRB(6, 10, 6, 2),
  child: Text(
    text,
    style: GoogleFonts.getFont(
      'Inter',
      fontSize: 14,
      color: const Color(0xFF000000),
    ),
  ),
);

Widget _sheet(GlobalKey key, Map<String, List<Widget>> rows) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Align(
    alignment: Alignment.topLeft,
    child: RepaintBoundary(
      key: key,
      child: ColoredBox(
        color: const Color(0xFFFFFFFF),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in rows.entries) ...[
              _label(row.key),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: row.value,
              ),
            ],
          ],
        ),
      ),
    ),
  ),
);

/// Writes a plain stand-in for somebody's capture to [path]: a pale screen
/// with a bar and a few cards, so row F shows where the phones sit without
/// showing anybody's app.
Future<void> _standInCapture(String path) async {
  const size = Size(600, 1300);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE9ECF3))
    ..drawRect(
      const Rect.fromLTWH(0, 0, 600, 180),
      Paint()..color = const Color(0xFF3D5AFE),
    );
  final card = Paint()..color = const Color(0xFFFFFFFF);
  for (var i = 0; i < 6; i++) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(40, 220.0 + i * 180, 520, 150),
        const Radius.circular(24),
      ),
      card,
    );
  }
  final image = await recorder.endRecording().toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

Future<void> _shoot(WidgetTester tester, GlobalKey key, String path) async {
  // Fonts and artwork load off the frame: give them real time, then frames to
  // lay out and paint what arrived.
  await tester.runAsync(GoogleFonts.pendingFonts);
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
  }
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
  // ignore: avoid_print
  print('wrote $path');
}

void main() {
  // No network under `flutter test`. The bundled faces load from assets.
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('render templates', (tester) async {
    final catalog = (await tester.runAsync(loadFrameCatalog))!;
    final scratch = Directory.systemTemp.createTempSync('template_preview');
    PathProviderPlatform.instance = _ScratchPaths(scratch.path);
    final container = ProviderContainer(
      overrides: [frameCatalogProvider.overrideWith((ref) => catalog)],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(frameCatalogProvider.future));
    final store = container.read(projectStoreProvider.notifier);
    final capture = '${scratch.path}/capture.png';
    await tester.runAsync(() => _standInCapture(capture));

    tester.view.physicalSize = const Size(3400, 4600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final template in screenTemplates) {
      if (_only.isNotEmpty && !template.id.contains(_only)) continue;

      // A fresh project per case, on the handset each store's set opens with:
      // the gallery's preview of it, and the set once the listing is applied.
      ({List<ScreenDoc> preview, List<ScreenDoc> applied, List<ScreenDoc> shot})
      build(
        StoreTarget target,
        String device,
        String variant, {
        bool ownWords = false,
      }) {
        final project = store.createProject(
          name: template.name,
          targets: [(targetId: target.id, presetId: target.defaultPreset.id)],
          initialDeviceId: device,
          initialVariantId: variant,
          templateScreens: template.length,
        );
        final sub = project.subProjects.single;
        // The gallery previews on the set's first screen, as its tiles do.
        final sample = sub.screens.first;
        final preview = [
          for (var i = 0; i < template.length; i++)
            template.applyTo(
              sample,
              index: i,
              withCopy: true,
              withDisplay: true,
              withFrame: templateWearsFrame(target, template),
              catalog: catalog,
            ),
        ];
        if (ownWords) {
          for (final (i, screen) in sub.screens.indexed) {
            final words = switch (i) {
              0 => 'Your headline\ngoes here.',
              1 => 'A much longer headline that keeps on going here',
              _ => 'Highlight feature ${i + 1}',
            };
            store.updateScreen(
              project.id,
              screen.copyWith(
                caption: screen.caption!.copyWith(
                  text: words,
                  runs: const [],
                  translations: i == 0
                      ? const {
                          'de': CaptionTranslation(
                            text: 'Deine Überschrift\nsteht hier.',
                          ),
                        }
                      : const {},
                ),
              ),
            );
          }
        }
        store.applyTemplate(project.id, sub.id, template, withCopy: !ownWords);
        List<ScreenDoc> screens() => store
            .byId(project.id)!
            .subProjectById(sub.id)!
            .screens
            .take(template.length)
            .toList();
        final applied = screens();
        // Then a capture in every phone, the way a batch from Uploads arrives.
        store.importScreenshots(project.id, sub.id, [
          for (var i = 0; i < template.length; i++) capture,
        ]);
        return (preview: preview, applied: applied, shot: screens());
      }

      final android = build(
        StoreTargets.androidPhone,
        'samsung-galaxy-note-10-plus',
        'aura-black',
      );
      final iphone = build(
        StoreTargets.iphone,
        'apple-iphone-16',
        '16---ultramarine',
      );
      final words = build(
        StoreTargets.androidPhone,
        'samsung-galaxy-note-10-plus',
        'aura-black',
        ownWords: true,
      );

      final key = GlobalKey();
      await tester.pumpWidget(
        _sheet(key, {
          '${template.id}: A gallery preview, Android 1080x1920': [
            for (final d in android.preview) _scene(d, catalog),
          ],
          '${template.id}: B applied to a new Android set': [
            for (final d in android.applied) _scene(d, catalog),
          ],
          '${template.id}: C gallery preview, iPhone 1320x2868': [
            for (final d in iphone.preview) _scene(d, catalog),
          ],
          '${template.id}: D applied to a new iPhone set': [
            for (final d in iphone.applied) _scene(d, catalog),
          ],
          '${template.id}: E applied over own words (screen 1 in German)': [
            for (final (i, d) in words.applied.indexed)
              _scene(i == 0 ? localizeScreen(d, 'de') : d, catalog),
          ],
          '${template.id}: F the iPhone set once captures are in': [
            for (final d in iphone.shot) _scene(d, catalog),
          ],
        }),
      );
      await _shoot(tester, key, '$_out/${template.id}.png');

      final scaled = GlobalKey();
      final first = android.preview.take(3).toList();
      await tester.pumpWidget(
        _sheet(scaled, {
          '${template.id}: system text scale 1.0 (left three) vs 1.3 (right '
              'three)': [
            for (final d in first) _scene(d, catalog),
            for (final d in first) _scene(d, catalog, textScale: 1.3),
          ],
        }),
      );
      await _shoot(tester, scaled, '$_out/${template.id}_textscale.png');
    }

    // The store saves on a short debounce, and a timer still pending when the
    // test ends fails it.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
