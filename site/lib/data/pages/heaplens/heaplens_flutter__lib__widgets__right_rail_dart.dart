import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/widgets/right_rail.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'right_rail.dart — the side that answers “what exactly?”'),
    cm('//', r'four sections: detail, history, plumbing, and a log that explains itself'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'the 380 px right column: detail, sparkline, connection stats, verbose logs'),
    kv('language', r'Dart / Flutter'),
    kv('size', r'296 lines, 2 commits: 1cfb7f9 (2026-07-19), cd348b6 (2026-07-21)'),
    kv('depends on', r'node_detail, ui_common, ws_provider, graph_provider'),
    kv('tests', r'none for this file directly'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'The center of the window is for looking; the right rail is '
        r'for asking questions about what you are looking at. Its '
        r'top two sections are the node panels, which have a page of '
        r'their own. The two below them are the reason the file '
        r'exists, and both are about trust: one shows the state of '
        r'the plumbing between the daemon and the screen, and one '
        r'narrates, with timestamps, everything the app has done. '
        r'The stats panel shows the same fields as the debug '
        r'overlay.'),
    ...sec(r'the layout, and what the comment gets wrong'),
    ...code('dart', 'heaplens_flutter/lib/widgets/right_rail.dart · lines 16-22', r'''
/// The right rail: four always-on, non-collapsible sections, top to
/// bottom — Node detail, Size over time, Connection & render stats,
/// Verbose logs. No accordion/collapse behavior anywhere in this widget.
/// The last section (verbose logs) expands to fill any remaining vertical
/// space so the rail's content always reaches the bottom edge of the
/// window rather than stopping partway down.
class RightRail extends StatelessWidget {'''),
    ...code('dart', 'heaplens_flutter/lib/widgets/right_rail.dart · lines 36-61', r'''
    return HudFrame(
      child: Container(
        key: const Key('rightRail'),
        width: 380,
        color: XynorashTheme.bgPanel,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              RailSection(title: 'Node detail', child: NodeDetail()),
              RailSection(title: 'Size over time', child: NodeSparklinePanel()),
              RailSection(
                title: 'Connection & render stats',
                muted: true,
                child: _ConnectionStatsPanel(),
              ),
              RailSection(
                title: 'Verbose logs',
                muted: true,
                child: SizedBox(height: 260, child: _VerboseLogsPanel()),
              ),
            ],
          ),
        ),
      ),
    );'''),
    ...para('//',
        r'The class comment says the last section expands to fill '
        r'the remaining vertical space so the rail always reaches '
        r'the bottom of the window. The build does something '
        r'different, and its own comment says why. An Expanded log '
        r'list needs a bounded-height ancestor, which would mean '
        r'IntrinsicHeight, and a ListView explicitly refuses '
        r'intrinsic-dimension queries. So the whole rail scrolls as '
        r'one unit and the log section is given a fixed 260 pixel '
        r'height instead. The doc above the class predates that '
        r'decision and was not updated, which is the bug in this '
        r'file. RailSection still has an expand parameter for the '
        r'approach that was abandoned; nothing in lib/ passes it.'),
    ...para('//',
        r'The rail is a fixed 380 wide on the bgPanel color, framed '
        r'with HudFrame corner brackets. In main.dart the row '
        r'stretches it to the full height, so the panel color '
        r'reaches the bottom of the window even though its content '
        r'does not.'),
    ...sec(r'connection and render stats'),
    ...code('dart', 'heaplens_flutter/lib/widgets/right_rail.dart · lines 65-70', r'''
/// Demoted developer-diagnostic block: the same WS/msgs/revision/live
/// nodes/sim nodes/sim bounds/last-paint data the (now opt-in-only)
/// standing debug overlay shows — this is the *only* place this data is
/// always visible; the floating green-text overlay that used to show it
/// unconditionally in every debug build has been removed (see
/// debug/debug_overlay.dart's `kShowDebugOverlay` doc).'''),
    ...code('dart', 'heaplens_flutter/lib/widgets/right_rail.dart · lines 86-94', r'''
    // Poll rather than watch a provider directly: `ForceLayout.simNodes`
    // and `GraphPainter.lastPaintAt` are mutated from deep inside
    // non-widget code (the physics step, the painter's paint()), the same
    // "watch a mutable field via a driven rebuild" pattern the old debug
    // overlay used.
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }'''),
    ...para('//',
        r'This section is the demoted diagnostic block. It shows the '
        r'WebSocket status, the counts of snapshots and diffs '
        r'received, the graph revision, live nodes, simulation '
        r'nodes, the bounds of the simulation, and the time since '
        r'the last paint. These are the same fields the opt-in debug '
        r'overlay prints, which is the history: the overlay used to '
        r'be on by default, and the UI refresh moved the data here '
        r'so it is always one glance away in a muted ten point type. '
        r'Reading the lines top to bottom walks the pipeline from '
        r'socket to paint, so the first wrong line points at the '
        r'broken seam.'),
    ...para('//',
        r'The polling timer is the same trade as in the overlay. The '
        r'simulation and the painter mutate their state in '
        r'non-widget code, so the panel redraws on a 500 ms timer '
        r'instead of watching a provider. It ticks every 500 ms '
        r'where the overlay ticks every 200 ms, a slower rate for a '
        r'panel that is always on. The panel also drops the '
        r'overlay’s stats counter and its NaN marker. And the '
        r'comment in the Stats arm records a deliberate choice: '
        r'Stats messages are observability-only, not graph topology, '
        r'so they are not tallied with snapshots and diffs.'),
    ...sec(r'the verbose log'),
    ...code('dart', 'heaplens_flutter/lib/widgets/right_rail.dart · lines 162-169', r'''
/// Full-transparency event log: every step HeapLens takes from connection
/// start onward — WS connect/connecting/disconnect transitions, each
/// snapshot/diff received, attach/detach requests and their results,
/// target-exited pushes, and any decode/connection error. Not just "no
/// events yet" — the goal is a reader can follow everything that
/// happened, in order, with timestamps. Bounded scrollback so this
/// doesn't grow forever in a long-running session.
class _VerboseLogsPanel extends ConsumerStatefulWidget {'''),
    ...para('//',
        r'The comment states the goal as full transparency. '
        r'Every step from connection start is logged with a '
        r'timestamp: connection transitions, each snapshot and diff, '
        r'stats, attach and detach requests and their results, '
        r'target-exited pushes, and any stream error. Not just a '
        r'bare no events yet, which is what an empty list says. The '
        r'goal is that a reader can follow what happened, in order. '
        r'It is bounded at 300 lines, with the oldest dropped, so a '
        r'long session does not grow without limit.'),
    ...code('dart', 'heaplens_flutter/lib/widgets/right_rail.dart · lines 188-201', r'''
  void _log(String line) {
    if (!mounted) return;
    setState(() {
      _lines.add('[${_timestamp()}] $line');
      if (_lines.length > _maxLines) _lines.removeAt(0);
    });
    // Keep the newest entry in view — this is a live tail, not a document
    // the reader is expected to scroll back through by default.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }'''),
    ...para('//',
        r'Each line is stamped HH:MM:SS.mmm in local time, and after '
        r'every append a post-frame callback jumps to the end of the '
        r'list. The comment calls it a live tail, not a document the '
        r'reader is expected to scroll back through. The cost is '
        r'real: while you are reading older lines, a new message '
        r'pulls you back to the bottom.'),
    ...code('dart', 'heaplens_flutter/lib/widgets/right_rail.dart · lines 211-227', r'''
    // WS connection lifecycle: connecting / connected / disconnected.
    final status = ref.watch(connectionStatusProvider);
    if (_lastStatus != status) {
      final previous = _lastStatus;
      _lastStatus = status;
      if (previous != null) {
        // Deferred: this build-phase transition must not synchronously
        // call setState on itself mid-build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _log('WS: ${previous.name} -> ${status.name}');
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _log('WS: ${status.name}');
        });
      }
    }'''),
    ...para('//',
        r'Connection transitions are the subtle part. Logging calls '
        r'setState, and build must not call setState on itself, so '
        r'the transition is noticed in build but the log call is '
        r'deferred to a post-frame callback. The first status is '
        r'logged plainly, as WS: connected; later ones as previous '
        r'-> next, with the arrow, which makes a flapping connection '
        r'obvious in the log at a glance.'),
    ...code('dart', 'heaplens_flutter/lib/widgets/right_rail.dart · lines 229-251', r'''
    // Every snapshot/diff, and any stream error (malformed frame, socket
    // error) surfaced as an AsyncValue.error.
    ref.listen<AsyncValue<GraphMessage>>(graphMessageProvider, (previous, next) {
      next.when(
        data: (message) {
          switch (message) {
            case GraphSnapshot snapshot:
              _log('snapshot received: ${snapshot.nodes.length} nodes');
            case GraphDiff diff:
              _log(
                'diff received: +${diff.add.length} add, ~${diff.update.length} update, -${diff.remove.length} remove',
              );
            case GraphStats stats:
              _log(
                'stats: events=${stats.eventsReceived} resolved=${stats.symbolsResolved} '
                'hex_fallback=${stats.hexFallback} target=${stats.targetName ?? "-"}',
              );
          }
        },
        error: (error, stackTrace) => _log('ERROR (graph stream): $error'),
        loading: () {},
      );
    });'''),
    ...para('//',
        r'Messages are described at a useful level of detail: a '
        r'snapshot as its node count, a diff as the sizes of its '
        r'add, update and remove lists, stats as the event and '
        r'symbol counters with the target name or a dash. The error '
        r'callbacks catch a failure as a log line, so a malformed '
        r'frame becomes visible instead of a silently empty canvas. '
        r'cd348b6 is why the stats case exists at all: a master '
        r'merge introduced the GraphStats variant, and flutter '
        r'analyze caught that this widget’s two switches did not '
        r'handle it.'),
    ...code('dart', 'heaplens_flutter/lib/widgets/right_rail.dart · lines 255-280', r'''
    ref.listen<AsyncValue<ControlResponse>>(controlResponseProvider, (previous, next) {
      next.when(
        data: (resp) {
          switch (resp) {
            case ProcessListResponse list:
              _log('process list received: ${list.processes.length} processes');
            case AttachResultResponse result:
              _log(
                result.ok
                    ? 'attach succeeded: ${result.message}'
                    : 'attach FAILED: ${result.message}',
              );
            case DetachResultResponse result:
              _log(
                result.ok
                    ? 'detach succeeded: ${result.message}'
                    : 'detach FAILED: ${result.message}',
              );
            case TargetExitedResponse exited:
              _log('target exited: pid ${exited.pid}');
          }
        },
        error: (error, stackTrace) => _log('ERROR (control stream): $error'),
        loading: () {},
      );
    });'''),
    ...para('//',
        r'The control channel is logged the same way: attach success '
        r'and failure with the daemon’s message, the same for '
        r'detach, the process list size, and target exited with the '
        r'pid. The failures are uppercased, attach FAILED, so they '
        r'stand out in a wall of grey ten point type.'),
    ...sec(r'edge cases and limits'),
    ...pt('//', r'not persistent',
        r'the list lives in widget state. If the rail is rebuilt or '
        r'the app restarts, the history is gone.'),
    ...pt('//', r'pause',
        r'the log keeps recording while the graph is paused, because '
        r'it listens to the stream, not the graph.'),
    ...pt('//', r'duplicated listeners',
        r'the stats panel and the log each add their own listener on '
        r'the message stream, along with the graph, the '
        r'orchestrator, the diagnostics provider and the overlay. '
        r'That is a lot of consumers of one stream. Each does one '
        r'cheap thing.'),
    ...pt('//', r'empty log',
        r'shows the shared empty state, > No events yet, with an '
        r'article icon.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'Not directly. No test in test/ references RightRail or the '
        r'log list key, so the coverage is indirect: its two top '
        r'sections are tested through node_detail_test.dart, its '
        r'empty state through the shared EmptyState, and the whole '
        r'app through widget_test.dart. This is the weakest-tested '
        r'file among the ones I have written about, and a '
        r'log-formatting regression would not fail any test.'),
    ...sec(r'history'),
    ...pt('//', r'1cfb7f9 (2026-07-19)',
        r'UI refresh: creates the rail with four always-on sections, '
        r'moving the overlay’s stats here and adding the log.'),
    ...pt('//', r'cd348b6 (2026-07-21)',
        r'fix(merge): add the GraphStats arm to two switches after a '
        r'merge introduced that variant.'),
  ],
);
