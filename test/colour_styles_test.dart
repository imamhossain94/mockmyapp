// Saved colours, and the scope that lets the picker find them.
//
// A colour style is simpler than a text style: it does not push, because a
// colour has no instances to rewrite — what a caption or a shape holds *is* the
// colour. What it needs instead is to be reachable, and the colour picker is
// opened from nine places, most of which never knew which project they were in.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/style_library.dart';
import 'package:mockmyapp/features/shared/project_scope.dart';

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProjectScope', () {
    testWidgets('publishes the project to everything below it', (tester) async {
      String? seen;
      await tester.pumpWidget(
        ProjectScope(
          projectId: 'p1',
          child: Builder(
            builder: (context) {
              seen = ProjectScope.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, 'p1');
    });

    testWidgets('is null where there is no project', (tester) async {
      // The settings screen opens the same colour picker, and "no project" is
      // a real answer there rather than a missing one.
      String? seen = 'unset';
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = ProjectScope.of(context);
            return const SizedBox();
          },
        ),
      );
      expect(seen, isNull);
    });
  });

  group('the library', () {
    test('saving twice under one id replaces rather than duplicates', () {
      const a = ColorStyle(id: 'c1', name: 'Brand', color: Color(0xFF336FE6));
      const b = ColorStyle(id: 'c1', name: 'Brand', color: Color(0xFFC15151));
      final library = StyleLibrary.empty.withColor(a).withColor(b);
      expect(library.colors, hasLength(1));
      expect(library.colors.single.color, const Color(0xFFC15151));
    });

    test('forgetting one leaves the rest', () {
      final library = StyleLibrary.empty
          .withColor(
            const ColorStyle(id: 'c1', name: 'Brand', color: Color(0xFF000000)),
          )
          .withColor(
            const ColorStyle(id: 'c2', name: 'Ink', color: Color(0xFF111111)),
          )
          .withoutColor('c1');
      expect(library.colors.map((c) => c.id), ['c2']);
    });
  });

  group('the store', () {
    late Directory tempDir;
    late ProviderContainer container;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('colour_styles_test');
      ImageLibrary.debugResetStorage();
      PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
      await ImageLibrary.initialize();
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

    ProjectStore store() => container.read(projectStoreProvider.notifier);
    Project byId(String id) =>
        container.read(projectStoreProvider).firstWhere((p) => p.id == id);

    Project make() => store().createProject(
      name: 'Listing',
      targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
      initialDeviceId: 'apple-iphone-16',
      initialVariantId: '16---ultramarine',
    );

    test('a saved colour is kept on the project', () {
      final project = make();
      store().saveColorStyle(
        project.id,
        const ColorStyle(id: 'c1', name: 'Brand', color: Color(0xFF336FE6)),
      );
      expect(byId(project.id).styles.colors.single.name, 'Brand');
      expect(
        byId(project.id).styles.colors.single.color,
        const Color(0xFF336FE6),
      );
    });

    test('saving a colour touches no screen', () {
      // Unlike a text style, there is nothing to push to: a caption holds the
      // colour itself, not a reference to one.
      final project = make();
      final before = byId(
        project.id,
      ).subProjects.first.screens.map((s) => s.caption?.color).toList();

      store().saveColorStyle(
        project.id,
        const ColorStyle(id: 'c1', name: 'Brand', color: Color(0xFF336FE6)),
      );

      final after = byId(
        project.id,
      ).subProjects.first.screens.map((s) => s.caption?.color).toList();
      expect(after, before);
    });

    test('deleting one leaves every screen exactly as it was', () {
      final project = make();
      store().saveColorStyle(
        project.id,
        const ColorStyle(id: 'c1', name: 'Brand', color: Color(0xFF336FE6)),
      );
      final before = byId(
        project.id,
      ).subProjects.first.screens.map((s) => s.caption?.color).toList();

      store().deleteColorStyle(project.id, 'c1');

      expect(byId(project.id).styles.colors, isEmpty);
      expect(
        byId(
          project.id,
        ).subProjects.first.screens.map((s) => s.caption?.color).toList(),
        before,
      );
    });
  });
}
