import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/features/repo_browser/domain/line_diff.dart';

void main() {
  test('returns empty diff for identical texts', () {
    final diff = LineDiff.compute('a\nb\nc', 'a\nb\nc');
    expect(diff.isEmpty, isTrue);
    expect(diff.hunks, isEmpty);
  });

  test('computes unified diff hunk with additions, removals, and context', () {
    const before = 'line1\nline2\nline3\nline4\nline5';
    const after = 'line1\nline2\nline3-edited\nline3b\nline4\nline5';

    final diff = LineDiff.compute(before, after, contextLines: 1);
    expect(diff.addedCount, 2);
    expect(diff.removedCount, 1);
    expect(diff.hunks.length, 1);

    final lines = diff.hunks.first.lines;
    expect(lines.first.kind, DiffLineKind.context);
    expect(lines.first.text, 'line2');
    expect(
      lines.where((l) => l.kind == DiffLineKind.removed).single.text,
      'line3',
    );
    expect(
      lines.where((l) => l.kind == DiffLineKind.added).map((l) => l.text),
      ['line3-edited', 'line3b'],
    );
    expect(lines.last.kind, DiffLineKind.context);
    expect(lines.last.text, 'line4');
  });

  test('splits distant edits into separate hunks', () {
    final before = List.generate(20, (i) => 'row_$i').join('\n');
    final afterLines = List.generate(20, (i) => 'row_$i');
    afterLines[1] = 'row_1_mod';
    afterLines[18] = 'row_18_mod';

    final diff = LineDiff.compute(before, afterLines.join('\n'), contextLines: 2);
    expect(diff.hunks.length, 2);
    expect(diff.addedCount, 2);
    expect(diff.removedCount, 2);
  });
}
