import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/assets/device_filter.dart';
import '../../data/assets/frame_catalog.dart';

/// Where the device picker was left.
///
/// Two halves with different lifetimes. The maker and the store scope are
/// the user's standing preferences and survive a restart. The kind and the
/// search are about the task in hand: they outlive switching library tabs,
/// which rebuilds the picker from nothing, but not the session.
@immutable
class DeviceFilterState {
  const DeviceFilterState({
    this.makerByPlatform = const {},
    this.scope = true,
    this.query = '',
    this.kindByTarget = const {},
  });

  /// The maker last picked, per half of the catalog.
  ///
  /// Per platform because Play work and App Store work want different
  /// makers: a remembered "Samsung" would otherwise open every App Store set
  /// on a maker it cannot show.
  final Map<FramePlatform, String> makerByPlatform;

  /// Whether "Only {store} devices" is on, for the targets that offer it.
  /// Global, because it is a stance rather than a per-set choice.
  final bool scope;

  /// The search, session-only.
  final String query;

  /// Kinds the user chose over a target's default, by target id, for this
  /// session. A key mapped to null is a deliberate "every kind"; a missing key
  /// is no choice at all.
  final Map<String, DeviceKind?> kindByTarget;

  String? makerFor(FramePlatform platform) => makerByPlatform[platform];

  /// The kind chosen for [targetId], or [fallback] — the target's own default —
  /// when nothing was.
  DeviceKind? kindFor(String targetId, DeviceKind? fallback) =>
      kindByTarget.containsKey(targetId) ? kindByTarget[targetId] : fallback;

  DeviceFilterState copyWith({
    Map<FramePlatform, String>? makerByPlatform,
    bool? scope,
    String? query,
    Map<String, DeviceKind?>? kindByTarget,
  }) => DeviceFilterState(
    makerByPlatform: makerByPlatform ?? this.makerByPlatform,
    scope: scope ?? this.scope,
    query: query ?? this.query,
    kindByTarget: kindByTarget ?? this.kindByTarget,
  );
}

/// The device picker's filter, kept app-wide.
///
/// App-global rather than per project for the reason `FontRecents` is: the
/// maker someone designs for is theirs, not the listing's.
class DeviceFilterNotifier extends Notifier<DeviceFilterState> {
  /// Preferences key. Versioned in the name, so a later shape of the value
  /// can be told from this one rather than misread as it.
  static const storageKey = 'device_filter_v1';

  /// How the store is reached. A seam for tests, which need one that refuses.
  @visibleForTesting
  static Future<SharedPreferences> Function() openStore =
      SharedPreferences.getInstance;

  SharedPreferences? _prefs;

  /// Set once the user changes something persisted, so a load that finishes
  /// late cannot overwrite the choice with the stale stored one.
  bool _touched = false;

  @override
  DeviceFilterState build() {
    unawaited(_load());
    return const DeviceFilterState();
  }

  Future<void> _load() async {
    try {
      _prefs = await openStore();
      final raw = _prefs?.getString(storageKey);
      if (raw == null || _touched) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final makers = <FramePlatform, String>{};
      if (decoded['makerByPlatform'] case final Map stored) {
        for (final platform in FramePlatform.values) {
          if (stored[platform.name] case final String maker
              when maker.isNotEmpty) {
            makers[platform] = maker;
          }
        }
      }
      final scope = decoded['scope'];
      state = state.copyWith(
        makerByPlatform: makers,
        scope: scope is bool ? scope : null,
      );
    } catch (_) {
      // No store — the web before a user gesture, a device that refused — or
      // a value this build cannot read. The defaults are a perfectly good
      // picker; a lost preference is not worth failing an editor session over.
    }
  }

  /// Remembers [maker] for [platform]'s half of the catalog; null is "All".
  void setMaker(FramePlatform platform, String? maker) {
    if (state.makerFor(platform) == maker) return;
    final makers = {...state.makerByPlatform};
    if (maker == null) {
      makers.remove(platform);
    } else {
      makers[platform] = maker;
    }
    _touched = true;
    state = state.copyWith(makerByPlatform: makers);
    unawaited(_save());
  }

  void setScope(bool scope) {
    if (state.scope == scope) return;
    _touched = true;
    state = state.copyWith(scope: scope);
    unawaited(_save());
  }

  /// Session-only: a search is about the task in hand.
  void setQuery(String query) {
    if (state.query == query) return;
    state = state.copyWith(query: query);
  }

  /// Session-only: the next set of the same target opens where this one was
  /// left, and a restart goes back to what the target asks for.
  void setKind(String targetId, DeviceKind? kind) {
    if (state.kindByTarget.containsKey(targetId) &&
        state.kindByTarget[targetId] == kind) {
      return;
    }
    state = state.copyWith(
      kindByTarget: {...state.kindByTarget, targetId: kind},
    );
  }

  /// Every kind, every maker, every store, in one step — what an empty
  /// state's "Search all devices" asks for. The search itself is kept: it is
  /// the thing being widened.
  void showEverything(FramePlatform platform, String targetId) {
    final makers = {...state.makerByPlatform}..remove(platform);
    _touched = true;
    state = state.copyWith(
      makerByPlatform: makers,
      scope: false,
      kindByTarget: {...state.kindByTarget, targetId: null},
    );
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      _prefs ??= await openStore();
      await _prefs?.setString(
        storageKey,
        jsonEncode({
          'makerByPlatform': {
            for (final MapEntry(:key, :value) in state.makerByPlatform.entries)
              key.name: value,
          },
          'scope': state.scope,
        }),
      );
    } catch (_) {
      // Same trade as [_load]: the in-memory filter still works for this
      // session, and a failed write is not worth surfacing mid-edit.
    }
  }
}

final deviceFilterProvider =
    NotifierProvider<DeviceFilterNotifier, DeviceFilterState>(
      DeviceFilterNotifier.new,
    );
