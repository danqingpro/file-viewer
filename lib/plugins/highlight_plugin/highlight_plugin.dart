import 'package:flutter/painting.dart';

import '../../core/plugin_manager/plugin.dart';
import '../../core/plugin_manager/event_bus.dart';

part 'highlighters/text_highlighter.dart';
part 'highlighters/json_highlighter.dart';
part 'highlighters/xml_highlighter.dart';
part 'highlighters/markdown_highlighter.dart';
part 'highlighters/cpp_highlighter.dart';
part 'highlighters/html_highlighter.dart';
part 'highlighters/css_highlighter.dart';
part 'highlighters/js_highlighter.dart';
part 'highlighters/python_highlighter.dart';
part 'highlighters/yaml_highlighter.dart';
part 'highlighters/batch_highlighter.dart';
part 'highlighters/mermaid_highlighter.dart';

/// Semantic category assigned to a token. The [HighlightPalette] maps each
/// category to a concrete color, so themes can be swapped without touching
/// the tokenizers.
enum TokenKind {
  plain,
  keyword,
  type,
  primitive,
  comment,
  string,
  number,
  punctuation,
  operator,
  tag,
  attr,
  attrValue,
  heading,
  bold,
  italic,
  code,
  link,
  brace,
}

/// A run of text [start, start+length) tagged with a [TokenKind].
class TokenSpan {
  final int start;
  final int length;
  final TokenKind kind;
  const TokenSpan(this.start, this.length, this.kind);
}

/// Contract every language highlighter implements. Given the raw [text],
/// return a flat list of non-overlapping [TokenSpan]s. The editor kernel's
/// [HighlightingController] merges any un-tokenized gaps into `plain` runs.
abstract class Highlighter {
  String get language;
  List<TokenSpan> tokenize(String text);
}

/// Theme-aware syntax palette. Light colors follow the classic Notepad++
/// scheme; dark colors follow VS Code Dark+ so every token keeps at
/// least WCAG-AA-level contrast against the 0xFF1E1E1E editor background
/// (the old single-palette design put dark-red 0xFF800000 inline code
/// and pure-blue 0xFF0000FF headings on a near-black background — both
/// fail contrast badly).
class HighlightPalette {
  const HighlightPalette();

  // ---- Light palette (unchanged, Notepad++-inspired) -----------------
  static const Color plain = Color(0xFF1E1E1E);
  static const Color keyword = Color(0xFF0000FF);
  static const Color type = Color(0xFF2B91AF);
  static const Color primitive = Color(0xFF0000FF);
  static const Color comment = Color(0xFF008000);
  static const Color string = Color(0xFFA31515);
  static const Color number = Color(0xFF800000);
  static const Color punctuation = Color(0xFF606060);
  static const Color operator = Color(0xFF606060);
  static const Color tag = Color(0xFF800000);
  static const Color attr = Color(0xFFFF0000);
  static const Color attrValue = Color(0xFF0000FF);
  static const Color heading = Color(0xFF0000FF);
  static const Color bold = Color(0xFF1E1E1E);
  static const Color italic = Color(0xFF1E1E1E);
  static const Color code = Color(0xFF800000);
  static const Color link = Color(0xFF0984E3);
  static const Color brace = Color(0xFF3333B0);

  // ---- Dark palette (VS Code Dark+) -----------------------------------
  static const Color dPlain = Color(0xFFD4D4D4);
  static const Color dKeyword = Color(0xFF569CD6);
  static const Color dType = Color(0xFF4EC9B0);
  static const Color dPrimitive = Color(0xFF569CD6);
  static const Color dComment = Color(0xFF6A9955);
  static const Color dString = Color(0xFFCE9178);
  static const Color dNumber = Color(0xFFB5CEA8);
  static const Color dPunctuation = Color(0xFFD4D4D4);
  static const Color dOperator = Color(0xFFD4D4D4);
  static const Color dTag = Color(0xFF569CD6);
  static const Color dAttr = Color(0xFF9CDCFE);
  static const Color dAttrValue = Color(0xFFCE9178);
  static const Color dHeading = Color(0xFF569CD6);
  static const Color dBold = Color(0xFFE8E8E8);
  static const Color dItalic = Color(0xFFE8E8E8);
  static const Color dCode = Color(0xFFCE9178);
  static const Color dLink = Color(0xFF4EA8FF);
  static const Color dBrace = Color(0xFFFFD700);

  static TextStyle styleFor(TokenKind kind, {required bool dark}) {
    final color = dark
        ? switch (kind) {
            TokenKind.keyword => dKeyword,
            TokenKind.type => dType,
            TokenKind.primitive => dPrimitive,
            TokenKind.comment => dComment,
            TokenKind.string => dString,
            TokenKind.number => dNumber,
            TokenKind.punctuation => dPunctuation,
            TokenKind.operator => dOperator,
            TokenKind.tag => dTag,
            TokenKind.attr => dAttr,
            TokenKind.attrValue => dAttrValue,
            TokenKind.heading => dHeading,
            TokenKind.bold => dBold,
            TokenKind.italic => dItalic,
            TokenKind.code => dCode,
            TokenKind.link => dLink,
            TokenKind.brace => dBrace,
            TokenKind.plain => dPlain,
          }
        : switch (kind) {
            TokenKind.keyword => keyword,
            TokenKind.type => type,
            TokenKind.primitive => primitive,
            TokenKind.comment => comment,
            TokenKind.string => string,
            TokenKind.number => number,
            TokenKind.punctuation => punctuation,
            TokenKind.operator => operator,
            TokenKind.tag => tag,
            TokenKind.attr => attr,
            TokenKind.attrValue => attrValue,
            TokenKind.heading => heading,
            TokenKind.bold => bold,
            TokenKind.italic => italic,
            TokenKind.code => code,
            TokenKind.link => link,
            TokenKind.brace => brace,
            TokenKind.plain => plain,
          };
    final weight = kind == TokenKind.heading || kind == TokenKind.bold ? FontWeight.w700 : FontWeight.w400;
    final style = kind == TokenKind.italic ? FontStyle.italic : FontStyle.normal;
    return TextStyle(color: color, fontWeight: weight, fontStyle: style);
  }
}

/// The highlight *plugin* surface: holds one [Highlighter] per language and
/// resolves the right one at runtime. Independent from the editor kernel so
/// new languages can be added by registering another highlighter.
class HighlightPlugin extends EditorPlugin {
  final Map<String, Highlighter> _byLang = {};

  @override
  String get id => 'highlight_plugin';

  @override
  String get displayName => '多格式语法高亮插件';

  @override
  String get description => '为 txt / md / cpp / h / hpp / json / xml 提供差异化语法着色。';

  @override
  void initialize(EventBus bus) {
    register(TextHighlighter());
    register(JsonHighlighter());
    register(XmlHighlighter());
    register(MarkdownHighlighter());
    register(CppHighlighter());
    register(HtmlHighlighter());
    register(CssHighlighter());
    register(JsHighlighter());
    register(PythonHighlighter());
    register(YamlHighlighter());
    register(BatchHighlighter());
    register(MermaidHighlighter());
  }

  void register(Highlighter h) {
    _byLang[h.language] = h;
  }

  @override
  void dispose() => _byLang.clear();

  Highlighter? forLanguage(String language) => _byLang[language];
}
