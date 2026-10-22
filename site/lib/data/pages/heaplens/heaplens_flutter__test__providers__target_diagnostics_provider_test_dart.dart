import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/providers/target_diagnostics_provider_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'target_diagnostics_provider_test.dart — two inputs, two clocks, one diagnosis'),
    cm('//', r'seven tests that feed the classifier from a real graph and an injected clock'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'pins how TargetDiagnosticsNotifier combines stats messages, the node map and elapsed time'),
    kv('language', r'Dart, flutter_test with a ProviderContainer'),
    kv('size', r'179 lines, 7 tests in 1 group'),
    kv('history', r'created in 0edc728 (2026-07-17); the orphan test was added in ead62bb (2026-07-22)'),
    kv('subject', r'lib/providers/target_diagnostics_provider.dart'),
    kv('sibling', r'test/models/target_diagnosis_test.dart pins the pure classifier'),
    ...sec(r'the layer between the classifier and the banner'),
    ...para('//', r'target_diagnosis_test.dart tests classify() as a decision table with hand-picked numbers. This file tests the notifier that supplies those numbers, and the question is different: where do eventsReceived, nodeCount, edgeCount, orphanCount and pastNoEventsWindow actually come from, and are they fresh? The answer in the source is that they come from two inputs on different cadences, GraphStats about once a second and the node map, which can change on every diff.'),
    ...code('dart', r'heaplens_flutter/lib/providers/target_diagnostics_provider.dart · the class and its doc', r'''
/// Derives [TargetDiagnosis] from two independent inputs that arrive on
/// different cadences: [GraphStats] messages (roughly once a second, see
/// heaplens-daemon's main.rs) for events/symbol counters, and the live node
/// map (via [graphProvider]) for node/edge counts, which can change on
/// every [GraphDiff]. Recomputes on every message of either kind so the
/// diagnosis never lags more than one message behind either input.
class TargetDiagnosticsNotifier extends Notifier<TargetDiagnosis> {
  /// Injectable clock so tests can control "how long since we started
  /// observing this session" without real `Duration(seconds: 3)` sleeps.
  /// Mutable (not constructor-injected) because Riverpod constructs
  /// `Notifier`s itself via the bare `.new` factory — tests instead grab
  /// `container.read(targetDiagnosticsProvider.notifier)` and override this
  /// field before pushing messages.
  DateTime Function() now = DateTime.now;'''),
    ...para('//', r'The doc comment states the invariant the tests check: recompute on every message of either kind, so the diagnosis never lags more than one message behind either input.'),
    ...sec(r'the harness: an injectable clock'),
    ...code('dart', r'heaplens_flutter/test/providers/target_diagnostics_provider_test.dart · setUp', r'''
void main() {
  group('TargetDiagnosticsNotifier', () {
    late StreamController<GraphMessage> controller;
    late ProviderContainer container;
    late DateTime clock;

    setUp(() {
      controller = StreamController<GraphMessage>();
      clock = DateTime(2026, 1, 1);
      container = ProviderContainer(
        overrides: [
          graphMessageProvider.overrideWith((ref) => controller.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() => controller.close());

      // Activate the notifier and pin its clock before any message arrives.
      container.read(targetDiagnosticsProvider.notifier).now = () => clock;
      container.listen(targetDiagnosticsProvider, (_, _) {});
    });'''),
    ...para('//', r'The three seconds of the no-events window are a problem for tests. Sleeping that long is slow and flaky. So the notifier has a public mutable field, now, defaulting to DateTime.now, and the test replaces it with a closure over a local variable named clock. The source explains why it is a field and not a constructor argument: Riverpod builds notifiers itself through the bare .new factory, so the test grabs the notifier from the container and overwrites the field before any message arrives. Moving time then costs one assignment.'),
    blank,
    ...para('//', r'The container only overrides graphMessageProvider. graphProvider is real, which is the point: tests in this file populate it through the real notifier, as the app does.'),
    ...sec(r'time-dependent behaviour'),
    ...code('dart', r'heaplens_flutter/test/providers/target_diagnostics_provider_test.dart · initial state', r'''
    test('initial state is capturing with no message', () {
      expect(container.read(targetDiagnosticsProvider).status, TargetStatus.capturing);
      expect(container.read(targetDiagnosticsProvider).message, isNull);
    });'''),
    ...code('dart', r'heaplens_flutter/test/providers/target_diagnostics_provider_test.dart · zero events inside the window', r'''
    test('zero events, still within the no-events window: stays capturing', () async {
      controller.add(const GraphStats(
        ts: 1,
        eventsReceived: 0,
        symbolsResolved: 0,
        hexFallback: 0,
      ));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(targetDiagnosticsProvider).status, TargetStatus.capturing);
    });'''),
    ...para('//', r'Before any message the state is capturing with no message. After the first zero-event stats message, still inside the window, it stays capturing. This is the first observation: that message is what sets _firstObservedAt in the source.'),
    ...code('dart', r'heaplens_flutter/test/providers/target_diagnostics_provider_test.dart · zero events past the window', r'''
    test('zero events, past the no-events window: transitions to noEvents', () async {
      controller.add(const GraphStats(
        ts: 1,
        eventsReceived: 0,
        symbolsResolved: 0,
        hexFallback: 0,
        targetPid: 99,
        targetName: 'idle.exe',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(targetDiagnosticsProvider).status, TargetStatus.capturing);

      // Advance the injected clock past the window and push a second stats
      // message (recompute only happens on message arrival).
      clock = clock.add(kNoEventsWindow + const Duration(seconds: 1));
      controller.add(const GraphStats(
        ts: 2,
        eventsReceived: 0,
        symbolsResolved: 0,
        hexFallback: 0,
        targetPid: 99,
        targetName: 'idle.exe',
      ));
      await Future<void>.delayed(Duration.zero);

      final diag = container.read(targetDiagnosticsProvider);
      expect(diag.status, TargetStatus.noEvents);
      expect(diag.message, contains('idle.exe'));
      expect(diag.message, contains('[99]'));
    });'''),
    ...para('//', r'This test is the clearest use of the injected clock. It sends one zero-event stats message and asserts capturing; then it moves clock forward by kNoEventsWindow plus one second, and sends a second message. Only then does it expect noEvents, with the name idle.exe and [99] in the message. The comment records a subtle rule: recompute happens only when a message arrives. Advancing the clock alone changes nothing. In production that is fine because stats arrive every second, but it means the status can only change when a message arrives.'),
    ...sec(r'combining the node map with stats'),
    ...code('dart', r'heaplens_flutter/test/providers/target_diagnostics_provider_test.dart · nodes without edges, events flowing', r'''
    test('nodes with no edges (via graphProvider) combined with events flowing: noEdges', () async {
      // Populate the node map directly through graphProvider, as the real
      // app does via its own listener on the same graphMessageProvider
      // stream.
      container.read(graphProvider.notifier).applyDiff(
        GraphSnapshot(ts: 1, nodes: [_node(id: 1), _node(id: 2), _node(id: 3)]),
      );

      controller.add(const GraphStats(
        ts: 1,
        eventsReceived: 500,
        symbolsResolved: 10,
        hexFallback: 0,
      ));
      await Future<void>.delayed(Duration.zero);

      final diag = container.read(targetDiagnosticsProvider);
      expect(diag.status, TargetStatus.noEdges);
      expect(diag.nodeCount, 3);
      expect(diag.edgeCount, 0);
    });'''),
    ...para('//', r'Three live nodes are put in the map by calling applyDiff on the real graph notifier, and a stats message with 500 events and ten resolved symbols is pushed. The result is noEdges, with nodeCount 3 and edgeCount 0. The comment explains the shortcut: the real app populates the map via its own listener on the same stream. The test asserts the counts on the diagnosis as well, which proves they were read from the map and not defaulted.'),
    ...code('dart', r'heaplens_flutter/test/providers/target_diagnostics_provider_test.dart · a diff alone recomputes', r'''
    test('a later Diff message (no accompanying Stats) still recomputes node/edge counts', () async {
      controller.add(const GraphStats(ts: 1, eventsReceived: 500, symbolsResolved: 10, hexFallback: 0));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(targetDiagnosticsProvider).status, TargetStatus.capturing);

      // A diff arrives that adds nodes with no edges, with no new Stats
      // message accompanying it — the diagnosis must still update because
      // _handleMessage recomputes on every message, not only on Stats.
      controller.add(GraphDiff(ts: 2, add: [_node(id: 1), _node(id: 2)], update: [], remove: []));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(targetDiagnosticsProvider).status, TargetStatus.noEdges);
    });'''),
    ...para('//', r'The most telling test for the design. Stats arrive first with 500 events and an empty map, which classifies as capturing. Then a diff adds two edgeless nodes, with no stats message at all, and the status becomes noEdges. If the notifier recomputed only on stats, this would stay capturing until the next second. The comment says it directly: recompute on every message, not only on Stats. This also exercises ordering. The diff reaches the graph notifier and the diagnostics notifier through the same stream, and the diagnostics notifier reads the node map. It only sees the new nodes because graph_provider registered its listener first.'),
    ...para('//', r'The source has a line to make that ordering hold: ref.read(graphProvider) at the top of build(), with a comment pointing at the same ordering hazard documented in main.dart. This test builds the diagnostics notifier first and populates the graph only through the stream, so it is the test that exercises that ordering.'),
    ...sec(r'the orphan and symbol branches through the notifier'),
    ...code('dart', r'heaplens_flutter/test/providers/target_diagnostics_provider_test.dart · mostly orphaned', r'''
    test('nodes mostly orphaned (via graphProvider), symbols fully resolved: '
        'noEdgesOrphaned, not the symbol-envelope message', () async {
      container.read(graphProvider.notifier).applyDiff(
        GraphSnapshot(
          ts: 1,
          nodes: List.generate(
            10,
            (i) => _node(id: i, state: NodeStateDto.orphan),
          ),
        ),
      );

      controller.add(const GraphStats(
        ts: 1,
        eventsReceived: 500,
        symbolsResolved: 10,
        hexFallback: 0,
      ));
      await Future<void>.delayed(Duration.zero);

      final diag = container.read(targetDiagnosticsProvider);
      expect(diag.status, TargetStatus.noEdgesOrphaned);
      expect(diag.message, isNot(contains('lacks the debug symbols')));
      expect(diag.message, contains('10 of 10 allocations are currently orphaned'));
    });'''),
    ...para('//', r'Ten orphan nodes, ten resolved symbols, zero hex fallback, 500 events. The expected status is noEdgesOrphaned, the message must not contain lacks the debug symbols, and must contain 10 of 10 allocations are currently orphaned. This test arrived in ead62bb with the fix: the classifier had learned about orphanCount, and the notifier needed to supply it. The source computes it in _recompute by counting live nodes whose state is orphan. Without that wire, classify() would receive its default of zero and the old wrong message would reappear, and the model test alone could not notice.'),
    ...code('dart', r'heaplens_flutter/test/providers/target_diagnostics_provider_test.dart · predominantly hex', r'''
    test('predominantly hex-fallback symbols alongside no edges: unsymbolized, folded into the noEdges message', () async {
      container.read(graphProvider.notifier).applyDiff(
        GraphSnapshot(ts: 1, nodes: List.generate(10, (i) => _node(id: i))),
      );
      controller.add(const GraphStats(
        ts: 1,
        eventsReceived: 500,
        symbolsResolved: 1,
        hexFallback: 99,
      ));
      await Future<void>.delayed(Duration.zero);

      final diag = container.read(targetDiagnosticsProvider);
      expect(diag.status, TargetStatus.unsymbolized);
      expect(diag.message, contains('Symbols unavailable for this target.'));
    });'''),
    ...para('//', r'One resolved and 99 hex fallback with ten edgeless nodes gives unsymbolized, with the generic Symbols unavailable text folded into the noEdges message. It checks that the symbol counters are forwarded from the stats message into the classifier.'),
    ...sec(r'details the tests make visible'),
    ...pt('//', r'live nodes only', r'_recompute filters to live nodes before counting nodes, edges and orphans. All test nodes are live, so the filter is not distinguished here; graph_provider_test covers the live/dead split in the getters, but not this filter.'),
    ...pt('//', r'no pause gate', r'unlike graph_provider.dart, this notifier does not consult pausedProvider (lib/providers/target_diagnostics_provider.dart lines 41-43). While the user has paused the view, the node map is frozen but new stats still change the diagnosis. No test addresses this, and the code does not say whether it is intended.'),
    ...pt('//', r'session start', r'_firstObservedAt is set once and never reset. The notifier does not distinguish a second attach in the same app run, so the window is measured from the first stats message of the whole run. The source comment admits the start time is only an approximation, since the daemon exports no attach timestamp.'),
  ],
);
