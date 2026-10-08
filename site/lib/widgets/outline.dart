import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'style.dart';

/// Aerial-style symbol outline for the open buffer: every `# section` with
/// its line number. Click or Enter to jump; j/k or arrows to move.
class OutlineOverlay extends StatelessWidget {
  final AppState state;
  const OutlineOverlay({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.themeController.theme;
    final sections = state.buffer.outline;
    final selected = sections.isEmpty
        ? -1
        : state.outlineSelection.clamp(0, sections.length - 1);
    final height = MediaQuery.sizeOf(context).height;

    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            constraints:
                BoxConstraints(maxWidth: 460, maxHeight: height * 0.7),
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
            child: sections.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('no sections in ${state.buffer.fileName}',
                        style: mono(t.muted, size: 12)),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.only(top: 14),
                          children: [
                            for (var i = 0; i < sections.length; i++)
                              InkWell(
                                onTap: () => state.gotoSection(i),
                                child: Container(
                                  width: double.infinity,
                                  color:
                                      i == selected ? t.bgHighlight : t.bgDark,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 4),
                                  child: Text.rich(
                                    TextSpan(children: [
                                      TextSpan(
                                          text: i == selected ? '> ' : '  ',
                                          style: mono(t.accent, size: 12)),
                                      TextSpan(
                                          text: '${sections[i].line + 1}'
                                              .padLeft(4),
                                          style: mono(t.lineNr, size: 12)),
                                      TextSpan(
                                          text: '  ${sections[i].title}',
                                          style: mono(
                                              i == selected ? t.fg : t.fgDim,
                                              size: 12)),
                                    ]),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        child: Text(
                            '${selected + 1}/${sections.length} · ⏎ jump · esc close',
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
              child: Text('Outline · ${state.buffer.fileName}',
                  style: mono(t.accent, size: 11, weight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
