import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/widgets/memory_map.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'memory_map.dart — the graph without the graph'),
    cm('//', r'one cell per live allocation, ordered by address'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'the alternate centre view: a grid of coloured cells'),
    kv('language', r'Dart / Flutter (GridView.builder)'),
    kv('size', r'121 lines; 2 commits, both 2026-07-06'),
    kv('tested by', r'test/widgets/memory_map_test.dart (7 widget tests)'),
    kv('shares', r'filters with graph_canvas.dart, colours via node_colors.dart'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'The Build Spec asked for two views of the same data. The '
        r'first, the force-directed graph, shows ownership. The '
        r'second, in section 6.5, is "memory_map.dart: structured grid '
        r'view (address-ordered cells) as the alternate view". The M5 '
        r'plan sharpened it: "one cell per node, ordered by ptr, is '
        r'sufficient", and explicitly not required: cell area '
        r'proportional to size.'),
    blank,
    ...para('//',
        r'The view earned a second job later. When a target has no '
        r'debug symbols, no ownership edges can be inferred, and the '
        r'graph is a scatter of unconnected discs. The target-status '
        r'banner then offers a one-tap "Switch to Map view" and says '
        r'the map is where the target is still readable. The grid does '
        r'not depend on edges, so it keeps working when the graph '
        r'cannot.'),
    ...sec(r'building the grid'),
    ...code('dart', 'heaplens_flutter/lib/widgets/memory_map.dart · build (trimmed)', r'''
    final visible = nodes.values.where((n) {
      if (!n.live) return false;
      if (n.size < minSize) return false;
      if (orphanOnly && n.state != NodeStateDto.orphan) return false;
      if (symbolSearch.isNotEmpty &&
          !n.symbol.toLowerCase().contains(symbolSearch)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.ptr.compareTo(b.ptr));

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth.isFinite
            ? ((constraints.maxWidth) / (_kCellSize + _kCellSpacing))
                .floor()
                .clamp(1, 1 << 30)
            : _kDefaultColumnsWhenUnbounded;

        return GridView.builder(
          padding: const EdgeInsets.all(_kCellSpacing),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: _kCellSpacing,
            mainAxisSpacing: _kCellSpacing,
          ),
          itemCount: visible.length,'''),
    ...pt('//', r'filter, then sort',
        r'the four conditions are the shared rendering-only filters: '
        r'live only, minimum size, orphans only, case-insensitive '
        r'symbol substring. The sort key is the pointer. A node '
        r'disappearing or appearing shifts every later cell, which is '
        r'the honest behaviour of an address-ordered list.'),
    ...pt('//', r'columns from width',
        r'28 px cells with 2 px spacing give floor(width / 30) columns, '
        r'clamped to at least 1. When the width is unbounded the code '
        r'falls back to 20 columns. That guard has a story, below.'),
    ...pt('//', r'GridView.builder',
        r'cells are built lazily, so a large map costs only the '
        r'visible rows.'),
    blank,
    ...para('//',
        r'A detail about the numbers: because the delegate has a fixed '
        r'cross-axis count, the real cell width is the available width '
        r'divided by the column count. The 28 px constant is a target '
        r'used to choose the count; the cells come out at 28 px or a '
        r'little wider, filling the row exactly.'),
    ...sec(r'the crash that was caught in review'),
    ...para('//',
        r'Commit cbb34ae, "add ptr-order test + unbounded-width guard", '
        r'describes the failure the isFinite branch prevents: calling '
        r'floor() on double.infinity raises "Infinity or NaN to int". A '
        r'LayoutBuilder in an unbounded parent, such as a horizontally '
        r'scrolling container, reports an infinite maxWidth. The fix '
        r'introduced the constant _kDefaultColumnsWhenUnbounded = 20 '
        r'and the check. The commit message also reports the state of '
        r'the suite at that point: "All 59 tests pass. Flutter analyze '
        r'clean."'),
    blank,
    ...para('//',
        r'A caution about what the test covers. The test named '
        r'"computes safe column count even when maxWidth is infinite" '
        r'actually wraps the map in a 100 by 100 SizedBox, which gives '
        r'it tight, finite constraints. Its own comment says it tests '
        r'"tight or unusual constraints". The unbounded branch is '
        r'therefore guarded in code but not exercised by any test.'),
    ...sec(r'a cell is a colour, a border and a tooltip'),
    ...code('dart', 'heaplens_flutter/lib/widgets/memory_map.dart · _MemoryMapCell', r'''
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: '${node.symbol}\n'
            'ptr: 0x${node.ptr.toRadixString(16)}\n'
            'size: ${node.size}',
        child: Container(
          decoration: BoxDecoration(
            color: colorForState(node.state),
            border: selected
                ? Border.all(color: Colors.white, width: 2)
                : null,
          ),
        ),
      ),
    );'''),
    ...para('//',
        r'The cell is deliberately mute. It carries the state colour '
        r'from the shared colorForState, a white border when selected, '
        r'and a hover tooltip with the symbol, the pointer in hex and '
        r'the size. Tapping writes selectedNodeIdProvider, so the '
        r'detail panel and sparkline work exactly as they do from the '
        r'graph. Each cell has a ValueKey of its node id, which is how '
        r'every test finds it.'),
    blank,
    ...para('//',
        r'Two honest observations about the design. First, the order is '
        r'by address but the layout does not show address distance: two '
        r'cells next to each other may be 16 bytes or 16 gigabytes '
        r'apart. It is a sorted list laid out as a grid, a '
        r'memory map in name more than in geometry. Second, size is '
        r'not encoded visually. The diagnostic banner promises that '
        r'"allocation sizes and growth are still available in the Map '
        r'view". Sizes are available on hover and through the '
        r'minimum-size filter, and growth shows as more cells; nothing '
        r'draws a larger allocation larger. The plan said this was '
        r'enough for M5, and it is still how the file works.'),
    ...sec(r'sharing instead of copying'),
    ...para('//',
        r'07b2011, the commit that added the file, also created '
        r'node_colors.dart. The plan had asked for it: reuse a shared '
        r'colour mapping "rather than duplicating the '
        r'healthy/orphan/hot/freed → color logic". The graph canvas '
        r'had its own copy; the commit moved it out so both views call '
        r'colorForState.'),
    blank,
    ...para('//',
        r'The filter predicate is the opposite case. graph_canvas.dart '
        r'has a named private function, _passesRenderFilters, and this '
        r'file repeats the same four conditions inline. The canvas '
        r'comment says the two are kept "in exact lockstep". They are '
        r'equal today. They are separate copies, tested separately.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'memory_map_test.dart has seven tests sharing a helper that '
        r'puts the map in a 400 by 400 box with a fake message stream:'),
    ...pt('//', r'renders a grid',
        r'two nodes in, one GridView out, no exception.'),
    ...pt('//', r'three filter tests',
        r'minimum size 100 hides the 8-byte node; orphans-only hides '
        r'the healthy one; the search "vec" keeps alloc::vec::Vec and '
        r'hides alloc::boxed::Box. Each ends by checking the node map '
        r'is untouched at length 2, the property that makes the '
        r'filters rendering-only.'),
    ...pt('//', r'tap selects',
        r'tapping the cell with key 7 sets the selection to 7.'),
    ...pt('//', r'ptr order',
        r'five nodes with pointers 500, 100, 300, 200 and 400 are '
        r'added. The test claims to verify ascending order, but its '
        r'assertions only check that each of the five keys is '
        r'present exactly once. Presence is all it proves. Removing the '
        r'sort would not fail it. The cbb34ae message says the test '
        r'verifies that the sort expression "is correctly applied"; as '
        r'written, it does not.'),
    ...pt('//', r'tight constraints',
        r'the test above.'),
    ...sec(r'limits'),
    ...pt('//', r'sorting each build',
        r'the filtered list is rebuilt and sorted on every graph '
        r'revision. Fine for hundreds of nodes; it is O(n log n) per '
        r'message.'),
    ...pt('//', r'no aggregation',
        r'the map lists every live node. It has no equivalent of the '
        r'500-node cutoff where the graph layout switches to '
        r'aggregates.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
