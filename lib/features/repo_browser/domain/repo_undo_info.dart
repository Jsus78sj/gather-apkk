import 'repo_change_plan.dart';

/// What the commit that can be reverted did (decides the wording of the
/// confirmation shown after the undo).
enum RepoUndoKind { delete, move, rename, edit, create, upload, restore }

/// The last committed change that can still be reverted with one tap.
class RepoUndoInfo {
  final RepoCommitResult result;

  /// Arabic one-liner shown in the undo bar, e.g. `تم حذف 3 عناصر`.
  final String summary;

  final RepoUndoKind kind;

  const RepoUndoInfo({
    required this.result,
    required this.summary,
    this.kind = RepoUndoKind.delete,
  });
}
