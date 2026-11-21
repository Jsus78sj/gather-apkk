import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/core/network/github_api_client.dart';
import 'package:github_nexus/core/network/github_exceptions.dart';
import 'package:github_nexus/features/repo_browser/domain/remote_tree_entry.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_op_result.dart';
import 'package:github_nexus/features/repo_browser/presentation/repo_browser_controller.dart';
import 'package:github_nexus/features/repos/domain/deploy_target.dart';
import 'support/browser_fakes.dart';

RepoBrowserController _controller(
  BrowserFakeApi api, {
  DeployTarget? target,
  Duration undoWindow = RepoBrowserController.defaultUndoWindow,
}) {
  final controller = RepoBrowserController(
    api: api,
    token: 't',
    target: target ?? browserTarget(),
    undoWindow: undoWindow,
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

Future<RepoBrowserController> _loaded(
  BrowserFakeApi api, {
  Duration undoWindow = RepoBrowserController.defaultUndoWindow,
}) async {
  final controller = _controller(api, undoWindow: undoWindow);
  await _settle(controller);
  return controller;
}

List<String> _names(RepoBrowserController controller) =>
    controller.debugState.entries.map((e) => e.name).toList();

RemoteTreeEntry _entry(RepoBrowserController controller, String name) =>
    controller.debugState.entries.firstWhere((e) => e.name == name);

/// Selects the entries called [names] in the current folder.
void _select(RepoBrowserController controller, List<String> names) {
  for (final name in names) {
    controller.toggleSelection(_entry(controller, name));
  }
}

void main() {
  group('selection', () {
    test('a long press selects, toggling deselects, the last one exits',
        () async {
      final controller = await _loaded(BrowserFakeApi());
      expect(controller.debugState.isSelecting, isFalse);

      controller.toggleSelection(_entry(controller, 'README.md'));
      expect(controller.debugState.isSelecting, isTrue);
      expect(controller.debugState.selectedPaths, {'README.md'});
      expect(controller.isSelected(_entry(controller, 'README.md')), isTrue);

      controller.toggleSelection(_entry(controller, 'lib'));
      expect(controller.debugState.selectedPaths, {'README.md', 'lib'});

      controller.toggleSelection(_entry(controller, 'README.md'));
      controller.toggleSelection(_entry(controller, 'lib'));
      expect(controller.debugState.selectedPaths, isEmpty);
      expect(controller.debugState.isSelecting, isFalse);
    });

    test('paths inside a sub-folder are stored in full', () async {
      final controller = await _loaded(BrowserFakeApi());
      await controller.openFolder('lib/utils');

      controller.toggleSelection(_entry(controller, 'a.dart'));

      expect(controller.debugState.selectedPaths, {'lib/utils/a.dart'});
    });

    test('select all picks every entry of the current folder', () async {
      final controller = await _loaded(BrowserFakeApi());

      controller.selectAll();

      expect(controller.debugState.selectedPaths.length, 5);
      expect(controller.debugState.selectedPaths, contains('docs'));
      expect(controller.debugState.selectedPaths, contains('app.zip'));
      expect(
        controller.debugState.selectedPaths.length >=
            controller.debugState.selectableCount,
        isTrue,
      );
    });

    test('clearSelection leaves selection mode', () async {
      final controller = await _loaded(BrowserFakeApi());
      controller.selectAll();

      controller.clearSelection();

      expect(controller.debugState.isSelecting, isFalse);
    });

    test('submodules can never be selected', () async {
      final controller = await _loaded(BrowserFakeApi());
      const submodule = RemoteTreeEntry(
        name: 'vendor',
        sha: 'sha_vendor',
        mode: '160000',
        type: 'commit',
      );

      expect(controller.canSelect(submodule), isFalse);
      controller.toggleSelection(submodule);

      expect(controller.debugState.selectedPaths, isEmpty);
    });

    test('opening a folder clears the selection', () async {
      final controller = await _loaded(BrowserFakeApi());
      _select(controller, ['README.md']);

      await controller.openFolder('lib');

      expect(controller.debugState.isSelecting, isFalse);
    });

    test('nothing can be selected while the search is open', () async {
      final controller = await _loaded(BrowserFakeApi());
      controller.setSearchActive(true);
      await _settle(controller);

      controller.toggleSelection(_entry(controller, 'README.md'));

      expect(controller.debugState.isSelecting, isFalse);
    });

    test('a refresh keeps only the selected paths that still exist', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md', 'lib']);

      // Someone else deleted README.md and pushed.
      api
        ..files = api.files.where((f) => f.path != 'README.md').toList()
        ..head = const BranchHeadRef(commitSha: 'head2', treeSha: 'tree_root2');
      await controller.refresh();

      expect(controller.debugState.selectedPaths, {'lib'});
    });
  });

  group('delete preview', () {
    test('summarises folders and files without writing anything', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['lib', 'README.md']);

      final result = await controller.previewDeleteSelection();

      expect(result.isSuccess, isTrue);
      final preview = result.value!;
      expect(preview.itemCount, 2);
      expect(preview.folderPaths, ['lib']);
      expect(preview.filePaths, ['README.md']);
      // lib/main.dart, lib/utils/a.dart, lib/utils/b.dart + README.md
      expect(preview.totalFileCount, 4);
      expect(preview.filesInFolder('lib'), 3);
      expect(preview.hasFolders, isTrue);
      expect(preview.defaultMessage, 'Nexus: delete lib, README.md');
      expect(preview.samples().map((s) => s.path), ['lib', 'README.md']);

      expect(api.createBlobCalls, 0);
      expect(api.createTreeCalls, 0);
      expect(api.createCommitCalls, 0);
      expect(api.updateRefCalls, 0);
      expect(controller.debugState.isMutating, isFalse);
    });

    test('a long selection gets a count-based default message', () async {
      final controller = await _loaded(BrowserFakeApi());
      controller.selectAll();

      final preview = (await controller.previewDeleteSelection()).value!;

      expect(preview.defaultMessage, 'Nexus: delete 5 items');
      expect(preview.samples(max: 3).length, 3);
      expect(preview.hiddenCount(max: 3), 2);
    });

    test('without a selection it is refused locally', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final result = await controller.previewDeleteSelection();

      expect(result.failure, RepoOpFailure.invalid);
      expect(api.headCalls, 1);
    });
  });

  group('delete', () {
    test('a folder and two files go in ONE commit, and undo brings them back',
        () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      final before = _names(controller);
      _select(controller, ['lib', 'README.md', 'app.zip']);

      final result = await controller.deleteSelection(message: 'تنظيف');

      expect(result.isSuccess, isTrue);
      // One blob-free tree, one commit, one ref move.
      expect(api.createBlobCalls, 0);
      expect(api.createTreeCalls, 1);
      expect(api.createCommitCalls, 1);
      expect(api.updateRefCalls, 1);
      expect(api.commitMessages.single, 'تنظيف');
      final deleted = api.treeCalls.single;
      expect(deleted.every((e) => e.isDelete), isTrue);
      expect(
        deleted.map((e) => e.path).toSet(),
        {
          'lib/main.dart',
          'lib/utils/a.dart',
          'lib/utils/b.dart',
          'README.md',
          'app.zip',
        },
      );

      var state = controller.debugState;
      expect(_names(controller), ['docs', 'scripts']);
      expect(state.isSelecting, isFalse);
      expect(state.isMutating, isFalse);
      expect(state.headCommitSha, api.head!.commitSha);
      expect(state.undo, isNotNull);
      expect(state.undo!.summary, 'تم حذف 3 عناصر (5 ملفات)');

      final undone = await controller.undoLastChange();

      expect(undone.isSuccess, isTrue);
      expect(api.createCommitCalls, 2);
      expect(api.commitMessages.last, startsWith('Revert "'));
      state = controller.debugState;
      expect(_names(controller), before);
      expect(state.undo, isNull);
      expect(state.isMutating, isFalse);
      expect(state.headCommitSha, api.head!.commitSha);
    });

    test('a single file summary has no file count in brackets', () async {
      final controller = await _loaded(BrowserFakeApi());
      _select(controller, ['README.md']);

      await controller.deleteSelection(message: 'm');

      expect(controller.debugState.undo!.summary, 'تم حذف عنصر واحد');
    });

    test('deleting everything in a folder falls back to its parent', () async {
      final controller = await _loaded(BrowserFakeApi());
      await controller.openFolder('lib/utils');
      controller.selectAll();

      final result = await controller.deleteSelection(message: 'm');

      expect(result.isSuccess, isTrue);
      // Git has no empty folders: lib/utils is gone, so we land in lib.
      expect(controller.debugState.path, 'lib');
      expect(_names(controller), ['main.dart']);
    });

    test('Arabic and spaced names are deleted by their exact path', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      await controller.openFolder('docs');
      _select(controller, ['دليل المستخدم.md']);

      await controller.deleteSelection(message: 'm');

      expect(api.treeCalls.single.single.path, 'docs/دليل المستخدم.md');
    });

    test('the commit message is required', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);

      final result = await controller.deleteSelection(message: '   ');

      expect(result.failure, RepoOpFailure.invalid);
      expect(api.createCommitCalls, 0);
      expect(controller.debugState.isSelecting, isTrue);
    });

    test('with nothing selected it is refused before any request', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      final headCalls = api.headCalls;

      final result = await controller.deleteSelection(message: 'm');

      expect(result.failure, RepoOpFailure.invalid);
      expect(api.headCalls, headCalls);
    });

    test('an empty repository cannot be edited', () async {
      final controller = await _loaded(BrowserFakeApi(head: null));

      final result = await controller.deleteSelection(message: 'm');

      expect(result.failure, RepoOpFailure.invalid);
    });
  });

  group('delete failures', () {
    test('a moved branch aborts before any write and reloads the listing',
        () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);
      api.head = const BranchHeadRef(
        commitSha: 'someone_else',
        treeSha: 'tree_other',
      );

      final result = await controller.deleteSelection(message: 'm');

      expect(result.failure, RepoOpFailure.branchChanged);
      expect(result.message, isNotEmpty);
      expect(api.createTreeCalls, 0);
      expect(api.updateRefCalls, 0);
      final state = controller.debugState;
      expect(state.headCommitSha, 'someone_else');
      expect(state.isMutating, isFalse);
      expect(state.undo, isNull);
      // README.md still exists, so the user can retry with the same selection.
      expect(state.selectedPaths, {'README.md'});
    });

    test('the preview also stops when the branch moved', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);
      api.head = const BranchHeadRef(
        commitSha: 'someone_else',
        treeSha: 'tree_other',
      );

      final result = await controller.previewDeleteSelection();

      expect(result.failure, RepoOpFailure.branchChanged);
      expect(controller.debugState.headCommitSha, 'someone_else');
    });

    test('a push that lost the race (422) is reported as a moved branch',
        () async {
      final api = BrowserFakeApi()
        ..updateRefError =
            const GitHubApiException('Update is not a fast forward', statusCode: 422);
      final controller = await _loaded(api);
      _select(controller, ['README.md']);

      final result = await controller.deleteSelection(message: 'm');

      expect(result.failure, RepoOpFailure.branchChanged);
      expect(controller.debugState.undo, isNull);
    });

    test('a protected branch gets its own message', () async {
      final api = BrowserFakeApi()
        ..updateRefError = const GitHubApiException(
          'Changes must be made through a pull request.',
          statusCode: 422,
        );
      final controller = await _loaded(api);
      _select(controller, ['README.md']);

      final result = await controller.deleteSelection(message: 'm');

      expect(result.failure, RepoOpFailure.protectedBranch);
      expect(result.message, contains('محمي'));
      expect(result.message, contains('"main"'));
      expect(result.message, contains('Pull Request'));
      final state = controller.debugState;
      expect(state.undo, isNull);
      expect(state.isMutating, isFalse);
      // The selection survives so the user can see what was rejected.
      expect(state.selectedPaths, {'README.md'});
      expect(_names(controller), contains('README.md'));
    });

    test('a token without write access is a permission failure', () async {
      final api = BrowserFakeApi()
        ..updateRefError =
            const GitHubApiException('Resource not accessible', statusCode: 403);
      final controller = await _loaded(api);
      _select(controller, ['README.md']);

      final result = await controller.deleteSelection(message: 'm');

      expect(result.failure, RepoOpFailure.permission);
      expect(result.message, contains('Contents'));
      expect(controller.debugState.undo, isNull);
    });

    test('a read-only repository is refused before any write', () async {
      final api = BrowserFakeApi();
      final controller = _controller(
        api,
        target: browserTarget(canPush: false),
      );
      await _settle(controller);
      _select(controller, ['README.md']);

      final result = await controller.deleteSelection(message: 'm');

      expect(result.failure, RepoOpFailure.permission);
      expect(result.message, 'لا تملك صلاحية الكتابة في هذا المستودع.');
      expect(api.createTreeCalls, 0);
    });

    test('a connection problem is reported as a network failure', () async {
      final api = BrowserFakeApi()
        ..updateRefError = DioException(
          requestOptions: RequestOptions(path: '/refs'),
          type: DioExceptionType.connectionError,
        );
      final controller = await _loaded(api);
      _select(controller, ['README.md']);

      final result = await controller.deleteSelection(message: 'm');

      expect(result.failure, RepoOpFailure.network);
      expect(controller.debugState.isMutating, isFalse);
      expect(controller.debugState.selectedPaths, {'README.md'});
    });

    test('a rate limit is reported with its own message', () async {
      final api = BrowserFakeApi()
        ..updateRefError = const RateLimitException();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);

      final result = await controller.deleteSelection(message: 'm');

      expect(result.failure, RepoOpFailure.rateLimit);
    });
  });

  group('undo', () {
    test('the bar expires after the undo window', () async {
      final controller = await _loaded(
        BrowserFakeApi(),
        undoWindow: const Duration(milliseconds: 60),
      );
      _select(controller, ['README.md']);
      await controller.deleteSelection(message: 'm');
      expect(controller.debugState.undo, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 160));

      expect(controller.debugState.undo, isNull);
    });

    test('a head change seen by a refresh drops the bar', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);
      await controller.deleteSelection(message: 'm');
      expect(controller.debugState.undo, isNotNull);

      // A refresh that sees our own commit keeps the bar...
      await controller.refresh();
      expect(controller.debugState.undo, isNotNull);

      // ...but somebody else's push removes it.
      api.head = const BranchHeadRef(
        commitSha: 'someone_else',
        treeSha: 'tree_other',
      );
      await controller.refresh();

      expect(controller.debugState.undo, isNull);
    });

    test('undo is refused, and the bar dropped, when the branch moved',
        () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);
      await controller.deleteSelection(message: 'm');
      api.head = const BranchHeadRef(
        commitSha: 'someone_else',
        treeSha: 'tree_other',
      );

      final result = await controller.undoLastChange();

      expect(result.failure, RepoOpFailure.branchChanged);
      expect(api.createCommitCalls, 1);
      expect(controller.debugState.undo, isNull);
      expect(controller.debugState.headCommitSha, 'someone_else');
    });

    test('a network failure keeps the bar so the user can retry', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);
      await controller.deleteSelection(message: 'm');
      api.updateRefError = DioException(
        requestOptions: RequestOptions(path: '/refs'),
        type: DioExceptionType.connectionError,
      );

      final failed = await controller.undoLastChange();
      expect(failed.failure, RepoOpFailure.network);
      expect(controller.debugState.undo, isNotNull);
      expect(_names(controller), isNot(contains('README.md')));

      api.updateRefError = null;
      final retried = await controller.undoLastChange();

      expect(retried.isSuccess, isTrue);
      expect(_names(controller), contains('README.md'));
      expect(controller.debugState.undo, isNull);
    });

    test('dismissUndo hides the bar without touching the branch', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);
      await controller.deleteSelection(message: 'm');

      controller.dismissUndo();

      expect(controller.debugState.undo, isNull);
      expect(api.createCommitCalls, 1);
    });

    test('a second delete replaces the undo of the first', () async {
      final controller = await _loaded(BrowserFakeApi());
      _select(controller, ['README.md']);
      await controller.deleteSelection(message: 'first');
      final first = controller.debugState.undo!;

      _select(controller, ['app.zip']);
      await controller.deleteSelection(message: 'second');
      final second = controller.debugState.undo!;

      expect(second.result.commit.sha, isNot(first.result.commit.sha));
      final undone = await controller.undoLastChange();
      expect(undone.isSuccess, isTrue);
      // Only the second delete was reverted.
      expect(_names(controller), contains('app.zip'));
      expect(_names(controller), isNot(contains('README.md')));
    });

    test('without a pending change there is nothing to undo', () async {
      final controller = await _loaded(BrowserFakeApi());

      final result = await controller.undoLastChange();

      expect(result.failure, RepoOpFailure.invalid);
    });
  });
}
