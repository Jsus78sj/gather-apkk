import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/network/github_api_client.dart';
import '../../../core/network/github_exceptions.dart';
import '../domain/remote_tree_entry.dart';
import '../domain/repo_path_validator.dart';

/// Reads a repository snapshot (identified by its root tree SHA) one folder
/// at a time. Listings are cached per tree SHA, so browsing back and forth and
/// resolving several paths in one batch costs a single request per folder.
///
/// Because it never needs the recursive tree, it also works for very large
/// repositories where `fetchRecursiveTree` reports `truncated`.
class RepoContentService {
  final GitHubApiClient api;
  final String token;
  final String owner;
  final String repo;
  final String rootTreeSha;

  final Map<String, List<RemoteTreeEntry>> _treeCache = {};

  RepoContentService({
    required this.api,
    required this.token,
    required this.owner,
    required this.repo,
    required this.rootTreeSha,
  });

  Future<List<RemoteTreeEntry>> _listTree(
    String treeSha, {
    CancelToken? cancelToken,
  }) async {
    final cached = _treeCache[treeSha];
    if (cached != null) return cached;

    final result = await api.fetchTreeShallow(
      token: token,
      owner: owner,
      repo: repo,
      treeSha: treeSha,
      cancelToken: cancelToken,
    );
    if (result.truncated) {
      // Never act on a partial folder listing (it could hide files from a
      // folder delete / rename).
      throw const InvalidRepoOperationException(
        'المجلد يحتوي عدداً ضخماً من العناصر ولا يمكن تحميله بالكامل.',
      );
    }
    _treeCache[treeSha] = result.entries;
    return result.entries;
  }

  /// Tree SHA of [folderPath] (`''` is the root), or `null` if it does not
  /// exist or one of its segments is a file.
  Future<String?> folderTreeSha(
    String folderPath, {
    CancelToken? cancelToken,
  }) async {
    var sha = rootTreeSha;
    if (folderPath.isEmpty) return sha;

    for (final segment in folderPath.split('/')) {
      final entries = await _listTree(sha, cancelToken: cancelToken);
      RemoteTreeEntry? next;
      for (final entry in entries) {
        if (entry.isFolder && entry.name == segment) {
          next = entry;
          break;
        }
      }
      if (next == null) return null;
      sha = next.sha;
    }
    return sha;
  }

  Future<bool> folderExists(
    String folderPath, {
    CancelToken? cancelToken,
  }) async =>
      (await folderTreeSha(folderPath, cancelToken: cancelToken)) != null;

  /// Direct children of [folderPath], folders first then files, each group
  /// sorted case-insensitively.
  Future<List<RemoteTreeEntry>> listFolder(
    String folderPath, {
    CancelToken? cancelToken,
  }) async {
    final sha = await folderTreeSha(folderPath, cancelToken: cancelToken);
    if (sha == null) {
      throw GitHubApiException(
        'المجلد غير موجود: $folderPath',
        statusCode: 404,
      );
    }
    final entries = List<RemoteTreeEntry>.of(
      await _listTree(sha, cancelToken: cancelToken),
    );
    entries.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  /// The file (blob) at [path], or `null` when absent or not a regular file.
  Future<RemoteTreeBlob?> findFile(
    String path, {
    CancelToken? cancelToken,
  }) async {
    final parentSha = await folderTreeSha(
      RepoPathValidator.parentOf(path),
      cancelToken: cancelToken,
    );
    if (parentSha == null) return null;

    final name = RepoPathValidator.nameOf(path);
    for (final entry in await _listTree(parentSha, cancelToken: cancelToken)) {
      if (entry.isFile && entry.name == name) {
        return RemoteTreeBlob(
          path: path,
          sha: entry.sha,
          mode: entry.mode,
          size: entry.size,
        );
      }
    }
    return null;
  }

  /// Every file under [folderPath], recursively, with full paths.
  Future<List<RemoteTreeBlob>> blobsUnder(
    String folderPath, {
    CancelToken? cancelToken,
  }) async {
    final rootSha = await folderTreeSha(folderPath, cancelToken: cancelToken);
    if (rootSha == null) return const [];

    final result = <RemoteTreeBlob>[];

    Future<void> walk(String treeSha, String prefix) async {
      final entries = await _listTree(treeSha, cancelToken: cancelToken);
      for (final entry in entries) {
        final fullPath = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';
        if (entry.isFolder) {
          await walk(entry.sha, fullPath);
        } else if (entry.isFile) {
          result.add(
            RemoteTreeBlob(
              path: fullPath,
              sha: entry.sha,
              mode: entry.mode,
              size: entry.size,
            ),
          );
        }
      }
    }

    await walk(rootSha, folderPath);
    return result;
  }

  Future<Uint8List> readBlob(
    String blobSha, {
    CancelToken? cancelToken,
  }) =>
      api.fetchFileBlob(
        token: token,
        owner: owner,
        repo: repo,
        blobSha: blobSha,
        cancelToken: cancelToken,
      );

  /// Bytes of the file at [path], or `null` if it does not exist.
  Future<Uint8List?> readFile(
    String path, {
    CancelToken? cancelToken,
  }) async {
    final file = await findFile(path, cancelToken: cancelToken);
    if (file == null) return null;
    return readBlob(file.sha, cancelToken: cancelToken);
  }
}
