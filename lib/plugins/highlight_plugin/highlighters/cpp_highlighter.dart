part of '../highlight_plugin.dart';

/// C/C++ tokenizer: keywords, primitive types, single/multi-line comments,
/// string & char literals, preprocessor directives (#include / #define),
/// numeric literals, and brace highlighting.
class CppHighlighter implements Highlighter {
  @override
  String get language => 'cpp';

  static const Set<String> _keywords = {
    'alignas', 'alignof', 'and', 'asm', 'auto', 'break', 'case', 'catch',
    'class', 'compl', 'concept', 'const', 'constexpr', 'const_cast', 'continue',
    'co_await', 'co_return', 'co_yield', 'decltype', 'default', 'delete',
    'do', 'dynamic_cast', 'else', 'enum', 'explicit', 'export', 'extern',
    'final', 'for', 'friend', 'goto', 'if', 'inline', 'mutable', 'namespace',
    'new', 'noexcept', 'nullptr', 'operator', 'override', 'private',
    'protected', 'public', 'reinterpret_cast', 'requires', 'return',
    'sizeof', 'static', 'static_assert', 'static_cast', 'struct',
    'switch', 'template', 'this', 'throw', 'try', 'typedef', 'typeid',
    'typename', 'union', 'using', 'virtual', 'volatile', 'while',
  };

  static const Set<String> _primitives = {
    'bool', 'char', 'char8_t', 'char16_t', 'char32_t', 'wchar_t', 'double',
    'float', 'int', 'long', 'short', 'signed', 'unsigned', 'void', 'size_t',
    'int8_t', 'int16_t', 'int32_t', 'int64_t', 'uint8_t', 'uint16_t',
    'uint32_t', 'uint64_t', 'intptr_t', 'uintptr_t', 'ptrdiff_t',
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
      // Preprocessor directive (starts at line beginning, possibly after ws).
      if (ch == '#' && (i == 0 || text[i - 1] == '\n')) {
        int end = i;
        while (end < n && text[end] != '\n') {
          if (text[end] == '\\' && end + 1 < n && text[end + 1] == '\n') {
            end += 2;
            continue;
          }
          end++;
        }
        spans.add(TokenSpan(i, end - i, TokenKind.type));
        i = end;
        continue;
      }
      // String literal "..."
      if (ch == '"') {
        int end = i + 1;
        while (end < n) {
          if (text[end] == '\\') {
            end += 2;
            continue;
          }
          if (text[end] == '"') break;
          end++;
        }
        final stop = end < n ? end + 1 : n;
        spans.add(TokenSpan(i, stop - i, TokenKind.string));
        i = stop;
        continue;
      }
      // Char literal '...'
      if (ch == "'") {
        int end = i + 1;
        while (end < n) {
          if (text[end] == '\\') {
            end += 2;
            continue;
          }
          if (text[end] == "'") break;
          end++;
        }
        final stop = end < n ? end + 1 : n;
        spans.add(TokenSpan(i, stop - i, TokenKind.string));
        i = stop;
        continue;
      }
      // Identifier / keyword / primitive.
      if (_isIdentStart(ch)) {
        int end = i + 1;
        while (end < n && _isIdent(text[end])) end++;
        final word = text.substring(i, end);
        if (_keywords.contains(word)) {
          spans.add(TokenSpan(i, end - i, TokenKind.keyword));
        } else if (_primitives.contains(word)) {
          spans.add(TokenSpan(i, end - i, TokenKind.primitive));
        } else {
          // Heuristic: capitalized words look like user types.
          final isType = word.isNotEmpty && word[0].toUpperCase() == word[0] && word[0].toLowerCase() != word[0];
          spans.add(TokenSpan(i, end - i, isType ? TokenKind.type : TokenKind.plain));
        }
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
      // Plain single char.
      spans.add(TokenSpan(i, 1, TokenKind.plain));
      i++;
    }
    return spans;
  }

  bool _isIdentStart(String c) {
    final v = c.codeUnitAt(0);
    return (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) || c == '_';
  }

  bool _isIdent(String c) {
    final v = c.codeUnitAt(0);
    return _isIdentStart(c) || (v >= 0x30 && v <= 0x39);
  }

  bool _isDigit(String c) {
    final v = c.codeUnitAt(0);
    return v >= 0x30 && v <= 0x39;
  }

  bool _isPunct(String c) =>
      c == ';' || c == ':' || c == ',' || c == '.' || c == '?' || c == '!' ||
      c == '+' || c == '-' || c == '*' || c == '/' || c == '%' || c == '=' ||
      c == '<' || c == '>' || c == '&' || c == '|' || c == '^' || c == '~' ||
      c == '@' || c == '#' || c == '\\';
}
