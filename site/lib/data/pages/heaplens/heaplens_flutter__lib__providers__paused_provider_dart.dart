import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/providers/paused_provider.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'paused_provider.dart — pause means drop, on purpose'),
    cm('//', r'one boolean and the longest comment about a tradeoff in the providers folder'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'whether incoming graph messages are ignored'),
    kv('language', r'Dart / Riverpod'),
    kv('size', r'15 lines, one commit: 0309d9e (2026-07-06)'),
    kv('written by', r'the control bar’s pause/resume button'),
    kv('read by', r'graph_provider.dart and main.dart’s orchestrator'),
    ...sec(r'the whole file'),
    ...code('dart', 'heaplens_flutter/lib/providers/paused_provider.dart · lines 3-15', r'''
/// Whether incoming [GraphMessage]s should be dropped instead of applied.
///
/// Toggled by the control bar's pause/resume button. `graph_provider.dart`
/// checks this before calling `applyDiff` on each incoming message (see the
/// `ref.listen` wiring in `GraphNotifier.build`) — this is the "drop-while-
/// paused" strategy locked in the M5 task-3/6 briefs: pausing simply stops
/// applying messages as they arrive (they are not queued), and resuming
/// picks back up with whatever the next message happens to be. Because the
/// daemon's WS connection stays open and keeps broadcasting while paused,
/// the client may miss diffs while paused; the next `snapshot` (e.g. after a
/// reconnect) or subsequent diffs will still bring it back in sync — this is
/// an accepted tradeoff for the simplicity of not buffering messages.
final pausedProvider = StateProvider<bool>((ref) => false);'''),
    ...para('//',
        r'The code is one line. The comment is the specification: it '
        r'names the strategy (drop while paused, locked in the '
        r'milestone briefs for the control bar), says what happens '
        r'to messages while paused (they are not queued), and says '
        r'what resume does (it picks up with whatever the next '
        r'message is). Then it states the cost: the daemon’s socket '
        r'stays open and keeps broadcasting, so a client that pauses '
        r'can miss diffs, and a later snapshot or the following '
        r'diffs bring it back into sync. The comment calls this an '
        r'accepted tradeoff for the simplicity of not buffering.'),
    ...sec(r'why not buffer'),
    ...para('//',
        r'The comment calls dropping an accepted tradeoff for the '
        r'simplicity of not buffering. My reading of why: a queue '
        r'would either grow without bound or need a cap, and would '
        r'replay a backlog on resume. Dropping keeps memory flat and '
        r'relies on the protocol’s snapshot message, which the '
        r'comment names as one way the client gets back in sync.'),
    ...para('//',
        r'The honest limit is that diffs applied against a stale '
        r'node map can be wrong in small ways. A remove for an id '
        r'the client never saw is a no-op, but an update to a node '
        r'the client never saw is an update to nothing. The '
        r'user-visible rule is simple: pause is for reading the '
        r'screen, not for freezing the world, and resume can show a '
        r'slightly different graph than the one you paused on.'),
    ...sec(r'the two gates, and why there are two'),
    ...code('dart', 'heaplens_flutter/lib/providers/graph_provider.dart · lines 38-40', r'''
    ref.listen<AsyncValue<GraphMessage>>(graphMessageProvider, (previous, next) {
      if (ref.read(pausedProvider)) return;
      next.whenData(applyDiff);'''),
    ...code('dart', 'heaplens_flutter/lib/main.dart · lines 172-175', r'''
    // simulation and the graph state stay consistent while paused — if only
    // one side were gated, the visual would keep animating new nodes while
    // the control bar's counters stayed frozen (or vice versa).
    if (ref.read(pausedProvider)) return;'''),
    ...para('//',
        r'The provider has two readers and the second one is the '
        r'subtle one. graph_provider.dart checks the flag before '
        r'applying a message to the node map, using ref.read and not '
        r'ref.watch so the notifier itself does not rebuild when the '
        r'pause toggle moves. The orchestrator in main.dart checks '
        r'the same flag before forwarding to the force layout, and '
        r'its comment says why: if only one side were gated, the '
        r'picture would keep animating new nodes while the counters '
        r'were frozen, or the other way round. Both consumers of the '
        r'message stream must make the same decision, and the '
        r'decision is made from one shared source of truth, this '
        r'provider.'),
    ...sec(r'what pause does not stop'),
    ...pt('//', r'the stats message',
        r'the target diagnostics provider and the debug overlay do '
        r'not read this flag, so the Stats counters and the banner '
        r'keep updating while the graph is frozen. That is arguably '
        r'right for a diagnostic, but it is a difference worth '
        r'knowing.'),
    ...pt('//', r'the verbose log',
        r'the right rail’s log lists every snapshot and diff as they '
        r'arrive, paused or not. It reads the stream, not the graph.'),
    ...pt('//', r'physics',
        r'the layout keeps stepping on its timer. Pause stops new '
        r'information, not motion of what is already there.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'control_bar_test.dart toggles the button and asserts the '
        r'provider goes from false to true and back. '
        r'widget_test.dart has the integration check, named while '
        r'paused, an incoming GraphDiff add is not applied to the '
        r'shared ForceLayout: it sets the flag with '
        r'container.read(pausedProvider.notifier).state = true, '
        r'sends a diff through a stream controller, and asserts on '
        r'the layout, which proves the orchestrator’s gate.'),
    ...sec(r'history'),
    ...pt('//', r'0309d9e (2026-07-06)',
        r'feat(flutter): control_bar. The message says the graph '
        r'provider’s listener now checks pausedProvider before '
        r'applying each message, drop-while-paused, and that the '
        r'check is ref.read so the notifier does not rebuild on '
        r'pause toggles. The main.dart gate arrived in the wiring '
        r'commit 23b80e4.'),
  ],
);
