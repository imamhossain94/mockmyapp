import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/engine/pattern_painter.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

/// Rasterises a pattern at [size] and returns its raw RGBA bytes.
Future<ByteData> _render(PatternBackground spec, Size size) async {
  final recorder = ui.PictureRecorder();
  PatternPainter(spec).paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  return data!;
}

/// Colour at a normalised point, so two different resolutions can be compared.
Color _sample(ByteData data, Size size, double u, double v) {
  final x = (u * size.width).clamp(0, size.width - 1).toInt();
  final y = (v * size.height).clamp(0, size.height - 1).toInt();
  final offset = (y * size.width.toInt() + x) * 4;
  return Color.fromARGB(
    data.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

void _expectClose(Color a, Color b, {int tolerance = 14, String? reason}) {
  int channel(double x) => (x * 255).round();
  expect(
    (channel(a.r) - channel(b.r)).abs(),
    lessThanOrEqualTo(tolerance),
    reason: reason,
  );
  expect(
    (channel(a.g) - channel(b.g)).abs(),
    lessThanOrEqualTo(tolerance),
    reason: reason,
  );
  expect(
    (channel(a.b) - channel(b.b)).abs(),
    lessThanOrEqualTo(tolerance),
    reason: reason,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PatternPainter', () {
    test('every style paints without throwing, at any size', () async {
      for (final style in PatternStyle.values) {
        final spec = PatternBackground(
          style: style,
          colors: const [
            Color(0xFF102A43),
            Color(0xFF3B82F6),
            Color(0xFFF9FAFB),
          ],
          seed: 11,
        );
        for (final size in const [
          Size(8, 16),
          Size(120, 260),
          Size(600, 1300),
        ]) {
          final data = await _render(spec, size);
          expect(
            data.lengthInBytes,
            size.width.toInt() * size.height.toInt() * 4,
            reason: '$style at $size',
          );
        }
      }
    });

    test('is deterministic — same spec, identical pixels', () async {
      for (final style in PatternStyle.values) {
        final spec = PatternBackground(
          style: style,
          colors: const [
            Color(0xFF1E1B4B),
            Color(0xFF5B21B6),
            Color(0xFF2563EB),
          ],
          seed: 42,
        );
        const size = Size(80, 160);
        final first = await _render(spec, size);
        final second = await _render(spec, size);
        expect(
          first.buffer.asUint8List(),
          second.buffer.asUint8List(),
          reason: '$style is not reproducible',
        );
      }
    });

    test('a new seed is a new composition', () async {
      const size = Size(80, 160);
      const base = PatternBackground(
        style: PatternStyle.mesh,
        colors: [Color(0xFF1E1B4B), Color(0xFF5B21B6), Color(0xFF2563EB)],
        seed: 1,
      );
      final a = await _render(base, size);
      final b = await _render(base.copyWith(seed: 2), size);
      expect(a.buffer.asUint8List(), isNot(b.buffer.asUint8List()));
    });

    test('every style rearranges on a new seed, not just recolours', () async {
      // The bug this exists for: `beams` pinned its ghost arrows to two fixed
      // corners and let the seed nudge them by a few percent, so every beams
      // composition was the same picture. A row of presets in one style then
      // differed only in hue, which is not a row of presets.
      //
      // Rendered in one colourway on purpose — holding the palette fixed is
      // what isolates *layout* variation from the colours doing the work.
      // Regular lattices are exempt, and correctly so: a grid that reshuffled
      // on a new seed would not be a grid. Everything else is a scatter or a
      // lit composition, and for those a fixed layout is the bug.
      const tilings = <PatternStyle>{
        PatternStyle.dots,
        PatternStyle.grid,
        PatternStyle.stripes,
        PatternStyle.checkers,
        PatternStyle.diamonds,
        PatternStyle.triangles,
        PatternStyle.hexagons,
        PatternStyle.crosses,
        PatternStyle.zigzag,
        PatternStyle.scales,
        PatternStyle.crosshatch,
        PatternStyle.halftone,
        PatternStyle.plaid,
        PatternStyle.isometric,
        // The strata bands and the crest layers come off fixed harmonics so
        // the section stays legible; the seed still moves the phase, but not
        // enough to change every pixel at preview size.
      };

      const size = Size(72, 144);
      const colors = [
        Color(0xFF0A0E22),
        Color(0xFF2645D4),
        Color(0xFFFFD84D),
        Color(0xFFFFFFFF),
      ];
      for (final style in PatternStyle.values) {
        final a = await _render(
          PatternBackground(style: style, colors: colors, seed: 11),
          size,
        );
        final b = await _render(
          PatternBackground(style: style, colors: colors, seed: 12),
          size,
        );
        final fixed =
            a.buffer.asUint8List().toString() ==
            b.buffer.asUint8List().toString();
        expect(
          fixed,
          tilings.contains(style),
          reason: fixed
              ? '${style.name} paints the same picture whatever the seed'
              : '${style.name} varies now — take it out of `tilings`',
        );
      }
    });

    test('resolution independent — a thumbnail matches the export', () async {
      // Checked on the smooth styles: the textured ones put hard edges exactly
      // where point sampling is meaningless.
      for (final style in [
        PatternStyle.mesh,
        PatternStyle.blobs,
        PatternStyle.waves,
        PatternStyle.stripes,
      ]) {
        final spec = PatternBackground(
          style: style,
          colors: const [
            Color(0xFF0F172A),
            Color(0xFF0EA5E9),
            Color(0xFF22D3EE),
          ],
          seed: 5,
        );
        const small = Size(60, 130);
        const large = Size(480, 1040);
        final thumb = await _render(spec, small);
        final export = await _render(spec, large);

        for (final (u, v) in const [(0.25, 0.2), (0.5, 0.5), (0.75, 0.85)]) {
          _expectClose(
            _sample(thumb, small, u, v),
            _sample(export, large, u, v),
            reason: '$style drifted at ($u, $v)',
          );
        }
      }
    });

    test('repaints only when the spec actually changes', () {
      const spec = PatternBackground(
        style: PatternStyle.dots,
        colors: [Color(0xFF000000), Color(0xFFFFFFFF)],
        seed: 3,
      );
      expect(
        const PatternPainter(spec).shouldRepaint(const PatternPainter(spec)),
        isFalse,
      );
      expect(
        PatternPainter(
          spec.copyWith(seed: 4),
        ).shouldRepaint(const PatternPainter(spec)),
        isTrue,
      );
      expect(
        PatternPainter(
          spec.copyWith(colors: const [Color(0xFF123456)]),
        ).shouldRepaint(const PatternPainter(spec)),
        isTrue,
      );
    });
  });

  group('serialization', () {
    test('a pattern survives a round trip', () {
      const original = PatternBackground(
        style: PatternStyle.rays,
        colors: [Color(0xFF18181B), Color(0xFFF59E0B), Color(0xFFEF4444)],
        seed: 9,
        scale: 1.2,
        angle: 12,
        intensity: 0.65,
      );

      final restored = backgroundFromJson(backgroundToJson(original));
      expect(restored, isA<PatternBackground>());
      final pattern = restored as PatternBackground;
      expect(pattern.style, PatternStyle.rays);
      expect(pattern.colors, original.colors);
      expect(pattern.seed, 9);
      expect(pattern.scale, closeTo(1.2, 1e-9));
      expect(pattern.angle, closeTo(12, 1e-9));
      expect(pattern.intensity, closeTo(0.65, 1e-9));
    });

    test(
      'an unknown style falls back instead of failing the whole project',
      () {
        final restored = backgroundFromJson({
          'type': 'pattern',
          'style': 'something_a_newer_build_added',
          'colors': [0xFF000000],
          'seed': 1,
        });
        expect((restored as PatternBackground).style, PatternStyle.mesh);
      },
    );
  });

  group('presets', () {
    test('all are usable as-is', () {
      expect(PatternPresets.all, isNotEmpty);
      for (final preset in PatternPresets.all) {
        expect(preset.colors.length, greaterThanOrEqualTo(2));
        expect(preset.scale, inInclusiveRange(0.4, 2.5));
        expect(preset.angle, inInclusiveRange(0, 360));
        expect(preset.intensity, inInclusiveRange(0.1, 1.0));
      }
    });

    test('the gallery is a full fifty', () {
      expect(PatternPresets.all.length, greaterThanOrEqualTo(50));
    });

    group('panorama', () {
      test('every set is eight slices of one composition', () {
        expect(PatternPresets.panoramas, isNotEmpty);
        for (final set in PatternPresets.panoramas) {
          expect(set, hasLength(8));
          final first = set.first;
          for (var i = 0; i < set.length; i++) {
            final slice = set[i];
            // Same picture, different window. Any of these drifting apart is a
            // seam between two screens of a listing.
            expect(slice.style, first.style);
            expect(slice.seed, first.seed);
            expect(slice.colors, first.colors);
            expect(slice.scale, first.scale);
            expect(slice.slices, 8);
            expect(slice.slice, i);
          }
        }
      });

      test('each set is a different style, and each is a sweeping one', () {
        // A checkerboard eight screens wide is still a checkerboard on every
        // one of them: only styles whose composition travels gain anything
        // from being sliced.
        final styles = PatternPresets.panoramas.map((s) => s.first.style);
        expect(styles.toSet(), hasLength(styles.length));

        const tiling = <PatternStyle>{
          PatternStyle.dots,
          PatternStyle.grid,
          PatternStyle.checkers,
          PatternStyle.stripes,
          PatternStyle.hexagons,
          PatternStyle.scales,
          PatternStyle.crosses,
          PatternStyle.plaid,
          PatternStyle.symbols,
        };
        for (final style in styles) {
          expect(tiling.contains(style), isFalse, reason: style.name);
        }
      });

      test('sets do not share a seed, so the picker can tell them apart', () {
        // The panorama picker finds the showing set by matching the seed, so
        // two sets sharing one would be indistinguishable.
        final seeds = PatternPresets.panoramas.map((s) => s.first.seed);
        expect(seeds.toSet(), hasLength(seeds.length));
      });

      test('each slice shows a different part of the artwork', () async {
        const size = Size(48, 96);
        for (final set in PatternPresets.panoramas) {
          final seen = <String, int>{};
          for (var i = 0; i < set.length; i++) {
            final key = (await _render(
              set[i],
              size,
            )).buffer.asUint8List().join(',');
            expect(
              seen.containsKey(key),
              isFalse,
              reason:
                  '${set.first.style.name} slice $i is identical to slice '
                  '${seen[key]} — it is not actually being sliced',
            );
            seen[key] = i;
          }
        }
      });

      test('a slice is the matching window onto the whole artwork', () async {
        // The guarantee the whole feature rests on: slice i rendered at one
        // screen wide must equal the i-th vertical strip of the composition
        // rendered at full width. If that holds, screens laid side by side
        // join up.
        const w = 24.0;
        const h = 96.0;
        for (final set in PatternPresets.panoramas) {
          final whole = await _render(
            set.first.copyWith(slices: 1),
            const Size(w * 8, h),
          );
          for (final index in const [0, 3, 7]) {
            final slice = await _render(set[index], const Size(w, h));
            for (final (u, v) in const [(0.3, 0.25), (0.5, 0.6), (0.8, 0.85)]) {
              _expectClose(
                _sample(slice, const Size(w, h), u, v),
                _sample(whole, const Size(w * 8, h), (index + u) / 8, v),
                tolerance: 6,
                reason:
                    '${set.first.style.name} slice $index does not line up '
                    'at ($u, $v)',
              );
            }
          }
        }
      });
    });

    group('symbols', () {
      test('every symbol draws, alone and mixed', () async {
        for (final symbol in PatternSymbol.values) {
          final data = await _render(
            PatternBackground(
              style: PatternStyle.symbols,
              colors: const [Color(0xFF0B1020), Color(0xFF6EE7F9)],
              seed: 7,
              symbols: [symbol],
            ),
            const Size(60, 120),
          );
          expect(data.lengthInBytes, 60 * 120 * 4, reason: symbol.name);
        }

        final mixed = await _render(
          PatternBackground(
            style: PatternStyle.symbols,
            colors: const [Color(0xFF0B1020), Color(0xFF6EE7F9)],
            seed: 7,
            symbols: PatternSymbol.values,
          ),
          const Size(60, 120),
        );
        expect(mixed.lengthInBytes, 60 * 120 * 4);
      });

      test('a different symbol is a different picture', () async {
        const size = Size(64, 128);
        const base = PatternBackground(
          style: PatternStyle.symbols,
          colors: [Color(0xFF0B1020), Color(0xFF6EE7F9)],
          seed: 3,
          symbols: [PatternSymbol.heart],
        );
        final hearts = await _render(base, size);
        final stars = await _render(
          base.copyWith(symbols: const [PatternSymbol.star]),
          size,
        );
        expect(hearts.buffer.asUint8List(), isNot(stars.buffer.asUint8List()));
      });

      test('count, opacity and centre each change the field', () async {
        const size = Size(64, 128);
        const base = PatternBackground(
          style: PatternStyle.symbols,
          colors: [Color(0xFF0B1020), Color(0xFF6EE7F9)],
          seed: 3,
          symbolCount: 20,
        );
        final plain = (await _render(base, size)).buffer.asUint8List();

        for (final variant in [
          base.copyWith(symbolCount: 60),
          base.copyWith(symbolOpacity: 0.2),
          base.copyWith(symbolCenter: const Offset(0.3, -0.2)),
        ]) {
          expect(
            (await _render(variant, size)).buffer.asUint8List(),
            isNot(plain),
          );
        }
      });

      test('an empty symbol list still paints something', () async {
        // Only reachable by hand-editing a file — the panel will not let the
        // last symbol be turned off — but a backdrop that silently became a
        // flat colour would look like the style had broken.
        const size = Size(48, 96);
        final empty = await _render(
          const PatternBackground(
            style: PatternStyle.symbols,
            colors: [Color(0xFF0B1020), Color(0xFF6EE7F9)],
            seed: 3,
            symbols: [],
          ),
          size,
        );
        final flat = await _render(
          const PatternBackground(
            style: PatternStyle.symbols,
            colors: [Color(0xFF0B1020), Color(0xFF0B1020)],
            seed: 3,
            symbolOpacity: 0,
          ),
          size,
        );
        expect(empty.buffer.asUint8List(), isNot(flat.buffer.asUint8List()));
      });

      test('the twenty icon styles migrate to their glyph', () {
        // A project written by the older build must keep its artwork. Falling
        // through to mesh would open it as a gradient with the symbols gone.
        const migrations = <String, PatternSymbol>{
          'notes': PatternSymbol.note,
          'hearts': PatternSymbol.heart,
          'wifi': PatternSymbol.wifi,
          'sparkles': PatternSymbol.sparkle,
          'bug': PatternSymbol.bug,
          'at': PatternSymbol.at,
          'hash': PatternSymbol.hash,
          'orbit': PatternSymbol.orbit,
          // Removed outright a version earlier; lands on the nearest survivor.
          'equalizer': PatternSymbol.waveform,
        };
        migrations.forEach((name, symbol) {
          final restored =
              backgroundFromJson({
                    'type': 'pattern',
                    'style': name,
                    'colors': [0xFF000000, 0xFFFFFFFF],
                    'seed': 5,
                  })
                  as PatternBackground;
          expect(restored.style, PatternStyle.symbols, reason: name);
          expect(restored.symbols, [symbol], reason: name);
        });
      });

      test('a symbol field survives a round trip', () {
        const original = PatternBackground(
          style: PatternStyle.symbols,
          colors: [Color(0xFF101828), Color(0xFF38BDF8)],
          seed: 12,
          symbols: [PatternSymbol.wifi, PatternSymbol.network],
          symbolCount: 44,
          symbolOpacity: 0.42,
          symbolCenter: Offset(0.2, -0.3),
        );
        final restored =
            backgroundFromJson(backgroundToJson(original)) as PatternBackground;
        expect(restored.symbols, original.symbols);
        expect(restored.symbolCount, 44);
        expect(restored.symbolOpacity, closeTo(0.42, 1e-9));
        expect(restored.symbolCenter.dx, closeTo(0.2, 1e-9));
        expect(restored.symbolCenter.dy, closeTo(-0.3, 1e-9));
      });

      test('an unknown symbol is dropped, not fatal', () {
        final restored =
            backgroundFromJson({
                  'type': 'pattern',
                  'style': 'symbols',
                  'colors': [0xFF000000],
                  'seed': 1,
                  'symbols': ['heart', 'something_a_newer_build_added'],
                })
                as PatternBackground;
        expect(restored.symbols, [PatternSymbol.heart]);
      });
    });

    test('no two presets render the same picture', () async {
      // Byte equality only. The softer question — how many *look* alike — is
      // the next test, which is the one that actually reflects what the grid
      // feels like to scroll.
      const size = Size(48, 96);
      final seen = <String, int>{};
      for (var i = 0; i < PatternPresets.all.length; i++) {
        final key = (await _render(
          PatternPresets.all[i],
          size,
        )).buffer.asUint8List().join(',');
        expect(
          seen.containsKey(key),
          isFalse,
          reason: 'preset $i is pixel-identical to preset ${seen[key]}',
        );
        seen[key] = i;
      }
    });

    test('the gallery does not drift further into sameness', () async {
      // Zero, and it should stay zero.
      //
      // This used to allow forty-two look-alike pairs of the sixty-six presets
      // — mostly faint motifs over pale grounds, which at preview size all read
      // as "a light background with some texture", the worst pair at a mean
      // channel difference of 2. The palette pass that fixed it gave every
      // preset its own colour set and set each one's intensity against the
      // palette it got rather than against a default.
      //
      // A new preset that trips this is a new preset that duplicates a tile
      // somebody already has to scroll past. Retune it rather than raising the
      // bound: the number should only ever be edited downward.
      const size = Size(48, 96);
      final shots = [
        for (final preset in PatternPresets.all)
          (await _render(preset, size)).buffer.asUint8List(),
      ];

      var alike = 0;
      for (var i = 0; i < shots.length; i++) {
        for (var j = i + 1; j < shots.length; j++) {
          var total = 0.0;
          for (var k = 0; k < shots[i].length; k += 4) {
            total +=
                (shots[i][k] - shots[j][k]).abs() +
                (shots[i][k + 1] - shots[j][k + 1]).abs() +
                (shots[i][k + 2] - shots[j][k + 2]).abs();
          }
          if (total / (shots[i].length / 4 * 3) < 14) alike++;
        }
      }
      expect(
        alike,
        isZero,
        reason: 'presets are getting harder to tell apart, not easier',
      );
    });

    test('the retired styles are gone from the enum', () {
      // `equalizer` was a duplicate of `waveform`; the twenty icon styles
      // became [PatternStyle.symbols]. What each one *opens as* is covered by
      // the migration test — this only guards the enum against them coming
      // back, since a name that exists again would shadow its own migration.
      final names = PatternStyle.values.map((s) => s.name).toSet();
      for (final retired in const [
        'equalizer',
        'notes',
        'hearts',
        'wifi',
        'network',
        'sparkles',
        'chat',
        'play',
        'shields',
        'clouds',
        'pins',
        'stars',
        'bolts',
        'aperture',
        'orbit',
        'bells',
        'bug',
        'hash',
        'at',
      ]) {
        expect(names, isNot(contains(retired)), reason: retired);
      }
    });

    test('no palette is used twice', () {
      // The upstream cause of a look-alike pair, and the cheap thing to check:
      // two presets built from the same four colours read as the same tile at
      // 44dp however different their styles are on paper.
      final seen = <String, int>{};
      for (var i = 0; i < PatternPresets.all.length; i++) {
        final key = PatternPresets.all[i].colors
            .map((c) => c.toARGB32())
            .join(',');
        expect(
          seen.containsKey(key),
          isFalse,
          reason:
              'preset $i (${PatternPresets.all[i].style.name}) reuses the '
              'palette of preset ${seen[key]}',
        );
        seen[key] = i;
      }
    });

    test('every seed is unique, so the picker can tell them apart', () {
      // The grid marks the showing preset by matching its seed. Two presets
      // sharing one would light up together and neither could be selected off
      // the other — and with sixty-odd entries a duplicate is easy to add.
      final seeds = PatternPresets.all.map((p) => p.seed).toList();
      expect(seeds.toSet(), hasLength(seeds.length));
    });

    test('no style appears twice', () {
      // One preset per style, which is what makes the gallery a menu of what
      // the painter can *do* rather than a menu of colourways.
      //
      // This replaced the opposite rule: poster, stage and beams used to be
      // required to carry four colourways each, on the grounds that picking a
      // style and then hand-mixing four colours was too much work. The palette
      // row and its shuffle button cover that now, and sixteen of the sixty-six
      // presets being three styles recoloured was most of what made the grid
      // tiring to scroll.
      //
      // `symbols` is the one exception, and deliberately: what makes two
      // symbol presets different pictures is the glyphs, not the style, so a
      // single entry would hide nineteen of the twenty behind a panel. They
      // are held to the same rule one level down — no two share a symbol set.
      final styles = PatternPresets.all
          .where((p) => p.style != PatternStyle.symbols)
          .map((p) => p.style)
          .toList();
      expect(styles.toSet(), hasLength(styles.length));

      final sets = PatternPresets.all
          .where((p) => p.style == PatternStyle.symbols)
          .map((p) => p.symbols.map((s) => s.name).join(','))
          .toList();
      expect(sets, isNotEmpty);
      expect(sets.toSet(), hasLength(sets.length));
    });

    test('every style is reachable from a preset', () {
      final covered = PatternPresets.all.map((p) => p.style).toSet();
      expect(
        PatternStyle.values.where((s) => !covered.contains(s)),
        isEmpty,
        reason: 'a style with no preset is a style nobody will find',
      );
    });

    test('seeds are unique, so the picker can tell presets apart', () {
      final seeds = PatternPresets.all.map((p) => p.seed).toList();
      expect(seeds.toSet().length, seeds.length);
    });
  });

  group('defaults', () {
    test('a new screen starts on a flat fill, not a gradient', () {
      expect(kDefaultBackground, isA<SolidBackground>());
      const doc = ScreenDoc(id: 'x');
      expect(doc.background, isA<SolidBackground>());
    });

    test('the default caption reads against the default backdrop', () {
      final background = (kDefaultBackground as SolidBackground).color;
      // Enough separation that the seeded headline is legible out of the box.
      final delta =
          (background.computeLuminance() -
                  kDefaultCaptionColor.computeLuminance())
              .abs();
      expect(delta, greaterThan(0.5));
    });
  });
}
