import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_file_content.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_file_kind.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_text_codec.dart';

void main() {
  test('preserves CRLF line endings and UTF-8 BOM on round-trip', () {
    final encoded = RepoTextCodec.encodeForCommit(
      'line1\nline2\n',
      originalLineEnding: LineEnding.crlf,
      hasBom: true,
    );
    expect(encoded.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    expect(utf8.decode(encoded.sublist(3)), 'line1\r\nline2\r\n');
  });

  test('preserves LF without BOM when original had LF and no BOM', () {
    final encoded = RepoTextCodec.encodeForCommit(
      'a\nb\n',
      originalLineEnding: LineEnding.lf,
      hasBom: false,
    );
    expect(utf8.decode(encoded), 'a\nb\n');
  });

  test('edit guard blocks binary, oversized, symlink, and read-only repos', () {
    const baseRef = RepoFileRef(path: 'a.dart', sha: 's1', size: 100);
    const textContent = RepoFileContent(
      file: baseRef,
      kind: RepoFileKind.text,
      text: 'hello',
    );

    expect(RepoEditGuard.whyNotEditable(textContent, canPush: true), isNull);
    expect(
      RepoEditGuard.whyNotEditable(textContent, canPush: false),
      isNotNull,
    );

    const binaryContent = RepoFileContent(
      file: RepoFileRef(path: 'app.apk', sha: 's2', size: 500),
      kind: RepoFileKind.binary,
    );
    expect(
      RepoEditGuard.whyNotEditable(binaryContent, canPush: true),
      isNotNull,
    );

    const hugeContent = RepoFileContent(
      file: RepoFileRef(
        path: 'big.json',
        sha: 's3',
        size: RepoFileKinds.maxTextPreviewBytes + 1,
      ),
      kind: RepoFileKind.text,
      text: 'x',
    );
    expect(
      RepoEditGuard.whyNotEditable(hugeContent, canPush: true),
      isNotNull,
    );

    const symlinkContent = RepoFileContent(
      file: RepoFileRef(
        path: 'link',
        sha: 's4',
        size: 10,
        mode: '120000',
      ),
      kind: RepoFileKind.text,
      text: 'target.txt',
    );
    expect(
      RepoEditGuard.whyNotEditable(symlinkContent, canPush: true),
      isNotNull,
    );
  });
}
