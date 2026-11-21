import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/core/network/github_exceptions.dart';
import 'package:github_nexus/features/repo_browser/presentation/repo_browser_controller.dart';
import 'package:github_nexus/features/repo_browser/presentation/repo_browser_screen.dart';
import 'package:github_nexus/features/repos/presentation/repos_controller.dart';
import 'support/browser_fakes.dart';

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
      // The branch pill reads the repositories state; an idle controller
      // (no token) keeps it free of network calls.
      reposControllerProvider.overrideWith(
        (ref) => ReposController(api: api, token: null),
      ),
    ],
    child: const MaterialApp(home: RepoBrowserScreen()),
  );
}

void main() {
  testWidgets('lists the root and navigates into a folder and back',
      (tester) async {
    await tester.pumpWidget(_app(BrowserFakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('abdullah/nexus-demo'), findsOneWidget);
    expect(find.text('docs'), findsOneWidget);
    expect(find.text('lib'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('3 مجلد'), findsOneWidget);
    expect(find.text('2 ملف'), findsOneWidget);

    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();

    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('utils'), findsOneWidget);
    expect(find.text('README.md'), findsNothing);

    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();

    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('main.dart'), findsNothing);
  });

  testWidgets('opens a markdown file in the viewer', (tester) async {
    final api = BrowserFakeApi();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('README.md'));
    await tester.pumpAndSettle();

    expect(api.blobReads, ['sha_readme']);
    expect(
      find.textContaining('content of sha_readme', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('binary files show an info card and are never downloaded',
      (tester) async {
    final api = BrowserFakeApi();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('app.zip'));
    await tester.pumpAndSettle();

    expect(find.text('لا توجد معاينة لهذا الملف'), findsOneWidget);
    expect(api.blobReads, isEmpty);
  });

  testWidgets('searches file names across the whole repository',
      (tester) async {
    final api = BrowserFakeApi();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('بحث'));
    await tester.pumpAndSettle();
    expect(find.text('ابحث في كل المستودع'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'main');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('1 نتيجة'), findsOneWidget);
    expect(api.recursiveCalls, 1);

    await tester.tap(find.byTooltip('إغلاق البحث'));
    await tester.pumpAndSettle();
    expect(find.text('README.md'), findsOneWidget);
  });

  testWidgets('an empty repository shows its own message', (tester) async {
    await tester.pumpWidget(_app(BrowserFakeApi(head: null)));
    await tester.pumpAndSettle();

    expect(find.text('المستودع فارغ'), findsOneWidget);
  });

  testWidgets('a load failure offers a retry that recovers', (tester) async {
    final api = BrowserFakeApi()
      ..headError = const GitHubApiException('تعذر الوصول');
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('تعذر تحميل المحتوى'), findsOneWidget);
    expect(find.text('تعذر الوصول'), findsOneWidget);

    api.headError = null;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();

    expect(find.text('تعذر تحميل المحتوى'), findsNothing);
    expect(find.text('README.md'), findsOneWidget);
  });
}
