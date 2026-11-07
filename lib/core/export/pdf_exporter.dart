import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Converts a Markdown document into a printable A4 PDF with:
///   * a clickable table of contents (目录) built from the headings,
///   * internal links that jump straight to the matching section,
///   * page numbers in the footer,
///   * an embedded simplified-Chinese font so CJK text renders correctly
///     offline (the stock PDF fonts have no CJK glyphs).
///
/// This is a deliberately small, dependency-light renderer: headings,
/// paragraphs, bullet / ordered lists, code fences, block quotes and
/// simple pipe tables are supported. Anything fancier degrades to plain
/// text rather than failing the export.
class PdfExporter {
  PdfExporter._();

  static pw.Font? _cachedFont;

  static Future<pw.Font> _font() async {
    final cached = _cachedFont;
    if (cached != null) return cached;
    final data = await rootBundle.load('assets/fonts/CJK-Regular.ttf');
    final font = pw.Font.ttf(data);
    _cachedFont = font;
    return font;
  }

  /// Render [markdown] to [outputPath]. Returns the written path.
  static Future<String> exportMarkdown({
    required String markdown,
    required String title,
    required String outputPath,
  }) async {
    final font = await _font();
    final doc = pw.Document(
      title: title,
      theme: pw.ThemeData.withFont(base: font, bold: font, italic: font),
    );

    final blocks = _parseBlocks(markdown);
    final headings = <_Block>[
      for (final b in blocks)
        if (b is _HeadingBlock) b,
    ];
    // Stable anchor names per heading block.
    final anchors = <_Block, String>{};
    for (int i = 0; i < headings.length; i++) {
      anchors[headings[i]] = 'sec$i';
    }

    final tocPage = headings.length > 2;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 40, 42, 42),
        header: (ctx) {
          if (ctx.pageNumber == 1) return pw.SizedBox();
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              title,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          );
        },
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.center,
          child: pw.Text(
            '${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (ctx) {
          final widgets = <pw.Widget>[
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '由 文件查看器 导出 · ${DateTime.now().toString().split('.').first}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
            pw.SizedBox(height: 14),
          ];

          if (tocPage) {
            widgets.add(_toc(headings, anchors));
            widgets.add(pw.NewPage());
          }

          for (final b in blocks) {
            widgets.addAll(b.build(anchors));
          }
          return widgets;
        },
      ),
    );

    // PDF bookmarks (书签大纲) so every viewer's navigation pane lists
    // the document structure with one click per section.
    _addOutline(doc, headings, anchors);

    final bytes = await doc.save();
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(Uint8List.fromList(bytes));
    return file.path;
  }

  /// Build the PDF outline tree from the heading list, nesting by level.
  static void _addOutline(
    pw.Document doc,
    List<_Block> headings,
    Map<_Block, String> anchors,
  ) {
    if (headings.isEmpty) return;
    final pdf = doc.document;
    final root = pdf.outline;
    final stack = <int, PdfOutline>{};
    for (final b in headings) {
      final h = b as _HeadingBlock;
      final node = PdfOutline(pdf, title: h.title, anchor: anchors[b]);
      PdfOutline? parent;
      for (int lv = h.level - 1; lv >= 1; lv--) {
        final candidate = stack[lv];
        if (candidate != null) {
          parent = candidate;
          break;
        }
      }
      (parent ?? root).add(node);
      stack[h.level] = node;
      // Drop deeper levels so siblings nest under the right parent.
      stack.removeWhere((k, _) => k > h.level);
    }
  }

  /// Clickable 目录. Each entry is an internal link to its heading anchor.
  static pw.Widget _toc(List<_Block> headings, Map<_Block, String> anchors) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '目录',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Divider(color: PdfColors.grey400),
        pw.SizedBox(height: 6),
        ...headings.map((h) {
          final heading = h as _HeadingBlock;
          final indent = (heading.level - 1) * 14.0;
          return pw.Padding(
            padding: pw.EdgeInsets.only(left: indent, top: 2, bottom: 2),
            child: pw.Link(
              destination: anchors[h]!,
              child: pw.Text(
                heading.title,
                style: pw.TextStyle(
                  fontSize: heading.level <= 2 ? 11 : 9.5,
                  decoration: pw.TextDecoration.underline,
                  color: PdfColors.blue700,
                  fontWeight: heading.level <= 2
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // ---- Markdown block parser -------------------------------------------

  static List<_Block> _parseBlocks(String src) {
    final blocks = <_Block>[];
    final lines = src.split('\n');
    bool inFence = false;
    String fenceMark = '';
    String fenceLang = '';
    List<String> fenceBuf = [];
    List<String> paraBuf = [];
    List<String> quoteBuf = [];
    final listBuf = <_ListItem>[];
    List<String> tableBuf = [];

    void flushPara() {
      if (paraBuf.isEmpty) return;
      blocks.add(_ParagraphBlock(paraBuf.join(' ').trim()));
      paraBuf = [];
    }

    void flushQuote() {
      if (quoteBuf.isEmpty) return;
      blocks.add(_QuoteBlock(quoteBuf.join('\n').trim()));
      quoteBuf = [];
    }

    void flushList() {
      if (listBuf.isEmpty) return;
      blocks.add(_ListBlock(List.of(listBuf)));
      listBuf.clear();
    }

    void flushTable() {
      if (tableBuf.isEmpty) return;
      blocks.add(_TableBlock(List.of(tableBuf)));
      tableBuf = [];
    }

    void flushAll() {
      flushPara();
      flushQuote();
      flushList();
      flushTable();
    }

    for (final raw in lines) {
      final line = raw.trimRight();
      final t = line.trimLeft();

      if (t.startsWith('```') || t.startsWith('~~~')) {
        final mark = t.substring(0, 3);
        if (!inFence) {
          flushAll();
          inFence = true;
          fenceMark = mark;
          // Capture the fence language (```mermaid, ```dart, …).
          fenceLang = t.length > 3 ? t.substring(3).trim() : '';
          fenceBuf = [];
        } else if (t.startsWith(fenceMark)) {
          inFence = false;
          blocks.add(_CodeBlock(fenceBuf.join('\n'), fenceLang));
          fenceBuf = [];
          fenceLang = '';
        } else {
          fenceBuf.add(raw);
        }
        continue;
      }

      if (inFence) {
        fenceBuf.add(raw);
        continue;
      }

      if (t.isEmpty) {
        flushPara();
        flushQuote();
        flushList();
        flushTable();
        continue;
      }

      // Heading
      final hm = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      if (hm != null) {
        flushAll();
        blocks.add(_HeadingBlock(hm.group(1)!.length, _stripInline(hm.group(2)!.trim())));
        continue;
      }

      // Horizontal rule
      if (RegExp(r'^(-{3,}|_{3,}|= {0,})$').hasMatch(t) && t.length > 2) {
        flushAll();
        blocks.add(_HrBlock());
        continue;
      }

      // Block quote
      if (t.startsWith('>')) {
        flushPara();
        flushList();
        flushTable();
        quoteBuf.add(t.replaceFirst(RegExp(r'^>\s*'), ''));
        continue;
      } else {
        flushQuote();
      }

      // Table rows
      if (t.startsWith('|') && t.endsWith('|')) {
        flushPara();
        flushList();
        tableBuf.add(t);
        continue;
      } else {
        flushTable();
      }

      // Lists
      final bullet = RegExp(r'^(-|\*|\+)\s+(.*)$').firstMatch(t);
      final ordered = RegExp(r'^(\d+)[\.\)]\s+(.*)$').firstMatch(t);
      if (bullet != null) {
        flushPara();
        listBuf.add(_ListItem(text: _stripInline(bullet.group(2)!), ordered: false));
        continue;
      }
      if (ordered != null) {
        flushPara();
        listBuf.add(_ListItem(
          text: _stripInline(ordered.group(2)!),
          ordered: true,
          number: int.tryParse(ordered.group(1)!) ?? 1,
        ));
        continue;
      } else if (!t.startsWith('-') && !t.startsWith('*') && !t.startsWith('+')) {
        // Continuation of a list item or a paragraph.
        if (listBuf.isNotEmpty && t.startsWith('  ')) {
          final last = listBuf.removeLast();
          listBuf.add(_ListItem(
            text: '${last.text} ${_stripInline(t)}',
            ordered: last.ordered,
            number: last.number,
          ));
          continue;
        }
        flushList();
      }

      paraBuf.add(_stripInline(t));
    }

    if (inFence && fenceBuf.isNotEmpty) {
      blocks.add(_CodeBlock(fenceBuf.join('\n'), ''));
    }
    flushAll();
    return blocks;
  }

  /// Strip inline markdown markers (`**`, `*`, `` ` ``, `[x](y)` → x).
  static String _stripInline(String s) {
    var out = s;
    out = out.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]+\)'),
      (m) => m.group(1)!,
    );
    out = out.replaceAll(RegExp(r'(\*\*|__)(.*?)(\*\*|__)'), r'$2');
    out = out.replaceAll(RegExp(r'`([^`]+)`'), r'$1');
    out = out.replaceAll(RegExp(r'(\*|_)([^*_]+)(\*|_)'), r'$2');
    out = out.replaceAll(RegExp(r'^>\s*'), '');
    return out;
  }
}

// ---- Block model --------------------------------------------------------

abstract class _Block {
  List<pw.Widget> build(Map<_Block, String> anchors);
}

class _HeadingBlock extends _Block {
  _HeadingBlock(this.level, this.title);
  final int level;
  final String title;

  @override
  List<pw.Widget> build(Map<_Block, String> anchors) {
    final size = switch (level) {
      1 => 18.0,
      2 => 15.0,
      3 => 13.0,
      4 => 11.5,
      _ => 10.5,
    };
    final anchor = anchors[this];
    final text = pw.Text(
      title,
      style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold),
    );
    return [
      pw.SizedBox(height: level <= 2 ? 12 : 8),
      if (anchor != null)
        pw.Anchor(name: anchor, child: text)
      else
        text,
      pw.SizedBox(height: 4),
    ];
  }
}

class _ParagraphBlock extends _Block {
  _ParagraphBlock(this.text);
  final String text;

  @override
  List<pw.Widget> build(Map<_Block, String> anchors) => [
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Text(text, style: const pw.TextStyle(fontSize: 10, lineSpacing: 3)),
        ),
      ];
}

class _QuoteBlock extends _Block {
  _QuoteBlock(this.text);
  final String text;

  @override
  List<pw.Widget> build(Map<_Block, String> anchors) => [
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 6),
          padding: const pw.EdgeInsets.only(left: 8, top: 4, bottom: 4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(left: pw.BorderSide(width: 2, color: PdfColors.grey500)),
          ),
          child: pw.Text(
            text,
            style: const pw.TextStyle(
              fontSize: 9.5,
              lineSpacing: 2,
              color: PdfColors.grey800,
            ),
          ),
        ),
      ];
}

class _ListItem {
  _ListItem({required this.text, required this.ordered, this.number = 1});
  final String text;
  final bool ordered;
  final int number;
}

class _ListBlock extends _Block {
  _ListBlock(this.items);
  final List<_ListItem> items;

  @override
  List<pw.Widget> build(Map<_Block, String> anchors) => [
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final item in items)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 8, bottom: 2),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(
                        width: 20,
                        child: pw.Text(
                          item.ordered ? '${item.number}.' : '•',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          item.text,
                          style: const pw.TextStyle(fontSize: 10, lineSpacing: 2),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ];
}

class _CodeBlock extends _Block {
  _CodeBlock(this.code, this.language);
  final String code;
  final String language;

  @override
  List<pw.Widget> build(Map<_Block, String> anchors) => [
        pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.only(bottom: 8),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(width: 0.5, color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Text(
            code.isEmpty ? '(空代码块)' : code,
            style: const pw.TextStyle(fontSize: 8.5, lineSpacing: 1.5),
          ),
        ),
      ];
}

class _HrBlock extends _Block {
  @override
  List<pw.Widget> build(Map<_Block, String> anchors) => [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 6),
          child: pw.Divider(color: PdfColors.grey400),
        ),
      ];
}

class _TableBlock extends _Block {
  _TableBlock(this.rows);
  final List<String> rows;

  @override
  List<pw.Widget> build(Map<_Block, String> anchors) {
    final cells = <List<String>>[];
    for (final row in rows) {
      final t = row.trim();
      // Skip the `|---|` separator row.
      if (RegExp(r'^\|(?:[-: ]+\|)+$').hasMatch(t.replaceAll(' ', ''))) continue;
      cells.add(
        t
            .substring(1, t.length - 1)
            .split('|')
            .map((c) => _PdfExporterInline.strip(c.trim()))
            .toList(),
      );
    }
    if (cells.isEmpty) return const [];
    final cols = cells.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    return [
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.TableHelper.fromTextArray(
          cellAlignment: pw.Alignment.centerLeft,
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 9),
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            for (int i = 0; i < cols; i++)
              i: const pw.FlexColumnWidth(1),
          },
          data: [
            for (final r in cells)
              [for (int i = 0; i < cols; i++) i < r.length ? r[i] : ''],
          ],
        ),
      ),
    ];
  }
}

/// Exposes [_stripInline] to the table renderer without widening the
/// parser API.
class _PdfExporterInline {
  static String strip(String s) => PdfExporter._stripInline(s);
}
