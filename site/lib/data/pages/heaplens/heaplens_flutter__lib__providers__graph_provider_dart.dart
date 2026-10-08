import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/providers/graph_provider.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'graph_provider.dart — the live graph, as a counter'),
    cm('//', r'state is a revision number; the data is mutated in place'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'holds the node map and applies snapshots and diffs to it'),
    kv('language', r'Dart (Riverpod Notifier)'),
    kv('size', r'108 lines; 5 commits, 2026-07-06 to 2026-07-19'),
    kv('tested by', r'test/providers/graph_provider_test.dart (13 tests)'),
    kv('watched by', r'9 build methods in 8 files, via ref.watch(graphProvider)'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'The daemon speaks in changes. The UI has to answer questions '
        r'about the whole: how many nodes are live, how many orphans, how '
        r'many bytes, which node owns this one. Something has to fold '
        r'the stream of snapshots and diffs into a current picture and '
        r'make that picture cheap to read. That is the entire job of '
        r'GraphNotifier.'),
    blank,
    ...para('//',
        r'The interesting part is how it exposes the picture. A '
        r'Riverpod Notifier normally holds immutable state: you build a '
        r'new value, assign it, and listeners compare old and new. This '
        r'one deliberately does not.'),
    ...sec(r'a deliberate break with the convention'),
    ...code('dart', 'heaplens_flutter/lib/providers/graph_provider.dart · GraphNotifier doc comment and build', r'''
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
class GraphNotifier extends Notifier<int> {
  final Map<int, NodeDto> _nodes = <int, NodeDto>{};

  @override
  int build() {
...
    ref.listen<AsyncValue<GraphMessage>>(graphMessageProvider, (previous, next) {
      if (ref.read(pausedProvider)) return;
      next.whenData(applyDiff);
    });
    return 0;
  }'''),
    ...para('//',
        r'The rationale is stated as performance, and the number behind '
        r'it is real: the daemon’s main loop only broadcasts a diff '
        r'when it is non-empty (is_non_empty_diff in the daemon’s '
        r'main.rs), once per tick, and the tick defaults to 33 ms, so '
        r'about 30 diffs a second at most. Copying a map that often is '
        r'wasteful in principle. I did not find a benchmark in the '
        r'repository that measures the saving, so read "performance '
        r'escape valve" as an engineering judgement rather than a '
        r'measured result. What the repository does provide is the '
        r'cost of the trade, in the form of rules written into the '
        r'doc comments and enforced by tests.'),
    blank,
    ...para('//',
        r'The state being an int has one useful property: the state '
        r'always changes. Riverpod notifies listeners when a new state '
        r'is not equal to the old one, and a counter that only goes up '
        r'is never equal to its predecessor. If the state were the same '
        r'map object mutated in place, a listener might never be '
        r'told. The int is the doorbell; the map is the data behind '
        r'the door.'),
    ...sec(r'the rules that come with it'),
    ...code('dart', 'heaplens_flutter/lib/providers/graph_provider.dart · the nodes getter', r'''
  /// **Important:** The returned map is mutated in place internally on each
  /// [applyDiff] call. Do not retain a reference to this map across a revision
  /// change and expect it to reflect old state. Always read the map fresh via
  /// `notifier.nodes` after a `ref.watch(graphProvider)` revision change;
  /// don't cache the reference.
  UnmodifiableMapView<int, NodeDto> get nodes => UnmodifiableMapView(_nodes);'''),
    ...para('//',
        r'The first version returned _nodes directly. 872430a ("return '
        r'UnmodifiableMapView from nodes getter for encapsulation") '
        r'fixed that: the commit message says the raw map let external '
        r'callers "bypass the revision-bump contract by mutating it '
        r'directly". The view is a window onto the same data, not a '
        r'copy, so it costs nothing; it just removes the write methods. '
        r'A test asserts that assignment, clear and remove through the '
        r'view all throw UnsupportedError and that the map is unchanged '
        r'afterwards.'),
    blank,
    ...para('//',
        r'Every widget that renders the graph follows the same two-step '
        r'pattern, and you can see it nine times in eight files '
        r'(main.dart, control_bar.dart, graph_canvas.dart, '
        r'memory_map.dart, insights_panel.dart, node_detail.dart twice, '
        r'right_rail.dart and the debug overlay): watch the revision '
        r'to be rebuilt, then read the map fresh from the notifier. '
        r'The comments in graph_canvas.dart and memory_map.dart repeat '
        r'the contract ("watched purely to know when to rebuild; read '
        r'the fresh node map below rather than caching it").'),
    ...sec(r'applying a message'),
    ...code('dart', 'heaplens_flutter/lib/providers/graph_provider.dart · applyDiff', r'''
  void applyDiff(GraphMessage msg) {
    switch (msg) {
      case GraphSnapshot snapshot:
        _nodes
          ..clear()
          ..addEntries(snapshot.nodes.map((n) => MapEntry(n.id, n)));
      case GraphDiff diff:
        for (final n in diff.add) {
          _nodes[n.id] = n;
        }
        for (final n in diff.update) {
          _nodes[n.id] = n;
        }
        for (final id in diff.remove) {
          _nodes.remove(id);
        }
      case GraphStats _:
        // Stats messages carry session counters, not node data — they must
        // not touch the node map or bump revision (that would trigger
        // needless graph rebuilds/repaints for something that never changes
        // what's on screen here). See target_diagnostics_provider.dart for
        // the listener that actually consumes them.
        return;
    }
    state = state + 1;
  }'''),
    ...pt('//', r'snapshot replaces',
        r'clear, then fill. This is what makes reconnects self-healing: '
        r'a fresh connection starts with a snapshot, which wipes any '
        r'node that disappeared while the socket was down. The test '
        r'applies a snapshot of ids {1, 2}, then a disjoint snapshot '
        r'{3}, and expects only {3}.'),
    ...pt('//', r'add and update are the same operation',
        r'both assign by id. The test name says why: "(per the add/update '
        r'are both upsert by id contract), not a no-op". If an update '
        r'arrives for a node the client missed adding, for example '
        r'during a pause, it becomes a node rather than being lost.'),
    ...pt('//', r'remove is forgiving',
        r'removing an id that is not present does nothing, and the '
        r'revision still bumps. The test removes id 888 and expects '
        r'the existing node untouched and the revision at 2.'),
    ...pt('//', r'one message, one revision',
        r'the bump is exactly 1 whatever the payload: a diff with 50 '
        r'adds is one revision, and so is an empty diff. The test '
        r'checks 50 adds, then an empty diff, expecting 1 then 2. '
        r'The consumer cost is therefore proportional to messages, '
        r'not to nodes.'),
    ...pt('//', r'stats do not count',
        r'the GraphStats arm returns before the bump. Without it, the '
        r'once-per-second counter message would repaint the canvas for '
        r'no visible change. Because GraphMessage is sealed, the '
        r'compiler requires this arm to exist; it was added in '
        r'0edc728 when stats were introduced. A test applies a stats '
        r'message after a diff and expects the revision to stay at 1.'),
    ...sec(r'the listener and the pause gate'),
    ...para('//',
        r'build() is where the notifier connects itself to the world: '
        r'it listens to graphMessageProvider and applies each arriving '
        r'message, so no widget ever has to feed it. That decision '
        r'shows in the tests, where one case pushes messages into a '
        r'fake stream and checks that revisions arrive as [1] and then '
        r'[1, 2].'),
    blank,
    ...para('//',
        r'The pause check arrived with the control bar (0309d9e): if '
        r'pausedProvider is true the message is dropped. The comment in '
        r'the file explains the choice of ref.read over ref.watch: the '
        r'notifier "must not rebuild when pause state changes". Using '
        r'watch would make build() run again whenever the user toggles '
        r'pause. Dropping instead of queueing is the other half of the '
        r'decision, recorded in paused_provider.dart as "an accepted '
        r'tradeoff for the simplicity of not buffering messages".'),
    blank,
    ...para('//',
        r'Reading the code, one consequence deserves stating. A '
        r'snapshot that arrives while paused is dropped like any other '
        r'message. If the socket reconnected while the user was paused, '
        r'the full-state message that would have replaced the map is '
        r'lost, and after resuming the map is only repaired as later '
        r'diffs overwrite or remove individual entries. That is my '
        r'reading of the code, not a behaviour I found documented or '
        r'tested; the paused_provider.dart comment hopes the next '
        r'snapshot or later diffs "will still bring it back in sync".'),
    ...sec(r'derived numbers, computed on demand'),
    ...code('dart', 'heaplens_flutter/lib/providers/graph_provider.dart · derived getters', r'''
  int get orphanCount =>
      _nodes.values.where((n) => n.state == NodeStateDto.orphan).length;

  /// Number of nodes currently marked `live`.
  int get liveNodeCount => _nodes.values.where((n) => n.live).length;

  /// Number of live nodes that own at least one other node (a non-empty
  /// `edges` list) — the top bar's plain-language "Owners" metric. Purely
  /// derived from data already present client-side; not a new wire field.
  int get ownerCount =>
      _nodes.values.where((n) => n.live && n.edges.isNotEmpty).length;

  /// Sum of `size` across all `live` nodes.
  int get totalLiveBytes => _nodes.values
      .where((n) => n.live)
      .fold(0, (sum, n) => sum + n.size);'''),
    ...para('//',
        r'Each getter is a full scan, recomputed on every read. The '
        r'plan says so on purpose: "Derived getters computed on demand '
        r'(not cached)". With four getters per ControlBar build, and a '
        r'few more elsewhere, a revision costs several passes over the '
        r'map. At the sizes this UI is designed for (the layout switches '
        r'to aggregation above 500 live nodes) that is cheap; at tens of '
        r'thousands of nodes it would be the first place to look. '
        r'Notice also that orphanCount does not filter on live, while '
        r'the others do. The daemon’s sweep in anomaly.rs skips nodes '
        r'that are not live (if !node.live { continue; }), so it only '
        r'ever assigns orphan to live ones. The test pins the '
        r'difference by '
        r'including a non-live orphan: orphanCount is 2, liveNodeCount '
        r'is 2 and totalLiveBytes is 30.'),
    blank,
    ...para('//',
        r'ownerCount is the newest, added in the UI refresh (1cfb7f9) '
        r'to feed the ribbon’s "Owners" tile. Its comment records an '
        r'architectural rule worth remembering: it is "purely derived '
        r'from data already present client-side; not a new wire field". '
        r'New questions get answered in the UI, not by widening the '
        r'protocol.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'graph_provider_test.dart has 13 tests. Twelve use a '
        r'ProviderContainer with graphMessageProvider overridden by a '
        r'StreamController’s stream, and call applyDiff directly on the '
        r'notifier. One goes the long way: it adds messages to the '
        r'stream, yields once with Future.delayed(Duration.zero), and '
        r'checks both the revision list and the map. Their names are a '
        r'readable spec: initial revision is 0 and the map is empty; '
        r'snapshot replaces; diff add inserts; update by id changes '
        r'fields without duplicating; remove deletes; remove of an '
        r'unknown id is a no-op; update of an unknown id upserts; '
        r'revision increments once per call; unknown state falls back '
        r'to healthy; the nodes map is immutable; stats do not touch '
        r'the map; derived getters; and automatic wiring.'),
    ...sec(r'limits and what is next'),
    ...pt('//', r'no change detail',
        r'the revision says "something changed", not what. Every '
        r'watcher rebuilds on every message and re-derives what it '
        r'needs. This is also why the force layout needs its own '
        r'listener (see main.dart): nothing here can tell it which '
        r'nodes were added.'),
    ...pt('//', r'owner lookup is a scan',
        r'there is no reverse index from child to owner. Both '
        r'ForceLayout and NodeDetail find an owner by scanning all '
        r'nodes for one whose edges contain the id.'),
    ...pt('//', r'a map nobody may keep',
        r'the contract that a map reference must not be retained across '
        r'revisions is enforced by documentation and one immutability '
        r'test, not by the type system.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
