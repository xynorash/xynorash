import 'package:flutter/foundation.dart';

import '../data/projects.dart';
import '../keymap/dispatcher.dart';
import '../keymap/fuzzy.dart';
import '../models/project.dart';
import '../services/github_stats.dart';
import 'file_tree.dart';
import '../theme/theme_controller.dart';

class AppState extends ChangeNotifier {
  final ThemeController themeController;
  final GithubStats _github;
  final KeyDispatcher dispatcher = KeyDispatcher();

  int bufferIndex = 0;

  /// Indices (into [kBuffers]) of the open buffers, in the order opened —
  /// these are the tabs.
  final List<int> openBuffers = [0];

  /// Explorer directories currently expanded (full paths).
  final Set<String> expandedDirs = {};

  /// The explorer tree, built once from the page paths.
  late final TreeNode tree = buildTree(kBuffers);

  int scrollLines = 0;
  UiMode mode = UiMode.normal;
  bool explorerOpen = false;

  String finderQuery = '';
  int finderSelection = 0;
  int outlineSelection = 0;

  String cmdline = '';
  String message = '';

  /// How many finder results are shown (and selectable) at once.
  static const int finderRows = 12;

  final Map<String, RepoStats> stats = {};

  AppState({required ThemeController theme, GithubStats? github})
      : themeController = theme,
        _github = github ?? GithubStats() {
    themeController.addListener(notifyListeners);
  }

  Buffer get buffer => kBuffers[bufferIndex];

  /// Fuzzy matches for the finder, best first. The file name is matched
  /// first (so "ring" finds ring.rs before anything whose directory merely
  /// contains those letters), then the whole path as a weaker fallback.
  List<int> get finderResults {
    if (finderQuery.isEmpty) {
      return List.generate(kBuffers.length, (i) => i);
    }
    final scored = <(int, int)>[];
    for (var i = 0; i < kBuffers.length; i++) {
      final b = kBuffers[i];
      final byName = fuzzyScore(finderQuery, b.fileName);
      final byPath = fuzzyScore(finderQuery, b.fullPath);
      final score = byName ?? (byPath == null ? null : 1000 + byPath);
      if (score != null) scored.add((score, i));
    }
    scored.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    return scored.map((s) => s.$2).toList();
  }

  /// Opens kBuffers[i] as a tab (or focuses it), reveals it in the explorer.
  void openBuffer(int i) {
    bufferIndex = i % kBuffers.length;
    if (!openBuffers.contains(bufferIndex)) openBuffers.add(bufferIndex);
    expandedDirs.addAll(ancestorsOf(buffer.fullPath));
    scrollLines = 0;
    mode = UiMode.normal;
    message = '';
    notifyListeners();
  }

  /// Opens a project's README and expands its directory.
  void openProject(String name) {
    final i = kBuffers.indexWhere((b) => b.fullPath == '$name/README.md');
    if (i < 0) return;
    expandedDirs.add(name);
    openBuffer(i);
  }

  /// Closes the tab for kBuffers[i]; focus moves to the neighbouring tab,
  /// and closing the last tab returns to the welcome page.
  void closeBuffer(int i) {
    final pos = openBuffers.indexOf(i);
    if (pos < 0) return;
    openBuffers.removeAt(pos);
    if (openBuffers.isEmpty) openBuffers.add(0);
    if (bufferIndex == i) {
      bufferIndex = openBuffers[(pos - 1).clamp(0, openBuffers.length - 1)];
      scrollLines = 0;
    }
    mode = UiMode.normal;
    notifyListeners();
  }

  void toggleDir(String path) {
    if (!expandedDirs.add(path)) expandedDirs.remove(path);
    notifyListeners();
  }

  /// Cycles through the open tabs.
  void _cycleTabs(int dir) {
    final pos = openBuffers.indexOf(bufferIndex);
    final n = openBuffers.length;
    openBuffer(openBuffers[((pos < 0 ? 0 : pos) + dir + n) % n]);
  }

  /// Called by the editor when the user scrolls with wheel/touch, so the
  /// statusline position follows what is actually on screen.
  void syncScroll(int line) {
    if (line == scrollLines) return;
    scrollLines = line;
    notifyListeners();
  }

  void openFinder() {
    mode = UiMode.finder;
    finderQuery = '';
    finderSelection = 0;
    notifyListeners();
  }

  void openOutline() {
    final cur = buffer.sectionAt(scrollLines);
    outlineSelection = cur == null ? 0 : buffer.outline.indexOf(cur);
    mode = UiMode.outline;
    notifyListeners();
  }

  /// Jumps to the section at [index] in the current buffer's outline.
  void gotoSection(int index) {
    final o = buffer.outline;
    if (o.isEmpty) return closeOverlay();
    scrollLines = o[index.clamp(0, o.length - 1)].line;
    mode = UiMode.normal;
    notifyListeners();
  }

  void _stepSection(int dir) {
    final o = buffer.outline;
    if (o.isEmpty) return;
    final target = dir > 0
        ? o.where((s) => s.line > scrollLines).firstOrNull
        : o.where((s) => s.line < scrollLines).lastOrNull;
    scrollLines = (target ?? (dir > 0 ? o.last : o.first)).line;
  }

  void openWhichKey() {
    mode = UiMode.whichkey;
    notifyListeners();
  }

  void openCmdline() {
    mode = UiMode.cmdline;
    cmdline = '';
    message = '';
    notifyListeners();
  }

  void closeOverlay() {
    mode = UiMode.normal;
    notifyListeners();
  }

  void toggleExplorer() {
    explorerOpen = !explorerOpen;
    mode = UiMode.normal;
    notifyListeners();
  }

  void cycleTheme() {
    themeController.cycle();
    mode = UiMode.normal;
  }

  void finderType(String q) {
    finderQuery = q;
    finderSelection = 0;
    notifyListeners();
  }

  void confirmFinder() {
    final results = finderResults.take(finderRows).toList();
    if (results.isEmpty) {
      closeOverlay();
      return;
    }
    openBuffer(results[finderSelection.clamp(0, results.length - 1)]);
  }

  void runCommand(String cmd) {
    final trimmed = cmd.trim();
    if (trimmed == 'q' || trimmed == 'q!' || trimmed == 'wq') {
      message = trimmed == 'wq'
          ? 'E492: Not an editor command: wq (nothing here needs saving)'
          : 'E37: No write since last change (this is a portfolio, you live here now)';
    } else if (trimmed == 'bd' || trimmed == 'bd!' || trimmed == 'bdelete') {
      closeBuffer(bufferIndex);
      message = '';
    } else if (trimmed == 'e' || trimmed.startsWith('e ')) {
      // :e <fuzzy path> opens the best match, like Telescope would.
      final q = trimmed.length > 1 ? trimmed.substring(2).trim() : '';
      finderQuery = q;
      final r = q.isEmpty ? <int>[] : finderResults;
      finderQuery = '';
      if (r.isEmpty) {
        message = q.isEmpty
            ? 'E32: No file name'
            : 'E344: Can\'t find file "$q" in path';
      } else {
        openBuffer(r.first);
        message = '';
      }
    } else if (trimmed.startsWith('theme')) {
      final name = trimmed.length > 5 ? trimmed.substring(5).trim() : '';
      if (!themeController.setTheme(name)) {
        message = 'E185: Cannot find color scheme \'$name\'';
      } else {
        message = '';
      }
    } else if (trimmed.isNotEmpty) {
      message = 'E492: Not an editor command: $trimmed';
    }
    mode = UiMode.normal;
    cmdline = '';
    notifyListeners();
  }

  void handleKey(String key) {
    // Text entry modes consume printable characters directly.
    if (mode == UiMode.cmdline) {
      switch (key) {
        case 'Escape':
          closeOverlay();
        case 'Enter':
          runCommand(cmdline);
        case 'Backspace':
          if (cmdline.isEmpty) {
            closeOverlay();
          } else {
            cmdline = cmdline.substring(0, cmdline.length - 1);
            notifyListeners();
          }
        default:
          if (key.length == 1) {
            cmdline += key;
            notifyListeners();
          }
      }
      return;
    }
    if (mode == UiMode.finder) {
      if (key == 'Backspace') {
        if (finderQuery.isNotEmpty) {
          finderType(finderQuery.substring(0, finderQuery.length - 1));
        }
        return;
      }
      if (key.length == 1) {
        finderType(finderQuery + key);
        return;
      }
    }
    if (mode == UiMode.whichkey) {
      final digit = int.tryParse(key);
      if (digit != null && digit >= 1 && digit <= openBuffers.length) {
        openBuffer(openBuffers[digit - 1]);
        return;
      }
      if (key == 'o') return openOutline();
      if (key == 'e') {
        toggleExplorer();
        return;
      }
      if (key == 'q') {
        runCommand('q');
        return;
      }
    }

    // Dashboard shortcuts: on the welcome buffer, digits open projects,
    // `a` opens about, `t` cycles the theme (mirrors the dashboard entries).
    if (mode == UiMode.normal &&
        buffer.id == 'welcome' &&
        dispatcher.pending.isEmpty) {
      final digit = int.tryParse(key);
      final names = projectNames;
      if (digit != null && digit >= 1 && digit <= names.length) {
        return openProject(names[digit - 1]);
      }
      if (key == 'a') return openBuffer(kBuffers.length - 1);
      if (key == 't') return cycleTheme();
    }

    if (mode == UiMode.outline) {
      // Outline overlay: Enter jumps, arrows/jk move (via the dispatcher).
      if (key == 'Enter') return gotoSection(outlineSelection);
    }

    final intent = dispatcher.feed(key, mode);
    if (intent == null) {
      notifyListeners(); // pending keys may have changed; cmdline hint updates
      return;
    }
    switch (intent) {
      case ScrollDown():
        scrollLines = (scrollLines + 1).clamp(0, buffer.lines.length - 1);
      case ScrollUp():
        scrollLines = (scrollLines - 1).clamp(0, buffer.lines.length - 1);
      case ScrollTop():
        scrollLines = 0;
      case ScrollBottom():
        scrollLines = buffer.lines.length - 1;
      case NextBuffer():
        return _cycleTabs(1);
      case PrevBuffer():
        return _cycleTabs(-1);
      case OpenWhichKey():
        return openWhichKey();
      case OpenFinder():
        return openFinder();
      case OpenCmdline():
        return openCmdline();
      case CloseOverlay():
        return closeOverlay();
      case ConfirmSelection():
        if (mode == UiMode.finder) return confirmFinder();
        return closeOverlay();
      case MoveSelectionDown():
        if (mode == UiMode.outline) {
          final n = buffer.outline.length;
          if (n > 0) outlineSelection = (outlineSelection + 1) % n;
        } else {
          final n = finderResults.take(finderRows).length;
          if (n > 0) finderSelection = (finderSelection + 1) % n;
        }
      case MoveSelectionUp():
        if (mode == UiMode.outline) {
          final n = buffer.outline.length;
          if (n > 0) outlineSelection = (outlineSelection - 1 + n) % n;
        } else {
          final n = finderResults.take(finderRows).length;
          if (n > 0) finderSelection = (finderSelection - 1 + n) % n;
        }
      case OpenOutline():
        return openOutline();
      case NextSection():
        _stepSection(1);
      case PrevSection():
        _stepSection(-1);
      case CycleTheme():
        return cycleTheme();
    }
    notifyListeners();
  }

  Future<void> loadStats() async {
    final repos = kBuffers.where((b) => b.repo != null).toList();
    final results = await Future.wait(repos.map((b) =>
        _github.fetch(b.repo!, RepoStats(b.fallbackStars, b.fallbackPushed))));
    for (var i = 0; i < repos.length; i++) {
      stats[repos[i].repo!] = results[i];
    }
    notifyListeners();
  }
}
