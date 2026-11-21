import 'dart:typed_data';

/// نتيجة تجهيز التنزيل من المستودع (ملف خام أو أرشيف ZIP).
class RepoDownloadPayload {
  final String fileName;
  final Uint8List bytes;
  final int fileCount;
  final bool isZip;

  const RepoDownloadPayload({
    required this.fileName,
    required this.bytes,
    required this.fileCount,
    required this.isZip,
  });

  int get sizeBytes => bytes.length;
}
