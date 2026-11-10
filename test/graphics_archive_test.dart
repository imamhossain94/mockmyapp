import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/data/repositories/graphics_archive.dart';
import 'package:mockmyapp/domain/engine/scene_renderer.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

/// A stand-in for a rendered screenshot. Only the bytes and the ordinal reach
/// the archive, so the payload can be anything recognisable.
RenderedScene scene(int index, String payload) => RenderedScene(
  index: index,
  doc: ScreenDoc(
    id: 'screen-$index',
    canvas: const Size(1284, 2778),
    background: const SolidBackground(Color(0xFF000000)),
    frames: const [],
  ),
  bytes: Uint8List.fromList(payload.codeUnits),
);

void main() {
  group('GraphicsArchive', () {
    test('packs every screenshot, numbered in set order', () {
      final bytes = GraphicsArchive.bundle(
        projectName: 'My App',
        scenes: [scene(0, 'one'), scene(1, 'two'), scene(2, 'three')],
      );

      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.files, hasLength(3));
      expect(archive.files.map((f) => f.name), [
        'My App/My App 01.png',
        'My App/My App 02.png',
        'My App/My App 03.png',
      ]);
    });

    test('and the bytes survive the round trip', () {
      final bytes = GraphicsArchive.bundle(
        projectName: 'My App',
        scenes: [scene(0, 'first-png'), scene(1, 'second-png')],
      );

      final archive = ZipDecoder().decodeBytes(bytes);
      String content(String name) =>
          String.fromCharCodes(archive.findFile(name)!.content as List<int>);

      expect(content('My App/My App 01.png'), 'first-png');
      expect(content('My App/My App 02.png'), 'second-png');
    });

    test('zero-pads so a file browser sorts the set correctly', () {
      final bytes = GraphicsArchive.bundle(
        projectName: 'Set',
        scenes: [for (var i = 0; i < 11; i++) scene(i, 'x')],
      );

      final names = ZipDecoder()
          .decodeBytes(bytes)
          .files
          .map((f) => f.name)
          .toList();

      // A zip carries no ordering of its own, so the ordinal in the name is
      // what keeps a store listing in the order it was composed. Unpadded,
      // "Set 10.png" would sort between 1 and 2.
      expect(names.first, 'Set/Set 01.png');
      expect(names.last, 'Set/Set 11.png');
      expect(List.of(names)..sort(), names);
    });

    test('a name that cannot be a path is made safe, consistently', () {
      final bytes = GraphicsArchive.bundle(
        projectName: 'My/App: v2',
        scenes: [scene(0, 'x')],
      );

      final name = ZipDecoder().decodeBytes(bytes).files.single.name;
      // One sanitised name, used for both the folder and the files — a stray
      // separator here would silently create a nested directory.
      final safe = GraphicsArchive.fileNameFor(
        'My/App: v2',
      ).replaceAll(' graphics.zip', '');
      expect(name, '$safe/$safe 01.png');
      expect(name.split('/'), hasLength(2));
    });

    test('the offered file name is a zip named for the project', () {
      expect(GraphicsArchive.fileNameFor('My App'), 'My App graphics.zip');
      expect(GraphicsArchive.fileExtension, 'zip');
      expect(GraphicsArchive.mimeType, 'application/zip');
    });

    test('an empty set still produces a readable archive', () {
      final bytes = GraphicsArchive.bundle(projectName: 'Empty', scenes: []);
      expect(ZipDecoder().decodeBytes(bytes).files, isEmpty);
    });
  });
}
