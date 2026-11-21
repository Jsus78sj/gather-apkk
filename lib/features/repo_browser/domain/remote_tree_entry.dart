/// One direct child of a Git tree (non-recursive listing).
///
/// [type] follows the Git Data API: `blob` (file), `tree` (folder) or
/// `commit` (submodule).
class RemoteTreeEntry {
  final String name;
  final String sha;
  final String mode;
  final String type;
  final int size;

  const RemoteTreeEntry({
    required this.name,
    required this.sha,
    required this.mode,
    required this.type,
    this.size = 0,
  });

  bool get isFolder => type == 'tree';
  bool get isFile => type == 'blob';
  bool get isSubmodule => type == 'commit';
  bool get isSymlink => mode == '120000';
  bool get isExecutable => mode == '100755';
}

/// Result of a non-recursive tree listing.
class ShallowTreeResult {
  final List<RemoteTreeEntry> entries;
  final bool truncated;

  const ShallowTreeResult({
    required this.entries,
    required this.truncated,
  });
}
