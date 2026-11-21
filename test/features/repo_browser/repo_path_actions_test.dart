import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/core/network/github_api_client.dart';
import 'package:github_nexus/features/repo_browser/domain/remote_tree_entry.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_op_result.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_path_change_preview.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_undo_info.dart';
import 'package:github_nexus/features/repo_browser/presentation/repo_browser_controller.dart';
import 'support/browser_fakes.dart';

/// Phase 8B controller tests: move, rename and download of the selection.
/// (The delete flow is covered by `repo_delete_flow_test.dart`.)

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

List<String> _names(RepoBrowserController controller) =>
    controller.debugState.entries.map((e) => e.name).toList();

RemoteTreeEntry _entry(RepoBrowserController controller, String name) =>
    controller.debugState.entries.firstWhere((e) => e.name == name);

void _select(RepoBrowserController controller, List<String> names) {
  for (final name in names) {
    controller.toggleSelection(_entry(controller, name));
  }
}

/// Tree entries of the single `createTree` call, keyed by path.
Map<String, String?> _treeEntries(BrowserFakeApi api) => {
      for (final entry in api.treeCalls.single) entry.path: entry.blobSha,
    };

class _OfflineBlobApi extends BrowserFakeApi {
  @override
  Future<Uint8List> fetchFileBlob({
    required String token,
    required String owner,
    required String repo,
    required String blobSha,
    CancelToken? cancelToken,
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/blob'),
      type: DioExceptionType.connectionError,
    );
  }
}

void main() {
  group('move', () {
    test('a file moves into another folder in ONE commit, nothing re-uploaded',
        () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);

      final preview = await controller.previewMoveSelection('docs');
      expect(preview.isSuccess, isTrue);
      expect(preview.value!.kind, RepoPathChangeKind.move);
      expect(
        preview.value!.plan.renamedPaths,
        [(from: 'README.md', to: 'docs/README.md')],
      );
      // The preview wrote nothing.
      expect(api.createTreeCalls, 0);
      expect(api.updateRefCalls, 0);

      final result = await controller.moveSelection(
        destinationFolder: 'docs',
        message: 'move readme',
      );

      expect(result.isSuccess, isTrue);
      expect(api.createBlobCalls, 0);
      expect(api.createTreeCalls, 1);
      expect(api.createCommitCalls, 1);
      expect(api.updateRefCalls, 1);
      expect(api.commitMessages.single, 'move readme');

      final entries = _treeEntries(api);
      expect(entries['docs/README.md'], 'sha_readme');
      expect(entries.containsKey('README.md'), isTrue);
      expect(entries['README.md'], isNull);
    });

    test('the listing reloads and the undo bar describes the move', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);

      await controller.moveSelection(
        destinationFolder: 'docs',
        message: 'm',
      );
      await _settle(controller);

      final state = controller.debugState;
      expect(_names(controller), isNot(contains('README.md')));
      expect(state.selectedPaths, isEmpty);
      expect(state.undo?.kind, RepoUndoKind.move);
      expect(state.undo?.summary, 'تم نقل "README.md"');

      await controller.openFolder('docs');
      await _settle(controller);
      expect(_names(controller), contains('README.md'));
    });

    test('a whole folder moves and the summary counts its files', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['lib']);

      final result = await controller.moveSelection(
        destinationFolder: 'docs',
        message: 'm',
      );
      await _settle(controller);

      expect(result.isSuccess, isTrue);
      expect(api.createTreeCalls, 1);
      expect(api.createBlobCalls, 0);
      final entries = _treeEntries(api);
      expect(entries['docs/lib/main.dart'], 'sha_main');
      expect(entries['docs/lib/utils/a.dart'], 'sha_a');
      expect(entries['docs/lib/utils/b.dart'], 'sha_b');
      expect(controller.debugState.undo?.summary, 'تم نقل "lib" (3 ملفات)');

      await controller.openFolder('docs');
      await _settle(controller);
      expect(_names(controller), contains('lib'));
    });

    test('several items move together into the repository root', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      await controller.openFolder('lib');
      await _settle(controller);
      _select(controller, ['main.dart', 'utils']);

      final result = await controller.moveSelection(
        destinationFolder: '',
        message: 'm',
      );
      await _settle(controller);

      expect(result.isSuccess, isTrue);
      expect(api.createTreeCalls, 1);
      final entries = _treeEntries(api);
      expect(entries['main.dart'], 'sha_main');
      expect(entries['utils/a.dart'], 'sha_a');
      expect(entries['lib/main.dart'], isNull);
      expect(controller.debugState.undo?.summary, startsWith('تم نقل عنصران'));
    });

    test('a folder cannot go inside itself, nor stay where it is', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['lib']);

      final inside = await controller.previewMoveSelection('lib/utils');
      expect(inside.failure, RepoOpFailure.invalid);
      expect(inside.message, 'لا يمكن نقل مجلد إلى داخل نفسه.');

      final onto = await controller.previewMoveSelection('lib');
      expect(onto.failure, RepoOpFailure.invalid);
      expect(onto.message, 'لا يمكن نقل مجلد إلى داخل نفسه.');

      final same = await controller.previewMoveSelection('');
      expect(same.failure, RepoOpFailure.invalid);
      expect(same.message, 'اختر مجلداً مختلفاً عن المجلد الحالي.');

      expect(api.createTreeCalls, 0);
      expect(controller.debugState.isMutating, isFalse);
    });

    test('a name already used at the destination is refused before writing',
        () async {
      final api = BrowserFakeApi(
        files: [
          ...defaultBrowserFiles(),
          const RemoteTreeBlob(
            path: 'docs/README.md',
            sha: 'sha_other',
            mode: '100644',
            size: 3,
          ),
        ],
      );
      final controller = await _loaded(api);
      _select(controller, ['README.md']);

      final preview = await controller.previewMoveSelection('docs');
      expect(preview.failure, RepoOpFailure.invalid);
      expect(preview.message, contains('docs/README.md'));

      final result = await controller.moveSelection(
        destinationFolder: 'docs',
        message: 'm',
      );
      expect(result.failure, RepoOpFailure.invalid);
      expect(api.createTreeCalls, 0);
      expect(api.updateRefCalls, 0);
    });

    test('an invalid destination name is refused locally', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);

      final result = await controller.previewMoveSelection('docs//x');

      expect(result.failure, RepoOpFailure.invalid);
      expect(api.createTreeCalls, 0);
    });

    test('the commit message is required', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);

      final result = await controller.moveSelection(
        destinationFolder: 'docs',
        message: '   ',
      );

      expect(result.failure, RepoOpFailure.invalid);
      expect(api.createTreeCalls, 0);
    });

    test('a moved branch aborts before any write and reloads the listing',
        () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);
      api.head = const BranchHeadRef(
        commitSha: 'someone_else',
        treeSha: 'tree_other',
      );

      final result = await controller.moveSelection(
        destinationFolder: 'docs',
        message: 'm',
      );

      expect(result.failure, RepoOpFailure.branchChanged);
      expect(api.createTreeCalls, 0);
      expect(controller.debugState.headCommitSha, 'someone_else');
      expect(controller.debugState.isMutating, isFalse);
      expect(controller.debugState.undo, isNull);
    });

    test('undo brings the moved items back to where they were', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);
      await controller.moveSelection(destinationFolder: 'docs', message: 'm');
      await _settle(controller);
      expect(_names(controller), isNot(contains('README.md')));

      final undo = await controller.undoLastChange();
      await _settle(controller);

      expect(undo.isSuccess, isTrue);
      expect(api.commitMessages.last, startsWith('Revert "'));
      expect(_names(controller), contains('README.md'));
      expect(controller.debugState.undo, isNull);
    });
  });

  group('rename', () {
    test('a file keeps its content: new path, same blob, old path removed',
        () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);

      final result = await controller.renameSelected(
        newName: 'GUIDE.md',
        message: 'rename readme',
      );
      await _settle(controller);

      expect(result.isSuccess, isTrue);
      expect(api.createBlobCalls, 0);
      expect(api.createTreeCalls, 1);
      expect(api.commitMessages.single, 'rename readme');
      final entries = _treeEntries(api);
      expect(entries['GUIDE.md'], 'sha_readme');
      expect(entries['README.md'], isNull);

      expect(_names(controller), contains('GUIDE.md'));
      expect(_names(controller), isNot(contains('README.md')));
      final undo = controller.debugState.undo;
      expect(undo?.kind, RepoUndoKind.rename);
      expect(undo?.summary, 'تمت إعادة تسمية "README.md" إلى "GUIDE.md"');
    });

    test('a folder rename previews every file whose path changes', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['lib']);

      final preview = await controller.previewRenameSelected('src');

      expect(preview.isSuccess, isTrue);
      expect(preview.value!.kind, RepoPathChangeKind.rename);
      expect(preview.value!.totalFileCount, 3);
      expect(preview.value!.defaultMessage, 'Nexus: rename lib to src');
      expect(api.createTreeCalls, 0);

      final result = await controller.renameSelected(
        newName: 'src',
        message: 'rename lib',
      );
      await _settle(controller);

      expect(result.isSuccess, isTrue);
      expect(api.createTreeCalls, 1);
      final entries = _treeEntries(api);
      expect(entries['src/main.dart'], 'sha_main');
      expect(entries['src/utils/b.dart'], 'sha_b');
      expect(
        controller.debugState.undo?.summary,
        'تمت إعادة تسمية "lib" إلى "src" (3 ملفات)',
      );
      expect(_names(controller), contains('src'));
      expect(_names(controller), isNot(contains('lib')));
    });

    test('Arabic and spaced names inside a sub-folder', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      await controller.openFolder('docs');
      await _settle(controller);
      _select(controller, ['دليل المستخدم.md']);

      final result = await controller.renameSelected(
        newName: 'دليل جديد.md',
        message: 'rename guide',
      );
      await _settle(controller);

      expect(result.isSuccess, isTrue);
      final entries = _treeEntries(api);
      expect(entries['docs/دليل جديد.md'], 'sha_guide');
      expect(entries['docs/دليل المستخدم.md'], isNull);
      expect(controller.debugState.path, 'docs');
      expect(_names(controller), ['دليل جديد.md']);
    });

    test('changing only the letter case is a real rename', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);

      final result = await controller.renameSelected(
        newName: 'readme.md',
        message: 'm',
      );

      expect(result.isSuccess, isTrue);
      final entries = _treeEntries(api);
      expect(entries['readme.md'], 'sha_readme');
      expect(entries['README.md'], isNull);
    });

    test('invalid names are refused before any request', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);

      Future<String?> messageFor(String name) async {
        final result = await controller.previewRenameSelected(name);
        expect(result.failure, RepoOpFailure.invalid, reason: name);
        return result.message;
      }

      expect(await messageFor(''), 'أدخل الاسم الجديد.');
      expect(await messageFor('   '), 'أدخل الاسم الجديد.');
      expect(
        await messageFor('a/b.md'),
        'أدخل الاسم فقط بدون "/". لنقل العنصر استخدم زر النقل.',
      );
      expect(await messageFor('README.md'), 'الاسم الجديد مطابق للاسم الحالي.');
      expect(await messageFor('..'), isNotEmpty);
      expect(await messageFor('.git'), isNotEmpty);
      expect(api.createTreeCalls, 0);
    });

    test('exactly one entry must be selected', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final none = await controller.previewRenameSelected('x');
      expect(none.failure, RepoOpFailure.invalid);

      _select(controller, ['README.md', 'app.zip']);
      final two = await controller.renameSelected(newName: 'x', message: 'm');
      expect(two.failure, RepoOpFailure.invalid);
      expect(two.message, 'حدد عنصراً واحداً فقط لإعادة تسميته.');
      expect(api.createTreeCalls, 0);
    });

    test('an existing sibling name is refused before writing', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);

      final result = await controller.renameSelected(
        newName: 'app.zip',
        message: 'm',
      );

      expect(result.failure, RepoOpFailure.invalid);
      expect(api.createTreeCalls, 0);
      expect(api.updateRefCalls, 0);
    });
  });

  group('download', () {
    test('a single file is returned as it is, nothing is written', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);

      final result = await controller.prepareDownload();

      expect(result.isSuccess, isTrue);
      final payload = result.value!;
      expect(payload.isZip, isFalse);
      expect(payload.fileName, 'README.md');
      expect(payload.fileCount, 1);
      expect(utf8.decode(payload.bytes), 'content of sha_readme');
      expect(api.createTreeCalls, 0);
      expect(api.updateRefCalls, 0);
      expect(controller.debugState.isMutating, isFalse);
      // The selection survives so the user can retry or pick another action.
      expect(controller.debugState.selectedPaths, {'README.md'});
    });

    test('a folder becomes a ZIP named after it, with relative paths',
        () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['lib']);

      final result = await controller.prepareDownload();

      expect(result.isSuccess, isTrue);
      final payload = result.value!;
      expect(payload.isZip, isTrue);
      expect(payload.fileName, 'lib.zip');
      expect(payload.fileCount, 3);
      expect(payload.bytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
      final raw = String.fromCharCodes(payload.bytes);
      expect(raw, contains('lib/main.dart'));
      expect(raw, contains('lib/utils/a.dart'));
      expect(raw, contains('lib/utils/b.dart'));
      expect(api.blobReads.toSet(), {'sha_main', 'sha_a', 'sha_b'});
    });

    test('zip paths are relative to the folder being browsed', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      await controller.openFolder('lib');
      await _settle(controller);
      _select(controller, ['utils']);

      final payload = (await controller.prepareDownload()).value!;

      final raw = String.fromCharCodes(payload.bytes);
      expect(payload.fileName, 'utils.zip');
      expect(raw, contains('utils/a.dart'));
      expect(raw, isNot(contains('lib/utils')));
    });

    test('several items are zipped under the repository name', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md', 'lib']);

      final payload = (await controller.prepareDownload()).value!;

      expect(payload.isZip, isTrue);
      expect(payload.fileName, 'nexus-demo-selection.zip');
      expect(payload.fileCount, 4);
      expect(String.fromCharCodes(payload.bytes), contains('README.md'));
    });

    test('Arabic file names are stored as UTF-8', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);
      _select(controller, ['docs']);

      final payload = (await controller.prepareDownload()).value!;

      expect(payload.fileName, 'docs.zip');
      expect(utf8.decode(payload.bytes, allowMalformed: true),
          contains('docs/دليل المستخدم.md'));
    });

    test('a selection above the size limit is refused before any download',
        () async {
      final api = BrowserFakeApi(
        files: [
          const RemoteTreeBlob(
            path: 'big.bin',
            sha: 'sha_big',
            mode: '100644',
            size: 60 * 1024 * 1024,
          ),
        ],
      );
      final controller = await _loaded(api);
      _select(controller, ['big.bin']);

      final result = await controller.prepareDownload();

      expect(result.failure, RepoOpFailure.invalid);
      expect(result.message, contains('الحد المسموح'));
      expect(api.blobReads, isEmpty);
    });

    test('without a selection there is nothing to download', () async {
      final api = BrowserFakeApi();
      final controller = await _loaded(api);

      final result = await controller.prepareDownload();

      expect(result.failure, RepoOpFailure.invalid);
      expect(api.blobReads, isEmpty);
    });

    test('a connection problem is a network failure and keeps the selection',
        () async {
      final api = _OfflineBlobApi();
      final controller = await _loaded(api);
      _select(controller, ['README.md']);

      final result = await controller.prepareDownload();

      expect(result.failure, RepoOpFailure.network);
      expect(controller.debugState.isMutating, isFalse);
      expect(controller.debugState.selectedPaths, {'README.md'});
    });
  });
}
