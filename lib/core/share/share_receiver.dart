import 'dart:async';

import 'package:flutter/services.dart';

/// Bridge to the Android `MainActivity`, which resolves incoming
/// `ACTION_VIEW` / `ACTION_SEND` / `ACTION_SEND_MULTIPLE` intents into
/// file paths and forwards them here.
///
/// Two channels are used:
///   * [methodChannel] `getPendingPaths` — returns paths received before
///     Flutter subscribed (cold-start case).
///   * [eventChannel] — pushes paths for subsequent shares while the app
///     is already running (onNewIntent).
///
/// The Dart side only deals with absolute file paths; content:// URIs are
/// already copied into the cache directory on the native side, so the
/// paths are readable through dart:io.
class ShareReceiver {
  ShareReceiver._();
  static final ShareReceiver instance = ShareReceiver._();

  static const String _methodChannel = 'app.share/openPath';
  static const String _eventChannel = 'app.share/pathStream';

  final MethodChannel _method = const MethodChannel(_methodChannel);
  final EventChannel _event = const EventChannel(_eventChannel);

  final StreamController<List<String>> _pathsController =
      StreamController<List<String>>.broadcast();

  /// Stream of shared-file path batches. Each event is a list of paths
  /// (length ≥ 1) that should be opened by the app.
  Stream<List<String>> get paths => _pathsController.stream;

  /// Must be called once at app startup to hook up the channels and pull
  /// any paths that arrived before the engine was ready.
  Future<void> init() async {
    _event.receiveBroadcastStream().listen((data) {
      if (data is List) {
        final paths = data.whereType<String>().toList();
        if (paths.isNotEmpty) _pathsController.add(paths);
      }
    });

    try {
      final pending =
          await _method.invokeMethod<List>('getPendingPaths') ?? const [];
      final paths = pending.whereType<String>().toList();
      if (paths.isNotEmpty) _pathsController.add(paths);
    } catch (_) {
      // Channel not implemented on non-Android platforms — ignore.
    }
  }
}
