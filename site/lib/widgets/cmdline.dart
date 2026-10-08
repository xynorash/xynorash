import 'package:flutter/material.dart';

import '../keymap/dispatcher.dart';
import '../state/app_state.dart';
import 'style.dart';

class CmdlineBar extends StatelessWidget {
  final AppState state;
  const CmdlineBar({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.themeController.theme;
    final Widget left;
    if (state.mode == UiMode.cmdline) {
      left = Text.rich(
        TextSpan(children: [
          TextSpan(text: ':${state.cmdline}', style: mono(t.fg, size: 12)),
          TextSpan(text: '▊', style: mono(t.accent, size: 12)),
        ]),
        overflow: TextOverflow.ellipsis,
      );
    } else if (state.message.isNotEmpty) {
      left = Text(state.message,
          style: mono(t.red, size: 12), overflow: TextOverflow.ellipsis);
    } else {
      Widget chip(String key, String label, VoidCallback onTap) => InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: key,
                    style:
                        mono(t.accent, size: 12, weight: FontWeight.w700)),
                TextSpan(text: ' $label', style: mono(t.muted, size: 12)),
              ])),
            ),
          );
      left = ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip('SPC', 'menu', state.openWhichKey),
          chip('f', 'find', state.openFinder),
          chip('o', 'outline', state.openOutline),
          chip('t', 'theme', state.cycleTheme),
          chip(':', 'cmd', state.openCmdline),
        ],
      );
    }
    return Container(
      color: t.bg,
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Expanded(child: left),
          if (state.dispatcher.pending.isNotEmpty)
            Text(state.dispatcher.pending, style: mono(t.yellow, size: 12)),
        ],
      ),
    );
  }
}
