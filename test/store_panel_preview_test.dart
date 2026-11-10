// Renders the store-panel looks to PNGs for eyeballing. Not an assertion
// suite — it exists so a change to the poster/stage/beams painters or to the
// caption effects can be *looked at* rather than only measured.
//
//   flutter test test/store_panel_preview_test.dart
//
// Writes into build/preview/.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/domain/engine/pattern_painter.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

const _out = 'build/preview';

Future<void> _write(String name, PatternBackground spec, Size size) async {
  final recorder = ui.PictureRecorder();
  PatternPainter(spec).paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();

  final file = File('$_out/$name.png')..createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
  print('  ${(file.lengthSync() / 1024).round()} KB  ${file.path}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('render the store-panel backdrops', () async {
    const cobalt = [
      Color(0xFF2645D4),
      Color(0xFF0A0E22),
      Color(0xFFFFD84D),
      Color(0xFFFFFFFF),
    ];
    const magenta = [
      Color(0xFFD82B86),
      Color(0xFF0A0E22),
      Color(0xFFFFD84D),
      Color(0xFFFFFFFF),
    ];
    const midnight = [
      Color(0xFF060B22),
      Color(0xFF2F55E0),
      Color(0xFF7A2FD8),
      Color(0xFFFFFFFF),
    ];

    const play = Size(1080, 1920);
    print('\nstore panels →');
    await _write(
      'poster_cobalt',
      const PatternBackground(
        style: PatternStyle.poster,
        colors: cobalt,
        seed: 51,
      ),
      play,
    );
    await _write(
      'stage_midnight',
      const PatternBackground(
        style: PatternStyle.stage,
        colors: midnight,
        seed: 52,
      ),
      play,
    );
    await _write(
      'beams_magenta',
      const PatternBackground(
        style: PatternStyle.beams,
        colors: magenta,
        seed: 53,
      ),
      play,
    );

    // Thumbnail legibility: the picker paints these at tile size, where the
    // grain and sparkles vanish and only the gradients carry the look.
    await _write(
      'beams_magenta_tile',
      const PatternBackground(
        style: PatternStyle.beams,
        colors: magenta,
        seed: 53,
      ),
      const Size(120, 214),
    );
  });

  // A whole composed panel is deliberately NOT rendered here: captions resolve
  // their typeface through `GoogleFonts`, which cannot fetch one under
  // `flutter test`, so the panel would come out in a fallback face and any
  // `pumpAndSettle` would hang waiting on the font. Compose panels in the app;
  // the caption effects themselves are asserted in scene_renderer_test.dart.
}
