import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/nexus_colors.dart';
import '../../domain/syntax_highlighter.dart';

/// Colors for each token type (tuned for the dark Nexus theme).
abstract final class SyntaxColors {
  static const Color plain = Color(0xFFE2E8F0);
  static const Color keyword = Color(0xFFC084FC);
  static const Color string = Color(0xFF86EFAC);
  static const Color comment = Color(0xFF64748B);
  static const Color number = Color(0xFFFBBF24);
  static const Color type = Color(0xFF67E8F9);
  static const Color tag = Color(0xFF7DD3FC);
  static const Color attribute = Color(0xFFFDBA74);
  static const Color key = Color(0xFF7DD3FC);
  static const Color meta = Color(0xFFF9A8D4);

  static TextStyle styleOf(TokenType type, TextStyle base) {
    return switch (type) {
      TokenType.plain => base.copyWith(color: plain),
      TokenType.keyword => base.copyWith(
          color: keyword,
          fontWeight: FontWeight.w600,
        ),
      TokenType.string => base.copyWith(color: string),
      TokenType.comment => base.copyWith(
          color: comment,
          fontStyle: FontStyle.italic,
        ),
      TokenType.number => base.copyWith(color: number),
      TokenType.type => base.copyWith(color: SyntaxColors.type),
      TokenType.tag => base.copyWith(color: tag),
      TokenType.attribute => base.copyWith(color: attribute),
      TokenType.key => base.copyWith(color: key),
      TokenType.meta => base.copyWith(color: meta),
    };
  }
}

/// Runs in a background isolate for large files.
List<List<HighlightSpan>> _highlightJob(List<Object?> args) =>
    SyntaxHighlighter.highlight(args[0]! as String, args[1] as String?);

/// Read-only code viewer: line numbers, syntax colors, optional soft wrap,
/// always left-to-right regardless of the app direction.
class CodeView extends StatefulWidget {
  final String text;
  final String? language;
  final bool wrap;

  const CodeView({
    super.key,
    required this.text,
    this.language,
    this.wrap = false,
  });

  @override
  State<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends State<CodeView> {
  /// Above this size highlighting runs in an isolate to keep scrolling smooth.
  static const int _isolateThreshold = 60 * 1024;

  /// Very long lines (minified files) are cut to stay renderable.
  static const int _maxLineChars = 2000;

  static const double _fontSize = 12.5;
  static const double _lineHeight = 1.5;
  static const TextStyle _baseStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: _fontSize,
    height: _lineHeight,
    color: SyntaxColors.plain,
  );

  late final double _charWidth = _measureCharWidth();

  List<List<HighlightSpan>>? _lines;
  int _maxLineLength = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _highlight();
  }

  @override
  void didUpdateWidget(CodeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.language != widget.language) {
      _highlight();
    }
  }

  static double _measureCharWidth() {
    final painter = TextPainter(
      text: const TextSpan(text: 'MMMMMMMMMM', style: _baseStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width / 10;
    painter.dispose();
    return width;
  }

  void _highlight() {
    final text = widget.text;
    final language = widget.language;
    final generation = ++_generation;

    if (text.length <= _isolateThreshold) {
      // Cheap enough to do synchronously (also keeps widget tests simple).
      _apply(SyntaxHighlighter.highlight(text, language));
      return;
    }

    () async {
      final result = await compute(_highlightJob, <Object?>[text, language]);
      if (!mounted || generation != _generation) return;
      setState(() => _apply(result));
    }();
  }

  void _apply(List<List<HighlightSpan>> raw) {
    final lines = <List<HighlightSpan>>[];
    var longest = 0;
    for (final line in raw) {
      final limited = _limitLine(line);
      var length = 0;
      for (final span in limited) {
        length += span.text.length;
      }
      longest = math.max(longest, length);
      lines.add(limited);
    }
    // A trailing newline yields one empty last line that is not a real line.
    if (lines.length > 1 && lines.last.isEmpty) lines.removeLast();

    _lines = lines;
    _maxLineLength = longest;
  }

  static List<HighlightSpan> _limitLine(List<HighlightSpan> line) {
    var total = 0;
    for (final span in line) {
      total += span.text.length;
    }
    if (total <= _maxLineChars) return line;

    final result = <HighlightSpan>[];
    var remaining = _maxLineChars;
    for (final span in line) {
      if (remaining <= 0) break;
      if (span.text.length <= remaining) {
        result.add(span);
        remaining -= span.text.length;
      } else {
        result.add(HighlightSpan(span.text.substring(0, remaining), span.type));
        remaining = 0;
      }
    }
    result.add(const HighlightSpan(' … [تم اقتطاع باقي السطر]', TokenType.comment));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    if (lines == null) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: NexusColors.primarySoft,
          ),
        ),
      );
    }

    final digits = lines.length.toString().length;
    final gutterWidth = math.max(digits, 2) * _charWidth + 20;

    Widget buildRow(BuildContext context, int index) {
      final spans = lines[index];
      final code = Text.rich(
        TextSpan(
          style: _baseStyle,
          children: [
            for (final span in spans)
              TextSpan(
                text: span.text,
                style: SyntaxColors.styleOf(span.type, _baseStyle),
              ),
          ],
        ),
        softWrap: widget.wrap,
        textDirection: TextDirection.ltr,
        strutStyle: const StrutStyle(
          fontFamily: 'monospace',
          fontSize: _fontSize,
          height: _lineHeight,
          forceStrutHeight: true,
        ),
      );

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gutterWidth,
            child: SelectionContainer.disabled(
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.right,
                  style: _baseStyle.copyWith(color: NexusColors.textSubtle),
                ),
              ),
            ),
          ),
          if (widget.wrap) Expanded(child: code) else code,
        ],
      );
    }

    final Widget list;
    if (widget.wrap) {
      list = ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        itemCount: lines.length,
        itemBuilder: buildRow,
      );
    } else {
      list = LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = math.max(
            constraints.maxWidth,
            gutterWidth + (_maxLineLength + 4) * _charWidth + 12,
          );
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              height: constraints.maxHeight,
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                itemCount: lines.length,
                itemBuilder: buildRow,
              ),
            ),
          );
        },
      );
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: SelectionArea(child: list),
    );
  }
}
