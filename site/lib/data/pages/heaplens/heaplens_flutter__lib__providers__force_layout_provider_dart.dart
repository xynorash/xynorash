import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/providers/force_layout_provider.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'force_layout_provider.dart — one physics world for the whole app'),
    cm('//', r'fifteen lines that decide who owns the simulation'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'exposes the single shared ForceLayout instance'),
    kv('language', r'Dart / Riverpod'),
    kv('size', r'15 lines, one commit: 23b80e4 (2026-07-06)'),
    kv('fed by', r'the orchestrator in lib/main.dart'),
    kv('read by', r'graph_canvas, main.dart, right_rail, debug_overlay'),
    ...sec(r'the whole file'),
    ...code('dart', 'heaplens_flutter/lib/providers/force_layout_provider.dart · lines 5-15', r'''
/// Single shared [ForceLayout] instance for the app's lifetime.
///
/// Fed by `main.dart`'s dedicated `ref.listen(graphMessageProvider, ...)`
/// (independent of `graph_provider.dart`'s own internal listener — see the
/// doc on `_GraphOrchestrator` in main.dart for why there are two separate
/// listeners on the same message stream) and read by `graph_canvas.dart` for
/// both physics-driven positions and hit-testing.
///
/// Deliberately a plain (non-autoDispose) [Provider]: the layout must persist
/// for the whole app lifetime, not be torn down when nothing is watching it.
final forceLayoutProvider = Provider<ForceLayout>((ref) => ForceLayout());'''),
    ...para('//',
        r'A provider with no logic: it constructs a ForceLayout and '
        r'hands out the same object every time. All of the interest '
        r'is in what the comment decides, which is lifetime and '
        r'ownership.'),
    ...sec(r'why a provider, and why not autoDispose'),
    ...para('//',
        r'The force layout holds positions and velocities for every '
        r'node, and those are the product of seconds or minutes of '
        r'simulation. If the instance were created by a widget, a '
        r'rebuild or a switch between the graph view and the memory '
        r'map could throw the positions away, and the graph would '
        r're-explode from scratch. Putting it behind a plain '
        r'Provider gives the layout the lifetime of the '
        r'ProviderScope, which in this app is the lifetime of the '
        r'window. The last paragraph of the comment says it in '
        r'words: a plain, non-autoDispose Provider, because nothing '
        r'watching it must not be a reason to tear it down. Under '
        r'autoDispose, switching to the memory map would drop the '
        r'only listener and reset the physics.'),
    ...para('//',
        r'widget_test.dart flips viewModeProvider to the memory map '
        r'and back and asserts that GraphCanvas and MemoryMap swap '
        r'in and out. It does not assert that positions survive the '
        r'swap; that property follows from the provider’s lifetime.'),
    ...sec(r'the two-listener story the comment points at'),
    ...code('dart', 'heaplens_flutter/lib/main.dart · lines 151-162', r'''
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
        r'The comment says the layout is fed by main.dart’s own '
        r'listener on the message stream, independent of the one '
        r'inside graph_provider.dart. The reason is in the commit '
        r'that created both: graph_provider’s node map is mutated in '
        r'place, so its listener cannot be asked afterwards what '
        r'changed, whereas the layout needs to hear the exact adds, '
        r'updates and removes as they arrive. Two listeners on one '
        r'stream is therefore a design, not an accident. The '
        r'orchestrator forces GraphNotifier.build() to run first so '
        r'the order of the two is deterministic, a point the commit '
        r'message also makes.'),
    ...para('//',
        r'The same snippet shows the layout being ticked: a periodic '
        r'timer calls layout.step with the interval in seconds. The '
        r'commit message gives the cadence as roughly 30 Hz (main.dart sets '
        r'a 33 ms interval). The '
        r'timer is cancelled in dispose, and the widget tests '
        r'unmount the tree at the end for exactly that reason; their '
        r'comments say a leaked periodic timer would be flagged by '
        r'the fake-async test zone.'),
    ...sec(r'who else holds a reference'),
    ...pt('//', r'graph_canvas',
        r'draws from layout.simNodes and uses the same object for '
        r'hit-testing, so what you tap is what is drawn.'),
    ...pt('//', r'right_rail and debug_overlay',
        r'both watch the provider and read the length of simNodes '
        r'and their x and y bounds for the stats readout. Because '
        r'this provider never changes value, watching it does not '
        r'rebuild them; they rebuild from their own polling timers.'),
    ...pt('//', r'widget_test',
        r'reads the layout through a ProviderContainer to assert on '
        r'what the pause gate did and did not forward.'),
    ...sec(r'trade-offs and sharp edges'),
    ...pt('//', r'global mutable state',
        r'a provider that returns a mutable object trades Riverpod’s '
        r'change tracking for convenience. Nothing notifies anyone '
        r'when the layout steps. The canvas reads simNodes on each '
        r'repaint instead of being notified.'),
    ...pt('//', r'testability',
        r'because the instance is built by the provider, a test can '
        r'override forceLayoutProvider with a seeded layout. The '
        r'existing tests instead use the real one and inspect it.'),
    ...pt('//', r'one world',
        r'there is exactly one simulation. A second view of the same '
        r'graph would share positions, which is right for the graph '
        r'and the map but would not suit a side-by-side compare.'),
    ...sec(r'history'),
    ...pt('//', r'23b80e4 (2026-07-06)',
        r'feat(flutter): main.dart wiring. Creates this file in the '
        r'same commit that introduces the orchestrator, the physics '
        r'ticker and ForceLayout.resetFrom for full snapshot '
        r'reconciliation. Not edited since.'),
  ],
);
