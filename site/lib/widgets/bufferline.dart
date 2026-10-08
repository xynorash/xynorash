import 'package:flutter/material.dart';

import '../data/projects.dart';
import '../state/app_state.dart';
import 'style.dart';

class Bufferline extends StatelessWidget {
  final AppState state;
  final bool showExplorerToggle;
  const Bufferline(
      {super.key, required this.state, this.showExplorerToggle = false});

  @override
  Widget build(BuildContext context) {
    final t = state.themeController.theme;
    return Container(
      color: t.bgDark,
      height: 34,
      child: Row(
        children: [
          if (showExplorerToggle)
            InkWell(
              onTap: state.toggleExplorer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('\u{f0c9}', style: mono(t.fgDim, size: 14)),
              ),
            ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: state.openBuffers.length,
              itemBuilder: (_, k) {
                final i = state.openBuffers[k];
                final b = kBuffers[i];
                final active = i == state.bufferIndex;
                // Two open files with the same name (README.md, lib.rs…)
                // get their parent directory, like a real bufferline.
                final dup = state.openBuffers.any(
                    (j) => j != i && kBuffers[j].fileName == b.fileName);
                final parts = b.fullPath.split('/');
                final label = (dup || b.fileName == 'README.md') &&
                        parts.length > 1
                    ? '${parts[parts.length - 2]}/${b.fileName}'
                    : b.fileName;
                return InkWell(
                  hoverColor: t.bgHighlight,
                  onTap: () => state.openBuffer(i),
                  child: Container(
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    decoration: BoxDecoration(
                      color: active ? t.bg : t.bgDark,
                      border: Border(
                        top: BorderSide(
                          color: active ? t.accent : t.bgDark,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(b.icon,
                            style: mono(active ? t.blue : t.muted, size: 12)),
                        const SizedBox(width: 6),
                        Text(label,
                            style: mono(active ? t.fg : t.muted, size: 12)),
                        const SizedBox(width: 2),
                        InkWell(
                          onTap: () => state.closeBuffer(i),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 8),
                            child: Text('\u{f00d}',
                                style: mono(
                                    active ? t.accent : t.muted.withValues(alpha: 0.6),
                                    size: 10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
