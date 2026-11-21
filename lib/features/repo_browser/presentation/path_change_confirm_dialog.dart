import 'package:flutter/material.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../repos/domain/deploy_target.dart';
import '../domain/arabic_count.dart';
import '../domain/repo_path_change_preview.dart';

/// تؤكد النقل أو إعادة تسمية المجلد وتُرجع رسالة الـ Commit المعتمدة، أو `null`.
Future<String?> showPathChangeConfirmDialog(
  BuildContext context, {
  required DeployTarget target,
  required RepoPathChangePreview preview,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.84),
    builder: (_) =>
        _PathChangeConfirmDialog(target: target, preview: preview),
  );
}

class _PathChangeConfirmDialog extends StatefulWidget {
  final DeployTarget target;
  final RepoPathChangePreview preview;

  const _PathChangeConfirmDialog({
    required this.target,
    required this.preview,
  });

  @override
  State<_PathChangeConfirmDialog> createState() =>
      _PathChangeConfirmDialogState();
}

class _PathChangeConfirmDialogState extends State<_PathChangeConfirmDialog> {
  late final TextEditingController _message =
      TextEditingController(text: widget.preview.defaultMessage);

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final isRename = preview.kind == RepoPathChangeKind.rename;
    final samples = preview.visibleSamples();
    final hidden = preview.hiddenCount();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassPanel(
          strong: true,
          borderRadius: 22,
          borderColor: NexusColors.primary.withOpacity(0.42),
          padding: const EdgeInsets.all(22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: NexusColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: NexusColors.primary.withOpacity(0.38),
                        ),
                      ),
                      child: Icon(
                        isRename
                            ? Icons.drive_file_rename_outline_rounded
                            : Icons.drive_file_move_outline,
                        color: NexusColors.primarySoft,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isRename ? 'تأكيد إعادة التسمية' : 'تأكيد النقل',
                            style: const TextStyle(
                              fontSize: 17.5,
                              fontWeight: FontWeight.w700,
                              color: NexusColors.textPrimary,
                            ),
                          ),
                          Text(
                            widget.target.displayTarget,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                              color: NexusColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _CounterBox(
                        label: 'عناصر محددة',
                        count: '${preview.itemCount}',
                        color: NexusColors.primarySoft,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CounterBox(
                        label: 'ملفات متأثرة',
                        count: '${preview.totalFileCount}',
                        color: NexusColors.successSoft,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: NexusColors.bgDeep.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: NexusColors.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final sample in samples)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              sample.isFolder
                                  ? '${sample.fromPath}/ → ${sample.toPath}/ (${sample.fileCount})'
                                  : '${sample.fromPath} → ${sample.toPath}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.2,
                                color: NexusColors.primarySoft,
                              ),
                            ),
                          ),
                        ),
                      if (hidden > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'و${arabicItems(hidden)} أخرى...',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: NexusColors.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'رسالة الـ Commit',
                  style: TextStyle(fontSize: 12, color: NexusColors.textMuted),
                ),
                const SizedBox(height: 6),
                TextField(
                  key: const ValueKey('path_change_commit_message'),
                  controller: _message,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: NexusColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'لا يُعاد رفع محتوى الملفات؛ تُحدَّث المسارات في Commit واحد قابل للتراجع.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: NexusColors.textMuted,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('path_change_cancel'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: NexusColors.textSecondary,
                          side: const BorderSide(
                            color: NexusColors.borderSubtle,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: NexusGradientButton(
                        key: const ValueKey('path_change_confirm'),
                        height: 48,
                        borderRadius: 13,
                        onPressed:
                            _message.text.trim().isEmpty ? null : _confirm,
                        child: Text(isRename ? 'نعم، أعد التسمية' : 'نعم، انقل'),
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

class _CounterBox extends StatelessWidget {
  final String label;
  final String count;
  final Color color;

  const _CounterBox({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.32)),
      ),
      child: Column(
        children: [
          Text(
            count,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: NexusColors.textMuted),
          ),
        ],
      ),
    );
  }
}
