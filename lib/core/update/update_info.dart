/// Metadata of a remote app update, parsed from the hosted `version.json`.
///
/// The JSON schema (all keys lowercase, no ambiguity between client/server):
/// ```json
/// {
///   "latestVersion": "1.6.2",
///   "apkUrl": "https://example.com/app-1.6.2.apk",
///   "changelog": "修复 XX\\n新增 YY",
///   "forceUpdate": false
/// }
/// ```
class UpdateInfo {
  const UpdateInfo({
    required this.latestVersion,
    required this.apkUrl,
    required this.changelog,
    required this.forceUpdate,
  });

  /// Remote version string, e.g. "1.6.2".
  final String latestVersion;

  /// Direct download URL of the APK.
  final String apkUrl;

  /// Human-readable change log (may contain \n).
  final String changelog;

  /// When true, the update dialog cannot be dismissed.
  final bool forceUpdate;

  /// Parse a JSON map. Missing fields fall back to safe defaults so a
  /// partial payload never crashes the app.
  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      latestVersion: (json['latestVersion'] as String?) ?? '0.0.0',
      apkUrl: (json['apkUrl'] as String?) ?? '',
      changelog: (json['changelog'] as String?) ?? '',
      forceUpdate: (json['forceUpdate'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'latestVersion': latestVersion,
        'apkUrl': apkUrl,
        'changelog': changelog,
        'forceUpdate': forceUpdate,
      };
}
