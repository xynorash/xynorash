import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/widgets/node_colors.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'node_colors.dart — one word, one color, one sentence'),
    cm('//', r'the state vocabulary of the whole UI in 83 lines'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'maps NodeStateDto to color, label and definition; the state chip'),
    kv('language', r'Dart / Flutter'),
    kv('size', r'83 lines, 2 commits: 07b2011 (2026-07-06), 1cfb7f9 (2026-07-19)'),
    kv('read by', r'graph_canvas, memory_map, node_detail, control_bar'),
    kv('pins', r'test/widgets/graph_canvas_test.dart, orphan fill'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'HeapLens tells you four things about an allocation: it is '
        r'healthy, it is an orphan, it is hot, or it has been freed. '
        r'Those four words are the entire vocabulary of the product, '
        r'and they appear in a canvas, a grid, a detail panel, a '
        r'counter tooltip and a banner. If any two of those draw the '
        r'same state in different colors, or give it different '
        r'words, the user has to re-learn the product in every '
        r'panel. This file is the one place where the mapping is '
        r'written down. It came out of the memory map commit: the '
        r'colors were first inlined in graph_canvas.dart, and the '
        r'second consumer made it worth extracting.'),
    ...sec(r'the three tables'),
    ...code('dart', 'heaplens_flutter/lib/widgets/node_colors.dart · lines 20-25, 34-39, 44-49', r'''
const Map<NodeStateDto, Color> kNodeStateColors = {
  NodeStateDto.healthy: XynorashTheme.teal,
  NodeStateDto.orphan: XynorashTheme.coral,
  NodeStateDto.hot: XynorashTheme.orange,
  NodeStateDto.freed: Color(0xFF9E9E9E), // gray — no clear theme mapping, unchanged
};
...
const Map<NodeStateDto, String> kNodeStateLabels = {
  NodeStateDto.healthy: 'Healthy',
  NodeStateDto.orphan: 'Orphan',
  NodeStateDto.hot: 'Hot',
  NodeStateDto.freed: 'Freed',
};
...
const Map<NodeStateDto, String> kNodeStateDescriptions = {
  NodeStateDto.healthy: 'A live allocation with a known owner.',
  NodeStateDto.orphan: 'A live allocation whose owner was freed — likely a leak.',
  NodeStateDto.hot: 'An owner whose children are growing quickly.',
  NodeStateDto.freed: 'No longer live; fading out of the graph.',
};'''),
    ...para('//',
        r'Three const maps, all keyed by NodeStateDto and all total '
        r'over the four values. The colors are XynorashTheme hues: '
        r'healthy is teal, orphan is coral, hot is orange. Freed is '
        r'a plain gray, and the comment next to it is honest about '
        r'why: no clear theme mapping, unchanged from before the '
        r'palette existed. The labels are the single capitalized '
        r'word for each state. The descriptions are one '
        r'plain-language sentence for each, written to be shown as a '
        r'tooltip anywhere the state, or a number derived from it, '
        r'is displayed.'),
    ...para('//',
        r'The sentences are worth reading as a spec. Healthy: a live '
        r'allocation with a known owner. Orphan: a live allocation '
        r'whose owner was freed, likely a leak. Hot: an owner whose '
        r'children are growing quickly. Freed: no longer live, '
        r'fading out of the graph. The orphan definition is the '
        r'product thesis in one line. It hedges with likely a leak: an '
        r'orphan is a fact about ownership, and leak is an inference.'),
    ...sec(r'the shared rule, and its boundary'),
    ...code('dart', 'heaplens_flutter/lib/widgets/node_colors.dart · lines 6-13, 27-28', r'''
/// Fill colors by [NodeStateDto], shared by every widget that renders nodes
/// (the graph canvas and the memory map). This is the single source of truth
/// for the healthy/orphan/hot/freed -> color mapping; do not duplicate this
/// map elsewhere.
///
/// Presentation effects specific to one widget (e.g. the graph canvas's
/// orphan pulsing ring, or freed-node fade alpha) are NOT part of this
/// shared mapping -- only the base fill color is shared.
...
/// Returns the shared base fill color for a given node [state].
Color colorForState(NodeStateDto state) => kNodeStateColors[state]!;'''),
    ...para('//',
        r'The doc comment draws a line. What is shared is '
        r'only the base fill color. Presentation specific to one '
        r'widget stays in that widget: the graph canvas’s orphan '
        r'pulse and its fade for freed nodes live in '
        r'graph_canvas.dart, where the code at the call site '
        r'multiplies the shared color by the node’s fade only when '
        r'the state is freed. The memory map uses the shared color '
        r'with no effect at all. Sharing the color and not the '
        r'effects is what lets two very different views look like '
        r'one app without forcing one to imitate the other.'),
    ...sec(r'the chip'),
    ...code('dart', 'heaplens_flutter/lib/widgets/node_colors.dart · lines 55-82', r'''
class NodeStateChip extends StatelessWidget {
  const NodeStateChip({super.key, required this.state});

  final NodeStateDto state;

  @override
  Widget build(BuildContext context) {
    final color = colorForState(state);
    return Tooltip(
      message: kNodeStateDescriptions[state]!,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          kNodeStateLabels[state]!,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }'''),
    ...para('//',
        r'NodeStateChip is a small pill: the state color at 18 '
        r'percent alpha as fill, the full color as border and text, '
        r'and a tooltip with the description. The comment states the '
        r'accessibility intent in one clause: it pairs the color '
        r'with the word, so state reads at a glance without relying '
        r'on color alone. A person who cannot tell coral from teal '
        r'still reads Orphan. The node detail panel shows the same '
        r'word a second time in plain text, as the raw state name in '
        r'a field row, so both the friendly label and the wire name '
        r'are visible.'),
    ...sec(r'edge cases'),
    ...pt('//', r'a fifth state',
        r'colorForState, the chip and the tooltips all index the '
        r'maps with a null check. The maps are complete today, but a '
        r'new enum value would compile and then fail at runtime with '
        r'a null check error the first time a node in that state was '
        r'drawn. An exhaustive switch expression would make it a '
        r'compile error instead. Nothing in the '
        r'source says why a map was chosen.'),
    ...pt('//', r'unknown wire strings',
        r'not here: NodeStateDto.fromWire maps an unrecognized '
        r'string to healthy, and contract_test.dart pins that. A '
        r'state the client does not know therefore renders as a teal '
        r'healthy node, a quiet failure mode rather than a loud one.'),
    ...pt('//', r'ghost nodes',
        r'a node removed from the graph keeps fading on the canvas '
        r'for a moment. The canvas draws it with colorForState of '
        r'the last state it had, which is why the freed entry is not '
        r'the only state a fading node shows.'),
    ...sec(r'who calls it'),
    ...pt('//', r'graph_canvas.dart',
        r'colorForState for live nodes and again for fading ghosts, '
        r'using the state they had when they left.'),
    ...pt('//', r'memory_map.dart',
        r'the cell fill is colorForState.'),
    ...pt('//', r'node_detail.dart',
        r'the chip, the tooltip text for the state row, and the '
        r'sparkline color, so the line has the color of the node it '
        r'plots.'),
    ...pt('//', r'control_bar.dart',
        r'the orphan description as the tooltip of the Orphans '
        r'counter, and the orphan color for the number when it is '
        r'above zero.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'Not in a test named for this file. The pin is indirect and '
        r'specific: graph_canvas_test.dart asserts that a selected '
        r'orphan node is painted with a circle whose color is '
        r'kNodeStateColors for the orphan state as its base fill, '
        r'then a cyan ring for the selection. That test came from '
        r'the fix for the orphan-banner bug: ead62bb adds it to '
        r'guard that a selected orphan node’s fill stays derived '
        r'from state, with the selection ring purely additive. The '
        r'commit says the suspected second bug did not reproduce; '
        r'the test stays as a guard.'),
    ...sec(r'history'),
    ...pt('//', r'07b2011 (2026-07-06)',
        r'feat(flutter): memory map view with shared node-color '
        r'helper. Extracts the mapping out of graph_canvas.dart.'),
    ...pt('//', r'1cfb7f9 (2026-07-19)',
        r'UI refresh: the colors become XynorashTheme hues (the '
        r'first version was a 2DD4BF teal, an FF7F50 coral and an '
        r'FFC107 amber), and the labels, descriptions and chip are '
        r'added.'),
  ],
);
