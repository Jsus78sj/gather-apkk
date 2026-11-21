import 'repo_change_plan.dart';

/// نوع تغيير المسار (إعادة تسمية أو نقل).
enum RepoPathChangeKind { rename, move }

/// مثال واحد لعنصر متأثر يظهر داخل نافذة التأكيد.
class RepoPathChangeSample {
  final String fromPath;
  final String toPath;
  final bool isFolder;
  final int fileCount;

  const RepoPathChangeSample({
    required this.fromPath,
    required this.toPath,
    required this.isFolder,
    required this.fileCount,
  });
}

/// معاينة عملية نقل أو إعادة تسمية قبل كتابة أي Commit.
class RepoPathChangePreview {
  final RepoPathChangeKind kind;
  final RepoChangePlan plan;
  final List<RepoPathChangeSample> items;
  final String destinationLabel;
  final String defaultMessage;

  const RepoPathChangePreview({
    required this.kind,
    required this.plan,
    required this.items,
    required this.destinationLabel,
    required this.defaultMessage,
  });

  factory RepoPathChangePreview.build({
    required RepoPathChangeKind kind,
    required RepoChangePlan plan,
    required List<({String from, String to, bool isFolder})> selectedMoves,
    required String destinationFolder,
  }) {
    final samples = <RepoPathChangeSample>[
      for (final m in selectedMoves)
        RepoPathChangeSample(
          fromPath: m.from,
          toPath: m.to,
          isFolder: m.isFolder,
          fileCount: m.isFolder
              ? plan.renamedPaths
                  .where((r) => r.from.startsWith('${m.from}/'))
                  .length
              : 1,
        ),
    ];

    final destLabel = destinationFolder.isEmpty ? '/' : '$destinationFolder/';
    final String message;
    if (kind == RepoPathChangeKind.rename && selectedMoves.length == 1) {
      final only = selectedMoves.first;
      message = 'Nexus: rename ${only.from} to ${only.to}';
    } else if (selectedMoves.length == 1) {
      final only = selectedMoves.first;
      message = 'Nexus: move ${only.from} to ${only.to}';
    } else {
      message = 'Nexus: move ${selectedMoves.length} items to $destLabel';
    }

    return RepoPathChangePreview(
      kind: kind,
      plan: plan,
      items: List.unmodifiable(samples),
      destinationLabel: destLabel,
      defaultMessage: message,
    );
  }

  int get itemCount => items.length;
  int get totalFileCount => plan.renamedPaths.length;
  bool get hasFolders => items.any((i) => i.isFolder);

  List<RepoPathChangeSample> visibleSamples({int max = 6}) =>
      items.length <= max ? items : items.sublist(0, max);

  int hiddenCount({int max = 6}) => itemCount > max ? itemCount - max : 0;
}
