import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/domain/engine/svg_path.dart';

/// The unit square, as this app writes one: absolute commands, one subpath.
const _square = 'M0 0 L1 0 L1 1 L0 1 Z';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseUnitPath', () {
    test('reads an outline back into the unit box', () {
      final path = parseUnitPath(_square);
      expect(path, isNotNull);
      final bounds = path!.getBounds();
      expect(bounds.left, closeTo(0, 0.0001));
      expect(bounds.top, closeTo(0, 0.0001));
      expect(bounds.right, closeTo(1, 0.0001));
      expect(bounds.bottom, closeTo(1, 0.0001));
    });

    test('reads the cubics the importer emits as curves', () {
      final path = parseUnitPath('M0 0 C0 1 1 1 1 0 Z');
      expect(path, isNotNull);
      // Tested by where the ink is rather than by the bounds, because
      // `Path.getBounds` reports the conservative control hull and so cannot
      // tell a curve from the polygon through its control points.
      expect(
        path!.contains(const Offset(0.5, 0.7)),
        isTrue,
        reason: 'the arch peaks at (0.5, 0.75)',
      );
      expect(
        path.contains(const Offset(0.05, 0.9)),
        isFalse,
        reason:
            'a cubic flattened onto its control points would fill '
            'the corner the curve sweeps past',
      );
    });

    test('defaults to the nonzero fill rule', () {
      expect(parseUnitPath(_square)!.fillType, PathFillType.nonZero);
    });

    test(
      'takes the even-odd rule when asked, so a counter reads as a hole',
      () {
        final path = parseUnitPath(_square, evenOdd: true);
        expect(path!.fillType, PathFillType.evenOdd);
      },
    );

    // Every one of these runs inside `build`, on a widget that also paints the
    // export raster. A null is a shape that paints as nothing and can be seen
    // and deleted; a throw is an export that silently produced nothing.
    test('returns null rather than throwing on a string it cannot read', () {
      for (final bad in [
        'not a path',
        'M0 0 L',
        'Q0 0 1 1',
        'M0 0 Lnope 3',
        '<svg/>',
        '@@@',
      ]) {
        expect(
          parseUnitPath(bad),
          isNull,
          reason: '"$bad" should read as no path at all',
        );
      }
    });

    test('returns null for the empty outline a shape starts with', () {
      expect(parseUnitPath(''), isNull);
      expect(parseUnitPath('   '), isNull);
    });

    test('returns null for a command run that draws nothing', () {
      expect(
        parseUnitPath('M0.5 0.5'),
        isNull,
        reason: 'a lone move puts the pen down and draws no ink',
      );
    });

    test('reads several subpaths as one path, which is what a hole needs', () {
      final path = parseUnitPath(
        'M0 0 L1 0 L1 1 L0 1 Z M0.25 0.25 L0.75 0.25 L0.75 0.75 L0.25 0.75 Z',
        evenOdd: true,
      );
      expect(path, isNotNull);
      expect(path!.contains(const Offset(0.1, 0.1)), isTrue);
      expect(
        path.contains(const Offset(0.5, 0.5)),
        isFalse,
        reason: 'the inner subpath is a hole under the even-odd rule',
      );
    });
  });
}
