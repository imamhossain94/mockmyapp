/// How the device picker narrows the frame catalog: by what a frame depicts,
/// by who makes it, by the store a set is for, and by a typed search.
///
/// Pure Dart, no widgets, so every rule the picker shows is a rule a unit test
/// can hold still. The picker itself (`DevicePickerList`) only renders what
/// [DeviceFilter.apply] hands back.
library;

import '../../domain/models/store_target.dart';
import 'frame_catalog.dart';

/// What a frame depicts, as the picker's form-factor menu files it.
///
/// Derived from the catalog entry rather than declared on it — see [kindOf] —
/// so a regenerated manifest or a newly drawn body cannot forget to say.
enum DeviceKind {
  phone('Phones', 'phone', 'phones'),
  foldable('Foldables', 'foldable', 'foldables'),
  tablet('Tablets', 'tablet', 'tablets'),
  computer('Computers', 'computer', 'computers'),
  browser('Browser', 'browser window', 'browser windows'),
  marketing('Marketing', 'marketing frame', 'marketing frames');

  const DeviceKind(this.label, this.singular, this.plural);

  /// The menu's name for the kind.
  final String label;

  final String singular;
  final String plural;

  /// "1 tablet", "3 tablets": the noun a count of this kind takes.
  String noun(int count) => count == 1 ? singular : plural;
}

/// What [device] depicts.
///
/// The order of the tests matters. `frameStyle: 'custom'` covers both the
/// editable handsets and "Build your own", so the marketing test comes first
/// and goes by id; a foldable is tablet-shaped when open, so it is caught
/// before the form factor is consulted.
DeviceKind kindOf(FrameDevice device) {
  if (device.frameStyle == 'slab' ||
      device.id.startsWith(kCustomFrameIdPrefix)) {
    return DeviceKind.marketing;
  }
  if (device.series == 'Foldable' || device.frameStyle.startsWith('foldable')) {
    return DeviceKind.foldable;
  }
  if (device.frameStyle == 'browser') return DeviceKind.browser;
  if (device.formFactor == 'desktop') return DeviceKind.computer;
  if (device.formFactor == 'tablet') return DeviceKind.tablet;
  return DeviceKind.phone;
}

/// The makers that lead the chip row, in this order.
///
/// The three whose hardware most store listings show. Everyone else follows
/// alphabetically — see [compareMakers] — so a maker a regenerated manifest
/// adds (Huawei, realme…) slots in without anyone editing this list.
const kMakerOrder = ['Apple', 'Samsung', 'Google'];

/// The maker of a frame that depicts no one's hardware in particular — a
/// browser window, a Windows laptop, the marketing slab. Always sorted last.
const kGenericMaker = 'Generic';

/// Orders makers for the chip row and the list's headings.
///
/// Case-insensitive, because makers spell themselves their own way: `OPPO`,
/// `vivo` and `OnePlus` sorted by code unit put OPPO before OnePlus and vivo
/// after Xiaomi.
int compareMakers(String a, String b) {
  if (a == b) return 0;
  if (a == kGenericMaker) return 1;
  if (b == kGenericMaker) return -1;
  final ai = kMakerOrder.indexOf(a);
  final bi = kMakerOrder.indexOf(b);
  if (ai != -1 || bi != -1) {
    if (ai == -1) return 1;
    if (bi == -1) return -1;
    return ai.compareTo(bi);
  }
  final byName = a.toLowerCase().compareTo(b.toLowerCase());
  return byName != 0 ? byName : a.compareTo(b);
}

/// The order devices are listed in: newest first, then by name, then by id.
///
/// Total, so the list never reshuffles between two builds — Dart's sort is not
/// stable past 32 items, and the picker sorts about fifty. The id tiebreak is
/// also what puts an editable handset straight after its traced twin: they
/// share a name and a year, and `apple-…`/`samsung-…` sort before `studio-…`.
int compareDevices(FrameDevice a, FrameDevice b) {
  final byYear = b.releaseYear.compareTo(a.releaseYear);
  if (byYear != 0) return byYear;
  final byModel = a.model.toLowerCase().compareTo(b.model.toLowerCase());
  if (byModel != 0) return byModel;
  return a.id.compareTo(b.id);
}

/// The kind the picker opens on for a set made for [target].
///
/// The target's own default frame decides when it names one, which gives the
/// iPad set Tablets, the Duo sets Foldables, a Mac set Computers and the Web
/// set Browser with no table to keep in step. A handset target with no default
/// opens on Phones. Null — every kind — for the targets the catalog has nothing
/// specific for: the watch, TV, Vision Pro and the store graphics.
DeviceKind? defaultKindFor(StoreTarget target, FrameCatalog catalog) {
  if (target.defaultFrame case (final id, _)) {
    for (final device in catalog.devices) {
      if (device.id == id) return kindOf(device);
    }
  }
  return switch (target.formFactor) {
    TargetFormFactor.phone => DeviceKind.phone,
    TargetFormFactor.tablet => DeviceKind.tablet,
    _ => null,
  };
}

/// Whether a set for [target] can be limited to its own store's devices.
///
/// Only the targets that wear a handset frame: the platform split is what
/// keeps Android hardware out of an App Store listing (App Review 2.3.10). A
/// Mac, Windows or Web set has no platform of its own to hold to — its default
/// browser window is filed under iOS — and its default kind already narrows the
/// list.
bool scopesByStore(StoreTarget? target) => target?.framePlatform != null;

/// The store's name as the scope line says it: "Only App Store devices".
String storeScopeName(StoreTarget target) =>
    target.store == StoreKind.huaweiAppGallery
    ? 'AppGallery'
    : target.storeLabel;

/// True for a finish the picker does not offer unless it is already in use.
///
/// The iPhone 14 Pro Max ships each colour twice, once with a drop shadow
/// baked into the artwork. The app draws its own shadow, so the baked one
/// doubles it. The ids stay valid — documents saved with them still open.
bool isPickerHidden(FrameVariant variant) => variant.id.endsWith('---shadow');

/// The finishes the picker shows for [device]: every one but the hidden
/// ones, plus the one in use whatever it is.
List<FrameVariant> pickerVariants(
  FrameDevice device, {
  String? currentVariantId,
}) => [
  for (final variant in device.variants)
    if (!isPickerHidden(variant) || variant.id == currentVariantId) variant,
];

/// [variant]'s name without the model it repeats.
///
/// Apple's artwork names each finish after the model as well as the colour
/// ("16 - Ultramarine"), which wraps a finish tile to two lines to say what
/// the row above it already says. Display only: names are never persisted,
/// ids are.
String displayFinishName(FrameDevice device, FrameVariant variant) {
  final name = variant.name;
  final dash = name.indexOf(' - ');
  if (dash <= 0) return name;
  final prefix = name.substring(0, dash).toLowerCase();
  if (!device.model.toLowerCase().contains(prefix)) return name;
  return name.substring(dash + 3);
}

/// Lower-case letters and digits only, so "Note 20", "note20" and "NOTE-20"
/// are one string.
String normalizeSearch(String text) =>
    text.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// The words a query is matched by, each normalised. Every one has to match.
List<String> searchTokens(String query) => [
  for (final word in query.split(RegExp(r'\s+')))
    if (normalizeSearch(word) case final token when token.isNotEmpty) token,
];

/// Extra words a kind answers to, beyond its own name.
const _kindWords = <DeviceKind, List<String>>{
  DeviceKind.phone: ['phone', 'smartphone', 'mobile', 'handset'],
  DeviceKind.foldable: ['foldable', 'fold', 'flip'],
  DeviceKind.tablet: ['tablet', 'tab'],
  DeviceKind.computer: ['computer', 'desktop', 'pc'],
  DeviceKind.browser: ['browser', 'web', 'website', 'chrome', 'safari'],
  DeviceKind.marketing: ['marketing', 'generic', 'custom'],
};

final _haystacks = Expando<String>('device search text');

/// Everything a query can match [device] by, each field normalised on its
/// own and the fields separated by a space.
///
/// Normalising a field whole is what lets "note20" find "Galaxy Note 20";
/// keeping the fields apart stops a match running from the end of one into
/// the start of the next. The release year is matched separately, and only
/// whole — see [matchesSearch].
String searchText(FrameDevice device) => _haystacks[device] ??= () {
  final kind = kindOf(device);
  final words = <String>[
    device.model,
    device.maker,
    device.series,
    device.id,
    for (final variant in device.variants) variant.name,
    ...?_kindWords[kind],
    // A computer or a browser window is a Mac one or a Windows one, and
    // people search for it by that rather than by "computer".
    if (kind == DeviceKind.computer || kind == DeviceKind.browser)
      ...(device.platform == FramePlatform.ios
          ? const ['mac', 'macos']
          : const ['windows', 'chromebook']),
    // The manifest calls every pill a notch (see `studio_frames.dart`), but
    // people looking for one call it what Apple does.
    if (device.maker == 'Apple' &&
        device.cutout == 'notch' &&
        device.releaseYear >= 2022)
      'dynamic island',
  ];
  return words.map(normalizeSearch).join(' ');
}();

/// Whether every one of [tokens] matches [device].
///
/// A token matches anywhere inside a field, or as the whole release year: a
/// year matched by substring would let "20" find every 2019 device, and
/// "note 20" would turn up the Note 10.
bool matchesSearch(FrameDevice device, List<String> tokens) {
  if (tokens.isEmpty) return true;
  final haystack = searchText(device);
  final year = '${device.releaseYear}';
  return tokens.every((t) => t == year || haystack.contains(t));
}

/// One heading's worth of the picker's list.
class DeviceGroup {
  const DeviceGroup(this.label, this.devices);

  /// The heading — a maker, or a kind's name — or null for a flat list that
  /// needs none.
  final String? label;
  final List<FrameDevice> devices;
}

/// What the picker is narrowed to.
class DeviceFilter {
  const DeviceFilter({
    this.kind,
    this.maker,
    this.query = '',
    this.scope,
    this.twinPlatform,
  });

  /// Null for every kind.
  final DeviceKind? kind;

  /// Null for every maker. A maker with nothing to show under [kind] and
  /// [scope] is ignored rather than honoured with an empty list — see
  /// [DeviceFilterResult.maker].
  final String? maker;

  final String query;

  /// The platform a set is limited to while "Only {store} devices" is on,
  /// or null while it is off.
  final FramePlatform? scope;

  /// Which platform's copy of the marketing frames to show.
  ///
  /// The slab and "Build your own" exist once per platform so each half of
  /// the catalog has them, and the two copies are identical: listing both
  /// would be listing one frame twice. Null shows both.
  final FramePlatform? twinPlatform;

  DeviceFilterResult apply(FrameCatalog catalog, {String? currentDeviceId}) {
    final tokens = searchTokens(query);

    final base = [
      for (final device in catalog.devices)
        // A hidden device is still listed while it is on the screen, so the
        // picker never loses the frame a document is wearing.
        if ((!device.pickerHidden || device.id == currentDeviceId) &&
            (twinPlatform == null ||
                kindOf(device) != DeviceKind.marketing ||
                device.platform == twinPlatform))
          device,
    ]..sort(compareDevices);

    final inScope = [
      for (final device in base)
        if (scope == null || device.platform == scope) device,
    ];
    final inKind = [
      for (final device in inScope)
        if (kind == null || kindOf(device) == kind) device,
    ];

    // Judged before the query, so typing never silently swaps the maker out
    // from under the user: "pixel" with Samsung chosen is an empty Samsung
    // list that offers to widen, not a quiet jump to every maker.
    final effectiveMaker = maker != null && inKind.any((d) => d.maker == maker)
        ? maker
        : null;

    final queried = [
      for (final device in inKind)
        if (matchesSearch(device, tokens)) device,
    ];

    final makerCounts = <String, int>{
      // The chosen maker keeps its chip at zero, so the row still says what
      // the list is filtered by while a search turns up nothing there.
      ?effectiveMaker: 0,
    };
    for (final device in queried) {
      makerCounts.update(device.maker, (n) => n + 1, ifAbsent: () => 1);
    }
    final makers = makerCounts.keys.toList()..sort(compareMakers);

    final kindCounts = <DeviceKind, int>{};
    var allKinds = 0;
    for (final device in inScope) {
      if (!matchesSearch(device, tokens)) continue;
      allKinds++;
      kindCounts.update(kindOf(device), (n) => n + 1, ifAbsent: () => 1);
    }

    final visible = [
      for (final device in queried)
        if (effectiveMaker == null || device.maker == effectiveMaker) device,
    ];
    // Across every kind, a maker's phones come before its tablets and its
    // computers. By year alone, Apple's drawn Macs and iPad — dated the year
    // they were drawn — would open the Apple list above every iPhone.
    if (kind == null) {
      visible.sort((a, b) {
        final byKind = kindOf(a).index.compareTo(kindOf(b).index);
        return byKind != 0 ? byKind : compareDevices(a, b);
      });
    }

    final groups = <DeviceGroup>[];
    if (effectiveMaker == null) {
      for (final m in makers) {
        final inMaker = [
          for (final d in visible)
            if (d.maker == m) d,
        ];
        if (inMaker.isNotEmpty) groups.add(DeviceGroup(m, inMaker));
      }
    } else if (kind == null) {
      // One maker across every kind: its phones, its tablets and its
      // computers are different questions, so they get a heading each.
      for (final k in DeviceKind.values) {
        final ofKind = [
          for (final d in visible)
            if (kindOf(d) == k) d,
        ];
        if (ofKind.isNotEmpty) groups.add(DeviceGroup(k.label, ofKind));
      }
    } else if (visible.isNotEmpty) {
      groups.add(DeviceGroup(null, visible));
    }

    FrameDevice? hiddenCurrent;
    if (currentDeviceId != null &&
        !visible.any((d) => d.id == currentDeviceId)) {
      for (final device in catalog.devices) {
        if (device.id == currentDeviceId) hiddenCurrent = device;
      }
    }

    return DeviceFilterResult(
      groups: groups,
      makers: [for (final m in makers) (m, makerCounts[m]!)],
      makerTotal: queried.length,
      kindCounts: kindCounts,
      allKindsCount: allKinds,
      maker: effectiveMaker,
      hiddenCurrent: hiddenCurrent,
      searchable: effectiveMaker == null
          ? inKind.length
          : inKind.where((d) => d.maker == effectiveMaker).length,
      matchesEverywhere: tokens.isEmpty
          ? base.length
          : base.where((d) => matchesSearch(d, tokens)).length,
    );
  }
}

/// What [DeviceFilter.apply] found.
class DeviceFilterResult {
  const DeviceFilterResult({
    required this.groups,
    required this.makers,
    required this.makerTotal,
    required this.kindCounts,
    required this.allKindsCount,
    required this.maker,
    required this.hiddenCurrent,
    required this.searchable,
    required this.matchesEverywhere,
  });

  /// The list, under its headings, in display order.
  final List<DeviceGroup> groups;

  /// Every maker with a match under the kind, scope and query, in chip order,
  /// with its count — plus the chosen maker, even at zero.
  final List<(String maker, int count)> makers;

  /// The "All" chip's count: matches under the kind, scope and query.
  final int makerTotal;

  /// Matches per kind under the scope and query, for the kind menu. Kinds with
  /// none are absent.
  final Map<DeviceKind, int> kindCounts;

  /// The kind menu's "All devices" count.
  final int allKindsCount;

  /// The maker the list is filtered by, or null for all of them — null too
  /// when the one asked for has nothing under this kind and scope.
  final String? maker;

  /// The device on the active screen, when the filters leave it out of
  /// [groups]. The picker pins it above the list so it is never lost.
  final FrameDevice? hiddenCurrent;

  /// How many devices the query is searching through, for the search hint.
  final int searchable;

  /// How many devices match the query with no kind, maker or scope at all —
  /// what "Search all devices" would show.
  final int matchesEverywhere;

  /// The listed devices, in order, without their headings.
  List<FrameDevice> get devices => [for (final g in groups) ...g.devices];

  bool get isEmpty => groups.isEmpty;
}
