import 'package:flutter/material.dart';

import '../data/projects.dart';
import '../state/app_state.dart';
import 'style.dart';

class WhichKeyOverlay extends StatelessWidget {
  final AppState state;
  const WhichKeyOverlay({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.themeController.theme;

    Widget row(String key, String label, VoidCallback onTap) => InkWell(
          onTap: onTap,
          hoverColor: t.bgHighlight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: t.bgHighlight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(key,
                          style: mono(t.accent,
                              size: 11, weight: FontWeight.w700)),
                    ),
                  ),
                ),
                Text('→ ', style: mono(t.muted, size: 12)),
                Text(label, style: mono(t.fg, size: 12)),
              ],
            ),
          ),
        );

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(vertical: 10),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: t.bgDark,
          border: Border.all(color: t.bgHighlight),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text('SPC',
                  style: mono(t.yellow, size: 12, weight: FontWeight.w700)),
            ),
            row('f', 'find project', state.openFinder),
            row('o', 'outline of this page', state.openOutline),
            row('t', 'cycle theme', state.cycleTheme),
            row('e', 'toggle explorer', state.toggleExplorer),
            row('1-${kBuffers.length}', 'goto buffer', () {}),
            row('q', 'quit (good luck)', () => state.runCommand('q')),
          ],
        ),
      ),
    );
  }
}
