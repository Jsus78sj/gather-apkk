import 'dart:convert';
import 'dart:typed_data';
import '../../../core/utils/format_bytes.dart';
import 'repo_file_kind.dart';
import 'repo_path_validator.dart';

/// Identifies one file (blob) of a repository snapshot.
class RepoFileRef {
  final String path;
  final String sha;
  final int size;
  final String mode;

  const RepoFileRef({
    required this.path,
    required this.sha,
    required this.size,
    this.mode = '100644',
  });

  String get name => RepoPathValidator.nameOf(path);
  String get parentPath => RepoPathValidator.parentOf(path);
  bool get isSymlink => mode == '120000';
  bool get isExecutable => mode == '100755';

  @override
  bool operator ==(Object other) =>
      other is RepoFileRef &&
      other.path == path &&
      other.sha == sha &&
      other.size == size &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(path, sha, size, mode);
}

enum LineEnding { none, lf, crlf, mixed }

extension LineEndingLabel on LineEnding {
  String get label => switch (this) {
        LineEnding.none => '—',
        LineEnding.lf => 'LF',
        LineEnding.crlf => 'CRLF',
        LineEnding.mixed => 'Mixed',
      };
}

/// What the viewer needs to render a file.
class RepoFileContent {
  final RepoFileRef file;
  final RepoFileKind kind;

  /// Decoded text for [RepoFileKind.text] / [RepoFileKind.markdown].
  final String? text;

  /// Raw bytes for [RepoFileKind.image].
  final Uint8List? imageBytes;

  /// Highlighter language id (text files only).
  final String? language;
  final bool hasBom;
  final LineEnding lineEnding;

  /// Why the file is shown as a plain info card (too large, binary, ...).
  final String? notice;

  const RepoFileContent({
    required this.file,
    required this.kind,
    this.text,
    this.imageBytes,
    this.language,
    this.hasBom = false,
    this.lineEnding = LineEnding.none,
    this.notice,
  });

  int get lineCount {
    final value = text;
    if (value == null || value.isEmpty) return 0;
    var count = 1;
    for (var i = 0; i < value.length; i++) {
      if (value.codeUnitAt(i) == 0x0A) count++;
    }
    // A trailing newline does not start a new visible line.
    if (value.codeUnitAt(value.length - 1) == 0x0A) count--;
    return count;
  }

  /// Loads and classifies [file]. [readBytes] is only called when the content
  /// is actually needed, so known binary / oversized files cost no request.
  static Future<RepoFileContent> load(
    RepoFileRef file,
    Future<Uint8List> Function() readBytes,
  ) async {
    final hint = RepoFileKinds.byName(file.name);

    if (hint == RepoFileKind.binary) {
      return RepoFileContent(
        file: file,
        kind: RepoFileKind.binary,
        notice: 'هذا النوع من الملفات لا يمكن عرضه كنص.',
      );
    }

    if (hint == RepoFileKind.image) {
      if (file.size > RepoFileKinds.maxImagePreviewBytes) {
        return RepoFileContent(
          file: file,
          kind: RepoFileKind.binary,
          notice: 'الصورة كبيرة جداً للمعاينة '
              '(${formatBytes(file.size)}، الحد '
              '${formatBytes(RepoFileKinds.maxImagePreviewBytes)}).',
        );
      }
      final bytes = await readBytes();
      return RepoFileContent(
        file: file,
        kind: RepoFileKind.image,
        imageBytes: bytes,
      );
    }

    if (file.size > RepoFileKinds.maxTextPreviewBytes) {
      return RepoFileContent(
        file: file,
        kind: RepoFileKind.binary,
        notice: 'الملف كبير جداً للمعاينة '
            '(${formatBytes(file.size)}، الحد '
            '${formatBytes(RepoFileKinds.maxTextPreviewBytes)}).',
      );
    }

    final bytes = await readBytes();
    return fromBytes(file, bytes, hint: hint);
  }

  /// Classifies already-downloaded [bytes] (also used directly by tests).
  static RepoFileContent fromBytes(
    RepoFileRef file,
    Uint8List bytes, {
    RepoFileKind? hint,
  }) {
    if (bytes.length > RepoFileKinds.maxTextPreviewBytes) {
      return RepoFileContent(
        file: file,
        kind: RepoFileKind.binary,
        notice: 'الملف كبير جداً للمعاينة (${formatBytes(bytes.length)}).',
      );
    }
    if (RepoFileKinds.looksBinary(bytes)) {
      return RepoFileContent(
        file: file,
        kind: RepoFileKind.binary,
        notice: 'يبدو أن الملف ثنائي (غير نصي).',
      );
    }

    final hasBom = bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF;
    final body = hasBom ? Uint8List.sublistView(bytes, 3) : bytes;
    final text = utf8.decode(body, allowMalformed: true);

    return RepoFileContent(
      file: file,
      kind: hint == RepoFileKind.markdown
          ? RepoFileKind.markdown
          : RepoFileKind.text,
      text: text,
      language: RepoFileKinds.languageOf(file.name),
      hasBom: hasBom,
      lineEnding: detectLineEnding(text),
      notice: file.isSymlink ? 'رابط رمزي (Symlink): المحتوى هو مسار الهدف.' : null,
    );
  }

  static LineEnding detectLineEnding(String text) {
    var lf = 0;
    var crlf = 0;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) != 0x0A) continue;
      if (i > 0 && text.codeUnitAt(i - 1) == 0x0D) {
        crlf++;
      } else {
        lf++;
      }
    }
    if (lf == 0 && crlf == 0) return LineEnding.none;
    if (crlf == 0) return LineEnding.lf;
    if (lf == 0) return LineEnding.crlf;
    return LineEnding.mixed;
  }
}
