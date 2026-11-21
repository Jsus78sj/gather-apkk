import 'dart:convert';
import 'dart:typed_data';
import '../../../core/utils/format_bytes.dart';
import 'repo_file_content.dart';
import 'repo_file_kind.dart';

/// حراسات التحقق من قابلية تعديل الملف قبل فتح المحرر أو حفظ التغييرات.
abstract final class RepoEditGuard {
  static const int maxEditableBytes = RepoFileKinds.maxTextPreviewBytes; // 1 MB

  /// يُرجع رسالة منع عربية واضحة، أو `null` إذا كان الملف صالحاً للتعديل.
  static String? whyNotEditable(
    RepoFileContent content, {
    required bool canPush,
  }) {
    if (!canPush) {
      return 'لا تملك صلاحية الكتابة في هذا المستودع.';
    }
    if (content.file.isSymlink) {
      return 'لا يمكن تعديل رابط رمزي (Symlink) من المحرر.';
    }
    if (content.kind != RepoFileKind.text &&
        content.kind != RepoFileKind.markdown) {
      return 'لا يمكن تعديل الملفات الثنائية أو الصور في محرر النصوص.';
    }
    if (content.text == null) {
      return 'تعذر قراءة محتوى الملف كنص قابل للتعديل.';
    }
    if (content.file.size > maxEditableBytes) {
      return 'حجم الملف (${formatBytes(content.file.size)}) يتجاوز الحد الأقصى '
          'للتعديل (${formatBytes(maxEditableBytes)}).';
    }
    return null;
  }

  /// يتحقق من أن المحتوى الناتج بعد التعديل لا يتجاوز حد 1 MB.
  static String? validateEncodedSize(Uint8List bytes) {
    if (bytes.length > maxEditableBytes) {
      return 'حجم الملف بعد التعديل (${formatBytes(bytes.length)}) يتجاوز '
          'الحد الأقصى المسموح (${formatBytes(maxEditableBytes)}).';
    }
    return null;
  }
}

/// تحويل النص بين صيغة المحرر (`\n`) وصيغة الحفظ الأصلية مع الحفاظ على CRLF والـ BOM.
abstract final class RepoTextCodec {
  static const List<int> utf8Bom = [0xEF, 0xBB, 0xBF];

  /// يوحّد نهايات الأسطر إلى `\n` للعمل بسلاسة داخل TextField في Flutter.
  static String normalizeForEditor(String rawText) =>
      rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  /// يعيد ترميز نص المحرر إلى بايتات UTF-8 مع استعادة CRLF وUTF-8 BOM إن وجدا أصلاً.
  static Uint8List encodeForCommit(
    String editorText, {
    required LineEnding originalLineEnding,
    required bool hasBom,
  }) {
    final normalized = normalizeForEditor(editorText);
    final withLineEndings = originalLineEnding == LineEnding.crlf
        ? normalized.replaceAll('\n', '\r\n')
        : normalized;
    final body = utf8.encode(withLineEndings);

    if (!hasBom) {
      return Uint8List.fromList(body);
    }
    final out = Uint8List(utf8Bom.length + body.length);
    out.setRange(0, utf8Bom.length, utf8Bom);
    out.setRange(utf8Bom.length, out.length, body);
    return out;
  }
}
