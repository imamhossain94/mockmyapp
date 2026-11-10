import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/app/theme/studio_icons.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/panels/background_panel.dart';
import 'package:mockmyapp/features/editor/panels/caption_panel.dart';
import 'package:mockmyapp/features/editor/panels/frame_layout_panel.dart';
import 'package:mockmyapp/features/editor/panels/screenshot_panel.dart';
import 'package:mockmyapp/features/editor/widgets/hsv_color_picker.dart';
import 'package:mockmyapp/features/editor/widgets/tool_sheet_height.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';

/// The shipped frame manifest, read straight off disk — see
/// `screens_smoke_test.dart` for why this is not `rootBundle`.
final FrameCatalog catalog = frameCatalogFromManifest(
  jsonDecode(File('assets/frames/manifest.json').readAsStringSync())
      as Map<String, dynamic>,
);

/// The tool sheet's real box: full phone width, and the height the editor gives
/// its tallest tab. Panels are laid out inside a fixed slab, so a section that
/// overflows it is a bug the user sees as a yellow-and-black bar.
const Size _sheetBox = Size(390, 420);

Future<void> pumpPanel(WidgetTester tester, Widget panel) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [frameCatalogProvider.overrideWith((ref) => catalog)],
      child: MaterialApp(
        theme: StudioAppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: _sheetBox.width,
              height: _sheetBox.height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: panel,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Taps a segmented cell by its caption and settles.
Future<void> tapSegment(WidgetTester tester, String label) async {
  // A crowded strip stops sharing its width equally and scrolls instead, so a
  // segment can be laid out past the right edge.
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label), warnIfMissed: false);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final device = catalog.devices.first;
  final placement = FramePlacement(
    deviceId: device.id,
    variantId: device.variants.first.id,
  );

  testWidgets('screenshot panel walks its three sections', (tester) async {
    var spec = const ScreenshotSpec();
    await pumpPanel(
      tester,
      StatefulBuilder(
        builder: (context, setState) => ScreenshotPanel(
          projectId: 'test-project',
          spec: spec,
          device: device,
          onChanged: (s) => setState(() => spec = s),
        ),
      ),
    );

    // Corners and stroke now share one tab, and transform has its own.
    expect(find.text('Image'), findsOneWidget);
    expect(find.text('Border'), findsOneWidget);
    expect(find.text('Transform'), findsWidgets);

    await tapSegment(tester, 'Border');
    expect(find.text('CORNERS'), findsOneWidget);
    expect(find.text('STROKE'), findsOneWidget);

    await tapSegment(tester, 'Transform');
    expect(find.text('TRANSFORM'), findsOneWidget);
    expect(find.text('Reset transform'), findsOneWidget);
  });

  testWidgets('frame panel walks its three sections', (tester) async {
    var current = placement;
    await pumpPanel(
      tester,
      StatefulBuilder(
        builder: (context, setState) => FrameLayoutPanel(
          placement: current,
          device: device,
          catalog: catalog,
          onPlacementChanged: (p) => setState(() => current = p),
          onLayoutPreset: (_) {},
          frameCount: 1,
          frameIndex: 0,
          onSelectFrame: (_) {},
          onAddFrame: () {},
          onRemoveFrame: null,
        ),
      ),
    );

    for (final section in ['Build', 'Place', '3D']) {
      await tapSegment(tester, section);
    }
    // 3D is the last one tapped: the angle opens it, and the shadow and the
    // opacity that were Effects follow below.
    expect(find.text('ANGLE'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('OPACITY'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.text('Drop shadow'), findsOneWidget);
    expect(find.text('OPACITY'), findsOneWidget);
  });

  testWidgets('background panel walks its four fills', (tester) async {
    Background background = const SolidBackground(Color(0xFF3574F0));
    await pumpPanel(
      tester,
      StatefulBuilder(
        builder: (context, setState) => BackgroundPanel(
          projectId: 'test-project',
          background: background,
          onChanged: (b) => setState(() => background = b),
        ),
      ),
    );

    for (final fill in ['Gradient', 'Pattern', 'Image', 'Solid']) {
      await tapSegment(tester, fill);
    }
    // Back on Solid, the preset strip is there rather than a six-row wrap.
    expect(find.text('PRESETS'), findsOneWidget);
  });

  testWidgets('the image backdrop can be framed, blurred and washed', (
    tester,
  ) async {
    Background background = const ImageBackground('/tmp/backdrop.png');
    await pumpPanel(
      tester,
      StatefulBuilder(
        builder: (context, setState) => BackgroundPanel(
          projectId: 'test-project',
          background: background,
          onChanged: (b) => setState(() => background = b),
        ),
      ),
    );

    await tapSegment(tester, 'Image');
    // Picking and tuning are separate views, so neither scroll fights the other.
    expect(find.text('Library'), findsOneWidget);
    await tapSegment(tester, 'Adjust');

    expect(find.text('FIT'), findsOneWidget);
    expect(find.text('FRAMING'), findsOneWidget);
    expect(find.text('BLUR & WASH'), findsOneWidget);

    await tapSegment(tester, 'Stretch');
    expect((background as ImageBackground).fit, ImageBackgroundFit.fill);

    // Reset is live once anything has moved, and puts every knob back.
    await tester.ensureVisible(find.text('Reset adjustments'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset adjustments'));
    await tester.pumpAndSettle();
    final reset = background as ImageBackground;
    expect(reset.fit, ImageBackgroundFit.cover);
    expect(reset.path, '/tmp/backdrop.png');
  });

  testWidgets('each section asks the sheet for its own height', (tester) async {
    final asked = <double>[];
    var current = placement;

    await pumpPanel(
      tester,
      NotificationListener<ToolSheetHeightRequest>(
        onNotification: (n) {
          asked.add(n.height);
          return true;
        },
        child: StatefulBuilder(
          builder: (context, setState) => FrameLayoutPanel(
            placement: current,
            device: device,
            catalog: catalog,
            onPlacementChanged: (p) => setState(() => current = p),
            onLayoutPreset: (_) {},
            frameCount: 1,
            frameIndex: 0,
            onSelectFrame: (_) {},
            onAddFrame: () {},
            onRemoveFrame: null,
          ),
        ),
      ),
    );

    // The panel announces itself on mount, opened on Place…
    expect(asked, isNotEmpty);
    expect(asked.first, 460);

    // …and every section it switches to asks for something of its own.
    await tapSegment(tester, 'Build');
    expect(asked.last, 460);

    // 3D asks for the whole sheet: its angle tiles and its pad are meant to be
    // seen at once, beside the device they are turning.
    final before = asked.length;
    await tapSegment(tester, '3D');
    expect(asked.length, greaterThan(before));
    expect(asked.last, 460);
  });

  testWidgets('a section asks the sheet for less as well as more', (
    tester,
  ) async {
    // The frame panel's sections all want the full sheet now that one of
    // them is 3D; the screenshot panel's do not, and a sheet that only ever
    // grew would sit half-empty over the canvas it is meant to leave room for.
    final asked = <double>[];
    var spec = const ScreenshotSpec();

    await pumpPanel(
      tester,
      NotificationListener<ToolSheetHeightRequest>(
        onNotification: (n) {
          asked.add(n.height);
          return true;
        },
        child: StatefulBuilder(
          builder: (context, setState) => ScreenshotPanel(
            projectId: 'test-project',
            spec: spec,
            device: device,
            onChanged: (s) => setState(() => spec = s),
          ),
        ),
      ),
    );

    expect(asked, isNotEmpty);
    await tapSegment(tester, 'Transform');
    expect(asked.last, lessThan(asked.first));
  });

  testWidgets('the drop shadow switch turns the shadow off', (tester) async {
    // Default placements carry a shadow, so the switch starts on.
    var current = placement;
    expect(current.shadow, isNotNull);

    await pumpPanel(
      tester,
      StatefulBuilder(
        builder: (context, setState) => FrameLayoutPanel(
          placement: current,
          device: device,
          catalog: catalog,
          onPlacementChanged: (p) => setState(() => current = p),
          onLayoutPreset: (_) {},
          frameCount: 1,
          frameIndex: 0,
          onSelectFrame: (_) {},
          onAddFrame: () {},
          onRemoveFrame: null,
        ),
      ),
    );

    // Below the angle and the depth, in the tab that used to be Effects.
    await tapSegment(tester, '3D');
    await tester.dragUntilVisible(
      find.byType(Switch),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // `copyWith(shadow: null)` used to mean "leave it alone", so this stuck on.
    expect(current.shadow, isNull);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(current.shadow, isNotNull);
  });

  testWidgets('hex is typed on the in-app keypad, not the system keyboard', (
    tester,
  ) async {
    Color emitted = const Color(0xFF3574F0);
    await pumpPanel(
      tester,
      SingleChildScrollView(
        child: HsvColorPicker(color: emitted, onChanged: (c) => emitted = c),
      ),
    );

    // The field never raises the system keyboard…
    final hexField = find.byType(StudioTextField);
    expect(tester.widget<StudioTextField>(hexField).readOnly, isTrue);
    // …and the pad is out of the way until asked for.
    expect(find.widgetWithText(InkWell, 'A'), findsNothing);

    await tester.tap(hexField);
    await tester.pumpAndSettle();

    // Sixteen characters, all one tap away.
    for (final key in ['0', '5', '9', 'A', 'F']) {
      expect(find.widgetWithText(InkWell, key), findsOneWidget);
    }

    for (final key in ['F', 'F', '0', '0', '0', '0']) {
      await tester.tap(find.widgetWithText(InkWell, key));
      await tester.pump();
    }

    // Applied the moment the sixth character lands — no separate confirm.
    expect(emitted.toARGB32(), 0xFFFF0000);
  });

  testWidgets('caption text opens in a sheet instead of raising the keyboard', (
    tester,
  ) async {
    var spec = const CaptionSpec(text: 'Ship it');
    await pumpPanel(
      tester,
      StatefulBuilder(
        builder: (context, setState) => CaptionPanel(
          styles: const [],
          onSaveStyle: (_, _) {},
          onApplyStyle: (_) {},
          onDeleteStyle: (_) {},
          spec: spec,
          backdrop: const Color(0xFF5B5FEF),
          onChanged: (c) => setState(() => spec = c),
        ),
      ),
    );

    // The inline field shows the value but refuses to edit it.
    final inline = tester.widget<StudioTextField>(
      find.byType(StudioTextField).first,
    );
    expect(inline.readOnly, isTrue);

    await tester.tap(find.byType(StudioTextField).first);
    await tester.pumpAndSettle();

    expect(find.text('Headline text'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('a crowded segmented control keeps its labels', (tester) async {
    // The regression: five cells share the width equally, and at phone width
    // "Device" plus its glyph and padding no longer fit — so the label
    // ellipsised away and the strip read as a row of anonymous icons.
    const labels = ['Device', 'Build', 'Layout', 'Move', 'Effects'];

    await pumpPanel(
      tester,
      SizedBox(
        width: 300,
        child: StudioSegmented<int>(
          value: 0,
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
    );

    for (final label in labels) {
      // Whole, never cut to "Dev…": a label that does not fit is scaled down
      // to, rather than truncated.
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: '$label should be shown whole',
      );
      // The real check: the caption is drawn wide enough to read, not shrunk
      // to a couple of pixels.
      expect(
        tester.getRect(find.text(label)).width,
        greaterThan(20),
        reason: '$label was squeezed out of its cell',
      );
    }

    // The glyphs are what gave way to make room.
    expect(find.byType(StudioIcon), findsNothing);
  });

  testWidgets('an uncrowded segmented control keeps its glyphs', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      SizedBox(
        width: 400,
        child: StudioSegmented<int>(
          value: 0,
          dense: true,
          onChanged: (_) {},
          segments: const [
            StudioSegment(0, 'Solid', icon: StudioIcons.solidFill),
            StudioSegment(1, 'Image', icon: StudioIcons.image),
          ],
        ),
      ),
    );

    expect(find.byType(StudioIcon), findsNWidgets(2));
    expect(find.text('Solid'), findsOneWidget);
  });

  testWidgets('the caption effect rows appear once their effect is on', (
    tester,
  ) async {
    // Outline, shadow, glow and the chip's own styling are all folded away
    // until they are switched on, so their rows are never built by the
    // default-spec smoke test above.
    var spec = const CaptionSpec(
      text: 'ARROW RUSH',
      letterSpacing: -1.5,
      strokeWidth: 5,
      shadowBlur: 10,
      shadowOffsetY: 4,
      glowBlur: 24,
      backgroundColor: Color(0xFF2645D4),
      backgroundRadius: 40,
      backgroundBorderColor: Color(0xFFFFFFFF),
      backgroundBorderWidth: 2,
    );
    await pumpPanel(
      tester,
      StatefulBuilder(
        builder: (context, setState) => CaptionPanel(
          styles: const [],
          onSaveStyle: (_, _) {},
          onApplyStyle: (_) {},
          onDeleteStyle: (_) {},
          spec: spec,
          backdrop: const Color(0xFF5B5FEF),
          onChanged: (c) => setState(() => spec = c),
        ),
      ),
    );

    // The editor is grouped now, so each control is reachable from its own
    // group rather than all of them living in one scroll.
    const groups = <String, List<String>>{
      'Text': ['Rich text'],
      'Size': ['Size', 'Line height', 'Tracking', 'Left · Right'],
      'Effects': [
        'Outline',
        'Outline colour',
        'Shadow',
        'Drop',
        'Shadow colour',
        'Glow',
        'Glow colour',
      ],
      'Colour': [
        'Highlight background',
        'Plate colour',
        'Corner',
        'Rim',
        'Rim colour',
      ],
    };

    for (final MapEntry(key: group, value: labels) in groups.entries) {
      await tapSegment(tester, group);
      for (final label in labels) {
        expect(
          find.text(label),
          findsWidgets,
          reason: '$label should be reachable from the $group group',
        );
      }
    }
  });

  testWidgets('the caption editor opens on its text, with a remove action', (
    tester,
  ) async {
    var spec = const CaptionSpec(text: 'Ship it');
    var removed = false;
    await pumpPanel(
      tester,
      StatefulBuilder(
        builder: (context, setState) => CaptionPanel(
          styles: const [],
          onSaveStyle: (_, _) {},
          onApplyStyle: (_) {},
          onDeleteStyle: (_) {},
          spec: spec,
          backdrop: const Color(0xFF5B5FEF),
          onChanged: (c) => setState(() => spec = c),
          onRemove: () => removed = true,
        ),
      ),
    );

    // Header names the layer and carries the destructive action.
    expect(find.text('Headline'), findsWidgets);
    expect(find.text('Remove'), findsOneWidget);

    // Text is the group you land on, so the first thing you can do is type.
    expect(find.byType(StudioTextField), findsWidgets);

    await tester.tap(find.text('Remove'));
    await tester.pump();
    expect(removed, isTrue);
  });
}
