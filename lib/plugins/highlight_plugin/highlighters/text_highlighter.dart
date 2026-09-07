part of '../highlight_plugin.dart';

/// Plain-text highlighter: no tokens, the editor renders everything as
/// the default `plain` style. Used for `.txt` and any unrecognized format.
class TextHighlighter implements Highlighter {
  @override
  String get language => 'txt';

  @override
  List<TokenSpan> tokenize(String text) => const [];
}
