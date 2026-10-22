import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/providers/graph_provider_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'graph_provider_test.dart — the node map that every widget reads'),
    cm('//', r'thirteen tests for a notifier whose state is a counter, not the data'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'pins applyDiff semantics, the revision counter, derived getters and stream wiring'),
    kv('language', r'Dart, flutter_test with a ProviderContainer'),
    kv('size', r'257 lines, 13 tests in 3 groups'),
    kv('history', r'8f1c59d (2026-07-06) created it, 872430a (2026-07-06) added the immutability test, 0edc728 (2026-07-17) added the stats test'),
    kv('subject', r'lib/providers/graph_provider.dart'),
    ...sec(r'the unusual design under test'),
    ...para('//', r'GraphNotifier breaks a Riverpod habit on purpose. Its state is not the node map; it is an int, the revision. The map itself is a private Map that is mutated in place on every message. The comment on the class calls this a locked decision and gives the reason: the daemon can push diffs at up to about thirty per second, and rebuilding or copying a large immutable map that often is wasteful. Widgets watch the revision to know when to repaint, and read the data separately through notifier.nodes.'),
    ...code('dart', r'heaplens_flutter/lib/providers/graph_provider.dart · the class and its doc comment', r'''
/// Owns the live ownership-graph node map and republishes a monotonically
/// increasing [revision] counter as its Riverpod state.
///
/// INTENTIONAL DESIGN (locked decision, see M5 task-3 brief Q3): this
/// `Notifier`'s state is the `revision` int, *not* the node map itself. The
/// node map ([_nodes]) is a private `Map<int, NodeDto>` that is mutated in
/// place on every [applyDiff] call. This deliberately breaks the usual
/// Riverpod convention of treating state as immutable data — it is a
/// performance escape valve, because the daemon can push graph diffs at up
/// to ~30/sec and rebuilding/copying a large map that often is wasteful.
/// Widgets should `ref.watch(graphProvider)` (the revision int) purely to
/// know *when* to rebuild/repaint, and separately call
/// `ref.read(graphProvider.notifier).nodes` (or the derived getters below)
/// to read the current data. Do NOT "fix" this back into an immutable map
/// — that would defeat the purpose.
class GraphNotifier extends Notifier<int> {'''),
    ...para('//', r'That design moves the guarantees from the type system into behaviour, and behaviour is what this file tests: the counter must move exactly when the map moves, the map must never be mutable from outside, and each message must change the map in exactly the documented way.'),
    ...sec(r'the fixture: a container with a fake stream'),
    ...code('dart', r'heaplens_flutter/test/providers/graph_provider_test.dart · setUp', r'''
void main() {
  group('GraphNotifier.applyDiff', () {
    late ProviderContainer container;
    late StreamController<GraphMessage> controller;

    setUp(() {
      controller = StreamController<GraphMessage>();
      container = ProviderContainer(
        overrides: [
          graphMessageProvider.overrideWith((ref) => controller.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() => controller.close());
      // Activate the notifier (and its ref.listen to graphMessageProvider).
      container.listen(graphProvider, (_, _) {});
    });'''),
    ...para('//', r'Each test gets a fresh ProviderContainer whose graphMessageProvider is overridden with a StreamController stream, the same trick widget_test.dart uses at app level. The last line of setUp matters: container.listen(graphProvider, ...) activates the notifier. Riverpod providers are lazy, and GraphNotifier registers its listener on the message stream inside build(), so until something reads the provider the stream has no subscriber. Most tests in this group call applyDiff directly and never touch the stream, which keeps them synchronous.'),
    ...sec(r'how applyDiff treats each message'),
    ...code('dart', r'heaplens_flutter/test/providers/graph_provider_test.dart · initial state and snapshots', r'''
    test('initial revision is 0 and node map is empty', () {
      expect(container.read(graphProvider), 0);
      expect(container.read(graphProvider.notifier).nodes, isEmpty);
    });

    test('snapshot replaces prior state entirely', () {
      final notifier = container.read(graphProvider.notifier);
      notifier.applyDiff(GraphSnapshot(ts: 1, nodes: [_node(id: 1), _node(id: 2)]));
      expect(container.read(graphProvider), 1);
      expect(notifier.nodes.keys.toSet(), {1, 2});

      // A second, disjoint snapshot fully replaces the map — id 1/2 gone.
      notifier.applyDiff(GraphSnapshot(ts: 2, nodes: [_node(id: 3)]));
      expect(container.read(graphProvider), 2);
      expect(notifier.nodes.keys.toSet(), {3});
    });'''),
    ...para('//', r'Starting point: revision 0, empty map. A snapshot is a full replace, and the test proves it with two snapshots that share no ids. After the second one the map holds only id 3 and the revision is 2. A merge instead of a replace would leave ids 1 and 2 in place, and the keys.toSet() comparison fails on any extra key.'),
    ...code('dart', r'heaplens_flutter/test/providers/graph_provider_test.dart · add, update, remove', r'''
    test('diff add inserts new nodes', () {
      final notifier = container.read(graphProvider.notifier);
      notifier.applyDiff(
        GraphDiff(ts: 1, add: [_node(id: 1), _node(id: 2)], update: [], remove: []),
      );
      expect(container.read(graphProvider), 1);
      expect(notifier.nodes.keys.toSet(), {1, 2});
    });

    test('diff update by id changes fields without duplicating', () {
      final notifier = container.read(graphProvider.notifier);
      notifier.applyDiff(
        GraphDiff(ts: 1, add: [_node(id: 1, symbol: 'first')], update: [], remove: []),
      );
      notifier.applyDiff(
        GraphDiff(
          ts: 2,
          add: [],
          update: [_node(id: 1, symbol: 'second', state: NodeStateDto.orphan)],
          remove: [],
        ),
      );

      expect(notifier.nodes, hasLength(1));
      final updated = notifier.nodes[1]!;
      expect(updated.symbol, 'second');
      expect(updated.state, NodeStateDto.orphan);
    });

    test('diff remove deletes by id', () {
      final notifier = container.read(graphProvider.notifier);
      notifier.applyDiff(
        GraphDiff(ts: 1, add: [_node(id: 1), _node(id: 2)], update: [], remove: []),
      );
      notifier.applyDiff(GraphDiff(ts: 2, add: [], update: [], remove: [1]));

      expect(notifier.nodes.keys.toSet(), {2});
    });'''),
    ...para('//', r'Add inserts. Update by id changes fields without duplicating, and the check is hasLength(1) plus the new symbol and state: the update changes both the symbol and the state to orphan, so it also shows that the whole NodeDto is replaced, not patched field by field. Remove deletes by id.'),
    ...sec(r'forgiving about edge cases'),
    ...code('dart', r'heaplens_flutter/test/providers/graph_provider_test.dart · no-op remove and upsert', r'''
    test('remove of an id not present is a no-op, not an error', () {
      final notifier = container.read(graphProvider.notifier);
      notifier.applyDiff(
        GraphDiff(ts: 1, add: [_node(id: 1)], update: [], remove: []),
      );
      expect(
        () => notifier.applyDiff(
          GraphDiff(ts: 2, add: [], update: [], remove: [888]),
        ),
        returnsNormally,
      );
      // Existing node untouched, no crash, still one node.
      expect(notifier.nodes.keys.toSet(), {1});
      expect(container.read(graphProvider), 2);
    });

    test('update for an id not previously seen upserts it (per the '
        '"add/update are both upsert by id" contract), not a no-op', () {
      final notifier = container.read(graphProvider.notifier);
      notifier.applyDiff(
        GraphDiff(ts: 1, add: [], update: [_node(id: 999)], remove: []),
      );
      expect(notifier.nodes.keys, contains(999));
      expect(container.read(graphProvider), 1);
    });'''),
    ...para('//', r'Two tests encode how the notifier treats a stream that is not perfectly consistent. Removing an id that is not present is a no-op (returnsNormally), the existing node stays, and the revision still increments to 2: a message was applied, even if it changed nothing. And an update for an id never seen before is an upsert, not a no-op; the title quotes the contract, add and update are both upsert by id. The effect is that an update for a node the client has not seen puts it on screen rather than being dropped.'),
    blank,
    ...para('//', r'The notifier does not try to detect that case. It treats every entry as the freshest truth.'),
    ...sec(r'the revision contract'),
    ...code('dart', r'heaplens_flutter/test/providers/graph_provider_test.dart · one bump per call', r'''
    test('revision increments exactly once per applyDiff call regardless of '
        'payload size', () {
      final notifier = container.read(graphProvider.notifier);
      final manyNodes = List.generate(50, (i) => _node(id: i));
      notifier.applyDiff(GraphDiff(ts: 1, add: manyNodes, update: [], remove: []));
      expect(container.read(graphProvider), 1);

      notifier.applyDiff(GraphDiff(ts: 2, add: [], update: [], remove: []));
      expect(container.read(graphProvider), 2);
    });'''),
    ...para('//', r'Fifty added nodes bump the revision by one, and an empty diff also bumps it by one. The count is per message, not per node. That is what keeps widget rebuilds proportional to the message rate rather than to the node count. The second half of the test is slightly stranger: an empty diff still moves the revision. It is the cost of not comparing the map before and after, and the doc comment accepts it: one message, one bump.'),
    ...code('dart', r'heaplens_flutter/test/providers/graph_provider_test.dart · stats leave the map alone', r'''
    test('a GraphStats message does not touch the node map or bump revision', () {
      final notifier = container.read(graphProvider.notifier);
      notifier.applyDiff(GraphDiff(ts: 1, add: [_node(id: 1)], update: [], remove: []));
      expect(container.read(graphProvider), 1);

      notifier.applyDiff(const GraphStats(
        ts: 2,
        eventsReceived: 10,
        symbolsResolved: 5,
        hexFallback: 1,
      ));

      expect(container.read(graphProvider), 1, reason: 'stats messages are not node data');
      expect(notifier.nodes.keys.toSet(), {1});
    });'''),
    ...para('//', r'GraphStats is the exception. It is a session-counter message that arrived with the diagnostics work (0edc728), and applyDiff returns early on it before reaching the revision bump. The test applies a diff, then a stats message, and asserts the revision is still 1 and the map unchanged. Without the early return, the once-a-second stats broadcast would trigger a repaint of the whole graph every second for nothing, as the source comment says.'),
    ...sec(r'the nodes getter is read-only'),
    ...code('dart', r'heaplens_flutter/test/providers/graph_provider_test.dart · UnmodifiableMapView', r'''
    test('returned nodes map is immutable — mutations throw UnsupportedError', () {
      final notifier = container.read(graphProvider.notifier);
      notifier.applyDiff(
        GraphDiff(ts: 1, add: [_node(id: 1)], update: [], remove: []),
      );
      final nodesView = notifier.nodes;

      // Attempting to mutate via assignment throws.
      expect(
        () => nodesView[999] = _node(id: 999),
        throwsUnsupportedError,
      );

      // Attempting to clear throws.
      expect(
        () => nodesView.clear(),
        throwsUnsupportedError,
      );

      // Attempting to remove throws.
      expect(
        () => nodesView.remove(1),
        throwsUnsupportedError,
      );

      // The internal state is unchanged.
      expect(notifier.nodes.keys.toSet(), {1});
    });'''),
    ...para('//', r'The getter returns UnmodifiableMapView over the private map, a change made by 872430a right after the first version, whose message says it was for encapsulation. The test tries three mutations from outside, an index assignment, clear and remove, and requires throwsUnsupportedError for each, then checks the map is intact. Notice what the view is and is not: it is a view, not a copy, so it still shows later changes. The source comment warns callers not to hold a reference across a revision, and this test does not cover that, only the write side.'),
    ...sec(r'one parsing test that lives here'),
    ...code('dart', r'heaplens_flutter/test/providers/graph_provider_test.dart · unknown state string', r'''
    test('unknown state string on a raw JSON node falls back to healthy '
        'via NodeDto.fromJson/fromWire', () {
      final json = {
        'id': 1,
        'ptr': 0,
        'size': 8,
        'ts': 0,
        'symbol': 'sym',
        'live': true,
        'state': 'some_future_state',
        'edges': <int>[],
      };
      final node = NodeDto.fromJson(json);
      final notifier = container.read(graphProvider.notifier);
      notifier.applyDiff(GraphSnapshot(ts: 1, nodes: [node]));
      expect(notifier.nodes[1]!.state, NodeStateDto.healthy);
    });'''),
    ...para('//', r'This test sits oddly in a provider file: it builds a raw JSON node with state some_future_state, runs it through NodeDto.fromJson, applies it as a snapshot, and expects healthy. It restates the leniency pinned in contract_test.dart, but goes one step further, through the notifier, to show that a future daemon state does not break the graph.'),
    ...sec(r'derived getters'),
    ...code('dart', r'heaplens_flutter/test/providers/graph_provider_test.dart · orphanCount, liveNodeCount, totalLiveBytes', r'''
    group('derived getters', () {
      test('orphanCount, liveNodeCount, totalLiveBytes computed on demand', () {
        final notifier = container.read(graphProvider.notifier);
        notifier.applyDiff(
          GraphSnapshot(
            ts: 1,
            nodes: [
              _node(id: 1, live: true, size: 10, state: NodeStateDto.healthy),
              _node(id: 2, live: true, size: 20, state: NodeStateDto.orphan),
              _node(id: 3, live: false, size: 30, state: NodeStateDto.orphan),
            ],
          ),
        );

        expect(notifier.orphanCount, 2);
        expect(notifier.liveNodeCount, 2);
        expect(notifier.totalLiveBytes, 30); // only live nodes: 10 + 20
      });
    });'''),
    ...para('//', r'Three nodes: a live healthy one of 10 bytes, a live orphan of 20 and a dead orphan of 30. The expected values show the definitions: orphanCount counts orphans regardless of liveness (2), liveNodeCount counts the live flag (2), and totalLiveBytes sums only live sizes (30, not 60). The dead orphan is the interesting row because it separates the three getters; with only live nodes, a wrong filter would go unnoticed.'),
    ...pt('//', r'not tested', r'ownerCount, the fourth getter in graph_provider.dart (lines 97-98), which feeds the top bar’s Owners metric, has no test in this file.'),
    ...sec(r'the stream wiring, asynchronously'),
    ...code('dart', r'heaplens_flutter/test/providers/graph_provider_test.dart · automatic wiring', r'''
  group('GraphNotifier automatic wiring to graphMessageProvider', () {
    test('applies messages that arrive on the live stream without manual '
        'feeding, bumping revision once per message', () async {
      final controller = StreamController<GraphMessage>();
      final container = ProviderContainer(
        overrides: [
          graphMessageProvider.overrideWith((ref) => controller.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() => controller.close());

      final revisions = <int>[];
      container.listen(graphProvider, (_, next) => revisions.add(next));
      // Ensure the notifier (and its ref.listen) is built before pushing.
      container.read(graphProvider);

      controller.add(GraphSnapshot(ts: 1, nodes: [_node(id: 1), _node(id: 2)]));
      await Future<void>.delayed(Duration.zero);

      expect(revisions, [1]);
      expect(container.read(graphProvider.notifier).nodes.keys.toSet(), {1, 2});

      controller.add(GraphDiff(ts: 2, add: [], update: [], remove: [1]));
      await Future<void>.delayed(Duration.zero);

      expect(revisions, [1, 2]);
      expect(container.read(graphProvider.notifier).nodes.keys.toSet(), {2});
    });
  });'''),
    ...para('//', r'The final group is the only async one. Messages pushed to the controller must reach applyDiff without the test feeding them. It listens to the provider and collects every revision it emits into a list, pushes a snapshot, waits one event-loop turn with Future.delayed(Duration.zero), and expects the list to be [1]; then pushes a diff and expects [1, 2]. Collecting the sequence instead of reading the final value is what proves one bump per message, not merely a final value of 2.'),
    ...pt('//', r'pause gate', r'graph_provider.dart line 39 drops messages while pausedProvider is true. That branch is not exercised in this file; control_bar_test.dart tests the toggle and widget_test.dart tests the matching gate in the orchestrator.'),
    ...sec(r'why it is written this way'),
    ...para('//', r'All tests reach the notifier through the container, never constructing GraphNotifier directly. The Notifier needs a Ref to exist, and going through the container tests the real provider, including its stream subscription. The helper _node with defaults keeps every row to the one field it is about. The result is a file that reads as the specification of a data structure: what goes in, what the counter does, and what may never be done to the map from outside.'),
  ],
);
