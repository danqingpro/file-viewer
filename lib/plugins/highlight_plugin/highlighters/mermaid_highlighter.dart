part of '../highlight_plugin.dart';

/// Lightweight Mermaid tokenizer: diagram-type keywords (graph, flowchart,
/// sequenceDiagram, …), directive keywords (participant, loop, note, …),
/// %% comments, quoted strings, edge operators (-->, -->>, -.->, ==>),
/// numbers, and bracket punctuation. Everything else stays plain so node
/// labels render in the theme's body color.
class MermaidHighlighter implements Highlighter {
  @override
  String get language => 'mermaid';

  static const Set<String> _keywords = {
    // Diagram types
    'graph', 'flowchart', 'sequencediagram', 'classdiagram', 'statediagram',
    'statediagram-v2', 'erdiagram', 'journey', 'gantt', 'pie', 'gitgraph',
    'mindmap', 'timeline', 'quadrantchart', 'requirementdiagram',
    'c4context', 'sankey-beta', 'xychart-beta', 'block-beta', 'kanban',
    'packet-beta', 'architecture-beta',
    // Directives / participants
    'participant', 'actor', 'create', 'destroy', 'loop', 'alt', 'else',
    'opt', 'par', 'and', 'rect', 'note', 'over', 'activate', 'deactivate',
    'end', 'subgraph', 'direction', 'click', 'class', 'style', 'linkstyle',
    'classdef', 'autonumber', 'title', 'section', 'dateformat', 'axisformat',
    'accdescription', 'accdescr', 'as', 'box', 'critical', 'option', 'break',
    'group', 'showinfo', 'tb', 'bt', 'td', 'lr', 'rl', 'll', 'bl',
  };

  @override
  List<TokenSpan> tokenize(String text) {
    final spans = <TokenSpan>[];
    final n = text.length;
    int i = 0;
    while (i < n) {
      final c = text[i];
      // Comment %% to end of line.
      if (c == '%' && i + 1 < n && text[i + 1] == '%') {
        int end = i;
        while (end < n && text[end] != '\n') end++;
        spans.add(TokenSpan(i, end - i, TokenKind.comment));
        i = end;
        continue;
      }
      // Quoted string "...".
      if (c == '"') {
        int end = i + 1;
        while (end < n && text[end] != '"' && text[end] != '\n') end++;
        if (end < n && text[end] == '"') end++;
        spans.add(TokenSpan(i, end - i, TokenKind.string));
        i = end;
        continue;
      }
      // Edge operators: -->, -->>, ->>, ->, -.->, ==>, ===, --x, --o, ---
      if (c == '-' || c == '=' || c == '.') {
        int end = i;
        while (end < n &&
            (text[end] == '-' ||
                text[end] == '=' ||
                text[end] == '>' ||
                text[end] == '<' ||
                text[end] == 'x' ||
                text[end] == 'o' ||
                text[end] == '.')) {
          end++;
        }
        if (end - i >= 2) {
          spans.add(TokenSpan(i, end - i, TokenKind.operator));
          i = end;
          continue;
        }
      }
      // Numbers.
      if (_isDigit(c)) {
        int end = i;
        while (end < n && (_isDigit(text[end]) || text[end] == '.')) end++;
        spans.add(TokenSpan(i, end - i, TokenKind.number));
        i = end;
        continue;
      }
      // Identifiers / keywords.
      if (_isIdentStart(c)) {
        int end = i;
        while (end < n && _isIdent(text[end])) end++;
        final word = text.substring(i, end);
        final lower = word.toLowerCase();
        if (_keywords.contains(lower)) {
          spans.add(TokenSpan(i, end - i, TokenKind.keyword));
        } else if (end < n && text[end] == ':') {
          // "label:" — e.g. sequence message labels.
          spans.add(TokenSpan(i, end - i, TokenKind.attr));
        } else {
          spans.add(TokenSpan(i, end - i, TokenKind.plain));
        }
        i = end;
        continue;
      }
      // Brackets / braces / parens.
      if (c == '[' || c == ']' || c == '{' || c == '}' || c == '(' || c == ')') {
        spans.add(TokenSpan(i, 1, TokenKind.brace));
        i++;
        continue;
      }
      // Anything else (whitespace, punctuation) as a single plain run.
      int end = i + 1;
      while (end < n &&
          !_isIdentStart(text[end]) &&
          !_isDigit(text[end]) &&
          text[end] != '"' &&
          text[end] != '%' &&
          text[end] != '-' &&
          text[end] != '=' &&
          text[end] != '.' &&
          text[end] != '[' &&
          text[end] != ']' &&
          text[end] != '{' &&
          text[end] != '}' &&
          text[end] != '(' &&
          text[end] != ')') {
        end++;
      }
      spans.add(TokenSpan(i, end - i, TokenKind.plain));
      i = end;
    }
    return spans;
  }

  bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

  bool _isIdentStart(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || c == '_';
  }

  bool _isIdent(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 0x41 && u <= 0x5A) ||
        (u >= 0x61 && u <= 0x7A) ||
        (u >= 0x30 && u <= 0x39) ||
        c == '_' ||
        c == '-';
  }
}
