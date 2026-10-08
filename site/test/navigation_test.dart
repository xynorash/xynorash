import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xnash_portfolio/data/projects.dart';
import 'package:xnash_portfolio/keymap/dispatcher.dart';
import 'package:xnash_portfolio/models/project.dart';
import 'package:xnash_portfolio/services/github_stats.dart';
import 'package:xnash_portfolio/state/app_state.dart';
import 'package:xnash_portfolio/theme/theme_controller.dart';
import 'package:xnash_portfolio/widgets/editor.dart';

AppState makeState() => AppState(
      theme: ThemeController(load: () => null, save: (_) {}),
      github: GithubStats(
          client: MockClient((_) async => http.Response('nope', 403))),
    );

void main() {
  test('every project buffer has a navigable outline', () {
    for (final b in kBuffers.where((b) => b.repo != null)) {
      expect(b.outline.length, greaterThanOrEqualTo(2), reason: b.fileName);
      expect(b.outline.first.line, lessThan(b.lines.length));
    }
  });

  test('sectionAt finds the enclosing heading', () {
    final b = kBuffers[1];
    final s = b.outline[2];
    expect(b.sectionAt(s.line)!.title, s.title);
    expect(b.sectionAt(s.line + 1)!.title, s.title);
    expect(b.sectionAt(0), isNull);
  });

  test(']] and [[ jump between sections', () {
    final s = makeState()..openBuffer(1);
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
    final s = makeState()..openBuffer(1);
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
}
