import 'package:flutter/material.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../domain/repo_edit_conflict.dart';

enum EditConflictAction {
  /// البقاء في المحرر دون حفظ.
  cancel,

  /// نسخ التعديلات المحلية إلى الحافظة والبقاء في المحرر.
  copyEdits,

  /// تجاهل التعديلات المحلية وإغلاق المحرر لإعادة تحميل النسخة الأحدث.
  reloadLatest,

  /// تحديث الأساس إلى أحدث HEAD وإعادة محاولة الحفظ (بدون force push).
  continueOnLatestHead,
}

Future<EditConflictAction> showEditConflictDialog(
  BuildContext context, {
  required String filePath,
  required RepoEditConflictInfo conflict,
}) async {
  final choice = await showDialog<EditConflictAction>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.86),
    builder: (_) => _EditConflictDialog(
      filePath: filePath,
      conflict: conflict,
    ),
  );
  return choice ?? EditConflictAction.cancel;
}

class _EditConflictDialog extends StatelessWidget {
  final String filePath;
  final RepoEditConflictInfo conflict;

  const _EditConflictDialog({
    required this.filePath,
    required this.conflict,
  });

  @override
  Widget build(BuildContext context) {
    final severe = conflict.sameFileChanged;
    final accent = severe ? NexusColors.roseSoft : NexusColors.warningSoft;
    final border = severe
        ? NexusColors.rose.withOpacity(0.45)
        : NexusColors.warning.withOpacity(0.45);

    final String bodyText;
    if (conflict.fileDeletedRemotely) {
      bodyText =
          'تغيّر رأس الفرع على GitHub (${conflict.shortOpenedHead} → ${conflict.shortLatestHead}) '
          'وحُذف هذا الملف من الفرع عن بُعد. انسخ تعديلاتك قبل إغلاق المحرر حتى لا تفقدها.';
    } else if (conflict.sameFileChanged) {
      bodyText =
          'تغيّر رأس الفرع على GitHub (${conflict.shortOpenedHead} → ${conflict.shortLatestHead}) '
          'وتم تعديل هذا الملف نفسه في Commit أحدث. نوصي بنسخ تعديلاتك أو إعادة تحميل النسخة الأحدث '
          'كي لا تستبدل التعديلات الأحدث عن غير قصد.';
    } else {
      bodyText =
          'تغيّر رأس الفرع على GitHub (${conflict.shortOpenedHead} → ${conflict.shortLatestHead}) '
          'بسبب تعديلات على ملفات أخرى، بينما لم يتغير "$filePath". يمكنك المتابعة على الرأس الأحدث بأمان.';
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassPanel(
          strong: true,
          borderRadius: 22,
          borderColor: border,
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accent.withOpacity(0.38)),
                    ),
                    child: Icon(
                      severe
                          ? Icons.sync_problem_rounded
                          : Icons.warning_amber_rounded,
                      color: accent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      severe
                          ? 'تعارض: الملف تغيّر على GitHub'
                          : 'تنبيه: الفرع تحرّك على GitHub',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                bodyText,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: NexusColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              if (!conflict.fileDeletedRemotely) ...[
                NexusGradientButton(
                  key: const ValueKey('conflict_continue_latest'),
                  height: 46,
                  borderRadius: 13,
                  gradient: severe
                      ? const LinearGradient(
                          colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
                        )
                      : NexusColors.primaryGradient,
                  onPressed: () => Navigator.of(context)
                      .pop(EditConflictAction.continueOnLatestHead),
                  child: Text(
                    severe
                        ? 'الحفظ فوق النسخة الأحدث (على الرأس الجديد)'
                        : 'المتابعة على الرأس الأحدث',
                  ),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                key: const ValueKey('conflict_copy_edits'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: NexusColors.primarySoft,
                  side: BorderSide(color: NexusColors.primary.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                onPressed: () =>
                    Navigator.of(context).pop(EditConflictAction.copyEdits),
                icon: const Icon(Icons.copy_rounded, size: 17),
                label: const Text('نسخ تعديلاتي للحافظة'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('conflict_reload'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: NexusColors.warningSoft,
                        side: BorderSide(
                          color: NexusColors.warning.withOpacity(0.4),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      onPressed: () => Navigator.of(context)
                          .pop(EditConflictAction.reloadLatest),
                      child: const Text('إعادة تحميل الأحدث'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('conflict_cancel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: NexusColors.textSecondary,
                        side: const BorderSide(color: NexusColors.borderSubtle),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      onPressed: () =>
                          Navigator.of(context).pop(EditConflictAction.cancel),
                      child: const Text('إلغاء'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
