part of '../highlight_plugin.dart';

/// Python tokenizer: keywords [TokenKind.keyword], built-ins as
/// [TokenKind.primitive], string literals (single/double/triple)
/// [TokenKind.string], numbers [TokenKind.number], line comments `#`
/// [TokenKind.comment], decorators `@` [TokenKind.type], braces
/// [TokenKind.brace].
class PythonHighlighter implements Highlighter {
  @override
  String get language => 'python';

  static const Set<String> _keywords = {
    'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await',
    'break', 'class', 'continue', 'def', 'del', 'elif', 'else', 'except',
    'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is',
    'lambda', 'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'try',
    'while', 'with', 'yield',
  };

  static const Set<String> _builtins = {
    'abs', 'all', 'any', 'ascii', 'bin', 'bool', 'breakpoint', 'bytearray',
    'bytes', 'callable', 'chr', 'classmethod', 'compile', 'complex',
    'delattr', 'dict', 'dir', 'divmod', 'enumerate', 'eval', 'exec',
    'filter', 'float', 'format', 'frozenset', 'getattr', 'globals',
    'hasattr', 'hash', 'help', 'hex', 'id', 'input', 'int', 'isinstance',
    'issubclass', 'iter', 'len', 'list', 'locals', 'map', 'max',
    'memoryview', 'min', 'next', 'object', 'oct', 'open', 'ord', 'pow',
    'print', 'property', 'range', 'repr', 'reversed', 'round', 'set',
    'setattr', 'slice', 'sorted', 'staticmethod', 'str', 'sum', 'super',
    'tuple', 'type', 'vars', 'zip', '__import__',
  };

  @override
  List<TokenSpan> tokenize(String text) {
    final spans = <TokenSpan>[];
    int i = 0;
    final n = text.length;
    while (i < n) {
      final ch = text[i];
      // Triple-quoted string """...""" or '''...'''
      if (_startsWith(text, i, '"""') || _startsWith(text, i, "'''")) {
        final marker = text.substring(i, i + 3);
        final end = _indexOf(text, marker, i + 3);
        final stop = end == -1 ? n : end + 3;
        spans.add(TokenSpan(i, stop - i, TokenKind.string));
        i = stop;
        continue;
      }
      // String literal '...' or "..."
      if (ch == "'" || ch == '"') {
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
      // Line comment #...
      if (ch == '#') {
        int end = i + 1;
        while (end < n && text[end] != '\n') end++;
        spans.add(TokenSpan(i, end - i, TokenKind.comment));
        i = end;
        continue;
      }
      // Decorator @name
      if (ch == '@' && i + 1 < n && _isIdentStart(text[i + 1])) {
        int end = i + 1;
        while (end < n && _isIdent(text[end])) end++;
        spans.add(TokenSpan(i, end - i, TokenKind.type));
        i = end;
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
      // Identifier / keyword / builtin.
      if (_isIdentStart(ch)) {
        int end = i + 1;
        while (end < n && _isIdent(text[end])) end++;
        final word = text.substring(i, end);
        if (_keywords.contains(word)) {
          spans.add(TokenSpan(i, end - i, TokenKind.keyword));
        } else if (_builtins.contains(word)) {
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
    return (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) || c == '_';
  }

  bool _isIdent(String c) => _isIdentStart(c) || _isDigit(c);

  bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

  bool _isPunct(String c) =>
      c == ';' || c == ':' || c == ',' || c == '.' || c == '?' || c == '!' ||
      c == '+' || c == '-' || c == '*' || c == '/' || c == '%' || c == '=' ||
      c == '<' || c == '>' || c == '&' || c == '|' || c == '^' || c == '~' ||
      c == '\\';

  bool _startsWith(String s, int i, String needle) {
    if (i + needle.length > s.length) return false;
    for (int k = 0; k < needle.length; k++) {
      if (s[i + k] != needle[k]) return false;
    }
    return true;
  }

  int _indexOf(String s, String needle, int from) {
    if (from >= s.length) return -1;
    return s.indexOf(needle, from);
  }
}
