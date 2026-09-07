import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'update_info.dart';

/// In-app auto-update service for the self-hosted + GitHub Releases model.
///
/// Flow:
///   1. Fetch `version.json` from [updateCheckUrl].
///   2. Compare `latestVersion` with the currently installed version.
///   3. If newer, expose the [UpdateInfo] so the UI can show a dialog.
///   4. On user confirmation, download the APK to the app cache and call
///      [installApk] which hands off to the system installer.
///
/// The check URL points at a static JSON file hosted on GitHub (raw
/// content). Replace [kUpdateCheckUrl] with your own repo's raw URL.
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  /// URL of the hosted `version.json`. For a GitHub repo this is the
  /// raw.githubusercontent.com address, e.g.:
  ///   https://raw.githubusercontent.com/<owner>/<repo>/main/version.json
  /// Using jsDelivr CDN gives better speed inside China:
  ///   https://cdn.jsdelivr.net/gh/<owner>/<repo>@main/version.json
  static const String kUpdateCheckUrl =
      'https://cdn.jsdelivr.net/gh/danqingpro/file-viewer@main/version.json';

  final http.Client _client;

  PackageInfo? _packageInfo;

  /// Cached current version info (versionName + buildNumber).
  Future<PackageInfo> get packageInfo async {
    _packageInfo ??= await PackageInfo.fromPlatform();
    return _packageInfo!;
  }

  /// Returns the currently installed version string (e.g. "1.6.1").
  Future<String> get currentVersion async => (await packageInfo).version;

  /// Check for an update. Returns the [UpdateInfo] if a newer version is
  /// available, otherwise `null`. Network/parse errors are swallowed so a
  /// failed check never disrupts the editor.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final resp = await _client
          .get(Uri.parse(kUpdateCheckUrl))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;

      final json = _parseJson(resp.body);
      if (json == null) return null;

      final info = UpdateInfo.fromJson(json);
      if (info.apkUrl.isEmpty) return null;

      final current = await currentVersion;
      if (!_isNewer(info.latestVersion, current)) return null;

      return info;
    } catch (_) {
      return null;
    }
  }

  /// Download the APK from [info.apkUrl] into the app's cache directory.
  /// Emits progress (0.0 .. 1.0) through [onProgress].
  /// Returns the local file path on success, or `null` on failure.
  Future<String?> downloadApk(
    UpdateInfo info, {
    required ValueChanged<double> onProgress,
  }) async {
    try {
      final request = http.Request('GET', Uri.parse(info.apkUrl));
      final response = await _client.send(request).timeout(
            const Duration(minutes: 5),
          );
      if (response.statusCode != 200) return null;

      final total = response.contentLength ?? 0;
      final dir = await getTemporaryDirectory();
      final fileName = 'update_${info.latestVersion}.apk';
      final file = File('${dir.path}/$fileName');

      int received = 0;
      final sink = file.openWrite();
      await response.stream.forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress(received / total);
        }
      });
      await sink.flush();
      await sink.close();

      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Open the downloaded APK so the system installer can overlay-install.
  /// Uses `open_filex` which handles FileProvider on Android 7+.
  Future<bool> installApk(String path) async {
    try {
      final result = await OpenFilex.open(
        path,
        type: 'application/vnd.android.package-archive',
      );
      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

  // ---- helpers -----------------------------------------------------------

  /// Minimal JSON parser for the version manifest.
  Map<String, dynamic>? _parseJson(String body) {
    try {
      return (jsonDecode(body) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// Compare two dotted version strings. Returns true if [a] is newer
  /// than [b]. Handles up to 4 numeric segments (e.g. "1.6.2" > "1.6.1").
  bool _isNewer(String a, String b) {
    final pa = _parseVersion(a);
    final pb = _parseVersion(b);
    for (int i = 0; i < pa.length || i < pb.length; i++) {
      final na = i < pa.length ? pa[i] : 0;
      final nb = i < pb.length ? pb[i] : 0;
      if (na != nb) return na > nb;
    }
    return false;
  }

  List<int> _parseVersion(String v) {
    return v
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
  }

  void dispose() => _client.close();
}
