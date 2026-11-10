// Renders one specimen sheet per candidate typeface, for identifying the face
// a reference listing was set in.
//
//   flutter test integration_test/font_fingerprint_test.dart -d windows
//
// A headline's ink is a fingerprint: for a given string, the ratio of its
// advance width to its cap height is a property of the face and of nothing
// else — not the size it was set at, not the canvas it was measured on. So
// rather than squinting at letterforms, this writes every candidate at one
// size and lets `tool/identify_font.py` measure them against the original.
//
// Runs here rather than under `flutter test` because the candidates have to
// actually download from Google Fonts to be measured, and the headless test
// binding has no network and no font loader. A research tool for whoever
// authors a template; the app itself never downloads a font.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mockmyapp/data/assets/studio_fonts.dart';

const _out = 'build/fingerprint/sheets';

/// The lines to set, one per row of every sheet.
///
/// Read from `build/fingerprint/lines.txt` — one line of copy per file line —
/// so identifying the next listing's face is a matter of writing that file and
/// re-running, rather than editing and rebuilding this.
final _raw = File(
  'build/fingerprint/lines.txt',
).readAsLinesSync().map((l) => l.trim()).toList();

final _lines = _raw.where((l) => l.isNotEmpty && !l.startsWith('#')).toList();

/// The weight the listing sets its headlines at.
///
/// Written as a `#bold=false` directive on the first line of the same file. It
/// is not a detail: a face measured at 700 against a listing set at 400
/// mismatches on every letter, and the ranking then says — correctly, and
/// uselessly — that none of the candidates fit.
final _bold = !_raw.contains('#bold=false');

/// Every heavy or squarish face in the app's own catalog. The listing was set
/// in one of these or in none of them, and a candidate that is not offered in
/// the caption panel is no use even if it matched.
const _candidates = [
  'Archivo Black',
  'Anton',
  'Rubik',
  'Poppins',
  'Montserrat',
  'Nunito',
  'Outfit',
  'Figtree',
  'Manrope',
  'Lexend',
  'Urbanist',
  'Gabarito',
  'Onest',
  'Archivo',
  'Inter',
  'Work Sans',
  'Space Grotesk',
  'Sora',
  'Russo One',
  'Secular One',
  'Paytone One',
  'Lilita One',
  'Righteous',
  'Bebas Neue',
  'Mulish',
  'Barlow',
  'Roboto',
];

/// Set big enough that a cap height is measurable to well under a percent,
/// and small enough that a sheet of [_perSheet] rows fits inside the window.
///
/// The window matters: content laid out past its height never paints, so a
/// taller sheet would come back with its last rows blank — which measures as a
/// missing line rather than as an error.
const _size = 90.0;

/// Leading, as a multiple of [_size].
const _lead = 1.35;

/// Rows per sheet. Twelve lines at this size do not fit in one window.
const _perSheet = 6;

final _key = GlobalKey();

Future<void> shoot(WidgetTester tester, String name) async {
  final boundary =
      _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  late final ui.Image image;
  await tester.runAsync(() async {
    image = await boundary.toImage(pixelRatio: 1);
  });
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('$_out/$name.png')..createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('specimen sheets', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final family in _candidates) {
      for (var sheet = 0; sheet * _perSheet < _lines.length; sheet++) {
        final rows = _lines.skip(sheet * _perSheet).take(_perSheet).toList();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: _key,
                // `Material`, not a bare `ColoredBox`: a `Text` with no
                // material ancestor is drawn with Flutter's debug double
                // underline, which lands in the raster as ink and measures as
                // part of the line.
                child: Material(
                  color: const Color(0xFF000000),
                  child: SizedBox(
                    width: 1400,
                    // Every row the same box height, so a row's index locates it
                    // in the sheet without having to segment the image.
                    height: _size * _lead * rows.length,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in rows)
                          SizedBox(
                            height: _size * _lead,
                            child: Text(
                              line,
                              maxLines: 1,
                              softWrap: false,
                              style: StudioFonts.style(
                                family,
                                fontSize: _size,
                                height: _lead,
                                color: const Color(0xFFFFFFFF),
                                fontWeight: _bold
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        // The face has to arrive before it can be measured; an unresolved
        // family rasterises as Roboto and would score as a false match.
        await tester.pumpAndSettle();
        await tester.runAsync(() => GoogleFonts.pendingFonts());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        await tester.pumpAndSettle();
        await shoot(tester, '${family.replaceAll(' ', '-')}-$sheet');
      }
      print('  sheets → $family');
    }
  });
}
