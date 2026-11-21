import 'repo_change_plan.dart';
import 'repo_file_content.dart';

/// Outcome of saving an edited file from the editor (one atomic commit).
class RepoFileSaveResult {
  /// The commit that was created (also what the undo bar reverts).
  final RepoCommitResult commit;

  /// The file as it now exists on the branch (new blob SHA and size), so the
  /// viewer can show the saved content without guessing.
  ///
  /// `null` only if GitHub did not report a blob for the path, which does not
  /// happen for an edit; callers then simply keep what they show.
  final RepoFileRef? updatedFile;

  const RepoFileSaveResult({
    required this.commit,
    required this.updatedFile,
  });
}
