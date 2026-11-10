import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

void main() {
  group('what a new screen opens on', () {
    test('the canvas is the gallery\'s first gradient colour', () {
      // Not near-white. A white canvas behind a white-bezelled phone reads as
      // a page nobody has designed yet, and it was the first thing every user
      // changed.
      expect(kDefaultBackground, isA<SolidBackground>());
      expect(
        (kDefaultBackground as SolidBackground).color,
        const Color(0xFF5B5FEF),
      );
    });

    test('the caption still reads against it', () {
      // The pair is the point: moving the canvas off near-white without moving
      // the ink turns every new screen's headline invisible.
      final bg = (kDefaultBackground as SolidBackground).color;
      final contrast =
          (_luminance(kDefaultCaptionColor) + 0.05) / (_luminance(bg) + 0.05);
      expect(
        contrast,
        greaterThan(4.5),
        reason: 'caption over canvas should clear WCAG AA for large text',
      );
    });
  });
}

double _luminance(Color c) => c.computeLuminance();
