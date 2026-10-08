import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'style.dart';

class Statusline extends StatelessWidget {
  final AppState state;
  const Statusline({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.themeController.theme;
    final total = state.buffer.lines.length;
    final line = state.scrollLines + 1;
    final section = state.buffer.sectionAt(state.scrollLines)?.title;
    final pct = total <= 1 ? 100 : ((line / total) * 100).round();

    Widget seg(String text, Color fg, Color bg,
            {FontWeight weight = FontWeight.w400}) =>
        Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Text(text,
              style: mono(fg, size: 11, weight: weight),
              overflow: TextOverflow.ellipsis),
        );

    // Powerline separators: fg is the segment being left, bg the one entered.
    Widget sepR(Color from, Color to) => Container(
          color: to,
          alignment: Alignment.center,
          child: Text('\u{e0b0}', style: mono(from, size: 14)),
        );
    Widget sepL(Color from, Color to) => Container(
          color: from,
          alignment: Alignment.center,
          child: Text('\u{e0b2}', style: mono(to, size: 14)),
        );

    return Container(
      color: t.bgHighlight,
      height: 26,
      child: Row(
        children: [
          seg('NORMAL', t.bgDark, t.accent, weight: FontWeight.w700),
          sepR(t.accent, t.bgHighlight),
          seg('\u{e725} main', t.fgDim, t.bgHighlight),
          sepR(t.bgHighlight, t.bg),
          Flexible(
            child: seg(
                '${state.buffer.icon} ${state.buffer.fullPath.replaceAll('/', ' › ')}'
                '${section == null ? '' : '  › $section'}',
                t.fg,
                t.bg),
          ),
          Expanded(child: Container(color: t.bg)),
          sepL(t.bg, t.bgHighlight),
          seg('\u{f043b} ${state.themeController.name}', t.purple,
              t.bgHighlight),
          sepL(t.bgHighlight, t.accent),
          seg('☰ $line:1  $pct%', t.bgDark, t.accent,
              weight: FontWeight.w700),
        ],
      ),
    );
  }
}
