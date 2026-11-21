import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/features/repo_browser/domain/remote_tree_entry.dart';
import 'package:github_nexus/features/repo_browser/presentation/widgets/code_view.dart';
import 'package:github_nexus/features/repo_browser/presentation/widgets/markdown_view.dart';
import 'package:github_nexus/features/repo_browser/presentation/widgets/repo_breadcrumb.dart';
import 'package:github_nexus/features/repo_browser/presentation/widgets/repo_entry_tile.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

RemoteTreeEntry _entry({
  String name = 'a.txt',
  String type = 'blob',
  String mode = '100644',
  int size = 0,
}) =>
    RemoteTreeEntry(name: name, sha: 's', mode: mode, type: type, size: size);

void main() {
  group('RepoBreadcrumb', () {
    testWidgets('tapping a crumb opens that folder; the current one is inert',
        (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        _host(
          RepoBreadcrumb(
            rootLabel: 'repo',
            segments: const ['lib', 'utils'],
            onOpen: opened.add,
          ),
        ),
      );

      await tester.tap(find.text('lib'));
      await tester.tap(find.text('repo'));
      await tester.tap(find.text('utils'));

      expect(opened, ['lib', '']);
    });
  });

  group('RepoEntryTile', () {
    test('subtitleFor describes each kind of entry', () {
      expect(RepoEntryTile.subtitleFor(_entry(type: 'tree')), isNull);
      expect(
        RepoEntryTile.subtitleFor(_entry(type: 'commit')),
        'Submodule',
      );
      expect(
        RepoEntryTile.subtitleFor(_entry(mode: '120000')),
        'رابط رمزي',
      );
      expect(RepoEntryTile.subtitleFor(_entry(size: 1536)), '1.5 KB');
      expect(
        RepoEntryTile.subtitleFor(_entry(mode: '100755', size: 1536)),
        '1.5 KB • قابل للتنفيذ',
      );
    });

    testWidgets('shows the name and reports taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          RepoEntryTile(
            entry: _entry(name: 'main.dart', size: 20),
            onTap: () => taps++,
          ),
        ),
      );

      expect(find.text('main.dart'), findsOneWidget);
      expect(find.text('20 B'), findsOneWidget);

      await tester.tap(find.text('main.dart'));
      expect(taps, 1);
    });
  });

  group('CodeView', () {
    testWidgets('numbers every line', (tester) async {
      await tester.pumpWidget(
        _host(const CodeView(text: 'a\nb\nc', language: null)),
      );
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('a trailing newline does not add a phantom line',
        (tester) async {
      await tester.pumpWidget(
        _host(const CodeView(text: 'a\nb\n', language: 'dart')),
      );
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsNothing);
    });
  });

  group('MarkdownView', () {
    testWidgets('renders headings and inline formatting as text',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const MarkdownView(source: '# Title\n\nHello **world**\n\n- item'),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Title', findRichText: true), findsWidgets);
      expect(
        find.textContaining('Hello world', findRichText: true),
        findsWidgets,
      );
      expect(find.textContaining('item', findRichText: true), findsWidgets);
    });

    testWidgets('an empty document shows a placeholder', (tester) async {
      await tester.pumpWidget(_host(const MarkdownView(source: '')));
      expect(find.text('الملف فارغ.'), findsOneWidget);
    });
  });
}
