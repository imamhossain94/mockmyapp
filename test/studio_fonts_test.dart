import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/assets/studio_fonts.dart';
import 'package:mockmyapp/data/repositories/font_library.dart';

import 'support/host_face.dart';

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// Every case here is a `testWidgets` even where nothing is pumped.
///
/// Resolving a Google family schedules google_fonts' own asset lookup, which
/// throws asynchronously under `flutter test` for any family or weight the
/// app does not ship under `assets/google_fonts/`.
/// `flutter_test_config.dart` filters exactly that message — but only
/// through `reportTestException`, which is `flutter_test`'s hook and is not
/// consulted for a plain `test()`. A bare `test()` therefore fails with "this
/// test failed after it had already completed" for a reason that has nothing to
/// do with what it asserts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final hostFace = readHostFace();

  setUp(FontLibrary.debugResetStorage);

  group('a family the app knows', () {
    testWidgets('resolves through google_fonts', (tester) async {
      final style = StudioFonts.style('Poppins', fontSize: 24);
      expect(style.fontFamily, isNotNull);
      expect(style.fontFamily, startsWith('Poppins'));
      expect(style.fontSize, 24);
      expect(StudioFonts.canResolve('Poppins'), isTrue);
      expect(StudioFonts.isMissing('Poppins'), isFalse);
      expect(StudioFonts.displayName('Poppins'), 'Poppins');
    });

    testWidgets('picks the variant file from the weight it is given', (
      tester,
    ) async {
      // The reason weight is a parameter here and never a `copyWith` applied
      // afterwards: google_fonts resolves the variant *file* from it, yielding
      // a family name like `Poppins_700`. Bolding after the fact would load
      // `Poppins_regular` and let the engine synthesise a faux bold on top of
      // it, which is a visibly different — and worse — letterform.
      final regular = StudioFonts.style('Poppins');
      final bold = StudioFonts.style('Poppins', fontWeight: FontWeight.bold);
      expect(bold.fontFamily, isNot(regular.fontFamily));
    });

    testWidgets('takes the nearest bundled file for a weight it lacks', (
      tester,
    ) async {
      // Poppins ships Regular and Bold. Semibold and black find the Bold
      // file rather than no file at all — which would paint in the platform
      // face — and still ask for the weight that was set.
      final bold = StudioFonts.style('Poppins', fontWeight: FontWeight.w700);
      final semibold = StudioFonts.style(
        'Poppins',
        fontWeight: FontWeight.w600,
      );
      final black = StudioFonts.style('Poppins', fontWeight: FontWeight.w900);
      expect(semibold.fontFamily, bold.fontFamily);
      expect(black.fontFamily, bold.fontFamily);
      expect(semibold.fontWeight, FontWeight.w600);
      // An italic asks the engine to slant the upright file.
      final italic = StudioFonts.style('Poppins', fontStyle: FontStyle.italic);
      expect(italic.fontFamily, StudioFonts.style('Poppins').fontFamily);
      expect(italic.fontStyle, FontStyle.italic);
    });

    test('the nearest weight follows CSS on a tie', () {
      const regularBold = [FontWeight.w400, FontWeight.w700];
      expect(
        StudioFonts.nearestWeight(regularBold, FontWeight.w300),
        FontWeight.w400,
      );
      expect(
        StudioFonts.nearestWeight(regularBold, FontWeight.w500),
        FontWeight.w400,
      );
      expect(
        StudioFonts.nearestWeight(regularBold, FontWeight.w600),
        FontWeight.w700,
      );
      expect(
        StudioFonts.nearestWeight(const [
          FontWeight.w400,
          FontWeight.w600,
        ], FontWeight.w500),
        FontWeight.w600,
        reason: 'medium and up breaks a tie towards heavier',
      );
      expect(
        StudioFonts.nearestWeight(const [FontWeight.w400], FontWeight.w900),
        FontWeight.w400,
      );
    });
  });

  group('a Google family the app does not ship', () {
    testWidgets('paints in the fallback face, and says it is missing', (
      tester,
    ) async {
      // Lato is one google_fonts knows and the app does not bundle: an older
      // build fetched it on demand, and this one never fetches anything.
      expect(GoogleFonts.asMap(), contains('Lato'));
      final style = StudioFonts.style('Lato', fontSize: 18);
      expect(style.fontFamily, startsWith(StudioFonts.fallbackFamily));
      expect(StudioFonts.canResolve('Lato'), isFalse);
      expect(
        StudioFonts.isMissing('Lato'),
        isTrue,
        reason: 'the person can upload it, so the editor tells them',
      );
    });
  });

  group('a family the app does not know', () {
    testWidgets('is exactly what google_fonts throws on', (tester) async {
      // The regression this whole layer exists for. Every render site used to
      // call getFont directly, inside build, unguarded — and the same closure
      // paints the editor canvas, the home-screen thumbnails and the export
      // raster, whose capture swallows exceptions and returns null.
      expect(() => GoogleFonts.getFont('No Such Family 9000'), throwsException);
    });

    testWidgets('resolves to the fallback face instead of throwing', (
      tester,
    ) async {
      late TextStyle style;
      expect(
        () => style = StudioFonts.style('No Such Family 9000', fontSize: 18),
        returnsNormally,
      );
      expect(style.fontFamily, startsWith(StudioFonts.fallbackFamily));
      expect(style.fontSize, 18, reason: 'the rest of the style still applies');
      expect(StudioFonts.canResolve('No Such Family 9000'), isFalse);
      expect(
        StudioFonts.isMissing('No Such Family 9000'),
        isFalse,
        reason:
            'an unknown Google family is not something the user can fix, so '
            'the editor must not offer to fix it',
      );
    });

    testWidgets('the empty string is not special-cased into a crash', (
      tester,
    ) async {
      expect(() => StudioFonts.style(''), returnsNormally);
      expect(StudioFonts.style('').fontFamily, startsWith('Roboto'));
    });
  });

  group('an uploaded family with nothing registered', () {
    testWidgets('falls back silently and reports itself missing', (
      tester,
    ) async {
      const family = 'user:deadbeef';
      expect(() => StudioFonts.style(family), returnsNormally);
      expect(StudioFonts.style(family).fontFamily, startsWith('Roboto'));
      expect(StudioFonts.isMissing(family), isTrue);
      expect(StudioFonts.canResolve(family), isFalse);
      // The panel row has to say something a person can read. `user:deadbeef`
      // is not it.
      expect(StudioFonts.displayName(family), 'Missing font');
    });
  });

  group(
    'a registered upload',
    () {
      late Directory tempDir;
      late ProviderContainer container;

      setUp(() async {
        tempDir = Directory.systemTemp.createTempSync('studio_fonts_test');
        FontLibrary.debugResetStorage();
        PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
        await FontLibrary.initialize();
        container = ProviderContainer();
      });

      tearDown(() {
        container.dispose();
        try {
          tempDir.deleteSync(recursive: true);
        } on FileSystemException {
          // Leave it for the OS.
        }
      });

      testWidgets('paints under the exact user: string it is stored as', (
        tester,
      ) async {
        // Through `runAsync`, because the import is real file I/O and a
        // `testWidgets` body runs in fake async — an awaited `File.writeAsBytes`
        // in there never completes and the case sits until the ten-minute
        // timeout.
        final entry = await tester.runAsync(
          () => container
              .read(fontLibraryProvider.notifier)
              .importBytes(hostFace!, label: 'Brand Sans'),
        );
        expect(entry, isNotNull);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text('Ag', style: StudioFonts.style(entry!.family)),
          ),
        );

        final text = tester.widget<Text>(find.text('Ag'));
        // The colon is the point. A caption stores `user:<id>`, FontLoader is
        // handed that same string, and the TextStyle names it verbatim — one
        // value, and no mapping table between the document and the engine.
        expect(text.style?.fontFamily, entry.family);
        expect(text.style?.fontFamily, startsWith('user:'));
        expect(
          text.style?.fontFamilyFallback,
          contains(StudioFonts.fallbackFamily),
          reason: 'digits and punctuation still resolve if the face is partial',
        );

        expect(StudioFonts.isMissing(entry.family), isFalse);
        expect(StudioFonts.displayName(entry.family), 'Brand Sans');
      });
    },
    skip: hostFace == null ? 'no readable system font on this machine' : null,
  );
}
