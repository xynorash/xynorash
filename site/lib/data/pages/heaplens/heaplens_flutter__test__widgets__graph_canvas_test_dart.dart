import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/widgets/graph_canvas_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'graph_canvas_test.dart — a canvas that passed 77 tests while blank'),
    cm('//', r'seven widget tests around a CustomPainter, including the one that checks it draws'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'pins tap selection, ghost and filter handling, fade painting and, via paints, real draw calls'),
    kv('language', r'Dart, flutter_test widget tests with the paints matcher'),
    kv('size', r'463 lines, 7 testWidgets'),
    kv('history', r'ed689f6 and 7b3b9c7 and fea8519 (2026-07-06); 091d71f (2026-07-07); 1cfb7f9 (2026-07-19); ead62bb (2026-07-22)'),
    kv('subject', r'lib/widgets/graph_canvas.dart'),
    ...sec(r'the hardest thing to test in a UI'),
    ...para('//', r'GraphCanvas is a CustomPainter that draws circles, edges, glows and pulsing rings for the ownership graph. A painter has no text to find and no buttons to tap, and an exception inside paint reaches the test only through the framework’s takeException. So the first five tests below are the natural tests of such a widget: it builds, it reacts to taps, it survives odd states, and takeException stays null. Then 091d71f added a test whose title is a confession.'),
    ...sec(r'what the widget needs from outside'),
    ...code('dart', r'heaplens_flutter/test/widgets/graph_canvas_test.dart · a layout built by hand', r'''
    final layout = ForceLayout(centerX: 200, centerY: 200, random: Random(1));
    final nodeA = _node(id: 1, state: NodeStateDto.healthy, edges: [2]);
    final nodeB = _node(id: 2, state: NodeStateDto.orphan);
    final currentNodes = {1: nodeA, 2: nodeB};
    layout.addNode(nodeA, currentNodes);
    layout.addNode(nodeB, currentNodes);
    layout.step(0.016);'''),
    ...para('//', r'GraphCanvas takes a ForceLayout through its constructor and reads node data from graphProvider. Both sides must agree on the ids. The tests build the layout themselves, with a seeded Random and an explicit centre, and add nodes to it directly. Then they feed the same nodes to the provider with applyDiff. Doing it by hand, and not through the orchestrator, lets a test create states the orchestrator would never produce, such as a SimNode with no NodeDto.'),
    ...sec(r'test 1: it paints'),
    ...code('dart', r'heaplens_flutter/test/widgets/graph_canvas_test.dart · paints a small static graph without throwing', r'''
  testWidgets('paints a small static graph without throwing', (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());

    final layout = ForceLayout(centerX: 200, centerY: 200, random: Random(1));
    final nodeA = _node(id: 1, state: NodeStateDto.healthy, edges: [2]);
    final nodeB = _node(id: 2, state: NodeStateDto.orphan);
    final currentNodes = {1: nodeA, 2: nodeB};
    layout.addNode(nodeA, currentNodes);
    layout.addNode(nodeB, currentNodes);
    layout.step(0.016);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          graphMessageProvider.overrideWith((ref) => controller.stream),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: GraphCanvas(layout: layout),
            ),
          ),
        ),
      ),
    );

    // Populate the graph provider's node map so paint has NodeDto data to
    // cross-reference against the layout's SimNodes.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GraphCanvas)),
    );
    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: [nodeA, nodeB]));
    await tester.pump();

    // A couple more pumps to exercise the pulsing-ring AnimatedBuilder path.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(GraphCanvas), findsOneWidget);
    expect(tester.takeException(), isNull);
  });'''),
    ...para('//', r'Two nodes with an edge between them, one orphan, a single physics step, then the widget. The comment about the extra pumps is the key to why there are three: the canvas has a 60 fps AnimationController for the pulsing rings of orphan nodes, and pumping 100 ms twice exercises that AnimatedBuilder path. The pass condition is the absence of exceptions. That is a weak claim, and the file later says so itself.'),
    ...sec(r'test 2: where a tap lands'),
    ...code('dart', r'heaplens_flutter/test/widgets/graph_canvas_test.dart · tap at a known node position selects that node', r'''
  testWidgets('tap at a known node position selects that node', (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());

    final layout = ForceLayout(centerX: 200, centerY: 200, random: Random(2));
    final node = _node(id: 42, state: NodeStateDto.healthy);
    layout.addNode(node, {42: node});
    // Pin the node's position/radius so we know exactly where to tap.
    layout.simNodes[42]!.position.setValues(150, 150);
    layout.simNodes[42]!.radius = 20;

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
                  child: GraphCanvas(layout: layout),
                ),
              ),
            );
          },
        ),
      ),
    );

    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: [node]));
    await tester.pump();

    expect(container.read(selectedNodeIdProvider), isNull);

    // The GraphCanvas is laid out starting at the SizedBox's top-left. Since
    // there's no extra offset above it in this tree, node-local (150, 150)
    // maps directly to that same global point.
    await tester.tapAt(const Offset(150, 150));
    await tester.pump();

    expect(container.read(selectedNodeIdProvider), 42);
  });'''),
    ...para('//', r'To tap a circle you have to know where it is, so the test pins the SimNode at (150, 150) with radius 20 and taps exactly there. The comment explains why the coordinates need no conversion: the canvas starts at the top-left of the SizedBox and nothing offsets it, so local equals global. Selection goes through selectedNodeIdProvider, null before and 42 after.'),
    ...code('dart', r'heaplens_flutter/lib/widgets/graph_canvas.dart · the hit test in the widget', r'''
    final tapPos = Vector2(
      details.localPosition.dx,
      details.localPosition.dy,
    );

    int? bestId;
    var bestDist = double.infinity;
    for (final entry in widget.layout.simNodes.entries) {
      final sim = entry.value;
      final dist = (sim.position - tapPos).length;
      if (dist <= sim.radius && dist < bestDist) {
        bestDist = dist;
        bestId = entry.key;
      }
    }'''),
    ...para('//', r'The widget side is a loop over simNodes that keeps the nearest node whose distance to the tap is at most its radius. The tests here only exercise a tap in the middle of a single circle, so they do not cover two overlapping circles, where dist < bestDist decides, nor the edge of a radius.'),
    ...sec(r'test 3: a SimNode with no NodeDto'),
    ...code('dart', r'heaplens_flutter/test/widgets/graph_canvas_test.dart · tap at a SimNode with no NodeDto backing', r'''
  testWidgets(
      'tap at a SimNode with no NodeDto backing does not select it',
      (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());

    final layout = ForceLayout(centerX: 200, centerY: 200, random: Random(3));
    // Create a node and add it to the layout so it exists in simNodes.
    final ghostNode = _node(id: 99, state: NodeStateDto.healthy);
    layout.addNode(ghostNode, {99: ghostNode});
    // Pin the node's position/radius so we know exactly where to tap.
    layout.simNodes[99]!.position.setValues(250, 250);
    layout.simNodes[99]!.radius = 20;

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
                  child: GraphCanvas(layout: layout),
                ),
              ),
            );
          },
        ),
      ),
    );

    // Intentionally do NOT add ghostNode to the node map via applyDiff.
    // This simulates the transient state where a SimNode exists but its
    // NodeDto has been removed (e.g., mid-fade-out after removal).
    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: []));
    await tester.pump();

    expect(container.read(selectedNodeIdProvider), isNull);

    // Try to tap on the ghost node. The tap handler should find it in
    // simNodes but must NOT select it because it has no NodeDto backing.
    await tester.tapAt(const Offset(250, 250));
    await tester.pump();

    // selectedNodeIdProvider should remain null/unchanged.
    expect(container.read(selectedNodeIdProvider), isNull);
  });'''),
    ...para('//', r'Commit 7b3b9c7 added a guard to the tap handler and this test with it. During diff application the layout can still hold a SimNode, for example mid-fade after a removal, whose NodeDto is already gone from the provider. Selecting that id would point the detail panel at nothing. The test builds exactly that state: it adds a node to the layout at (250, 250), but applies an empty snapshot to the provider, taps on it, and expects the selection to stay null. The comment says it plainly: the handler finds the node in simNodes but must not select it.'),
    ...code('dart', r'heaplens_flutter/lib/widgets/graph_canvas.dart · the guard in the widget', r'''
    // without a matching NodeDto during diff application (e.g.,
    // mid-fade-out after removal) — avoid selecting a ghost id that has no
    // NodeDto backing. A node hidden by a filter shouldn't be selectable via
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
        ref.read(selectedNodeIdProvider.notifier).state = bestId;
      }
    }
  }

  @override'''),
    ...para('//', r'The guard that makes the test pass is the nodes[bestId] lookup, which returns null for a missing id. It was written first as only an existence check, and later grew filter checks in the same condition.'),
    ...sec(r'test 4: a fading ghost keeps painting'),
    ...code('dart', r'heaplens_flutter/test/widgets/graph_canvas_test.dart · a removed node keeps painting', r'''
  testWidgets(
      'a removed node keeps painting (fading ghost) after its NodeDto is '
      'gone from the graph provider map', (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());

    final layout = ForceLayout(centerX: 200, centerY: 200, random: Random(4));
    final node = _node(id: 77, state: NodeStateDto.orphan);
    layout.addNode(node, {77: node});

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
                  child: GraphCanvas(layout: layout),
                ),
              ),
            );
          },
        ),
      ),
    );

    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: [node]));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Mirror main.dart's orchestrator: the same message-processing step
    // removes the NodeDto from graph_provider's map AND starts the
    // ForceLayout fade for the same id.
    container.read(graphProvider.notifier).applyDiff(
          const GraphDiff(ts: 2, add: [], update: [], remove: [77]),
        );
    layout.removeNode(77);
    await tester.pump();

    // NodeDto is gone...
    expect(
      container.read(graphProvider.notifier).nodes.containsKey(77),
      isFalse,
    );
    // ...but the SimNode is still mid-fade, with a captured last-known
    // state, and the widget must keep painting it without throwing.
    expect(layout.simNodes.containsKey(77), isTrue);
    expect(layout.simNodes[77]!.lastKnownState, equals(NodeStateDto.orphan));
    expect(tester.takeException(), isNull);

    // Advance the fade partway and pump again: still mid-fade, still must
    // render without crashing.
    layout.step(0.5);
    await tester.pump();
    expect(layout.simNodes.containsKey(77), isTrue);
    expect(layout.simNodes[77]!.fade, lessThan(1.0));
    expect(layout.simNodes[77]!.fade, greaterThan(0.0));
    expect(tester.takeException(), isNull);
  });'''),
    ...para('//', r'This is the visible half of the fade-out feature (fea8519). The test mirrors what main.dart does for a remove message: it removes the NodeDto from the provider and calls layout.removeNode for the same id. Then it asserts the pieces of the contract. The NodeDto is gone from the provider map. The SimNode is still there with lastKnownState equal to orphan. After layout.step(0.5), the fade value is strictly between 0 and 1. At each stage takeException must be null.'),
    ...para('//', r'What it does not assert is that anything is drawn. The title says keeps painting, but the body proves that painting a SimNode without a NodeDto does not throw, which is what the old code did. A painter that skipped the ghost entirely would also pass. The paints matcher used in the later tests would close that gap.'),
    ...sec(r'test 5: the filter applies to what you can click'),
    ...code('dart', r'heaplens_flutter/test/widgets/graph_canvas_test.dart · min-size filter hides a node from painting and hit-testing', r'''
  testWidgets(
      'min-size filter hides a node from graph-view painting and hit-testing',
      (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());

    final layout = ForceLayout(centerX: 200, centerY: 200, random: Random(6));
    final small = _node(id: 1, size: 8);
    final big = _node(id: 2, size: 4096);
    layout.addNode(small, {1: small, 2: big});
    layout.addNode(big, {1: small, 2: big});
    // Pin positions so we know exactly where to tap.
    layout.simNodes[1]!.position.setValues(100, 100);
    layout.simNodes[1]!.radius = 20;
    layout.simNodes[2]!.position.setValues(300, 300);
    layout.simNodes[2]!.radius = 20;

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
                  child: GraphCanvas(layout: layout),
                ),
              ),
            );
          },
        ),
      ),
    );

    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: [small, big]));
    await tester.pump();

    // Before filtering: tapping the small node selects it.
    await tester.tapAt(const Offset(100, 100));
    await tester.pump();
    expect(container.read(selectedNodeIdProvider), 1);

    container.read(selectedNodeIdProvider.notifier).state = null;
    container.read(minSizeFilterProvider.notifier).state = 100;
    await tester.pump();
    expect(tester.takeException(), isNull);

    // After filtering: the small node is hidden from hit-testing...
    await tester.tapAt(const Offset(100, 100));
    await tester.pump();
    expect(container.read(selectedNodeIdProvider), isNull);

    // ...but the big node remains tappable...
    await tester.tapAt(const Offset(300, 300));
    await tester.pump();
    expect(container.read(selectedNodeIdProvider), 2);

    // ...and the underlying node map is untouched by the filter.
    expect(container.read(graphProvider.notifier).nodes.length, 2);
  });'''),
    ...para('//', r'The control bar sets minSizeFilterProvider and the canvas has to respect it twice: in what it draws and in what it lets you select. A node you cannot see should not be selectable by tapping where it used to be. The test places a small node (8 bytes) at (100, 100) and a big one (4096) at (300, 300). Before filtering, tapping the small one selects it. Then it clears the selection, sets the filter to 100, and taps the same spot again. The selection must stay null. The big node must remain tappable, and the provider map must still hold both.'),
    ...para('//', r'That last line matters. The comment in the widget says the filters are about what the view chooses to draw. A filter that deleted data would make the controls destructive. This is the same rule that memory_map_test.dart checks for the grid.'),
    ...sec(r'test 6: the one about 77 tests'),
    ...code('dart', r'heaplens_flutter/test/widgets/graph_canvas_test.dart · regression: painter actually draws circles', r'''
  testWidgets(
      'regression: painter actually draws circles when the provider is '
      'populated, and draws nothing when it is empty — the test class '
      'missing before fix/canvas-render (77 tests passed with a blank '
      'canvas, none of them asserted anything was actually painted)',
      (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());

    final layout = ForceLayout(centerX: 200, centerY: 200, random: Random(7));
    final node = _node(id: 1, state: NodeStateDto.healthy);
    layout.addNode(node, {1: node});
    layout.simNodes[1]!.position.setValues(150, 150);
    layout.simNodes[1]!.radius = 20;

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
                  child: GraphCanvas(layout: layout),
                ),
              ),
            );
          },
        ),
      ),
    );

    // Empty provider: no *nodes* to paint. The painter now always draws a
    // faint background HUD grid regardless of data (see graph_canvas.dart
    // `_paintGrid` — a persistent scale reference, not conditional on
    // there being anything to show), so "paints nothing at all" is no
    // longer the right assertion; tightened to "paints no circles" per
    // this test's own original guidance above.
    await tester.pump();
    expect(find.byKey(const Key('graphCanvasPaint')), isNot(paints..circle()));

    // Populate: the painter must now actually issue a drawCircle call for
    // the live node. This is the assertion class that would have caught a
    // dead render path (revision/simNodes populated correctly upstream,
    // but the painter never invoked, or invoked with stale/empty data).
    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: [node]));
    await tester.pump();
    expect(find.byKey(const Key('graphCanvasPaint')), paints..circle());
  });'''),
    ...para('//', r'The title of this test tells a story and the commit message of 091d71f tells the rest. At the end of milestone 5 there were 77 tests passing while a person looking at the live app saw a blank canvas. Every existing test either asserted that nothing was thrown, or tested hit-testing and selection. None asserted that anything was drawn. The commit says it used the paints matcher from flutter_test, which records actual Canvas calls, to check that nothing is drawn for an empty provider and a circle is drawn once populated. And the commit also records the control experiment: the author temporarily commented out the node drawCircle call, saw the test fail exactly as expected, and reverted it. That is how you know a regression test can fail.'),
    ...para('//', r'The same commit is honest about the real cause. A live trace with a new debug overlay found no rendering bug: nodes render, persist for a 60 second hold, and fade on removal. The most likely explanation was that the producer used in the demo ran a burst-and-free lifetime of about two seconds, which a human could easily miss, and a slower demo producer was added. So the test did not fix a bug; it closed a blind spot in the test suite.'),
    ...para('//', r'A later edit, in the comment inside the test, records that the painter now always draws a faint background grid, so paints nothing at all is no longer the right assertion for an empty graph. The test was tightened to isNot(paints..circle()): no circles, grid allowed. The test finds the painter by Key(graphCanvasPaint), which the widget attaches to its CustomPaint for exactly this purpose.'),
    ...sec(r'test 7: selection must not recolour'),
    ...code('dart', r'heaplens_flutter/test/widgets/graph_canvas_test.dart · a selected orphan keeps its state colour', r'''
  testWidgets(
      'regression: a selected orphan node keeps its state-derived coral '
      'fill and additionally gets the selection ring — selection must never '
      'override the state color', (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());

    final layout = ForceLayout(centerX: 200, centerY: 200, random: Random(8));
    final node = _node(id: 5, state: NodeStateDto.orphan);
    layout.addNode(node, {5: node});
    layout.simNodes[5]!.position.setValues(150, 150);
    layout.simNodes[5]!.radius = 20;

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
                  child: GraphCanvas(layout: layout),
                ),
              ),
            );
          },
        ),
      ),
    );

    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: [node]));
    await tester.pump();

    await tester.tapAt(const Offset(150, 150));
    await tester.pump();
    expect(container.read(selectedNodeIdProvider), 5);

    // Paint order (graph_canvas.dart's `_paintNodes`): glow, base fill,
    // orphan pulsing ring, selection glow, selection ring — `paints`
    // matches each chained `.circle()` against the *next* drawCircle call,
    // so the base fill's position in that sequence (2nd) must be
    // accounted for rather than matched as "any circle".
    //
    // The base fill color must still be the state color (coral for
    // orphan), not overridden by selection...
    expect(
      find.byKey(const Key('graphCanvasPaint')),
      paints
        ..circle() // glow
        ..circle(color: kNodeStateColors[NodeStateDto.orphan]), // base fill
    );
    // ...and the cyan selection ring must additionally be present further
    // along in the same paint sequence (additive, not a replacement).
    expect(
      find.byKey(const Key('graphCanvasPaint')),
      paints
        ..circle() // glow
        ..circle() // base fill
        ..circle() // orphan pulsing ring
        ..circle() // selection glow (cyan, alpha 0.5)
        ..circle(color: XynorashTheme.cyan), // selection ring (cyan, alpha 1.0)
    );
  });'''),
    ...para('//', r'This one was added in ead62bb, in the commit about the misleading banner. During live testing a selected orphan node looked as if it lost its coral colour, and this was suspected to be a second bug. The commit message says it did not reproduce, neither on inspection of the paint code nor by sampling pixels of the original screenshot, so the test was added as a defensive guard going forward.'),
    ...para('//', r'It is the most detailed use of the paints matcher in the file. Each chained circle() matches the next drawCircle call in order, so the test has to know the paint order, which the comment lists: glow, base fill, orphan pulsing ring, selection glow, selection ring. The first expectation says the second circle, the base fill, has the colour kNodeStateColors[orphan]. The second expectation says that after glow, fill and ring, a cyan selection glow and then a cyan ring follow. Together: selection is additive, never a replacement for the state colour.'),
    ...para('//', r'Because the matcher is order-sensitive, this test is also coupled to the paint order. If someone inserts a new circle before the base fill, it will fail even though behaviour is correct; the comment in the test is there so the failure is understandable.'),
    ...sec(r'what the file does not test'),
    ...pt('//', r'drawn edges', r'no assertion about lines between nodes; there is a pair of connected nodes in test 1, but only for the no-throw check.'),
    ...pt('//', r'aggregated bubbles', r'the canvas also paints aggregate nodes when there are over 500 live nodes; ForceLayout tests the mode switch, this file never reaches it.'),
    ...pt('//', r'the grid and the debug overlay', r'mentioned in comments, not asserted.'),
    ...pt('//', r'repetition', r'six tests copy the same twenty-line pumpWidget block instead of a shared helper like the one other widget tests use.'),
  ],
);
