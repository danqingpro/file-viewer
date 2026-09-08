import 'package:flutter/material.dart';

import 'background_update_service.dart';
import 'update_info.dart';
import 'update_service.dart';

/// Dialog that shows available update info, downloads the APK with a
/// progress bar, and triggers installation.
///
/// Usage:
/// ```dart
/// final info = await UpdateService().checkForUpdate();
/// if (info != null) {
///   UpdateDialog.show(context, info);
/// }
/// ```
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.info});

  final UpdateInfo info;

  static Future<void> show(BuildContext context, UpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (_) => UpdateDialog(info: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final UpdateService _service = UpdateService();
  bool _downloading = false;
  double _progress = 0.0;
  String? _error;

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _startUpdate() async {
    setState(() {
      _downloading = true;
      _progress = 0.0;
      _error = null;
    });

    final path = await _service.downloadApk(
      widget.info,
      onProgress: (p) => setState(() => _progress = p),
    );

    if (path == null) {
      setState(() {
        _downloading = false;
        _error = '下载失败，请检查网络后重试';
      });
      return;
    }

    final ok = await _service.installApk(path);
    if (!ok && mounted) {
      setState(() {
        _downloading = false;
        _error = '无法启动安装，请手动安装下载的 APK';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white60 : Colors.black54;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF2D2D30) : Colors.white,
      title: Row(
        children: [
          Icon(Icons.system_update, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Text('发现新版本 ${widget.info.latestVersion}',
              style: TextStyle(color: fg, fontSize: 18)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.info.changelog.isNotEmpty) ...[
            Text('更新内容：', style: TextStyle(color: sub, fontSize: 13)),
            const SizedBox(height: 6),
            Text(widget.info.changelog,
                style: TextStyle(color: fg, fontSize: 14, height: 1.5)),
            const SizedBox(height: 12),
          ],
          if (_downloading)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('正在下载：${(_progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: fg, fontSize: 13)),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _progress.clamp(0.0, 1.0)),
              ],
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
      ),
      actions: [
        if (!widget.info.forceUpdate && !_downloading)
          TextButton(
            onPressed: _onDefer,
            child: const Text('稍后'),
          ),
        if (_downloading)
          TextButton(
            onPressed: null,
            child: Text('下载中...', style: TextStyle(color: sub)),
          )
        else
          TextButton(
            onPressed: _startUpdate,
            child: const Text('立即更新'),
          ),
      ],
    );
  }

  /// Called when the user taps "稍后". Instead of just closing, ask
  /// whether the update should keep downloading in the background so the
  /// APK is ready when the user next opens the app.
  Future<void> _onDefer() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('后台下载更新'),
        content: Text(
            '是否在后台继续下载新版本 ${widget.info.latestVersion}？\n下载完成后可在应用内直接安装。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('否'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('后台下载'),
          ),
        ],
      ),
    );
    if (result == true) {
      BackgroundUpdateService.instance.start(widget.info);
    }
    if (mounted) Navigator.of(context).pop();
  }
}

/// Manually check for updates and show the appropriate dialog.
/// Shows an "already up to date" message if no update is available,
/// or the update dialog if a new version is found.
/// Should be called from a user-triggered action (e.g. menu item).
Future<void> manualCheckForUpdate(BuildContext context) async {
  // Show a loading indicator
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      content: const Row(
        children: [
          SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 16),
          Text('正在检查更新…'),
        ],
      ),
    ),
  );

  final service = UpdateService();
  UpdateInfo? info;
  bool networkError = false;
  try {
    info = await service.checkForUpdate();
  } catch (_) {
    networkError = true;
  }
  service.dispose();

  if (!context.mounted) return;
  Navigator.of(context).pop(); // Close loading dialog

  if (networkError) {
    _showMessageDialog(context, '检查失败',
        '无法连接到更新服务器，请检查网络后重试。');
  } else if (info != null) {
    UpdateDialog.show(context, info);
  } else {
    final current = await UpdateService().currentVersion;
    _showMessageDialog(context, '已是最新版本',
        '当前版本 $current 已是最新版本，无需更新。');
  }
}

void _showMessageDialog(BuildContext context, String title, String message) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
