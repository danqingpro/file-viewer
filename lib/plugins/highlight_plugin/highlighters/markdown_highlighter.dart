part of '../highlight_plugin.dart';

/// Markdown tokenizer: ATX headings (#..######), fenced code blocks
/// (```), inline code (`), bold (**__**__), italic (*_), and link labels
/// ([text](url)). Lists / blockquotes are styled as plain for v1.
class MarkdownHighlighter implements Highlighter {
  @override
  String get language => 'md';

  @override
  List<TokenSpan> tokenize(String text) {
    final spans = <TokenSpan>[];
    int i = 0;
    final n = text.length;
    while (i < n) {
      // Fenced code block ```...```
      if (_startsWith(text, i, '```')) {
        int end = _indexOf(text, '```', i + 3);
        if (end == -1) end = n - 3;
        final stop = end < n ? end + 3 : n;
        spans.add(TokenSpan(i, stop - i, TokenKind.code));
        i = stop;
        continue;
      }
      // ATX heading at line start
      if ((i == 0 || text[i - 1] == '\n') && i < n && text[i] == '#') {
        int j = i;
        while (j < n && text[j] == '#') j++;
        int end = j;
        while (end < n && text[end] != '\n') end++;
        spans.add(TokenSpan(i, end - i, TokenKind.heading));
        i = end;
        continue;
      }
      // Bold ** or __
      if (_startsWith(text, i, '**') || _startsWith(text, i, '__')) {
        final marker = text.substring(i, i + 2);
        int end = _indexOf(text, marker, i + 2);
        if (end == -1) {
          spans.add(TokenSpan(i, 2, TokenKind.plain));
          i += 2;
          continue;
        }
        final stop = end + 2;
        spans.add(TokenSpan(i, 2, TokenKind.punctuation));
        spans.add(TokenSpan(i + 2, end - i - 2, TokenKind.bold));
        spans.add(TokenSpan(end, 2, TokenKind.punctuation));
        i = stop;
        continue;
      }
      // Inline code `...`
      if (i < n && text[i] == '`') {
        int end = _indexOf(text, '`', i + 1);
        if (end == -1) {
          spans.add(TokenSpan(i, 1, TokenKind.plain));
          i++;
          continue;
        }
        spans.add(TokenSpan(i, end - i + 1, TokenKind.code));
        i = end + 1;
        continue;
      }
      // Link [text](url)
      if (i < n && text[i] == '[') {
        final textClose = _indexOf(text, ']', i + 1);
        if (textClose != -1 && textClose + 1 < n && text[textClose + 1] == '(') {
          final urlClose = _indexOf(text, ')', textClose + 2);
          if (urlClose != -1) {
            spans.add(TokenSpan(i, 1, TokenKind.punctuation));
            spans.add(TokenSpan(i + 1, textClose - i - 1, TokenKind.link));
            spans.add(TokenSpan(textClose, urlClose - textClose + 1, TokenKind.attr));
            i = urlClose + 1;
            continue;
          }
        }
      }
      // Italic * or _
      if ((i < n && (text[i] == '*' || text[i] == '_'))) {
        final marker = text[i];
        int end = i + 1;
        while (end < n && text[end] != marker) end++;
        if (end < n) {
          spans.add(TokenSpan(i, 1, TokenKind.punctuation));
          spans.add(TokenSpan(i + 1, end - i - 1, TokenKind.italic));
          spans.add(TokenSpan(end, 1, TokenKind.punctuation));
          i = end + 1;
          continue;
        }
      }
      // Plain run until next interesting char.
      int end = i + 1;
      while (end < n &&
          text[end] != '`' &&
          text[end] != '*' &&
          text[end] != '_' &&
          text[end] != '[' &&
          !(text[end] == '#' && (end == 0 || text[end - 1] == '\n')) &&
          !((text[end] == '`') && _startsWith(text, end, '```'))) {
        end++;
      }
      spans.add(TokenSpan(i, end - i, TokenKind.plain));
      i = end;
    }
    return spans;
  }

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
