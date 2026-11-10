import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/app/theme/studio_tokens.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/panels/background_panel.dart';
import 'package:mockmyapp/features/editor/panels/caption_panel.dart';
import 'package:mockmyapp/features/editor/panels/frame_layout_panel.dart';
import 'package:mockmyapp/features/editor/panels/screenshot_panel.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';

/// The shipped frame manifest, read straight off disk — see
/// `screens_smoke_test.dart` for why this is not `rootBundle`.
final FrameCatalog catalog = frameCatalogFromManifest(
  jsonDecode(File('assets/frames/manifest.json').readAsStringSync())
      as Map<String, dynamic>,
);

/// Pane widths every panel has to survive.
///
/// The panels were written against a fixed ~350dp phone sheet. The docked
/// inspector is drag-resizable, so that stopped being true the moment it
/// shipped: five 52dp tool buttons, four 44dp swatches and a slider whose
/// controls alone claim 236dp all overflowed once the pane was dragged in.
///
/// The floor is [StudioLayout.inspectorMinWidth] — what the divider clamps to —
/// and the rest step up to a comfortable desktop width.
const _paneWidths = <double>[260, 300, 320, 340, 380, 420];

/// The inspector's own padding, so a width here means the same thing it means
/// in the editor. Mirrors `_Inspector` in `editor_screen.dart`.
const _inspectorPadding = EdgeInsets.fromLTRB(
  StudioSpace.l,
  StudioSpace.m,
  StudioSpace.l,
  0,
);

/// Builds [panel] fresh at [width], opens exactly [section], and returns any
/// layout error.
///
/// One section per tree on purpose: an overflow leaves an exception pending,
/// and walking on to the next section from a tree that already failed reports
/// the first fault over and over instead of finding the rest.
Future<Object?> probe(
  WidgetTester tester,
  Widget Function() build,
  String? section,
  double width,
) async {
  tester.view.physicalSize = const Size(1440, 900) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [frameCatalogProvider.overrideWith((ref) => catalog)],
      child: MaterialApp(
        theme: StudioAppTheme.dark(),
        builder: StudioLayoutScope.wrap,
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: width,
              height: 900,
              child: Padding(padding: _inspectorPadding, child: build()),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  final opening = tester.takeException();
  if (opening != null) return opening;

  if (section != null && find.text(section).evaluate().isNotEmpty) {
    await tester.tap(find.text(section).first, warnIfMissed: false);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    return tester.takeException();
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final device = catalog.devices.first;
  final placement = FramePlacement(
    deviceId: device.id,
    variantId: device.variants.first.id,
  );

  /// Walks [sections] × [_paneWidths] and fails naming the first bad pair.
  ///
  /// A null section means "whatever the panel opens on".
  Future<void> sweep(
    WidgetTester tester,
    Widget Function() build,
    List<String?> sections,
  ) async {
    for (final section in sections) {
      for (final width in _paneWidths) {
        final error = await probe(tester, build, section, width);
        expect(
          error,
          isNull,
          reason: '${section ?? 'opening section'} at ${width.toInt()}dp',
        );
      }
    }
  }

  group('panels survive a dragged-in inspector', () {
    testWidgets('caption', (tester) async {
      var spec = const CaptionSpec(text: 'Your headline goes here.');
      await sweep(
        tester,
        () => StatefulBuilder(
          builder: (context, setState) => CaptionPanel(
            styles: const [],
            onSaveStyle: (_, _) {},
            onApplyStyle: (_) {},
            onDeleteStyle: (_) {},
            spec: spec,
            backdrop: const Color(0xFF5B5FEF),
            onChanged: (c) => setState(() => spec = c),
            onRemove: () {},
          ),
        ),
        const [null, 'Size', 'Colour', 'Effects'],
      );
    });

    testWidgets('subcaption', (tester) async {
      var spec = const CaptionSpec(
        text: 'Supporting detail goes here',
        size: 34,
        lineHeight: 42,
        bold: false,
      );
      await sweep(
        tester,
        () => StatefulBuilder(
          builder: (context, setState) => CaptionPanel(
            styles: const [],
            onSaveStyle: (_, _) {},
            onApplyStyle: (_) {},
            onDeleteStyle: (_) {},
            spec: spec,
            backdrop: const Color(0xFF5B5FEF),
            isSubCaption: true,
            onChanged: (c) => setState(() => spec = c),
            onRemove: () {},
          ),
        ),
        const [null, 'Size', 'Colour', 'Effects'],
      );
    });

    testWidgets('frame', (tester) async {
      var current = placement;
      await sweep(
        tester,
        () => StatefulBuilder(
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
        const [null, 'Build', 'Place', '3D'],
      );
    });

    testWidgets('background', (tester) async {
      Background background = const SolidBackground(Color(0xFF3574F0));
      await sweep(
        tester,
        () => StatefulBuilder(
          builder: (context, setState) => BackgroundPanel(
            projectId: 'test-project',
            background: background,
            canvasAspect: 1284 / 2778,
            onChanged: (b) => setState(() => background = b),
          ),
        ),
        const [null, 'Gradient', 'Pattern', 'Image'],
      );
    });

    testWidgets('screenshot', (tester) async {
      var spec = const ScreenshotSpec();
      await sweep(
        tester,
        () => StatefulBuilder(
          builder: (context, setState) => ScreenshotPanel(
            projectId: 'test-project',
            spec: spec,
            device: device,
            onChanged: (s) => setState(() => spec = s),
          ),
        ),
        const [null, 'Border', 'Transform'],
      );
    });
  });

  testWidgets('the slider stacks its caption rather than overflowing', (
    tester,
  ) async {
    // The row's controls alone — two 48dp nudge targets, the gap and the
    // readout — claim 236dp, so a narrow pane cannot also fit the caption
    // beside them. It goes above instead of being ellipsised to nothing.
    // Scrollable, so the height is unbounded exactly as it is inside a panel.
    // Material's Slider fills whatever height it is given, so a fixed-height
    // box would measure the box rather than the row.
    Widget slider(double width) => MaterialApp(
      theme: StudioAppTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: StudioSlider(
              label: 'Rotation',
              value: 0.5,
              min: 0,
              max: 1,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(slider(400));
    final wide = tester.getRect(find.byType(StudioSlider));
    final wideLabel = tester.getRect(find.text('Rotation'));

    await tester.pumpWidget(slider(240));
    await tester.pump();
    final narrow = tester.getRect(find.byType(StudioSlider));
    final narrowLabel = tester.getRect(find.text('Rotation'));

    expect(tester.takeException(), isNull);
    expect(
      narrow.height,
      greaterThan(wide.height),
      reason: 'stacked, so it is taller',
    );
    expect(
      narrowLabel.left,
      lessThan(wideLabel.left + 8),
      reason: 'caption still starts at the leading edge',
    );
  });
}
