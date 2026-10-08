import '../models/project.dart';
import 'highlight.dart';

export 'highlight.dart' show codeBlock;

// Authoring helpers for project buffers. `p` is the filetype's line-comment
// leader (`//`, `--`, `#`).

const CodeLine blank = CodeLine([Span(' ', Tok.plain)]);

CodeLine cm(String p, String t) => CodeLine([Span('$p $t', Tok.comment)]);
CodeLine plain(String t) => CodeLine([Span(t, Tok.plain)]);
CodeLine heading(String t) => CodeLine([Span(t, Tok.heading)]);
CodeLine link(String label, String url) =>
    CodeLine([Span(label, Tok.link, url: url)]);

CodeLine kv(String k, String v) => CodeLine([
      Span(k, Tok.keyword),
      const Span(' = ', Tok.punct),
      Span('"$v"', Tok.string),
      const Span(';', Tok.punct),
    ]);

CodeLine decl(String kw, String name, [String trail = '']) => CodeLine([
      Span(kw, Tok.keyword),
      const Span(' ', Tok.plain),
      Span(name, Tok.fn),
      if (trail.isNotEmpty) Span(trail, Tok.punct),
    ]);

CodeLine item(String p, String head, String rest) => CodeLine([
      Span('$p ', Tok.comment),
      Span(head, Tok.type),
      Span(' — $rest', Tok.comment),
    ]);

/// Word-wraps [text] to [width] columns.
List<String> wrapText(String text, int width) {
  final out = <String>[];
  var cur = '';
  for (final w in text.split(' ')) {
    if (cur.isEmpty) {
      cur = w;
    } else if (cur.length + 1 + w.length <= width) {
      cur = '$cur $w';
    } else {
      out.add(cur);
      cur = w;
    }
  }
  if (cur.isNotEmpty) out.add(cur);
  return out;
}

/// A wrapped comment paragraph.
List<CodeLine> para(String p, String text, {int width = 62}) =>
    [for (final l in wrapText(text, width)) cm(p, l)];

/// A wrapped "head — rest" bullet: highlighted head, hanging indent.
List<CodeLine> pt(String p, String head, String rest, {int width = 62}) {
  final ls = wrapText('$head — $rest', width);
  return [
    CodeLine([
      Span('$p ', Tok.comment),
      Span(head, Tok.type),
      Span(ls.first.substring(head.length), Tok.comment),
    ]),
    for (final l in ls.skip(1)) cm(p, '  $l'),
  ];
}

/// A blank line followed by a section heading (these feed the outline).
List<CodeLine> sec(String title) => [blank, heading('# $title')];

/// A blank line before a code excerpt.
List<CodeLine> code(String lang, String path, String src) =>
    [blank, ...codeBlock(lang, path, src), blank];

// ── Pages ────────────────────────────────────────────────────────────────

/// Nerd-font icon for a file name.
String iconFor(String fileName) {
  final n = fileName.toLowerCase();
  final ext = n.contains('.') ? n.substring(n.lastIndexOf('.') + 1) : '';
  if (n == 'readme.md') return '\u{f48a}';
  if (n == 'cargo.toml' || n == 'cargo.lock') return '\u{e7a8}';
  if (n == 'install.sh') return '\u{f489}';
  return switch (ext) {
    'rs' => '\u{e7a8}',
    'lua' => '\u{e620}',
    'dart' => '\u{e798}',
    'ps1' || 'psm1' => '\u{ebc7}',
    'sh' || 'bash' => '\u{f489}',
    'py' => '\u{e73c}',
    'js' || 'mjs' => '\u{e74e}',
    'json' || 'jsonc' => '\u{e60b}',
    'toml' || 'ini' || 'conf' || 'cfg' => '\u{e615}',
    'yaml' || 'yml' => '\u{e6a8}',
    'md' => '\u{f48a}',
    'csv' => '\u{f1c3}',
    'txt' => '\u{f15c}',
    'service' => '\u{f013}',
    _ => '\u{f15b}',
  };
}

/// Editor filetype for a file name.
String filetypeFor(String fileName) {
  final n = fileName.toLowerCase();
  final ext = n.contains('.') ? n.substring(n.lastIndexOf('.') + 1) : '';
  return switch (ext) {
    'rs' => 'rust',
    'lua' => 'lua',
    'dart' => 'dart',
    'ps1' || 'psm1' => 'powershell',
    'sh' || 'bash' => 'bash',
    'py' => 'python',
    'js' || 'mjs' => 'js',
    'json' || 'jsonc' => 'json',
    'toml' || 'ini' || 'conf' || 'cfg' || 'service' => 'ini',
    'md' => 'markdown',
    _ => 'text',
  };
}

/// Builds a page in the project tree. [path] is the repo-relative path with
/// the project directory first (`heaplens/crates/heaplens-alloc/src/ring.rs`);
/// id, file name, icon and filetype are derived from it.
Buffer makePage(
  String path, {
  required List<CodeLine> lines,
  String summary = '',
  String? repo,
  int fallbackStars = 0,
  String fallbackPushed = '',
}) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  return Buffer(
    id: path,
    path: path,
    fileName: name,
    icon: iconFor(name),
    filetype: filetypeFor(name),
    repo: repo,
    summary: summary,
    fallbackStars: fallbackStars,
    fallbackPushed: fallbackPushed,
    lines: lines,
  );
}

/// A wrapped plain-text paragraph (for markdown pages, where prose is not
/// shown as comments).
List<CodeLine> text(String t, {int width = 64}) =>
    [for (final l in wrapText(t, width)) plain(l)];

/// A wrapped markdown-style bullet: highlighted head, hanging indent.
List<CodeLine> bullet(String head, String rest, {int width = 64}) {
  final ls = wrapText('$head — $rest', width - 2);
  return [
    CodeLine([
      const Span('- ', Tok.punct),
      Span(head, Tok.type),
      Span(ls.first.substring(head.length), Tok.plain),
    ]),
    for (final l in ls.skip(1)) plain('  $l'),
  ];
}
