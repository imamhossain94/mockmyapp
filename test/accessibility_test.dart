// The accessibility floor, asserted rather than hoped for.
//
// Flutter ships the guidelines as matchers, so this is not a hand-rolled
// opinion about what "accessible" means: `labeledTapTargetGuideline` walks the
// live semantics tree and fails on any node that can be tapped but says
// nothing, and `textContrastGuideline` fails on text that does not clear WCAG
// AA against what is painted behind it. Both run against the real component
// library rather than a fixture, so a control that loses its label loses a test
// with it — and because every screen in the app is built out of these
// components, one pass here is the whole app's floor.
//
// Contrast is checked in BOTH themes on purpose: the tokens differ, and a pair
// that clears AA on the dark panel can fail on the light one.

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/app/theme/studio_icons.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';

/// Every node in the live semantics tree, flattened.
///
/// Read directly rather than through `find.bySemanticsLabel`, which resolves a
/// label against each element's *own* semantics and so cannot see one that only
/// exists on a merged node — which is most of them here, since a chip's label,
/// its selected flag and its tap action are three widgets that become one node.
/// This walk sees what a screen reader sees.
List<SemanticsNode> _nodes(WidgetTester tester) {
  final out = <SemanticsNode>[];
  void walk(SemanticsNode node) {
    out.add(node);
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(tester.binding.rootElement!.renderObject!.debugSemantics!);
  return out;
}

/// The single node announced as [label].
SemanticsNode _labelled(WidgetTester tester, String label) {
  final all = _nodes(tester);
  final matches = all.where((n) => n.label == label).toList();
  if (matches.length != 1) {
    fail(
      'expected exactly one node labelled "$label", found ${matches.length} '
      'among ${all.map((n) => n.label).where((l) => l.isNotEmpty).toList()}',
    );
  }
  return matches.single;
}

Tristate _selected(WidgetTester tester, String label) =>
    _labelled(tester, label).getSemanticsData().flagsCollection.isSelected;

bool _inGroup(WidgetTester tester, String label) => _labelled(
  tester,
  label,
).getSemanticsData().flagsCollection.isInMutuallyExclusiveGroup;

/// Pumps [child] inside the app's own theme, in [brightness], painted at
/// [scale] times its size.
Future<void> pumpStudio(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.dark,
  double scale = 1,
}) async {
  // Everything on screen at once. A node scrolled out of view is not in the
  // semantics tree, and a guideline that silently skipped half the gallery
  // would pass for the wrong reason. The view grows with [scale] for the same
  // reason: the contrast guideline skips a node painted past its edge.
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(420, 1600) * scale;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark
          ? StudioAppTheme.dark()
          : StudioAppTheme.light(),
      home: Scaffold(
        // Scaled in paint only, so every component is laid out exactly as it
        // is at 1x.
        body: Center(
          child: Transform.scale(
            scale: scale,
            child: SizedBox(width: 360, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  /// Every interactive component the library offers, in one tree.
  Widget gallery() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StudioButton(label: 'Primary', onPressed: () {}),
      StudioButton(
        label: 'Ghost',
        variant: StudioButtonVariant.ghost,
        icon: StudioIcons.add,
        onPressed: () {},
      ),
      StudioButton(
        label: 'Danger',
        variant: StudioButtonVariant.danger,
        onPressed: () {},
      ),
      const StudioButton(label: 'Disabled'),
      StudioChip(label: 'Apple', onTap: () {}),
      StudioChip(label: 'Google', selected: true, onTap: () {}),
      StudioListRow(title: 'Plain row', onTap: () {}),
      StudioListRow(
        title: 'Selected row',
        icon: StudioIcons.device,
        selected: true,
        onTap: () {},
      ),
      StudioSegmented<int>(
        value: 0,
        segments: const [StudioSegment(0, 'Round'), StudioSegment(1, 'Smooth')],
        onChanged: (_) {},
      ),
      StudioSlider(
        label: 'Corners',
        value: 0.5,
        min: 0,
        max: 1,
        display: (v) => '${(v * 100).round()}%',
        onChanged: (_) {},
      ),
      Row(
        children: [
          StudioSwatch(color: const Color(0xFF2C3C52), onTap: () {}),
          StudioSwatch(
            color: const Color(0xFFC96A3C),
            tooltip: '#C96A3C',
            onTap: () {},
          ),
          StudioSwatch(
            color: const Color(0x80FFFFFF),
            semanticLabel: 'Body colour',
            selected: true,
            onTap: () {},
          ),
        ],
      ),
    ],
  );

  group('every control says what it is', () {
    testWidgets('nothing tappable is unlabelled', (tester) async {
      // The guideline this library failed hardest: a colour swatch is a painted
      // rectangle, and colour is precisely what a screen reader cannot see.
      final handle = tester.ensureSemantics();
      await pumpStudio(tester, gallery());
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('a swatch falls back through its tooltip to its hex', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpStudio(tester, gallery());

      // Nothing given: the hex is what is left, and it beats silence.
      _labelled(tester, '#2C3C52');
      // A tooltip is a better answer than the hex...
      _labelled(tester, '#C96A3C');
      // ...and a caller who knows the colour's role beats both.
      _labelled(tester, 'Body colour');
      handle.dispose();
    });

    testWidgets('a slider is named, and its value is the printed one', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpStudio(tester, gallery());

      // Stated once. The caption is excluded from semantics precisely so that
      // this group label is the only "Corners" in the tree.
      _labelled(tester, 'Corners');

      final slider = _nodes(
        tester,
      ).singleWhere((n) => n.getSemanticsData().flagsCollection.isSlider);
      expect(
        slider.value,
        '50%',
        reason: 'spoken as the readout shows it, not as a raw double',
      );
      final data = slider.getSemanticsData();
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      expect(data.hasAction(SemanticsAction.decrease), isTrue);
      handle.dispose();
    });
  });

  group('state that is painted is also spoken', () {
    testWidgets('a selected chip and row report themselves selected', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpStudio(tester, gallery());

      expect(_selected(tester, 'Google'), Tristate.isTrue);
      expect(_selected(tester, 'Apple'), Tristate.isFalse);
      expect(_selected(tester, 'Selected row'), Tristate.isTrue);
      expect(_selected(tester, 'Plain row'), Tristate.isFalse);
      handle.dispose();
    });

    testWidgets('a segmented control reads as one choice among several', (
      tester,
    ) async {
      // Without this a screen reader announces a row of unrelated buttons and
      // never says which one is in force.
      final handle = tester.ensureSemantics();
      await pumpStudio(tester, gallery());

      expect(_inGroup(tester, 'Round'), isTrue);
      expect(_selected(tester, 'Round'), Tristate.isTrue);
      expect(_inGroup(tester, 'Smooth'), isTrue);
      expect(_selected(tester, 'Smooth'), Tristate.isFalse);
      handle.dispose();
    });

    testWidgets('a disabled button is not offered as tappable', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpStudio(tester, gallery());

      final data = _labelled(tester, 'Disabled').getSemanticsData();
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });
  });

  group('text clears WCAG AA in both themes', () {
    // Not a sample: the same gallery every other test in this file asserts on,
    // selected states and all. Three of those states used to fail —
    //
    //   selected chip     accent #3574F0 on its own wash      2.51 / 3.77
    //   selected segment  white on accent #3574F0             4.28
    //   danger button     white on danger #DB5C5C             3.69
    //
    // — which is what moved `accent` to #336FE6, `danger` to #C15151 and put
    // chip text on the new `onAccentSubtle` token. Both themes, because the
    // palettes differ and a pair that clears AA on the dark panel can fail on
    // the light one.
    //
    // Painted at twice the size, because the guideline never reads a text
    // colour. It photographs the screen at one pixel per logical pixel,
    // whatever the device pixel ratio, and takes the commonest light and dark
    // colours in each label's box to be the text and what is behind it. A
    // regular 14px Inter stroke is barely wider than a pixel, so few of its
    // pixels are fully covered, and whether they outnumber the commonest edge
    // shade depends on the machine, because the test shell draws glyphs with
    // the host's own font engine. With a Mac's CoreText the text colour wins.
    // With Linux's FreeType an edge shade won, and CI read the plain and
    // selected rows as 1.41 and 1.17 when they are 14.21 and 12.65. At twice
    // the size every stroke has a solid core on both, and the bar stays where
    // it was: the guideline takes the 14px from the style, not from the
    // screen, so it still asks for 4.5.
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name} theme', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpStudio(tester, gallery(), brightness: brightness, scale: 2);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });

  group('the tab strip and the tool rail', () {
    Widget navigation() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StudioTabStrip(
          currentIndex: 1,
          onChanged: (_) {},
          items: const [
            StudioTabItem(StudioIcons.device, 'Frame'),
            StudioTabItem(StudioIcons.layout, 'Layout'),
          ],
        ),
        SizedBox(
          height: 200,
          width: 72,
          child: StudioToolRail(
            currentIndex: 0,
            onChanged: (_) {},
            items: const [
              StudioTabItem(StudioIcons.device, 'Screens'),
              StudioTabItem(StudioIcons.shadow, 'Effects'),
            ],
          ),
        ),
      ],
    );

    testWidgets('name their icon-only tabs and say which is current', (
      tester,
    ) async {
      // Both strip their captions when the window is tight, at which point the
      // glyph is all that is left on screen and the tooltip is all that is left
      // to read.
      final handle = tester.ensureSemantics();
      await pumpStudio(tester, navigation());
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      expect(_selected(tester, 'Layout'), Tristate.isTrue);
      expect(_selected(tester, 'Frame'), Tristate.isFalse);
      expect(_selected(tester, 'Screens'), Tristate.isTrue);
      expect(_selected(tester, 'Effects'), Tristate.isFalse);
      handle.dispose();
    });
  });
}
