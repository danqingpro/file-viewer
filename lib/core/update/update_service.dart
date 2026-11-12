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

  /// GitHub repository slug, used to build canonical release URLs.
  static const String kRepoSlug = 'danqingpro/file-viewer';

  /// Authoritative manifest attached as an asset to every release. The
  /// `/releases/latest/download/...` alias always resolves to the newest
  /// release and is **not** cached for hours like jsDelivr's `@main`.
  static const String kReleasesLatestJsonUrl =
      'https://github.com/danqingpro/file-viewer/releases/latest/download/version.json';

  /// GitHub Releases API — returns the newest non-prerelease tag directly.
  static const String kReleasesApiUrl =
      'https://api.github.com/repos/danqingpro/file-viewer/releases/latest';

  /// jsDelivr package metadata — a live list of git tags. Unlike
  /// `@main/version.json`, this endpoint is not edge-cached for hours, so
  /// it still reports the newest tag when a POP serves a stale JSON file.
  static const String kTagListUrl =
      'https://data.jsdelivr.com/v1/package/gh/danqingpro/file-viewer';

  /// URLs of the hosted `version.json`, ordered by freshness + reachability
  /// in China. Every source is queried and the highest version wins.
  ///
  /// The jsDelivr mirrors are kept as fallbacks only: their `@main` cache
  /// can keep serving an older manifest for days, which made older builds
  /// report "已是最新版本" long after a release had shipped.
  static const List<String> kUpdateCheckUrls = [
    kReleasesLatestJsonUrl,
    'https://fastly.jsdelivr.net/gh/danqingpro/file-viewer@main/version.json',
    'https://gcore.jsdelivr.net/gh/danqingpro/file-viewer@main/version.json',
    'https://testingcf.jsdelivr.net/gh/danqingpro/file-viewer@main/version.json',
    'https://raw.githubusercontent.com/danqingpro/file-viewer/main/version.json',
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
        final uri = Uri.parse(url).replace(queryParameters: {
          '_': DateTime.now().millisecondsSinceEpoch.toString(),
        });
        final resp = await _client.get(
          uri,
          headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ).timeout(const Duration(seconds: 12));
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
      throw UpdateFetchException('无法连接到更新服务器（已尝试 $attempted 个镜像）');
    }

    // Authoritative sources that do not depend on the CDN-cached manifest.
    // They carry no changelog, but they tell us the true newest tag even
    // when every version.json mirror is stale.
    for (final fetch in <Future<UpdateInfo?> Function()>[
      _fetchFromReleasesApi,
      _fetchFromTagList,
    ]) {
      try {
        final info = await fetch();
        if (info == null) continue;
        succeeded++;
        if (best == null || _isNewer(info.latestVersion, best.latestVersion)) {
          best = info;
        }
      } catch (_) {
        // Optional source — ignore and keep whatever the mirrors gave us.
      }
    }

    if (best == null) return null;
    if (!_isNewer(best.latestVersion, current)) return null;
    return best;
  }

  /// Newest release tag + APK asset straight from the GitHub Releases API.
  /// Not CDN-cached, so it is immune to stale `version.json` mirrors.
  Future<UpdateInfo?> _fetchFromReleasesApi() async {
    final resp = await _client.get(
      Uri.parse(kReleasesApiUrl),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'file-viewer-updater',
        'Cache-Control': 'no-cache',
      },
    ).timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) return null;

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) return null;

    final tag = (decoded['tag_name'] as String? ?? '')
        .replaceFirst(RegExp(r'^[vV]'), '')
        .trim();
    if (tag.isEmpty) return null;

    var apkUrl = '';
    final assets = decoded['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = asset['name'] as String? ?? '';
        if (!name.endsWith('.apk')) continue;
        apkUrl = asset['browser_download_url'] as String? ?? '';
        if (apkUrl.isNotEmpty) break;
      }
    }

    return UpdateInfo(
      latestVersion: tag,
      apkUrl: apkUrl.isEmpty ? _defaultApkUrl(tag) : apkUrl,
      changelog: (decoded['body'] as String?) ?? '',
      forceUpdate: false,
    );
  }

  /// Newest tag from jsDelivr's package metadata. This endpoint reflects
  /// the git tags live instead of serving a cached file.
  Future<UpdateInfo?> _fetchFromTagList() async {
    final resp = await _client.get(
      Uri.parse(kTagListUrl),
      headers: const {'Cache-Control': 'no-cache'},
    ).timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) return null;

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) return null;

    final versions = decoded['versions'];
    if (versions is! List) return null;

    String? newest;
    for (final raw in versions) {
      if (raw is! String) continue;
      final tag = raw.replaceFirst(RegExp(r'^[vV]'), '').trim();
      // Only plain numeric versions — skip pre-releases / branches.
      if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(tag)) continue;
      if (newest == null || _isNewer(tag, newest)) newest = tag;
    }
    if (newest == null) return null;

    return UpdateInfo(
      latestVersion: newest,
      apkUrl: _defaultApkUrl(newest),
      changelog: '',
      forceUpdate: false,
    );
  }

  /// Canonical release asset URL for [version].
  String _defaultApkUrl(String version) =>
      'https://github.com/$kRepoSlug/releases/download/v$version/'
      'file-viewer-$version.apk';

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
      final bool resumed = response.statusCode == 206;
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
      final sink =
          file.openWrite(mode: resumed ? FileMode.append : FileMode.write);
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
    return v.split('.').map((s) => int.tryParse(s) ?? 0).toList();
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
