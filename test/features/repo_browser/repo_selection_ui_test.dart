import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/core/network/github_api_client.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_change_plan.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_delete_preview.dart';
import 'package:github_nexus/features/repo_browser/presentation/delete_confirm_dialog.dart';
import 'package:github_nexus/features/repo_browser/presentation/repo_browser_controller.dart';
import 'package:github_nexus/features/repo_browser/presentation/repo_browser_screen.dart';
import 'package:github_nexus/core/widgets/glass_panel.dart';
import 'package:github_nexus/features/repos/presentation/repos_controller.dart';
import 'support/browser_fakes.dart';

/// Phase 8 widget tests: selection mode, bottom bar, delete confirmation
/// dialog and the undo bar. The controller logic itself is covered by
/// `repo_delete_flow_test.dart`; move / rename / download flows are in
/// `repo_path_actions_ui_test.dart`.

Widget _app(BrowserFakeApi api) {
  return ProviderScope(
    overrides: [
      repoBrowserControllerProvider.overrideWith(
        (ref) => RepoBrowserController(
          api: api,
          token: 't',
          target: browserTarget(),
        ),
      ),
      reposControllerProvider.overrideWith(
        (ref) => ReposController(api: api, token: null),
      ),
    ],
    child: const MaterialApp(home: RepoBrowserScreen()),
  );
}

/// Haptics go through the platform channel, which has no handler in tests.
void _mockPlatform(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });
}

/// A tall screen so the whole dialog is visible without scrolling.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<BrowserFakeApi> _pumpScreen(WidgetTester tester) async {
  _mockPlatform(tester);
  _tallScreen(tester);
  final api = BrowserFakeApi();
  await tester.pumpWidget(_app(api));
  await tester.pumpAndSettle();
  return api;
}

Future<void> _longPress(WidgetTester tester, String name) async {
  await tester.longPress(find.text(name));
  await tester.pumpAndSettle();
}

InkWell _barInkWell(WidgetTester tester, String key) => tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(InkWell),
      ),
    );

/// Unmounts the screen so the controller cancels its undo timer.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

RepoDeletePreview _preview({
  List<String> folders = const ['lib'],
  List<String> files = const ['README.md'],
  List<String>? deleted,
}) {
  return RepoDeletePreview.build(
    plan: RepoChangePlan(
      addedPaths: const [],
      modifiedPaths: const [],
      deletedPaths: deleted ??
          const [
            'lib/main.dart',
            'lib/utils/a.dart',
            'lib/utils/b.dart',
            'README.md',
          ],
      renamedPaths: const [],
      uploadCount: 0,
    ),
    folderPaths: folders,
    filePaths: files,
  );
}

/// Pumps a page whose button opens the dialog; the approved message (or
/// `null`) lands in the returned holder once the dialog closes.
Future<({List<String?> results})> _pumpDialogHost(
  WidgetTester tester,
  RepoDeletePreview preview,
) async {
  _tallScreen(tester);
  final results = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final message = await showDeleteConfirmDialog(
                  context,
                  target: browserTarget(),
                  preview: preview,
                );
                results.add(message);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (results: results);
}

void main() {
  group('selection mode', () {
    testWidgets('a long press selects, shows the counter and the action bar',
        (tester) async {
      await _pumpScreen(tester);

      expect(find.byKey(const ValueKey('selection_delete')), findsNothing);

      await _longPress(tester, 'lib');

      expect(find.text('1 محدد'), findsOneWidget);
      expect(find.byKey(const ValueKey('selection_delete')), findsOneWidget);
      // The normal header (search / refresh) is replaced by the selection one.
      expect(find.byTooltip('بحث'), findsNothing);
      expect(find.byTooltip('إلغاء التحديد'), findsOneWidget);
      // Selecting does not open the folder.
      expect(find.text('main.dart'), findsNothing);
    });

    testWidgets('delete, move, rename and download are all enabled for one item',
        (tester) async {
      await _pumpScreen(tester);
      await _longPress(tester, 'lib');

      expect(_barInkWell(tester, 'selection_delete').onTap, isNotNull);
      expect(_barInkWell(tester, 'selection_move').onTap, isNotNull);
      expect(_barInkWell(tester, 'selection_rename').onTap, isNotNull);
      expect(_barInkWell(tester, 'selection_download').onTap, isNotNull);
    });

    testWidgets('rename needs exactly one selected item', (tester) async {
      await _pumpScreen(tester);
      await _longPress(tester, 'lib');
      await tester.tap(find.text('README.md'));
      await tester.pumpAndSettle();

      expect(find.text('2 محدد'), findsOneWidget);
      expect(_barInkWell(tester, 'selection_rename').onTap, isNull);
      expect(_barInkWell(tester, 'selection_move').onTap, isNotNull);
      expect(_barInkWell(tester, 'selection_download').onTap, isNotNull);
    });

    testWidgets('while selecting, a tap toggles instead of opening',
        (tester) async {
      await _pumpScreen(tester);
      await _longPress(tester, 'lib');

      await tester.tap(find.text('docs'));
      await tester.pumpAndSettle();
      expect(find.text('2 محدد'), findsOneWidget);
      expect(find.text('main.dart'), findsNothing);

      // Tapping a selected row deselects it.
      await tester.tap(find.text('docs'));
      await tester.pumpAndSettle();
      expect(find.text('1 محدد'), findsOneWidget);

      // Deselecting the last one leaves selection mode.
      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('selection_delete')), findsNothing);
      expect(find.byTooltip('بحث'), findsOneWidget);
    });

    testWidgets('select all counts every entry and then disables itself',
        (tester) async {
      await _pumpScreen(tester);
      await _longPress(tester, 'lib');

      await tester.tap(find.text('تحديد الكل'));
      await tester.pumpAndSettle();

      expect(find.text('5 محدد'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('تحديد الكل'),
          matching: find.byWidgetPredicate((w) => w is TextButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('the close button cancels the selection', (tester) async {
      await _pumpScreen(tester);
      await _longPress(tester, 'lib');

      await tester.tap(find.byTooltip('إلغاء التحديد'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('selection_delete')), findsNothing);
      expect(find.text('lib'), findsOneWidget);
    });

    testWidgets('system back closes the selection before anything else',
        (tester) async {
      await _pumpScreen(tester);
      await _longPress(tester, 'lib');
      expect(find.text('1 محدد'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('selection_delete')), findsNothing);
      // The screen itself is still open.
      expect(find.byType(RepoBrowserScreen), findsOneWidget);
      expect(find.text('abdullah/nexus-demo'), findsOneWidget);
    });
  });

  group('delete confirmation dialog', () {
    testWidgets('shows counters, folder warning, samples and the message',
        (tester) async {
      await _pumpDialogHost(tester, _preview());

      expect(find.text('تأكيد الحذف'), findsOneWidget);
      expect(find.text('abdullah/nexus-demo:main'), findsOneWidget);

      final items = find.byKey(const ValueKey('delete_items_count'));
      final files = find.byKey(const ValueKey('delete_files_count'));
      expect(
        find.descendant(of: items, matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: files, matching: find.text('4')),
        findsOneWidget,
      );

      expect(find.byKey(const ValueKey('delete_folder_warning')), findsOneWidget);
      expect(find.textContaining('3 ملفات داخل مجلد واحد'), findsOneWidget);

      expect(find.text('− lib/  (3)'), findsOneWidget);
      expect(find.text('− README.md'), findsOneWidget);

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('delete_commit_message')),
      );
      expect(field.controller!.text, 'Nexus: delete lib, README.md');
    });

    testWidgets('a files-only selection has no folder warning', (tester) async {
      await _pumpDialogHost(
        tester,
        _preview(
          folders: const [],
          files: const ['README.md', 'app.zip'],
          deleted: const ['README.md', 'app.zip'],
        ),
      );

      expect(find.byKey(const ValueKey('delete_folder_warning')), findsNothing);
    });

    testWidgets('long selections list a few examples and count the rest',
        (tester) async {
      final files = [for (var i = 1; i <= 8; i++) 'f$i.txt'];
      await _pumpDialogHost(
        tester,
        _preview(
          folders: const ['lib'],
          files: files,
          deleted: ['lib/main.dart', 'lib/a.dart', 'lib/b.dart', ...files],
        ),
      );

      // 9 selected items, 6 shown, 3 hidden.
      expect(find.text('و3 عناصر أخرى...'), findsOneWidget);
      expect(find.text('− f5.txt'), findsOneWidget);
      expect(find.text('− f6.txt'), findsNothing);
    });

    testWidgets('confirming returns the edited commit message', (tester) async {
      final host = await _pumpDialogHost(tester, _preview());

      await tester.enterText(
        find.byKey(const ValueKey('delete_commit_message')),
        '  حذف الملفات القديمة  ',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('delete_confirm')));
      await tester.pumpAndSettle();

      expect(host.results, ['حذف الملفات القديمة']);
      expect(find.text('تأكيد الحذف'), findsNothing);
    });

    testWidgets('cancel returns null', (tester) async {
      final host = await _pumpDialogHost(tester, _preview());

      await tester.tap(find.byKey(const ValueKey('delete_cancel')));
      await tester.pumpAndSettle();

      expect(host.results, [null]);
      expect(find.text('تأكيد الحذف'), findsNothing);
    });

    testWidgets('a blank message disables the confirm button', (tester) async {
      await _pumpDialogHost(tester, _preview());

      NexusGradientButton confirm() => tester.widget<NexusGradientButton>(
            find.byKey(const ValueKey('delete_confirm')),
          );
      expect(confirm().onPressed, isNotNull);

      await tester.enterText(
        find.byKey(const ValueKey('delete_commit_message')),
        '   ',
      );
      await tester.pump();
      expect(confirm().onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('delete_commit_message')),
        'x',
      );
      await tester.pump();
      expect(confirm().onPressed, isNotNull);
    });
  });

  group('delete flow on the screen', () {
    testWidgets('delete a folder and two files in one commit, then undo',
        (tester) async {
      final api = await _pumpScreen(tester);

      await _longPress(tester, 'lib');
      await tester.tap(find.text('README.md'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('app.zip'));
      await tester.pumpAndSettle();
      expect(find.text('3 محدد'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('selection_delete')));
      await tester.pumpAndSettle();

      // The preview wrote nothing.
      expect(find.text('تأكيد الحذف'), findsOneWidget);
      expect(api.createCommitCalls, 0);
      expect(api.updateRefCalls, 0);

      await tester.enterText(
        find.byKey(const ValueKey('delete_commit_message')),
        'تنظيف المستودع',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('delete_confirm')));
      await tester.pumpAndSettle();

      expect(api.createTreeCalls, 1);
      expect(api.createCommitCalls, 1);
      expect(api.updateRefCalls, 1);
      expect(api.commitMessages.single, 'تنظيف المستودع');

      expect(find.text('lib'), findsNothing);
      expect(find.text('README.md'), findsNothing);
      expect(find.text('app.zip'), findsNothing);
      expect(find.text('docs'), findsOneWidget);
      expect(find.text('scripts'), findsOneWidget);
      // Selection mode is over and the undo bar offers the way back.
      expect(find.byKey(const ValueKey('selection_delete')), findsNothing);
      expect(find.text('تم حذف 3 عناصر (5 ملفات)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('undo_button')));
      await tester.pumpAndSettle();

      expect(api.createCommitCalls, 2);
      expect(api.commitMessages.last, startsWith('Revert "'));
      expect(find.text('lib'), findsOneWidget);
      expect(find.text('README.md'), findsOneWidget);
      expect(find.text('app.zip'), findsOneWidget);
      expect(find.byKey(const ValueKey('undo_button')), findsNothing);
      expect(find.text('تم التراجع واستعادة العناصر المحذوفة.'), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('cancelling the dialog keeps the selection and writes nothing',
        (tester) async {
      final api = await _pumpScreen(tester);

      await _longPress(tester, 'lib');
      await tester.tap(find.byKey(const ValueKey('selection_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete_cancel')));
      await tester.pumpAndSettle();

      expect(api.createCommitCalls, 0);
      expect(find.text('1 محدد'), findsOneWidget);
      expect(find.byKey(const ValueKey('selection_delete')), findsOneWidget);
      expect(find.text('lib'), findsOneWidget);
    });

    testWidgets('the undo bar can be dismissed without reverting',
        (tester) async {
      final api = await _pumpScreen(tester);

      await _longPress(tester, 'app.zip');
      await tester.tap(find.byKey(const ValueKey('selection_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete_confirm')));
      await tester.pumpAndSettle();
      expect(find.text('تم حذف عنصر واحد'), findsOneWidget);

      await tester.tap(find.byTooltip('إخفاء'));
      await tester.pumpAndSettle();

      expect(find.text('تم حذف عنصر واحد'), findsNothing);
      expect(find.text('app.zip'), findsNothing);
      expect(api.createCommitCalls, 1);

      await _unmount(tester);
    });

    testWidgets('a branch that moved aborts the delete and reloads',
        (tester) async {
      final api = await _pumpScreen(tester);

      await _longPress(tester, 'app.zip');
      await tester.tap(find.byKey(const ValueKey('selection_delete')));
      await tester.pumpAndSettle();

      // Somebody pushes while the dialog is open.
      api.head = const BranchHeadRef(
        commitSha: 'someone_elses_commit',
        treeSha: kBrowserRootTree,
      );
      await tester.tap(find.byKey(const ValueKey('delete_confirm')));
      await tester.pumpAndSettle();

      expect(api.createCommitCalls, 0);
      expect(api.updateRefCalls, 0);
      // The failure toast (now a top banner) explains the moved branch.
      expect(
        find.textContaining('تغيّر الفرع على GitHub'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('undo_button')), findsNothing);
      // The listing was reloaded against the new head and nothing was lost.
      expect(find.text('app.zip'), findsOneWidget);
      expect(find.textContaining('HEAD someone'), findsOneWidget);

      await _unmount(tester);
    });
  });
}
