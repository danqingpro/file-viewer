import 'package:flutter/widgets.dart';

import '../../plugins/highlight_plugin/highlight_plugin.dart';

/// A [TextEditingController] that renders inline syntax highlighting by
/// overriding [buildTextSpan]. The editor kernel owns one instance per
/// tab; it is fed the active language and a [HighlightPlugin] so the right
/// tokenizer is applied. Tokenization is cached per-text to keep typing
/// smooth on large buffers.
class HighlightingController extends TextEditingController {
  HighlightingController({String text = ''}) : super(text: text);

  HighlightPlugin? _plugin;
  String _language = 'txt';
  String _lastTokenized = '';
  List<TokenSpan> _cached = const [];
  TextStyle _baseStyle = const TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: ['Courier', 'Menlo', 'DejaVu Sans Mono'],
    fontSize: 14,
    color: Color(0xFF1E1E1E),
  );

  /// Whether the surrounding theme is dark. The token palette switches
  /// between the light (Notepad++) and dark (VS Code Dark+) maps so
  /// syntax colors keep readable contrast in both themes.
  bool _darkMode = false;

  set darkMode(bool value) {
    if (value == _darkMode) return;
    _darkMode = value;
    notifyListeners();
  }

  set baseStyle(TextStyle s) {
    if (s == _baseStyle) return;
    _baseStyle = s;
    notifyListeners();
  }

  void attach(HighlightPlugin? plugin, String language) {
    if (_plugin == plugin && _language == language) return;
    _plugin = plugin;
    _language = language;
    _lastTokenized = ''; // invalidate cache
    notifyListeners();
  }

  /// Set text without firing the editor kernel's change-driven undo
  /// (used when loading a file or applying a formatter).
  void setTextSilently(String text) {
    _lastTokenized = '';
    super.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final effectiveBase = (style ?? _baseStyle).copyWith(fontFamily: 'monospace');
    final text = this.text;
    if (text.isEmpty) return TextSpan(text: '', style: effectiveBase);

    final plugin = _plugin;
    final highlighter = plugin?.forLanguage(_language);
    if (highlighter == null) {
      return TextSpan(text: text, style: effectiveBase);
    }

    if (text != _lastTokenized) {
      _cached = highlighter.tokenize(text);
      _lastTokenized = text;
    }

    final spans = _cached;
    if (spans.isEmpty) {
      return TextSpan(text: text, style: effectiveBase);
    }

    final children = <InlineSpan>[];
    var cursor = 0;
    for (final s in spans) {
      if (s.start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, s.start), style: effectiveBase));
      }
      final end = (s.start + s.length).clamp(0, text.length);
      final seg = text.substring(s.start.clamp(0, text.length), end);
      if (seg.isNotEmpty) {
        children.add(TextSpan(
          text: seg,
          style: HighlightPalette.styleFor(s.kind, dark: _darkMode).copyWith(
            fontFamily: 'monospace',
            fontFamilyFallback: effectiveBase.fontFamilyFallback,
            fontSize: effectiveBase.fontSize,
          ),
        ));
      }
      cursor = end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor), style: effectiveBase));
    }
    return TextSpan(style: effectiveBase, children: children);
  }
}
