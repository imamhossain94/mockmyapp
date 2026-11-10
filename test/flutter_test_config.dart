import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Runs before every test in this directory.
///
/// Neutralises google_fonts, which any test that renders a composed scene runs
/// into: `SceneView` styles a caption with `GoogleFonts.getFont`, and the
/// package's default is to fetch the file over HTTP on first use. A widget test
/// has no network — the binding answers every request with a 400 — so the fetch
/// throws from an async suspension, lands on whichever test happens to be
/// running, and fails it for reasons unrelated to what it asserts.
///
/// Two steps, because either alone is not enough:
///
///  * Runtime fetching off, as the app has it (`lib/main.dart`), so no
///    request is attempted at all. On its own this only changes the
///    exception's message — the package still throws when the font is absent
///    from the assets. The faces under `assets/google_fonts/` load from there,
///    as they do in the app; only a family the app does not ship is absent.
///  * The resulting exception filtered out of the test report. Nothing is
///    swallowed beyond fonts: the predicate matches only google_fonts' own
///    message, and every other exception reports exactly as it did before.
///
/// So a scene set in a bundled face lays out in that face's real metrics, and
/// one set in any other family in the test font.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GoogleFonts.config.allowRuntimeFetching = false;

  final report = reportTestException;
  reportTestException = (details, testDescription) {
    if (_isMissingFont(details.exception)) return;
    report(details, testDescription);
  };

  await testMain();
}

bool _isMissingFont(Object exception) {
  final text = exception.toString();
  return text.contains('GoogleFonts.config.allowRuntimeFetching') ||
      text.contains('Failed to load font with url');
}
