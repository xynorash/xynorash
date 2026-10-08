import 'package:flutter_test/flutter_test.dart';
import 'package:xnash_portfolio/data/highlight.dart';
import 'package:xnash_portfolio/models/project.dart';

String join(List<Span> s) => s.map((x) => x.text).join();
Tok? tokOf(List<Span> s, String text) =>
    s.where((x) => x.text == text).map((x) => x.tok).firstOrNull;

void main() {
  test('rust: keywords, types, calls, comments, strings', () {
    const src = 'pub fn push(&self, ev: AllocEvent) -> bool { // hot';
    final s = highlightLine('rust', src);
    expect(join(s), src);
    expect(tokOf(s, 'pub'), Tok.keyword);
    expect(tokOf(s, 'push'), Tok.fn);
    expect(tokOf(s, 'AllocEvent'), Tok.type);
    expect(s.last.tok, Tok.comment);
  });

  test('comment markers inside strings do not start a comment', () {
    final s = highlightLine('rust', 'let u = "http://x"; // real');
    expect(tokOf(s, '"http://x"'), Tok.string);
    expect(s.last.text, '// real');
    expect(s.last.tok, Tok.comment);
  });

  test('rust lifetimes are not strings, char literals are', () {
    final life = highlightLine('rust', "fn f<'a>(x: &'a str)");
    expect(life.any((x) => x.tok == Tok.string), isFalse);
    final ch = highlightLine('rust', "let c = 'x';");
    expect(ch.any((x) => x.tok == Tok.string && x.text == "'x'"), isTrue);
  });

  test('powershell: variables, case-insensitive keywords', () {
    final s = highlightLine('powershell', r'Foreach ($x in $env:PATH) {');
    expect(tokOf(s, 'Foreach'), Tok.keyword);
    expect(tokOf(s, r'$x'), Tok.type);
    expect(tokOf(s, r'$env:PATH'), Tok.type);
  });

  test('lua uses -- comments and single-quoted strings', () {
    final s = highlightLine('lua', "local a = 'x' -- why");
    expect(tokOf(s, 'local'), Tok.keyword);
    expect(tokOf(s, "'x'"), Tok.string);
    expect(s.last.tok, Tok.comment);
  });

  test('every line round-trips exactly (highlighting never alters text)',
      () {
    const src = '''
let _g = guard::ScopedGuard::enter();
if next == self.head.load(Ordering::Acquire) { return false; }
self.tail.store(next, Ordering::Release);''';
    for (final line in src.split('\n')) {
      expect(join(highlightLine('rust', line)), line);
    }
  });

  test('codeBlock frames a snippet with header, gutter, footer', () {
    final b = codeBlock('lua', 'a/b.lua', '\nlocal x = 1\n\nreturn x\n');
    expect(join(b.first.spans), '  ┌─ a/b.lua');
    expect(join(b.last.spans), '  └─');
    expect(b.length, 2 + 3); // leading blank trimmed, interior blank kept
    expect(b[1].spans.first.text, '  │ ');
    for (final l in b) {
      for (final s in l.spans) {
        expect(s.text, isNotEmpty);
      }
    }
  });
}
