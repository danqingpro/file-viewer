import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/config/app_info.dart';
import 'core/config/app_settings.dart';
import 'core/config/app_theme.dart';
import 'core/editor_kernel/editor_state.dart';
import 'core/update/update_dialog.dart';
import 'editor_service.dart';
import 'ui/about/about_page.dart';
import 'ui/binary_viewer/binary_viewer.dart';
import 'ui/editor_view/editor_view.dart';
import 'ui/menu/menu_bar.dart';
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

  @override
  void initState() {
    super.initState();
    _service = EditorService()..addListener(_onServiceChanged);
    _focusNode = FocusNode();
    // Check for app updates in the background; shows a dialog if a newer
    // version is published on GitHub. Silent on failure.
    checkAndShowUpdate(context);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _service.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _openAbout() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AboutPage(plugins: _service.plugins.describeAll()),
      ),
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
              onInvoke: (_) => _service.closeTab(_service.activeIndex)),
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
            // SafeArea keeps the menu bar clear of the phone status bar and
            // the bottom system gesture bar on mobile. On desktop it's a no-op.
            body: SafeArea(
              top: true,
              bottom: true,
              child: Column(
                children: [
                  EditorMenuBar(service: _service, onAbout: _openAbout, settings: widget.settings),
                  _TabStrip(service: _service),
                  const Divider(height: 1, color: Color(0xFFE0E0E0)),
                  Expanded(
                    child: Row(
                      children: [
                        if (_service.workspacePath != null)
                          WorkspaceTree(
                            rootPath: _service.workspacePath!,
                            service: _service,
                            onClose: _service.closeWorkspace,
                          ),
                        Expanded(
                          child: active == null
                              ? const _EmptyState()
                              : active.isBinary
                                  ? BinaryViewer(
                                      key: ValueKey(active),
                                      tab: active,
                                      onBytesChanged: _service.updateBinaryBytes,
                                    )
                                  : EditorView(
                                      key: ValueKey(active),
                                      tab: active,
                                      highlightPlugin: _service.highlightPlugin,
                                      onTextChanged: _service.onTextChanged,
                                      onSelectionChanged: _service.onSelectionChanged,
                                      onControllerAttached: _service.bindLiveController,
                                      onControllerDetached: _service.unbindLiveController,
                                    ),
                        ),
                      ],
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
            ),
          ),
        ),
      ),
    );
  }

  int _byteSizeOf(EditorTabController tab) {
    // Live byte length of the current buffer in UTF-8 — accurate for the
    // status bar regardless of whether the file has been saved.
    try {
      return tab.text.codeUnits.fold<int>(0, (a, c) => a + (c < 0x80 ? 1 : (c < 0x800 ? 2 : 3)));
    } catch (_) {
      return -1;
    }
  }
}

/// Horizontal scrollable tab strip with close buttons, mirroring Notepad++.
class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.service});
  final EditorService service;

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
                onClose: () => service.closeTab(i),
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
