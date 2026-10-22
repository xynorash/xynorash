import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/providers/filter_providers.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'filter_providers.dart — three knobs that change what is drawn, not what is true'),
    cm('//', r'the one rule in this file is a negative: nothing here filters state'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'three StateProviders for the control bar’s min-size, orphan-only and search filters'),
    kv('language', r'Dart / Riverpod'),
    kv('size', r'23 lines, one commit: 0309d9e (2026-07-06)'),
    kv('written by', r'widgets/control_bar.dart'),
    kv('read by', r'widgets/graph_canvas.dart and widgets/memory_map.dart'),
    ...sec(r'the whole file'),
    ...code('dart', 'heaplens_flutter/lib/providers/filter_providers.dart · lines 3-23', r'''
/// Rendering-only filters written to by the control bar and read by
/// `graph_canvas.dart` / `memory_map.dart` (a future task/follow-up wires
/// the actual read side — this task only defines the providers and the UI
/// controls that write to them).
///
/// Important: none of these filter the underlying node map owned by
/// `graph_provider.dart` — they only affect what a given view chooses to
/// draw. The full node map (and its derived getters like `orphanCount`)
/// always reflects true daemon state regardless of these filters.

/// Minimum node size (bytes) to render; nodes below this threshold are
/// hidden from the view, not removed from state. Default 0 (show all).
final minSizeFilterProvider = StateProvider<double>((ref) => 0);

/// When true, a view should render only nodes in the `orphan` state.
/// Default false (show all states).
final orphanOnlyFilterProvider = StateProvider<bool>((ref) => false);

/// Case-insensitive substring filter against `NodeDto.symbol`. Empty string
/// means "no filter, show all".
final symbolSearchFilterProvider = StateProvider<String>((ref) => '');'''),
    ...para('//',
        r'Three providers and a doc comment that matters more than '
        r'the code. Each one is a StateProvider with the obvious '
        r'default: a minimum size of 0 bytes (so everything passes), '
        r'orphan-only off, and an empty search string (which means '
        r'no filter). A filter that defaults to the identity is what '
        r'lets the app start with every node on screen and no '
        r'special first-run case.'),
    ...sec(r'the rule: filters are a view concern'),
    ...para('//',
        r'The paragraph in the middle of the doc comment is the '
        r'design. None of these providers touches the node map that '
        r'graph_provider.dart owns. The comment says the full map '
        r'and its derived getters, such as the orphan count, always '
        r'reflect the true daemon state whatever the filters say. '
        r'That has a visible consequence in the UI: you can push the '
        r'minimum-size slider to its 4096 byte maximum, watch most '
        r'of the canvas empty, and the Orphans counter in the ribbon '
        r'still tells you how many orphans exist. A filter that '
        r'changed the counters would make the counters lie, and the '
        r'whole point of the app is that they do not.'),
    ...para('//',
        r'It also makes the filters cheap and safe. Because they '
        r'never mutate state, there is nothing to undo when a filter '
        r'is cleared, and the force layout keeps simulating every '
        r'node in the background. The graph canvas doc says it '
        r'directly: filtered nodes are omitted from painting and '
        r'hit-testing, but are never touched in the node map or in '
        r'the layout’s simulation nodes.'),
    ...sec(r'who reads them, and what each does'),
    ...code('dart', 'heaplens_flutter/lib/widgets/memory_map.dart · lines 41-53', r'''
    final minSize = ref.watch(minSizeFilterProvider);
    final orphanOnly = ref.watch(orphanOnlyFilterProvider);
    final symbolSearch = ref.watch(symbolSearchFilterProvider).toLowerCase();

    final visible = nodes.values.where((n) {
      if (!n.live) return false;
      if (n.size < minSize) return false;
      if (orphanOnly && n.state != NodeStateDto.orphan) return false;
      if (symbolSearch.isNotEmpty &&
          !n.symbol.toLowerCase().contains(symbolSearch)) {
        return false;
      }
      return true;'''),
    ...para('//',
        r'The memory map is the simplest reader. It drops a node '
        r'that is not live, a node smaller than the minimum size, '
        r'any non-orphan node when orphan-only is on, and any node '
        r'whose symbol does not contain the search text, compared in '
        r'lower case. The order of those checks is cheap-first and '
        r'every one is a plain predicate, so the filters compose as '
        r'an AND: size and orphan and search must all pass.'),
    ...code('dart', 'heaplens_flutter/lib/widgets/graph_canvas.dart · lines 141-153', r'''
    // tap either, since it isn't visible to tap "on".
    if (bestId != null) {
      final nodes = ref.read(graphProvider.notifier).nodes;
      final node = nodes[bestId];
      if (node != null &&
          _passesRenderFilters(
            node,
            minSize: ref.read(minSizeFilterProvider),
            orphanOnly: ref.read(orphanOnlyFilterProvider),
            symbolSearchLower:
                ref.read(symbolSearchFilterProvider).toLowerCase(),
          )) {
        ref.read(selectedNodeIdProvider.notifier).state = bestId;'''),
    ...para('//',
        r'The graph canvas applies the same predicate through a '
        r'shared function, and applies it twice: when building the '
        r'set of visible nodes to paint, and again on a tap before '
        r'it writes the selection. The comment on the second one '
        r'gives the reason: a node hidden by a filter should not be '
        r'selectable, because there is nothing visible to tap. '
        r'The tap handler uses ref.read and build uses ref.watch, so '
        r'build re-runs when a filter moves, while the handler takes '
        r'the value at the moment of the tap.'),
    ...sec(r'the comment that is out of date'),
    ...para('//',
        r'The first sentences of the doc say that a future task or '
        r'follow-up will wire the read side, and that this task only '
        r'defines the providers and the controls that write to them. '
        r'That was true on 2026-07-06 when the control bar landed; '
        r'it stopped being true when the memory map and then the '
        r'graph canvas started reading all three. The graph canvas '
        r'comment calls the graph view the default and primary view, '
        r'which is why it applies the filters like the memory map. '
        r'The stale paragraph is still in the file. '
        r'A reader who trusted it would hunt for a missing wiring '
        r'step that already exists.'),
    ...sec(r'edge cases'),
    ...pt('//', r'slider and size',
        r'the minimum is a double because it comes from a slider, '
        r'while a node’s size is an int, so the comparison is int '
        r'against double. Nothing is lost at this scale.'),
    ...pt('//', r'case',
        r'the search is lower-cased on both sides by each reader, so '
        r'an upper-case query still matches. The provider stores '
        r'whatever the field holds.'),
    ...pt('//', r'selection and filters',
        r'setting a filter does not clear the current selection. A '
        r'selected node that a filter then hides stays selected and '
        r'its detail panel stays populated; only new taps are gated.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'In three places. control_bar_test.dart checks the writers, '
        r'one test per control: the min-size slider moves '
        r'minSizeFilterProvider off 0, the orphan-only switch flips '
        r'it from false to true, and typing alloc::vec into the '
        r'search field makes the provider hold exactly that. '
        r'memory_map_test.dart sets each provider directly (min size '
        r'100, orphan-only true, search text vec) and asserts what '
        r'is left in the grid. graph_canvas_test.dart sets the '
        r'minimum size to 100 and checks the canvas.'),
    ...sec(r'history'),
    ...pt('//', r'0309d9e (2026-07-06)',
        r'feat(flutter): control_bar. Adds this file with the paused '
        r'and view-mode providers in the same commit. The message '
        r'calls the filters rendering-only, consumed by a later '
        r'task.'),
  ],
);
