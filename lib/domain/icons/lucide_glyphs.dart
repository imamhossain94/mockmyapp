import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../data/assets/element_catalog.dart';
import '../engine/svg_path.dart';

/// The Lucide glyphs an icon can carry, by slug, read once from
/// `assets/icons/lucide.json` (ISC licence) and kept for the run.
///
/// Through [loadElementCatalog], so the licence is registered with Flutter's
/// licence page whichever screen reads the icons first — the ISC licence asks
/// for the notice to travel with them. Static rather than a provider because
/// the icon painter runs without a widget tree: in an export, a test, a
/// thumbnail in the store preview.
abstract final class LucideGlyphs {
  static Future<Map<String, IconDef>>? _loading;
  static Map<String, IconDef>? _byName;
  static final Map<String, Path?> _paths = {};

  /// Every glyph by slug, loaded on first ask.
  static Future<Map<String, IconDef>> load() =>
      _loading ??= loadElementCatalog().then((c) => _index(c.icons));

  /// The glyphs, when they have loaded; null before.
  static Map<String, IconDef>? get loaded => _byName;

  /// Uses [icons] instead of the bundled file — for tests, which read the
  /// asset from disk.
  @visibleForTesting
  static void debugUse(List<IconDef> icons) {
    _paths.clear();
    _loading = Future.value(_index(icons));
  }

  static Map<String, IconDef> _index(List<IconDef> icons) =>
      _byName = {for (final icon in icons) icon.name: icon};

  /// The glyph [name] in the unit box, or null when there is no such glyph or
  /// its outline does not read. Parsed once per name.
  static Path? pathOf(String name) {
    if (_paths.containsKey(name)) return _paths[name];
    final def = _byName?[name];
    final path = def == null ? null : parseUnitPath(def.pathData);
    if (def != null) _paths[name] = path;
    return path;
  }

  /// [pathOf], after loading the glyphs if they have not loaded yet.
  static Future<Path?> resolve(String name) async {
    await load();
    return pathOf(name);
  }
}
