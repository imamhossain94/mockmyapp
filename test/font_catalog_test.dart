import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:mockmyapp/data/assets/font_catalog.dart';
import 'package:mockmyapp/data/assets/studio_fonts.dart';
import 'package:mockmyapp/data/repositories/font_library.dart';

/// google_fonts' own name for a weight's file: `Regular`, `Bold`…
final _fileWeight = {
  FontWeight.w400: 'Regular',
  FontWeight.w500: 'Medium',
  FontWeight.w600: 'SemiBold',
  FontWeight.w700: 'Bold',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the catalog', () {
    test('names only families google_fonts actually ships', () {
      // Cheap, and it is the only thing standing between a typo here and a row
      // that silently previews in Roboto: the resolver is total by design, so a
      // misspelt family does not throw, it just quietly renders the wrong face
      // in the picker, on the canvas and in the export.
      final known = GoogleFonts.asMap().keys.toSet();
      final unknown = [
        for (final entry in fontCatalog)
          if (!known.contains(entry.family)) entry.family,
      ];
      expect(unknown, isEmpty, reason: 'not families google_fonts knows');
    });

    test('offers only families the app ships', () {
      // The app never downloads a font, so a row for a family it does not
      // ship would preview, paint and export in the fallback face.
      final bundled = {for (final f in kBundledFonts) f.family};
      final missing = [
        for (final entry in fontCatalog)
          if (!bundled.contains(entry.family)) entry.family,
      ];
      expect(missing, isEmpty, reason: 'not in kBundledFonts');
    });

    test('lists no family twice', () {
      final seen = <String>{};
      final duplicates = [
        for (final entry in fontCatalog)
          if (!seen.add(entry.family)) entry.family,
      ];
      expect(duplicates, isEmpty);
    });

    test('has at least one popular face in every category', () {
      // The quick strip is composed from the popular flag and nothing else, so
      // a category with none of them is a whole look — mono, handwriting — that
      // can only be reached by opening the picker.
      for (final category in FontCategory.values) {
        expect(
          fontCatalog.any((f) => f.category == category && f.popular),
          isTrue,
          reason: 'no popular entry in ${category.name}',
        );
      }
    });

    test('keeps the popular set small enough to be a shortcut', () {
      // The strip caps at sixteen tiles and shares them with the user's own
      // recents and uploads. More popular entries than that would push the
      // things a person actually reached for off the end of the row.
      final popular = fontCatalog.where((f) => f.popular);
      expect(popular.length, lessThanOrEqualTo(16));
      expect(popular.length, greaterThanOrEqualTo(8));
    });

    test('cannot collide with an uploaded font', () {
      // The whole `user:<id>` scheme rests on this. It is asserted over the
      // curated list rather than over all 1,709 Google families because this is
      // the list that grows by hand.
      for (final entry in fontCatalog) {
        expect(
          FontLibrary.idOf(entry.family),
          isNull,
          reason: '${entry.family} would be read as an uploaded font',
        );
      }
    });
  });

  group('the bundled fonts', () {
    test('are exactly the files in assets/google_fonts', () {
      // Both directions: a face in the table with no file paints in the
      // platform's font, and a file nobody lists is weight in every build.
      final expected = <String>{
        for (final font in kBundledFonts) ...[
          for (final weight in font.weights)
            '${font.file}-${_fileWeight[weight]}.ttf',
          '${font.file}-OFL.txt',
        ],
      };
      final onDisk = {
        for (final file in Directory('assets/google_fonts').listSync())
          if (file is File) file.uri.pathSegments.last,
      }..remove('.DS_Store');
      expect(onDisk, expected);
    });

    test('are families google_fonts knows, under the file names it reads', () {
      final known = GoogleFonts.asMap().keys.toSet();
      for (final font in kBundledFonts) {
        expect(known, contains(font.family));
        expect(font.file, font.family.replaceAll(' ', ''));
        expect(font.weights, isNotEmpty);
      }
    });
  });
}
