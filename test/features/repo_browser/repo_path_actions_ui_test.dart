import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/features/repo_browser/data/repo_download_saver.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_download_payload.dart';
import 'package:github_nexus/features/repo_browser/presentation/repo_browser_controller.dart';
import 'package:github_nexus/features/repo_browser/presentation/repo_browser_screen.dart';
import 'package:github_nexus/features/repos/presentation/repos_controller.dart';
import 'support/browser_fakes.dart';

/// Phase 8B widget tests: move, rename and download from the selection bar.
/// The controller logic is covered by `repo_path_actions_test.dart`.

class _FakeSaver implements RepoDownloadSaver {
  RepoDownloadPayload? saved;

  /// What the "save as" dialog answers (`null` = the user cancelled).
  String? answer = '/storage/emulated/0/Download/saved';

  @override
  Future<String?> save(RepoDownloadPayload payload) async {
    saved = payload;
    return answer;
  }
}

Widget _app(BrowserFakeApi api, _FakeSaver saver) {
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
      repoDownloadSaverProvider.overrideWithValue(saver),
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

/// A tall screen so dialogs and sheets are fully visible.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<BrowserFakeApi> _pumpScreen(WidgetTester tester, _FakeSaver saver) async {
  _mockPlatform(tester);
  _tallScreen(tester);
  final api = BrowserFakeApi();
  await tester.pumpWidget(_app(api, saver));
  await tester.pumpAndSettle();
  return api;
}

Future<void> _longPress(WidgetTester tester, String name) async {
  await tester.longPress(find.text(name));
  await tester.pumpAndSettle();
}

/// Unmounts the screen so the controller cancels its undo timer.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  group('rename on the screen', () {
    testWidgets('a file is renamed in one commit, then undone', (tester) async {
      final api = await _pumpScreen(tester, _FakeSaver());

      await _longPress(tester, 'README.md');
      await tester.tap(find.byKey(const ValueKey('selection_rename')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('rename_name_field')),
        'GUIDE.md',
      );
      await tester.pump();
      // Nothing is written before the user confirms.
      expect(api.createCommitCalls, 0);

      await tester.tap(find.byKey(const ValueKey('rename_confirm')));
      await tester.pumpAndSettle();

      expect(api.createBlobCalls, 0);
      expect(api.createTreeCalls, 1);
      expect(api.createCommitCalls, 1);
      expect(api.updateRefCalls, 1);
      expect(api.commitMessages.single, 'Nexus: rename README.md to GUIDE.md');

      expect(find.text('GUIDE.md'), findsOneWidget);
      expect(find.text('README.md'), findsNothing);
      expect(find.byKey(const ValueKey('selection_delete')), findsNothing);
      expect(
        find.text('تمت إعادة تسمية "README.md" إلى "GUIDE.md"'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('undo_button')));
      await tester.pumpAndSettle();

      expect(api.createCommitCalls, 2);
      expect(api.commitMessages.last, startsWith('Revert "'));
      expect(find.text('README.md'), findsOneWidget);
      expect(find.text('GUIDE.md'), findsNothing);
      expect(find.text('تم التراجع عن إعادة التسمية.'), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('a folder rename is confirmed with the affected files first',
        (tester) async {
      final api = await _pumpScreen(tester, _FakeSaver());

      await _longPress(tester, 'lib');
      await tester.tap(find.byKey(const ValueKey('selection_rename')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('rename_name_field')),
        'src',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rename_confirm')));
      await tester.pumpAndSettle();

      // The preview dialog is up and still nothing was written.
      expect(find.text('تأكيد إعادة التسمية'), findsOneWidget);
      expect(api.createCommitCalls, 0);

      await tester.tap(find.byKey(const ValueKey('path_change_confirm')));
      await tester.pumpAndSettle();

      expect(api.createTreeCalls, 1);
      expect(api.createCommitCalls, 1);
      expect(api.commitMessages.single, 'Nexus: rename lib to src');
      expect(find.text('src'), findsOneWidget);
      expect(find.text('lib'), findsNothing);

      await _unmount(tester);
    });

    testWidgets('cancelling the dialog writes nothing and keeps the selection',
        (tester) async {
      final api = await _pumpScreen(tester, _FakeSaver());

      await _longPress(tester, 'README.md');
      await tester.tap(find.byKey(const ValueKey('selection_rename')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rename_cancel')));
      await tester.pumpAndSettle();

      expect(api.createCommitCalls, 0);
      expect(find.text('1 محدد'), findsOneWidget);
      expect(find.text('README.md'), findsOneWidget);
    });
  });

  group('move on the screen', () {
    testWidgets('pick a folder, confirm, and the file moves in one commit',
        (tester) async {
      final api = await _pumpScreen(tester, _FakeSaver());

      await _longPress(tester, 'README.md');
      await tester.tap(find.byKey(const ValueKey('selection_move')));
      await tester.pumpAndSettle();

      // Open `docs` inside the destination picker and choose it.
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('docs'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('move_select_destination')));
      await tester.pumpAndSettle();

      expect(find.text('تأكيد النقل'), findsOneWidget);
      expect(api.createCommitCalls, 0);

      await tester.tap(find.byKey(const ValueKey('path_change_confirm')));
      await tester.pumpAndSettle();

      expect(api.createBlobCalls, 0);
      expect(api.createTreeCalls, 1);
      expect(api.createCommitCalls, 1);
      expect(
        api.commitMessages.single,
        'Nexus: move README.md to docs/README.md',
      );
      expect(find.text('README.md'), findsNothing);
      expect(find.text('تم نقل "README.md"'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('undo_button')));
      await tester.pumpAndSettle();

      expect(find.text('README.md'), findsOneWidget);
      expect(
        find.text('تم التراجع عن النقل وإعادة العناصر إلى أماكنها.'),
        findsOneWidget,
      );

      await _unmount(tester);
    });

    testWidgets('closing the picker moves nothing', (tester) async {
      final api = await _pumpScreen(tester, _FakeSaver());

      await _longPress(tester, 'README.md');
      await tester.tap(find.byKey(const ValueKey('selection_move')));
      await tester.pumpAndSettle();
      // Dismiss the sheet by tapping the barrier.
      await tester.tapAt(const Offset(400, 20));
      await tester.pumpAndSettle();

      expect(api.createCommitCalls, 0);
      expect(find.text('1 محدد'), findsOneWidget);
    });
  });

  group('download on the screen', () {
    testWidgets('a file is handed to the saver and the selection ends',
        (tester) async {
      final saver = _FakeSaver();
      final api = await _pumpScreen(tester, saver);

      await _longPress(tester, 'README.md');
      await tester.tap(find.byKey(const ValueKey('selection_download')));
      await tester.pumpAndSettle();

      final saved = saver.saved;
      expect(saved, isNotNull);
      expect(saved!.fileName, 'README.md');
      expect(saved.isZip, isFalse);
      expect(saved.bytes, isA<Uint8List>());
      expect(find.text('تم حفظ README.md.'), findsOneWidget);
      expect(find.byKey(const ValueKey('selection_delete')), findsNothing);
      // Downloading never writes to the repository.
      expect(api.createCommitCalls, 0);
      expect(api.updateRefCalls, 0);
    });

    testWidgets('a folder is saved as a ZIP', (tester) async {
      final saver = _FakeSaver();
      await _pumpScreen(tester, saver);

      await _longPress(tester, 'lib');
      await tester.tap(find.byKey(const ValueKey('selection_download')));
      await tester.pumpAndSettle();

      expect(saver.saved?.fileName, 'lib.zip');
      expect(saver.saved?.isZip, isTrue);
      expect(saver.saved?.fileCount, 3);
      expect(find.text('تم حفظ lib.zip (3 ملفات).'), findsOneWidget);
    });

    testWidgets('cancelling the save dialog keeps the selection',
        (tester) async {
      final saver = _FakeSaver()..answer = null;
      await _pumpScreen(tester, saver);

      await _longPress(tester, 'README.md');
      await tester.tap(find.byKey(const ValueKey('selection_download')));
      await tester.pumpAndSettle();

      expect(saver.saved, isNotNull);
      expect(find.text('1 محدد'), findsOneWidget);
      expect(find.textContaining('تم حفظ'), findsNothing);
    });
  });
}
