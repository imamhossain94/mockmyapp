import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/domain/engine/palette_roll.dart';

double contrast(Color c, Color d) {
  final a = c.computeLuminance(), b = d.computeLuminance();
  return ((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05);
}

void main() {
  group('rollPalette', () {
    test('returns the asked-for number of stops, clamped to 2..4', () {
      for (var n = 1; n <= 6; n++) {
        expect(rollPalette(count: n, seed: 1), hasLength(n.clamp(2, 4)));
      }
    });

    test('is deterministic in its seed', () {
      // The whole reason a seed exists: a stored roll has to re-render as the
      // same picture, exactly as PatternBackground.seed guarantees for layout.
      for (var s = 0; s < 20; s++) {
        expect(rollPalette(count: 4, seed: s), rollPalette(count: 4, seed: s));
      }
    });

    test('different seeds give different palettes', () {
      final seen = {
        for (var s = 0; s < 40; s++) rollPalette(count: 3, seed: s).toString(),
      };
      expect(seen.length, greaterThan(30), reason: 'rolls should vary');
    });

    test('every harmony produces a full palette', () {
      for (final h in PaletteHarmony.values) {
        final p = rollPalette(count: 4, seed: 5, harmony: h);
        expect(p, hasLength(4), reason: '$h');
        expect(
          p.toSet().length,
          greaterThan(1),
          reason: '$h is not one colour',
        );
      }
    });

    test('the ground follows the dark flag', () {
      for (var s = 0; s < 15; s++) {
        expect(
          rollPalette(count: 2, seed: s, dark: true).first.computeLuminance(),
          lessThan(0.25),
          reason: 'seed $s',
        );
        expect(
          rollPalette(count: 2, seed: s, dark: false).first.computeLuminance(),
          greaterThan(0.6),
          reason: 'seed $s',
        );
      }
    });
  });

  group('rollReadablePalette', () {
    test('the motif always separates from its base', () {
      // A pattern you cannot see is the one failure mode that makes the whole
      // button useless, and it has to hold for every seed, not most of them.
      for (var s = 0; s < 200; s++) {
        final p = rollReadablePalette(count: 3, seed: s);
        expect(
          contrast(p[0], p[1]),
          greaterThanOrEqualTo(1.9),
          reason: 'seed $s produced an invisible motif',
        );
      }
    });

    test('is deterministic too', () {
      expect(
        rollReadablePalette(count: 4, seed: 42),
        rollReadablePalette(count: 4, seed: 42),
      );
    });
  });
}
