import 'package:flutter/material.dart';

import '../../core/config/app_info.dart';
import '../../core/config/app_settings.dart';
import '../../core/plugin_manager/plugin.dart';
import '../../editor_service.dart';
import '../status_bar/status_bar.dart' show kEncodingOptions, kLanguageOptions;

/// Top menu strip + quick-access toolbar, styled after VS Code:
///
///   * a compact horizontal menu row (文件 / 编辑 / 视图 / 格式 / 插件 / 语音 / 帮助),
///   * a compact horizontal toolbar below it whose buttons can render as
///     icon-only, text-only, or icon-above-text (chosen in the 视图 menu).
///
/// Each top-level entry is a [PopupMenuButton] so dropdowns work on desktop
/// and touch. Keyboard shortcuts are wired through [Shortcuts]/[Actions]
/// higher up the tree (see [EditorShell]).
class EditorMenuBar extends StatelessWidget {
  const EditorMenuBar({
    super.key,
    required this.service,
    required this.onAbout,
    required this.settings,
    this.onRename,
    this.onFeedback,
    this.onCheckUpdate,
    this.onOpenWorkspace,
    this.onToggleWorkspace,
  });

  final EditorService service;
  final VoidCallback onAbout;
  final AppSettings settings;

  /// Triggered by "文件 → 重命名…". The UI layer is responsible for showing
  /// a filename input dialog and then calling [EditorService.renameActiveTo].
  final VoidCallback? onRename;

  /// Triggered by "帮助 → 意见反馈".
  final VoidCallback? onFeedback;

  /// Triggered by "帮助 → 检查更新".
  final VoidCallback? onCheckUpdate;

  /// Triggered by "文件 → 打开文件夹作为工作区…". Wraps
  /// [EditorService.openWorkspace] so the shell can auto-open the drawer.
  final VoidCallback? onOpenWorkspace;

  /// Triggered by the toolbar "切换工作区" button — opens or closes
  /// the workspace drawer. No-op when no workspace is loaded.
  final VoidCallback? onToggleWorkspace;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3);
    final border = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE0E0E0);
    // Phones have a short screen; shrink the menu bar so every button is
    // reachable by thumb. Desktop keeps the roomier VS Code sizing.
    final isMobile = MediaQuery.of(context).size.shortestSide < 600;
    final menuHeight = isMobile ? 26.0 : 30.0;
    final menuFontSize = isMobile ? 12.0 : 13.0;

    return Material(
      color: surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---- Top menu strip (VS Code style, single row) ----
          SizedBox(
            height: menuHeight,
            child: Row(
              children: [
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    children: [
                      _menu(context, '文件', _fileItems(), menuFontSize),
                      _menu(context, '编辑', _editItems(), menuFontSize),
                      _menu(context, '视图', _viewItems(), menuFontSize),
                      _menu(context, '格式', _formatItems(), menuFontSize),
                      _menu(context, '编码', _encodingItems(), menuFontSize),
                      _menu(context, '语言', _languageItems(), menuFontSize),
                      _menu(context, '插件', _pluginItems(service), menuFontSize),
                      _menu(context, '语音', _voiceItems(), menuFontSize),
                      _menu(context, '帮助', _helpItems(), menuFontSize),
                    ],
                  ),
                ),
                if (!isMobile)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                      AppInfo.name,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: border),
          // ---- Quick-action toolbar (compact horizontal) ----
          AnimatedBuilder(
            animation: settings,
            builder: (context, _) {
              final mode = settings.toolbarMode;
              // On phones the icon+text row is too tall to reach; compress it.
              final rowHeight = isMobile
                  ? (mode == ToolbarDisplayMode.iconAndText ? 44.0 : 32.0)
                  : (mode == ToolbarDisplayMode.iconAndText ? 56.0 : 36.0);
              return SizedBox(
                height: rowHeight,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  children: [
                    _toolButton(context, Icons.note_add_outlined, '新建', service.newTab, mode, isMobile),
                    _toolButton(context, Icons.folder_open_outlined, '打开', service.openFiles, mode, isMobile),
                    // Workspace toggle button — only visible when a workspace is loaded.
                    if (service.workspacePath != null) ...[
                      _toolButton(
                        context,
                        Icons.folder_shared_outlined,
                        '工作区',
                        onToggleWorkspace ?? () {},
                        mode,
                        isMobile,
                      ),
                    ],
                    _toolButton(context, Icons.save_outlined, '保存', service.saveActive, mode, isMobile),
                    _toolButton(context, Icons.save_alt_outlined, '另存为', service.saveActiveAs, mode, isMobile),
                    _divider(isDark, isMobile),
                    _toolButton(context, Icons.undo_outlined, '撤销', service.undo, mode, isMobile),
                    _toolButton(context, Icons.redo_outlined, '重做', service.redo, mode, isMobile),
                    _divider(isDark, isMobile),
                    _toolButton(context, Icons.format_align_left_outlined, '格式化', service.applyFormat, mode, isMobile),
                    _toolButton(context, Icons.record_voice_over_outlined, '语音播报', service.speakSelected, mode, isMobile),
                    _divider(isDark, isMobile),
                    _themeButton(context, mode, isMobile),
                    _toolButton(context, Icons.info_outline, '关于', onAbout, mode, isMobile),
                  ],
                ),
              );
            },
          ),
          Divider(height: 1, thickness: 1, color: border),
        ],
      ),
    );
  }

  // ---- Menu item builders ------------------------------------------------

  List<PopupMenuEntry<Object>> _fileItems() {
    final recent = service.recentFiles;
    return [
      _item('新建文件', Icons.note_add_outlined, service.newTab, shortcut: 'Ctrl+N'),
      _item('打开文件…', Icons.folder_open_outlined, service.openFiles, shortcut: 'Ctrl+O'),
      _item('打开文件夹作为工作区…', Icons.folder_shared_outlined,
          onOpenWorkspace ?? service.openWorkspace),
      const PopupMenuDivider(),
      _item('重新读取文件', Icons.refresh_outlined, service.reloadActive, shortcut: 'Ctrl+R'),
      _item('保存', Icons.save_outlined, service.saveActive, shortcut: 'Ctrl+S'),
      _item('另存为…', Icons.save_alt_outlined, service.saveActiveAs, shortcut: 'Ctrl+Shift+S'),
      _item('拷贝另存为…', Icons.content_copy_outlined, service.saveActiveCopy),
      _item('全部保存', Icons.save_alt_outlined, service.saveAll, shortcut: 'Ctrl+Shift+L'),
      _item('重命名…', Icons.drive_file_rename_outline, onRename ?? () {}, shortcut: 'Ctrl+Shift+S'),
      const PopupMenuDivider(),
      _item('关闭标签页', Icons.close_outlined, () => service.closeTab(service.activeIndex), shortcut: 'Ctrl+W'),
      _item('全部关闭', Icons.close_fullscreen_outlined, service.closeAllTabs, shortcut: 'Ctrl+Shift+W'),
      _item('从磁盘删除', Icons.delete_outline, service.deleteActiveFromDisk),
      const PopupMenuDivider(),
      _item('恢复最近一个关闭的文件', Icons.restore_outlined, service.restoreLastClosed,
          shortcut: 'Ctrl+Shift+T'),
      if (recent.isNotEmpty) ...[
        _sectionHeader('最近打开的文件'),
        for (int i = 0; i < recent.length; i++)
          _item(
            '${i + 1}: ${_baseName(recent[i])}',
            Icons.description_outlined,
            () => service.openRecentFile(recent[i]),
          ),
        _item('打开所有最近的文件', Icons.folder_shared_outlined, service.openAllRecent),
        _item('清空最近的文件列表', Icons.delete_sweep_outlined, service.clearRecent),
      ],
      const PopupMenuDivider(),
      _item('退出', Icons.exit_to_app_outlined, service.exitApp, shortcut: 'Alt+F4'),
    ];
  }

  String _baseName(String path) {
    final i = path.lastIndexOf(RegExp(r'[/\\]'));
    return i == -1 ? path : path.substring(i + 1);
  }

  List<PopupMenuEntry<Object>> _editItems() => [
        _item('撤销', Icons.undo_outlined, service.undo, shortcut: 'Ctrl+Z'),
        _item('重做', Icons.redo_outlined, service.redo, shortcut: 'Ctrl+Y'),
        const PopupMenuDivider(),
        _item('剪切', Icons.content_cut_outlined, service.cut, shortcut: 'Ctrl+X'),
        _item('复制', Icons.copy_outlined, service.copy, shortcut: 'Ctrl+C'),
        _item('粘贴', Icons.paste_outlined, service.paste, shortcut: 'Ctrl+V'),
        _item('全选', Icons.select_all_outlined, service.selectAll, shortcut: 'Ctrl+A'),
      ];

  List<PopupMenuEntry<Object>> _viewItems() {
    final hasWorkspace = service.workspacePath != null;
    return [
      // Workspace drawer toggle (only when a workspace is loaded).
      if (hasWorkspace) ...[
        _item('切换工作区面板', Icons.folder_shared_outlined,
            onToggleWorkspace ?? () {}),
        const PopupMenuDivider(),
      ],
      const PopupMenuDivider(),
      _sectionHeader('主题'),
      _checkItem('浅色', Icons.light_mode_outlined, settings.themeMode == ThemeMode.light,
          () => settings.setThemeMode(ThemeMode.light)),
      _checkItem('深色', Icons.dark_mode_outlined, settings.themeMode == ThemeMode.dark,
          () => settings.setThemeMode(ThemeMode.dark)),
      _checkItem('跟随系统', Icons.brightness_auto_outlined, settings.themeMode == ThemeMode.system,
          () => settings.setThemeMode(ThemeMode.system)),
      const PopupMenuDivider(),
      _sectionHeader('工具栏显示'),
      _checkItem('仅图标', Icons.crop_original_outlined, settings.toolbarMode == ToolbarDisplayMode.iconOnly,
          () => settings.setToolbarMode(ToolbarDisplayMode.iconOnly)),
      _checkItem('仅文字', Icons.text_fields, settings.toolbarMode == ToolbarDisplayMode.textOnly,
          () => settings.setToolbarMode(ToolbarDisplayMode.textOnly)),
      _checkItem('图标 + 文字', Icons.view_module_outlined,
          settings.toolbarMode == ToolbarDisplayMode.iconAndText,
          () => settings.setToolbarMode(ToolbarDisplayMode.iconAndText)),
    ];
  }

  List<PopupMenuEntry<Object>> _formatItems() => [
        _item('一键格式化当前文件', Icons.format_align_left_outlined, service.applyFormat,
            shortcut: 'Ctrl+Shift+F'),
      ];

  List<PopupMenuEntry<Object>> _encodingItems() {
    final current = service.active?.encoding ?? 'UTF-8';
    return [
      _sectionHeader('转为编码（重新解码文件）'),
      for (final enc in kEncodingOptions)
        _checkItem(enc, Icons.text_fields, current == enc, () => service.switchEncoding(enc)),
    ];
  }

  List<PopupMenuEntry<Object>> _languageItems() {
    final current = service.active?.language ?? 'txt';
    return [
      _sectionHeader('切换语法高亮语言'),
      for (final lang in kLanguageOptions)
        _checkItem(_languageLabel(lang), Icons.code, current == lang, () => service.setLanguage(lang)),
    ];
  }

  List<PopupMenuEntry<Object>> _voiceItems() => [
        _item('播报选中文本', Icons.record_voice_over_outlined, service.speakSelected),
        _item('播报全文', Icons.campaign_outlined, service.speakAll),
        const PopupMenuDivider(),
        _item('暂停', Icons.pause_outlined, service.pauseVoice),
        _item('继续', Icons.play_arrow_outlined, service.resumeVoice),
        _item('停止', Icons.stop_outlined, service.stopVoice),
      ];

  List<PopupMenuEntry<Object>> _helpItems() => [
        _item('检查更新', Icons.system_update_alt_outlined, onCheckUpdate ?? () {}),
        _item('意见反馈', Icons.feedback_outlined, onFeedback ?? () {}),
        const PopupMenuDivider(),
        _item('关于 ${AppInfo.name}', Icons.info_outline, onAbout),
      ];

  List<PopupMenuEntry<Object>> _pluginItems(EditorService service) {
    final infos = service.plugins.describeAll();
    return [
      for (final p in infos) _pluginItem(p, service),
      const PopupMenuDivider(),
      _item('查看「关于」中的插件清单', Icons.list_alt, onAbout),
    ];
  }

  // ---- Widget helpers ----------------------------------------------------

  Widget _menu(BuildContext context, String label, List<PopupMenuEntry<Object>> items, double fontSize) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white70 : Colors.black87;
    return PopupMenuButton<Object>(
      tooltip: label,
      offset: const Offset(0, 30),
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      splashRadius: 16,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(label, style: TextStyle(fontSize: fontSize, color: fg)),
      ),
      itemBuilder: (_) => items,
    );
  }

  PopupMenuItem<Object> _item(
    String label,
    IconData icon,
    VoidCallback onTap, {
    String? shortcut,
  }) {
    return PopupMenuItem<Object>(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF007ACC)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          if (shortcut != null)
            Text(shortcut,
                style: const TextStyle(fontSize: 11, color: Colors.black45, fontFamily: 'monospace')),
        ],
      ),
      onTap: onTap,
    );
  }

  PopupMenuItem<Object> _checkItem(
    String label,
    IconData icon,
    bool checked,
    VoidCallback onTap,
  ) {
    return PopupMenuItem<Object>(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            checked ? Icons.check_box_outlined : Icons.check_box_outline_blank_outlined,
            size: 16,
            color: checked ? const Color(0xFF007ACC) : Colors.black38,
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 16, color: const Color(0xFF007ACC)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        ],
      ),
      onTap: onTap,
    );
  }

  PopupMenuEntry<Object> _sectionHeader(String title) {
    return PopupMenuItem<Object>(
      enabled: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(
        title,
        style: const TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w700),
      ),
    );
  }

  /// Human-readable label for a language id, matching the status bar.
  String _languageLabel(String lang) {
    switch (lang) {
      case 'txt':
        return '纯文本 (TXT)';
      case 'md':
        return 'Markdown (MD)';
      case 'cpp':
        return 'C/C++';
      case 'json':
        return 'JSON';
      case 'xml':
        return 'XML';
      case 'html':
        return 'HTML';
      case 'css':
        return 'CSS';
      case 'js':
        return 'JavaScript';
      case 'python':
        return 'Python';
      case 'yaml':
        return 'YAML';
      case 'batch':
        return '批处理 (BAT/CMD)';
      case 'binary':
        return '二进制 (BIN)';
      default:
        return lang.toUpperCase();
    }
  }

  PopupMenuItem<Object> _pluginItem(PluginInfo p, EditorService service) {
    return PopupMenuItem<Object>(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            p.enabled ? Icons.check_box_outlined : Icons.check_box_outline_blank_outlined,
            size: 16,
            color: p.enabled ? const Color(0xFF0A8754) : Colors.black45,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(p.displayName, style: const TextStyle(fontSize: 13))),
          Text('v${p.version}',
              style: const TextStyle(fontSize: 11, color: Colors.black45, fontFamily: 'monospace')),
        ],
      ),
      onTap: () {
        if (p.enabled) {
          service.plugins.disable(p.id);
        } else {
          service.plugins.enable(p.id);
        }
      },
    );
  }

  /// A compact toolbar button. Renders according to [mode]:
  ///   - iconOnly     : just the icon
  ///   - textOnly     : just the label
  ///   - iconAndText  : icon above, label below
  Widget _toolButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
    ToolbarDisplayMode mode,
    bool isMobile,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white70 : Colors.black87;
    const radius = BorderRadius.all(Radius.circular(4));
    final iconSize = isMobile ? 16.0 : 18.0;
    final textFontSize = isMobile ? 10.0 : 12.0;
    final subFontSize = isMobile ? 9.0 : 10.0;
    final hPad = isMobile ? 6.0 : 8.0;

    Widget child;
    switch (mode) {
      case ToolbarDisplayMode.iconOnly:
        child = Icon(icon, size: iconSize, color: fg);
        break;
      case ToolbarDisplayMode.textOnly:
        child = Text(label, style: TextStyle(fontSize: textFontSize, color: fg));
        break;
      case ToolbarDisplayMode.iconAndText:
        child = Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: iconSize, color: fg),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: subFontSize, color: fg)),
          ],
        );
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 4),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  /// Theme toggle button. Cycles light -> dark -> system on click.
  /// The icon reflects the *current* mode so users always know which state
  /// they are in without opening the menu.
  Widget _themeButton(BuildContext context, ToolbarDisplayMode mode, bool isMobile) {
    final current = settings.themeMode;
    final (icon, label) = switch (current) {
      ThemeMode.light => (Icons.light_mode_outlined, '主题：浅色'),
      ThemeMode.dark => (Icons.dark_mode_outlined, '主题：深色'),
      ThemeMode.system => (Icons.brightness_auto_outlined, '主题：跟随系统'),
    };
    return _toolButton(
      context,
      icon,
      label,
      () {
        final next = switch (current) {
          ThemeMode.light => ThemeMode.dark,
          ThemeMode.dark => ThemeMode.system,
          ThemeMode.system => ThemeMode.light,
        };
        settings.setThemeMode(next);
      },
      mode,
      isMobile,
    );
  }

  Widget _divider(bool isDark, bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 2 : 4, vertical: 6),
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: isDark ? const Color(0xFF3E3E42) : const Color(0xFFD0D0D0),
      ),
    );
  }
}
