import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/github_api_client.dart';
import '../../../core/network/github_exceptions.dart';
import '../../../core/utils/format_bytes.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../repos/domain/deploy_target.dart';
import '../../repos/presentation/repos_controller.dart';
import '../data/repo_content_service.dart';
import '../data/repo_files_engine.dart';
import '../data/simple_zip_builder.dart';
import '../domain/arabic_count.dart';
import '../domain/file_op.dart';
import '../domain/remote_tree_entry.dart';
import '../domain/repo_change_plan.dart';
import '../domain/repo_code_search.dart';
import '../domain/repo_commit_summary.dart';
import '../domain/repo_delete_preview.dart';
import '../domain/repo_download_payload.dart';
import '../domain/repo_edit_conflict.dart';
import '../domain/repo_file_content.dart';
import '../domain/repo_file_save_result.dart';
import '../domain/repo_op_result.dart';
import '../domain/repo_path_change_preview.dart';
import '../domain/repo_path_validator.dart';
import '../domain/repo_pull_request.dart';
import '../domain/repo_search_index.dart';
import '../domain/repo_text_codec.dart';
import '../domain/repo_undo_info.dart';
import '../domain/search_rate_limiter.dart';

/// Zips off the UI thread. Top-level on purpose: the closure must not capture
/// the controller (it cannot be sent to another isolate).
Future<Uint8List> _buildZipInIsolate(List<ZipBuildEntry> entries) =>
    Isolate.run(() => SimpleZipBuilder.build(entries));

class RepoBrowserState {
  /// Repository + branch being browsed (`null` when nothing is selected).
  final DeployTarget? target;

  /// Head commit of the branch at the time the tree was loaded.
  final String? headCommitSha;
  final bool isEmptyRepo;

  /// Current folder (`''` is the repository root).
  final String path;
  final List<RemoteTreeEntry> entries;
  final bool isLoading;
  final String? error;

  // --- file-name search ---
  final bool searchActive;
  final String searchQuery;
  final bool isIndexing;
  final String? searchError;
  final RepoSearchResult searchResult;

  /// `true` when GitHub truncated the full tree, so results are partial.
  final bool searchPartial;

  // --- content search (GitHub Search API) ---

  /// `true` while the search screen queries file CONTENT through the Search
  /// API instead of matching file names in the local index.
  final bool codeSearchMode;
  final bool isCodeSearching;
  final String? codeSearchError;
  final RepoCodeSearchResult codeSearchResult;

  // --- multi-selection & write operations ---

  /// Full paths of the selected entries (always inside the current folder).
  final Set<String> selectedPaths;

  /// A preview / commit / undo is running: the screen is locked meanwhile.
  final bool isMutating;
  final String? busyLabel;

  /// The last commit that can still be reverted (`null` once it expires,
  /// is used, or the branch head moves).
  final RepoUndoInfo? undo;

  const RepoBrowserState({
    this.target,
    this.headCommitSha,
    this.isEmptyRepo = false,
    this.path = '',
    this.entries = const [],
    this.isLoading = false,
    this.error,
    this.searchActive = false,
    this.searchQuery = '',
    this.isIndexing = false,
    this.searchError,
    this.searchResult = RepoSearchResult.empty,
    this.searchPartial = false,
    this.codeSearchMode = false,
    this.isCodeSearching = false,
    this.codeSearchError,
    this.codeSearchResult = RepoCodeSearchResult.empty,
    this.selectedPaths = const <String>{},
    this.isMutating = false,
    this.busyLabel,
    this.undo,
  });

  /// Path segments of [path], for the breadcrumb.
  List<String> get segments =>
      path.isEmpty ? const [] : path.split('/');

  /// Multi-selection mode is on while at least one entry is selected.
  bool get isSelecting => selectedPaths.isNotEmpty;

  /// Entries of the current folder that can be selected (not submodules).
  int get selectableCount => entries.where((e) => !e.isSubmodule).length;

  RepoBrowserState copyWith({
    DeployTarget? target,
    String? headCommitSha,
    bool clearHead = false,
    bool? isEmptyRepo,
    String? path,
    List<RemoteTreeEntry>? entries,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool? searchActive,
    String? searchQuery,
    bool? isIndexing,
    String? searchError,
    bool clearSearchError = false,
    RepoSearchResult? searchResult,
    bool? searchPartial,
    bool? codeSearchMode,
    bool? isCodeSearching,
    String? codeSearchError,
    bool clearCodeSearchError = false,
    RepoCodeSearchResult? codeSearchResult,
    Set<String>? selectedPaths,
    bool? isMutating,
    String? busyLabel,
    bool clearBusy = false,
    RepoUndoInfo? undo,
    bool clearUndo = false,
  }) {
    return RepoBrowserState(
      target: target ?? this.target,
      headCommitSha: clearHead ? null : (headCommitSha ?? this.headCommitSha),
      isEmptyRepo: isEmptyRepo ?? this.isEmptyRepo,
      path: path ?? this.path,
      entries: entries ?? this.entries,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      searchActive: searchActive ?? this.searchActive,
      searchQuery: searchQuery ?? this.searchQuery,
      isIndexing: isIndexing ?? this.isIndexing,
      searchError:
          clearSearchError ? null : (searchError ?? this.searchError),
      searchResult: searchResult ?? this.searchResult,
      searchPartial: searchPartial ?? this.searchPartial,
      codeSearchMode: codeSearchMode ?? this.codeSearchMode,
      isCodeSearching: isCodeSearching ?? this.isCodeSearching,
      codeSearchError:
          clearCodeSearchError ? null : (codeSearchError ?? this.codeSearchError),
      codeSearchResult: codeSearchResult ?? this.codeSearchResult,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      isMutating: isMutating ?? this.isMutating,
      busyLabel: clearBusy ? null : (busyLabel ?? this.busyLabel),
      undo: clearUndo ? null : (undo ?? this.undo),
    );
  }
}

/// Browser for the repository currently selected in [reposControllerProvider].
///
/// Rebuilt (and therefore reset to the root) whenever the selected repository,
/// branch or account changes.
final repoBrowserControllerProvider =
    StateNotifierProvider.autoDispose<RepoBrowserController, RepoBrowserState>(
  (ref) {
    final api = ref.watch(githubApiClientProvider);
    final token = ref.watch(
      authControllerProvider.select((s) => s.activeAccount?.token),
    );
    ref.watch(
      reposControllerProvider.select((s) => (s.selectedRepo?.id, s.selectedBranch)),
    );
    final target = ref.read(reposControllerProvider).activeTarget;

    return RepoBrowserController(api: api, token: token, target: target);
  },
);

class RepoBrowserController extends StateNotifier<RepoBrowserState> {
  /// How long the "undo" bar stays available after a successful commit.
  static const Duration defaultUndoWindow = Duration(seconds: 20);

  /// Largest download assembled in memory on the phone.
  static const int maxDownloadBytes = 50 * 1024 * 1024;

  /// Archives smaller than this are zipped inline; bigger ones in an isolate.
  static const int _inlineZipLimit = 2 * 1024 * 1024;

  /// Blobs fetched in parallel while preparing a download.
  static const int _downloadParallelism = 4;

  final GitHubApiClient api;
  final String? token;
  final DeployTarget? target;
  final RepoFilesEngine _engine;
  final Duration undoWindow;

  Timer? _undoTimer;
  CancelToken? _opCancel;

  RepoContentService? _service;
  String? _rootTreeSha;
  RepoSearchIndex? _index;
  bool _indexPartial = false;

  /// Incremented by every navigation / reload; results of older ones are
  /// dropped so a slow response can never overwrite a newer screen.
  int _navSeq = 0;
  CancelToken? _navCancel;
  int _indexSeq = 0;
  CancelToken? _indexCancel;
  int _codeSearchSeq = 0;
  CancelToken? _codeSearchCancel;

  /// Throttles content searches to stay under the GitHub code-search quota.
  final SearchRateLimiter _codeSearchLimiter = SearchRateLimiter();

  /// The ops of the write commit currently in flight (set right before
  /// `applyChanges`, cleared afterwards).
  List<FileOp>? _lastWriteOps;

  /// The ops of the last write rejected by branch protection, so the screen
  /// can offer to apply them on a fresh branch and open a pull request.
  List<FileOp>? _rejectedWriteOps;

  RepoBrowserController({
    required this.api,
    required this.token,
    required this.target,
    RepoFilesEngine? engine,
    this.undoWindow = defaultUndoWindow,
  })  : _engine = engine ?? RepoFilesEngine(api: api),
        super(
          RepoBrowserState(
            target: target,
            isLoading: target != null && (token ?? '').isNotEmpty,
            error: target == null
                ? 'اختر مستودعاً أولاً لتصفح ملفاته.'
                : ((token ?? '').isEmpty ? 'لا توجد جلسة نشطة.' : null),
          ),
        ) {
    if (_canLoad) _initialize();
  }

  bool get _canLoad => target != null && (token ?? '').isNotEmpty;

  /// Reader for file contents of the loaded snapshot (`null` until loaded, or
  /// for an empty repository).
  RepoContentService? get service => _service;

  @override
  void dispose() {
    _navCancel?.cancel();
    _indexCancel?.cancel();
    _codeSearchCancel?.cancel();
    _opCancel?.cancel();
    _undoTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Loading / navigation
  // ---------------------------------------------------------------------------

  /// Re-reads the branch head and reloads [path] (falls back to the nearest
  /// existing parent folder when it no longer exists).
  Future<void> refresh() => _initialize(path: state.path);

  Future<void> _initialize({String path = ''}) async {
    final activeTarget = target;
    final activeToken = token;
    if (activeTarget == null || activeToken == null || activeToken.isEmpty) {
      return;
    }

    final seq = _beginNavigation();
    final cancel = _navCancel!;
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final head = await api.fetchBranchHead(
        token: activeToken,
        owner: activeTarget.repo.ownerLogin,
        repo: activeTarget.repo.name,
        branchName: activeTarget.branchName,
        cancelToken: cancel,
      );
      if (!_isCurrent(seq)) return;
      _dropUndoIfHeadMoved(head?.commitSha);

      if (head == null) {
        _service = null;
        _rootTreeSha = null;
        _index = null;
        state = state.copyWith(
          isLoading: false,
          isEmptyRepo: true,
          path: '',
          entries: const [],
          selectedPaths: const <String>{},
          clearHead: true,
          clearError: true,
        );
        return;
      }

      final service = RepoContentService(
        api: api,
        token: activeToken,
        owner: activeTarget.repo.ownerLogin,
        repo: activeTarget.repo.name,
        rootTreeSha: head.treeSha,
      );

      // The folder we were in may have been deleted remotely.
      var resolved = path;
      while (resolved.isNotEmpty &&
          !await service.folderExists(resolved, cancelToken: cancel)) {
        if (!_isCurrent(seq)) return;
        resolved = RepoPathValidator.parentOf(resolved);
      }
      if (!_isCurrent(seq)) return;

      final entries = await service.listFolder(resolved, cancelToken: cancel);
      if (!_isCurrent(seq)) return;

      _service = service;
      _rootTreeSha = head.treeSha;
      // The snapshot changed: drop the index (and any build in flight).
      _index = null;
      _indexSeq++;
      _indexCancel?.cancel();
      _indexCancel = null;
      state = state.copyWith(
        isLoading: false,
        isEmptyRepo: false,
        isIndexing: false,
        headCommitSha: head.commitSha,
        path: resolved,
        entries: entries,
        selectedPaths: _pruneSelection(resolved, entries),
        clearError: true,
      );

      if (state.searchActive) _ensureIndex();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      _fail(seq, 'تعذر الاتصال بخوادم GitHub.');
    } on GitHubException catch (e) {
      _fail(seq, e.message);
    } catch (_) {
      _fail(seq, 'تعذر تحميل ملفات المستودع.');
    }
  }

  /// Opens the folder [path] (`''` = root).
  Future<void> openFolder(String path) async {
    final service = _service;
    if (service == null) return;

    final seq = _beginNavigation();
    final cancel = _navCancel!;
    // Show the new location immediately; the listing follows.
    state = state.copyWith(
      path: path,
      entries: const [],
      selectedPaths: const <String>{},
      isLoading: true,
      clearError: true,
    );

    try {
      final entries = await service.listFolder(path, cancelToken: cancel);
      if (!_isCurrent(seq)) return;
      state = state.copyWith(isLoading: false, entries: entries);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      _fail(seq, 'تعذر الاتصال بخوادم GitHub.');
    } on GitHubException catch (e) {
      _fail(seq, e.message);
    } catch (_) {
      _fail(seq, 'تعذر تحميل محتوى المجلد.');
    }
  }

  /// Re-attempts the folder that failed to load.
  Future<void> retry() =>
      _service == null ? _initialize(path: state.path) : openFolder(state.path);

  /// Goes one level up. Returns `false` when already at the root.
  bool goUp() {
    if (state.path.isEmpty) return false;
    openFolder(RepoPathValidator.parentOf(state.path));
    return true;
  }

  /// Path of the child [name] inside the current folder.
  String childPath(String name) =>
      state.path.isEmpty ? name : '${state.path}/$name';

  int _beginNavigation() {
    _navCancel?.cancel();
    _navCancel = CancelToken();
    return ++_navSeq;
  }

  bool _isCurrent(int seq) => mounted && seq == _navSeq;

  void _fail(int seq, String message) {
    if (!_isCurrent(seq)) return;
    state = state.copyWith(isLoading: false, error: message);
  }

  // ---------------------------------------------------------------------------
  // Multi-selection
  // ---------------------------------------------------------------------------

  /// Submodules point at another repository: they cannot be deleted here.
  bool canSelect(RemoteTreeEntry entry) => !entry.isSubmodule;

  bool isSelected(RemoteTreeEntry entry) =>
      state.selectedPaths.contains(childPath(entry.name));

  /// A long press starts the selection; later taps / long presses toggle.
  /// Deselecting the last entry leaves selection mode.
  void toggleSelection(RemoteTreeEntry entry) {
    if (state.isMutating || state.searchActive || !canSelect(entry)) return;
    final path = childPath(entry.name);
    final next = <String>{...state.selectedPaths};
    if (!next.remove(path)) next.add(path);
    state = state.copyWith(selectedPaths: next);
  }

  /// Selects every selectable entry of the current folder.
  void selectAll() {
    if (state.isMutating || state.searchActive) return;
    state = state.copyWith(
      selectedPaths: <String>{
        for (final entry in state.entries)
          if (canSelect(entry)) childPath(entry.name),
      },
    );
  }

  void clearSelection() {
    if (state.selectedPaths.isEmpty) return;
    state = state.copyWith(selectedPaths: const <String>{});
  }

  /// Keeps only the selected paths that still exist in [entries].
  Set<String> _pruneSelection(String folder, List<RemoteTreeEntry> entries) {
    if (state.selectedPaths.isEmpty) return state.selectedPaths;
    final alive = <String>{
      for (final entry in entries)
        folder.isEmpty ? entry.name : '$folder/${entry.name}',
    };
    return state.selectedPaths.where(alive.contains).toSet();
  }

  /// Selected paths in a stable order. The selection never mixes levels
  /// (it is cleared when the folder changes), so no path can be nested inside
  /// another selected one.
  List<String> _selectedPathsSorted() => state.selectedPaths.toList()..sort();

  bool _isFolderPath(String path) => state.entries.any(
        (entry) => entry.isFolder && childPath(entry.name) == path,
      );

  // ---------------------------------------------------------------------------
  // Delete / undo (one atomic commit through RepoFilesEngine)
  // ---------------------------------------------------------------------------

  RepoOpResult<T>? _blockedWrite<T>() {
    final activeToken = token;
    if (target == null || activeToken == null || activeToken.isEmpty) {
      return RepoOpResult.failed(
        RepoOpFailure.invalid,
        'لا توجد جلسة نشطة أو مستودع محدد.',
      );
    }
    if (state.isMutating) {
      return RepoOpResult.failed(
        RepoOpFailure.invalid,
        'عملية أخرى قيد التنفيذ، انتظر انتهاءها.',
      );
    }
    if (state.headCommitSha == null) {
      return RepoOpResult.failed(
        RepoOpFailure.invalid,
        'لم تُحمَّل ملفات الفرع بعد.',
      );
    }
    return null;
  }

  void _endBusy() {
    if (mounted) state = state.copyWith(isMutating: false, clearBusy: true);
  }

  /// Maps [error]; when the branch moved, reloads the listing first so the
  /// user sees what changed. A rejection by branch protection keeps the ops
  /// around for the "new branch + pull request" fallback.
  Future<RepoOpResult<T>> _failWrite<T>(Object error) async {
    final failure = RepoOpResult.fromError<T>(error);
    if (failure.failure == RepoOpFailure.protectedBranch) {
      _rejectedWriteOps = _lastWriteOps;
    }
    if (failure.failure == RepoOpFailure.branchChanged && mounted) {
      state = state.copyWith(busyLabel: 'جارٍ تحديث الملفات...');
      await _initialize(path: state.path);
    }
    return failure;
  }

  /// The ops rejected by branch protection (taken once, then cleared), or
  /// `null` when the last failure was not a protected-branch rejection.
  List<FileOp>? takeRejectedWriteOps() {
    final ops = _rejectedWriteOps;
    _rejectedWriteOps = null;
    return ops;
  }

  /// Resolves the selection into a plan (nothing is written) for the
  /// confirmation dialog.
  Future<RepoOpResult<RepoDeletePreview>> previewDeleteSelection() async {
    final blocked = _blockedWrite<RepoDeletePreview>();
    if (blocked != null) return blocked;

    final paths = _selectedPathsSorted();
    if (paths.isEmpty) {
      return RepoOpResult.failed(RepoOpFailure.invalid, 'لم تحدد أي عنصر.');
    }
    final folders = [for (final p in paths) if (_isFolderPath(p)) p];
    final files = [for (final p in paths) if (!_isFolderPath(p)) p];

    final cancel = _opCancel = CancelToken();
    state = state.copyWith(
      isMutating: true,
      busyLabel: 'جارٍ تجهيز ملخص الحذف...',
    );
    try {
      final plan = await _engine.previewChanges(
        token: token!,
        target: target!,
        ops: [for (final path in paths) DeleteOp(path)],
        expectedHeadSha: state.headCommitSha,
        cancelToken: cancel,
      );
      return RepoOpResult.success(
        RepoDeletePreview.build(
          plan: plan,
          folderPaths: folders,
          filePaths: files,
        ),
      );
    } catch (e) {
      return await _failWrite<RepoDeletePreview>(e);
    } finally {
      _endBusy();
    }
  }

  /// Deletes the selection in ONE commit, then reloads the listing and
  /// offers an undo.
  Future<RepoOpResult<RepoCommitResult>> deleteSelection({
    required String message,
  }) async {
    final blocked = _blockedWrite<RepoCommitResult>();
    if (blocked != null) return blocked;

    final paths = _selectedPathsSorted();
    if (paths.isEmpty) {
      return RepoOpResult.failed(RepoOpFailure.invalid, 'لم تحدد أي عنصر.');
    }

    final cancel = _opCancel = CancelToken();
    state = state.copyWith(
      isMutating: true,
      busyLabel: 'جارٍ حذف العناصر في Commit واحد...',
    );
    final ops = [for (final path in paths) DeleteOp(path)];
    _lastWriteOps = ops;
    try {
      final result = await _engine.applyChanges(
        token: token!,
        target: target!,
        ops: ops,
        message: message,
        expectedHeadSha: state.headCommitSha,
        cancelToken: cancel,
      );
      if (!mounted) return RepoOpResult.success(result);
      _lastWriteOps = null;

      final deleted = paths.toSet();
      final fileCount = result.plan.deletedPaths.length;
      final summary = StringBuffer('تم حذف ${arabicItems(paths.length)}');
      if (fileCount != paths.length) {
        summary.write(' (${arabicFiles(fileCount)})');
      }
      // Show the new state right away; the reload below confirms it.
      state = state.copyWith(
        selectedPaths: const <String>{},
        entries: [
          for (final entry in state.entries)
            if (!deleted.contains(childPath(entry.name))) entry,
        ],
        undo: RepoUndoInfo(
          result: result,
          summary: summary.toString(),
          kind: RepoUndoKind.delete,
        ),
      );
      _startUndoTimer();
      await _initialize(path: state.path);
      return RepoOpResult.success(result);
    } catch (e) {
      return await _failWrite<RepoCommitResult>(e);
    } finally {
      _endBusy();
    }
  }

  // ---------------------------------------------------------------------------
  // Move / rename (one atomic commit, no content is re-uploaded)
  // ---------------------------------------------------------------------------

  /// Sub-folders of [folderPath] of the loaded snapshot, for the destination
  /// picker of the move action.
  Future<List<RemoteTreeEntry>> listSubfolders(
    String folderPath, {
    CancelToken? cancelToken,
  }) async {
    final service = _service;
    if (service == null) {
      throw const InvalidRepoOperationException('لم تُحمَّل ملفات الفرع بعد.');
    }
    final entries =
        await service.listFolder(folderPath, cancelToken: cancelToken);
    return [
      for (final entry in entries)
        if (entry.isFolder) entry,
    ];
  }

  /// One [RenameOp] per selected entry, moving it into [destinationFolder]
  /// (`''` = repository root). Returns an Arabic error when the move is not
  /// allowed (nothing is requested from GitHub yet).
  ({List<RenameOp>? ops, String? error}) _moveOps(String destinationFolder) {
    if (destinationFolder.isNotEmpty) {
      final error = RepoPathValidator.validate(destinationFolder);
      if (error != null) return (ops: null, error: error);
    }
    if (destinationFolder == state.path) {
      return (ops: null, error: 'اختر مجلداً مختلفاً عن المجلد الحالي.');
    }

    final ops = <RenameOp>[];
    for (final from in _selectedPathsSorted()) {
      if (destinationFolder == from ||
          RepoPathValidator.isInside(from, destinationFolder)) {
        return (ops: null, error: 'لا يمكن نقل مجلد إلى داخل نفسه.');
      }
      final name = RepoPathValidator.nameOf(from);
      ops.add(
        RenameOp(
          fromPath: from,
          toPath: destinationFolder.isEmpty ? name : '$destinationFolder/$name',
        ),
      );
    }
    if (ops.isEmpty) return (ops: null, error: 'لم تحدد أي عنصر.');
    return (ops: ops, error: null);
  }

  /// The [RenameOp] that gives the single selected entry [newName] (same
  /// folder). Returns an Arabic error when the name is not acceptable.
  ({RenameOp? op, String? error}) _renameOp(String newName) {
    final paths = _selectedPathsSorted();
    if (paths.length != 1) {
      return (op: null, error: 'حدد عنصراً واحداً فقط لإعادة تسميته.');
    }
    final name = newName.trim();
    if (name.isEmpty) return (op: null, error: 'أدخل الاسم الجديد.');
    if (name.contains('/') || name.contains('\\')) {
      return (
        op: null,
        error: 'أدخل الاسم فقط بدون "/". لنقل العنصر استخدم زر النقل.',
      );
    }

    final from = paths.first;
    final to = state.path.isEmpty ? name : '${state.path}/$name';
    if (to == from) {
      return (op: null, error: 'الاسم الجديد مطابق للاسم الحالي.');
    }
    final error = RepoPathValidator.validate(to);
    if (error != null) return (op: null, error: error);
    return (op: RenameOp(fromPath: from, toPath: to), error: null);
  }

  /// Resolves moving the selection into [destinationFolder] (nothing is
  /// written) for the confirmation dialog.
  Future<RepoOpResult<RepoPathChangePreview>> previewMoveSelection(
    String destinationFolder,
  ) async {
    final blocked = _blockedWrite<RepoPathChangePreview>();
    if (blocked != null) return blocked;

    final built = _moveOps(destinationFolder);
    final ops = built.ops;
    if (ops == null) {
      return RepoOpResult.failed(RepoOpFailure.invalid, built.error!);
    }
    return _previewPathChange(
      kind: RepoPathChangeKind.move,
      ops: ops,
      destinationFolder: destinationFolder,
      busyLabel: 'جارٍ تجهيز ملخص النقل...',
    );
  }

  /// Resolves renaming the single selected entry to [newName] (nothing is
  /// written). Folders go through the confirmation dialog because every file
  /// inside them changes path.
  Future<RepoOpResult<RepoPathChangePreview>> previewRenameSelected(
    String newName,
  ) async {
    final blocked = _blockedWrite<RepoPathChangePreview>();
    if (blocked != null) return blocked;

    final built = _renameOp(newName);
    final op = built.op;
    if (op == null) {
      return RepoOpResult.failed(RepoOpFailure.invalid, built.error!);
    }
    return _previewPathChange(
      kind: RepoPathChangeKind.rename,
      ops: [op],
      destinationFolder: state.path,
      busyLabel: 'جارٍ تجهيز ملخص إعادة التسمية...',
    );
  }

  Future<RepoOpResult<RepoPathChangePreview>> _previewPathChange({
    required RepoPathChangeKind kind,
    required List<RenameOp> ops,
    required String destinationFolder,
    required String busyLabel,
  }) async {
    final cancel = _opCancel = CancelToken();
    state = state.copyWith(isMutating: true, busyLabel: busyLabel);
    try {
      final plan = await _engine.previewChanges(
        token: token!,
        target: target!,
        ops: ops,
        expectedHeadSha: state.headCommitSha,
        cancelToken: cancel,
      );
      return RepoOpResult.success(
        RepoPathChangePreview.build(
          kind: kind,
          plan: plan,
          selectedMoves: [
            for (final op in ops)
              (
                from: op.fromPath,
                to: op.toPath,
                isFolder: _isFolderPath(op.fromPath),
              ),
          ],
          destinationFolder: destinationFolder,
        ),
      );
    } catch (e) {
      return await _failWrite<RepoPathChangePreview>(e);
    } finally {
      _endBusy();
    }
  }

  /// Moves the selection into [destinationFolder] in ONE commit, then
  /// reloads the listing and offers an undo.
  Future<RepoOpResult<RepoCommitResult>> moveSelection({
    required String destinationFolder,
    required String message,
  }) async {
    final blocked = _blockedWrite<RepoCommitResult>();
    if (blocked != null) return blocked;

    final built = _moveOps(destinationFolder);
    final ops = built.ops;
    if (ops == null) {
      return RepoOpResult.failed(RepoOpFailure.invalid, built.error!);
    }
    final summary = ops.length == 1
        ? 'تم نقل "${RepoPathValidator.nameOf(ops.first.fromPath)}"'
        : 'تم نقل ${arabicItems(ops.length)}';
    return _commitPathChange(
      ops: ops,
      message: message,
      busyLabel: 'جارٍ نقل العناصر في Commit واحد...',
      summary: summary,
      kind: RepoUndoKind.move,
    );
  }

  /// Renames the single selected entry in ONE commit, then reloads the
  /// listing and offers an undo.
  Future<RepoOpResult<RepoCommitResult>> renameSelected({
    required String newName,
    required String message,
  }) async {
    final blocked = _blockedWrite<RepoCommitResult>();
    if (blocked != null) return blocked;

    final built = _renameOp(newName);
    final op = built.op;
    if (op == null) {
      return RepoOpResult.failed(RepoOpFailure.invalid, built.error!);
    }
    return _commitPathChange(
      ops: [op],
      message: message,
      busyLabel: 'جارٍ إعادة التسمية...',
      summary:
          'تمت إعادة تسمية "${RepoPathValidator.nameOf(op.fromPath)}" إلى "${RepoPathValidator.nameOf(op.toPath)}"',
      kind: RepoUndoKind.rename,
    );
  }

  /// Commits [ops] as ONE atomic change on the browsed branch, reloads the
  /// listing and offers an undo. Shared by delete / move / rename / create /
  /// upload / restore.
  Future<RepoOpResult<RepoCommitResult>> _commitOps({
    required List<FileOp> ops,
    required String message,
    required String busyLabel,
    required String summary,
    required RepoUndoKind kind,
  }) async {
    final cancel = _opCancel = CancelToken();
    state = state.copyWith(isMutating: true, busyLabel: busyLabel);
    _lastWriteOps = ops;
    try {
      final result = await _engine.applyChanges(
        token: token!,
        target: target!,
        ops: ops,
        message: message,
        expectedHeadSha: state.headCommitSha,
        cancelToken: cancel,
      );
      if (!mounted) return RepoOpResult.success(result);
      _lastWriteOps = null;

      // A folder move touches many files: say how many.
      final fileCount = result.plan.renamedPaths.length;
      final text = StringBuffer(summary);
      if (fileCount > ops.length) text.write(' (${arabicFiles(fileCount)})');

      state = state.copyWith(
        selectedPaths: const <String>{},
        undo: RepoUndoInfo(
          result: result,
          summary: text.toString(),
          kind: kind,
        ),
      );
      _startUndoTimer();
      await _initialize(path: state.path);
      return RepoOpResult.success(result);
    } catch (e) {
      return await _failWrite<RepoCommitResult>(e);
    } finally {
      _endBusy();
    }
  }

  Future<RepoOpResult<RepoCommitResult>> _commitPathChange({
    required List<RenameOp> ops,
    required String message,
    required String busyLabel,
    required String summary,
    required RepoUndoKind kind,
  }) =>
      _commitOps(
        ops: ops,
        message: message,
        busyLabel: busyLabel,
        summary: summary,
        kind: kind,
      );

  // ---------------------------------------------------------------------------
  // Text editor: conflict check + save (one atomic commit)
  // ---------------------------------------------------------------------------

  /// Compares the branch head the editor was opened on ([openedHeadSha]) with
  /// the head GitHub has now. Nothing is written.
  ///
  /// * success(`null`): the head did not move, saving is safe.
  /// * success(info): the head moved. [RepoEditConflictInfo.sameFileChanged]
  ///   tells whether this very file changed (or was deleted) in the meantime.
  Future<RepoOpResult<RepoEditConflictInfo?>> checkEditConflict({
    required RepoFileRef openedFile,
    required String openedHeadSha,
  }) async {
    final activeToken = token;
    final activeTarget = target;
    if (activeTarget == null || activeToken == null || activeToken.isEmpty) {
      return RepoOpResult.failed(
        RepoOpFailure.invalid,
        'لا توجد جلسة نشطة أو مستودع محدد.',
      );
    }

    final cancel = _opCancel = CancelToken();
    try {
      final head = await api.fetchBranchHead(
        token: activeToken,
        owner: activeTarget.repo.ownerLogin,
        repo: activeTarget.repo.name,
        branchName: activeTarget.branchName,
        cancelToken: cancel,
      );
      if (head == null) {
        return RepoOpResult.failed(
          RepoOpFailure.invalid,
          'الفرع \"${activeTarget.branchName}\" غير موجود أو المستودع فارغ.',
        );
      }
      if (head.commitSha == openedHeadSha) {
        return const RepoOpResult.success(null);
      }

      // The head moved: find out whether OUR file is affected.
      final latest = await RepoContentService(
        api: api,
        token: activeToken,
        owner: activeTarget.repo.ownerLogin,
        repo: activeTarget.repo.name,
        rootTreeSha: head.treeSha,
      ).findFile(openedFile.path, cancelToken: cancel);

      if (latest == null) {
        return RepoOpResult.success(
          RepoEditConflictInfo(
            openedHeadSha: openedHeadSha,
            latestHeadSha: head.commitSha,
            sameFileChanged: true,
            fileDeletedRemotely: true,
          ),
        );
      }
      return RepoOpResult.success(
        RepoEditConflictInfo(
          openedHeadSha: openedHeadSha,
          latestHeadSha: head.commitSha,
          sameFileChanged:
              latest.sha != openedFile.sha || latest.mode != openedFile.mode,
          fileDeletedRemotely: false,
          latestFileRef: RepoFileRef(
            path: latest.path,
            sha: latest.sha,
            size: latest.size,
            mode: latest.mode,
          ),
        ),
      );
    } catch (e) {
      return RepoOpResult.fromError<RepoEditConflictInfo?>(e);
    }
  }

  /// Commits the edited [bytes] of [openedFile] in ONE commit on top of
  /// [expectedHeadSha] (never forced: a concurrent push gives
  /// [RepoOpFailure.branchChanged]). The file mode (e.g. `100755`) is kept by
  /// the engine; line endings / BOM are already applied by the caller through
  /// `RepoTextCodec.encodeForCommit`.
  Future<RepoOpResult<RepoFileSaveResult>> saveFileEdit({
    required RepoFileRef openedFile,
    required Uint8List bytes,
    required String message,
    required String expectedHeadSha,
  }) async {
    final blocked = _blockedWrite<RepoFileSaveResult>();
    if (blocked != null) return blocked;

    final sizeError = RepoEditGuard.validateEncodedSize(bytes);
    if (sizeError != null) {
      return RepoOpResult.failed(RepoOpFailure.invalid, sizeError);
    }

    final cancel = _opCancel = CancelToken();
    state = state.copyWith(
      isMutating: true,
      busyLabel: 'جارٍ حفظ التعديلات في Commit واحد...',
    );
    final ops = [UpdateFileOp(path: openedFile.path, bytes: bytes)];
    _lastWriteOps = ops;
    try {
      final result = await _engine.applyChanges(
        token: token!,
        target: target!,
        ops: ops,
        message: message,
        expectedHeadSha: expectedHeadSha,
        cancelToken: cancel,
      );
      _lastWriteOps = null;

      final newSha = result.uploadedBlobShas[openedFile.path];
      final saved = RepoFileSaveResult(
        commit: result,
        updatedFile: newSha == null
            ? null
            : RepoFileRef(
                path: openedFile.path,
                sha: newSha,
                size: bytes.length,
                mode: openedFile.mode,
              ),
      );
      if (!mounted) return RepoOpResult.success(saved);

      state = state.copyWith(
        undo: RepoUndoInfo(
          result: result,
          summary: 'تم حفظ التعديلات في \"${openedFile.name}\"',
          kind: RepoUndoKind.edit,
        ),
      );
      _startUndoTimer();
      await _initialize(path: state.path);
      return RepoOpResult.success(saved);
    } catch (e) {
      return await _failWrite<RepoFileSaveResult>(e);
    } finally {
      _endBusy();
    }
  }

  // ---------------------------------------------------------------------------
  // Download (read-only)
  // ---------------------------------------------------------------------------

  /// Reads the selection from GitHub: one file is returned as is, anything
  /// else (several items, or a folder) as a ZIP whose paths are relative to
  /// the current folder. Nothing is written to the repository.
  Future<RepoOpResult<RepoDownloadPayload>> prepareDownload() async {
    final blocked = _blockedWrite<RepoDownloadPayload>();
    if (blocked != null) return blocked;

    final service = _service;
    final activeTarget = target;
    final paths = _selectedPathsSorted();
    if (service == null || activeTarget == null || paths.isEmpty) {
      return RepoOpResult.failed(RepoOpFailure.invalid, 'لم تحدد أي عنصر.');
    }

    final cancel = _opCancel = CancelToken();
    state = state.copyWith(
      isMutating: true,
      busyLabel: 'جارٍ تجهيز الملفات للتنزيل...',
    );
    try {
      final files = <RemoteTreeBlob>[];
      for (final path in paths) {
        RemoteTreeEntry? entry;
        for (final candidate in state.entries) {
          if (childPath(candidate.name) == path) {
            entry = candidate;
            break;
          }
        }
        if (entry == null) continue;
        if (entry.isFolder) {
          files.addAll(await service.blobsUnder(path, cancelToken: cancel));
        } else if (entry.isFile) {
          files.add(
            RemoteTreeBlob(
              path: path,
              sha: entry.sha,
              mode: entry.mode,
              size: entry.size,
            ),
          );
        }
      }

      if (files.isEmpty) {
        return RepoOpResult.failed(
          RepoOpFailure.invalid,
          'لا توجد ملفات للتنزيل في التحديد.',
        );
      }
      final total = files.fold<int>(0, (sum, file) => sum + file.size);
      if (total > maxDownloadBytes) {
        return RepoOpResult.failed(
          RepoOpFailure.invalid,
          'حجم الملفات المحددة (${formatBytes(total)}) يتجاوز الحد المسموح للتنزيل '
          '(${formatBytes(maxDownloadBytes)}).',
        );
      }

      final singleFile = paths.length == 1 &&
          files.length == 1 &&
          !_isFolderPath(paths.first);
      if (singleFile) {
        final file = files.first;
        final bytes = await service.readBlob(file.sha, cancelToken: cancel);
        return RepoOpResult.success(
          RepoDownloadPayload(
            fileName: RepoPathValidator.nameOf(file.path),
            bytes: bytes,
            fileCount: 1,
            isZip: false,
          ),
        );
      }

      final prefix = state.path.isEmpty ? '' : '${state.path}/';
      final zipEntries = <ZipBuildEntry>[];
      for (var i = 0; i < files.length; i += _downloadParallelism) {
        final chunk = files.skip(i).take(_downloadParallelism).toList();
        if (mounted) {
          state = state.copyWith(
            busyLabel: 'جارٍ تنزيل الملفات (${i + chunk.length}/${files.length})...',
          );
        }
        final contents = await Future.wait([
          for (final file in chunk)
            service.readBlob(file.sha, cancelToken: cancel),
        ]);
        for (var j = 0; j < chunk.length; j++) {
          final fullPath = chunk[j].path;
          zipEntries.add(
            ZipBuildEntry(
              path: fullPath.startsWith(prefix)
                  ? fullPath.substring(prefix.length)
                  : fullPath,
              bytes: contents[j],
            ),
          );
        }
      }

      if (mounted) state = state.copyWith(busyLabel: 'جارٍ ضغط الأرشيف...');
      final Uint8List zipBytes = total <= _inlineZipLimit
          ? SimpleZipBuilder.build(zipEntries)
          : await _buildZipInIsolate(zipEntries);

      final onlyFolder = paths.length == 1 && _isFolderPath(paths.first);
      return RepoOpResult.success(
        RepoDownloadPayload(
          fileName: onlyFolder
              ? '${RepoPathValidator.nameOf(paths.first)}.zip'
              : '${activeTarget.repo.name}-selection.zip',
          bytes: zipBytes,
          fileCount: files.length,
          isZip: true,
        ),
      );
    } catch (e) {
      return RepoOpResult.fromError<RepoDownloadPayload>(e);
    } finally {
      _endBusy();
    }
  }

  // ---------------------------------------------------------------------------
  // Create / upload (one atomic commit)
  // ---------------------------------------------------------------------------

  /// Creates a new file, or a folder whose `.gitkeep` makes it exist for Git.
  /// [name] may span nested folders (`assets/icons`); it is resolved relative
  /// to the folder being browsed.
  Future<RepoOpResult<RepoCommitResult>> createEntry({
    required String name,
    required Uint8List? bytes, // null = folder (.gitkeep)
    required String message,
  }) async {
    final blocked = _blockedWrite<RepoCommitResult>();
    if (blocked != null) return blocked;

    var clean = name.trim().replaceAll('\\', '/');
    while (clean.startsWith('/')) {
      clean = clean.substring(1);
    }
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (clean.isEmpty) {
      return RepoOpResult.failed(RepoOpFailure.invalid, 'أدخل اسماً صالحاً.');
    }
    final isFolder = bytes == null;
    final fullPath = childPath(isFolder ? '$clean/.gitkeep' : clean);
    final pathError = RepoPathValidator.validate(fullPath);
    if (pathError != null) {
      return RepoOpResult.failed(RepoOpFailure.invalid, pathError);
    }

    return _commitOps(
      ops: [CreateFileOp(path: fullPath, bytes: bytes ?? Uint8List(0))],
      message: message,
      busyLabel: 'جارٍ إنشاء ${isFolder ? 'المجلد' : 'الملف'} في Commit واحد...',
      summary: isFolder
          ? 'تم إنشاء مجلد "$clean"'
          : 'تم إنشاء "${childPath(clean)}"',
      kind: RepoUndoKind.create,
    );
  }

  /// Uploads files picked on the phone into the folder being browsed as ONE
  /// atomic commit. With [overwriteExisting] colliding names become updates;
  /// without it a collision is refused before anything is sent.
  Future<RepoOpResult<RepoCommitResult>> uploadFiles({
    required List<({String name, Uint8List bytes})> files,
    required String message,
    required bool overwriteExisting,
  }) async {
    final blocked = _blockedWrite<RepoCommitResult>();
    if (blocked != null) return blocked;
    if (files.isEmpty) {
      return RepoOpResult.failed(RepoOpFailure.invalid, 'لم تختر أي ملفات للرفع.');
    }

    final existingNames = <String>{
      for (final entry in state.entries)
        if (entry.isFile) entry.name,
    };
    final ops = <FileOp>[];
    for (final file in files) {
      final clean = file.name.trim();
      if (clean.isEmpty || clean.contains('/') || clean.contains('\\')) {
        return RepoOpResult.failed(
          RepoOpFailure.invalid,
          'اسم ملف غير صالح: "${file.name}".',
        );
      }
      final fullPath = childPath(clean);
      final pathError = RepoPathValidator.validate(fullPath);
      if (pathError != null) {
        return RepoOpResult.failed(
          RepoOpFailure.invalid,
          '$pathError ("${file.name}")',
        );
      }
      final collides = existingNames.contains(clean);
      if (collides && !overwriteExisting) {
        return RepoOpResult.failed(
          RepoOpFailure.invalid,
          'يوجد ملف بنفس الاسم: "$clean". فعّل الاستبدال أو أعد تسمية الملف.',
        );
      }
      ops.add(
        collides
            ? UpdateFileOp(path: fullPath, bytes: file.bytes)
            : CreateFileOp(path: fullPath, bytes: file.bytes),
      );
    }

    final destination = state.path.isEmpty ? '/' : '${state.path}/';
    return _commitOps(
      ops: ops,
      message: message,
      busyLabel: 'جارٍ رفع ${arabicFiles(files.length)} في Commit واحد...',
      summary: 'تم رفع ${arabicFiles(files.length)} إلى $destination',
      kind: RepoUndoKind.upload,
    );
  }

  // ---------------------------------------------------------------------------
  // File history & restore (phase 10)
  // ---------------------------------------------------------------------------

  /// Commit history touching [filePath] on the browsed branch (latest first).
  Future<RepoOpResult<List<RepoCommitSummary>>> fetchFileHistory(
    String filePath,
  ) async {
    final activeTarget = target;
    final activeToken = token;
    if (activeTarget == null || activeToken == null || activeToken.isEmpty) {
      return RepoOpResult.failed(
        RepoOpFailure.invalid,
        'لا توجد جلسة نشطة أو مستودع محدد.',
      );
    }

    final cancel = _opCancel = CancelToken();
    try {
      final commits = await api.fetchCommits(
        token: activeToken,
        owner: activeTarget.repo.ownerLogin,
        repo: activeTarget.repo.name,
        branchName: activeTarget.branchName,
        path: filePath,
        cancelToken: cancel,
      );
      return RepoOpResult.success(commits);
    } catch (e) {
      return RepoOpResult.fromError<List<RepoCommitSummary>>(e);
    }
  }

  /// Restores [filePath] with its content from [commit] by creating a NEW
  /// commit on the branch head (history is never rewritten). The file mode is
  /// taken from the restored version.
  Future<RepoOpResult<RepoFileSaveResult>> restoreFileFromCommit({
    required String filePath,
    required RepoCommitSummary commit,
  }) async {
    final blocked = _blockedWrite<RepoFileSaveResult>();
    if (blocked != null) return blocked;

    final activeTarget = target!;
    final cancel = _opCancel = CancelToken();
    state = state.copyWith(
      isMutating: true,
      busyLabel: 'جارٍ استعادة النسخة ${commit.shortSha}...',
    );
    try {
      final commitTreeSha = await api.fetchCommitTreeSha(
        token: token!,
        owner: activeTarget.repo.ownerLogin,
        repo: activeTarget.repo.name,
        commitSha: commit.sha,
        cancelToken: cancel,
      );
      final historic = await RepoContentService(
        api: api,
        token: token!,
        owner: activeTarget.repo.ownerLogin,
        repo: activeTarget.repo.name,
        rootTreeSha: commitTreeSha,
      ).findFile(filePath, cancelToken: cancel);
      if (historic == null) {
        return RepoOpResult.failed(
          RepoOpFailure.invalid,
          'الملف غير موجود في النسخة ${commit.shortSha}.',
        );
      }
      final bytes = await RepoContentService(
        api: api,
        token: token!,
        owner: activeTarget.repo.ownerLogin,
        repo: activeTarget.repo.name,
        rootTreeSha: commitTreeSha,
      ).readBlob(historic.sha, cancelToken: cancel);

      // Nothing to do when the restored content is identical to what is on
      // the branch right now.
      final current = await _service?.findFile(filePath, cancelToken: cancel);
      if (current != null && current.sha == historic.sha) {
        return RepoOpResult.failed(
          RepoOpFailure.invalid,
          'النسخة ${commit.shortSha} مطابقة للمحتوى الحالي.',
        );
      }

      final result = await _engine.applyChanges(
        token: token!,
        target: activeTarget,
        ops: [UpdateFileOp(path: filePath, bytes: bytes)],
        message: 'Nexus: restore "$filePath" from ${commit.shortSha}',
        expectedHeadSha: state.headCommitSha,
        cancelToken: cancel,
      );

      final newSha = result.uploadedBlobShas[filePath];
      final restored = RepoFileRef(
        path: filePath,
        sha: newSha ?? historic.sha,
        size: bytes.length,
        mode: historic.mode,
      );
      if (!mounted) {
        return RepoOpResult.success(
          RepoFileSaveResult(commit: result, updatedFile: restored),
        );
      }

      state = state.copyWith(
        undo: RepoUndoInfo(
          result: result,
          summary:
              'تمت استعادة "${RepoPathValidator.nameOf(filePath)}" من ${commit.shortSha}',
          kind: RepoUndoKind.restore,
        ),
      );
      _startUndoTimer();
      await _initialize(path: state.path);
      return RepoOpResult.success(
        RepoFileSaveResult(commit: result, updatedFile: restored),
      );
    } catch (e) {
      return await _failWrite<RepoFileSaveResult>(e);
    } finally {
      _endBusy();
    }
  }

  /// Resolves a bookmarked file path against the loaded snapshot, so a
  /// favorite / recent entry can be opened without storing blob SHAs.
  Future<RepoFileRef?> resolveFileRef(
    String filePath, {
    CancelToken? cancelToken,
  }) async {
    final blob = await _service?.findFile(filePath, cancelToken: cancelToken);
    if (blob == null) return null;
    return RepoFileRef(
      path: blob.path,
      sha: blob.sha,
      size: blob.size,
      mode: blob.mode,
    );
  }

  // ---------------------------------------------------------------------------
  // Protected branch fallback: new branch + pull request (phase 10)
  // ---------------------------------------------------------------------------

  /// Applies the write that a protected branch rejected onto a NEW branch
  /// created from the current one, then opens a pull request back into it.
  /// A half-finished flow cleans up the branch it created.
  Future<RepoOpResult<CreatedPullRequestResult>>
      commitOnNewBranchAndOpenPullRequest({
    required List<FileOp> ops,
    required String message,
    required String newBranchName,
    required String prTitle,
    String prBody = '',
  }) async {
    final activeTarget = target;
    final activeToken = token;
    if (activeTarget == null || activeToken == null || activeToken.isEmpty) {
      return RepoOpResult.failed(
        RepoOpFailure.invalid,
        'لا توجد جلسة نشطة أو مستودع محدد.',
      );
    }
    if (state.isMutating) {
      return RepoOpResult.failed(
        RepoOpFailure.invalid,
        'عملية أخرى قيد التنفيذ، انتظر انتهاءها.',
      );
    }

    final branch = newBranchName.trim();
    final title = prTitle.trim();
    if (branch.isEmpty || branch == activeTarget.branchName) {
      return RepoOpResult.failed(
        RepoOpFailure.invalid,
        'أدخل اسماً مختلفاً للفرع الجديد.',
      );
    }
    if (title.isEmpty) {
      return RepoOpResult.failed(
        RepoOpFailure.invalid,
        'أدخل عنوان الـ Pull Request.',
      );
    }

    final owner = activeTarget.repo.ownerLogin;
    final repo = activeTarget.repo.name;
    final cancel = _opCancel = CancelToken();
    state = state.copyWith(
      isMutating: true,
      busyLabel: 'جارٍ إنشاء الفرع "$branch"...',
    );
    var branchCreated = false;
    try {
      await api.createBranch(
        token: activeToken,
        owner: owner,
        repo: repo,
        newBranchName: branch,
        baseBranchName: activeTarget.branchName,
      );
      branchCreated = true;

      state = state.copyWith(busyLabel: 'جارٍ تطبيق التغييرات على الفرع الجديد...');
      await _engine.applyChanges(
        token: activeToken,
        target: DeployTarget(
          repo: activeTarget.repo,
          branchName: branch,
          isEmptyRepo: false,
        ),
        ops: ops,
        message: message,
        cancelToken: cancel,
      );

      state = state.copyWith(busyLabel: 'جارٍ فتح الـ Pull Request...');
      final pr = await api.createPullRequest(
        token: activeToken,
        owner: owner,
        repo: repo,
        title: title,
        headBranch: branch,
        baseBranch: activeTarget.branchName,
        body: prBody,
        cancelToken: cancel,
      );
      if (mounted) _endBusy();
      return RepoOpResult.success(pr);
    } catch (e) {
      // The commit may have landed without a PR, or the branch may be empty:
      // either way a stray branch has no value for the user.
      if (branchCreated) {
        try {
          await api.deleteBranchRef(
            token: activeToken,
            owner: owner,
            repo: repo,
            branchName: branch,
          );
        } catch (_) {
          // Cleanup is best-effort only.
        }
      }
      if (mounted) _endBusy();
      return RepoOpResult.fromError<CreatedPullRequestResult>(e);
    }
  }

  /// Reverts the last change (delete / move / rename). Refused (and the bar dropped) when anybody
  /// pushed to the branch in the meantime.
  Future<RepoOpResult<CreatedCommitResult>> undoLastChange() async {
    final undo = state.undo;
    if (undo == null) {
      return RepoOpResult.failed(
        RepoOpFailure.invalid,
        'لا توجد عملية يمكن التراجع عنها.',
      );
    }
    final blocked = _blockedWrite<CreatedCommitResult>();
    if (blocked != null) return blocked;

    final cancel = _opCancel = CancelToken();
    state = state.copyWith(isMutating: true, busyLabel: 'جارٍ التراجع...');
    try {
      final revert = await _engine.undoCommit(
        token: token!,
        target: target!,
        result: undo.result,
        cancelToken: cancel,
      );
      if (!mounted) return RepoOpResult.success(revert);
      _clearUndo();
      await _initialize(path: state.path);
      return RepoOpResult.success(revert);
    } catch (e) {
      final failure = RepoOpResult.fromError<CreatedCommitResult>(e);
      if (mounted && failure.failure == RepoOpFailure.branchChanged) {
        _clearUndo();
        state = state.copyWith(busyLabel: 'جارٍ تحديث الملفات...');
        await _initialize(path: state.path);
      }
      return failure;
    } finally {
      _endBusy();
    }
  }

  /// Hides the undo bar without reverting.
  void dismissUndo() => _clearUndo();

  void _startUndoTimer() {
    _undoTimer?.cancel();
    _undoTimer = Timer(undoWindow, () {
      if (mounted) _clearUndo();
    });
  }

  void _clearUndo() {
    _undoTimer?.cancel();
    _undoTimer = null;
    if (mounted && state.undo != null) state = state.copyWith(clearUndo: true);
  }

  /// The undo only makes sense while its commit is still the branch head.
  void _dropUndoIfHeadMoved(String? headSha) {
    final undo = state.undo;
    if (undo != null && undo.result.commit.sha != headSha) _clearUndo();
  }

  // ---------------------------------------------------------------------------
  // File-name search
  // ---------------------------------------------------------------------------

  void setSearchActive(bool active) {
    _codeSearchSeq++;
    _codeSearchCancel?.cancel();
    _codeSearchCancel = null;
    state = state.copyWith(
      searchActive: active,
      searchQuery: '',
      searchResult: RepoSearchResult.empty,
      clearSearchError: true,
      codeSearchMode: false,
      isCodeSearching: false,
      codeSearchResult: RepoCodeSearchResult.empty,
      clearCodeSearchError: true,
    );
    if (active) {
      _ensureIndex();
    } else {
      _indexCancel?.cancel();
      _indexCancel = null;
      _indexSeq++;
      if (state.isIndexing) state = state.copyWith(isIndexing: false);
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(
      searchQuery: query,
      searchResult: _index?.search(query) ?? RepoSearchResult.empty,
    );
  }

  Future<void> _ensureIndex() async {
    if (_index != null || state.isIndexing) return;
    final activeTarget = target;
    final activeToken = token;
    final rootTreeSha = _rootTreeSha;
    if (activeTarget == null ||
        activeToken == null ||
        activeToken.isEmpty ||
        rootTreeSha == null) {
      return;
    }

    final seq = ++_indexSeq;
    _indexCancel?.cancel();
    final cancel = _indexCancel = CancelToken();
    state = state.copyWith(isIndexing: true, clearSearchError: true);

    try {
      final snapshot = await api.fetchRecursiveTree(
        token: activeToken,
        owner: activeTarget.repo.ownerLogin,
        repo: activeTarget.repo.name,
        treeSha: rootTreeSha,
        cancelToken: cancel,
      );
      if (!mounted || seq != _indexSeq) return;

      _index = RepoSearchIndex.fromBlobs(snapshot.blobs);
      _indexPartial = snapshot.truncated;
      state = state.copyWith(
        isIndexing: false,
        searchPartial: _indexPartial,
        searchResult: _index!.search(state.searchQuery),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      _failIndex(seq, 'تعذر الاتصال بخوادم GitHub.');
    } on GitHubException catch (e) {
      _failIndex(seq, e.message);
    } catch (_) {
      _failIndex(seq, 'تعذر بناء فهرس البحث.');
    }
  }

  void _failIndex(int seq, String message) {
    if (!mounted || seq != _indexSeq) return;
    state = state.copyWith(isIndexing: false, searchError: message);
  }

  /// Retries building the search index after a failure.
  Future<void> retryIndex() => _ensureIndex();

  // ---------------------------------------------------------------------------
  // Content search (GitHub Search API, rate limited)
  // ---------------------------------------------------------------------------

  /// Switches the search screen between matching file NAMES (local index) and
  /// searching file CONTENT through the Search API.
  void setCodeSearchMode(bool enabled) {
    if (state.codeSearchMode == enabled) return;
    _codeSearchSeq++;
    state = state.copyWith(
      codeSearchMode: enabled,
      isCodeSearching: false,
      codeSearchResult: RepoCodeSearchResult.empty,
      clearCodeSearchError: true,
    );
  }

  /// Searches the CONTENT of repository files for [query]. Refused locally
  /// (with the seconds to wait) while the client-side quota is exhausted —
  /// GitHub counts a rejected request against the limit too.
  Future<void> runCodeSearch(String query) async {
    final activeTarget = target;
    final activeToken = token;
    final term = query.trim();
    if (term.isEmpty) return;
    if (state.isCodeSearching) return;

    void fail(String message) {
      if (!mounted) return;
      state = state.copyWith(isCodeSearching: false, codeSearchError: message);
    }

    if (activeTarget == null || activeToken == null || activeToken.isEmpty) {
      fail('لا توجد جلسة نشطة أو مستودع محدد.');
      return;
    }

    final wait = _codeSearchLimiter.waitTime();
    if (wait != null) {
      fail(
        'تجاوزت حدّ البحث في المحتوى '
        '(${_codeSearchLimiter.maxRequests} مرات في الدقيقة). '
        'انتظر ${wait.inSeconds} ثانية ثم أعد المحاولة.',
      );
      return;
    }
    _codeSearchLimiter.record();

    final seq = ++_codeSearchSeq;
    _codeSearchCancel?.cancel();
    final cancel = _codeSearchCancel = CancelToken();
    if (mounted) {
      state = state.copyWith(isCodeSearching: true, clearCodeSearchError: true);
    }

    try {
      final result = await api.searchCode(
        token: activeToken,
        owner: activeTarget.repo.ownerLogin,
        repo: activeTarget.repo.name,
        query: term,
        cancelToken: cancel,
      );
      if (!mounted || seq != _codeSearchSeq) return;
      state = state.copyWith(
        isCodeSearching: false,
        codeSearchResult: result,
        clearCodeSearchError: true,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      if (!mounted || seq != _codeSearchSeq) return;
      fail('تعذر الاتصال بخوادم GitHub.');
    } on GitHubException catch (e) {
      if (!mounted || seq != _codeSearchSeq) return;
      fail(e.message);
    } catch (_) {
      if (!mounted || seq != _codeSearchSeq) return;
      fail('تعذر تنفيذ البحث في المحتوى.');
    }
  }
}
