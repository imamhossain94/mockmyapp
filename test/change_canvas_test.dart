import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/assets/default_frames.dart';
import 'package:mockmyapp/data/assets/studio_frames.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/domain/models/sub_project.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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

  late Directory tempDir;
  late ProviderContainer container;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('change_canvas_test');
    PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
    tempDir.deleteSync(recursive: true);
  });

  ProjectStore store() => container.read(projectStoreProvider.notifier);

  /// A project on [targets], wearing a real catalog frame.
  String seed(List<TargetChoice> targets) => store()
      .createProject(
        name: 'Listing',
        targets: targets,
        initialDeviceId: 'apple-iphone-16',
        initialVariantId: '16---ultramarine',
        initialCornerRadiusPct: 0.12,
      )
      .id;

  const iphone = (targetId: 'ios-iphone', presetId: 'iphone-6-9');
  const ipad = (targetId: 'ios-ipad', presetId: 'ipad-13');
  const androidPhone = (
    targetId: 'android-phone',
    presetId: 'android-phone-9-16',
  );

  group('createProject', () {
    test('makes one sub-project per target, each at its own canvas', () {
      final id = seed([iphone, ipad, androidPhone]);
      final project = store().byId(id)!;

      expect(project.subProjects, hasLength(3));
      expect(
        [for (final s in project.subProjects) s.targetId],
        ['ios-iphone', 'ios-ipad', 'android-phone'],
      );
      expect(project.subProjects[0].canvas, const Size(1320, 2868));
      expect(project.subProjects[1].canvas, const Size(2064, 2752));
      expect(project.subProjects[2].canvas, const Size(1080, 1920));
    });

    test('the starter screens agree with their own sub-project', () {
      final id = seed([iphone, ipad]);
      for (final sub in store().byId(id)!.subProjects) {
        expect(sub.screens, hasLength(3));
        for (final screen in sub.screens) {
          expect(screen.canvas, sub.canvas);
        }
      }
    });

    test('the sets are independent from the first frame', () {
      // Seeded from the same starter screens, so they look alike — but no id is
      // shared, which is what stops an edit to one reaching the others.
      final id = seed([iphone, ipad]);
      final project = store().byId(id)!;
      final a = project.subProjects[0].screens.map((s) => s.id).toSet();
      final b = project.subProjects[1].screens.map((s) => s.id).toSet();
      expect(a.intersection(b), isEmpty);
    });

    test('a framed target wears the picked device', () {
      final id = seed([iphone]);
      final frame = store()
          .byId(id)!
          .subProjects
          .first
          .screens
          .first
          .frames
          .first;
      expect(frame.deviceId, 'apple-iphone-16');
      expect(frame.frameHidden, isFalse);
      expect(frame.screenshot.cornerRadiusPct, 0.12);
    });

    test('a target with its own body opens in it, not in a handset', () {
      // The handset pick is an iPhone. None of these targets should take it —
      // an iPad set opens in an iPad, a Mac set in a MacBook, a Web set in a
      // browser window.
      final id = seed([
        ipad,
        (targetId: 'mac', presetId: 'mac-2880'),
        (targetId: 'windows', presetId: 'windows-1080'),
        (targetId: 'web', presetId: 'web-1280'),
      ]);

      expect(
        [
          for (final sub in store().byId(id)!.subProjects)
            sub.screens.first.frames.first.deviceId,
        ],
        [
          StudioFrameIds.ipad,
          StudioFrameIds.macbook,
          StudioFrameIds.windowsLaptop,
          StudioFrameIds.browserMac,
        ],
      );

      for (final sub in store().byId(id)!.subProjects) {
        final frame = sub.screens.first.frames.first;
        expect(frame.frameHidden, isFalse, reason: sub.targetId);
        expect(
          frame.design,
          isNull,
          reason: '${sub.targetId} uses the catalog',
        );
        // These bodies are already the shape of their canvas, so nothing is
        // rotated into place the way a landscape phone set is.
        expect(frame.transform.rotationDeg, 0, reason: sub.targetId);
      }
    });

    test('the feature graphic is the one thing that stays bare', () {
      // A banner is the artwork. Wrapping it in a device would frame the thing
      // the frame is supposed to be about.
      final id = seed([
        (targetId: 'android-feature-graphic', presetId: 'play-feature-graphic'),
      ]);
      final sub = store().byId(id)!.subProjects.single;
      final frame = sub.screens.first.frames.first;

      expect(frame.frameHidden, isTrue);
      expect(frame.design, isNotNull);
      // Zero bezel all round, so the aperture is the whole frame.
      expect(frame.design!.thickness, 0);
      expect(frame.design!.top, 0);
      expect(frame.design!.bottom, 0);
      // …and proportioned to the canvas rather than to a phone.
      expect(
        frame.design!.aspect,
        closeTo(sub.canvas.width / sub.canvas.height, 1e-9),
      );
    });

    test('a feature graphic is one banner, not a set of three', () {
      final id = seed([
        (targetId: 'android-feature-graphic', presetId: 'play-feature-graphic'),
      ]);
      expect(store().byId(id)!.subProjects.first.screens, hasLength(1));
    });

    test('a landscape preset rotates the starter frame', () {
      final id = seed([
        (targetId: 'ios-iphone', presetId: 'iphone-6-9-landscape'),
      ]);
      final frame = store()
          .byId(id)!
          .subProjects
          .first
          .screens
          .first
          .frames
          .first;
      expect(frame.transform.rotationDeg, -90);
    });
  });

  group('changeCanvasPreset', () {
    test('resizes every screen in that sub-project', () {
      final id = seed([iphone]);
      final subId = store().byId(id)!.subProjects.first.id;

      store().changeCanvasPreset(id, subId, 'iphone-6-5');

      final sub = store().byId(id)!.subProjects.first;
      expect(sub.presetId, 'iphone-6-5');
      expect(sub.canvas, const Size(1284, 2778));
      for (final screen in sub.screens) {
        expect(screen.canvas, const Size(1284, 2778));
      }
    });

    test('leaves the project\'s other targets completely alone', () {
      // The whole point of sub-projects: changing the iPhone set's canvas is
      // not a statement about the iPad set.
      final id = seed([iphone, ipad, androidPhone]);
      final before = store().byId(id)!;
      final subId = before.subProjects.first.id;

      store().changeCanvasPreset(id, subId, 'iphone-6-5');

      final after = store().byId(id)!;
      for (var i = 1; i < after.subProjects.length; i++) {
        expect(after.subProjects[i].canvas, before.subProjects[i].canvas);
        expect(
          after.subProjects[i].screens,
          same(before.subProjects[i].screens),
        );
      }
    });

    test('the composition rides along untouched', () {
      // The whole feature rests on every measurement being a share of the
      // canvas. If a resize ever starts rewriting these, it has stopped being
      // safe and this test is the thing that says so.
      final id = seed([iphone]);
      final subId = store().byId(id)!.subProjects.first.id;
      store().updateScreen(
        id,
        store()
            .byId(id)!
            .subProjects
            .first
            .screens
            .first
            .copyWith(
              background: const PatternBackground(
                style: PatternStyle.aurora,
                colors: [Color(0xFF060B1F), Color(0xFF4F46E5)],
                seed: 9,
              ),
              caption: const CaptionSpec(
                text: 'Ship it',
                size: 64,
                lineHeight: 74,
              ),
            ),
      );
      final before = store().byId(id)!.subProjects.first.screens.first;

      store().changeCanvasPreset(id, subId, 'iphone-6-5');
      final after = store().byId(id)!.subProjects.first.screens.first;

      expect(after.canvas, isNot(before.canvas));
      expect(after.background, same(before.background));
      expect(after.caption, same(before.caption));
      expect(after.frames.first.transform, same(before.frames.first.transform));
      expect(after.frames.first.deviceId, before.frames.first.deviceId);
    });

    test('device frames are deliberately left alone', () {
      final id = seed([iphone]);
      final subId = store().byId(id)!.subProjects.first.id;
      store().changeCanvasPreset(id, subId, 'iphone-6-5');
      for (final screen in store().byId(id)!.subProjects.first.screens) {
        expect(screen.frames.first.deviceId, 'apple-iphone-16');
      }
    });

    test('switching back restores the original canvas exactly', () {
      final id = seed([iphone]);
      final subId = store().byId(id)!.subProjects.first.id;
      final before = [
        for (final s in store().byId(id)!.subProjects.first.screens) s.canvas,
      ];

      store().changeCanvasPreset(id, subId, 'iphone-6-5');
      store().changeCanvasPreset(id, subId, 'iphone-6-9');

      final sub = store().byId(id)!.subProjects.first;
      expect(sub.presetId, 'iphone-6-9');
      expect([for (final s in sub.screens) s.canvas], before);
    });

    test('re-picking the canvas it is already on changes nothing', () {
      final id = seed([iphone]);
      final subId = store().byId(id)!.subProjects.first.id;
      final before = store().byId(id)!.subProjects.first;
      store().changeCanvasPreset(id, subId, 'iphone-6-9');
      expect(store().byId(id)!.subProjects.first.screens, same(before.screens));
    });

    test('a preset from another target is refused', () {
      // Presets are scoped to their target; an iPad canvas is not something the
      // iPhone set can be moved to by id.
      final id = seed([iphone]);
      final subId = store().byId(id)!.subProjects.first.id;
      store().changeCanvasPreset(id, subId, 'ipad-13');
      expect(
        store().byId(id)!.subProjects.first.canvas,
        const Size(1320, 2868),
      );
    });
  });

  group('changeCanvasCustom', () {
    test('moves a set onto a size of its own, every screen with it', () {
      final id = seed([androidPhone]);
      final subId = store().byId(id)!.subProjects.first.id;

      store().changeCanvasCustom(id, subId, const Size(1000, 1800));

      final sub = store().byId(id)!.subProjects.first;
      expect(sub.presetId, kCustomPresetId);
      expect(sub.hasCustomCanvas, isTrue);
      expect(sub.canvas, const Size(1000, 1800));
      expect(sub.preset.label, 'Custom size');
      expect(sub.preset.size, const Size(1000, 1800));
      for (final screen in sub.screens) {
        expect(screen.canvas, const Size(1000, 1800));
      }
    });

    test("a size that is one of the target's presets lands on it", () {
      final id = seed([iphone]);
      final subId = store().byId(id)!.subProjects.first.id;

      store().changeCanvasCustom(id, subId, const Size(1284, 2778));

      final sub = store().byId(id)!.subProjects.first;
      expect(sub.presetId, 'iphone-6-5');
      expect(sub.hasCustomCanvas, isFalse);
    });

    test('rounds to whole pixels and keeps inside the bounds', () {
      final id = seed([androidPhone]);
      final subId = store().byId(id)!.subProjects.first.id;

      store().changeCanvasCustom(id, subId, const Size(20.4, 99999));

      final sub = store().byId(id)!.subProjects.first;
      expect(
        sub.canvas,
        Size(
          CanvasPreset.customMin.toDouble(),
          CanvasPreset.customMax.toDouble(),
        ),
      );
    });

    test('a preset picked afterwards takes the set back off it', () {
      final id = seed([iphone]);
      final subId = store().byId(id)!.subProjects.first.id;
      store().changeCanvasCustom(id, subId, const Size(1500, 1000));
      store().changeCanvasPreset(id, subId, 'iphone-6-9');

      final sub = store().byId(id)!.subProjects.first;
      expect(sub.presetId, 'iphone-6-9');
      expect(sub.hasCustomCanvas, isFalse);
      expect(sub.canvas, const Size(1320, 2868));
    });

    test('is persisted only when set, and reads back as it was', () {
      final id = seed([iphone]);
      final plain = store().byId(id)!.subProjects.first;
      final plainJson = plain.toJson();
      expect(plainJson['presetId'], 'iphone-6-9');
      expect(plainJson.containsKey('custom'), isFalse);

      store().changeCanvasCustom(id, plain.id, const Size(1500, 1000));
      final custom = store().byId(id)!.subProjects.first;
      final json = custom.toJson();
      expect(json['presetId'], kCustomPresetId);
      expect(json['canvas'], {'w': 1500.0, 'h': 1000.0});
      expect(
        json.keys.toSet(),
        plainJson.keys.toSet(),
        reason: 'a custom size adds no field, only a preset id',
      );

      final back = SubProject.fromJson(json);
      expect(back.hasCustomCanvas, isTrue);
      expect(back.canvas, const Size(1500, 1000));
      expect(back.target.id, 'ios-iphone');
    });

    test('an id an older build does not know still keeps its canvas', () {
      // What a build without custom sizes does with one: ticks its default
      // row and keeps the stored canvas, which is the property that matters.
      final sub = SubProject.fromJson({
        'id': 's',
        'targetId': 'ios-iphone',
        'presetId': kCustomPresetId,
        'canvas': {'w': 1500, 'h': 1000},
        'screens': const [],
      });
      expect(StoreTargets.iphone.resolvePreset(sub.presetId).id, 'iphone-6-9');
      expect(sub.canvas, const Size(1500, 1000));
    });
  });

  group('addTarget / removeTarget', () {
    test('adds a sub-project seeded like a new one', () {
      final id = seed([iphone]);
      store().addTarget(id, ipad);

      final project = store().byId(id)!;
      expect(project.subProjects, hasLength(2));
      expect(project.subProjects.last.targetId, 'ios-ipad');
      expect(project.subProjects.last.screens, hasLength(3));
      expect(project.subProjects.last.canvas, const Size(2064, 2752));
    });

    test('a target added later inherits the frame the others wear', () {
      final id = seed([iphone]);
      store().addTarget(id, androidPhone);
      final frame = store()
          .byId(id)!
          .subProjects
          .last
          .screens
          .first
          .frames
          .first;
      expect(frame.deviceId, 'apple-iphone-16');
      expect(frame.screenshot.cornerRadiusPct, 0.12);
    });

    test('a framed target added to a frameless project still gets a frame', () {
      // Nothing in a Mac-only project has a device to inherit, and a phone set
      // that arrives frameless is not what "add iPhone" means.
      final id = store()
          .createProject(
            name: 'Desktop only',
            targets: const [(targetId: 'mac', presetId: 'mac-2880')],
          )
          .id;

      store().addTarget(id, iphone);
      final frame = store()
          .byId(id)!
          .subProjects
          .last
          .screens
          .first
          .frames
          .first;
      expect(frame.frameHidden, isFalse);
      expect(frame.deviceId, 'apple-iphone-16');
    });

    test('an Android target falls back to Android hardware', () {
      final id = store()
          .createProject(
            name: 'Desktop only',
            targets: const [(targetId: 'web', presetId: 'web-1280')],
          )
          .id;

      store().addTarget(id, androidPhone);
      expect(
        store().byId(id)!.subProjects.last.screens.first.frames.first.deviceId,
        kDefaultAndroidHandset.deviceId,
      );
    });

    test('refuses a duplicate target', () {
      // Two sub-projects for one device class would export two folders the
      // store has one slot for.
      final id = seed([iphone]);
      expect(store().addTarget(id, iphone), isNull);
      expect(store().byId(id)!.subProjects, hasLength(1));
    });

    test('removes a target and everything on it', () {
      final id = seed([iphone, ipad]);
      final subId = store().byId(id)!.subProjects.first.id;
      store().removeTarget(id, subId);

      final project = store().byId(id)!;
      expect(project.subProjects, hasLength(1));
      expect(project.subProjects.single.targetId, 'ios-ipad');
    });

    test('refuses to remove the last target', () {
      // A project with no targets has no canvas, nowhere to add a screen and no
      // way back through the UI.
      final id = seed([iphone]);
      final subId = store().byId(id)!.subProjects.first.id;
      store().removeTarget(id, subId);
      expect(store().byId(id)!.subProjects, hasLength(1));
    });
  });

  group('copyScreensFrom', () {
    test('replaces the destination with copies at its own canvas', () {
      final id = seed([iphone, ipad]);
      final project = store().byId(id)!;
      final from = project.subProjects[0];
      final to = project.subProjects[1];

      store().updateScreen(
        id,
        from.screens.first.copyWith(
          caption: const CaptionSpec(text: 'Designed once'),
        ),
      );
      store().copyScreensFrom(id, from.id, to.id);

      final after = store().byId(id)!.subProjects[1];
      expect(after.screens, hasLength(from.screens.length));
      expect(after.screens.first.caption!.text, 'Designed once');
      for (final screen in after.screens) {
        expect(screen.canvas, const Size(2064, 2752));
      }
    });

    test('is a snapshot, not a link', () {
      final id = seed([iphone, ipad]);
      final project = store().byId(id)!;
      store().copyScreensFrom(
        id,
        project.subProjects[0].id,
        project.subProjects[1].id,
      );

      final after = store().byId(id)!;
      final sourceIds = after.subProjects[0].screens.map((s) => s.id).toSet();
      final copyIds = after.subProjects[1].screens.map((s) => s.id).toSet();
      expect(sourceIds.intersection(copyIds), isEmpty);
    });

    test('copying a target onto itself does nothing', () {
      final id = seed([iphone]);
      final sub = store().byId(id)!.subProjects.first;
      store().copyScreensFrom(id, sub.id, sub.id);
      expect(store().byId(id)!.subProjects.first.screens, same(sub.screens));
    });
  });

  group('screens find their own target', () {
    test('addScreen joins the target it was given', () {
      final id = seed([iphone, ipad]);
      final ipadSub = store().byId(id)!.subProjects[1];
      final screen = store().addScreen(id, ipadSub.id);

      final after = store().byId(id)!;
      expect(after.subProjects[0].screens, hasLength(3));
      expect(after.subProjects[1].screens, hasLength(4));
      expect(after.subProjects[1].screens.last.id, screen.id);
      expect(screen.canvas, const Size(2064, 2752));
    });

    test('deleteScreen only touches the set the screen belongs to', () {
      final id = seed([iphone, ipad]);
      final victim = store().byId(id)!.subProjects[1].screens.first;
      store().deleteScreen(id, victim.id);

      final after = store().byId(id)!;
      expect(after.subProjects[0].screens, hasLength(3));
      expect(after.subProjects[1].screens, hasLength(2));
    });

    test('reordering stays inside one target', () {
      final id = seed([iphone, ipad]);
      final sub = store().byId(id)!.subProjects[1];
      final second = sub.screens[1];
      store().moveScreenLeft(id, second.id);

      final after = store().byId(id)!;
      expect(after.subProjects[1].screens.first.id, second.id);
      expect(
        after.subProjects[0].screens,
        same(store().byId(id)!.subProjects[0].screens),
      );
    });

    test('applyStyleToAll stops at the target boundary', () {
      // A look tuned for a 9:20 phone is not automatically what the 13-inch
      // iPad set wants. Pushing it there is copyScreensFrom's job.
      final id = seed([iphone, ipad]);
      final project = store().byId(id)!;
      final source = project.subProjects[0].screens.first;
      const marker = SolidBackground(Color(0xFF123456));

      store().updateScreen(id, source.copyWith(background: marker));
      store().applyStyleToAll(id, source.id);

      final after = store().byId(id)!;
      for (final screen in after.subProjects[0].screens) {
        expect(screen.background, isA<SolidBackground>());
        expect((screen.background as SolidBackground).color, marker.color);
      }
      for (final screen in after.subProjects[1].screens) {
        expect(screen.background, same(kDefaultBackground));
      }
    });
  });

  group('sub-project lookups', () {
    test('subProjectOf finds the owner of any screen', () {
      final id = seed([iphone, ipad]);
      final project = store().byId(id)!;
      for (final sub in project.subProjects) {
        for (final screen in sub.screens) {
          expect(project.subProjectOf(screen.id)!.id, sub.id);
        }
      }
      expect(project.subProjectOf('not-a-screen'), isNull);
    });

    test('screenCount and allScreens span every target', () {
      final id = seed([iphone, ipad, androidPhone]);
      final project = store().byId(id)!;
      expect(project.screenCount, 9);
      expect(project.allScreens, hasLength(9));
    });

    test('a sub-project resolves its own target and preset', () {
      final id = seed([ipad]);
      final sub = store().byId(id)!.subProjects.single;
      expect(sub.target.id, StoreTargets.ipad.id);
      expect(sub.preset.size, const Size(2064, 2752));
      expect(sub.label, 'iPad');
      expect(sub.isLandscape, isFalse);
    });
  });
}
