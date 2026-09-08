/// GitHub configuration for the in-app feedback feature.
///
/// The token is used to create issues and upload attachments to the
/// repository. For a personal / side-loaded app this is acceptable, but
/// do NOT use a token with broader scope than `repo`.
///
/// ⚠️ The token is deliberately left as an empty string in the source
/// tree — populate it locally via a build-time injection or before each
/// release. Never commit a real PAT.
class GithubConfig {
  /// Fine-grained personal access token with `Contents` (read/write) and
  /// `Issues` (read/write) permissions on the target repository.
  ///
  /// Replace with a real token in your local build before releasing.
  static const String token = '';

  /// Owner of the repository that receives feedback issues.
  static const String owner = 'danqingpro';

  /// Repository name.
  static const String repo = 'file-viewer';

  /// Label applied to every feedback issue, so they're easy to filter.
  static const String feedbackLabel = 'feedback';

  /// Base URL of the GitHub REST API.
  static const String apiBase = 'https://api.github.com';
}
