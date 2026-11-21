import 'package:flutter/services.dart';

class TextSnapshot {
  final String text;
  final TextSelection selection;

  const TextSnapshot({
    required this.text,
    required this.selection,
  });
}

/// سجل تراجع/إعادة (Undo/Redo) مخصص لمحرر الكود مع دمج الكتابة السريعة المتتالية.
class EditorHistory {
  final int maxSteps;
  final Duration coalesceWindow;

  final List<TextSnapshot> _stack = [];
  int _index = -1;
  DateTime _lastPushAt = DateTime.fromMillisecondsSinceEpoch(0);

  EditorHistory({
    required TextSnapshot initial,
    this.maxSteps = 100,
    this.coalesceWindow = const Duration(milliseconds: 650),
  }) {
    reset(initial);
  }

  bool get canUndo => _index > 0;
  bool get canRedo => _index >= 0 && _index < _stack.length - 1;
  TextSnapshot get current => _stack[_index];

  void reset(TextSnapshot snapshot) {
    _stack
      ..clear()
      ..add(snapshot);
    _index = 0;
    _lastPushAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void push(
    TextSnapshot snapshot, {
    bool forceNewEntry = false,
    DateTime? now,
  }) {
    if (_index >= 0 && _stack[_index].text == snapshot.text) {
      _stack[_index] = snapshot;
      return;
    }

    final timestamp = now ?? DateTime.now();

    // حذف فرع الإعادة عند إدخال تعديل جديد بعد التراجع.
    if (_index < _stack.length - 1) {
      _stack.removeRange(_index + 1, _stack.length);
    }

    final prevText = _index >= 0 ? _stack[_index].text : '';
    final deltaLen = (snapshot.text.length - prevText.length).abs();
    final insertedNewline =
        snapshot.text.length > prevText.length &&
        snapshot.selection.baseOffset > 0 &&
        snapshot.selection.baseOffset <= snapshot.text.length &&
        snapshot.text.codeUnitAt(snapshot.selection.baseOffset - 1) == 0x0A;

    final shouldCoalesce = !forceNewEntry &&
        _index > 0 &&
        deltaLen == 1 &&
        !insertedNewline &&
        timestamp.difference(_lastPushAt) <= coalesceWindow;

    if (shouldCoalesce) {
      _stack[_index] = snapshot;
    } else {
      _stack.add(snapshot);
      if (_stack.length > maxSteps) {
        _stack.removeAt(0);
      }
      _index = _stack.length - 1;
    }
    _lastPushAt = timestamp;
  }

  TextSnapshot? undo() {
    if (!canUndo) return null;
    _index--;
    _lastPushAt = DateTime.fromMillisecondsSinceEpoch(0);
    return _stack[_index];
  }

  TextSnapshot? redo() {
    if (!canRedo) return null;
    _index++;
    _lastPushAt = DateTime.fromMillisecondsSinceEpoch(0);
    return _stack[_index];
  }
}

class TextMatchRange {
  final int start;
  final int end;
  final int lineNumber;

  const TextMatchRange({
    required this.start,
    required this.end,
    required this.lineNumber,
  });
}

/// أدوات البحث والاستبدال داخل النص (نص عادي أو Regex).
abstract final class EditorTextSearch {
  static String? validateRegex(String query) {
    if (query.isEmpty) return null;
    try {
      RegExp(query);
      return null;
    } on FormatException {
      return 'تعبير Regex غير صالح.';
    }
  }

  static List<TextMatchRange> findAll(
    String text,
    String query, {
    bool caseSensitive = false,
    bool useRegex = false,
  }) {
    if (query.isEmpty || text.isEmpty) return const [];

    final Pattern pattern;
    if (useRegex) {
      try {
        pattern = RegExp(query, caseSensitive: caseSensitive, multiLine: true);
      } on FormatException {
        return const [];
      }
    } else {
      pattern = RegExp(RegExp.escape(query), caseSensitive: caseSensitive);
    }

    final matches = <TextMatchRange>[];
    var line = 1;
    var lastOffset = 0;

    for (final m in pattern.allMatches(text)) {
      if (m.end <= m.start) continue; // تجنب المطابقات الفارغة في Regex.
      for (var i = lastOffset; i < m.start; i++) {
        if (text.codeUnitAt(i) == 0x0A) line++;
      }
      lastOffset = m.start;
      matches.add(TextMatchRange(start: m.start, end: m.end, lineNumber: line));
    }
    return matches;
  }

  static ({String text, int nextCursor}) replaceOne(
    String text,
    TextMatchRange range,
    String replacement,
  ) {
    final updated = text.replaceRange(range.start, range.end, replacement);
    return (text: updated, nextCursor: range.start + replacement.length);
  }

  static ({String text, int replacedCount}) replaceAll(
    String text,
    List<TextMatchRange> matches,
    String replacement,
  ) {
    if (matches.isEmpty) return (text: text, replacedCount: 0);
    final buffer = StringBuffer();
    var cursor = 0;
    for (final m in matches) {
      if (m.start < cursor) continue;
      buffer.write(text.substring(cursor, m.start));
      buffer.write(replacement);
      cursor = m.end;
    }
    buffer.write(text.substring(cursor));
    return (text: buffer.toString(), replacedCount: matches.length);
  }
}
