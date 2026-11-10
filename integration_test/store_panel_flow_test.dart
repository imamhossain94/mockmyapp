// Drives the real app to the marketing looks, writing a PNG of the window at
// each step into build/shots/.
//
//   flutter test integration_test/store_panel_flow_test.dart -d windows
//
// This runs the actual `MockMyApp`, so unlike `flutter test` it has a
// real engine and shapes the caption typeface as a device does — which is the
// whole reason the panel is composed here rather than in a widget test.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mockmyapp/app/app.dart';
import 'package:mockmyapp/app/theme/studio_icons.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';

const _shots = 'build/shots';

/// Captures whatever the window is showing.
///
/// `takeScreenshot` needs the driver extension, which a plain
/// `flutter test -d windows` run does not have; the render view's own layer is
/// the same pixels without it.
Future<void> shoot(WidgetTester tester, String name) async {
  final view = tester.binding.renderViews.first;
  // Reading the render view's own layer is the only way to rasterise the
  // window without the driver extension; there is no public accessor.
  // ignore: invalid_use_of_protected_member
  final image = await (view.layer! as OffsetLayer).toImage(view.paintBounds);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();

  final file = File('$_shots/$name.png')..createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
  print('  shot → ${file.path} (${(file.lengthSync() / 1024).round()} KB)');
}

/// Taps [label], shooting the screen first if it is missing so a failure shows
/// *where* the flow stopped rather than only that it did.
///
/// The scroll is not optional: the style strip is a two-row wrap inside a
/// horizontal scroller, so a chip can be in the tree at coordinates that are
/// clipped away — tapping those hits whatever is painted there instead.
Future<void> tapText(WidgetTester tester, String label) async {
  final finder = find.text(label);
  if (finder.evaluate().isEmpty) {
    await shoot(tester, 'missing-$label');
    fail('could not find "$label" — see $_shots/missing-$label.png');
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// Taps the visually largest [InkWell] — on the project screen that is a
/// screen card, which the app bar's icon buttons would otherwise win.
Future<void> tapBiggestCard(WidgetTester tester) async {
  final cards = find.byType(InkWell).evaluate().toList();
  expect(cards, isNotEmpty, reason: 'the project should list a screen');
  Rect? best;
  for (final element in cards) {
    final box = element.renderObject as RenderBox?;
    if (box == null || !box.hasSize) continue;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (best == null || rect.width * rect.height > best.width * best.height) {
      best = rect;
    }
  }
  expect(best, isNotNull);
  await tester.tapAt(best!.center);
  await tester.pumpAndSettle();
}

/// Scrolls the panel until [label] exists, then returns its finder.
///
/// `ensureVisible` is not enough here: a `ListView` only instantiates the rows
/// near the viewport, so a control far down the panel is not merely offscreen,
/// it is absent from the tree and `find.text` sees nothing.
/// [up] searches back toward the top of the panel; the default hunts downward.
/// Getting this backwards drags away from the target until the helper gives up.
Future<Finder> scrollToText(
  WidgetTester tester,
  String label, {
  bool up = false,
}) async {
  final finder = find.text(label);
  await tester.pumpAndSettle();

  // Driven by hand rather than through `dragUntilVisible`: that helper
  // resolves the scrollable on every iteration and throws outright if a
  // rebuild leaves it momentarily unmounted, which a sheet that re-requests
  // its height on every tap does routinely.
  //
  // Both directions get a sweep. [up] only says which to try first — a target
  // sits above or below depending on where the previous step left the panel,
  // and hard-coding that per call is how this helper kept picking wrong.
  Future<void> sweep(double dy) async {
    for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 32));
        continue;
      }
      await tester.drag(scrollable.last, Offset(0, dy));
      await tester.pumpAndSettle();
    }
  }

  if (finder.evaluate().isEmpty) await sweep(up ? 120 : -120);
  if (finder.evaluate().isEmpty) await sweep(up ? -120 : 120);

  expect(finder, findsWidgets, reason: 'never scrolled "$label" into the tree');
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  return finder;
}

/// Taps tab [index] of the editor's bottom strip by position — the strip's
/// labels are not always laid out as findable text at every window width.
Future<void> tapTab(WidgetTester tester, int index, int count) async {
  final strip = find.byType(StudioTabStrip);
  expect(strip, findsOneWidget, reason: 'the editor should show its tab strip');
  final rect = tester.getRect(strip);
  await tester.tapAt(
    Offset(rect.left + rect.width * (index + 0.5) / count, rect.center.dy),
  );
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('build a store panel with the marketing looks', (tester) async {
    // The editor picks its chrome off the window size, and the native test
    // window is short enough to get the compact layout. Force the size the
    // flow is written against.
    //
    // Caveat this cost an hour: the surface is larger than the OS window, so
    // anything past the window's height lays out and hit-tests but never
    // paints. Widget-scoped taps (`tester.tap` after `ensureVisible`) are
    // therefore fine; raw `tapAt` coordinates are not, and screenshots show
    // white where the surface overhangs the window.
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await ImageLibrary.initialize();
    await tester.pumpWidget(const ProviderScope(child: MockMyApp()));
    await tester.pumpAndSettle();
    await shoot(tester, '01-home');

    await tapText(tester, 'Create New Project');
    await shoot(tester, '02-new-project');
    await tapText(tester, 'Create Project');
    await shoot(tester, '03-project');

    await tapBiggestCard(tester);
    await shoot(tester, '04-editor');

    // Tab 1 is Background (Frame, Background, Caption, Subcaption, Screenshot).
    await tapTab(tester, 1, 5);
    await shoot(tester, '05-background-panel');
    await tapText(tester, 'Pattern');
    await shoot(tester, '06-pattern-tools');

    for (final style in ['Poster', 'Stage', 'Beams']) {
      await tapText(tester, style);
      await shoot(tester, '07-style-${style.toLowerCase()}');
    }

    // Caption, where the new effect controls live — below the fold, so scroll
    // to them and drive the outline up until the headline actually changes.
    await tapTab(tester, 2, 5);
    await shoot(tester, '08-caption-panel');

    // The editor is grouped now; outline, shadow and glow live under Effects.
    await tapText(tester, 'Effects');
    await tester.pumpAndSettle();
    await shoot(tester, '09-caption-effects');

    // Drive the outline up. Reached through its own row so it cannot be
    // confused with the Size or Tracking slider above it.
    final outline = find.descendant(
      of: find.widgetWithText(StudioSlider, 'Outline'),
      matching: find.byType(Slider),
    );
    expect(
      outline,
      findsOneWidget,
      reason: 'the Outline row should have a slider',
    );
    await tester.drag(outline, const Offset(160, 0));
    await tester.pumpAndSettle();
    await shoot(tester, '10-caption-outlined');

    // Per-letter caption ink.
    // (The parts editor is exercised later, once the frame work is done.)

    // Frame → the Studio slab, all the way to a variant so the bezel draws.
    await tapTab(tester, 0, 5);
    await shoot(tester, '12-frame-panel');
    await tapText(tester, 'Studio');
    await tapText(tester, 'Marketing');
    await tapText(tester, 'Ink');
    await shoot(tester, '13-studio-slab');

    // Build tab → a designed frame, then its punch hole and side keys.
    await tapText(tester, 'Build');
    await shoot(tester, '14-build-empty');
    await tapText(tester, 'Start from a plain frame');
    await shoot(tester, '15-built-frame');

    // The builder is split into four short groups rather than one long scroll.
    await tapText(tester, 'Camera');
    final cutout = await scrollToText(tester, 'Show cut-out');
    await tester.tap(cutout.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await shoot(tester, '16-punch-hole');

    // Stretch the hole into a pill.
    await scrollToText(tester, 'Width');
    final width = find.descendant(
      of: find.widgetWithText(StudioSlider, 'Width'),
      matching: find.byType(Slider),
    );
    expect(width, findsOneWidget);
    await tester.drag(width, const Offset(90, 0));
    await tester.pumpAndSettle();
    await shoot(tester, '17-pill-hole');

    // Side keys — each group's switch is titled with the group's own name.
    await tapText(tester, 'Keys');
    for (final group in ['Power key', 'Volume keys']) {
      final row = await scrollToText(tester, group);
      await tester.tap(row.first, warnIfMissed: false);
      await tester.pumpAndSettle();
    }
    await shoot(tester, '18-side-keys');

    // Thickness to zero is the frameless case.
    await tapText(tester, 'Body');
    await scrollToText(tester, 'Thickness', up: true);
    final thickness = find.descendant(
      of: find.widgetWithText(StudioSlider, 'Thickness'),
      matching: find.byType(Slider),
    );
    await tester.drag(thickness, const Offset(-400, 0));
    await tester.pumpAndSettle();
    await shoot(tester, '19-frameless');

    // Smooth (continuous) corners, the shape the curved-edge device frames
    // are drawn with.
    await tapText(tester, 'Body');
    await scrollToText(tester, 'Smooth', up: true);
    await tapText(tester, 'Smooth');
    await shoot(tester, '20-smooth-corners');

    // The chin, independently of the other three sides.
    final chin = await scrollToText(tester, 'Chin');
    expect(chin, findsOneWidget);
    final chinSlider = find.descendant(
      of: find.widgetWithText(StudioSlider, 'Chin'),
      matching: find.byType(Slider),
    );
    await tester.drag(chinSlider, const Offset(-200, 0));
    await tester.pumpAndSettle();
    await shoot(tester, '21-thin-chin');

    // The waterfall edge — a specular band down one side of the glass and a
    // shadow down the other.
    await scrollToText(tester, 'Edge curve');
    final curve = find.descendant(
      of: find.widgetWithText(StudioSlider, 'Edge curve'),
      matching: find.byType(Slider),
    );
    expect(curve, findsOneWidget);
    await tester.drag(curve, const Offset(400, 0));
    await tester.pumpAndSettle();
    await shoot(tester, '22-edge-curve');

    // Colouring parts of the caption separately.
    await tapTab(tester, 2, 5);
    await shoot(tester, '23a-caption-text-group');
    // Split the caption into individually styled lines and add one, which is
    // where the old run editor used to fight the keyboard.
    final split = await scrollToText(tester, 'Style each line');
    await tester.tap(split.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await shoot(tester, '23-caption-lines');

    await tapText(tester, 'Add line');
    await shoot(tester, '23b-caption-line-added');

    // Typing into a line must land in that line and leave the cursor alone.
    final field = find.byType(StudioTextField).last;
    await tester.enterText(field, 'DISTANCE');
    await tester.pumpAndSettle();
    await shoot(tester, '23c-caption-line-typed');

    // Removing the caption entirely, then putting it back. Remove is in the
    // panel header now, so it is reachable from any group.
    await tapText(tester, 'Remove');
    await shoot(tester, '24-caption-removed');
    await tapText(tester, 'Add caption');
    await shoot(tester, '25-caption-restored');
  });

  testWidgets('the five-cell tool strip at phone width', (tester) async {
    // The reported bug: five cells share the width equally, and at phone width
    // the captions ellipsised away leaving a row of anonymous glyphs. Pumped on
    // its own rather than inside the app so the surface can be phone-sized
    // without the editor swapping to its wide layout.
    //
    // Measured rather than screenshotted: a resized surface lays out and
    // hit-tests correctly but does not repaint the window region under it, so
    // a capture here comes back blank however long you pump. The label widths
    // are the actual claim anyway.
    await tester.binding.setSurfaceSize(const Size(400, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final width in [280.0, 400.0]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: StudioAppTheme.dark(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: StudioSegmented<int>(
                  value: 1,
                  dense: true,
                  onChanged: (_) {},
                  segments: const [
                    StudioSegment(0, 'Device', icon: StudioIcons.device),
                    StudioSegment(1, 'Build', icon: StudioIcons.adjust),
                    StudioSegment(2, 'Layout', icon: StudioIcons.layout),
                    StudioSegment(3, 'Move', icon: StudioIcons.transform),
                    StudioSegment(4, 'Effects', icon: StudioIcons.shadow),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in ['Device', 'Build', 'Layout', 'Move', 'Effects']) {
        expect(
          tester.getSize(find.text(label)).width,
          greaterThan(20),
          reason: '$label was squeezed out of its cell at ${width}px',
        );
      }
    }
  });
}
