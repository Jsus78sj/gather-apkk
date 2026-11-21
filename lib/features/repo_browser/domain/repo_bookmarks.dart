/// عنصر مفضّل (ملف أو مجلد داخل مستودع وفرع محددين).
class RepoBookmarkEntry {
  final String repoFullName;
  final String branchName;
  final String path;
  final bool isFolder;
  final DateTime savedAt;

  const RepoBookmarkEntry({
    required this.repoFullName,
    required this.branchName,
    required this.path,
    required this.isFolder,
    required this.savedAt,
  });

  String get key => '$repoFullName::$branchName::$path';

  factory RepoBookmarkEntry.fromJson(Map<String, dynamic> json) {
    return RepoBookmarkEntry(
      repoFullName: (json['repoFullName'] as String?) ?? '',
      branchName: (json['branchName'] as String?) ?? '',
      path: (json['path'] as String?) ?? '',
      isFolder: (json['isFolder'] as bool?) ?? false,
      savedAt: DateTime.tryParse((json['savedAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'repoFullName': repoFullName,
        'branchName': branchName,
        'path': path,
        'isFolder': isFolder,
        'savedAt': savedAt.toIso8601String(),
      };
}

class RepoBookmarksState {
  final List<RepoBookmarkEntry> favorites;
  final List<RepoBookmarkEntry> recents;

  const RepoBookmarksState({
    this.favorites = const [],
    this.recents = const [],
  });

  bool isFavorite({
    required String repoFullName,
    required String branchName,
    required String path,
  }) {
    final targetKey = '$repoFullName::$branchName::$path';
    return favorites.any((e) => e.key == targetKey);
  }

  List<RepoBookmarkEntry> favoritesFor(String repoFullName, String branchName) =>
      favorites
          .where((e) =>
              e.repoFullName == repoFullName && e.branchName == branchName)
          .toList();

  List<RepoBookmarkEntry> recentsFor(String repoFullName, String branchName) =>
      recents
          .where((e) =>
              e.repoFullName == repoFullName && e.branchName == branchName)
          .toList();
}
