import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/data/services/svg_import.dart';
import 'package:mockmyapp/domain/engine/svg_path.dart';

/// Wraps [body] in the smallest SVG the parser will accept.
String svg(String body, {String viewBox = '0 0 10 10'}) =>
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="$viewBox">$body</svg>';

/// The outline of [result], as the shape's own box would see it.
Rect boundsOf(SvgImportResult result) {
  expect(result, isA<SvgImportSuccess>());
  final success = result as SvgImportSuccess;
  final path = parseUnitPath(success.pathData, evenOdd: success.evenOdd);
  expect(
    path,
    isNotNull,
    reason:
        'the importer emitted a string it cannot '
        'read back: ${success.pathData}',
  );
  return path!.getBounds();
}

/// Whether [rect] is the unit box, to a tolerance that ignores the five
/// decimals coordinates are written at.
Matcher get isUnitBox => predicate<Rect>(
  (r) =>
      (r.left).abs() < 0.001 &&
      (r.top).abs() < 0.001 &&
      (r.right - 1).abs() < 0.001 &&
      (r.bottom - 1).abs() < 0.001,
  'the unit box',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reading an outline', () {
    test('a plain path arrives normalised into the unit box', () {
      final result = SvgImport.read(
        svg('<path d="M0 0 L10 0 L10 10 Z" fill="#000"/>'),
      );
      expect(boundsOf(result), isUnitBox);
    });

    // The test that pins the whole choice of parser. A `<rect>` carries no `d`
    // attribute at all, so a reader that scrapes `d=` with a regex turns this
    // file into an empty shape and reports success — and most icon sets are
    // built out of rects and circles.
    test('a file whose only content is a <rect> imports', () {
      final result = SvgImport.read(
        svg(
          '<rect x="2" y="1" width="16" height="8" fill="#000"/>',
          viewBox: '0 0 20 10',
        ),
      );
      expect(boundsOf(result), isUnitBox);
      expect((result as SvgImportSuccess).aspect, closeTo(2, 0.001));
    });

    test('a <circle> imports as a curved outline, not as nothing', () {
      final result = SvgImport.read(
        svg('<circle cx="5" cy="5" r="4" fill="#000"/>'),
      );
      final success = result as SvgImportSuccess;
      expect(success.pathData, contains('C'));
      expect(success.aspect, closeTo(1, 0.001));
    });

    // The other half of the same choice. Figma and Illustrator both emit
    // `<g transform="translate(…)">` as a matter of course, and an outline read
    // without applying it lands somewhere else entirely — silently, because the
    // path data itself parses perfectly well.
    test('a path under a translated group lands where an untranslated one '
        'does', () {
      const d = 'M0 0 L10 0 L10 10 Z';
      final plain = SvgImport.read(
        svg('<path d="$d" fill="#000"/>', viewBox: '0 0 100 100'),
      );
      final grouped = SvgImport.read(
        svg(
          '<g transform="translate(50,50)"><path d="$d" fill="#000"/></g>',
          viewBox: '0 0 100 100',
        ),
      );
      expect(
        (grouped as SvgImportSuccess).pathData,
        (plain as SvgImportSuccess).pathData,
        reason:
            'both outlines are normalised against their own ink, so a '
            'group translation must fall out entirely',
      );
    });

    // `instructions.paths` is the pool every command indexes into, clips
    // included, and this is the file shape that makes taking the pool wrong: a
    // Figma export wraps its artboard in a full-bleed clip rect. Including it
    // would add a rectangle to the outline and normalise the ink against the
    // artboard instead of against itself.
    test('an artboard clip rect is not mistaken for part of the outline', () {
      final result = SvgImport.read(
        svg(
          '<g clip-path="url(#c0)">'
          '<path d="M4 4 L12 4 L12 12 Z" fill="#000"/>'
          '</g>'
          '<defs><clipPath id="c0">'
          '<rect width="24" height="24" fill="white"/>'
          '</clipPath></defs>',
          viewBox: '0 0 24 24',
        ),
      );
      final success = result as SvgImportSuccess;
      expect(
        'M'.allMatches(success.pathData).length,
        1,
        reason: 'the clip rect would be a second subpath',
      );
      expect(boundsOf(result), isUnitBox);
    });

    test('a small mark in a large viewBox still fills the unit box', () {
      // Normalised against the ink and not against the artboard: an icon drawn
      // with padding would otherwise arrive as a speck floating in the middle
      // of its own drag handles.
      final result = SvgImport.read(
        svg(
          '<path d="M40 45 L60 45 L60 55 L40 55 Z" fill="#000"/>',
          viewBox: '0 0 100 100',
        ),
      );
      expect(boundsOf(result), isUnitBox);
      expect((result as SvgImportSuccess).aspect, closeTo(2, 0.001));
    });

    test('a 200 by 100 outline reports its own proportions', () {
      final result = SvgImport.read(
        svg(
          '<rect width="200" height="100" fill="#000"/>',
          viewBox: '0 0 200 100',
        ),
      );
      expect((result as SvgImportSuccess).aspect, closeTo(2, 0.001));
    });

    test('a stroked path with no fill is still an outline', () {
      final result = SvgImport.read(
        svg('<path d="M0 0 L10 10" fill="none" stroke="#000"/>'),
      );
      expect(result, isA<SvgImportSuccess>());
    });

    test('the preamble a real exporter writes does not get in the way', () {
      // A byte-order mark, an XML declaration, a generator comment, a DOCTYPE
      // and CRLF line endings — between them, what Illustrator and Inkscape
      // actually put at the top of a file.
      final source = utf8.decode([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(
          '<?xml version="1.0" encoding="UTF-8"?>\r\n'
          '<!-- Generator: Adobe Illustrator -->\r\n'
          '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" '
          '"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">\r\n'
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">\r\n'
          '<path d="M0 0 L10 0 L10 10 Z" fill="#000"/>\r\n'
          '</svg>',
        ),
      ]);
      expect(boundsOf(SvgImport.read(source)), isUnitBox);
    });

    test('a shape reached through <use> is resolved rather than skipped', () {
      // `<use>` is how an exporter avoids repeating a path it draws twice, and
      // the referenced path lives in `<defs>` where nothing draws it directly.
      final result = SvgImport.read(
        svg(
          '<defs><path id="p" d="M0 0 L10 0 L10 10 Z"/></defs>'
          '<use href="#p" fill="#000"/>'
          '<use href="#p" x="10" fill="#000"/>',
          viewBox: '0 0 20 10',
        ),
      );
      final success = result as SvgImportSuccess;
      expect(
        'M'.allMatches(success.pathData).length,
        2,
        reason: 'both placements are drawn, at their own positions',
      );
      expect(success.aspect, closeTo(2, 0.001));
      expect(boundsOf(result), isUnitBox);
    });

    test('several shapes come through as one outline in paint order', () {
      final result = SvgImport.read(
        svg(
          '<rect width="4" height="4" fill="#000"/>'
          '<rect x="6" y="6" width="4" height="4" fill="#000"/>',
        ),
      );
      final success = result as SvgImportSuccess;
      expect('M'.allMatches(success.pathData).length, 2);
      expect(boundsOf(result), isUnitBox);
    });
  });

  group('the fill rule', () {
    test('nonzero unless the file asks otherwise', () {
      final result = SvgImport.read(
        svg('<path d="M0 0 L10 0 L10 10 Z" fill="#000"/>'),
      );
      expect((result as SvgImportSuccess).evenOdd, isFalse);
    });

    test('even-odd carries through, which is what makes a counter a hole', () {
      final result = SvgImport.read(
        svg(
          '<path fill-rule="evenodd" fill="#000" '
          'd="M0 0 L10 0 L10 10 L0 10 Z M3 3 L7 3 L7 7 L3 7 Z"/>',
        ),
      );
      final success = result as SvgImportSuccess;
      expect(success.evenOdd, isTrue);

      final path = parseUnitPath(success.pathData, evenOdd: success.evenOdd)!;
      expect(path.contains(const Offset(0.1, 0.1)), isTrue);
      expect(
        path.contains(const Offset(0.5, 0.5)),
        isFalse,
        reason: 'the inner ring is a hole, not solid ink',
      );
    });
  });

  group('refusing a file', () {
    // Every one of these reaches the parser as a `StateError` thrown from
    // somewhere inside its tokeniser. None of them may reach the caller as one.
    test('malformed, empty and non-SVG input all fail with a message', () {
      for (final source in [
        '<svg><path d=',
        '',
        '   ',
        '<html><body>not a drawing</body></html>',
        'M0 0 L10 10',
      ]) {
        final result = SvgImport.read(source);
        expect(
          result,
          isA<SvgImportFailure>(),
          reason: 'should be refused: "$source"',
        );
        expect((result as SvgImportFailure).message, isNotEmpty);
      }
    });

    test('an SVG with nothing drawable in it says so', () {
      for (final body in ['', '<path d="M0 0 L10 10" fill="none"/>']) {
        expect(
          SvgImport.read(svg(body)),
          isA<SvgImportFailure>(),
          reason: 'should be refused: "$body"',
        );
      }
    });

    test('a flat outline is given a box it can be grabbed by', () {
      // A single horizontal segment has zero height. Refusing it outright would
      // be defensible; giving it a floor is what `_addDrawnShape` already does
      // for a perfectly straight freehand stroke.
      final result = SvgImport.read(
        svg('<path d="M0 5 L10 5" fill="none" stroke="#000"/>'),
      );
      final success = result as SvgImportSuccess;
      expect(success.aspect, lessThanOrEqualTo(20.001));
      expect(success.aspect, greaterThan(1));
    });

    test('artwork past the outline cap comes in as a picture instead', () {
      // The string lives in `project.json` and is rewritten on every edit to
      // the screen it sits on, so this is a cost the document would carry
      // forever rather than one paid once. A picture of it is one file.
      final d = StringBuffer('M100 100');
      for (var i = 0; i < 6000; i++) {
        final x = 100 + 90 * math.cos(i.toDouble());
        final y = 100 + 90 * math.sin(i.toDouble());
        d.write(' L${x.toStringAsFixed(3)} ${y.toStringAsFixed(3)}');
      }
      final result = SvgImport.read(
        svg('<path d="$d" fill="#000"/>', viewBox: '0 0 200 200'),
      );
      expect(result, isA<SvgImportPicture>());
      expect((result as SvgImportPicture).aspect, closeTo(1, 0.001));
    });

    test('an outline just under the cap still imports', () {
      final d = StringBuffer('M100 100');
      for (var i = 0; i < 500; i++) {
        final x = 100 + 90 * math.cos(i.toDouble());
        final y = 100 + 90 * math.sin(i.toDouble());
        d.write(' L${x.toStringAsFixed(3)} ${y.toStringAsFixed(3)}');
      }
      final result = SvgImport.read(
        svg('<path d="$d" fill="#000"/>', viewBox: '0 0 200 200'),
      );
      expect(result, isA<SvgImportSuccess>());
      expect(
        (result as SvgImportSuccess).pathData.length,
        lessThan(SvgImport.maxPathDataChars),
      );
    });
  });

  group('colour', () {
    test('artwork in one colour keeps it', () {
      final result = SvgImport.read(
        svg('<rect width="10" height="6" fill="#5B5FEF"/>'),
      );
      final success = result as SvgImportSuccess;
      expect(success.colour.toARGB32(), 0xFF5B5FEF);
      expect(success.stroke, isNull, reason: 'it is filled, not drawn');
    });

    test('a file that names no colour is drawn in black', () {
      final success =
          SvgImport.read(svg('<rect width="10" height="10"/>'))
              as SvgImportSuccess;
      expect(success.colour.toARGB32(), 0xFF000000);
    });

    test('line art comes in as a stroke, weighted against its own box', () {
      final success =
          SvgImport.read(
                svg(
                  '<circle cx="5" cy="5" r="4" fill="none" '
                  'stroke="#23C4A8" stroke-width="2"/>',
                ),
              )
              as SvgImportSuccess;
      expect(success.colour.toARGB32(), 0xFF23C4A8);
      // A 2-unit line on an outline 8 units across.
      expect(success.stroke, closeTo(2 / 8, 0.02));
    });

    test('two colours, a gradient or type come in as a picture', () {
      for (final body in [
        '<rect width="5" height="10" fill="#f00"/>'
            '<rect x="5" width="5" height="10" fill="#00f"/>',
        '<defs><linearGradient id="g"><stop offset="0" stop-color="#f00"/>'
            '<stop offset="1" stop-color="#00f"/></linearGradient></defs>'
            '<rect width="10" height="10" fill="url(#g)"/>',
        '<text x="1" y="5">MockMyApp</text>',
        // One colour, but a disc filled inside a ring drawn: filling the
        // ring as well would close it up.
        '<circle cx="5" cy="5" r="2" fill="#f00"/>'
            '<circle cx="5" cy="5" r="4" fill="none" stroke="#f00"/>',
      ]) {
        expect(
          SvgImport.read(svg(body)),
          isA<SvgImportPicture>(),
          reason: body,
        );
      }
    });
  });

  group('what is written', () {
    test('only the four commands the reader knows', () {
      final result = SvgImport.read(
        svg('<path d="M0 0 H10 V10 A5 5 0 0 1 0 5 Q2 2 0 0 Z" fill="#000"/>'),
      );
      final success = result as SvgImportSuccess;
      final verbs = RegExp(
        '[A-Za-z]',
      ).allMatches(success.pathData).map((m) => m[0]).toSet();
      expect(
        verbs,
        everyElement(isIn(const ['M', 'L', 'C', 'Z'])),
        reason:
            'arcs, quadratics and the shorthands are all reduced before '
            'they are written',
      );
      expect(parseUnitPath(success.pathData), isNotNull);
    });

    test('coordinates are trimmed rather than written at full precision', () {
      final result = SvgImport.read(
        svg('<path d="M0 0 L10 0 L10 10 Z" fill="#000"/>'),
      );
      expect(
        (result as SvgImportSuccess).pathData,
        'M0 0L1 0L1 1Z',
        reason: 'a whole coordinate should cost one character, not seven',
      );
    });
  });
}
