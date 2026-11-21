import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/core/network/github_api_client.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_path_validator.dart';

class _StubResponse {
  final int status;
  final String body;
  const _StubResponse(this.status, this.body);
}

class _StubAdapter implements HttpClientAdapter {
  final Map<String, _StubResponse> responses;
  final List<RequestOptions> requests = [];

  _StubAdapter(this.responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final stub = responses[options.uri.path] ??
        const _StubResponse(404, '{"message":"Not Found"}');
    return ResponseBody.fromString(
      stub.body,
      stub.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

GitHubApiClient _client(_StubAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: GitHubApiClient.baseUrl,
      validateStatus: (s) => s != null && s < 500 && s != 429,
    ),
  );
  dio.httpClientAdapter = adapter;
  return GitHubApiClient(dio: dio);
}

void main() {
  group('fetchFileBlob', () {
    test('decodes base64 content that GitHub wraps with newlines', () async {
      final adapter = _StubAdapter({
        '/repos/o/r/git/blobs/abc': const _StubResponse(
          200,
          '{"content":"SGVsbG8s\\nIHdvcmxk\\n","encoding":"base64","size":12}',
        ),
      });
      final bytes = await _client(adapter).fetchFileBlob(
        token: 't',
        owner: 'o',
        repo: 'r',
        blobSha: 'abc',
      );
      expect(utf8.decode(bytes), 'Hello, world');
    });

    test('handles utf-8 encoded blobs', () async {
      final adapter = _StubAdapter({
        '/repos/o/r/git/blobs/abc': _StubResponse(
          200,
          jsonEncode({'content': 'مرحبا', 'encoding': 'utf-8'}),
        ),
      });
      final bytes = await _client(adapter).fetchFileBlob(
        token: 't',
        owner: 'o',
        repo: 'r',
        blobSha: 'abc',
      );
      expect(utf8.decode(bytes), 'مرحبا');
    });
  });

  group('fetchTreeShallow', () {
    test('parses files, folders and submodules', () async {
      final adapter = _StubAdapter({
        '/repos/o/r/git/trees/root': const _StubResponse(
          200,
          '{"sha":"root","truncated":false,"tree":['
              '{"path":"src","mode":"040000","type":"tree","sha":"s1"},'
              '{"path":"a.txt","mode":"100644","type":"blob","sha":"b1","size":5},'
              '{"path":"run.sh","mode":"100755","type":"blob","sha":"b2","size":9},'
              '{"path":"sub","mode":"160000","type":"commit","sha":"c1"}]}',
        ),
      });
      final result = await _client(adapter).fetchTreeShallow(
        token: 't',
        owner: 'o',
        repo: 'r',
        treeSha: 'root',
      );

      expect(result.truncated, isFalse);
      expect(result.entries.length, 4);
      expect(result.entries[0].isFolder, isTrue);
      expect(result.entries[1].isFile, isTrue);
      expect(result.entries[1].size, 5);
      expect(result.entries[2].isExecutable, isTrue);
      expect(result.entries[3].isSubmodule, isTrue);
    });

    test('empty repository (409) yields an empty listing', () async {
      final adapter = _StubAdapter({
        '/repos/o/r/git/trees/root': const _StubResponse(
          409,
          '{"message":"Git Repository is empty."}',
        ),
      });
      final result = await _client(adapter).fetchTreeShallow(
        token: 't',
        owner: 'o',
        repo: 'r',
        treeSha: 'root',
      );
      expect(result.entries, isEmpty);
    });
  });

  group('fetchCommits', () {
    test('parses commits and sends the path filter', () async {
      final adapter = _StubAdapter({
        '/repos/o/r/commits': const _StubResponse(
          200,
          '[{"sha":"abcdef1234567","html_url":"https://github.com/o/r/commit/abcdef1234567",'
              '"commit":{"message":"fix: a\\n\\nbody","author":{"name":"Ali","date":"2026-11-20T10:00:00Z"}}}]',
        ),
      });
      final commits = await _client(adapter).fetchCommits(
        token: 't',
        owner: 'o',
        repo: 'r',
        branchName: 'main',
        path: 'lib/main.dart',
      );

      expect(commits.single.shortSha, 'abcdef1');
      expect(commits.single.title, 'fix: a');
      expect(commits.single.authorName, 'Ali');
      expect(commits.single.authoredAt, isNotNull);
      expect(adapter.requests.single.queryParameters['path'], 'lib/main.dart');
      expect(adapter.requests.single.queryParameters['sha'], 'main');
    });

    test('empty repository (409) yields an empty list', () async {
      final adapter = _StubAdapter({
        '/repos/o/r/commits':
            const _StubResponse(409, '{"message":"Git Repository is empty."}'),
      });
      final commits = await _client(adapter).fetchCommits(
        token: 't',
        owner: 'o',
        repo: 'r',
        branchName: 'main',
      );
      expect(commits, isEmpty);
    });
  });

  group('RepoPathValidator', () {
    test('accepts normal, spaced and Arabic paths', () {
      for (final path in [
        'README.md',
        'lib/src/main.dart',
        'docs/دليل المستخدم.md',
        'my folder/file one.txt',
        '.github/workflows/build.yml',
      ]) {
        expect(RepoPathValidator.validate(path), isNull, reason: path);
      }
    });

    test('rejects invalid paths', () {
      for (final path in [
        '',
        '   ',
        '/a',
        'a/',
        'a//b',
        'a/../b',
        './a',
        '.git',
        'x/.GIT/config',
        'a\\b',
        'a\u0000b',
      ]) {
        expect(RepoPathValidator.validate(path), isNotNull, reason: path);
      }
    });

    test('helpers', () {
      expect(RepoPathValidator.isInside('a/b', 'a/b/c.txt'), isTrue);
      expect(RepoPathValidator.isInside('a/b', 'a/bc/d.txt'), isFalse);
      expect(RepoPathValidator.parentOf('a/b/c.txt'), 'a/b');
      expect(RepoPathValidator.parentOf('c.txt'), '');
      expect(RepoPathValidator.nameOf('a/b/c.txt'), 'c.txt');
    });
  });
}
