import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';

/// A slider on its own, wide enough that the caption stays beside the track.
///
/// [touch] picks which manual-entry route is under test, and is declared here
/// rather than left to the ambient platform: `flutter test` reports Android, so
/// a test that did not say would silently exercise the sheet.
Widget _host({
  required double value,
  required ValueChanged<double> onChanged,
  String Function(double)? display,
  double min = 0,
  double max = 1,
  double? step,
  bool enabled = true,
  bool touch = false,
  ValueChanged<double>? onChangeEnd,
}) => MaterialApp(
  theme: StudioAppTheme.dark(),
  home: StudioLayoutScope(
    layout: touch
        ? const StudioLayout(
            form: StudioFormFactor.phonePortrait,
            size: Size(390, 844),
            isTouchPrimary: true,
          )
        : const StudioLayout(
            form: StudioFormFactor.desktop,
            size: Size(1440, 900),
            isTouchPrimary: false,
          ),
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: 420,
          child: StudioSlider(
            label: 'Strength',
            value: value,
            min: min,
            max: max,
            step: step,
            display: display,
            enabled: enabled,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ),
    ),
  ),
);

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.byType(StudioNumericWell));
  await tester.pumpAndSettle();
}

void main() {
  group('StudioDisplayScale', () {
    // The formatters below are lifted verbatim from the panels, because the
    // whole risk in inferring the scale is that it works on invented examples
    // and not on the ones actually in the app.

    test('recovers a percentage formatter', () {
      final scale = StudioDisplayScale.fit(
        (v) => '${(v * 100).round()}%',
        0,
        1,
      );
      expect(scale.gain, closeTo(100, 1e-6));
      expect(scale.offset, closeTo(0, 1e-6));
      expect(scale.decimals, 0);
      expect(scale.toValue(35), closeTo(0.35, 1e-9));
      expect(scale.toDisplay(0.28), closeTo(28, 1e-9));
    });

    test(
      'recovers the blur formatter, whose units are nothing like its value',
      () {
        // Shows 0–100 for a stored 0–0.08 fraction of canvas width.
        final scale = StudioDisplayScale.fit(
          (v) => '${(v / 0.08 * 100).round()}',
          0,
          0.08,
        );
        expect(scale.toValue(32), closeTo(0.0256, 1e-6));
      },
    );

    test('recovers a per-mille formatter with a decimal place', () {
      final scale = StudioDisplayScale.fit(
        (v) => (v * 1000).toStringAsFixed(1),
        0,
        0.1,
      );
      expect(scale.gain, closeTo(1000, 1e-6));
      expect(scale.decimals, 1);
    });

    test('recovers a degrees formatter with a unit suffix', () {
      final scale = StudioDisplayScale.fit((v) => '${v.round()}°', 0, 360);
      expect(scale.gain, closeTo(1, 1e-6));
      expect(scale.toValue(217), closeTo(217, 0.5));
    });

    test('survives a formatter with a word at one end', () {
      // `Off` yields no number, so that sample is skipped and the numeric part
      // still fits. Dragging can still reach the sentinel.
      final scale = StudioDisplayScale.fit(
        (v) => v < 0.5 ? 'Off' : '${v.round()}',
        0,
        60,
      );
      expect(scale.gain, closeTo(1, 1e-6));
      expect(scale.toValue(24), closeTo(24, 0.5));
    });

    test('falls back to the raw value for a non-affine formatter', () {
      // An aspect readout: `1:2.00`. The first number is the constant `1`, so
      // no honest line fits — the field must edit the raw value rather than
      // convert it wrongly.
      final scale = StudioDisplayScale.fit(
        (v) => '1:${(1 / v).toStringAsFixed(2)}',
        0.4,
        2.5,
      );
      expect(scale.gain, 1);
      expect(scale.offset, 0);
    });

    test('falls back when the formatter ignores the value entirely', () {
      final scale = StudioDisplayScale.fit((v) => '42%', 0, 1);
      expect(scale.gain, 1);
    });

    test('edits the raw value when there is no formatter', () {
      final scale = StudioDisplayScale.fit(null, 0, 1);
      expect(scale.gain, 1);
      expect(scale.toValue(0.5), 0.5);
    });

    test('round-trips every formatter shape the app actually uses', () {
      // Swept from the panels — `grep "display: (v)"`. The unit test above
      // covers the interesting cases one at a time; this is the safety net
      // that says none of the others quietly converts wrong, because a wrong
      // conversion here is invisible until someone types 35 and gets 34.
      const cases = <(String, double, double)>[
        ('percent', 0, 1),
        ('permille0', 0, 0.1),
        ('permille1', 0, 0.1),
        ('round', 0, 360),
        ('degrees', 0, 360),
        ('blur', 0, 0.08),
        ('offPermille1', 0, 0.02),
        ('nonePermille0', 0, 0.05),
        ('offRound', 0, 60),
        ('flatPercent', 0, 1),
      ];

      String format(String kind, double v) => switch (kind) {
        'percent' => '${(v * 100).round()}%',
        'permille0' => (v * 1000).toStringAsFixed(0),
        'permille1' => (v * 1000).toStringAsFixed(1),
        'round' => '${v.round()}',
        'degrees' => '${v.round()}°',
        'blur' => '${(v / 0.08 * 100).round()}',
        'offPermille1' => v < 0.0005 ? 'Off' : (v * 1000).toStringAsFixed(1),
        'nonePermille0' => v < 0.002 ? 'None' : (v * 1000).toStringAsFixed(0),
        'offRound' => v < 0.5 ? 'Off' : '${v.round()}',
        'flatPercent' => v < 0.02 ? 'Flat' : '${(v * 100).round()}%',
        _ => throw ArgumentError(kind),
      };

      for (final (kind, min, max) in cases) {
        final scale = StudioDisplayScale.fit((v) => format(kind, v), min, max);

        // The round trip is the whole assertion. Checking the gain instead
        // would prove nothing: several of these are honestly 1:1, so a gain of
        // one is both the correct answer and the fallback, and the two are
        // indistinguishable from outside.
        //
        // What the user does: read a number off the slider, retype it, expect
        // the same value back.
        for (final t in const [0.2, 0.5, 0.85]) {
          final value = min + (max - min) * t;
          final shown = double.parse(
            RegExp(r'-?\d+(?:\.\d+)?').firstMatch(format(kind, value))![0]!,
          );
          expect(
            scale.toValue(shown),
            closeTo(value, (max - min) * 0.011),
            reason: '$kind did not round-trip at $value',
          );
        }
      }
    });
  });

  group('manual entry — pointer', () {
    // The desktop route: a popover anchored to the readout. No software
    // keyboard is coming, so nothing has to move out of its way.
    testWidgets('tapping the readout opens a field seeded with the value', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          value: 0.28,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (_) {},
        ),
      );

      expect(find.byType(TextField), findsNothing);
      await _openEditor(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      // Seeded in the units on screen — 28, not 0.28.
      expect(field.controller!.text, '28');
      // And it says what it will accept.
      expect(find.text('0 – 100'), findsOneWidget);
    });

    testWidgets('a typed value commits in display units', (tester) async {
      var latest = 0.28;
      var committed = 0.0;
      await tester.pumpWidget(
        _host(
          value: 0.28,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (v) => latest = v,
          onChangeEnd: (v) => committed = v,
        ),
      );

      await _openEditor(tester);
      await tester.enterText(find.byType(TextField), '73');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(latest, closeTo(0.73, 1e-9));
      // Undo is committed once, not per keystroke.
      expect(committed, closeTo(0.73, 1e-9));
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a typed value is held to the range', (tester) async {
      var latest = 0.5;
      await tester.pumpWidget(
        _host(
          value: 0.5,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (v) => latest = v,
        ),
      );

      await _openEditor(tester);
      await tester.enterText(find.byType(TextField), '480');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(latest, 1.0);
    });

    testWidgets('escape discards without writing anything', (tester) async {
      var changes = 0;
      await tester.pumpWidget(
        _host(
          value: 0.28,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (_) => changes++,
        ),
      );

      await _openEditor(tester);
      await tester.enterText(find.byType(TextField), '90');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      // The point of not committing on keystroke: an abandoned edit leaves no
      // undo entry behind.
      expect(changes, isZero);
    });

    testWidgets('tapping away commits what is in the box', (tester) async {
      var latest = 0.28;
      await tester.pumpWidget(
        _host(
          value: 0.28,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (v) => latest = v,
        ),
      );

      await _openEditor(tester);
      await tester.enterText(find.byType(TextField), '61');
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(latest, closeTo(0.61, 1e-9));
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('the arrow keys step the value', (tester) async {
      var latest = 0.5;
      await tester.pumpWidget(
        _host(
          value: 0.5,
          step: 0.1,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (v) => latest = v,
        ),
      );

      await _openEditor(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(latest, closeTo(0.6, 1e-9));
    });

    testWidgets('a disabled slider does not open the field', (tester) async {
      await tester.pumpWidget(
        _host(
          value: 0.28,
          enabled: false,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (_) {},
        ),
      );

      await tester.tap(find.byType(StudioNumericWell), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('manual entry — touch', () {
    // The phone route. The tool sheet lives at the bottom of the screen, which
    // is exactly where the keyboard opens, so the input moves into a sheet of
    // its own — the same pattern caption editing uses.

    testWidgets('tapping the readout opens a sheet, not a popover', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          value: 0.28,
          touch: true,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (_) {},
        ),
      );

      await _openEditor(tester);

      // Titled with the slider's own caption, and holding exactly four things:
      // the field, the two arrows, and the confirm.
      expect(find.text('Strength'), findsWidgets);
      expect(find.text('Apply'), findsOneWidget);
      expect(find.byTooltip('Increase'), findsNWidgets(2));
      expect(find.byTooltip('Decrease'), findsNWidgets(2));
      // The sheet does not carry a second track: only the slider behind it.
      expect(find.byType(Slider), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '28');
    });

    testWidgets('typing previews live and commits once on close', (
      tester,
    ) async {
      final live = <double>[];
      final committed = <double>[];
      await tester.pumpWidget(
        _host(
          value: 0.28,
          touch: true,
          display: (v) => '${(v * 100).round()}%',
          onChanged: live.add,
          onChangeEnd: committed.add,
        ),
      );

      await _openEditor(tester);
      await tester.enterText(find.byType(TextField), '73');
      await tester.pumpAndSettle();

      // The slider behind the sheet has already moved...
      expect(live.last, closeTo(0.73, 1e-9));
      // ...but nothing has been committed to undo yet.
      expect(committed, isEmpty);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // One entry for the whole edit, exactly like one drag.
      expect(committed, hasLength(1));
      expect(committed.single, closeTo(0.73, 1e-9));
    });

    testWidgets('the stepper steps the value', (tester) async {
      final live = <double>[];
      await tester.pumpWidget(
        _host(
          value: 0.5,
          touch: true,
          step: 0.1,
          display: (v) => '${(v * 100).round()}%',
          onChanged: live.add,
        ),
      );

      await _openEditor(tester);
      // `.last`: the slider row behind the sheet has its own pair with the
      // same tooltips, and the sheet's are the ones on top.
      await tester.tap(find.byTooltip('Increase').last);
      await tester.pumpAndSettle();

      expect(live.last, closeTo(0.6, 1e-9));
      // The field follows the value rather than the arithmetic.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '60',
      );
    });

    testWidgets('a value typed past the bound is clamped', (tester) async {
      final live = <double>[];
      await tester.pumpWidget(
        _host(
          value: 0.5,
          touch: true,
          display: (v) => '${(v * 100).round()}%',
          onChanged: live.add,
        ),
      );

      await _openEditor(tester);
      await tester.enterText(find.byType(TextField), '480');
      await tester.pumpAndSettle();
      // Clamped rather than refused: the bounds line says what the range is,
      // and typing past it lands on the end of it.
      expect(live.last, 1.0);
    });

    testWidgets('closing without typing commits nothing', (tester) async {
      final live = <double>[];
      final committed = <double>[];
      await tester.pumpWidget(
        _host(
          value: 0.28,
          touch: true,
          display: (v) => '${(v * 100).round()}%',
          onChanged: live.add,
          onChangeEnd: committed.add,
        ),
      );

      await _openEditor(tester);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(live, isEmpty);
      expect(committed, isEmpty);
    });
  });

  group('manual entry — shared', () {
    testWidgets('a bare readout stays read-only', (tester) async {
      // The wells that are not sliders — hex codes, canvas size — must not
      // sprout an editor just because the widget can now have one.
      await tester.pumpWidget(
        MaterialApp(
          theme: StudioAppTheme.dark(),
          home: const Scaffold(
            body: Center(child: StudioNumericWell(text: '1290×2796')),
          ),
        ),
      );

      await tester.tap(find.byType(StudioNumericWell), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    });
  });
}
