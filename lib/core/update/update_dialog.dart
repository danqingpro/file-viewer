import 'dart:io';

import 'package:flutter/material.dart';

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
            onPressed: () => Navigator.of(context).pop(),
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
}

/// Check for updates and show the dialog if one is available.
/// Called once at app startup. Failures are silent (no crash).
Future<void> checkAndShowUpdate(BuildContext context) async {
  try {
    // Skip on non-Android platforms (desktop doesn't use APK install).
    if (!Platform.isAndroid) return;

    final service = UpdateService();
    final info = await service.checkForUpdate();
    service.dispose();
    if (info != null) {
      // Use a microtask delay so the dialog isn't shown during the first
      // frame build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) UpdateDialog.show(context, info);
      });
    }
  } catch (_) {
    // Never let an update check break the app startup.
  }
}
