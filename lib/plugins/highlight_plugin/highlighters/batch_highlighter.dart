part of '../highlight_plugin.dart';

/// Windows Batch (.bat/.cmd) tokenizer: keywords (echo, set, if, for,
/// goto, call, etc.) as [TokenKind.keyword], `@echo off` directives,
/// `%VAR%` / `%1` variable references as [TokenKind.primitive],
/// `::` comments and `REM` lines as [TokenKind.comment], labels `:name`
/// as [TokenKind.type], quoted strings as [TokenKind.string], redirection
/// operators as [TokenKind.punctuation].
class BatchHighlighter implements Highlighter {
  @override
  String get language => 'batch';

  static const Set<String> _keywords = {
    'echo', 'set', 'if', 'else', 'for', 'in', 'do', 'goto', 'call',
    'pause', 'exit', 'rem', 'shift', 'cd', 'dir', 'copy', 'del',
    'move', 'ren', 'type', 'find', 'findstr', 'choice', 'timeout',
    'start', 'tasklist', 'taskkill', 'ping', 'net', 'sc', 'reg',
    'title', 'color', 'prompt', 'cls', 'ver', 'date', 'time',
    'pushd', 'popd', 'md', 'mkdir', 'rd', 'rmdir', 'erase',
  };

  @override
  List<TokenSpan> tokenize(String text) {
    final spans = <TokenSpan>[];
    int i = 0;
    final n = text.length;
    while (i < n) {
      final ch = text[i];
      // Line comment :: or REM (case-insensitive, at line start).
      final atLineStart = i == 0 || text[i - 1] == '\n';
      if (atLineStart && ch == ':' && i + 1 < n && text[i + 1] == ':') {
        int end = i + 2;
        while (end < n && text[end] != '\n') end++;
        spans.add(TokenSpan(i, end - i, TokenKind.comment));
        i = end;
        continue;
      }
      // Quoted string "..."
      if (ch == '"') {
        int end = i + 1;
        while (end < n && text[end] != '"') end++;
        final stop = end < n ? end + 1 : n;
        spans.add(TokenSpan(i, stop - i, TokenKind.string));
        i = stop;
        continue;
      }
      // Variable %VAR% or parameter %1..%9 or %*.
      if (ch == '%') {
        int end = i + 1;
        if (end < n && text[end] == '%') {
          // %% escape
          spans.add(TokenSpan(i, 2, TokenKind.punctuation));
          i = end + 1;
          continue;
        }
        while (end < n && text[end] != '%' && text[end] != '\n') end++;
        if (end < n && text[end] == '%') end++;
        spans.add(TokenSpan(i, end - i, TokenKind.primitive));
        i = end;
        continue;
      }
      // Variable !VAR! (delayed expansion)
      if (ch == '!') {
        int end = i + 1;
        while (end < n && text[end] != '!' && text[end] != '\n') end++;
        if (end < n && text[end] == '!') end++;
        spans.add(TokenSpan(i, end - i, TokenKind.primitive));
        i = end;
        continue;
      }
      // Label :name at line start.
      if (atLineStart && ch == ':' && (i + 1 >= n || text[i + 1] != ':')) {
        int end = i + 1;
        while (end < n && !_isSpace(text[end]) && text[end] != '\n') end++;
        spans.add(TokenSpan(i, end - i, TokenKind.type));
        i = end;
        continue;
      }
      // Identifier / keyword.
      if (_isIdentStart(ch)) {
        int end = i + 1;
        while (end < n && _isIdent(text[end])) end++;
        final word = text.substring(i, end).toLowerCase();
        if (_keywords.contains(word)) {
          spans.add(TokenSpan(i, end - i, TokenKind.keyword));
        } else {
          spans.add(TokenSpan(i, end - i, TokenKind.plain));
        }
        i = end;
        continue;
      }
      // Number literal.
      if (_isDigit(ch)) {
        int end = i + 1;
        while (end < n && _isDigit(text[end])) end++;
        spans.add(TokenSpan(i, end - i, TokenKind.number));
        i = end;
        continue;
      }
      // Punctuation / redirection operator.
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

  bool _isSpace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';
  bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
  bool _isIdentStart(String c) {
    final v = c.codeUnitAt(0);
    return (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) || c == '_';
  }
  bool _isIdent(String c) => _isIdentStart(c) || _isDigit(c);
  bool _isPunct(String c) =>
      c == ';' || c == ',' || c == '.' || c == '?' || c == '+' || c == '-' ||
      c == '*' || c == '/' || c == '=' || c == '<' || c == '>' || c == '&' ||
      c == '|' || c == '^' || c == '(' || c == ')';
}
