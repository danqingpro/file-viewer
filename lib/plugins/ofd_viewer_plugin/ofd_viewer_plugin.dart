import '../../core/plugin_manager/plugin.dart';
import '../../core/plugin_manager/event_bus.dart';

/// Recognizes OFD documents (`.ofd`) and opens them with the dedicated
/// [OfdViewer] instead of the text or hex viewer.
///
/// OFD (Open Fixed-layout Document) is the Chinese national fixed-layout
/// document standard — a ZIP container of XML describing pages, text and
/// images. Rendering happens fully offline inside a WebView via the bundled
/// `assets/ofd/ofd.js` engine.
///
/// When this plugin is disabled, opening a .ofd file falls back to the
/// binary (hex) viewer.
class OfdViewerPlugin extends EditorPlugin {
  @override
  String get id => 'ofd_viewer_plugin';

  @override
  String get displayName => 'OFD 预览插件';

  @override
  String get description => '直接预览 .ofd 版式文档，支持多页浏览与缩放。';

  @override
  void initialize(EventBus bus) {}

  @override
  void dispose() {}

  /// Extensions handled by the OFD viewer.
  static const Set<String> ofdExtensions = {'ofd'};

  /// Whether [path] should be opened as an OFD document.
  bool isOfd(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return false;
    final ext = path.substring(dot + 1).toLowerCase();
    return ofdExtensions.contains(ext);
  }
}
