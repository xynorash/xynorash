import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/providers/target_diagnostics_provider.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'target_diagnostics_provider.dart — why does the graph look like that?'),
    cm('//', r'two inputs on two clocks, one honest sentence out'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'derives a TargetDiagnosis from Stats messages and the live node map'),
    kv('language', r'Dart / Riverpod'),
    kv('size', r'91 lines, 7 provider tests'),
    kv('history', r'2 commits: 0edc728 (2026-07-17), ead62bb (2026-07-22)'),
    kv('test', r'test/providers/target_diagnostics_provider_test.dart'),
    kv('read by', r'widgets/target_status_banner.dart'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'An empty canvas is ambiguous. It can mean the target is '
        r'idle, that it uses a heap path the hook does not cover, '
        r'that allocations flow but no ownership could be inferred, '
        r'or that everything has leaked. Before this file, all of '
        r'those looked the same: a dark rectangle, and a person '
        r'wondering whether the tool was broken. The commit that '
        r'added it says what it is for in its first line: honest '
        r'target-status banner, so the user is not left staring at a '
        r'blank graph.'),
    ...para('//',
        r'The classification itself lives in the model, '
        r'TargetDiagnosis.classify, which is a pure function from '
        r'counters to a status and a sentence. This provider is the '
        r'plumbing that feeds it, and the plumbing is where the '
        r'interesting problem is: the inputs arrive on different '
        r'clocks.'),
    ...sec(r'two inputs, two cadences'),
    ...code('dart', 'heaplens_flutter/lib/providers/target_diagnostics_provider.dart · lines 9-29', r'''
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
  DateTime Function() now = DateTime.now;

  DateTime? _firstObservedAt;
  int _eventsReceived = 0;
  int _symbolsResolved = 0;
  int _hexFallback = 0;
  int? _targetPid;
  String? _targetName;'''),
    ...para('//',
        r'Event and symbol counters come from the daemon’s Stats '
        r'message, which the commit message gives as a one second '
        r'cadence. Node and edge counts come from the graph, which '
        r'changes on every diff. A provider that recomputed only on '
        r'Stats would show a node count up to a second old; one that '
        r'recomputed only on diffs would never notice that events '
        r'stopped. So it recomputes on every message of either kind, '
        r'and the doc comment states the resulting guarantee: the '
        r'diagnosis never lags more than one message behind either '
        r'input.'),
    ...para('//',
        r'The notifier keeps the counters as private fields, '
        r'overwritten wholesale by each Stats message. They are '
        r'totals reported by the daemon, not increments, so there is '
        r'nothing to accumulate and a missed message costs nothing. '
        r'The injectable clock is a mutable field and not a '
        r'constructor argument, with the reason in the comment: '
        r'Riverpod builds Notifiers itself from the bare .new '
        r'factory, so a test reaches in through the notifier and '
        r'overrides now before pushing messages.'),
    ...sec(r'the ordering hazard'),
    ...code('dart', 'heaplens_flutter/lib/providers/target_diagnostics_provider.dart · lines 31-46', r'''
  @override
  TargetDiagnosis build() {
    // Force GraphNotifier.build() to run first, registering its own
    // ref.listen(graphMessageProvider, ...) ahead of ours — mirrors the
    // ordering hazard documented on main.dart's _GraphOrchestrator class:
    // without this, a Diff/Snapshot message could reach our listener before
    // graph_provider.dart has applied it, and _recompute() would read stale
    // node/edge counts for that one message.
    ref.read(graphProvider);

    ref.listen<AsyncValue<GraphMessage>>(graphMessageProvider, (previous, next) {
      next.whenData(_handleMessage);
    });

    return TargetDiagnosis.initial();
  }'''),
    ...para('//',
        r'The first statement of build is not obvious and is the one '
        r'I would least want to lose. It reads graphProvider just to '
        r'force GraphNotifier.build() to run, which registers that '
        r'notifier’s own listener on the message stream before this '
        r'one. The design relies on listeners firing in the order '
        r'they were registered. Without the read, a Diff could reach '
        r'this listener first, and the recompute would count nodes '
        r'and edges from a map that had not yet applied that diff, '
        r'so the diagnosis would be wrong for exactly one message. '
        r'The comment cites the same hazard documented for the '
        r'orchestrator in main.dart. It is the second place in the '
        r'app with this ordering rule; the first is the orchestrator '
        r'in main.dart, which guards itself the same way.'),
    ...sec(r'recomputing'),
    ...code('dart', 'heaplens_flutter/lib/providers/target_diagnostics_provider.dart · lines 48-82', r'''
  void _handleMessage(GraphMessage message) {
    if (message is GraphStats) {
      _firstObservedAt ??= now();
      _eventsReceived = message.eventsReceived;
      _symbolsResolved = message.symbolsResolved;
      _hexFallback = message.hexFallback;
      _targetPid = message.targetPid;
      _targetName = message.targetName;
    }
    _recompute();
  }

  void _recompute() {
    final notifier = ref.read(graphProvider.notifier);
    final liveNodes = notifier.nodes.values.where((n) => n.live);
    final nodeCount = liveNodes.length;
    final edgeCount = liveNodes.fold<int>(0, (sum, n) => sum + n.edges.length);
    final orphanCount =
        liveNodes.where((n) => n.state == NodeStateDto.orphan).length;

    final pastWindow = _firstObservedAt != null &&
        now().difference(_firstObservedAt!) >= kNoEventsWindow;

    state = TargetDiagnosis.classify(
      eventsReceived: _eventsReceived,
      symbolsResolved: _symbolsResolved,
      hexFallback: _hexFallback,
      nodeCount: nodeCount,
      edgeCount: edgeCount,
      pastNoEventsWindow: pastWindow,
      targetPid: _targetPid,
      targetName: _targetName,
      orphanCount: orphanCount,
    );
  }'''),
    ...para('//',
        r'Only a Stats message updates the stored counters; every '
        r'message then triggers a recompute. The first Stats message '
        r'sets _firstObservedAt with the null-aware assignment and '
        r'it is never touched again. The recompute scans the live '
        r'nodes three ways: the count, the sum of edge list lengths, '
        r'and the number in the orphan state. It then asks whether '
        r'the no-events window has passed, and hands everything to '
        r'the classifier.'),
    ...para('//',
        r'The window matters. A target that has produced zero events '
        r'for 3 seconds (kNoEventsWindow) is probably idle; a target '
        r'at second one may just be starting. The model’s comment is '
        r'candid about the measurement: the daemon exports no attach '
        r'timestamp, so the window runs from when this client first '
        r'saw the session. It calls that an acceptable approximation '
        r'for a banner and not a precision measurement.'),
    ...sec(r'what the classifier decides'),
    ...pt('//', r'capturing',
        r'default, and the state before any evidence. The banner '
        r'renders nothing.'),
    ...pt('//', r'noEvents',
        r'zero events past the window. The message names the target '
        r'when the daemon supplied a name and pid.'),
    ...pt('//', r'noEdges / unsymbolized',
        r'allocations flow, but fewer than 5 percent of nodes have '
        r'an edge. If at least 80 percent of symbols are hex '
        r'fallbacks the status is unsymbolized, else noEdges.'),
    ...pt('//', r'noEdgesOrphaned',
        r'the same low edge ratio, explained by orphans: at least '
        r'half the nodes are orphans and symbols are fine. Added in '
        r'ead62bb.'),
    ...sec(r'the bug that added the fourth state'),
    ...para('//',
        r'The second commit exists because of a live session. The '
        r'message says that, running against a checkout service, the '
        r'banner claimed the target lacked debug symbols while the '
        r'counters showed 111 of 111 symbols resolved and none '
        r'falling back to hex. The real cause was that every node '
        r'had become an orphan. An orphan has no owner and so no '
        r'owning edge, which yields the same low edge ratio for an '
        r'entirely different, benign reason. The fix passes '
        r'orphanCount into classify and adds the new status; this '
        r'provider’s part of it is the three lines that count '
        r'orphans. The symptom was a false accusation by the banner, '
        r'and the discriminating fact was one the app already had.'),
    ...sec(r'edge cases and sharp edges'),
    ...pt('//', r'first observed is permanent',
        r'the field is assigned once and nothing in this file clears '
        r'it. In the daemon, events_received is declared once in '
        r'main.rs and only ever incremented; I found no place that '
        r'resets it on attach. So after a first target has produced '
        r'events, the counter stays above zero for the life of the '
        r'daemon process, and the no-events window is not re-armed '
        r'for a later target. I read the daemon source for this but '
        r'did not run it.'),
    ...pt('//', r'window needs a message',
        r'the status can only change when a message arrives, which '
        r'is why the test pushes a second Stats to move out of the '
        r'window. With the daemon sending one per second this is '
        r'fine; if the Stats stream stopped, the banner would stay '
        r'where it was.'),
    ...pt('//', r'pause',
        r'this provider does not read the pause flag, so the '
        r'diagnosis keeps updating while the graph is frozen.'),
    ...pt('//', r'cost',
        r'each diff walks all live nodes three times. At the scales '
        r'this app draws that is negligible, and it is not measured.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'Seven cases in '
        r'test/providers/target_diagnostics_provider_test.dart, '
        r'built around a stream controller standing in for the '
        r'message provider and the injectable clock. The initial '
        r'state is capturing with no message. Zero events inside the '
        r'window stays capturing. Zero events past the window, after '
        r'the clock is advanced by the window plus a second, flips '
        r'to noEvents and the message contains the name idle.exe and '
        r'[99]. Nodes without edges, with events flowing, give '
        r'noEdges, and a later Diff with no Stats still recomputes '
        r'the counts. Ten orphaned nodes with all symbols resolved '
        r'give noEdgesOrphaned, the message is asserted not to '
        r'contain lacks the debug symbols, and it must contain 10 of '
        r'10 allocations are currently orphaned. Mostly hex symbols '
        r'with no edges give unsymbolized folded into the noEdges '
        r'message.'),
    ...sec(r'history'),
    ...pt('//', r'0edc728 (2026-07-17)',
        r'feat(target-diagnostics): banner and daemon observability '
        r'counters. The daemon side forwards the handshake’s pid and '
        r'name and adds a Stats message; this file is the Flutter '
        r'half.'),
    ...pt('//', r'ead62bb (2026-07-22)',
        r'fix(ui): stop blaming missing debug symbols for an '
        r'orphan-caused low edge ratio. Adds orphan counting here.'),
  ],
);
