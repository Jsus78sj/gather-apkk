import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/core/network/github_api_client.dart';
import 'package:github_nexus/features/repo_browser/domain/repo_search_index.dart';

RemoteTreeBlob _blob(String path, {int size = 1, String mode = '100644'}) =>
    RemoteTreeBlob(path: path, sha: 'sha:$path', mode: mode, size: size);

RepoSearchIndex _sample() => RepoSearchIndex.fromBlobs([
      _blob('README.md'),
      _blob('lib/main.dart', size: 20),
      _blob('lib/utils/a.dart'),
      _blob('lib/utils/b.dart'),
      _blob('docs/دليل المستخدم.md'),
    ]);

void main() {
  test('the index holds every file plus each ancestor folder once', () {
    // 5 files + folders: lib, lib/utils, docs.
    expect(_sample().length, 8);
  });

  test('blank queries return nothing', () {
    final result = _sample().search('   ');
    expect(result.hits, isEmpty);
    expect(result.total, 0);
  });

  test('folders can be found, and rank before files that only match by path',
      () {
    final result = _sample().search('utils');
    expect(
      result.hits.map((h) => h.path),
      ['lib/utils', 'lib/utils/a.dart', 'lib/utils/b.dart'],
    );
    expect(result.hits.first.isFolder, isTrue);
    expect(result.total, 3);
  });

  test('search is case-insensitive and carries file details', () {
    final result = _sample().search('MAIN');
    expect(result.total, 1);
    final hit = result.hits.single;
    expect(hit.path, 'lib/main.dart');
    expect(hit.name, 'main.dart');
    expect(hit.parentPath, 'lib');
    expect(hit.isFolder, isFalse);
    expect(hit.size, 20);
    expect(hit.sha, 'sha:lib/main.dart');
  });

  test('every word must match somewhere in the path', () {
    final result = _sample().search('lib a.dart');
    expect(result.hits.map((h) => h.path), ['lib/utils/a.dart']);
  });

  test('file names starting with the query come first', () {
    final index = RepoSearchIndex.fromBlobs([
      _blob('src/zzmain.dart'),
      _blob('main.dart'),
      _blob('src/main_test.dart'),
    ]);
    expect(
      index.search('main').hits.map((h) => h.path),
      ['main.dart', 'src/main_test.dart', 'src/zzmain.dart'],
    );
  });

  test('Arabic names are searchable', () {
    final result = _sample().search('دليل');
    expect(result.hits.single.path, 'docs/دليل المستخدم.md');
  });

  test('the display limit caps hits but not the total', () {
    final index = RepoSearchIndex.fromBlobs([
      for (var i = 0; i < 300; i++) _blob('f$i.txt'),
    ]);
    final result = index.search('f', limit: 50);
    expect(result.hits.length, 50);
    expect(result.total, 300);
  });
}
