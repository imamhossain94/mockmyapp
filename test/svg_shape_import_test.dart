import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/features/editor/widgets/svg_shape_import.dart';

/// What an imported SVG becomes on the canvas.
///
/// Imports used to be silhouettes in the canvas's ink, whatever the file
/// said: a brand-blue logo arrived white, a two-colour one arrived as one
/// blob, and an outlined icon arrived filled in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ink = Color(0xFFFFFFFF);

  test('a coloured outline keeps its colour', () {
    final shape = importedShape(
      pathData: 'M0 0L1 0L1 1Z',
      evenOdd: false,
      aspect: 1,
      ink: ink,
      colour: const Color(0xFF5B5FEF),
    );
    expect(shape.fill.toARGB32(), 0xFF5B5FEF);
    expect(shape.strokeWidth, 0);
  });

  test('an outline that named no colour takes the canvas ink', () {
    // Black is what a colourless file and `currentColor` both draw in, and a
    // black mark on a dark backdrop is one nobody can see.
    final shape = importedShape(
      pathData: 'M0 0L1 0L1 1Z',
      evenOdd: false,
      aspect: 1,
      ink: ink,
    );
    expect(shape.fill, ink);
  });

  test('line art stays a line, as the icon library draws it', () {
    final shape = importedShape(
      pathData: 'M0 0L1 1',
      evenOdd: false,
      aspect: 1,
      ink: ink,
      colour: const Color(0xFF23C4A8),
      stroke: 0.25,
    );
    expect(shape.fill.a, 0, reason: 'nothing filled in');
    expect(shape.strokeColor.toARGB32(), 0xFF23C4A8);
    expect(shape.strokeWidth, 0.25);
    expect(shape.strokeInBox, isTrue);
  });

  test('artwork an outline cannot carry is drawn as it is', () async {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 10">'
        '<rect width="10" height="10" fill="#ff0000"/>'
        '<rect x="10" width="10" height="10" fill="#0000ff"/>'
        '</svg>';
    final png = await rasteriseSvg(svg, longest: 40);
    expect(png, isNotNull);

    final codec = await ui.instantiateImageCodec(png!);
    final image = (await codec.getNextFrame()).image;
    expect((image.width, image.height), (40, 20));
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    Color at(int x, int y) {
      final o = (y * image.width + x) * 4;
      return Color.fromARGB(
        data.getUint8(o + 3),
        data.getUint8(o),
        data.getUint8(o + 1),
        data.getUint8(o + 2),
      );
    }

    expect(at(10, 10), const Color(0xFFFF0000));
    expect(at(30, 10), const Color(0xFF0000FF));
    image.dispose();
  });
}
