import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Renders a Mermaid diagram source string inside an embedded WebView.
///
/// The WebView loads the bundled `assets/mermaid/mermaid.html` shell which
/// ships `mermaid.min.js` locally (fully offline). Once the page signals
/// readiness, [source] is pushed into `window.renderMermaid(code, theme)`.
/// The widget re-renders whenever [source] or [dark] changes, so it can
/// sit inside a live preview pane while the user types.
class MermaidView extends StatefulWidget {
  const MermaidView({
    super.key,
    required this.source,
    required this.dark,
    this.onError,
  });

  /// Mermaid diagram source (`graph TD; A-->B;` …).
  final String source;

  /// Whether the surrounding app theme is dark; switches the mermaid
  /// render theme between `dark` and `default`.
  final bool dark;

  /// Optional error listener — receives the mermaid parse error message.
  final ValueChanged<String>? onError;

  @override
  State<MermaidView> createState() => _MermaidViewState();
}

class _MermaidViewState extends State<MermaidView> {
  late final WebViewController _controller;
  bool _pageReady = false;
  String? _error;

  /// Debounce for source changes while the user types: mermaid.render is
  /// comparatively heavy, so re-render at most ~2.5×/second during edits.
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final bg = widget.dark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(bg)
      ..addJavaScriptChannel(
        'MermaidChannel',
        onMessageReceived: (msg) {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            if (data['status'] == 'ok') {
              if (_error != null && mounted) setState(() => _error = null);
            } else {
              final m = data['message']?.toString() ?? '渲染失败';
              widget.onError?.call(m);
              if (mounted) setState(() => _error = m);
            }
          } catch (_) {}
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _pageReady = true;
            _render();
          },
        ),
      )
      ..loadFlutterAsset('assets/mermaid/mermaid.html');
  }

  @override
  void didUpdateWidget(covariant MermaidView old) {
    super.didUpdateWidget(old);
    if (old.dark != widget.dark) {
      _controller.setBackgroundColor(
        widget.dark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF),
      );
      _render(immediate: true); // theme switch should feel instant
    } else if (old.source != widget.source) {
      _render(); // debounced while typing
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _render({bool immediate = false}) {
    if (!_pageReady) return;
    _debounce?.cancel();
    if (immediate) {
      _doRender();
    } else {
      _debounce = Timer(const Duration(milliseconds: 400), _doRender);
    }
  }

  void _doRender() {
    if (!_pageReady || !mounted) return;
    final theme = widget.dark ? 'dark' : 'default';
    final code = jsonEncode(widget.source);
    _controller.runJavaScript('window.renderMermaid($code, "$theme")');
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _controller),
        if (!_pageReady && _error == null)
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        if (_error != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: widget.dark
                  ? const Color(0xFF3A1D1D)
                  : const Color(0xFFFFEBEE),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 16,
                      color: widget.dark
                          ? const Color(0xFFFF8A80)
                          : const Color(0xFFD32F2F)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mermaid 语法错误',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.dark
                            ? const Color(0xFFFF8A80)
                            : const Color(0xFFD32F2F),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
