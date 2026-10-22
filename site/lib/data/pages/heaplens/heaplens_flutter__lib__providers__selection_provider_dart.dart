import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/providers/selection_provider.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'selection_provider.dart — which node the user is looking at'),
    cm('//', r'six lines that connect three panels without any of them knowing about each other'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'the currently selected node id, or null'),
    kv('language', r'Dart / Riverpod'),
    kv('size', r'6 lines, one commit: ed689f6 (2026-07-06)'),
    kv('written by', r'graph_canvas, memory_map, insights_panel'),
    kv('read by', r'node_detail (both panels), memory_map'),
    ...sec(r'the whole file'),
    ...code('dart', 'heaplens_flutter/lib/providers/selection_provider.dart · lines 3-6', r'''
/// Currently-selected node id (or `null` if nothing is selected), set by a
/// tap on the graph canvas. Read by `node_detail.dart` (a later task) to
/// show details for the selected node.
final selectedNodeIdProvider = StateProvider<int?>((ref) => null);'''),
    ...para('//',
        r'A nullable integer. The null means nothing is selected, '
        r'and the integer is a node id from the daemon, not an index '
        r'into anything the client owns. The doc comment names one '
        r'writer, a tap on the graph canvas, and one reader, '
        r'node_detail.dart, described as a later task. Both '
        r'statements are out of date, and that fact is the most '
        r'useful thing to know about this file.'),
    ...sec(r'what actually writes and reads it'),
    ...code('dart', 'heaplens_flutter/lib/widgets/memory_map.dart · lines 79-81', r'''
              onTap: () {
                ref.read(selectedNodeIdProvider.notifier).state = node.id;
              },'''),
    ...code('dart', 'heaplens_flutter/lib/widgets/insights_panel.dart · lines 84-90', r'''
                          onSelect: (insight) {
                            setState(() => _selectedInsightId = insight.id);
                            if (insight.implicatedNodeId != null) {
                              ref.read(selectedNodeIdProvider.notifier).state =
                                  insight.implicatedNodeId;
                            }
                          },'''),
    ...para('//',
        r'The memory map writes the id of a tapped cell, and the '
        r'insights panel writes the id of the node an insight '
        r'implicates: a finding in the insights panel selects its '
        r'node in the graph, per that file’s doc. The graph canvas '
        r'still writes when you tap a node. So one provider is the '
        r'single meeting point of three different views, and the '
        r'right rail’s Node detail and Size over time panels both '
        r'listen to it. Picking a cell in the map shows the same '
        r'details as picking a dot in the graph, because they set '
        r'the same value.'),
    ...sec(r'why an id and not a node'),
    ...para('//',
        r'Storing the node object would freeze a copy of its fields. '
        r'The graph notifier mutates its node map in place and bumps '
        r'a revision number, so the right thing is to store the key '
        r'and look the node up on each build. That is what '
        r'NodeDetail does: it watches the graph revision and this '
        r'id, and reads the current node from the map. The selection '
        r'survives every update to the selected node for free, and '
        r'the age and size you see are the live ones.'),
    ...sec(r'the stale selection problem'),
    ...code('dart', 'heaplens_flutter/lib/widgets/node_detail.dart · lines 92-99', r'''
    final selectedId = ref.watch(selectedNodeIdProvider);

    if (selectedId == null || !nodes.containsKey(selectedId)) {
      // Selection cleared, or the selected node no longer exists in state
      // (e.g. a `remove` diff deleted it) -- show a placeholder rather than
      // risk a null lookup.
      return const EmptyState(message: 'no node selected', icon: Icons.touch_app_outlined);
    }'''),
    ...para('//',
        r'An id can outlive its node. A remove diff can delete the '
        r'selected allocation between two frames. Nothing clears the '
        r'selection when that happens, so the readers must tolerate '
        r'it. NodeDetail checks containsKey and shows an explicit '
        r'empty state, no node selected, instead of doing a null '
        r'lookup. The doc comment promises exactly this, never '
        r'crashes on a stale selection, and node_detail_test.dart '
        r'has the cases for nothing selected and for an id that is '
        r'not in the map.'),
    ...para('//',
        r'A subtle companion: the sparkline panel resets its buffer '
        r'when the selection is null or stale, and its buffer also '
        r'resets when the id changes, so a new selection never '
        r'inherits another node’s history.'),
    ...sec(r'what it does not do'),
    ...pt('//', r'multi-select',
        r'one id only. There is no way to compare two nodes.'),
    ...pt('//', r'clearing on filter',
        r'changing a filter does not clear it, and nothing in lib/ '
        r'ever writes null back: the three writers only set ids. A '
        r'selection ends only by going stale, when its node '
        r'disappears from the map, and the panels then behave as if '
        r'nothing were selected.'),
    ...pt('//', r'persistence',
        r'nothing is stored across restarts.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'Mostly by setting the provider directly and looking at '
        r'what the panels draw. node_detail_test.dart writes '
        r'container.read(selectedNodeIdProvider.notifier).state = 1 '
        r'or 2 in seven places. memory_map_test.dart has the tap '
        r'test: tapping a cell selects that node via '
        r'selectedNodeIdProvider, with the expected id 7 after being '
        r'null before.'),
    ...sec(r'history'),
    ...pt('//', r'ed689f6 (2026-07-06)',
        r'feat(flutter): graph_canvas. The commit message lists this '
        r'provider as the new thing that enables tap-to-select. The '
        r'file has not been edited since, which is why its comment '
        r'still describes the world of that day.'),
  ],
);
