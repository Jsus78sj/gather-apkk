import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/core/network/github_api_client.dart';
import 'package:github_nexus/core/network/github_exceptions.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_file_content.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_op_result.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_text_codec.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_undo_info.dart';
import 'package:github_nexus/features/repo_browser/presentation/repo_browser_controller.dart';
import 'support/browser_fakes.dart';

/// Phase 9 controller tests: conflict detection and the atomic save used by
/// the text editor.

RepoBrowserController _controller(
  BrowserFakeApi api, {
  bool canPush = true,
}) {
  final controller = RepoBrowserController(
    api: api,
    token: 't',
    target: browserTarget(canPush: canPush),
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
  bool canPush = true,
}) async {
  final controller = _controller(api, canPush: canPush);
  await _settle(controller);
  return controller;
}

const _readme = RepoFileRef(path: 'README.md', sha: 'sha_readme', size: 21);
const _script = RepoFileRef(
  path: 'scripts/run.sh',
  sha: 'sha_run',
  size: 7,
  mode: '100755',
);

Uint8List _bytes(String text) => RepoTextCodec.encodeForCommit(
      text,
      originalLineEnding: LineEnding.lf,
      hasBom: false,
    );

/// The remote branch moved: a new head whose files are [files].
void _moveHead(BrowserFakeApi api, List<RemoteTreeBlob> files) {
  api.head = const BranchHeadRef(
    commitSha: 'head_other',
    treeSha: 'tree_other',
  );
  api.files = files;
}

void main() {
  group('checkEditConflict', () {
    test('no conflict while the branch head is still the one opened',
        () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final result = await controller.checkEditConflict(
        openedFile: _readme,
        openedHeadSha: kBrowserHeadCommit,
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, isNull);
    });

    test('head moved by changes to OTHER files: warns, file untouched',
        () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _moveHead(api, [
        for (final f in defaultBrowserFiles())
          if (f.path == 'lib/main.dart')
            const RemoteTreeBlob(
              path: 'lib/main.dart',
              sha: 'sha_main_v2',
              mode: '100644',
              size: 30,
            )
          else
            f,
      ]);

      final result = await controller.checkEditConflict(
        openedFile: _readme,
        openedHeadSha: kBrowserHeadCommit,
      );

      expect(result.isSuccess, isTrue);
      final conflict = result.value!;
      expect(conflict.sameFileChanged, isFalse);
      expect(conflict.fileDeletedRemotely, isFalse);
      expect(conflict.openedHeadSha, kBrowserHeadCommit);
      expect(conflict.latestHeadSha, 'head_other');
      expect(conflict.latestFileRef?.sha, 'sha_readme');
    });

    test('the very file changed remotely: severe conflict with latest ref',
        () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _moveHead(api, [
        for (final f in defaultBrowserFiles())
          if (f.path == 'README.md')
            const RemoteTreeBlob(
              path: 'README.md',
              sha: 'sha_readme_v2',
              mode: '100644',
              size: 40,
            )
          else
            f,
      ]);

      final result = await controller.checkEditConflict(
        openedFile: _readme,
        openedHeadSha: kBrowserHeadCommit,
      );

      final conflict = result.value!;
      expect(conflict.sameFileChanged, isTrue);
      expect(conflict.fileDeletedRemotely, isFalse);
      expect(conflict.latestFileRef?.sha, 'sha_readme_v2');
      expect(conflict.latestFileRef?.size, 40);
    });

    test('the file was deleted remotely', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _moveHead(api, [
        for (final f in defaultBrowserFiles())
          if (f.path != 'README.md') f,
      ]);

      final result = await controller.checkEditConflict(
        openedFile: _readme,
        openedHeadSha: kBrowserHeadCommit,
      );

      final conflict = result.value!;
      expect(conflict.fileDeletedRemotely, isTrue);
      expect(conflict.sameFileChanged, isTrue);
      expect(conflict.latestFileRef, isNull);
    });

    test('a network failure is reported, not thrown', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      api.headError = const GitHubApiException('boom', statusCode: 500);

      final result = await controller.checkEditConflict(
        openedFile: _readme,
        openedHeadSha: kBrowserHeadCommit,
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, 'boom');
    });
  });

  group('saveFileEdit', () {
    test('saves in ONE commit with the edited content', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final result = await controller.saveFileEdit(
        openedFile: _readme,
        bytes: _bytes('# new title\n'),
        message: 'Nexus: update README.md',
        expectedHeadSha: kBrowserHeadCommit,
      );

      expect(result.isSuccess, isTrue);
      expect(api.createBlobCalls, 1);
      expect(api.createTreeCalls, 1);
      expect(api.createCommitCalls, 1);
      expect(api.updateRefCalls, 1);
      expect(api.commitMessages.single, 'Nexus: update README.md');

      final entry = api.treeCalls.single.single;
      expect(entry.path, 'README.md');
      expect(entry.blobSha, 'new_blob_1');
      expect(entry.mode, '100644');

      final saved = result.value!;
      expect(saved.commit.uploadedBlobShas, {'README.md': 'new_blob_1'});
      expect(saved.updatedFile?.path, 'README.md');
      expect(saved.updatedFile?.sha, 'new_blob_1');
      expect(saved.updatedFile?.size, _bytes('# new title\n').length);
    });

    test('keeps the executable bit of the file', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final result = await controller.saveFileEdit(
        openedFile: _script,
        bytes: _bytes('echo hi\n'),
        message: 'edit script',
        expectedHeadSha: kBrowserHeadCommit,
      );

      expect(result.isSuccess, isTrue);
      expect(api.treeCalls.single.single.mode, '100755');
      expect(result.value!.updatedFile?.mode, '100755');
    });

    test('CRLF and BOM chosen by the caller reach the uploaded content',
        () async {
      final bytes = RepoTextCodec.encodeForCommit(
        'a\nb\n',
        originalLineEnding: LineEnding.crlf,
        hasBom: true,
      );
      // Sanity of the input the controller is handed (the codec has its own
      // tests): BOM + CRLF.
      expect(bytes.take(3), RepoTextCodec.utf8Bom);
      expect(bytes.sublist(3), [0x61, 0x0D, 0x0A, 0x62, 0x0D, 0x0A]);

      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      final result = await controller.saveFileEdit(
        openedFile: _readme,
        bytes: bytes,
        message: 'm',
        expectedHeadSha: kBrowserHeadCommit,
      );
      expect(result.isSuccess, isTrue);
      expect(result.value!.updatedFile?.size, bytes.length);
    });

    test('the listing reloads and the undo bar offers a revert', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      final headsBefore = api.headCalls;

      await controller.saveFileEdit(
        openedFile: _readme,
        bytes: _bytes('x'),
        message: 'edit',
        expectedHeadSha: kBrowserHeadCommit,
      );
      await _settle(controller);

      final state = controller.debugState;
      expect(api.headCalls, greaterThan(headsBefore));
      expect(state.headCommitSha, 'commit_new_1');
      expect(state.isMutating, isFalse);
      expect(state.undo?.kind, RepoUndoKind.edit);
      expect(state.undo?.summary, 'تم حفظ التعديلات في "README.md"');
    });

    test('undo restores the previous content with a revert commit', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      await controller.saveFileEdit(
        openedFile: _readme,
        bytes: _bytes('x'),
        message: 'edit',
        expectedHeadSha: kBrowserHeadCommit,
      );
      await _settle(controller);
      expect(api.files.firstWhere((f) => f.path == 'README.md').sha,
          'new_blob_1');

      final undo = await controller.undoLastChange();
      await _settle(controller);

      expect(undo.isSuccess, isTrue);
      expect(api.createCommitCalls, 2);
      expect(api.commitMessages.last, startsWith('Revert "'));
      expect(api.files.firstWhere((f) => f.path == 'README.md').sha,
          'sha_readme');
      expect(controller.debugState.undo, isNull);
    });

    test('a head that moved is refused BEFORE anything is uploaded',
        () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _moveHead(api, defaultBrowserFiles());

      final result = await controller.saveFileEdit(
        openedFile: _readme,
        bytes: _bytes('x'),
        message: 'edit',
        expectedHeadSha: kBrowserHeadCommit,
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure, RepoOpFailure.branchChanged);
      expect(api.createBlobCalls, 0);
      expect(api.createTreeCalls, 0);
      expect(api.updateRefCalls, 0);
      await _settle(controller);
      // The listing was reloaded on the new head.
      expect(controller.debugState.headCommitSha, 'head_other');
    });

    test('a push between check and ref update is never overwritten',
        () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      // Not a fast-forward: GitHub answers 422 to the non-forced ref update.
      api.updateRefError = const GitHubApiException(
        'Update is not a fast forward',
        statusCode: 422,
      );

      final result = await controller.saveFileEdit(
        openedFile: _readme,
        bytes: _bytes('x'),
        message: 'edit',
        expectedHeadSha: kBrowserHeadCommit,
      );

      expect(result.failure, RepoOpFailure.branchChanged);
      expect(controller.debugState.undo, isNull);
    });

    test('a protected branch is reported as such', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      api.updateRefError = const GitHubApiException(
        'Protected branch update failed for refs/heads/main',
        statusCode: 403,
      );

      final result = await controller.saveFileEdit(
        openedFile: _readme,
        bytes: _bytes('x'),
        message: 'edit',
        expectedHeadSha: kBrowserHeadCommit,
      );

      expect(result.failure, RepoOpFailure.protectedBranch);
      expect(controller.debugState.undo, isNull);
    });

    test('no write access: refused with a permission failure', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api, canPush: false);

      final result = await controller.saveFileEdit(
        openedFile: _readme,
        bytes: _bytes('x'),
        message: 'edit',
        expectedHeadSha: kBrowserHeadCommit,
      );

      expect(result.failure, RepoOpFailure.permission);
      expect(api.createBlobCalls, 0);
    });

    test('content above the 1 MB limit never reaches the network', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final result = await controller.saveFileEdit(
        openedFile: _readme,
        bytes: Uint8List(RepoEditGuard.maxEditableBytes + 1),
        message: 'edit',
        expectedHeadSha: kBrowserHeadCommit,
      );

      expect(result.failure, RepoOpFailure.invalid);
      expect(api.createBlobCalls, 0);
      expect(api.createCommitCalls, 0);
    });

    test('an empty commit message is refused', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final result = await controller.saveFileEdit(
        openedFile: _readme,
        bytes: _bytes('x'),
        message: '   ',
        expectedHeadSha: kBrowserHeadCommit,
      );

      expect(result.failure, RepoOpFailure.invalid);
      expect(api.createBlobCalls, 0);
    });

    test('a file deleted remotely cannot be saved over', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      // Same head (so the expected-head guard passes) but the file is gone.
      api.files = [
        for (final f in defaultBrowserFiles())
          if (f.path != 'README.md') f,
      ];

      final result = await controller.saveFileEdit(
        openedFile: _readme,
        bytes: _bytes('x'),
        message: 'edit',
        expectedHeadSha: kBrowserHeadCommit,
      );

      expect(result.failure, RepoOpFailure.invalid);
      expect(api.createCommitCalls, 0);
    });

    test('a symlink is never rewritten from the editor', () async {
      final api = BrowserFakeApi(
        files: const [
          RemoteTreeBlob(
            path: 'link',
            sha: 'sha_link',
            mode: '120000',
            size: 6,
          ),
        ],
      );
      final controller = await _loaded(api);

      final result = await controller.saveFileEdit(
        openedFile: const RepoFileRef(
          path: 'link',
          sha: 'sha_link',
          size: 6,
          mode: '120000',
        ),
        bytes: _bytes('other'),
        message: 'edit',
        expectedHeadSha: kBrowserHeadCommit,
      );

      expect(result.failure, RepoOpFailure.invalid);
      expect(api.createCommitCalls, 0);
    });
  });

  group('RepoEditGuard', () {
    RepoFileContent text({
      int size = 10,
      String mode = '100644',
      String? body = 'hello',
    }) =>
        RepoFileContent.fromBytes(
          RepoFileRef(path: 'a.txt', sha: 's', size: size, mode: mode),
          Uint8List.fromList((body ?? '').codeUnits),
        );

    test('plain text with push access is editable', () {
      expect(
        RepoEditGuard.whyNotEditable(text(), canPush: true),
        isNull,
      );
    });

    test('no push access, symlinks and oversized files are refused', () {
      expect(
        RepoEditGuard.whyNotEditable(text(), canPush: false),
        isNotNull,
      );
      expect(
        RepoEditGuard.whyNotEditable(text(mode: '120000'), canPush: true),
        isNotNull,
      );
      expect(
        RepoEditGuard.whyNotEditable(
          text(size: RepoEditGuard.maxEditableBytes + 1),
          canPush: true,
        ),
        isNotNull,
      );
    });

    test('binary content is refused', () {
      final binary = RepoFileContent.fromBytes(
        const RepoFileRef(path: 'a.bin', sha: 's', size: 4),
        Uint8List.fromList([0, 1, 2, 0]),
      );
      expect(RepoEditGuard.whyNotEditable(binary, canPush: true), isNotNull);
    });
  });
}
