import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'core/config/app_info.dart';
import 'core/config/app_settings.dart';
import 'core/config/app_theme.dart';
import 'core/editor_kernel/editor_state.dart';
import 'core/export/pdf_exporter.dart';
import 'core/update/background_update_service.dart';
import 'core/update/update_dialog.dart' show manualCheckForUpdate, UpdateDialog;
import 'editor_service.dart';
import 'plugins/voice_plugin/voice_plugin.dart' show VoiceState;
import 'ui/about/about_page.dart';
import 'ui/binary_viewer/binary_viewer.dart';
import 'ui/binary_viewer/large_binary_viewer.dart';
import 'ui/pdf_viewer/pdf_viewer.dart';
import 'ui/word_viewer/word_viewer.dart';
import 'ui/editor_view/editor_view.dart';
import 'ui/feedback/feedback_page.dart';
import 'ui/markdown/markdown_preview.dart';
import 'ui/menu/menu_bar.dart';
import 'ui/mermaid/mermaid_view.dart';
import 'ui/status_bar/status_bar.dart';
import 'ui/workspace/workspace_tree.dart';

/// Root widget: a thin [MaterialApp] that hosts the editor shell and the
/// About page route. Rebuilds when [AppSettings] changes so the theme and
/// toolbar display mode update live.
class EditorApp extends StatefulWidget {
  const EditorApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<EditorApp> createState() => _EditorAppState();
}

class _EditorAppState extends State<EditorApp> {
  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: widget.settings.themeMode,
      home: EditorShell(settings: widget.settings),
    );
  }
}

/// The main shell: menu + toolbar + tab strip + editor surface + status
/// bar. Owns the [EditorService] and wires global keyboard shortcuts.
class EditorShell extends StatefulWidget {
  const EditorShell({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends State<EditorShell> {
  late final EditorService _service;
  late final FocusNode _focusNode;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _service = EditorService()..addListener(_onServiceChanged);
    _focusNode = FocusNode();
    BackgroundUpdateService.instance.addListener(_onBackgroundUpdate);
  }

  @override
  void dispose() {
    BackgroundUpdateService.instance.removeListener(_onBackgroundUpdate);
    _service.removeListener(_onServiceChanged);
    _service.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _onBackgroundUpdate() {
    if (mounted) setState(() {});
    // When the background download finishes, surface a SnackBar so the
    // user knows the APK is ready to install (in case the banner was
    // missed or the app was backgrounded).
    final bg = BackgroundUpdateService.instance;
    if (bg.state == BackgroundUpdateState.ready &&
        _lastShownBgState != BackgroundUpdateState.ready) {
      _lastShownBgState = BackgroundUpdateState.ready;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('新版本 ${bg.info?.latestVersion} 已下载完成'),
          action: SnackBarAction(
            label: '安装',
            onPressed: () => bg.install(),
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } else if (bg.state == BackgroundUpdateState.failed) {
      _lastShownBgState = BackgroundUpdateState.failed;
    } else if (bg.state == BackgroundUpdateState.idle) {
      _lastShownBgState = BackgroundUpdateState.idle;
    }
  }

  /// Tracks the last banner state we surfaced a SnackBar for, so we
  /// don't re-show the "ready" SnackBar on every notifyListeners().
  BackgroundUpdateState _lastShownBgState = BackgroundUpdateState.idle;

  /// Toggle the workspace drawer. Called from the menu bar "切换工作区"
  /// button and from the "打开文件夹作为工作区" flow (auto-open).
  void _toggleWorkspaceDrawer() {
    if (_service.workspacePath == null) return;
    final scaffold = _scaffoldKey.currentState;
    if (scaffold == null) return;
    if (scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
    } else {
      scaffold.openDrawer();
    }
  }

  /// Close the workspace drawer (called after selecting a file).
  void _closeWorkspaceDrawer() {
    _scaffoldKey.currentState?.closeDrawer();
  }

  /// Close a tab, prompting to save if it has unsaved changes.
  ///
  /// Mirrors most editors' behaviour: a dirty tab shows a dialog with
  /// 保存 / 不保存 / 取消. Only [EditorTabController.dirty] text/binary
  /// tabs trigger the prompt (PDF / Word tabs are read-only and always
  /// close directly).
  Future<void> _closeTabWithConfirm(int index) async {
    if (index < 0 || index >= _service.tabs.length) return;
    final tab = _service.tabs[index];
    if (!_service.tabNeedsSaveConfirmation(index)) {
      _service.closeTab(index);
      return;
    }

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('保存文件？'),
        content: Text('文件「${tab.label}」尚未保存，是否保存修改？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: const Text('不保存'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (result == 'cancel') return;
    if (result == 'save') {
      // Re-index because other tabs may have changed state; use the same
      // label matching to find the tab we want to save.
      final idx = _service.tabs.indexOf(tab);
      if (idx == -1) return;
      if (idx != _service.activeIndex) {
        _service.switchTab(idx);
      }
      final saved = await _service.saveActive();
      if (!saved) return; // save failed or cancelled; do not close
    }
    // Find the index again (the tab list may have shifted after save).
    final idx = _service.tabs.indexOf(tab);
    if (idx == -1) return;
    _service.closeTab(idx);
  }

  Future<void> _openWorkspace() async {
    await _service.openWorkspace();
    // Auto-open the drawer once a workspace is selected.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_service.workspacePath != null && mounted) {
        _scaffoldKey.currentState?.openDrawer();
      }
    });
  }

  /// Build the Drawer widget that contains the workspace tree.
  /// Wraps [WorkspaceTree] in a Material Drawer so it slides in from
  /// the left with a scrim overlay; taps outside / back button close it.
  Widget _buildWorkspaceDrawer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      width: 300,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: SafeArea(
        child: WorkspaceTree(
          rootPath: _service.workspacePath!,
          service: _service,
          onClose: _service.closeWorkspace,
          onFileOpened: _closeWorkspaceDrawer,
        ),
      ),
    );
  }

  void _openAbout() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AboutPage(plugins: _service.plugins.describeAll()),
      ),
    );
  }

  /// 文件 → 导出 PDF…：renders the active Markdown / Mermaid tab to a
  /// PDF with a clickable table of contents, saves it under the app
  /// documents folder, then hands it to the system viewer.
  Future<void> _exportActivePdf() async {
    final tab = _service.active;
    if (tab == null || !tab.supportsPreview) {
      _showSnack('当前文件不支持导出 PDF（仅 Markdown / Mermaid 可用）');
      return;
    }
    if (tab.text.trim().isEmpty) {
      _showSnack('文件内容为空，没有可导出的内容');
      return;
    }

    final link = tab.label;
    final stem = link.replaceAll(
      RegExp(r'\.(md|markdown|mkd|mmd|mermaid)$', caseSensitive: false),
      '',
    );
    final safeName = stem.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    _showProgressDialog('正在生成 PDF…');

    try {
      final docs = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('.', '')
          .substring(0, 15);
      final outPath = '${docs.path}/exports/$safeName-$stamp.pdf';
      final path = await PdfExporter.exportMarkdown(
        markdown: tab.text,
        title: safeName,
        outputPath: outPath,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // dismiss progress
      _showSnack(
        '已导出 PDF：$path',
        action: SnackBarAction(
          label: '打开',
          onPressed: () => OpenFilex.open(path),
        ),
      );
      await OpenFilex.open(path);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showSnack('导出 PDF 失败：$e');
    }
  }

  /// Non-dismissible progress dialog shown while the PDF renders.
  void _showProgressDialog(String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12)),
        action: action,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  /// Manually check for updates (帮助 → 检查更新).
  void _onCheckUpdate() {
    manualCheckForUpdate(context);
  }

  /// Show a filename input dialog and rename the active file in place.
  void _onRename() {
    final tab = _service.active;
    if (tab == null || tab.path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有可重命名的文件，请先打开或保存文件')),
      );
      return;
    }
    final currentName = tab.label;
    final ctrl = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名文件'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新的文件名'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty) return;
              Navigator.of(ctx).pop();
              final (ok, err) = await _service.renameActiveTo(newName);
              if (!ok && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err ?? '重命名失败')),
                );
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// Open the feedback page (帮助 → 意见反馈).
  void _onFeedback() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FeedbackPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _service.active;
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): const _NewIntent(),
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): const _OpenIntent(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): const _SaveIntent(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): const _SaveAsIntent(),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): const _ReloadIntent(),
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): const _CloseTabIntent(),
        const SingleActivator(LogicalKeyboardKey.keyW, control: true, shift: true): const _CloseAllIntent(),
        const SingleActivator(LogicalKeyboardKey.keyT, control: true, shift: true): const _RestoreClosedIntent(),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): const _UndoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): const _RedoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true): const _FormatIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _NewIntent: CallbackAction<_NewIntent>(onInvoke: (_) => _service.newTab()),
          _OpenIntent: CallbackAction<_OpenIntent>(onInvoke: (_) => _service.openFiles()),
          _SaveIntent: CallbackAction<_SaveIntent>(onInvoke: (_) => _service.saveActive()),
          _SaveAsIntent: CallbackAction<_SaveAsIntent>(onInvoke: (_) => _service.saveActiveAs()),
          _ReloadIntent: CallbackAction<_ReloadIntent>(onInvoke: (_) => _service.reloadActive()),
          _CloseTabIntent: CallbackAction<_CloseTabIntent>(
              onInvoke: (_) => _closeTabWithConfirm(_service.activeIndex)),
          _CloseAllIntent: CallbackAction<_CloseAllIntent>(onInvoke: (_) => _service.closeAllTabs()),
          _RestoreClosedIntent:
              CallbackAction<_RestoreClosedIntent>(onInvoke: (_) => _service.restoreLastClosed()),
          _UndoIntent: CallbackAction<_UndoIntent>(onInvoke: (_) => _service.undo()),
          _RedoIntent: CallbackAction<_RedoIntent>(onInvoke: (_) => _service.redo()),
          _FormatIntent: CallbackAction<_FormatIntent>(onInvoke: (_) => _service.applyFormat()),
        },
          child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          child: Scaffold(
            key: _scaffoldKey,
            // Drawer-style workspace panel. Only shown when a workspace is
            // opened; otherwise the editor takes the full width. The user
            // can toggle it from the toolbar / menu.
            drawer: _service.workspacePath != null
                ? _buildWorkspaceDrawer()
                : null,
            // SafeArea keeps the menu bar clear of the phone status bar and
            // the bottom system gesture bar on mobile. On desktop it's a no-op.
            body: SafeArea(
              top: true,
              bottom: true,
              child: Stack(
                children: [
                  Column(
                    children: [
                      EditorMenuBar(
                        service: _service,
                        onAbout: _openAbout,
                        settings: widget.settings,
                        onRename: _onRename,
                        onFeedback: _onFeedback,
                        onCheckUpdate: _onCheckUpdate,
                        onOpenWorkspace: _openWorkspace,
                        onToggleWorkspace: _toggleWorkspaceDrawer,
                        onExportPdf: _exportActivePdf,
                        onCloseTab: () => _closeTabWithConfirm(_service.activeIndex),
                      ),
                      _TabStrip(service: _service, onCloseTab: _closeTabWithConfirm),
                      const Divider(height: 1, color: Color(0xFFE0E0E0)),
                      Expanded(
                        child: active == null
                            ? const _EmptyState()
                            : active.isPdf
                                ? PdfViewer(key: ValueKey(active), tab: active)
                                : active.isWord
                                    ? WordViewer(
                                        key: ValueKey(active), tab: active)
                                    : active.isLargeBinary
                                        ? LargeBinaryViewer(
                                            key: ValueKey(active), tab: active)
                                        : active.isBinary
                                            ? BinaryViewer(
                                                key: ValueKey(active),
                                                tab: active,
                                                onBytesChanged:
                                                    _service.updateBinaryBytes,
                                              )
                                            : _EditorWithPreview(
                                                key: ValueKey(active),
                                                tab: active,
                                                service: _service,
                                                onExportPdf: _exportActivePdf,
                                              ),
                      ),
                      if (active != null)
                        StatusBar(
                          tab: active,
                          fileTypeLabel: _service.fileTypeLabelFor(active),
                          byteSize: _byteSizeOf(active),
                          onEncodingChanged: (enc) => _service.switchEncoding(enc),
                          onLanguageChanged: (lang) => _service.setLanguage(lang),
                        ),
                    ],
                  ),
                  // Floating background-update banner pinned to the bottom.
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: const _BackgroundUpdateBanner(),
                  ),
                  // Floating voice controls while narration is playing.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 40,
                    child: Center(child: _VoiceBar(service: _service)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _byteSizeOf(EditorTabController tab) {
    // Large binary tabs keep their true size (never held in memory).
    if (tab.isLargeBinary) return tab.largeBinaryLength;
    if (tab.isBinary) return tab.bytes?.length ?? 0;
    // Live byte length of the current buffer in UTF-8 — accurate for the
    // status bar regardless of whether the file has been saved.
    try {
      return tab.text.codeUnits.fold<int>(0, (a, c) => a + (c < 0x80 ? 1 : (c < 0x800 ? 2 : 3)));
    } catch (_) {
      return -1;
    }
  }
}

/// Text editor surface with an exclusive Markdown / Mermaid preview mode.
///
/// Editing and preview are **mutually exclusive** (as requested): the tab
/// is either showing the source editor or the rendered preview, in both
/// portrait and landscape. The preview gets its own compact top bar with
/// 编辑 / 导出 PDF so the way back is always visible, and the toolbar
/// 预览 button is pinned to the front of the toolbar so it cannot scroll
/// off-screen in landscape.
class _EditorWithPreview extends StatelessWidget {
  const _EditorWithPreview({
    super.key,
    required this.tab,
    required this.service,
    required this.onExportPdf,
  });

  final EditorTabController tab;
  final EditorService service;
  final VoidCallback onExportPdf;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tab,
      builder: (context, _) {
        final previewOn = tab.previewEnabled && tab.supportsPreview;

        if (!previewOn) {
          return EditorView(
            tab: tab,
            highlightPlugin: service.highlightPlugin,
            onTextChanged: service.onTextChanged,
            onSelectionChanged: service.onSelectionChanged,
            onControllerAttached: service.bindLiveController,
            onControllerDetached: service.unbindLiveController,
          );
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final Widget preview = tab.language == 'mermaid'
            ? MermaidView(source: tab.text, dark: isDark)
            : MarkdownPreview(data: tab.text);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PreviewTopBar(
              isDark: isDark,
              title: tab.language == 'mermaid' ? '图表预览' : '预览',
              onEdit: service.togglePreview,
              onExportPdf: onExportPdf,
            ),
            Expanded(child: preview),
          ],
        );
      },
    );
  }
}

/// Compact bar shown above the rendered preview: 编辑 (back to source),
/// 导出 PDF. Kept separate from the app menu/toolbar so the exit path is
/// never hidden by the landscape toolbar overflow.
class _PreviewTopBar extends StatelessWidget {
  const _PreviewTopBar({
    required this.isDark,
    required this.title,
    required this.onEdit,
    required this.onExportPdf,
  });

  final bool isDark;
  final String title;
  final VoidCallback onEdit;
  final VoidCallback onExportPdf;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3);
    final border = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE0E0E0);
    final fg = isDark ? const Color(0xFFCCCCCC) : const Color(0xFF333333);
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: border, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black45,
              fontFamily: 'monospace',
            ),
          ),
          const Spacer(),
          _barButton(
            icon: Icons.picture_as_pdf_outlined,
            label: '导出 PDF',
            fg: fg,
            onTap: onExportPdf,
          ),
          const SizedBox(width: 4),
          _barButton(
            icon: Icons.edit_note_outlined,
            label: '编辑',
            fg: fg,
            onTap: onEdit,
          ),
        ],
      ),
    );
  }

  Widget _barButton({
    required IconData icon,
    required String label,
    required Color fg,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// Floating voice playback control. Appears while narration is running
/// and offers 暂停/继续 + 停止 — the fix for "播报开启后关不掉".
class _VoiceBar extends StatelessWidget {
  const _VoiceBar({required this.service});

  final EditorService service;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<VoiceState>(
      valueListenable: service.voicePlugin.stateListenable,
      builder: (context, state, _) {
        final busy = state == VoiceState.speaking || state == VoiceState.paused;
        if (!busy) return const SizedBox.shrink();
        final playing = state == VoiceState.speaking;
        final bg = isDark ? const Color(0xF2252526) : const Color(0xF2FFFFFF);
        final fg = isDark ? const Color(0xFFE0E0E0) : const Color(0xFF1F1F1F);
        final border = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFD0D0D0);
        return Material(
          color: bg,
          elevation: 4,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border, width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  playing ? Icons.graphic_eq : Icons.pause_circle_outline,
                  size: 16,
                  color: const Color(0xFF007ACC),
                ),
                const SizedBox(width: 6),
                Text(
                  playing ? '正在播报' : '已暂停',
                  style: TextStyle(fontSize: 12, color: fg),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    if (playing) {
                      await service.pauseVoice();
                    } else {
                      await service.resumeVoice();
                    }
                  },
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(playing ? '暂停' : '继续',
                      style: const TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: service.stopVoice,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: const Color(0xFFD32F2F),
                  ),
                  child: const Text('停止', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Horizontal scrollable tab strip with close buttons, mirroring Notepad++.
class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.service, required this.onCloseTab});
  final EditorService service;
  final void Function(int index) onCloseTab;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final tabs = service.tabs;
        final active = service.activeIndex;
        return Container(
          height: 30,
          color: isDark ? const Color(0xFF252526) : const Color(0xFFEAEAEA),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: tabs.length,
            itemBuilder: (context, i) {
              final tab = tabs[i];
              final isActive = i == active;
              return _TabChip(
                label: tab.label,
                active: isActive,
                dirty: tab.dirty,
                isDark: isDark,
                onTap: () => service.switchTab(i),
                onClose: () => onCloseTab(i),
              );
            },
          ),
        );
      },
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.active,
    required this.dirty,
    required this.isDark,
    required this.onTap,
    required this.onClose,
  });

  final String label;
  final bool active;
  final bool dirty;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final inactiveBg = isDark ? const Color(0xFF2D2D30) : const Color(0xFFEAEAEA);
    final activeBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final border = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFD5D5D5);
    final inactiveFg = isDark ? const Color(0xFF969696) : const Color(0xFF333333);
    final closeFg = isDark ? const Color(0xFF858585) : const Color(0xFF666666);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: active ? activeBg : inactiveBg,
          border: Border(
            right: BorderSide(color: border, width: 1),
            bottom: BorderSide(color: active ? activeBg : border, width: 1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: active ? const Color(0xFF007ACC) : inactiveFg,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 6),
            if (dirty)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.circle, size: 8, color: Color(0xFFFF9800)),
              ),
            InkWell(
              onTap: onClose,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close, size: 14, color: closeFg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating banner that reflects the background update download state.
/// Hidden when idle. Shows progress while downloading, an install action
/// when ready, and an error message if the download failed.
class _BackgroundUpdateBanner extends StatelessWidget {
  const _BackgroundUpdateBanner();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: BackgroundUpdateService.instance,
      builder: (context, _) {
        final bg = BackgroundUpdateService.instance;
        if (bg.state == BackgroundUpdateState.idle) {
          return const SizedBox.shrink();
        }
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final cardColor = isDark ? const Color(0xFF2D2D30) : Colors.white;
        final fg = isDark ? Colors.white : Colors.black87;
        final accent = Theme.of(context).primaryColor;

        return Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(8),
          color: cardColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  bg.state == BackgroundUpdateState.ready
                      ? Icons.system_update_alt
                      : bg.state == BackgroundUpdateState.failed
                          ? Icons.error_outline
                          : Icons.download_rounded,
                  color: bg.state == BackgroundUpdateState.failed
                      ? Colors.red.shade400
                      : accent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (bg.state == BackgroundUpdateState.downloading)
                        Text(
                          '后台下载新版本 ${bg.info?.latestVersion}：${(bg.progress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(color: fg, fontSize: 13),
                        )
                      else if (bg.state == BackgroundUpdateState.ready)
                        Text(
                          '新版本 ${bg.info?.latestVersion} 已下载完成，可立即安装',
                          style: TextStyle(color: fg, fontSize: 13),
                        )
                      else
                        Text(
                          bg.error ?? '后台下载失败',
                          style: TextStyle(color: Colors.red.shade400, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (bg.state == BackgroundUpdateState.downloading) ...[
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: bg.progress.clamp(0.0, 1.0),
                          backgroundColor: isDark ? Colors.white12 : Colors.black12,
                          color: accent,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (bg.state == BackgroundUpdateState.ready)
                  TextButton(
                    onPressed: () => bg.install(),
                    child: const Text('安装'),
                  )
                else if (bg.state == BackgroundUpdateState.downloading)
                  TextButton(
                    onPressed: () => bg.dismiss(),
                    child: const Text('取消'),
                  )
                else
                  TextButton(
                    onPressed: () => bg.dismiss(),
                    child: const Text('关闭'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? const Color(0xFF5A5A5A) : const Color(0xFFBBBBBB);
    final sub = isDark ? const Color(0xFF7A7A7A) : const Color(0xFF999999);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined, size: 56, color: fg),
          const SizedBox(height: 12),
          Text('没有打开的标签页', style: TextStyle(color: sub)),
        ],
      ),
    );
  }
}

// --- Shortcut intents -------------------------------------------------------

class _NewIntent extends Intent {
  const _NewIntent();
}

class _OpenIntent extends Intent {
  const _OpenIntent();
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _SaveAsIntent extends Intent {
  const _SaveAsIntent();
}

class _ReloadIntent extends Intent {
  const _ReloadIntent();
}

class _CloseTabIntent extends Intent {
  const _CloseTabIntent();
}

class _CloseAllIntent extends Intent {
  const _CloseAllIntent();
}

class _RestoreClosedIntent extends Intent {
  const _RestoreClosedIntent();
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

class _FormatIntent extends Intent {
  const _FormatIntent();
}
