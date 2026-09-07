import '../config/app_info.dart';
import 'event_bus.dart';

/// Unified plugin protocol. Every extension point of the editor
/// (highlighting, formatting, voice, file-type detection, encoding) must
/// implement this lifecycle: initialize → register events → execute →
/// dispose. The kernel's [PluginManager] schedules these uniformly so
/// plugins never interfere with one another.
abstract class EditorPlugin {
  /// Stable, unique id (matches the directory name, e.g. `highlight_plugin`).
  String get id;

  /// Human-readable display name, surfaced in the Plugins menu.
  String get displayName;

  /// Semver-style version string of the plugin itself.
  String get version => AppInfo.versionNumber;

  /// Short description shown in the UI.
  String get description;

  /// Whether the plugin can be toggled at runtime. Built-in plugins return
  /// true so users can disable voice/highlighting without a rebuild.
  bool get userToggleable => true;

  /// Called once on startup (or when re-enabled). Register event handlers
  /// against [bus], acquire resources, etc. Must be idempotent.
  void initialize(EventBus bus);

  /// Called when the plugin is disabled or the app is shutting down.
  /// Release every resource acquired in [initialize].
  void dispose();
}

/// Metadata exposed by [PluginManager.describeAll] for the About page.
class PluginInfo {
  final String id;
  final String displayName;
  final String version;
  final String description;
  final bool enabled;
  const PluginInfo({
    required this.id,
    required this.displayName,
    required this.version,
    required this.description,
    required this.enabled,
  });
}
