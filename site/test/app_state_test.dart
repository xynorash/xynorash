import 'package:flutter_test/flutter_test.dart';
import 'package:xnash_portfolio/data/projects.dart';
import 'package:xnash_portfolio/keymap/dispatcher.dart';

import 'support.dart';

void main() {
  test('opening pages adds tabs; ]b / [b cycle the open tabs with wrap', () {
    final s = makeState();
    expect(s.openBuffers, [0]);
    s.openBuffer(idxOf('heaplens/README.md'));
    s.openBuffer(idxOf('xynovim/README.md'));
    expect(s.openBuffers.length, 3);
    s.handleKey(']');
    s.handleKey('b');
    expect(s.bufferIndex, 0); // wrapped to the welcome tab
    s.handleKey('H');
    expect(s.bufferIndex, idxOf('xynovim/README.md'));
    s.handleKey('H');
    expect(s.bufferIndex, idxOf('heaplens/README.md'));
  });

  test('opening an already-open page focuses it instead of duplicating', () {
    final s = makeState();
    final i = idxOf('heaplens/README.md');
    s.openBuffer(i);
    s.openBuffer(0);
    s.openBuffer(i);
    expect(s.openBuffers.where((b) => b == i).length, 1);
  });

  test('closing tabs moves focus to the neighbour; last tab -> welcome', () {
    final s = makeState();
    final a = idxOf('heaplens/README.md');
    final b = idxOf('xynovim/README.md');
    s.openBuffer(a);
    s.openBuffer(b);
    s.closeBuffer(b);
    expect(s.bufferIndex, a);
    s.closeBuffer(a);
    expect(s.bufferIndex, 0);
    s.closeBuffer(0);
    expect(s.openBuffers, [0]); // never zero tabs
    expect(s.bufferIndex, 0);
  });

  test('opening a page reveals it in the explorer; dirs toggle', () {
    final s = makeState();
    final nested = kBuffers.firstWhere(
        (b) => b.fullPath.split('/').length >= 3 && b.project == 'heaplens');
    s.openBuffer(kBuffers.indexOf(nested));
    final parts = nested.fullPath.split('/');
    for (var d = 1; d < parts.length; d++) {
      expect(s.expandedDirs, contains(parts.sublist(0, d).join('/')));
    }
    s.toggleDir('heaplens');
    expect(s.expandedDirs, isNot(contains('heaplens')));
    s.toggleDir('heaplens');
    expect(s.expandedDirs, contains('heaplens'));
  });

  test('space f opens the finder; typing filters by name then path', () {
    final s = makeState();
    s.handleKey(' ');
    expect(s.mode, UiMode.whichkey);
    s.handleKey('f');
    expect(s.mode, UiMode.finder);
    for (final ch in 'xynov'.split('')) {
      s.handleKey(ch);
    }
    expect(s.finderQuery, 'xynov');
    expect(s.finderResults, isNotEmpty);
    expect(kBuffers[s.finderResults.first].project, 'xynovim');
    s.handleKey('Enter');
    expect(kBuffers[s.bufferIndex].project, 'xynovim');
    expect(s.mode, UiMode.normal);
  });

  test('finder prefers file-name matches over directory-only matches', () {
    final s = makeState();
    s.finderType('readme');
    final first = kBuffers[s.finderResults.first];
    expect(first.fileName.toLowerCase(), 'readme.md');
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

  test('cmdline: theme, :e, :bd, unknown command, :q easter egg', () {
    final s = makeState();
    s.runCommand('theme hackerman');
    expect(s.themeController.name, 'hackerman');
    s.runCommand('theme nope');
    expect(s.message, contains('E185'));
    s.runCommand('e xynovim/README');
    expect(s.buffer.fullPath, 'xynovim/README.md');
    s.runCommand('bd');
    expect(s.bufferIndex, 0);
    s.runCommand('e zzzzqq');
    expect(s.message, contains('E344'));
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
    final s = makeState()..openBuffer(idxOf('heaplens/README.md'));
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

  test('whichkey digits jump to the nth open tab; toggles work', () {
    final s = makeState();
    s.openBuffer(idxOf('heaplens/README.md'));
    s.openBuffer(idxOf('xynovim/README.md'));
    s.openWhichKey();
    s.handleKey('2');
    expect(s.bufferIndex, idxOf('heaplens/README.md'));
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
    final repos = kBuffers.where((b) => b.repo != null);
    expect(repos.length, projectNames.length);
    for (final b in repos) {
      expect(s.stats[b.repo], isNotNull);
      expect(s.stats[b.repo]!.stars, b.fallbackStars);
    }
  });
}
