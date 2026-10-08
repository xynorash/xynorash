/// Token kinds used to fake syntax highlighting in the editor pane.
enum Tok { comment, keyword, string, fn, type, plain, punct, heading, link }

class Span {
  final String text;
  final Tok tok;
  final String? url;
  const Span(this.text, this.tok, {this.url});
}

class CodeLine {
  final List<Span> spans;
  const CodeLine(this.spans);
}

/// One "open file" in the fake editor. `repo == null` for plain md pages.
class Buffer {
  final String id;

  /// Repo-relative path including the project directory, e.g.
  /// `heaplens/crates/heaplens-alloc/src/ring.rs`. Drives the explorer tree.
  /// Defaults to [fileName] for top-level pages (welcome.md, about.md).
  final String path;
  final String fileName;
  final String icon;
  final String filetype;
  final String? repo;

  /// One-line description shown on the dashboard next to the file name.
  final String summary;

  /// Private/internal project: listed like a repo but has no public GitHub
  /// stats line and no link.
  final bool internal;
  final int fallbackStars;
  final String fallbackPushed;
  final List<CodeLine> lines;

  const Buffer({
    required this.id,
    this.path = '',
    required this.fileName,
    required this.icon,
    required this.filetype,
    this.repo,
    this.summary = '',
    this.internal = false,
    this.fallbackStars = 0,
    this.fallbackPushed = '',
    required this.lines,
  });

  /// Full path, falling back to the bare file name.
  String get fullPath => path.isEmpty ? fileName : path;

  /// Top-level directory (the project), or null for top-level pages.
  String? get project {
    final i = fullPath.indexOf('/');
    return i < 0 ? null : fullPath.substring(0, i);
  }

  /// Section headings (`# title` lines) as (line index, title), in order.
  /// Powers the outline overlay, `]]` / `[[` jumps and the statusline crumb.
  List<Section> get outline => [
    for (var i = 0; i < lines.length; i++)
      if (lines[i].spans.isNotEmpty &&
          lines[i].spans.first.tok == Tok.heading &&
          lines[i].spans.first.text.startsWith('# '))
        Section(i, lines[i].spans.first.text.substring(2)),
      ];

  /// The section containing [line], or null above the first heading.
  Section? sectionAt(int line) {
    Section? cur;
    for (final s in outline) {
      if (s.line > line) break;
      cur = s;
    }
    return cur;
  }
}

class Section {
  final int line;
  final String title;
  const Section(this.line, this.title);
}
