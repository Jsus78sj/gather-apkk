import '../../../core/network/github_api_client.dart';

/// Human-readable summary of what a batch of [FileOp]s will change.
/// Used by the confirmation modal before anything is written.
class RepoChangePlan {
  final List<String> addedPaths;
  final List<String> modifiedPaths;
  final List<String> deletedPaths;
  final List<({String from, String to})> renamedPaths;

  /// Number of blobs that must be uploaded (new or edited content).
  final int uploadCount;

  const RepoChangePlan({
    required this.addedPaths,
    required this.modifiedPaths,
    required this.deletedPaths,
    required this.renamedPaths,
    required this.uploadCount,
  });

  int get totalChanges =>
      addedPaths.length +
      modifiedPaths.length +
      deletedPaths.length +
      renamedPaths.length;

  bool get isEmpty => totalChanges == 0;

  /// Default commit message, e.g. `Nexus: add 1, update 2, delete 3`.
  String get defaultCommitMessage {
    final parts = <String>[
      if (addedPaths.isNotEmpty) 'add ${addedPaths.length}',
      if (modifiedPaths.isNotEmpty) 'update ${modifiedPaths.length}',
      if (deletedPaths.isNotEmpty) 'delete ${deletedPaths.length}',
      if (renamedPaths.isNotEmpty) 'rename ${renamedPaths.length}',
    ];
    if (parts.isEmpty) return 'Nexus: update repository';
    return 'Nexus: ${parts.join(', ')}';
  }
}

/// Outcome of a successful atomic file-operations commit.
///
/// [previousCommitSha] / [previousTreeSha] allow a one-tap undo through
/// `RepoFilesEngine.undoCommit`.
class RepoCommitResult {
  final CreatedCommitResult commit;
  final String previousCommitSha;
  final String previousTreeSha;
  final String newTreeSha;
  final RepoChangePlan plan;

  /// Blob SHA of every path whose content was uploaded by this commit
  /// (new or edited files). Renames and deletes upload nothing.
  final Map<String, String> uploadedBlobShas;

  const RepoCommitResult({
    required this.commit,
    required this.previousCommitSha,
    required this.previousTreeSha,
    required this.newTreeSha,
    required this.plan,
    this.uploadedBlobShas = const <String, String>{},
  });
}
