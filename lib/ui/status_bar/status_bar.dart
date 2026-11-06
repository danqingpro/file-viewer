import 'package:flutter/material.dart';

import '../../core/editor_kernel/editor_state.dart';

/// Encoding options offered in the status bar / menu bar. Mirrors the
/// labels [FileKernel] and [EditorService.switchEncoding] understand.
const List<String> kEncodingOptions = [
  'ANSI',
  'UTF-8',
  'UTF-8-BOM',
  'UTF-16-BE-BOM',
  'UTF-16-LE-BOM',
  'GBK',
  'ASCII',
];

/// Language ids the user can manually switch to from the status bar /
/// menu bar. The list mirrors the highlighters registered in
/// [HighlightPlugin].
const List<String> kLanguageOptions = [
  'txt',
  'md',
  'cpp',
  'json',
  'xml',
  'html',
  'css',
  'js',
  'python',
  'yaml',
  'batch',
  'mermaid',
];

/// Bottom status bar, mirroring Notepad++: file type, encoding, cursor
/// line/column, file size, and dirty indicator. The encoding and language
/// chips are tappable: tapping pops up a menu to switch them.
class StatusBar extends StatelessWidget {
  const StatusBar({
    super.key,
    required this.tab,
    required this.fileTypeLabel,
    required this.byteSize,
    required this.onEncodingChanged,
    required this.onLanguageChanged,
  });

  final EditorTabController tab;
  final String fileTypeLabel;
  final int byteSize;
  final ValueChanged<String> onEncodingChanged;
  final ValueChanged<String> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final pos = CursorPosition.fromOffset(tab.text, tab.cursorOffset);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0xFF007ACC),
      child: Row(
        children: [
          _languageChip(context),
          const SizedBox(width: 16),
          _encodingChip(context),
          const SizedBox(width: 16),
          _chip(Icons.grid_3x3_outlined, '行 ${pos.line}, 列 ${pos.column}'),
          const SizedBox(width: 16),
          _chip(Icons.storage_outlined, _formatSize(byteSize)),
          const Spacer(),
          _chip(
            tab.dirty ? Icons.error_outline : Icons.check_circle_outline,
            tab.dirty ? '未保存' : '已保存',
            highlight: tab.dirty,
          ),
        ],
      ),
    );
  }

  Widget _languageChip(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '切换语言（高亮）',
      offset: const Offset(0, -180),
      padding: EdgeInsets.zero,
      splashRadius: 16,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.description_outlined, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            fileTypeLabel,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
          ),
          const Icon(Icons.arrow_drop_up, size: 14, color: Colors.white70),
        ],
      ),
      itemBuilder: (_) => [
        for (final lang in kLanguageOptions)
          PopupMenuItem<String>(
            value: lang,
            child: Row(
              children: [
                Icon(
                  lang == tab.language ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 16,
                  color: lang == tab.language ? const Color(0xFF007ACC) : Colors.black38,
                ),
                const SizedBox(width: 10),
                Text(_languageLabel(lang), style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
      ],
      onSelected: onLanguageChanged,
    );
  }

  Widget _encodingChip(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '切换编码',
      offset: const Offset(0, -160),
      padding: EdgeInsets.zero,
      splashRadius: 16,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.text_fields, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            tab.encoding,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
          ),
          const Icon(Icons.arrow_drop_up, size: 14, color: Colors.white70),
        ],
      ),
      itemBuilder: (_) => [
        for (final enc in kEncodingOptions)
          PopupMenuItem<String>(
            value: enc,
            child: Row(
              children: [
                Icon(
                  enc == tab.encoding ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 16,
                  color: enc == tab.encoding ? const Color(0xFF007ACC) : Colors.black38,
                ),
                const SizedBox(width: 10),
                Text(enc, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
      ],
      onSelected: onEncodingChanged,
    );
  }

  Widget _chip(IconData icon, String text, {bool highlight = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: highlight ? const Color(0xFFFF9800) : Colors.white),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: highlight ? const Color(0xFFFF9800) : Colors.white,
            fontSize: 12,
            fontFamily: 'monospace',
            fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 0) return '大小未知';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  /// Keep this in sync with [FileTypePlugin.labelFor] so the popup shows
  /// the same labels as the status bar chip.
  String _languageLabel(String lang) {
    switch (lang) {
      case 'txt':
        return '纯文本 (TXT)';
      case 'md':
        return 'Markdown (MD)';
      case 'cpp':
        return 'C/C++';
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
      case 'mermaid':
        return 'Mermaid 图表 (MMD)';
      case 'binary':
        return '二进制 (BIN)';
      default:
        return lang.toUpperCase();
    }
  }
}
