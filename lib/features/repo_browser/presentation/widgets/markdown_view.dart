import 'package:flutter/material.dart';
import '../../../../core/theme/nexus_colors.dart';
import '../../domain/markdown_parser.dart';
import '../../domain/syntax_highlighter.dart';
import 'code_view.dart';

/// Renders Markdown source with the subset supported by [MarkdownParser].
class MarkdownView extends StatefulWidget {
  final String source;

  const MarkdownView({super.key, required this.source});

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  late List<MdBlock> _blocks = MarkdownParser.parse(widget.source);

  @override
  void didUpdateWidget(MarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _blocks = MarkdownParser.parse(widget.source);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_blocks.isEmpty) {
      return const Center(
        child: Text(
          'الملف فارغ.',
          style: TextStyle(color: NexusColors.textMuted),
        ),
      );
    }

    return SelectionArea(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        itemCount: _blocks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _buildBlock(_blocks[index]),
      ),
    );
  }

  Widget _buildBlock(MdBlock block) {
    return switch (block) {
      MdHeading h => _heading(h),
      MdParagraph p => Text.rich(
          _inline(p.text, _bodyStyle),
          style: _bodyStyle,
        ),
      MdCodeBlock c => _CodeBlock(code: c.code, language: c.language),
      MdQuote q => _quote(q),
      MdRule _ => const Divider(height: 24, color: NexusColors.borderSubtle),
      MdList l => _list(l),
      MdTable t => _table(t),
    };
  }

  static const TextStyle _bodyStyle = TextStyle(
    fontSize: 14,
    height: 1.6,
    color: NexusColors.textSecondary,
  );

  Widget _heading(MdHeading block) {
    final size = switch (block.level) {
      1 => 24.0,
      2 => 20.0,
      3 => 17.0,
      4 => 15.5,
      _ => 14.5,
    };
    final style = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w700,
      height: 1.35,
      color: NexusColors.textPrimary,
    );
    final text = Text.rich(_inline(block.text, style), style: style);
    if (block.level > 2) return text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        text,
        const SizedBox(height: 8),
        const Divider(height: 1, color: NexusColors.borderSubtle),
      ],
    );
  }

  Widget _quote(MdQuote block) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: NexusColors.primary.withOpacity(0.06),
        border: const Border(
          left: BorderSide(color: NexusColors.primary, width: 3),
        ),
      ),
      child: Text.rich(
        _inline(block.text.replaceAll('\n', ' '), _bodyStyle),
        style: _bodyStyle.copyWith(color: NexusColors.textMuted),
      ),
    );
  }

  Widget _list(MdList block) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in block.items)
          Padding(
            padding: EdgeInsets.only(
              left: item.depth * 18.0,
              bottom: 4,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: item.checked != null
                      ? Icon(
                          item.checked!
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 17,
                          color: item.checked!
                              ? NexusColors.successSoft
                              : NexusColors.textSubtle,
                        )
                      : Text(
                          item.number != null
                              ? '${item.number}.'
                              : (item.depth.isEven ? '•' : '◦'),
                          style: _bodyStyle.copyWith(
                            color: NexusColors.textMuted,
                          ),
                        ),
                ),
                Expanded(
                  child: Text.rich(
                    _inline(item.text, _bodyStyle),
                    style: _bodyStyle,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _table(MdTable block) {
    final columns = block.header.length;

    TableRow row(List<String> cells, {bool header = false}) {
      return TableRow(
        decoration: header
            ? BoxDecoration(color: Colors.white.withOpacity(0.05))
            : null,
        children: [
          for (var c = 0; c < columns; c++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Text.rich(
                _inline(
                  c < cells.length ? cells[c] : '',
                  _bodyStyle.copyWith(
                    fontWeight: header ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: NexusColors.borderSubtle),
        children: [
          row(block.header, header: true),
          for (final r in block.rows) row(r),
        ],
      ),
    );
  }

  /// Builds a [TextSpan] tree for inline Markdown.
  static TextSpan _inline(String text, TextStyle base) {
    final spans = MarkdownParser.parseInline(text);
    return TextSpan(
      style: base,
      children: [
        for (final span in spans)
          TextSpan(
            text: span.text,
            style: base.copyWith(
              fontWeight: span.bold ? FontWeight.w700 : null,
              fontStyle: span.italic ? FontStyle.italic : null,
              decoration: span.link != null
                  ? TextDecoration.underline
                  : (span.strike ? TextDecoration.lineThrough : null),
              color: span.link != null ? NexusColors.primarySoft : null,
              fontFamily: span.code ? 'monospace' : null,
              fontSize: span.code ? (base.fontSize ?? 14) - 1 : null,
              backgroundColor:
                  span.code ? Colors.white.withOpacity(0.08) : null,
            ),
          ),
      ],
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String code;
  final String? language;

  const _CodeBlock({required this.code, required this.language});

  static const TextStyle _style = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12.5,
    height: 1.5,
    color: SyntaxColors.plain,
  );

  @override
  Widget build(BuildContext context) {
    final lines = SyntaxHighlighter.highlight(code, _normalize(language));
    final children = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      for (final span in lines[i]) {
        children.add(
          TextSpan(
            text: span.text,
            style: SyntaxColors.styleOf(span.type, _style),
          ),
        );
      }
      if (i < lines.length - 1) children.add(const TextSpan(text: '\n'));
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: NexusColors.bgDeep.withOpacity(0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexusColors.borderSubtle),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Text.rich(
            TextSpan(style: _style, children: children),
            softWrap: false,
          ),
        ),
      ),
    );
  }

  /// Maps fence info strings (```js, ```yml ...) to highlighter ids.
  static String? _normalize(String? language) {
    switch (language?.toLowerCase()) {
      case 'js':
      case 'javascript':
      case 'jsx':
        return 'js';
      case 'ts':
      case 'typescript':
      case 'tsx':
        return 'ts';
      case 'yml':
      case 'yaml':
        return 'yaml';
      case 'sh':
      case 'bash':
      case 'zsh':
      case 'shell':
      case 'console':
        return 'shell';
      case 'py':
      case 'python':
        return 'python';
      case 'html':
      case 'xml':
      case 'svg':
        return 'xml';
      case 'kt':
      case 'kotlin':
        return 'kotlin';
      case 'rb':
      case 'ruby':
        return 'ruby';
      case 'rs':
      case 'rust':
        return 'rust';
      case 'c++':
      case 'cpp':
        return 'cpp';
      case 'c#':
      case 'cs':
      case 'csharp':
        return 'csharp';
      case 'dart':
      case 'json':
      case 'java':
      case 'swift':
      case 'go':
      case 'c':
      case 'php':
      case 'sql':
      case 'css':
      case 'toml':
      case 'dockerfile':
      case 'makefile':
        return language!.toLowerCase();
      default:
        return null;
    }
  }
}
