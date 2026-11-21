/// Lightweight commit description used by file / repository history views.
class RepoCommitSummary {
  final String sha;
  final String message;
  final String authorName;
  final DateTime? authoredAt;
  final String htmlUrl;

  const RepoCommitSummary({
    required this.sha,
    required this.message,
    required this.authorName,
    required this.authoredAt,
    required this.htmlUrl,
  });

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;

  String get title {
    final newline = message.indexOf('\n');
    return (newline == -1 ? message : message.substring(0, newline)).trim();
  }

  factory RepoCommitSummary.fromJson(Map<String, dynamic> json) {
    final commitMap = json['commit'] is Map
        ? Map<String, dynamic>.from(json['commit'] as Map)
        : const <String, dynamic>{};
    final authorMap = commitMap['author'] is Map
        ? Map<String, dynamic>.from(commitMap['author'] as Map)
        : const <String, dynamic>{};
    final sha = (json['sha'] as String?) ?? '';

    return RepoCommitSummary(
      sha: sha,
      message: (commitMap['message'] as String?) ?? '',
      authorName: (authorMap['name'] as String?) ?? '',
      authoredAt: DateTime.tryParse((authorMap['date'] as String?) ?? ''),
      htmlUrl: (json['html_url'] as String?) ?? '',
    );
  }
}
