import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/device_motion.dart';

/// The last video settings used, remembered between launches.
///
/// App-wide rather than per project, the way the image export settings are:
/// someone who films App Store previews films them for every app, and a clip
/// for the next screen should start where the last one was made. The App Store
/// device class is the exception — the export sheet picks it from the set
/// being filmed each time, since an iPad set wants the iPad size whatever the
/// last clip was.
class VideoSettingsNotifier extends Notifier<VideoSettings> {
  /// Preferences key. Versioned in the name, so a later shape of the value
  /// can be told from this one rather than misread as it.
  static const storageKey = 'video_settings_v1';

  /// How the store is reached. A seam for tests, which need one that refuses.
  @visibleForTesting
  static Future<SharedPreferences> Function() openStore =
      SharedPreferences.getInstance;

  /// Set once the user changes something, so a load that finishes late cannot
  /// overwrite the choice with the stale stored one.
  bool _touched = false;

  late Future<void> _loading;

  @override
  VideoSettings build() {
    _loading = _load();
    return const VideoSettings();
  }

  Future<void> _load() async {
    try {
      final prefs = await openStore();
      final raw = prefs.getString(storageKey);
      if (raw == null || _touched) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      state = VideoSettings.fromJson(decoded.cast<String, Object?>());
    } catch (_) {
      // No store, or a value this build cannot read: the defaults film a
      // perfectly good clip, and a lost preference is not worth an error.
    }
  }

  /// The settings once the stored ones have been read — what the export sheet
  /// opens with, so it never starts from the defaults while the read is still
  /// on its way.
  Future<VideoSettings> settled() async {
    await _loading;
    return state;
  }

  /// Remembers [next], here at once and on disk as soon as it can.
  Future<void> set(VideoSettings next) async {
    _touched = true;
    state = next;
    try {
      final prefs = await openStore();
      await prefs.setString(storageKey, jsonEncode(next.toJson()));
    } catch (_) {
      // Remembered for this session regardless.
    }
  }
}

final videoSettingsProvider =
    NotifierProvider<VideoSettingsNotifier, VideoSettings>(
      VideoSettingsNotifier.new,
    );
