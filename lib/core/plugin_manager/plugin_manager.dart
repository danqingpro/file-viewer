import 'event_bus.dart';
import 'plugin.dart';

/// Singleton-ish scheduler that owns every [EditorPlugin] instance.
///
/// The kernel talks to extension points exclusively through this manager,
/// so new features can be added by registering a plugin without touching
/// the core. Toggle / list / lookup operations are all routed here.
class PluginManager {
  PluginManager(this._bus);

  final EventBus _bus;
  final Map<String, _Registered> _plugins = {};

  /// Register and initialize a plugin. Idempotent: re-registering an id
  /// that already exists is a no-op.
  void register(EditorPlugin plugin, {bool enabled = true}) {
    if (_plugins.containsKey(plugin.id)) return;
    final reg = _Registered(plugin: plugin, enabled: enabled);
    if (enabled) {
      plugin.initialize(_bus);
    }
    _plugins[plugin.id] = reg;
  }

  /// Enable a previously disabled plugin (calls initialize).
  void enable(String id) {
    final reg = _plugins[id];
    if (reg == null || reg.enabled) return;
    reg.plugin.initialize(_bus);
    reg.enabled = true;
  }

  /// Disable a plugin (calls dispose). Safe to call on already-disabled.
  void disable(String id) {
    final reg = _plugins[id];
    if (reg == null || !reg.enabled) return;
    reg.plugin.dispose();
    reg.enabled = false;
  }

  /// Whether a plugin is currently enabled.
  bool isEnabled(String id) => _plugins[id]?.enabled ?? false;

  /// Returns the plugin instance if registered and enabled, else null.
  T? get<T extends EditorPlugin>(String id) {
    final reg = _plugins[id];
    if (reg == null || !reg.enabled) return null;
    if (reg.plugin is T) return reg.plugin as T;
    return null;
  }

  /// Snapshot of every registered plugin, used by the About / Plugins view.
  List<PluginInfo> describeAll() => _plugins.values
      .map((r) => PluginInfo(
            id: r.plugin.id,
            displayName: r.plugin.displayName,
            version: r.plugin.version,
            description: r.plugin.description,
            enabled: r.enabled,
          ))
      .toList(growable: false);

  /// Dispose every enabled plugin. Called once on shutdown.
  Future<void> disposeAll() async {
    for (final reg in _plugins.values) {
      if (reg.enabled) {
        reg.plugin.dispose();
        reg.enabled = false;
      }
    }
    await _bus.dispose();
  }
}

class _Registered {
  final EditorPlugin plugin;
  bool enabled;
  _Registered({required this.plugin, required this.enabled});
}
