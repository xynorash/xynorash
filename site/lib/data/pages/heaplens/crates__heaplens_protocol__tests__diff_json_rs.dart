import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-protocol/tests/diff_json.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'diff_json.rs — asserting on the JSON a Dart client will actually see'),
    cm('//', r'parse it back into a Value and check the keys, not the string'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'pins the JSON shape of the daemon-to-UI messages'),
    kv('language', r'Rust integration test (serde_json is a dev-dependency)'),
    kv('size', r'86 lines, 4 tests (design note id T7)'),
    kv('history', r'one commit, 67d3658 on 2026-06-24, never edited since'),
    kv('exercises', r'GraphMessage, NodeDto, NodeState'),
    ...sec(r'why test JSON this way'),
    ...para('//',
        r'The Flutter app is a separate codebase in a different language. '
        r'What it depends on is not the Rust types but the bytes they '
        r'serialise to. A natural but weak test would compare the '
        r'serialised string to a literal. That is brittle against field '
        r'order and spacing, and it tests nothing about what a consumer '
        r'would observe. The Stage 1 design note says what to do instead: '
        r'"Serialize snapshot + diff; parse back as serde_json::Value; '
        r'assert value[’type’] == ’snapshot’ ... — key assertions on '
        r'parsed Value, not substring match" (abridged).'),
    blank,
    ...para('//',
        r'That is exactly the shape of these tests: serialise, parse into '
        r'a generic Value, and then ask the questions a Dart client would '
        r'ask. Does the type field say snapshot? Is nodes an array? Is '
        r'there no add key? Is size a number and symbol a string?'),
    ...sec(r'the shared fixture'),
    ...code('rust', 'crates/heaplens-protocol/tests/diff_json.rs · sample_node', r'''
use heaplens_protocol::{GraphMessage, NodeDto, NodeState};
use serde_json::Value;

fn sample_node(id: u64) -> NodeDto {
    NodeDto {
        id,
        ptr: 0x2000_0000_0000 + id,
        size: 128,
        ts: 1_719_240_000_000,
        symbol: "alloc::vec::Vec::push".to_owned(),
        live: true,
        state: NodeState::Healthy,
        edges: vec![id + 100, id + 101],
    }
}'''),
    ...para('//',
        r'Every test starts from sample_node(id). The numbers are sample '
        r'values: a pointer base of 0x2000_0000_0000 plus the id, a '
        r'timestamp of 1_719_240_000_000 (the example from the Build '
        r'Spec’s JSON, which looks like a millisecond epoch time but is '
        r'only a stand-in; real ts values are producer-clock nanoseconds), '
        r'a symbol of alloc::vec::Vec::push (close to the spec’s example), '
        r'a live node in the healthy state with two edges at id + 100 and '
        r'id + 101. The edges are chosen so that a node’s edge list is '
        r'visibly derived from its id, which makes any cross-wiring '
        r'between nodes easy to spot in a failure.'),
    ...sec(r'snapshot shape'),
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
        r'The assertions come in two kinds. Positive ones check types: '
        r'nodes is an array; for the first node, id, ptr, size and ts are '
        r'numbers, symbol is a string, live is a boolean, state is the '
        r'string "healthy", edges is an array. Negative ones check '
        r'absence: a snapshot must not have add, update or remove. The '
        r'negative assertions are the less obvious and more important '
        r'kind. With serde’s internally tagged enums, an implementation '
        r'slip (say, flattening both Snapshot and Diff into one struct '
        r'with optional fields) would still serialise a valid-looking '
        r'message but with the wrong keys, and the absent-field checks are '
        r'what catch it.'),
    blank,
    ...para('//',
        r'The messages are checked for is_number() and not for a '
        r'particular integer representation. That keeps the test honest '
        r'about what the contract promises: a JSON number, not a '
        r'particular width. What a JSON number means to the reader is the '
        r'2^53 caveat in the diff.rs page.'),
    ...sec(r'diff shape'),
    ...code('rust', 'crates/heaplens-protocol/tests/diff_json.rs · diff_json_shape', r'''
#[test]
fn diff_json_shape() {
    let msg = GraphMessage::Diff {
        ts: 1_719_240_001_000,
        add:    vec![sample_node(10)],
        update: vec![sample_node(11)],
        remove: vec![100, 101],
    };
    let json = serde_json::to_string(&msg).expect("serialize");
    let v: Value = serde_json::from_str(&json).expect("parse");

    assert_eq!(v["type"], "diff", "type tag must be 'diff'");
    assert!(v["add"].is_array(),    "diff must have 'add'");
    assert!(v["update"].is_array(), "diff must have 'update'");
    assert!(v["remove"].is_array(), "diff must have 'remove'");
    assert!(v.get("nodes").is_none(), "diff must not have 'nodes'");
    assert_eq!(v["remove"][0], 100);
    assert_eq!(v["remove"][1], 101);
}'''),
    ...para('//',
        r'The diff test checks the three arrays (add, update, remove) '
        r'exist, that nodes does not, and the ids in remove come through '
        r'in order, 100 then 101. Remove is a list of bare ids, so the '
        r'check is by value (v["remove"][0] == 100). That the diff carries '
        r'whole nodes in add and update but only ids in remove is a design '
        r'decision recorded in the Build Spec; the test is where it is '
        r'enforced.'),
    ...sec(r'the enum’s wire strings'),
    ...code('rust', 'crates/heaplens-protocol/tests/diff_json.rs · nodestate_serializes_lowercase', r'''
#[test]
fn nodestate_serializes_lowercase() {
    let cases = [
        (NodeState::Healthy, "healthy"),
        (NodeState::Orphan,  "orphan"),
        (NodeState::Hot,     "hot"),
        (NodeState::Freed,   "freed"),
    ];
    for (state, expected) in &cases {
        let json = serde_json::to_string(state).expect("serialize");
        assert_eq!(json, format!("\"{}\"", expected));
    }
}'''),
    ...para('//',
        r'A table-driven test: four pairs of (NodeState, expected string), '
        r'each serialised and compared to the quoted lowercase name. This '
        r'pins the one serde attribute that makes the state a lowercase '
        r'word. If someone changed rename_all to something else, or added '
        r'a variant whose name did not follow the convention, this test '
        r'names the culprit. The Dart side, NodeStateDto.fromWire, '
        r'switches on those exact four strings.'),
    ...sec(r'the round trip'),
    ...code('rust', 'crates/heaplens-protocol/tests/diff_json.rs · round_trip_snapshot', r'''
#[test]
fn round_trip_snapshot() {
    let original = GraphMessage::Snapshot {
        ts: 42,
        nodes: vec![sample_node(99)],
    };
    let json = serde_json::to_string(&original).expect("serialize");
    let decoded: GraphMessage = serde_json::from_str(&json).expect("deserialize");
    assert_eq!(decoded, original);
}'''),
    ...para('//',
        r'The last test serialises a snapshot and deserialises it into the '
        r'same type, then compares with assert_eq!. It relies on the types '
        r'deriving PartialEq and Debug (commit fb8a4fc added Eq to both '
        r'right after the first version). The round trip also exercises '
        r'the deserialisation path, which the daemon never uses for '
        r'GraphMessage (it only serialises) but which a Rust client does: '
        r'the h1-harness parses incoming diffs with '
        r'serde_json::from_str into GraphMessage::Diff.'),
    ...sec(r'what is not covered, and what probing shows'),
    ...para('//',
        r'This file was written once, before the Stats variant or the '
        r'control module existed, and has not been touched since. Nothing '
        r'in the protocol crate asserts the Stats shape or any of the '
        r'control messages; commit 0edc728 added the Stats variant and '
        r'updated daemon and Flutter tests but left this file alone. '
        r'Serialising those variants in a scratch crate gives output that '
        r'matches the doc comments: a stats message has target_pid and '
        r'target_name as null until a handshake arrives, and the control '
        r'tags are snake_case. They are pinned from the other side: the '
        r'Flutter contract tests, and the daemon’s '
        r'target_diagnostics_stats.rs.'),
    blank,
    ...para('//',
        r'The leniency promised in the doc comment is not tested either. '
        r'By probing: a snapshot whose node has an unknown extra field '
        r'deserialises fine, as the comment says, an unknown node state is '
        r'rejected by serde, and an unknown message type is rejected with '
        r'a list of the valid names. Only the first is a property the '
        r'project chose; the others fall out of serde’s defaults and are '
        r'covered on the Dart side by explicit fallbacks.'),
    blank,
    ...para('//',
        r'Finally, no test uses a value above 2^53. A test with u64::MAX '
        r'for ptr would show the number surviving serde_json (a scratch '
        r'run printed 18446744073709551615) but would not say anything '
        r'about the reader, which is the part that matters.'),
    ...sec(r'related'),
    ...pt('//',
        r'diff.rs',
        r'the types under test, and the integer-width warning.'),
    ...pt('//',
        r'control.rs',
        r'the sibling JSON module with no test of its own in this crate.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-protocol/tests/diff_json.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-protocol/tests/diff_json.rs'),
  ],
);
