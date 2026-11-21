import 'package:flutter/material.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../domain/remote_tree_entry.dart';
import '../domain/repo_path_validator.dart';

class RenameDialogResult {
  final String newName;
  final String? commitMessage;

  const RenameDialogResult({required this.newName, this.commitMessage});
}

/// يطلب الاسم الجديد لعنصر واحد (ملف أو مجلد).
/// بالنسبة للملف المفرد يطلب رسالة الـ Commit مباشرة، أما للمجلد فيُكتفى بالاسم
/// لتُعرض بعدها نافذة التأكيد مع عدد الملفات المتأثرة داخله.
Future<RenameDialogResult?> showRenameDialog(
  BuildContext context, {
  required RemoteTreeEntry entry,
  required String currentFolderPath,
  required Set<String> siblingNames,
}) {
  return showDialog<RenameDialogResult>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.84),
    builder: (_) => _RenameDialog(
      entry: entry,
      currentFolderPath: currentFolderPath,
      siblingNames: siblingNames,
    ),
  );
}

class _RenameDialog extends StatefulWidget {
  final RemoteTreeEntry entry;
  final String currentFolderPath;
  final Set<String> siblingNames;

  const _RenameDialog({
    required this.entry,
    required this.currentFolderPath,
    required this.siblingNames,
  });

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _messageController;
  bool _messageEditedByUser = false;

  String get _oldPath => widget.currentFolderPath.isEmpty
      ? widget.entry.name
      : '${widget.currentFolderPath}/${widget.entry.name}';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.entry.name);
    // تحديد الاسم قبل الامتداد للملفات لتسهيل الكتابة السريعة.
    if (!widget.entry.isFolder) {
      final dot = widget.entry.name.lastIndexOf('.');
      if (dot > 0) {
        _nameController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: dot,
        );
      }
    }
    _messageController = TextEditingController(
      text: _defaultCommitMessage(widget.entry.name),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  String _fullPathFor(String name) => widget.currentFolderPath.isEmpty
      ? name
      : '${widget.currentFolderPath}/$name';

  String _defaultCommitMessage(String newName) =>
      'Nexus: rename $_oldPath to ${_fullPathFor(newName)}';

  String? _validateName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return 'أدخل الاسم الجديد.';
    if (name.contains('/') || name.contains('\\')) {
      return 'أدخل الاسم فقط بدون "/". لنقل العنصر استخدم زر النقل.';
    }
    if (name == widget.entry.name) {
      return 'الاسم الجديد مطابق للاسم الحالي.';
    }
    final err = RepoPathValidator.validate(_fullPathFor(name));
    if (err != null) return err;
    if (widget.siblingNames.contains(name)) {
      return 'يوجد عنصر آخر بنفس الاسم في هذا المجلد.';
    }
    return null;
  }

  void _onNameChanged(String value) {
    if (!_messageEditedByUser && !widget.entry.isFolder) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        _messageController.text = _defaultCommitMessage(trimmed);
      }
    }
    setState(() {});
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (_validateName(name) != null) return;
    if (!widget.entry.isFolder && _messageController.text.trim().isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      RenameDialogResult(
        newName: name,
        commitMessage:
            widget.entry.isFolder ? null : _messageController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _nameController.text.trim();
    final error = _validateName(name);
    final canSubmit = error == null &&
        (widget.entry.isFolder || _messageController.text.trim().isNotEmpty);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassPanel(
          strong: true,
          borderRadius: 22,
          borderColor: NexusColors.warning.withOpacity(0.42),
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
                        color: NexusColors.warning.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: NexusColors.warning.withOpacity(0.38),
                        ),
                      ),
                      child: const Icon(
                        Icons.drive_file_rename_outline_rounded,
                        color: NexusColors.warningSoft,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.entry.isFolder
                                ? 'إعادة تسمية مجلد'
                                : 'إعادة تسمية ملف',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: NexusColors.textPrimary,
                            ),
                          ),
                          Text(
                            _oldPath,
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
                const SizedBox(height: 16),
                const Text(
                  'الاسم الجديد',
                  style: TextStyle(fontSize: 12, color: NexusColors.textMuted),
                ),
                const SizedBox(height: 6),
                TextField(
                  key: const ValueKey('rename_name_field'),
                  controller: _nameController,
                  autofocus: true,
                  textDirection: TextDirection.ltr,
                  textInputAction: widget.entry.isFolder
                      ? TextInputAction.done
                      : TextInputAction.next,
                  onChanged: _onNameChanged,
                  onSubmitted: (_) {
                    if (widget.entry.isFolder && canSubmit) _submit();
                  },
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13.5,
                    color: NexusColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    errorText: name == widget.entry.name ? null : error,
                  ),
                ),
                if (!widget.entry.isFolder) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'رسالة الـ Commit',
                    style:
                        TextStyle(fontSize: 12, color: NexusColors.textMuted),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    key: const ValueKey('rename_commit_message'),
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 2,
                    onChanged: (_) {
                      _messageEditedByUser = true;
                      setState(() {});
                    },
                    style: const TextStyle(
                      fontSize: 13,
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
                ] else ...[
                  const SizedBox(height: 10),
                  const Text(
                    'سيُعرض ملخص الملفات المتأثرة داخل المجلد قبل تنفيذ الـ Commit.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: NexusColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('rename_cancel'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: NexusColors.textSecondary,
                          side: const BorderSide(
                            color: NexusColors.borderSubtle,
                          ),
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
                        key: const ValueKey('rename_confirm'),
                        height: 46,
                        borderRadius: 13,
                        onPressed: canSubmit ? _submit : null,
                        child: Text(
                          widget.entry.isFolder ? 'معاينة التغيير' : 'تأكيد الاسم',
                        ),
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
