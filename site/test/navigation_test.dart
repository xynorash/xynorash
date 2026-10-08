import 'package:flutter_test/flutter_test.dart';
import 'package:xnash_portfolio/data/projects.dart';
import 'package:xnash_portfolio/keymap/dispatcher.dart';
import 'package:xnash_portfolio/models/project.dart';
import 'package:xnash_portfolio/widgets/editor.dart';

import 'support.dart';

void main() {
  test('every project README has a navigable outline', () {
    for (final b in kBuffers.where((b) => b.repo != null)) {
      expect(b.outline.length, greaterThanOrEqualTo(2), reason: b.fullPath);
      expect(b.outline.first.line, lessThan(b.lines.length));
    }
  });

  test('sectionAt finds the enclosing heading', () {
    final b = kBuffers[idxOf('heaplens/README.md')];
    final s = b.outline[2];
    expect(b.sectionAt(s.line)!.title, s.title);
    expect(b.sectionAt(s.line + 1)!.title, s.title);
    expect(b.sectionAt(0), isNull);
  });

  test(']] and [[ jump between sections', () {
    final s = makeState()..openBuffer(idxOf('heaplens/README.md'));
    final o = s.buffer.outline;
    s.handleKey(']');
    s.handleKey(']');
    expect(s.scrollLines, o[0].line);
    s.handleKey(']');
    s.handleKey(']');
    expect(s.scrollLines, o[1].line);
    s.handleKey('[');
    s.handleKey('[');
    expect(s.scrollLines, o[0].line);
  });

  test('space o opens the outline; enter jumps; esc closes', () {
    final s = makeState()..openBuffer(idxOf('heaplens/README.md'));
    s.handleKey(' ');
    s.handleKey('o');
    expect(s.mode, UiMode.outline);
    s.handleKey('j');
    s.handleKey('j');
    s.handleKey('Enter');
    expect(s.mode, UiMode.normal);
    expect(s.scrollLines, s.buffer.outline[2].line);
    s.handleKey(' ');
    s.handleKey('o');
    s.handleKey('Escape');
    expect(s.mode, UiMode.normal);
  });

  test('wrapSpans keeps text, styles, and respects the column limit', () {
    final line = [
      const Span('// ', Tok.comment),
      const Span('alpha beta gamma delta epsilon zeta eta theta', Tok.type),
    ];
    final rows = wrapSpans(line, 20);
    expect(rows.length, greaterThan(2));
    for (final r in rows) {
      expect(r.map((s) => s.text).join().length, lessThanOrEqualTo(20));
    }
    final joined = rows.map((r) => r.map((s) => s.text).join()).join(' ');
    expect(joined.replaceAll(RegExp(r'\s+'), ' '),
        '// alpha beta gamma delta epsilon zeta eta theta');
    expect(wrapSpans(line, 200).length, 1);
  });

  test('wrapped code lines keep their gutter bar and extra indent', () {
    final line = [
      const Span('  │ ', Tok.punct),
      const Span('    let value = compute_something(argument_one, argument_two);',
          Tok.plain),
    ];
    final rows = wrapSpans(line, 40);
    expect(rows.length, greaterThan(1));
    for (final r in rows) {
      final t = r.map((x) => x.text).join();
      expect(t.startsWith('  │ '), isTrue, reason: t);
      expect(t.length, lessThanOrEqualTo(40));
    }
    // continuation rows are indented past the original code indent
    final cont = rows[1].map((x) => x.text).join();
    expect(cont.substring(4).startsWith('      '), isTrue);
  });
}
