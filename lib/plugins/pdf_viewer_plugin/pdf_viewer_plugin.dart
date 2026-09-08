import '../../core/plugin_manager/plugin.dart';
import '../../core/plugin_manager/event_bus.dart';

/// Recognizes PDF files (`.pdf`) and opens them with the dedicated PDF
/// preview widget instead of the text or hex viewer.
///
/// When this plugin is disabled, opening a .pdf file falls back to the
/// text viewer (which shows garbled binary content).
class PdfViewerPlugin extends EditorPlugin {
  @override
  String get id => 'pdf_viewer_plugin';

  @override
  String get displayName => 'PDF 预览插件';

  @override
  String get description => '直接预览 .pdf 文件，支持翻页与缩放。';

  @override
  void initialize(EventBus bus) {}

  @override
  void dispose() {}

  /// Extensions handled by the PDF viewer.
  static const Set<String> pdfExtensions = {'pdf'};

  /// Whether [path] should be opened as a PDF.
  bool isPdf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return false;
    final ext = path.substring(dot + 1).toLowerCase();
    return pdfExtensions.contains(ext);
  }
}
