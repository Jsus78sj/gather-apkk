import 'package:flutter/material.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../domain/repo_pull_request.dart';

class ProtectedBranchPrInput {
  final String newBranchName;
  final String prTitle;
  final String prBody;

  const ProtectedBranchPrInput({
    required this.newBranchName,
    required this.prTitle,
    required this.prBody,
  });
}

/// تظهر تلقائياً عند رفض الفرع المحمي للدفع المباشر، وتقترح إنشاء فرع جديد ثم Pull Request.
Future<ProtectedBranchPrInput?> showProtectedBranchPrDialog(
  BuildContext context, {
  required String protectedBranch,
  required String suggestedCommitMessage,
}) {
  return showDialog<ProtectedBranchPrInput>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.86),
    builder: (_) => _ProtectedBranchPrDialog(
      protectedBranch: protectedBranch,
      suggestedCommitMessage: suggestedCommitMessage,
    ),
  );
}

/// تظهر بعد إنشاء الفرع الجديد وفتح الـ Pull Request بنجاح، وتعرض رقمه ورابطه.
Future<void> showPullRequestCreatedDialog(
  BuildContext context,
  CreatedPullRequestResult pr,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.84),
    builder: (_) => AlertDialog(
      backgroundColor: NexusColors.bgSurface,
      title: Text('تم فتح الـ Pull Request #${pr.number}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${pr.headBranch} ← ${pr.baseBranch}',
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 10),
          SelectableText(
            pr.htmlUrl,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: NexusColors.primarySoft,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('حسناً'),
        ),
      ],
    ),
  );
}

class _ProtectedBranchPrDialog extends StatefulWidget {
  final String protectedBranch;
  final String suggestedCommitMessage;

  const _ProtectedBranchPrDialog({
    required this.protectedBranch,
    required this.suggestedCommitMessage,
  });

  @override
  State<_ProtectedBranchPrDialog> createState() =>
      _ProtectedBranchPrDialogState();
}

class _ProtectedBranchPrDialogState extends State<_ProtectedBranchPrDialog> {
  late final TextEditingController _branchController;
  late final TextEditingController _titleController;
  final TextEditingController _bodyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    _branchController = TextEditingController(text: 'nexus/patch-$stamp');
    _titleController = TextEditingController(
      text: widget.suggestedCommitMessage,
    );
  }

  @override
  void dispose() {
    _branchController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  bool get _isBranchValid {
    final b = _branchController.text.trim();
    if (b.isEmpty || b == widget.protectedBranch) return false;
    return !RegExp(r'[\s~^:?*\[\\]|\.\.').hasMatch(b) &&
        !b.startsWith('/') &&
        !b.endsWith('/');
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _isBranchValid && _titleController.text.trim().isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassPanel(
          strong: true,
          borderRadius: 22,
          borderColor: NexusColors.warning.withOpacity(0.45),
          padding: const EdgeInsets.all(22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      color: NexusColors.warningSoft,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'الفرع "${widget.protectedBranch}" محمي',
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: NexusColors.warningSoft,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'رفض GitHub الدفع المباشر بسبب قواعد حماية الفرع. '
                  'يمكنك إنشاء فرع جديد وتطبيق نفس التغييرات عليه ثم فتح Pull Request تلقائياً.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: NexusColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('pr_new_branch'),
                  controller: _branchController,
                  textDirection: TextDirection.ltr,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: NexusColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'اسم الفرع الجديد',
                    errorText: _isBranchValid ? null : 'اسم فرع Git غير صالح.',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('pr_title'),
                  controller: _titleController,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    fontSize: 13,
                    color: NexusColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'عنوان الـ Pull Request',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _bodyController,
                  minLines: 2,
                  maxLines: 4,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: NexusColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'وصف إضافي (اختياري)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: NexusGradientButton(
                        key: const ValueKey('pr_confirm'),
                        height: 46,
                        borderRadius: 13,
                        onPressed: canSubmit
                            ? () => Navigator.of(context).pop(
                                  ProtectedBranchPrInput(
                                    newBranchName:
                                        _branchController.text.trim(),
                                    prTitle: _titleController.text.trim(),
                                    prBody: _bodyController.text.trim(),
                                  ),
                                )
                            : null,
                        child: const Text('إنشاء فرع و PR'),
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
  }
}
