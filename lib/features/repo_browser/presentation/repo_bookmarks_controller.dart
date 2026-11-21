import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repo_bookmarks_storage.dart';
import '../domain/repo_bookmarks.dart';

final repoBookmarksStoreProvider = Provider<RepoBookmarksStore>(
  (ref) => SecureRepoBookmarksStore(),
);

final repoBookmarksProvider =
    StateNotifierProvider<RepoBookmarksController, RepoBookmarksState>(
  (ref) => RepoBookmarksController(ref.watch(repoBookmarksStoreProvider)),
);

class RepoBookmarksController extends StateNotifier<RepoBookmarksState> {
  static const int maxRecents = 30;
  static const int maxFavorites = 100;

  final RepoBookmarksStore _store;

  RepoBookmarksController(this._store) : super(const RepoBookmarksState()) {
    _hydrate();
  }

  Future<void> _hydrate() async {
    final loaded = await _store.load();
    if (mounted) state = loaded;
  }

  Future<bool> toggleFavorite({
    required String repoFullName,
    required String branchName,
    required String path,
    required bool isFolder,
  }) async {
    final entry = RepoBookmarkEntry(
      repoFullName: repoFullName,
      branchName: branchName,
      path: path,
      isFolder: isFolder,
      savedAt: DateTime.now(),
    );
    final next = List<RepoBookmarkEntry>.from(state.favorites);
    final existingIdx = next.indexWhere((e) => e.key == entry.key);
    final bool added;
    if (existingIdx >= 0) {
      next.removeAt(existingIdx);
      added = false;
    } else {
      next.insert(0, entry);
      if (next.length > maxFavorites) {
        next.removeRange(maxFavorites, next.length);
      }
      added = true;
    }

    state = RepoBookmarksState(
      favorites: List.unmodifiable(next),
      recents: state.recents,
    );
    await _store.save(state);
    return added;
  }

  Future<void> recordRecentFile({
    required String repoFullName,
    required String branchName,
    required String path,
  }) async {
    final entry = RepoBookmarkEntry(
      repoFullName: repoFullName,
      branchName: branchName,
      path: path,
      isFolder: false,
      savedAt: DateTime.now(),
    );
    final next = List<RepoBookmarkEntry>.from(state.recents)
      ..removeWhere((e) => e.key == entry.key)
      ..insert(0, entry);
    if (next.length > maxRecents) {
      next.removeRange(maxRecents, next.length);
    }

    state = RepoBookmarksState(
      favorites: state.favorites,
      recents: List.unmodifiable(next),
    );
    await _store.save(state);
  }

  Future<void> clearRecents() async {
    state = RepoBookmarksState(
      favorites: state.favorites,
      recents: const [],
    );
    await _store.save(state);
  }
}
