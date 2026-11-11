import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'core/config/app_info.dart';
import 'core/editor_kernel/editor_state.dart';
import 'core/file_kernel/encoding.dart' show utf16be, utf16le;
import 'core/file_kernel/file_kernel.dart';
import 'core/plugin_manager/event_bus.dart';
import 'core/plugin_manager/plugin_manager.dart';
import 'plugins/binary_viewer_plugin/binary_viewer_plugin.dart';
import 'plugins/pdf_viewer_plugin/pdf_viewer_plugin.dart';
import 'plugins/word_viewer_plugin/word_viewer_plugin.dart';
import 'plugins/file_type_plugin/file_type_plugin.dart';
import 'plugins/format_plugin/format_plugin.dart';
import 'plugins/highlight_plugin/highlight_plugin.dart';
import 'plugins/voice_plugin/voice_plugin.dart';
import 'ui/editor_view/highlighting_controller.dart';

/// The app-wide orchestrator. Owns the kernel (file kernel, plugin
/// manager, event bus) and the list of open tabs, and exposes the
/// high-level actions the menu / toolbar / shortcuts call into
/// (new/open/save/format/voice/clipboard…). Everything flows through here
/// so the UI widgets stay thin.
class EditorService extends ChangeNotifier {
  EditorService() {
    _plugins = PluginManager(_bus);
    _plugins.register(FileTypePlugin());
    _plugins.register(HighlightPlugin());
    _plugins.register(FormatPlugin());
    _plugins.register(VoicePlugin());
    _plugins.register(BinaryViewerPlugin());
    _plugins.register(PdfViewerPlugin());
    _plugins.register(WordViewerPlugin());
    _fileKernel = FileKernel(_bus);
    _fileType = _plugins.get<FileTypePlugin>('file_type_plugin')!;
    _highlight = _plugins.get<HighlightPlugin>('highlight_plugin')!;
    _format = _plugins.get<FormatPlugin>('format_plugin')!;
    _voice = _plugins.get<VoicePlugin>('voice_plugin')!;
    _binary = _plugins.get<BinaryViewerPlugin>('binary_viewer_plugin')!;
    _pdf = _plugins.get<PdfViewerPlugin>('pdf_viewer_plugin')!;
    _word = _plugins.get<WordViewerPlugin>('word_viewer_plugin')!;
    newTab();
  }

  final EventBus _bus = EventBus();
  late final PluginManager _plugins;
  late final FileKernel _fileKernel;
  late final FileTypePlugin _fileType;
  late final HighlightPlugin _highlight;
  late final FormatPlugin _format;
  late final VoicePlugin _voice;
  late final BinaryViewerPlugin _binary;
  late final PdfViewerPlugin _pdf;
  late final WordViewerPlugin _word;

  final List<EditorTabController> _tabs = [];
  int _active = 0;
  HighlightingController? _live;

  /// Recently opened file paths, newest first. Capped to keep the menu
  /// tidy (Notepad++ defaults to 10).
  final List<String> _recentFiles = [];
  static const int _maxRecent = 10;

  /// Snapshot of the most recently closed tab, so "恢复最近一个关闭的文件"
  /// can bring it back. Only the last closed tab is kept.
  EditorTabController? _lastClosed;

  PluginManager get plugins => _plugins;
  HighlightPlugin get highlightPlugin => _highlight;
  FormatPlugin get formatPlugin => _format;
  VoicePlugin get voicePlugin => _voice;
  BinaryViewerPlugin get binaryViewerPlugin => _binary;
  List<EditorTabController> get tabs => List.unmodifiable(_tabs);
  int get activeIndex => _tabs.isEmpty ? 0 : _active.clamp(0, _tabs.length - 1);
  EditorTabController? get active => _tabs.isEmpty ? null : _tabs[activeIndex];
  List<String> get recentFiles => List.unmodifiable(_recentFiles);

  /// Update the active binary tab's bytes (called by the hex viewer when
  /// the user edits bytes). Marks the tab dirty.
  void updateBinaryBytes(Uint8List bytes) {
    final tab = active;
    if (tab == null || !tab.isBinary) return;
    tab.updateBytes(bytes);
    notifyListeners();
  }

  /// Called by [EditorView] whenever its controller becomes the live edit
  /// target. Clipboard operations route through this controller so they
  /// touch the real selection.
  void bindLiveController(HighlightingController c) => _live = c;

  void unbindLiveController(HighlightingController c) {
    if (_live == c) _live = null;
  }

  // ---- Tabs ---------------------------------------------------------------

  void newTab() {
    final t = EditorTabController();
    _tabs.add(t);
    _active = _tabs.length - 1;
    notifyListeners();
    _bus.emit(AppEvents.tabSwitched, {'index': _active});
  }

  void switchTab(int index) {
    if (index < 0 || index >= _tabs.length || index == _active) return;
    _active = index;
    notifyListeners();
    _bus.emit(AppEvents.tabSwitched, {'index': index});
  }

  void closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final t = _tabs.removeAt(index);
    // Remember the closed tab so "恢复最近一个关闭的文件" can bring it back.
    // Dispose the previously remembered tab to avoid leaks.
    _lastClosed?.dispose();
    _lastClosed = t;
    if (_tabs.isEmpty) {
      newTab();
      return;
    }
    if (_active >= _tabs.length) _active = _tabs.length - 1;
    notifyListeners();
    _bus.emit(AppEvents.tabClosed, {'index': index});
  }

  /// Returns true if the tab at [index] has unsaved changes and the user
  /// should be asked whether to save before closing. Used by the UI to
  /// show a confirmation dialog before calling [closeTab].
  bool tabNeedsSaveConfirmation(int index) {
    if (index < 0 || index >= _tabs.length) return false;
    return _tabs[index].dirty;
  }

  /// Push a path onto the recent-files list (newest first), dropping
  /// duplicates and capping at [_maxRecent].
  void _trackRecent(String path) {
    _recentFiles.remove(path);
    _recentFiles.insert(0, path);
    if (_recentFiles.length > _maxRecent) _recentFiles.removeLast();
  }

  // ---- File operations ----------------------------------------------------

  static const _extensions = [
    'txt', 'md', 'markdown', 'mmd', 'mermaid',
    'cpp', 'cc', 'cxx', 'c', 'h', 'hpp', 'hh', 'hxx',
    'json', 'jsonc',
    'xml', 'svg', 'xhtml', 'xsd', 'xsl',
    'html', 'htm', 'shtml',
    'css', 'scss', 'less',
    'js', 'jsx', 'mjs', 'cjs',
    'py', 'pyw', 'pyi',
    'yaml', 'yml',
    'bat', 'cmd', 'sh', 'bash',
    'java', 'log',
  ];

  /// Binary files at or above this size (in bytes) are opened in on-demand
  /// (chunked) mode instead of being loaded fully into memory. Below it,
  /// the file is small enough to edit safely in the standard hex viewer.
  static const int _largeBinaryThreshold = 1024 * 1024; // 1 MiB

  Future<void> openFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      dialogTitle: '打开文件',
    );
    if (result == null || result.files.isEmpty) return;
    for (final f in result.files) {
      final path = f.path;
      if (path == null) continue;
      await _openPath(path);
    }
    _active = _tabs.length - 1;
    notifyListeners();
  }

  Future<bool> saveActive() async {
    final tab = active;
    if (tab == null) return false;
    // Large binaries are read-only on-demand views; there's nothing to
    // write back (and writing tab.text would corrupt the file).
    if (tab.isLargeBinary) return true;
    if (tab.path == null) return saveActiveAs();

    // Try a direct write first (works for files opened from the app's
    // cache directory). On Android, files saved via SAF (另存为) have a
    // Downloads path that may not be directly writable by dart:io — in
    // that case fall back to the saveFile-with-bytes flow.
    try {
      if (tab.isBinary) {
        final bytes = tab.bytes;
        if (bytes == null) return false;
        await _fileKernel.writeBytes(tab.path!, bytes);
      } else {
        await _fileKernel.write(tab.path!, tab.text, encodingLabel: tab.encoding);
      }
      tab.markSaved(path: tab.path!, encoding: tab.encoding);
      notifyListeners();
      return true;
    } catch (_) {
      // Direct write failed (e.g. Android scoped storage). Fall back to
      // the SAF save flow which writes bytes natively.
      return saveActiveAs();
    }
  }

  Future<bool> saveActiveAs() async {
    final tab = active;
    if (tab == null) return false;
    // Large binary on-demand views are read-only; exporting is out of scope.
    if (tab.isLargeBinary) return false;
    final ext = tab.path != null ? _extOf(tab.path!) : 'txt';
    // Default filename carries the app version number so "另存为" exports are
    // immediately identifiable, e.g. `report_v1.6.0.txt`.
    final base = _stripExtension(tab.label);
    final versioned = '${base}_v${AppInfo.versionNumber}.$ext';

    // Encode the content to bytes and pass them to saveFile(). On Android
    // the native SAF handler writes the bytes to the chosen content URI;
    // without bytes the native code crashes (NPE on outputStream.write).
    final Uint8List bytes = tab.isBinary
        ? (tab.bytes ?? Uint8List(0))
        : _fileKernel.encode(tab.text, encodingLabel: tab.encoding);

    final outPath = await FilePicker.platform.saveFile(
      dialogTitle: '另存为',
      fileName: versioned,
      type: FileType.any,
      bytes: bytes,
    );
    if (outPath == null || outPath.isEmpty) return false;
    tab.markSaved(path: outPath, encoding: tab.encoding);
    if (!tab.isBinary) {
      tab._setLanguage(_fileType.detect(outPath));
    }
    _trackRecent(outPath);
    notifyListeners();
    return true;
  }

  /// Remove a trailing extension (the last `.xxx`) from a filename so the
  /// version tag can be inserted cleanly before it.
  String _stripExtension(String name) {
    final i = name.lastIndexOf('.');
    return i <= 0 ? name : name.substring(0, i);
  }

  String _extOf(String path) {
    final i = path.lastIndexOf('.');
    return i == -1 ? 'txt' : path.substring(i + 1).toLowerCase();
  }

  String fileTypeLabelFor(EditorTabController tab) {
    if (tab.isPdf) return 'PDF 文档';
    if (tab.isWord) return 'Word 文档';
    return _fileType.labelFor(tab.language);
  }

  /// Reload the active tab's content from disk, discarding any unsaved
  /// edits. Mirrors Notepad++'s "文件 → 重新读取文件".
  Future<bool> reloadActive() async {
    final tab = active;
    if (tab == null || tab.path == null) return false;
    // On-demand views always read straight from disk; nothing to reload.
    if (tab.isLargeBinary) return true;
    try {
      if (tab.isBinary) {
        final bytes = await _fileKernel.readBytes(tab.path!);
        tab.bindBinary(path: tab.path!, bytes: bytes);
      } else {
        final loaded = await _fileKernel.read(tab.path!);
        tab.bindFile(
          path: loaded.path,
          content: loaded.content,
          encoding: loaded.encodingLabel,
          language: _fileType.detect(tab.path!),
        );
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// "拷贝另存为" — save a copy of the current buffer to a new path but
  /// keep the active tab bound to its original path (unlike 另存为 which
  /// re-points the tab). Mirrors Notepad++'s "文件 → 拷贝另存为".
  Future<bool> saveActiveCopy() async {
    final tab = active;
    if (tab == null) return false;
    // Large binary on-demand views are read-only.
    if (tab.isLargeBinary) return false;
    final ext = tab.path != null ? _extOf(tab.path!) : 'txt';
    final base = _stripExtension(tab.label);
    final Uint8List bytes = tab.isBinary
        ? (tab.bytes ?? Uint8List(0))
        : _fileKernel.encode(tab.text, encodingLabel: tab.encoding);
    final outPath = await FilePicker.platform.saveFile(
      dialogTitle: '拷贝另存为',
      fileName: '${base}_副本.$ext',
      type: FileType.any,
      bytes: bytes,
    );
    if (outPath == null || outPath.isEmpty) return false;
    _trackRecent(outPath);
    notifyListeners();
    return true;
  }

  /// Save every dirty tab. Tabs without a path are skipped (the user must
  /// save them individually with 另存为). Mirrors Notepad++'s "全部保存".
  Future<int> saveAll() async {
    int saved = 0;
    for (final tab in List.of(_tabs)) {
      if (tab.path == null) continue;
      if (!tab.dirty) continue;
      try {
        if (tab.isBinary) {
          final bytes = tab.bytes;
          if (bytes != null) {
            await _fileKernel.writeBytes(tab.path!, bytes);
            tab.markSaved(path: tab.path!, encoding: 'BINARY');
            saved++;
          }
        } else {
          await _fileKernel.write(tab.path!, tab.text, encodingLabel: tab.encoding);
          tab.markSaved(path: tab.path!, encoding: tab.encoding);
          saved++;
        }
      } catch (_) {
        // Direct write failed (Android scoped storage). Fall back to the
        // saveFile-with-bytes flow for this tab.
        if (await saveActiveAsFor(tab)) saved++;
      }
    }
    notifyListeners();
    return saved;
  }

  /// Internal: save a specific tab using the SAF flow (passes bytes to
  /// saveFile). Used by saveAll() when a direct write fails.
  Future<bool> saveActiveAsFor(EditorTabController tab) async {
    final ext = tab.path != null ? _extOf(tab.path!) : 'txt';
    final base = _stripExtension(tab.label);
    final versioned = '${base}_v${AppInfo.versionNumber}.$ext';
    final Uint8List bytes = tab.isBinary
        ? (tab.bytes ?? Uint8List(0))
        : _fileKernel.encode(tab.text, encodingLabel: tab.encoding);
    final outPath = await FilePicker.platform.saveFile(
      dialogTitle: '保存',
      fileName: versioned,
      type: FileType.any,
      bytes: bytes,
    );
    if (outPath == null || outPath.isEmpty) return false;
    tab.markSaved(path: outPath, encoding: tab.encoding);
    _trackRecent(outPath);
    return true;
  }

  /// Rename the active file in place (same directory, new filename).
  /// Mirrors Notepad++'s "文件 → 重命名".
  ///
  /// On Android, `File.rename` only works for files inside the app's
  /// private directories. For files in shared storage (opened via the
  /// system file picker or workspace), we fall back to a "save as +
  /// delete old" approach using FilePicker.saveFile (SAF).
  ///
  /// Returns a record of (success, errorMessage).
  Future<(bool, String?)> renameActiveTo(String newName) async {
    final tab = active;
    if (tab == null || tab.path == null) return (false, '没有可重命名的文件');
    // Large binary on-demand views are read-only.
    if (tab.isLargeBinary) return (false, '只读大文件不支持重命名');
    final oldPath = tab.path!;

    // Reject content URIs (SAF) — can't be renamed directly.
    if (oldPath.startsWith('content://')) {
      return (false, '此文件通过系统文件选择器打开，不支持原地重命名，请使用「另存为」');
    }

    final dir = oldPath.substring(0, oldPath.lastIndexOf(RegExp(r'[/\\]')) + 1);
    final newPath = '$dir$newName';
    if (newPath == oldPath) return (true, null);

    // Try direct rename first (works for workspace files with permission,
    // and for files in the app's cache directory).
    try {
      await File(oldPath).rename(newPath);
      _recentFiles.remove(oldPath);
      tab.markSaved(path: newPath, encoding: tab.encoding);
      if (!tab.isBinary) {
        tab._setLanguage(_fileType.detect(newPath));
      }
      _trackRecent(newPath);
      notifyListeners();
      return (true, null);
    } catch (_) {
      // Direct rename failed (likely Android scoped storage).
      // Fall back to "save as + delete old" via SAF.
    }

    // Fallback: use FilePicker.saveFile with the file's bytes, then
    // try to delete the old file.
    try {
      final Uint8List bytes = tab.isBinary
          ? (tab.bytes ?? Uint8List(0))
          : _fileKernel.encode(tab.text, encodingLabel: tab.encoding);

      final outPath = await FilePicker.platform.saveFile(
        dialogTitle: '重命名（选择保存位置）',
        fileName: newName,
        type: FileType.any,
        bytes: bytes,
      );
      if (outPath == null || outPath.isEmpty) {
        return (false, '重命名已取消');
      }

      // Try to delete the old file (may fail on scoped storage; that's OK).
      try {
        await File(oldPath).delete();
      } catch (_) {
        // Old file might remain; not a failure for the rename itself.
      }

      _recentFiles.remove(oldPath);
      tab.markSaved(path: outPath, encoding: tab.encoding);
      if (!tab.isBinary) {
        tab._setLanguage(_fileType.detect(outPath));
      }
      _trackRecent(outPath);
      notifyListeners();
      return (true, null);
    } catch (e) {
      return (false, '重命名失败：$e');
    }
  }

  /// Close every open tab. Mirrors Notepad++'s "全部关闭".
  void closeAllTabs() {
    for (final t in _tabs) {
      t.dispose();
    }
    _tabs.clear();
    _lastClosed?.dispose();
    _lastClosed = null;
    newTab();
  }

  /// Delete the active file from disk and close its tab. Mirrors
  /// Notepad++'s "从磁盘删除".
  Future<bool> deleteActiveFromDisk() async {
    final tab = active;
    if (tab == null || tab.path == null) return false;
    final path = tab.path!;
    try {
      await File(path).delete();
    } catch (_) {
      return false;
    }
    _recentFiles.remove(path);
    final idx = _active;
    _tabs.removeAt(idx);
    tab.dispose();
    if (_tabs.isEmpty) {
      newTab();
    } else {
      if (_active >= _tabs.length) _active = _tabs.length - 1;
    }
    notifyListeners();
    return true;
  }

  /// Re-open the most recently closed tab (content restored from memory).
  /// Mirrors Notepad++'s "恢复最近一个关闭的文件".
  void restoreLastClosed() {
    final t = _lastClosed;
    if (t == null) return;
    _lastClosed = null;
    _tabs.add(t);
    _active = _tabs.length - 1;
    if (t.path != null) _trackRecent(t.path!);
    notifyListeners();
  }

  /// Open every path in the recent-files list. Mirrors Notepad++'s
  /// "打开所有最近的文件".
  Future<void> openAllRecent() async {
    for (final path in List.of(_recentFiles)) {
      await _openPath(path);
    }
  }

  /// Clear the recent-files list. Mirrors Notepad++'s "清空最近的文件列表".
  void clearRecent() {
    _recentFiles.clear();
    notifyListeners();
  }

  /// Open a single file by path (used by the recent-files menu).
  Future<void> openRecentFile(String path) async {
    await _openPath(path);
  }

  /// Open one or more files by path. Used by the "Open with" / "Share
  /// with" flow — the shell forwards paths received from the OS share
  /// sheet.
  Future<void> openPaths(List<String> paths) async {
    for (final p in paths) {
      await _openPath(p);
    }
    if (_tabs.isNotEmpty) {
      _active = _tabs.length - 1;
      notifyListeners();
    }
  }

  Future<void> _openPath(String path) async {
    try {
      final isPdf = _pdf.isPdf(path);
      final isWord = _word.isWord(path);
      final isBin = _binary.isBinary(path);
      if (isPdf) {
        // PDF: read raw bytes and bind as a binary tab; the UI detects the
        // .pdf extension and renders the PdfViewer widget.
        final bytes = await _fileKernel.readBytes(path);
        final tab = EditorTabController()..bindBinary(path: path, bytes: bytes);
        _tabs.add(tab);
      } else if (isWord) {
        // Word: read raw bytes and bind as a binary tab; the UI detects the
        // .doc/.docx extension and renders the WordViewer widget, which
        // hands the temp file to the system document viewer (read-only).
        final bytes = await _fileKernel.readBytes(path);
        final tab = EditorTabController()..bindBinary(path: path, bytes: bytes);
        _tabs.add(tab);
      } else if (isBin) {
        // Binary file: small files load fully into memory and are editable
        // in hex; large files (.exe/.apk/…) open in on-demand mode so the
        // app doesn't freeze reading tens of megabytes at once.
        final binaryFile = File(path);
        final size = binaryFile.lengthSync();
        if (size >= _largeBinaryThreshold) {
          final tab = EditorTabController()
            ..bindLargeBinary(path: path, length: size);
          _tabs.add(tab);
        } else {
          final bytes = await _fileKernel.readBytes(path);
          final tab = EditorTabController()..bindBinary(path: path, bytes: bytes);
          _tabs.add(tab);
        }
      } else {
        final loaded = await _fileKernel.read(path);
        final lang = _fileType.detect(path);
        final tab = EditorTabController()
          ..bindFile(
            path: loaded.path,
            content: loaded.content,
            encoding: loaded.encodingLabel,
            language: lang,
          );
        _tabs.add(tab);
      }
      _trackRecent(path);
    } catch (_) {
      _recentFiles.remove(path);
    }
    _active = _tabs.length - 1;
    notifyListeners();
  }

  /// Exit the application. Mirrors Notepad++'s "文件 → 退出".
  void exitApp() {
    // SystemNavigator.pop asks the platform to close the app; on Android
    // this finishes the activity. Falls back to dart:io exit() on desktop.
    try {
      SystemNavigator.pop();
    } catch (_) {
      exit(0);
    }
  }

  // ---- Workspace (folder tree) --------------------------------------------

  String? _workspacePath;
  String? get workspacePath => _workspacePath;

  /// Open a folder as a workspace. The folder tree is shown in a side panel.
  /// Mirrors Notepad++'s "文件 → 打开文件夹作为工作区".
  ///
  /// On Android, requests storage permission first (all-files access on
  /// Android 11+). Without it, `Directory.listSync` and `File.readAsBytes`
  /// fail silently, which is why workspace files appeared unopenable.
  Future<bool> openWorkspace() async {
    await _ensureStoragePermission();
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择工作区文件夹',
    );
    if (dir == null || dir.isEmpty) return false;
    _workspacePath = dir;
    notifyListeners();
    return true;
  }

  /// Request the storage permission needed to browse / read workspace files.
  /// On Android 11+ this means "all files access", which requires sending
  /// the user to system settings. On older Android versions a normal
  /// runtime permission dialog is enough.
  Future<void> _ensureStoragePermission() async {
    if (!Platform.isAndroid) return;
    try {
      if (await Permission.manageExternalStorage.isGranted) return;
      // Try to request; on Android 11+ this opens the system settings page
      // where the user toggles "允许管理所有文件".
      final status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        // Fallback for older Android: request legacy read permission.
        await Permission.storage.request();
      }
    } catch (_) {
      // Permission API failures must not block the workspace picker.
    }
  }

  /// Close the workspace panel.
  void closeWorkspace() {
    _workspacePath = null;
    notifyListeners();
  }

  // ---- Encoding / language switching --------------------------------------

  /// Switch the active tab's encoding and re-decode the on-disk bytes with
  /// the new encoding. If the tab has no path (unsaved), just updates the
  /// label (next save uses it). Mirrors Notepad++'s "编码 → 转为 X 编码".
  Future<void> switchEncoding(String encoding) async {
    final tab = active;
    if (tab == null) return;
    // Large binary on-demand views are read-only byte data, not text.
    if (tab.isLargeBinary) return;
    final path = tab.path;
    if (path == null) {
      tab.setEncoding(encoding);
      notifyListeners();
      return;
    }
    try {
      final raw = await File(path).readAsBytes();
      String text;
      switch (encoding) {
        case 'UTF-8-BOM':
          final body = raw.length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF
              ? raw.sublist(3)
              : raw;
          text = utf8.decode(body, allowMalformed: true);
          break;
        case 'UTF-16-BE-BOM':
          text = utf16be.decode(_stripBom(raw, 2));
          break;
        case 'UTF-16-LE-BOM':
          text = utf16le.decode(_stripBom(raw, 2));
          break;
        case 'GBK':
          // Dart has no built-in GBK codec; use latin1 as a byte-stable
          // fallback so the file stays round-trippable.
          text = latin1.decode(raw, allowInvalid: true);
          break;
        case 'ANSI':
          // ANSI approximated as latin1 (ISO-8859-1).
          text = latin1.decode(raw, allowInvalid: true);
          break;
        case 'ASCII':
          text = String.fromCharCodes(raw.map((b) => b < 0x80 ? b : 0xFFFD));
          break;
        case 'UTF-8':
        default:
          text = utf8.decode(raw, allowMalformed: true);
      }
      tab.bindFile(path: path, content: text, encoding: encoding, language: tab.language);
    } catch (_) {
      tab.setEncoding(encoding);
    }
    notifyListeners();
  }

  /// Strip a leading BOM of [length] bytes if present.
  List<int> _stripBom(List<int> raw, int length) {
    if (raw.length >= length) return raw.sublist(length);
    return raw;
  }

  /// Switch the active tab's language (highlighter). No file re-read.
  void setLanguage(String language) {
    final tab = active;
    if (tab == null) return;
    tab.setLanguage(language);
    notifyListeners();
  }

  // ---- Editing actions ----------------------------------------------------

  void undo() {
    active?.undo();
  }

  void redo() {
    active?.redo();
  }

  void onTextChanged(String text) {
    final tab = active;
    if (tab == null) return;
    if (tab.text != text) {
      tab.text = text;
      // Forward the dirty-state change to the shell so the tab strip's dot
      // and the status bar's "未保存" chip update immediately.
      notifyListeners();
    }
  }

  void onSelectionChanged(TextSelection sel) {
    final tab = active;
    if (tab == null) return;
    tab.setSelection(sel.start, sel.end);
    _bus.emit(AppEvents.cursorMoved, {'start': sel.start, 'end': sel.end});
    notifyListeners();
  }

  Future<void> copy() async {
    final c = _live;
    if (c == null) return;
    final sel = c.selection;
    if (sel.isCollapsed) return;
    final s = sel.start < sel.end ? sel.start : sel.end;
    final e = sel.start < sel.end ? sel.end : sel.start;
    final text = c.text.substring(s.clamp(0, c.text.length), e.clamp(0, c.text.length));
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> cut() async {
    final c = _live;
    final tab = active;
    if (c == null || tab == null) return;
    final sel = c.selection;
    if (sel.isCollapsed) return;
    final s = sel.start < sel.end ? sel.start : sel.end;
    final e = sel.start < sel.end ? sel.end : sel.start;
    final full = c.text;
    final selected = full.substring(s.clamp(0, full.length), e.clamp(0, full.length));
    await Clipboard.setData(ClipboardData(text: selected));
    final newText = full.substring(0, s.clamp(0, full.length)) + full.substring(e.clamp(0, full.length));
    tab.text = newText;
    c.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: s.clamp(0, newText.length)),
    );
  }

  Future<void> paste() async {
    final c = _live;
    final tab = active;
    if (c == null || tab == null) return;
    final data = await Clipboard.getData('text/plain');
    final insert = data?.text ?? '';
    if (insert.isEmpty) return;
    final sel = c.selection;
    final s = sel.start < sel.end ? sel.start : sel.end;
    final e = sel.start < sel.end ? sel.end : sel.start;
    final full = c.text;
    final newText = full.substring(0, s.clamp(0, full.length)) +
        insert +
        full.substring(e.clamp(0, full.length));
    tab.text = newText;
    c.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: s + insert.length),
    );
  }

  void selectAll() {
    final c = _live;
    if (c == null) return;
    final len = c.text.length;
    c.selection = TextSelection(baseOffset: 0, extentOffset: len);
    onSelectionChanged(c.selection);
  }

  // ---- Format plugin ------------------------------------------------------

  void applyFormat() {
    final tab = active;
    if (tab == null) return;
    final formatter = _format.forLanguage(tab.language);
    if (formatter == null) {
      _bus.emit(AppEvents.formatApplied, {'error': '当前格式暂不支持格式化'});
      return;
    }
    final result = formatter.format(tab.text);
    if (result.ok) {
      tab.text = result.text;
      final ctrl = _live;
      if (ctrl != null) {
        ctrl.setTextSilently(result.text);
      }
      _bus.emit(AppEvents.formatApplied, {'language': tab.language});
    } else {
      _bus.emit(AppEvents.formatApplied, {'error': result.error});
    }
    notifyListeners();
  }

  /// Toggle the live preview pane for Markdown / Mermaid tabs.
  void togglePreview() {
    final tab = active;
    if (tab == null || !tab.supportsPreview) return;
    tab.setPreviewEnabled(!tab.previewEnabled);
    notifyListeners();
  }

  // ---- Voice plugin -------------------------------------------------------

  Future<void> speakSelected() async {
    final tab = active;
    if (tab == null) return;
    final text = tab.selectedText.isNotEmpty ? tab.selectedText : tab.text;
    await _voice.speak(_bus, text);
    notifyListeners();
  }

  /// Toolbar behaviour for the 语音播报 button: start speaking when idle,
  /// stop playback when a narration is already running. This is what
  /// makes the button a real toggle — previously the only way to stop was
  /// the 语音 menu, so playback felt impossible to cancel.
  Future<void> toggleVoice() async {
    if (_voice.isBusy) {
      await stopVoice();
    } else {
      await speakSelected();
    }
  }

  Future<void> speakAll() async {
    final tab = active;
    if (tab == null) return;
    await _voice.speak(_bus, tab.text);
    notifyListeners();
  }

  Future<void> pauseVoice() async {
    await _voice.pause(_bus);
    notifyListeners();
  }

  Future<void> resumeVoice() async {
    await _voice.resume(_bus);
    notifyListeners();
  }

  Future<void> stopVoice() async {
    await _voice.stop(_bus);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final t in _tabs) {
      t.dispose();
    }
    _lastClosed?.dispose();
    _plugins.disposeAll();
    super.dispose();
  }
}

/// Small extension letting the service set a tab's language after a
/// "save as" without exposing a public mutator on the kernel type.
extension _TabLanguageSetter on EditorTabController {
  void _setLanguage(String language) => setLanguage(language);
}
