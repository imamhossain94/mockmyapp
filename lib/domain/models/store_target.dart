import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../data/assets/frame_catalog.dart';
import '../../data/assets/studio_frames.dart';
import 'export_format.dart';

/// A catalog frame named by id, for a target that knows what it wants to open
/// in without consulting the loaded catalog.
typedef FrameRef = (String deviceId, String variantId);

/// Which console a target's artwork is uploaded to — or, for [social], which
/// kind of surface outside the stores it is posted on.
///
/// Persisted only indirectly — a [SubProject] stores a [StoreTarget.id], never
/// this — so entries can be reordered freely.
enum StoreKind {
  appStore,
  playStore,
  macAppStore,
  microsoftStore,
  chromeWebStore,
  huaweiAppGallery,
  galaxyStore,

  /// Link previews, social posts and launch sites: Open Graph, X, LinkedIn,
  /// Product Hunt. Not a store, but the same kind of deliverable — an exact
  /// canvas with a file-size cap — made at the same moment as the listing.
  social,
}

/// What a target's screenshots depict.
///
/// Drives two things and nothing else: which device frames the picker offers,
/// and what a freshly seeded screen looks like. [graphic] is the odd one — a
/// Play feature graphic is a banner rather than a screenshot, so it gets no
/// frame and no orientation of its own.
enum TargetFormFactor { phone, tablet, desktop, graphic, watch }

/// The [CanvasPreset.id] a set carries once its canvas is a size of the user's
/// own rather than one of its target's presets.
///
/// A reserved value of the existing `presetId` field rather than a new field,
/// so nothing is written for a set that never had a custom size and every
/// saved document reads back byte for byte. [SubProject.canvas] has always
/// been the source of truth over the preset; a custom size just stops
/// pretending there is a preset behind it. A build that predates this resolves
/// the id like any other it does not know — to the target's default row in the
/// picker — and keeps the stored canvas, which is the property that matters.
const kCustomPresetId = 'custom';

/// One canvas a store will accept, in export pixels.
class CanvasPreset {
  const CanvasPreset({
    required this.id,
    required this.label,
    required this.size,
    this.note,
  });

  /// The row a custom-sized set shows in place of a preset.
  CanvasPreset.custom(this.size)
    : id = kCustomPresetId,
      label = 'Custom size',
      note = null;

  /// The smallest side a custom canvas may have, in pixels. Below the
  /// smallest canvas any target here asks for, the 240 px Product Hunt
  /// thumbnail, with room to spare.
  static const int customMin = 100;

  /// The largest side a custom canvas may have: Play's limit for tablet
  /// screenshots, and the most any console in the table takes. The renderer
  /// captures at four times the laid-out size, so this is also a memory bound.
  static const int customMax = 7680;

  /// Stable and persisted — renaming one silently re-points every document
  /// that chose it.
  final String id;

  /// Short human label, e.g. `6.9" display`.
  final String label;

  /// What the store says about this particular size — "required base",
  /// "accepted fallback", "minimum". Null when there is nothing to add.
  final String? note;

  final Size size;

  bool get isLandscape => size.width > size.height;

  /// `1320 × 2868` — for the mono readouts that show a canvas to the user.
  String get sizeLabel => '${size.width.round()} × ${size.height.round()}';
}

/// Which canvas sizes a target's console takes.
enum SizePolicy {
  /// Only the preset sizes, exactly as listed: Apple's Mac and TV classes, the
  /// Play feature graphic, the Chrome Web Store's two sizes.
  presets,

  /// Only the preset sizes, but in either orientation. Apple accepts every
  /// iPhone and iPad size turned on its side, and listing all of those as
  /// presets would double a picker for a choice almost nobody makes.
  presetsEitherWay,

  /// Anything inside the [StoreRules]' bounds. Play, Huawei and the Microsoft
  /// Store publish limits rather than a list of sizes.
  bounds,
}

/// A console's published rules for one slot, in a form the export checker can
/// test a file against.
///
/// These replaced a single display line per target, which said the same
/// things in prose and was enforced by nothing: a 2× export, a JPG for the
/// PNG-only Microsoft Store or a twelfth screenshot for an eight-slot listing
/// all went out without a word. `StoreValidator` reads these; [describe] is
/// the line the canvas pickers still show, now generated from the same
/// numbers so the two cannot disagree.
class StoreRules {
  const StoreRules({
    this.formats = const {ExportFormat.png, ExportFormat.jpg},
    this.alphaAllowed = false,
    this.maxBytes,
    this.minCount = 1,
    this.maxCount,
    this.recommendedCount,
    this.sizes = SizePolicy.presets,
    this.minShortSide,
    this.maxShortSide,
    this.minLongSide,
    this.maxLongSide,
    this.maxAspect,
    this.aspect,
    this.source,
    this.note,
    this.contentRule,
  });

  /// The file types the console takes.
  final Set<ExportFormat> formats;

  /// Whether a file may carry transparency. Exports are always flattened onto
  /// white (`encodeExport`), so this only ever decides whether the checklist
  /// says so.
  final bool alphaAllowed;

  /// The largest file the console takes, in bytes, or null when it states no
  /// cap. Counted in thousands, never 1024s, so a file the checker passes is
  /// under the cap whichever way the console happens to count.
  final int? maxBytes;

  /// How many images one listing slot takes: at least [minCount], at most
  /// [maxCount] (null for no stated limit).
  final int minCount;
  final int? maxCount;

  /// The count below which the console accepts a set but does less with it —
  /// Play's large-screen promotion wants four. Null when there is none.
  final int? recommendedCount;

  final SizePolicy sizes;

  /// Bounds on the short and long side in pixels, whatever the orientation.
  /// Read only under [SizePolicy.bounds].
  final int? minShortSide;
  final int? maxShortSide;
  final int? minLongSide;
  final int? maxLongSide;

  /// The most elongated a canvas may be, long side over short — Play's "the
  /// long side must not be more than twice the short side" is 2.
  final double? maxAspect;

  /// The exact proportion the console demands, width over height, within 1%:
  /// 16:9 for an In-App Event card, 9:16 for its details page.
  final double? aspect;

  /// Who sets these rules, when it is not the target's store — "LinkedIn",
  /// "Product Hunt" — for the checklist's sentences.
  final String? source;

  /// Anything else the console says that the checker cannot test, shown at
  /// the end of the [describe] line.
  final String? note;

  /// A rule about what the artwork may show, which only a person can check —
  /// "no text, app UI or devices". The checklist shows it as a reminder.
  final String? contentRule;

  /// The rules as one line, for the foot of a canvas picker: `PNG or JPEG · no
  /// alpha · up to 10 MB · up to 10 per listing · sRGB`.
  String describe() => [
    switch (formats.length) {
      1 => '${_formatName(formats.single)} only',
      _ => 'PNG or JPEG',
    },
    if (!alphaAllowed) 'no alpha',
    ?_sizeLabel,
    if (maxBytes case final cap?) 'up to ${formatBytes(cap)}',
    ?_countLabel,
    ?note,
    ?contentRule,
  ].join(' · ');

  static String _formatName(ExportFormat format) =>
      format == ExportFormat.jpg ? 'JPEG' : format.label;

  String? get _countLabel {
    final max = maxCount;
    if (max == 1) return 'exactly one';
    if (max == null) return minCount > 1 ? 'at least $minCount' : null;
    if (minCount <= 1) return 'up to $max per listing';
    return '$minCount–$max per listing';
  }

  String? get _sizeLabel {
    if (sizes != SizePolicy.bounds) return null;
    final parts = <String>[];
    if (aspect case final r?) {
      // Long sides, implied from whichever bound was stated.
      final stretch = r >= 1 ? r : 1 / r;
      final minLong =
          minLongSide ??
          (minShortSide == null ? null : (minShortSide! * stretch).round());
      final maxLong =
          maxLongSide ??
          (maxShortSide == null ? null : (maxShortSide! * stretch).round());
      String dims(int long) => r >= 1
          ? '$long × ${(long / r).round()}'
          : '${(long * r).round()} × $long';
      parts.add(switch ((minLong, maxLong)) {
        (final lo?, final hi?) =>
          '${ratioLabel(r)}, ${dims(lo)} to ${dims(hi)}',
        (final lo?, null) => '${ratioLabel(r)}, ${dims(lo)} or larger',
        (null, final hi?) => '${ratioLabel(r)}, up to ${dims(hi)}',
        _ => ratioLabel(r),
      });
    } else if (minLongSide != null && minShortSide != null) {
      parts.add('$minLongSide × $minShortSide or larger');
      if (maxLongSide != null && maxShortSide != null) {
        parts.add('up to $maxLongSide × $maxShortSide');
      } else if (maxLongSide != null) {
        parts.add('sides up to $maxLongSide px');
      }
    } else {
      final lo = minShortSide, hi = maxLongSide;
      if (lo != null && hi != null) {
        parts.add('sides $lo–$hi px');
      } else if (lo != null) {
        parts.add('sides at least $lo px');
      } else if (hi != null) {
        parts.add('sides up to $hi px');
      }
    }
    if (maxAspect case final m?) parts.add('at most ${ratioLabel(m)}');
    return parts.isEmpty ? null : parts.join(', ');
  }
}

/// [ratio] as the store writes it — `16:9`, `9:16`, `8:5`, `2:1` — or to two
/// decimals when no small whole numbers make it.
String ratioLabel(double ratio) {
  for (var d = 1; d <= 20; d++) {
    final n = ratio * d;
    if ((n - n.roundToDouble()).abs() < 0.01) return '${n.round()}:$d';
  }
  return ratio.toStringAsFixed(2);
}

/// [bytes] as a person reads a size: `10 MB`, `1024 KB`, `3.5 MB`.
///
/// A store's round caps print as written. Any other size rounds *up*, so a file
/// a few bytes over a 2 MB cap reads "2.1 MB" rather than a "2.0 MB" that
/// looks as if it fits.
String formatBytes(int bytes) {
  const kb = 1000, mb = 1000 * 1000;
  if (bytes >= mb && bytes % mb == 0) return '${bytes ~/ mb} MB';
  if (bytes % kb == 0 && bytes <= 2 * mb) return '${bytes ~/ kb} KB';
  if (bytes >= mb) return '${(bytes / (mb / 10)).ceil() / 10} MB';
  return '${(bytes / kb).ceil()} KB';
}

/// A store listing slot: one device class at one console, with the canvases it
/// accepts.
class StoreTarget {
  const StoreTarget({
    required this.id,
    required this.label,
    required this.storeLabel,
    required this.store,
    required this.formFactor,
    required this.framePlatform,
    required this.rules,
    required this.presets,
    this.defaultFrame,
    this.shortName,
  });

  /// Stable and persisted. See [CanvasPreset.id].
  final String id;

  /// The device class — `iPhone`, `Android tablet`, `Feature graphic`.
  final String label;

  /// What a tag too narrow for [label] calls this target, when the default
  /// reading in [shortLabel] would be wrong — a Play icon is not a "Feature".
  final String? shortName;

  /// [label] with the console dropped, for a tag too narrow to hold it.
  ///
  /// "Android phone" and "Android tablet" both ellipsise to "Andr…" in a
  /// library card, which tells the reader nothing and tells them it twice. The
  /// store is either shown beside the tag or irrelevant to it, so the word that
  /// survives is the one that distinguishes the two.
  String get shortLabel => switch (formFactor) {
    TargetFormFactor.phone => store == StoreKind.playStore ? 'Phone' : label,
    TargetFormFactor.tablet => store == StoreKind.playStore ? 'Tablet' : label,
    // Apple's header and search artwork is a graphic too, and "Feature" is
    // Google's word for Google's banner.
    TargetFormFactor.graphic =>
      shortName ?? (store == StoreKind.playStore ? 'Feature' : 'Creative'),
    TargetFormFactor.desktop || TargetFormFactor.watch => shortName ?? label,
  };

  /// The console — `App Store`, `Google Play`, `Microsoft Store`.
  final String storeLabel;

  final StoreKind store;
  final TargetFormFactor formFactor;

  /// Which half of the frame catalog this target's screens can wear, or null
  /// when the catalog has nothing to offer it.
  ///
  /// Null is the honest answer for desktop and for the feature graphic: the
  /// catalog's phones are handsets, and wrapping a 16:10 Mac screenshot in a
  /// phone bezel is worse than wrapping it in nothing. Screens seeded for a
  /// null-platform target start frameless — see `ProjectStore.createProject`.
  final FramePlatform? framePlatform;

  /// The console's rules for this slot — formats, transparency, file size,
  /// counts and sizes — which the export checker tests every store export
  /// against.
  final StoreRules rules;

  /// The store's format rules, as one display line. Shown under the preset
  /// list so the numbers and the constraints arrive together. Generated from
  /// [rules], so what the picker says is what the checker enforces.
  String get requirements => rules.describe();

  /// Who the checklist says sets this slot's rules: the store, or for a
  /// social target the site itself.
  String get rulesBy => rules.source ?? storeLabel;

  /// Accepted canvases, best first. [defaultPreset] takes the head, so the
  /// order here is the recommendation.
  final List<CanvasPreset> presets;

  /// Every size the console accepts, when it accepts a list rather than a
  /// range — the presets, turned on their side as well where
  /// [SizePolicy.presetsEitherWay] says so. Null under [SizePolicy.bounds].
  ///
  /// Derived rather than declared, because a second copy of these numbers is
  /// a second chance for them to disagree with the presets above.
  List<Size>? get exactSizes => switch (rules.sizes) {
    SizePolicy.bounds => null,
    SizePolicy.presets => [for (final p in presets) p.size],
    // A set rather than a list, because the iPhone table already carries
    // some landscapes as presets of their own.
    SizePolicy.presetsEitherWay => {
      for (final p in presets) ...[p.size, p.size.flipped],
    }.toList(),
  };

  /// The frame a screen on this target starts in, when the target knows better
  /// than the user's handset pick does.
  ///
  /// Set on every target the drawn bodies in `studio_frames.dart` cover: an
  /// iPad set opens in an iPad, a Mac set in a MacBook, a Web set in a browser
  /// window. Null on the two handset targets, which take whatever device the
  /// new-project form's frame picker resolved — that picker is a *handset*
  /// picker, and it has nothing useful to say about a Mac.
  ///
  /// Null also on the feature graphic, which is a banner. Wrapping it in a
  /// device would be wrapping the artwork in the thing the artwork is about.
  ///
  /// Named by id rather than resolved here so `ProjectStore` can seed a screen
  /// without the catalog loaded; both halves are resolved leniently downstream.
  final FrameRef? defaultFrame;

  /// Whether the frame catalog has anything appropriate to offer this target.
  bool get wearsDeviceFrame => framePlatform != null;

  /// Which half of the catalog the frame picker opens on.
  ///
  /// Unlike [framePlatform] this always answers, because the picker has to show
  /// *something* even for a target that starts frameless — a Mac screenshot the
  /// user decides to put in a phone after all is a choice, not a mistake to
  /// prevent. Apple's consoles get Apple hardware; everything else gets
  /// Android's.
  FramePlatform get catalogPlatform =>
      framePlatform ??
      (store == StoreKind.appStore || store == StoreKind.macAppStore
          ? FramePlatform.ios
          : FramePlatform.android);

  /// How many screens a new sub-project starts with.
  ///
  /// A feature graphic is one banner by definition — Google accepts exactly one
  /// per listing — so seeding it with a set of three would be seeding two
  /// deliverables that cannot be uploaded.
  int get starterScreenCount => formFactor == TargetFormFactor.graphic ? 1 : 3;

  /// The most screens this app will seed a set with unprompted.
  ///
  /// Above the eight Play accepts and below anything that would make the
  /// project screen a wall of blanks. Only a template can reach it — the plain
  /// starter is always [starterScreenCount].
  static const int maxStarterScreens = 12;

  /// How many screens to seed when a listing template is coming with them.
  ///
  /// A template is a *sequence* of designs — an opener, several feature
  /// screens, a closing card — and seeding three screens for an eight-screen
  /// listing threw five of those designs away before the user ever saw them.
  /// So the set is created at the template's own length.
  ///
  /// Never fewer than [starterScreenCount], because a short template is a
  /// reason to repeat its designs rather than to hand over a smaller project
  /// than the form would otherwise have made. And never for a feature graphic,
  /// which is exactly one image whatever else is going on.
  int screenCountFor(int? templateScreens) {
    if (formFactor == TargetFormFactor.graphic) return 1;
    if (templateScreens == null) return starterScreenCount;
    return templateScreens.clamp(starterScreenCount, maxStarterScreens);
  }

  CanvasPreset get defaultPreset => presets.first;

  CanvasPreset? presetById(String id) =>
      presets.where((p) => p.id == id).firstOrNull;

  /// The preset [id] names, or [defaultPreset] when it names nothing.
  ///
  /// A document that chose a preset a later build dropped keeps its own stored
  /// canvas — this only decides which row the picker ticks.
  CanvasPreset resolvePreset(String id) => presetById(id) ?? defaultPreset;
}

/// Bytes in the stores' own units: thousands, not 1024s. See
/// [StoreRules.maxBytes].
const int _kb = 1000;
const int _mb = 1000 * _kb;

/// Apple's rules for every screenshot class, from App Store Connect's
/// screenshot specifications: one to ten per device class and locale, PNG or
/// JPEG, no transparency. The 10 MB cap is the figure this table has always
/// carried; Apple's page prints none, so it errs on the safe side.
const _appleScreens = StoreRules(
  maxBytes: 10 * _mb,
  maxCount: 10,
  sizes: SizePolicy.presetsEitherWay,
  note: 'sRGB',
);

/// Play's rules for phone screenshots: JPEG or 24-bit PNG with no alpha, 8 MB
/// each, two to eight, sides 320–3840 px and the long side no more than twice
/// the short one. Four or more are needed for Play's promotional placements.
const _playScreens = StoreRules(
  maxBytes: 8 * _mb,
  minCount: 2,
  maxCount: 8,
  recommendedCount: 4,
  sizes: SizePolicy.bounds,
  minShortSide: 320,
  maxLongSide: 3840,
  maxAspect: 2,
);

/// Play's rules for tablet and Chromebook screenshots: the phone rules, but
/// sides up to 7680 px, and optional — a listing without them is not refused,
/// it just is not promoted on large screens.
const _playLargeScreens = StoreRules(
  maxBytes: 8 * _mb,
  maxCount: 8,
  recommendedCount: 4,
  sizes: SizePolicy.bounds,
  minShortSide: 320,
  maxLongSide: 7680,
  maxAspect: 2,
);

/// AppGallery's rules. Third-party figures — Huawei's own page needs a login
/// and JavaScript — so worth checking in AppGallery Connect: three to eight
/// for an Android app (HarmonyOS apps take three to five), 2 MB each, sides
/// 320–3840 px. An uncompressed PNG can pass 2 MB at 1080 × 1920, which is the
/// cap the checker most often catches.
const _huaweiScreens = StoreRules(
  alphaAllowed: true,
  maxBytes: 2 * _mb,
  minCount: 3,
  maxCount: 8,
  sizes: SizePolicy.bounds,
  minShortSide: 320,
  maxLongSide: 3840,
  note: 'HarmonyOS apps take 3–5',
);

/// Every store target the app can produce artwork for.
///
/// The single table of published store requirements. It used to be four sizes
/// hard-coded inside the new-project form, then four inside `StoreCanvas`;
/// keeping them in one place is the property worth preserving, because a second
/// copy of these numbers is a second chance for them to disagree.
///
/// Sizes and rules come from each console's own documentation as of October
/// 2026 (`docs/research/2026-10-02/store-specs.md` lists the pages). Huawei's,
/// and X's, are third-party readings and the most worth re-checking against
/// the console before a release.
abstract final class StoreTargets {
  static const iphone = StoreTarget(
    id: 'ios-iphone',
    label: 'iPhone',
    storeLabel: 'App Store',
    store: StoreKind.appStore,
    formFactor: TargetFormFactor.phone,
    framePlatform: FramePlatform.ios,
    rules: _appleScreens,
    presets: [
      // The 6.9-inch class is the master source App Store Connect asks for.
      // Everything smaller is downscaled from it automatically, so the smaller
      // classes at the end of the list are optional — for a listing that wants
      // a set composed for a smaller phone rather than scaled down to it.
      CanvasPreset(
        id: 'iphone-6-9',
        label: '6.9" display',
        note: 'Required base',
        size: Size(1320, 2868),
      ),
      CanvasPreset(
        id: 'iphone-6-9-2796',
        label: '6.9" display',
        note: 'Accepted variant',
        size: Size(1290, 2796),
      ),
      CanvasPreset(
        id: 'iphone-6-9-2736',
        label: '6.9" display',
        note: 'Accepted variant',
        size: Size(1260, 2736),
      ),
      CanvasPreset(
        id: 'iphone-6-9-landscape',
        label: '6.9" landscape',
        size: Size(2868, 1320),
      ),
      CanvasPreset(
        id: 'iphone-6-9-landscape-2796',
        label: '6.9" landscape',
        note: 'Accepted variant',
        size: Size(2796, 1290),
      ),
      // Demanded as the master source only when no 6.9-inch set is supplied.
      CanvasPreset(
        id: 'iphone-6-5',
        label: '6.5" display',
        note: 'Fallback base',
        size: Size(1284, 2778),
      ),
      CanvasPreset(
        id: 'iphone-6-5-2688',
        label: '6.5" display',
        note: 'Accepted variant',
        size: Size(1242, 2688),
      ),
      CanvasPreset(
        id: 'iphone-6-5-landscape',
        label: '6.5" landscape',
        size: Size(2778, 1284),
      ),
      CanvasPreset(
        id: 'iphone-6-3',
        label: '6.3" display',
        note: 'Optional',
        size: Size(1206, 2622),
      ),
      // Apple lists 1179 × 2556 as a 6.3-inch size. It was labelled 6.1" here
      // until October 2026; the id stays, because documents saved with it
      // must go on resolving to the same canvas.
      CanvasPreset(
        id: 'iphone-6-1',
        label: '6.3" display',
        note: 'Optional · accepted variant',
        size: Size(1179, 2556),
      ),
      CanvasPreset(
        id: 'iphone-6-1-2532',
        label: '6.1" display',
        note: 'Optional',
        size: Size(1170, 2532),
      ),
      CanvasPreset(
        id: 'iphone-6-1-2436',
        label: '6.1" display',
        note: 'Optional · accepted variant',
        size: Size(1125, 2436),
      ),
      CanvasPreset(
        id: 'iphone-6-1-2340',
        label: '6.1" display',
        note: 'Optional · accepted variant',
        size: Size(1080, 2340),
      ),
      CanvasPreset(
        id: 'iphone-5-5',
        label: '5.5" display',
        note: 'Optional · home-button iPhones',
        size: Size(1242, 2208),
      ),
    ],
  );

  /// The folding iPhone, open: a book-style inner display at 1.42:1.
  ///
  /// Apple lists the iPhone Duo's two displays as two screenshot sizes of
  /// their own, so they are two targets here, each opening in the body it
  /// shows — an open foldable for this one, the closed phone for
  /// [iphoneDuoOuter]. A tablet as far as this table is concerned: the canvas
  /// is squarer than any phone's, and a listing template's drawn handset has
  /// no business on it.
  static const iphoneDuoInner = StoreTarget(
    id: 'ios-iphone-duo-inner',
    label: 'iPhone Duo inner',
    storeLabel: 'App Store',
    store: StoreKind.appStore,
    formFactor: TargetFormFactor.tablet,
    framePlatform: FramePlatform.ios,
    rules: _appleDuoScreens,
    presets: [
      CanvasPreset(
        id: 'iphone-duo-inner',
        label: 'Inner display',
        note: 'Unfolded, portrait',
        size: Size(2007, 2853),
      ),
      CanvasPreset(
        id: 'iphone-duo-inner-landscape',
        label: 'Inner landscape',
        note: 'Unfolded, as it is held',
        size: Size(2853, 2007),
      ),
    ],
    defaultFrame: (StudioFrameIds.iphoneDuoOpen, 'black'),
  );

  /// The folding iPhone, closed: the 5.4-inch outer display.
  static const iphoneDuoOuter = StoreTarget(
    id: 'ios-iphone-duo-outer',
    label: 'iPhone Duo outer',
    storeLabel: 'App Store',
    store: StoreKind.appStore,
    formFactor: TargetFormFactor.phone,
    framePlatform: FramePlatform.ios,
    rules: _appleDuoScreens,
    presets: [
      CanvasPreset(
        id: 'iphone-duo-outer',
        label: 'Outer display',
        note: 'Folded',
        size: Size(1398, 2034),
      ),
      CanvasPreset(
        id: 'iphone-duo-outer-landscape',
        label: 'Outer landscape',
        size: Size(2034, 1398),
      ),
    ],
    defaultFrame: (StudioFrameIds.iphoneDuoCover, 'black'),
  );

  /// Both iPhone Duo displays: Apple's screenshot rules, uploads not open yet.
  static const _appleDuoScreens = StoreRules(
    maxBytes: 10 * _mb,
    maxCount: 10,
    sizes: SizePolicy.presetsEitherWay,
    note: 'sRGB · App Store Connect opens iPhone Duo uploads later in 2026',
  );

  /// Apple's creative assets: artwork that is not a screenshot — the header
  /// at the top of the product page, the card in search results, and one
  /// universal design that serves both.
  ///
  /// Sizes are Apple's own templates (published August 2026, from WWDC26):
  /// upload opens with the Asset Library in App Store Connect this fall. A
  /// graphic rather than a set, like Play's feature graphic — one image per
  /// placement.
  static const appStoreCreative = StoreTarget(
    id: 'ios-creative-assets',
    label: 'Creative assets',
    storeLabel: 'App Store',
    store: StoreKind.appStore,
    formFactor: TargetFormFactor.graphic,
    framePlatform: null,
    rules: StoreRules(
      maxCount: 1,
      note:
          "Apple's templates · keep key art in the centre safe area · "
          'uploads open with the Asset Library',
      contentRule: "No prices, URLs, awards or other platforms' names",
    ),
    presets: [
      CanvasPreset(
        id: 'creative-header',
        label: 'Product page header',
        note: 'The top of the product page',
        size: Size(3840, 1646),
      ),
      CanvasPreset(
        id: 'creative-search',
        label: 'Search results',
        note: '3:2 · the Apple Ads size too',
        size: Size(3840, 2560),
      ),
      CanvasPreset(
        id: 'creative-universal',
        label: 'Universal',
        note: 'One design for header and search · 16:9',
        size: Size(5244, 2950),
      ),
    ],
  );

  /// The card an In-App Event shows in search, on the Today tab and on the
  /// product page.
  ///
  /// A target of its own rather than a preset beside [appStoreEventPage]: an
  /// event needs both images, and a project holds one set per target. Apple
  /// takes any 16:9 size between the two presets.
  static const appStoreEventCard = StoreTarget(
    id: 'ios-event-card',
    label: 'In-App Event card',
    shortName: 'Event card',
    storeLabel: 'App Store',
    store: StoreKind.appStore,
    formFactor: TargetFormFactor.graphic,
    framePlatform: null,
    rules: StoreRules(
      alphaAllowed: true,
      maxCount: 1,
      sizes: SizePolicy.bounds,
      aspect: 16 / 9,
      minShortSide: 1080,
      maxLongSide: 3840,
      note: 'Event name 30 characters, short description 50',
    ),
    presets: [
      CanvasPreset(
        id: 'event-card',
        label: 'Event card',
        note: 'Smallest accepted · 16:9',
        size: Size(1920, 1080),
      ),
      CanvasPreset(
        id: 'event-card-4k',
        label: 'Event card',
        note: 'Largest accepted',
        size: Size(3840, 2160),
      ),
    ],
  );

  /// The full-screen image at the top of an In-App Event's details page.
  static const appStoreEventPage = StoreTarget(
    id: 'ios-event-details',
    label: 'In-App Event page',
    shortName: 'Event page',
    storeLabel: 'App Store',
    store: StoreKind.appStore,
    formFactor: TargetFormFactor.graphic,
    framePlatform: null,
    rules: StoreRules(
      alphaAllowed: true,
      maxCount: 1,
      sizes: SizePolicy.bounds,
      aspect: 9 / 16,
      minShortSide: 1080,
      maxLongSide: 3840,
      note: 'Long description 120 characters',
    ),
    presets: [
      CanvasPreset(
        id: 'event-details',
        label: 'Details page',
        note: 'Smallest accepted · 9:16',
        size: Size(1080, 1920),
      ),
      CanvasPreset(
        id: 'event-details-4k',
        label: 'Details page',
        note: 'Largest accepted',
        size: Size(2160, 3840),
      ),
    ],
  );

  static const appleWatch = StoreTarget(
    id: 'apple-watch',
    label: 'Apple Watch',
    storeLabel: 'App Store',
    store: StoreKind.appStore,
    formFactor: TargetFormFactor.watch,
    // No watch in the frame catalog, and a watch listing is the app's own face
    // edge to edge anyway.
    framePlatform: null,
    rules: StoreRules(
      maxBytes: 10 * _mb,
      maxCount: 10,
      note: 'sRGB · one size for every watch in the set',
    ),
    presets: [
      CanvasPreset(
        id: 'watch-ultra-3',
        label: 'Ultra 3 & 4',
        note: 'Largest',
        size: Size(422, 514),
      ),
      CanvasPreset(
        id: 'watch-ultra',
        label: 'Ultra & Ultra 2',
        size: Size(410, 502),
      ),
      CanvasPreset(
        id: 'watch-series-10',
        label: 'Series 10–12',
        size: Size(416, 496),
      ),
      CanvasPreset(
        id: 'watch-series-7',
        label: 'Series 7–9',
        size: Size(396, 484),
      ),
      CanvasPreset(
        id: 'watch-series-4',
        label: 'Series 4–6 & SE',
        size: Size(368, 448),
      ),
    ],
  );

  static const appleTv = StoreTarget(
    id: 'apple-tv',
    label: 'Apple TV',
    storeLabel: 'App Store',
    store: StoreKind.appStore,
    formFactor: TargetFormFactor.desktop,
    framePlatform: null,
    rules: _appleLandscapeScreens,
    presets: [
      CanvasPreset(id: 'tv-4k', label: '4K', size: Size(3840, 2160)),
      CanvasPreset(id: 'tv-1080', label: '1080p', size: Size(1920, 1080)),
    ],
  );

  static const visionPro = StoreTarget(
    id: 'vision-pro',
    label: 'Apple Vision Pro',
    storeLabel: 'App Store',
    store: StoreKind.appStore,
    formFactor: TargetFormFactor.desktop,
    framePlatform: null,
    rules: _appleLandscapeScreens,
    presets: [
      CanvasPreset(
        id: 'vision-4k',
        label: '3840 × 2160',
        note: 'Required size',
        size: Size(3840, 2160),
      ),
    ],
  );

  /// Apple's rules for the classes that only come landscape: TV, Vision Pro
  /// and the Mac.
  static const _appleLandscapeScreens = StoreRules(
    maxBytes: 10 * _mb,
    maxCount: 10,
    note: 'sRGB',
  );

  static const ipad = StoreTarget(
    id: 'ios-ipad',
    label: 'iPad',
    storeLabel: 'App Store',
    store: StoreKind.appStore,
    formFactor: TargetFormFactor.tablet,
    framePlatform: FramePlatform.ios,
    // Apple blocks submission of an iPadOS-supporting app with no native iPad
    // set, so this target is not optional the way the desktop ones are.
    rules: StoreRules(
      maxBytes: 10 * _mb,
      maxCount: 10,
      sizes: SizePolicy.presetsEitherWay,
      note: 'sRGB · required if the app supports iPadOS',
    ),
    presets: [
      CanvasPreset(
        id: 'ipad-13',
        label: '13" display',
        note: 'Required base',
        size: Size(2064, 2752),
      ),
      CanvasPreset(
        id: 'ipad-13-2732',
        label: '13" display',
        note: 'Accepted variant',
        size: Size(2048, 2732),
      ),
      CanvasPreset(
        id: 'ipad-13-landscape',
        label: '13" landscape',
        size: Size(2752, 2064),
      ),
      CanvasPreset(
        id: 'ipad-13-landscape-2732',
        label: '13" landscape',
        note: 'Accepted variant',
        size: Size(2732, 2048),
      ),
    ],
    defaultFrame: (StudioFrameIds.ipad, 'space-black'),
  );

  static const androidPhone = StoreTarget(
    id: 'android-phone',
    label: 'Android phone',
    storeLabel: 'Google Play',
    store: StoreKind.playStore,
    formFactor: TargetFormFactor.phone,
    framePlatform: FramePlatform.android,
    rules: _playScreens,
    presets: [
      CanvasPreset(
        id: 'android-phone-9-16',
        label: 'Portrait 9:16',
        note: 'Most common',
        size: Size(1080, 1920),
      ),
      CanvasPreset(
        id: 'android-phone-qhd',
        label: 'Portrait QHD',
        size: Size(1440, 2560),
      ),
      CanvasPreset(
        id: 'android-phone-landscape',
        label: 'Landscape 16:9',
        size: Size(1920, 1080),
      ),
      // Last, and saying why: at 2.22:1 these break Play's rule that the long
      // side be no more than twice the short one, which the export checker
      // now reports. They were offered as "modern tall displays" until
      // October 2026, and stay so that documents made at them resolve.
      CanvasPreset(
        id: 'android-phone-9-20',
        label: 'Portrait 9:20',
        note: "Over Play's 2:1 limit",
        size: Size(1080, 2400),
      ),
      CanvasPreset(
        id: 'android-phone-landscape-tall',
        label: 'Landscape 20:9',
        note: "Over Play's 2:1 limit",
        size: Size(2400, 1080),
      ),
    ],
  );

  static const androidTablet = StoreTarget(
    id: 'android-tablet',
    label: 'Android tablet',
    storeLabel: 'Google Play',
    store: StoreKind.playStore,
    formFactor: TargetFormFactor.tablet,
    framePlatform: FramePlatform.android,
    rules: StoreRules(
      maxBytes: 8 * _mb,
      maxCount: 8,
      recommendedCount: 4,
      sizes: SizePolicy.bounds,
      minShortSide: 320,
      maxLongSide: 7680,
      maxAspect: 2,
      note: 'native tablet layouts required for large screens',
    ),
    presets: [
      // 9:16 and 16:9 first: Play's large-screen promotion asks for one or the
      // other, and the 10:16 sizes below — the default until October 2026 —
      // are accepted but not eligible.
      CanvasPreset(
        id: 'android-tablet-9-16',
        label: 'Portrait 9:16',
        note: 'Large-screen promotion',
        size: Size(1440, 2560),
      ),
      CanvasPreset(
        id: 'android-tablet-16-9',
        label: 'Landscape 16:9',
        note: 'Large-screen promotion',
        size: Size(2560, 1440),
      ),
      CanvasPreset(
        id: 'android-tablet-9-16-4k',
        label: 'Portrait 9:16',
        note: '4K',
        size: Size(2160, 3840),
      ),
      CanvasPreset(
        id: 'android-tablet-16-9-4k',
        label: 'Landscape 16:9',
        note: '4K',
        size: Size(3840, 2160),
      ),
      CanvasPreset(
        id: 'android-tablet-10',
        label: '10" portrait',
        note: '10:16',
        size: Size(1600, 2560),
      ),
      CanvasPreset(
        id: 'android-tablet-7',
        label: '7" portrait',
        size: Size(1080, 1920),
      ),
      CanvasPreset(
        id: 'android-tablet-10-landscape',
        label: '10" landscape',
        note: '16:10',
        size: Size(2560, 1600),
      ),
      CanvasPreset(
        id: 'android-tablet-7-wide',
        label: '7" portrait',
        note: 'WUXGA',
        size: Size(1200, 1920),
      ),
      CanvasPreset(
        id: 'android-tablet-10-wuxga-landscape',
        label: '10" landscape',
        note: 'WUXGA',
        size: Size(1920, 1200),
      ),
      // Play has no foldable slot of its own: an open foldable's shots go in
      // with the tablets, at the size Google recommends for one.
      CanvasPreset(
        id: 'android-foldable-open',
        label: 'Foldable, open',
        note: 'Goes in the tablet slot',
        size: Size(1840, 2208),
      ),
    ],
    defaultFrame: (StudioFrameIds.androidTablet, 'space-black'),
  );

  /// The banner every Play listing has to carry, alongside its screenshots.
  ///
  /// A target rather than a preset of [androidPhone] because it is a different
  /// deliverable: one image, one exact size, no orientation, and a listing is
  /// rejected without it.
  static const playFeatureGraphic = StoreTarget(
    id: 'android-feature-graphic',
    label: 'Feature graphic',
    storeLabel: 'Google Play',
    store: StoreKind.playStore,
    formFactor: TargetFormFactor.graphic,
    framePlatform: null,
    // Play's page states no file-size cap for the feature graphic any more;
    // the 1024 KB it used to be quoted with belongs to the 512 icon.
    rules: StoreRules(
      maxCount: 1,
      contentRule: 'Keep the name, logo and words clear of the edges',
    ),
    presets: [
      CanvasPreset(
        id: 'play-feature-graphic',
        label: 'Feature graphic',
        note: 'Exact size — required on every listing',
        size: Size(1024, 500),
      ),
    ],
  );

  /// The 512-pixel listing icon Play shows beside the app's name.
  ///
  /// The artwork `fastlane supply` uploads as `icon.png`, and the icon the
  /// store preview shows when a project has one. Square and full-bleed: Play
  /// rounds the corners and adds the shadow itself.
  static const playIcon = StoreTarget(
    id: 'android-app-icon',
    label: 'App icon',
    shortName: 'Icon',
    storeLabel: 'Google Play',
    store: StoreKind.playStore,
    formFactor: TargetFormFactor.graphic,
    framePlatform: null,
    rules: StoreRules(
      formats: {ExportFormat.png},
      alphaAllowed: true,
      maxBytes: 1024 * _kb,
      maxCount: 1,
      contentRule: 'A full square: Play adds the rounded corners and shadow',
    ),
    presets: [
      CanvasPreset(
        id: 'play-icon',
        label: 'App icon',
        note: 'Exact size',
        size: Size(512, 512),
      ),
    ],
  );

  static const chromebook = StoreTarget(
    id: 'chromebook',
    label: 'Chromebook',
    storeLabel: 'Google Play',
    store: StoreKind.playStore,
    formFactor: TargetFormFactor.desktop,
    framePlatform: null,
    rules: _playLargeScreens,
    presets: [
      CanvasPreset(
        id: 'chromebook-1080',
        label: '1920 × 1080',
        size: Size(1920, 1080),
      ),
      CanvasPreset(
        id: 'chromebook-1440',
        label: '2560 × 1440',
        size: Size(2560, 1440),
      ),
    ],
    defaultFrame: (StudioFrameIds.windowsLaptop, 'space-black'),
  );

  /// Screenshots for Android XR headsets: 8:5, four to eight of them.
  static const androidXr = StoreTarget(
    id: 'android-xr',
    label: 'Android XR',
    storeLabel: 'Google Play',
    store: StoreKind.playStore,
    formFactor: TargetFormFactor.desktop,
    framePlatform: null,
    rules: StoreRules(
      maxBytes: 8 * _mb,
      minCount: 4,
      maxCount: 8,
      sizes: SizePolicy.bounds,
      aspect: 8 / 5,
      minShortSide: 1200,
      maxLongSide: 3840,
    ),
    presets: [
      CanvasPreset(
        id: 'xr-3840',
        label: '3840 × 2400',
        note: 'Recommended · 8:5',
        size: Size(3840, 2400),
      ),
      CanvasPreset(
        id: 'xr-1920',
        label: '1920 × 1200',
        note: 'Minimum',
        size: Size(1920, 1200),
      ),
    ],
  );

  static const huaweiPhone = StoreTarget(
    id: 'huawei-phone',
    label: 'Huawei phone',
    storeLabel: 'Huawei AppGallery',
    store: StoreKind.huaweiAppGallery,
    formFactor: TargetFormFactor.phone,
    framePlatform: FramePlatform.android,
    rules: _huaweiScreens,
    presets: [
      CanvasPreset(
        id: 'huawei-phone-portrait',
        label: 'Portrait',
        size: Size(1080, 1920),
      ),
      CanvasPreset(
        id: 'huawei-phone-landscape',
        label: 'Landscape',
        size: Size(1920, 1080),
      ),
    ],
  );

  static const huaweiTablet = StoreTarget(
    id: 'huawei-tablet',
    label: 'Huawei tablet',
    storeLabel: 'Huawei AppGallery',
    store: StoreKind.huaweiAppGallery,
    formFactor: TargetFormFactor.tablet,
    framePlatform: FramePlatform.android,
    rules: _huaweiScreens,
    presets: [
      CanvasPreset(
        id: 'huawei-tablet-portrait',
        label: 'Portrait',
        size: Size(1280, 1920),
      ),
      CanvasPreset(
        id: 'huawei-tablet-landscape',
        label: 'Landscape',
        size: Size(1920, 1280),
      ),
    ],
    defaultFrame: (StudioFrameIds.androidTablet, 'space-black'),
  );

  /// The hero image the Galaxy Store shows above some listings — in some
  /// countries, and mostly for games. Its screenshots are the Play phone set,
  /// which meets Samsung's rules as it is.
  static const galaxyHero = StoreTarget(
    id: 'galaxy-hero',
    label: 'Hero image',
    shortName: 'Hero',
    storeLabel: 'Galaxy Store',
    store: StoreKind.galaxyStore,
    formFactor: TargetFormFactor.graphic,
    framePlatform: null,
    rules: StoreRules(
      alphaAllowed: true,
      maxBytes: 1024 * _kb,
      maxCount: 1,
      note: 'Shown in some countries, mostly for games',
    ),
    presets: [
      CanvasPreset(
        id: 'galaxy-hero',
        label: 'Hero image',
        note: 'Exact size',
        size: Size(1200, 675),
      ),
    ],
  );

  static const mac = StoreTarget(
    id: 'mac',
    label: 'Mac',
    storeLabel: 'Mac App Store',
    store: StoreKind.macAppStore,
    formFactor: TargetFormFactor.desktop,
    framePlatform: null,
    rules: StoreRules(
      maxBytes: 10 * _mb,
      maxCount: 10,
      note: 'sRGB · one of these four sizes',
    ),
    presets: [
      CanvasPreset(
        id: 'mac-2880',
        label: '2880 × 1800',
        size: Size(2880, 1800),
      ),
      CanvasPreset(
        id: 'mac-2560',
        label: '2560 × 1600',
        size: Size(2560, 1600),
      ),
      CanvasPreset(id: 'mac-1440', label: '1440 × 900', size: Size(1440, 900)),
      CanvasPreset(id: 'mac-1280', label: '1280 × 800', size: Size(1280, 800)),
    ],
    defaultFrame: (StudioFrameIds.macbook, 'space-black'),
  );

  static const windows = StoreTarget(
    id: 'windows',
    label: 'Windows',
    storeLabel: 'Microsoft Store',
    store: StoreKind.microsoftStore,
    formFactor: TargetFormFactor.desktop,
    framePlatform: null,
    // PNG only, which the global JPG setting used to break without a word.
    rules: StoreRules(
      formats: {ExportFormat.png},
      alphaAllowed: true,
      maxBytes: 50 * _mb,
      maxCount: 10,
      recommendedCount: 4,
      sizes: SizePolicy.bounds,
      minLongSide: 1366,
      minShortSide: 768,
      maxLongSide: 3840,
      maxShortSide: 2160,
      note: 'keep key content in the top two-thirds',
    ),
    presets: [
      CanvasPreset(
        id: 'windows-1080',
        label: '1080p',
        note: 'Recommended',
        size: Size(1920, 1080),
      ),
      CanvasPreset(id: 'windows-4k', label: '4K', size: Size(3840, 2160)),
      CanvasPreset(
        id: 'windows-768',
        label: '1366 × 768',
        note: 'Minimum accepted',
        size: Size(1366, 768),
      ),
    ],
    defaultFrame: (StudioFrameIds.windowsLaptop, 'space-black'),
  );

  /// The 16:9 "super hero" art at the top of a Microsoft Store listing. A
  /// natural home for an AI background; Microsoft allows nothing else in it.
  static const microsoftHero = StoreTarget(
    id: 'ms-hero-art',
    label: 'Hero art',
    shortName: 'Hero art',
    storeLabel: 'Microsoft Store',
    store: StoreKind.microsoftStore,
    formFactor: TargetFormFactor.graphic,
    framePlatform: null,
    rules: StoreRules(
      formats: {ExportFormat.png},
      alphaAllowed: true,
      maxCount: 1,
      contentRule:
          'No text, app UI or devices · keep key art out of the bottom third',
    ),
    presets: [
      CanvasPreset(
        id: 'ms-hero-1080',
        label: '1920 × 1080',
        note: 'Smallest accepted',
        size: Size(1920, 1080),
      ),
      CanvasPreset(
        id: 'ms-hero-4k',
        label: '3840 × 2160',
        note: '4K',
        size: Size(3840, 2160),
      ),
    ],
  );

  static const web = StoreTarget(
    id: 'web',
    label: 'Web',
    storeLabel: 'Chrome Web Store',
    store: StoreKind.chromeWebStore,
    formFactor: TargetFormFactor.desktop,
    framePlatform: null,
    rules: StoreRules(
      maxCount: 5,
      note: 'square corners, full bleed · one of these two sizes',
    ),
    presets: [
      CanvasPreset(
        id: 'web-1280',
        label: '1280 × 800',
        note: 'Preferred',
        size: Size(1280, 800),
      ),
      CanvasPreset(id: 'web-640', label: '640 × 400', size: Size(640, 400)),
    ],
    defaultFrame: (StudioFrameIds.browserMac, 'mac-light'),
  );

  /// The small promo tile every Chrome Web Store listing must have.
  static const chromeSmallTile = StoreTarget(
    id: 'chrome-small-tile',
    label: 'Small promo tile',
    shortName: 'Small tile',
    storeLabel: 'Chrome Web Store',
    store: StoreKind.chromeWebStore,
    formFactor: TargetFormFactor.graphic,
    framePlatform: null,
    rules: StoreRules(maxCount: 1, note: 'required on every listing'),
    presets: [
      CanvasPreset(
        id: 'chrome-tile-440',
        label: 'Small promo tile',
        note: 'Exact size — required',
        size: Size(440, 280),
      ),
    ],
  );

  /// The wide banner the Chrome Web Store shows when it features a listing.
  static const chromeMarquee = StoreTarget(
    id: 'chrome-marquee',
    label: 'Marquee tile',
    shortName: 'Marquee',
    storeLabel: 'Chrome Web Store',
    store: StoreKind.chromeWebStore,
    formFactor: TargetFormFactor.graphic,
    framePlatform: null,
    rules: StoreRules(maxCount: 1),
    presets: [
      CanvasPreset(
        id: 'chrome-marquee-1400',
        label: 'Marquee tile',
        note: 'Exact size',
        size: Size(1400, 560),
      ),
    ],
  );

  /// The image a link to the app's site unfurls into, on Facebook, iMessage,
  /// Slack and nearly everything else that reads Open Graph tags.
  static const openGraph = StoreTarget(
    id: 'social-og',
    label: 'Open Graph',
    storeLabel: 'Social & launch',
    store: StoreKind.social,
    formFactor: TargetFormFactor.graphic,
    framePlatform: null,
    rules: StoreRules(
      alphaAllowed: true,
      maxBytes: 8 * _mb,
      maxCount: 1,
      sizes: SizePolicy.bounds,
      minShortSide: 200,
      source: 'Open Graph',
      note: '1.91:1 shows as a large card',
    ),
    presets: [
      CanvasPreset(
        id: 'og-1200',
        label: 'Link preview',
        note: 'Facebook, iMessage, Slack and most others',
        size: Size(1200, 630),
      ),
    ],
  );

  /// A 16:9 image for a launch post on X.
  static const xPost = StoreTarget(
    id: 'social-x',
    label: 'X post',
    storeLabel: 'Social & launch',
    store: StoreKind.social,
    formFactor: TargetFormFactor.graphic,
    framePlatform: null,
    rules: StoreRules(
      alphaAllowed: true,
      maxBytes: 5 * _mb,
      maxCount: 1,
      sizes: SizePolicy.bounds,
      maxLongSide: 4096,
      source: 'X',
    ),
    presets: [
      CanvasPreset(
        id: 'x-1600',
        label: 'Post image',
        note: '16:9, shown whole in the timeline',
        size: Size(1600, 900),
      ),
    ],
  );

  static const linkedIn = StoreTarget(
    id: 'social-linkedin',
    label: 'LinkedIn',
    storeLabel: 'Social & launch',
    store: StoreKind.social,
    formFactor: TargetFormFactor.graphic,
    framePlatform: null,
    rules: StoreRules(
      alphaAllowed: true,
      maxBytes: 5 * _mb,
      maxCount: 1,
      sizes: SizePolicy.bounds,
      minLongSide: 1200,
      minShortSide: 627,
      source: 'LinkedIn',
    ),
    presets: [
      CanvasPreset(
        id: 'linkedin-1200',
        label: 'Link preview',
        note: '1.91:1',
        size: Size(1200, 627),
      ),
    ],
  );

  /// The square thumbnail a Product Hunt launch is listed under.
  static const productHuntThumbnail = StoreTarget(
    id: 'producthunt-thumbnail',
    label: 'Product Hunt thumbnail',
    shortName: 'PH thumbnail',
    storeLabel: 'Social & launch',
    store: StoreKind.social,
    formFactor: TargetFormFactor.graphic,
    framePlatform: null,
    rules: StoreRules(
      alphaAllowed: true,
      maxBytes: 3 * _mb,
      maxCount: 1,
      sizes: SizePolicy.bounds,
      aspect: 1,
      minShortSide: 240,
      source: 'Product Hunt',
    ),
    presets: [
      CanvasPreset(
        id: 'ph-thumbnail',
        label: 'Thumbnail',
        note: 'Square',
        size: Size(240, 240),
      ),
    ],
  );

  /// The gallery on a Product Hunt launch page: two or more images, so a set
  /// rather than a single graphic.
  static const productHuntGallery = StoreTarget(
    id: 'producthunt-gallery',
    label: 'Product Hunt gallery',
    shortName: 'PH gallery',
    storeLabel: 'Social & launch',
    store: StoreKind.social,
    formFactor: TargetFormFactor.desktop,
    framePlatform: null,
    rules: StoreRules(
      alphaAllowed: true,
      minCount: 2,
      sizes: SizePolicy.bounds,
      minShortSide: 320,
      source: 'Product Hunt',
    ),
    presets: [
      CanvasPreset(
        id: 'ph-gallery',
        label: 'Gallery image',
        note: 'Recommended size',
        size: Size(1270, 760),
      ),
    ],
  );

  /// Every target, in the order the pickers show them, grouped by console.
  ///
  /// The two stores that demand the most work come first — each with its
  /// phone and tablet sets, then the graphics a listing carries, then the
  /// device classes fewer apps ship to — then the other stores, and last the
  /// social and launch kit, which belongs to no store at all. The pickers
  /// group by [StoreKind] in the order the kinds first appear here.
  static const List<StoreTarget> all = [
    iphone,
    ipad,
    iphoneDuoInner,
    iphoneDuoOuter,
    appStoreCreative,
    appStoreEventCard,
    appStoreEventPage,
    appleWatch,
    appleTv,
    visionPro,
    androidPhone,
    androidTablet,
    playFeatureGraphic,
    playIcon,
    chromebook,
    androidXr,
    huaweiPhone,
    huaweiTablet,
    galaxyHero,
    mac,
    windows,
    microsoftHero,
    web,
    chromeSmallTile,
    chromeMarquee,
    openGraph,
    xPost,
    linkedIn,
    productHuntThumbnail,
    productHuntGallery,
  ];

  /// The target a new project opens with, read off the machine it is being
  /// designed on.
  ///
  /// Someone screenshotting on an Android phone is overwhelmingly making a Play
  /// listing, and someone on an iPhone an App Store one — so the form opens on
  /// the one they are standing in rather than on iPhone for everybody. It is a
  /// starting tick like any other and costs one tap to change.
  ///
  /// Desktop keeps a handset rather than its own store target: a Mac set is a
  /// deliverable a minority of projects need, and defaulting to it would seed
  /// the wrong canvas for the majority who opened the app on a laptop to build
  /// a phone listing. Apple's desktops take the iPhone for the same reason
  /// their phones do.
  static StoreTarget get suggestedDefault {
    if (kIsWeb) return androidPhone;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => iphone,
      _ => androidPhone,
    };
  }

  static StoreTarget? byId(String id) =>
      all.where((t) => t.id == id).firstOrNull;

  /// [byId] with a fallback, for anything holding an id from a build that knew
  /// a target this one does not.
  static StoreTarget resolve(String id) => byId(id) ?? iphone;

  static CanvasPreset? presetIn(String targetId, String presetId) =>
      byId(targetId)?.presetById(presetId);

  /// The targets of one store, for the grouped picker.
  static List<StoreTarget> forStore(StoreKind store) =>
      all.where((t) => t.store == store).toList();

  /// The stores that have targets, in [all] order.
  static List<StoreKind> get stores {
    final seen = <StoreKind>[];
    for (final t in all) {
      if (!seen.contains(t.store)) seen.add(t.store);
    }
    return seen;
  }

  /// The `(target, preset)` a pre-sub-project document belongs to.
  ///
  /// Projects written before this model stored a `FramePlatform` and left the
  /// rest of the shape implicit in each screen's canvas, so the form factor has
  /// to be read back off the pixels. That recovery is inherited from the old
  /// `StoreCanvas.shapeOf` and works the same way: an exact match against the
  /// table first, and for a canvas that matches nothing — a hand-edited
  /// document, or one from a build that is not this one — the aspect ratio,
  /// because tablets are squarer than phones at every size either store
  /// accepts.
  ///
  /// Always answers. A migration that could fail is a migration that loses
  /// somebody's project.
  static (StoreTarget, CanvasPreset) forLegacy(
    FramePlatform platform,
    Size canvas,
  ) {
    final candidates = platform == FramePlatform.ios
        ? const [iphone, ipad]
        : const [androidPhone, androidTablet];

    for (final target in candidates) {
      for (final preset in target.presets) {
        if (preset.size.width == canvas.width &&
            preset.size.height == canvas.height) {
          return (target, preset);
        }
      }
    }

    // No exact match. In the table these documents were written against,
    // phones ran 0.462–0.5625 short/long and tablets 0.625–0.75, so the
    // midpoint of that gap separates them. (Play's 9:16 tablet presets came
    // later and never reach here: a legacy document predates them.)
    final landscape = canvas.width > canvas.height;
    final longest = landscape ? canvas.width : canvas.height;
    final shortest = landscape ? canvas.height : canvas.width;
    final tablet = longest <= 0 || shortest / longest > 0.59375;

    final target = candidates[tablet ? 1 : 0];
    final preset =
        target.presets.where((p) => p.isLandscape == landscape).firstOrNull ??
        target.defaultPreset;
    return (target, preset);
  }
}
