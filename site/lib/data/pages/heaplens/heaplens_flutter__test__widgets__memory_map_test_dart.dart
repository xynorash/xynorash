import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/widgets/memory_map_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'memory_map_test.dart — one cell per allocation, ordered by address'),
    cm('//', r'seven widget tests for the grid view, two of them weaker than their titles'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'pins the MemoryMap grid: rendering, the three filters, tap selection, ptr order, column guard'),
    kv('language', r'Dart, flutter_test widget tests'),
    kv('size', r'258 lines, 7 testWidgets'),
    kv('history', r'07b2011 (2026-07-06) created it with the widget; cbb34ae (2026-07-06) added the last two tests'),
    kv('subject', r'lib/widgets/memory_map.dart'),
    ...sec(r'what MemoryMap is'),
    ...para('//', r'The second view of the app, beside the force graph. It lays one small square for every live node on a grid, sorted by address, and colours each square by the node’s state. It is the view to use when the graph has no structure, which is why the target status banner links to it. Sizes are not drawn to scale; the class comment says one cell per node, ordered by ptr, was sufficient for milestone 5.'),
    ...code('dart', r'heaplens_flutter/lib/widgets/memory_map.dart · the filtering and sorting', r'''
class MemoryMap extends ConsumerWidget {
  const MemoryMap({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched purely to know *when* to rebuild; the fresh node map is read
    // below rather than cached across revisions (same contract as
    // graph_canvas.dart).
    ref.watch(graphProvider);
    final nodes = ref.read(graphProvider.notifier).nodes;
    final selectedId = ref.watch(selectedNodeIdProvider);

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
      return true;
    }).toList()
      ..sort((a, b) => a.ptr.compareTo(b.ptr));'''),
    ...para('//', r'Reading the source first makes the tests easy to follow. The widget watches the revision, reads the fresh node map, applies three filters (minimum size, orphans only, symbol substring, case-insensitive), drops anything not live, and sorts by ptr ascending. Each cell has a ValueKey(node.id), which is what almost every test uses to find it.'),
    ...sec(r'the harness'),
    ...code('dart', r'heaplens_flutter/test/widgets/memory_map_test.dart · _pumpMemoryMap', r'''
Future<ProviderContainer> _pumpMemoryMap(
  WidgetTester tester,
  StreamController<GraphMessage> controller,
) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        graphMessageProvider.overrideWith((ref) => controller.stream),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 400,
                child: const MemoryMap(),
              ),
            ),
          );
        },
      ),
    ),
  );
  return container;
}'''),
    ...para('//', r'The view is placed in a 400 by 400 SizedBox, inside a MaterialApp and Scaffold. Giving it a definite size matters: a GridView inside an unconstrained parent throws, and the last test goes looking for exactly that kind of problem. As in other files, a Consumer captures the container.'),
    ...sec(r'test 1: it renders'),
    ...code('dart', r'heaplens_flutter/test/widgets/memory_map_test.dart · renders a grid of cells without throwing', r'''
  testWidgets('renders a grid of cells without throwing', (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpMemoryMap(tester, controller);

    final nodeA = _node(id: 1, ptr: 100, state: NodeStateDto.healthy);
    final nodeB = _node(id: 2, ptr: 50, state: NodeStateDto.orphan);
    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: [nodeA, nodeB]));
    await tester.pump();

    expect(find.byType(MemoryMap), findsOneWidget);
    expect(tester.takeException(), isNull);
    // One GestureDetector-wrapped cell per live node.
    expect(find.byType(GridView), findsOneWidget);
  });'''),
    ...para('//', r'Two nodes, one orphan, applied through the real graph notifier. The expectations are that a MemoryMap and a GridView exist and no exception was recorded. The comment above the last line says one GestureDetector-wrapped cell per live node, but the assertion only looks for the GridView, so the cell count is not verified here.'),
    ...sec(r'tests 2 to 4: filters change the view, not the data'),
    ...code('dart', r'heaplens_flutter/test/widgets/memory_map_test.dart · min-size filter', r'''
  testWidgets(
      'min-size filter hides a cell from the rendered grid without '
      'touching the underlying node map', (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpMemoryMap(tester, controller);

    final small = _node(id: 1, ptr: 10, size: 8);
    final big = _node(id: 2, ptr: 20, size: 4096);
    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: [small, big]));
    await tester.pump();

    // Both nodes present in the grid before filtering.
    expect(find.byKey(const ValueKey(1)), findsOneWidget);
    expect(find.byKey(const ValueKey(2)), findsOneWidget);

    container.read(minSizeFilterProvider.notifier).state = 100;
    await tester.pump();

    // The small node's cell is hidden from the grid...
    expect(find.byKey(const ValueKey(1)), findsNothing);
    expect(find.byKey(const ValueKey(2)), findsOneWidget);

    // ...but the underlying node map is untouched by the filter.
    expect(container.read(graphProvider.notifier).nodes.length, 2);
  });'''),
    ...para('//', r'Nodes of 8 and 4096 bytes. Before filtering, both cells exist. Setting minSizeFilterProvider to 100 removes the key for the small node and keeps the big one. The final line, the one that makes it a good test, asserts the graph provider still holds two nodes. This is the rule from the widget’s own documentation: filters never touch the underlying map, they only decide what this view draws.'),
    ...code('dart', r'heaplens_flutter/test/widgets/memory_map_test.dart · orphan-only filter', r'''
  testWidgets('orphan-only filter hides non-orphan cells', (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpMemoryMap(tester, controller);

    final healthy = _node(id: 1, ptr: 10, state: NodeStateDto.healthy);
    final orphan = _node(id: 2, ptr: 20, state: NodeStateDto.orphan);
    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: [healthy, orphan]));
    await tester.pump();

    container.read(orphanOnlyFilterProvider.notifier).state = true;
    await tester.pump();

    expect(find.byKey(const ValueKey(1)), findsNothing);
    expect(find.byKey(const ValueKey(2)), findsOneWidget);
    expect(container.read(graphProvider.notifier).nodes.length, 2);
  });'''),
    ...code('dart', r'heaplens_flutter/test/widgets/memory_map_test.dart · symbol search filter', r'''
  testWidgets('symbol search filter hides non-matching cells', (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpMemoryMap(tester, controller);

    final vecNode = _node(id: 1, ptr: 10, symbol: 'alloc::vec::Vec');
    final boxNode = _node(id: 2, ptr: 20, symbol: 'alloc::boxed::Box');
    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: [vecNode, boxNode]));
    await tester.pump();

    container.read(symbolSearchFilterProvider.notifier).state = 'vec';
    await tester.pump();

    expect(find.byKey(const ValueKey(1)), findsOneWidget);
    expect(find.byKey(const ValueKey(2)), findsNothing);
    expect(container.read(graphProvider.notifier).nodes.length, 2);
  });'''),
    ...para('//', r'The same pattern for the other two. With orphanOnly on, the healthy cell disappears and the orphan stays. With the search text vec, the cell for alloc::vec::Vec stays and alloc::boxed::Box disappears. The search string is lower case but the symbols are mixed, so the case-insensitive match is also exercised in one direction: lower case needle, mixed case haystack. The converse, an upper case needle, is not tested.'),
    blank,
    ...para('//', r'Both tests also check the node map length again. The repetition is the point; a filter implemented by mutating the map would pass the visibility check and fail this one.'),
    ...sec(r'test 5: tap to select'),
    ...code('dart', r'heaplens_flutter/test/widgets/memory_map_test.dart · tapping a cell selects that node', r'''
  testWidgets('tapping a cell selects that node via selectedNodeIdProvider',
      (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpMemoryMap(tester, controller);

    final node = _node(id: 7, ptr: 10);
    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: [node]));
    await tester.pump();

    expect(container.read(selectedNodeIdProvider), isNull);

    await tester.tap(find.byKey(const ValueKey(7)));
    await tester.pump();

    expect(container.read(selectedNodeIdProvider), 7);
  });'''),
    ...para('//', r'selectedNodeIdProvider is null, a tap on the cell with key 7, and the provider is 7. This is the link to the node detail panel in the right rail: selection is shared state, so a click in either view fills the same panel. Note that the widget reads the provider with ref.read inside the tap callback, and the test confirms the write path is wired.'),
    ...sec(r'test 6: ordering, and what the test really shows'),
    ...code('dart', r'heaplens_flutter/test/widgets/memory_map_test.dart · renders cells in ascending ptr order', r'''
  testWidgets('renders cells in ascending ptr order despite shuffled input',
      (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpMemoryMap(tester, controller);

    // Create nodes with non-sequential, scrambled ptr values.
    // Add them in order: 500, 100, 300, 200, 400 to verify sorting.
    final node1 = _node(id: 1, ptr: 500);
    final node2 = _node(id: 2, ptr: 100);
    final node3 = _node(id: 3, ptr: 300);
    final node4 = _node(id: 4, ptr: 200);
    final node5 = _node(id: 5, ptr: 400);
    container.read(graphProvider.notifier).applyDiff(
          GraphSnapshot(ts: 1, nodes: [node1, node2, node3, node4, node5]),
        );
    await tester.pump();

    // Find all _MemoryMapCell widgets (there should be 5).
    final cellFinder = find.byType(Container);
    expect(cellFinder, findsWidgets);

    // Verify that when we iterate through the cells' keys in the order
    // they appear in the tree (via byKey), they correspond to nodes
    // in ascending ptr order: 100, 200, 300, 400, 500 (ids 2, 4, 3, 5, 1).
    final expectedOrderByPtr = [2, 4, 3, 5, 1]; // ids with ptrs 100, 200, 300, 400, 500
    for (int i = 0; i < expectedOrderByPtr.length; i++) {
      expect(
        find.byKey(ValueKey(expectedOrderByPtr[i])),
        findsOneWidget,
        reason: 'Node ${expectedOrderByPtr[i]} should be in grid at ptr-sorted position $i',
      );
    }

    // Also verify the cells are present in the grid.
    expect(find.byType(GridView), findsOneWidget);
  });'''),
    ...para('//', r'The test inserts five nodes with scrambled addresses (500, 100, 300, 200, 400) and lists the expected ids in address order, 2, 4, 3, 5, 1. It then loops over those ids and asserts that each one is found once. That is where a careful reader should stop. find.byKey(...) returns a widget regardless of its position in the tree, so this loop proves each cell exists, not that the cells are in that order. A widget that rendered the cells in insertion order would pass, and so would a widget that did no sorting at all.'),
    ...para('//', r'The commit message for cbb34ae says the test verifies the .sort call is correctly applied and the rendered order. The code does not go that far. An assertion that does would read the position of each cell, for example through tester.getTopLeft for each key and compare coordinates. The sort in memory_map.dart line 55 is therefore the least well-protected line in the file.'),
    ...sec(r'test 7: the infinite width guard'),
    ...code('dart', r'heaplens_flutter/lib/widgets/memory_map.dart · the column calculation', r'''
        final columns = constraints.maxWidth.isFinite
            ? ((constraints.maxWidth) / (_kCellSize + _kCellSpacing))
                .floor()
                .clamp(1, 1 << 30)
            : _kDefaultColumnsWhenUnbounded;'''),
    ...code('dart', r'heaplens_flutter/test/widgets/memory_map_test.dart · computes safe column count even when maxWidth is infinite', r'''
  testWidgets('computes safe column count even when maxWidth is infinite',
      (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());

    late ProviderContainer container;
    // Test that MemoryMap can be rendered without the columns calculation
    // throwing when given tight or unusual constraints.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          graphMessageProvider.overrideWith((ref) => controller.stream),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    // Wrap in a very small SizedBox to test within a constrained context,
                    // but the MemoryMap's internal LayoutBuilder will see tight constraints.
                    width: 100,
                    height: 100,
                    child: MemoryMap(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    // Add a node to render.
    final node = _node(id: 1, ptr: 10);
    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: [node]));

    // Should not throw on the columns calculation.
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(MemoryMap), findsOneWidget);
  });'''),
    ...para('//', r'The same commit fixed a crash. The grid computes its column count as floor of the available width divided by the cell pitch of 30 pixels, and calling floor on double.infinity throws an Infinity or NaN to int error. The fix checks isFinite first and uses 20 columns as a default, the constant _kDefaultColumnsWhenUnbounded. A named constant instead of a magic number, with a doc comment about unbounded width.'),
    ...para('//', r'Another honest observation. The test is titled maxWidth is infinite, but it builds a 100 by 100 SizedBox, so the LayoutBuilder sees tight, finite constraints and the guarded branch is not reached. The comment inside the test says the intent is tight or unusual constraints. The guard against infinity has no test that would fail if it were removed, since 100 pixels simply gives three columns (floor of 3.3) and works either way. This is also why the test calls takeException twice.'),
    ...sec(r'what to take away'),
    ...para('//', r'Five of the seven tests do what they say, and the filter tests are the strongest, because each one checks both sides of the rule: the view changes, the data does not. The two added in the fix commit are the weaker pair, and both fixes they were written for live in code that now has no failing test if it is reverted. They are worth tightening: compare cell positions for the ordering, and give the last test an unbounded parent such as a horizontal scroll view.'),
  ],
);
