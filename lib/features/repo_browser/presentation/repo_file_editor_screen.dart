import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/nexus_toast.dart';
import '../domain/editor_history.dart';
import '../domain/file_op.dart';
import '../domain/line_diff.dart';
import '../domain/repo_edit_conflict.dart';
import '../domain/repo_file_content.dart';
import '../domain/repo_op_result.dart';
import '../domain/repo_text_codec.dart';
import 'diff_confirm_dialog.dart';
import 'edit_conflict_dialog.dart';
import 'protected_branch_pr_dialog.dart';
import 'repo_browser_controller.dart';
import 'widgets/editor_find_replace_bar.dart';
import 'widgets/repo_selection_bar.dart';

/// يفتح محرر النصوص للملف ويُرجع الـ [RepoFileRef] المحدّث عند نجاح الحفظ،
/// أو `null` إذا أُغلق المحرر دون حفظ.
Future<RepoFileRef?> openRepoFileEditor(
  BuildContext context, {
  required RepoFileContent content,
  required String openedHeadSha,
}) {
  return Navigator.of(context).push<RepoFileRef?>(
    MaterialPageRoute<RepoFileRef?>(
      builder: (_) => RepoFileEditorScreen(
        content: content,
        openedHeadSha: openedHeadSha,
      ),
    ),
  );
}

class RepoFileEditorScreen extends ConsumerStatefulWidget {
  final RepoFileContent content;
  final String openedHeadSha;

  const RepoFileEditorScreen({
    super.key,
    required this.content,
    required this.openedHeadSha,
  });

  @override
  ConsumerState<RepoFileEditorScreen> createState() =>
      _RepoFileEditorScreenState();
}

class _RepoFileEditorScreenState extends ConsumerState<RepoFileEditorScreen> {
  static const TextStyle _codeStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    height: 1.5,
    color: NexusColors.textPrimary,
  );
  static const StrutStyle _codeStrut = StrutStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    height: 1.5,
    forceStrutHeight: true,
  );

  late final String _originalText;
  late String _baseHeadSha;
  late final TextEditingController _textController;
  late final EditorHistory _history;
  final FocusNode _editorFocus = FocusNode();

  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();

  bool _applyingHistory = false;
  bool _isSaving = false;
  String? _busyMessage;

  bool _findBarOpen = false;
  bool _showReplace = false;
  bool _caseSensitive = false;
  bool _useRegex = false;
  String? _regexError;
  List<TextMatchRange> _matches = const [];
  int _activeMatchIndex = -1;

  int _lineCount = 1;
  int _maxLineChars = 1;

  bool get _hasChanges => _textController.text != _originalText;

  @override
  void initState() {
    super.initState();
    _originalText = RepoTextCodec.normalizeForEditor(widget.content.text ?? '');
    _baseHeadSha = widget.openedHeadSha;
    _textController = TextEditingController(text: _originalText);
    _history = EditorHistory(
      initial: TextSnapshot(
        text: _originalText,
        selection: const TextSelection.collapsed(offset: 0),
      ),
    );
    _recomputeMetrics(_originalText);
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _findController.dispose();
    _replaceController.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  void _recomputeMetrics(String text) {
    var lines = 1;
    var maxChars = 1;
    var currentChars = 0;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        if (currentChars > maxChars) maxChars = currentChars;
        currentChars = 0;
        lines++;
      } else {
        currentChars++;
      }
    }
    if (currentChars > maxChars) maxChars = currentChars;
    _lineCount = lines;
    _maxLineChars = maxChars;
  }

  void _onTextChanged() {
    final text = _textController.text;
    _recomputeMetrics(text);

    if (!_applyingHistory) {
      _history.push(
        TextSnapshot(text: text, selection: _textController.selection),
      );
    }
    if (_findBarOpen && _findController.text.isNotEmpty) {
      _refreshMatches(keepIndex: true);
    } else {
      setState(() {});
    }
  }

  void _applySnapshot(TextSnapshot snapshot) {
    _applyingHistory = true;
    _textController.value = TextEditingValue(
      text: snapshot.text,
      selection: _clampSelection(snapshot.selection, snapshot.text.length),
    );
    _applyingHistory = false;
    _recomputeMetrics(snapshot.text);
    if (_findBarOpen && _findController.text.isNotEmpty) {
      _refreshMatches(keepIndex: true);
    } else {
      setState(() {});
    }
  }

  TextSelection _clampSelection(TextSelection sel, int length) {
    if (!sel.isValid) return TextSelection.collapsed(offset: length);
    return TextSelection(
      baseOffset: sel.baseOffset.clamp(0, length),
      extentOffset: sel.extentOffset.clamp(0, length),
    );
  }

  void _undo() {
    final prev = _history.undo();
    if (prev != null) _applySnapshot(prev);
  }

  void _redo() {
    final next = _history.redo();
    if (next != null) _applySnapshot(next);
  }

  // ---------------------------------------------------------------------------
  // البحث والاستبدال
  // ---------------------------------------------------------------------------

  void _toggleFindBar() {
    setState(() {
      _findBarOpen = !_findBarOpen;
      if (!_findBarOpen) {
        _matches = const [];
        _activeMatchIndex = -1;
        _regexError = null;
      } else if (_findController.text.isNotEmpty) {
        _refreshMatches(keepIndex: false);
      }
    });
  }

  void _refreshMatches({required bool keepIndex}) {
    final query = _findController.text;
    final regexErr = _useRegex ? EditorTextSearch.validateRegex(query) : null;
    if (regexErr != null) {
      setState(() {
        _regexError = regexErr;
        _matches = const [];
        _activeMatchIndex = -1;
      });
      return;
    }

    final found = EditorTextSearch.findAll(
      _textController.text,
      query,
      caseSensitive: _caseSensitive,
      useRegex: _useRegex,
    );

    int nextIndex;
    if (found.isEmpty) {
      nextIndex = -1;
    } else if (keepIndex && _activeMatchIndex >= 0) {
      nextIndex = _activeMatchIndex.clamp(0, found.length - 1);
    } else {
      nextIndex = 0;
    }

    setState(() {
      _regexError = null;
      _matches = found;
      _activeMatchIndex = nextIndex;
    });
  }

  void _selectActiveMatch() {
    if (_activeMatchIndex < 0 || _activeMatchIndex >= _matches.length) return;
    final match = _matches[_activeMatchIndex];
    _editorFocus.requestFocus();
    _textController.selection = TextSelection(
      baseOffset: match.start,
      extentOffset: match.end,
    );
  }

  void _findNext() {
    if (_matches.isEmpty) return;
    setState(() {
      _activeMatchIndex = (_activeMatchIndex + 1) % _matches.length;
    });
    _selectActiveMatch();
  }

  void _findPrevious() {
    if (_matches.isEmpty) return;
    setState(() {
      _activeMatchIndex =
          (_activeMatchIndex - 1 + _matches.length) % _matches.length;
    });
    _selectActiveMatch();
  }

  void _replaceCurrent() {
    if (_activeMatchIndex < 0 || _activeMatchIndex >= _matches.length) return;
    final currentMatch = _matches[_activeMatchIndex];
    final replaced = EditorTextSearch.replaceOne(
      _textController.text,
      currentMatch,
      _replaceController.text,
    );
    final nextSelection = TextSelection.collapsed(offset: replaced.nextCursor);

    _history.push(
      TextSnapshot(text: replaced.text, selection: nextSelection),
      forceNewEntry: true,
    );
    _applySnapshot(TextSnapshot(text: replaced.text, selection: nextSelection));
    if (_matches.isNotEmpty) _selectActiveMatch();
  }

  void _replaceAll() {
    if (_matches.isEmpty) return;
    final replaced = EditorTextSearch.replaceAll(
      _textController.text,
      _matches,
      _replaceController.text,
    );
    final nextSelection = const TextSelection.collapsed(offset: 0);
    _history.push(
      TextSnapshot(text: replaced.text, selection: nextSelection),
      forceNewEntry: true,
    );
    _applySnapshot(TextSnapshot(text: replaced.text, selection: nextSelection));
    showNexusToast(
      context,
      'تم استبدال ${replaced.replacedCount} موضع.',
      type: NexusToastType.info,
    );
  }

  // ---------------------------------------------------------------------------
  // الخروج مع حماية التغييرات غير المحفوظة
  // ---------------------------------------------------------------------------

  Future<void> _confirmAndPop() async {
    if (_isSaving) return;
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.84),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: GlassPanel(
            strong: true,
            borderRadius: 20,
            borderColor: NexusColors.warning.withOpacity(0.42),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'تجاهل التعديلات غير المحفوظة؟',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: NexusColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'لديك تعديلات لم تُحفظ بعد. إذا خرجت الآن ستُفقد هذه التعديلات.',
                  style: TextStyle(
                    fontSize: 13,
                    color: NexusColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('متابعة التحرير'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NexusColors.rose,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('تجاهل والخروج'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (discard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  // ---------------------------------------------------------------------------
  // تدفق الحفظ: ترميز -> كشف تعارض -> Diff -> Commit ذري
  // ---------------------------------------------------------------------------

  Future<void> _onSavePressed() async {
    if (_isSaving || !_hasChanges) return;

    final browserState = ref.read(repoBrowserControllerProvider);
    final target = browserState.target;
    if (target == null) return;

    final encodedBytes = RepoTextCodec.encodeForCommit(
      _textController.text,
      originalLineEnding: widget.content.lineEnding,
      hasBom: widget.content.hasBom,
    );
    final sizeError = RepoEditGuard.validateEncodedSize(encodedBytes);
    if (sizeError != null) {
      showNexusToast(context, sizeError, type: NexusToastType.error);
      return;
    }

    final controller = ref.read(repoBrowserControllerProvider.notifier);

    // 1. فحص تعارض رأس الفرع قبل فتح نافذة الـ Diff
    setState(() {
      _isSaving = true;
      _busyMessage = 'جارٍ التحقق من حالة الفرع...';
    });

    final conflictCheck = await controller.checkEditConflict(
      openedFile: widget.content.file,
      openedHeadSha: _baseHeadSha,
    );

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _busyMessage = null;
    });

    if (!conflictCheck.isSuccess) {
      showNexusToast(
        context,
        conflictCheck.message ?? 'تعذر التحقق من حالة الفرع.',
        type: NexusToastType.error,
      );
      return;
    }

    final conflict = conflictCheck.value;
    if (conflict != null) {
      final proceed = await _handleConflict(conflict);
      if (!proceed || !mounted) return;
    }

    // 2. حساب الفروقات وعرض نافذة Diff
    final diff = LineDiff.compute(_originalText, _textController.text);
    if (diff.isEmpty) {
      showNexusToast(
        context,
        'لا توجد تغييرات لحفظها.',
        type: NexusToastType.info,
      );
      return;
    }

    final commitMessage = await showDiffConfirmDialog(
      context,
      target: target,
      file: widget.content.file,
      diff: diff,
      lineEnding: widget.content.lineEnding,
      hasBom: widget.content.hasBom,
    );
    if (!mounted || commitMessage == null) return;

    // 3. تنفيذ الـ Commit الذري
    setState(() {
      _isSaving = true;
      _busyMessage = 'جارٍ حفظ التغييرات في Commit واحد...';
    });

    final saveResult = await controller.saveFileEdit(
      openedFile: widget.content.file,
      bytes: encodedBytes,
      message: commitMessage,
      expectedHeadSha: _baseHeadSha,
    );

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _busyMessage = null;
    });

    if (saveResult.isSuccess) {
      showNexusToast(
        context,
        'تم حفظ ${widget.content.file.name} في Commit واحد بنجاح.',
        type: NexusToastType.success,
      );
      Navigator.of(context).pop(saveResult.value!.updatedFile);
      return;
    }

    // إذا وقع تعارض في اللحظة الفاصلة بين الفحص وتحديث المرجع (force: false)
    if (saveResult.failure == RepoOpFailure.branchChanged) {
      final recheck = await controller.checkEditConflict(
        openedFile: widget.content.file,
        openedHeadSha: _baseHeadSha,
      );
      if (!mounted) return;
      if (recheck.isSuccess && recheck.value != null) {
        await _handleConflict(recheck.value!);
        return;
      }
    }

    // الفرع محمي: نعرض إنشاء فرع جديد وتطبيق نفس التعديل عليه ثم فتح PR.
    if (saveResult.failure == RepoOpFailure.protectedBranch) {
      final ops = controller.takeRejectedWriteOps();
      if (ops != null && ops.isNotEmpty && mounted) {
        await _saveOnNewBranchAndOpenPullRequest(
          ops: ops,
          commitMessage: commitMessage,
        );
      }
      return;
    }

    showNexusToast(
      context,
      saveResult.message ?? 'تعذر حفظ التعديلات.',
      type: NexusToastType.error,
    );
  }

  Future<void> _saveOnNewBranchAndOpenPullRequest({
    required List<FileOp> ops,
    required String commitMessage,
  }) async {
    final target = ref.read(repoBrowserControllerProvider).target;
    if (target == null) return;

    final input = await showProtectedBranchPrDialog(
      context,
      protectedBranch: target.branchName,
      suggestedCommitMessage: commitMessage,
    );
    if (!mounted || input == null) return;

    setState(() {
      _isSaving = true;
      _busyMessage = 'جارٍ إنشاء الفرع الجديد وتطبيق التعديل...';
    });

    final prResult = await ref
        .read(repoBrowserControllerProvider.notifier)
        .commitOnNewBranchAndOpenPullRequest(
          ops: ops,
          message: commitMessage,
          newBranchName: input.newBranchName,
          prTitle: input.prTitle,
          prBody: input.prBody,
        );

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _busyMessage = null;
    });

    if (prResult.isSuccess) {
      // الفرع الحالي لم يتغير، لذا يبقى العارض على النسخة الحالية.
      showNexusToast(
        context,
        'حُفظ التعديل على الفرع "${prResult.value!.headBranch}" وتم فتح الـ PR.',
        type: NexusToastType.success,
      );
      await showPullRequestCreatedDialog(context, prResult.value!);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    showNexusToast(
      context,
      prResult.message ?? 'تعذّر تنفيذ الحفظ عبر فرع جديد.',
      type: NexusToastType.error,
    );
  }

  /// يعرض تحذير التعارض ويعيد `true` فقط إذا وافق المستخدم صراحةً على المتابعة على الرأس الأحدث.
  Future<bool> _handleConflict(RepoEditConflictInfo conflict) async {
    final action = await showEditConflictDialog(
      context,
      filePath: widget.content.file.path,
      conflict: conflict,
    );
    if (!mounted) return false;

    switch (action) {
      case EditConflictAction.copyEdits:
        await Clipboard.setData(ClipboardData(text: _textController.text));
        if (mounted) {
          showNexusToast(
            context,
            'تم نسخ تعديلاتك إلى الحافظة.',
            type: NexusToastType.success,
          );
        }
        return false;

      case EditConflictAction.reloadLatest:
        await ref.read(repoBrowserControllerProvider.notifier).refresh();
        if (mounted) {
          Navigator.of(context).pop(conflict.latestFileRef);
        }
        return false;

      case EditConflictAction.continueOnLatestHead:
        setState(() {
          _baseHeadSha = conflict.latestHeadSha;
        });
        return true;

      case EditConflictAction.cancel:
        return false;
    }
  }

  // ---------------------------------------------------------------------------
  // البناء
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final file = widget.content.file;
    final gutterDigits = math.max(2, _lineCount.toString().length);
    final gutterWidth = (gutterDigits * 9.0) + 20.0;

    return PopScope(
      canPop: !_hasChanges && !_isSaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmAndPop();
      },
      child: Scaffold(
        body: NexusAmbientBackground(
          child: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  children: [
                    _buildHeader(file),
                    if (_findBarOpen)
                      EditorFindReplaceBar(
                        findController: _findController,
                        replaceController: _replaceController,
                        showReplace: _showReplace,
                        caseSensitive: _caseSensitive,
                        useRegex: _useRegex,
                        regexError: _regexError,
                        matchCount: _matches.length,
                        activeMatchIndex: _activeMatchIndex,
                        onToggleReplace: () =>
                            setState(() => _showReplace = !_showReplace),
                        onToggleCaseSensitive: () {
                          _caseSensitive = !_caseSensitive;
                          _refreshMatches(keepIndex: false);
                        },
                        onToggleRegex: () {
                          _useRegex = !_useRegex;
                          _refreshMatches(keepIndex: false);
                        },
                        onFindPrevious: _findPrevious,
                        onFindNext: _findNext,
                        onReplaceCurrent: _replaceCurrent,
                        onReplaceAll: _replaceAll,
                        onClose: _toggleFindBar,
                        onQueryChanged: (_) =>
                            _refreshMatches(keepIndex: false),
                      ),
                    Expanded(
                      child: _buildCodeArea(gutterWidth),
                    ),
                    _buildStatusFooter(file),
                  ],
                ),
                if (_isSaving)
                  RepoBusyOverlay(label: _busyMessage ?? 'جارٍ الحفظ...'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(RepoFileRef file) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
      decoration: BoxDecoration(
        color: NexusColors.bgDeep.withOpacity(0.75),
        border: const Border(
          bottom: BorderSide(color: NexusColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'رجوع',
            onPressed: _confirmAndPop,
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: NexusColors.textSecondary,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                          color: NexusColors.textPrimary,
                        ),
                      ),
                    ),
                    if (_hasChanges) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: NexusColors.warningSoft,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  file.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                    color: NexusColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('editor_undo'),
            tooltip: 'تراجع',
            visualDensity: VisualDensity.compact,
            onPressed: _history.canUndo ? _undo : null,
            icon: Icon(
              Icons.undo_rounded,
              size: 20,
              color: _history.canUndo
                  ? NexusColors.textPrimary
                  : NexusColors.textSubtle,
            ),
          ),
          IconButton(
            key: const ValueKey('editor_redo'),
            tooltip: 'إعادة',
            visualDensity: VisualDensity.compact,
            onPressed: _history.canRedo ? _redo : null,
            icon: Icon(
              Icons.redo_rounded,
              size: 20,
              color: _history.canRedo
                  ? NexusColors.textPrimary
                  : NexusColors.textSubtle,
            ),
          ),
          IconButton(
            key: const ValueKey('editor_find_toggle'),
            tooltip: 'بحث واستبدال',
            visualDensity: VisualDensity.compact,
            onPressed: _toggleFindBar,
            icon: Icon(
              Icons.find_replace_rounded,
              size: 20,
              color: _findBarOpen
                  ? NexusColors.primarySoft
                  : NexusColors.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
          FilledButton(
            key: const ValueKey('editor_save'),
            style: FilledButton.styleFrom(
              backgroundColor: _hasChanges
                  ? NexusColors.success
                  : NexusColors.bgElevated,
              foregroundColor:
                  _hasChanges ? Colors.white : NexusColors.textSubtle,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: (_hasChanges && !_isSaving) ? _onSavePressed : null,
            child: const Text(
              'حفظ',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  /// منطقة التحرير باتجاه LTR دائم مع عمود أرقام أسطر متزامن عمودياً وتمرير أفقي للكود.
  Widget _buildCodeArea(double gutterWidth) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: NexusColors.bgDeep.withOpacity(0.72),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportEditorWidth =
                math.max(200.0, constraints.maxWidth - gutterWidth);
            final estimatedCodeWidth = (_maxLineChars * 8.4) + 96.0;
            final editorWidth =
                math.max(viewportEditorWidth, estimatedCodeWidth);

            final lineNumbersText =
                List<String>.generate(_lineCount, (i) => '${i + 1}').join('\n');

            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 48),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // عمود أرقام الأسطر
                    Container(
                      width: gutterWidth,
                      padding: const EdgeInsets.fromLTRB(6, 12, 10, 12),
                      decoration: BoxDecoration(
                        color: NexusColors.bgSurface.withOpacity(0.55),
                        border: const Border(
                          right: BorderSide(color: NexusColors.borderSubtle),
                        ),
                      ),
                      child: Text(
                        lineNumbersText,
                        textAlign: TextAlign.right,
                        style: _codeStyle.copyWith(
                          color: NexusColors.textSubtle,
                        ),
                        strutStyle: _codeStrut,
                      ),
                    ),

                    // حقل الكود (تمرير أفقي بدون التفاف لضمان محاذاة أرقام الأسطر 1:1)
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: editorWidth,
                          child: TextField(
                            key: const ValueKey('code_editor_field'),
                            controller: _textController,
                            focusNode: _editorFocus,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            autocorrect: false,
                            enableSuggestions: false,
                            textDirection: TextDirection.ltr,
                            style: _codeStyle,
                            strutStyle: _codeStrut,
                            scrollPhysics: const NeverScrollableScrollPhysics(),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.fromLTRB(
                                12,
                                12,
                                16,
                                12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusFooter(RepoFileRef file) {
    final le = widget.content.lineEnding == LineEnding.none
        ? 'LF'
        : widget.content.lineEnding.label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: NexusColors.bgSurface.withOpacity(0.9),
        border: const Border(
          top: BorderSide(color: NexusColors.borderSubtle),
        ),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            Text(
              '$_lineCount lines',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: NexusColors.textMuted,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              le,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: NexusColors.primarySoft,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.content.hasBom) ...[
              const SizedBox(width: 10),
              const Text(
                'UTF-8 BOM',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: NexusColors.warningSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (file.isExecutable) ...[
              const SizedBox(width: 10),
              const Text(
                '100755',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: NexusColors.successSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const Spacer(),
            Text(
              'BASE ${_baseHeadSha.length > 7 ? _baseHeadSha.substring(0, 7) : _baseHeadSha}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                color: NexusColors.textSubtle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
