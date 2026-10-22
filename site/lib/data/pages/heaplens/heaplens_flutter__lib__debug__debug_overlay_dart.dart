import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/debug/debug_overlay.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'debug_overlay.dart — the pipeline, on screen'),
    cm('//', r'an instrument built after the canvas stayed blank while every test passed'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'opt-in on-screen readout of every stage from socket to paint'),
    kv('language', r'Dart / Flutter'),
    kv('size', r'166 lines, no test of its own'),
    kv('history', r'4 commits, ac78534 (2026-07-07) to 1cfb7f9 (2026-07-19), plus the merge 64c523c (2026-07-21)'),
    kv('switch', r'--dart-define=HEAPLENS_DEBUG_OVERLAY=true'),
    kv('mounted by', r'lib/main.dart, as the last child of the outer Stack'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'The overlay was born from an incident, and the commit that '
        r'added it says so in the first line of its body: a '
        r'blank-canvas defect, reported by direct human observation, '
        r'overrides the merged acceptance of the milestone. '
        r'Everything I had done to verify the pipeline before that '
        r'was indirect: WebSocket captures, logs, memory growth, and '
        r'77 tests. All of it was green while a person looking at '
        r'the window saw nothing. A dead render path cannot be ruled '
        r'out with evidence that never looks at the render path.'),
    ...para('//',
        r'So the overlay makes the whole path from the daemon to the '
        r'canvas observable on the canvas. The class comment names '
        r'five seams where a break can hide, and the point of the '
        r'widget is that a human watching the live app can tell '
        r'which one failed without logs or screenshots: the '
        r'WebSocket connection, message arrival, the provider '
        r'revision, the population of simulation nodes, and the '
        r'execution of paint. Each line the widget draws answers one '
        r'of those questions.'),
    ...code('dart', 'heaplens_flutter/lib/debug/debug_overlay.dart · lines 23-37', r'''
/// Standing on-screen diagnostic instrument (added for the fix/canvas-render
/// investigation; kept for every future visual gate, not removed once this
/// bug is fixed). Makes every stage of the daemon -> canvas pipeline
/// observable directly on screen, without logs or screenshots, so a human
/// watching the live app can localize a break to one of five seams: WS
/// connection, message arrival, provider revision, SimNode population, or
/// paint execution.
///
/// [GraphPainter.lastPaintAt] and [ForceLayout.simNodes]'s length are
/// mutated from deep inside non-widget code (the painter's `paint()`, the
/// physics step) where threading a Riverpod provider through would be
/// invasive for a diagnostic tool — this widget instead polls them on a
/// short timer and forces its own rebuild, the same "watch a mutable field
/// via a driven rebuild" pattern `graph_canvas.dart` already uses for its
/// pulse animation.'''),
    ...para('//',
        r'The commit message also declares what this is not. It is a '
        r'standing instrument and not a throwaway: it stays past the '
        r'fix, for every future visual gate. That is why the file '
        r'has a doc comment instead of a TODO.'),
    ...sec(r'the five seams and the line that answers each'),
    ...pt('//', r'connection',
        r'Text(WS: status.name) reads connectionStatusProvider. If '
        r'this says disconnected nothing downstream matters.'),
    ...pt('//', r'message arrival',
        r'the msgs line counts snapshots, diffs and stats seen by '
        r'this widget. A connected socket with zero messages is a '
        r'daemon or decode problem.'),
    ...pt('//', r'provider revision',
        r'revision is the integer returned by graphProvider, and '
        r'live nodes is liveNodeCount from the notifier. Messages '
        r'arriving while the revision stays still means the pause '
        r'gate or the apply step is dropping them.'),
    ...pt('//', r'simulation',
        r'simNodes is the length of the force layout map and sim '
        r'bounds is the min and max of x and y. Live nodes greater '
        r'than zero with simNodes at zero means the second listener '
        r'never forwarded anything.'),
    ...pt('//', r'paint',
        r'last paint prints how long ago GraphPainter.paint last '
        r'ran. Never means the canvas was not built or not painted.'),
    ...sec(r'a stat that only an instrument would think of: NaN'),
    ...code('dart', 'heaplens_flutter/lib/debug/debug_overlay.dart · lines 103-116', r'''
    final xs = layout.simNodes.values.map((s) => s.position.x);
    final ys = layout.simNodes.values.map((s) => s.position.y);
    final bounds = simNodeCount == 0
        ? 'n/a'
        : 'x[${xs.reduce((a, b) => a < b ? a : b).toStringAsFixed(0)}, '
            '${xs.reduce((a, b) => a > b ? a : b).toStringAsFixed(0)}] '
            'y[${ys.reduce((a, b) => a < b ? a : b).toStringAsFixed(0)}, '
            '${ys.reduce((a, b) => a > b ? a : b).toStringAsFixed(0)}]';
    final hasNaN = xs.any((v) => v.isNaN) || ys.any((v) => v.isNaN);

    final lastPaintAt = GraphPainter.lastPaintAt;
    final sincePaint = lastPaintAt == null
        ? 'never'
        : '${DateTime.now().difference(lastPaintAt).inMilliseconds}ms ago';'''),
    ...para('//',
        r'The bounds line is more than decoration. A physics '
        r'simulation that blows up produces NaN positions, and a NaN '
        r'position paints nothing and throws nothing, which is '
        r'exactly the shape of a blank-canvas bug. So the widget '
        r'computes the bounds from the real positions, prints n/a '
        r'when there are none, and appends a loud NaN marker when '
        r'any coordinate is NaN.'),
    ...para('//',
        r'The reduce calls are safe because the empty case is '
        r'handled one line earlier by the simNodeCount == 0 branch. '
        r'The bounds scan walks the node map several times per rebuild, '
        r'and it only runs when the overlay is switched on.'),
    ...sec(r'polling a mutable field instead of threading a provider'),
    ...code('dart', 'heaplens_flutter/lib/debug/debug_overlay.dart · lines 54-66, 68-73', r'''
  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
    // Mirrors the overlay's on-screen text to the console every 2s so the
    // pipeline is traceable from logs alone, not only by looking at the
    // window — useful for automated/log-only verification passes.
    _logTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_lastStatsLine != null) debugPrint('[DebugOverlay] $_lastStatsLine');
    });
  }
...
  @override
  void dispose() {
    _pollTimer?.cancel();
    _logTimer?.cancel();
    super.dispose();
  }'''),
    ...para('//',
        r'The class comment gives the reason in full: '
        r'GraphPainter.lastPaintAt and the simulation node map are '
        r'written from deep inside non-widget code, the painter’s '
        r'paint method and the physics step. Making them reactive '
        r'would mean pushing a Riverpod provider through code that '
        r'has no business knowing about one, for the sake of a '
        r'diagnostic. So the widget polls every 200 ms and calls '
        r'setState, the same watch a mutable field through a driven '
        r'rebuild pattern the graph canvas already uses for its '
        r'pulse animation. It is a deliberate smell, kept inside a '
        r'debug widget.'),
    ...para('//',
        r'The second timer exists for a different observer. a457fed, '
        r'the same day as the first commit, added a 2 second mirror of '
        r'the on-screen text to debugPrint, because the next '
        r'verification passes had to run from logs alone with '
        r'screenshots off the table. The line it prints, '
        r'_lastStatsLine, is built in the same pass as the Text '
        r'widgets, so the screen and the console cannot disagree. '
        r'Both timers are cancelled in dispose, so toggling the '
        r'overlay does not leak a periodic callback.'),
    ...sec(r'the third listener'),
    ...code('dart', 'heaplens_flutter/lib/debug/debug_overlay.dart · lines 75-95', r'''
  @override
  Widget build(BuildContext context) {
    // A third independent listener on the same message stream, purely to
    // count arrivals for display here. Multiple listeners on
    // graphMessageProvider are already an established, safe pattern in this
    // codebase — see main.dart's _GraphOrchestrator class doc.
    ref.listen<AsyncValue<GraphMessage>>(graphMessageProvider, (previous, next) {
      next.whenData((message) {
        setState(() {
          switch (message) {
            case GraphSnapshot _:
              _snapshotCount++;
            case GraphDiff _:
              _diffCount++;
            case GraphStats stats:
              _statsCount++;
              _lastStats = stats;
          }
        });
      });
    });'''),
    ...para('//',
        r'The overlay counts messages by listening to '
        r'graphMessageProvider itself, which makes it a third '
        r'independent consumer of the stream after the graph '
        r'notifier and the orchestrator in main.dart. The comment '
        r'cites the _GraphOrchestrator class doc: several listeners '
        r'on one stream is an established, safe pattern in this code '
        r'base. The switch has no default branch, so if a new '
        r'message type is added to the sealed message hierarchy the '
        r'compiler forces this file to be updated, which is the '
        r'right behaviour for an instrument that is supposed to '
        r'account for every message.'),
    ...para('//',
        r'One property worth knowing: the counts are taken from the '
        r'stream, not from the graph state, so they keep counting '
        r'while the graph is paused. The pause gate lives in the '
        r'graph notifier and the orchestrator, not here. Pausing the '
        r'app and watching the msgs counters keep rising is a useful '
        r'way to confirm the gate is dropping messages rather than '
        r'the socket being quiet.'),
    ...sec(r'the stats line and the target diagnosis'),
    ...code('dart', 'heaplens_flutter/lib/debug/debug_overlay.dart · lines 118-128', r'''
    final stats = _lastStats;
    final statsSummary = stats == null
        ? 'none yet'
        : 'events=${stats.eventsReceived} '
            'symbols=${stats.symbolsResolved}/${stats.symbolsResolved + stats.hexFallback} '
            'target=${stats.targetName ?? '?'}[${stats.targetPid ?? '?'}]';

    _lastStatsLine = 'WS=${status.name} msgs(snap=$_snapshotCount,diff=$_diffCount,stats=$_statsCount) '
        'revision=$revision liveNodes=$liveNodeCount simNodes=$simNodeCount '
        'bounds=$bounds${hasNaN ? ' NaN!' : ''} lastPaint=$sincePaint '
        'targetDiag($statsSummary)';'''),
    ...para('//',
        r'Once the daemon began sending a Stats message every '
        r'second, the overlay learned a fourth number to show: '
        r'events received, symbols resolved out of symbols total, '
        r'and the target name and pid. The commit that introduced it '
        r'(0edc728) says the banner’s raw counts are mirrored here, '
        r'so a person looking at the banner’s plain-language '
        r'headline can see the same numbers the headline was derived '
        r'from. The question marks are the null fallback: before any '
        r'attach there is no target name or pid.'),
    ...sec(r'opt-in, and why it stopped being on by default'),
    ...code('dart', 'heaplens_flutter/lib/debug/debug_overlay.dart · lines 12-21', r'''
/// Whether [DebugOverlay] should be built. Opt-in only, via
/// `--dart-define=HEAPLENS_DEBUG_OVERLAY=true` — this used to also default
/// on for every debug build, which meant the floating stats box (green
/// monospace text, bottom-right of the graph) was effectively always
/// visible in normal dev usage and duplicated the right rail's own
/// "Connection & render stats" panel. The overlay itself (and its
/// diagnostic value for investigating a symptom that might not reproduce
/// under `flutter run`'s debug-mode overhead) is unchanged — it just no
/// longer turns itself on unasked.
const bool kShowDebugOverlay = bool.fromEnvironment('HEAPLENS_DEBUG_OVERLAY');'''),
    ...para('//',
        r'The first version was on by default in debug builds and '
        r'could be forced in release with the dart-define flag. That '
        r'worked for an investigation and then became noise: the '
        r'green monospace box was always visible in normal '
        r'development and duplicated the right rail’s Connection and '
        r'render stats panel. The UI refresh commit (1cfb7f9) made '
        r'the overlay strictly opt-in. The doc comment is careful to '
        r'say that the overlay itself and its diagnostic value are '
        r'unchanged, and to explain why it is worth keeping: a '
        r'symptom that might not reproduce under the overhead of '
        r'flutter run in debug mode can still be investigated with '
        r'the flag in a release build, which the first commit '
        r'explicitly allowed.'),
    ...para('//',
        r'bool.fromEnvironment is evaluated at compile time. With '
        r'the flag absent the constant is false, the if in main.dart '
        r'is a constant condition, and the overlay widget is not '
        r'built at all, so it costs nothing in a normal run.'),
    ...sec(r'layout and a small inaccuracy'),
    ...code('dart', 'heaplens_flutter/lib/debug/debug_overlay.dart · lines 130-140', r'''
    return Positioned(
      right: 8,
      bottom: 8,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),'''),
    ...para('//',
        r'The box is Positioned at right 8, bottom 8, wrapped in '
        r'IgnorePointer so it never steals a click from the canvas, '
        r'on a 75 percent black fill with a white24 border and green '
        r'accent text in 11 point monospace. Two things are worth '
        r'saying plainly. First, the class comment calls it the '
        r'bottom-right of the graph, but main.dart mounts it in the '
        r'outermost Stack, so on screen it sits at the bottom-right '
        r'of the window, over the right rail’s log section. Second, '
        r'it assigns _lastStatsLine inside build, a side effect in a '
        r'build method; the value is idempotent so nothing breaks, '
        r'but it is the sort of thing that would not pass review in '
        r'production code.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'It is not. A search of test/ finds no reference to '
        r'DebugOverlay or kShowDebugOverlay, and the only code that '
        r'uses them is main.dart. The coverage is indirect: it reads '
        r'providers that have their own tests (graph_provider_test, '
        r'ws_provider_test, force_layout_test) and its parts of the '
        r'layout do not appear anywhere else. The honest description '
        r'is that the instrument is verified by being used, which is '
        r'how it was designed to be used. If I added a test it would '
        r'pump the widget with the flag on and assert on the WS line '
        r'and the NaN marker.'),
    ...sec(r'trade-offs'),
    ...pt('//', r'polling vs reactive',
        r'200 ms polling is the cost of keeping diagnostics out of '
        r'the physics and the painter.'),
    ...pt('//', r'static field for last paint',
        r'GraphPainter.lastPaintAt is a static, so the readout works '
        r'with only one canvas on screen. Two canvases would '
        r'overwrite each other. That is fine for a diagnostic.'),
    ...pt('//', r'duplication',
        r'right_rail.dart contains a near-copy of the bounds and '
        r'paint code (without the NaN check and the stats line). '
        r'Having two copies means the overlay can drift from the '
        r'panel.'),
    ...sec(r'history'),
    ...pt('//', r'ac78534 (2026-07-07)',
        r'add the standing overlay for live-pipeline diagnosis; on '
        r'by default in debug builds.'),
    ...pt('//', r'a457fed (2026-07-07)',
        r'mirror the stats to the console every 2 seconds.'),
    ...pt('//', r'0edc728 (2026-07-17)',
        r'add the target diagnostic line from the new Stats message.'),
    ...pt('//', r'1cfb7f9 (2026-07-19)',
        r'make the overlay opt-in only; its stats stay visible in '
        r'the right rail.'),
  ],
);
