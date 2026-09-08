import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_info.dart';
import '../config/github_config.dart';

/// Result of a feedback submission.
class FeedbackResult {
  final bool success;
  final String? issueUrl;
  final String? error;
  const FeedbackResult({required this.success, this.issueUrl, this.error});
}

/// An attachment picked by the user for the feedback.
class FeedbackAttachment {
  final String name;
  final String path;
  final int size;
  const FeedbackAttachment({required this.name, required this.path, required this.size});
}

/// Submits user feedback to GitHub:
///   1. Uploads each attachment to the repo's `feedback/` folder via the
///      Contents API (base64-encoded).
///   2. Creates an issue with the user's text and links to the attachments.
class FeedbackService {
  FeedbackService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Submit a piece of feedback. [description] is the user's text;
  /// [attachments] are the chosen files (images / videos / archives).
  Future<FeedbackResult> submit({
    required String description,
    List<FeedbackAttachment> attachments = const [],
  }) async {
    if (description.trim().isEmpty && attachments.isEmpty) {
      return const FeedbackResult(success: false, error: '请填写反馈内容或添加附件');
    }

    try {
      final pkg = await PackageInfo.fromPlatform();
      final timestamp = DateTime.now().toIso8601String();
      final tsForPath = timestamp.replaceAll(RegExp(r'[:.]'), '-');

      // 1. Upload attachments and collect their download URLs.
      final attachmentUrls = <String>[];
      for (final att in attachments) {
        final url = await _uploadAttachment(att, tsForPath);
        if (url != null) attachmentUrls.add('[$att.name]($url)');
      }

      // 2. Build the issue body.
      final body = StringBuffer()
        ..writeln('**反馈内容**')
        ..writeln()
        ..writeln(description.trim().isEmpty ? '(无文字描述)' : description.trim())
        ..writeln()
        ..writeln('---')
        ..writeln('**环境信息**')
        ..writeln('- 应用版本: ${AppInfo.versionNumber} (build ${pkg.buildNumber})')
        ..writeln('- 平台: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
        ..writeln('- 提交时间: $timestamp');

      if (attachmentUrls.isNotEmpty) {
        body
          ..writeln()
          ..writeln('**附件**')
          ..writeln(attachmentUrls.join('\n'));
      }

      // 3. Create the issue.
      final issueUrl = await _createIssue(
        title: _issueTitle(description, attachments),
        body: body.toString(),
      );

      return FeedbackResult(success: true, issueUrl: issueUrl);
    } catch (e) {
      return FeedbackResult(success: false, error: '提交失败：$e');
    }
  }

  /// Upload a single attachment to `feedback/<timestamp>/<name>` and return
  /// its raw download URL, or `null` on failure.
  Future<String?> _uploadAttachment(FeedbackAttachment att, String tsForPath) async {
    final bytes = await File(att.path).readAsBytes();
    final encoded = base64Encode(bytes);
    final safeName = att.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path = 'feedback/$tsForPath/$safeName';

    final resp = await _client.put(
      Uri.parse('${GithubConfig.apiBase}/repos/${GithubConfig.owner}/${GithubConfig.repo}/contents/$path'),
      headers: {
        'Authorization': 'Bearer ${GithubConfig.token}',
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'message': 'feedback attachment: $safeName',
        'content': encoded,
      }),
    );

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final content = data['content'] as Map<String, dynamic>?;
      return content?['download_url'] as String?;
    }
    return null;
  }

  /// Create a GitHub issue and return its HTML URL.
  Future<String> _createIssue({required String title, required String body}) async {
    final resp = await _client.post(
      Uri.parse('${GithubConfig.apiBase}/repos/${GithubConfig.owner}/${GithubConfig.repo}/issues'),
      headers: {
        'Authorization': 'Bearer ${GithubConfig.token}',
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'title': title,
        'body': body,
        'labels': [GithubConfig.feedbackLabel],
      }),
    );

    if (resp.statusCode != 201) {
      throw Exception('GitHub API ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['html_url'] as String;
  }

  String _issueTitle(String description, List<FeedbackAttachment> attachments) {
    final text = description.trim();
    final firstLine = text.isEmpty ? '(无标题)' : text.split('\n').first;
    final preview = firstLine.length > 50 ? '${firstLine.substring(0, 50)}…' : firstLine;
    return '[反馈] $preview';
  }

  void dispose() => _client.close();
}
