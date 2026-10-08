import 'package:flutter/foundation.dart';

import '../data/projects.dart';
import '../keymap/dispatcher.dart';
import '../keymap/fuzzy.dart';
import '../models/project.dart';
import '../services/github_stats.dart';
import '../theme/theme_controller.dart';

class AppState extends ChangeNotifier {
  final ThemeController themeController;
  final GithubStats _github;
  final KeyDispatcher dispatcher = KeyDispatcher();

  int bufferIndex = 0;
  int scrollLines = 0;
  UiMode mode = UiMode.normal;
  bool explorerOpen = false;

  String finderQuery = '';
  int finderSelection = 0;
  int outlineSelection = 0;

  String cmdline = '';
  String message = '';

  final Map<String, RepoStats> stats = {};

  AppState({required ThemeController theme, GithubStats? github})
      : themeController = theme,
        _github = github ?? GithubStats() {
    themeController.addListener(notifyListeners);
  }

  Buffer get buffer => kBuffers[bufferIndex];

  List<int> get finderResults =>
      fuzzyRank(finderQuery, kBuffers.map((b) => b.fileName).toList());

  void openBuffer(int i) {
    bufferIndex = i % kBuffers.length;
    scrollLines = 0;
    mode = UiMode.normal;
    message = '';
    notifyListeners();
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
    final results = finderResults;
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
      if (digit != null && digit >= 1 && digit <= kBuffers.length) {
        openBuffer(digit - 1);
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
    if (mode == UiMode.normal && bufferIndex == 0 && dispatcher.pending.isEmpty) {
      final digit = int.tryParse(key);
      if (digit != null && digit >= 1 && digit < kBuffers.length - 1) {
        return openBuffer(digit);
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
        return openBuffer(bufferIndex + 1);
      case PrevBuffer():
        return openBuffer(bufferIndex - 1 + kBuffers.length);
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
          final n = finderResults.length;
          if (n > 0) finderSelection = (finderSelection + 1) % n;
        }
      case MoveSelectionUp():
        if (mode == UiMode.outline) {
          final n = buffer.outline.length;
          if (n > 0) outlineSelection = (outlineSelection - 1 + n) % n;
        } else {
          final n = finderResults.length;
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
