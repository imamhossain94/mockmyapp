import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'settings_provider.g.dart';

class SettingsState {
  const SettingsState({
    required this.themeMode,
    required this.dynamicColorEnabled,
  });

  final ThemeMode themeMode;
  final bool dynamicColorEnabled;

  SettingsState copyWith({ThemeMode? themeMode, bool? dynamicColorEnabled}) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      dynamicColorEnabled: dynamicColorEnabled ?? this.dynamicColorEnabled,
    );
  }
}

@riverpod
class Settings extends _$Settings {
  static const _themeModeKey = 'theme_mode';
  static const _dynamicColorKey = 'dynamic_color';

  SharedPreferences? _prefs;

  @override
  SettingsState build() {
    _initPrefs();
    return const SettingsState(
      themeMode: ThemeMode.dark, // Default to dark for PS aesthetic
      dynamicColorEnabled: false, // Default false to prefer vibrant PS blue
    );
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();

    final savedThemeStr = _prefs?.getString(_themeModeKey);
    final themeMode = switch (savedThemeStr) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };

    final savedDynamicColor = _prefs?.getBool(_dynamicColorKey) ?? false;

    state = SettingsState(
      themeMode: themeMode,
      dynamicColorEnabled: savedDynamicColor,
    );
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _prefs?.setString(_themeModeKey, mode.name);
  }

  void setDynamicColorEnabled(bool enabled) {
    state = state.copyWith(dynamicColorEnabled: enabled);
    _prefs?.setBool(_dynamicColorKey, enabled);
  }
}
