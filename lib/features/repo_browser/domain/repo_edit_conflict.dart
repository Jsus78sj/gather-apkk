import 'repo_file_content.dart';

/// تفاصيل تعارض رأس الفرع عند تغيّر GitHub بعد فتح الملف في المحرر.
class RepoEditConflictInfo {
  final String openedHeadSha;
  final String latestHeadSha;

  /// `true` إذا تغيّر الملف نفسه أو حُذف على GitHub بعد فتحه.
  final bool sameFileChanged;

  /// `true` إذا حُذف الملف من الفرع عن بُعد.
  final bool fileDeletedRemotely;

  /// أحدث مرجع للملف على الرأس الجديد (إن كان لا يزال موجوداً).
  final RepoFileRef? latestFileRef;

  const RepoEditConflictInfo({
    required this.openedHeadSha,
    required this.latestHeadSha,
    required this.sameFileChanged,
    required this.fileDeletedRemotely,
    this.latestFileRef,
  });

  String get shortOpenedHead =>
      openedHeadSha.length > 7 ? openedHeadSha.substring(0, 7) : openedHeadSha;

  String get shortLatestHead =>
      latestHeadSha.length > 7 ? latestHeadSha.substring(0, 7) : latestHeadSha;
}
