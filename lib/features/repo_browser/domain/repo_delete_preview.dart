import 'repo_change_plan.dart';

/// One selected item shown as an example in the delete confirmation.
class RepoDeleteSample {
  final String path;
  final bool isFolder;

  /// Files that disappear with this item (1 for a file).
  final int fileCount;

  const RepoDeleteSample({
    required this.path,
    required this.isFolder,
    required this.fileCount,
  });
}

/// What the delete confirmation dialog needs: the resolved [plan] plus the
/// items the user actually selected (a folder counts as one item).
class RepoDeletePreview {
  final RepoChangePlan plan;
  final List<String> folderPaths;
  final List<String> filePaths;

  /// Suggested commit message (editable by the user).
  final String defaultMessage;

  const RepoDeletePreview({
    required this.plan,
    required this.folderPaths,
    required this.filePaths,
    required this.defaultMessage,
  });

  factory RepoDeletePreview.build({
    required RepoChangePlan plan,
    required List<String> folderPaths,
    required List<String> filePaths,
  }) {
    final all = [...folderPaths, ...filePaths];
    final message = all.length <= 2
        ? 'Nexus: delete ${all.join(', ')}'
        : 'Nexus: delete ${all.length} items';
    return RepoDeletePreview(
      plan: plan,
      folderPaths: List.unmodifiable(folderPaths),
      filePaths: List.unmodifiable(filePaths),
      defaultMessage: message,
    );
  }

  int get itemCount => folderPaths.length + filePaths.length;

  /// Every file that will be removed from the tree (folders expanded).
  int get totalFileCount => plan.deletedPaths.length;

  bool get hasFolders => folderPaths.isNotEmpty;

  int filesInFolder(String folder) =>
      plan.deletedPaths.where((p) => p.startsWith('$folder/')).length;

  /// Selected items, folders first, at most [max] of them.
  List<RepoDeleteSample> samples({int max = 6}) {
    final all = <RepoDeleteSample>[
      for (final f in folderPaths)
        RepoDeleteSample(
          path: f,
          isFolder: true,
          fileCount: filesInFolder(f),
        ),
      for (final f in filePaths)
        RepoDeleteSample(path: f, isFolder: false, fileCount: 1),
    ];
    return all.length <= max ? all : all.sublist(0, max);
  }

  /// Selected items that do not fit in [samples].
  int hiddenCount({int max = 6}) => itemCount > max ? itemCount - max : 0;
}
