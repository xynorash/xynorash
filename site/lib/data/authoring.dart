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
