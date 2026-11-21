import 'dart:math' as math;

enum DiffLineKind { context, added, removed }

class DiffLine {
  final DiffLineKind kind;
  final int? oldLine;
  final int? newLine;
  final String text;

  const DiffLine({
    required this.kind,
    required this.oldLine,
    required this.newLine,
    required this.text,
  });
}

class DiffHunk {
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final List<DiffLine> lines;

  const DiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.lines,
  });

  String get header => '@@ -$oldStart,$oldCount +$newStart,$newCount @@';
}

class TextDiffResult {
  final List<DiffHunk> hunks;
  final int addedCount;
  final int removedCount;
  final bool isSimplified;

  const TextDiffResult({
    required this.hunks,
    required this.addedCount,
    required this.removedCount,
    this.isSimplified = false,
  });

  bool get isEmpty => addedCount == 0 && removedCount == 0;
}

/// محرك مقارنة سطر بسطر ينتج Hunks موحّدة (Unified Diff) قبل الـ Commit.
abstract final class LineDiff {
  /// الحد الأقصى لحجم مصفوفة LCS قبل الانتقال لمقارنة كتلية خطية سريعة.
  static const int _maxLcsCells = 1200000;

  static TextDiffResult compute(
    String before,
    String after, {
    int contextLines = 3,
  }) {
    if (before == after) {
      return const TextDiffResult(hunks: [], addedCount: 0, removedCount: 0);
    }

    final oldLines = _splitLines(before);
    final newLines = _splitLines(after);

    // قص البادئة واللاحقة المتطابقتين لتقليص نافذة المقارنة لأصغر حجم ممكن.
    var prefix = 0;
    final minLen = math.min(oldLines.length, newLines.length);
    while (prefix < minLen && oldLines[prefix] == newLines[prefix]) {
      prefix++;
    }

    var suffix = 0;
    while (suffix < (minLen - prefix) &&
        oldLines[oldLines.length - 1 - suffix] ==
            newLines[newLines.length - 1 - suffix]) {
      suffix++;
    }

    final oldMid = oldLines.sublist(prefix, oldLines.length - suffix);
    final newMid = newLines.sublist(prefix, newLines.length - suffix);

    final ops = <DiffLine>[];
    for (var i = 0; i < prefix; i++) {
      ops.add(
        DiffLine(
          kind: DiffLineKind.context,
          oldLine: i + 1,
          newLine: i + 1,
          text: oldLines[i],
        ),
      );
    }

    var simplified = false;
    final cellCount = oldMid.length * newMid.length;
    if (oldMid.isEmpty) {
      for (var j = 0; j < newMid.length; j++) {
        ops.add(
          DiffLine(
            kind: DiffLineKind.added,
            oldLine: null,
            newLine: prefix + j + 1,
            text: newMid[j],
          ),
        );
      }
    } else if (newMid.isEmpty) {
      for (var i = 0; i < oldMid.length; i++) {
        ops.add(
          DiffLine(
            kind: DiffLineKind.removed,
            oldLine: prefix + i + 1,
            newLine: null,
            text: oldMid[i],
          ),
        );
      }
    } else if (cellCount <= _maxLcsCells) {
      _appendLcsDiff(
        oldMid: oldMid,
        newMid: newMid,
        oldOffset: prefix,
        newOffset: prefix,
        out: ops,
      );
    } else {
      simplified = true;
      for (var i = 0; i < oldMid.length; i++) {
        ops.add(
          DiffLine(
            kind: DiffLineKind.removed,
            oldLine: prefix + i + 1,
            newLine: null,
            text: oldMid[i],
          ),
        );
      }
      for (var j = 0; j < newMid.length; j++) {
        ops.add(
          DiffLine(
            kind: DiffLineKind.added,
            oldLine: null,
            newLine: prefix + j + 1,
            text: newMid[j],
          ),
        );
      }
    }

    final oldSuffixStart = oldLines.length - suffix;
    final newSuffixStart = newLines.length - suffix;
    for (var k = 0; k < suffix; k++) {
      ops.add(
        DiffLine(
          kind: DiffLineKind.context,
          oldLine: oldSuffixStart + k + 1,
          newLine: newSuffixStart + k + 1,
          text: oldLines[oldSuffixStart + k],
        ),
      );
    }

    var added = 0;
    var removed = 0;
    for (final line in ops) {
      if (line.kind == DiffLineKind.added) added++;
      if (line.kind == DiffLineKind.removed) removed++;
    }

    final hunks = _buildHunks(ops, contextLines: contextLines);
    return TextDiffResult(
      hunks: hunks,
      addedCount: added,
      removedCount: removed,
      isSimplified: simplified,
    );
  }

  static List<String> _splitLines(String text) {
    if (text.isEmpty) return const [];
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return normalized.split('\n');
  }

  static void _appendLcsDiff({
    required List<String> oldMid,
    required List<String> newMid,
    required int oldOffset,
    required int newOffset,
    required List<DiffLine> out,
  }) {
    final m = oldMid.length;
    final n = newMid.length;
    final stride = n + 1;
    final dp = List<int>.filled((m + 1) * stride, 0);

    for (var i = m - 1; i >= 0; i--) {
      final row = i * stride;
      final nextRow = (i + 1) * stride;
      for (var j = n - 1; j >= 0; j--) {
        if (oldMid[i] == newMid[j]) {
          dp[row + j] = dp[nextRow + j + 1] + 1;
        } else {
          final down = dp[nextRow + j];
          final right = dp[row + j + 1];
          dp[row + j] = down >= right ? down : right;
        }
      }
    }

    var i = 0;
    var j = 0;
    while (i < m && j < n) {
      if (oldMid[i] == newMid[j]) {
        out.add(
          DiffLine(
            kind: DiffLineKind.context,
            oldLine: oldOffset + i + 1,
            newLine: newOffset + j + 1,
            text: oldMid[i],
          ),
        );
        i++;
        j++;
      } else if (dp[(i + 1) * stride + j] >= dp[i * stride + j + 1]) {
        out.add(
          DiffLine(
            kind: DiffLineKind.removed,
            oldLine: oldOffset + i + 1,
            newLine: null,
            text: oldMid[i],
          ),
        );
        i++;
      } else {
        out.add(
          DiffLine(
            kind: DiffLineKind.added,
            oldLine: null,
            newLine: newOffset + j + 1,
            text: newMid[j],
          ),
        );
        j++;
      }
    }

    while (i < m) {
      out.add(
        DiffLine(
          kind: DiffLineKind.removed,
          oldLine: oldOffset + i + 1,
          newLine: null,
          text: oldMid[i],
        ),
      );
      i++;
    }
    while (j < n) {
      out.add(
        DiffLine(
          kind: DiffLineKind.added,
          oldLine: null,
          newLine: newOffset + j + 1,
          text: newMid[j],
        ),
      );
      j++;
    }
  }

  static List<DiffHunk> _buildHunks(
    List<DiffLine> ops, {
    required int contextLines,
  }) {
    final changeIndices = <int>[
      for (var i = 0; i < ops.length; i++)
        if (ops[i].kind != DiffLineKind.context) i,
    ];
    if (changeIndices.isEmpty) return const [];

    final ranges = <({int start, int end})>[];
    var start = math.max(0, changeIndices.first - contextLines);
    var end = math.min(ops.length - 1, changeIndices.first + contextLines);

    for (var k = 1; k < changeIndices.length; k++) {
      final idx = changeIndices[k];
      final nextStart = math.max(0, idx - contextLines);
      final nextEnd = math.min(ops.length - 1, idx + contextLines);
      if (nextStart <= end + 1) {
        end = math.max(end, nextEnd);
      } else {
        ranges.add((start: start, end: end));
        start = nextStart;
        end = nextEnd;
      }
    }
    ranges.add((start: start, end: end));

    return [
      for (final r in ranges) _makeHunk(ops.sublist(r.start, r.end + 1)),
    ];
  }

  static DiffHunk _makeHunk(List<DiffLine> slice) {
    int? firstOld;
    int? firstNew;
    var oldCount = 0;
    var newCount = 0;

    for (final line in slice) {
      if (line.oldLine != null) {
        firstOld ??= line.oldLine;
        oldCount++;
      }
      if (line.newLine != null) {
        firstNew ??= line.newLine;
        newCount++;
      }
    }

    return DiffHunk(
      oldStart: firstOld ?? 0,
      oldCount: oldCount,
      newStart: firstNew ?? 0,
      newCount: newCount,
      lines: List.unmodifiable(slice),
    );
  }
}
