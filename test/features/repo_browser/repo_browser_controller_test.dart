import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/core/network/github_api_client.dart';
import 'package:github_nexus/core/network/github_exceptions.dart';
import 'package:github_nexus/features/repo_browser/presentation/repo_browser_controller.dart';
import 'package:github_nexus/features/repos/domain/deploy_target.dart';
import 'support/browser_fakes.dart';

RepoBrowserController _controller(
  BrowserFakeApi api, {
  String? token = 't',
  DeployTarget? target,
  bool withTarget = true,
}) {
  final controller = RepoBrowserController(
    api: api,
    token: token,
    target: withTarget ? (target ?? browserTarget()) : null,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// Waits until the controller has no navigation or indexing in flight.
Future<void> _settle(RepoBrowserController controller) async {
  for (var i = 0; i < 400; i++) {
    final state = controller.debugState;
    if (!state.isLoading && !state.isIndexing) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('the controller never settled');
}

List<String> _names(RepoBrowserController controller) =>
    controller.debugState.entries.map((e) => e.name).toList();

void main() {
  group('initial state', () {
    test('without a token nothing is requested', () {
      final api = BrowserFakeApi();
      final controller = _controller(api, token: null);

      expect(controller.debugState.isLoading, isFalse);
      expect(controller.debugState.error, 'لا توجد جلسة نشطة.');
      expect(api.headCalls, 0);
    });

    test('without a selected repository nothing is requested', () {
      final api = BrowserFakeApi();
      final controller = _controller(api, withTarget: false);

      expect(controller.debugState.isLoading, isFalse);
      expect(controller.debugState.error, 'اختر مستودعاً أولاً لتصفح ملفاته.');
      expect(api.headCalls, 0);
    });
  });

  group('loading the root', () {
    test('lists folders first, then files, each sorted by name', () async {
      final api = BrowserFakeApi();
      final controller = _controller(api);
      expect(controller.debugState.isLoading, isTrue);

      await _settle(controller);

      final state = controller.debugState;
      expect(state.error, isNull);
      expect(state.isEmptyRepo, isFalse);
      expect(state.path, '');
      expect(state.segments, isEmpty);
      expect(state.headCommitSha, kBrowserHeadCommit);
      expect(_names(controller), ['docs', 'lib', 'scripts', 'app.zip', 'README.md']);
      expect(controller.service, isNotNull);
    });

    test('an empty repository has no entries and no service', () async {
      final api = BrowserFakeApi(head: null);
      final controller = _controller(api);
      await _settle(controller);

      expect(controller.debugState.isEmptyRepo, isTrue);
      expect(controller.debugState.entries, isEmpty);
      expect(controller.debugState.headCommitSha, isNull);
      expect(controller.service, isNull);
    });

    test('a failure is reported and retry recovers', () async {
      final api = BrowserFakeApi()
        ..headError = const GitHubApiException('خطأ تجريبي', statusCode: 500);
      final controller = _controller(api);
      await _settle(controller);

      expect(controller.debugState.error, 'خطأ تجريبي');
      expect(controller.debugState.entries, isEmpty);

      api.headError = null;
      await controller.retry();

      expect(controller.debugState.error, isNull);
      expect(_names(controller), contains('README.md'));
    });
  });

  group('navigation', () {
    test('openFolder / goUp walk the tree', () async {
      final api = BrowserFakeApi();
      final controller = _controller(api);
      await _settle(controller);

      await controller.openFolder('lib/utils');
      expect(controller.debugState.path, 'lib/utils');
      expect(controller.debugState.segments, ['lib', 'utils']);
      expect(_names(controller), ['a.dart', 'b.dart']);
      expect(controller.childPath('a.dart'), 'lib/utils/a.dart');

      expect(controller.goUp(), isTrue);
      await _settle(controller);
      expect(controller.debugState.path, 'lib');
      expect(_names(controller), ['utils', 'main.dart']);

      expect(controller.goUp(), isTrue);
      await _settle(controller);
      expect(controller.debugState.path, '');
      expect(controller.goUp(), isFalse);
      expect(controller.childPath('x'), 'x');
    });

    test('Arabic and spaced folder names open correctly', () async {
      final api = BrowserFakeApi();
      final controller = _controller(api);
      await _settle(controller);

      await controller.openFolder('docs');
      expect(_names(controller), ['دليل المستخدم.md']);
    });

    test('a slow listing can never overwrite a newer one', () async {
      final api = BrowserFakeApi();
      final controller = _controller(api);
      await _settle(controller);
      api.shallowDelays['tree:lib'] = const Duration(milliseconds: 60);

      final slow = controller.openFolder('lib');
      final fast = controller.openFolder('docs');
      await Future.wait([slow, fast]);

      expect(controller.debugState.path, 'docs');
      expect(_names(controller), ['دليل المستخدم.md']);
      expect(controller.debugState.isLoading, isFalse);
    });

    test('folders are cached, so going back costs no new request', () async {
      final api = BrowserFakeApi();
      final controller = _controller(api);
      await _settle(controller);

      await controller.openFolder('lib');
      final callsAfterFirstVisit = api.shallowCalls;
      await controller.openFolder('');
      await controller.openFolder('lib');

      expect(api.shallowCalls, callsAfterFirstVisit);
    });

    test('refresh keeps the folder, or falls back to the nearest parent', () async {
      final api = BrowserFakeApi();
      final controller = _controller(api);
      await _settle(controller);
      await controller.openFolder('lib/utils');

      // Someone deleted lib/utils and pushed a new commit.
      api
        ..files = api.files.where((f) => !f.path.startsWith('lib/utils/')).toList()
        ..head = const BranchHeadRef(commitSha: 'head2', treeSha: 'tree_root2');
      await controller.refresh();

      expect(controller.debugState.path, 'lib');
      expect(_names(controller), ['main.dart']);
      expect(controller.debugState.headCommitSha, 'head2');
    });
  });

  group('file-name search', () {
    test('builds the index once and filters locally', () async {
      final api = BrowserFakeApi();
      final controller = _controller(api);
      await _settle(controller);

      controller.setSearchActive(true);
      expect(controller.debugState.searchActive, isTrue);
      expect(controller.debugState.isIndexing, isTrue);
      await _settle(controller);

      controller.setSearchQuery('main');
      expect(
        controller.debugState.searchResult.hits.map((h) => h.path),
        ['lib/main.dart'],
      );

      controller.setSearchQuery('utils');
      expect(controller.debugState.searchResult.total, 3);
      expect(api.recursiveCalls, 1);
    });

    test('closing the search resets the query', () async {
      final api = BrowserFakeApi();
      final controller = _controller(api);
      await _settle(controller);
      controller.setSearchActive(true);
      await _settle(controller);
      controller.setSearchQuery('main');

      controller.setSearchActive(false);

      expect(controller.debugState.searchActive, isFalse);
      expect(controller.debugState.searchQuery, '');
      expect(controller.debugState.searchResult.hits, isEmpty);
    });

    test('a truncated tree marks the results as partial', () async {
      final api = BrowserFakeApi(truncated: true);
      final controller = _controller(api);
      await _settle(controller);

      controller.setSearchActive(true);
      await _settle(controller);
      controller.setSearchQuery('main');

      expect(controller.debugState.searchPartial, isTrue);
      expect(controller.debugState.searchResult.hits, isEmpty);
    });

    test('an indexing failure is shown and retryIndex recovers', () async {
      final api = BrowserFakeApi()
        ..recursiveError = const GitHubApiException('boom');
      final controller = _controller(api);
      await _settle(controller);

      controller.setSearchActive(true);
      await _settle(controller);
      expect(controller.debugState.searchError, 'boom');

      api.recursiveError = null;
      await controller.retryIndex();
      controller.setSearchQuery('main');

      expect(controller.debugState.searchError, isNull);
      expect(controller.debugState.searchResult.total, 1);
    });

    test('refresh drops the stale index and rebuilds it while searching', () async {
      final api = BrowserFakeApi();
      final controller = _controller(api);
      await _settle(controller);
      controller.setSearchActive(true);
      await _settle(controller);
      expect(api.recursiveCalls, 1);

      await controller.refresh();
      await _settle(controller);

      expect(api.recursiveCalls, 2);
    });
  });
}
