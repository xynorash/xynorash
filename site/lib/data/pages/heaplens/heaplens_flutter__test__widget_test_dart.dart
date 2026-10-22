import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/widget_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'widget_test.dart — the whole app, with a fake daemon'),
    cm('//', r'three widget tests that run main.dart exactly as shipped'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'app-level smoke tests for main.dart wiring: lifecycle, pause gate, view toggle'),
    kv('language', r'Dart, flutter_test widget tests'),
    kv('size', r'217 lines, 3 testWidgets'),
    kv('history', r'scaffolded 56d5e41 (2026-07-06), rewritten 23b80e4 (2026-07-06), pause test added 4ad9349 (2026-07-06)'),
    kv('exercises', r'HeapLensApp, _GraphOrchestrator, forceLayoutProvider, pausedProvider, viewModeProvider'),
    ...sec(r'why this test exists'),
    ...para('//', r'Every other test in heaplens_flutter/test looks at one piece: a model, a provider, a painter, a widget. None of them can notice a mistake in the glue. And main.dart is mostly glue. It contains a private widget called _GraphOrchestrator whose only job is to sit between the websocket stream and the physics engine: it forwards each GraphMessage into the shared ForceLayout and ticks the simulation on a timer. That wiring was the last task of milestone 5 (commit 23b80e4), and this file is its safety net.'),
    blank,
    ...para('//', r'The file started life as the stub that flutter create generates (56d5e41 scaffolded it). 23b80e4 replaced it with the first and third tests below, and 4ad9349 added the second one. Its message says the pause gate in the orchestrator was previously untested, so a regression removing the check would pass.'),
    ...sec(r'the harness: a stream you control'),
    ...para('//', r'The trick that makes an app-level test possible without a daemon is one override. graphMessageProvider is the single entry point where decoded websocket messages enter the app. Replacing it with a StreamController stream means the test is the daemon: it decides which snapshot or diff arrives, and when.'),
    ...code('dart', r'heaplens_flutter/test/widget_test.dart · testWidgets 1, setup', r'''
  testWidgets(
      'app builds, renders a static graph through the full '
      'snapshot -> diff(update) -> diff(remove) lifecycle, and drives the '
      'shared ForceLayout accordingly', (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());

    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          graphMessageProvider.overrideWith((ref) => controller.stream),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const HeapLensApp();
          },
        ),
      ),
    );
    await tester.pump();'''),
    ...para('//', r'Two details are worth reading closely. The Consumer wrapper exists only to capture the ProviderContainer into a late variable, so later lines can read and write providers (forceLayoutProvider, pausedProvider) from outside the widget tree. And addTearDown closes the controller, so a failing assertion does not leave an open stream behind.'),
    blank,
    ...para('//', r'The helper at the top, _node, gives every NodeDto field a harmless default (64 bytes, symbol sym, healthy, no edges). Each test then names only the field it cares about, so the intent of a node reads at a glance: _node(id: 2, state: NodeStateDto.orphan) is an orphan and nothing more.'),
    ...code('dart', r'heaplens_flutter/test/widget_test.dart · _node helper', r'''
NodeDto _node({
  required int id,
  int ptr = 0,
  int size = 64,
  int ts = 0,
  String symbol = 'sym',
  bool live = true,
  NodeStateDto state = NodeStateDto.healthy,
  List<int> edges = const [],
}) {
  return NodeDto(
    id: id,
    ptr: ptr,
    size: size,
    ts: ts,
    symbol: symbol,
    live: live,
    state: state,
    edges: edges,
  );
}'''),
    ...sec(r'test 1: snapshot, update, remove'),
    ...para('//', r'The first test walks one node set through the three message shapes the daemon can send, and after each step checks both the physics state and tester.takeException(). The second check matters as much as the first: takeException returns any exception the framework caught while building or painting, so asserting it is null states explicitly that the lifecycle ran without a build or paint error.'),
    blank,
    ...pt('//', r'snapshot', r'two nodes, with an edge from 1 to 2 and node 2 marked orphan. The test asserts the shared layout holds SimNodes for exactly ids 1 and 2. Reading forceLayoutProvider from the container proves the orchestrator and the test see the same ForceLayout instance.'),
    ...pt('//', r'diff with update', r'node 1 comes back with size 4096. The assertion is that the key set is still {1, 2}. A same-id update must change the node in place, not spawn a second SimNode, so this is a duplicate-body guard.'),
    ...pt('//', r'diff with remove', r'node 2 is removed. Right afterwards it must still be in simNodes. Removal starts a fade rather than deleting immediately, and that is what keeps freed allocations visible as ghosts for a moment.'),
    ...code('dart', r'heaplens_flutter/test/widget_test.dart · step 1: the snapshot', r'''
    controller.add(
      GraphSnapshot(
        ts: 1,
        nodes: [
          _node(id: 1, edges: [2]),
          _node(id: 2, state: NodeStateDto.orphan),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    final layout = container.read(forceLayoutProvider);
    expect(layout.simNodes.keys.toSet(), {1, 2});
    expect(tester.takeException(), isNull);'''),
    ...code('dart', r'heaplens_flutter/test/widget_test.dart · step 3: remove, then wait out the fade', r'''
    // Diff: remove node 2 — starts a fade, still present immediately after.
    controller.add(GraphDiff(ts: 3, add: [], update: [], remove: [2]));
    await tester.pump();
    await tester.pump();

    expect(layout.simNodes.containsKey(2), isTrue);
    expect(tester.takeException(), isNull);

    // Advance enough physics ticks (30Hz, driven by the orchestrator's own
    // Timer.periodic — advance real+fake time together) for the ~1s fade to
    // complete and the SimNode to be deleted.
    await tester.pump(const Duration(seconds: 2));

    expect(layout.simNodes.containsKey(2), isFalse);
    expect(layout.simNodes.containsKey(1), isTrue);
    expect(tester.takeException(), isNull);'''),
    ...para('//', r'The last block is the interesting one. tester.pump(const Duration(seconds: 2)) advances the fake clock by two seconds, and the orchestrator owns a Timer.periodic at 33 ms that calls layout.step. The comment in the test says it plainly: the physics timer runs under the fake-async zone, so one pump of two seconds drives roughly sixty ticks, enough for the fade of about one second to finish. Afterwards node 2 must be gone and node 1 must still be there. That single check covers the timer being created, the step function being called, and the fade completing, which no unit test of ForceLayout alone could say about the real app.'),
    ...sec(r'test 2: the pause gate'),
    ...para('//', r'The control bar has a pause button. Pausing is supposed to freeze the picture: counters stop, nodes stop appearing. There are two consumers of the message stream, graph_provider.dart and the orchestrator, and each has its own check of pausedProvider. If only one side were gated, the canvas would keep animating new nodes while the counters stayed frozen. The orchestrator comment in main.dart says it mirrors the provider gate exactly; this test is what keeps that sentence true.'),
    ...code('dart', r'heaplens_flutter/test/widget_test.dart · baseline, pause, push a diff', r'''
    // Establish a baseline node before pausing, so we can tell "nothing new
    // arrived" apart from "nothing has ever arrived".
    controller.add(GraphSnapshot(ts: 1, nodes: [_node(id: 1)]));
    await tester.pump();
    await tester.pump();

    final layout = container.read(forceLayoutProvider);
    expect(layout.simNodes.keys.toSet(), {1});

    // Pause, then push a diff that adds a new node.
    container.read(pausedProvider.notifier).state = true;
    controller.add(
      GraphDiff(ts: 2, add: [_node(id: 2)], update: [], remove: []),
    );
    await tester.pump();
    await tester.pump();

    // The pause gate in `_GraphOrchestratorState._handleMessage` should have
    // dropped the message before it ever reached `ForceLayout`.
    expect(layout.simNodes.keys.toSet(), {1});
    expect(layout.simNodes.containsKey(2), isFalse);
    expect(tester.takeException(), isNull);'''),
    ...para('//', r'Notice the baseline. A node 1 is added first, so the final expectation, simNodes keys equal to {1}, can tell two failure modes apart. If the gate were broken, node 2 would appear. If nothing had ever reached the layout, the set would be empty rather than {1}. Without the baseline, the test could not distinguish "paused correctly" from "never connected at all".'),
    ...sec(r'test 3: the view toggle'),
    ...para('//', r'The third test is short and structural. By default the centre of the window shows GraphCanvas and no MemoryMap. Writing ViewMode.memoryMap into viewModeProvider swaps them, and writing ViewMode.graph swaps back. Each state is checked with findsOneWidget on one side and findsNothing on the other, so it fails both if the wrong widget appears and if both are mounted at once.'),
    ...code('dart', r'heaplens_flutter/test/widget_test.dart · toggle there and back', r'''
    // Defaults to graph view.
    expect(find.byType(GraphCanvas), findsOneWidget);
    expect(find.byType(MemoryMap), findsNothing);

    container.read(viewModeProvider.notifier).state = ViewMode.memoryMap;
    await tester.pump();

    expect(find.byType(GraphCanvas), findsNothing);
    expect(find.byType(MemoryMap), findsOneWidget);

    container.read(viewModeProvider.notifier).state = ViewMode.graph;
    await tester.pump();

    expect(find.byType(GraphCanvas), findsOneWidget);
    expect(find.byType(MemoryMap), findsNothing);'''),
    ...para('//', r'Mounting only one of the two matters beyond looks. GraphCanvas runs its own 60 fps animation controller for the pulsing rings. If both stayed mounted, the canvas would keep running its animation controller; the findsNothing assertions are what rule that out.'),
    ...sec(r'the unmount line at the end of each test'),
    ...para('//', r'Each test ends with await tester.pumpWidget(const SizedBox()). That is not cosmetic. The orchestrator starts its Timer.periodic in initState and cancels it in dispose. flutter_test runs each test in a fake-async zone and fails the test if a timer is still pending at teardown, so without the unmount the test would pass its assertions and then fail on cleanup. The comments in all three tests repeat the reason; the line is in effect an assertion that dispose cancels the timer.'),
    ...code('dart', r'heaplens_flutter/test/widget_test.dart · the teardown', r'''
    // Unmount so `_GraphOrchestratorState.dispose()` cancels its physics
    // `Timer.periodic` — otherwise flutter_test's fake-async zone flags it
    // as a leaked pending timer at test teardown.
    await tester.pumpWidget(const SizedBox());'''),
    ...sec(r'what it does not cover'),
    ...pt('//', r'listener ordering', r'main.dart documents a known, dev-only hazard: if graphProvider is invalidated or hot-reloaded, its listener moves behind the orchestrator and a single new node can spawn near the canvas centre instead of near its owner. The tests never invalidate the provider, so they do not exercise it. The code comment calls it cosmetic and says it self-corrects on the next message.'),
    ...pt('//', r'freed updates', r'an update whose state is freed does not start a fade in the orchestrator, only a remove does. The comment explains the daemon never emits that state for a live node, so no test asserts it.'),
    ...pt('//', r'the stats branch', r'GraphStats messages are ignored by the orchestrator. Here no stats message is sent, so that branch is covered only by the provider tests.'),
    ...sec(r'how it fits'),
    ...para('//', r'Think of it as three layers of Flutter tests. Model tests (contract_test, control_test) pin the wire shapes. Provider and widget tests pin one component each, with the neighbours faked. This file is the only one that mounts HeapLensApp itself, so when a component test and an integration disagree, this is where the disagreement shows. It is deliberately small: three tests, one fake stream, and a clear rule that anything it checks must be visible through the shared ForceLayout or the widget tree.'),
  ],
);
