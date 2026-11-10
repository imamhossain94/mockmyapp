// The app icon, saved with the project: written only when there is one, and
// inside it only what differs from the defaults, so every project saved
// before icons existed loads and saves back byte for byte — and one with an
// icon does too, its picture travelling with backups and duplicates.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/repositories/font_library.dart';
import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_archive.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/models/icon_doc.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/store_target.dart';

import 'support/project_fixture.dart';

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// `projects.json` as a build from before icons wrote it: a plain project, and
/// one with a second language and store copy — exactly the keys an older
/// `toJson` produced.
const _oldProjectsFile =
    '[{"id":"p1","name":"Wayfare","subProjects":[{"id":"s1",'
    '"targetId":"ios-iphone","presetId":"iphone-6-9","canvas":'
    '{"w":1320.0,"h":2868.0},"screens":[]}],'
    '"createdAt":"2026-07-14T12:00:00.000","styles":{"colors":[],'
    '"texts":[],"components":[]}},{"id":"p2","name":"Arrow Rush",'
    '"subProjects":[{"id":"s2","targetId":"android-phone","presetId":'
    '"android-phone-9-16","canvas":{"w":1080.0,"h":1920.0},'
    '"screens":[]}],"createdAt":"2026-08-01T09:30:00.000","styles":'
    '{"colors":[],"texts":[],"components":[]},"languages":["en-US",'
    '"de-DE"],"brief":{"appName":"Arrow Rush"},"storeCopy":{"appStore":'
    '{"en-US":{"name":"Arrow Rush"}}}}]';

String _resave(String file) => jsonEncode([
  for (final p in jsonDecode(file) as List)
    Project.fromJson(p as Map<String, dynamic>).toJson(),
]);

String _roundTrip(Project project) {
  final once = jsonEncode(project.toJson());
  final again = jsonEncode(
    Project.fromJson(jsonDecode(once) as Map<String, dynamic>).toJson(),
  );
  expect(again, once);
  return once;
}

const _glyphIcon = IconDoc(
  background: GradientBackground(
    colorOne: Color(0xFF0B3D4C),
    colorTwo: Color(0xFF1E7A8C),
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  foreground: IconGlyph('compass'),
  scale: 0.66,
  offset: Offset(0, -0.04),
  glyphColor: Color(0xFFFFD166),
  stroke: 1.4,
  innerShadow: IconInnerShadow(opacity: 0.35, blur: 0.025),
  corner: IconCorner.circle,
);

void main() {
  group('an old project', () {
    test('saves back byte for byte', () {
      expect(_resave(_oldProjectsFile), _oldProjectsFile);
    });

    test('reads with no icon, and writes no icon key', () {
      for (final p in jsonDecode(_oldProjectsFile) as List) {
        final project = Project.fromJson(p as Map<String, dynamic>);
        expect(project.icon, isNull);
        expect(project.toJson().containsKey('icon'), isFalse);
      }
    });
  });

  group('a project with an icon', () {
    test('round-trips a glyph icon byte for byte, written last', () {
      final project = projectOf(const []).copyWith(icon: _glyphIcon);
      final json = jsonDecode(_roundTrip(project)) as Map<String, dynamic>;
      expect(json.keys.last, 'icon');
      final restored = Project.fromJson(json);
      expect(restored.icon, _glyphIcon);
      expect(restored.icon!.glyph, 'compass');
    });

    test('round-trips a monogram on a pattern', () {
      const icon = IconDoc(
        background: PatternBackground(
          style: PatternStyle.aurora,
          colors: [Color(0xFF101828), Color(0xFF7C3AED), Color(0xFF22D3EE)],
          seed: 4242,
          scale: 1.3,
          angle: 30,
          intensity: 0.8,
        ),
        foreground: IconText('W', fontFamily: 'Poppins'),
      );
      final project = projectOf(const []).copyWith(icon: icon);
      _roundTrip(project);
      expect(
        Project.fromJson(project.toJson()).icon!.foreground,
        const IconText('W', fontFamily: 'Poppins'),
      );
    });

    test('round-trips a picture foreground', () {
      const icon = IconDoc(
        background: SolidBackground(Color(0xFF0F172A)),
        foreground: IconImage('/library/abc.png'),
        scale: 1,
      );
      final project = projectOf(const []).copyWith(icon: icon);
      _roundTrip(project);
      expect(
        Project.fromJson(project.toJson()).icon!.imagePath,
        '/library/abc.png',
      );
    });

    test('writes only what differs from the defaults', () {
      const plain = IconDoc(background: SolidBackground(Color(0xFF5B5FEF)));
      expect(plain.toJson(), {
        'background': {'type': 'solid', 'color': 0xFF5B5FEF},
      });
      const glyph = IconDoc(
        background: SolidBackground(Color(0xFF5B5FEF)),
        foreground: IconGlyph('rocket'),
      );
      expect(glyph.toJson().keys, ['background', 'foreground']);
      expect(const IconText('AB').toJson(), {'type': 'text', 'text': 'AB'});
      final full = _glyphIcon.toJson();
      expect(full.keys, [
        'background',
        'foreground',
        'scale',
        'offsetY',
        'glyphColor',
        'stroke',
        'innerShadow',
        'corner',
      ]);
    });

    test('taking the icon away saves the project as it was before', () {
      final before = jsonEncode(projectOf(const []).toJson());
      final withIcon = projectOf(const []).copyWith(icon: _glyphIcon);
      expect(jsonEncode(withIcon.toJson()), isNot(before));
      expect(jsonEncode(withIcon.copyWith(clearIcon: true).toJson()), before);
    });
  });

  group('reading tolerantly', () {
    test('anything that is not an icon reads as none', () {
      expect(IconDoc.fromJson(null), isNull);
      expect(IconDoc.fromJson('nonsense'), isNull);
      expect(
        IconDoc.fromJson({
          'foreground': {'type': 'glyph'},
        }),
        isNull,
      );
      expect(IconDoc.fromJson({'background': 'red'}), isNull);
    });

    test('an unknown foreground costs the mark, not the background', () {
      final icon = IconDoc.fromJson({
        'background': {'type': 'solid', 'color': 0xFF112233},
        'foreground': {'type': 'hologram', 'name': 'x'},
        'corner': 'hexagon',
        'scale': 'big',
      })!;
      expect(icon.foreground, isNull);
      expect(icon.corner, IconCorner.squircle);
      expect(icon.scale, kDefaultIconScale);
      expect(
        (icon.background as SolidBackground).color,
        const Color(0xFF112233),
      );
    });

    test('a project with a broken icon still opens', () {
      final json = projectOf(const []).toJson()..['icon'] = {'oops': true};
      final project = Project.fromJson(json);
      expect(project.icon, isNull);
      expect(project.subProjects, hasLength(1));
    });
  });

  group('the project store', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('icon_doc_test');
      ImageLibrary.debugResetStorage();
      PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
      await ImageLibrary.initialize();
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // The store flushes on a debounce; leave the directory to the OS.
      }
    });

    test('sets, updates and clears the icon, and saves it', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(projectStoreProvider.notifier);
      final project = store.createProject(
        name: 'Wayfare',
        targets: [
          (
            targetId: StoreTargets.iphone.id,
            presetId: StoreTargets.iphone.defaultPreset.id,
          ),
        ],
      );
      final bare = jsonEncode(store.byId(project.id)!.toJson());

      // Nothing to update until there is an icon.
      store.updateIcon(project.id, (i) => i.copyWith(scale: 0.9));
      expect(store.byId(project.id)!.icon, isNull);

      store.setIcon(project.id, _glyphIcon);
      store.updateIcon(project.id, (i) => i.copyWith(scale: 0.5));
      expect(store.byId(project.id)!.icon!.scale, 0.5);

      await store.debugFlush();
      final onDisk =
          jsonDecode(File('${tempDir.path}/projects.json').readAsStringSync())
              as List;
      final reread = Project.fromJson(onDisk.single as Map<String, dynamic>);
      expect(reread.icon, _glyphIcon.copyWith(scale: 0.5));

      store.setIcon(project.id, null);
      expect(jsonEncode(store.byId(project.id)!.toJson()), bare);
      await store.debugFlush();
    });

    test('a backup and a duplicate carry the icon and its picture', () async {
      FontLibrary.debugResetStorage();
      await FontLibrary.initialize();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final library = container.read(imageLibraryProvider.notifier);
      final png = img.encodePng(
        img.Image(width: 64, height: 64, numChannels: 4)
          ..clear(img.ColorRgba8(255, 255, 255, 0)),
      );
      final logo = await library.importBytes(
        png,
        projectId: 'p1',
        kind: LibraryImageKind.element,
      );
      final icon = IconDoc(
        background: const SolidBackground(Color(0xFF0F172A)),
        foreground: IconImage(logo.path),
      );
      final original = projectOf(
        const [],
        name: 'Wayfare',
      ).copyWith(icon: icon);

      expect(ProjectArchive.referencedImages(original), {
        logo.path: LibraryImageKind.element,
      });

      final store = container.read(projectStoreProvider.notifier);
      final restored = await store.importProject(
        Uint8List.fromList(await ProjectArchive.bundle(original)),
      );
      final restoredPath = restored.icon!.imagePath!;
      expect(restoredPath, isNot(logo.path));
      expect(File(restoredPath).readAsBytesSync(), png);
      expect(restored.icon!.background, isA<SolidBackground>());

      final copy = (await store.duplicateProject(restored.id))!;
      final copiedPath = copy.icon!.imagePath!;
      expect(copiedPath, isNot(restoredPath));
      expect(File(copiedPath).readAsBytesSync(), png);
      await store.debugFlush();
    });
  });
}
