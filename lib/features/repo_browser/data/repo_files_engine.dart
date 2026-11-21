import 'dart:math' as math;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/network/github_api_client.dart';
import '../../../core/network/github_exceptions.dart';
import '../../repos/domain/deploy_target.dart';
import '../domain/file_op.dart';
import '../domain/repo_change_plan.dart';
import '../domain/repo_path_validator.dart';
import 'repo_content_service.dart';

typedef RepoUploadProgressCallback = void Function(int uploaded, int total);

/// Applies a batch of [FileOp]s to a branch as ONE atomic Git commit:
///
/// 1. Reads the branch head and resolves every op against the remote tree
///    (ops are applied in order, so "create then rename" etc. work).
/// 2. Uploads only new / edited content as blobs (renames reuse blob SHAs).
/// 3. Builds the tree on top of the head tree (`base_tree`); deletions are
///    entries with `sha: null`, folder deletes are expanded to their files.
/// 4. Creates a single commit and moves the branch ref WITHOUT `force`,
///    so a concurrent push is never overwritten.
class RepoFilesEngine {
  static const int _treeChunkSize = 1000;

  final GitHubApiClient api;

  RepoFilesEngine({required this.api});

  /// Resolves [ops] without writing anything, for the confirmation modal.
  Future<RepoChangePlan> previewChanges({
    required String token,
    required DeployTarget target,
    required List<FileOp> ops,
    String? expectedHeadSha,
    CancelToken? cancelToken,
  }) async {
    final resolved = await _resolve(
      token: token,
      target: target,
      ops: ops,
      expectedHeadSha: expectedHeadSha,
      cancelToken: cancelToken,
    );
    return resolved.plan;
  }

  /// Commits [ops] atomically.
  ///
  /// Pass [expectedHeadSha] (the branch head the user was looking at) to get a
  /// [BranchChangedException] instead of silently committing on top of newer
  /// remote changes.
  Future<RepoCommitResult> applyChanges({
    required String token,
    required DeployTarget target,
    required List<FileOp> ops,
    required String message,
    String? expectedHeadSha,
    int uploadConcurrency = 4,
    RepoUploadProgressCallback? onUploadProgress,
    CancelToken? cancelToken,
  }) async {
    final commitMessage = message.trim();
    if (commitMessage.isEmpty) {
      throw const InvalidRepoOperationException('رسالة الـ Commit مطلوبة.');
    }

    final owner = target.repo.ownerLogin;
    final repo = target.repo.name;

    final resolved = await _resolve(
      token: token,
      target: target,
      ops: ops,
      expectedHeadSha: expectedHeadSha,
      cancelToken: cancelToken,
    );
    final overlay = resolved.tree.overlay;
    final paths = overlay.keys.toList()..sort();

    try {
      // --- Upload new / edited content (bounded parallelism) ----------------
      final uploadPaths = [
        for (final path in paths)
          if (overlay[path]?.bytes != null) path,
      ];
      final shaByPath = <String, String>{};
      final concurrency = math.max(1, uploadConcurrency);

      for (var i = 0; i < uploadPaths.length; i += concurrency) {
        _throwIfCancelled(cancelToken);
        final end = math.min(i + concurrency, uploadPaths.length);
        await Future.wait([
          for (final path in uploadPaths.sublist(i, end))
            () async {
              shaByPath[path] = await api.createBlob(
                token: token,
                owner: owner,
                repo: repo,
                bytes: overlay[path]!.bytes!,
                cancelToken: cancelToken,
              );
            }(),
        ]);
        onUploadProgress?.call(end, uploadPaths.length);
      }

      // --- Tree entries ------------------------------------------------------
      final entries = <GitTreeItemInput>[];
      for (final path in paths) {
        final pending = overlay[path];
        if (pending == null) {
          entries.add(GitTreeItemInput.delete(path: path));
          continue;
        }
        final sha = pending.bytes != null ? shaByPath[path] : pending.existingSha;
        if (sha == null || sha.isEmpty) {
          throw GitHubApiException('تعذر تحديد SHA للملف: $path');
        }
        entries.add(GitTreeItemInput(path: path, blobSha: sha, mode: pending.mode));
      }

      // Each createTree returns a full tree, so large batches are chained.
      var treeSha = resolved.head.treeSha;
      for (var i = 0; i < entries.length; i += _treeChunkSize) {
        _throwIfCancelled(cancelToken);
        treeSha = await api.createTree(
          token: token,
          owner: owner,
          repo: repo,
          entries: entries.sublist(
            i,
            math.min(i + _treeChunkSize, entries.length),
          ),
          baseTreeSha: treeSha,
          cancelToken: cancelToken,
        );
      }

      _throwIfCancelled(cancelToken);
      final commit = await api.createCommit(
        token: token,
        owner: owner,
        repo: repo,
        message: commitMessage,
        treeSha: treeSha,
        parentShas: [resolved.head.commitSha],
        cancelToken: cancelToken,
      );

      try {
        await api.updateBranchRef(
          token: token,
          owner: owner,
          repo: repo,
          branchName: target.branchName,
          commitSha: commit.sha,
          force: false,
          cancelToken: cancelToken,
        );
      } on GitHubApiException catch (e) {
        // 422 = not a fast-forward: someone pushed while we were working.
        // A 422 caused by branch protection is NOT that: it is mapped below.
        if (e.statusCode == 422 && !_isProtectedBranchError(e)) {
          throw const BranchChangedException();
        }
        rethrow;
      }

      return RepoCommitResult(
        commit: commit,
        previousCommitSha: resolved.head.commitSha,
        previousTreeSha: resolved.head.treeSha,
        newTreeSha: treeSha,
        plan: resolved.plan,
        uploadedBlobShas: Map<String, String>.unmodifiable(shaByPath),
      );
    } on GitHubApiException catch (e) {
      throw _mapWriteError(e, target.branchName);
    }
  }

  /// Reverts [result] by committing the tree that existed before it on top of
  /// the current head. Only allowed while [result]'s commit is still the head,
  /// so nobody else's later work is ever discarded.
  Future<CreatedCommitResult> undoCommit({
    required String token,
    required DeployTarget target,
    required RepoCommitResult result,
    String? message,
    CancelToken? cancelToken,
  }) async {
    _assertWritable(target);
    final owner = target.repo.ownerLogin;
    final repo = target.repo.name;

    final head = await api.fetchBranchHead(
      token: token,
      owner: owner,
      repo: repo,
      branchName: target.branchName,
      cancelToken: cancelToken,
    );
    if (head == null || head.commitSha != result.commit.sha) {
      throw const BranchChangedException(
        'لا يمكن التراجع لأن الفرع تغيّر بعد هذا الـ Commit.',
      );
    }

    final title = result.commit.message.split('\n').first.trim();
    final revertMessage = (message != null && message.trim().isNotEmpty)
        ? message.trim()
        : 'Revert "$title"';

    try {
      final revert = await api.createCommit(
        token: token,
        owner: owner,
        repo: repo,
        message: revertMessage,
        treeSha: result.previousTreeSha,
        parentShas: [head.commitSha],
        cancelToken: cancelToken,
      );
      try {
        await api.updateBranchRef(
          token: token,
          owner: owner,
          repo: repo,
          branchName: target.branchName,
          commitSha: revert.sha,
          force: false,
          cancelToken: cancelToken,
        );
      } on GitHubApiException catch (e) {
        if (e.statusCode == 422 && !_isProtectedBranchError(e)) {
          throw const BranchChangedException();
        }
        rethrow;
      }
      return revert;
    } on GitHubApiException catch (e) {
      throw _mapWriteError(e, target.branchName);
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _assertWritable(DeployTarget target) {
    if (!target.repo.canPush) {
      throw const InsufficientScopeException(
        grantedScopes: [],
        message: 'لا تملك صلاحية الكتابة في هذا المستودع.',
      );
    }
    if (target.isEmptyRepo) {
      throw const InvalidRepoOperationException(
        'المستودع فارغ. ابدأ برفع ملف أو تهيئته بـ README قبل التعديل.',
      );
    }
  }

  /// GitHub reports branch protection through the message text only (the
  /// status is 422 or 403 depending on the rule), so it is matched by phrase.
  static const List<String> _protectionPhrases = [
    'protected branch',
    'protected ref',
    'pull request',
    'status check',
    'approving review',
    'review is required',
    'rule violation',
    'repository rule',
    'verified signature',
  ];

  static bool _isProtectedBranchError(GitHubApiException e) {
    final status = e.statusCode;
    if (status != 403 && status != 409 && status != 422) return false;
    final message = e.message.toLowerCase();
    return _protectionPhrases.any(message.contains);
  }

  GitHubException _mapWriteError(GitHubApiException e, String branchName) {
    if (_isProtectedBranchError(e)) return ProtectedBranchException(branchName);
    if (e.statusCode == 403) {
      return const InsufficientScopeException(
        grantedScopes: [],
        message: 'رفض GitHub الكتابة. تأكد أن التوكن يملك صلاحية '
            'Contents: Read and write (أو repo) وأن الفرع ليس محمياً.',
      );
    }
    return e;
  }

  Future<_Resolved> _resolve({
    required String token,
    required DeployTarget target,
    required List<FileOp> ops,
    String? expectedHeadSha,
    CancelToken? cancelToken,
  }) async {
    if (ops.isEmpty) {
      throw const InvalidRepoOperationException('لا توجد عمليات لتنفيذها.');
    }
    _assertWritable(target);

    final owner = target.repo.ownerLogin;
    final repo = target.repo.name;

    final head = await api.fetchBranchHead(
      token: token,
      owner: owner,
      repo: repo,
      branchName: target.branchName,
      cancelToken: cancelToken,
    );
    if (head == null) {
      throw GitHubApiException(
        'الفرع "${target.branchName}" غير موجود أو المستودع فارغ.',
        statusCode: 404,
      );
    }
    if (expectedHeadSha != null && expectedHeadSha != head.commitSha) {
      throw const BranchChangedException();
    }

    final snapshot = await api.fetchRecursiveTree(
      token: token,
      owner: owner,
      repo: repo,
      treeSha: head.treeSha,
      cancelToken: cancelToken,
    );

    // A truncated recursive tree is incomplete: resolve paths folder by folder.
    final _RemoteIndex index = snapshot.truncated
        ? _ShallowIndex(
            RepoContentService(
              api: api,
              token: token,
              owner: owner,
              repo: repo,
              rootTreeSha: head.treeSha,
            ),
            cancelToken,
          )
        : _SnapshotIndex(snapshot);

    final tree = _WorkingTree(index);
    for (final op in ops) {
      _throwIfCancelled(cancelToken);
      await tree.apply(op);
    }
    await tree.normalize();

    if (tree.overlay.isEmpty) {
      throw const InvalidRepoOperationException(
        'العمليات المطلوبة لا تُحدث أي تغيير في الملفات.',
      );
    }

    return _Resolved(head: head, tree: tree, plan: await tree.buildPlan());
  }
}

void _throwIfCancelled(CancelToken? token) {
  if (token != null && token.isCancelled) {
    throw DioException.requestCancelled(
      requestOptions: RequestOptions(path: ''),
      reason: 'تم إلغاء العملية',
    );
  }
}

class _Resolved {
  final BranchHeadRef head;
  final _WorkingTree tree;
  final RepoChangePlan plan;

  const _Resolved({
    required this.head,
    required this.tree,
    required this.plan,
  });
}

/// A file as it will exist after the batch.
class _Pending {
  /// Blob SHA of an existing remote object that is reused as-is (renames and
  /// untouched files). `null` when [bytes] holds new content.
  final String? existingSha;

  /// New content to upload as a blob.
  final Uint8List? bytes;
  final String mode;

  /// Original remote path when this file was produced by a rename / move.
  final String? movedFrom;

  const _Pending({
    this.existingSha,
    this.bytes,
    required this.mode,
    this.movedFrom,
  });
}

abstract class _RemoteIndex {
  Future<RemoteTreeBlob?> file(String path);
  Future<List<RemoteTreeBlob>> under(String folderPath);
  Future<bool> folderExists(String folderPath);
}

class _SnapshotIndex implements _RemoteIndex {
  final Map<String, RemoteTreeBlob> _byPath;

  _SnapshotIndex(RemoteTreeSnapshot snapshot)
      : _byPath = {for (final blob in snapshot.blobs) blob.path: blob};

  @override
  Future<RemoteTreeBlob?> file(String path) async => _byPath[path];

  @override
  Future<List<RemoteTreeBlob>> under(String folderPath) async {
    final prefix = '$folderPath/';
    return _byPath.values.where((b) => b.path.startsWith(prefix)).toList();
  }

  @override
  Future<bool> folderExists(String folderPath) async {
    final prefix = '$folderPath/';
    return _byPath.keys.any((path) => path.startsWith(prefix));
  }
}

class _ShallowIndex implements _RemoteIndex {
  final RepoContentService _service;
  final CancelToken? _cancelToken;

  _ShallowIndex(this._service, this._cancelToken);

  @override
  Future<RemoteTreeBlob?> file(String path) =>
      _service.findFile(path, cancelToken: _cancelToken);

  @override
  Future<List<RemoteTreeBlob>> under(String folderPath) =>
      _service.blobsUnder(folderPath, cancelToken: _cancelToken);

  @override
  Future<bool> folderExists(String folderPath) =>
      _service.folderExists(folderPath, cancelToken: _cancelToken);
}

/// Remote snapshot + the staged changes on top of it.
///
/// [overlay] maps a path to its new state: a [_Pending] (file will exist with
/// that content) or `null` (a remote file that will be deleted).
class _WorkingTree {
  final _RemoteIndex remote;
  final Map<String, _Pending?> overlay = {};

  _WorkingTree(this.remote);

  Future<void> apply(FileOp op) async {
    switch (op) {
      case final CreateFileOp o:
        await _create(o);
      case final UpdateFileOp o:
        await _update(o);
      case final DeleteOp o:
        await _delete(o);
      case final RenameOp o:
        await _rename(o);
    }
  }

  void _checkPath(String path) {
    final error = RepoPathValidator.validate(path);
    if (error != null) {
      throw InvalidRepoOperationException('$error ($path)');
    }
  }

  /// Current state of the file at [path] (staged changes included).
  Future<_Pending?> _file(String path) async {
    if (overlay.containsKey(path)) return overlay[path];
    final blob = await remote.file(path);
    if (blob == null) return null;
    return _Pending(existingSha: blob.sha, mode: blob.mode);
  }

  /// Every file path under [folder] after staged changes.
  Future<List<String>> _pathsUnder(String folder) async {
    final prefix = '$folder/';
    final paths = <String>{
      for (final blob in await remote.under(folder)) blob.path,
    };
    overlay.forEach((path, pending) {
      if (!path.startsWith(prefix)) return;
      if (pending == null) {
        paths.remove(path);
      } else {
        paths.add(path);
      }
    });
    return paths.toList()..sort();
  }

  Future<bool> _folderExists(String folder) async {
    final prefix = '$folder/';
    for (final entry in overlay.entries) {
      if (entry.value != null && entry.key.startsWith(prefix)) return true;
    }
    if (!await remote.folderExists(folder)) return false;
    return (await _pathsUnder(folder)).isNotEmpty;
  }

  /// A new file / folder may be written at [path] only if nothing occupies it
  /// and no parent segment is a file.
  Future<void> _assertCanWrite(String path) async {
    if ((await _file(path)) != null) {
      throw InvalidRepoOperationException('يوجد ملف بنفس المسار: $path');
    }
    if (await _folderExists(path)) {
      throw InvalidRepoOperationException('يوجد مجلد بنفس الاسم: $path');
    }
    final segments = path.split('/');
    for (var i = 1; i < segments.length; i++) {
      final ancestor = segments.sublist(0, i).join('/');
      if ((await _file(ancestor)) != null) {
        throw InvalidRepoOperationException(
          'المسار "$ancestor" ملف وليس مجلداً، لا يمكن الكتابة داخله.',
        );
      }
    }
  }

  Future<void> _removeFile(String path) async {
    if ((await remote.file(path)) != null) {
      overlay[path] = null;
    } else {
      overlay.remove(path);
    }
  }

  Future<void> _moveFile(String from, String to, _Pending source) async {
    final existsRemotely = (await remote.file(from)) != null;
    final moved = _Pending(
      existingSha: source.existingSha,
      bytes: source.bytes,
      mode: source.mode,
      movedFrom: source.movedFrom ?? (existsRemotely ? from : null),
    );
    await _removeFile(from);
    overlay[to] = moved;
  }

  Future<void> _create(CreateFileOp op) async {
    _checkPath(op.path);
    if (op.mode != '100644' && op.mode != '100755') {
      throw InvalidRepoOperationException('نمط ملف غير مدعوم: ${op.mode}');
    }
    await _assertCanWrite(op.path);
    overlay[op.path] = _Pending(bytes: op.bytes, mode: op.mode);
  }

  Future<void> _update(UpdateFileOp op) async {
    _checkPath(op.path);
    final existing = await _file(op.path);
    if (existing == null) {
      throw InvalidRepoOperationException(
        'لا يمكن تعديل ملف غير موجود: ${op.path}',
      );
    }
    if (existing.mode == '120000') {
      throw InvalidRepoOperationException(
        'لا يمكن تعديل رابط رمزي (symlink) من التطبيق: ${op.path}',
      );
    }
    overlay[op.path] = _Pending(
      bytes: op.bytes,
      mode: existing.mode,
      movedFrom: existing.movedFrom,
    );
  }

  Future<void> _delete(DeleteOp op) async {
    _checkPath(op.path);
    if ((await _file(op.path)) != null) {
      await _removeFile(op.path);
      return;
    }
    final children = await _pathsUnder(op.path);
    if (children.isEmpty) {
      throw InvalidRepoOperationException('العنصر غير موجود: ${op.path}');
    }
    for (final child in children) {
      await _removeFile(child);
    }
  }

  Future<void> _rename(RenameOp op) async {
    _checkPath(op.fromPath);
    _checkPath(op.toPath);
    if (op.fromPath == op.toPath) {
      throw const InvalidRepoOperationException(
        'المسار الجديد مطابق للمسار الحالي.',
      );
    }
    if (RepoPathValidator.isInside(op.fromPath, op.toPath)) {
      throw const InvalidRepoOperationException(
        'لا يمكن نقل مجلد إلى داخل نفسه.',
      );
    }

    final file = await _file(op.fromPath);
    if (file != null) {
      await _assertCanWrite(op.toPath);
      await _moveFile(op.fromPath, op.toPath, file);
      return;
    }

    final children = await _pathsUnder(op.fromPath);
    if (children.isEmpty) {
      throw InvalidRepoOperationException('العنصر غير موجود: ${op.fromPath}');
    }
    await _assertCanWrite(op.toPath);
    for (final child in children) {
      final source = await _file(child);
      if (source == null) continue;
      final destination = '${op.toPath}${child.substring(op.fromPath.length)}';
      await _moveFile(child, destination, source);
    }
  }

  /// Drops staged entries that end up identical to the remote file
  /// (e.g. a rename that was moved back).
  Future<void> normalize() async {
    for (final path in overlay.keys.toList()) {
      final pending = overlay[path];
      if (pending == null || pending.bytes != null) continue;
      final blob = await remote.file(path);
      if (blob != null &&
          blob.sha == pending.existingSha &&
          blob.mode == pending.mode) {
        overlay.remove(path);
      }
    }
  }

  Future<RepoChangePlan> buildPlan() async {
    final added = <String>[];
    final modified = <String>[];
    final deleted = <String>[];
    final renamed = <({String from, String to})>[];
    final renamedSources = <String>{};
    var uploads = 0;

    final paths = overlay.keys.toList()..sort();
    for (final path in paths) {
      final pending = overlay[path];
      if (pending == null) continue;
      if (pending.bytes != null) uploads++;

      final from = pending.movedFrom;
      if (from != null) {
        renamed.add((from: from, to: path));
        renamedSources.add(from);
        continue;
      }
      if ((await remote.file(path)) != null) {
        modified.add(path);
      } else {
        added.add(path);
      }
    }
    for (final path in paths) {
      if (overlay[path] == null && !renamedSources.contains(path)) {
        deleted.add(path);
      }
    }

    return RepoChangePlan(
      addedPaths: added,
      modifiedPaths: modified,
      deletedPaths: deleted,
      renamedPaths: renamed,
      uploadCount: uploads,
    );
  }
}
