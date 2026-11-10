// Image panoramas: one picture laid across a set, each screen on its own
// slice — the same pair of numbers a pattern panorama has, written to disk
// only when there is a panorama, painted by the backdrop itself, and kept
// when the set stops being continuous or the background goes to every screen.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/engine/continuous.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/sub_project.dart';

final FrameCatalog _catalog = frameCatalogFromManifest(
  jsonDecode(File('assets/frames/manifest.json').readAsStringSync())
      as Map<String, dynamic>,
);

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// A left-to-right ramp, red rising and green falling, so a pixel's red says
/// how far along the picture it came from.
Uint8List _ramp(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var x = 0; x < width; x++) {
    final r = (x * 255 / (width - 1)).round();
    for (var y = 0; y < height; y++) {
      image.setPixelRgb(x, y, r, 255 - r, 96);
    }
  }
  return img.encodePng(image);
}

ScreenDoc _screen(String id, Background background) =>
    ScreenDoc(id: id, canvas: const Size(100, 200), background: background);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageBackground slices', () {
    test('an image backdrop saved before panoramas reads and writes '
        'byte for byte', () {
      // Exactly what every build so far has written for a photo backdrop.
      const saved =
          '{"type":"image","path":"/library/a.jpg","fit":"cover","scale":1.0,'
          '"offsetX":0.0,"offsetY":0.0,"blur":0.04,"overlayColor":4278190080,'
          '"overlayOpacity":0.2}';
      final read =
          backgroundFromJson(jsonDecode(saved) as Map<String, dynamic>)
              as ImageBackground;
      expect(read.slices, 1);
      expect(read.slice, 0);
      expect(isPanorama(read), isFalse);
      expect(jsonEncode(backgroundToJson(read)), saved);
    });

    test('a one-screen picture writes no slicing at all', () {
      final json = backgroundToJson(const ImageBackground('/library/b.png'));
      expect(json.containsKey('slices'), isFalse);
      expect(json.containsKey('slice'), isFalse);
    });

    test('a panorama round-trips its slicing', () {
      const panorama = ImageBackground(
        '/library/wide.jpg',
        blur: 0.01,
        slices: 5,
        slice: 3,
      );
      final json = backgroundToJson(panorama);
      expect(json['slices'], 5);
      expect(json['slice'], 3);
      final back =
          backgroundFromJson(
                jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
              )
              as ImageBackground;
      expect(back.slices, 5);
      expect(back.slice, 3);
      expect(back.blur, 0.01);
      expect(jsonEncode(backgroundToJson(back)), jsonEncode(json));
    });

    test('a nonsense slicing from a hand-edited file degrades to one '
        'picture', () {
      final read =
          backgroundFromJson({
                'type': 'image',
                'path': '/library/c.png',
                'slices': -4,
                'slice': -2,
              })
              as ImageBackground;
      expect(read.slices, 1);
      expect(read.slice, 0);
    });
  });

  group('panoramaAt with pictures', () {
    const panorama = ImageBackground('/library/wide.jpg', slices: 5, slice: 4);

    test('lays the picture across exactly this set', () {
      for (var i = 0; i < 3; i++) {
        final shown =
            panoramaAt(panorama, index: i, count: 3) as ImageBackground;
        expect(shown.slices, 3);
        expect(shown.slice, i);
        expect(shown.path, panorama.path);
      }
    });

    test('an ordinary picture, and a set of one, are left alone', () {
      const single = ImageBackground('/library/photo.jpg');
      expect(panoramaAt(single, index: 2, count: 5), same(single));
      expect(panoramaAt(panorama, index: 0, count: 1), same(panorama));
    });

    test('a position past the end clamps to the last slice', () {
      final shown = panoramaAt(panorama, index: 9, count: 3) as ImageBackground;
      expect(shown.slice, 2);
    });
  });

  group('composeScreen', () {
    test('a picture panorama paints its own slice, and is not slid again', () {
      const stored = ImageBackground('/library/wide.jpg', slices: 8, slice: 6);
      final set = [
        for (final id in ['a', 'b', 'c', 'd']) _screen(id, stored),
      ];
      for (var i = 0; i < set.length; i++) {
        final composed = composeScreen(set, i, continuous: true);
        final shown = composed.doc.background as ImageBackground;
        expect(shown.slices, 4);
        expect(shown.slice, i);
        expect(composed.backgroundSlice, isNull);
      }
    });

    test('an ordinary picture is still painted a set wide and slid', () {
      const photo = ImageBackground('/library/photo.jpg');
      final set = [_screen('a', photo), _screen('b', photo)];
      final composed = composeScreen(set, 1, continuous: true);
      expect(composed.doc.background, same(photo));
      expect(
        composed.backgroundSlice,
        const BackgroundSlice(index: 1, count: 2),
      );
    });
  });

  group('in the store', () {
    late Directory tempDir;
    late ProviderContainer container;
    late ProjectStore store;
    late String projectId;

    SubProject sub() =>
        container.read(projectStoreProvider).first.subProjects.single;

    List<ImageBackground> backgrounds() => [
      for (final s in sub().screens) s.background as ImageBackground,
    ];

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('image_slices_test');
      PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
      container = ProviderContainer(
        overrides: [frameCatalogProvider.overrideWith((ref) => _catalog)],
      );
      store = container.read(projectStoreProvider.notifier);
      projectId = store
          .createProject(
            name: 'Panorama',
            targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
            initialDeviceId: 'apple-iphone-16',
            initialVariantId: '16---ultramarine',
          )
          .id;
      while (sub().screens.length < 3) {
        store.addScreen(projectId, sub().id);
      }
    });

    tearDown(() {
      container.dispose();
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // The store flushes on a debounce; leave the directory to the OS.
      }
    });

    test('turning continuous off leaves each screen on its slice of the '
        'picture', () {
      const panorama = ImageBackground(
        '/library/wide.jpg',
        slices: 8,
        slice: 2,
      );
      store.updateScreen(
        projectId,
        sub().screens.first.copyWith(background: panorama),
      );
      store.setContinuous(
        projectId,
        sub().id,
        on: true,
        backgroundFrom: sub().screens.first.id,
      );
      store.setContinuous(projectId, sub().id, on: false);

      expect(sub().continuous, isFalse);
      expect([for (final b in backgrounds()) b.slice], [0, 1, 2]);
      expect([for (final b in backgrounds()) b.slices], [3, 3, 3]);
      expect({for (final b in backgrounds()) b.path}, {'/library/wide.jpg'});
    });

    test('an ordinary picture is left whole on every screen', () {
      const photo = ImageBackground('/library/photo.jpg');
      store.updateScreen(
        projectId,
        sub().screens.first.copyWith(background: photo),
      );
      store.setContinuous(
        projectId,
        sub().id,
        on: true,
        backgroundFrom: sub().screens.first.id,
      );
      store.setContinuous(projectId, sub().id, on: false);
      expect([for (final b in backgrounds()) b.slices], [1, 1, 1]);
    });

    test('spreading a panorama gives every screen its own slice', () {
      store.spreadBackground(
        projectId,
        sub().id,
        const ImageBackground('/library/wide.jpg', slices: 3),
      );
      expect([for (final b in backgrounds()) b.slice], [0, 1, 2]);
      expect([for (final b in backgrounds()) b.slices], [3, 3, 3]);
    });

    test('applying a style keeps each screen\'s own picture and slicing', () {
      // The source is a panorama; the targets hold photos of their own. The
      // treatment travels, the pictures and how they are cut do not.
      final screens = sub().screens;
      store.updateScreen(
        projectId,
        screens[0].copyWith(
          background: const ImageBackground(
            '/library/wide.jpg',
            blur: 0.03,
            slices: 3,
          ),
        ),
      );
      for (final s in screens.skip(1)) {
        store.updateScreen(
          projectId,
          s.copyWith(background: ImageBackground('/library/${s.id}.jpg')),
        );
      }
      store.applyStyleToAll(projectId, screens[0].id);
      final after = backgrounds();
      expect(after[1].path, '/library/${screens[1].id}.jpg');
      expect(after[1].slices, 1, reason: 'a photo is not cut into strips');
      expect(after[1].blur, 0.03, reason: 'the treatment travelled');
      expect(after[2].slices, 1);
    });
  });

  group('the picture on screen', () {
    late Directory tempDir;
    late String path;

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('image_slices_render');
      // Three 300×600 panels' worth of picture: exactly the set's shape, so
      // cover-fitting it across the set crops nothing.
      path = '${tempDir.path}/ramp.png';
      File(path).writeAsBytesSync(_ramp(900, 600));
    });

    tearDownAll(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Left to the OS.
      }
    });

    /// Decodes [path] into the image cache, so the scene paints it on its
    /// first frame as an export does.
    Future<void> warm(WidgetTester tester) => tester.runAsync(() async {
      final stream = FileImage(File(path)).resolve(ImageConfiguration.empty);
      final done = Completer<void>();
      late final ImageStreamListener listener;
      listener = ImageStreamListener((_, _) {
        stream.removeListener(listener);
        done.complete();
      }, onError: (_, _) => done.complete());
      stream.addListener(listener);
      await done.future;
    });

    /// [composed] painted at 100×200 logical pixels, as RGBA.
    Future<Uint8List> paint(
      WidgetTester tester,
      ComposedScreen composed,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 100,
                height: 200,
                child: SceneView.composed(
                  composed,
                  catalog: _catalog,
                  forExport: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final bytes = await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      return bytes!;
    }

    int red(Uint8List rgba, int x, int y) => rgba[(y * 100 + x) * 4];

    testWidgets('each screen shows its own third, continuous on or off', (
      tester,
    ) async {
      await warm(tester);
      final panorama = ImageBackground(path, slices: 3);
      final continuousSet = [
        for (final id in ['a', 'b', 'c']) _screen(id, panorama),
      ];
      // The set made separate again: each screen stores its own slice.
      final separateSet = [
        for (var i = 0; i < 3; i++)
          _screen('s$i', panoramaAt(panorama, index: i, count: 3)),
      ];

      final on = <Uint8List>[];
      final off = <Uint8List>[];
      for (var i = 0; i < 3; i++) {
        on.add(
          await paint(
            tester,
            composeScreen(continuousSet, i, continuous: true),
          ),
        );
        off.add(await paint(tester, ComposedScreen.alone(separateSet[i])));
      }

      for (var i = 0; i < 3; i++) {
        expect(off[i], on[i], reason: 'screen $i is one picture either way');
        // Screen i starts a third of the way further along the ramp.
        final left = red(on[i], 1, 100);
        final right = red(on[i], 98, 100);
        expect(left, closeTo(i * 85, 6), reason: 'screen $i left edge');
        expect(right, closeTo((i + 1) * 85, 6), reason: 'screen $i right');
      }
      // And the joins meet: where one screen ends the next begins.
      for (var i = 0; i < 2; i++) {
        expect(red(on[i], 99, 100), closeTo(red(on[i + 1], 0, 100), 6));
      }
    });

    testWidgets('without its slicing, the whole picture is squeezed into '
        'one screen', (tester) async {
      // What a panorama looked like after "continuous off" before pictures
      // learned to slice: the centre of the whole set on every screen.
      await warm(tester);
      final whole = await paint(
        tester,
        ComposedScreen.alone(_screen('w', ImageBackground(path))),
      );
      final first = await paint(
        tester,
        ComposedScreen.alone(
          _screen('f', ImageBackground(path, slices: 3, slice: 0)),
        ),
      );
      expect(red(whole, 1, 100), closeTo(85, 6));
      expect(red(first, 1, 100), closeTo(0, 6));
    });
  });
}
