import 'package:flutter/material.dart';

import 'app.dart';
import 'core/config/app_settings.dart';

/// Program entry point. Boots the cross-platform plugin-based editor.
///
/// Loads persisted settings (theme / toolbar mode) synchronously before the
/// first frame so the app starts in the correct theme.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  runApp(EditorApp(settings: settings));
}
