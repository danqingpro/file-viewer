import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// A parsed, ready-to-render OFD document.
///
/// All geometry is in millimetres (the OFD coordinate unit). The UI layer
/// converts to device pixels when laying pages out.
class OfdDocument {
  const OfdDocument({required this.pages});

  final List<OfdPage> pages;

  bool get isEmpty => pages.isEmpty;
}

class OfdPage {
  const OfdPage({
    required this.widthMm,
    required this.heightMm,
    required this.elements,
  });

  final double widthMm;
  final double heightMm;
  final List<OfdElement> elements;
}

/// A drawing primitive positioned by its `Boundary` rectangle, in millimetres.
sealed class OfdElement {
  const OfdElement({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;
}

class OfdTextElement extends OfdElement {
  const OfdTextElement({
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required this.text,
    required this.sizeMm,
    required this.color,
  });

  final String text;
  final double sizeMm;

  /// ARGB colour.
  final int color;
}

class OfdPathElement extends OfdElement {
  const OfdPathElement({
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required this.data,
    required this.fill,
    required this.stroke,
    required this.fillColor,
    required this.strokeColor,
    required this.lineWidthMm,
    this.ctm,
  });

  /// Raw OFD `AbbreviatedData`, coordinates relative to the boundary origin.
  final String data;
  final bool fill;
  final bool stroke;
  final int fillColor;
  final int strokeColor;
  final double lineWidthMm;

  /// Optional `CTM` matrix (`a b c d e f`) applied to [data] before drawing.
  final List<double>? ctm;
}

class OfdImageElement extends OfdElement {
  const OfdImageElement({
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required this.bytes,
  });

  final Uint8List bytes;
}

class OfdParseException implements Exception {
  const OfdParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Minimal OFD (GB/T 33190) parser: unzips the package, walks
/// `OFD.xml → Document.xml → Pages/Page_N/Content.xml`, and collects text,
/// path and image primitives. Templates referenced by a page are rendered
/// first so backgrounds and table rules appear underneath the content.
///
/// Fonts are not embedded here: text is drawn with the platform font at the
/// size declared by the document, which is enough for on-screen preview.
class OfdParser {
  static OfdDocument parse(Uint8List bytes) {
    final files = _unzip(bytes);
    if (files.isEmpty) {
      throw const OfdParseException('文件为空或不是有效的 OFD 压缩包');
    }

    final rootPath = _findFile(files, 'OFD.xml') ?? files.keys.first;
    final rootXml = _readXml(files[rootPath]!);
    final docRoot = _textOf(rootXml.rootElement, 'DocRoot') ??
        _firstTextLocal(rootXml, 'DocRoot');
    final docPath = docRoot == null
        ? (_findFile(files, 'Document.xml') ??
            (throw const OfdParseException('OFD 缺少 Document.xml')))
        : _resolve(_dir(rootPath), docRoot);
    final docFilePath = _findFile(files, docPath) ??
        _findFile(files, 'Document.xml') ??
        (throw const OfdParseException('OFD 缺少 Document.xml'));

    final docXml = _readXml(files[docFilePath]!);
    final docDir = _dir(docFilePath);
    final common = _childLocal(docXml.rootElement, 'CommonData');

    final defaultBox =
        _boxFrom(_firstBoxText(common)) ?? const _Box(0, 0, 210, 297);

    // Font/multimedia resources referenced by the page content.
    final media = <String, Uint8List>{};
    final resLocs = <String>[
      if (_textOf(common, 'PublicRes') != null) _textOf(common, 'PublicRes')!,
      if (_textOf(common, 'DocumentRes') != null)
        _textOf(common, 'DocumentRes')!,
    ];
    for (final loc in resLocs) {
      final path = _findFile(files, _resolve(docDir, loc));
      if (path == null) continue;
      final resXml = _readXml(files[path]!);
      // `ofd:Res` may declare BaseLoc="Res", making MediaFile paths relative
      // to that folder rather than to the XML file.
      final baseLoc = resXml.rootElement.getAttribute('BaseLoc') ?? '';
      final base = _resolve(_dir(path), baseLoc);
      _collectMedia(resXml, base, files, media);
    }

    // Page templates: page elements reference these by ID.
    final templates = <String, String>{};
    if (common != null) {
      for (final tpl in common.childElements
          .where((e) => e.name.local == 'TemplatePage')) {
        final id = tpl.getAttribute('ID');
        final loc = tpl.getAttribute('BaseLoc');
        if (id != null && loc != null) templates[id] = loc;
      }
    }

    final pagesEl = _childLocal(docXml.rootElement, 'Pages');
    if (pagesEl == null) {
      throw const OfdParseException('OFD 中没有页面');
    }

    final pages = <OfdPage>[];
    for (final pageEl
        in pagesEl.childElements.where((e) => e.name.local == 'Page')) {
      final loc = pageEl.getAttribute('BaseLoc');
      if (loc == null) continue;
      final pagePath = _findFile(files, _resolve(docDir, loc));
      if (pagePath == null) continue;
      final pageXml = _readXml(files[pagePath]!);
      final pageRoot = pageXml.rootElement;

      final box = _boxFrom(_firstBoxText(pageRoot)) ?? defaultBox;

      final elements = <OfdElement>[];
      // Templates (backgrounds, watermarks) come first.
      for (final tplEl
          in pageRoot.childElements.where((e) => e.name.local == 'Template')) {
        final tplId = tplEl.getAttribute('TemplateID');
        final tplLoc = tplId == null ? null : templates[tplId];
        if (tplLoc == null) continue;
        final tplPath = _findFile(files, _resolve(docDir, tplLoc));
        if (tplPath == null) continue;
        elements.addAll(_parseContent(_readXml(files[tplPath]!), media));
      }
      elements.addAll(_parseContent(pageXml, media));

      pages.add(OfdPage(
        widthMm: box.width,
        heightMm: box.height,
        elements: elements,
      ));
    }

    if (pages.isEmpty) {
      throw const OfdParseException('OFD 中没有可显示的页面');
    }
    return OfdDocument(pages: pages);
  }

  // ---------------------------------------------------------------- package

  static Map<String, Uint8List> _unzip(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: false);
    } catch (_) {
      throw const OfdParseException('无法解压该文件，可能不是 OFD 或已加密');
    }
    final files = <String, Uint8List>{};
    for (final f in archive.files) {
      if (!f.isFile) continue;
      files[_normalize(f.name)] = f.content;
    }
    return files;
  }

  static String _normalize(String name) =>
      name.startsWith('./') ? name.substring(2) : name;

  /// Case-insensitive lookup that also tolerates a leading `./`.
  static String? _findFile(Map<String, Uint8List> files, String name) {
    final n = _normalize(name);
    if (files.containsKey(n)) return n;
    final lower = n.toLowerCase();
    for (final k in files.keys) {
      if (k.toLowerCase() == lower) return k;
    }
    return null;
  }

  static void _collectMedia(
    XmlDocument xml,
    String baseDir,
    Map<String, Uint8List> files,
    Map<String, Uint8List> out,
  ) {
    for (final mm in _descendantsLocal(xml.rootElement, 'MultiMedia')) {
      final id = mm.getAttribute('ID');
      if (id == null) continue;
      final mediaFile = _childLocal(mm, 'MediaFile')?.innerText.trim();
      if (mediaFile == null || mediaFile.isEmpty) continue;
      final path = _findFile(files, _resolve(baseDir, mediaFile));
      if (path != null) out[id] = files[path]!;
    }
  }

  // ----------------------------------------------------------------- content

  static List<OfdElement> _parseContent(
    XmlDocument xml,
    Map<String, Uint8List> media,
  ) {
    final out = <OfdElement>[];
    final root = xml.rootElement;
    final content = _childLocal(root, 'Content') ?? root;
    for (final el in content.descendantElements) {
      switch (el.name.local) {
        case 'TextObject':
          out.addAll(_parseText(el));
          break;
        case 'PathObject':
          final path = _parsePath(el);
          if (path != null) out.add(path);
          break;
        case 'ImageObject':
          final image = _parseImage(el, media);
          if (image != null) out.add(image);
          break;
      }
    }
    return out;
  }

  static List<OfdTextElement> _parseText(XmlElement el) {
    final box = _box(el.getAttribute('Boundary'));
    if (box == null) return const [];
    final size = _num(el.getAttribute('Size')) ?? 3.5;
    final color = _colorOf(_childLocal(el, 'FillColor'));
    final letters = <OfdTextElement>[];
    final codes =
        el.childElements.where((e) => e.name.local == 'TextCode').toList();
    if (codes.isEmpty) {
      final plain = el.innerText.trim();
      if (plain.isEmpty) return const [];
      return [
        OfdTextElement(
          x: box.x,
          y: box.y,
          width: box.width,
          height: size * 1.2,
          text: plain,
          sizeMm: size,
          color: color,
        )
      ];
    }
    for (final code in codes) {
      final text = code.innerText;
      if (text.trim().isEmpty) continue;
      final dx = _num(code.getAttribute('X')) ?? 0;
      final dy = _num(code.getAttribute('Y')) ?? size;
      letters.add(OfdTextElement(
        x: box.x + dx,
        // `Y` is the baseline offset from the object's top edge.
        y: box.y + dy - size * 0.88,
        width: box.width,
        height: size * 1.2,
        text: text,
        sizeMm: size,
        color: color,
      ));
    }
    return letters;
  }

  static OfdPathElement? _parsePath(XmlElement el) {
    final box = _box(el.getAttribute('Boundary'));
    if (box == null) return null;
    final data = _childLocal(el, 'AbbreviatedData')?.innerText.trim() ?? '';
    if (data.isEmpty) return null;
    final fill = el.getAttribute('Fill') == 'true';
    final stroke = el.getAttribute('Stroke') == 'true' || !fill;
    return OfdPathElement(
      x: box.x,
      y: box.y,
      width: box.width,
      height: box.height,
      data: data,
      fill: fill,
      stroke: stroke,
      fillColor: _colorOf(_childLocal(el, 'FillColor')),
      strokeColor: _colorOf(_childLocal(el, 'StrokeColor')),
      lineWidthMm: _num(el.getAttribute('LineWidth')) ?? 0.353,
      ctm: _matrix(el.getAttribute('CTM')),
    );
  }

  static OfdImageElement? _parseImage(
    XmlElement el,
    Map<String, Uint8List> media,
  ) {
    final box = _box(el.getAttribute('Boundary'));
    final id = el.getAttribute('ResourceID');
    if (box == null || id == null) return null;
    final bytes = media[id];
    if (bytes == null || bytes.isEmpty) return null;
    return OfdImageElement(
      x: box.x,
      y: box.y,
      width: box.width,
      height: box.height,
      bytes: bytes,
    );
  }

  // -------------------------------------------------------------------- xml

  static XmlDocument _readXml(Uint8List bytes) {
    try {
      return XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      throw const OfdParseException('OFD 内的 XML 内容无法解析');
    }
  }

  static XmlElement? _childLocal(XmlElement? parent, String local) {
    if (parent == null) return null;
    for (final c in parent.childElements) {
      if (c.name.local == local) return c;
    }
    return null;
  }

  static Iterable<XmlElement> _descendantsLocal(
    XmlElement root,
    String local,
  ) =>
      root.descendantElements.where((e) => e.name.local == local);

  static String? _textOf(XmlElement? parent, String local) {
    final el = _childLocal(parent, local);
    final t = el?.innerText.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static String? _firstTextLocal(XmlDocument doc, String local) {
    for (final e in _descendantsLocal(doc.rootElement, local)) {
      final t = e.innerText.trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  /// Returns the first `PhysicalBox` text found under [root]. Page layouts
  /// put it at `Page/Area/PhysicalBox` or `Page/Area/PageArea/PhysicalBox`
  /// depending on the producer, so searching descendants covers both.
  static String? _firstBoxText(XmlElement? root) {
    if (root == null) return null;
    for (final e in _descendantsLocal(root, 'PhysicalBox')) {
      final t = e.innerText.trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  // ------------------------------------------------------------------ values

  static String _dir(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  static String _resolve(String base, String loc) {
    var p = loc.trim();
    if (p.startsWith('/')) p = p.substring(1);
    if (base.isEmpty) return _normalize(p);
    // Walk `..` segments if present.
    final parts = <String>[...base.split('/').where((s) => s.isNotEmpty)];
    for (final seg in p.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(seg);
      }
    }
    return parts.join('/');
  }

  static double? _num(String? s) =>
      s == null ? null : double.tryParse(s.trim());

  /// Parses a `CTM` attribute (`a b c d e f`).
  static List<double>? _matrix(String? s) {
    if (s == null) return null;
    final parts = s
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((p) => p.isNotEmpty)
        .map(double.tryParse)
        .whereType<double>()
        .toList();
    if (parts.length < 6) return null;
    return parts.sublist(0, 6);
  }

  static _Box? _boxFrom(String? s) => _box(s);

  static _Box? _box(String? s) {
    if (s == null) return null;
    final parts = s
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((p) => p.isNotEmpty)
        .map(double.tryParse)
        .whereType<double>()
        .toList();
    if (parts.length < 4) return null;
    return _Box(parts[0], parts[1], parts[2], parts[3]);
  }

  /// Parses an OFD colour element. Supports `#rr gg bb` hex components,
  /// decimal `0-255` components, `0-1` float components and CMYK.
  static int _colorOf(XmlElement? el) {
    const black = 0xFF000000;
    final value = el?.getAttribute('Value')?.trim();
    if (value == null || value.isEmpty) return black;
    final parts =
        value.split(RegExp(r'[\s,]+')).where((p) => p.isNotEmpty).toList();
    if (parts.length < 3) return black;

    final isHex = value.contains('#');
    final isFloat = !isHex && value.contains('.');
    int component(String raw) {
      final s = raw.replaceAll('#', '');
      if (isHex) return int.tryParse(s, radix: 16) ?? 0;
      if (isFloat) {
        return ((double.tryParse(s) ?? 0) * 255).round().clamp(0, 255).toInt();
      }
      final v = int.tryParse(s);
      // Some writers emit bare hex (`EE`).
      return v ?? (int.tryParse(s, radix: 16) ?? 0);
    }

    final c = parts.map(component).toList();
    int r, g, b;
    if (c.length >= 4) {
      final k = c[3] / 255.0;
      r = (c[0] / 255.0 * (1 - k) * 255).round();
      g = (c[1] / 255.0 * (1 - k) * 255).round();
      b = (c[2] / 255.0 * (1 - k) * 255).round();
    } else {
      r = c[0];
      g = c[1];
      b = c[2];
    }
    return 0xFF000000 |
        (r.clamp(0, 255).toInt() << 16) |
        (g.clamp(0, 255).toInt() << 8) |
        b.clamp(0, 255).toInt();
  }
}

class _Box {
  const _Box(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;
}
