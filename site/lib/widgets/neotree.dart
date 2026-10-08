import 'package:flutter/material.dart';

import '../data/projects.dart';
import '../state/app_state.dart';
import '../state/file_tree.dart';
import 'style.dart';

/// The explorer: projects are directories, pages are the files inside them,
/// mirroring each repository's real layout.
class NeoTree extends StatefulWidget {
  final AppState state;
  final void Function(int index) onSelect;
  const NeoTree({super.key, required this.state, required this.onSelect});

  @override
  State<NeoTree> createState() => _NeoTreeState();
}

class _NeoTreeState extends State<NeoTree> {
  final _activeKey = GlobalKey();
  int _revealedFor = -1;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final t = state.themeController.theme;
    final rows = visibleRows(state.tree, state.expandedDirs);

    // Keep the active file in view after it changes (open, tab switch).
    if (_revealedFor != state.bufferIndex) {
      _revealedFor = state.bufferIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _activeKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx,
              duration: const Duration(milliseconds: 120),
              alignment: 0.5);
        }
      });
    }

    String guideFor(TreeRow r) {
      final b = StringBuffer();
      for (final g in r.guides) {
        b.write(g ? '│ ' : '  ');
      }
      b.write(r.isLast ? '└─' : '├─');
      return b.toString();
    }

    Widget rowWidget(TreeRow r) {
      final n = r.node;
      final isFile = !n.isDir;
      final active = isFile && n.bufferIndex == state.bufferIndex;
      final open = n.isDir && state.expandedDirs.contains(n.path);
      final b = isFile ? kBuffers[n.bufferIndex!] : null;
      final isProject = n.isDir && r.depth == 0;

      final iconColor = n.isDir
          ? (isProject ? t.accent : t.blue)
          : (active ? t.accent : t.blue);
      final nameColor =
          active ? t.accent : (isProject ? t.fg : (n.isDir ? t.fgDim : t.fg));

      return InkWell(
        key: active ? _activeKey : null,
        hoverColor: t.bgHighlight,
        onTap: () {
          if (n.isDir) {
            state.toggleDir(n.path);
          } else {
            state.openBuffer(n.bufferIndex!);
            widget.onSelect(n.bufferIndex!);
          }
        },
        child: Container(
          width: double.infinity,
          color: active ? t.bgHighlight : t.bgDark,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: guideFor(r), style: mono(t.muted, size: 12)),
              TextSpan(
                  text: n.isDir ? (open ? ' \u{f07c} ' : ' \u{f07b} ') : ' ${b!.icon} ',
                  style: mono(iconColor, size: 12)),
              TextSpan(
                  text: n.name,
                  style: mono(nameColor,
                      size: 12,
                      weight: isProject || active
                          ? FontWeight.w700
                          : FontWeight.w400)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      );
    }

    return Container(
      width: 270,
      color: t.bgDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Text('\u{f07b}  ~/projects',
                style: mono(t.fgDim, size: 12, weight: FontWeight.w700)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: [for (final r in rows) rowWidget(r)],
            ),
          ),
        ],
      ),
    );
  }
}
