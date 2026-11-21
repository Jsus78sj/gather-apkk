import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_file_content.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_file_kind.dart';

RepoFileRef _ref(
  String path, {
  int size = 10,
  String mode = '100644',
}) =>
    RepoFileRef(path: path, sha: 'sha_$path', size: size, mode: mode);

Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  group('RepoFileKinds.byName', () {
    test('classifies images, markdown, binaries and text by extension', () {
      expect(RepoFileKinds.byName('logo.PNG'), RepoFileKind.image);
      expect(RepoFileKinds.byName('README.md'), RepoFileKind.markdown);
      expect(RepoFileKinds.byName('notes.markdown'), RepoFileKind.markdown);
      expect(RepoFileKinds.byName('app.zip'), RepoFileKind.binary);
      expect(RepoFileKinds.byName('font.woff2'), RepoFileKind.binary);
      expect(RepoFileKinds.byName('main.dart'), RepoFileKind.text);
      expect(RepoFileKinds.byName('data.csv'), RepoFileKind.text);
    });

    test('recognises well-known files without an extension', () {
      expect(RepoFileKinds.byName('Dockerfile'), RepoFileKind.text);
      expect(RepoFileKinds.byName('Makefile'), RepoFileKind.text);
      expect(RepoFileKinds.byName('LICENSE'), RepoFileKind.text);
      expect(RepoFileKinds.byName('.gitignore'), RepoFileKind.text);
    });

    test('returns null when the name alone cannot decide', () {
      expect(RepoFileKinds.byName('mystery.xyz'), isNull);
      expect(RepoFileKinds.byName('noextension'), isNull);
    });
  });

  group('RepoFileKinds.extensionOf / languageOf', () {
    test('extensionOf lower-cases and ignores trailing dots', () {
      expect(RepoFileKinds.extensionOf('a.b.TXT'), 'txt');
      expect(RepoFileKinds.extensionOf('Makefile'), '');
      expect(RepoFileKinds.extensionOf('trailing.'), '');
      expect(RepoFileKinds.extensionOf('.gitignore'), 'gitignore');
    });

    test('languageOf maps extensions and special file names', () {
      expect(RepoFileKinds.languageOf('App.TS'), 'ts');
      expect(RepoFileKinds.languageOf('main.dart'), 'dart');
      expect(RepoFileKinds.languageOf('config.yml'), 'yaml');
      expect(RepoFileKinds.languageOf('Dockerfile'), 'dockerfile');
      expect(RepoFileKinds.languageOf('CMakeLists.txt'), 'makefile');
      expect(RepoFileKinds.languageOf('.gitignore'), 'shell');
      expect(RepoFileKinds.languageOf('plain.txt'), isNull);
    });
  });

  group('RepoFileKinds.looksBinary', () {
    test('empty and normal text are not binary', () {
      expect(RepoFileKinds.looksBinary(Uint8List(0)), isFalse);
      expect(RepoFileKinds.looksBinary(_utf8('hello\nworld')), isFalse);
      expect(RepoFileKinds.looksBinary(_utf8('مرحباً بالعالم')), isFalse);
    });

    test('a NUL byte means binary', () {
      expect(
        RepoFileKinds.looksBinary(Uint8List.fromList([104, 105, 0, 1])),
        isTrue,
      );
    });

    test('mostly invalid UTF-8 means binary', () {
      expect(
        RepoFileKinds.looksBinary(Uint8List.fromList(List.filled(100, 0xFF))),
        isTrue,
      );
    });
  });

  group('RepoFileContent.fromBytes', () {
    test('decodes text, detects CRLF and the highlighter language', () {
      final content = RepoFileContent.fromBytes(
        _ref('lib/a.dart'),
        _utf8('line1\r\nline2\r\n'),
      );
      expect(content.kind, RepoFileKind.text);
      expect(content.text, 'line1\r\nline2\r\n');
      expect(content.lineEnding, LineEnding.crlf);
      expect(content.hasBom, isFalse);
      expect(content.language, 'dart');
      expect(content.lineCount, 2);
    });

    test('strips and reports a UTF-8 BOM', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('x')]);
      final content = RepoFileContent.fromBytes(_ref('a.txt'), bytes);
      expect(content.hasBom, isTrue);
      expect(content.text, 'x');
    });

    test('keeps markdown kind when the name hints it', () {
      final content = RepoFileContent.fromBytes(
        _ref('README.md'),
        _utf8('# Hi'),
        hint: RepoFileKind.markdown,
      );
      expect(content.kind, RepoFileKind.markdown);
      expect(content.text, '# Hi');
    });

    test('binary content becomes an info card without text', () {
      final content = RepoFileContent.fromBytes(
        _ref('blob.dat'),
        Uint8List.fromList([1, 2, 0, 3]),
      );
      expect(content.kind, RepoFileKind.binary);
      expect(content.text, isNull);
      expect(content.notice, isNotNull);
    });

    test('oversized content is not decoded', () {
      final content = RepoFileContent.fromBytes(
        _ref('huge.txt'),
        Uint8List(RepoFileKinds.maxTextPreviewBytes + 1),
      );
      expect(content.kind, RepoFileKind.binary);
      expect(content.text, isNull);
    });

    test('a symlink carries an explanatory notice', () {
      final content = RepoFileContent.fromBytes(
        _ref('link', mode: '120000'),
        _utf8('../target'),
      );
      expect(content.notice, contains('رابط رمزي'));
      expect(content.text, '../target');
    });
  });

  group('RepoFileContent helpers', () {
    test('detectLineEnding', () {
      expect(RepoFileContent.detectLineEnding('abc'), LineEnding.none);
      expect(RepoFileContent.detectLineEnding('a\nb'), LineEnding.lf);
      expect(RepoFileContent.detectLineEnding('a\r\nb'), LineEnding.crlf);
      expect(RepoFileContent.detectLineEnding('a\r\nb\nc'), LineEnding.mixed);
    });

    test('lineCount ignores one trailing newline', () {
      RepoFileContent withText(String text) => RepoFileContent(
            file: _ref('a.txt'),
            kind: RepoFileKind.text,
            text: text,
          );
      expect(withText('').lineCount, 0);
      expect(withText('a').lineCount, 1);
      expect(withText('a\nb').lineCount, 2);
      expect(withText('a\nb\n').lineCount, 2);
    });

    test('RepoFileRef exposes name, parent and mode flags', () {
      final ref = _ref('scripts/run.sh', mode: '100755');
      expect(ref.name, 'run.sh');
      expect(ref.parentPath, 'scripts');
      expect(ref.isExecutable, isTrue);
      expect(ref.isSymlink, isFalse);
      expect(ref, _ref('scripts/run.sh', mode: '100755'));
      expect(ref.hashCode, _ref('scripts/run.sh', mode: '100755').hashCode);
    });
  });

  group('RepoFileContent.load', () {
    test('known binary types are never downloaded', () async {
      var reads = 0;
      final content = await RepoFileContent.load(_ref('app.zip'), () async {
        reads++;
        return Uint8List(0);
      });
      expect(content.kind, RepoFileKind.binary);
      expect(reads, 0);
    });

    test('images are downloaded and kept as bytes', () async {
      var reads = 0;
      final bytes = Uint8List.fromList([1, 2, 3]);
      final content = await RepoFileContent.load(_ref('logo.png'), () async {
        reads++;
        return bytes;
      });
      expect(content.kind, RepoFileKind.image);
      expect(content.imageBytes, bytes);
      expect(reads, 1);
    });

    test('oversized images and text files are not downloaded', () async {
      var reads = 0;
      Future<Uint8List> reader() async {
        reads++;
        return Uint8List(0);
      }

      final image = await RepoFileContent.load(
        _ref('big.png', size: RepoFileKinds.maxImagePreviewBytes + 1),
        reader,
      );
      final text = await RepoFileContent.load(
        _ref('big.txt', size: RepoFileKinds.maxTextPreviewBytes + 1),
        reader,
      );
      expect(image.kind, RepoFileKind.binary);
      expect(text.kind, RepoFileKind.binary);
      expect(reads, 0);
    });

    test('regular text files are downloaded once and decoded', () async {
      var reads = 0;
      final content = await RepoFileContent.load(_ref('a.json'), () async {
        reads++;
        return _utf8('{"a": 1}');
      });
      expect(content.kind, RepoFileKind.text);
      expect(content.language, 'json');
      expect(content.text, '{"a": 1}');
      expect(reads, 1);
    });
  });
}
