import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/widgets/node_detail.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'node_detail.dart — one allocation, in full'),
    cm('//', r'the selected node as fields, an age that never goes backwards, and a bounded sparkline'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'right-rail panels: Node detail and Size over time'),
    kv('language', r'Dart / Flutter, fl_chart'),
    kv('size', r'272 lines, 6 widget tests and 5 buffer tests'),
    kv('history', r'3 commits: 8d22db5 (2026-07-06), 0661725 (2026-07-06), 1cfb7f9 (2026-07-19)'),
    kv('tests', r'test/widgets/node_detail_test.dart, test/widgets/sparkline_buffer_test.dart'),
    kv('reads', r'selectedNodeIdProvider, graphProvider'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'The canvas shows shape and the map shows layout; neither '
        r'can say how large this one allocation is, where it lives, '
        r'who owns it or how long it has existed. This file is the '
        r'place a person goes after clicking a node. It holds two '
        r'widgets: NodeDetail, a field list for the selected node, '
        r'and NodeSparklinePanel, a small chart of that node’s size '
        r'over time. They were one panel in the first version and '
        r'were split in the UI refresh so that each can live in its '
        r'own section of the right rail.'),
    ...sec(r'the field list'),
    ...code('dart', 'heaplens_flutter/lib/widgets/node_detail.dart · lines 92-110', r'''
    final selectedId = ref.watch(selectedNodeIdProvider);

    if (selectedId == null || !nodes.containsKey(selectedId)) {
      // Selection cleared, or the selected node no longer exists in state
      // (e.g. a `remove` diff deleted it) -- show a placeholder rather than
      // risk a null lookup.
      return const EmptyState(message: 'no node selected', icon: Icons.touch_app_outlined);
    }

    final node = nodes[selectedId]!;

    int scanMaxTs = node.ts;
    NodeDto? owner;
    for (final n in nodes.values) {
      if (n.ts > scanMaxTs) scanMaxTs = n.ts;
      if (n.edges.contains(selectedId)) owner = n;
    }
    _maxTsSeen = _maxTsSeen > scanMaxTs ? _maxTsSeen : scanMaxTs;
    final age = _maxTsSeen - node.ts;'''),
    ...para('//',
        r'The build watches the graph revision so it rebuilds when '
        r'anything changes, then reads the node map fresh, and reads '
        r'the selection. If nothing is selected, or the selected id '
        r'has left the map, it returns an explicit empty state '
        r'instead of dereferencing a missing node. Otherwise a '
        r'single pass over all nodes does two jobs at once: it finds '
        r'the largest timestamp in the map, and it finds the owner, '
        r'the node whose edge list contains the selected id.'),
    ...para('//',
        r'That owner lookup is a linear scan with no index. The wire '
        r'format stores edges from owner to children, so the reverse '
        r'question, who owns me, has to be answered by searching. If '
        r'two nodes both list the selected id, the last one in map '
        r'order wins, which in a clean ownership tree never happens. '
        r'At the scale this app draws, one scan per rebuild is a '
        r'fair price for not maintaining a reverse index that could '
        r'drift from the real map.'),
    ...code('dart', 'heaplens_flutter/lib/widgets/node_detail.dart · lines 116-142', r'''
        Row(
          children: [
            Expanded(
              // The symbol is a real code identifier (a resolved call-site
              // name), not prose — monospace here too, same as the field
              // values below, at a size that reads as a header.
              child: Text(
                node.symbol,
                style: XynorashTheme.mono(fontSize: 15, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            NodeStateChip(state: node.state),
          ],
        ),
        const SizedBox(height: 8),
        _DetailRow('ptr', '0x${node.ptr.toRadixString(16)}'),
        _DetailRow('size', '${node.size}', tooltip: 'Allocation size in bytes.'),
        _DetailRow('age', '$age', tooltip: 'How long this allocation has been live, in producer-clock ticks.'),
        _DetailRow('state', node.state.name, tooltip: kNodeStateDescriptions[node.state]!),
        _DetailRow(
          'owner',
          owner == null ? 'none' : '${owner.id}',
          trailing: owner == null ? null : '(0x${owner.ptr.toRadixString(16)})',
          tooltip: 'The allocation that owns this one, if any.',
        ),
        _DetailRow('edges', '${node.edges.length}', tooltip: 'Number of allocations this node owns.'),'''),
    ...para('//',
        r'Every row is a label and a monospace value, with a '
        r'plain-language tooltip on all but the pointer. The pointer '
        r'is printed in hex, the size in bytes, and the owner as an '
        r'id with its pointer in parentheses, or none. The state row '
        r'shows the raw wire name next to the colored chip in the '
        r'header, so both the friendly label and the machine name '
        r'are on screen. The comment on the symbol says why it is '
        r'monospace: it is a resolved call-site identifier, not '
        r'prose.'),
    ...sec(r'an age that does not run backwards'),
    ...code('dart', 'heaplens_flutter/lib/widgets/node_detail.dart · lines 77-86', r'''
class _NodeDetailState extends ConsumerState<NodeDetail> {
  /// Client-side rolling max of `ts` across all nodes ever seen, analogous
  /// to the daemon's own `max_ts_seen` (see graph.rs:
  /// `self.max_ts_seen = self.max_ts_seen.max(ev.ts_nanos)`). Monotonic --
  /// updated only via `.max()` against the current live-node scan, so it
  /// never decreases even when the node carrying the current max is later
  /// removed by a `remove` diff. Persisted on the state (not recomputed
  /// from scratch each build) precisely so that churn like alloc-then-free
  /// can't make a selected node's displayed `age` visibly snap backwards.
  int _maxTsSeen = 0;'''),
    ...para('//',
        r'Age is the largest timestamp seen minus this node’s '
        r'timestamp, with no wall clock involved: timestamps are the '
        r'producer’s own ticks, and the tooltip says exactly that. '
        r'The first version recomputed the maximum from scratch on '
        r'every build by scanning only the nodes currently live. The '
        r'commit that fixed it describes the symptom: when the node '
        r'carrying the current maximum was freed by a remove diff, '
        r'which is ordinary alloc and free churn, the next build '
        r'computed a smaller maximum and the displayed age of a '
        r'selected node visibly snapped toward zero and climbed '
        r'again.'),
    ...para('//',
        r'The fix, 0661725, keeps the running maximum on the State '
        r'object and moves it only upward, mirroring what the commit '
        r'calls the daemon’s own max_ts_seen. The regression test is '
        r'named age does not decrease when the node carrying the max '
        r'ts is removed. The persisted field is also why the widget '
        r'is a ConsumerStatefulWidget and not a plain '
        r'ConsumerWidget; it is the only reason.'),
    ...para('//',
        r'A limit worth knowing: the maximum is never reset. It '
        r'survives a change of selection, which is right, and it '
        r'would survive a new session or a reconnect to a different '
        r'target, which could be wrong if the new producer’s clock '
        r'starts lower. Nothing in the file handles that case.'),
    ...sec(r'the ring buffer behind the chart'),
    ...code('dart', 'heaplens_flutter/lib/widgets/node_detail.dart · lines 12-16, 32-49', r'''
/// Bounded ring-buffer capacity for the size-over-time sparkline.
const int kSparklineCapacity = 120;

/// One (ts, size) sample recorded for the sparkline.
typedef SparklineSample = ({int ts, int size});
...
  /// Records a sample for [node]. If [node.id] differs from the id the
  /// buffer currently tracks, the buffer is reset (old samples discarded)
  /// before recording. Consecutive samples with an unchanged `size` are
  /// deduplicated (only the first is kept) so the sparkline reflects actual
  /// size changes rather than every message. Bounded to
  /// [kSparklineCapacity] entries; oldest is evicted once full.
  void record(NodeDto node) {
    if (_nodeId != node.id) {
      _nodeId = node.id;
      _samples.clear();
    }
    if (_samples.isEmpty || _samples.last.size != node.size) {
      _samples.add((ts: node.ts, size: node.size));
      if (_samples.length > kSparklineCapacity) {
        _samples.removeAt(0);
      }
    }
  }'''),
    ...para('//',
        r'SparklineBuffer holds at most 120 samples for one node at '
        r'a time. It is a separate class, and not private widget '
        r'state, so its rules can be unit tested without a widget '
        r'tree: the commit says so. Three rules. A different node id '
        r'clears the buffer, so a new selection never inherits '
        r'another node’s history. A sample is skipped when its size '
        r'equals the last recorded size, and the doc says why: the '
        r'chart should show actual changes, not every message. And '
        r'beyond 120 entries the oldest is dropped.'),
    ...para('//',
        r'The deduplication is not only about looks. '
        r'NodeSparklinePanel calls record from inside build, a side '
        r'effect in a build method, and Flutter may rebuild with the '
        r'same node many times. Because a repeated size is ignored, '
        r'recording is idempotent, which is what makes that '
        r'tolerable. Samples are named records of timestamp and '
        r'size, a Dart 3 typedef.'),
    ...sec(r'a flat line is an answer'),
    ...code('dart', 'heaplens_flutter/lib/widgets/node_detail.dart · lines 229-245', r'''
    // A node whose size genuinely never changes only ever produces one
    // deduplicated sample (SparklineBuffer.record dedupes consecutive
    // same-size updates) — that used to fall into the same "collecting
    // data..." branch as zero samples and never resolve, since a
    // single-point line has nothing to interpolate between. That's not
    // "still collecting", it's a real, final answer: this allocation's
    // size has been constant since it appeared. Render it as a flat line
    // at that one value instead of leaving the panel looking broken.
    final spots = samples.length == 1
        ? [
            FlSpot(0, samples[0].size.toDouble()),
            FlSpot(1, samples[0].size.toDouble()),
          ]
        : [
            for (var i = 0; i < samples.length; i++)
              FlSpot(i.toDouble(), samples[i].size.toDouble()),
          ];'''),
    ...para('//',
        r'This comment records a bug that the code now handles. A node '
        r'whose size never changes yields exactly one deduplicated '
        r'sample, and a line chart cannot draw one point, so it fell '
        r'into the same collecting data branch as zero samples and '
        r'the panel stayed in that state forever. That is not still '
        r'collecting, it is a final answer: this allocation has had '
        r'the same size since it appeared. The code now renders a '
        r'single sample as a flat line, two points at the same '
        r'value. Two or more samples plot the index of the sample on '
        r'the x axis, not time, so the chart is a history of '
        r'changes, not a time-proportional plot; the bottom, top and '
        r'right axis titles are off and only the left size scale '
        r'remains.'),
    ...sec(r'edge cases'),
    ...pt('//', r'stale selection',
        r'handled in both panels: the detail returns the empty '
        r'state, the sparkline resets its buffer and returns its '
        r'own.'),
    ...pt('//', r'rapid selection changes',
        r'switching nodes resets the buffer through the id check, '
        r'and a test covers switching without a crash.'),
    ...pt('//', r'chart cost',
        r'LineChart rebuilds on every graph revision while a node is '
        r'selected. With at most 120 points that is cheap.'),
    ...pt('//', r'line color',
        r'the sparkline uses colorForState of the node, so the chart '
        r'of an orphan is coral.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'Two files. node_detail_test.dart has six widget tests: the '
        r'placeholder when nothing is selected (it expects the text '
        r'> no node selected and no exception), the placeholder when '
        r'the selected id is not in the map, the full field '
        r'rendering for a selected node, age computed against the '
        r'rolling maximum and not wall-clock, age that does not '
        r'decrease when the max-ts node is removed, and switching '
        r'selection without a crash. sparkline_buffer_test.dart has '
        r'five unit tests: records samples, deduplicates equal '
        r'sizes, resets on a new id, reset clears and forgets the '
        r'id, and stays bounded at the capacity.'),
    ...sec(r'history'),
    ...pt('//', r'8d22db5 (2026-07-06)',
        r'M5 task 8: node detail side panel with a sparkline. '
        r'Introduces the 120-sample buffer as its own class and the '
        r'age against a rolling maximum.'),
    ...pt('//', r'0661725 (2026-07-06)',
        r'fix: persist the monotonic rolling maximum in the state, '
        r'with a regression test.'),
    ...pt('//', r'1cfb7f9 (2026-07-19)',
        r'UI refresh: splits the sparkline into its own panel, moves '
        r'to the monospace field list, tooltips and the shared empty '
        r'state.'),
  ],
);
