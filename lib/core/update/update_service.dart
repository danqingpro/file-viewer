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

  /// URLs of the hosted `version.json`, ordered by freshness + reachability
  /// in China (first-to-try).
  ///
  ///   1. fastly.jsdelivr.net — fast CDN mirror, low cache TTL, reachable in CN
  ///   2. raw.githubusercontent.com — direct GitHub raw (often blocked /
  ///      timing out in China, 15s timeout)
  ///   3. cdn.jsdelivr.net — legacy jsDelivr mirror, **long cache TTL** for
  ///      GitHub raw files; placed last as a true last resort
  static const List<String> kUpdateCheckUrls = [
    'https://fastly.jsdelivr.net/gh/danqingpro/file-viewer@main/version.json',
    'https://raw.githubusercontent.com/danqingpro/file-viewer/main/version.json',
    'https://cdn.jsdelivr.net/gh/danqingpro/file-viewer@main/version.json',
  ];

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
  /// available, `null` if no newer version exists (all reachable mirrors
  /// say current or older), and throws a [UpdateFetchException] if every
  /// configured mirror failed (network error / timeout / non-200).
  ///
  /// Unlike the previous "first-success wins" approach, this method tries
  /// **all** configured mirrors and picks the **highest** version returned.
  /// This defends against stale CDN caches (e.g. jsDelivr often serves
  /// version.json from days ago even though the main branch has moved
  /// forward — the old code would incorrectly conclude "already up to date"
  /// because the stale version is numerically less than the installed one).
  ///
  /// A second bug fixed here: if **all** mirrors are unreachable, the
  /// method used to silently return `null`, which the caller interpreted
  /// as "already up to date" — hiding genuine network failures. Now we
  /// throw [UpdateFetchException] so the UI can show a proper error.
  Future<UpdateInfo?> checkForUpdate() async {
    final current = await currentVersion;

    // Best (highest-version) result collected from any mirror so far.
    UpdateInfo? best;

    // Count how many mirrors we tried and how many succeeded. If zero
    // succeeded, throw — the caller must distinguish "no update" from
    // "can't reach server".
    int attempted = 0;
    int succeeded = 0;

    for (final url in kUpdateCheckUrls) {
      attempted++;
      try {
        final resp = await _client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 12));
        if (resp.statusCode != 200) continue;

        final json = _parseJson(resp.body);
        if (json == null) continue;

        final info = UpdateInfo.fromJson(json);
        if (info.apkUrl.isEmpty) continue;

        succeeded++;

        // Keep the highest-versioned result across mirrors.
        if (best == null || _isNewer(info.latestVersion, best.latestVersion)) {
          best = info;
        }
      } catch (_) {
        // Try next mirror — timeouts / network errors are expected in CN.
        continue;
      }
    }

    if (succeeded == 0) {
      // Every mirror failed — network outage or all mirrors unreachable.
      throw UpdateFetchException(
        '无法连接到更新服务器（已尝试 $attempted 个镜像）');
    }

    if (best == null) return null;
    if (!_isNewer(best.latestVersion, current)) return null;
    return best;
  }

  /// Download the APK from [info.apkUrl] into the app's cache directory.
  /// Emits progress (0.0 .. 1.0) through [onProgress].
  /// Returns the local file path on success, or `null` on failure.
  ///
  /// Supports **resume** (断点续传): if a partially-downloaded file from
  /// a previous attempt already exists in the cache, it sends an HTTP
  /// `Range` header to continue from the last received byte instead of
  /// starting over. If the server does not honour the Range header
  /// (returns 200 instead of 206), the partial file is discarded and a
  /// fresh full download starts.
  Future<String?> downloadApk(
    UpdateInfo info, {
    required ValueChanged<double> onProgress,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final fileName = 'update_${info.latestVersion}.apk';
      final file = File('${dir.path}/$fileName');

      // Existing partial download size — basis for the Range request.
      int start = file.existsSync() ? await file.length() : 0;

      final request = http.Request('GET', Uri.parse(info.apkUrl));
      if (start > 0) {
        request.headers['Range'] = 'bytes=$start-';
      }

      final response = await _client.send(request).timeout(
            const Duration(minutes: 10),
          );

      // Server honours Range: continues from `start`.
      // Server ignores Range (200): restart from scratch.
      final bool resumed =
          response.statusCode == 206;
      if (response.statusCode == 200) {
        // Server ignored the Range header — delete any partial file and
        // write from the beginning.
        if (await file.exists()) await file.delete();
        start = 0;
      } else if (response.statusCode != 206) {
        // Unexpected status (e.g. 416 Range Not Satisfiable if the file
        // is already the full size, or 404).
        return null;
      }

      // Total file size. For a 206 response the server returns
      // `Content-Range: bytes start-end/total`; for 200 it returns
      // `Content-Length`.
      int? expectedTotal;
      final contentRange = response.headers['content-range'];
      if (contentRange != null) {
        // e.g. "bytes 1024-2047/4096"
        final slash = contentRange.lastIndexOf('/');
        if (slash != -1 && slash < contentRange.length - 1) {
          final totalStr = contentRange.substring(slash + 1);
          expectedTotal = int.tryParse(totalStr);
        }
      }
      final total = expectedTotal ?? response.contentLength ?? 0;

      // Append mode for resumed downloads, write mode for fresh.
      final sink = file.openWrite(mode: resumed ? FileMode.append : FileMode.write);
      int received = start;
      if (total > 0) {
        onProgress(received / total);
      }

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

/// Thrown when [UpdateService.checkForUpdate] cannot reach any of the
/// configured version.json mirrors (network outage, DNS failure, timeout
/// on every URL). Distinct from `null` return (which means "all reachable
/// mirrors report no newer version").
class UpdateFetchException implements Exception {
  final String message;
  UpdateFetchException(this.message);
  @override
  String toString() => 'UpdateFetchException: $message';
}
