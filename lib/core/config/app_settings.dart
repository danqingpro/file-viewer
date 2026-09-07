import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the quick-action toolbar renders each button.
///
/// - [iconOnly]  : just the icon (VSCode default look).
/// - [textOnly]  : just the label text.
/// - [iconAndText] : icon on top, label below it.
enum ToolbarDisplayMode {
  iconOnly,
  textOnly,
  iconAndText,
}

extension ToolbarDisplayModeLabel on ToolbarDisplayMode {
  String get label => switch (this) {
        ToolbarDisplayMode.iconOnly => '仅图标',
        ToolbarDisplayMode.textOnly => '仅文字',
        ToolbarDisplayMode.iconAndText => '图标 + 文字',
      };
}

/// User-tunable application settings: theme mode and toolbar display mode.
///
/// Persists to [SharedPreferences] so the choice survives restarts. The
/// whole app listens to this ChangeNotifier to rebuild when either setting
/// changes.
class AppSettings extends ChangeNotifier {
  AppSettings._({
    ThemeMode themeMode = ThemeMode.system,
    ToolbarDisplayMode toolbarMode = ToolbarDisplayMode.iconAndText,
  })  : _themeMode = themeMode,
        _toolbarMode = toolbarMode;

  static const String _kThemeMode = 'theme_mode';
  static const String _kToolbarMode = 'toolbar_mode';

  ThemeMode _themeMode;
  ToolbarDisplayMode _toolbarMode;

  ThemeMode get themeMode => _themeMode;
  ToolbarDisplayMode get toolbarMode => _toolbarMode;

  /// Synchronous default (used by tests / fallbacks).
  factory AppSettings.defaults() => AppSettings._();

  /// Bootstrap from disk. Call once at startup before runApp so the first
  /// frame already uses the persisted theme.
  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final tm = prefs.getString(_kThemeMode);
    final themeMode = tm != null
        ? ThemeMode.values.firstWhere(
            (e) => e.name == tm,
            orElse: () => ThemeMode.system,
          )
        : ThemeMode.system;
    final tb = prefs.getString(_kToolbarMode);
    final toolbarMode = tb != null
        ? ToolbarDisplayMode.values.firstWhere(
            (e) => e.name == tb,
            orElse: () => ToolbarDisplayMode.iconAndText,
          )
        : ToolbarDisplayMode.iconAndText;
    return AppSettings._(themeMode: themeMode, toolbarMode: toolbarMode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode.name);
  }

  Future<void> setToolbarMode(ToolbarDisplayMode mode) async {
    if (mode == _toolbarMode) return;
    _toolbarMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToolbarMode, mode.name);
  }
}
