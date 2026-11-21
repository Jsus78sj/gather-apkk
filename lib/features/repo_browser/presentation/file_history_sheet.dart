import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/nexus_toast.dart';
import '../domain/repo_commit_summary.dart';
import '../domain/repo_file_content.dart';
import 'repo_browser_controller.dart';

/// يعرض سجل الـ Commits لملف محدد مع زر استعادة أي نسخة سابقة.
/// يُرجع [RepoFileRef] المحدّث إذا نُفّذت استعادة، أو `null`.
Future<RepoFileRef?> showFileHistorySheet(
  BuildContext context, {
  required RepoFileRef file,
  required bool canPush,
}) {
  return showModalBottomSheet<RepoFileRef?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FileHistorySheet(file: file, canPush: canPush),
  );
}

class _FileHistorySheet extends ConsumerStatefulWidget {
  final RepoFileRef file;
  final bool canPush;

  const _FileHistorySheet({required this.file, required this.canPush});

  @override
  ConsumerState<_FileHistorySheet> createState() => _FileHistorySheetState();
}

class _FileHistorySheetState extends ConsumerState<_FileHistorySheet> {
  List<RepoCommitSummary> _commits = const [];
  bool _loading = true;
  bool _restoring = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await ref
        .read(repoBrowserControllerProvider.notifier)
        .fetchFileHistory(widget.file.path);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.isSuccess) {
        _commits = res.value!;
      } else {
        _error = res.message ?? 'تعذر تحميل سجل التعديلات.';
      }
    });
  }

  Future<void> _restore(RepoCommitSummary commit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.84),
      builder: (_) => AlertDialog(
        backgroundColor: NexusColors.bgSurface,
        title: const Text('استعادة نسخة سابقة'),
        content: Text(
          'سيتم استعادة "${widget.file.name}" إلى محتواه في الـ Commit '
          '${commit.shortSha} عبر إنشاء Commit جديد على رأس الفرع.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _restoring = true);
    final res = await ref
        .read(repoBrowserControllerProvider.notifier)
        .restoreFileFromCommit(filePath: widget.file.path, commit: commit);
    if (!mounted) return;
    setState(() => _restoring = false);

    if (res.isSuccess) {
      showNexusToast(
        context,
        'تمت استعادة النسخة ${commit.shortSha} بنجاح.',
        type: NexusToastType.success,
      );
      Navigator.of(context).pop(res.value!.updatedFile);
    } else {
      showNexusToast(
        context,
        res.message ?? 'تعذرت استعادة النسخة.',
        type: NexusToastType.error,
      );
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
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
                  Icons.history_rounded,
                  color: NexusColors.primarySoft,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'سجل تعديلات الملف',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: NexusColors.textPrimary,
                        ),
                      ),
                      Text(
                        widget.file.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: NexusColors.textMuted,
                        ),
                      ),
                    ],
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
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 160, maxHeight: 380),
              child: _loading || _restoring
                  ? const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: NexusColors.primarySoft,
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error!,
                                style: const TextStyle(
                                  color: NexusColors.roseSoft,
                                  fontSize: 13,
                                ),
                              ),
                              TextButton(
                                onPressed: _load,
                                child: const Text('إعادة المحاولة'),
                              ),
                            ],
                          ),
                        )
                      : _commits.isEmpty
                          ? const Center(
                              child: Text(
                                'لا يوجد سجل تعديلات لهذا الملف.',
                                style: TextStyle(color: NexusColors.textMuted),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: _commits.length,
                              separatorBuilder: (_, __) => const Divider(
                                height: 1,
                                color: NexusColors.borderSubtle,
                              ),
                              itemBuilder: (_, idx) {
                                final c = _commits[idx];
                                final isLatest = idx == 0;
                                return ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  title: Text(
                                    c.title.isEmpty ? '(بدون عنوان)' : c.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: NexusColors.textPrimary,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '${c.shortSha} · ${c.authorName} · ${_formatDate(c.authoredAt)}',
                                      textDirection: TextDirection.ltr,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 10.5,
                                        color: NexusColors.textMuted,
                                      ),
                                    ),
                                  ),
                                  trailing: isLatest
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: NexusColors.success
                                                .withOpacity(0.14),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: const Text(
                                            'الحالية',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: NexusColors.successSoft,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        )
                                      : (widget.canPush
                                          ? TextButton(
                                              onPressed: () => _restore(c),
                                              child: const Text(
                                                'استعادة',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      NexusColors.warningSoft,
                                                ),
                                              ),
                                            )
                                          : null),
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
