part of '../highlight_plugin.dart';

/// CSS tokenizer: selectors as [TokenKind.tag], property names as
/// [TokenKind.attr], property values as [TokenKind.plain] with numbers
/// [TokenKind.number] and string values [TokenKind.string], `@` rules
/// as [TokenKind.keyword], comments `/* */` as [TokenKind.comment].
class CssHighlighter implements Highlighter {
  @override
  String get language => 'css';

  @override
  List<TokenSpan> tokenize(String text) {
    final spans = <TokenSpan>[];
    int i = 0;
    final n = text.length;
    int depth = 0; // brace depth: 0 = selector context, 1+ = declaration
    while (i < n) {
      final ch = text[i];
      // Comment /* ... */
      if (ch == '/' && i + 1 < n && text[i + 1] == '*') {
        int end = i + 2;
        while (end < n && !(text[end] == '*' && end + 1 < n && text[end + 1] == '/')) end++;
        final stop = end + 2 <= n ? end + 2 : n;
        spans.add(TokenSpan(i, stop - i, TokenKind.comment));
        i = stop;
        continue;
      }
      // @rule (e.g. @media, @import, @keyframes)
      if (ch == '@') {
        int end = i + 1;
        while (end < n && !_isSpace(text[end]) && text[end] != '{' && text[end] != ';' && text[end] != '(') end++;
        spans.add(TokenSpan(i, end - i, TokenKind.keyword));
        i = end;
        continue;
      }
      // String "..." or '...'
      if (ch == '"' || ch == "'") {
        final quote = ch;
        int end = i + 1;
        while (end < n) {
          if (text[end] == '\\') {
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
      // Braces track selector vs declaration context.
      if (ch == '{') {
        spans.add(TokenSpan(i, 1, TokenKind.punctuation));
        depth++;
        i++;
        continue;
      }
      if (ch == '}') {
        spans.add(TokenSpan(i, 1, TokenKind.punctuation));
        if (depth > 0) depth--;
        i++;
        continue;
      }
      // Colon inside declaration: the token before it is a property name.
      if (ch == ':' && depth > 0) {
        // Find the preceding identifier and reclassify it as attr.
        int nameEnd = i;
        int nameStart = i;
        while (nameStart > 0 && !_isSpace(text[nameStart - 1]) && text[nameStart - 1] != ';' && text[nameStart - 1] != '{') {
          nameStart--;
        }
        if (nameEnd > nameStart) {
          spans.add(TokenSpan(nameStart, nameEnd - nameStart, TokenKind.attr));
        }
        spans.add(TokenSpan(i, 1, TokenKind.punctuation));
        i++;
        continue;
      }
      // Semicolon / colon (outside declaration) punctuation.
      if (ch == ';' || ch == ':') {
        spans.add(TokenSpan(i, 1, TokenKind.punctuation));
        i++;
        continue;
      }
      // Number literal.
      if (_isDigit(ch) || (ch == '#' && i + 1 < n && _isHex(text[i + 1]))) {
        int end = i + 1;
        while (end < n && (_isHex(text[end]) || text[end] == '.' || text[end] == '%' || text[end] == '-' ||
            _isLetter(text[end]))) end++;
        spans.add(TokenSpan(i, end - i, TokenKind.number));
        i = end;
        continue;
      }
      // Identifier.
      if (_isIdentStart(ch)) {
        int end = i + 1;
        while (end < n && _isIdent(text[end])) end++;
        if (depth == 0) {
          // Selector context: tag/class/id names as tag.
          spans.add(TokenSpan(i, end - i, TokenKind.tag));
        } else {
          spans.add(TokenSpan(i, end - i, TokenKind.plain));
        }
        i = end;
        continue;
      }
      spans.add(TokenSpan(i, 1, TokenKind.plain));
      i++;
    }
    return spans;
  }

  bool _isSpace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';
  bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
  bool _isHex(String c) {
    final v = c.codeUnitAt(0);
    return (v >= 0x30 && v <= 0x39) || (v >= 0x41 && v <= 0x46) || (v >= 0x61 && v <= 0x66);
  }
  bool _isLetter(String c) {
    final v = c.codeUnitAt(0);
    return (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A);
  }
  bool _isIdentStart(String c) => _isLetter(c) || c == '_' || c == '-' || c == '.' || c == '#';
  bool _isIdent(String c) => _isIdentStart(c) || _isDigit(c);
}
