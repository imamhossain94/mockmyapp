import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The language each project was last edited in, by project id.
///
/// The editor used to hold it for the length of a visit only, so reopening a
/// project — or reloading the web app, which is how a browser tab gets
/// reopened — put a German listing back on the English words every time.
///
/// Kept on this device rather than in the project: it is where one person was
/// looking, not part of the listing, and a backup opened on another device
/// should open on the default words. A project's default language is never
/// stored; its absence means the default.
class EditorLanguages extends Notifier<Map<String, String>> {
  /// Preferences key, versioned in case the value ever needs more than a code.
  static const _key = 'editor_languages_v1';

  SharedPreferences? _prefs;

  /// The read of what is stored. A save waits for it: written first, the
  /// choice of the moment would replace every other project's before they
  /// had been read back.
  Future<void>? _loading;

  @override
  Map<String, String> build() {
    _loading = _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs?.getString(_key);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      state = {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
        // A language chosen while this was still loading is the newer choice.
        ...state,
      };
    } catch (_) {
      // No preferences store, or a value this build cannot read: the editor
      // opens on the default words, as it always did.
    }
  }

  /// Remembers [language] for [projectId]; null forgets it, which is how the
  /// default language is chosen.
  void set(String projectId, String? language) {
    if (state[projectId] == language) return;
    final next = {...state};
    if (language == null) {
      next.remove(projectId);
    } else {
      next[projectId] = language;
    }
    state = next;
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      await _loading;
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setString(_key, jsonEncode(state));
    } catch (_) {
      // Remembered for this session all the same.
    }
  }
}

final editorLanguagesProvider =
    NotifierProvider<EditorLanguages, Map<String, String>>(EditorLanguages.new);
