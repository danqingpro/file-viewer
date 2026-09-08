import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/editor_kernel/editor_state.dart';

/// Renders a Word document loaded into [tab] (its bytes are stored in
/// [EditorTabController.bytes]).
///
/// Word documents (`.doc` / `.docx`) are handed to the system's native
/// document viewer (Word / WPS / Google Docs …) via `open_filex`. This
/// reliably supports every Word sub-format — including the legacy binary
/// `.doc` container that no pure-Dart library can decode — and keeps the
/// preview strictly read-only. The bytes are first written to a temp file
/// preserving the original extension so the system viewer recognizes the
/// format.
class WordViewer extends StatefulWidget {
  const WordViewer({super.key, required this.tab});

  final EditorTabController tab;

  @override
  State<WordViewer> createState() => _WordViewerState();
}

class _WordViewerState extends State<WordViewer> {
  String? _tempPath;
  bool _ready = false;
  String? _error;
  OpenResult? _lastResult;

  @override
  void initState() {
    super.initState();
    _writeTempFileAndOpen();
  }

  Future<void> _writeTempFileAndOpen() async {
    try {
      final dir = await getTemporaryDirectory();
      final ext = _extensionOf(widget.tab.path);
      final file = File(
          '${dir.path}/word_preview_${DateTime.now().microsecondsSinceEpoch}.$ext');
      await file.writeAsBytes(widget.tab.bytes!);
      if (!mounted) return;
      setState(() {
        _tempPath = file.path;
        _ready = true;
      });
      // Hand off to the system document viewer (Word / WPS / Google Docs).
      final result = await OpenFilex.open(file.path);
      if (!mounted) return;
      setState(() => _lastResult = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  String _extensionOf(String? path) {
    if (path == null) return 'docx';
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return 'docx';
    return path.substring(dot + 1).toLowerCase();
  }

  Future<void> _reopen() async {
    final p = _tempPath;
    if (p == null) return;
    final result = await OpenFilex.open(p);
    if (!mounted) return;
    setState(() => _lastResult = result);
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
    final fg = isDark ? Colors.white60 : Colors.black54;
    final sub = isDark ? Colors.white38 : Colors.black38;

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text('无法打开此 Word 文档', style: TextStyle(color: fg)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(_error!,
                  style: TextStyle(fontSize: 12, color: sub),
                  textAlign: TextAlign.center),
            ),
          ],
        ),
      );
    }

    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }

    final opened = _lastResult?.type == ResultType.done;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 56, color: fg),
            const SizedBox(height: 12),
            Text(
              opened ? '已调用系统查看器打开 Word 文档' : '已生成预览文件',
              style: TextStyle(color: fg),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              opened ? '可在系统文档应用中查看。如未弹出，点击下方按钮重试。' : '点击下方按钮调用系统查看器打开文档。',
              style: TextStyle(fontSize: 12, color: sub),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _reopen,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('在系统查看器中打开'),
            ),
          ],
        ),
      ),
    );
  }
}
