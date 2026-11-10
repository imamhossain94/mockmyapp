import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app/app.dart';
import 'data/assets/studio_fonts.dart';
import 'data/repositories/font_library.dart';
import 'data/repositories/image_library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Every face the app paints ships with it (`kBundledFonts`), so google_fonts
  // is never allowed to fetch one: the app makes no network request of its
  // own. A family it does not ship paints in the fallback face instead.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Resolves the app's picture folder before the first frame so image paths can
  // be repaired synchronously while painting. See [ImageLibrary.resolve].
  //
  // The font library follows for the same reason and one more: every uploaded
  // face has to reach the engine before anything paints, because resolving a
  // family happens inside `build` and cannot wait. `ScreenThumbnail` has no
  // readiness barrier at all, so a face registered lazily would leave every
  // tile on the home screen drawn in the fallback face on each cold launch,
  // with nothing to correct it afterwards.
  //
  // Guarded as well as guarding itself. Nothing between here and [runApp] may
  // decide whether the app starts: an exception on either line means no frame
  // is ever painted, and a Flutter web build shows its splash until the first
  // frame arrives — so a missing plugin turned into an app that hangs on the
  // splash screen with no error on screen to explain it.
  try {
    await ImageLibrary.initialize();
    await FontLibrary.initialize();
  } catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'mockmyapp',
        context: ErrorDescription('initialising storage before startup'),
      ),
    );
  }

  // The OFL asks for the bundled fonts' licence to travel with them. Nothing
  // is read until the licence page opens.
  registerBundledFontLicences();

  runApp(const ProviderScope(child: MockMyApp()));
}
