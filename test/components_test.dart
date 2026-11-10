// Reusable groups of shapes — see `ComponentDef`.
//
// Components push the way styles do: editing the master rewrites every
// placement of it, and the screens go on holding concrete shapes so a document
// still draws with no library in reach. The one thing the master does *not*
// own is where a placement sits, and getting that wrong would drag every
// instance in the project onto the same spot the first time somebody recoloured
// a dot.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/style_library.dart';

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// A badge: a dot with a tick beside it.
ComponentDef badge({Color fill = const Color(0xFFFF0000)}) => ComponentDef(
  id: 'c1',
  name: 'Badge',
  shapes: [
    ShapeSpec(
      kind: ShapeKind.ellipse,
      center: const Offset(0.2, 0.2),
      fill: fill,
    ),
    const ShapeSpec(kind: ShapeKind.star, center: Offset(0.3, 0.2)),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('stamping a placement', () {
    test('the anchor lands where it was asked for', () {
      final stamped = badge().stamp(
        at: const Offset(0.7, 0.5),
        instanceId: 'i1',
        base: kStackOverEverything,
      );
      expect(stamped.first.center, const Offset(0.7, 0.5));
    });

    test('the shapes keep their positions relative to each other', () {
      // The second shape sits 0.1 to the right of the first in the master, and
      // has to go on doing so wherever the placement lands.
      final stamped = badge().stamp(
        at: const Offset(0.7, 0.5),
        instanceId: 'i1',
        base: kStackOverEverything,
      );
      expect(stamped[1].center.dx - stamped[0].center.dx, closeTo(0.1, 1e-9));
      expect(stamped[1].center.dy - stamped[0].center.dy, closeTo(0, 1e-9));
    });

    test('every shape is tagged, and numbered in order', () {
      final stamped = badge().stamp(
        at: Offset.zero,
        instanceId: 'i1',
        base: kStackOverEverything,
      );
      expect(stamped.map((s) => s.componentId), everyElement('c1'));
      expect(stamped.map((s) => s.instanceId), everyElement('i1'));
      expect(stamped.map((s) => s.slot), [0, 1]);
      expect(stamped.every((s) => s.isInstance), isTrue);
    });

    test('the placement stacks up from the base it was given', () {
      // The master's own z values are ranked, not copied: they were read off
      // whatever screen it was saved from, and copying them would drop the
      // placement behind everything on any other screen.
      final master = badge();
      final stamped = master.stamp(at: Offset.zero, instanceId: 'i1', base: 40);
      expect(stamped.map((s) => s.z), [40, 41]);
    });

    test('the placement keeps the order the master had', () {
      final master = ComponentDef(
        id: 'c1',
        name: 'Badge',
        shapes: [
          const ShapeSpec(kind: ShapeKind.ellipse, z: kStackOverEverything),
          const ShapeSpec(kind: ShapeKind.star, z: kStackBehindFrames),
        ],
      );
      // The star is behind the ellipse in the master, so it stays behind it.
      final stamped = master.stamp(at: Offset.zero, instanceId: 'i1', base: 40);
      expect(stamped.map((s) => s.z), [41, 40]);
    });

    test('the anchor is the first shape, not the bounding box', () {
      // A bounding-box anchor would move every instance on every screen as a
      // side effect of resizing one shape in the master.
      expect(badge().anchor, const Offset(0.2, 0.2));
    });
  });

  group('a screen draws without the library', () {
    test('the tags survive a round-trip', () {
      final shape = badge()
          .stamp(
            at: const Offset(0.5, 0.5),
            instanceId: 'i1',
            base: kStackOverEverything,
          )
          .first;
      final back = shapeFromJson(
        shapeToJson(shape),
        canvas: const Size(1179, 2556),
      );
      expect(back.componentId, 'c1');
      expect(back.instanceId, 'i1');
      expect(back.slot, 0);
      expect(back.center, shape.center);
    });

    test('a shape written before components existed loads untagged', () {
      final json = shapeToJson(const ShapeSpec(kind: ShapeKind.ellipse))
        ..remove('componentId')
        ..remove('instanceId')
        ..remove('slot');
      final back = shapeFromJson(json, canvas: const Size(1179, 2556));
      expect(back.componentId, isNull);
      expect(back.isInstance, isFalse);
    });

    test('the library round-trips on the project', () {
      final project = Project(
        id: 'p1',
        name: 'Listing',
        subProjects: const [],
        createdAt: DateTime.utc(2026),
        styles: StyleLibrary(components: [badge()]),
      );
      final back = Project.fromJson(project.toJson());
      expect(back.styles.components.single.name, 'Badge');
      expect(back.styles.components.single.shapes, hasLength(2));
    });
  });

  group('editing the master pushes', () {
    late Directory tempDir;
    late ProviderContainer container;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('components_test');
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

    List<ShapeSpec> shapesOf(Project p, {int screen = 0}) =>
        byId(p.id).subProjects.first.screens[screen].shapes;

    /// Places [component] on the first screen at [at].
    void place(Project p, ComponentDef component, Offset at, String instance) {
      final screen = byId(p.id).subProjects.first.screens.first;
      store().updateScreen(
        p.id,
        screen.copyWith(
          shapes: [
            ...screen.shapes,
            ...component.stamp(
              at: at,
              instanceId: instance,
              base: screen.topZ + 1,
            ),
          ],
        ),
      );
    }

    test('every placement is rewritten', () {
      final project = make();
      store().saveComponent(project.id, badge());
      place(project, badge(), const Offset(0.3, 0.3), 'i1');
      place(project, badge(), const Offset(0.8, 0.7), 'i2');

      store().saveComponent(project.id, badge(fill: const Color(0xFF00FF00)));

      final tagged = shapesOf(project).where((s) => s.isInstance).toList();
      expect(tagged, hasLength(4));
      expect(
        tagged.where((s) => s.slot == 0).map((s) => s.fill),
        everyElement(const Color(0xFF00FF00)),
      );
    });

    test('each placement keeps where it was put', () {
      // The failure this exists for: re-stamping every instance at the
      // master's own anchor drags them all onto one spot.
      final project = make();
      store().saveComponent(project.id, badge());
      place(project, badge(), const Offset(0.3, 0.3), 'i1');
      place(project, badge(), const Offset(0.8, 0.7), 'i2');

      store().saveComponent(project.id, badge(fill: const Color(0xFF00FF00)));

      final anchors = shapesOf(
        project,
      ).where((s) => s.isInstance && s.slot == 0).map((s) => s.center).toList();
      expect(anchors, contains(const Offset(0.3, 0.3)));
      expect(anchors, contains(const Offset(0.8, 0.7)));
    });

    test('shapes that are not part of it are left alone', () {
      final project = make();
      final screen = byId(project.id).subProjects.first.screens.first;
      store().updateScreen(
        project.id,
        screen.copyWith(
          shapes: const [
            ShapeSpec(kind: ShapeKind.rectangle, center: Offset(0.1, 0.1)),
          ],
        ),
      );
      store().saveComponent(project.id, badge());
      place(project, badge(), const Offset(0.5, 0.5), 'i1');

      store().saveComponent(project.id, badge(fill: const Color(0xFF00FF00)));

      final loose = shapesOf(project).where((s) => !s.isInstance).toList();
      expect(loose, hasLength(1));
      expect(loose.single.kind, ShapeKind.rectangle);
      expect(loose.single.center, const Offset(0.1, 0.1));
    });

    test('saving a new component places nothing', () {
      final project = make();
      final before = shapesOf(project).length;
      store().saveComponent(project.id, badge());
      expect(shapesOf(project), hasLength(before));
    });

    test('deleting cuts placements loose but keeps the shapes', () {
      final project = make();
      store().saveComponent(project.id, badge());
      place(project, badge(), const Offset(0.5, 0.5), 'i1');
      final before = shapesOf(project).length;

      store().deleteComponent(project.id, 'c1');

      expect(byId(project.id).styles.components, isEmpty);
      expect(shapesOf(project), hasLength(before));
      expect(shapesOf(project).where((s) => s.isInstance), isEmpty);
    });

    test('a detached instance stops following the master', () {
      final project = make();
      store().saveComponent(project.id, badge());
      place(project, badge(), const Offset(0.5, 0.5), 'i1');

      // Detach: what "unlink this instance" does.
      final screen = byId(project.id).subProjects.first.screens.first;
      store().updateScreen(
        project.id,
        screen.copyWith(
          shapes: [
            for (final s in screen.shapes) s.copyWith(clearComponent: true),
          ],
        ),
      );

      store().saveComponent(project.id, badge(fill: const Color(0xFF00FF00)));

      expect(
        shapesOf(project).map((s) => s.fill),
        isNot(contains(const Color(0xFF00FF00))),
      );
    });
  });
}
