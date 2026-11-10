import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/screen_doc.dart';

/// The Elements library: every decorative shape and every icon the editor can
/// drop on a screen.
///
/// Two assets, both generated:
///
/// * `assets/elements/elements.json` — original vector elements (shapes,
///   sparkles, arrows, callouts, badges, awards, laurels, decor, blobs,
///   waves, lines, patterns), drawn by `tool/generate_elements.py`;
/// * `assets/icons/lucide.json` — the Lucide icon set (ISC licence),
///   converted by `tool/generate_icons.py`.
///
/// Both come out as ordinary shapes: an element or an icon on the canvas is a
/// [ShapeSpec] like any other, so it is moved, coloured, stacked, shadowed and
/// exported by exactly the code every shape already goes through.

/// A named group of entries, in display order.
@immutable
class LibraryCategory {
  const LibraryCategory(this.id, this.label);

  final String id;
  final String label;
}

/// One entry of the element library.
@immutable
class ElementDef {
  const ElementDef({
    required this.id,
    required this.name,
    required this.category,
    required this.aspect,
    this.kind,
    this.pathData,
    this.evenOdd = false,
    this.strokeWidth,
    this.dash,
    this.cornerRadius,
    this.sides,
    this.innerRatio,
    this.label,
    this.labelSize = 0.034,
    this.labelWeight,
    this.labelPadding = 0.01,
  });

  factory ElementDef.fromJson(Map<String, dynamic> j) {
    final label = j['label'] as Map<String, dynamic>?;
    return ElementDef(
      id: j['id'] as String,
      name: j['n'] as String,
      category: j['c'] as String,
      aspect: (j['a'] as num?)?.toDouble() ?? 1,
      kind: switch (j['k']) {
        final String k =>
          ShapeKind.values.where((v) => v.name == k).firstOrNull,
        _ => null,
      },
      pathData: j['d'] as String?,
      evenOdd: j['eo'] as bool? ?? false,
      strokeWidth: (j['sw'] as num?)?.toDouble(),
      dash: switch (j['dash']) {
        final String d =>
          StrokeStyle.values.where((v) => v.name == d).firstOrNull,
        _ => null,
      },
      cornerRadius: (j['cr'] as num?)?.toDouble(),
      sides: (j['sides'] as num?)?.toInt(),
      innerRatio: (j['inner'] as num?)?.toDouble(),
      label: label?['text'] as String?,
      labelSize: (label?['size'] as num?)?.toDouble() ?? 0.034,
      labelWeight: (label?['weight'] as num?)?.toInt(),
      labelPadding: (label?['pad'] as num?)?.toDouble() ?? 0.01,
    );
  }

  final String id;
  final String name;
  final String category;

  /// Width over height, as drawn.
  final double aspect;

  /// A parametric kind, for the basics the app draws natively — so their
  /// corner and side controls keep working. Null for a drawn path.
  final ShapeKind? kind;

  /// The drawing, in the unit box, when this is not a [kind].
  final String? pathData;
  final bool evenOdd;

  /// Non-null for line art: stroked, not filled, at this share of the shape's
  /// shorter side. See [ShapeSpec.strokeInBox].
  final double? strokeWidth;
  final StrokeStyle? dash;

  final double? cornerRadius;
  final int? sides;
  final double? innerRatio;

  /// Words the element carries — an award's citation, a pill's feature.
  final String? label;
  final double labelSize;
  final int? labelWeight;
  final double labelPadding;

  bool get isStroked => strokeWidth != null;

  /// The shape this element drops onto the canvas, in [ink].
  ///
  /// Sized so its longer side is [size] canvas widths, at its own proportions.
  /// Words on a filled element take whichever of near-black and white reads on
  /// [ink]; words on line art (a laurel) are [ink] itself.
  ShapeSpec toShape({Color ink = const Color(0xFFFFFFFF), double size = 0.34}) {
    final width = aspect >= 1 ? size : size * aspect;
    final height = width / (aspect <= 0 ? 1 : aspect);
    final words = label;
    final filledUnderWords = pathData == null || !isStroked;
    final wordInk = words == null
        ? ink
        : (kind != null && filledUnderWords) || _wordsInside
        ? _onInk(ink)
        : ink;

    final ShapeSpec base;
    if (kind != null) {
      final of = ShapeSpec.of(kind!, fill: ink);
      base = of.copyWith(
        width: width,
        height: height,
        cornerRadius: cornerRadius,
        sides: sides,
        innerRatio: innerRatio,
        strokeStyle: dash,
      );
    } else {
      base = ShapeSpec(
        kind: ShapeKind.path,
        pathData: pathData ?? '',
        evenOdd: evenOdd,
        width: width,
        height: height,
        fill: isStroked ? const Color(0x00000000) : ink,
        strokeColor: ink,
        strokeWidth: strokeWidth ?? 0,
        strokeInBox: isStroked,
        strokeStyle: dash ?? StrokeStyle.solid,
        z: kStackOverEverything,
      );
    }
    if (words == null) return base;
    return base.copyWith(
      label: ShapeLabel(
        words,
        fontFamily: 'Inter',
        size: labelSize,
        color: wordInk,
        weight: labelWeight,
        bold: labelWeight == null,
        padding: labelPadding,
      ),
    );
  }

  /// Whether the words sit on the element's own ink — a burst or a pill — as
  /// opposed to in the open space between line art, like a laurel's.
  bool get _wordsInside => category != 'awards';

  static Color _onInk(Color ink) => ink.computeLuminance() > 0.5
      ? const Color(0xFF11142A)
      : const Color(0xFFFFFFFF);
}

/// One Lucide icon.
@immutable
class IconDef {
  const IconDef({
    required this.name,
    required this.categories,
    required this.tags,
    required this.pathData,
  });

  factory IconDef.fromJson(Map<String, dynamic> j) => IconDef(
    name: j['n'] as String,
    categories: [for (final c in j['c'] as List) c as String],
    tags: [for (final t in (j['t'] as List? ?? const [])) t as String],
    pathData: j['d'] as String,
  );

  /// Lucide's own slug, e.g. `circle-check`.
  final String name;
  final List<String> categories;
  final List<String> tags;

  /// The icon on its 24-unit grid, scaled into the unit box.
  final String pathData;

  /// Lucide's stroke: 2 on a 24 grid.
  static const double stroke = 2 / 24;

  String get label => name.replaceAll('-', ' ');

  /// Whether [query] finds this icon by name or tag.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.contains(q) || tags.any((t) => t.contains(q));
  }

  /// The icon as a shape in [ink], [size] canvas widths square.
  ShapeSpec toShape({
    Color ink = const Color(0xFFFFFFFF),
    double size = 0.18,
  }) => ShapeSpec(
    kind: ShapeKind.path,
    pathData: pathData,
    width: size,
    height: size,
    fill: const Color(0x00000000),
    strokeColor: ink,
    strokeWidth: stroke,
    strokeInBox: true,
    name: label[0].toUpperCase() + label.substring(1),
    z: kStackOverEverything,
  );
}

@immutable
class ElementCatalog {
  const ElementCatalog({
    required this.categories,
    required this.elements,
    required this.iconCategories,
    required this.icons,
  });

  factory ElementCatalog.fromJson({
    required Map<String, dynamic> elements,
    required Map<String, dynamic> icons,
  }) => ElementCatalog(
    categories: [
      for (final c in elements['categories'] as List)
        LibraryCategory(c['id'] as String, c['label'] as String),
    ],
    elements: [
      for (final e in elements['elements'] as List)
        ElementDef.fromJson(e as Map<String, dynamic>),
    ],
    iconCategories: [
      for (final c in icons['categories'] as List)
        LibraryCategory(c['id'] as String, c['label'] as String),
    ],
    icons: [
      for (final i in icons['icons'] as List)
        IconDef.fromJson(i as Map<String, dynamic>),
    ],
  );

  final List<LibraryCategory> categories;
  final List<ElementDef> elements;
  final List<LibraryCategory> iconCategories;
  final List<IconDef> icons;

  List<ElementDef> elementsIn(String? category, {String query = ''}) {
    final q = query.trim().toLowerCase();
    return [
      for (final e in elements)
        if ((category == null || e.category == category) &&
            (q.isEmpty || e.name.toLowerCase().contains(q)))
          e,
    ];
  }

  List<IconDef> iconsIn(String? category, {String query = ''}) => [
    for (final i in icons)
      if ((category == null || i.categories.contains(category)) &&
          i.matches(query))
        i,
  ];

  /// The icons worth showing before anything is searched or picked: the ones
  /// store screenshots actually use, rather than the alphabet's first page.
  static const featuredIcons = [
    'star',
    'heart',
    'check',
    'circle-check',
    'shield-check',
    'zap',
    'sparkles',
    'rocket',
    'lock',
    'bell',
    'camera',
    'music',
    'play',
    'mic',
    'image',
    'message-circle',
    'send',
    'users',
    'user',
    'calendar',
    'clock',
    'map-pin',
    'globe',
    'search',
    'settings',
    'trending-up',
    'chart-bar',
    'wallet',
    'credit-card',
    'shopping-cart',
    'gift',
    'trophy',
    'award',
    'crown',
    'thumbs-up',
    'smile',
    'sun',
    'moon',
    'cloud',
    'wifi',
    'battery-charging',
    'download',
    'upload',
    'share-2',
    'bookmark',
    'flag',
    'target',
    'layers',
  ];

  List<IconDef> get featured {
    final byName = {for (final i in icons) i.name: i};
    return [for (final n in featuredIcons) ?byName[n]];
  }
}

/// Loads both catalogs, and registers Lucide's licence with Flutter's licence
/// page — the notice the ISC licence asks to travel with the icons.
Future<ElementCatalog> loadElementCatalog([AssetBundle? bundle]) async {
  final assets = bundle ?? rootBundle;
  final elements =
      jsonDecode(await assets.loadString('assets/elements/elements.json'))
          as Map<String, dynamic>;
  final icons =
      jsonDecode(await assets.loadString('assets/icons/lucide.json'))
          as Map<String, dynamic>;
  _registerLucideLicence(assets);
  return ElementCatalog.fromJson(elements: elements, icons: icons);
}

bool _licenceRegistered = false;

void _registerLucideLicence(AssetBundle assets) {
  if (_licenceRegistered) return;
  _licenceRegistered = true;
  LicenseRegistry.addLicense(() async* {
    final text = await assets.loadString('assets/icons/LICENSE');
    yield LicenseEntryWithLineBreaks(['Lucide icons'], text);
  });
}

final elementCatalogProvider = FutureProvider<ElementCatalog>(
  (ref) => loadElementCatalog(),
);

/// The longest side a newly placed element takes, as a share of the canvas:
/// big enough to read at a glance, small enough to leave the device visible.
double defaultElementSize(ElementDef element) =>
    element.category == 'patterns' || element.category == 'awards'
    ? 0.5
    : math.min(0.34, 0.2 + 0.05 * element.aspect);
