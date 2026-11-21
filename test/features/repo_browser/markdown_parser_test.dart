import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/features/repo_browser/domain/markdown_parser.dart';

void main() {
  group('MarkdownParser.parse (blocks)', () {
    test('heading followed by a paragraph that joins soft line breaks', () {
      final blocks = MarkdownParser.parse('# Title\n\nhello\nworld');
      expect(blocks.length, 2);

      final heading = blocks[0] as MdHeading;
      expect(heading.level, 1);
      expect(heading.text, 'Title');

      final paragraph = blocks[1] as MdParagraph;
      expect(paragraph.text, 'hello world');
    });

    test('heading levels and closing hashes', () {
      final blocks = MarkdownParser.parse('### Deep ###\n\n###### Six');
      expect((blocks[0] as MdHeading).level, 3);
      expect((blocks[0] as MdHeading).text, 'Deep');
      expect((blocks[1] as MdHeading).level, 6);
    });

    test('fenced code block keeps its language and content', () {
      final blocks = MarkdownParser.parse(
        'before\n\n```dart\nvoid main() {}\n```\n\nafter',
      );
      final code = blocks[1] as MdCodeBlock;
      expect(code.language, 'dart');
      expect(code.code, 'void main() {}');
      expect(blocks[2], isA<MdParagraph>());
    });

    test('an unterminated fence runs to the end of the file', () {
      final blocks = MarkdownParser.parse('```\nline1\nline2');
      expect(blocks.length, 1);
      final code = blocks.single as MdCodeBlock;
      expect(code.language, isNull);
      expect(code.code, 'line1\nline2');
    });

    test('markdown inside a fence is not interpreted', () {
      final blocks = MarkdownParser.parse('```\n# not a heading\n- not a list\n```');
      expect(blocks.single, isA<MdCodeBlock>());
      expect((blocks.single as MdCodeBlock).code, '# not a heading\n- not a list');
    });

    test('nested bullet list tracks depth', () {
      final blocks = MarkdownParser.parse('- a\n  - b\n- c');
      final list = blocks.single as MdList;
      expect(list.items.map((i) => i.text), ['a', 'b', 'c']);
      expect(list.items.map((i) => i.depth), [0, 1, 0]);
      expect(list.items.every((i) => i.number == null), isTrue);
    });

    test('ordered list keeps numbers', () {
      final list = MarkdownParser.parse('1. x\n2. y').single as MdList;
      expect(list.items.map((i) => i.number), [1, 2]);
    });

    test('task list items expose their checked state', () {
      final list =
          MarkdownParser.parse('- [x] done\n- [ ] todo').single as MdList;
      expect(list.items[0].checked, isTrue);
      expect(list.items[0].text, 'done');
      expect(list.items[1].checked, isFalse);
      expect(list.items[1].text, 'todo');
    });

    test('table with header and rows', () {
      final table = MarkdownParser.parse('| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |')
          .single as MdTable;
      expect(table.header, ['a', 'b']);
      expect(table.rows, [
        ['1', '2'],
        ['3', '4'],
      ]);
    });

    test('block quote joins its lines', () {
      final quote = MarkdownParser.parse('> hello\n> world').single as MdQuote;
      expect(quote.text, 'hello\nworld');
    });

    test('horizontal rule', () {
      final blocks = MarkdownParser.parse('a\n\n---\n\nb');
      expect(blocks[1], isA<MdRule>());
    });

    test('Windows line endings are normalised', () {
      final blocks = MarkdownParser.parse('a\r\n\r\nb');
      expect(blocks.length, 2);
      expect((blocks[0] as MdParagraph).text, 'a');
      expect((blocks[1] as MdParagraph).text, 'b');
    });

    test('raw HTML lines are reduced to their visible text', () {
      expect(MarkdownParser.parse('<p align="center">'), isEmpty);
      final blocks = MarkdownParser.parse('<h1>Hi</h1>');
      expect((blocks.single as MdParagraph).text, 'Hi');
    });

    test('empty input yields no blocks', () {
      expect(MarkdownParser.parse(''), isEmpty);
      expect(MarkdownParser.parse('\n\n  \n'), isEmpty);
    });
  });

  group('MarkdownParser.parseInline', () {
    test('plain text is a single span', () {
      final spans = MarkdownParser.parseInline('just text');
      expect(spans.length, 1);
      expect(spans.single.text, 'just text');
      expect(spans.single.bold, isFalse);
    });

    test('bold', () {
      final spans = MarkdownParser.parseInline('a **b** c');
      expect(spans.map((s) => s.text), ['a ', 'b', ' c']);
      expect(spans.map((s) => s.bold), [false, true, false]);
    });

    test('italic with stars', () {
      final spans = MarkdownParser.parseInline('a *b* c');
      expect(spans.map((s) => s.text), ['a ', 'b', ' c']);
      expect(spans[1].italic, isTrue);
    });

    test('underscores inside words are not italics', () {
      final spans = MarkdownParser.parseInline('snake_case_name');
      expect(spans.length, 1);
      expect(spans.single.text, 'snake_case_name');
      expect(spans.single.italic, isFalse);
    });

    test('strikethrough', () {
      final spans = MarkdownParser.parseInline('~~x~~');
      expect(spans.single.text, 'x');
      expect(spans.single.strike, isTrue);
    });

    test('inline code', () {
      final spans = MarkdownParser.parseInline('use `x` now');
      expect(spans.map((s) => s.text), ['use ', 'x', ' now']);
      expect(spans[1].code, isTrue);
    });

    test('links carry their url on every span of the label', () {
      final spans = MarkdownParser.parseInline('see [site](https://e.com) ok');
      expect(spans.map((s) => s.text), ['see ', 'site', ' ok']);
      expect(spans[0].link, isNull);
      expect(spans[1].link, 'https://e.com');
      expect(spans[2].link, isNull);
    });

    test('styled link labels keep both the style and the link', () {
      final spans = MarkdownParser.parseInline('[**x**](u)');
      expect(spans.single.text, 'x');
      expect(spans.single.bold, isTrue);
      expect(spans.single.link, 'u');
    });

    test('images become a text placeholder', () {
      expect(
        MarkdownParser.parseInline('![logo](a.png)').single.text,
        '[صورة: logo]',
      );
      expect(MarkdownParser.parseInline('![](a.png)').single.text, '[صورة]');
    });

    test('autolinks', () {
      final span = MarkdownParser.parseInline('<https://e.com>').single;
      expect(span.text, 'https://e.com');
      expect(span.link, 'https://e.com');
    });

    test('inline HTML tags are dropped', () {
      final spans = MarkdownParser.parseInline('a<br>b');
      expect(spans.map((s) => s.text), ['a', 'b']);
    });
  });
}
