import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../mermaid/mermaid_view.dart';

/// Live Markdown preview pane with a built-in document outline (导航栏).
///
/// The document is split into heading-rooted sections (code fences are
/// respected, so `#` inside a fence is not a heading). Each section is a
/// separate [MarkdownBody] wrapped in a keyed subtree, which lets the
/// outline jump to any heading via [Scrollable.ensureVisible] — real
/// navigation instead of a dead table of contents.
///
/// Fenced ```mermaid blocks render as live diagrams; other code blocks
/// become themed, horizontally scrollable cards. Colors follow the
/// surrounding theme, so light/dark both stay readable.
class MarkdownPreview extends StatefulWidget {
  const MarkdownPreview({super.key, required this.data});

  final String data;

  @override
  State<MarkdownPreview> createState() => _MarkdownPreviewState();
}

class _MarkdownPreviewState extends State<MarkdownPreview> {
  final ScrollController _scroll = ScrollController();
  final List<GlobalKey> _keys = [];
  List<_MdSection> _sections = const [];
  bool _outlineOpen = false;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(covariant MarkdownPreview old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) _rebuild();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _rebuild() {
    _sections = _splitSections(widget.data);
    _keys
      ..clear()
      ..addAll(List.generate(_sections.length, (_) => GlobalKey()));
  }

  List<_MdSection> get _headings =>
      _sections.where((s) => s.level > 0 && s.title.isNotEmpty).toList();

  Future<void> _jumpTo(_MdSection section) async {
    final index = _sections.indexOf(section);
    if (index < 0) return;
    setState(() => _outlineOpen = false);
    final ctx = _keys[index].currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sheet = _buildStyleSheet(theme, isDark);

    return Stack(
      children: [
        SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < _sections.length; i++)
                KeyedSubtree(
                  key: _keys[i],
                  child: MarkdownBody(
                    data: _sections[i].text,
                    selectable: true,
                    softLineBreak: true,
                    extensionSet: md.ExtensionSet.gitHubWeb,
                    builders: {
                      'pre': _PreBuilder(
                        dark: isDark,
                        codeFg: isDark
                            ? const Color(0xFFCE9178)
                            : const Color(0xFF800000),
                        codeBg: isDark
                            ? const Color(0xFF2D2D30)
                            : const Color(0xFFF6F8FA),
                      ),
                    },
                    styleSheet: sheet,
                    onTapLink: (text, href, title) {},
                  ),
                ),
            ],
          ),
        ),
        // Outline toggle — always reachable, whatever the orientation.
        if (_headings.isNotEmpty)
          Positioned(
            top: 8,
            right: 8,
            child: _OutlineButton(
              isDark: isDark,
              count: _headings.length,
              open: _outlineOpen,
              onTap: () => setState(() => _outlineOpen = !_outlineOpen),
            ),
          ),
        if (_outlineOpen && _headings.isNotEmpty) ...[
          GestureDetector(
            onTap: () => setState(() => _outlineOpen = false),
            child: Container(color: Colors.black54),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _OutlinePanel(
              headings: _headings,
              isDark: isDark,
              onSelect: _jumpTo,
              onClose: () => setState(() => _outlineOpen = false),
            ),
          ),
        ],
      ],
    );
  }

  MarkdownStyleSheet _buildStyleSheet(ThemeData theme, bool isDark) {
    final fg = isDark ? const Color(0xFFE0E0E0) : const Color(0xFF1F1F1F);
    final muted = isDark ? const Color(0xFF9E9E9E) : const Color(0xFF6A737D);
    final accent = isDark ? const Color(0xFF4EA8FF) : const Color(0xFF0969DA);
    final codeFg = isDark ? const Color(0xFFCE9178) : const Color(0xFF800000);
    final codeBg = isDark ? const Color(0xFF2D2D30) : const Color(0xFFF6F8FA);
    final quoteFg = isDark ? const Color(0xFFB0B0B0) : const Color(0xFF57606A);
    final quoteBar = isDark ? const Color(0xFF4EA8FF) : const Color(0xFFD0D7DE);
    final tableBorder = isDark ? const Color(0xFF444444) : const Color(0xFFD0D7DE);

    return MarkdownStyleSheet.fromTheme(theme).copyWith(
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
  }
}

/// A heading-rooted slice of the document. `level == 0` marks the
/// preamble (content before the first heading) and is excluded from the
/// outline.
class _MdSection {
  _MdSection({required this.level, required this.title, required this.text});

  final int level;
  final String title;
  final String text;
}

final RegExp _headingRe = RegExp(r'^(#{1,6})\s+(.*)$');

/// Split [src] into heading-rooted sections, ignoring `#` inside fenced
/// code blocks so shell/C comments are never mistaken for headings.
List<_MdSection> _splitSections(String src) {
  final sections = <_MdSection>[];
  final buf = <String>[];
  int curLevel = 0;
  String curTitle = '';
  bool inFence = false;
  String fenceMark = '';

  void flush() {
    final text = buf.join('\n');
    if (text.trim().isEmpty && curTitle.isEmpty) {
      buf.clear();
      return;
    }
    sections.add(_MdSection(level: curLevel, title: curTitle, text: text));
    buf.clear();
    curLevel = 0;
    curTitle = '';
  }

  for (final line in src.split('\n')) {
    final t = line.trimLeft();
    if (t.startsWith('```') || t.startsWith('~~~')) {
      final mark = t.substring(0, 3);
      if (!inFence) {
        inFence = true;
        fenceMark = mark;
      } else if (t.startsWith(fenceMark)) {
        inFence = false;
      }
      buf.add(line);
      continue;
    }
    if (!inFence) {
      final m = _headingRe.firstMatch(line);
      if (m != null) {
        flush();
        curLevel = m.group(1)!.length;
        curTitle = m.group(2)!.trim();
        buf.add(line);
        continue;
      }
    }
    buf.add(line);
  }
  flush();
  if (sections.isEmpty) {
    return [_MdSection(level: 0, title: '', text: src)];
  }
  return sections;
}

/// Floating "大纲" pill in the preview corner.
class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.isDark,
    required this.count,
    required this.open,
    required this.onTap,
  });

  final bool isDark;
  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xE6252526) : const Color(0xF5FFFFFF);
    final fg = isDark ? const Color(0xFFE0E0E0) : const Color(0xFF1F1F1F);
    return Material(
      color: bg,
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(open ? Icons.close : Icons.toc, size: 16, color: fg),
              const SizedBox(width: 4),
              Text(
                open ? '关闭大纲' : '大纲 $count',
                style: TextStyle(fontSize: 12, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slide-in outline panel listing every heading, indented by level.
class _OutlinePanel extends StatelessWidget {
  const _OutlinePanel({
    required this.headings,
    required this.isDark,
    required this.onSelect,
    required this.onClose,
  });

  final List<_MdSection> headings;
  final bool isDark;
  final ValueChanged<_MdSection> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF252526) : Colors.white;
    final fg = isDark ? const Color(0xFFE0E0E0) : const Color(0xFF1F1F1F);
    final width = (MediaQuery.of(context).size.width * 0.78).clamp(200.0, 320.0);

    return Material(
      color: bg,
      elevation: 8,
      child: SizedBox(
        width: width,
        height: double.infinity,
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(Icons.toc, size: 16,
                        color: isDark ? Colors.white70 : Colors.black54),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '文档大纲 (${headings.length})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: Icon(Icons.close, size: 18,
                          color: isDark ? Colors.white70 : Colors.black54),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE0E0E0),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: headings.length,
                  itemBuilder: (context, i) {
                    final h = headings[i];
                    final indent = ((h.level - 1) * 14).toDouble();
                    final isMajor = h.level <= 2;
                    return InkWell(
                      onTap: () => onSelect(h),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(12 + indent, 8, 10, 8),
                        child: Text(
                          h.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isMajor ? 13.5 : 12.5,
                            height: 1.35,
                            fontWeight:
                                isMajor ? FontWeight.w600 : FontWeight.w400,
                            color: isMajor ? fg : (isDark ? const Color(0xFFB8B8B8) : const Color(0xFF555555)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
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
