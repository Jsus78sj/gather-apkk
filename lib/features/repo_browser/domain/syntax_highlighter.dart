/// Lightweight, dependency-free syntax highlighter.
///
/// It is a single-pass tokenizer (comments, strings, numbers, keywords and a
/// few language specific extras), which is enough for a read-only viewer and
/// keeps highlighting of a 1 MB file in the tens of milliseconds.
enum TokenType {
  plain,
  keyword,
  string,
  comment,
  number,
  type,
  tag,
  attribute,
  key,
  meta,
}

class HighlightSpan {
  final String text;
  final TokenType type;

  const HighlightSpan(this.text, this.type);

  @override
  String toString() => '${type.name}(${text.replaceAll('\n', r'\n')})';
}

abstract final class SyntaxHighlighter {
  /// Highlights [text] and returns it split into lines (without line
  /// terminators; `\r` before `\n` is dropped). The result always has at least
  /// one line. Unknown / `null` [language] yields plain spans.
  static List<List<HighlightSpan>> highlight(String text, String? language) {
    final builder = _LineBuilder();
    final spec = language == null ? null : _specs[language];

    if (spec == null) {
      builder.add(text, TokenType.plain);
    } else if (spec.markup) {
      _tokenizeMarkup(text, builder);
    } else {
      _tokenizeCode(text, spec, builder);
    }
    return builder.lines;
  }

  // -------------------------------------------------------------------------
  // Generic code tokenizer
  // -------------------------------------------------------------------------

  static void _tokenizeCode(String text, _Spec spec, _LineBuilder out) {
    var cursor = 0;

    for (final match in spec.regex.allMatches(text)) {
      if (match.start > cursor) {
        out.add(text.substring(cursor, match.start), TokenType.plain);
      }
      final value = match.group(0)!;

      TokenType type;
      if (match.namedGroup('comment') != null) {
        type = TokenType.comment;
      } else if (match.namedGroup('string') != null) {
        type = spec.stringKeys && _followedByColon(text, match.end)
            ? TokenType.key
            : TokenType.string;
      } else if (match.namedGroup('number') != null) {
        type = TokenType.number;
      } else if (match.namedGroup('key') != null) {
        type = TokenType.key;
      } else if (match.namedGroup('meta') != null) {
        type = TokenType.meta;
      } else {
        // identifier
        final word = spec.caseInsensitive ? value.toLowerCase() : value;
        if (spec.keywords.contains(word)) {
          type = TokenType.keyword;
        } else if (spec.highlightTypes &&
            value.length > 1 &&
            _isUpper(value.codeUnitAt(0))) {
          type = TokenType.type;
        } else {
          type = TokenType.plain;
        }
      }

      out.add(value, type);
      cursor = match.end;
    }

    if (cursor < text.length) {
      out.add(text.substring(cursor), TokenType.plain);
    }
  }

  static bool _isUpper(int unit) => unit >= 0x41 && unit <= 0x5A;

  static bool _followedByColon(String text, int from) {
    var i = from;
    while (i < text.length) {
      final unit = text.codeUnitAt(i);
      if (unit == 0x20 || unit == 0x09) {
        i++;
        continue;
      }
      return unit == 0x3A; // ':'
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Markup (HTML / XML / SVG)
  // -------------------------------------------------------------------------

  static final RegExp _markupOuter = RegExp(
    r'(?<comment><!--[\s\S]*?(?:-->|$))|(?<tag><[!?/]?[A-Za-z][^>]*>?)',
  );

  static final RegExp _markupInner = RegExp(
    r'''(?<name>^<[!?/]?[\w:.\-]+)|(?<string>"[^"]*"?|'[^']*'?)|(?<attr>[\w:@.\-]+(?==))|(?<close>/?\??>$)''',
  );

  static void _tokenizeMarkup(String text, _LineBuilder out) {
    var cursor = 0;

    for (final match in _markupOuter.allMatches(text)) {
      if (match.start > cursor) {
        out.add(text.substring(cursor, match.start), TokenType.plain);
      }
      final value = match.group(0)!;

      if (match.namedGroup('comment') != null) {
        out.add(value, TokenType.comment);
      } else {
        _tokenizeTag(value, out);
      }
      cursor = match.end;
    }

    if (cursor < text.length) {
      out.add(text.substring(cursor), TokenType.plain);
    }
  }

  static void _tokenizeTag(String tag, _LineBuilder out) {
    var cursor = 0;
    for (final match in _markupInner.allMatches(tag)) {
      if (match.start > cursor) {
        out.add(tag.substring(cursor, match.start), TokenType.plain);
      }
      final value = match.group(0)!;
      if (match.namedGroup('string') != null) {
        out.add(value, TokenType.string);
      } else if (match.namedGroup('attr') != null) {
        out.add(value, TokenType.attribute);
      } else {
        out.add(value, TokenType.tag);
      }
      cursor = match.end;
    }
    if (cursor < tag.length) {
      out.add(tag.substring(cursor), TokenType.plain);
    }
  }

  // -------------------------------------------------------------------------
  // Language specs
  // -------------------------------------------------------------------------

  static final Map<String, _Spec> _specs = _buildSpecs();

  static Map<String, _Spec> _buildSpecs() {
    final cLikeComments = _Comments(line: '//', block: ('/*', '*/'));

    _Spec cLike(
      Set<String> keywords, {
      bool backtickStrings = false,
      String? metaPattern,
      bool types = true,
    }) =>
        _Spec.code(
          comments: cLikeComments,
          quotes: ['"', "'", if (backtickStrings) '`'],
          keywords: keywords,
          metaPattern: metaPattern ?? r'@[A-Za-z_][\w.]*',
          highlightTypes: types,
        );

    final jsKeywords = {
      'abstract', 'as', 'async', 'await', 'break', 'case', 'catch', 'class',
      'const', 'constructor', 'continue', 'debugger', 'declare', 'default',
      'delete', 'do', 'else', 'enum', 'export', 'extends', 'false', 'finally',
      'for', 'from', 'function', 'get', 'if', 'implements', 'import', 'in',
      'instanceof', 'interface', 'let', 'namespace', 'new', 'null', 'of',
      'private', 'protected', 'public', 'readonly', 'return', 'set', 'static',
      'super', 'switch', 'this', 'throw', 'true', 'try', 'type', 'typeof',
      'undefined', 'var', 'void', 'while', 'with', 'yield',
    };

    return {
      'dart': cLike({
        'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case',
        'catch', 'class', 'const', 'continue', 'covariant', 'default',
        'deferred', 'do', 'dynamic', 'else', 'enum', 'export', 'extends',
        'extension', 'external', 'factory', 'false', 'final', 'finally',
        'for', 'Function', 'get', 'hide', 'if', 'implements', 'import', 'in',
        'interface', 'is', 'late', 'library', 'mixin', 'new', 'null', 'on',
        'operator', 'part', 'required', 'rethrow', 'return', 'sealed', 'set',
        'show', 'static', 'super', 'switch', 'sync', 'this', 'throw', 'true',
        'try', 'typedef', 'var', 'void', 'when', 'while', 'with', 'yield',
      }),
      'js': cLike(jsKeywords, backtickStrings: true),
      'ts': cLike(jsKeywords, backtickStrings: true),
      'java': cLike({
        'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch',
        'char', 'class', 'const', 'continue', 'default', 'do', 'double',
        'else', 'enum', 'extends', 'false', 'final', 'finally', 'float', 'for',
        'if', 'implements', 'import', 'instanceof', 'int', 'interface', 'long',
        'native', 'new', 'null', 'package', 'private', 'protected', 'public',
        'return', 'short', 'static', 'super', 'switch', 'synchronized', 'this',
        'throw', 'throws', 'transient', 'true', 'try', 'var', 'void',
        'volatile', 'while', 'record', 'sealed', 'permits',
      }),
      'kotlin': cLike({
        'abstract', 'actual', 'annotation', 'as', 'break', 'by', 'catch',
        'class', 'companion', 'const', 'constructor', 'continue', 'crossinline',
        'data', 'do', 'else', 'enum', 'expect', 'external', 'false', 'final',
        'finally', 'for', 'fun', 'if', 'import', 'in', 'infix', 'init',
        'inline', 'inner', 'interface', 'internal', 'is', 'lateinit', 'noinline',
        'null', 'object', 'open', 'operator', 'out', 'override', 'package',
        'private', 'protected', 'public', 'reified', 'return', 'sealed',
        'super', 'suspend', 'this', 'throw', 'true', 'try', 'typealias', 'val',
        'var', 'vararg', 'when', 'where', 'while',
      }),
      'swift': cLike({
        'associatedtype', 'async', 'await', 'break', 'case', 'catch', 'class',
        'continue', 'default', 'defer', 'deinit', 'do', 'else', 'enum',
        'extension', 'fallthrough', 'false', 'fileprivate', 'for', 'func',
        'guard', 'if', 'import', 'in', 'init', 'inout', 'internal', 'is', 'let',
        'nil', 'open', 'operator', 'override', 'private', 'protocol', 'public',
        'return', 'self', 'Self', 'static', 'struct', 'subscript', 'super',
        'switch', 'throw', 'throws', 'true', 'try', 'typealias', 'var',
        'where', 'while',
      }),
      'go': cLike(
        {
          'break', 'case', 'chan', 'const', 'continue', 'default', 'defer',
          'else', 'fallthrough', 'false', 'for', 'func', 'go', 'goto', 'if',
          'import', 'interface', 'map', 'nil', 'package', 'range', 'return',
          'select', 'struct', 'switch', 'true', 'type', 'var',
        },
        backtickStrings: true,
      ),
      'rust': cLike(
        {
          'as', 'async', 'await', 'break', 'const', 'continue', 'crate', 'dyn',
          'else', 'enum', 'extern', 'false', 'fn', 'for', 'if', 'impl', 'in',
          'let', 'loop', 'match', 'mod', 'move', 'mut', 'pub', 'ref', 'return',
          'self', 'Self', 'static', 'struct', 'super', 'trait', 'true', 'type',
          'unsafe', 'use', 'where', 'while',
        },
        metaPattern: r'#!?\[[^\]\n]*\]',
      ),
      'c': cLike(
        _cKeywords,
        metaPattern: r'^[ \t]*#[ \t]*[a-z]+',
        types: false,
      ),
      'cpp': cLike(
        {
          ..._cKeywords,
          'class', 'namespace', 'template', 'typename', 'public', 'private',
          'protected', 'virtual', 'override', 'new', 'delete', 'this',
          'nullptr', 'true', 'false', 'using', 'try', 'catch', 'throw',
          'constexpr', 'noexcept', 'auto', 'bool', 'friend', 'operator',
        },
        metaPattern: r'^[ \t]*#[ \t]*[a-z]+',
        types: false,
      ),
      'csharp': cLike({
        'abstract', 'as', 'async', 'await', 'base', 'bool', 'break', 'byte',
        'case', 'catch', 'char', 'class', 'const', 'continue', 'decimal',
        'default', 'delegate', 'do', 'double', 'else', 'enum', 'event',
        'explicit', 'extern', 'false', 'finally', 'fixed', 'float', 'for',
        'foreach', 'get', 'if', 'implicit', 'in', 'int', 'interface',
        'internal', 'is', 'lock', 'long', 'namespace', 'new', 'null', 'object',
        'operator', 'out', 'override', 'params', 'private', 'protected',
        'public', 'readonly', 'ref', 'return', 'sealed', 'set', 'short',
        'static', 'string', 'struct', 'switch', 'this', 'throw', 'true', 'try',
        'typeof', 'uint', 'ulong', 'using', 'var', 'virtual', 'void', 'while',
        'yield',
      }),
      'php': _Spec.code(
        comments: _Comments(line: '//', block: ('/*', '*/'), altLine: '#'),
        quotes: ['"', "'"],
        keywords: {
          'abstract', 'and', 'array', 'as', 'break', 'case', 'catch', 'class',
          'const', 'continue', 'default', 'do', 'echo', 'else', 'elseif',
          'extends', 'false', 'final', 'finally', 'fn', 'for', 'foreach',
          'function', 'global', 'if', 'implements', 'include', 'interface',
          'isset', 'namespace', 'new', 'null', 'or', 'private', 'protected',
          'public', 'require', 'return', 'static', 'switch', 'throw', 'trait',
          'true', 'try', 'use', 'var', 'while',
        },
        metaPattern: r'\$[A-Za-z_]\w*',
      ),
      'python': _Spec.code(
        comments: _Comments(line: '#'),
        quotes: ['"', "'"],
        tripleQuotes: true,
        keywords: {
          'and', 'as', 'assert', 'async', 'await', 'break', 'class',
          'continue', 'def', 'del', 'elif', 'else', 'except', 'False',
          'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is',
          'lambda', 'None', 'nonlocal', 'not', 'or', 'pass', 'raise', 'return',
          'True', 'try', 'while', 'with', 'yield', 'self', 'cls',
        },
        metaPattern: r'@[A-Za-z_][\w.]*',
      ),
      'ruby': _Spec.code(
        comments: _Comments(line: '#'),
        quotes: ['"', "'"],
        keywords: {
          'alias', 'and', 'begin', 'break', 'case', 'class', 'def', 'defined?',
          'do', 'else', 'elsif', 'end', 'ensure', 'false', 'for', 'if', 'in',
          'module', 'next', 'nil', 'not', 'or', 'redo', 'require', 'rescue',
          'retry', 'return', 'self', 'super', 'then', 'true', 'undef',
          'unless', 'until', 'when', 'while', 'yield',
        },
        metaPattern: r':[A-Za-z_]\w*',
      ),
      'shell': _Spec.code(
        comments: _Comments(line: '#'),
        quotes: ['"', "'", '`'],
        keywords: {
          'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'until', 'do',
          'done', 'case', 'esac', 'in', 'function', 'return', 'exit', 'export',
          'local', 'readonly', 'set', 'unset', 'source', 'echo', 'cd', 'rem',
          'call', 'goto', 'setlocal', 'endlocal',
        },
        metaPattern: r'\$(?:\{[^}\n]*\}|[A-Za-z_]\w*|[0-9@#?$!*])',
        highlightTypes: false,
      ),
      'dockerfile': _Spec.code(
        comments: _Comments(line: '#'),
        quotes: ['"', "'"],
        keywords: {
          'from', 'run', 'cmd', 'label', 'maintainer', 'expose', 'env', 'add',
          'copy', 'entrypoint', 'volume', 'user', 'workdir', 'arg',
          'onbuild', 'stopsignal', 'healthcheck', 'shell', 'as',
        },
        caseInsensitive: true,
        highlightTypes: false,
      ),
      'makefile': _Spec.code(
        comments: _Comments(line: '#'),
        quotes: ['"', "'"],
        keywords: {
          'ifeq', 'ifneq', 'ifdef', 'ifndef', 'else', 'endif', 'include',
          'define', 'endef', 'export', 'override',
        },
        keyPattern: r'^[A-Za-z0-9_.\-%/ ]+(?=:(?!=))',
        metaPattern: r'\$[({][^)}\n]*[)}]',
        highlightTypes: false,
      ),
      'sql': _Spec.code(
        comments: _Comments(line: '--', block: ('/*', '*/')),
        quotes: ["'", '"'],
        keywords: {
          'select', 'from', 'where', 'and', 'or', 'not', 'insert', 'into',
          'values', 'update', 'set', 'delete', 'create', 'table', 'alter',
          'drop', 'index', 'view', 'join', 'inner', 'left', 'right', 'outer',
          'full', 'on', 'as', 'group', 'by', 'order', 'having', 'limit',
          'offset', 'union', 'all', 'distinct', 'null', 'is', 'in', 'like',
          'between', 'exists', 'case', 'when', 'then', 'else', 'end',
          'primary', 'key', 'foreign', 'references', 'default', 'constraint',
          'unique', 'begin', 'commit', 'rollback', 'if', 'true', 'false',
        },
        caseInsensitive: true,
        highlightTypes: false,
      ),
      'json': _Spec.code(
        comments: const _Comments(),
        quotes: ['"'],
        keywords: {'true', 'false', 'null'},
        stringKeys: true,
        highlightTypes: false,
      ),
      'yaml': _Spec.code(
        comments: _Comments(line: '#'),
        quotes: ['"', "'"],
        keywords: {'true', 'false', 'null', 'yes', 'no', 'on', 'off'},
        keyPattern: r'^[ \t]*(?:-[ \t]+)?[\w.\-/]+(?=[ \t]*:(?:[ \t]|$))',
        metaPattern: r'[&*][A-Za-z_][\w\-]*',
        highlightTypes: false,
      ),
      'toml': _Spec.code(
        comments: _Comments(line: '#', altLine: ';'),
        quotes: ['"', "'"],
        keywords: {'true', 'false'},
        keyPattern: r'^[ \t]*[\w.\-]+(?=[ \t]*=)',
        metaPattern: r'^[ \t]*\[[^\]\n]*\]',
        highlightTypes: false,
      ),
      'css': _Spec.code(
        comments: _Comments(block: ('/*', '*/')),
        quotes: ['"', "'"],
        keywords: const {},
        keyPattern: r'[a-z\-]+(?=[ \t]*:(?!:))',
        metaPattern: r'@[A-Za-z\-]+',
        extraNumberPattern: r'#[0-9a-fA-F]{3,8}\b',
        highlightTypes: false,
      ),
      'xml': _Spec.markupSpec(),
    };
  }

  static const Set<String> _cKeywords = {
    'auto', 'break', 'case', 'char', 'const', 'continue', 'default', 'do',
    'double', 'else', 'enum', 'extern', 'float', 'for', 'goto', 'if', 'inline',
    'int', 'long', 'register', 'return', 'short', 'signed', 'sizeof', 'static',
    'struct', 'switch', 'typedef', 'union', 'unsigned', 'void', 'volatile',
    'while', 'NULL',
  };
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

class _Comments {
  final String? line;
  final String? altLine;
  final (String, String)? block;

  const _Comments({this.line, this.altLine, this.block});
}

class _Spec {
  final RegExp regex;
  final Set<String> keywords;
  final bool caseInsensitive;
  final bool stringKeys;
  final bool highlightTypes;
  final bool markup;

  _Spec._({
    required this.regex,
    required this.keywords,
    required this.caseInsensitive,
    required this.stringKeys,
    required this.highlightTypes,
    required this.markup,
  });

  factory _Spec.markupSpec() => _Spec._(
        regex: RegExp(r'(?!)'),
        keywords: const {},
        caseInsensitive: false,
        stringKeys: false,
        highlightTypes: false,
        markup: true,
      );

  factory _Spec.code({
    required _Comments comments,
    required List<String> quotes,
    required Set<String> keywords,
    bool tripleQuotes = false,
    bool caseInsensitive = false,
    bool stringKeys = false,
    bool highlightTypes = true,
    String? keyPattern,
    String? metaPattern,
    String? extraNumberPattern,
  }) {
    // Every named group always exists (never-matching `(?!)` when a language
    // does not use it), because Match.namedGroup throws for unknown names.
    const never = '(?!)';
    // `$` would also match at every line end (multiLine), so "end of input"
    // is spelled as a negative lookahead.
    const endOfInput = r'(?![\s\S])';

    final commentParts = <String>[];
    final block = comments.block;
    if (block != null) {
      commentParts.add(
        '${RegExp.escape(block.$1)}[\\s\\S]*?'
        '(?:${RegExp.escape(block.$2)}|$endOfInput)',
      );
    }
    for (final prefix in [comments.line, comments.altLine]) {
      if (prefix != null) {
        commentParts.add('${RegExp.escape(prefix)}[^\\n]*');
      }
    }

    final stringParts = <String>[];
    if (tripleQuotes) {
      stringParts
        ..add('"""[\\s\\S]*?(?:"""|$endOfInput)')
        ..add("\'\'\'[\\s\\S]*?(?:\'\'\'|$endOfInput)");
    }
    for (final q in quotes) {
      // Backtick strings may span lines; the others stop at the line end.
      final excluded = q == '`' ? r'\\' : r'\\\n';
      stringParts.add('$q' r'(?:\\[\s\S]|[^' '$q$excluded' r'])*' '$q?');
    }

    final numberParts = <String>[
      if (extraNumberPattern != null) extraNumberPattern,
      r'\b0[xX][0-9a-fA-F_]+\b',
      r'\b\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?\b',
    ];

    final parts = <String>[
      '(?<comment>${commentParts.isEmpty ? never : commentParts.join('|')})',
      '(?<string>${stringParts.isEmpty ? never : stringParts.join('|')})',
      '(?<key>${keyPattern ?? never})',
      '(?<meta>${metaPattern ?? never})',
      '(?<number>${numberParts.join('|')})',
      r'(?<word>[A-Za-z_$][\w$]*)',
    ];

    return _Spec._(
      regex: RegExp(parts.join('|'), multiLine: true),
      keywords: caseInsensitive
          ? {for (final k in keywords) k.toLowerCase()}
          : keywords,
      caseInsensitive: caseInsensitive,
      stringKeys: stringKeys,
      highlightTypes: highlightTypes,
      markup: false,
    );
  }
}

/// Accumulates spans into lines, merging neighbours of the same type.
class _LineBuilder {
  final List<List<HighlightSpan>> lines = [<HighlightSpan>[]];

  void add(String text, TokenType type) {
    var start = 0;
    while (true) {
      final newline = text.indexOf('\n', start);
      final end = newline == -1 ? text.length : newline;
      var segment = text.substring(start, end);
      if (newline != -1 && segment.endsWith('\r')) {
        segment = segment.substring(0, segment.length - 1);
      }
      if (segment.isNotEmpty) _append(segment, type);
      if (newline == -1) break;
      lines.add(<HighlightSpan>[]);
      start = newline + 1;
    }
  }

  void _append(String segment, TokenType type) {
    final line = lines.last;
    if (line.isNotEmpty && line.last.type == type) {
      final last = line.removeLast();
      line.add(HighlightSpan(last.text + segment, type));
    } else {
      line.add(HighlightSpan(segment, type));
    }
  }
}
