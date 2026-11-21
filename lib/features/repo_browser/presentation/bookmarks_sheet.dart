import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../domain/repo_bookmarks.dart';
import 'repo_bookmarks_controller.dart';

/// يعرض المفضلة والملفات الحديثة للمستودع والفرع الحاليين.
/// يُرجع العنصر الذي اختاره المستخدم للانتقال المباشر إليه، أو `null`.
Future<RepoBookmarkEntry?> showRepoBookmarksSheet(
  BuildContext context, {
  required String repoFullName,
  required String branchName,
}) {
  return showModalBottomSheet<RepoBookmarkEntry?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RepoBookmarksSheet(
      repoFullName: repoFullName,
      branchName: branchName,
    ),
  );
}

class _RepoBookmarksSheet extends ConsumerStatefulWidget {
  final String repoFullName;
  final String branchName;

  const _RepoBookmarksSheet({
    required this.repoFullName,
    required this.branchName,
  });

  @override
  ConsumerState<_RepoBookmarksSheet> createState() =>
      _RepoBookmarksSheetState();
}

class _RepoBookmarksSheetState extends ConsumerState<_RepoBookmarksSheet> {
  int _tab = 0; // 0 = المفضلة، 1 = الحديثة

  @override
  Widget build(BuildContext context) {
    final bookmarks = ref.watch(repoBookmarksProvider);
    final items = _tab == 0
        ? bookmarks.favoritesFor(widget.repoFullName, widget.branchName)
        : bookmarks.recentsFor(widget.repoFullName, widget.branchName);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 32, 12, 12),
      child: GlassPanel(
        strong: true,
        borderRadius: 24,
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.bookmarks_outlined,
                  color: NexusColors.warningSoft,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'المفضلة والملفات الحديثة',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: NexusColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: NexusColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.star_rounded, size: 16),
                  label: Text('المفضلة'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.schedule_rounded, size: 16),
                  label: Text('الحديثة'),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 140, maxHeight: 340),
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        _tab == 0
                            ? 'لا توجد ملفات أو مجلدات مفضلة في هذا الفرع بعد.'
                            : 'لم تفتح أي ملفات مؤخراً في هذا الفرع.',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: NexusColors.textMuted,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        color: NexusColors.borderSubtle,
                      ),
                      itemBuilder: (_, idx) {
                        final item = items[idx];
                        return Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                          dense: true,
                          leading: Icon(
                            item.isFolder
                                ? Icons.folder_rounded
                                : Icons.description_outlined,
                            color: item.isFolder
                                ? NexusColors.warningSoft
                                : NexusColors.primarySoft,
                          ),
                          title: Text(
                            item.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              color: NexusColors.textPrimary,
                            ),
                          ),
                          trailing: _tab == 0
                              ? IconButton(
                                  tooltip: 'إزالة من المفضلة',
                                  onPressed: () => ref
                                      .read(repoBookmarksProvider.notifier)
                                      .toggleFavorite(
                                        repoFullName: item.repoFullName,
                                        branchName: item.branchName,
                                        path: item.path,
                                        isFolder: item.isFolder,
                                      ),
                                  icon: const Icon(
                                    Icons.star_rounded,
                                    color: NexusColors.warningSoft,
                                    size: 19,
                                  ),
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(item),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
