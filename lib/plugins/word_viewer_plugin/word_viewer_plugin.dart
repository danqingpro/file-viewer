import '../../core/plugin_manager/plugin.dart';
import '../../core/plugin_manager/event_bus.dart';

/// Recognizes Word documents (`.doc` / `.docx`) and opens them with the
/// dedicated Word preview widget instead of the text or hex viewer.
///
/// Word documents cover both the legacy binary format (`.doc`) and the
/// modern XML format (`.docx`). Both are rendered read-only by handing
/// the temp file off to the system's native document viewer (e.g. Word,
/// WPS, Google Docs), which supports every Word sub-format faithfully —
/// no pure-Dart library can decode the legacy `.doc` binary container.
///
/// When this plugin is disabled, opening a .doc/.docx file falls back to
/// the binary hex viewer (raw bytes).
class WordViewerPlugin extends EditorPlugin {
  @override
  String get id => 'word_viewer_plugin';

  @override
  String get displayName => 'Word 文档预览插件';

  @override
  String get description => '预览 .doc / .docx 文档，调用系统查看器渲染（只读）。';

  @override
  void initialize(EventBus bus) {}

  @override
  void dispose() {}

  /// Extensions handled by the Word viewer. Covers both the legacy binary
  /// Word format and the modern XML-based format.
  static const Set<String> wordExtensions = {'doc', 'docx'};

  /// Whether [path] should be opened as a Word document.
  bool isWord(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return false;
    final ext = path.substring(dot + 1).toLowerCase();
    return wordExtensions.contains(ext);
  }
}
