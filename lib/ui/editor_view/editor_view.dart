import 'package:flutter/material.dart';

import '../../core/editor_kernel/editor_state.dart';
import '../../plugins/highlight_plugin/highlight_plugin.dart';
import 'highlighting_controller.dart';

/// Renders the active tab's editor surface: a line-number gutter on the
/// left and the editable, syntax-highlighted text field on the right.
/// The gutter is a single [Text] widget translated by the editor's scroll
/// offset so it stays aligned with the buffer as the user scrolls.
class EditorView extends StatefulWidget {
  const EditorView({
    super.key,
    required this.tab,
    required this.highlightPlugin,
    required this.onTextChanged,
    required this.onSelectionChanged,
    required this.onControllerAttached,
    required this.onControllerDetached,
  });

  final EditorTabController tab;
  final HighlightPlugin? highlightPlugin;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<TextSelection> onSelectionChanged;
  final ValueChanged<HighlightingController> onControllerAttached;
  final ValueChanged<HighlightingController> onControllerDetached;

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
  late final HighlightingController _controller;
  late final ScrollController _scroll;
  bool _syncing = false;
  double _scrollOffset = 0;

  static const TextStyle _baseStyle = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: ['Courier', 'Menlo', 'DejaVu Sans Mono'],
    fontSize: 14,
    height: 1.4,
    color: Color(0xFF1E1E1E),
  );

  @override
  void initState() {
    super.initState();
    _controller = HighlightingController(text: widget.tab.text)
      ..attach(widget.highlightPlugin, widget.tab.language);
    _controller.addListener(_onControllerChanged);
    _scroll = ScrollController()..addListener(_onScroll);
    widget.tab.addListener(_onTabChanged);
    widget.onControllerAttached(_controller);
  }

  @override
  void didUpdateWidget(covariant EditorView old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab) {
      old.tab.removeListener(_onTabChanged);
      widget.tab.addListener(_onTabChanged);
      _controller.attach(widget.highlightPlugin, widget.tab.language);
      _syncing = true;
      _controller.setTextSilently(widget.tab.text);
      _syncing = false;
    } else if (old.tab.language != widget.tab.language ||
        old.highlightPlugin != widget.highlightPlugin) {
      _controller.attach(widget.highlightPlugin, widget.tab.language);
    }
  }

  @override
  void dispose() {
    widget.onControllerDetached(_controller);
    widget.tab.removeListener(_onTabChanged);
    _controller.removeListener(_onControllerChanged);
    _scroll.removeListener(_onScroll);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_syncing) return;
    _syncing = true;
    if (_controller.text != widget.tab.text) {
      _controller.setTextSilently(widget.tab.text);
    }
    _controller.attach(widget.highlightPlugin, widget.tab.language);
    _syncing = false;
  }

  void _onControllerChanged() {
    if (_syncing) return;
    widget.onTextChanged(_controller.text);
    final sel = _controller.selection;
    if (sel.isValid) widget.onSelectionChanged(sel);
  }

  void _onScroll() {
    setState(() => _scrollOffset = _scroll.hasClients ? _scroll.offset : 0);
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gutterBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3);
    final gutterFg = isDark ? const Color(0xFF6E6E6E) : const Color(0xFF858585);
    final divider = isDark ? const Color(0xFF2D2D30) : const Color(0xFFE0E0E0);
    final textColor = isDark ? const Color(0xFFD4D4D4) : const Color(0xFF1E1E1E);

    final lineCount = '\n'.allMatches(tab.text).length + 1;
    final gutterText = List.generate(lineCount, (i) => '${i + 1}').join('\n');

    // Push the theme-aware base style into the highlighting controller so
    // syntax highlighting re-tokenizes against the right foreground color.
    final base = _baseStyle.copyWith(color: textColor);
    _controller.baseStyle = base;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Line-number gutter.
        Container(
          width: 52,
          color: gutterBg,
          padding: const EdgeInsets.only(top: 8, right: 6),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topRight,
              minWidth: 40,
              maxWidth: 40,
              maxHeight: double.infinity,
              child: Transform.translate(
                offset: Offset(0, -_scrollOffset),
                child: Text(
                  gutterText,
                  textAlign: TextAlign.right,
                  style: base.copyWith(
                    color: gutterFg,
                    fontSize: 13,
                    height: base.height,
                  ),
                ),
              ),
            ),
          ),
        ),
        VerticalDivider(width: 1, color: divider),
        // Editable area.
        Expanded(
          child: TextField(
            controller: _controller,
            scrollController: _scroll,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: base,
            cursorColor: const Color(0xFF007ACC),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: InputBorder.none,
              isDense: true,
            ),
            onChanged: null,
          ),
        ),
      ],
    );
  }
}
