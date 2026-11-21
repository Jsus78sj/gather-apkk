import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/features/repo_browser/domain/syntax_highlighter.dart';

bool _has(List<HighlightSpan> line, TokenType type, String text) =>
    line.any((s) => s.type == type && s.text == text);

void main() {
  group('line splitting', () {
    test('empty input is one empty line', () {
      final lines = SyntaxHighlighter.highlight('', null);
      expect(lines.length, 1);
      expect(lines.single, isEmpty);
    });

    test('unknown language is plain text split per line', () {
      final lines = SyntaxHighlighter.highlight('a\nb', 'brainfuck');
      expect(lines.length, 2);
      expect(lines[0].single.text, 'a');
      expect(lines[0].single.type, TokenType.plain);
      expect(lines[1].single.text, 'b');
    });

    test('CR before LF is dropped and a trailing newline adds an empty line', () {
      final lines = SyntaxHighlighter.highlight('a\r\nb\n', null);
      expect(lines.length, 3);
      expect(lines[0].single.text, 'a');
      expect(lines[1].single.text, 'b');
      expect(lines[2], isEmpty);
    });
  });

  group('code languages', () {
    test('dart: keyword, number and line comment', () {
      final line = SyntaxHighlighter.highlight(
        'final x = 42; // note',
        'dart',
      ).single;
      expect(_has(line, TokenType.keyword, 'final'), isTrue);
      expect(_has(line, TokenType.number, '42'), isTrue);
      expect(_has(line, TokenType.comment, '// note'), isTrue);
    });

    test('dart: capitalised identifiers are types, lower-case are plain', () {
      final line = SyntaxHighlighter.highlight('Foo bar', 'dart').single;
      expect(line.first.type, TokenType.type);
      expect(line.first.text, 'Foo');
      expect(line.last.type, TokenType.plain);
    });

    test('a comment marker inside a string stays part of the string', () {
      final line = SyntaxHighlighter.highlight(
        'var s = "hi // not comment";',
        'dart',
      ).single;
      expect(_has(line, TokenType.string, '"hi // not comment"'), isTrue);
      expect(line.any((s) => s.type == TokenType.comment), isFalse);
    });

    test('block comments span lines and unterminated ones run to the end', () {
      final lines = SyntaxHighlighter.highlight('/* a\nb */ x', 'dart');
      expect(lines.length, 2);
      expect(lines[0].single.type, TokenType.comment);
      expect(lines[0].single.text, '/* a');
      expect(lines[1].first.type, TokenType.comment);
      expect(lines[1].first.text, 'b */');

      final open = SyntaxHighlighter.highlight('/* abc', 'dart').single;
      expect(open.single.type, TokenType.comment);
      expect(open.single.text, '/* abc');
    });

    test('json: keys differ from string values', () {
      final line = SyntaxHighlighter.highlight(
        '{"a": "v", "n": 1, "t": true}',
        'json',
      ).single;
      expect(_has(line, TokenType.key, '"a"'), isTrue);
      expect(_has(line, TokenType.string, '"v"'), isTrue);
      expect(_has(line, TokenType.number, '1'), isTrue);
      expect(_has(line, TokenType.keyword, 'true'), isTrue);
    });

    test('yaml: keys and comments', () {
      final line = SyntaxHighlighter.highlight('name: value # c', 'yaml').single;
      expect(_has(line, TokenType.key, 'name'), isTrue);
      expect(_has(line, TokenType.comment, '# c'), isTrue);
    });

    test('python: triple-quoted strings span lines', () {
      final lines = SyntaxHighlighter.highlight(
        '"""doc\nmore"""\nx = 1',
        'python',
      );
      expect(lines.length, 3);
      expect(lines[0].first.type, TokenType.string);
      expect(lines[1].first.type, TokenType.string);
      expect(_has(lines[2], TokenType.number, '1'), isTrue);
    });

    test('shell: comments and variables', () {
      final lines = SyntaxHighlighter.highlight(
        '# build\necho \$HOME',
        'shell',
      );
      expect(lines[0].single.type, TokenType.comment);
      expect(_has(lines[1], TokenType.keyword, 'echo'), isTrue);
      expect(_has(lines[1], TokenType.meta, '\$HOME'), isTrue);
    });
  });

  group('markup', () {
    test('tags, attributes, strings and text', () {
      final line = SyntaxHighlighter.highlight(
        '<a href="x">hi</a>',
        'xml',
      ).single;
      expect(_has(line, TokenType.tag, '<a'), isTrue);
      expect(_has(line, TokenType.attribute, 'href'), isTrue);
      expect(_has(line, TokenType.string, '"x"'), isTrue);
      expect(_has(line, TokenType.plain, 'hi'), isTrue);
    });

    test('comments', () {
      final line = SyntaxHighlighter.highlight('<!-- c -->', 'xml').single;
      expect(line.single.type, TokenType.comment);
    });
  });

  test('every language id used by the app is supported', () {
    // Ids produced by RepoFileKinds.languageOf must not fall back to plain
    // text by accident: each one has to tokenize a trivial snippet.
    const ids = [
      'dart', 'js', 'ts', 'json', 'yaml', 'toml', 'xml', 'css', 'python',
      'ruby', 'java', 'kotlin', 'swift', 'go', 'rust', 'c', 'cpp', 'csharp',
      'php', 'shell', 'sql', 'dockerfile', 'makefile',
    ];
    for (final id in ids) {
      final lines = SyntaxHighlighter.highlight('x 1 "s" # c', id);
      expect(lines, isNotEmpty, reason: id);
    }
  });

  test('large files tokenize into the expected number of lines', () {
    final source = List.filled(20000, 'final a = 1;').join('\n');
    final lines = SyntaxHighlighter.highlight(source, 'dart');
    expect(lines.length, 20000);
  });
}
