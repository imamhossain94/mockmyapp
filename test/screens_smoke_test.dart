import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/features/home/home_screen.dart';
import 'package:mockmyapp/features/project/new_project_screen.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';

/// The shipped frame manifest, read straight off disk.
///
/// Deliberately not `rootBundle`: an asset load resolves on the real event loop
/// while a widget test drives a fake clock, so a screen that waits for the
/// catalog would only *usually* have it by the time assertions run. Reading the
/// file synchronously and overriding the provider makes these tests exact.
final FrameCatalog testCatalog = frameCatalogFromManifest(
  jsonDecode(File('assets/frames/manifest.json').readAsStringSync())
      as Map<String, dynamic>,
);

List<Override> get catalogOverride => [
  frameCatalogProvider.overrideWith((ref) => testCatalog),
];

/// Pumps [child] as a real screen on a phone-sized surface.
///
/// A phone viewport matters here: every screen in this app docks a bar to the
/// bottom of the window, and the default 800x600 test surface is wide enough to
/// hide a layout that would overflow on the devices it ships to.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.dark,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: catalogOverride,
      child: MaterialApp(
        theme: brightness == Brightness.dark
            ? StudioAppTheme.dark()
            : StudioAppTheme.light(),
        home: child,
      ),
    ),
  );
  await settle(tester);
}

/// Pumps a few frames so post-frame work (the default-frame resolution) lands.
Future<void> settle(WidgetTester tester, {int frames = 4}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The new-project form's card for the target with [id].
///
/// By key rather than by text, because a selected target names itself twice on
/// this form — once on its card and once in the canvas list under it — and a
/// plain `find.text` would be ambiguous the moment a test ticks one.
Finder targetCard(String id) => find.byKey(ValueKey('target-$id'));

/// The canvas row of the selected target with [id].
Finder canvasRow(String id) => find.byKey(ValueKey('canvas-$id'));

/// Walks the new-project form from its first step to its second.
Future<void> goToTargets(WidgetTester tester) async {
  await tester.tap(find.text('Next'));
  await settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final brightness in Brightness.values) {
    group('[${brightness.name}]', () {
      testWidgets('the first run offers the three ways in, AI first', (
        tester,
      ) async {
        await pumpScreen(tester, const HomeScreen(), brightness: brightness);

        expect(
          find.text('Make store screenshots that convert'),
          findsOneWidget,
        );
        // Generate with AI, then a blank project, then a template — the
        // order the cards stack in on a phone.
        final ai = tester.getRect(find.byKey(const ValueKey('start-ai')));
        final blank = tester.getRect(find.byKey(const ValueKey('start-new')));
        final template = tester.getRect(
          find.byKey(const ValueKey('start-template')),
        );
        expect(ai.top, lessThan(blank.top));
        expect(blank.top, lessThan(template.top));
        // Restoring a backup is the rare case: a link, not a fourth card.
        expect(find.text('Import a backup'), findsOneWidget);
        // The cards are the verbs, so nothing is docked under them.
        expect(find.byType(StudioDock), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the new-project form opens on the name step', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          const NewProjectScreen(),
          brightness: brightness,
        );

        expect(find.text('New Project'), findsOneWidget);
        // Both steps are named up front, so the form says how long it is
        // before asking anything.
        expect(find.text('Name & look'), findsOneWidget);
        expect(find.text('Targets'), findsOneWidget);
        // Step one asks two things and nothing else.
        expect(find.text('PROJECT NAME'), findsOneWidget);
        expect(find.text('No template'), findsOneWidget);
        // The stores belong to step two.
        expect(find.text('APP STORE'), findsNothing);
        expect(find.text('Next'), findsOneWidget);
        expect(find.text('Create Project'), findsNothing);
      });

      testWidgets('the new-project form lays its targets out', (tester) async {
        await pumpScreen(
          tester,
          const NewProjectScreen(),
          brightness: brightness,
        );
        await goToTargets(tester);

        // Targets are grouped under an UPPERCASE store eyebrow — see
        // `StudioSectionHeader`, which upper-cases its own label.
        expect(find.text('APP STORE'), findsOneWidget);
        expect(find.text('GOOGLE PLAY'), findsOneWidget);
        // One card per device class the store takes, not one per store.
        expect(targetCard('ios-iphone'), findsOneWidget);
        expect(targetCard('ios-ipad'), findsOneWidget);
        expect(targetCard('android-feature-graphic'), findsOneWidget);
        expect(find.text('Create Project'), findsOneWidget);
      });

      testWidgets('a missing project reports itself', (tester) async {
        await pumpScreen(
          tester,
          const EditorScreen(projectId: 'nope'),
          brightness: brightness,
        );
        expect(find.text('Project not found'), findsOneWidget);
      });
    });
  }

  testWidgets('the name field matches the height of the rows around it', (
    tester,
  ) async {
    await pumpScreen(tester, const NewProjectScreen());

    final field = tester.widget<StudioTextField>(
      find.byType(StudioTextField).first,
    );
    expect(field.height, 44);

    // And it is actually painted at that height, not just configured for it.
    final painted = tester.getSize(
      find
          .descendant(
            of: find.byType(StudioTextField).first,
            matching: find.byType(Container),
          )
          .first,
    );
    expect(painted.height, 44);
  });

  testWidgets('the form opens on the target the host machine suggests', (
    tester,
  ) async {
    // Someone screenshotting on an Android phone is making a Play listing.
    //
    // Reset inside the body rather than in a tear-down: the binding asserts
    // every foundation debug variable is back to null the moment the body
    // returns, which is before any tear-down runs.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpScreen(tester, const NewProjectScreen());
      await goToTargets(tester);

      expect(canvasRow('android-phone'), findsOneWidget);
      expect(canvasRow('ios-iphone'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('an Apple host opens on the iPhone instead', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpScreen(tester, const NewProjectScreen());
      await goToTargets(tester);

      expect(canvasRow('ios-iphone'), findsOneWidget);
      expect(canvasRow('android-phone'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the form never asks which handset to start on', (tester) async {
    // It resolves one from the chosen targets instead. The question cost a
    // whole step and bought a decision that takes two taps to change in the
    // editor, where you can actually see it.
    await pumpScreen(tester, const NewProjectScreen());
    expect(find.text('Initial Frame'), findsNothing);

    await goToTargets(tester);
    expect(find.text('Initial Frame'), findsNothing);
    expect(find.text('iPhone 16'), findsNothing);
    expect(find.text('Galaxy Note 10+'), findsNothing);
  });

  testWidgets('a frameless-only selection is still creatable', (tester) async {
    // Nothing in the catalog fits a Mac screenshot, and a desktop-only project
    // is a real one.
    await pumpScreen(tester, const NewProjectScreen());
    await goToTargets(tester);

    // The list of targets runs past the fold; scroll to each before tapping.
    await tester.ensureVisible(targetCard('mac'));
    await settle(tester);
    await tester.tap(targetCard('mac'));
    await settle(tester);
    await tester.ensureVisible(targetCard(StoreTargets.suggestedDefault.id));
    await settle(tester);
    await tester.tap(targetCard(StoreTargets.suggestedDefault.id));
    await settle(tester);

    await tester.ensureVisible(canvasRow('mac'));
    await settle(tester);
    expect(canvasRow('mac'), findsOneWidget);
    expect(find.text('Create Project'), findsOneWidget);
    expect(
      tester
          .widget<StudioButton>(
            find.widgetWithText(StudioButton, 'Create Project'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('a project with no targets cannot be created', (tester) async {
    await pumpScreen(tester, const NewProjectScreen());
    await goToTargets(tester);

    // The target list outgrew the test window once the store groups and the
    // 44pt touch sizes both landed, so the card is scrolled to like any other.
    await tester.ensureVisible(targetCard(StoreTargets.suggestedDefault.id));
    await settle(tester);
    await tester.tap(targetCard(StoreTargets.suggestedDefault.id));
    await settle(tester);

    expect(
      find.text('Pick at least one target to create the project.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<StudioButton>(
            find.widgetWithText(StudioButton, 'Create Project'),
          )
          .onPressed,
      isNull,
    );
  });

  test('a new project seeds three screens on the chosen frame', () {
    final container = ProviderContainer(overrides: catalogOverride);
    addTearDown(container.dispose);

    final device = testCatalog.forPlatform(FramePlatform.ios).first;
    final project = container
        .read(projectStoreProvider.notifier)
        .createProject(
          name: 'Smoke Test',
          targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
          initialDeviceId: device.id,
          initialVariantId: device.variants.first.id,
          initialCornerRadiusPct: device.cornerRadiusPct,
        );

    expect(project.name, 'Smoke Test');
    expect(project.subProjects.single.screens, hasLength(3));
    for (final screen in project.subProjects.single.screens) {
      expect(screen.canvas, const Size(1284, 2778));
      expect(screen.frames.single.deviceId, device.id);
    }
  });
}
