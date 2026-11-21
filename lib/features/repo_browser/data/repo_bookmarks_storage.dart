import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/repo_bookmarks.dart';

/// واجهة تخزين بسيطة (تُحقن في الاختبارات بنسخة داخل الذاكرة).
abstract class RepoBookmarksStore {
  Future<RepoBookmarksState> load();
  Future<void> save(RepoBookmarksState state);
}

/// يحفظ المفضلة والملفات الحديثة محلياً عبر FlutterSecureStorage المتوفر في المشروع.
class SecureRepoBookmarksStore implements RepoBookmarksStore {
  static const String _storageKey = 'github_nexus_repo_bookmarks_v1';

  final FlutterSecureStorage _storage;

  SecureRepoBookmarksStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  @override
  Future<RepoBookmarksState> load() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null || raw.isEmpty) return const RepoBookmarksState();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const RepoBookmarksState();

      final favs = <RepoBookmarkEntry>[];
      final rawFavs = decoded['favorites'];
      if (rawFavs is List) {
        for (final item in rawFavs) {
          if (item is Map) {
            favs.add(
              RepoBookmarkEntry.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }
      }

      final recents = <RepoBookmarkEntry>[];
      final rawRecents = decoded['recents'];
      if (rawRecents is List) {
        for (final item in rawRecents) {
          if (item is Map) {
            recents.add(
              RepoBookmarkEntry.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }
      }

      return RepoBookmarksState(
        favorites: List.unmodifiable(favs),
        recents: List.unmodifiable(recents),
      );
    } catch (_) {
      return const RepoBookmarksState();
    }
  }

  @override
  Future<void> save(RepoBookmarksState state) async {
    final payload = jsonEncode({
      'favorites': state.favorites.map((e) => e.toJson()).toList(),
      'recents': state.recents.map((e) => e.toJson()).toList(),
    });
    try {
      await _storage.write(key: _storageKey, value: payload);
    } catch (_) {
      // Favorites are a convenience: losing them must never crash a feature.
    }
  }
}
