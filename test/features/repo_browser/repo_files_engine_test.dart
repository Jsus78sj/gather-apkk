import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/core/network/github_api_client.dart';
import 'package:github_nexus/core/network/github_exceptions.dart';
import 'package:github_nexus/features/repo_browser/data/repo_content_service.dart';
import 'package:github_nexus/features/repo_browser/data/repo_files_engine.dart';
import 'package:github_nexus/features/repo_browser/domain/file_op.dart';
import 'package:github_nexus/features/repo_browser/domain/remote_tree_entry.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_change_plan.dart';
import 'package:github_nexus/features/repos/domain/deploy_target.dart';
import 'package:github_nexus/features/repos/domain/github_repo.dart';

const _kHeadCommit = 'head_commit';
const _kRootTree = 'tree_root';

List<RemoteTreeBlob> _defaultFiles() => const [
      RemoteTreeBlob(path: 'README.md', sha: 'sha_readme', mode: '100644', size: 10),
      RemoteTreeBlob(path: 'lib/main.dart', sha: 'sha_main', mode: '100644', size: 20),
      RemoteTreeBlob(path: 'lib/utils/a.dart', sha: 'sha_a', mode: '100644', size: 5),
      RemoteTreeBlob(path: 'lib/utils/b.dart', sha: 'sha_b', mode: '100644', size: 6),
      RemoteTreeBlob(path: 'scripts/run.sh', sha: 'sha_run', mode: '100755', size: 7),
      RemoteTreeBlob(path: 'docs/دليل المستخدم.md', sha: 'sha_guide', mode: '100644', size: 8),
    ];

class _FakeApi extends GitHubApiClient {
  BranchHeadRef? head = const BranchHeadRef(
    commitSha: _kHeadCommit,
    treeSha: _kRootTree,
  );
  List<RemoteTreeBlob> files;
  bool truncated = false;

  Object? blobError;
  Object? updateRefError;

  int headCalls = 0;
  int shallowCalls = 0;
  int createBlobCalls = 0;
  int createTreeCalls = 0;
  int createCommitCalls = 0;
  int updateRefCalls = 0;

  final List<Uint8List> uploaded = [];
  final List<List<GitTreeItemInput>> treeCalls = [];
  final List<String?> treeBases = [];
  String? lastCommitTree;
  List<String>? lastCommitParents;
  String? lastCommitMessage;

  _FakeApi({List<RemoteTreeBlob>? files}) : files = files ?? _defaultFiles();

  @override
  Future<BranchHeadRef?> fetchBranchHead({
    required String token,
    required String owner,
    required String repo,
    required String branchName,
    CancelToken? cancelToken,
  }) async {
    headCalls++;
    return head;
  }

  @override
  Future<RemoteTreeSnapshot> fetchRecursiveTree({
    required String token,
    required String owner,
    required String repo,
    required String treeSha,
    CancelToken? cancelToken,
  }) async =>
      RemoteTreeSnapshot(
        // A truncated snapshot is deliberately incomplete.
        blobs: truncated ? files.take(1).toList() : files,
        truncated: truncated,
      );

  @override
  Future<ShallowTreeResult> fetchTreeShallow({
    required String token,
    required String owner,
    required String repo,
    required String treeSha,
    CancelToken? cancelToken,
  }) async {
    shallowCalls++;
    final dir = treeSha.startsWith('tree:') ? treeSha.substring(5) : '';
    final prefix = dir.isEmpty ? '' : '$dir/';
    final entries = <String, RemoteTreeEntry>{};
    for (final f in files) {
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
          () => RemoteTreeEntry(
            name: folder,
            sha: 'tree:$prefix$folder',
            mode: '040000',
            type: 'tree',
          ),
        );
      }
    }
    return ShallowTreeResult(entries: entries.values.toList(), truncated: false);
  }

  @override
  Future<Uint8List> fetchFileBlob({
    required String token,
    required String owner,
    required String repo,
    required String blobSha,
    CancelToken? cancelToken,
  }) async =>
      Uint8List.fromList(utf8.encode('content of $blobSha'));

  @override
  Future<String> createBlob({
    required String token,
    required String owner,
    required String repo,
    required Uint8List bytes,
    CancelToken? cancelToken,
  }) async {
    createBlobCalls++;
    if (blobError != null) throw blobError!;
    uploaded.add(bytes);
    return 'new_blob_${uploaded.length}';
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
    treeBases.add(baseTreeSha);
    treeCalls.add(entries);
    return 'tree_new_$createTreeCalls';
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
    lastCommitTree = treeSha;
    lastCommitParents = parentShas;
    lastCommitMessage = message;
    final sha = 'commit_new_$createCommitCalls';
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
    if (updateRefError != null) throw updateRefError!;
    head = BranchHeadRef(commitSha: commitSha, treeSha: 'tree_after_$commitSha');
  }
}

DeployTarget _makeTarget({bool canPush = true, bool isEmpty = false}) {
  return DeployTarget(
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
    branchName: 'main',
    isEmptyRepo: isEmpty,
    headCommitSha: _kHeadCommit,
  );
}

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

Map<String, GitTreeItemInput> _byPath(List<GitTreeItemInput> entries) =>
    {for (final e in entries) e.path: e};

void main() {
  late _FakeApi api;
  late RepoFilesEngine engine;

  setUp(() {
    api = _FakeApi();
    engine = RepoFilesEngine(api: api);
  });

  Future<RepoCommitResult> apply(
    List<FileOp> ops, {
    String? expectedHeadSha,
    String message = 'test commit',
    DeployTarget? target,
  }) =>
      engine.applyChanges(
        token: 'token',
        target: target ?? _makeTarget(),
        ops: ops,
        message: message,
        expectedHeadSha: expectedHeadSha,
      );

  group('GitTreeItemInput', () {
    test('delete entry serialises sha as null', () {
      final json = const GitTreeItemInput.delete(path: 'a/b.txt').toJson();
      expect(json.containsKey('sha'), isTrue);
      expect(json['sha'], isNull);
      expect(json['path'], 'a/b.txt');
      expect(json['type'], 'blob');
    });

    test('regular entry keeps sha and mode', () {
      final json = const GitTreeItemInput(
        path: 'run.sh',
        blobSha: 'abc',
        mode: '100755',
      ).toJson();
      expect(json['sha'], 'abc');
      expect(json['mode'], '100755');
    });
  });

  group('RepoFilesEngine - single atomic commit', () {
    test('delete folder + delete file + edit file => one tree, one commit', () async {
      final result = await apply([
        const DeleteOp('lib/utils'),
        const DeleteOp('README.md'),
        UpdateFileOp(path: 'lib/main.dart', bytes: _bytes('void main() {}')),
      ]);

      expect(api.createTreeCalls, 1);
      expect(api.createCommitCalls, 1);
      expect(api.updateRefCalls, 1);
      expect(api.createBlobCalls, 1, reason: 'only the edited file is uploaded');
      expect(api.treeBases.single, _kRootTree);
      expect(api.lastCommitParents, [_kHeadCommit]);

      final entries = _byPath(api.treeCalls.single);
      expect(entries.keys.toSet(), {
        'README.md',
        'lib/main.dart',
        'lib/utils/a.dart',
        'lib/utils/b.dart',
      });
      expect(entries['README.md']!.isDelete, isTrue);
      expect(entries['lib/utils/a.dart']!.isDelete, isTrue);
      expect(entries['lib/utils/b.dart']!.isDelete, isTrue);
      expect(entries['lib/main.dart']!.blobSha, 'new_blob_1');

      expect(result.previousCommitSha, _kHeadCommit);
      expect(result.previousTreeSha, _kRootTree);
      expect(result.plan.deletedPaths, [
        'README.md',
        'lib/utils/a.dart',
        'lib/utils/b.dart',
      ]);
      expect(result.plan.modifiedPaths, ['lib/main.dart']);
      expect(api.head!.commitSha, result.commit.sha);
    });

    test('rename file reuses blob sha and keeps executable mode', () async {
      final result = await apply([
        const RenameOp(fromPath: 'scripts/run.sh', toPath: 'bin/run.sh'),
      ]);

      expect(api.createBlobCalls, 0);
      final entries = _byPath(api.treeCalls.single);
      expect(entries['scripts/run.sh']!.isDelete, isTrue);
      expect(entries['bin/run.sh']!.blobSha, 'sha_run');
      expect(entries['bin/run.sh']!.mode, '100755');
      expect(result.plan.renamedPaths, [
        (from: 'scripts/run.sh', to: 'bin/run.sh'),
      ]);
      expect(result.plan.deletedPaths, isEmpty);
      expect(result.plan.addedPaths, isEmpty);
    });

    test('rename folder moves every file without uploads', () async {
      final result = await apply([
        const RenameOp(fromPath: 'lib/utils', toPath: 'lib/helpers'),
      ]);

      expect(api.createBlobCalls, 0);
      final entries = _byPath(api.treeCalls.single);
      expect(entries['lib/utils/a.dart']!.isDelete, isTrue);
      expect(entries['lib/utils/b.dart']!.isDelete, isTrue);
      expect(entries['lib/helpers/a.dart']!.blobSha, 'sha_a');
      expect(entries['lib/helpers/b.dart']!.blobSha, 'sha_b');
      expect(result.plan.renamedPaths.length, 2);
    });

    test('update preserves the original file mode', () async {
      await apply([
        UpdateFileOp(path: 'scripts/run.sh', bytes: _bytes('echo hi')),
      ]);
      final entry = _byPath(api.treeCalls.single)['scripts/run.sh']!;
      expect(entry.mode, '100755');
      expect(entry.blobSha, 'new_blob_1');
    });

    test('create file keeps Arabic and spaced paths untouched', () async {
      final result = await apply([
        CreateFileOp(path: 'ملاحظات/ملف جديد.txt', bytes: _bytes('مرحبا')),
      ]);
      final entry = _byPath(api.treeCalls.single)['ملاحظات/ملف جديد.txt']!;
      expect(entry.mode, '100644');
      expect(result.plan.addedPaths, ['ملاحظات/ملف جديد.txt']);
      expect(utf8.decode(api.uploaded.single), 'مرحبا');
    });

    test('operations are applied in order against staged state', () async {
      final result = await apply([
        CreateFileOp(path: 'new.txt', bytes: _bytes('x')),
        const RenameOp(fromPath: 'new.txt', toPath: 'docs/new.txt'),
        const DeleteOp('README.md'),
      ]);
      final entries = _byPath(api.treeCalls.single);
      expect(entries.containsKey('new.txt'), isFalse);
      expect(entries['docs/new.txt']!.blobSha, 'new_blob_1');
      expect(result.plan.addedPaths, ['docs/new.txt']);
      expect(result.plan.deletedPaths, ['README.md']);
    });

    test('create then delete in the same batch changes nothing', () async {
      await expectLater(
        apply([
          CreateFileOp(path: 'tmp.txt', bytes: _bytes('x')),
          const DeleteOp('tmp.txt'),
        ]),
        throwsA(isA<InvalidRepoOperationException>()),
      );
      expect(api.createTreeCalls, 0);
      expect(api.createBlobCalls, 0);
    });

    test('renaming back to the original path is a no-op', () async {
      await expectLater(
        apply([
          const RenameOp(fromPath: 'README.md', toPath: 'README2.md'),
          const RenameOp(fromPath: 'README2.md', toPath: 'README.md'),
        ]),
        throwsA(isA<InvalidRepoOperationException>()),
      );
      expect(api.createTreeCalls, 0);
    });

    test('large batches are chained through multiple trees', () async {
      api.files = [
        for (var i = 0; i < 1200; i++)
          RemoteTreeBlob(
            path: 'bulk/f$i.txt',
            sha: 'sha_$i',
            mode: '100644',
            size: 1,
          ),
        const RemoteTreeBlob(
          path: 'keep.txt',
          sha: 'sha_keep',
          mode: '100644',
          size: 1,
        ),
      ];
      await apply([const DeleteOp('bulk')]);

      expect(api.createTreeCalls, 2);
      expect(api.treeBases, [_kRootTree, 'tree_new_1']);
      expect(api.treeCalls[0].length + api.treeCalls[1].length, 1200);
      expect(api.lastCommitTree, 'tree_new_2');
      expect(api.createCommitCalls, 1);
    });

    test('default commit message summarises the plan', () async {
      final plan = await engine.previewChanges(
        token: 'token',
        target: _makeTarget(),
        ops: [
          CreateFileOp(path: 'new.txt', bytes: _bytes('x')),
          UpdateFileOp(path: 'lib/main.dart', bytes: _bytes('y')),
          const DeleteOp('lib/utils'),
          const RenameOp(fromPath: 'scripts/run.sh', toPath: 'bin/run.sh'),
        ],
      );
      expect(plan.defaultCommitMessage,
          'Nexus: add 1, update 1, delete 2, rename 1');
      expect(api.createBlobCalls, 0, reason: 'preview never writes');
      expect(api.createTreeCalls, 0);
    });
  });

  group('RepoFilesEngine - validation', () {
    test('rejects dangerous or malformed paths', () async {
      for (final path in ['../x', '.git/config', '/abs', 'a//b', 'a/', 'a\\b', '']) {
        await expectLater(
          apply([CreateFileOp(path: path, bytes: _bytes('x'))]),
          throwsA(isA<InvalidRepoOperationException>()),
          reason: 'path "$path" must be rejected',
        );
      }
      expect(api.createBlobCalls, 0);
    });

    test('create fails when the target path is occupied', () async {
      // existing file
      await expectLater(
        apply([CreateFileOp(path: 'README.md', bytes: _bytes('x'))]),
        throwsA(isA<InvalidRepoOperationException>()),
      );
      // existing folder
      await expectLater(
        apply([CreateFileOp(path: 'lib', bytes: _bytes('x'))]),
        throwsA(isA<InvalidRepoOperationException>()),
      );
      // a parent segment is a file
      await expectLater(
        apply([CreateFileOp(path: 'README.md/child.txt', bytes: _bytes('x'))]),
        throwsA(isA<InvalidRepoOperationException>()),
      );
    });

    test('rename fails onto an existing path or into itself', () async {
      await expectLater(
        apply([const RenameOp(fromPath: 'README.md', toPath: 'lib/main.dart')]),
        throwsA(isA<InvalidRepoOperationException>()),
      );
      await expectLater(
        apply([const RenameOp(fromPath: 'lib', toPath: 'lib/inner/lib')]),
        throwsA(isA<InvalidRepoOperationException>()),
      );
      await expectLater(
        apply([const RenameOp(fromPath: 'lib/utils', toPath: 'docs')]),
        throwsA(isA<InvalidRepoOperationException>()),
      );
    });

    test('missing sources are reported', () async {
      await expectLater(
        apply([const DeleteOp('nope.txt')]),
        throwsA(isA<InvalidRepoOperationException>()),
      );
      await expectLater(
        apply([UpdateFileOp(path: 'nope.txt', bytes: _bytes('x'))]),
        throwsA(isA<InvalidRepoOperationException>()),
      );
      await expectLater(
        apply([const RenameOp(fromPath: 'nope', toPath: 'other')]),
        throwsA(isA<InvalidRepoOperationException>()),
      );
    });

    test('symlinks cannot be edited', () async {
      api.files = [
        const RemoteTreeBlob(path: 'link', sha: 'sha_link', mode: '120000', size: 3),
      ];
      await expectLater(
        apply([UpdateFileOp(path: 'link', bytes: _bytes('x'))]),
        throwsA(isA<InvalidRepoOperationException>()),
      );
    });

    test('blank message and empty op list are rejected', () async {
      await expectLater(
        apply([const DeleteOp('README.md')], message: '   '),
        throwsA(isA<InvalidRepoOperationException>()),
      );
      await expectLater(
        apply(const []),
        throwsA(isA<InvalidRepoOperationException>()),
      );
    });

    test('read-only repositories fail before any API call', () async {
      await expectLater(
        apply(
          [const DeleteOp('README.md')],
          target: _makeTarget(canPush: false),
        ),
        throwsA(isA<InsufficientScopeException>()),
      );
      expect(api.headCalls, 0);
    });

    test('empty repositories are refused with a clear error', () async {
      await expectLater(
        apply(
          [CreateFileOp(path: 'a.txt', bytes: _bytes('x'))],
          target: _makeTarget(isEmpty: true),
        ),
        throwsA(isA<InvalidRepoOperationException>()),
      );
    });
  });

  group('RepoFilesEngine - conflicts & permissions', () {
    test('stale expectedHeadSha aborts before any write', () async {
      await expectLater(
        apply([const DeleteOp('README.md')], expectedHeadSha: 'older_commit'),
        throwsA(isA<BranchChangedException>()),
      );
      expect(api.createBlobCalls, 0);
      expect(api.createTreeCalls, 0);
      expect(api.updateRefCalls, 0);
    });

    test('matching expectedHeadSha succeeds', () async {
      await apply([const DeleteOp('README.md')], expectedHeadSha: _kHeadCommit);
      expect(api.updateRefCalls, 1);
    });

    test('non fast-forward ref update becomes BranchChangedException', () async {
      api.updateRefError =
          const GitHubApiException('Update is not a fast forward', statusCode: 422);
      await expectLater(
        apply([const DeleteOp('README.md')]),
        throwsA(isA<BranchChangedException>()),
      );
    });

    test('403 while writing maps to InsufficientScopeException', () async {
      api.blobError =
          const GitHubApiException('Resource not accessible', statusCode: 403);
      await expectLater(
        apply([UpdateFileOp(path: 'README.md', bytes: _bytes('x'))]),
        throwsA(isA<InsufficientScopeException>()),
      );
    });

    test('branch protection (422) is not mistaken for a moved branch', () async {
      api.updateRefError = const GitHubApiException(
        'Changes must be made through a pull request.',
        statusCode: 422,
      );
      await expectLater(
        apply([const DeleteOp('README.md')]),
        throwsA(isA<ProtectedBranchException>()),
      );
    });

    test('branch protection (403) maps to ProtectedBranchException', () async {
      api.updateRefError = const GitHubApiException(
        'Protected branch update failed for refs/heads/main.',
        statusCode: 403,
      );
      await expectLater(
        apply([const DeleteOp('README.md')]),
        throwsA(
          isA<ProtectedBranchException>()
              .having((e) => e.branchName, 'branchName', 'main')
              .having((e) => e.message, 'message', contains('"main"')),
        ),
      );
    });

    test('undo against a protected branch reports the protection', () async {
      final result = await apply([const DeleteOp('README.md')]);
      api.updateRefError = const GitHubApiException(
        'Required status check "ci" is expected.',
        statusCode: 422,
      );
      await expectLater(
        engine.undoCommit(token: 'token', target: _makeTarget(), result: result),
        throwsA(isA<ProtectedBranchException>()),
      );
    });
  });

  group('RepoFilesEngine - truncated trees', () {
    test('folder delete works through per-folder listings', () async {
      api.truncated = true;
      final result = await apply([const DeleteOp('lib/utils')]);

      expect(api.shallowCalls, greaterThan(0));
      final entries = _byPath(api.treeCalls.single);
      expect(entries.keys.toSet(), {'lib/utils/a.dart', 'lib/utils/b.dart'});
      expect(entries.values.every((e) => e.isDelete), isTrue);
      expect(result.plan.deletedPaths.length, 2);
    });

    test('rename works and keeps shas', () async {
      api.truncated = true;
      await apply([
        const RenameOp(fromPath: 'scripts/run.sh', toPath: 'bin/run.sh'),
      ]);
      final entries = _byPath(api.treeCalls.single);
      expect(entries['bin/run.sh']!.blobSha, 'sha_run');
      expect(entries['bin/run.sh']!.mode, '100755');
      expect(entries['scripts/run.sh']!.isDelete, isTrue);
    });
  });

  group('RepoFilesEngine - undo', () {
    test('undo commits the previous tree on top of the new head', () async {
      final result = await apply([const DeleteOp('README.md')]);
      final revert = await engine.undoCommit(
        token: 'token',
        target: _makeTarget(),
        result: result,
      );

      expect(api.createCommitCalls, 2);
      expect(api.lastCommitTree, result.previousTreeSha);
      expect(api.lastCommitParents, [result.commit.sha]);
      expect(api.lastCommitMessage, startsWith('Revert "'));
      expect(api.head!.commitSha, revert.sha);
    });

    test('undo is refused when the branch moved on', () async {
      final result = await apply([const DeleteOp('README.md')]);
      api.head = const BranchHeadRef(
        commitSha: 'someone_elses_commit',
        treeSha: 'tree_other',
      );
      final commitsBefore = api.createCommitCalls;

      await expectLater(
        engine.undoCommit(token: 'token', target: _makeTarget(), result: result),
        throwsA(isA<BranchChangedException>()),
      );
      expect(api.createCommitCalls, commitsBefore);
    });
  });

  group('RepoContentService', () {
    late RepoContentService service;

    setUp(() {
      service = RepoContentService(
        api: api,
        token: 'token',
        owner: 'abdullah',
        repo: 'nexus-demo',
        rootTreeSha: _kRootTree,
      );
    });

    test('listFolder returns folders first, then files, sorted', () async {
      final entries = await service.listFolder('');
      expect(entries.map((e) => e.name).toList(), [
        'docs',
        'lib',
        'scripts',
        'README.md',
      ]);
      expect(entries.first.isFolder, isTrue);
      expect(entries.last.isFile, isTrue);
    });

    test('findFile / folderExists / blobsUnder', () async {
      expect((await service.findFile('lib/main.dart'))!.sha, 'sha_main');
      expect(await service.findFile('lib/missing.dart'), isNull);
      expect(await service.findFile('lib'), isNull);
      expect(await service.folderExists('lib/utils'), isTrue);
      expect(await service.folderExists('lib/main.dart'), isFalse);

      final under = await service.blobsUnder('lib');
      expect(under.map((b) => b.path).toSet(), {
        'lib/main.dart',
        'lib/utils/a.dart',
        'lib/utils/b.dart',
      });
    });

    test('listing the same tree twice hits the network once', () async {
      await service.listFolder('lib');
      final calls = api.shallowCalls;
      await service.listFolder('lib');
      expect(api.shallowCalls, calls);
    });

    test('listFolder on a missing folder throws 404', () async {
      await expectLater(
        service.listFolder('nope'),
        throwsA(isA<GitHubApiException>()),
      );
    });

    test('readFile returns blob bytes or null', () async {
      final bytes = await service.readFile('README.md');
      expect(utf8.decode(bytes!), 'content of sha_readme');
      expect(await service.readFile('missing.md'), isNull);
    });
  });
}
