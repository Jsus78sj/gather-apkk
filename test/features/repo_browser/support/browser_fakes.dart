import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:github_nexus/core/network/github_api_client.dart';
import 'package:github_nexus/core/network/github_exceptions.dart';
import 'package:github_nexus/features/repo_browser/domain/remote_tree_entry.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_code_search.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_commit_summary.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_pull_request.dart';
import 'package:github_nexus/features/repos/domain/deploy_target.dart';
import 'package:github_nexus/features/repos/domain/github_branch.dart';
import 'package:github_nexus/features/repos/domain/github_repo.dart';

const kBrowserHeadCommit = 'head_commit';
const kBrowserRootTree = 'tree_root';

List<RemoteTreeBlob> defaultBrowserFiles() => const [
      RemoteTreeBlob(
        path: 'README.md',
        sha: 'sha_readme',
        mode: '100644',
        size: 21,
      ),
      RemoteTreeBlob(
        path: 'lib/main.dart',
        sha: 'sha_main',
        mode: '100644',
        size: 20,
      ),
      RemoteTreeBlob(
        path: 'lib/utils/a.dart',
        sha: 'sha_a',
        mode: '100644',
        size: 5,
      ),
      RemoteTreeBlob(
        path: 'lib/utils/b.dart',
        sha: 'sha_b',
        mode: '100644',
        size: 6,
      ),
      RemoteTreeBlob(
        path: 'scripts/run.sh',
        sha: 'sha_run',
        mode: '100755',
        size: 7,
      ),
      RemoteTreeBlob(
        path: 'docs/دليل المستخدم.md',
        sha: 'sha_guide',
        mode: '100644',
        size: 8,
      ),
      RemoteTreeBlob(
        path: 'app.zip',
        sha: 'sha_zip',
        mode: '100644',
        size: 2048,
      ),
    ];

DeployTarget browserTarget({String branch = 'main', bool canPush = true}) =>
    DeployTarget(
      repo: GitHubRepo(
        id: 10,
        name: 'nexus-demo',
        fullName: 'abdullah/nexus-demo',
        ownerLogin: 'abdullah',
        description: '',
        isPrivate: true,
        defaultBranch: 'main',
        stargazersCount: 0,
        language: 'Dart',
        sizeKb: 100,
        updatedAt: null,
        htmlUrl: 'https://github.com/abdullah/nexus-demo',
        canPush: canPush,
      ),
      branchName: branch,
      isEmptyRepo: false,
    );

/// In-memory GitHub API for the browser (reads AND atomic writes).
///
/// Folders get the synthetic tree SHA `tree:<path>`; any other SHA is the
/// repository root. Writes behave like Git: `createTree` applies its entries
/// (a `null` blob SHA deletes) on top of the base tree, `createCommit` points
/// at a tree, and `updateBranchRef` moves the head, so the listing really
/// changes after a commit and really comes back after an undo. Nothing here
/// uses timers unless [shallowDelays] is set, so widget tests can rely on
/// `pumpAndSettle`.
class BrowserFakeApi extends GitHubApiClient {
  BranchHeadRef? head;
  List<RemoteTreeBlob> files;
  bool truncated;

  /// The branch the [head] / [files] pair belongs to (the browsed one).
  String currentBranch;

  /// Thrown by [fetchBranchHead] while set.
  Object? headError;

  /// Thrown by [fetchRecursiveTree] while set.
  Object? recursiveError;

  /// Artificial latency per tree SHA (real timers: unit tests only).
  final Map<String, Duration> shallowDelays = {};

  /// Thrown by [updateBranchRef] while set (e.g. a 422 or a 403).
  Object? updateRefError;

  /// Branches whose ref update is rejected as "protected" (a realistic
  /// per-branch variant of [updateRefError] for the pull-request fallback).
  final Set<String> protectedBranches = {};

  /// Thrown by [createBlob] while set.
  Object? blobError;

  // --- phase 10: history, branches, pull requests, code search -------------

  /// Pre-seeded commit history returned by [fetchCommits].
  List<RepoCommitSummary> commits;
  Object? commitsError;
  int commitsCalls = 0;

  Object? createBranchError;
  Object? createPullRequestError;

  /// Branches created through [createBranch]: name -> head (commit + tree).
  final Map<String, BranchHeadRef> extraBranches = {};

  int createBranchCalls = 0;
  int deleteBranchCalls = 0;
  int createPullRequestCalls = 0;
  int searchCalls = 0;

  RepoCodeSearchResult searchResult;
  Object? searchError;
  String? lastPullRequestHead;
  String? lastPullRequestBase;
  String? lastPullRequestTitle;

  int headCalls = 0;
  int shallowCalls = 0;
  int recursiveCalls = 0;
  int createBlobCalls = 0;
  int createTreeCalls = 0;
  int createCommitCalls = 0;
  int updateRefCalls = 0;
  final List<String> blobReads = [];

  /// Entries of every `createTree` call, in order.
  final List<List<GitTreeItemInput>> treeCalls = [];

  /// Messages of every `createCommit` call, in order.
  final List<String> commitMessages = [];

  /// File lists of every tree the fake knows about, by tree SHA.
  final Map<String, List<RemoteTreeBlob>> _snapshots = {};
  final Map<String, String> _commitTrees = {};

  BrowserFakeApi({
    List<RemoteTreeBlob>? files,
    this.truncated = false,
    this.currentBranch = 'main',
    this.commits = const [],
    RepoCodeSearchResult? searchResult,
    this.head = const BranchHeadRef(
      commitSha: kBrowserHeadCommit,
      treeSha: kBrowserRootTree,
    ),
  })  : files = files ?? defaultBrowserFiles(),
        searchResult = searchResult ?? RepoCodeSearchResult.empty;

  /// Registers an artificial commit (history restore tests), so
  /// `fetchCommitTreeSha` resolves and the tree reads exactly [treeFiles].
  void seedCommit(String commitSha, String treeSha, List<RemoteTreeBlob> treeFiles) {
    _commitTrees[commitSha] = treeSha;
    _snapshots[treeSha] = List.of(treeFiles);
  }

  @override
  Future<BranchHeadRef?> fetchBranchHead({
    required String token,
    required String owner,
    required String repo,
    required String branchName,
    CancelToken? cancelToken,
  }) async {
    headCalls++;
    final error = headError;
    if (error != null) throw error;
    if (branchName != currentBranch) return extraBranches[branchName];
    return head;
  }

  @override
  Future<List<RepoCommitSummary>> fetchCommits({
    required String token,
    required String owner,
    required String repo,
    required String branchName,
    String? path,
    int perPage = 30,
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    commitsCalls++;
    final error = commitsError;
    if (error != null) throw error;
    return List.of(commits);
  }

  @override
  Future<String> fetchCommitTreeSha({
    required String token,
    required String owner,
    required String repo,
    required String commitSha,
    CancelToken? cancelToken,
  }) async {
    final treeSha = _commitTrees[commitSha];
    if (treeSha == null) {
      throw GitHubApiException('Commit غير معروف: $commitSha', statusCode: 404);
    }
    return treeSha;
  }

  @override
  Future<GitHubBranch> createBranch({
    required String token,
    required String owner,
    required String repo,
    required String newBranchName,
    required String baseBranchName,
  }) async {
    createBranchCalls++;
    final error = createBranchError;
    if (error != null) throw error;
    final base = baseBranchName == currentBranch
        ? head
        : extraBranches[baseBranchName];
    if (base == null) throw StateError('unknown base branch $baseBranchName');
    final created = BranchHeadRef(commitSha: base.commitSha, treeSha: base.treeSha);
    extraBranches[newBranchName] = created;
    return GitHubBranch(
      name: newBranchName,
      commitSha: base.commitSha,
      isProtected: false,
    );
  }

  @override
  Future<CreatedPullRequestResult> createPullRequest({
    required String token,
    required String owner,
    required String repo,
    required String title,
    required String headBranch,
    required String baseBranch,
    String body = '',
    CancelToken? cancelToken,
  }) async {
    createPullRequestCalls++;
    final error = createPullRequestError;
    if (error != null) throw error;
    lastPullRequestHead = headBranch;
    lastPullRequestBase = baseBranch;
    lastPullRequestTitle = title;
    return CreatedPullRequestResult(
      number: createPullRequestCalls,
      title: title,
      htmlUrl: 'https://github.com/$owner/$repo/pull/$createPullRequestCalls',
      headBranch: headBranch,
      baseBranch: baseBranch,
    );
  }

  @override
  Future<void> deleteBranchRef({
    required String token,
    required String owner,
    required String repo,
    required String branchName,
    CancelToken? cancelToken,
  }) async {
    deleteBranchCalls++;
    extraBranches.remove(branchName);
  }

  @override
  Future<RepoCodeSearchResult> searchCode({
    required String token,
    required String owner,
    required String repo,
    required String query,
    int perPage = 30,
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    searchCalls++;
    final error = searchError;
    if (error != null) throw error;
    return searchResult;
  }

  @override
  Future<RemoteTreeSnapshot> fetchRecursiveTree({
    required String token,
    required String owner,
    required String repo,
    required String treeSha,
    CancelToken? cancelToken,
  }) async {
    recursiveCalls++;
    final error = recursiveError;
    if (error != null) throw error;
    return RemoteTreeSnapshot(
      // A truncated snapshot is deliberately incomplete.
      blobs: truncated ? files.take(1).toList() : files,
      truncated: truncated,
    );
  }

  @override
  Future<ShallowTreeResult> fetchTreeShallow({
    required String token,
    required String owner,
    required String repo,
    required String treeSha,
    CancelToken? cancelToken,
  }) async {
    shallowCalls++;
    final delay = shallowDelays[treeSha];
    if (delay != null) await Future<void>.delayed(delay);

    // Resolve the blob list this tree SHA refers to:
    // - a seeded / committed full tree reads its own snapshot;
    // - `tree:<rootSha>::<path>` reads inside a seeded snapshot (history);
    // - `tree:<path>` / any other SHA reads the live files (browsing).
    List<RemoteTreeBlob> source;
    var dir = '';
    var snapshotBacked = false;
    final seededRoot = _snapshots[treeSha];
    if (seededRoot != null) {
      source = seededRoot;
      snapshotBacked = true;
    } else if (treeSha.contains('::')) {
      final sep = treeSha.indexOf('::');
      final seeded = _snapshots[treeSha.substring(0, sep)];
      if (seeded != null) {
        source = seeded;
        dir = treeSha.substring(sep + 2);
        snapshotBacked = true;
      } else {
        source = files;
        dir = treeSha.substring(5);
      }
    } else {
      source = files;
      if (treeSha.startsWith('tree:')) dir = treeSha.substring(5);
    }

    final prefix = dir.isEmpty ? '' : '$dir/';
    final entries = <String, RemoteTreeEntry>{};
    for (final f in source) {
      if (!f.path.startsWith(prefix)) continue;
      final rest = f.path.substring(prefix.length);
      final slash = rest.indexOf('/');
      if (slash == -1) {
        entries[rest] = RemoteTreeEntry(
          name: rest,
          sha: f.sha,
          mode: f.mode,
          type: 'blob',
          size: f.size,
        );
      } else {
        final folder = rest.substring(0, slash);
        entries.putIfAbsent(
          folder,
          () {
            // Snapshot-backed listings must stay inside their snapshot, so
            // their folder SHAs carry the root tree SHA.
            final String sha;
            if (snapshotBacked) {
              final root = treeSha.contains('::')
                  ? treeSha.substring(0, treeSha.indexOf('::'))
                  : treeSha;
              final path = dir.isEmpty ? folder : '$dir/$folder';
              sha = '$root::$path';
            } else {
              sha = 'tree:$prefix$folder';
            }
            return RemoteTreeEntry(
              name: folder,
              sha: sha,
              mode: '040000',
              type: 'tree',
            );
          },
        );
      }
    }
    return ShallowTreeResult(
      entries: entries.values.toList(),
      truncated: false,
    );
  }

  @override
  Future<Uint8List> fetchFileBlob({
    required String token,
    required String owner,
    required String repo,
    required String blobSha,
    CancelToken? cancelToken,
  }) async {
    blobReads.add(blobSha);
    return Uint8List.fromList(utf8.encode('content of $blobSha'));
  }
  // --- writes -------------------------------------------------------------

  @override
  Future<String> createBlob({
    required String token,
    required String owner,
    required String repo,
    required Uint8List bytes,
    CancelToken? cancelToken,
  }) async {
    createBlobCalls++;
    final error = blobError;
    if (error != null) throw error;
    return 'new_blob_$createBlobCalls';
  }

  @override
  Future<String> createTree({
    required String token,
    required String owner,
    required String repo,
    required List<GitTreeItemInput> entries,
    String? baseTreeSha,
    CancelToken? cancelToken,
  }) async {
    createTreeCalls++;
    treeCalls.add(entries);

    // Remember the tree the head points at, so an undo can come back to it.
    final base = baseTreeSha ?? head?.treeSha ?? kBrowserRootTree;
    final baseFiles = _snapshots.putIfAbsent(base, () => List.of(files));

    final byPath = {for (final f in baseFiles) f.path: f};
    for (final entry in entries) {
      final sha = entry.blobSha;
      if (sha == null) {
        byPath.remove(entry.path);
      } else {
        byPath[entry.path] = RemoteTreeBlob(
          path: entry.path,
          sha: sha,
          mode: entry.mode,
          size: 0,
        );
      }
    }
    final newSha = 'tree_new_$createTreeCalls';
    _snapshots[newSha] = byPath.values.toList();
    return newSha;
  }

  @override
  Future<CreatedCommitResult> createCommit({
    required String token,
    required String owner,
    required String repo,
    required String message,
    required String treeSha,
    required List<String> parentShas,
    CancelToken? cancelToken,
  }) async {
    createCommitCalls++;
    commitMessages.add(message);
    final sha = 'commit_new_$createCommitCalls';
    _commitTrees[sha] = treeSha;
    return CreatedCommitResult(
      sha: sha,
      htmlUrl: 'https://github.com/$owner/$repo/commit/$sha',
      message: message,
    );
  }

  @override
  Future<void> updateBranchRef({
    required String token,
    required String owner,
    required String repo,
    required String branchName,
    required String commitSha,
    bool force = false,
    CancelToken? cancelToken,
  }) async {
    updateRefCalls++;
    if (protectedBranches.contains(branchName)) {
      throw GitHubApiException(
        'cannot push to protected branch $branchName',
        statusCode: 403,
      );
    }
    final error = updateRefError;
    if (error != null) throw error;

    final tree = _commitTrees[commitSha];
    if (tree == null) throw StateError('unknown commit $commitSha');
    if (branchName != currentBranch) {
      // A pull-request fallback branch: its head moves, the browsed one stays.
      extraBranches[branchName] =
          BranchHeadRef(commitSha: commitSha, treeSha: tree);
      return;
    }
    head = BranchHeadRef(commitSha: commitSha, treeSha: tree);
    files = List.of(_snapshots[tree] ?? files);
  }
}
