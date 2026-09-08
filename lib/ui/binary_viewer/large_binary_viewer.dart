import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/editor_kernel/editor_state.dart';
import 'binary_data_source.dart';

/// Read-only hex viewer for large binary files (.exe/.apk/.bin…).
///
/// Unlike [BinaryViewer], which holds the whole file in memory and lets the
/// user edit it, this viewer binds a [FileBinaryDataSource] and loads byte
/// ranges on demand. `ListView.builder` only builds the rows that are on
/// screen; each row pulls its bytes from a small chunk cache, so scrolling a
/// multi-hundred-megabyte file never loads it all into RAM.
///
/// ## Extension points (frame length / frame count / keyword search)
/// The viewer is deliberately parameterised for the features planned next:
///   * [bytesPerRow] is the "frame length" — change it to view data aligned
///     on packet/frame boundaries instead of fixed 16-byte rows. It is
///     exposed in the toolbar.
///   * The data source already defines `search(pattern)`; the toolbar wires
///     that into a keyword finder that scrolls to the first match.
///   * Row data is produced by [BinaryDataSource.readRange] through the
///     [_RowData] adapter, so a future frame-aware source can be dropped in
///     without touching the rendering code here.
class LargeBinaryViewer extends StatefulWidget {
  const LargeBinaryViewer({
    super.key,
    required this.tab,
    this.bytesPerRow = 16,
  });

  final EditorTabController tab;

  /// Bytes shown per row (the "frame length"). 8/16/32 are offered in the
  /// toolbar; any positive value works.
  final int bytesPerRow;

  /// Valid frame lengths offered in the toolbar.
  static const List<int> frameLengthOptions = [8, 16, 32];

  @override
  State<LargeBinaryViewer> createState() => _LargeBinaryViewerState();
}

class _LargeBinaryViewerState extends State<LargeBinaryViewer> {
  late BinaryDataSource _source;
  late int _bytesPerRow;
  int _length = 0;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  /// Row index -> parsed hex/ascii. Only rows on/near the viewport are kept.
  final Map<int, _RowData> _rows = {};

  /// Byte offsets of windows already parsed into [_rows], to avoid re-reading.
  final Set<int> _loadedWindows = {};

  /// Byte windows read at a time (a few screens of hex).
  static const int _windowBytes = 16 * 1024;

  /// Current keyword match (byte offset), for "find next" and highlighting.
  int _lastMatch = -1;
  int? _highlightRow;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _bytesPerRow = widget.bytesPerRow;
    _source = FileBinaryDataSource(File(widget.tab.path!));
    _length = _source.length > 0 ? _source.length : widget.tab.largeBinaryLength;
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadWindow(0));
  }

  @override
  void didUpdateWidget(covariant LargeBinaryViewer old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab) {
      _source.dispose();
      _source = FileBinaryDataSource(File(widget.tab.path!));
      _length = _source.length > 0 ? _source.length : widget.tab.largeBinaryLength;
      _rows.clear();
      _loadedWindows.clear();
      _lastMatch = -1;
      _highlightRow = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadWindow(0));
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchController.dispose();
    _source.dispose();
    super.dispose();
  }

  // ---- On-demand loading --------------------------------------------------

  int get _rowCount => _length == 0 ? 0 : (_length / _bytesPerRow).ceil();

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final rows = _rowCount;
    if (rows == 0) return;
    final offset = _scroll.offset;
    final viewport = _scroll.position.viewportDimension;
    final firstRow = (offset / _rowHeight).floor().clamp(0, rows - 1).toInt();
    final lastRow =
        ((offset + viewport) / _rowHeight).ceil().clamp(0, rows - 1).toInt();
    _loadWindow(firstRow);
    if (lastRow != firstRow) _loadWindow(lastRow);
  }

  /// Ensure the byte window containing [row] is read and parsed into [_rows].
  Future<void> _loadWindow(int row) async {
    if (_length == 0) return;
    final rowStart = row * _bytesPerRow;
    final windowStart = (rowStart ~/ _windowBytes) * _windowBytes;
    if (_loadedWindows.contains(windowStart)) return;
    _loadedWindows.add(windowStart);

    final windowEnd = (windowStart + _windowBytes).clamp(0, _length);
    final bytes = await _source.readRange(windowStart, windowEnd);
    if (!mounted) return;

    setState(() {
      final firstRow = windowStart ~/ _bytesPerRow;
      int r = firstRow;
      while (r * _bytesPerRow < windowStart + bytes.length) {
        final inStart = r * _bytesPerRow - windowStart;
        if (inStart >= bytes.length) break;
        final inEnd = (inStart + _bytesPerRow).clamp(0, bytes.length);
        _rows[r] = _RowData.fromBytes(Uint8List.sublistView(bytes, inStart, inEnd));
        r++;
      }
    });
  }

  // ---- Searching (keyword / pattern) --------------------------------------

  /// Parse the search box into a byte pattern. Hex input (e.g. "48 65" or
  /// "4865") is treated as bytes; anything else is UTF-8 text.
  List<int>? _parsePattern(String input) {
    if (input.isEmpty) return null;
    final compact = input.replaceAll(' ', '');
    if (compact.length.isEven &&
        RegExp(r'^[0-9A-Fa-f]+$').hasMatch(compact)) {
      final bytes = <int>[];
      for (int i = 0; i < compact.length; i += 2) {
        bytes.add(int.parse(compact.substring(i, i + 2), radix: 16));
      }
      return bytes;
    }
    return utf8.encode(input);
  }

  Future<void> _find({required bool next}) async {
    if (_searching) return;
    final pattern = _parsePattern(_searchController.text.trim());
    if (pattern == null) {
      _showHint('请输入关键字或十六进制字节');
      return;
    }
    setState(() => _searching = true);
    final start = next && _lastMatch >= 0 ? _lastMatch + 1 : 0;
    final found = await _source.search(pattern, start: start);
    if (!mounted) return;
    setState(() => _searching = false);

    if (found < 0) {
      // Wrap once: if we started past 0, try from the top.
      if (start > 0) {
        final wrapped = await _source.search(pattern, start: 0);
        if (!mounted) return;
        if (wrapped >= 0) {
          _onMatch(wrapped);
          return;
        }
      }
      _showHint('未找到关键字');
      return;
    }
    _onMatch(found);
  }

  void _onMatch(int offset) {
    final row = offset ~/ _bytesPerRow;
    setState(() {
      _lastMatch = offset;
      _highlightRow = row;
    });
    _loadWindow(row).then((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = (row * _rowHeight)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _showHint(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message),
          duration: const Duration(seconds: 2)));
  }

  // ---- Rendering ----------------------------------------------------------

  // Fixed row height so empty (not-yet-loaded) rows occupy the same space as
  // filled ones, keeping scroll math deterministic.
  static const double _rowHeight = 18.0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final fg = isDark ? const Color(0xFFD4D4D4) : const Color(0xFF1E1E1E);
    final addrFg = isDark ? const Color(0xFF4E9A06) : const Color(0xFF0A8754);
    final asciiFg = isDark ? const Color(0xFFCE9178) : const Color(0xFFA31515);
    final headerBg = isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3);

    final frameCount = _length == 0 ? 0 : (_length / _bytesPerRow).ceil();

    return Container(
      color: bg,
      child: Column(
        children: [
          _Toolbar(
            bytesPerRow: _bytesPerRow,
            length: _length,
            frameCount: frameCount,
            searchController: _searchController,
            searching: _searching,
            onFrameLengthChanged: _setFrameLength,
            onFind: () => _find(next: false),
            onFindNext: () => _find(next: true),
            onClearSearch: _clearSearch,
          ),
          const Divider(height: 1),
          // Header row: offset | 0 1 2 ... F | ASCII
          Container(
            color: headerBg,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text('偏移',
                      style: TextStyle(color: addrFg, fontSize: 12,
                          fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: Text(_hexHeader(),
                      style: TextStyle(color: fg, fontSize: 12,
                          fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                ),
                SizedBox(
                  width: 150,
                  child: Text('ASCII',
                      style: TextStyle(color: asciiFg, fontSize: 12,
                          fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _length == 0
                ? Center(child: Text('空文件', style: TextStyle(color: fg)))
                : ListView.builder(
                    controller: _scroll,
                    itemCount: _rowCount,
                    itemExtent: _rowHeight,
                    itemBuilder: (context, i) {
                      final data = _rows[i];
                      if (data == null) {
                        // Fire a load for the window under this row; it's
                        // idempotent thanks to [_loadedWindows].
                        _loadWindow(i);
                      }
                      return _RowView(
                        rowIndex: i,
                        data: data,
                        bytesPerRow: _bytesPerRow,
                        height: _rowHeight,
                        highlighted: i == _highlightRow,
                        addrFg: addrFg,
                        fg: fg,
                        asciiFg: asciiFg,
                        isDark: isDark,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _hexHeader() {
    final b = StringBuffer();
    for (int i = 0; i < _bytesPerRow; i++) {
      if (i > 0) b.write('  ');
      b.write(i.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
    return b.toString();
  }

  void _setFrameLength(int value) {
    if (value == _bytesPerRow) return;
    setState(() {
      _bytesPerRow = value;
      _rows.clear();
      _loadedWindows.clear();
      _lastMatch = -1;
      _highlightRow = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _loadWindow(0);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _lastMatch = -1;
      _highlightRow = null;
    });
  }
}

/// One parsed row of hex/ascii, generated lazily from a byte slice.
class _RowData {
  _RowData.fromBytes(Uint8List bytes)
      : hex = _hex(bytes),
        asciiText = _ascii(bytes);

  final String hex;
  final String asciiText;

  static String _hex(Uint8List b) {
    final s = StringBuffer();
    for (int i = 0; i < b.length; i++) {
      if (i > 0) s.write(' ');
      s.write(b[i].toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return s.toString();
  }

  static String _ascii(Uint8List b) {
    final s = StringBuffer();
    for (final byte in b) {
      s.write((byte >= 0x20 && byte < 0x7F) ? String.fromCharCode(byte) : '.');
    }
    return s.toString();
  }
}

class _RowView extends StatelessWidget {
  const _RowView({
    required this.rowIndex,
    required this.data,
    required this.bytesPerRow,
    required this.height,
    required this.highlighted,
    required this.addrFg,
    required this.fg,
    required this.asciiFg,
    required this.isDark,
  });

  final int rowIndex;
  final _RowData? data;
  final int bytesPerRow;
  final double height;
  final bool highlighted;
  final Color addrFg;
  final Color fg;
  final Color asciiFg;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final addr = (rowIndex * bytesPerRow)
        .toRadixString(16)
        .padLeft(8, '0')
        .toUpperCase();
    final highlightColor = isDark ? const Color(0xFF5A3212) : const Color(0xFFFFE0A3);
    final textStyle = TextStyle(
        fontSize: 12, fontFamily: 'monospace', height: 1.3, color: fg);

    return Container(
      height: height,
      color: highlighted ? highlightColor : null,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(addr,
                style: TextStyle(
                    color: addrFg, fontSize: 12, fontFamily: 'monospace', height: 1.3)),
          ),
          Expanded(
            child: Text(data?.hex ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle),
          ),
          SizedBox(
            width: 150,
            child: Text(data?.asciiText ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: asciiFg, fontSize: 12, fontFamily: 'monospace', height: 1.3)),
          ),
        ],
      ),
    );
  }
}

/// Compact toolbar: frame-length selector, size/frame-count readout, and a
/// keyword search box.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.bytesPerRow,
    required this.length,
    required this.frameCount,
    required this.searchController,
    required this.searching,
    required this.onFrameLengthChanged,
    required this.onFind,
    required this.onFindNext,
    required this.onClearSearch,
  });

  final int bytesPerRow;
  final int length;
  final int frameCount;
  final TextEditingController searchController;
  final bool searching;
  final ValueChanged<int> onFrameLengthChanged;
  final VoidCallback onFind;
  final VoidCallback onFindNext;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3);
    final fg = isDark ? Colors.white70 : Colors.black87;

    return Container(
      color: surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const Text('帧长', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          DropdownButton<int>(
            value: bytesPerRow,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final v in LargeBinaryViewer.frameLengthOptions)
                DropdownMenuItem(value: v, child: Text('$v', style: const TextStyle(fontSize: 12))),
            ],
            onChanged: (v) {
              if (v != null) onFrameLengthChanged(v);
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$length 字节 · $frameCount 帧',
              style: TextStyle(fontSize: 12, color: fg),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 160,
            height: 28,
            child: TextField(
              controller: searchController,
              onSubmitted: (_) => onFindNext(),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: '关键字 / 十六进制',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                suffixIcon: ValueListenableBuilder(
                  valueListenable: searchController,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.clear, size: 14),
                          onPressed: onClearSearch,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '查找',
            icon: searching
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search, size: 18),
            onPressed: onFind,
          ),
          IconButton(
            tooltip: '下一个',
            icon: const Icon(Icons.arrow_downward, size: 18),
            onPressed: onFindNext,
          ),
        ],
      ),
    );
  }
}