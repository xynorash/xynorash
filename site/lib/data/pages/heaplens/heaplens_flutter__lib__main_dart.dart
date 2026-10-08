import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/main.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'main.dart — the wiring of the HeapLens UI'),
    cm('//', r'one app shell, one physics clock, two listeners on one stream'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'entry point; owns the physics ticker and the page layout'),
    kv('language', r'Dart / Flutter (Windows desktop target)'),
    kv('size', r'327 lines, 3 widget tests in test/widget_test.dart'),
    kv('history', r'7 commits, 2026-07-06 (scaffold) to 2026-07-19 (UI refresh)'),
    kv('depends on', r'every provider, plus ControlBar, GraphCanvas, MemoryMap, RightRail'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'Everything else in heaplens_flutter is a leaf: a model that '
        r'parses JSON, a provider that holds one piece of state, a widget '
        r'that draws one panel. main.dart is the only place where those '
        r'leaves are joined into an application, and it has two jobs that '
        r'no leaf can do. It lays the panels out (HeapLensHome), and it '
        r'runs the thing that makes the graph move: a timer that steps the '
        r'force-directed simulation about thirty times a second and a '
        r'listener that tells the simulation what the daemon just said '
        r'(_GraphOrchestrator).'),
    blank,
    ...para('//',
        r'The Build Spec puts the whole UI under one rule, invariant 10: '
        r'"Flutter knows only JSON." That rule explains the shape of this '
        r'file. Nothing here knows about pointers, stacks or the allocator; '
        r'it receives decoded GraphMessage values and turns them into '
        r'pixels. Everything the simulation needs to know about a node '
        r'arrives inside a NodeDto.'),
    ...sec(r'the shell: ProviderScope and a dark theme'),
    ...code('dart', 'heaplens_flutter/lib/main.dart · main() and HeapLensApp', r'''
void main() {
  runApp(const ProviderScope(child: HeapLensApp()));
}
...
class HeapLensApp extends StatelessWidget {
  const HeapLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HeapLens',
      debugShowCheckedModeBanner: false,
      theme: XynorashTheme.darkTheme(),
      home: const _GraphOrchestrator(child: HeapLensHome()),
    );
  }
}'''),
    ...para('//',
        r'Two choices are worth noticing. First, the orchestrator is '
        r'inserted above HeapLensHome, in the MaterialApp home slot, '
        r'rather than inside the page. Its doc comment gives the reason: '
        r'it wires the physics simulation "regardless of which '
        r'page/route is showing". The simulation belongs to the app, not '
        r'to a screen. Second, all colours come from XynorashTheme (see '
        r'theme/xynorash_theme.dart), so the app inherits the palette of '
        r'the author’s terminal setup instead of the default Material '
        r'purple.'),
    blank,
    ...para('//',
        r'The widget tests use the same trick in reverse: they put their '
        r'own ProviderScope with graphMessageProvider overridden by a '
        r'fake StreamController, then pump HeapLensApp unchanged. Because '
        r'the real WebSocket provider is the only thing replaced, the '
        r'tests exercise exactly this wiring.'),
    ...sec(r'the problem: two consumers of one event stream'),
    ...para('//',
        r'The daemon sends a stream of GraphMessage values: a snapshot on '
        r'connect, then diffs. Two different parts of the UI need every '
        r'message. GraphNotifier (providers/graph_provider.dart) applies '
        r'it to the node map. ForceLayout (simulation/force_layout.dart) '
        r'must also react: spawn a SimNode for each added node, change a '
        r'radius for each update, start a fade for each removal.'),
    blank,
    ...para('//',
        r'The obvious design is to let ForceLayout watch graphProvider and '
        r'diff the node map between revisions. The class comment explains '
        r'why that cannot work:'),
    ...code('dart', 'heaplens_flutter/lib/main.dart · _GraphOrchestrator doc comment (trimmed)', r'''
/// `graph_provider.dart`'s `GraphNotifier` already has its own internal
/// `ref.listen(graphMessageProvider, ...)` that mutates its node map and
/// bumps `revision`. [ForceLayout] needs to react to the exact same stream of
/// events (to spawn/update/fade `SimNode`s), but it cannot be driven by
/// diffing `graphProvider`'s revision changes, because that node map is
/// mutated in place — there is no "before" snapshot left to diff against
/// "after". So this widget sets up a *second*, independent
/// `ref.listen(graphMessageProvider, ...)` that receives every raw
...'''),
    ...para('//',
        r'The cause is a deliberate decision made in graph_provider.dart: '
        r'the node map is mutated in place and the Riverpod state is just '
        r'an integer revision counter. That makes graph updates cheap, but '
        r'it destroys the "before" picture. So the orchestrator listens to '
        r'the raw messages itself and forwards add, update and remove '
        r'calls to the shared ForceLayout. The ForceLayout instance is '
        r'created once by forceLayoutProvider (a plain Provider, not '
        r'auto-dispose) so the physics outlives any widget.'),
    ...sec(r'a bug that was only a risk: listener ordering'),
    ...para('//',
        r'Two listeners on one provider raise an ordering question. When a '
        r'diff arrives, ForceLayout.addNode needs the current node map to '
        r'find each new node’s owner (the other node whose edges list '
        r'contains the new id). If the orchestrator’s listener runs before '
        r'GraphNotifier has applied the same diff, the lookup sees stale '
        r'data and the node spawns at canvas centre instead of beside its '
        r'owner. The class comment states that Riverpod calls listeners in '
        r'the order they were registered, and that naive widget build '
        r'order would register the orchestrator first, because the '
        r'orchestrator is the parent of the ControlBar whose build is what '
        r'normally first touches graphProvider.'),
    blank,
    ...para('//',
        r'The fix, from the 23b80e4 integration commit, is one line in '
        r'initState:'),
    ...code('dart', 'heaplens_flutter/lib/main.dart · _GraphOrchestratorState.initState', r'''
  @override
  void initState() {
    super.initState();

    // Force `GraphNotifier.build()` to run now, registering its internal
    // `ref.listen(graphMessageProvider, ...)` before this widget's own
    // `build()` (and its own `ref.listen` call) executes. See the ordering
    // note on the class doc above for why this matters.
    ref.read(graphProvider);

    final layout = ref.read(forceLayoutProvider);
    final dtSeconds = _physicsInterval.inMicroseconds / 1e6;
    _physicsTimer = Timer.periodic(_physicsInterval, (_) {
      layout.step(dtSeconds);
    });
  }'''),
    ...para('//',
        r'The commit message calls this giving "a deterministic firing '
        r'order rather than depending on incidental widget-tree shape". '
        r'Reading the provider in initState forces GraphNotifier.build() '
        r'to run, which registers its listener first. The same trick '
        r'reappears later in providers/target_diagnostics_provider.dart, '
        r'whose build() starts with ref.read(graphProvider) and a comment '
        r'that points back at this class.'),
    blank,
    ...para('//',
        r'The guarantee is only established at mount, and the doc comment '
        r'is candid about that. A follow-up commit, 4ad9349 ("document '
        r'hot-reload ordering hazard"), added two known ways to break it '
        r'in a running app: an explicit ref.invalidate(graphProvider), '
        r'which re-registers the notifier’s listener at the end of the '
        r'list, and a dev-time hot reload, where Riverpod may call '
        r'invalidateSelf on GraphNotifier if its source changed while '
        r'initState does not re-run. The visible effect would be limited '
        r'to one message, one node spawning near the centre instead of '
        r'near its owner. A search of lib/ and test/ shows no call to '
        r'invalidate on graphProvider, and the comment notes it cannot '
        r'occur in release builds. It also sketches the robust fix (do '
        r'owner lookups against a locally merged view of the node map) and '
        r'explains why it was left out of scope. That is a good example '
        r'of writing a known limitation down where the next maintainer '
        r'will meet it.'),
    ...sec(r'the physics clock: 30 Hz, decoupled from rendering'),
    ...code('dart', 'heaplens_flutter/lib/main.dart · _physicsInterval', r'''
  /// Physics tick rate, decoupled from `graph_canvas.dart`'s own 60fps
  /// render-clock `AnimationController` (used only for the pulsing-ring
  /// effect). ~30 Hz is plenty for smooth-looking force-directed motion.
  static const Duration _physicsInterval = Duration(milliseconds: 33);'''),
    ...para('//',
        r'The plan for milestone M5 asks for "Physics tick ~30 Hz, '
        r'decoupled from 60 fps render". The interval is 33 ms, which '
        r'matches the daemon’s default tick_ms of 33 in config.rs, '
        r'although nothing in the code ties the two together; I would not '
        r'claim they are synchronised. The step is fed a fixed '
        r'dtSeconds computed once from the interval, so the simulation '
        r'advances by a constant dt per tick no matter how late a tick '
        r'fires. A late timer slows the animation instead of making the '
        r'integrator take a large, unstable step. The timer is cancelled '
        r'in dispose, and the widget tests unmount the app at the end '
        r'for exactly that reason: flutter_test flags a leaked periodic '
        r'timer otherwise.'),
    ...sec(r'what the orchestrator does with each message'),
    ...code('dart', 'heaplens_flutter/lib/main.dart · _handleMessage (trimmed)', r'''
  void _handleMessage(GraphMessage message) {
    // Mirror `graph_provider.dart`'s own pause gate exactly, so the physics
    // simulation and the graph state stay consistent while paused — if only
    // one side were gated, the visual would keep animating new nodes while
    // the control bar's counters stayed frozen (or vice versa).
    if (ref.read(pausedProvider)) return;

    final layout = ref.read(forceLayoutProvider);
    final currentNodes = ref.read(graphProvider.notifier).nodes;

    switch (message) {
      case GraphSnapshot snapshot:
        final snapshotMap = {for (final n in snapshot.nodes) n.id: n};
        layout.resetFrom(snapshot.nodes, snapshotMap);
      case GraphDiff diff:
        for (final n in diff.add) {
          layout.addNode(n, currentNodes);
        }
...
        for (final n in diff.update) {
          layout.updateNode(n);
        }
        for (final id in diff.remove) {
          layout.removeNode(id);
        }
      case GraphStats _:
        // Session counters, not node data — the physics layout has nothing
        // to do with these.
        return;
    }
  }'''),
    ...pt('//', r'the pause gate',
        r'pausing drops messages instead of queueing them. The same check '
        r'exists in GraphNotifier.build. Having it in both places is what '
        r'keeps the picture and the counters consistent. 4ad9349 added a '
        r'widget test for precisely this gate, because the check on the '
        r'orchestrator side was previously untested and a regression '
        r'removing it would have passed.'),
    ...pt('//', r'snapshots use their own map',
        r'for a snapshot the owner lookup uses a map built from the '
        r'snapshot itself, so it does not depend on whether '
        r'graph_provider has already applied it. The comment calls this '
        r'"entirely self-contained". Diffs, by contrast, do depend on '
        r'the ordering guarantee above.'),
    ...pt('//', r'update never fades',
        r'an update whose state is freed does not call removeNode. The '
        r'long comment in the file (elided above) argues this is a '
        r'non-issue because the daemon never produces a freed node on an '
        r'update. That is checkable: in crates/heaplens-daemon/src the '
        r'only NodeState values constructed are Healthy (graph.rs) and '
        r'Orphan, Hot and Healthy (anomaly.rs). The M4 plan says it '
        r'outright: "NodeState::Freed is NOT emitted in M4". A freed '
        r'node therefore always ends through a remove entry. The comment '
        r'also records what to change if that ever stops being true.'),
    ...pt('//', r'stats are ignored',
        r'GraphStats was added by the target-diagnostics work '
        r'(0edc728). Because GraphMessage is a sealed class, the Dart '
        r'compiler forces every switch to handle it. The follow-up '
        r'commit cd348b6 records that right_rail.dart needed a GraphStats arm '
        r'added to two switches after a merge introduced the variant, '
        r'"caught by flutter analyze". This is the failure mode that '
        r'section 7 of the Build Spec warns about on the Rust side: a '
        r'new enum variant meeting an old _ wildcard arm. An exhaustive '
        r'switch over a sealed type cannot have that bug.'),
    ...sec(r'subscribing: why it lives in build'),
    ...code('dart', 'heaplens_flutter/lib/main.dart · _GraphOrchestratorState.build', r'''
  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<GraphMessage>>(graphMessageProvider, (previous, next) {
      next.whenData(_handleMessage);
    });
    return widget.child;
  }'''),
    ...para('//',
        r'In a ConsumerStatefulWidget, ref.listen is called from build. '
        r'That is the reason the ordering trick in initState is needed at '
        r'all: the orchestrator’s listener is registered at its first '
        r'build, while GraphNotifier registers its own in its build() '
        r'method the first time the provider is read. The listener '
        r'receives an AsyncValue because graphMessageProvider is a '
        r'StreamProvider; whenData skips loading and error states, so a '
        r'malformed frame, which ws_provider reports as a stream error, '
        r'never reaches the layout.'),
    ...sec(r'the page layout'),
    ...code('dart', 'heaplens_flutter/lib/main.dart · HeapLensHome (trimmed)', r'''
class HeapLensHome extends ConsumerWidget {
  const HeapLensHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(viewModeProvider);
    final layout = ref.watch(forceLayoutProvider);
    final status = ref.watch(connectionStatusProvider);
    ref.watch(graphProvider); // rebuild when the node map changes
    final liveNodeCount = ref.read(graphProvider.notifier).liveNodeCount;
...
                                    child: switch (viewMode) {
                                      ViewMode.graph => GraphCanvas(layout: layout),
                                      ViewMode.memoryMap => const MemoryMap(),
                                    },
...
                                  if (status != ConnectionStatus.connected &&
                                      liveNodeCount == 0)
                                    const _WaitingForDaemon(),
...
                            const Expanded(flex: 2, child: InsightsPanel()),
                          ],
                        ),
                      ),
                      const RightRail(),
...
            if (kShowDebugOverlay) const DebugOverlay(),'''),
    ...para('//',
        r'The layout, top to bottom: the ControlBar ribbon, the '
        r'TargetStatusBanner (which renders nothing unless something '
        r'needs explaining), then a row with the centre column (graph or '
        r'memory map at flex 3, the InsightsPanel below it at flex 2) and '
        r'the fixed-width RightRail. The doc comment stresses that the '
        r'rail is "always present and always expanded" with no '
        r'accordions; each panel handles its own empty state instead.'),
    blank,
    ...para('//',
        r'The view switch is a Dart 3 switch expression over the ViewMode '
        r'enum, so adding a third view without handling it here would not '
        r'compile. The "Waiting for daemon…" overlay appears only when '
        r'the socket is not connected and there are no live nodes, so '
        r'the user sees an explicit state instead of an empty canvas. '
        r'HeapLensHome watches the revision int from graphProvider only '
        r'to rebuild, then reads the real data from the notifier, the '
        r'contract that graph_provider.dart documents.'),
    blank,
    ...para('//',
        r'The two comments about CrossAxisAlignment.stretch record layout '
        r'bugs found by looking at the running app. The ribbon sized '
        r'itself to the intrinsic width of its five cells, leaving blank '
        r'space on the right, and the right rail sized to its content '
        r'height, "leaving a dead black gap below the last section". '
        r'Both are fixed by one line each, and each fix has a comment '
        r'explaining the symptom.'),
    ...sec(r'what changed over time'),
    ...pt('//', r'2026-07-06 scaffold (56d5e41)',
        r'the stock "Flutter Demo" counter app produced by flutter '
        r'create, with the four dependencies added.'),
    ...pt('//', r'2026-07-06 integration (23b80e4)',
        r'M5 task 9: ProviderScope, dark theme, the orchestrator and the '
        r'second listener. Also adds ForceLayout.resetFrom for snapshots '
        r'and forceLayoutProvider.'),
    ...pt('//', r'2026-07-06 hot-reload note (4ad9349)',
        r'the pause-gate test and the long hazard comment.'),
    ...pt('//', r'2026-07-06 final review (fea8519)',
        r'14 lines: documents why a freed update is not a fade trigger, '
        r'next to the code that makes the fade ghosts visible in '
        r'graph_canvas.dart.'),
    ...pt('//', r'2026-07-07 debug overlay (ac78534)',
        r'the layout gains the DebugOverlay slot, after a human saw a '
        r'blank canvas with 77 tests green. The overlay is now opt-in; '
        r'see debug/debug_overlay.dart.'),
    ...pt('//', r'2026-07-17 diagnostics (0edc728)',
        r'the TargetStatusBanner joins the column.'),
    ...pt('//', r'2026-07-19 UI refresh (1cfb7f9)',
        r'the layout becomes ribbon, banner, centre column plus '
        r'InsightsPanel, and RightRail; 92 lines changed. The merge of '
        r'master into the UI-refresh branch (64c523c) listed main.dart '
        r'among its conflicted files.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'test/widget_test.dart holds three widget tests that go through '
        r'the whole wiring with a fake message stream. The first drives a '
        r'snapshot, an update and a removal, and checks the ForceLayout '
        r'state after each: the SimNode ids are {1, 2}, the removed node '
        r'is still present immediately (fade in progress), and after '
        r'pumping two seconds it is gone while node 1 remains. The second '
        r'sets pausedProvider and checks that a diff add does not reach '
        r'the layout. The third flips viewModeProvider and checks that '
        r'GraphCanvas and MemoryMap swap. Each test ends by pumping an '
        r'empty SizedBox so the orchestrator’s timer is disposed.'),
    ...sec(r'limits'),
    ...pt('//', r'ordering is by convention',
        r'the two-listener design works because of a registration-order '
        r'argument. It is documented and tested at mount, but nothing '
        r'asserts it after an invalidation or hot reload.'),
    ...pt('//', r'no re-centring of the simulation',
        r'ForceLayout keeps a fixed centre (400, 300) by default; '
        r'graph_canvas.dart translates the view to compensate. The '
        r'orchestrator does not tell the layout the real viewport size.'),
    ...pt('//', r'one process, one connection',
        r'the app connects to a fixed address, ws://127.0.0.1:9999, a '
        r'single top-level const in ws_provider.dart that its own comment '
        r'says "a later task may make configurable".'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
