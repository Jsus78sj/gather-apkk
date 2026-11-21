import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/github_exceptions.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/utils/format_bytes.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/nexus_toast.dart';
import '../domain/repo_file_content.dart';
import '../domain/repo_file_kind.dart';
import '../domain/repo_text_codec.dart';
import 'file_history_sheet.dart';
import 'repo_bookmarks_controller.dart';
import 'repo_browser_controller.dart';
import 'repo_file_editor_screen.dart';
import 'widgets/code_view.dart';
import 'widgets/markdown_view.dart';
import 'widgets/repo_entry_visual.dart';
import 'widgets/repo_state_views.dart';

/// Downloads and classifies one file of the browsed snapshot.
final repoFileContentProvider = FutureProvider.autoDispose
    .family<RepoFileContent, RepoFileRef>((ref, file) async {
  final service = ref.read(repoBrowserControllerProvider.notifier).service;
  if (service == null) {
    throw const GitHubApiException('لا يوجد مستودع محمّل حالياً.');
  }

  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);

  return RepoFileContent.load(
    file,
    () => service.readBlob(file.sha, cancelToken: cancel),
  );
});

Future<void> openRepoFile(BuildContext context, RepoFileRef file) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => RepoFileViewerScreen(file: file)),
  );
}

class RepoFileViewerScreen extends ConsumerStatefulWidget {
  final RepoFileRef file;

  const RepoFileViewerScreen({super.key, required this.file});

  @override
  ConsumerState<RepoFileViewerScreen> createState() =>
      _RepoFileViewerScreenState();
}

class _RepoFileViewerScreenState extends ConsumerState<RepoFileViewerScreen> {
  bool _wrap = false;
  bool _showMarkdownSource = false;

  /// The file being shown. Starts as [RepoFileViewerScreen.file] and moves to
  /// the new version after the editor saved (or reloaded a newer one).
  late RepoFileRef _file;

  /// Branch head this file was read at: the base the editor checks for
  /// conflicts against.
  String? _openedHeadSha;

  @override
  void initState() {
    super.initState();
    _file = widget.file;
    _openedHeadSha = ref.read(repoBrowserControllerProvider).headCommitSha;
    // Modifying a provider inside initState is forbidden: run after build.
    Future.microtask(_recordRecent);
  }

  /// Feeds the "recent files" list of the current repo + branch.
  void _recordRecent() {
    final target = ref.read(repoBrowserControllerProvider).target;
    if (target == null) return;
    ref
        .read(repoBookmarksProvider.notifier)
        .recordRecentFile(
          repoFullName: target.repo.fullName,
          branchName: target.branchName,
          path: _file.path,
        );
  }

  void _toggleFavorite() {
    final target = ref.read(repoBrowserControllerProvider).target;
    if (target == null) return;
    ref
        .read(repoBookmarksProvider.notifier)
        .toggleFavorite(
          repoFullName: target.repo.fullName,
          branchName: target.branchName,
          path: _file.path,
          isFolder: false,
        );
  }

  /// Commit history of the file shown, with a one-tap restore of any older
  /// version (creates a new commit on the branch head).
  Future<void> _showHistory() async {
    final canPush =
        ref.read(repoBrowserControllerProvider).target?.repo.canPush ?? false;
    final updated = await showFileHistorySheet(
      context,
      file: _file,
      canPush: canPush,
    );
    if (!mounted || updated == null) return;
    setState(() {
      _file = updated;
      _openedHeadSha = ref
              .read(repoBrowserControllerProvider)
              .headCommitSha ??
          _openedHeadSha;
    });
  }

  Future<void> _openEditor(RepoFileContent content) async {
    final browser = ref.read(repoBrowserControllerProvider);
    final reason = RepoEditGuard.whyNotEditable(
      content,
      canPush: browser.target?.repo.canPush ?? false,
    );
    if (reason != null) {
      showNexusToast(context, reason, type: NexusToastType.warning);
      return;
    }
    final head = _openedHeadSha ?? browser.headCommitSha;
    if (head == null) {
      showNexusToast(
        context,
        'لم تُحمَّل ملفات الفرع بعد.',
        type: NexusToastType.warning,
      );
      return;
    }

    final updated = await openRepoFileEditor(
      context,
      content: content,
      openedHeadSha: head,
    );
    if (!mounted || updated == null) return;

    // Saved (or reloaded the newer version): show it. The controller has
    // already refreshed, so its head is the new base for the next edit.
    setState(() {
      _file = updated;
      _openedHeadSha =
          ref.read(repoBrowserControllerProvider).headCommitSha ?? head;
    });
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showNexusToast(context, message, type: NexusToastType.success);
  }

  void _showInfo(RepoFileContent? content) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FileInfoSheet(
        file: _file,
        content: content,
        onCopyPath: () => _copy(_file.path, 'تم نسخ المسار'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final async = ref.watch(repoFileContentProvider(file));
    final content = async.valueOrNull;
    final visual = RepoEntryVisuals.forFileName(file.name);
    final canPush = ref.watch(
      repoBrowserControllerProvider
          .select((s) => s.target?.repo.canPush ?? false),
    );
    final editBlockedReason = content == null
        ? null
        : RepoEditGuard.whyNotEditable(content, canPush: canPush);

    final isText = content != null &&
        (content.kind == RepoFileKind.text ||
            (content.kind == RepoFileKind.markdown && _showMarkdownSource));

    final target = ref.watch(
      repoBrowserControllerProvider.select((s) => s.target),
    );
    final isFavorite = target != null &&
        ref.watch(
          repoBookmarksProvider.select(
            (b) => b.isFavorite(
              repoFullName: target.repo.fullName,
              branchName: target.branchName,
              path: file.path,
            ),
          ),
        );

    return Scaffold(
      body: NexusAmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                decoration: BoxDecoration(
                  color: NexusColors.bgDeep.withOpacity(0.55),
                  border: const Border(
                    bottom: BorderSide(color: NexusColors.borderSubtle),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'رجوع',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: NexusColors.textSecondary,
                      ),
                    ),
                    Icon(visual.icon, color: visual.color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: NexusColors.textPrimary,
                            ),
                          ),
                          Text(
                            file.parentPath.isEmpty ? '/' : file.parentPath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: NexusColors.textSubtle,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (content != null &&
                        content.kind == RepoFileKind.markdown)
                      IconButton(
                        tooltip: _showMarkdownSource
                            ? 'عرض منسّق'
                            : 'عرض المصدر',
                        onPressed: () => setState(
                          () => _showMarkdownSource = !_showMarkdownSource,
                        ),
                        icon: Icon(
                          _showMarkdownSource
                              ? Icons.visibility_outlined
                              : Icons.code_rounded,
                          color: NexusColors.textMuted,
                          size: 21,
                        ),
                      ),
                    if (isText)
                      IconButton(
                        tooltip: _wrap ? 'إلغاء التفاف الأسطر' : 'التفاف الأسطر',
                        onPressed: () => setState(() => _wrap = !_wrap),
                        icon: Icon(
                          Icons.wrap_text_rounded,
                          size: 21,
                          color: _wrap
                              ? NexusColors.primarySoft
                              : NexusColors.textMuted,
                        ),
                      ),
                    if (content != null &&
                        (content.kind == RepoFileKind.text ||
                            content.kind == RepoFileKind.markdown))
                      IconButton(
                        key: const ValueKey('viewer_edit'),
                        tooltip: 'تعديل الملف',
                        onPressed: () => _openEditor(content),
                        icon: Icon(
                          Icons.edit_rounded,
                          size: 20,
                          color: editBlockedReason == null
                              ? NexusColors.primarySoft
                              : NexusColors.textSubtle,
                        ),
                      ),
                    IconButton(
                      key: const ValueKey('viewer_favorite'),
                      tooltip: isFavorite
                          ? 'إزالة من المفضلة'
                          : 'إضافة إلى المفضلة',
                      onPressed: target == null ? null : _toggleFavorite,
                      icon: Icon(
                        isFavorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 21,
                        color: isFavorite
                            ? NexusColors.warningSoft
                            : NexusColors.textMuted,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'المزيد',
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        size: 21,
                        color: NexusColors.textMuted,
                      ),
                      onSelected: (value) {
                        switch (value) {
                          case 'history':
                            _showHistory();
                          case 'copy':
                            if (content?.text != null) {
                              _copy(content!.text!, 'تم نسخ محتوى الملف');
                            }
                          case 'info':
                            _showInfo(content);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'history',
                          child: Row(
                            children: [
                              Icon(Icons.history_rounded, size: 19),
                              SizedBox(width: 10),
                              Expanded(child: Text('سجل التعديلات والاستعادة')),
                            ],
                          ),
                        ),
                        if (content?.text != null)
                          const PopupMenuItem(
                            value: 'copy',
                            child: Row(
                              children: [
                                Icon(Icons.copy_rounded, size: 19),
                                SizedBox(width: 10),
                                Expanded(child: Text('نسخ المحتوى')),
                              ],
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'info',
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 19),
                              SizedBox(width: 10),
                              Expanded(child: Text('معلومات الملف')),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: async.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: NexusColors.primarySoft,
                    ),
                  ),
                  error: (error, _) => RepoMessageView(
                    icon: Icons.error_outline_rounded,
                    color: NexusColors.roseSoft,
                    title: 'تعذر تحميل الملف',
                    message: error is GitHubException
                        ? error.message
                        : 'حدث خطأ غير متوقع أثناء قراءة الملف.',
                    actionLabel: 'إعادة المحاولة',
                    onAction: () =>
                        ref.invalidate(repoFileContentProvider(file)),
                  ),
                  data: (content) => _buildContent(content),
                ),
              ),
              if (content != null && content.text != null)
                _TextStatusBar(content: content),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(RepoFileContent content) {
    switch (content.kind) {
      case RepoFileKind.text:
        if (content.text!.isEmpty) {
          return const RepoMessageView(
            icon: Icons.insert_drive_file_outlined,
            title: 'الملف فارغ',
          );
        }
        return CodeView(
          text: content.text!,
          language: content.language,
          wrap: _wrap,
        );
      case RepoFileKind.markdown:
        if (_showMarkdownSource) {
          return CodeView(text: content.text!, wrap: _wrap);
        }
        return MarkdownView(source: content.text!);
      case RepoFileKind.image:
        return _ImageViewer(bytes: content.imageBytes!);
      case RepoFileKind.binary:
        return _BinaryCard(content: content);
    }
  }
}

// ---------------------------------------------------------------------------

class _TextStatusBar extends StatelessWidget {
  final RepoFileContent content;

  const _TextStatusBar({required this.content});

  @override
  Widget build(BuildContext context) {
    final language = content.language;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: NexusColors.bgDeep.withOpacity(0.7),
        border: const Border(top: BorderSide(color: NexusColors.borderSubtle)),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          RepoChip(label: '${content.lineCount} سطر', icon: Icons.notes_rounded),
          RepoChip(label: formatBytes(content.file.size)),
          RepoChip(label: content.hasBom ? 'UTF-8 BOM' : 'UTF-8'),
          if (content.lineEnding != LineEnding.none)
            RepoChip(label: content.lineEnding.label),
          if (language != null)
            RepoChip(label: language, color: NexusColors.primarySoft),
          if (content.file.isExecutable)
            const RepoChip(label: 'exec', color: NexusColors.successSoft),
        ],
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  final Uint8List bytes;

  const _ImageViewer({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.25),
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 8,
        child: Center(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const RepoMessageView(
              icon: Icons.broken_image_outlined,
              color: NexusColors.warningSoft,
              title: 'تعذر عرض الصورة',
              message: 'تنسيق الصورة غير مدعوم أو الملف تالف.',
            ),
          ),
        ),
      ),
    );
  }
}

class _BinaryCard extends StatelessWidget {
  final RepoFileContent content;

  const _BinaryCard({required this.content});

  @override
  Widget build(BuildContext context) {
    final file = content.file;
    final visual = RepoEntryVisuals.forFileName(file.name);

    return RepoMessageView(
      icon: visual.icon,
      color: visual.color,
      title: 'لا توجد معاينة لهذا الملف',
      message: [
        if (content.notice != null) content.notice!,
        '${file.name} • ${formatBytes(file.size)}',
      ].join('\n'),
    );
  }
}

class _FileInfoSheet extends StatelessWidget {
  final RepoFileRef file;
  final RepoFileContent? content;
  final VoidCallback onCopyPath;

  const _FileInfoSheet({
    required this.file,
    required this.content,
    required this.onCopyPath,
  });

  static String _modeLabel(String mode) => switch (mode) {
        '100755' => 'ملف تنفيذي (100755)',
        '120000' => 'رابط رمزي (120000)',
        '100644' => 'ملف عادي (100644)',
        _ => mode,
      };

  @override
  Widget build(BuildContext context) {
    final content = this.content;
    final rows = <(String, String)>[
      ('الاسم', file.name),
      ('المسار', file.path),
      ('الحجم', '${formatBytes(file.size)} (${file.size} بايت)'),
      ('الصلاحية', _modeLabel(file.mode)),
      ('SHA', file.sha),
      if (content?.text != null) ...[
        ('الأسطر', '${content!.lineCount}'),
        ('الترميز', content.hasBom ? 'UTF-8 مع BOM' : 'UTF-8'),
        ('نهايات الأسطر', content.lineEnding.label),
      ],
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: GlassPanel(
          strong: true,
          borderRadius: 22,
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'معلومات الملف',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: NexusColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                for (final (label, value) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 96,
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: NexusColors.textMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            value,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.start,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontFamily: 'monospace',
                              color: NexusColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                NexusGradientButton(
                  height: 42,
                  borderRadius: 12,
                  onPressed: () {
                    onCopyPath();
                    Navigator.of(context).pop();
                  },
                  child: const Text('نسخ المسار'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
