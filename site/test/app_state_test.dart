import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xnash_portfolio/data/projects.dart';
import 'package:xnash_portfolio/keymap/dispatcher.dart';
import 'package:xnash_portfolio/services/github_stats.dart';
import 'package:xnash_portfolio/state/app_state.dart';
import 'package:xnash_portfolio/theme/theme_controller.dart';

AppState makeState() => AppState(
      theme: ThemeController(load: () => null, save: (_) {}),
      github: GithubStats(
          client: MockClient((_) async => http.Response('nope', 403))),
    );

void main() {
  test(']b advances buffer with wraparound', () {
    final s = makeState();
    expect(s.bufferIndex, 0);
    s.handleKey(']');
    s.handleKey('b');
    expect(s.bufferIndex, 1);
    for (var i = 0; i < 5; i++) {
      s.handleKey('L');
    }
    expect(s.bufferIndex, 0); // wrapped
    s.handleKey('H');
    expect(s.bufferIndex, kBuffers.length - 1);
  });

  test('space then f opens finder; typing filters; enter opens buffer', () {
    final s = makeState();
    s.handleKey(' ');
    expect(s.mode, UiMode.whichkey);
    s.handleKey('f');
    expect(s.mode, UiMode.finder);
    for (final ch in 'xynov'.split('')) {
      s.handleKey(ch);
    }
    expect(s.finderQuery, 'xynov');
    expect(s.finderResults, [2]);
    s.handleKey('Enter');
    expect(s.bufferIndex, 2);
    expect(s.mode, UiMode.normal);
  });

  test('backspace edits finder query, escape closes', () {
    final s = makeState();
    s.openFinder();
    s.handleKey('x');
    s.handleKey('Backspace');
    expect(s.finderQuery, '');
    s.handleKey('Escape');
    expect(s.mode, UiMode.normal);
  });

  test('cmdline: theme switch, unknown command, :q easter egg', () {
    final s = makeState();
    s.runCommand('theme hackerman');
    expect(s.themeController.name, 'hackerman');
    s.runCommand('theme nope');
    expect(s.message, contains('E185'));
    s.runCommand('wq');
    expect(s.message, contains('E492'));
    s.runCommand('q');
    expect(s.message, contains('E37'));
  });

  test('cmdline typing via keys', () {
    final s = makeState();
    s.handleKey(':');
    expect(s.mode, UiMode.cmdline);
    for (final ch in 'theme aether'.split('')) {
      s.handleKey(ch);
    }
    s.handleKey('Enter');
    expect(s.mode, UiMode.normal);
    expect(s.themeController.name, 'aether');
  });

  test('scroll intents clamp', () {
    final s = makeState();
    s.handleKey('k');
    expect(s.scrollLines, 0);
    s.handleKey('G');
    expect(s.scrollLines, s.buffer.lines.length - 1);
    s.handleKey('j');
    expect(s.scrollLines, s.buffer.lines.length - 1);
    s.handleKey('g');
    s.handleKey('g');
    expect(s.scrollLines, 0);
  });

  test('whichkey digits and toggles', () {
    final s = makeState();
    s.openWhichKey();
    s.handleKey('3');
    expect(s.bufferIndex, 2);
    expect(s.mode, UiMode.normal);
    s.openWhichKey();
    s.handleKey('t');
    expect(s.themeController.name, isNot('aether'));
    final was = s.explorerOpen;
    s.openWhichKey();
    s.handleKey('e');
    expect(s.explorerOpen, !was);
  });

  test('loadStats fills all repos with fallbacks on failure', () async {
    final s = makeState();
    await s.loadStats();
    for (final b in kBuffers.where((b) => b.repo != null)) {
      expect(s.stats[b.repo], isNotNull);
      expect(s.stats[b.repo]!.stars, b.fallbackStars);
    }
  });
}
