import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/editor_kernel/editor_state.dart';

/// A Notepad++-style hex viewer for binary files (.bin/.bit/.raw/.dat).
///
/// Layout (matching the user's spec):
///   ┌──────────┬─────────────────────────────────┬──────────────────┐
///   │ (offset) │ 0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F │ ASCII            │
///   ├──────────┼─────────────────────────────────┼──────────────────┤
///   │ 00000000 │ 48 65 6C 6C 6F 20 57 6F 72 6C 64 00 00 00 00 00 │ Hello World..... │
///   │ 00000010 │ ...                                       │ ...              │
///   └──────────┴─────────────────────────────────┴──────────────────┘
///
/// The hex area is editable; ASCII is derived from the bytes and shown
/// read-only. Editing invalid hex is rejected (keeps the last valid state).
class BinaryViewer extends StatefulWidget {
  const BinaryViewer({
    super.key,
    required this.tab,
    required this.onBytesChanged,
  });

  final EditorTabController tab;
  final ValueChanged<Uint8List> onBytesChanged;

  @override
  State<BinaryViewer> createState() => _BinaryViewerState();
}

class _BinaryViewerState extends State<BinaryViewer> {
  late final TextEditingController _hexController;
  late final ScrollController _scroll;
  String _lastValidHex = '';
  bool _syncing = false;

  static const int _bytesPerRow = 16;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    _hexController = TextEditingController(text: _bytesToHex(widget.tab.bytes ?? Uint8List(0)));
    _lastValidHex = _hexController.text;
    _hexController.addListener(_onHexChanged);
    widget.tab.addListener(_onTabChanged);
  }

  @override
  void didUpdateWidget(covariant BinaryViewer old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab) {
      old.tab.removeListener(_onTabChanged);
      widget.tab.addListener(_onTabChanged);
      _loadFromTab();
    }
  }

  @override
  void dispose() {
    widget.tab.removeListener(_onTabChanged);
    _hexController.removeListener(_onHexChanged);
    _hexController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_syncing) return;
    // If bytes were changed externally (e.g. reload), reload the view.
    final currentHex = _bytesToHex(widget.tab.bytes ?? Uint8List(0));
    if (currentHex != _hexController.text.replaceAll(RegExp(r'\s+'), '').toUpperCase()) {
      _loadFromTab();
    }
  }

  void _loadFromTab() {
    _syncing = true;
    final hex = _bytesToHex(widget.tab.bytes ?? Uint8List(0));
    _hexController.text = hex;
    _lastValidHex = hex;
    _syncing = false;
  }

  void _onHexChanged() {
    if (_syncing) return;
    final cleaned = _hexController.text.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    // Validate: must be even-length hex digits.
    if (cleaned.length.isOdd || !RegExp(r'^[0-9A-F]*$').hasMatch(cleaned)) {
      // Reject invalid input by restoring the last valid state.
      _syncing = true;
      _hexController.text = _lastValidHex;
      _hexController.selection = TextSelection.fromPosition(
        TextPosition(offset: _hexController.text.length),
      );
      _syncing = false;
      return;
    }
    _lastValidHex = _hexController.text;
    final bytes = _hexToBytes(cleaned);
    widget.onBytesChanged(bytes);
    setState(() {});
  }

  /// Format raw bytes into a multi-line hex string: 16 bytes per row,
  /// space-separated, e.g. "48 65 6C 6C 6F 20 57 6F 72 6C 64 00 00 00 00 00".
  String _bytesToHex(Uint8List bytes) {
    final buf = StringBuffer();
    for (int i = 0; i < bytes.length; i++) {
      if (i > 0 && i % _bytesPerRow == 0) buf.write('\n');
      buf.write(bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase());
      if ((i + 1) % _bytesPerRow != 0) buf.write(' ');
    }
    return buf.toString();
  }

  Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final fg = isDark ? const Color(0xFFD4D4D4) : const Color(0xFF1E1E1E);
    final addrFg = isDark ? const Color(0xFF4E9A06) : const Color(0xFF0A8754);
    final asciiFg = isDark ? const Color(0xFFCE9178) : const Color(0xFFA31515);
    final headerBg = isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3);
    final bytes = widget.tab.bytes ?? Uint8List(0);

    // Build the ASCII column text aligned with the hex rows.
    final asciiLines = <String>[];
    for (int i = 0; i < bytes.length; i += _bytesPerRow) {
      final end = (i + _bytesPerRow > bytes.length) ? bytes.length : i + _bytesPerRow;
      final line = StringBuffer();
      for (int j = i; j < end; j++) {
        final b = bytes[j];
        line.write((b >= 0x20 && b < 0x7F) ? String.fromCharCode(b) : '.');
      }
      asciiLines.add(line.toString());
    }

    return Container(
      color: bg,
      child: Column(
        children: [
          // Header row: address | 0 1 2 ... F | ASCII
          Container(
            color: headerBg,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text('偏移', style: TextStyle(color: addrFg, fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: Text(
                    '0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F',
                    style: TextStyle(color: fg, fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: Text('ASCII', style: TextStyle(color: asciiFg, fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Body: three columns (address gutter, hex editor, ASCII view)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Address gutter (left)
                Container(
                  width: 90,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF7F7F7),
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: (bytes.length / _bytesPerRow).ceil().clamp(1, 1 << 30),
                    itemBuilder: (context, i) {
                      final addr = (i * _bytesPerRow).toRadixString(16).padLeft(8, '0').toUpperCase();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(addr, style: TextStyle(color: addrFg, fontSize: 12, fontFamily: 'monospace')),
                      );
                    },
                  ),
                ),
                VerticalDivider(width: 1, color: isDark ? const Color(0xFF333) : const Color(0xFFE0E0E0)),
                // Hex editor (middle)
                Expanded(
                  child: TextField(
                    controller: _hexController,
                    scrollController: _scroll,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: TextStyle(color: fg, fontSize: 12, fontFamily: 'monospace', height: 1.4),
                    cursorColor: const Color(0xFF007ACC),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                VerticalDivider(width: 1, color: isDark ? const Color(0xFF333) : const Color(0xFFE0E0E0)),
                // ASCII view (right)
                Container(
                  width: 150,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF7F7F7),
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: asciiLines.isEmpty ? 1 : asciiLines.length,
                    itemBuilder: (context, i) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          i < asciiLines.length ? asciiLines[i] : '',
                          style: TextStyle(color: asciiFg, fontSize: 12, fontFamily: 'monospace', height: 1.4),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
