import '../../core/plugin_manager/plugin.dart';
import '../../core/plugin_manager/event_bus.dart';

/// Recognizes binary file extensions (.bin / .bit / .raw / .dat) and
/// tells the editor kernel to open them with the binary (hex) viewer
/// instead of the text editor.
///
/// When this plugin is disabled, opening a .bin file falls back to text
/// mode and the UI shows "无法打开此格式的文件".
class BinaryViewerPlugin extends EditorPlugin {
  @override
  String get id => 'binary_viewer_plugin';

  @override
  String get displayName => '二进制查看插件';

  @override
  String get description => '识别并以十六进制查看 .bin/.bit/.raw/.dat 等二进制文件。';

  @override
  void initialize(EventBus bus) {}

  @override
  void dispose() {}

  /// Extensions handled by the binary viewer.
  static const Set<String> binaryExtensions = {
    'bin', 'bit', 'raw', 'dat',
  };

  /// Whether [path] should be opened as a binary file.
  bool isBinary(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return false;
    final ext = path.substring(dot + 1).toLowerCase();
    return binaryExtensions.contains(ext);
  }
}
