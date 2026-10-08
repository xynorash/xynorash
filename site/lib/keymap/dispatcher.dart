/// Typed intents produced by the key dispatcher.
sealed class Intent2 {
  const Intent2();
}

class ScrollDown extends Intent2 { const ScrollDown(); }
class ScrollUp extends Intent2 { const ScrollUp(); }
class ScrollTop extends Intent2 { const ScrollTop(); }
class ScrollBottom extends Intent2 { const ScrollBottom(); }
class NextBuffer extends Intent2 { const NextBuffer(); }
class PrevBuffer extends Intent2 { const PrevBuffer(); }
class OpenWhichKey extends Intent2 { const OpenWhichKey(); }
class OpenFinder extends Intent2 { const OpenFinder(); }
class OpenCmdline extends Intent2 { const OpenCmdline(); }
class CloseOverlay extends Intent2 { const CloseOverlay(); }
class ConfirmSelection extends Intent2 { const ConfirmSelection(); }
class MoveSelectionDown extends Intent2 { const MoveSelectionDown(); }
class MoveSelectionUp extends Intent2 { const MoveSelectionUp(); }
class CycleTheme extends Intent2 { const CycleTheme(); }
class OpenOutline extends Intent2 { const OpenOutline(); }
class NextSection extends Intent2 { const NextSection(); }
class PrevSection extends Intent2 { const PrevSection(); }

enum UiMode { normal, whichkey, finder, outline, cmdline }

/// Turns logical key labels into intents; holds multi-key pending state
/// (`gg`, `[b`, `]b`, `[[`, `]]`). Pure logic — no widget dependencies.
class KeyDispatcher {
  String pending = '';

  Intent2? feed(String key, UiMode mode) {
    if (mode != UiMode.normal) {
      switch (key) {
        case 'Escape':
          return const CloseOverlay();
        case 'Enter':
          return const ConfirmSelection();
        case 'ArrowDown':
          return const MoveSelectionDown();
        case 'ArrowUp':
          return const MoveSelectionUp();
      }
      if (mode == UiMode.whichkey) {
        switch (key) {
          case 'f':
            return const OpenFinder();
          case 't':
            return const CycleTheme();
          case 'o':
            return const OpenOutline();
          case 'j':
            return const MoveSelectionDown();
          case 'k':
            return const MoveSelectionUp();
        }
      }
      if (mode == UiMode.outline) {
        switch (key) {
          case 'j':
            return const MoveSelectionDown();
          case 'k':
            return const MoveSelectionUp();
        }
      }
      return null;
    }

    // normal mode
    if (pending == 'g') {
      pending = '';
      return key == 'g' ? const ScrollTop() : null;
    }
    if (pending == '[') {
      pending = '';
      if (key == '[') return const PrevSection();
      return key == 'b' ? const PrevBuffer() : null;
    }
    if (pending == ']') {
      pending = '';
      if (key == ']') return const NextSection();
      return key == 'b' ? const NextBuffer() : null;
    }

    switch (key) {
      case 'j':
      case 'ArrowDown':
        return const ScrollDown();
      case 'k':
      case 'ArrowUp':
        return const ScrollUp();
      case 'G':
        return const ScrollBottom();
      case 'H':
        return const PrevBuffer();
      case 'L':
        return const NextBuffer();
      case ' ':
        return const OpenWhichKey();
      case ':':
        return const OpenCmdline();
      case 'g':
      case '[':
      case ']':
        pending = key;
        return null;
      default:
        pending = '';
        return null;
    }
  }
}
