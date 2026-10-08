import 'package:flutter/material.dart';

import '../data/projects.dart';
import '../state/app_state.dart';
import 'style.dart';

const _banner = [
  '██╗  ██╗ ██╗   ██╗ ███╗   ██╗  ██████╗  ██████╗   █████╗  ███████╗ ██╗  ██╗',
  '╚██╗██╔╝ ╚██╗ ██╔╝ ████╗  ██║ ██╔═══██╗ ██╔══██╗ ██╔══██╗ ██╔════╝ ██║  ██║',
  ' ╚███╔╝   ╚████╔╝  ██╔██╗ ██║ ██║   ██║ ██████╔╝ ███████║ ███████╗ ███████║',
  ' ██╔██╗    ╚██╔╝   ██║╚██╗██║ ██║   ██║ ██╔══██╗ ██╔══██║ ╚════██║ ██╔══██║',
  '██╔╝ ██╗    ██║    ██║ ╚████║ ╚██████╔╝ ██║  ██║ ██║  ██║ ███████║ ██║  ██║',
  '╚═╝  ╚═╝    ╚═╝    ╚═╝  ╚═══╝  ╚═════╝  ╚═╝  ╚═╝ ╚═╝  ╚═╝ ╚══════╝ ╚═╝  ╚═╝',
];

/// LazyVim-style start screen shown for the welcome buffer.
class Dashboard extends StatelessWidget {
  final AppState state;
  const Dashboard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.themeController.theme;

    // Descriptions only where there is room beside the explorer.
    final showSummary = MediaQuery.sizeOf(context).width >= 940;

    Widget entry(String key, String icon, String label, VoidCallback onTap,
            {String summary = ''}) =>
        InkWell(
          onTap: onTap,
          hoverColor: t.bgHighlight,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(icon, style: mono(t.blue, size: 13)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 190,
                  child: Text(label, style: mono(t.fg, size: 13)),
                ),
                if (showSummary)
                  SizedBox(
                    width: 330,
                    child: Text(summary,
                        overflow: TextOverflow.ellipsis,
                        style: mono(t.muted, size: 11)),
                  ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: t.bgHighlight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(key,
                      style:
                          mono(t.accent, size: 11, weight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        );

    // Projects are directories; each opens its README and expands in the
    // explorer.
    final projects = [
      for (final name in projectNames)
        (
          name,
          kBuffers.firstWhere((b) => b.fullPath == '$name/README.md'),
        ),
    ];
    final internal = [
      for (final b in kBuffers)
        if (b.internal && b.fullPath.endsWith('README.md')) b,
    ];

    return Container(
      color: t.bg,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final row in _banner)
                      Text(row, style: mono(t.accent, size: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text('Solving problems at the edge of impossible.',
                style: mono(t.fgDim, size: 13, style: FontStyle.italic)),
            const SizedBox(height: 28),
            for (var i = 0; i < projects.length; i++)
              entry('${i + 1}', '\u{f07b}', '${projects[i].$1}/',
                  () => state.openProject(projects[i].$1),
                  summary: projects[i].$2.summary),
            for (final b in internal)
              entry('', '\u{f023}', '${b.project ?? b.fileName}/',
                  () => state.openBuffer(kBuffers.indexOf(b)),
                  summary: b.summary),
            entry('a', '\u{f48a}', 'about.md',
                () => state.openBuffer(kBuffers.length - 1)),
            entry('SPC f', '\u{f002}', 'find file', state.openFinder),
            entry('t', '\u{f043b}', 'cycle theme', state.cycleTheme),
            const SizedBox(height: 28),
            Text('⚡ xynovim loaded ${projects.length} projects in 0.038s',
                style: mono(t.muted, size: 12)),
          ],
        ),
      ),
    );
  }
}
