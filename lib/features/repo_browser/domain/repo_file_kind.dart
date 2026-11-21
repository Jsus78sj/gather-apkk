import 'dart:convert';
import 'dart:typed_data';

/// How a repository file is presented in the viewer.
enum RepoFileKind { text, markdown, image, binary }

/// Pure helpers that classify files by name and by content.
abstract final class RepoFileKinds {
  /// Text files above this size are not previewed (also the planned edit limit).
  static const int maxTextPreviewBytes = 1024 * 1024;

  /// Images above this size are not decoded in the viewer.
  static const int maxImagePreviewBytes = 10 * 1024 * 1024;

  static const Set<String> _imageExts = {
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico',
  };

  static const Set<String> _markdownExts = {'md', 'markdown', 'mdx'};

  static const Set<String> _binaryExts = {
    'zip', 'gz', 'tgz', 'tar', '7z', 'rar', 'bz2', 'xz', 'jar', 'war', 'apk',
    'aab', 'ipa', 'exe', 'dll', 'so', 'dylib', 'bin', 'class', 'o', 'a',
    'pdf', 'mp3', 'mp4', 'm4a', 'mov', 'avi', 'mkv', 'webm', 'wav', 'ogg',
    'flac', 'ttf', 'otf', 'woff', 'woff2', 'eot', 'psd', 'ai', 'sketch',
    'sqlite', 'sqlite3', 'db', 'keystore', 'jks', 'p12', 'iso', 'dmg', 'deb',
    'rpm', 'pyc', 'wasm', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
    'heic', 'tif', 'tiff', 'pack', 'idx',
  };

  /// extension -> highlighter language id.
  static const Map<String, String> _languageByExt = {
    'dart': 'dart',
    'js': 'js', 'mjs': 'js', 'cjs': 'js', 'jsx': 'js',
    'ts': 'ts', 'tsx': 'ts',
    'json': 'json', 'jsonc': 'json', 'arb': 'json', 'map': 'json',
    'yaml': 'yaml', 'yml': 'yaml',
    'toml': 'toml', 'ini': 'toml', 'cfg': 'toml', 'conf': 'toml',
    'properties': 'toml', 'env': 'toml',
    'xml': 'xml', 'html': 'xml', 'htm': 'xml', 'svg': 'xml', 'xhtml': 'xml',
    'plist': 'xml',
    'css': 'css', 'scss': 'css', 'sass': 'css', 'less': 'css',
    'py': 'python', 'pyw': 'python',
    'rb': 'ruby', 'rake': 'ruby', 'gemspec': 'ruby',
    'java': 'java',
    'kt': 'kotlin', 'kts': 'kotlin',
    'gradle': 'kotlin', 'groovy': 'kotlin',
    'swift': 'swift',
    'go': 'go',
    'rs': 'rust',
    'c': 'c', 'h': 'c',
    'cpp': 'cpp', 'cc': 'cpp', 'cxx': 'cpp', 'hpp': 'cpp', 'hh': 'cpp',
    'cs': 'csharp',
    'php': 'php',
    'sh': 'shell', 'bash': 'shell', 'zsh': 'shell', 'fish': 'shell',
    'bat': 'shell', 'cmd': 'shell',
    'sql': 'sql',
    'dockerfile': 'dockerfile',
    'mk': 'makefile',
  };

  static const Set<String> _plainTextExts = {
    'txt', 'text', 'log', 'csv', 'tsv', 'gitignore', 'gitattributes',
    'editorconfig', 'lock', 'rst', 'tex', 'diff', 'patch', 'license',
    'pro', 'iml', 'xaml', 'proto', 'graphql', 'gql', 'vue', 'svelte', 'lua',
    'pl', 'r', 'm', 'mm', 'ex', 'exs', 'erl', 'hs', 'clj', 'scala', 'sbt',
  };

  static const Map<String, String> _languageByFileName = {
    'dockerfile': 'dockerfile',
    'makefile': 'makefile',
    'gnumakefile': 'makefile',
    'gemfile': 'ruby',
    'rakefile': 'ruby',
    'podfile': 'ruby',
    'cmakelists.txt': 'makefile',
    '.gitignore': 'shell',
    '.env': 'toml',
  };

  static const Set<String> _plainTextNames = {
    'readme', 'license', 'licence', 'changelog', 'authors', 'notice',
    'copying', 'contributing', 'codeowners',
  };

  /// Lower-cased extension of [fileName] without the dot, or `''`.
  static String extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  /// Classification from the name alone. `null` means "unknown": the content
  /// has to be inspected to decide.
  static RepoFileKind? byName(String fileName) {
    final lower = fileName.toLowerCase();
    final ext = extensionOf(fileName);

    if (_imageExts.contains(ext)) return RepoFileKind.image;
    if (_markdownExts.contains(ext)) return RepoFileKind.markdown;
    if (_binaryExts.contains(ext)) return RepoFileKind.binary;
    if (_languageByExt.containsKey(ext) ||
        _plainTextExts.contains(ext) ||
        _languageByFileName.containsKey(lower) ||
        _plainTextNames.contains(lower)) {
      return RepoFileKind.text;
    }
    return null;
  }

  /// Highlighter language id for [fileName], or `null` for plain text.
  static String? languageOf(String fileName) {
    final lower = fileName.toLowerCase();
    final byFile = _languageByFileName[lower];
    if (byFile != null) return byFile;
    return _languageByExt[extensionOf(fileName)];
  }

  /// Heuristic binary detection: NUL bytes, or a large share of bytes that
  /// are not valid UTF-8, in the first 8000 bytes.
  static bool looksBinary(Uint8List bytes) {
    final sampleLength = bytes.length < 8000 ? bytes.length : 8000;
    if (sampleLength == 0) return false;

    for (var i = 0; i < sampleLength; i++) {
      if (bytes[i] == 0) return true;
    }

    final decoded = utf8.decode(
      Uint8List.sublistView(bytes, 0, sampleLength),
      allowMalformed: true,
    );
    if (decoded.isEmpty) return false;

    var replacements = 0;
    for (final unit in decoded.codeUnits) {
      if (unit == 0xFFFD) replacements++;
    }
    // A sample cut in the middle of a multi-byte character yields at most one
    // replacement character, which the ratio below tolerates.
    return replacements / decoded.length > 0.1;
  }
}
