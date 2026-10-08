import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'keymap/dispatcher.dart';
import 'services/github_stats.dart';
import 'state/app_state.dart';
import 'theme/theme_controller.dart';
import 'widgets/bufferline.dart';
import 'widgets/dashboard.dart';
import 'widgets/cmdline.dart';
import 'widgets/editor.dart';
import 'widgets/neotree.dart';
import 'widgets/outline.dart';
import 'widgets/statusline.dart';
import 'widgets/telescope.dart';
import 'widgets/whichkey.dart';

class XnashApp extends StatelessWidget {
  const XnashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XNash — Xynorash',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late final AppState state;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    state = AppState(theme: ThemeController(), github: GithubStats());
    state.loadStats();
  }

  @override
  void dispose() {
    _focus.dispose();
    state.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = switch (event.logicalKey) {
      LogicalKeyboardKey.escape => 'Escape',
      LogicalKeyboardKey.enter => 'Enter',
      LogicalKeyboardKey.backspace => 'Backspace',
      LogicalKeyboardKey.arrowDown => 'ArrowDown',
      LogicalKeyboardKey.arrowUp => 'ArrowUp',
      _ => (event.character != null && event.character!.length == 1)
          ? event.character!
          : '',
    };
    if (key.isEmpty) return KeyEventResult.ignored;
    state.handleKey(key);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: _focus.requestFocus,
        child: AnimatedBuilder(
          animation: state,
          builder: (context, _) {
            final t = state.themeController.theme;
            final showTree = wide || state.explorerOpen;
            final window = Column(
              children: [
                Bufferline(state: state, showExplorerToggle: !wide),
                Expanded(
                  child: Row(
                    children: [
                      if (showTree)
                        NeoTree(
                          state: state,
                          onSelect: (_) {
                            if (!wide) state.toggleExplorer();
                          },
                        ),
                      Expanded(
                        child: Stack(
                          children: [
                            if (state.buffer.id == 'welcome')
                              Dashboard(state: state)
                            else
                              EditorPane(state: state),
                            if (state.mode == UiMode.whichkey ||
                                state.mode == UiMode.finder ||
                                state.mode == UiMode.outline) ...[
                              Positioned.fill(
                                child: GestureDetector(
                                  onTap: state.closeOverlay,
                                  child: Container(
                                      color: Colors.black
                                          .withValues(alpha: 0.35)),
                                ),
                              ),
                              if (state.mode == UiMode.whichkey)
                                WhichKeyOverlay(state: state),
                              if (state.mode == UiMode.finder)
                                TelescopeOverlay(state: state),
                              if (state.mode == UiMode.outline)
                                OutlineOverlay(state: state),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Statusline(state: state),
                CmdlineBar(state: state),
              ],
            );
            // Hyprland-style tiled window: gap, focused border, shadow.
            return Scaffold(
              backgroundColor: t.desktopBg,
              body: wide
                  ? Padding(
                      padding: const EdgeInsets.all(18),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: t.accent.withValues(alpha: 0.55)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 40,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: window,
                        ),
                      ),
                    )
                  : window,
            );
          },
        ),
      ),
    );
  }
}
