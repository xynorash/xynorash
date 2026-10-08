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
  final String fileName;
  final String icon;
  final String filetype;
  final String? repo;
  final int fallbackStars;
  final String fallbackPushed;
  final List<CodeLine> lines;

  const Buffer({
    required this.id,
    required this.fileName,
    required this.icon,
    required this.filetype,
    this.repo,
    this.fallbackStars = 0,
    this.fallbackPushed = '',
    required this.lines,
  });
}
