import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/features/repo_browser/domain/editor_history.dart';

void main() {
  test('undo/redo navigates snapshots and clears redo on new edit', () {
    final history = EditorHistory(
      initial: const TextSnapshot(
        text: 'v0',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );

    history.push(
      const TextSnapshot(
        text: 'v1',
        selection: TextSelection.collapsed(offset: 2),
      ),
      forceNewEntry: true,
    );
    history.push(
      const TextSnapshot(
        text: 'v2',
        selection: TextSelection.collapsed(offset: 2),
      ),
      forceNewEntry: true,
    );

    expect(history.canUndo, isTrue);
    expect(history.canRedo, isFalse);

    expect(history.undo()!.text, 'v1');
    expect(history.canRedo, isTrue);

    expect(history.redo()!.text, 'v2');
    expect(history.undo()!.text, 'v1');

    // New branch discards redo history
    history.push(
      const TextSnapshot(
        text: 'v1-branch',
        selection: TextSelection.collapsed(offset: 9),
      ),
      forceNewEntry: true,
    );
    expect(history.canRedo, isFalse);
    expect(history.undo()!.text, 'v1');
    expect(history.undo()!.text, 'v0');
    expect(history.canUndo, isFalse);
  });

  test('find and replace supports case sensitivity and regex', () {
    const sample = 'Foo bar\nfoo baz\nFOO 123';

    final ci = EditorTextSearch.findAll(sample, 'foo', caseSensitive: false);
    expect(ci.length, 3);
    expect(ci.map((m) => m.lineNumber), [1, 2, 3]);

    final cs = EditorTextSearch.findAll(sample, 'foo', caseSensitive: true);
    expect(cs.length, 1);
    expect(cs.first.lineNumber, 2);

    final re = EditorTextSearch.findAll(sample, r'\d+', useRegex: true);
    expect(re.length, 1);
    expect(sample.substring(re.first.start, re.first.end), '123');

    expect(EditorTextSearch.validateRegex('[unclosed'), isNotNull);

    final replacedAll = EditorTextSearch.replaceAll(sample, ci, 'qux');
    expect(replacedAll.replacedCount, 3);
    expect(replacedAll.text, 'qux bar\nqux baz\nqux 123');
  });
}
