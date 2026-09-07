import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// A single open document in a tab. Holds the editable text, its file
/// metadata, the detected/assigned language id, and an undo/redo history.
///
/// This is the editor kernel's atomic unit; the UI binds one
/// [EditorTabController] per tab and renders it through the editor view.
class EditorTabController extends ChangeNotifier {
  EditorTabController({String label = '新建文件'}) : _label = label;

  String _label;
  String? _path;
  String _text = '';
  String _encoding = 'UTF-8';
  String _language = 'txt';
  bool _dirty = false;
  int _cursorOffset = 0;
  int _selectionEnd = 0;

  /// Raw bytes for binary files (.bin/.bit/.raw/.dat). When non-null the
  /// tab is rendered by the binary viewer instead of the text editor.
  Uint8List? _bytes;

  // Undo/redo stacks. Entries are full snapshots to keep the kernel tiny;
  // a future "coalescing" plugin can replace this without touching the UI.
  final List<String> _undo = [];
  final List<String> _redo = [];
  static const int _maxHistory = 500;

  String get label => _label;
  String? get path => _path;
  String get text => _text;
  String get encoding => _encoding;
  String get language => _language;
  bool get dirty => _dirty;
  int get cursorOffset => _cursorOffset;
  int get selectionEnd => _selectionEnd;
  Uint8List? get bytes => _bytes;
  bool get isBinary => _bytes != null;

  set text(String value) {
    if (value == _text) return;
    _pushUndo();
    _text = value;
    _dirty = true;
    notifyListeners();
  }

  void setSelection(int start, int end) {
    _cursorOffset = start;
    _selectionEnd = end;
    notifyListeners();
  }

  void bindFile({
    required String? path,
    required String content,
    required String encoding,
    required String language,
  }) {
    _path = path;
    _text = content;
    _encoding = encoding;
    _language = language;
    _dirty = false;
    _undo.clear();
    _redo.clear();
    _cursorOffset = content.length;
    _selectionEnd = content.length;
    _label = path == null ? '新建文件' : _baseName(path);
    notifyListeners();
  }

  void markSaved({required String path, required String encoding}) {
    _path = path;
    _encoding = encoding;
    _dirty = false;
    _label = _baseName(path);
    notifyListeners();
  }

  /// Bind a binary file (.bin/.bit/.raw/.dat). Stores raw bytes and sets
  /// the language to 'binary' so the UI renders the hex viewer.
  void bindBinary({
    required String path,
    required Uint8List bytes,
  }) {
    _path = path;
    _bytes = bytes;
    _language = 'binary';
    _encoding = 'BINARY';
    _dirty = false;
    _undo.clear();
    _redo.clear();
    _cursorOffset = 0;
    _selectionEnd = 0;
    _label = _baseName(path);
    notifyListeners();
  }

  /// Replace the binary bytes (after editing in the hex viewer).
  void updateBytes(Uint8List bytes) {
    _bytes = bytes;
    _dirty = true;
    notifyListeners();
  }

  /// Update the language id (e.g. after a "save as" to a new extension).
  /// Does not clear undo history or touch the text.
  void setLanguage(String language) {
    if (language == _language) return;
    _language = language;
    notifyListeners();
  }

  /// Update the encoding label (e.g. when the user switches encoding from
  /// the status bar / menu). Does not re-read the file; the next save will
  /// use this encoding. To re-read the file with a different encoding, use
  /// the service's [switchEncoding] which re-decodes the bytes.
  void setEncoding(String encoding) {
    if (encoding == _encoding) return;
    _encoding = encoding;
    notifyListeners();
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_text);
    _text = _undo.removeLast();
    _dirty = true;
    _cursorOffset = _text.length;
    _selectionEnd = _text.length;
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_text);
    _text = _redo.removeLast();
    _dirty = true;
    _cursorOffset = _text.length;
    _selectionEnd = _text.length;
    notifyListeners();
  }

  void _pushUndo() {
    _undo.add(_text);
    if (_undo.length > _maxHistory) _undo.removeAt(0);
    _redo.clear();
  }

  String _baseName(String path) {
    final i = path.lastIndexOf(RegExp(r'[/\\]'));
    return i == -1 ? path : path.substring(i + 1);
  }

  /// Selected substring (may be empty). Used by voice / format plugins.
  String get selectedText {
    final start = _cursorOffset < _selectionEnd ? _cursorOffset : _selectionEnd;
    final end = _cursorOffset < _selectionEnd ? _selectionEnd : _cursorOffset;
    if (start < 0 || end > _text.length || start >= end) return '';
    return _text.substring(start, end);
  }
}

/// Cursor position expressed as 1-based line / column, computed from the
/// controller's current offset. Shown in the status bar.
class CursorPosition {
  final int line;
  final int column;
  const CursorPosition(this.line, this.column);

  static CursorPosition fromOffset(String text, int offset) {
    if (offset < 0) offset = 0;
    if (offset > text.length) offset = text.length;
    int line = 1;
    int lastBreak = -1;
    for (int i = 0; i < offset; i++) {
      if (text[i] == '\n') {
        line++;
        lastBreak = i;
      }
    }
    final column = offset - lastBreak;
    return CursorPosition(line, column);
  }
}
