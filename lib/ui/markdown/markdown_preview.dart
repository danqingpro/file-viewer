import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../mermaid/mermaid_view.dart';

/// Live Markdown preview pane.
///
/// Renders [data] with GFM extensions (tables, strikethrough, task
/// lists). Fenced ```mermaid blocks are intercepted by [_PreBuilder] and
/// rendered as real diagrams via the embedded WebView renderer; every
/// other code block falls back to a themed, horizontally scrollable
/// monospaced card. All colors are derived from the surrounding theme so
/// the preview stays readable in both light and dark mode.
class MarkdownPreview extends StatelessWidget {
  const MarkdownPreview({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final fg = isDark ? const Color(0xFFE0E0E0) : const Color(0xFF1F1F1F);
    final muted = isDark ? const Color(0xFF9E9E9E) : const Color(0xFF6A737D);
    final accent = isDark ? const Color(0xFF4EA8FF) : const Color(0xFF0969DA);
    final codeFg = isDark ? const Color(0xFFCE9178) : const Color(0xFF800000);
    final codeBg = isDark ? const Color(0xFF2D2D30) : const Color(0xFFF6F8FA);
    final quoteFg = isDark ? const Color(0xFFB0B0B0) : const Color(0xFF57606A);
    final quoteBar = isDark ? const Color(0xFF4EA8FF) : const Color(0xFFD0D7DE);
    final tableBorder = isDark ? const Color(0xFF444444) : const Color(0xFFD0D7DE);

    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: TextStyle(color: fg, fontSize: 14, height: 1.55),
      h1: TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.w700, height: 1.6),
      h2: TextStyle(color: fg, fontSize: 19, fontWeight: FontWeight.w700, height: 1.6),
      h3: TextStyle(color: fg, fontSize: 16.5, fontWeight: FontWeight.w700, height: 1.6),
      h4: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w600, height: 1.6),
      h5: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w600, height: 1.6),
      h6: TextStyle(color: muted, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.6),
      a: TextStyle(color: accent, decoration: TextDecoration.underline),
      strong: TextStyle(color: fg, fontWeight: FontWeight.w700),
      em: TextStyle(color: fg, fontStyle: FontStyle.italic),
      del: TextStyle(color: muted, decoration: TextDecoration.lineThrough),
      code: TextStyle(
        color: codeFg,
        backgroundColor: codeBg,
        fontFamily: 'monospace',
        fontSize: 13,
      ),
      codeblockDecoration: BoxDecoration(
        color: codeBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tableBorder, width: 0.5),
      ),
      blockquote: TextStyle(color: quoteFg, fontSize: 14, height: 1.5),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: quoteBar, width: 3)),
      ),
      listBullet: TextStyle(color: fg, fontSize: 14, height: 1.55),
      tableHead: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13),
      tableBody: TextStyle(color: fg, fontSize: 13),
      tableBorder: TableBorder.all(color: tableBorder, width: 0.5),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: tableBorder, width: 1)),
      ),
      checkbox: TextStyle(color: fg, fontSize: 14),
    );

    return Markdown(
      data: data,
      selectable: true,
      softLineBreak: true,
      extensionSet: md.ExtensionSet.gitHubWeb,
      builders: {
        'pre': _PreBuilder(dark: isDark, codeFg: codeFg, codeBg: codeBg),
      },
      styleSheet: sheet,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    );
  }
}

/// Custom renderer for `pre` (fenced code block) elements. Mermaid fences
/// become live diagrams; everything else renders as a themed code card.
class _PreBuilder extends MarkdownElementBuilder {
  _PreBuilder({required this.dark, required this.codeFg, required this.codeBg});

  final bool dark;
  final Color codeFg;
  final Color codeBg;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    md.Element? codeEl;
    if (element.children != null) {
      for (final child in element.children!) {
        if (child is md.Element && child.tag == 'code') {
          codeEl = child;
          break;
        }
      }
    }
    final lang = codeEl?.attributes['class'] ?? '';
    final source = element.textContent;

    if (lang == 'language-mermaid') {
      return _MermaidBlock(source: source.trim(), dark: dark);
    }

    // Default code card (the stock renderer would lose our theme colors).
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: codeBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          source,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.45,
            color: codeFg,
          ),
        ),
      ),
    );
  }
}

/// Inline mermaid diagram card inside a markdown document. Fixed height
/// keeps the document flow stable; tapping the expand icon opens a
/// full-screen view for pan/zoom reading.
class _MermaidBlock extends StatelessWidget {
  const _MermaidBlock({required this.source, required this.dark});

  final String source;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final border = dark ? const Color(0xFF444444) : const Color(0xFFD0D7DE);
    return Container(
      height: 320,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: border, width: 0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: MermaidView(source: source, dark: dark)),
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: dark ? Colors.black54 : Colors.white70,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _openFullScreen(context),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.open_in_full,
                    size: 16,
                    color: dark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MermaidFullScreen(source: source),
      ),
    );
  }
}

/// Full-screen mermaid diagram viewer (opened from an inline preview card).
class _MermaidFullScreen extends StatelessWidget {
  const _MermaidFullScreen({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Mermaid 图表')),
      body: InteractiveViewer(
        maxScale: 6,
        minScale: 0.4,
        child: SizedBox.expand(
          child: MermaidView(source: source, dark: isDark),
        ),
      ),
    );
  }
}
