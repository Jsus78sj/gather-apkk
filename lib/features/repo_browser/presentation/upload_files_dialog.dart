import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/utils/format_bytes.dart';
import '../../../core/widgets/glass_panel.dart';
import '../domain/arabic_count.dart';

class UploadFilesDialogResult {
  final List<({String name, Uint8List bytes})> files;
  final String commitMessage;
  final bool overwriteExisting;

  const UploadFilesDialogResult({
    required this.files,
    required this.commitMessage,
    required this.overwriteExisting,
  });
}

/// يفتح منتقي الملفات من الهاتف ثم يعرض نافذة مراجعة قبل رفعها في Commit واحد.
Future<UploadFilesDialogResult?> pickAndConfirmLocalFilesUpload(
  BuildContext context, {
  required String currentFolderPath,
  required Set<String> existingFileNames,
}) async {
  final picked = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    withData: true,
  );
  if (picked == null || picked.files.isEmpty || !context.mounted) return null;

  final loaded = <({String name, Uint8List bytes})>[];
  for (final pf in picked.files) {
    Uint8List? bytes = pf.bytes;
    if (bytes == null && pf.path != null) {
      bytes = await File(pf.path!).readAsBytes();
    }
    if (bytes != null) {
      loaded.add((name: pf.name, bytes: bytes));
    }
  }
  if (loaded.isEmpty || !context.mounted) return null;

  return showDialog<UploadFilesDialogResult>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.84),
    builder: (_) => _UploadConfirmDialog(
      files: loaded,
      currentFolderPath: currentFolderPath,
      existingFileNames: existingFileNames,
    ),
  );
}

class _UploadConfirmDialog extends StatefulWidget {
  final List<({String name, Uint8List bytes})> files;
  final String currentFolderPath;
  final Set<String> existingFileNames;

  const _UploadConfirmDialog({
    required this.files,
    required this.currentFolderPath,
    required this.existingFileNames,
  });

  @override
  State<_UploadConfirmDialog> createState() => _UploadConfirmDialogState();
}

class _UploadConfirmDialogState extends State<_UploadConfirmDialog> {
  late final TextEditingController _message;
  bool _overwrite = false;

  @override
  void initState() {
    super.initState();
    final dest = widget.currentFolderPath.isEmpty
        ? '/'
        : '${widget.currentFolderPath}/';
    _message = TextEditingController(
      text: widget.files.length == 1
          ? 'Nexus: upload ${widget.files.first.name}'
          : 'Nexus: upload ${widget.files.length} files to $dest',
    );
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalBytes =
        widget.files.fold<int>(0, (sum, f) => sum + f.bytes.length);
    final collisions = widget.files
        .where((f) => widget.existingFileNames.contains(f.name))
        .length;
    final canSubmit = _message.text.trim().isNotEmpty &&
        (collisions == 0 || _overwrite);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassPanel(
          strong: true,
          borderRadius: 22,
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.upload_file_rounded,
                      color: NexusColors.successSoft,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'رفع ${arabicFiles(widget.files.length)} (${formatBytes(totalBytes)})',
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: NexusColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 170),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: NexusColors.bgDeep.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: NexusColors.borderSubtle),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.files.length,
                    itemBuilder: (_, idx) {
                      final f = widget.files[idx];
                      final exists = widget.existingFileNames.contains(f.name);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                f.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11.5,
                                  color: exists
                                      ? NexusColors.warningSoft
                                      : NexusColors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatBytes(f.bytes.length),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10.5,
                                color: NexusColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (collisions > 0) ...[
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _overwrite,
                    activeColor: NexusColors.warning,
                    title: Text(
                      'استبدال ${arabicFiles(collisions)} موجودة بنفس الاسم',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: NexusColors.warningSoft,
                      ),
                    ),
                    onChanged: (v) => setState(() => _overwrite = v ?? false),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _message,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    fontSize: 13,
                    color: NexusColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'رسالة الـ Commit',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
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
                        height: 46,
                        borderRadius: 13,
                        gradient: NexusColors.successGradient,
                        onPressed: canSubmit
                            ? () => Navigator.of(context).pop(
                                  UploadFilesDialogResult(
                                    files: widget.files,
                                    commitMessage: _message.text.trim(),
                                    overwriteExisting: _overwrite,
                                  ),
                                )
                            : null,
                        child: const Text('رفع و Commit'),
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
