part of '../highlight_plugin.dart';

/// JSON tokenizer: keys (string followed by `:`) are highlighted as
/// [TokenKind.attr], other strings as [TokenKind.string], numbers as
/// [TokenKind.number], `true`/`false`/`null` as [TokenKind.keyword], and
/// structural punctuation `{ } [ ] : ,` as [TokenKind.punctuation].
class JsonHighlighter implements Highlighter {
  @override
  String get language => 'json';

  @override
  List<TokenSpan> tokenize(String text) {
    final spans = <TokenSpan>[];
    int i = 0;
    final n = text.length;
    while (i < n) {
      final ch = text[i];
      if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
        i++;
        continue;
      }
      if (ch == '"') {
        // String literal, scan to closing quote honoring escapes.
        int end = i + 1;
        while (end < n) {
          if (text[end] == '\\') {
            end += 2;
            continue;
          }
          if (text[text.length == end ? 0 : end] == '"') break;
          end++;
        }
        end = end < n ? end : n - 1;
        final strLen = end - i + 1;
        // Look ahead: is the next non-space char a ':' ? -> it's a key.
        int k = end + 1;
        while (k < n && (text[k] == ' ' || text[k] == '\t' || text[k] == '\n' || text[k] == '\r')) {
          k++;
        }
        final isKey = k < n && text[k] == ':';
        spans.add(TokenSpan(i, strLen, isKey ? TokenKind.attr : TokenKind.string));
        i = end + 1;
        continue;
      }
      if (_isDigit(ch) || (ch == '-' && i + 1 < n && _isDigit(text[i + 1]))) {
        int end = i + 1;
        while (end < n && (_isDigit(text[end]) || text[end] == '.' || text[end] == 'e' || text[end] == 'E' || text[end] == '+' || text[end] == '-')) {
          end++;
        }
        spans.add(TokenSpan(i, end - i, TokenKind.number));
        i = end;
        continue;
      }
      if (_isIdentStart(ch)) {
        int end = i + 1;
        while (end < n && _isIdent(text[end])) {
          end++;
        }
        final word = text.substring(i, end);
        if (word == 'true' || word == 'false' || word == 'null') {
          spans.add(TokenSpan(i, end - i, TokenKind.keyword));
        } else {
          spans.add(TokenSpan(i, end - i, TokenKind.plain));
        }
        i = end;
        continue;
      }
      // Punctuation.
      spans.add(TokenSpan(i, 1, TokenKind.punctuation));
      i++;
    }
    return spans;
  }

  bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
  bool _isIdentStart(String c) =>
      (c.codeUnitAt(0) >= 0x41 && c.codeUnitAt(0) <= 0x5A) ||
      (c.codeUnitAt(0) >= 0x61 && c.codeUnitAt(0) <= 0x7A) ||
      c == '_';
  bool _isIdent(String c) => _isIdentStart(c) || _isDigit(c);
}
