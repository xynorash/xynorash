import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-protocol/src/diff.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'diff.rs — the JSON contract between the daemon and the UI'),
    cm('//', r'three message shapes, one inline type tag, and a warning about 2^53'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'the daemon-to-Flutter seam (snapshot, diff, stats)'),
    kv('language', r'Rust with serde derive'),
    kv('size', r'59 lines, 4 integration tests in tests/diff_json.rs'),
    kv('history', r'4 commits, 2026-06-24 to 2026-07-17'),
    kv('mirrored by', r'heaplens_flutter/lib/models/node.dart and graph_diff.dart'),
    ...sec(r'the second seam'),
    ...para('//',
        r'The Build Spec says there are exactly two coupling contracts in '
        r'the system. The first is the binary frame protocol from the '
        r'allocator to the daemon (frame.rs). The second is this file: the '
        r'JSON the daemon pushes over a WebSocket to the Flutter app. '
        r'Everything else in each unit is private. The rule behind it '
        r'(invariant 10 in the spec) is that "Flutter knows only JSON": '
        r'the UI makes no assumptions about Rust layouts, pointers as '
        r'pointers, or anything inside the daemon.'),
    blank,
    ...para('//',
        r'That makes these 59 lines the most load-bearing part of the UI’s '
        r'design. If a field here changes name, the Dart models break. The '
        r'comments say so twice: "Field names are the wire contract — '
        r'Flutter mirrors them verbatim."'),
    ...sec(r'the node: one allocation as the UI sees it'),
    ...code('rust', 'crates/heaplens-protocol/src/diff.rs · NodeState and NodeDto', r'''
use serde::{Deserialize, Serialize};

/// Node lifecycle state. Serializes as lowercase: "healthy" | "orphan" | "hot" | "freed".
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum NodeState {
    Healthy,
    Orphan,
    Hot,
    Freed,
}

/// Single node in the ownership graph.
/// Field names are the wire contract — Flutter mirrors them verbatim.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct NodeDto {
    pub id:     u64,
    pub ptr:    u64,
    pub size:   u64,
    pub ts:     u64,
    pub symbol: String,
    pub live:   bool,
    pub state:  NodeState,
    pub edges:  Vec<u64>,
}'''),
    ...para('//',
        r'A NodeDto is one live (or just-freed) allocation. id is the '
        r'daemon’s own identifier for the node, ptr is the allocation '
        r'address, size is in bytes, ts is the producer-side timestamp at '
        r'allocation, symbol is the resolved name of the node’s effective '
        r'call site, live says whether it still exists, state is the '
        r'lifecycle label, and edges lists the ids of the nodes this one '
        r'owns. The ownership edges are the daemon’s inference (its phi '
        r'function), not facts observed by the allocator; the UI just '
        r'draws them.'),
    blank,
    ...para('//',
        r'NodeState is serialised in lowercase by a single serde '
        r'attribute, so the four states appear on the wire as "healthy", '
        r'"orphan", "hot" and "freed". The test '
        r'nodestate_serializes_lowercase pins each of the four strings. '
        r'The Dart mirror (node.dart, NodeStateDto.fromWire) is '
        r'deliberately forgiving: an unknown state string falls back to '
        r'healthy with a debug-mode warning, so a state added on the Rust '
        r'side does not crash an older client. The Rust side has no such '
        r'fallback.'),
    ...sec(r'the message: an internally tagged union'),
    ...code('rust', 'crates/heaplens-protocol/src/diff.rs · GraphMessage (doc comment and the first two variants) (trimmed)', r'''
/// Discriminated union for the daemon→Flutter message shapes.
///
/// Serializes with an inline `"type"` tag:
///   Snapshot → `{ "type": "snapshot", "ts": …, "nodes": […] }`
///   Diff     → `{ "type": "diff",     "ts": …, "add": […], "update": […], "remove": […] }`
...
///
/// NOTE: `u64` fields serialize as bare JSON numbers. This is safe for the
/// Dart VM (Flutter desktop/native on Windows) where `int` is 64-bit.
/// It is NOT safe under dart2js / Flutter web (IEEE-754 doubles, max 2^53).
/// If the project retargets Flutter web, ptr/id/ts must become JSON strings.
///
/// Lenient deserialization (no `deny_unknown_fields`) is deliberate: forward-
/// compatible additions to NodeDto must not break older deserializers.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum GraphMessage {
    Snapshot { ts: u64, nodes: Vec<NodeDto> },
    Diff     { ts: u64, add: Vec<NodeDto>, update: Vec<NodeDto>, remove: Vec<u64> },'''),
    ...para('//',
        r'The enum uses serde’s internal tagging: #[serde(tag = "type", '
        r'rename_all = "lowercase")]. Instead of wrapping every message in '
        r'an envelope, the variant name becomes a "type" field next to the '
        r'payload, so a snapshot is { "type": "snapshot", "ts": ..., '
        r'"nodes": [...] } and a diff is { "type": "diff", "ts": ..., '
        r'"add": [...], "update": [...], "remove": [...] }. The tests '
        r'assert the shape both ways: a snapshot must not carry add, '
        r'update or remove, and a diff must not carry nodes.'),
    blank,
    ...para('//',
        r'The protocol is built around a snapshot-then-diff idea. On '
        r'connect the daemon sends one full snapshot; after that it sends '
        r'diffs. In daemon/server.rs the snapshot and the subscription to '
        r'the diff stream are requested together from the graph task, '
        r'"atomically", so a client cannot miss a change in between. In '
        r'diffs, add and update carry whole NodeDto values and remove '
        r'carries only ids. The diff cadence is the daemon’s tick, 33 ms '
        r'by default (about 30 Hz, config.rs), and a tick that changed '
        r'nothing sends nothing (main.rs gates the broadcast on '
        r'is_non_empty_diff).'),
    blank,
    ...para('//',
        r'A detail worth knowing: the ts in a message is not wall-clock '
        r'time. The daemon fills it with max_ts_seen, the largest producer '
        r'timestamp it has received (nanoseconds on the producer’s own '
        r'monotonic clock, whose zero is its first captured event; see '
        r'capture.rs). The sample values in the tests, like '
        r'1_719_240_000_000, are only sample numbers. The same logical '
        r'clock is why the example producers keep a heartbeat of tiny '
        r'allocations running: no events, no clock, no ageing.'),
    ...sec(r'the third variant arrives'),
    ...code('rust', 'crates/heaplens-protocol/src/diff.rs · Stats', r'''
    /// Observability-only, periodic session counters — never consulted by
    /// phi or anomaly detection, purely for the Flutter target-diagnostics
    /// banner to classify "capturing / no events / no edges / unsymbolized".
    /// `target_pid`/`target_name` are `None` until the daemon has received a
    /// HANDSHAKE frame from the attached target.
    Stats {
        ts: u64,
        events_received: u64,
        symbols_resolved: u64,
        hex_fallback: u64,
        target_pid: Option<u64>,
        target_name: Option<String>,
    },
}'''),
    ...para('//',
        r'Stats was added on 2026-07-17 in commit 0edc728 ("honest '
        r'target-status banner"). Its job is to let the UI tell the user '
        r'why the graph is blank. A plain empty graph could mean the '
        r'target is not allocating, or events are arriving but no '
        r'ownership edges form, or symbols are not resolving and every '
        r'frame name is a hex fallback. The counters distinguish them: '
        r'events_received (counted before diff filtering, so allocations '
        r'born and freed within one tick still count), symbols_resolved '
        r'and hex_fallback, and the attached process’s pid and name. The '
        r'doc comment is explicit that these are "never consulted by phi '
        r'or anomaly detection", and the commit message says the daemon '
        r'test suite passed unchanged, with a dedicated regression test '
        r'proving edges still form with the counters on.'),
    blank,
    ...para('//',
        r'The daemon emits Stats on a fixed one-second cadence '
        r'(STATS_INTERVAL in main.rs), decoupled from the 33 ms tick. '
        r'target_pid and target_name are Option, so they serialise as null '
        r'until the handshake frame has arrived.'),
    blank,
    ...para('//',
        r'Adding the variant is also a lesson about where leniency stops. '
        r'Probing the types in a scratch crate maps it. Unknown fields are '
        r'ignored: a snapshot whose node carries an extra future_field '
        r'deserialises fine. Unknown node states are not: serde rejects a '
        r'state of "weird" with a list of the four valid names, and only '
        r'the Dart NodeStateDto.fromWire falls back to healthy. Unknown '
        r'message types are rejected on both sides: serde reports "unknown '
        r'variant `nodedetail`, expected one of `snapshot`, `diff`, '
        r'`stats`", and the Dart GraphMessage.fromJson has a default arm '
        r'in its switch on json[’type’] that throws a '
        r'FormatException("unknown type"). So a new message type is a '
        r'coordinated change, and commit 0edc728 touched both sides, '
        r'adding GraphStats to graph_diff.dart.'),
    blank,
    ...para('//',
        r'What the types emit, copied from a scratch run that serialised '
        r'them with serde_json (not part of the repo):'),
    blank,
    cm('//', r'{"type":"diff","ts":1,"add":[],"update":[],"remove":[5]}'),
    cm('//', r'{"type":"stats","ts":7,"events_received":1,"symbols_resolved":2,'),
    cm('//', r' "hex_fallback":3,"target_pid":null,"target_name":null}'),
    cm('//', r'{"type":"stats", ... "target_pid":4242,"target_name":"x"}'),
    cm('//', r'{"id":1,"ptr":18446744073709551615,"size":1,"ts":18446744073709551615,'),
    cm('//', r' "symbol":"s","live":true,"state":"hot","edges":[2,3]}'),
    blank,
    ...para('//',
        r'The last line is the one to look at for the 2^53 warning below: '
        r'u64::MAX is written as a bare 20-digit JSON number. serde_json '
        r'is perfectly happy with it; whether the reader is, depends on '
        r'what its number type is.'),
    ...sec(r'two decisions written down in the doc comment'),
    ...para('//',
        r'The comment above the enum records two choices that are easy to '
        r'get wrong later.'),
    blank,
    ...para('//',
        r'First, no deny_unknown_fields. The Stage 1 design note gives two '
        r'reasons: internal tagging interacts poorly with it in some serde '
        r'versions, and forbidding unknown fields would make the contract '
        r'brittle against forward-compatible additions to NodeDto. Lenient '
        r'deserialisation was picked as the right default for a type that '
        r'will evolve, and it did evolve: Stats is the proof.'),
    blank,
    ...para('//',
        r'Second, the NOTE on 64-bit integers. id, ptr, ts and size are '
        r'u64 and become bare JSON numbers. The Dart VM’s int is 64-bit, '
        r'so this is exact for Flutter desktop on Windows, which is the '
        r'target. Under dart2js (Flutter web), numbers are IEEE-754 '
        r'doubles and anything above 2^53 silently loses bits. The comment '
        r'says what to do if the project retargets the web: make ptr, id '
        r'and ts JSON strings. A reading that the repo does not claim: on '
        r'64-bit Windows, user-mode addresses sit below 2^47, so real '
        r'pointers would fit in a double exactly, and ts in nanoseconds '
        r'since process start would take about 104 days to reach 2^53. The '
        r'warning is conservative rather than imminent, but it is stated '
        r'at the point where the type is defined, which is where it will '
        r'be seen.'),
    blank,
    ...para('//',
        r'A serde subtlety to keep in mind, because the sibling file '
        r'control.rs behaves differently: this enum uses rename_all = '
        r'"lowercase", which does not insert underscores. A future '
        r'multi-word variant such as NodeDetail would become "nodedetail" '
        r'here, while ControlResponse uses snake_case and would give '
        r'"node_detail". The two tag vocabularies are disjoint today '
        r'(snapshot, diff, stats against process_list, attach_result, '
        r'detach_result, target_exited), which is what lets one WebSocket '
        r'carry both streams.'),
    ...sec(r'how it is tested'),
    ...code('rust', 'crates/heaplens-protocol/tests/diff_json.rs · snapshot_json_shape', r'''
#[test]
fn snapshot_json_shape() {
    let msg = GraphMessage::Snapshot {
        ts: 1_719_240_000_000,
        nodes: vec![sample_node(1), sample_node(2)],
    };
    let json = serde_json::to_string(&msg).expect("serialize");
    let v: Value = serde_json::from_str(&json).expect("parse");

    assert_eq!(v["type"], "snapshot", "type tag must be 'snapshot'");
    assert!(v["nodes"].is_array(), "nodes must be an array");
    assert!(v.get("add").is_none(), "snapshot must not have 'add'");
    assert!(v.get("update").is_none(), "snapshot must not have 'update'");
    assert!(v.get("remove").is_none(), "snapshot must not have 'remove'");

    let first = &v["nodes"][0];
    assert!(first["id"].is_number());
    assert!(first["ptr"].is_number());
    assert!(first["size"].is_number());
    assert!(first["ts"].is_number());
    assert!(first["symbol"].is_string());
    assert!(first["live"].is_boolean());
    assert_eq!(first["state"], "healthy");
    assert!(first["edges"].is_array());
}'''),
    ...para('//',
        r'The tests parse the serialised string back into '
        r'serde_json::Value and assert on keys and types instead of '
        r'comparing strings, so they are insensitive to field order and '
        r'whitespace and sensitive to exactly what a Dart client would '
        r'see. The design note calls this out: key assertions on a parsed '
        r'Value, not substring matches. A fourth test round-trips a '
        r'snapshot through JSON and compares for equality, which is why '
        r'the types derive PartialEq and Eq (commit fb8a4fc added Eq to '
        r'NodeDto and GraphMessage right after the first version).'),
    blank,
    ...para('//',
        r'There is no Rust test for the Stats variant inside this crate. '
        r'It is exercised in the daemon '
        r'(tests/target_diagnostics_stats.rs) and from the other side in '
        r'the Flutter contract tests.'),
    ...sec(r'limits'),
    ...pt('//',
        r'no schema version',
        r'nothing on the wire says which revision of the contract a '
        r'message follows. Changes are made in lock-step across Rust and '
        r'Dart, in one repository.'),
    ...pt('//',
        r'whole-node updates',
        r'an update repeats the full NodeDto, including the entire edges '
        r'list, even if only one edge was added. For a hot owner with '
        r'dozens of children that is bigger than it needs to be. The '
        r'simplicity (the UI replaces the node by id) is the trade.'),
    ...pt('//',
        r'two ways to say dead',
        r'a node carries both live: bool and state: Freed. The spec’s '
        r'example JSON has both, and no place turned up where the pair can '
        r'disagree, but the redundancy is a thing to keep in sync.'),
    ...pt('//',
        r'ts is not wall time',
        r'described above. Any consumer that wants a real timestamp has to '
        r'add one.'),
    ...pt('//',
        r'strict on variants',
        r'described above. The first unknown type kills the Dart parse of '
        r'that message.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-protocol/src/diff.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-protocol/src/diff.rs'),
  ],
);
