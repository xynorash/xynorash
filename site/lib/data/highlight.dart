import '../models/project.dart';

/// A tiny, dependency-free syntax highlighter for the code excerpts shown
/// in project buffers. It is deliberately simple — one line at a time, no
/// multi-line state — which is plenty for short, curated snippets.
class _Lang {
  final String? lineComment;
  final Set<String> keywords;
  final bool singleQuoteStrings;
  final bool dollarVars;
  final bool caseInsensitive;
  const _Lang({
    this.lineComment,
    this.keywords = const {},
    this.singleQuoteStrings = false,
    this.dollarVars = false,
    this.caseInsensitive = false,
  });
}

const _rust = _Lang(lineComment: '//', keywords: {
  'fn', 'let', 'mut', 'pub', 'use', 'mod', 'impl', 'struct', 'enum', 'trait',
  'for', 'in', 'if', 'else', 'match', 'while', 'loop', 'return', 'break',
  'continue', 'const', 'static', 'unsafe', 'extern', 'as', 'where', 'move',
  'self', 'Self', 'crate', 'super', 'true', 'false', 'type', 'dyn', 'ref',
  'async', 'await',
});

const _lua = _Lang(
  lineComment: '--',
  singleQuoteStrings: true,
  keywords: {
    'local', 'function', 'return', 'if', 'then', 'else', 'elseif', 'end',
    'for', 'in', 'do', 'while', 'not', 'and', 'or', 'nil', 'true', 'false',
    'require',
  },
);

const _dart = _Lang(
  lineComment: '//',
  singleQuoteStrings: true,
  keywords: {
    'class', 'final', 'const', 'var', 'void', 'return', 'if', 'else', 'for',
    'while', 'switch', 'case', 'default', 'try', 'catch', 'on', 'throw',
    'async', 'await', 'extends', 'implements', 'static', 'late', 'new',
    'this', 'super', 'null', 'true', 'false', 'is', 'as', 'in', 'enum',
    'import', 'export', 'required', 'dynamic', 'factory', 'with',
  },
);

const _ps = _Lang(
  lineComment: '#',
  singleQuoteStrings: true,
  dollarVars: true,
  caseInsensitive: true,
  keywords: {
    'function', 'if', 'else', 'elseif', 'foreach', 'for', 'while', 'return',
    'try', 'catch', 'finally', 'param', 'switch', 'in', 'not', 'and', 'or',
    'begin', 'process', 'end', 'throw', 'break', 'continue',
  },
);

const _sh = _Lang(
  lineComment: '#',
  singleQuoteStrings: true,
  dollarVars: true,
  keywords: {
    'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'do', 'done', 'in',
    'case', 'esac', 'function', 'return', 'exit', 'local', 'set', 'export',
    'echo', 'sudo', 'mkdir', 'rmdir', 'mv', 'ln', 'rm', 'cp', 'kill',
    'sleep', 'read', 'grep', 'find', 'awk', 'install', 'systemctl',
  },
);

const _js = _Lang(lineComment: '//', singleQuoteStrings: true, keywords: {
  'const', 'let', 'var', 'function', 'return', 'if', 'else', 'async',
  'await', 'new', 'export', 'default', 'import', 'from', 'null', 'true',
  'false',
});

const _ini = _Lang(lineComment: '#', keywords: {});
const _json = _Lang(keywords: {'true', 'false', 'null'});

const _langs = {
  'rust': _rust,
  'lua': _lua,
  'dart': _dart,
  'powershell': _ps,
  'ps1': _ps,
  'bash': _sh,
  'sh': _sh,
  'js': _js,
  'ini': _ini,
  'toml': _ini,
  'json': _json,
};

bool _isIdStart(String c) => RegExp(r'[A-Za-z_]').hasMatch(c);
bool _isId(String c) => RegExp(r'[A-Za-z0-9_]').hasMatch(c);
bool _isDigit(String c) => RegExp(r'[0-9]').hasMatch(c);

/// Highlights one line of [src] as [lang].
List<Span> highlightLine(String lang, String src) {
  final l = _langs[lang] ?? _ini;
  final out = <Span>[];
  void add(String t, Tok k) {
    if (t.isEmpty) return;
    if (out.isNotEmpty && out.last.tok == k && out.last.url == null) {
      out[out.length - 1] = Span(out.last.text + t, k);
    } else {
      out.add(Span(t, k));
    }
  }

  var i = 0;
  while (i < src.length) {
    final c = src[i];
    final rest = src.substring(i);

    if (l.lineComment != null && rest.startsWith(l.lineComment!)) {
      add(rest, Tok.comment);
      break;
    }
    if (c == '"' || (c == '\'' && l.singleQuoteStrings)) {
      var j = i + 1;
      while (j < src.length && src[j] != c) {
        if (src[j] == '\\') j++;
        j++;
      }
      j = (j + 1).clamp(0, src.length);
      add(src.substring(i, j), Tok.string);
      i = j;
      continue;
    }
    // Rust char literals ('x', '\n') — lifetimes ('a) stay punctuation.
    if (c == '\'' && lang == 'rust') {
      final m = RegExp(r"^'(\\.|[^\\'])'").firstMatch(rest);
      if (m != null) {
        add(m.group(0)!, Tok.string);
        i += m.group(0)!.length;
        continue;
      }
    }
    if (l.dollarVars && c == r'$') {
      var j = i + 1;
      if (j < src.length && src[j] == '{') {
        final close = src.indexOf('}', j);
        j = close == -1 ? src.length : close + 1;
      } else {
        while (j < src.length && (_isId(src[j]) || src[j] == ':')) {
          j++;
        }
      }
      add(src.substring(i, j), Tok.type);
      i = j;
      continue;
    }
    if (_isDigit(c)) {
      var j = i;
      while (j < src.length && RegExp(r'[0-9a-fA-FxX_.]').hasMatch(src[j])) {
        j++;
      }
      add(src.substring(i, j), Tok.string);
      i = j;
      continue;
    }
    if (_isIdStart(c)) {
      var j = i;
      while (j < src.length && _isId(src[j])) {
        j++;
      }
      final word = src.substring(i, j);
      final key = l.caseInsensitive ? word.toLowerCase() : word;
      final next = j < src.length ? src[j] : '';
      final prevDot = i > 0 && (src[i - 1] == '.' || src[i - 1] == ':');
      Tok k;
      if (l.keywords.contains(key) && !prevDot) {
        k = Tok.keyword;
      } else if (next == '(' || (next == '!' && lang == 'rust')) {
        k = Tok.fn;
      } else if (RegExp(r'^[A-Z]').hasMatch(word) && lang != 'sh') {
        k = Tok.type;
      } else {
        k = Tok.plain;
      }
      add(word, k);
      i = j;
      continue;
    }
    if (c == ' ' || c == '\t') {
      add(c, Tok.plain);
    } else {
      add(c, Tok.punct);
    }
    i++;
  }
  return out;
}

/// A framed code excerpt: a header naming the source file, then each line
/// highlighted behind a gutter bar. Leading blank lines are trimmed.
List<CodeLine> codeBlock(String lang, String path, String src) {
  final lines = src.trimRight().split('\n');
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  return [
    CodeLine([
      const Span('  ┌─ ', Tok.punct),
      Span(path, Tok.type),
    ]),
    for (final ln in lines)
      CodeLine([
        const Span('  │ ', Tok.punct),
        ...highlightLine(lang, ln),
        if (ln.isEmpty) const Span(' ', Tok.plain),
      ]),
    const CodeLine([Span('  └─', Tok.punct)]),
  ];
}
