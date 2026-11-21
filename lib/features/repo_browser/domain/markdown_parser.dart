/// Minimal Markdown parser (block + inline) for the read-only README viewer.
///
/// It intentionally covers the subset that real READMEs use: headings,
/// paragraphs, fenced code, block quotes, (nested) lists with task boxes,
/// tables, horizontal rules, and inline code / bold / italic / strike /
/// links / images. Raw HTML is reduced to its text.
sealed class MdBlock {
  const MdBlock();
}

final class MdHeading extends MdBlock {
  final int level;
  final String text;
  const MdHeading(this.level, this.text);
}

final class MdParagraph extends MdBlock {
  final String text;
  const MdParagraph(this.text);
}

final class MdCodeBlock extends MdBlock {
  final String? language;
  final String code;
  const MdCodeBlock(this.language, this.code);
}

final class MdQuote extends MdBlock {
  final String text;
  const MdQuote(this.text);
}

final class MdRule extends MdBlock {
  const MdRule();
}

class MdListItem {
  /// Nesting depth (0 = top level).
  final int depth;

  /// `null` for bullets, the number for ordered items.
  final int? number;

  /// `null` when not a task item.
  final bool? checked;
  final String text;

  const MdListItem({
    required this.depth,
    required this.number,
    required this.checked,
    required this.text,
  });

  MdListItem copyWithText(String value) => MdListItem(
        depth: depth,
        number: number,
        checked: checked,
        text: value,
      );
}

final class MdList extends MdBlock {
  final List<MdListItem> items;
  const MdList(this.items);
}

final class MdTable extends MdBlock {
  final List<String> header;
  final List<List<String>> rows;
  const MdTable(this.header, this.rows);
}

/// One run of inline text with its style.
class MdSpan {
  final String text;
  final bool bold;
  final bool italic;
  final bool strike;
  final bool code;
  final String? link;

  const MdSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
    this.link,
  });

  @override
  String toString() => 'MdSpan($text${bold ? ' b' : ''}${italic ? ' i' : ''}'
      '${code ? ' code' : ''}${link != null ? ' ->$link' : ''})';
}

abstract final class MarkdownParser {
  static final RegExp _fence = RegExp(r'^\s{0,3}(`{3,}|~{3,})\s*([^\s`]*)');
  static final RegExp _heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)(?:\s+#+)?\s*$');
  static final RegExp _rule = RegExp(r'^\s{0,3}([-*_])(?:\s*\1){2,}\s*$');
  static final RegExp _listItem = RegExp(r'^(\s*)([-*+]|\d{1,9}[.)])\s+(.*)$');
  static final RegExp _tableSeparator =
      RegExp(r'^\s*\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)*\|?\s*$');
  static final RegExp _htmlTag = RegExp(r'<[^>]+>');
  static final RegExp _task = RegExp(r'^\[([ xX])\]\s+(.*)$');

  static List<MdBlock> parse(String source) {
    final lines = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final blocks = <MdBlock>[];

    final paragraph = <String>[];
    var listItems = <MdListItem>[];
    // Indentation widths of the currently open list levels.
    final indents = <int>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add(MdParagraph(paragraph.join(' ').trim()));
      paragraph.clear();
    }

    void flushList() {
      if (listItems.isEmpty) return;
      blocks.add(MdList(listItems));
      listItems = <MdListItem>[];
      indents.clear();
    }

    void flushAll() {
      flushParagraph();
      flushList();
    }

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];

      // Fenced code block -------------------------------------------------
      final fence = _fence.firstMatch(line);
      if (fence != null) {
        flushAll();
        final marker = fence.group(1)!;
        final language = fence.group(2);
        final code = <String>[];
        i++;
        while (i < lines.length) {
          final trimmed = lines[i].trim();
          if (trimmed.startsWith(marker) &&
              trimmed.replaceAll(marker[0], '').isEmpty) {
            break;
          }
          code.add(lines[i]);
          i++;
        }
        i++; // closing fence (or past the end for an unterminated block)
        blocks.add(
          MdCodeBlock(
            (language == null || language.isEmpty) ? null : language,
            code.join('\n'),
          ),
        );
        continue;
      }

      // Blank line --------------------------------------------------------
      if (line.trim().isEmpty) {
        flushAll();
        i++;
        continue;
      }

      // Heading -----------------------------------------------------------
      final heading = _heading.firstMatch(line);
      if (heading != null) {
        flushAll();
        blocks.add(MdHeading(heading.group(1)!.length, heading.group(2)!));
        i++;
        continue;
      }

      // Horizontal rule ---------------------------------------------------
      if (_rule.hasMatch(line)) {
        flushAll();
        blocks.add(const MdRule());
        i++;
        continue;
      }

      // Table -------------------------------------------------------------
      if (line.contains('|') &&
          i + 1 < lines.length &&
          lines[i + 1].contains('-') &&
          _tableSeparator.hasMatch(lines[i + 1])) {
        flushAll();
        final header = _splitRow(line);
        final rows = <List<String>>[];
        i += 2;
        while (i < lines.length &&
            lines[i].trim().isNotEmpty &&
            lines[i].contains('|')) {
          rows.add(_splitRow(lines[i]));
          i++;
        }
        blocks.add(MdTable(header, rows));
        continue;
      }

      // Block quote -------------------------------------------------------
      if (line.trimLeft().startsWith('>')) {
        flushAll();
        final quote = <String>[];
        while (i < lines.length && lines[i].trimLeft().startsWith('>')) {
          quote.add(lines[i].trimLeft().substring(1).trimLeft());
          i++;
        }
        blocks.add(MdQuote(quote.join('\n')));
        continue;
      }

      // List item ---------------------------------------------------------
      final item = _listItem.firstMatch(line);
      if (item != null) {
        flushParagraph();
        final indent = _indentWidth(item.group(1)!);
        final marker = item.group(2)!;
        var text = item.group(3)!;
        bool? checked;
        final task = _task.firstMatch(text);
        if (task != null) {
          checked = task.group(1) != ' ';
          text = task.group(2)!;
        }
        final isOrdered = RegExp(r'^\d').hasMatch(marker);
        while (indents.isNotEmpty && indents.last > indent) {
          indents.removeLast();
        }
        if (indents.isEmpty || indents.last < indent) indents.add(indent);
        listItems.add(
          MdListItem(
            depth: indents.length - 1,
            number: isOrdered
                ? int.tryParse(marker.replaceAll(RegExp(r'\D'), ''))
                : null,
            checked: checked,
            text: text,
          ),
        );
        i++;
        continue;
      }

      // Continuation of the previous list item ----------------------------
      if (listItems.isNotEmpty && _indentWidth(line) >= 2) {
        final last = listItems.removeLast();
        listItems.add(last.copyWithText('${last.text} ${line.trim()}'));
        i++;
        continue;
      }

      // Raw HTML line -> its visible text only ----------------------------
      final trimmed = line.trim();
      if (trimmed.startsWith('<') && trimmed.endsWith('>')) {
        final visible = trimmed.replaceAll(_htmlTag, '').trim();
        if (visible.isNotEmpty) paragraph.add(visible);
        i++;
        continue;
      }

      // Paragraph text ----------------------------------------------------
      flushList();
      paragraph.add(trimmed);
      i++;
    }

    flushAll();
    return blocks;
  }

  static int _indentWidth(String leading) {
    var width = 0;
    for (final unit in leading.codeUnits) {
      if (unit == 0x20) {
        width++;
      } else if (unit == 0x09) {
        width += 4;
      } else {
        break;
      }
    }
    return width;
  }

  static List<String> _splitRow(String row) {
    var value = row.trim();
    if (value.startsWith('|')) value = value.substring(1);
    if (value.endsWith('|')) value = value.substring(0, value.length - 1);
    return value.split('|').map((cell) => cell.trim()).toList();
  }

  // -------------------------------------------------------------------------
  // Inline
  // -------------------------------------------------------------------------

  static final RegExp _inline = RegExp(
    r'(?<code2>``(?<c2>.+?)``)'
    r'|(?<code1>`(?<c1>[^`\n]+)`)'
    r'|(?<image>!\[(?<ialt>[^\]]*)\]\((?<iurl>[^)\s]*)(?:\s+"[^"]*")?\))'
    r'|(?<link>\[(?<ltext>(?:!\[[^\]]*\]\([^)]*\)|[^\[\]])+)\]\((?<lurl>[^)\s]*)(?:\s+"[^"]*")?\))'
    r'|(?<auto><(?<aurl>https?://[^>\s]+)>)'
    r'|(?<bold>\*\*(?<b1>.+?)\*\*|__(?<b2>.+?)__)'
    r'|(?<strike>~~(?<s1>.+?)~~)'
    r'|(?<italic>\*(?<i1>[^*\s](?:[^*]*[^*\s])?)\*|(?<![\w])_(?<i2>[^_\s](?:[^_]*[^_\s])?)_(?![\w]))'
    r'|(?<html><[^>\n]+>)',
  );

  static List<MdSpan> parseInline(
    String text, {
    bool bold = false,
    bool italic = false,
    bool strike = false,
    String? link,
  }) {
    final spans = <MdSpan>[];

    void plain(String value) {
      if (value.isEmpty) return;
      spans.add(
        MdSpan(value, bold: bold, italic: italic, strike: strike, link: link),
      );
    }

    var cursor = 0;
    for (final m in _inline.allMatches(text)) {
      if (m.start > cursor) plain(text.substring(cursor, m.start));
      cursor = m.end;

      if (m.namedGroup('code2') != null || m.namedGroup('code1') != null) {
        final code = m.namedGroup('c2') ?? m.namedGroup('c1') ?? '';
        spans.add(MdSpan(code.trim(), code: true, bold: bold, link: link));
      } else if (m.namedGroup('image') != null) {
        final alt = (m.namedGroup('ialt') ?? '').trim();
        spans.add(
          MdSpan(
            alt.isEmpty ? '[صورة]' : '[صورة: $alt]',
            italic: true,
            link: link,
          ),
        );
      } else if (m.namedGroup('link') != null) {
        spans.addAll(
          parseInline(
            m.namedGroup('ltext')!,
            bold: bold,
            italic: italic,
            strike: strike,
            link: m.namedGroup('lurl') ?? '',
          ),
        );
      } else if (m.namedGroup('auto') != null) {
        final url = m.namedGroup('aurl')!;
        spans.add(MdSpan(url, link: url));
      } else if (m.namedGroup('bold') != null) {
        spans.addAll(
          parseInline(
            m.namedGroup('b1') ?? m.namedGroup('b2') ?? '',
            bold: true,
            italic: italic,
            strike: strike,
            link: link,
          ),
        );
      } else if (m.namedGroup('strike') != null) {
        spans.addAll(
          parseInline(
            m.namedGroup('s1') ?? '',
            bold: bold,
            italic: italic,
            strike: true,
            link: link,
          ),
        );
      } else if (m.namedGroup('italic') != null) {
        spans.addAll(
          parseInline(
            m.namedGroup('i1') ?? m.namedGroup('i2') ?? '',
            bold: bold,
            italic: true,
            strike: strike,
            link: link,
          ),
        );
      }
      // `html` group: inline tags (<br>, <img ...>, <b>) are dropped.
    }
    if (cursor < text.length) plain(text.substring(cursor));
    return spans;
  }
}
