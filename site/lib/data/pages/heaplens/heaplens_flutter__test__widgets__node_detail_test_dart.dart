import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/widgets/node_detail_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'node_detail_test.dart — one allocation, up close'),
    cm('//', r'six widget tests for the side panel, one of them about time running backwards'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'pins the NodeDetail panel: placeholder states, field rendering, age against a rolling max'),
    kv('language', r'Dart, flutter_test widget tests'),
    kv('size', r'229 lines, 6 testWidgets'),
    kv('history', r'8d22db5 (2026-07-06) created it; 0661725 (2026-07-06) added the monotonic age test; 1cfb7f9 (2026-07-19) adjusted it for the UI refresh'),
    kv('subject', r'NodeDetail in lib/widgets/node_detail.dart'),
    ...sec(r'the panel'),
    ...para('//', r'Click a circle in the graph or a cell in the memory map and the right rail shows the facts about that allocation: symbol, pointer in hex, size, age, state, owner, and how many allocations it owns. NodeDetail is that panel. It reads two providers, the selection and the node map, and has one piece of its own state, which turns out to be the subject of the most interesting test.'),
    ...code('dart', r'heaplens_flutter/lib/widgets/node_detail.dart · the doc comment and the rolling max', r'''
/// The "Node detail" right-rail panel: full field detail for the currently
/// selected node ([selectedNodeIdProvider]) — symbol, ptr (hex), size,
/// age, state (as a plain-language color chip, paired with the raw state
/// name via its tooltip), owner (id + ptr), edge count.
///
/// Renders an explicit [EmptyState] when nothing is selected, or when the
/// selected id no longer exists in the node map (e.g. it was removed by a
/// `remove` diff) — never crashes on a stale selection.
///
/// The size-over-time sparkline is a separate right-rail panel
/// ([NodeSparklinePanel]) per the UI refresh's panel grouping — this
/// widget only renders the raw/technical field list.
class NodeDetail extends ConsumerStatefulWidget {
  const NodeDetail({super.key});

  @override
  ConsumerState<NodeDetail> createState() => _NodeDetailState();
}

class _NodeDetailState extends ConsumerState<NodeDetail> {
  /// Client-side rolling max of `ts` across all nodes ever seen, analogous
  /// to the daemon's own `max_ts_seen` (see graph.rs:'''),
    ...sec(r'the harness'),
    ...code('dart', r'heaplens_flutter/test/widgets/node_detail_test.dart · _pumpNodeDetail', r'''
Future<ProviderContainer> _pumpNodeDetail(
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
          return const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 400,
                child: NodeDetail(),
              ),
            ),
          );
        },
      ),
    ),
  );
  return container;
}'''),
    ...para('//', r'As in the other widget tests, the stream is overridden with a controllable one and a Consumer captures the container, so tests can write the selection and the node map directly. The panel sits in a 400 by 400 box. Almost all assertions use find.text, so the tests read like a description of what a user sees.'),
    ...sec(r'two ways to show nothing'),
    ...code('dart', r'heaplens_flutter/test/widgets/node_detail_test.dart · nothing selected', r'''
  testWidgets('renders placeholder when nothing selected', (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    await _pumpNodeDetail(tester, controller);

    expect(find.text('> no node selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });'''),
    ...para('//', r'With no selection the panel shows the text > no node selected. In the source, the string is passed to an EmptyState widget with an icon; the leading prompt character comes from that widget, and this test fixes the visible string.'),
    ...code('dart', r'heaplens_flutter/test/widgets/node_detail_test.dart · a stale selection', r'''
  testWidgets(
      'renders placeholder when selected id no longer exists in node map',
      (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpNodeDetail(tester, controller);

    final node = _node(id: 1, ptr: 10);
    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: [node]));
    container.read(selectedNodeIdProvider.notifier).state = 1;
    await tester.pump();

    expect(find.text('sym'), findsOneWidget);

    // Remove the node entirely via a diff.
    container.read(graphProvider.notifier).applyDiff(
          GraphDiff(ts: 2, add: const [], update: const [], remove: const [1]),
        );
    await tester.pump();

    expect(find.text('> no node selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });'''),
    ...para('//', r'The second placeholder test protects against a crash that real data makes likely. The user selects node 1, then a remove diff deletes it, while selectedNodeIdProvider still says 1. The test makes that exact sequence: select, see the symbol sym, remove through the graph notifier, and expect the placeholder, with no exception. The source comment is explicit about why: show a placeholder rather than risk a null lookup. An allocator churns, so a selected node being freed is the normal case and not an edge case.'),
    ...sec(r'all the fields at once'),
    ...code('dart', r'heaplens_flutter/test/widgets/node_detail_test.dart · symbol, ptr, size, state, owner, edges', r'''
  testWidgets(
      'renders symbol/ptr(hex)/size/state/owner/edge-count for a selected node',
      (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpNodeDetail(tester, controller);

    // node 1 owns node 2 (edges contains 2); node 2 is selected.
    final owner = _node(id: 1, ptr: 0x10, symbol: 'owner_sym', edges: [2]);
    final selected = _node(
      id: 2,
      ptr: 0xABCD,
      size: 512,
      symbol: 'target_sym',
      state: NodeStateDto.orphan,
      edges: [3, 4],
    );
    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: [owner, selected]));
    container.read(selectedNodeIdProvider.notifier).state = 2;
    await tester.pump();

    expect(find.text('target_sym'), findsOneWidget);
    expect(find.text('0xabcd'), findsOneWidget);
    expect(find.text('512'), findsOneWidget);
    expect(find.text('orphan'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // owner id
    expect(find.text('2'), findsOneWidget); // edge count
  });'''),
    ...para('//', r'Two nodes are built so that every field has a distinct, recognisable value. The owner has id 1 and lists 2 in its edges. The selected node is id 2 with pointer 0xABCD, size 512, symbol target_sym, state orphan, and edges [3, 4]. The expectations: the symbol text, the pointer rendered as 0xabcd in lower-case hex (not 0xABCD), 512, the word orphan, 1 as the owner id and 2 as the number of edges. The owner is not stored on the node. The panel finds it by scanning every node for one whose edges contain the selected id, which is why the test must build an owner whose edge list points back.'),
    ...para('//', r'The lookups for 1 and 2 use find.text with findsOneWidget, so they rely on no other text in the panel being exactly those digits. With the chosen values that holds. The owner row also shows its pointer in parentheses, but that part is not asserted.'),
    ...sec(r'age is not wall-clock time'),
    ...code('dart', r'heaplens_flutter/test/widgets/node_detail_test.dart · age computes against rolling max ts seen', r'''
  testWidgets(
      'age computes against rolling max ts seen, not wall-clock',
      (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpNodeDetail(tester, controller);

    // Use ts values wildly far from real wall-clock epoch millis, to prove
    // age is derived purely from observed ts values.
    const farFutureTs = 999999999999;
    final selected = _node(id: 1, ts: farFutureTs - 500, symbol: 'aged');
    final other = _node(id: 2, ts: farFutureTs, symbol: 'newer');
    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: [selected, other]));
    container.read(selectedNodeIdProvider.notifier).state = 1;
    await tester.pump();

    // maxTsSeen (farFutureTs, from `other`) - selected.ts (farFutureTs - 500) = 500.
    expect(find.text('500'), findsOneWidget);
  });'''),
    ...para('//', r'A node’s age is shown as the difference between the newest timestamp the panel has seen and the node’s own timestamp. The test picks timestamps around 999,999,999,999, far away from any real clock, and expects exactly 500. If the panel compared against DateTime.now the answer would be some huge unrelated number. It is a quiet way of locking the units: the producer’s own clock ticks, as the row’s tooltip in the source says, not milliseconds since the epoch.'),
    ...sec(r'the bug where age went backwards'),
    ...code('dart', r'heaplens_flutter/test/widgets/node_detail_test.dart · age does not decrease when the node carrying the max ts is removed', r'''
  testWidgets(
      'age does not decrease when the node carrying the max ts is removed',
      (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpNodeDetail(tester, controller);

    // Selected node has ts=100. A second node arrives with ts=300 (the
    // current max), making age = 300 - 100 = 200.
    final selected = _node(id: 1, ts: 100, symbol: 'selected');
    final other = _node(id: 2, ts: 300, symbol: 'other');
    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: [selected, other]));
    container.read(selectedNodeIdProvider.notifier).state = 1;
    await tester.pump();

    expect(find.text('200'), findsOneWidget);

    // Remove `other` -- the node that carried the observed max ts. A naive
    // "recompute max from currently-live nodes" implementation would now
    // see only `selected` (ts=100) and report age=0, i.e. age would
    // visibly decrease. The rolling max must be persisted and monotonic,
    // so age must stay at 200.
    container.read(graphProvider.notifier).applyDiff(
          GraphDiff(ts: 2, add: const [], update: const [], remove: const [2]),
        );
    await tester.pump();

    expect(find.text('selected'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });'''),
    ...para('//', r'Commit 0661725 states the problem in terms of what a user would see. The first version recomputed the maximum timestamp from scratch on every build by scanning only the nodes currently alive. When the newest node was freed, which happens constantly, the maximum dropped, and the displayed age of a selected node snapped toward zero and climbed back up. The test reproduces it with two nodes: the selected one at ts 100, another at ts 300, so the age is 200. Then the other node is removed. A naive implementation sees only ts 100 and shows 0. The correct answer is that 200 stays on screen.'),
    ...code('dart', r'heaplens_flutter/lib/widgets/node_detail.dart · the fix: a persisted, monotonic max', r'''
/// ([NodeSparklinePanel]) per the UI refresh's panel grouping — this
/// widget only renders the raw/technical field list.
class NodeDetail extends ConsumerStatefulWidget {
  const NodeDetail({super.key});

  @override
  ConsumerState<NodeDetail> createState() => _NodeDetailState();
}

class _NodeDetailState extends ConsumerState<NodeDetail> {
  /// Client-side rolling max of `ts` across all nodes ever seen, analogous
  /// to the daemon's own `max_ts_seen` (see graph.rs:'''),
    ...para('//', r'The fix keeps _maxTsSeen on the State object and only ever raises it with max, mirroring a pattern in the daemon’s own graph code, where the field is updated with a max of the old value and each event’s timestamp. The comment in the source says exactly why it is state and not recomputed: churn like alloc-then-free must not make the age snap backwards. Note the test also asserts that the selected symbol is still on screen, so the node was not removed by mistake, and that no exception was thrown.'),
    ...para('//', r'The state lives as long as the widget does. It is not reset when the selection changes. So the maximum is across the whole session, which is the daemon-like behaviour the comment wants. The test does not cover a change of selection, so it does not say whether that was a choice or an accident.'),
    ...sec(r'switching selection'),
    ...code('dart', r'heaplens_flutter/test/widgets/node_detail_test.dart · switching selection to a different node', r'''
  testWidgets(
      'switching selection to a different node does not crash and shows '
      'the new node\'s data', (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpNodeDetail(tester, controller);

    final nodeA = _node(id: 1, ts: 1, size: 100, symbol: 'a');
    final nodeB = _node(id: 2, ts: 1, size: 200, symbol: 'b');
    container
        .read(graphProvider.notifier)
        .applyDiff(GraphSnapshot(ts: 1, nodes: [nodeA, nodeB]));
    container.read(selectedNodeIdProvider.notifier).state = 1;
    await tester.pump();

    // Grow node A's size a few times while selected.
    for (final size in [110, 120, 130]) {
      container.read(graphProvider.notifier).applyDiff(
            GraphDiff(
              ts: size,
              add: const [],
              update: [_node(id: 1, ts: size, size: size, symbol: 'a')],
              remove: const [],
            ),
          );
      await tester.pump();
    }

    container.read(selectedNodeIdProvider.notifier).state = 2;
    await tester.pump();

    expect(find.text('b'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Switch back to node A: must not crash or retain node B's samples.
    container.read(selectedNodeIdProvider.notifier).state = 1;
    await tester.pump();

    expect(find.text('a'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });'''),
    ...para('//', r'The last test selects node A, grows its size three times with update diffs (110, 120, 130), then switches to B and back to A, asserting after each switch that the right symbol is on screen and nothing was thrown. A comment says that the switch back must not retain node B’s samples. That comment is a leftover. When the test was written (8d22db5) the sparkline lived inside NodeDetail, and a buffer reset on selection change was a real risk. The UI refresh moved the sparkline into NodeSparklinePanel, so what the test now protects is the simpler claim: NodeDetail rebuilds correctly after repeated updates and selection changes.'),
    ...sec(r'what is out of reach'),
    ...pt('//', r'the sparkline panel', r'NodeSparklinePanel, which now owns the size-over-time chart, is mounted by no test in the suite. Its buffer is covered by sparkline_buffer_test.dart, its wiring is not.'),
    ...pt('//', r'the chip and tooltips', r'the state chip and the tooltips with plain-language descriptions are not checked. The test finds the raw word orphan in the state row only.'),
    ...pt('//', r'two owners', r'the owner lookup keeps the last node in map order that lists the selected id. If a node were listed by two owners, the result would depend on iteration order, and no test builds that case.'),
  ],
);
