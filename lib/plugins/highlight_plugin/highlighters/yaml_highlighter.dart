part of '../highlight_plugin.dart';

/// YAML tokenizer: keys (before `:`) as [TokenKind.attr], string values
/// with quotes as [TokenKind.string], numbers / booleans / null as
/// [TokenKind.number] / [TokenKind.keyword], comments `#` as
/// [TokenKind.comment], list markers `-` and structural `:` as
/// [TokenKind.punctuation].
class YamlHighlighter implements Highlighter {
  @override
  String get language => 'yaml';

  static const Set<String> _scalars = {
    'true', 'false', 'yes', 'no', 'on', 'off', 'null', '~',
  };

  @override
  List<TokenSpan> tokenize(String text) {
    final spans = <TokenSpan>[];
    int i = 0;
    final n = text.length;
    while (i < n) {
      final ch = text[i];
      // Comment #...
      if (ch == '#' && (i == 0 || text[i - 1] == ' ' || text[i - 1] == '\t' || text[i - 1] == '\n')) {
        int end = i + 1;
        while (end < n && text[end] != '\n') end++;
        spans.add(TokenSpan(i, end - i, TokenKind.comment));
        i = end;
        continue;
      }
      // Quoted string '...' or "..."
      if (ch == "'" || ch == '"') {
        final quote = ch;
        int end = i + 1;
        while (end < n) {
          if (text[end] == '\\' && quote == '"') {
            end += 2;
            continue;
          }
          if (text[end] == quote) break;
          end++;
        }
        final stop = end < n ? end + 1 : n;
        spans.add(TokenSpan(i, stop - i, TokenKind.string));
        i = stop;
        continue;
      }
      // Key: at line start (after indent), identifier followed by ':'.
      if ((i == 0 || text[i - 1] == '\n') && (ch == ' ' || ch == '\t' || _isKeyStart(ch))) {
        // Skip leading whitespace.
        int j = i;
        while (j < n && (text[j] == ' ' || text[j] == '\t')) j++;
        if (j < n && text[j] == '-') {
          spans.add(TokenSpan(j, 1, TokenKind.punctuation));
          j++;
          while (j < n && (text[j] == ' ' || text[j] == '\t')) j++;
        }
        if (j < n && _isKeyStart(text[j])) {
          int keyEnd = j;
          while (keyEnd < n && text[keyEnd] != ':' && text[keyEnd] != '\n') keyEnd++;
          if (keyEnd < n && text[keyEnd] == ':') {
            // Trim trailing whitespace from key.
            int keyStop = keyEnd;
            while (keyStop > j && (text[keyStop - 1] == ' ' || text[keyStop - 1] == '\t')) keyStop--;
            spans.add(TokenSpan(j, keyStop - j, TokenKind.attr));
            spans.add(TokenSpan(keyEnd, 1, TokenKind.punctuation));
            // The whitespace before the colon stays plain.
            i = keyEnd + 1;
            continue;
          }
        }
      }
      // Number literal.
      if (_isDigit(ch) || (ch == '-' && i + 1 < n && _isDigit(text[i + 1]))) {
        int end = i + 1;
        while (end < n && !_isSpace(text[end]) && text[end] != ':' && text[end] != ',' && text[end] != '#') end++;
        final word = text.substring(i, end).trim();
        if (_looksLikeNumber(word)) {
          spans.add(TokenSpan(i, end - i, TokenKind.number));
          i = end;
          continue;
        }
      }
      // Scalar word (true/false/null etc.)
      if (_isIdentStart(ch)) {
        int end = i + 1;
        while (end < n && !_isSpace(text[end]) && text[end] != ':' && text[end] != ',' && text[end] != '#') end++;
        final word = text.substring(i, end).toLowerCase();
        if (_scalars.contains(word)) {
          spans.add(TokenSpan(i, end - i, TokenKind.keyword));
          i = end;
          continue;
        }
      }
      // Punctuation.
      if (ch == ':' || ch == ',' || ch == '-' || ch == '[' || ch == ']' || ch == '{' || ch == '}') {
        spans.add(TokenSpan(i, 1, TokenKind.punctuation));
        i++;
        continue;
      }
      spans.add(TokenSpan(i, 1, TokenKind.plain));
      i++;
    }
    return spans;
  }

  bool _isSpace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';
  bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
  bool _isIdentStart(String c) {
    final v = c.codeUnitAt(0);
    return (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) || c == '_';
  }
  bool _isKeyStart(String c) => _isIdentStart(c) || c == '"' || c == "'";

  bool _looksLikeNumber(String s) {
    if (s.isEmpty) return false;
    if (s == '0') return true;
    final re = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$');
    return re.hasMatch(s);
  }
}
