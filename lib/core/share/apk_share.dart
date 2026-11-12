import 'package:flutter/services.dart';

/// Shares the currently installed APK through the Android system share sheet.
class ApkShare {
  const ApkShare._();

  static const MethodChannel _channel = MethodChannel('app.share/openPath');

  /// Returns whether the share sheet was opened successfully.
  static Future<bool> shareCurrentApk() async {
    try {
      return await _channel.invokeMethod<bool>('shareCurrentApk') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
