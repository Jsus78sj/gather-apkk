/// Validation and small helpers for repository-relative paths.
class RepoPathValidator {
  const RepoPathValidator._();

  static const int maxPathLength = 4096;

  /// Returns an Arabic error message, or `null` when [path] is acceptable.
  static String? validate(String path) {
    if (path.trim().isEmpty) return 'المسار فارغ.';
    if (path.length > maxPathLength) return 'المسار طويل جداً.';
    if (path.startsWith('/') || path.endsWith('/')) {
      return 'يجب ألا يبدأ المسار أو ينتهي بالرمز "/".';
    }
    if (path.contains('\\')) return 'المسار يحتوي الرمز "\\" غير المسموح.';
    if (path.contains('//')) return 'المسار يحتوي مقطعاً فارغاً ("//").';

    for (final unit in path.codeUnits) {
      if (unit < 0x20 || unit == 0x7f) {
        return 'المسار يحتوي أحرفاً تحكمية غير مسموحة.';
      }
    }

    for (final segment in path.split('/')) {
      if (segment.trim().isEmpty) return 'المسار يحتوي اسماً فارغاً.';
      if (segment == '.' || segment == '..') {
        return 'المسار لا يقبل المقطعين "." أو "..".';
      }
      if (segment.toLowerCase() == '.git') {
        return 'لا يمكن استخدام المجلد ".git" في المسار.';
      }
    }
    return null;
  }

  /// `true` when [child] lives strictly inside the folder [parent].
  static bool isInside(String parent, String child) =>
      child.startsWith('$parent/');

  static String parentOf(String path) {
    final i = path.lastIndexOf('/');
    return i == -1 ? '' : path.substring(0, i);
  }

  static String nameOf(String path) {
    final i = path.lastIndexOf('/');
    return i == -1 ? path : path.substring(i + 1);
  }
}
