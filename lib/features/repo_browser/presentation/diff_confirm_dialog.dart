import 'package:flutter/material.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../repos/domain/deploy_target.dart';
import '../domain/line_diff.dart';
import '../domain/repo_file_content.dart';

/// يعرض مقارنة (Diff) مفصلة للتغييرات قبل تنفيذ الـ Commit.
/// يُرجع رسالة الـ Commit المعتمدة، أو `null` عند الإلغاء.
Future<String?> showDiffConfirmDialog(
  BuildContext context, {
  required DeployTarget target,
  required RepoFileRef file,
  required TextDiffResult diff,
  required LineEnding lineEnding,
  required bool hasBom,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.86),
    builder: (_) => _DiffConfirmDialog(
      target: target,
      file: file,
      diff: diff,
      lineEnding: lineEnding,
      hasBom: hasBom,
    ),
  );
}

class _DiffConfirmDialog extends StatefulWidget {
  final DeployTarget target;
  final RepoFileRef file;
  final TextDiffResult diff;
  final LineEnding lineEnding;
  final bool hasBom;

  const _DiffConfirmDialog({
    required this.target,
    required this.file,
    required this.diff,
    required this.lineEnding,
    required this.hasBom,
  });

  @override
  State<_DiffConfirmDialog> createState() => _DiffConfirmDialogState();
}

class _DiffConfirmDialogState extends State<_DiffConfirmDialog> {
  late final TextEditingController _message =
      TextEditingController(text: 'Nexus: update ${widget.file.path}');

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
    final diff = widget.diff;
    final flatItems = <_DiffDisplayItem>[];
    for (final hunk in diff.hunks) {
      flatItems.add(_DiffDisplayItem.hunkHeader(hunk.header));
      for (final line in hunk.lines) {
        flatItems.add(_DiffDisplayItem.line(line));
      }
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: GlassPanel(
          strong: true,
          borderRadius: 22,
          borderColor: NexusColors.primary.withOpacity(0.45),
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: NexusColors.primary.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: NexusColors.primary.withOpacity(0.38),
                      ),
                    ),
                    child: const Icon(
                      Icons.difference_outlined,
                      color: NexusColors.primarySoft,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'مراجعة التغييرات (Diff)',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: NexusColors.textPrimary,
                          ),
                        ),
                        Text(
                          '${widget.target.displayTarget} · ${widget.file.path}',
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
                ],
              ),
              const SizedBox(height: 12),

              // شارات الإحصائيات والخصائص المحفوظة
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Badge(
                    label: '+${diff.addedCount}',
                    color: NexusColors.successSoft,
                  ),
                  _Badge(
                    label: '-${diff.removedCount}',
                    color: NexusColors.roseSoft,
                  ),
                  if (widget.lineEnding != LineEnding.none)
                    _Badge(
                      label: widget.lineEnding.label,
                      color: NexusColors.primarySoft,
                    ),
                  if (widget.hasBom)
                    const _Badge(
                      label: 'UTF-8 BOM',
                      color: NexusColors.warningSoft,
                    ),
                  if (widget.file.isExecutable)
                    const _Badge(
                      label: '100755 +x',
                      color: NexusColors.warningSoft,
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // عارض الفروقات باتجاه LTR دائم
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 140),
                  decoration: BoxDecoration(
                    color: NexusColors.bgDeep.withOpacity(0.88),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: NexusColors.borderSubtle),
                  ),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: flatItems.length,
                      itemBuilder: (_, index) {
                        final item = flatItems[index];
                        if (item.header != null) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            color: NexusColors.primary.withOpacity(0.14),
                            child: Text(
                              item.header!,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: NexusColors.primarySoft,
                              ),
                            ),
                          );
                        }
                        final line = item.diffLine!;
                        final (bg, fg, prefix) = switch (line.kind) {
                          DiffLineKind.added => (
                              NexusColors.success.withOpacity(0.16),
                              NexusColors.successSoft,
                              '+',
                            ),
                          DiffLineKind.removed => (
                              NexusColors.rose.withOpacity(0.16),
                              NexusColors.roseSoft,
                              '-',
                            ),
                          DiffLineKind.context => (
                              Colors.transparent,
                              NexusColors.textSecondary,
                              ' ',
                            ),
                        };
                        final oldStr = line.oldLine?.toString() ?? '';
                        final newStr = line.newLine?.toString() ?? '';
                        return Container(
                          color: bg,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 32,
                                  child: Text(
                                    oldStr,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 10.5,
                                      color: NexusColors.textSubtle,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 32,
                                  child: Text(
                                    newStr,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 10.5,
                                      color: NexusColors.textSubtle,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$prefix ${line.text}',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11.8,
                                    color: fg,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              const Text(
                'رسالة الـ Commit',
                style: TextStyle(fontSize: 12, color: NexusColors.textMuted),
              ),
              const SizedBox(height: 6),
              TextField(
                key: const ValueKey('diff_commit_message'),
                controller: _message,
                minLines: 1,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontSize: 13,
                  color: NexusColors.textPrimary,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('diff_cancel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: NexusColors.textSecondary,
                        side: const BorderSide(color: NexusColors.borderSubtle),
                        padding: const EdgeInsets.symmetric(vertical: 13),
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
                      key: const ValueKey('diff_confirm'),
                      height: 46,
                      borderRadius: 13,
                      gradient: NexusColors.successGradient,
                      onPressed:
                          _message.text.trim().isEmpty ? null : _confirm,
                      child: const Text('حفظ و Commit'),
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

class _DiffDisplayItem {
  final String? header;
  final DiffLine? diffLine;

  const _DiffDisplayItem.hunkHeader(this.header) : diffLine = null;
  const _DiffDisplayItem.line(this.diffLine) : header = null;
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
