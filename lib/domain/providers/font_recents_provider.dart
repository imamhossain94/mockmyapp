import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/assets/font_catalog.dart';

/// The typefaces this user actually reaches for, newest first.
///
/// The quick strip under the caption's typeface row used to be a hard-coded
/// list of twelve popular families. It was the fastest way to change a font in
/// the app and it was the same twelve for everybody, so for anyone whose brand
/// face was not among them it was twelve taps that did nothing they wanted —
/// the picker sheet was the only real route, every time.
///
/// This is the same strip, kept live. It opens on [_seed] so a fresh install
/// still has something useful in it, and every choice made anywhere — the strip
/// itself, the picker sheet, the rich text editor's typeface button — moves
/// that face to the front. After a handful of edits the strip is the user's own
/// shortlist, which is the thing that makes changing a font quick.
///
/// Families are stored as the plain strings a document already holds, so an
/// uploaded font (`user:<uuid>`) recents exactly like a catalog one. A family
/// that no longer resolves — an upload the user deleted — is filtered on read
/// rather than pruned on write: the alternative is a background write racing a
/// library that is still loading its index at startup.
///
/// Deliberately *not* persisted per project. A typeface is a brand asset, and
/// someone who just set a headline in Poppins on one listing wants Poppins near
/// to hand on the next one. This is the same reasoning that makes
/// `FontLibrary` app-global rather than per-project.
class FontRecents extends Notifier<List<String>> {
  /// Preferences key. Versioned in the name, because the value is a list whose
  /// meaning would change if uploads ever stopped being addressable by family.
  static const _key = 'font_recents_v1';

  /// How many the strip holds. Eight is what fits a 390dp phone at the tile
  /// width the strip already uses, scrolled once.
  static const max = 8;

  /// What the strip shows before the user has chosen anything.
  ///
  /// The head of the old hard-coded list, kept so an install that has never
  /// picked a font looks exactly as it did — the strip earns its place on day
  /// one and personalises from the first edit rather than starting empty.
  static const _seed = <String>[
    'Inter',
    'Poppins',
    'Montserrat',
    'Roboto',
    'Oswald',
    'Bebas Neue',
    'Playfair Display',
    'Anton',
  ];

  SharedPreferences? _prefs;

  @override
  List<String> build() {
    unawaited(_load());
    return _seed;
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final saved = _prefs?.getStringList(_key);
      if (saved == null || saved.isEmpty) return;
      state = saved.take(max).toList();
    } catch (_) {
      // No preferences store — the web before a user gesture, or a device that
      // refused. The seed is a perfectly good strip; losing the personalised
      // order is not worth failing an editor session over.
    }
  }

  /// Moves [family] to the front, dropping any earlier copy of it.
  ///
  /// Called from every place a font is chosen, so the strip reflects choices
  /// made through the picker sheet and the editor's typeface button as well as
  /// through the strip itself. Choosing the face that is already first is a
  /// no-op rather than a rewrite — it happens on every rebuild of a panel whose
  /// font did not change.
  void record(String family) {
    if (family.isEmpty) return;
    if (state.isNotEmpty && state.first == family) return;

    state = [family, ...state.where((f) => f != family)].take(max).toList();
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setStringList(_key, state);
    } catch (_) {
      // Same trade as [_load]: the in-memory order still works for this
      // session, and a failed write is not worth surfacing mid-edit.
    }
  }

  /// The strip's contents, with anything that will not render dropped.
  ///
  /// [resolves] is supplied by the caller rather than reached for here, because
  /// whether a family resolves is a question about `FontLibrary`'s index and
  /// this provider must not depend on it — the library is still loading during
  /// the first frames, and a recents list that pruned itself against a
  /// half-loaded index would quietly forget the user's uploads.
  List<String> visible(bool Function(String) resolves) {
    final kept = [
      for (final family in state)
        if (resolves(family)) family,
    ];
    // Backfilled from the catalog so the strip never collapses to two tiles
    // after a couple of uploads are deleted.
    if (kept.length >= max) return kept;
    for (final font in fontCatalog) {
      if (kept.length >= max) break;
      if (!kept.contains(font.family)) kept.add(font.family);
    }
    return kept;
  }
}

final fontRecentsProvider = NotifierProvider<FontRecents, List<String>>(
  FontRecents.new,
);
