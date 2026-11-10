import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../repositories/font_library.dart';

/// One family bundled under `assets/google_fonts/`.
@immutable
class BundledFamily {
  const BundledFamily(this.file, this.family, this.weights);

  /// What its files start with: `PlayfairDisplay` for
  /// `PlayfairDisplay-Bold.ttf`, the name google_fonts looks for in the asset
  /// manifest. Its licence is `<file>-OFL.txt` beside them.
  final String file;

  /// The family as documents store it and google_fonts names it.
  final String family;

  /// The upright weights its files carry, lightest first. No italic is
  /// bundled; the engine slants the upright face.
  final List<FontWeight> weights;
}

/// Every family the app ships, and so every Google family it can paint.
///
/// The app never downloads a font (`allowRuntimeFetching` is off in
/// `main.dart`): a family missing here paints in [StudioFonts.fallbackFamily],
/// and the editor says so. `tool/bundle_google_fonts.py` fetches a family's
/// files and its licence; `font_catalog_test.dart` holds this table and the
/// folder to each other.
const kBundledFonts = [
  BundledFamily('AbrilFatface', 'Abril Fatface', [FontWeight.w400]),
  BundledFamily('Anton', 'Anton', [FontWeight.w400]),
  BundledFamily('ArchivoBlack', 'Archivo Black', [FontWeight.w400]),
  BundledFamily('BebasNeue', 'Bebas Neue', [FontWeight.w400]),
  BundledFamily('DancingScript', 'Dancing Script', [
    FontWeight.w400,
    FontWeight.w700,
  ]),
  BundledFamily('Figtree', 'Figtree', [FontWeight.w400, FontWeight.w700]),
  BundledFamily('Inter', 'Inter', [
    FontWeight.w400,
    FontWeight.w500,
    FontWeight.w600,
    FontWeight.w700,
  ]),
  BundledFamily('JetBrainsMono', 'JetBrains Mono', [
    FontWeight.w400,
    FontWeight.w500,
    FontWeight.w700,
  ]),
  BundledFamily('Lobster', 'Lobster', [FontWeight.w400]),
  BundledFamily('Lora', 'Lora', [FontWeight.w400, FontWeight.w700]),
  BundledFamily('Montserrat', 'Montserrat', [FontWeight.w400, FontWeight.w700]),
  BundledFamily('Oswald', 'Oswald', [FontWeight.w400, FontWeight.w700]),
  BundledFamily('Pacifico', 'Pacifico', [FontWeight.w400]),
  BundledFamily('PlayfairDisplay', 'Playfair Display', [
    FontWeight.w400,
    FontWeight.w700,
  ]),
  BundledFamily('Poppins', 'Poppins', [FontWeight.w400, FontWeight.w700]),
  BundledFamily('Roboto', 'Roboto', [FontWeight.w400, FontWeight.w700]),
  BundledFamily('Urbanist', 'Urbanist', [FontWeight.w400, FontWeight.w700]),
];

final Map<String, BundledFamily> _bundledByFamily = {
  for (final family in kBundledFonts) family.family: family,
};

bool _fontLicencesRegistered = false;

/// Adds each bundled family's licence to Flutter's licence page, which the OFL
/// asks to travel with the fonts. Idempotent; the texts are only read when the
/// page asks for them.
void registerBundledFontLicences([AssetBundle? bundle]) {
  if (_fontLicencesRegistered) return;
  _fontLicencesRegistered = true;
  final assets = bundle ?? rootBundle;
  LicenseRegistry.addLicense(() async* {
    for (final font in kBundledFonts) {
      final text = await assets.loadString(
        'assets/google_fonts/${font.file}-OFL.txt',
      );
      yield LicenseEntryWithLineBreaks(['${font.family} font'], text);
    }
  });
}

/// The one way to turn a stored family name into a text style.
///
/// Every render site calls this instead of `GoogleFonts.getFont`, and the
/// reason is that `getFont` **throws synchronously** for a family it does not
/// know — its body is `if (!fonts.containsKey(fontFamily)) throw`. Every one of
/// those call sites is inside a `build` method, none of them is guarded, and
/// the app installs no `ErrorWidget.builder`; worse, the same closure that
/// paints the editor canvas also paints the home-screen thumbnails *and* the
/// export raster, and the capture path swallows every exception and returns
/// null. So a family name the build does not recognise did not surface as an
/// error message — it surfaced as "export silently produced nothing".
///
/// Which is why the contract here is absolute: **[style] never throws, for any
/// input string, ever.** A family it cannot resolve degrades to
/// [fallbackFamily], and the editor — not the canvas — is where the user is
/// told about it, through [isMissing] and [displayName].
///
/// Three things about the implementation that are load-bearing:
///
///  * [fontWeight] picks the bundled *file*. `getFont` resolves the variant
///    file from the weight it is given (yielding a family name like
///    `Poppins_700`), and only the weights in [kBundledFonts] exist on disk:
///    asking for any other would find no file and paint in the platform face.
///    So the weight is first moved to the nearest bundled one, and the asked
///    weight and style are put back on the result, where the engine can only
///    slant an upright face or embolden a family with a single weight.
///  * The recursion into [fallbackFamily] bottoms out after exactly one hop:
///    `FontLibrary.idOf('Roboto')` is null and Roboto is bundled, so the
///    fallback call takes the Google branch and cannot recurse again.
///  * The bundled table is a map built once, so the guard is a constant-time
///    lookup — free enough to sit in the hot paint path.
abstract final class StudioFonts {
  /// What anything unresolvable paints in.
  ///
  /// Roboto rather than the platform default because it is what
  /// `CaptionSpec.fontFamily` already defaults to, so a caption that falls back
  /// looks like an unstyled caption rather than like a bug.
  static const fallbackFamily = 'Roboto';

  /// The style [family] paints with, at this weight and size.
  static TextStyle style(
    String family, {
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
    Color? color,
    Paint? foreground,
    List<Shadow>? shadows,
    TextDecoration? decoration,
    Color? decorationColor,
  }) {
    TextStyle fallback() => family == fallbackFamily
        // Last resort, and only reachable if a build of google_fonts ever drops
        // Roboto: a null family is the platform's own face, which is always
        // there and always renders something.
        ? TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            letterSpacing: letterSpacing,
            height: height,
            color: color,
            foreground: foreground,
            shadows: shadows,
            decoration: decoration,
            decorationColor: decorationColor,
          )
        : style(
            fallbackFamily,
            fontSize: fontSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            letterSpacing: letterSpacing,
            height: height,
            color: color,
            foreground: foreground,
            shadows: shadows,
            decoration: decoration,
            decorationColor: decorationColor,
          );

    if (FontLibrary.idOf(family) != null) {
      // An uploaded face whose bytes never reached the engine — a backup
      // restored on a device that does not have the file, a deleted entry, a
      // reloaded web session. Painting it would give blank space, so it takes
      // the fallback and the editor says why.
      if (!FontLibrary.isRegistered(family)) return fallback();
      return TextStyle(
        // The exact key the face was handed to [FontLoader] under. Both halves
        // of that are the same string on purpose: no mapping table to keep in
        // step, and a caption's stored value *is* the engine's lookup key.
        fontFamily: family,
        // Latin punctuation and digits still resolve when the uploaded face is
        // a partial one — an icon font, or a display face with no numerals.
        fontFamilyFallback: const [fallbackFamily],
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
        foreground: foreground,
        shadows: shadows,
        decoration: decoration,
        decorationColor: decorationColor,
      );
    }

    // A family the app does not ship — one an older build downloaded, a
    // hand-edited project, a document from a foreign source.
    final bundled = _bundledByFamily[family];
    if (bundled == null) return fallback();

    try {
      return GoogleFonts.getFont(
        family,
        fontSize: fontSize,
        fontWeight: nearestWeight(
          bundled.weights,
          fontWeight ?? FontWeight.w400,
        ),
        letterSpacing: letterSpacing,
        height: height,
        color: color,
        foreground: foreground,
        shadows: shadows,
        decoration: decoration,
        decorationColor: decorationColor,
      ).copyWith(fontWeight: fontWeight, fontStyle: fontStyle);
    } catch (_) {
      // Unreachable through the guard above, and caught anyway: the promise
      // this function makes is worth more than the one branch it costs.
      return TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
        foreground: foreground,
        shadows: shadows,
        decoration: decoration,
        decorationColor: decorationColor,
      );
    }
  }

  /// Whether [family] resolves to real glyphs right now: a registered upload,
  /// or a bundled family.
  static bool canResolve(String family) => FontLibrary.idOf(family) != null
      ? FontLibrary.isRegistered(family)
      : _bundledByFamily.containsKey(family);

  /// True when [family] is a font the person could bring back: an upload
  /// whose bytes are not registered, or a Google family the app does not
  /// ship — which they can upload themselves.
  ///
  /// Deliberately narrower than `!canResolve`: a name no font has ever had is
  /// a document from somewhere else and nothing the user can act on.
  static bool isMissing(String family) => FontLibrary.idOf(family) != null
      ? !FontLibrary.isRegistered(family)
      : !_bundledByFamily.containsKey(family) &&
            GoogleFonts.asMap().containsKey(family);

  /// The weight in [weights] closest to [wanted]. A tie goes heavier from
  /// medium up and lighter below it, as CSS matches a weight.
  @visibleForTesting
  static FontWeight nearestWeight(List<FontWeight> weights, FontWeight wanted) {
    var best = weights.first;
    for (final weight in weights.skip(1)) {
      final distance = (weight.value - wanted.value).abs();
      final bestDistance = (best.value - wanted.value).abs();
      if (distance < bestDistance ||
          (distance == bestDistance &&
              (wanted.value >= 500
                  ? weight.value > best.value
                  : weight.value < best.value))) {
        best = weight;
      }
    }
    return best;
  }

  /// What chrome calls [family].
  ///
  /// The user's own label for an uploaded font, the family name itself for a
  /// Google one, and a plain "Missing font" for an upload the library has no
  /// record of at all — because the alternative is a caption panel whose
  /// typeface row reads `user:0f3a7c1e-…`.
  static String displayName(String family) => FontLibrary.idOf(family) == null
      ? family
      : FontLibrary.labelFor(family) ?? 'Missing font';
}
