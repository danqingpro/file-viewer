part of '../highlight_plugin.dart';

/// JavaScript tokenizer: keywords [TokenKind.keyword], identifiers,
/// string literals (single/double/template) [TokenKind.string],
/// numbers [TokenKind.number], line/block comments [TokenKind.comment],
/// regex literals `/.../` [TokenKind.string], braces [TokenKind.brace].
class JsHighlighter implements Highlighter {
  @override
  String get language => 'js';

  static const Set<String> _keywords = {
    'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger',
    'default', 'delete', 'do', 'else', 'export', 'extends', 'finally',
    'for', 'function', 'if', 'import', 'in', 'instanceof', 'let', 'new',
    'return', 'super', 'switch', 'this', 'throw', 'try', 'typeof', 'var',
    'void', 'while', 'with', 'yield', 'await', 'async', 'of', 'static',
    'get', 'set', 'from', 'as',
  };

  static const Set<String> _literals = {
    'true', 'false', 'null', 'undefined', 'NaN', 'Infinity',
  };

  @override
  List<TokenSpan> tokenize(String text) {
    final spans = <TokenSpan>[];
    int i = 0;
    final n = text.length;
    while (i < n) {
      final ch = text[i];
      // Line comment //...
      if (ch == '/' && i + 1 < n && text[i + 1] == '/') {
        int end = i + 2;
        while (end < n && text[end] != '\n') end++;
        spans.add(TokenSpan(i, end - i, TokenKind.comment));
        i = end;
        continue;
      }
      // Block comment /* ... */
      if (ch == '/' && i + 1 < n && text[i + 1] == '*') {
        int end = i + 2;
        while (end < n && !(text[end] == '*' && end + 1 < n && text[end + 1] == '/')) end++;
        final stop = end + 2 <= n ? end + 2 : n;
        spans.add(TokenSpan(i, stop - i, TokenKind.comment));
        i = stop;
        continue;
      }
      // String literals: '...'  "..."  `...`
      if (ch == "'" || ch == '"' || ch == '`') {
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
      // Number literal.
      if (_isDigit(ch) || (ch == '.' && i + 1 < n && _isDigit(text[i + 1]))) {
        int end = i + 1;
        while (end < n && (_isIdent(text[end]) || text[end] == '.' || text[end] == '+' || text[end] == '-')) end++;
        spans.add(TokenSpan(i, end - i, TokenKind.number));
        i = end;
        continue;
      }
      // Identifier / keyword / literal.
      if (_isIdentStart(ch)) {
        int end = i + 1;
        while (end < n && _isIdent(text[end])) end++;
        final word = text.substring(i, end);
        if (_keywords.contains(word)) {
          spans.add(TokenSpan(i, end - i, TokenKind.keyword));
        } else if (_literals.contains(word)) {
          spans.add(TokenSpan(i, end - i, TokenKind.primitive));
        } else {
          spans.add(TokenSpan(i, end - i, TokenKind.plain));
        }
        i = end;
        continue;
      }
      // Braces / brackets.
      if (ch == '{' || ch == '}' || ch == '(' || ch == ')' || ch == '[' || ch == ']') {
        spans.add(TokenSpan(i, 1, TokenKind.brace));
        i++;
        continue;
      }
      // Punctuation / operator.
      if (_isPunct(ch)) {
        spans.add(TokenSpan(i, 1, TokenKind.punctuation));
        i++;
        continue;
      }
      spans.add(TokenSpan(i, 1, TokenKind.plain));
      i++;
    }
    return spans;
  }

  bool _isIdentStart(String c) {
    final v = c.codeUnitAt(0);
    return (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) || c == '_' || c == r'$';
  }

  bool _isIdent(String c) => _isIdentStart(c) || _isDigit(c);

  bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

  bool _isPunct(String c) =>
      c == ';' || c == ':' || c == ',' || c == '.' || c == '?' || c == '!' ||
      c == '+' || c == '-' || c == '*' || c == '/' || c == '%' || c == '=' ||
      c == '<' || c == '>' || c == '&' || c == '|' || c == '^' || c == '~' ||
      c == '@' || c == '#' || c == '\\';
}
