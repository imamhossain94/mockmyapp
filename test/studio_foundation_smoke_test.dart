import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/app/theme/studio_icons.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/app/theme/studio_tokens.dart';
import 'package:mockmyapp/app/theme/studio_typography.dart';
import 'package:mockmyapp/features/shared/save_actions.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';

/// Builds [child] under the real Studio theme for [brightness] and pumps it.
Future<void> pumpStudio(
  WidgetTester tester,
  Brightness brightness,
  Widget child,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark
          ? StudioAppTheme.dark()
          : StudioAppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 360, child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    final name = brightness.name;

    group('[$name]', () {
      testWidgets('themes build and carry the token extension', (tester) async {
        await pumpStudio(tester, brightness, const SizedBox());
        final context = tester.element(find.byType(SizedBox).first);
        final expected = StudioColors.of(brightness);
        expect(context.studio, expected);
        expect(context.isDark, brightness == Brightness.dark);
      });

      testWidgets('buttons build in every variant and state', (tester) async {
        await pumpStudio(
          tester,
          brightness,
          Column(
            children: [
              for (final v in StudioButtonVariant.values) ...[
                StudioButton(label: 'Enabled', variant: v, onPressed: () {}),
                StudioButton(label: 'Disabled', variant: v),
                StudioButton(
                  label: 'Icon + dense + full',
                  variant: v,
                  icon: StudioIcons.export,
                  dense: true,
                  fullWidth: true,
                  onPressed: () {},
                ),
              ],
              StudioIconButton(icon: StudioIcons.undo, onPressed: () {}),
              const StudioIconButton(icon: StudioIcons.redo),
              StudioIconButton(
                icon: StudioIcons.grid,
                selected: true,
                onPressed: () {},
              ),
              StudioToolButton(icon: StudioIcons.crop, onPressed: () {}),
              StudioToolButton(
                icon: StudioIcons.layout,
                label: 'Layout',
                selected: true,
                onPressed: () {},
              ),
            ],
          ),
        );
        expect(tester.takeException(), isNull);
      });

      // A widget test reports Android, so this is the touch case: 44px, and
      // a dense button painted at 36 but tapped across the full 44.
      testWidgets('button heights honour the touch size tokens', (
        tester,
      ) async {
        await pumpStudio(
          tester,
          brightness,
          Column(
            children: [
              StudioButton(label: 'Standard', onPressed: () {}),
              StudioButton(label: 'Dense', dense: true, onPressed: () {}),
            ],
          ),
        );
        Finder painted(String label) => find.descendant(
          of: find.widgetWithText(StudioButton, label),
          matching: find.byType(TextButton),
        );
        expect(
          tester.getSize(find.widgetWithText(StudioButton, 'Standard')).height,
          StudioSizes.buttonTouch,
        );
        expect(
          tester.getSize(painted('Dense')).height,
          StudioSizes.buttonTouchDense,
        );
        expect(
          tester.getSize(find.widgetWithText(StudioButton, 'Dense')).height,
          StudioSizes.touchTarget,
        );
      });

      // Desktop density is a feature: a mouse hits a 30px button every time.
      testWidgets(
        'and keep the desktop density where a pointer is primary',
        (tester) async {
          await pumpStudio(
            tester,
            brightness,
            Column(
              children: [
                StudioButton(label: 'Standard', onPressed: () {}),
                StudioButton(label: 'Dense', dense: true, onPressed: () {}),
              ],
            ),
          );
          expect(
            tester
                .getSize(find.widgetWithText(StudioButton, 'Standard'))
                .height,
            StudioSizes.button,
          );
          expect(
            tester.getSize(find.widgetWithText(StudioButton, 'Dense')).height,
            StudioSizes.buttonCompact,
          );
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );

      testWidgets('a padded dense button takes a tap in its margin', (
        tester,
      ) async {
        var taps = 0;
        await pumpStudio(
          tester,
          brightness,
          Center(
            child: StudioButton(
              label: 'Dense',
              dense: true,
              onPressed: () => taps++,
            ),
          ),
        );
        final box = tester.getRect(find.widgetWithText(StudioButton, 'Dense'));
        // 2px inside the top of the 44px target: outside the 36px paint.
        await tester.tapAt(Offset(box.center.dx, box.top + 2));
        expect(taps, 1);
      });

      testWidgets('a loading button keeps its width and ignores taps', (
        tester,
      ) async {
        var taps = 0;
        Widget button({required bool loading}) => Center(
          child: StudioButton(
            label: 'Generate',
            icon: StudioIcons.add,
            variant: StudioButtonVariant.primary,
            loading: loading,
            onPressed: () => taps++,
          ),
        );
        await pumpStudio(tester, brightness, button(loading: false));
        final idle = tester.getSize(find.byType(StudioButton));

        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.dark
                ? StudioAppTheme.dark()
                : StudioAppTheme.light(),
            home: Scaffold(body: button(loading: true)),
          ),
        );
        await tester.pump();
        expect(tester.getSize(find.byType(StudioButton)), idle);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Generate'), findsOneWidget);
        await tester.tap(find.byType(StudioButton), warnIfMissed: false);
        await tester.pump();
        expect(taps, 0);
      });

      testWidgets(
        'standard buttons with larger minimumSize build without constraint errors',
        (tester) async {
          await pumpStudio(
            tester,
            brightness,
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48.0, 48.0)),
              onPressed: () {},
              child: const Text('Custom Min Size'),
            ),
          );
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('panels, dividers and section headers build', (tester) async {
        await pumpStudio(
          tester,
          brightness,
          Column(
            children: [
              StudioPanel(
                title: 'Frame',
                trailing: StudioIconButton(
                  icon: StudioIcons.reset,
                  onPressed: () {},
                ),
                child: const Text('body'),
              ),
              const StudioDivider(),
              const StudioSectionHeader(label: 'Background'),
              const SizedBox(height: 20, child: StudioVDivider()),
            ],
          ),
        );
        // The eyebrow is upper-cased by the component, not the caller.
        expect(find.text('FRAME'), findsOneWidget);
        expect(find.text('BACKGROUND'), findsOneWidget);
      });

      testWidgets('slider builds, formats and nudges', (tester) async {
        final changed = <double>[];
        final ended = <double>[];
        await pumpStudio(
          tester,
          brightness,
          StudioSlider(
            label: 'Scale',
            value: 50,
            min: 0,
            max: 100,
            step: 5,
            display: (v) => '${v.round()}%',
            onChanged: changed.add,
            onChangeEnd: ended.add,
          ),
        );
        expect(find.text('50%'), findsOneWidget);

        await tester.tap(find.byTooltip('Increase'));
        expect(changed.single, 55);
        expect(ended.single, 55);

        changed.clear();
        ended.clear();
        await tester.tap(find.byTooltip('Decrease'));
        expect(changed.single, 45);
        expect(ended.single, 45);
      });

      testWidgets('slider clamps out-of-range values', (tester) async {
        await pumpStudio(
          tester,
          brightness,
          StudioSlider(
            label: 'Over',
            value: 999,
            min: 0,
            max: 100,
            display: (v) => v.round().toString(),
            onChanged: (_) {},
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('100'), findsOneWidget);
      });

      testWidgets('fields and segmented build and report', (tester) async {
        Object? picked;
        await pumpStudio(
          tester,
          brightness,
          Column(
            children: [
              const StudioTextField(label: 'Name', hint: 'Untitled'),
              StudioTextField(
                icon: StudioIcons.search,
                hint: 'Search',
                trailing: StudioIconButton(
                  icon: StudioIcons.close,
                  onPressed: () {},
                ),
              ),
              const StudioTextField(hint: 'Notes', maxLines: 3),
              const StudioTextField(hint: 'Disabled', enabled: false),
              StudioSegmented<String>(
                segments: const [
                  StudioSegment('a', 'Solid', icon: StudioIcons.solidFill),
                  StudioSegment('b', 'Gradient'),
                  StudioSegment('c', 'Image'),
                ],
                value: 'a',
                onChanged: (v) => picked = v,
              ),
              const StudioSegmented<String>(
                segments: [StudioSegment('a', 'Off')],
                value: 'a',
                onChanged: null,
              ),
            ],
          ),
        );
        expect(find.text('NAME'), findsOneWidget);
        await tester.tap(find.text('Gradient'));
        expect(picked, 'b');
      });

      testWidgets('single-line field locks to the input height', (
        tester,
      ) async {
        await pumpStudio(
          tester,
          brightness,
          const StudioTextField(hint: 'One line'),
        );
        expect(
          tester.getSize(find.byType(StudioTextField)).height,
          StudioSizes.input,
        );
      });

      testWidgets('and centres its text in that height', (tester) async {
        await pumpStudio(
          tester,
          brightness,
          const StudioTextField(hint: 'One line'),
        );

        final box = tester.getRect(find.byType(StudioTextField));
        final text = tester.getRect(find.byType(EditableText));

        // The theme puts a 34dp `minHeight` on every Material input. Inheriting
        // it made the inner decorator as tall as the field's own box, and a
        // decorator packs a short child to the top — so the text sat flush
        // against the top edge with every pixel of the difference below it.
        expect(
          text.top - box.top,
          closeTo(box.bottom - text.bottom, 0.5),
          reason: 'text is centred, not packed to the top',
        );
      });

      testWidgets('a multi-line field is as tall as the lines it shows', (
        tester,
      ) async {
        await pumpStudio(
          tester,
          brightness,
          const StudioTextField(hint: 'Line 1', minLines: 1, maxLines: 4),
        );

        final box = tester.getRect(find.byType(StudioTextField));
        final text = tester.getRect(find.byType(EditableText));

        // One line of content, so the box is that line plus its own padding —
        // not the 34dp floor plus its padding on top of it.
        expect(box.height, lessThan(StudioSizes.input));
        expect(
          text.top - box.top,
          closeTo(box.bottom - text.bottom, 0.5),
          reason: 'evenly padded',
        );
      });

      testWidgets('chips, swatches and progress build', (tester) async {
        await pumpStudio(
          tester,
          brightness,
          Column(
            children: [
              Wrap(
                children: [
                  StudioChip(label: 'Plain', onTap: () {}),
                  StudioChip(
                    label: 'Selected',
                    icon: StudioIcons.check,
                    selected: true,
                    onTap: () {},
                  ),
                  const StudioChip(label: 'Static'),
                ],
              ),
              Row(
                children: [
                  StudioSwatch(color: const Color(0xFF3574F0), onTap: () {}),
                  // Translucent -> exercises the checkerboard painter.
                  StudioSwatch(
                    color: const Color(0x803574F0),
                    selected: true,
                    tooltip: '#3574F0 50%',
                    onTap: () {},
                  ),
                ],
              ),
              const StudioProgressBar(value: 0.4),
              // Out-of-range values must clamp, not assert.
              const StudioProgressBar(value: 5),
              const StudioProgressBar(value: -3),
            ],
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('swatch keeps a >=44px touch target', (tester) async {
        await pumpStudio(
          tester,
          brightness,
          Align(
            alignment: Alignment.centerLeft,
            child: StudioSwatch(color: const Color(0xFF3574F0), onTap: () {}),
          ),
        );
        final size = tester.getSize(find.byType(StudioSwatch));
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      });

      testWidgets('list rows build and fire callbacks', (tester) async {
        var taps = 0;
        var longPresses = 0;
        await pumpStudio(
          tester,
          brightness,
          Column(
            children: [
              StudioListRow(
                title: 'Tappable',
                icon: StudioIcons.settings,
                subtitle: 'With a subtitle',
                trailing: const StudioIcon(StudioIcons.chevronRight),
                onTap: () => taps++,
                onLongPress: () => longPresses++,
              ),
              const StudioListRow(title: 'Selected', selected: true),
              StudioListRow(
                title: 'Disabled',
                enabled: false,
                onTap: () => taps++,
              ),
            ],
          ),
        );
        await tester.tap(find.text('Tappable'));
        await tester.longPress(find.text('Tappable'));
        // A disabled row must swallow the tap.
        await tester.tap(find.text('Disabled'));
        expect(taps, 1);
        expect(longPresses, 1);
        expect(
          tester.getSize(find.widgetWithText(StudioListRow, 'Selected')).height,
          greaterThanOrEqualTo(StudioSizes.listRow),
        );
      });

      testWidgets('tab strip builds when tabs fit and when they scroll', (
        tester,
      ) async {
        var index = 0;
        const items = [
          StudioTabItem(StudioIcons.screenshot, 'Screen'),
          StudioTabItem(StudioIcons.frame, 'Frame'),
          StudioTabItem(StudioIcons.background, 'Background'),
          StudioTabItem(StudioIcons.caption, 'Caption'),
          StudioTabItem(StudioIcons.export, 'Export'),
        ];
        await pumpStudio(
          tester,
          brightness,
          Column(
            children: [
              // Glyphs only, which is the default: 5 * 56 = 280, so the strip
              // fits whole on the narrowest phone rather than scrolling two of
              // the five off the end.
              StudioTabStrip(
                items: items,
                currentIndex: 0,
                onChanged: (i) => index = i,
              ),
              // Forces the scrolling branch.
              const StudioTabStrip(
                items: items,
                currentIndex: 4,
                minTabWidth: 120,
                onChanged: _noop,
              ),
              // The captions are still available for anywhere with the width.
              const StudioTabStrip(
                items: items,
                currentIndex: 2,
                showLabels: true,
                onChanged: _noop,
              ),
            ],
          ),
        );
        expect(tester.takeException(), isNull);

        // Named by tooltip when the caption is off.
        await tester.tap(find.byTooltip('Frame').first);
        expect(index, 1);

        // And spelled out by the strip that opted in.
        expect(find.text('Background'), findsOneWidget);
      });

      testWidgets('empty states build in both densities', (tester) async {
        await pumpStudio(
          tester,
          brightness,
          Column(
            children: [
              StudioEmptyState(
                icon: StudioIcons.empty,
                title: 'No projects yet',
                message: 'Create one to get started.',
                primaryAction: StudioButton(
                  label: 'New project',
                  variant: StudioButtonVariant.primary,
                  onPressed: () {},
                ),
                secondaryAction: StudioButton(
                  label: 'Import',
                  onPressed: () {},
                ),
              ),
              const StudioEmptyState(
                icon: StudioIcons.image,
                title: 'Nothing here',
                compact: true,
              ),
            ],
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('empty states survive a box too short for them', (
        tester,
      ) async {
        // An editor sub-panel really can leave under 80px. The component sheds
        // its message, then its glyph, and scrolls before it ever overflows —
        // callers cannot all police the height they hand it.
        for (final height in <double>[240, 120, 78, 40]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: brightness == Brightness.dark
                  ? StudioAppTheme.dark()
                  : StudioAppTheme.light(),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 344,
                    height: height,
                    child: const StudioEmptyState(
                      compact: true,
                      icon: StudioIcons.images,
                      title: 'Library is empty',
                      message:
                          'Images you import are kept here so you can reuse '
                          'them across every screen in the project.',
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'overflowed at ${height}px tall',
          );
          expect(find.text('Library is empty'), findsOneWidget);
        }
      });

      testWidgets('sheet opens, headers, and closes', (tester) async {
        await pumpStudio(
          tester,
          brightness,
          Builder(
            builder: (context) => StudioButton(
              label: 'Open',
              onPressed: () => showStudioSheet<void>(
                context,
                title: 'Pick a device',
                actions: [
                  StudioIconButton(icon: StudioIcons.search, onPressed: () {}),
                ],
                child: const StudioListRow(title: 'iPhone 16 Pro'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Pick a device'), findsOneWidget);
        expect(find.text('iPhone 16 Pro'), findsOneWidget);

        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Pick a device'), findsNothing);
      });

      testWidgets('confirm dialog resolves true / false', (tester) async {
        late BuildContext ctx;
        await pumpStudio(
          tester,
          brightness,
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        );

        var future = showStudioConfirm(
          ctx,
          title: 'Delete project?',
          message: 'This cannot be undone.',
          confirmLabel: 'Delete',
          danger: true,
          icon: StudioIcons.delete,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(await future, isTrue);

        future = showStudioConfirm(ctx, title: 'Again?');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(await future, isFalse);
      });

      testWidgets('dialog builds with custom content', (tester) async {
        await pumpStudio(
          tester,
          brightness,
          StudioDialog(
            title: 'Rename',
            icon: StudioIcons.edit,
            content: const StudioTextField(hint: 'Project name'),
            actions: [
              StudioButton(
                label: 'Cancel',
                variant: StudioButtonVariant.ghost,
                onPressed: () {},
              ),
              StudioButton(
                label: 'Save',
                variant: StudioButtonVariant.primary,
                onPressed: () {},
              ),
            ],
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('every StudioIcons glyph renders', (tester) async {
        await pumpStudio(
          tester,
          brightness,
          Wrap(children: [for (final icon in _allIcons) StudioIcon(icon)]),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(StudioIcon), findsNWidgets(_allIcons.length));
      });

      testWidgets('typography roles all resolve', (tester) async {
        await pumpStudio(
          tester,
          brightness,
          Builder(
            builder: (context) => Column(
              children: [
                Text('display', style: StudioText.displayTitle(context)),
                Text('titleLarge', style: StudioText.titleLarge(context)),
                Text('titleSmall', style: StudioText.titleSmall(context)),
                Text('SECTION', style: StudioText.sectionLabel(context)),
                Text('body', style: StudioText.body(context)),
                Text('bodyStrong', style: StudioText.bodyStrong(context)),
                Text('caption', style: StudioText.caption(context)),
                Text('micro', style: StudioText.micro(context)),
                Text('1290x2796', style: StudioText.mono(context)),
              ],
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    });
  }

  test('token values match the design spec exactly', () {
    const dark = StudioColors.dark;
    expect(dark.canvas, const Color(0xFF1E1F22));
    expect(dark.panel, const Color(0xFF2B2D30));
    expect(dark.panelAlt, const Color(0xFF313438));
    // A step above `canvas` so a filled input still recesses against `panel`.
    expect(dark.well, const Color(0xFF26282C));
    expect(dark.overlay, const Color(0xFF2B2D30));
    // The neutral control fill — never `panelAlt`, which panels paint.
    expect(dark.control, const Color(0xFF3C3F44));
    expect(dark.border, const Color(0xFF393B40));
    expect(dark.borderSubtle, const Color(0xFF303236));
    expect(dark.borderStrong, const Color(0xFF4E5157));
    expect(dark.textPrimary, const Color(0xFFDFE1E5));
    expect(dark.textSecondary, const Color(0xFF9DA0A8));
    // Disabled text and placeholders only; was #6F737A at 2.63 on panelAlt.
    expect(dark.textTertiary, const Color(0xFF8E929A));
    // The accent moved off #3574F0 and hover reversed direction, both to clear
    // WCAG AA — white on #3574F0 measures 4.28 and white on the old #4A85F5
    // hover 3.77, and white on accent is what every filled button, selected
    // segment and selected tab in the app is. See `accessibility_test.dart`,
    // which asserts the ratios rather than the hex.
    expect(dark.accent, const Color(0xFF336FE6));
    expect(dark.accentHover, const Color(0xFF2F66D4));
    expect(dark.accentPressed, const Color(0xFF2A5BBD));
    expect(dark.accentSubtle, const Color(0x29336FE6));
    expect(dark.onAccent, const Color(0xFFFFFFFF));
    // Text on the wash, which cannot be `accent`: accent on its own tint
    // measures 2.51 here.
    expect(dark.onAccentSubtle, const Color(0xFF80A7F6));
    expect(dark.success, const Color(0xFF5FAD65));
    expect(dark.warning, const Color(0xFFD6A32E));
    // #DB5C5C put white at 3.69.
    expect(dark.danger, const Color(0xFFC15151));
    // Text roles, which the fills above are not: see `contrast_test.dart`.
    expect(dark.accentText, const Color(0xFF80A7F6));
    expect(dark.dangerText, const Color(0xFFE67F7F));
    expect(dark.successText, const Color(0xFF5FAD65));
    expect(dark.warningText, const Color(0xFFD6A32E));
    expect(dark.selectionBg, const Color(0xFF2E436E));
    expect(dark.hoverBg, const Color(0x0FFFFFFF));

    const light = StudioColors.light;
    // Light mode carries a real tonal ramp — recessed `well` < `canvas` <
    // `panel` chrome and overlays < raised `panelAlt` — which is what lets a
    // borderless filled design read as layered instead of as a white void.
    expect(light.canvas, const Color(0xFFEDEEF2));
    expect(light.panel, const Color(0xFFF4F5F8));
    expect(light.panelAlt, const Color(0xFFFFFFFF));
    expect(light.well, const Color(0xFFE4E6EC));
    // Off white, so a white `StudioPanel` inside a dialog still reads.
    expect(light.overlay, const Color(0xFFF4F5F8));
    expect(light.control, const Color(0xFFE8EAEE));
    expect(light.border, const Color(0xFFD3D5DB));
    expect(light.borderSubtle, const Color(0xFFE3E5EB));
    expect(light.borderStrong, const Color(0xFFA8ADB8));
    expect(light.textPrimary, const Color(0xFF1E1F22));
    expect(light.textSecondary, const Color(0xFF5A5D63));
    expect(light.textTertiary, const Color(0xFF676C73));
    expect(light.accent, const Color(0xFF336FE6));
    expect(light.accentHover, const Color(0xFF2F66D4));
    expect(light.accentPressed, const Color(0xFF244EA1));
    expect(light.accentSubtle, const Color(0x1A336FE6));
    expect(light.onAccent, const Color(0xFFFFFFFF));
    // Fitted against the wash over `canvas`, the darkest surface a chip sits
    // on — over white it clears comfortably, over canvas it is the tight case.
    expect(light.onAccentSubtle, const Color(0xFF2B5EC2));
    expect(light.success, const Color(0xFF3D8B40));
    expect(light.warning, const Color(0xFFB8860B));
    expect(light.danger, const Color(0xFFC4453D));
    expect(light.accentText, const Color(0xFF2B5EC2));
    expect(light.dangerText, const Color(0xFFA93A33));
    expect(light.successText, const Color(0xFF2B7030));
    expect(light.warningText, const Color(0xFF7F5C06));
    expect(light.selectionBg, const Color(0xFFD4E2FF));
    expect(light.hoverBg, const Color(0x0D000000));
  });

  test('surfaces separate by tone, so a borderless fill still reads', () {
    // The literals above can be retuned; this ordering is the rule they have to
    // keep, in both themes and in opposite directions.
    double luminance(Color c) => c.computeLuminance();

    const light = StudioColors.light;
    expect(luminance(light.well), lessThan(luminance(light.canvas)));
    expect(luminance(light.canvas), lessThan(luminance(light.panel)));
    expect(luminance(light.panel), lessThan(luminance(light.panelAlt)));

    const dark = StudioColors.dark;
    expect(luminance(dark.canvas), lessThan(luminance(dark.well)));
    expect(luminance(dark.well), lessThan(luminance(dark.panel)));
    expect(luminance(dark.panel), lessThan(luminance(dark.panelAlt)));
  });

  group('docked chrome', () {
    /// Pumps [child] and hands back a context inside it.
    Future<BuildContext> pumpWithContext(
      WidgetTester tester,
      Widget Function(Widget probe) build,
    ) async {
      late BuildContext captured;
      final probe = Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.expand();
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: StudioAppTheme.dark(),
          home: Scaffold(body: build(probe)),
        ),
      );
      return captured;
    }

    EdgeInsets marginOf(WidgetTester tester) =>
        tester.widget<SnackBar>(find.byType(SnackBar)).margin! as EdgeInsets;

    testWidgets('a toast clears the chrome a screen has docked', (
      tester,
    ) async {
      final context = await pumpWithContext(
        tester,
        (probe) => StudioBottomChrome(height: 120, child: probe),
      );

      showStudioSnack(context, 'Saved');
      await tester.pump();

      expect(marginOf(tester).bottom, 120 + StudioSpace.l);
    });

    testWidgets('and sits where Flutter puts it when nothing is docked', (
      tester,
    ) async {
      final context = await pumpWithContext(tester, (probe) => probe);

      showStudioSnack(context, 'Saved');
      await tester.pump();

      expect(marginOf(tester).bottom, StudioSpace.l);
    });

    testWidgets('StudioDock paints at the height it advertises', (
      tester,
    ) async {
      // `barHeightOf` is hand-derived from the tokens the dock lays itself out
      // with, and the toast offset is computed from it — so if the padding is
      // ever retuned without the sum, this is what catches it.
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: StudioAppTheme.dark(),
          home: Scaffold(
            body: Column(
              children: [
                Builder(
                  builder: (c) {
                    context = c;
                    return const Spacer();
                  },
                ),
                StudioDock(
                  children: [
                    Expanded(
                      child: StudioButton(label: 'Go', onPressed: () {}),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSize(find.byType(StudioDock)).height,
        StudioDock.barHeightOf(context),
      );
    });

    testWidgets('and so does the two-tier dock a phone uses', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: StudioAppTheme.dark(),
          home: Scaffold(
            body: Column(
              children: [
                Builder(
                  builder: (c) {
                    context = c;
                    return const Spacer();
                  },
                ),
                StudioDock(
                  lead: StudioButton(
                    label: 'New project',
                    variant: StudioButtonVariant.primary,
                    height: StudioSizes.buttonTall,
                    fullWidth: true,
                    onPressed: () {},
                  ),
                  children: [
                    Expanded(
                      child: StudioButton(label: 'Import', onPressed: () {}),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSize(find.byType(StudioDock)).height,
        StudioDock.barHeightOf(
          context,
          rows: [StudioSizes.buttonTall, StudioButton.heightFor(context)],
        ),
      );
    });
  });

  test('geometry tokens match the design spec', () {
    expect(StudioRadius.xs, 4);
    expect(StudioRadius.sm, 6);
    expect(StudioRadius.md, 8);
    expect(StudioRadius.lg, 12);
    expect(StudioSizes.toolbar, 48);
    expect(StudioSizes.toolButton, 32);
    expect(StudioSizes.buttonCompact, 30);
    expect(StudioSizes.button, 36);
    expect(StudioSizes.input, 34);
    expect(StudioSizes.listRow, 44);
    expect(StudioSizes.tabStrip, 64);
  });

  test('no two semantic icon members are accidentally unset', () {
    // Guards against a member being left as a placeholder default.
    for (final icon in _allIcons) {
      expect(icon.fontFamily, isNotNull);
    }
  });
}

void _noop(int _) {}

/// Every member of [StudioIcons], so the render test proves each glyph resolves.
const List<StudioIconData> _allIcons = <StudioIconData>[
  StudioIcons.ai,
  StudioIcons.listView,
  StudioIcons.storePreview,
  StudioIcons.watch,
  StudioIcons.tv,
  StudioIcons.headset,
  StudioIcons.back,
  StudioIcons.forward,
  StudioIcons.close,
  StudioIcons.check,
  StudioIcons.more,
  StudioIcons.moreVertical,
  StudioIcons.chevronRight,
  StudioIcons.chevronLeft,
  StudioIcons.expand,
  StudioIcons.collapse,
  StudioIcons.add,
  StudioIcons.remove,
  StudioIcons.addCircle,
  StudioIcons.delete,
  StudioIcons.edit,
  StudioIcons.duplicate,
  StudioIcons.applyToAll,
  StudioIcons.moveLeft,
  StudioIcons.moveRight,
  StudioIcons.reset,
  StudioIcons.undo,
  StudioIcons.redo,
  StudioIcons.preview,
  StudioIcons.previewOff,
  StudioIcons.export,
  StudioIcons.save,
  StudioIcons.share,
  StudioIcons.shareTo,
  StudioIcons.import,
  StudioIcons.upload,
  StudioIcons.openExternal,
  StudioIcons.settings,
  StudioIcons.search,
  StudioIcons.info,
  StudioIcons.privacy,
  StudioIcons.terms,
  StudioIcons.licenses,
  StudioIcons.memory,
  StudioIcons.quality,
  StudioIcons.code,
  StudioIcons.adjust,
  StudioIcons.themeLight,
  StudioIcons.themeDark,
  StudioIcons.themeSystem,
  StudioIcons.project,
  StudioIcons.projects,
  StudioIcons.screens,
  StudioIcons.screenshot,
  StudioIcons.addScreenshot,
  StudioIcons.addImage,
  StudioIcons.addPhoto,
  StudioIcons.image,
  StudioIcons.images,
  StudioIcons.layers,
  StudioIcons.device,
  StudioIcons.devices,
  StudioIcons.deviceIos,
  StudioIcons.deviceAndroid,
  StudioIcons.phone,
  StudioIcons.tablet,
  StudioIcons.frame,
  StudioIcons.platformApple,
  StudioIcons.platformAndroid,
  StudioIcons.platformPlayStore,
  StudioIcons.background,
  StudioIcons.caption,
  StudioIcons.subcaption,
  StudioIcons.text,
  StudioIcons.layout,
  StudioIcons.grid,
  StudioIcons.border,
  StudioIcons.align,
  StudioIcons.alignLeft,
  StudioIcons.alignCenter,
  StudioIcons.alignRight,
  StudioIcons.alignTop,
  StudioIcons.alignBottom,
  StudioIcons.transform,
  StudioIcons.move,
  StudioIcons.rotateLeft,
  StudioIcons.rotateRight,
  StudioIcons.scale,
  StudioIcons.aspectRatio,
  StudioIcons.cornerRadius,
  StudioIcons.crop,
  StudioIcons.cropPortrait,
  StudioIcons.cropLandscape,
  StudioIcons.palette,
  StudioIcons.solidFill,
  StudioIcons.gradientFill,
  StudioIcons.colorPicker,
  StudioIcons.opacity,
  StudioIcons.shadow,
  StudioIcons.blur,
  StudioIcons.font,
  StudioIcons.fontSize,
  StudioIcons.bold,
  StudioIcons.textAlignLeft,
  StudioIcons.textAlignCenter,
  StudioIcons.textAlignRight,
  StudioIcons.lineHeight,
  StudioIcons.letterSpacing,
  StudioIcons.dragHandle,
  StudioIcons.dragHandleVertical,
  StudioIcons.empty,
  StudioIcons.warning,
  StudioIcons.success,
  StudioIcons.error,
];
