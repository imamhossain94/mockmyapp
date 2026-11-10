import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/repositories/project_archive.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

/// A project document in the shape written before sub-projects existed: one
/// `platform` over one flat `screens` list.
///
/// The **envelope** is spelled out as a literal on purpose — it is the part
/// that changed, so it is the contract with every file already on a user's
/// disk, and a fixture built from today's `Project.toJson` could not detect the
/// day the reader stops understanding yesterday's. The screens inside it go
/// through the real `screenDocToJson`, because `ScreenDoc`'s format did *not*
/// change and re-typing it here would only test my typing.
Map<String, dynamic> legacyProject({
  String platform = 'ios',
  List<Size> canvases = const [Size(1284, 2778), Size(1284, 2778)],
}) => {
  'id': 'legacy-project-id',
  'name': 'Shipped Last Year',
  'platform': platform,
  'createdAt': '2025-03-04T10:11:12.000',
  'screens': [
    for (var i = 0; i < canvases.length; i++)
      screenDocToJson(
        ScreenDoc(
          id: 'legacy-screen-$i',
          canvas: canvases[i],
          caption: CaptionSpec(
            text: 'Headline $i',
            size: 64,
            lineHeight: 74,
            color: kDefaultCaptionColor,
          ),
          frames: [
            FramePlacement(
              deviceId: 'apple-iphone-16',
              variantId: '16---ultramarine',
              screenshot: ScreenshotSpec(cornerRadiusPct: 0.12),
            ),
          ],
        ),
      ),
  ],
};

/// A version-1 bundle: the manifest that build wrote, over a legacy document.
Uint8List legacyBundle(Map<String, dynamic> project) {
  ArchiveFile entry(String name, Object value) =>
      ArchiveFile.typedData(name, utf8.encode(jsonEncode(value)));

  final archive = Archive()
    ..add(entry('project.json', project))
    ..add(
      entry('manifest.json', {
        'format': 'mockup-studio-project',
        'version': 1,
        'createdAt': '2025-03-04T10:11:12.000',
        'images': const [],
      }),
    );
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  group('a project written before targets existed', () {
    test('loads as one sub-project on the right target', () {
      final project = Project.fromJson(legacyProject());

      expect(project.name, 'Shipped Last Year');
      expect(project.subProjects, hasLength(1));

      final sub = project.subProjects.single;
      expect(sub.targetId, 'ios-iphone');
      expect(sub.presetId, 'iphone-6-5', reason: '1284x2778 is the 6.5" class');
      expect(sub.canvas, const Size(1284, 2778));
      expect(sub.screens, hasLength(2));
    });

    test('keeps every screen, in order, unmodified', () {
      final project = Project.fromJson(legacyProject());
      final screens = project.subProjects.single.screens;

      expect(
        [for (final s in screens) s.id],
        ['legacy-screen-0', 'legacy-screen-1'],
      );
      expect(screens.first.caption!.text, 'Headline 0');
      expect(screens.first.frames.first.deviceId, 'apple-iphone-16');
      expect(screens.first.frames.first.screenshot.cornerRadiusPct, 0.12);
    });

    test('the sub-project inherits the project id', () {
      // Unique by construction, needs no uuid down in the model, and makes a
      // migrated project recognisable inside a bundle.
      final project = Project.fromJson(legacyProject());
      expect(project.subProjects.single.id, project.id);
    });

    test('recovers the form factor from the canvas', () {
      final tablet = Project.fromJson(
        legacyProject(canvases: const [Size(2048, 2732)]),
      );
      expect(tablet.subProjects.single.targetId, 'ios-ipad');

      final androidPhone = Project.fromJson(
        legacyProject(platform: 'android', canvases: const [Size(1080, 1920)]),
      );
      expect(androidPhone.subProjects.single.targetId, 'android-phone');

      final androidTablet = Project.fromJson(
        legacyProject(platform: 'android', canvases: const [Size(1600, 2560)]),
      );
      expect(androidTablet.subProjects.single.targetId, 'android-tablet');
    });

    test('recovers a landscape set as landscape', () {
      final project = Project.fromJson(
        legacyProject(canvases: const [Size(2778, 1284)]),
      );
      final sub = project.subProjects.single;
      expect(sub.isLandscape, isTrue);
      expect(sub.canvas, const Size(2778, 1284));
    });

    test('a canvas the old table never produced still opens', () {
      // Hand-edited, or written by a build this is not. Losing the project here
      // would be far worse than landing it on an approximate preset.
      // (Not 1170 × 2532 any more, which became a 6.1-inch preset.)
      final project = Project.fromJson(
        legacyProject(canvases: const [Size(1100, 2400)]),
      );
      final sub = project.subProjects.single;
      expect(sub.targetId, 'ios-iphone');
      // The stored canvas wins over the preset's: the document is the truth.
      expect(sub.canvas, const Size(1100, 2400));
      expect(sub.screens.single.canvas, const Size(1100, 2400));
    });

    test('a project with no screens at all still opens', () {
      final project = Project.fromJson(legacyProject(canvases: const []));
      expect(project.subProjects, hasLength(1));
      expect(project.subProjects.single.screens, isEmpty);
      expect(
        project.subProjects.single.canvas,
        const Size(1320, 2868),
        reason: 'with nothing to read back, the target default applies',
      );
    });
  });

  group('round-tripping', () {
    test('a migrated project re-saves in the new shape', () {
      final migrated = Project.fromJson(legacyProject());
      final json = migrated.toJson();

      expect(json['subProjects'], isA<List>());
      expect(json.containsKey('platform'), isFalse);
      expect(json.containsKey('screens'), isFalse);

      final reloaded = Project.fromJson(json);
      expect(reloaded.subProjects.single.targetId, 'ios-iphone');
      expect(reloaded.subProjects.single.canvas, const Size(1284, 2778));
      expect(reloaded.screenCount, 2);
      expect(reloaded.createdAt, migrated.createdAt);
    });

    test('a multi-target project survives a save and a load', () {
      final source = Project.fromJson(legacyProject());
      final reloaded = Project.fromJson(source.toJson());
      expect(reloaded.subProjects.single.presetId, 'iphone-6-5');
      expect(
        reloaded.subProjects.single.screens.first.id,
        source.subProjects.single.screens.first.id,
      );
    });
  });

  group('a version-1 backup', () {
    test('restores into one correctly-targeted sub-project', () {
      final bundle = ProjectArchive.read(legacyBundle(legacyProject()));

      expect(bundle.project.subProjects, hasLength(1));
      expect(bundle.project.subProjects.single.targetId, 'ios-iphone');
      expect(bundle.project.subProjects.single.canvas, const Size(1284, 2778));
      expect(bundle.images, isEmpty);
    });

    test('a bare legacy .json is still accepted', () {
      // What a backup looked like before bundles existed at all.
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(
            legacyProject(
              platform: 'android',
              canvases: const [Size(1080, 1920)],
            ),
          ),
        ),
      );
      final bundle = ProjectArchive.read(bytes);
      expect(bundle.project.subProjects.single.targetId, 'android-phone');
    });

    test('a backup from a newer build is still refused', () {
      // The version is only ever checked upwards, and that has to keep working
      // now that the current version has moved.
      final archive = Archive()
        ..add(
          ArchiveFile.typedData(
            'project.json',
            utf8.encode(jsonEncode(legacyProject())),
          ),
        )
        ..add(
          ArchiveFile.typedData(
            'manifest.json',
            utf8.encode(
              jsonEncode({
                'format': 'mockup-studio-project',
                'version': 99,
                'images': const [],
              }),
            ),
          ),
        );

      expect(
        () => ProjectArchive.read(
          Uint8List.fromList(ZipEncoder().encodeBytes(archive)),
        ),
        throwsA(isA<ProjectArchiveException>()),
      );
    });
  });
}
