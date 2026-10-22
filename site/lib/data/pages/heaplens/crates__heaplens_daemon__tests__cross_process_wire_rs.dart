import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/tests/cross_process_wire.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'cross_process_wire.rs — a real producer, a real pipe, a real daemon pipeline'),
    cm('//', r'the test that asks whether the whole chain from allocator to ownership graph still holds together'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'end-to-end test: wire_producer.exe through the named pipe, ingest, φ, and the WebSocket snapshot'),
    kv('language', r'Rust, tokio multi-thread runtime, Windows only (#![cfg(windows)])'),
    kv('size', r'444 lines, 1 test, eight commits (2acccba 2026-07-02 to 71c6240 2026-07-26)'),
    kv('exercises', r'ingest::run, GraphMsg, OwnershipGraph, Resolver, server::run, the protocol framing, heaplens-alloc’s writer'),
    kv('needs', r'cargo build --example wire_producer -p heaplens-alloc, and the pipe name \\.\pipe\heaplens free'),
    ...sec(r'why it exists'),
    ...para('//',
        r'Every other daemon test builds its input in memory. This one does not. It starts the same pipe server the daemon runs (ingest::run), spawns a separate process, the wire_producer example from heaplens-alloc, which uses HeapLensAlloc as its global allocator, and lets that process stream its own allocations over the named pipe. Everything in between is real: the ring buffer, the writer thread, the symbol resolution done on the producer’s side, the SYMBOLS and EVENTS frames, the FrameDecoder, the φ inference over real stack addresses. The commit that created it (2acccba) is titled "cross-process wire test — pipe end-to-end, phi inference on real stacks".'),
    blank,
    ...para('//',
        r'That last phrase is the reason the file exists. graph_unit.rs proves φ works on stacks a human wrote. This test proves it works on stacks the Rust compiler and the Windows stack walker produced, where function names have to survive inlining, debug info and symbolisation.'),
    blank,
    ...sec(r'the workload'),
    ...para('//',
        r'The producer (crates/heaplens-alloc/examples/wire_producer.rs) holds a Vec with room for 100 pairs, calls nested_alloc 100 times (each allocates an outer buffer and, through leaf_alloc, an inner one), sleeps 100 ms, drops everything, then sleeps 500 ms so the writer can drain. The functions are marked #[inline(never)] so their frames appear on the captured stack. That is 200 allocations plus the Vec itself, which is why the test’s comments talk about 202 and assert a floor of 100.'),
    blank,
    ...sec(r'the summary the test keeps'),
    ...code('rust', r'crates/heaplens-daemon/tests/cross_process_wire.rs · lines 16-19, 21-23, 45-45, 53-54', r'''
const PIPE_NAME: &str = r"\\.\pipe\heaplens";
/// Minimum allocs expected: 100 nested_alloc calls × 2 Vec allocs each = 200.
/// We assert ≥ 100 to tolerate any ring drops under pressure.
const MIN_ALLOC_NODES: usize = 100;
...
#[derive(Default, Debug)]
struct Summary {
    alloc_count: usize,
...
    final_edges: std::collections::HashMap<u64, Vec<u64>>,
...
    non_machinery_names: std::collections::HashSet<String>,
}'''),
    ...para('//',
        r'Three things are recorded while the run is in progress. alloc_count counts alloc events as they arrive, because drain_diff hides nodes born and freed in the same window. final_edges keeps, per node id, the longest edge list ever seen in any add or update. non_machinery_names collects the distinct names the producer’s symbol frames classified as real code.'),
    blank,
    ...para('//',
        r'The doc comment on final_edges is a piece of debugging history. The field is named final_edges but it is not last-write-wins, and the comment says why. The producer frees everything before it exits, so a node’s final state is its torn-down state; and the daemon sends dealloc events in capped batches, so which diff shows what depends on batch boundaries. The comment records that on 2026-07-22 a correctness fix to the producer-side ring, capping drain_all’s per-call batch size (fa3fe78), moved those boundaries and flipped this test from pass to fail, "though φ inference recorded the correct owner for every single allocation, verified via direct trace". Taking the peak edge list measures the topology the test cares about regardless of how the teardown is chunked.'),
    blank,
    ...sec(r'standing the pipeline up'),
    ...code('rust', r'crates/heaplens-daemon/tests/cross_process_wire.rs · lines 56-65, 100-105', r'''
fn producer_path() -> std::path::PathBuf {
    // Test binary is at target/debug/deps/<name>-<hash>.exe
    // Wire producer is at target/debug/examples/wire_producer.exe
    let test_exe = std::env::current_exe().unwrap();
    let target_debug = test_exe
        .parent() // deps/
        .and_then(|p| p.parent()) // debug/ (or release/)
        .expect("cannot determine target dir from test exe path");
    target_debug.join("examples").join("wire_producer.exe")
}
...
    // Start the pipe server BEFORE spawning the child.
    // ingest::run loops forever; we abort it after the child exits.
    let ingest_handle = tokio::spawn(ingest::run(PIPE_NAME.to_owned(), ingest_tx));

    // Give the OS time to make the pipe available.
    tokio::time::sleep(Duration::from_millis(100)).await;'''),
    ...para('//',
        r'producer_path finds the example binary from the test’s own path: the test exe is at target/debug/deps/, the example at target/debug/examples/wire_producer.exe, and a missing file is a panic with the exact cargo command to build it. The test does not build it itself. The WebSocket server is started on a free port, then the pipe server, then, after 100 ms for the OS to publish the pipe, the child. The ordering matters: the pipe server must exist before the producer’s writer thread tries to connect.'),
    blank,
    ...para('//',
        r'The pipe name is the daemon’s real default, \\.\pipe\heaplens, hard-coded as a constant. ingest::run creates the first instance with first_pipe_instance(true), so if a real daemon (or another test) is holding that name, this test cannot run. There is no unique name per run. The hook_self_load_wire test and the GUI and TUI wire tests use the same PIPE_NAME constant too, so they could not run at the same time as this one.'),
    blank,
    ...sec(r'the graph loop'),
    ...code('rust', r'crates/heaplens-daemon/tests/cross_process_wire.rs · lines 144-155, 159-178, 180-187', r'''
                    Some(GraphMsg::Events(events)) => {
                        for ev in &events {
                            match ev.kind {
                                0 => {
                                    graph.on_alloc(ev, &resolver);
                                    alloc_count += 1;
                                }
                                1 => graph.on_dealloc(ev.ptr, ev.ts_nanos),
                                2 => graph.on_realloc(ev.old_ptr, ev.ptr, ev.size, &resolver),
                                _ => {}
                            }
                        }
...
                        let diff = graph.drain_diff(&resolver);
                        // Broadcast non-empty diffs so connected WS clients receive updates.
                        let is_non_empty = matches!(
                            &diff,
                            heaplens_protocol::GraphMessage::Diff { add, update, remove, .. }
                            if !add.is_empty() || !update.is_empty() || !remove.is_empty()
                        );
                        if is_non_empty {
                            let _ = broadcast_tx_clone.send(Arc::new(diff.clone()));
                        }
                        if let heaplens_protocol::GraphMessage::Diff { add, update, .. } = diff {
                            for n in add.iter().chain(update.iter()) {
                                // Keep the largest-ever-seen edge list, not the
                                // latest — see `Summary::final_edges`'s doc comment.
                                let entry = final_edges.entry(n.id).or_default();
                                if n.edges.len() > entry.len() {
                                    *entry = n.edges.clone();
                                }
                            }
                        }
...
                    // The real producer sends a HANDSHAKE frame on connect,
                    // now forwarded by ingest.rs as GraphMsg::TargetConnected
                    // instead of discarded — this must not be treated as
                    // end-of-stream by the catch-all below (it isn't a
                    // connection close). TargetDisconnected is the pipe-close
                    // counterpart and is equally not end-of-stream here.
                    Some(GraphMsg::TargetConnected { .. }) | Some(GraphMsg::TargetDisconnected { .. }) => continue,
                    _ => break,'''),
    ...para('//',
        r'This is a reduced main.rs graph task that runs inside the test. It consumes GraphMsg from the ingest channel with an 8-second deadline, and on every Events message it applies each event, drains a diff immediately, and updates the three summary fields from the add and update lists. Draining after each batch is deliberate, the comment says so: "so nodes allocated before deallocs appear in the diff accumulator’s add set and edge relationships are captured before the nodes are freed".'),
    blank,
    ...para('//',
        r'Several details are worth reading closely.'),
    blank,
    ...para('//',
        r'· Symbols are applied to the resolver before the events that need them, and non-machinery names are collected as they arrive. On the real wire the producer’s writer thread builds SYMBOLS frames (writer.rs); the test’s loop simply handles each message in the order it arrives.'),
    ...pt('//', r'The TargetConnected and TargetDisconnected arms use continue. The comment explains',
        r'a handshake is not end-of-stream, and the wildcard arm below them is break. When GraphMsg grew those two variants, the old wildcard silently turned a handshake into a loop exit. This match arm exists for that reason, and the hook tests carry a comment pointing back at this one.'),
    ...para('//',
        r'· The graph loop also answers ConnectRequests, so a WebSocket client can connect while it is running. It broadcasts non-empty diffs to them.'),
    ...sec(r'waiting for the child and the drain window'),
    ...code('rust', r'crates/heaplens-daemon/tests/cross_process_wire.rs · lines 236-265', r'''
    // Give the daemon a 2-second drain window after child exits.
    tokio::time::sleep(Duration::from_secs(2)).await;

    // WS snapshot assertion — performed while graph loop is still running so it
    // can handle the ConnectRequest and return a snapshot.
    // Note: by this point, wire_producer has freed all its allocations, so the
    // snapshot's node list will be empty (all live=false). We assert structure only.
    {
        let ws_url = format!("ws://{ws_addr}");
        let (mut ws_stream, _) = tokio_tungstenite::connect_async(&ws_url)
            .await
            .expect("failed to connect to WS server");

        let first_msg = tokio::time::timeout(Duration::from_secs(5), ws_stream.next())
            .await
            .expect("WS receive timed out")
            .expect("WS stream ended")
            .expect("WS message error");

        if let Message::Text(json) = first_msg {
            let parsed: serde_json::Value =
                serde_json::from_str(&json).expect("WS snapshot is not valid JSON");
            assert_eq!(
                parsed["type"], "snapshot",
                "WS first message must be a snapshot; got: {parsed}"
            );
        } else {
            panic!("expected Text WS message for snapshot, got: {first_msg:?}");
        }
    }'''),
    ...para('//',
        r'The child’s exit is awaited with a 10-second limit, via spawn_blocking and try_wait polling every 100 ms, and killed on timeout. A non-zero exit status fails the test. Then it sleeps two seconds: the producer sleeps for 500 ms to drain, but the daemon side needs its own margin to ingest the tail.'),
    blank,
    ...para('//',
        r'The WebSocket assertion comes next, deliberately before the graph loop is stopped. It connects, reads the first frame with a 5-second timeout, and checks type is "snapshot". The comment admits the weakness: by this time the producer has freed everything, so "the snapshot’s node list will be empty (all live=false). We assert structure only." It proves that the server and graph loop are wired together after real traffic, not that the snapshot carries real nodes.'),
    blank,
    ...sec(r'the assertions, and the calibration behind them'),
    ...code('rust', r'crates/heaplens-daemon/tests/cross_process_wire.rs · lines 312-317, 347-355', r'''
    assert!(
        s.non_machinery_names.len() > 1,
        "expected multiple distinct non-machinery call sites (nested_alloc, leaf_alloc, main, \
         ...), got {:?} — classification has collapsed",
        s.non_machinery_names
    );
...
    let root_owners: Vec<(&u64, &Vec<u64>)> = s.final_edges.iter()
        .filter(|(_, edges)| edges.len() > 1)
        .collect();
    assert!(
        !root_owners.is_empty(),
        "expected at least one node with fan-out > 1 (main's long-lived `items` root \
         container should own many `outer` buffers) — got none, final_edges: {:?}",
        s.final_edges
    );'''),
    ...para('//',
        r'The topology assertions are the part with the most history. They go in order from loosest to tightest.'),
    blank,
    ...para('//',
        r'1. alloc_count at least 100 (MIN_ALLOC_NODES, with a comment about tolerating ring drops). A failure message says "possible wire/framing failure". This is the check that no bytes were lost or misframed. 2. non_machinery_names has more than one entry. The comment calls it a "collapse canary": the project had hit two bugs where classification collapsed, either everything was machinery (zero edges) or one leftover frame swallowed everything (one giant chain), and each produced a plausible-looking wrong result. Requiring several distinct real names would have caught both. 3. At least one node has more than one child: the long-lived Vec in main, which encloses all 100 calls, should own many outer buffers.'),
    blank,
    ...para('//',
        r'The comments give the reasoning for the weakened parts, and they are candid. φ walks the entire ancestor stack, so the root container owns every outer buffer, and each outer owns its inner: a two-level chain, root to outer to inner. An earlier version asserted that no owner is itself owned. That held only while a debug-info gap (the long comment in the workspace Cargo.toml, debug = true under [profile.release]) collapsed all names to one and hid the ancestry.'),
    blank,
    ...para('//',
        r'Then there are two confirmed instances where the test flipped for reasons outside the topology. The first was the batch-size change. The second, root-caused on 2026-07-26, is the recency tie-break: with about 100 live outer buffers from one call site, an inner can be attributed to an older sibling instead of its immediate outer, so one sibling is "robbed" (0 children) and another gets 2. The comment records the evidence: alloc_count and the name set were rock steady across 18 or more consecutive runs while the root’s child count ranged from 24 to 47, so it is redistribution and not lost data.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/cross_process_wire.rs · lines 367-386', r'''
    let &(root_id, root_children) = root_owners.iter()
        .max_by_key(|(_, edges)| edges.len())
        .expect("root_owners is non-empty, checked above");

    // Calibrated against real observed behavior (2026-07-26: 18 consecutive
    // runs, root's own child count ranged 24-47, never below 24), not the
    // originally-assumed ~100 (nor the old, never-reliably-met 50). Set
    // with real margin below the observed floor — low enough to never be a
    // false failure from ordinary redistribution jitter, high enough that
    // it still only passes when φ has built substantial, genuine
    // multi-level structure (dozens of correctly-inferred parent-child
    // pairs), not a handful of isolated fragments or a collapsed/empty
    // result.
    const MIN_STAR_OWNERS: usize = 15;
    assert!(
        root_children.len() >= MIN_STAR_OWNERS,
        "expected the root container to own ≥ {MIN_STAR_OWNERS} `outer` buffers, got {} \
         (root id {root_id})",
        root_children.len()
    );'''),
    ...para('//',
        r'The root is chosen as the node with the largest edge list, since a thief sibling reaches only 2 while the real root has dozens. MIN_STAR_OWNERS is 15: the comment says it was set "with real margin below the observed floor" of 24, rather than the 100 originally assumed or the 50 that was "never-reliably-met".'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/cross_process_wire.rs · lines 393-410, 429-443', r'''
    let mut total_inner_attributions = 0usize;
    for &outer_id in root_children {
        let edges = s.final_edges.get(&outer_id).map(Vec::as_slice).unwrap_or(&[]);
        assert!(
            edges.len() <= 2,
            "outer node {outer_id} (owned by root {root_id}) has {} edges, expected 0, 1, or \
             2 (0 = robbed by a tie-break-ambiguous sibling, 1 = normal, 2 = the sibling that \
             stole one — never more, which would be a real anomaly) — {edges:?}",
            edges.len()
        );
        total_inner_attributions += edges.len();
    }
    assert!(
        total_inner_attributions >= MIN_STAR_OWNERS,
        "expected ≥ {MIN_STAR_OWNERS} total inner attributions across all root-owned outers, \
         got {total_inner_attributions} — inner-level attribution collapsed even though \
         outer-level attribution to root did not"
    );
...
    // No node has more than one owner: every id is claimed as a child by at
    // most one owner (the root's children set, and each outer's own
    // children, however many it legitimately has per above).
    let mut all_children: Vec<u64> = root_children.clone();
    for &outer_id in root_children {
        if let Some(edges) = s.final_edges.get(&outer_id) {
            all_children.extend(edges.iter().copied());
        }
    }
    let unique_children: std::collections::HashSet<u64> = all_children.iter().copied().collect();
    assert_eq!(
        all_children.len(), unique_children.len(),
        "a node was claimed as a child by more than one owner — expected each node to have \
         at most one owner"
    );'''),
    ...para('//',
        r'The last checks tighten the structure within that tolerance. Every outer under the root has at most 2 edges (0 for the robbed, 1 normally, 2 for the thief, never more, which would be a real anomaly). The total of inner attributions is at least 15. Every inner is a leaf, which rules out chaining beyond root to outer to inner. And no id is claimed as a child twice, which is the structural invariant of a tree.'),
    blank,
    ...sec(r'what the test proves, and what it concedes'),
    ...para('//',
        r'It proves that bytes written by a real HeapLensAlloc in another process arrive intact (the count), that symbolisation works on release-profile-with-debug binaries (the canary), and that φ builds a multi-level star with no double ownership (the structural checks). It concedes exact topology: the numbers 15, 2 and 1 are tolerances around a known ambiguity (graph_unit.rs documents the same behaviour in phi_recency_discriminator_misattributes_late_child_to_newer_same_name_owner) and not an exact expectation. That is the honest form of the assertion, and the comment explains each loosening instead of hiding it.'),
    blank,
    ...sec(r'failure modes'),
    ...pt('//', r'The producer has not been built',
        r'a panic with the build command.'),
    ...pt('//', r'The pipe is already taken by another daemon',
        r'ingest::run logs "pipe create failed" and retries every 100 ms, so the symptom is a low or zero alloc count, not a clear message.'),
    ...pt('//', r'A slow machine',
        r'the 2-second drain and 8-second deadline are fixed.'),
    ...pt('//', r'Windows only',
        r'the whole file is behind #![cfg(windows)].'),
    ...sec(r'history'),
    ...pt('//', r'2acccba (2026-07-02)',
        r'created: pipe end to end, φ inference on real stacks.'),
    ...pt('//', r'8e5c26f (2026-07-02)',
        r'the WebSocket snapshot assertion added.'),
    ...pt('//', r'43fc22e (2026-07-08)',
        r'function-name-granularity φ.'),
    ...pt('//', r'b97b008 (2026-07-16) and 0edc728 (2026-07-17)',
        r'follow-on signature and message changes.'),
    ...pt('//', r'724695a (2026-07-19)',
        r'the new server::run signature and the TargetConnected and TargetDisconnected arms.'),
    ...pt('//', r'fa3fe78 (2026-07-22)',
        r'the ring batch cap, which exposed the last-write-wins weakness.'),
    ...pt('//', r'71c6240 (2026-07-26)',
        r'"harden cross_process_wire’s topology assertion to match phi’s actual guarantee": the tolerant version of the assertions above.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/tests/cross_process_wire.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/tests/cross_process_wire.rs'),
  ],
);
