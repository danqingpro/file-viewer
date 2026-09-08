import 'package:flutter/foundation.dart';

import 'update_info.dart';
import 'update_service.dart';

/// State of a background update download.
enum BackgroundUpdateState { idle, downloading, ready, failed }

/// Singleton service that downloads an app update in the background after
/// the user dismisses the update dialog.
///
/// The app shell listens to this and shows a floating progress banner
/// while [state] is [BackgroundUpdateState.downloading], and a "安装更新"
/// action once [state] becomes [BackgroundUpdateState.ready].
///
/// Lifecycle:
///   1. [start] — kicks off a download (no-op if already downloading).
///   2. Listeners are notified on progress / state changes.
///   3. [install] — launches the system installer for the downloaded APK.
///   4. [dismiss] — clears the state (used after the user installs or
///      dismisses the banner).
class BackgroundUpdateService extends ChangeNotifier {
  BackgroundUpdateService._();
  static final BackgroundUpdateService instance = BackgroundUpdateService._();

  BackgroundUpdateState _state = BackgroundUpdateState.idle;
  double _progress = 0.0;
  String? _error;
  String? _apkPath;
  UpdateInfo? _info;
  UpdateService? _service;

  BackgroundUpdateState get state => _state;
  double get progress => _progress;
  String? get error => _error;
  String? get apkPath => _apkPath;
  UpdateInfo? get info => _info;

  /// Whether a background download is currently in flight.
  bool get isDownloading => _state == BackgroundUpdateState.downloading;

  /// Start downloading [info] in the background. Safe to call multiple
  /// times — a second call while downloading is ignored.
  void start(UpdateInfo info) {
    if (_state == BackgroundUpdateState.downloading) return;
    _service?.dispose();
    _service = UpdateService();
    _info = info;
    _state = BackgroundUpdateState.downloading;
    _progress = 0.0;
    _error = null;
    _apkPath = null;
    notifyListeners();
    _download(info);
  }

  Future<void> _download(UpdateInfo info) async {
    try {
      final path = await _service!.downloadApk(
        info,
        onProgress: (p) {
          _progress = p;
          notifyListeners();
        },
      );
      if (path == null) {
        _state = BackgroundUpdateState.failed;
        _error = '后台下载失败，请稍后重试';
      } else {
        _state = BackgroundUpdateState.ready;
        _apkPath = path;
      }
    } catch (e) {
      _state = BackgroundUpdateState.failed;
      _error = e.toString();
    }
    notifyListeners();
  }

  /// Launch the system installer for the downloaded APK. Returns false if
  /// the installer could not be started.
  Future<bool> install() async {
    final p = _apkPath;
    if (p == null) return false;
    final ok = await _service?.installApk(p) ?? false;
    return ok;
  }

  /// Clear all state. Called by the UI after the user dismisses the banner
  /// (after install, or after dismissing an error).
  void dismiss() {
    _state = BackgroundUpdateState.idle;
    _progress = 0.0;
    _error = null;
    _apkPath = null;
    _info = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _service?.dispose();
    super.dispose();
  }
}
