import 'dart:typed_data';

/// A single staged change against a repository branch.
///
/// Several [FileOp]s are resolved together and committed atomically by
/// `RepoFilesEngine`. Paths are repository-relative, use `/` and have no
/// leading or trailing slash.
sealed class FileOp {
  const FileOp();
}

/// Creates a new file. Fails if the path already exists.
final class CreateFileOp extends FileOp {
  final String path;
  final Uint8List bytes;
  final String mode;

  const CreateFileOp({
    required this.path,
    required this.bytes,
    this.mode = '100644',
  });
}

/// Replaces the content of an existing file (its mode is preserved).
final class UpdateFileOp extends FileOp {
  final String path;
  final Uint8List bytes;

  const UpdateFileOp({required this.path, required this.bytes});
}

/// Deletes a file, or a folder together with everything inside it.
final class DeleteOp extends FileOp {
  final String path;

  const DeleteOp(this.path);
}

/// Renames or moves a file or a whole folder without re-uploading content.
final class RenameOp extends FileOp {
  final String fromPath;
  final String toPath;

  const RenameOp({required this.fromPath, required this.toPath});
}
