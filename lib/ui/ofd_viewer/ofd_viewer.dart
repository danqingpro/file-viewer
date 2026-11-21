import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/editor_kernel/editor_state.dart';
import '../../core/ofd/ofd_parser.dart';

/// In-app, offline OFD preview.
///
/// OFD (Open Fixed-layout Document) is the Chinese national fixed-layout
/// document standard: a ZIP package of XML describing pages, text, vector
/// paths and images. [OfdParser] turns it into draw primitives, and this
/// widget lays those out as white A4-style pages that can be scrolled and
/// pinch-zoomed.
///
/// If parsing fails (encrypted package, unsupported variant), the user can
/// still hand the file to any installed OFD reader via the system intent.
class OfdViewer extends StatefulWidget {
  const OfdViewer({super.key, required this.tab});

  final EditorTabController tab;

  @override
  State<OfdViewer> createState() => _OfdViewerState();
}

class _OfdViewerState extends State<OfdViewer> {
  late Future<OfdDocument> _future;
  final TransformationController _transform = TransformationController();
  double _scale = 1;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
    _future = _load();
  }

  Future<OfdDocument> _load() async {
    final bytes = widget.tab.bytes;
    if (bytes == null) {
      throw const OfdParseException('没有可用的文件内容');
    }
    // Parsing (unzip + XML) runs off the UI isolate.
    return compute(OfdParser.parse, bytes);
  }

  void _onTransform() {
    final s = _transform.value.getMaxScaleOnAxis();
    if ((s - _scale).abs() > 1e-3) setState(() => _scale = s);
  }

  Future<void> _openWithSystem() async {
    final bytes = widget.tab.bytes;
    if (bytes == null) return;
    setState(() => _opening = true);
    try {
      final dir = await getTemporaryDirectory();
      final name = (widget.tab.path ?? 'document.ofd')
          .split(Platform.pathSeparator)
          .last;
      final file = File(
          '${dir.path}/ofd_preview_${DateTime.now().microsecondsSinceEpoch}_$name');
      await file.writeAsBytes(bytes);
      await OpenFilex.open(file.path);
    } catch (_) {
      // Nothing to do — the error screen already explains the failure.
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEDEDED);

    return Container(
      color: bg,
      child: FutureBuilder<OfdDocument>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          if (snapshot.hasError) {
            return _ErrorView(
              message: snapshot.error.toString(),
              busy: _opening,
              onRetry: () => setState(() => _future = _load()),
              onOpenWithSystem: _openWithSystem,
            );
          }
          final doc = snapshot.data!;
          return LayoutBuilder(
            builder: (context, constraints) {
              final widthPx =
                  (constraints.maxWidth - 16).clamp(120.0, 4000.0).toDouble();
              return InteractiveViewer(
                transformationController: _transform,
                minScale: 0.5,
                maxScale: 5,
                // At 1× let the list scroll natively; once zoomed the
                // viewer pans instead.
                panEnabled: _scale > 1.001,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: doc.pages.length,
                  itemBuilder: (context, i) => Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _OfdPageView(
                        page: doc.pages[i],
                        widthPx: widthPx,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _OfdPageView extends StatelessWidget {
  const _OfdPageView({required this.page, required this.widthPx});

  final OfdPage page;
  final double widthPx;

  @override
  Widget build(BuildContext context) {
    final scale = widthPx / page.widthMm;
    final heightPx = page.heightMm * scale;
    return Container(
      width: widthPx,
      height: heightPx,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final e in page.elements)
              _element(e, scale, widthPx, heightPx),
          ],
        ),
      ),
    );
  }

  Widget _element(
    OfdElement e,
    double scale,
    double pageWidthPx,
    double pageHeightPx,
  ) {
    final left = e.x * scale;
    final top = e.y * scale;
    final w = (e.width * scale).clamp(0.0, pageWidthPx).toDouble();
    final h = (e.height * scale).clamp(0.0, pageHeightPx).toDouble();

    if (e is OfdTextElement) {
      return Positioned(
        left: left,
        top: top,
        child: Text(
          e.text,
          textScaler: TextScaler.noScaling,
          softWrap: false,
          style: TextStyle(
            fontSize: e.sizeMm * scale,
            height: 1.0,
            color: Color(e.color),
            fontFamilyFallback: const [
              'Noto Sans CJK SC',
              'Source Han Sans SC',
              'sans-serif',
            ],
          ),
        ),
      );
    }
    if (e is OfdPathElement) {
      return Positioned(
        left: left,
        top: top,
        width: w,
        height: h,
        child: CustomPaint(painter: _OfdPathPainter(e, scale)),
      );
    }
    if (e is OfdImageElement) {
      return Positioned(
        left: left,
        top: top,
        width: w,
        height: h,
        child: Image.memory(
          e.bytes,
          fit: BoxFit.fill,
          gaplessPlayback: true,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Draws one OFD path. `AbbreviatedData` coordinates are in millimetres
/// relative to the object's boundary, so the canvas is scaled instead of
/// rebuilding the path at every zoom level.
class _OfdPathPainter extends CustomPainter {
  _OfdPathPainter(this.element, this.scale) : path = _buildPath(element.data);

  final OfdPathElement element;
  final double scale;
  final ui.Path path;

  static const Map<String, int> _argCounts = {
    'M': 2,
    'L': 2,
    'Q': 4,
    'B': 6,
    'A': 7,
    'C': 0,
    'Z': 0,
  };

  /// Builds the CTM as a column-major matrix (a b c d e f).
  static Matrix4 _matrixOf(List<double> ctm) => Matrix4.identity()
    ..setEntry(0, 0, ctm[0])
    ..setEntry(1, 0, ctm[1])
    ..setEntry(0, 1, ctm[2])
    ..setEntry(1, 1, ctm[3])
    ..setEntry(0, 3, ctm[4])
    ..setEntry(1, 3, ctm[5]);

  static ui.Path _buildPath(String data) {
    final p = ui.Path();
    final tokens =
        data.split(RegExp(r'[\s,]+')).where((t) => t.isNotEmpty).toList();
    var i = 0;
    while (i < tokens.length) {
      final cmd = tokens[i++].toUpperCase();
      final n = _argCounts[cmd];
      if (n == null) break;
      final args = <double>[];
      for (var k = 0; k < n && i < tokens.length; k++) {
        args.add(double.tryParse(tokens[i++]) ?? 0);
      }
      switch (cmd) {
        case 'M':
          p.moveTo(args[0], args[1]);
          break;
        case 'L':
          p.lineTo(args[0], args[1]);
          break;
        case 'Q':
          p.quadraticBezierTo(args[0], args[1], args[2], args[3]);
          break;
        case 'B':
          p.cubicTo(args[0], args[1], args[2], args[3], args[4], args[5]);
          break;
        case 'A':
          // Arcs are rare in OFD; approximate with a straight segment.
          p.lineTo(args[5], args[6]);
          break;
        case 'C':
        case 'Z':
          p.close();
          break;
      }
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    final ctm = element.ctm;
    if (ctm != null) {
      canvas.transform(_matrixOf(ctm).storage);
    }
    if (element.fill) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = Color(element.fillColor),
      );
    }
    if (element.stroke) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = element.lineWidthMm
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Color(element.strokeColor),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OfdPathPainter old) =>
      old.scale != scale || old.element != element;
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.busy,
    required this.onRetry,
    required this.onOpenWithSystem,
  });

  final String message;
  final bool busy;
  final VoidCallback onRetry;
  final VoidCallback onOpenWithSystem;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: isDark ? Colors.white38 : Colors.black26),
            const SizedBox(height: 12),
            const Text('无法预览此 OFD 文档'),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重试'),
                ),
                FilledButton.icon(
                  onPressed: busy ? null : onOpenWithSystem,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_new, size: 18),
                  label: const Text('用系统应用打开'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
