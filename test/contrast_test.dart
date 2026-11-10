// WCAG contrast, computed from the token values themselves.
//
// `accessibility_test.dart` asserts contrast on rendered widgets, which only
// covers the pairs the component gallery happens to put on screen. This file
// covers the palette: every text role against every surface it can sit on, in
// both themes, so a retuned hex that breaks a pair nobody rendered still fails
// a test. The ratios are the WCAG 2.x formula (`StudioColors.contrastRatio`).
//
// AA asks 4.5:1 for normal text and 3:1 for large text and glyphs
// (WCAG 2.2, 1.4.3 and 1.4.11).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/app/theme/studio_tokens.dart';
import 'package:mockmyapp/app/theme/studio_typography.dart';

const double _aa = 4.5;

/// Every opaque surface text is laid on.
Map<String, Color> _surfaces(StudioColors c) => {
  'canvas': c.canvas,
  'panel': c.panel,
  'panelAlt': c.panelAlt,
  'well': c.well,
  'overlay': c.overlay,
};

/// The roles that carry words a person has to read.
Map<String, Color> _textRoles(StudioColors c) => {
  'textPrimary': c.textPrimary,
  'textSecondary': c.textSecondary,
  'accentText': c.accentText,
  'dangerText': c.dangerText,
  'successText': c.successText,
  'warningText': c.warningText,
};

double _ratio(Color a, Color b) => StudioColors.contrastRatio(a, b);

void main() {
  test('the ratio is the WCAG formula', () {
    expect(
      _ratio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21, 0.001),
    );
    expect(_ratio(const Color(0xFF777777), const Color(0xFF777777)), 1);
    // A published reference pair: #767676 on white is the classic 4.54.
    expect(
      _ratio(const Color(0xFF767676), const Color(0xFFFFFFFF)),
      closeTo(4.54, 0.01),
    );
  });

  for (final (name, c) in [
    ('dark', StudioColors.dark),
    ('light', StudioColors.light),
  ]) {
    group('[$name]', () {
      test('every text role clears AA on every surface', () {
        final failures = <String>[];
        for (final MapEntry(key: role, value: fg) in _textRoles(c).entries) {
          for (final MapEntry(key: surface, value: bg) in _surfaces(
            c,
          ).entries) {
            final r = _ratio(fg, bg);
            if (r < _aa) {
              failures.add('$role on $surface: ${r.toStringAsFixed(2)}');
            }
          }
        }
        expect(failures, isEmpty);
      });

      test('the faintest grey stays legible and stays fainter', () {
        // Disabled text and placeholders: exempt from AA as disabled text,
        // but a placeholder still has to be read, so it clears 4:1 everywhere
        // — and it must stay below the secondary grey, or the two roles stop
        // meaning different things.
        for (final MapEntry(key: surface, value: bg) in _surfaces(c).entries) {
          final tertiary = _ratio(c.textTertiary, bg);
          expect(tertiary, greaterThanOrEqualTo(4.0), reason: surface);
          expect(
            tertiary,
            lessThan(_ratio(c.textSecondary, bg)),
            reason: surface,
          );
        }
      });

      test('words on the accent and danger fills clear AA', () {
        expect(_ratio(c.onAccent, c.accent), greaterThanOrEqualTo(_aa));
        expect(_ratio(c.onAccent, c.accentHover), greaterThanOrEqualTo(_aa));
        expect(_ratio(c.onAccent, c.danger), greaterThanOrEqualTo(_aa));
      });

      test('words on the accent wash clear AA wherever a wash lands', () {
        for (final surface in [c.canvas, c.panel, c.panelAlt]) {
          final wash = Color.alphaBlend(c.accentSubtle, surface);
          expect(
            _ratio(c.onAccentSubtle, wash),
            greaterThanOrEqualTo(_aa),
            reason: '$surface',
          );
        }
      });

      test('a neutral control has an edge on every surface', () {
        // The collision this token fixes: a control filled like its panel.
        expect(c.control, isNot(c.panelAlt));
        for (final MapEntry(key: surface, value: bg) in _surfaces(c).entries) {
          final fill = c.controlOn(bg);
          expect(
            _ratio(fill, bg),
            greaterThanOrEqualTo(1.08),
            reason: '$surface gets ${fill.toARGB32().toRadixString(16)}',
          );
        }
        // And the plain token holds on the surfaces controls usually sit on.
        expect(_ratio(c.control, c.panel), greaterThanOrEqualTo(1.08));
        expect(_ratio(c.control, c.panelAlt), greaterThanOrEqualTo(1.08));
      });

      test('a panel inside a dialog is not the dialog colour', () {
        expect(c.overlay, isNot(c.panelAlt));
        expect(_ratio(c.panelAlt, c.overlay), greaterThanOrEqualTo(1.08));
      });

      testWidgets('section eyebrows are coloured to clear AA', (tester) async {
        // Resolved inside a widget test: StudioText builds Inter styles, and
        // the test config is what keeps their font loading quiet.
        await tester.pumpWidget(
          MaterialApp(
            theme: name == 'dark'
                ? StudioAppTheme.dark()
                : StudioAppTheme.light(),
            home: const SizedBox(),
          ),
        );
        final eyebrow = StudioText.sectionLabelFor(c).color!;
        for (final MapEntry(key: surface, value: bg) in _surfaces(c).entries) {
          expect(
            _ratio(eyebrow, bg),
            greaterThanOrEqualTo(_aa),
            reason: surface,
          );
        }
      });
    });
  }
}
