import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../domain/repo_download_payload.dart';

/// يحفظ ملفاً منزّلاً (أو أرشيف ZIP) في الموقع الذي يختاره المستخدم.
/// يُرجع المسار المحفوظ، أو `null` إذا ألغى المستخدم نافذة الحفظ.
class RepoDownloadSaver {
  const RepoDownloadSaver();

  Future<String?> save(RepoDownloadPayload payload) async {
    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'حفظ ${payload.fileName}',
      fileName: payload.fileName,
      bytes: payload.bytes,
    );
    if (savedPath == null || savedPath.isEmpty) return null;

    // على سطح المكتب لا يكتب saveFile البايتات تلقائياً؛ نكتبها إذا كان مساراً محلياً.
    if (!Platform.isAndroid && !Platform.isIOS) {
      final file = File(savedPath);
      await file.writeAsBytes(payload.bytes, flush: true);
    }
    return savedPath;
  }
}
