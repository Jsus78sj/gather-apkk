import '../../../core/network/github_api_client.dart' show RemoteTreeBlob;
import 'repo_path_validator.dart';

/// One result of a local file-name search.
class RepoSearchHit {
  final String path;
  final bool isFolder;
  final int size;
  final String mode;
  final String sha;

  const RepoSearchHit({
    required this.path,
    required this.isFolder,
    this.size = 0,
    this.mode = '100644',
    this.sha = '',
  });

  String get name => RepoPathValidator.nameOf(path);
  String get parentPath => RepoPathValidator.parentOf(path);
}

class RepoSearchResult {
  final List<RepoSearchHit> hits;

  /// Number of matches before the display [limit] was applied.
  final int total;

  const RepoSearchResult({required this.hits, required this.total});

  static const empty = RepoSearchResult(hits: [], total: 0);
}

/// In-memory index of every file and folder path of a snapshot, searched
/// locally by name (no extra API requests).
class RepoSearchIndex {
  final List<_Entry> _entries;

  RepoSearchIndex._(this._entries);

  int get length => _entries.length;

  factory RepoSearchIndex.fromBlobs(List<RemoteTreeBlob> blobs) {
    final entries = <_Entry>[];
    final folders = <String>{};

    for (final blob in blobs) {
      entries.add(
        _Entry(
          RepoSearchHit(
            path: blob.path,
            isFolder: false,
            size: blob.size,
            mode: blob.mode,
            sha: blob.sha,
          ),
        ),
      );
      // Register every ancestor folder so folders can be found by name too.
      var parent = RepoPathValidator.parentOf(blob.path);
      while (parent.isNotEmpty && folders.add(parent)) {
        entries.add(_Entry(RepoSearchHit(path: parent, isFolder: true)));
        parent = RepoPathValidator.parentOf(parent);
      }
    }
    return RepoSearchIndex._(entries);
  }

  /// Case-insensitive search. Every whitespace-separated word of [query] must
  /// appear in the path. Matches in the file name rank before matches that
  /// are only in the folder part; shorter paths come first.
  RepoSearchResult search(String query, {int limit = 200}) {
    final words = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return RepoSearchResult.empty;

    final scored = <({_Entry entry, int rank})>[];
    for (final entry in _entries) {
      if (!words.every(entry.lowerPath.contains)) continue;

      final inName = words.every(entry.lowerName.contains);
      final startsWithName = inName && entry.lowerName.startsWith(words.first);
      final rank = startsWithName ? 0 : (inName ? 1 : 2);
      scored.add((entry: entry, rank: rank));
    }

    scored.sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      if (byRank != 0) return byRank;
      final byLength =
          a.entry.hit.path.length.compareTo(b.entry.hit.path.length);
      if (byLength != 0) return byLength;
      return a.entry.hit.path.compareTo(b.entry.hit.path);
    });

    return RepoSearchResult(
      hits: [for (final item in scored.take(limit)) item.entry.hit],
      total: scored.length,
    );
  }
}

class _Entry {
  final RepoSearchHit hit;
  final String lowerPath;
  final String lowerName;

  _Entry(this.hit)
      : lowerPath = hit.path.toLowerCase(),
        lowerName = hit.name.toLowerCase();
}
