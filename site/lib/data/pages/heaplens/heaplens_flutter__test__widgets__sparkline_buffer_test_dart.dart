import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/widgets/sparkline_buffer_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'sparkline_buffer_test.dart — a bounded history for one node'),
    cm('//', r'five unit tests, no widget tree, for the sparkline’s data structure'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'pins the record, dedupe, reset and bound behaviour of SparklineBuffer'),
    kv('language', r'Dart, flutter_test unit tests'),
    kv('size', r'74 lines, 5 tests'),
    kv('history', r'one commit, 8d22db5 (2026-07-06), together with the node detail panel'),
    kv('subject', r'SparklineBuffer in lib/widgets/node_detail.dart'),
    ...sec(r'why a separate test file for a class in a widget file'),
    ...para('//', r'SparklineBuffer lives in node_detail.dart next to the panel that draws it, but the doc comment above the class says why it is a class of its own: it is exposed rather than inlined as private widget state so its reset and bound-growth behaviour can be unit tested directly, without driving a widget tree. This file is that decision cashed in. No pumpWidget, no providers; just construct a buffer, feed it nodes, read samples.'),
    ...sec(r'what the buffer is for'),
    ...code('dart', r'heaplens_flutter/lib/widgets/node_detail.dart · capacity and sample type', r'''
const int kSparklineCapacity = 120;

/// One (ts, size) sample recorded for the sparkline.
typedef SparklineSample = ({int ts, int size});'''),
    ...para('//', r'The node detail panel shows the size of the selected allocation over time as a small chart. The data is a list of (ts, size) pairs for one node, capped at 120. The tests describe four rules, and the helper at the top builds a NodeDto with only the three fields that matter here: id, ts and size.'),
    ...code('dart', r'heaplens_flutter/test/widgets/sparkline_buffer_test.dart · helper', r'''
NodeDto _node({required int id, required int ts, required int size}) {
  return NodeDto(
    id: id,
    ptr: 0,
    size: size,
    ts: ts,
    symbol: 'sym',
    live: true,
    state: NodeStateDto.healthy,
    edges: const [],
  );
}'''),
    ...sec(r'rule 1: record what arrives, in order'),
    ...code('dart', r'heaplens_flutter/test/widgets/sparkline_buffer_test.dart · records samples', r'''
  test('records (ts, size) samples for a node', () {
    final buffer = SparklineBuffer();
    buffer.record(_node(id: 1, ts: 1, size: 10));
    buffer.record(_node(id: 1, ts: 2, size: 20));

    expect(buffer.nodeId, 1);
    expect(buffer.samples, [(ts: 1, size: 10), (ts: 2, size: 20)]);
  });'''),
    ...para('//', r'Two updates for node 1 give two samples in order, and nodeId is 1. Dart records make this assertion readable: samples is compared to a list of (ts: ..., size: ...) records by value.'),
    ...sec(r'rule 2: only record changes'),
    ...code('dart', r'heaplens_flutter/test/widgets/sparkline_buffer_test.dart · dedupe', r'''
  test('deduplicates consecutive samples with an unchanged size', () {
    final buffer = SparklineBuffer();
    buffer.record(_node(id: 1, ts: 1, size: 10));
    buffer.record(_node(id: 1, ts: 2, size: 10));
    buffer.record(_node(id: 1, ts: 3, size: 20));

    expect(buffer.samples, [(ts: 1, size: 10), (ts: 3, size: 20)]);
  });'''),
    ...para('//', r'The daemon sends an update for a node whenever something about it changes, not just its size. If every update became a point the chart would be a flat line with a point per message. The buffer keeps a sample only when the size differs from the last one. In the test, sizes 10, 10, 20 give two samples, and the one that survives of the first pair is the earlier one (ts 1): the comment in node_detail.dart says only the first of an unchanged run is kept.'),
    blank,
    ...para('//', r'The comparison is against the last sample only. A node that goes 10, 20, 10 would record all three; that is by design a change-log, not a set. No test covers that case.'),
    ...sec(r'rule 3: one node at a time'),
    ...code('dart', r'heaplens_flutter/test/widgets/sparkline_buffer_test.dart · a new id resets', r'''
  test('resets and discards old samples when fed a different node id', () {
    final buffer = SparklineBuffer();
    buffer.record(_node(id: 1, ts: 1, size: 10));
    buffer.record(_node(id: 1, ts: 2, size: 20));
    expect(buffer.samples.length, 2);

    buffer.record(_node(id: 2, ts: 3, size: 999));

    expect(buffer.nodeId, 2);
    expect(buffer.samples, [(ts: 3, size: 999)]);
  });'''),
    ...para('//', r'The buffer follows whichever node is selected. Feeding it node 2 after node 1 must discard node 1’s samples, otherwise the chart for the new selection would start with a stale tail from the old one. The test records two samples for id 1, checks the length is 2 to make sure the setup worked, then records node 2 and expects nodeId 2 and exactly one sample. The sizes 999 versus 10 and 20 are far apart so a leak would be obvious in the failure message.'),
    ...code('dart', r'heaplens_flutter/test/widgets/sparkline_buffer_test.dart · reset()', r'''
  test('reset() clears samples and forgets the tracked node id', () {
    final buffer = SparklineBuffer();
    buffer.record(_node(id: 1, ts: 1, size: 10));

    buffer.reset();

    expect(buffer.nodeId, isNull);
    expect(buffer.samples, isEmpty);
  });'''),
    ...para('//', r'reset() is the explicit version, for when the selection is cleared. It must both empty the samples and forget the node id, which the test checks with isNull and isEmpty. Forgetting the id matters: if the id stayed, re-selecting the same node would skip the reset branch and keep samples from before the gap.'),
    ...sec(r'rule 4: stay bounded'),
    ...code('dart', r'heaplens_flutter/test/widgets/sparkline_buffer_test.dart · bounded at kSparklineCapacity', r'''
  test('stays bounded at kSparklineCapacity despite many updates', () {
    final buffer = SparklineBuffer();
    for (var i = 0; i < kSparklineCapacity * 3; i++) {
      // Distinct sizes each time so nothing gets deduplicated away.
      buffer.record(_node(id: 1, ts: i, size: i));
    }

    expect(buffer.samples.length, kSparklineCapacity);
    // Oldest entries were evicted: the buffer should hold the most recent
    // kSparklineCapacity samples, i.e. sizes from
    // (3*cap - cap) .. (3*cap - 1).
    final expectedFirstSize = kSparklineCapacity * 3 - kSparklineCapacity;
    expect(buffer.samples.first.size, expectedFirstSize);
    expect(buffer.samples.last.size, kSparklineCapacity * 3 - 1);
  });'''),
    ...para('//', r'The loop feeds 360 samples, three times the 120 capacity, each with a distinct size so deduplication cannot remove any, as the comment in the loop says. The result must be exactly 120 long, the first retained size must be 240 (360 minus 120), and the last 359. That checks two things at once: the cap, and that eviction removes the oldest rather than the newest. A buffer that dropped incoming samples once full would be bounded too, and would fail the first-size assertion.'),
    blank,
    ...para('//', r'The expected values are computed from kSparklineCapacity instead of written as 240, so the test keeps passing if somebody retunes the capacity. Eviction is removeAt(0) on a plain list; at 120 entries the cost is irrelevant. The source does not use a ring-buffer class.'),
    ...sec(r'boundaries of the test'),
    ...pt('//', r'not the drawing', r'how the samples become a line is in the _Sparkline widget in node_detail.dart. No test file mounts NodeSparklinePanel, the panel that owns the buffer and calls record() on every build and reset() when the selection clears.'),
    ...pt('//', r'a moved panel', r'the sparkline started inside NodeDetail (8d22db5) and was split into its own right-rail panel by the UI refresh (1cfb7f9). node_detail_test.dart still has a test about switching selection, but it now exercises NodeDetail only.'),
  ],
);
