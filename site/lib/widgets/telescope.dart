import 'package:flutter/material.dart';

import '../data/projects.dart';
import '../state/app_state.dart';
import 'style.dart';

/// "  heaplens/crates/…" — the directory part of a path, for dimmed display.
String _dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : '  ${path.substring(0, i)}';
}

class TelescopeOverlay extends StatelessWidget {
  final AppState state;
  const TelescopeOverlay({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.themeController.theme;
    final all = state.finderResults;
    final results = all.take(AppState.finderRows).toList();
    final selected =
        results.isEmpty ? -1 : state.finderSelection.clamp(0, results.length - 1);

    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 640),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: t.bgDark,
              border: Border.all(color: t.muted.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.bgHighlight)),
              ),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '> ', style: mono(t.accent, size: 13)),
                  TextSpan(text: state.finderQuery, style: mono(t.fg, size: 13)),
                  TextSpan(text: '▊', style: mono(t.accent, size: 13)),
                ]),
              ),
            ),
            for (var r = 0; r < results.length; r++)
              InkWell(
                onTap: () => state.openBuffer(results[r]),
                child: Container(
                  width: double.infinity,
                  color: r == selected ? t.bgHighlight : t.bgDark,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: r == selected ? '> ' : '  ',
                          style: mono(t.accent, size: 12)),
                      TextSpan(
                          text: '${kBuffers[results[r]].icon} ',
                          style: mono(t.blue, size: 12)),
                      TextSpan(
                          text: kBuffers[results[r]].fileName,
                          style: mono(
                              r == selected ? t.fg : t.fgDim, size: 12)),
                      TextSpan(
                          text: _dirOf(kBuffers[results[r]].fullPath),
                          style: mono(t.muted, size: 11)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Text('${all.length}/${kBuffers.length}',
                  style: mono(t.muted, size: 11)),
            ),
          ],
            ),
          ),
          Positioned(
            top: -8,
            left: 40,
            child: Container(
              color: t.bgDark,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('Find Files',
                  style: mono(t.accent, size: 11, weight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
