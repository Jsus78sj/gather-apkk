import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/core/network/github_api_client.dart';
import 'package:github_nexus/core/network/github_exceptions.dart';
import 'package:github_nexus/features/repo_browser/domain/file_op.dart';
import 'package:github_nexus/features/repo_browser/domain/remote_tree_entry.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_code_search.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_commit_summary.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_file_content.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_op_result.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_undo_info.dart';
import 'package:github_nexus/features/repo_browser/domain/search_rate_limiter.dart';
import 'package:github_nexus/features/repo_browser/presentation/repo_browser_controller.dart';
import 'support/browser_fakes.dart';

/// Phase 10 controller tests: create / upload / history restore / protected
/// branch fallback / content search. (The UI wiring is covered by
/// `repo_phase10_ui_test.dart`.)

RepoBrowserController _controller(BrowserFakeApi api) {
  final controller = RepoBrowserController(
    api: api,
    token: 't',
    target: browserTarget(),
  );
  addTearDown(controller.dispose);
  return controller;
}

Future<void> _settle(RepoBrowserController controller) async {
  for (var i = 0; i < 400; i++) {
    final state = controller.debugState;
    if (!state.isLoading && !state.isIndexing && !state.isMutating) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('the controller never settled');
}

Future<RepoBrowserController> _loaded(BrowserFakeApi api) async {
  final controller = _controller(api);
  await _settle(controller);
  return controller;
}

RemoteTreeEntry _entry(RepoBrowserController controller, String name) =>
    controller.debugState.entries.firstWhere((e) => e.name == name);

void main() {
  group('createEntry', () {
    test('a file is created with its content in ONE commit', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final res = await controller.createEntry(
        name: 'notes/idea.md',
        bytes: Uint8List.fromList(utf8.encode('hello nexus')),
        message: 'Nexus: create notes/idea.md',
      );

      expect(res.isSuccess, isTrue);
      expect(api.createCommitCalls, 1);
      expect(api.commitMessages.single, 'Nexus: create notes/idea.md');
      expect(api.files.map((f) => f.path), contains('notes/idea.md'));
      expect(controller.debugState.undo?.kind, RepoUndoKind.create);
      // The listing was reloaded and shows the new folder.
      expect(
        controller.debugState.entries.map((e) => e.name),
        contains('notes'),
      );
    });

    test('a folder is materialized by .gitkeep', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final res = await controller.createEntry(
        name: 'docs',
        bytes: null,
        message: 'Nexus: create folder docs',
      );

      expect(res.isSuccess, isTrue);
      expect(api.files.map((f) => f.path), contains('docs/.gitkeep'));
    });

    test('an existing path is refused before any write', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final res = await controller.createEntry(
        name: 'README.md',
        bytes: utf8.encode('dup'),
        message: 'Nexus: create README.md',
      );

      expect(res.isSuccess, isFalse);
      expect(res.failure, RepoOpFailure.invalid);
      expect(api.createCommitCalls, 0);
    });

    test('an invalid path is refused locally', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final res = await controller.createEntry(
        name: 'a/../b.md',
        bytes: utf8.encode('x'),
        message: 'Nexus: create',
      );

      expect(res.isSuccess, isFalse);
      expect(res.failure, RepoOpFailure.invalid);
      expect(api.createCommitCalls, 0);
    });
  });

  group('uploadFiles', () {
    test('new files are uploaded in ONE commit', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final res = await controller.uploadFiles(
        files: [
          (name: 'a.png', bytes: utf8.encode('image')),
          (name: 'b.txt', bytes: utf8.encode('text')),
        ],
        message: 'Nexus: upload 2 files',
        overwriteExisting: false,
      );

      expect(res.isSuccess, isTrue);
      expect(api.createCommitCalls, 1);
      expect(api.files.map((f) => f.path), containsAll(['a.png', 'b.txt']));
      expect(controller.debugState.undo?.kind, RepoUndoKind.upload);
    });

    test('a colliding name without overwrite is refused', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final res = await controller.uploadFiles(
        files: [(name: 'README.md', bytes: utf8.encode('replacement'))],
        message: 'Nexus: upload',
        overwriteExisting: false,
      );

      expect(res.isSuccess, isFalse);
      expect(res.failure, RepoOpFailure.invalid);
      expect(api.createCommitCalls, 0);
    });

    test('a colliding name with overwrite becomes an update', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final res = await controller.uploadFiles(
        files: [(name: 'README.md', bytes: utf8.encode('replacement'))],
        message: 'Nexus: upload',
        overwriteExisting: true,
      );

      expect(res.isSuccess, isTrue);
      final readme = api.files.firstWhere((f) => f.path == 'README.md');
      expect(readme.sha, 'new_blob_1');
      expect(readme.mode, '100644'); // the remote mode is preserved
    });

    test('an empty selection is refused', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final res = await controller.uploadFiles(
        files: const [],
        message: 'Nexus: upload',
        overwriteExisting: false,
      );

      expect(res.isSuccess, isFalse);
      expect(res.failure, RepoOpFailure.invalid);
    });
  });

  group('file history & restore', () {
    test('fetchFileHistory returns the seeded commits', () async {
      final api = BrowserFakeApi();
      api.commits = [
        const RepoCommitSummary(
          sha: 'abc1234def',
          message: 'Nexus: update README',
          authorName: 'dev',
          authoredAt: null,
          htmlUrl: '',
        ),
      ];
      final controller = await _loaded(api);

      final res = await controller.fetchFileHistory('README.md');

      expect(res.isSuccess, isTrue);
      expect(res.value, hasLength(1));
      expect(res.value!.single.shortSha, 'abc1234');
    });

    test('restore commits the historic content as a new commit', () async {
      // The historic snapshot (what docs/a.md looked like at c_old): the file
      // was executable then.
      final api = BrowserFakeApi(files: [
        const RemoteTreeBlob(
          path: 'docs/a.md',
          sha: 'sha_cur_a',
          mode: '100644',
          size: 5,
        ),
        const RemoteTreeBlob(
          path: 'README.md',
          sha: 'sha_readme',
          mode: '100644',
          size: 21,
        ),
      ]);
      api.seedCommit('c_old', 'tree_old', const [
        RemoteTreeBlob(
          path: 'docs/a.md',
          sha: 'sha_old_a',
          mode: '100755',
          size: 3,
        ),
        RemoteTreeBlob(
          path: 'README.md',
          sha: 'sha_readme',
          mode: '100644',
          size: 21,
        ),
      ]);
      api.commits = [
        const RepoCommitSummary(
          sha: 'c_old',
          message: 'old version',
          authorName: 'dev',
          authoredAt: null,
          htmlUrl: '',
        ),
      ];
      final controller = await _loaded(api);

      final res = await controller.restoreFileFromCommit(
        filePath: 'docs/a.md',
        commit: api.commits.first,
      );

      expect(res.isSuccess, isTrue);
      expect(res.value!.updatedFile!.mode, '100755'); // the historic mode
      expect(
        api.files.firstWhere((f) => f.path == 'docs/a.md').sha,
        'new_blob_1', // the historic content was re-uploaded
      );
      expect(api.createCommitCalls, 1);
      expect(
        api.commitMessages.single,
        contains('restore'),
      );
      expect(controller.debugState.undo?.kind, RepoUndoKind.restore);
      // The other files are untouched.
      expect(
        api.files.firstWhere((f) => f.path == 'README.md').sha,
        'sha_readme',
      );
    });

    test('restoring an identical version is refused', () async {
      final api = BrowserFakeApi(files: [
        const RemoteTreeBlob(
          path: 'docs/a.md',
          sha: 'sha_cur_a',
          mode: '100644',
          size: 5,
        ),
      ]);
      api.seedCommit('c_same', 'tree_same', const [
        RemoteTreeBlob(
          path: 'docs/a.md',
          sha: 'sha_cur_a',
          mode: '100644',
          size: 5,
        ),
      ]);
      api.commits = [
        const RepoCommitSummary(
          sha: 'c_same',
          message: 'same',
          authorName: 'dev',
          authoredAt: null,
          htmlUrl: '',
        ),
      ];
      final controller = await _loaded(api);

      final res = await controller.restoreFileFromCommit(
        filePath: 'docs/a.md',
        commit: api.commits.first,
      );

      expect(res.isSuccess, isFalse);
      expect(res.failure, RepoOpFailure.invalid);
      expect(api.createCommitCalls, 0);
    });

    test('a file missing from the historic commit is refused', () async {
      final api = BrowserFakeApi();
      api.seedCommit('c_old', 'tree_old', const [
        RemoteTreeBlob(
          path: 'README.md',
          sha: 'sha_readme',
          mode: '100644',
          size: 21,
        ),
      ]);
      api.commits = [
        const RepoCommitSummary(
          sha: 'c_old',
          message: 'old',
          authorName: 'dev',
          authoredAt: null,
          htmlUrl: '',
        ),
      ];
      final controller = await _loaded(api);

      final res = await controller.restoreFileFromCommit(
        filePath: 'lib/main.dart', // not in the historic tree
        commit: api.commits.first,
      );

      expect(res.isSuccess, isFalse);
      expect(res.failure, RepoOpFailure.invalid);
      expect(api.createCommitCalls, 0);
    });

    test('resolveFileRef resolves loaded files and misses unknown ones',
        () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final ref = await controller.resolveFileRef('lib/main.dart');
      expect(ref, isNotNull);
      expect(ref!.sha, 'sha_main');
      expect(ref.size, 20);

      expect(await controller.resolveFileRef('ghost.txt'), isNull);
    });
  });

  group('protected branch fallback', () {
    test('the rejected ops are kept for the fallback', () async {
      final api = BrowserFakeApi();
      api.protectedBranches.add('main');
      final controller = await _loaded(api);

      controller.toggleSelection(_entry(controller, 'README.md'));
      final res = await controller.deleteSelection(message: 'Nexus: delete');

      expect(res.isSuccess, isFalse);
      expect(res.failure, RepoOpFailure.protectedBranch);

      final ops = controller.takeRejectedWriteOps();
      expect(ops, isNotNull);
      expect(ops, hasLength(1));
      // Taking them clears the stash.
      expect(controller.takeRejectedWriteOps(), isNull);
    });

    test('the fallback commits on a new branch and opens the PR', () async {
      final api = BrowserFakeApi();
      api.protectedBranches.add('main');
      final controller = await _loaded(api);

      controller.toggleSelection(_entry(controller, 'README.md'));
      final delete = await controller.deleteSelection(message: 'Nexus: delete');
      expect(delete.failure, RepoOpFailure.protectedBranch);
      final ops = controller.takeRejectedWriteOps()!;

      final pr = await controller.commitOnNewBranchAndOpenPullRequest(
        ops: ops,
        message: 'Nexus: delete README.md',
        newBranchName: 'nexus/patch-1',
        prTitle: 'Remove README',
      );

      expect(pr.isSuccess, isTrue);
      expect(api.createBranchCalls, 1);
      expect(api.createPullRequestCalls, 1);
      expect(api.lastPullRequestHead, 'nexus/patch-1');
      expect(api.lastPullRequestBase, 'main');
      expect(api.lastPullRequestTitle, 'Remove README');
      // The commit landed on the new branch, not on the browsed one. The
      // rejected delete attempt on `main` had already built a commit
      // (commit_new_1) that was never pushed, so the fallback is the second.
      expect(api.extraBranches['nexus/patch-1']?.commitSha, 'commit_new_2');
      expect(api.head?.commitSha, kBrowserHeadCommit);
      expect(api.files.map((f) => f.path), contains('README.md'));
      expect(api.deleteBranchCalls, 0);
    });

    test('a failed fallback deletes the branch it created', () async {
      final api = BrowserFakeApi();
      // BOTH branches reject pushes, so the fallback commit fails too.
      api.protectedBranches.addAll({'main', 'nexus/patch-1'});
      final controller = await _loaded(api);

      controller.toggleSelection(_entry(controller, 'README.md'));
      final delete = await controller.deleteSelection(message: 'Nexus: delete');
      final ops = controller.takeRejectedWriteOps()!;

      final pr = await controller.commitOnNewBranchAndOpenPullRequest(
        ops: ops,
        message: 'Nexus: delete README.md',
        newBranchName: 'nexus/patch-1',
        prTitle: 'Remove README',
      );

      expect(pr.isSuccess, isFalse);
      expect(pr.failure, RepoOpFailure.protectedBranch);
      expect(api.createPullRequestCalls, 0);
      expect(api.deleteBranchCalls, 1);
      expect(api.extraBranches.containsKey('nexus/patch-1'), isFalse);
      // Nothing was written anywhere.
      expect(api.head?.commitSha, kBrowserHeadCommit);
    });

    test('an invalid branch name is refused locally', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final pr = await controller.commitOnNewBranchAndOpenPullRequest(
        ops: const [DeleteOp('README.md')],
        message: 'Nexus: delete',
        newBranchName: 'main',
        prTitle: 'same as base',
      );

      expect(pr.isSuccess, isFalse);
      expect(pr.failure, RepoOpFailure.invalid);
      expect(api.createBranchCalls, 0);
    });
  });

  group('content search', () {
    test('runCodeSearch returns the API results', () async {
      final api = BrowserFakeApi();
      api.searchResult = const RepoCodeSearchResult(
        totalCount: 1,
        incompleteResults: false,
        items: [
          RepoCodeSearchHit(
            path: 'lib/main.dart',
            sha: 'sha_main',
            htmlUrl: '',
            snippets: ['void main()'],
          ),
        ],
      );
      final controller = await _loaded(api);

      await controller.runCodeSearch('void main');

      expect(api.searchCalls, 1);
      expect(controller.debugState.codeSearchResult.items.single.path,
          'lib/main.dart');
      expect(controller.debugState.codeSearchError, isNull);
    });

    test('an empty query costs no request', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      await controller.runCodeSearch('   ');

      expect(api.searchCalls, 0);
    });

    test('the quota is enforced locally before hitting the API', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      for (var i = 0; i < 8; i++) {
        await controller.runCodeSearch('query $i');
      }
      expect(api.searchCalls, 8);

      await controller.runCodeSearch('query 8');
      expect(api.searchCalls, 8); // refused locally
      expect(controller.debugState.codeSearchError, isNotNull);
      expect(controller.debugState.codeSearchError, contains('انتظر'));
    });

    test('a search failure surfaces as codeSearchError', () async {
      final api = BrowserFakeApi();
      api.searchError = const GitHubApiException('استعلام غير صالح',
          statusCode: 422);
      final controller = await _loaded(api);

      await controller.runCodeSearch('???');

      expect(controller.debugState.codeSearchError, isNotNull);
      expect(controller.debugState.isCodeSearching, isFalse);
    });

    test('closing the search resets the content-search state', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      controller.setSearchActive(true);
      controller.setCodeSearchMode(true);
      expect(controller.debugState.codeSearchMode, isTrue);

      controller.setSearchActive(false);
      expect(controller.debugState.codeSearchMode, isFalse);
      expect(controller.debugState.codeSearchResult.items, isEmpty);
    });
  });

  test('the search rate limiter allows a burst then refuses', () {
    var now = DateTime(2026, 1, 1, 12);
    final limiter = SearchRateLimiter(
      maxRequests: 3,
      window: const Duration(minutes: 1),
      now: () => now,
    );

    expect(limiter.waitTime(), isNull);
    limiter
      ..record()
      ..record()
      ..record();
    expect(limiter.waitTime(), isNotNull);

    now = now.add(const Duration(seconds: 61));
    expect(limiter.waitTime(), isNull);
  });
}
