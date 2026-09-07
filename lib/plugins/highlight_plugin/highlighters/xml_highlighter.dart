part of '../highlight_plugin.dart';

/// XML tokenizer: tag names [TokenKind.tag], attribute names [TokenKind.attr],
/// attribute values [TokenKind.attrValue], comments [TokenKind.comment],
/// and `<?xml ... ?>` processing instructions as [TokenKind.tag].
class XmlHighlighter implements Highlighter {
  @override
  String get language => 'xml';

  @override
  List<TokenSpan> tokenize(String text) {
    final spans = <TokenSpan>[];
    int i = 0;
    final n = text.length;
    while (i < n) {
      // Comment block <!-- ... -->
      if (_startsWith(text, i, '<!--')) {
        final end = _indexOf(text, '-->', i + 4);
        final stop = end == -1 ? n : end + 3;
        spans.add(TokenSpan(i, stop - i, TokenKind.comment));
        i = stop;
        continue;
      }
      // Processing instruction <? ... ?>
      if (i < n && text[i] == '<' && i + 1 < n && text[i + 1] == '?') {
        final end = _indexOf(text, '?>', i + 2);
        final stop = end == -1 ? n : end + 2;
        spans.add(TokenSpan(i, stop - i, TokenKind.tag));
        i = stop;
        continue;
      }
      // A tag begins with '<'
      if (i < n && text[i] == '<') {
        final close = _indexOf(text, '>', i + 1);
        if (close == -1) {
          spans.add(TokenSpan(i, n - i, TokenKind.tag));
          break;
        }
        // Inside the tag: name, attrs, string values.
        int j = i + 1;
        // Skip leading '/' for closing tags.
        if (j < n && (text[j] == '/' || text[j] == '!')) j++;
        // Tag name.
        int nameStart = j;
        while (j < n && !_isSpace(text[j]) && text[j] != '>' && text[j] != '/' && text[j] != '=') {
          j++;
        }
        if (j > nameStart) spans.add(TokenSpan(nameStart, j - nameStart, TokenKind.tag));
        // Attributes + values.
        while (j < close) {
          while (j < close && _isSpace(text[j])) j++;
          if (j >= close || text[j] == '/' || text[j] == '>') break;
          int aStart = j;
          while (j < close && text[j] != '=' && text[j] != ' ' && text[j] != '/') j++;
          if (j > aStart) spans.add(TokenSpan(aStart, j - aStart, TokenKind.attr));
          if (j < close && text[j] == '=') {
            j++; // '='
            while (j < close && _isSpace(text[j])) j++;
            if (j < close && (text[j] == '"' || text[j] == "'")) {
              final quote = text[j];
              int vStart = j;
              j++;
              while (j < close && text[j] != quote) j++;
              j = j < close ? j + 1 : close;
              spans.add(TokenSpan(vStart, j - vStart, TokenKind.attrValue));
            }
          }
        }
        spans.add(TokenSpan(i, 1, TokenKind.punctuation)); // '<'
        spans.add(TokenSpan(close, 1, TokenKind.punctuation)); // '>'
        i = close + 1;
        continue;
      }
      // Plain text content between tags.
      int end = i;
      while (end < n && text[end] != '<') end++;
      spans.add(TokenSpan(i, end - i, TokenKind.plain));
      i = end;
    }
    return spans;
  }

  bool _isSpace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';

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
