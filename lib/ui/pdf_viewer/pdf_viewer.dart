import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/editor_kernel/editor_state.dart';

/// Renders a PDF file loaded into [tab] (its bytes are stored in
/// [EditorTabController.bytes]).
///
/// Uses `flutter_pdfview` (native Pdfium on Android). The bytes are first
/// written to a temp file because the native view expects a file path.
/// This is a read-only preview; editing PDFs is out of scope.
class PdfViewer extends StatefulWidget {
  const PdfViewer({super.key, required this.tab});

  final EditorTabController tab;

  @override
  State<PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<PdfViewer> {
  String? _tempPath;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _writeTempFile();
  }

  Future<void> _writeTempFile() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/pdf_preview_${DateTime.now().microsecondsSinceEpoch}.pdf');
      await file.writeAsBytes(widget.tab.bytes!);
      if (!mounted) return;
      setState(() {
        _tempPath = file.path;
        _ready = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    // Clean up the temp file.
    final p = _tempPath;
    if (p != null) {
      File(p).delete().catchError((_) => File(p));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text('无法打开此 PDF 文件',
                style: TextStyle(color: isDark ? Colors.white60 : Colors.black54)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(_error!,
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38),
                  textAlign: TextAlign.center),
            ),
          ],
        ),
      );
    }

    if (!_ready || _tempPath == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return PDFView(
      filePath: _tempPath!,
      enableSwipe: true,
      swipeHorizontal: false,
      autoSpacing: false,
      pageFling: false,
      fitPolicy: FitPolicy.BOTH,
      onError: (e) {
        if (mounted) setState(() => _error = e.toString());
      },
    );
  }
}
