import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../domain/repo_path_validator.dart';

class CreateEntryDialogResult {
  final String name;
  final Uint8List? fileBytes; // null عند إنشاء مجلد فارغ (.gitkeep)
  final String commitMessage;

  const CreateEntryDialogResult({
    required this.name,
    required this.fileBytes,
    required this.commitMessage,
  });

  bool get isFolder => fileBytes == null;
}

Future<CreateEntryDialogResult?> showCreateEntryDialog(
  BuildContext context, {
  required bool isFolder,
  required String currentFolderPath,
}) {
  return showDialog<CreateEntryDialogResult>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.84),
    builder: (_) => _CreateEntryDialog(
      isFolder: isFolder,
      currentFolderPath: currentFolderPath,
    ),
  );
}

class _CreateEntryDialog extends StatefulWidget {
  final bool isFolder;
  final String currentFolderPath;

  const _CreateEntryDialog({
    required this.isFolder,
    required this.currentFolderPath,
  });

  @override
  State<_CreateEntryDialog> createState() => _CreateEntryDialogState();
}

class _CreateEntryDialogState extends State<_CreateEntryDialog> {
  final _nameController = TextEditingController();
  final _contentController = TextEditingController();
  final _messageController = TextEditingController();
  bool _messageTouched = false;

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  String _fullPath(String rawName) {
    var clean = rawName.trim().replaceAll('\\', '/');
    while (clean.startsWith('/')) {
      clean = clean.substring(1);
    }
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (clean.isEmpty) return '';
    return widget.currentFolderPath.isEmpty
        ? clean
        : '${widget.currentFolderPath}/$clean';
  }

  String? _validate() {
    final full = _fullPath(_nameController.text);
    if (full.isEmpty) {
      return widget.isFolder ? 'أدخل اسم المجلد.' : 'أدخل اسم الملف.';
    }
    return RepoPathValidator.validate(full);
  }

  void _onNameChanged(String value) {
    if (!_messageTouched) {
      final full = _fullPath(value);
      if (full.isNotEmpty) {
        _messageController.text = widget.isFolder
            ? 'Nexus: create folder $full'
            : 'Nexus: create $full';
      }
    }
    setState(() {});
  }

  void _submit() {
    if (_validate() != null) return;
    final msg = _messageController.text.trim();
    if (msg.isEmpty) return;

    Navigator.of(context).pop(
      CreateEntryDialogResult(
        name: _nameController.text.trim(),
        fileBytes: widget.isFolder
            ? null
            : Uint8List.fromList(utf8.encode(_contentController.text)),
        commitMessage: msg,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nameError = _nameController.text.isEmpty ? null : _validate();
    final canSubmit =
        _validate() == null && _messageController.text.trim().isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassPanel(
          strong: true,
          borderRadius: 22,
          padding: const EdgeInsets.all(22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      widget.isFolder
                          ? Icons.create_new_folder_rounded
                          : Icons.note_add_rounded,
                      color: NexusColors.primarySoft,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.isFolder ? 'مجلد جديد' : 'ملف جديد',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: NexusColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('create_entry_name'),
                  controller: _nameController,
                  autofocus: true,
                  textDirection: TextDirection.ltr,
                  onChanged: _onNameChanged,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13.5,
                    color: NexusColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: widget.isFolder ? 'اسم المجلد' : 'اسم الملف',
                    hintText: widget.isFolder
                        ? 'مثال: docs أو assets/icons'
                        : 'مثال: notes.md أو lib/helper.dart',
                    errorText: nameError,
                  ),
                ),
                if (widget.isFolder) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'لا يدعم Git المجلدات الفارغة تماماً؛ سيُنشأ ملف .gitkeep داخل المجلد تلقائياً.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: NexusColors.textMuted,
                      height: 1.45,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('create_entry_content'),
                    controller: _contentController,
                    textDirection: TextDirection.ltr,
                    minLines: 4,
                    maxLines: 8,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      color: NexusColors.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'محتوى مبدئي (اختياري)',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('create_entry_message'),
                  controller: _messageController,
                  onChanged: (_) {
                    _messageTouched = true;
                    setState(() {});
                  },
                  style: const TextStyle(
                    fontSize: 13,
                    color: NexusColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'رسالة الـ Commit',
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
                        key: const ValueKey('create_entry_submit'),
                        height: 46,
                        borderRadius: 13,
                        onPressed: canSubmit ? _submit : null,
                        child: const Text('إنشاء و Commit'),
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
