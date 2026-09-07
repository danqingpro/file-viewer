import '../../core/plugin_manager/plugin.dart';
import '../../core/plugin_manager/event_bus.dart';

/// Maps a file path / extension to a language id (`txt`, `md`, `cpp`, `json`,
/// `xml`, …). This is the first plugin consulted when opening a file — the
/// editor kernel uses its answer to pick the right highlighter and formatter.
class FileTypePlugin extends EditorPlugin {
  @override
  String get id => 'file_type_plugin';

  @override
  String get displayName => '文件格式识别插件';

  @override
  String get description => '按扩展名识别文件类型，分发到对应高亮 / 格式化插件。';

  @override
  void initialize(EventBus bus) {}

  @override
  void dispose() {}

  static const Map<String, String> _byExt = {
    // Plain text
    'txt': 'txt',
    'log': 'txt',
    'text': 'txt',
    // Markdown
    'md': 'md',
    'markdown': 'md',
    'mkd': 'md',
    // C / C++
    'cpp': 'cpp',
    'cc': 'cpp',
    'cxx': 'cpp',
    'c': 'cpp',
    'h': 'cpp',
    'hpp': 'cpp',
    'hh': 'cpp',
    'hxx': 'cpp',
    // JSON
    'json': 'json',
    'jsonc': 'json',
    // XML
    'xml': 'xml',
    'svg': 'xml',
    'xhtml': 'xml',
    'xsd': 'xml',
    'xsl': 'xml',
    // HTML
    'html': 'html',
    'htm': 'html',
    'shtml': 'html',
    // CSS
    'css': 'css',
    'scss': 'css',
    'less': 'css',
    // JavaScript
    'js': 'js',
    'jsx': 'js',
    'mjs': 'js',
    'cjs': 'js',
    // Python
    'py': 'python',
    'pyw': 'python',
    'pyi': 'python',
    // YAML
    'yaml': 'yaml',
    'yml': 'yaml',
    // Batch / Shell
    'bat': 'batch',
    'cmd': 'batch',
    // Java (use cpp highlighter as a close approximation for C-like syntax)
    'java': 'cpp',
    // Shell scripts -> batch for now (best-effort)
    'sh': 'batch',
    'bash': 'batch',
  };

  /// Resolve language id from a path. Unknown extensions fall back to `txt`.
  String detect(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return 'txt';
    final ext = path.substring(dot + 1).toLowerCase();
    return _byExt[ext] ?? 'txt';
  }

  /// Human label for a language id, shown in the status bar.
  String labelFor(String language) {
    switch (language) {
      case 'txt':
        return '纯文本 (TXT)';
      case 'md':
        return 'Markdown (MD)';
      case 'cpp':
        return 'C/C++ (cpp/h/hpp)';
      case 'json':
        return 'JSON';
      case 'xml':
        return 'XML';
      case 'html':
        return 'HTML';
      case 'css':
        return 'CSS';
      case 'js':
        return 'JavaScript';
      case 'python':
        return 'Python';
      case 'yaml':
        return 'YAML';
      case 'batch':
        return '批处理 (BAT/CMD)';
      case 'binary':
        return '二进制 (BIN)';
      default:
        return language.toUpperCase();
    }
  }
}
