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
  /// comparatively heavy, so re-render at most ~2×/second during edits.
  Timer? _debounce;

  /// Last (source, theme) actually pushed to the WebView. Lets us skip a
  /// redundant re-render when the parent rebuilds with identical content
  /// (e.g. the live-preview AnimatedBuilder fires on every cursor move).
  String? _lastSource;
  bool? _lastDark;

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
            final status = data['status'];
            if (status == 'ready') {
              // Page shell is up — render now if onPageFinished hasn't.
              if (!_pageReady) {
                _pageReady = true;
                _render(immediate: true);
              }
            } else if (status == 'ok') {
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
      _debounce = Timer(const Duration(milliseconds: 500), _doRender);
    }
  }

  void _doRender() {
    if (!_pageReady || !mounted) return;
    // Skip work entirely when neither the source nor the theme changed since
    // the last render — kills the "keeps refreshing" loop from parent rebuilds.
    if (_lastSource == widget.source && _lastDark == widget.dark) return;
    _lastSource = widget.source;
    _lastDark = widget.dark;

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

/// Scale-aware wrapper around [MermaidView] for surfaces where the diagram
/// is the primary content (the editor's preview pane and the full-screen
/// viewer).
///
/// Gesture strategy:
///   * at 1× [InteractiveViewer.panEnabled] is false, so one-finger drags
///     fall through to the WebView and the diagram scrolls natively (tall /
///     wide diagrams stay reachable) — this is what was broken before
///   * once the user pinch-zooms in, panning is handed to [InteractiveViewer]
///     so the zoomed image can be dragged around
class MermaidDiagramViewer extends StatefulWidget {
  const MermaidDiagramViewer({
    super.key,
    required this.source,
    required this.dark,
    this.onError,
  });

  final String source;
  final bool dark;
  final ValueChanged<String>? onError;

  @override
  State<MermaidDiagramViewer> createState() => _MermaidDiagramViewerState();
}

class _MermaidDiagramViewerState extends State<MermaidDiagramViewer> {
  final TransformationController _transform = TransformationController();
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
  }

  void _onTransform() {
    final s = _transform.value.getMaxScaleOnAxis();
    if ((s - _scale).abs() > 1e-3) setState(() => _scale = s);
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _transform,
      minScale: 0.3,
      maxScale: 6,
      panEnabled: _scale > 1.001,
      child: SizedBox.expand(
        child: MermaidView(
          source: widget.source,
          dark: widget.dark,
          onError: widget.onError,
        ),
      ),
    );
  }
}
