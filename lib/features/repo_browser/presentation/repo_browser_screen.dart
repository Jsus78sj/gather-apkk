import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/nexus_toast.dart';
import '../data/repo_download_saver.dart';
import '../domain/arabic_count.dart';
import '../domain/file_op.dart';
import '../domain/remote_tree_entry.dart';
import '../domain/repo_change_plan.dart';
import '../domain/repo_code_search.dart';
import '../domain/repo_file_content.dart';
import '../domain/repo_op_result.dart';
import '../domain/repo_search_index.dart';
import '../domain/repo_undo_info.dart';
import 'bookmarks_sheet.dart';
import 'create_entry_dialog.dart';
import 'delete_confirm_dialog.dart';
import 'move_destination_sheet.dart';
import 'path_change_confirm_dialog.dart';
import 'protected_branch_pr_dialog.dart';
import 'rename_dialog.dart';
import 'repo_browser_controller.dart';
import 'repo_bookmarks_controller.dart';
import 'repo_file_viewer_screen.dart';
import 'upload_files_dialog.dart';
import 'widgets/repo_branch_switcher.dart';
import 'widgets/repo_breadcrumb.dart';
import 'widgets/repo_entry_tile.dart';
import 'widgets/repo_selection_bar.dart';
import 'widgets/repo_state_views.dart';

/// Writes downloaded files / archives to the device (overridden in tests).
final repoDownloadSaverProvider =
    Provider<RepoDownloadSaver>((ref) => const RepoDownloadSaver());

/// Opens the file browser of the repository / branch currently selected in
/// the repositories section.
Future<void> openRepoBrowser(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const RepoBrowserScreen()),
  );
}

class RepoBrowserScreen extends ConsumerStatefulWidget {
  const RepoBrowserScreen({super.key});

  @override
  ConsumerState<RepoBrowserScreen> createState() => _RepoBrowserScreenState();
}

class _RepoBrowserScreenState extends ConsumerState<RepoBrowserScreen> {
  final TextEditingController _searchText = TextEditingController();
  Timer? _debounce;

  /// The last query sent to the content Search API (drives the empty hints).
  String _lastCodeQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchText.dispose();
    super.dispose();
  }

  RepoBrowserController get _controller =>
      ref.read(repoBrowserControllerProvider.notifier);

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  /// Back button / system back: closes the search, then the selection mode,
  /// then goes up one folder, and only leaves the screen from the root.
  /// Ignored while a commit is running.
  void _handleBack() {
    final state = ref.read(repoBrowserControllerProvider);
    if (state.isMutating) return;
    if (state.searchActive) {
      _closeSearch();
      return;
    }
    if (state.isSelecting) {
      _controller.clearSelection();
      return;
    }
    if (!_controller.goUp()) {
      Navigator.of(context).maybePop();
    }
  }

  void _openSearch() {
    _debounce?.cancel();
    _searchText.clear();
    _lastCodeQuery = '';
    _controller.setSearchActive(true);
  }

  void _closeSearch() {
    _debounce?.cancel();
    _searchText.clear();
    _lastCodeQuery = '';
    _controller.setSearchActive(false);
  }

  void _onQueryChanged(String query) {
    // Content search is rate limited: it runs on submit only.
    if (ref.read(repoBrowserControllerProvider).codeSearchMode) return;
    _debounce?.cancel();
    // Rebuilds the (possibly large) result list at most once per pause.
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      if (!ref.read(repoBrowserControllerProvider).searchActive) return;
      _controller.setSearchQuery(query);
    });
  }

  void _submitQuery() {
    if (!ref.read(repoBrowserControllerProvider).codeSearchMode) return;
    _debounce?.cancel();
    _lastCodeQuery = _searchText.text.trim();
    _controller.runCodeSearch(_lastCodeQuery);
  }

  void _clearQuery() {
    _debounce?.cancel();
    _searchText.clear();
    _controller.setSearchQuery('');
  }

  void _onEntryTap(RemoteTreeEntry entry) {
    final controller = _controller;
    // In selection mode a tap only toggles; it never opens anything.
    if (ref.read(repoBrowserControllerProvider).isSelecting) {
      controller.toggleSelection(entry);
      return;
    }
    if (entry.isFolder) {
      controller.openFolder(controller.childPath(entry.name));
      return;
    }
    if (entry.isSubmodule) {
      showNexusToast(
        context,
        'هذا العنصر Submodule يشير إلى مستودع آخر ولا يمكن تصفحه هنا.',
        type: NexusToastType.info,
      );
      return;
    }
    openRepoFile(
      context,
      RepoFileRef(
        path: controller.childPath(entry.name),
        sha: entry.sha,
        size: entry.size,
        mode: entry.mode,
      ),
    );
  }

  void _onEntryLongPress(RemoteTreeEntry entry) {
    final controller = _controller;
    if (!controller.canSelect(entry)) {
      showNexusToast(
        context,
        'لا يمكن تحديد Submodule لأنه يشير إلى مستودع آخر.',
        type: NexusToastType.info,
      );
      return;
    }
    HapticFeedback.selectionClick();
    controller.toggleSelection(entry);
  }

  // ---------------------------------------------------------------------------
  // Delete / undo
  // ---------------------------------------------------------------------------

  void _toastFailure(RepoOpResult<Object?> result) {
    showNexusToast(
      context,
      result.message ?? 'تعذر تنفيذ العملية.',
      type: result.failure == RepoOpFailure.branchChanged
          ? NexusToastType.warning
          : NexusToastType.error,
    );
  }

  Future<void> _onDeletePressed() async {
    final controller = _controller;
    final target = ref.read(repoBrowserControllerProvider).target;
    if (target == null) return;

    final preview = await controller.previewDeleteSelection();
    if (!mounted) return;
    if (!preview.isSuccess) {
      _toastFailure(preview);
      return;
    }

    final message = await showDeleteConfirmDialog(
      context,
      target: target,
      preview: preview.value!,
    );
    if (!mounted || message == null) return;

    final result = await controller.deleteSelection(message: message);
    if (!mounted) return;
    if (!result.isSuccess) {
      await _handleCommitFailure(result, suggestedMessage: message);
    }
  }

  Future<void> _onUndoPressed() async {
    // Read before the call: a successful undo clears the bar.
    final kind =
        ref.read(repoBrowserControllerProvider).undo?.kind ?? RepoUndoKind.delete;
    final result = await _controller.undoLastChange();
    if (!mounted) return;
    if (result.isSuccess) {
      showNexusToast(
        context,
        switch (kind) {
          RepoUndoKind.delete => 'تم التراجع واستعادة العناصر المحذوفة.',
          RepoUndoKind.move => 'تم التراجع عن النقل وإعادة العناصر إلى أماكنها.',
          RepoUndoKind.rename => 'تم التراجع عن إعادة التسمية.',
          RepoUndoKind.edit => 'تم التراجع عن تعديل الملف.',
          RepoUndoKind.create => 'تم التراجع وحُذف العنصر الذي أُنشئ.',
          RepoUndoKind.upload => 'تم التراجع وأُزيلت الملفات المرفوعة.',
          RepoUndoKind.restore => 'تم التراجع عن الاستعادة.',
        },
        type: NexusToastType.success,
      );
    } else {
      _toastFailure(result);
    }
  }

  // ---------------------------------------------------------------------------
  // Move / rename / download
  // ---------------------------------------------------------------------------

  Future<void> _onMovePressed() async {
    final controller = _controller;
    final state = ref.read(repoBrowserControllerProvider);
    final target = state.target;
    if (target == null || controller.service == null) return;

    final destination = await showMoveDestinationSheet(
      context,
      repoName: target.repo.name,
      currentFolderPath: state.path,
      selectedPaths: state.selectedPaths,
      listFolders: controller.listSubfolders,
    );
    if (!mounted || destination == null) return;

    final preview = await controller.previewMoveSelection(destination);
    if (!mounted) return;
    if (!preview.isSuccess) {
      _toastFailure(preview);
      return;
    }

    final message = await showPathChangeConfirmDialog(
      context,
      target: target,
      preview: preview.value!,
    );
    if (!mounted || message == null) return;

    final result = await controller.moveSelection(
      destinationFolder: destination,
      message: message,
    );
    if (!mounted) return;
    if (!result.isSuccess) {
      await _handleCommitFailure(result, suggestedMessage: message);
    }
  }

  Future<void> _onRenamePressed() async {
    final controller = _controller;
    final state = ref.read(repoBrowserControllerProvider);
    final target = state.target;
    if (target == null || state.selectedPaths.length != 1) return;

    final path = state.selectedPaths.first;
    RemoteTreeEntry? entry;
    for (final candidate in state.entries) {
      if (controller.childPath(candidate.name) == path) {
        entry = candidate;
        break;
      }
    }
    if (entry == null) return;
    final selected = entry;

    final answer = await showRenameDialog(
      context,
      entry: selected,
      currentFolderPath: state.path,
      siblingNames: {
        for (final other in state.entries)
          if (other.name != selected.name) other.name,
      },
    );
    if (!mounted || answer == null) return;

    // A file carries its own commit message (asked in the dialog). A folder
    // changes the path of every file inside it, so it is confirmed first.
    String message;
    if (selected.isFolder) {
      final preview = await controller.previewRenameSelected(answer.newName);
      if (!mounted) return;
      if (!preview.isSuccess) {
        _toastFailure(preview);
        return;
      }
      final confirmed = await showPathChangeConfirmDialog(
        context,
        target: target,
        preview: preview.value!,
      );
      if (!mounted || confirmed == null) return;
      message = confirmed;
    } else {
      message = answer.commitMessage ??
          'Nexus: rename $path to ${state.path.isEmpty ? answer.newName : '${state.path}/${answer.newName}'}';
    }

    final result = await controller.renameSelected(
      newName: answer.newName,
      message: message,
    );
    if (!mounted) return;
    if (!result.isSuccess) {
      await _handleCommitFailure(result, suggestedMessage: message);
    }
  }

  Future<void> _onDownloadPressed() async {
    final controller = _controller;
    final prepared = await controller.prepareDownload();
    if (!mounted) return;
    if (!prepared.isSuccess) {
      _toastFailure(prepared);
      return;
    }

    final payload = prepared.value!;
    try {
      final savedPath = await ref.read(repoDownloadSaverProvider).save(payload);
      if (!mounted) return;
      // `null`: the user closed the save dialog; keep the selection.
      if (savedPath == null) return;
      controller.clearSelection();
      showNexusToast(
        context,
        payload.isZip
            ? 'تم حفظ ${payload.fileName} (${arabicFiles(payload.fileCount)}).'
            : 'تم حفظ ${payload.fileName}.',
        type: NexusToastType.success,
      );
    } catch (_) {
      if (!mounted) return;
      showNexusToast(
        context,
        'تعذر حفظ الملف على الجهاز.',
        type: NexusToastType.error,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Create / upload / bookmarks (phase 10)
  // ---------------------------------------------------------------------------

  bool get _canWrite =>
      ref.read(repoBrowserControllerProvider).target?.repo.canPush ?? false;

  /// Handles a failed write: when branch protection rejected the push, offers
  /// to apply the very same ops on a fresh branch and open a pull request.
  Future<void> _handleCommitFailure(
    RepoOpResult<RepoCommitResult> result, {
    required String suggestedMessage,
  }) async {
    if (!mounted) return;
    if (result.failure == RepoOpFailure.protectedBranch) {
      final ops = _controller.takeRejectedWriteOps();
      if (ops != null && ops.isNotEmpty) {
        await _offerProtectedBranchFallback(
          ops: ops,
          suggestedMessage: suggestedMessage,
        );
        return;
      }
    }
    _toastFailure(result);
  }

  Future<void> _offerProtectedBranchFallback({
    required List<FileOp> ops,
    required String suggestedMessage,
  }) async {
    final target = ref.read(repoBrowserControllerProvider).target;
    if (target == null || !mounted) return;

    final input = await showProtectedBranchPrDialog(
      context,
      protectedBranch: target.branchName,
      suggestedCommitMessage: suggestedMessage,
    );
    if (!mounted || input == null) return;

    final pr = await _controller.commitOnNewBranchAndOpenPullRequest(
      ops: ops,
      message: suggestedMessage,
      newBranchName: input.newBranchName,
      prTitle: input.prTitle,
      prBody: input.prBody,
    );
    if (!mounted) return;
    if (pr.isSuccess) {
      await showPullRequestCreatedDialog(context, pr.value!);
    } else {
      _toastFailure(pr);
    }
  }

  Future<void> _onCreateEntryPressed(bool isFolder) async {
    final state = ref.read(repoBrowserControllerProvider);
    // The atomic engine needs a branch head, so an empty repository must be
    // bootstrapped from the main screen first.
    if (state.target == null || state.isEmptyRepo) return;

    final answer = await showCreateEntryDialog(
      context,
      isFolder: isFolder,
      currentFolderPath: state.path,
    );
    if (!mounted || answer == null) return;

    final result = await _controller.createEntry(
      name: answer.name,
      bytes: answer.fileBytes,
      message: answer.commitMessage,
    );
    if (!mounted) return;
    if (result.isSuccess) {
      showNexusToast(
        context,
        answer.isFolder
            ? 'تم إنشاء المجلد في Commit واحد.'
            : 'تم إنشاء الملف في Commit واحد.',
        type: NexusToastType.success,
      );
    } else {
      await _handleCommitFailure(
        result,
        suggestedMessage: answer.commitMessage,
      );
    }
  }

  Future<void> _onUploadPressed() async {
    final state = ref.read(repoBrowserControllerProvider);
    if (state.target == null || state.isEmptyRepo) return;

    final existingNames = <String>{
      for (final entry in state.entries)
        if (entry.isFile) entry.name,
    };
    final answer = await pickAndConfirmLocalFilesUpload(
      context,
      currentFolderPath: state.path,
      existingFileNames: existingNames,
    );
    if (!mounted || answer == null) return;

    final result = await _controller.uploadFiles(
      files: [
        for (final file in answer.files) (name: file.name, bytes: file.bytes),
      ],
      message: answer.commitMessage,
      overwriteExisting: answer.overwriteExisting,
    );
    if (!mounted) return;
    if (result.isSuccess) {
      showNexusToast(
        context,
        'تم رفع ${arabicFiles(answer.files.length)} في Commit واحد.',
        type: NexusToastType.success,
      );
    } else {
      await _handleCommitFailure(
        result,
        suggestedMessage: answer.commitMessage,
      );
    }
  }

  Future<void> _openBookmarks() async {
    final state = ref.read(repoBrowserControllerProvider);
    final target = state.target;
    if (target == null) return;

    final picked = await showRepoBookmarksSheet(
      context,
      repoFullName: target.repo.fullName,
      branchName: target.branchName,
    );
    if (!mounted || picked == null) return;

    if (picked.isFolder) {
      await _controller.openFolder(picked.path);
      return;
    }
    final resolved = await _controller.resolveFileRef(picked.path);
    if (!mounted) return;
    if (resolved == null) {
      showNexusToast(
        context,
        'الملف غير موجود الآن — ربما حُذف أو أعيدت تسميته.',
        type: NexusToastType.warning,
      );
      return;
    }
    openRepoFile(context, resolved);
  }

  /// Adds the folder being browsed to the favorites (or removes it).
  Future<void> _toggleFolderFavorite() async {
    final state = ref.read(repoBrowserControllerProvider);
    final target = state.target;
    if (target == null || state.path.isEmpty) return;

    final added = await ref
        .read(repoBookmarksProvider.notifier)
        .toggleFavorite(
          repoFullName: target.repo.fullName,
          branchName: target.branchName,
          path: state.path,
          isFolder: true,
        );
    if (!mounted) return;
    showNexusToast(
      context,
      added
          ? 'أُضيف المجلد إلى المفضلة.'
          : 'أُزيل المجلد من المفضلة.',
      type: NexusToastType.success,
    );
  }

  void _onHitTap(RepoSearchHit hit) {
    if (hit.isFolder) {
      _closeSearch();
      _controller.openFolder(hit.path);
      return;
    }
    // The search stays open so the user can come back to the results.
    openRepoFile(
      context,
      RepoFileRef(
        path: hit.path,
        sha: hit.sha,
        size: hit.size,
        mode: hit.mode,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repoBrowserControllerProvider);

    // A failed refresh keeps the old listing on screen, so tell the user.
    ref.listen<String?>(
      repoBrowserControllerProvider.select((s) => s.error),
      (previous, next) {
        if (next == null || next == previous) return;
        if (ref.read(repoBrowserControllerProvider).entries.isEmpty) return;
        showNexusToast(context, next, type: NexusToastType.error);
      },
    );

    final undo = state.undo;

    return PopScope(
      canPop: !state.searchActive &&
          !state.isSelecting &&
          !state.isMutating &&
          state.path.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        body: NexusAmbientBackground(
          child: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  children: [
                    _buildHeader(state),
                    if (!state.searchActive && !state.isEmptyRepo)
                      Container(
                        decoration: BoxDecoration(
                          color: NexusColors.bgDeep.withOpacity(0.35),
                          border: const Border(
                            bottom: BorderSide(color: NexusColors.borderSubtle),
                          ),
                        ),
                        child: RepoBreadcrumb(
                          rootLabel: state.target?.repo.name ?? 'root',
                          segments: state.segments,
                          onOpen: _controller.openFolder,
                        ),
                      ),
                    if (state.isLoading && state.entries.isNotEmpty)
                      const LinearProgressIndicator(
                        minHeight: 2,
                        color: NexusColors.primarySoft,
                        backgroundColor: Colors.transparent,
                      ),
                    if (state.searchActive)
                      Container(
                        decoration: BoxDecoration(
                          color: NexusColors.bgDeep.withOpacity(0.35),
                          border: const Border(
                            bottom: BorderSide(color: NexusColors.borderSubtle),
                          ),
                        ),
                        child: _buildSearchModeBar(state),
                      ),
                    Expanded(
                      child: state.searchActive
                          ? (state.codeSearchMode
                              ? _buildCodeSearchBody(state)
                              : _buildSearchBody(state))
                          : _buildBrowseBody(state),
                    ),
                    if (undo != null)
                      RepoUndoBar(
                        summary: undo.summary,
                        onUndo: _onUndoPressed,
                        onDismiss: _controller.dismissUndo,
                      ),
                    if (state.isSelecting)
                      RepoSelectionBar(
                        onDelete: _onDeletePressed,
                        onMove: _onMovePressed,
                        onRename:
                            state.selectedPaths.length == 1 ? _onRenamePressed : null,
                        onDownload: _onDownloadPressed,
                      ),
                  ],
                ),
                if (state.isMutating)
                  RepoBusyOverlay(label: state.busyLabel ?? 'جارٍ التنفيذ...'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(RepoBrowserState state) {
    if (state.isSelecting) {
      return RepoSelectionHeader(
        count: state.selectedPaths.length,
        allSelected: state.selectedPaths.length >= state.selectableCount,
        onClose: _controller.clearSelection,
        onSelectAll: _controller.selectAll,
      );
    }

    final decoration = BoxDecoration(
      color: NexusColors.bgDeep.withOpacity(0.55),
      border: const Border(bottom: BorderSide(color: NexusColors.borderSubtle)),
    );
    final backButton = IconButton(
      tooltip: state.searchActive ? 'إغلاق البحث' : 'رجوع',
      onPressed: _handleBack,
      icon: const Icon(
        Icons.arrow_back_rounded,
        color: NexusColors.textSecondary,
      ),
    );

    if (state.searchActive) {
      return Container(
        padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
        decoration: decoration,
        child: Row(
          children: [
            backButton,
            Expanded(
              child: TextField(
                controller: _searchText,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                onSubmitted: (_) => _submitQuery(),
                style: const TextStyle(
                  fontSize: 14,
                  color: NexusColors.textPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: state.codeSearchMode
                      ? 'ابحث داخل محتوى الملفات ثم اضغط بحث...'
                      : 'ابحث عن ملف أو مجلد بالاسم...',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  suffixIcon: state.codeSearchMode
                      ? IconButton(
                          tooltip: 'بحث في المحتوى',
                          onPressed: _submitQuery,
                          icon: const Icon(
                            Icons.travel_explore_rounded,
                            size: 20,
                            color: NexusColors.primarySoft,
                          ),
                        )
                      : ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _searchText,
                          builder: (context, value, _) => value.text.isEmpty
                              ? const SizedBox.shrink()
                              : IconButton(
                                  tooltip: 'مسح',
                                  onPressed: _clearQuery,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: NexusColors.textMuted,
                                  ),
                                ),
                        ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final target = state.target;
    final canPush = target?.repo.canPush ?? false;
    final canWriteHere = target != null && !state.isEmptyRepo;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      decoration: decoration,
      child: Row(
        children: [
          backButton,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target?.repo.fullName ?? 'تصفح الملفات',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: NexusColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: RepoBranchButton(),
                ),
              ],
            ),
          ),
          if (target != null)
            IconButton(
              tooltip: 'المفضلة والملفات الحديثة',
              onPressed: _openBookmarks,
              icon: const Icon(
                Icons.bookmarks_outlined,
                size: 21,
                color: NexusColors.textSecondary,
              ),
            ),
          if (canWriteHere)
            PopupMenuButton<String>(
              key: const ValueKey('browser_add_menu'),
              tooltip: 'إنشاء أو رفع',
              icon: const Icon(
                Icons.add_rounded,
                size: 24,
                color: NexusColors.textSecondary,
              ),
              onSelected: (value) => switch (value) {
                'file' => _onCreateEntryPressed(false),
                'folder' => _onCreateEntryPressed(true),
                'upload' => _onUploadPressed(),
                'favorite' => _toggleFolderFavorite(),
                _ => null,
              },
              itemBuilder: (_) {
                final isFavFolder = state.path.isNotEmpty &&
                    ref.read(repoBookmarksProvider).isFavorite(
                          repoFullName: target.repo.fullName,
                          branchName: target.branchName,
                          path: state.path,
                        );
                return [
                  if (canPush) ...[
                    const PopupMenuItem(
                      value: 'file',
                      child: Row(
                        children: [
                          Icon(Icons.note_add_rounded, size: 19),
                          SizedBox(width: 10),
                          Expanded(child: Text('ملف جديد')),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'folder',
                      child: Row(
                        children: [
                          Icon(Icons.create_new_folder_rounded, size: 19),
                          SizedBox(width: 10),
                          Expanded(child: Text('مجلد جديد')),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'upload',
                      child: Row(
                        children: [
                          Icon(Icons.upload_file_rounded, size: 19),
                          SizedBox(width: 10),
                          Expanded(child: Text('رفع ملفات من الجهاز')),
                        ],
                      ),
                    ),
                  ],
                  if (state.path.isNotEmpty)
                    PopupMenuItem(
                      value: 'favorite',
                      child: Row(
                        children: [
                          Icon(
                            isFavFolder
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            size: 19,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isFavFolder
                                  ? 'إزالة المجلد الحالي من المفضلة'
                                  : 'إضافة المجلد الحالي إلى المفضلة',
                            ),
                          ),
                        ],
                      ),
                    ),
                ];
              },
            ),
          IconButton(
            tooltip: 'بحث',
            onPressed: state.target == null || state.isEmptyRepo
                ? null
                : _openSearch,
            icon: const Icon(
              Icons.search_rounded,
              color: NexusColors.textSecondary,
            ),
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: state.isLoading ? null : _controller.refresh,
            icon: const Icon(
              Icons.refresh_rounded,
              color: NexusColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Folder listing
  // ---------------------------------------------------------------------------

  Widget _buildBrowseBody(RepoBrowserState state) {
    if (state.error != null && state.entries.isEmpty) {
      return RepoMessageView(
        icon: Icons.error_outline_rounded,
        color: NexusColors.roseSoft,
        title: 'تعذر تحميل المحتوى',
        message: state.error,
        actionLabel: 'إعادة المحاولة',
        onAction: _controller.retry,
      );
    }

    if (state.isEmptyRepo) {
      return const RepoMessageView(
        icon: Icons.inbox_outlined,
        title: 'المستودع فارغ',
        message: 'لا توجد Commits في هذا الفرع بعد. ارفع ملفات ZIP من الشاشة '
            'الرئيسية أو أنشئ ملفاً عبر موقع GitHub لتهيئة الفرع أولاً.',
      );
    }

    if (state.isLoading && state.entries.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.6,
          color: NexusColors.primarySoft,
        ),
      );
    }

    if (state.entries.isEmpty) {
      return const RepoMessageView(
        icon: Icons.folder_open_rounded,
        title: 'المجلد فارغ',
      );
    }

    final folders = state.entries.where((e) => e.isFolder).length;
    final files = state.entries.length - folders;
    final head = state.headCommitSha;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          if (folders > 0)
            RepoChip(
              label: '$folders مجلد',
              icon: Icons.folder_rounded,
              color: NexusColors.warningSoft,
            ),
          if (files > 0)
            RepoChip(
              label: '$files ملف',
              icon: Icons.insert_drive_file_outlined,
            ),
          if (head != null)
            RepoChip(
              label: 'HEAD ${head.length >= 7 ? head.substring(0, 7) : head}',
              color: NexusColors.primarySoft,
            ),
        ],
      ),
    );

    return RefreshIndicator(
      color: NexusColors.primarySoft,
      backgroundColor: NexusColors.bgSurface,
      onRefresh: _controller.refresh,
      child: _LazyRows(
        header: header,
        itemCount: state.entries.length,
        itemBuilder: (context, index) {
          final entry = state.entries[index];
          final path =
              state.path.isEmpty ? entry.name : '${state.path}/${entry.name}';
          return RepoEntryTile(
            key: ValueKey(path),
            entry: entry,
            selectionMode: state.isSelecting,
            selected: state.selectedPaths.contains(path),
            onTap: () => _onEntryTap(entry),
            onLongPress: () => _onEntryLongPress(entry),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Search: names (local index) vs content (Search API)
  // ---------------------------------------------------------------------------

  Widget _buildSearchModeBar(RepoBrowserState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('الأسماء'),
            selected: !state.codeSearchMode,
            onSelected: (_) => _controller.setCodeSearchMode(false),
            labelStyle: TextStyle(
              fontSize: 12.5,
              color: state.codeSearchMode
                  ? NexusColors.textMuted
                  : NexusColors.textPrimary,
            ),
            selectedColor: NexusColors.primary.withOpacity(0.22),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('المحتوى'),
            selected: state.codeSearchMode,
            onSelected: (_) => _controller.setCodeSearchMode(true),
            labelStyle: TextStyle(
              fontSize: 12.5,
              color: state.codeSearchMode
                  ? NexusColors.textPrimary
                  : NexusColors.textMuted,
            ),
            selectedColor: NexusColors.primary.withOpacity(0.22),
          ),
          if (state.codeSearchMode) ...[
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'عبر Search API — الفرع الافتراضي فقط',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: NexusColors.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCodeSearchBody(RepoBrowserState state) {
    if (state.codeSearchError != null) {
      return RepoMessageView(
        icon: Icons.error_outline_rounded,
        color: NexusColors.roseSoft,
        title: 'تعذر البحث في المحتوى',
        message: state.codeSearchError,
        actionLabel: 'إعادة المحاولة',
        onAction: () => _controller.runCodeSearch(_searchText.text),
      );
    }

    if (state.isCodeSearching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2.6,
              color: NexusColors.primarySoft,
            ),
            SizedBox(height: 14),
            Text(
              'جارٍ البحث في محتوى الملفات...',
              style: TextStyle(fontSize: 13, color: NexusColors.textMuted),
            ),
          ],
        ),
      );
    }

    final result = state.codeSearchResult;
    if (_lastCodeQuery.isEmpty) {
      return const RepoMessageView(
        icon: Icons.travel_explore_rounded,
        title: 'ابحث داخل محتوى الملفات',
        message: 'اكتب كلمة أو عبارة موجودة في الكود واضغط بحث. '
            'الخدمة تعمل على الفرع الافتراضي فقط وتسمح بعدد محدود من '
            'عمليات البحث في الدقيقة، لذلك تُنفَّذ عند الضغط على بحث فقط.',
      );
    }

    if (result.items.isEmpty) {
      return RepoMessageView(
        icon: Icons.search_off_rounded,
        title: 'لا توجد نتائج',
        message: result.incompleteResults
            ? 'فهرس GitHub غير مكتمل حالياً؛ أعد البحث بعد قليل.'
            : 'لا يوجد ملف يحتوي "${_lastCodeQuery}" في الفرع الافتراضي. '
                'لاحظ أن الملفات الأكبر من 384 KB تُستثنى من الفهرس.',
      );
    }

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Text(
            result.totalCount > result.items.length
                ? 'عرض أول ${result.items.length} من ${result.totalCount} ملف '
                    'يحتوي "${_lastCodeQuery}"'
                : '${result.totalCount} ملف يحتوي "${_lastCodeQuery}"',
            style: const TextStyle(
              fontSize: 12,
              color: NexusColors.textMuted,
            ),
          ),
        ),
        if (result.incompleteResults)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: NexusColors.warning.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NexusColors.warning.withOpacity(0.35)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: NexusColors.warningSoft,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'فهرس البحث غير مكتمل: النتائج قد تكون جزئية.',
                    style: TextStyle(
                      fontSize: 12,
                      color: NexusColors.warningSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return _LazyRows(
      header: header,
      itemCount: result.items.length,
      itemBuilder: (context, index) {
        final hit = result.items[index];
        return RepoCodeHitTile(
          key: ValueKey('code_${hit.path}'),
          hit: hit,
          onTap: () => _onCodeHitTap(hit),
        );
      },
    );
  }

  void _onCodeHitTap(RepoCodeSearchHit hit) {
    if (hit.path.isEmpty) return;
    // The Search API reports no size: 0 passes the preview gate and the real
    // size is computed from the downloaded bytes.
    openRepoFile(
      context,
      RepoFileRef(path: hit.path, sha: hit.sha, size: 0),
    );
  }

  Widget _buildSearchBody(RepoBrowserState state) {
    if (state.searchError != null) {
      return RepoMessageView(
        icon: Icons.error_outline_rounded,
        color: NexusColors.roseSoft,
        title: 'تعذر بناء فهرس البحث',
        message: state.searchError,
        actionLabel: 'إعادة المحاولة',
        onAction: _controller.retryIndex,
      );
    }

    if (state.isIndexing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2.6,
              color: NexusColors.primarySoft,
            ),
            SizedBox(height: 14),
            Text(
              'جارٍ فهرسة ملفات المستودع...',
              style: TextStyle(fontSize: 13, color: NexusColors.textMuted),
            ),
          ],
        ),
      );
    }

    if (state.searchQuery.trim().isEmpty) {
      return const RepoMessageView(
        icon: Icons.manage_search_rounded,
        title: 'ابحث في كل المستودع',
        message: 'اكتب جزءاً من اسم ملف أو مجلد. يمكنك كتابة عدة كلمات '
            'وسيطابق البحث كل الكلمات في المسار.',
      );
    }

    final result = state.searchResult;
    if (result.hits.isEmpty) {
      return RepoMessageView(
        icon: Icons.search_off_rounded,
        title: 'لا توجد نتائج',
        message: state.searchPartial
            ? 'المستودع ضخم وعُرضت شجرته جزئياً، لذلك قد لا يكون الملف '
                'ضمن الفهرس. جرّب التنقل بين المجلدات.'
            : 'لا يوجد ملف أو مجلد يطابق "${state.searchQuery.trim()}".',
      );
    }

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Text(
            result.total > result.hits.length
                ? 'عرض أول ${result.hits.length} من ${result.total} نتيجة — '
                    'ضيّق البحث بكلمات إضافية.'
                : '${result.total} نتيجة',
            style: const TextStyle(fontSize: 12, color: NexusColors.textMuted),
          ),
        ),
        if (state.searchPartial)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: NexusColors.warning.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NexusColors.warning.withOpacity(0.35)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: NexusColors.warningSoft,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'المستودع ضخم: النتائج قد تكون غير كاملة.',
                    style: TextStyle(
                      fontSize: 12,
                      color: NexusColors.warningSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return _LazyRows(
      header: header,
      itemCount: result.hits.length,
      itemBuilder: (context, index) {
        final hit = result.hits[index];
        return RepoSearchHitTile(
          key: ValueKey(hit.path),
          hit: hit,
          onTap: () => _onHitTap(hit),
        );
      },
    );
  }
}

/// One content-search hit: the file path plus the matching fragments that the
/// Search API returned for the query.
class RepoCodeHitTile extends StatelessWidget {
  final RepoCodeSearchHit hit;
  final VoidCallback onTap;

  const RepoCodeHitTile({
    super.key,
    required this.hit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final snippets = hit.snippets.take(2).toList();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.text_snippet_outlined,
              size: 22,
              color: NexusColors.primarySoft,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hit.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: NexusColors.textPrimary,
                    ),
                  ),
                  if (hit.parentPath.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        hit.parentPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: NexusColors.textSubtle,
                        ),
                      ),
                    ),
                  if (snippets.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: GlassPanel(
                        strong: false,
                        borderRadius: 10,
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final snippet in snippets)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 1),
                                child: Text(
                                  snippet.length > 220
                                      ? '${snippet.substring(0, 220)}…'
                                      : snippet,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  textDirection: TextDirection.ltr,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    height: 1.4,
                                    fontFamily: 'monospace',
                                    color: NexusColors.textMuted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Scrollable list of rows (built lazily, so folders with thousands of entries
/// stay smooth) with a [header] on top and thin dividers between rows.
class _LazyRows extends StatelessWidget {
  final Widget header;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  const _LazyRows({
    required this.header,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    // Item 0 is the header; row `i` of the data is list item `i + 1`.
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 28),
      itemCount: itemCount + 1,
      separatorBuilder: (context, index) => index == 0
          ? const SizedBox.shrink()
          : const Divider(
              height: 1,
              indent: 62,
              endIndent: 12,
              color: NexusColors.borderSubtle,
            ),
      itemBuilder: (context, index) =>
          index == 0 ? header : itemBuilder(context, index - 1),
    );
  }
}
