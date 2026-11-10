import 'studio_fonts.dart' show kBundledFonts;

/// What a face *looks* like, for the picker's filter chips.
///
/// Deliberately not a statement about where a font came from — an uploaded face
/// has no category and is grouped by ownership instead, under "Your fonts". A
/// `custom` value here would conflate the two questions and make the chips mean
/// two different things at once.
///
/// Never serialised anywhere: it exists only to narrow a list on screen, which
/// is why adding [monospace] cost nothing but a switch arm in the picker.
enum FontCategory { sansSerif, serif, display, handwriting, monospace }

class FontEntry {
  const FontEntry(this.family, this.category, {this.popular = false});

  /// Exactly as `GoogleFonts.asMap()` and [kBundledFonts] spell it. A typo
  /// here does not throw — the resolver is total — it silently renders Roboto
  /// instead, which is why `font_catalog_test.dart` checks every entry against
  /// both.
  final String family;

  final FontCategory category;

  /// Offered in the caption panel's quick strip without opening the picker.
  ///
  /// A dozen or so spread across the categories, not a ranking: the strip is a
  /// shortcut to the faces most people reach for first, and it shares its space
  /// with the user's own recents and uploads, so a long tail here would only
  /// push those off the end of the row.
  final bool popular;
}

/// The families the picker offers: exactly the Google families bundled with
/// the app ([kBundledFonts]), so every row previews in its own face without a
/// download, on a machine that has never been online.
///
/// A face that is not here is one upload away: the picker's "Upload a font"
/// takes any TrueType or OpenType file, and it stays on the device. Adding a
/// family for everybody is `tool/bundle_google_fonts.py`, then a row here and
/// in [kBundledFonts]; `font_catalog_test.dart` fails until all three agree.
///
/// Ordered by category and then roughly by familiarity inside it, because the
/// picker renders the list in this order and there is nothing else to sort by
/// that a user would recognise.
const fontCatalog = [
  // ── Sans serif ──────────────────────────────────────────────────────────
  FontEntry('Roboto', FontCategory.sansSerif, popular: true),
  FontEntry('Inter', FontCategory.sansSerif, popular: true),
  FontEntry('Montserrat', FontCategory.sansSerif, popular: true),
  FontEntry('Poppins', FontCategory.sansSerif, popular: true),
  FontEntry('Figtree', FontCategory.sansSerif, popular: true),
  FontEntry('Urbanist', FontCategory.sansSerif),

  // ── Serif ───────────────────────────────────────────────────────────────
  FontEntry('Playfair Display', FontCategory.serif, popular: true),
  FontEntry('Lora', FontCategory.serif),

  // ── Display ─────────────────────────────────────────────────────────────
  FontEntry('Oswald', FontCategory.display, popular: true),
  FontEntry('Bebas Neue', FontCategory.display, popular: true),
  FontEntry('Anton', FontCategory.display, popular: true),
  FontEntry('Abril Fatface', FontCategory.display, popular: true),
  FontEntry('Archivo Black', FontCategory.display),

  // ── Handwriting ─────────────────────────────────────────────────────────
  FontEntry('Dancing Script', FontCategory.handwriting, popular: true),
  FontEntry('Pacifico', FontCategory.handwriting, popular: true),
  FontEntry('Lobster', FontCategory.handwriting, popular: true),

  // ── Monospace ───────────────────────────────────────────────────────────
  // A caption is not code, so this exists for a narrower reason: a screenshot
  // of a terminal, an API key, a version string — the places where even
  // spacing is the point rather than a style.
  FontEntry('JetBrains Mono', FontCategory.monospace, popular: true),
];
