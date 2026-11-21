import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/core/network/github_api_client.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_bookmarks.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_code_search.dart';
import 'package:github_nexus/features/repo_browser/data/repo_bookmarks_storage.dart';
import 'package:github_nexus/features/repo_browser/presentation/repo_bookmarks_controller.dart';
import 'package:github_nexus/features/repo_browser/presentation/repo_browser_controller.dart';
import 'package:github_nexus/features/repo_browser/presentation/repo_browser_screen.dart';
import 'package:github_nexus/features/repos/presentation/repos_controller.dart';
import 'support/browser_fakes.dart';

/// Phase 10 widget tests: the create/upload menu, favorites & recents, the
/// content-search mode and the protected-branch → pull-request flow.

class _MemoryBookmarksStore implements RepoBookmarksStore {
  RepoBookmarksState state = const RepoBookmarksState();

  @override
  Future<RepoBookmarksState> load() async => state;

  @override
  Future<void> save(RepoBookmarksState state) async => this.state = state;
}

Widget _app(BrowserFakeApi api, _MemoryBookmarksStore store) {
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
      repoBookmarksStoreProvider.overrideWithValue(store),
    ],
    child: const MaterialApp(home: RepoBrowserScreen()),
  );
}

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

Future<BrowserFakeApi> _pumpScreen(
  WidgetTester tester, {
  _MemoryBookmarksStore? store,
}) async {
  _mockPlatform(tester);
  _tallScreen(tester);
  final api = BrowserFakeApi();
  await tester.pumpWidget(_app(api, store ?? _MemoryBookmarksStore()));
  await tester.pumpAndSettle();
  return api;
}

Future<void> _openAddMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('browser_add_menu')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('create a file from the + menu in one commit', (tester) async {
    final api = await _pumpScreen(tester);

    await _openAddMenu(tester);
    await tester.tap(find.text('ملف جديد'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('create_entry_name')),
        'notes.md');
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('create_entry_content')), 'hello phase 10');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('create_entry_submit')));
    await tester.pumpAndSettle();

    expect(api.createCommitCalls, 1);
    expect(api.files.map((f) => f.path), contains('notes.md'));
    // The undo bar of the create appears.
    expect(find.textContaining('تم إنشاء'), findsWidgets);
  });

  testWidgets('create a folder from the + menu materializes .gitkeep',
      (tester) async {
    final api = await _pumpScreen(tester);

    await _openAddMenu(tester);
    await tester.tap(find.text('مجلد جديد'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('create_entry_name')), 'docs2');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('create_entry_submit')));
    await tester.pumpAndSettle();

    expect(api.files.map((f) => f.path), contains('docs2/.gitkeep'));
  });

  testWidgets('the current folder can be favorited from the menu',
      (tester) async {
    final store = _MemoryBookmarksStore();
    final api = await _pumpScreen(tester, store: store);

    // Into the folder first (root itself is never favorited).
    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();

    await _openAddMenu(tester);
    await tester.tap(find.text('إضافة المجلد الحالي إلى المفضلة'));
    await tester.pumpAndSettle();

    expect(
      store.state.favorites.map((e) => e.path),
      contains('lib'),
    );

    // Re-opening the menu shows the removal action.
    await _openAddMenu(tester);
    expect(find.text('إزالة المجلد الحالي من المفضلة'), findsOneWidget);
    await tester.tap(find.text('إزالة المجلد الحالي من المفضلة'));
    await tester.pumpAndSettle();
    expect(store.state.favorites, isEmpty);
  });

  testWidgets('opening a file records a recent and the sheet offers it',
      (tester) async {
    final store = _MemoryBookmarksStore();
    await _pumpScreen(tester, store: store);

    await tester.tap(find.text('README.md'));
    await tester.pumpAndSettle();
    expect(store.state.recents.map((e) => e.path), contains('README.md'));

    // Back to the browser, then open the bookmarks sheet.
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('المفضلة والملفات الحديثة'));
    await tester.pumpAndSettle();

    // The favorites tab is empty; switch to recents.
    await tester.tap(find.text('الحديثة'));
    await tester.pumpAndSettle();
    expect(find.text('README.md'), findsOneWidget);
  });

  testWidgets('the viewer star toggles the favorite of the file',
      (tester) async {
    final store = _MemoryBookmarksStore();
    final api = await _pumpScreen(tester, store: store);

    await tester.tap(find.text('README.md'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('viewer_favorite')));
    await tester.pumpAndSettle();
    expect(store.state.favorites.map((e) => e.path), contains('README.md'));

    await tester.tap(find.byKey(const ValueKey('viewer_favorite')));
    await tester.pumpAndSettle();
    expect(store.state.favorites, isEmpty);
    // Sanity: the file shown is the fake's README.
    expect(api.blobReads, contains('sha_readme'));
  });

  testWidgets('content search queries the Search API on submit only',
      (tester) async {
    final api = await _pumpScreen(tester);
    api.searchResult = const RepoCodeSearchResult(
      totalCount: 1,
      incompleteResults: false,
      items: [
        RepoCodeSearchHit(
          path: 'lib/main.dart',
          sha: 'sha_main',
          htmlUrl: '',
          snippets: ['void main() {'],
        ),
      ],
    );

    await tester.tap(find.byTooltip('بحث'));
    await tester.pumpAndSettle();

    // Switch to the content mode; typing alone must not hit the API.
    await tester.tap(find.text('المحتوى'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'void main');
    await tester.pumpAndSettle();
    expect(api.searchCalls, 0);

    await tester.tap(find.byTooltip('بحث في المحتوى'));
    await tester.pumpAndSettle();

    expect(api.searchCalls, 1);
    expect(find.text('main.dart'), findsOneWidget);
    expect(find.textContaining('void main() {'), findsOneWidget);
  });

  testWidgets('a protected branch offers the new-branch + PR flow',
      (tester) async {
    final api = await _pumpScreen(tester);
    api.protectedBranches.add('main');

    await tester.longPress(find.text('README.md'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection_delete')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('delete_commit_message')),
      'Nexus: delete README.md',
    );
    await tester.tap(find.byKey(const ValueKey('delete_confirm')));
    await tester.pumpAndSettle();

    // The protected-branch dialog opened automatically.
    expect(find.byKey(const ValueKey('pr_new_branch')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('pr_new_branch')),
      'nexus/patch-1',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pr_confirm')));
    await tester.pumpAndSettle();

    expect(api.createBranchCalls, 1);
    expect(api.createPullRequestCalls, 1);
    expect(api.lastPullRequestBase, 'main');
    // The browsed branch never lost the file.
    expect(api.files.map((f) => f.path), contains('README.md'));
    // The result dialog confirms the PR.
    expect(find.textContaining('Pull Request #'), findsOneWidget);
  });

  testWidgets('a chosen bookmark folder opens it in the browser',
      (tester) async {
    final store = _MemoryBookmarksStore();
    store.state = RepoBookmarksState(
      favorites: [
        RepoBookmarkEntry(
          repoFullName: 'abdullah/nexus-demo',
          branchName: 'main',
          path: 'lib',
          isFolder: true,
          savedAt: DateTime(2026),
        ),
      ],
    );
    await _pumpScreen(tester, store: store);

    await tester.tap(find.byTooltip('المفضلة والملفات الحديثة'));
    await tester.pumpAndSettle();
    // The sheet row (ListTile), not the folder tile behind it.
    await tester.tap(
      find.descendant(of: find.byType(ListTile), matching: find.text('lib')),
    );
    await tester.pumpAndSettle();

    // The browser navigated into the favorite folder.
    expect(find.text('main.dart'), findsOneWidget);
  });
}
