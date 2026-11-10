import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/features/editor/screenshot_editor/screenshot_edit_ops.dart';
import 'package:mockmyapp/features/editor/screenshot_editor/screenshot_editor_screen.dart';

/// The photo editor opened for real, on phones and on a desktop window.
///
/// What it guards is the feel of the thing rather than its arithmetic: every
/// tool's panel fits the room kept for it, opening a tool never re-fits the
/// photo, a choice never slides out from under the finger that made it, and
/// back steps out one level at a time.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Any picture in the bundle will do; this one is small, phone-shaped and
  // always there. (It was an iPhone bezel PNG until those were replaced by
  // drawn frames and left the bundle.)
  const photo = 'asset:assets/templates/arrowrush/01.webp';

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: StudioAppTheme.dark(),
          home: const ScreenshotEditorScreen(
            imagePath: photo,
            screenAspect: null,
            projectId: null,
            statusBarStyle: StatusBarStyle.ios,
          ),
        ),
      ),
    );
    // The photo loads and decodes on the real event loop, a few hops long,
    // and then reads its pixels for the eyedropper; wait out both.
    for (
      var i = 0;
      i < 100 && find.byType(RetouchCanvas).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.byType(RetouchCanvas), findsOneWidget);
  }

  Future<void> tapTool(WidgetTester tester, PhotoTool tool) async {
    await tester.tap(find.text(tool.label).last);
    await tester.pump(const Duration(milliseconds: 300));
  }

  EdgeInsets insets(WidgetTester tester) =>
      tester.widget<RetouchCanvas>(find.byType(RetouchCanvas)).chromeInsets;

  for (final (name, size) in const [
    ('phone', Size(390, 844)),
    ('small phone', Size(360, 740)),
    ('phone on its side', Size(844, 390)),
    ('tablet', Size(1024, 768)),
    ('desktop window', Size(1280, 800)),
  ]) {
    testWidgets('every tool opens, fits and keeps the photo still on a $name', (
      tester,
    ) async {
      await open(tester, size);
      final resting = insets(tester);
      expect(find.textContaining('Pick a tool'), findsOneWidget);

      for (final tool in PhotoTool.values) {
        await tapTool(tester, tool);
        // A RenderFlex overflow is reported as an exception and fails the
        // test on its own; this is the other half of fitting.
        expect(
          insets(tester),
          resting,
          reason: 'opening ${tool.label} re-fitted the photo',
        );
      }
    });
  }

  testWidgets('a wide window puts the tools beside the photo', (tester) async {
    await open(tester, const Size(1280, 800));
    final photo = insets(tester);
    // Room kept on both sides, little underneath.
    expect(photo.left, greaterThan(70));
    expect(photo.right, greaterThan(250));
    expect(photo.bottom, lessThan(60));
    expect(find.textContaining('Pick a tool on the left'), findsOneWidget);

    await tapTool(tester, PhotoTool.adjust);
    // The open tool names itself at the head of its panel.
    expect(find.text('Adjust'), findsNWidgets(2));
    expect(find.text('Brightness'), findsWidgets);
  });

  testWidgets('the tool bar shows every tool on a phone', (tester) async {
    await open(tester, const Size(390, 844));
    for (final tool in PhotoTool.values) {
      final at = tester.getCenter(find.text(tool.label).last);
      expect(at.dx, inInclusiveRange(0, 390), reason: tool.label);
    }
  });

  testWidgets('a text layer is added, boxed and given a box colour', (
    tester,
  ) async {
    await open(tester, const Size(390, 844));
    await tapTool(tester, PhotoTool.text);
    await tester.tap(find.text('Add text'));
    await tester.pumpAndSettle();

    // The words open for typing straight away, over the photo.
    await tester.enterText(find.byType(EditableText), 'Set alarms fast');
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();

    final box = find.text('Box');
    final before = tester.getTopLeft(box);
    await tester.tap(box);
    await tester.pump(const Duration(milliseconds: 300));

    // Box brings a second colour, and a way to choose which the swatches
    // set — without adding a row that pushes the one tapped out of place.
    expect(tester.getTopLeft(find.text('Box').first), before);
    // The toggle's two sides — beside the tool bar's own "Text".
    expect(find.text('Text'), findsNWidgets(2));
    expect(find.text('Box'), findsNWidgets(2));
  });

  testWidgets('back closes the open tool before it leaves the editor', (
    tester,
  ) async {
    await open(tester, const Size(390, 844));
    await tapTool(tester, PhotoTool.adjust);
    expect(find.textContaining('Pick a tool below'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Pick a tool below'), findsOneWidget);
    expect(find.byType(RetouchCanvas), findsOneWidget);
  });

  testWidgets('the Hide tool shows its pages whole on a small phone', (
    tester,
  ) async {
    await open(tester, const Size(360, 740));
    await tapTool(tester, PhotoTool.hide);
    for (final page in ['Hide areas', 'Status bar', 'Nav bar']) {
      final chip = find.text(page);
      expect(chip, findsOneWidget, reason: page);
      expect(tester.getRect(chip).right, lessThanOrEqualTo(360), reason: page);
    }
  });

  List<EditOp> ops(WidgetTester tester) =>
      tester.widget<RetouchCanvas>(find.byType(RetouchCanvas)).ops;

  /// Taps a choice in a strip, scrolling it into view first: the test font
  /// is far wider than the real one, and pushes the end of a strip off a
  /// phone that shows it whole.
  Future<void> tapChip(WidgetTester tester, String label) async {
    final chip = find.text(label, skipOffstage: false).last;
    await tester.ensureVisible(chip);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(chip);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a status bar is put on, made taller and taken off', (
    tester,
  ) async {
    await open(tester, const Size(390, 844));
    await tapTool(tester, PhotoTool.hide);
    await tester.tap(find.text('Status bar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tapChip(tester, 'Samsung');

    final bar = ops(tester).whereType<StatusBarOp>().single;
    expect(bar.style, StatusBarStyle.samsung);

    await tester.drag(find.byType(Slider), const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 300));
    final taller = ops(tester).whereType<StatusBarOp>().single;
    expect(taller.height, greaterThan(bar.height));
    expect(taller.style, StatusBarStyle.samsung);

    await tapChip(tester, 'Off');
    expect(ops(tester).whereType<StatusBarOp>(), isEmpty);
  });

  testWidgets('a navigation bar is drawn in the style picked', (tester) async {
    await open(tester, const Size(390, 844));
    await tapTool(tester, PhotoTool.hide);
    await tester.tap(find.text('Nav bar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tapChip(tester, '3 buttons');

    final bar = ops(tester).whereType<NavBarOp>().single;
    expect(bar.style, NavBarStyle.buttons);
    expect(bar.background.a, 1, reason: 'three buttons sit on a bar');

    await tapChip(tester, 'None');
    expect(ops(tester).whereType<NavBarOp>().single.background.a, 0);

    // The iPhone's indicator goes straight over the app.
    await tapChip(tester, 'iPhone');
    final ios = ops(tester).whereType<NavBarOp>().single;
    expect(ios.style, NavBarStyle.ios);
    expect(ios.background.a, 0);
  });

  testWidgets('an area drawn in Hide stays selected and takes a new style', (
    tester,
  ) async {
    await open(tester, const Size(390, 844));
    await tapTool(tester, PhotoTool.hide);
    final canvas = find.byType(RetouchCanvas);
    await tester.dragFrom(
      tester.getCenter(canvas) - const Offset(60, 60),
      const Offset(120, 60),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final drawn = ops(tester).whereType<HideOp>().single;
    expect(drawn.style, HideStyle.blur);
    expect(tester.widget<RetouchCanvas>(canvas).selection?.id, drawn.id);

    await tester.tap(find.text('Cover'));
    await tester.pump(const Duration(milliseconds: 300));
    final covered = ops(tester).whereType<HideOp>().single;
    expect(covered.id, drawn.id);
    expect(covered.style, HideStyle.cover);
    expect(covered.center, drawn.center, reason: 'restyled where it was');
  });

  testWidgets('a side panel tucked away leaves a tab to bring it back', (
    tester,
  ) async {
    await open(tester, const Size(1280, 800));
    await tapTool(tester, PhotoTool.hide);
    final wide = insets(tester);
    expect(find.text('Hide areas'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide the panel'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Hide areas'), findsNothing);
    expect(
      insets(tester).right,
      lessThan(wide.right),
      reason: 'the photo has the room the panel had',
    );

    await tester.tap(find.bySemanticsLabel('Show the Hide panel'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Hide areas'), findsOneWidget);
  });

  testWidgets('tapping the open tool tucks its panel away and back', (
    tester,
  ) async {
    await open(tester, const Size(390, 844));
    await tapTool(tester, PhotoTool.hide);
    expect(find.text('Hide areas'), findsOneWidget);

    await tapTool(tester, PhotoTool.hide);
    expect(find.text('Hide areas'), findsNothing);
    // The tool is still on: a drag still hides.
    await tester.dragFrom(
      tester.getCenter(find.byType(RetouchCanvas)),
      const Offset(80, 40),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(ops(tester).whereType<HideOp>(), hasLength(1));

    await tester.tap(find.bySemanticsLabel('Show the tool panel'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Hide areas'), findsOneWidget);
  });
}
