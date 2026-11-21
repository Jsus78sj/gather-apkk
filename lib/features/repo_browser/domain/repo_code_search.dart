import 'repo_path_validator.dart';

class RepoCodeSearchHit {
  final String path;
  final String sha;
  final String htmlUrl;
  final List<String> snippets;

  const RepoCodeSearchHit({
    required this.path,
    required this.sha,
    required this.htmlUrl,
    required this.snippets,
  });

  String get name => RepoPathValidator.nameOf(path);
  String get parentPath => RepoPathValidator.parentOf(path);

  factory RepoCodeSearchHit.fromJson(Map<String, dynamic> json) {
    final matches = json['text_matches'];
    final snippets = <String>[];
    if (matches is List) {
      for (final item in matches) {
        if (item is Map && item['fragment'] is String) {
          final frag = (item['fragment'] as String).trim();
          if (frag.isNotEmpty) snippets.add(frag);
        }
      }
    }
    return RepoCodeSearchHit(
      path: (json['path'] as String?) ?? '',
      sha: (json['sha'] as String?) ?? '',
      htmlUrl: (json['html_url'] as String?) ?? '',
      snippets: List.unmodifiable(snippets),
    );
  }
}

class RepoCodeSearchResult {
  final int totalCount;
  final bool incompleteResults;
  final List<RepoCodeSearchHit> items;

  const RepoCodeSearchResult({
    required this.totalCount,
    required this.incompleteResults,
    required this.items,
  });

  static const empty = RepoCodeSearchResult(
    totalCount: 0,
    incompleteResults: false,
    items: [],
  );
}
