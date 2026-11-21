import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/core/network/github_api_client.dart';
import 'package:github_nexus/features/repo_browser/domain/remote_tree_entry.dart';
import 'package:github_nexus/features/repo_browser/presentation/repo_browser_controller.dart';
import 'package:github_nexus/features/repo_browser/presentation/repo_browser_screen.dart';
import 'package:github_nexus/features/repos/presentation/repos_controller.dart';
import 'support/browser_fakes.dart';

/// Phase 9 widget tests: viewer -> editor -> conflict check -> diff -> commit.
/// The controller logic is covered by `repo_file_edit_flow_test.dart`.

Widget _app(BrowserFakeApi api, {bool canPush = true}) {
  return ProviderScope(
    overrides: [
      repoBrowserControllerProvider.overrideWith(
        (ref) => RepoBrowserController(
          api: api,
          token: 't',
          target: browserTarget(canPush: canPush),
        ),
      ),
      reposControllerProvider.overrideWith(
        (ref) => ReposController(api: api, token: null),
      ),
    ],
    child: const MaterialApp(home: RepoBrowserScreen()),
  );
}

/// Haptics / clipboard go through the platform channel (no handler in tests).
void _mockPlatform(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });
}

void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<BrowserFakeApi> _pumpBrowser(
  WidgetTester tester, {
  bool canPush = true,
}) async {
  _mockPlatform(tester);
  _tallScreen(tester);
  final api = BrowserFakeApi();
  await tester.pumpWidget(_app(api, canPush: canPush));
  await tester.pumpAndSettle();
  return api;
}

/// Unmounts the screen so the controller cancels its undo timer.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

Future<void> _openViewer(WidgetTester tester) async {
  await tester.tap(find.text('README.md'));
  await tester.pumpAndSettle();
}

Future<void> _openEditor(WidgetTester tester) async {
  await _openViewer(tester);
  await tester.tap(find.byKey(const ValueKey('viewer_edit')));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey('code_editor_field')),
    text,
  );
  await tester.pump();
}

Future<void> _pressSave(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('editor_save')));
  await tester.pumpAndSettle();
}

const _editorField = ValueKey('code_editor_field');

void main() {
  group('opening the editor', () {
    testWidgets('the edit button opens the editor with the file content',
        (tester) async {
      await _pumpBrowser(tester);
      await _openEditor(tester);

      expect(find.byKey(_editorField), findsOneWidget);
      expect(find.text('content of sha_readme'), findsOneWidget);
      // Nothing changed yet: saving is disabled.
      final save = tester.widget<FilledButton>(
        find.byKey(const ValueKey('editor_save')),
      );
      expect(save.onPressed, isNull);

      await _unmount(tester);
    });

    testWidgets('without write access the editor is not opened',
        (tester) async {
      await _pumpBrowser(tester, canPush: false);
      await _openEditor(tester);

      expect(find.byKey(_editorField), findsNothing);
      expect(
        find.text('لا تملك صلاحية الكتابة في هذا المستودع.'),
        findsOneWidget,
      );

      await _unmount(tester);
    });

    testWidgets('a binary file has no edit button', (tester) async {
      await _pumpBrowser(tester);
      await tester.tap(find.text('app.zip'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('viewer_edit')), findsNothing);

      await _unmount(tester);
    });
  });

  group('saving', () {
    testWidgets('edit -> diff -> ONE commit -> undo bar', (tester) async {
      final api = await _pumpBrowser(tester);
      await _openEditor(tester);

      await _type(tester, 'edited text');
      final save = tester.widget<FilledButton>(
        find.byKey(const ValueKey('editor_save')),
      );
      expect(save.onPressed, isNotNull);
      await _pressSave(tester);

      // The diff dialog is shown BEFORE anything is written.
      expect(find.byKey(const ValueKey('diff_confirm')), findsOneWidget);
      expect(api.createCommitCalls, 0);

      await tester.tap(find.byKey(const ValueKey('diff_confirm')));
      await tester.pumpAndSettle();

      expect(api.createBlobCalls, 1);
      expect(api.createTreeCalls, 1);
      expect(api.createCommitCalls, 1);
      expect(api.updateRefCalls, 1);
      expect(api.commitMessages.single, 'Nexus: update README.md');
      // The editor closed; the viewer is back on the saved file.
      expect(find.byKey(_editorField), findsNothing);
      expect(find.byKey(const ValueKey('viewer_edit')), findsOneWidget);

      // Back on the browser the commit can be reverted.
      await tester.tap(find.byTooltip('رجوع'));
      await tester.pumpAndSettle();
      expect(find.text('تم حفظ التعديلات في "README.md"'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('undo_button')));
      await tester.pumpAndSettle();
      expect(api.createCommitCalls, 2);
      expect(api.commitMessages.last, startsWith('Revert "'));
      expect(find.text('تم التراجع عن تعديل الملف.'), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('cancelling the diff writes nothing and keeps the edits',
        (tester) async {
      final api = await _pumpBrowser(tester);
      await _openEditor(tester);

      await _type(tester, 'edited text');
      await _pressSave(tester);
      await tester.tap(find.byKey(const ValueKey('diff_cancel')));
      await tester.pumpAndSettle();

      expect(api.createBlobCalls, 0);
      expect(api.createCommitCalls, 0);
      expect(find.byKey(_editorField), findsOneWidget);
      expect(find.text('edited text'), findsOneWidget);

      await _unmount(tester);
    });
  });

  group('leaving with unsaved changes', () {
    testWidgets('back asks first; "continue editing" keeps the editor',
        (tester) async {
      final api = await _pumpBrowser(tester);
      await _openEditor(tester);
      await _type(tester, 'edited text');

      await tester.tap(find.byTooltip('رجوع'));
      await tester.pumpAndSettle();
      expect(find.text('تجاهل التعديلات غير المحفوظة؟'), findsOneWidget);

      await tester.tap(find.text('متابعة التحرير'));
      await tester.pumpAndSettle();
      expect(find.byKey(_editorField), findsOneWidget);

      await tester.tap(find.byTooltip('رجوع'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تجاهل والخروج'));
      await tester.pumpAndSettle();
      expect(find.byKey(_editorField), findsNothing);
      expect(api.createCommitCalls, 0);

      await _unmount(tester);
    });
  });

  group('branch conflicts', () {
    List<RemoteTreeBlob> filesWith(String path, String sha) => [
          for (final f in defaultBrowserFiles())
            if (f.path == path)
              RemoteTreeBlob(path: path, sha: sha, mode: f.mode, size: 40)
            else
              f,
        ];

    void moveHead(BrowserFakeApi api, List<RemoteTreeBlob> files) {
      api.head = const BranchHeadRef(
        commitSha: 'head_other',
        treeSha: 'tree_other',
      );
      api.files = files;
    }

    testWidgets('another file changed: warns, then saves on the latest head',
        (tester) async {
      final api = await _pumpBrowser(tester);
      await _openEditor(tester);
      await _type(tester, 'edited text');
      moveHead(api, filesWith('lib/main.dart', 'sha_main_v2'));

      await _pressSave(tester);
      expect(find.byKey(const ValueKey('conflict_continue_latest')),
          findsOneWidget);
      expect(find.text('تنبيه: الفرع تحرّك على GitHub'), findsOneWidget);
      expect(api.createCommitCalls, 0);

      await tester.tap(find.byKey(const ValueKey('conflict_continue_latest')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('diff_confirm')));
      await tester.pumpAndSettle();

      expect(api.createCommitCalls, 1);
      expect(api.head?.commitSha, 'commit_new_1');
      expect(find.byKey(_editorField), findsNothing);

      await _unmount(tester);
    });

    testWidgets('the same file changed: severe warning, nothing is written',
        (tester) async {
      final api = await _pumpBrowser(tester);
      await _openEditor(tester);
      await _type(tester, 'edited text');
      moveHead(api, filesWith('README.md', 'sha_readme_v2'));

      await _pressSave(tester);
      expect(find.text('تعارض: الملف تغيّر على GitHub'), findsOneWidget);

      // Copying the edits keeps the editor open and writes nothing.
      await tester.tap(find.byKey(const ValueKey('conflict_copy_edits')));
      await tester.pumpAndSettle();
      expect(find.byKey(_editorField), findsOneWidget);
      expect(find.text('edited text'), findsOneWidget);
      expect(api.createCommitCalls, 0);

      await _unmount(tester);
    });

    testWidgets('"reload latest" drops the edits and shows the new version',
        (tester) async {
      final api = await _pumpBrowser(tester);
      await _openEditor(tester);
      await _type(tester, 'edited text');
      moveHead(api, filesWith('README.md', 'sha_readme_v2'));

      await _pressSave(tester);
      await tester.tap(find.byKey(const ValueKey('conflict_reload')));
      await tester.pumpAndSettle();

      expect(find.byKey(_editorField), findsNothing);
      expect(api.createCommitCalls, 0);
      // The viewer now reads the newer blob.
      expect(api.blobReads, contains('sha_readme_v2'));

      await _unmount(tester);
    });
  });
}
