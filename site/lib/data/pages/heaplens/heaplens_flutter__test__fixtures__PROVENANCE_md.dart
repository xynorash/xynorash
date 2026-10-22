import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/fixtures/PROVENANCE.md',
  lines: [
    heading(r'# Fixture provenance'),
    blank,
    ...text(
        r'A test fixture is a claim about the real world, and a '
        r'claim needs a source. PROVENANCE.md is the source note for '
        r'the four JSON files in test/fixtures, and the part of it I '
        r'care most about is the one honest admission: exactly one '
        r'value in those files is not real, and the note says which.'),
    blank,
    kv('role', r'says where each fixture came from and what was edited by hand'),
    kv('language', r'Markdown'),
    kv('size', r'21 lines, one commit: 9ac04cd (2026-07-06)'),
    kv('covers', r'snapshot.json, diff_add.json, diff_remove.json, diff_orphan.json'),
    kv('read by', r'people; no code reads this file'),
    ...sec(r'the capture, as the note describes it'),
    ...code('ini', 'heaplens_flutter/test/fixtures/PROVENANCE.md · lines 3-6', r'''
All fixtures were captured from a live `heaplens-daemon` session:
daemon built from `dev/phase_4` (`master` at `3b6b4a2`), connected to via
`ws://127.0.0.1:9999` while `crates/heaplens-alloc/examples/wire_producer`-style
allocation traffic ran in another process. Capture was done with a small,'''),
    ...text(
        r'Every fixture was captured from a live heaplens-daemon '
        r'session. The daemon was built from the phase 4 branch at a '
        r'named commit, a client connected to its WebSocket on the '
        r'loopback address, and a separate process produced '
        r'allocation traffic. The producer is named in the note as a '
        r'wire_producer-style example from the allocator crate, so '
        r'the traffic shape is the same kind the crate’s own '
        r'examples generate. The capture client is called a small, '
        r'uncommitted Dart WebSocket client that is not part of the '
        r'repository. That is a limit of the note: the tool that made the files cannot '
        r'be re-run from the repo.'),
    ...sec(r'what each file is'),
    ...code('ini', 'heaplens_flutter/test/fixtures/PROVENANCE.md · lines 9-13', r'''
- `snapshot.json` — real snapshot, captured mid-session with 101 live nodes.
- `diff_add.json` — real diff, `add` contains 101 freshly allocated nodes,
  `update`/`remove` empty.
- `diff_remove.json` — real diff, `remove` contains the same 101 node ids
  after they were freed together in one `drop`.'''),
    ...text(
        r'The first three are straight captures. The snapshot has '
        r'101 live nodes: the snapshot file itself shows 100 nodes '
        r'with one outgoing edge and one node with none, all with '
        r'the state healthy, and sizes of 128 or 256 bytes apart '
        r'from one node of 2400. The add diff carries 101 fresh '
        r'nodes; the remove diff carries the same 101 ids after they '
        r'were freed together in a single drop. The fixtures are '
        r'therefore a matched lifecycle: appear, snapshot, '
        r'disappear.'),
    ...sec(r'the hand-edited fixture'),
    ...code('ini', 'heaplens_flutter/test/fixtures/PROVENANCE.md · lines 14-21', r'''
- `diff_orphan.json` — the `update[0]` entry is a **real captured `NodeDto`**
  (same node as `diff_add.json` id `500`), with only the `state` field
  hand-flipped from `"healthy"` to `"orphan"`. The capture rig frees an
  owner and all its children in the same `drop`, so no owner-freed-but-
  child-still-live window (the real precondition for orphan status) occurred
  naturally within the capture session. This fixture exists solely to pin
  `NodeStateDto.orphan` deserialization to the real wire shape; every field
  other than `state` is unmodified real data.'''),
    ...text(
        r'This paragraph is why the file exists. Orphan is the state '
        r'the product is about: an allocation that is live while the '
        r'allocation that owned it has been freed. The rig that '
        r'produced the traffic always freed an owner together with '
        r'all its children in one drop, so the window in which a '
        r'child outlives its owner never occurred, and no real '
        r'orphan could be captured. Rather than fake a whole '
        r'capture, the note takes a real node (the same one that is '
        r'id 500 in the add diff), changes one field, state from '
        r'healthy to orphan, and leaves every other field exactly as '
        r'captured.'),
    ...text(
        r'The note also states the purpose in one clause: the '
        r'fixture exists solely to pin the decoding of the orphan '
        r'state to the real wire shape. It does not claim the data '
        r'is a real orphan, it does not claim the daemon would send '
        r'that exact message, and it names the single modified '
        r'field. A reader who finds a surprising value in '
        r'diff_orphan.json can tell in seconds whether it is real.'),
    ...sec(r'how the fixtures are used'),
    ...text(
        r'The contract test is the consumer. '
        r'test/models/contract_test.dart opens each file with '
        r'dart:io by the relative path test/fixtures, which is why '
        r'the tests must be run from the heaplens_flutter directory. '
        r'Its header says the wire contract source of truth is the '
        r'diff.rs file in the protocol crate. For the snapshot it '
        r'asserts the timestamp 329700, a node count of 101, and '
        r'then every field of the first node: id 571, pointer '
        r'1599777467168, size 256, timestamp 230900, a hex symbol, '
        r'live, healthy, and the edge list with the one entry 572. '
        r'For the diffs it asserts 101 adds and 101 removes, and '
        r'empty lists for the other two kinds.'),
    ...text(
        r'The snapshot symbols are all the same hex address, '
        r'0x7ff74ba66230, and none is a resolved name, so the '
        r'capture is also a picture of a target whose call sites '
        r'were not symbolized. You can check that by opening the '
        r'file.'),
    ...sec(r'limits worth knowing'),
    ...bullet(r'the commit hash',
        r'the note names the daemon commit as 3b6b4a2. In the repo that '
        r'is the merge commit of dev/phase_4 (2026-07-06, anomaly '
        r'detection, SQLite store, WS server), which matches the '
        r'note.'),
    ...bullet(r'the snapshot is one sample',
        r'a single mid-session snapshot with a uniform shape. It '
        r'pins the format, not the variety of real programs.'),
    ...bullet(r'no daemon-side check',
        r'I found nothing in the repo that regenerates the fixtures or '
        r'compares them against the daemon. If the daemon changes the wire format the '
        r'Dart tests keep passing against stale JSON until someone '
        r're-captures.'),
    ...bullet(r'new message kinds',
        r'the Stats and control messages added later have no '
        r'captured fixture files here; contract_test.dart has its '
        r'own group for GraphStats.fromJson instead.'),
    ...sec(r'history'),
    ...bullet(r'9ac04cd (2026-07-06)',
        r'docs(flutter): M5 build plan and real captured contract '
        r'fixtures. This one commit adds the note, all four JSON '
        r'files, and the M5 plan.'),
  ],
);
