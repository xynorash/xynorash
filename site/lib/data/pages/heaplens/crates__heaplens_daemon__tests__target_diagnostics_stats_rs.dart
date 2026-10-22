import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/tests/target_diagnostics_stats.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'target_diagnostics_stats.rs — three counters and the promise not to touch φ'),
    cm('//', r'a Stats message over a real socket: events seen, symbols resolved, who the target is'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'regression tests for the target-diagnostics counters carried by GraphMessage::Stats'),
    kv('language', r'Rust, tokio::test, tokio-tungstenite client'),
    kv('size', r'249 lines, 3 tests, two commits (0edc728 2026-07-17, cd348b6 2026-07-21)'),
    kv('exercises', r'OwnershipGraph::symbol_stats, GraphMessage::Stats, GraphMsg::{Symbols, TargetConnected}, server::run'),
    kv('consumer', r'the Flutter target-diagnostics banner (see target_diagnosis.dart)'),
    ...sec(r'the problem these counters solve'),
    ...para('//',
        r'A user attaches HeapLens to a program and sees an empty graph. The commit that introduced the counters (0edc728, "honest target-status banner + daemon observability counters") says it distinguishes four states, capturing, no-events, no-edges and unsymbolized, "instead of leaving the user staring at a blank graph". One case the tests care about: a node born and freed within one tick never appears in a diff. Another: allocations whose addresses the resolver cannot name leave φ with nothing to match on. The commit adds three numbers and an identity so the UI can tell these apart: events_received, symbols_resolved, hex_fallback, and the pid and name from the target’s handshake.'),
    blank,
    ...para('//',
        r'The header comment of the test file states the discipline that goes with them: these counters "must never influence phi ownership inference or anomaly detection", mirroring "the read-only, decision already made discipline" of the H1 orphan-timestamp work. They are observation, not input. Two of the three tests prove that the counters count correctly; the third proves they did not disturb φ.'),
    blank,
    ...sec(r'a graph loop that mirrors main.rs'),
    ...code('rust', r'crates/heaplens-daemon/tests/target_diagnostics_stats.rs · lines 51-86', r'''
/// Mirrors main.rs's Tick-arm handling closely enough to exercise the new
/// counters end-to-end over a real WS connection: events counted before
/// diff-visibility filtering, `symbol_stats` computed fresh each tick, and a
/// Stats broadcast sent every tick (unlike main.rs's real 1s cadence — sent
/// every tick here so tests don't need to sleep a full second).
async fn run_graph_loop(
    mut graph_rx: mpsc::UnboundedReceiver<GraphMsg>,
    mut connect_rx: mpsc::UnboundedReceiver<ConnectRequest>,
    broadcast_tx: broadcast::Sender<Arc<GraphMessage>>,
) {
    let mut graph = OwnershipGraph::new();
    let mut resolver = Resolver::new();
    let mut events_received: u64 = 0;
    let mut target_pid: Option<u64> = None;
    let mut target_name: Option<String> = None;

    loop {
        tokio::select! {
            msg = graph_rx.recv() => match msg {
                Some(GraphMsg::Events(events)) => {
                    events_received += events.len() as u64;
                    for ev in &events {
                        match ev.kind {
                            0 => graph.on_alloc(ev, &resolver),
                            1 => graph.on_dealloc(ev.ptr, ev.ts_nanos),
                            2 => graph.on_realloc(ev.old_ptr, ev.ptr, ev.size, &resolver),
                            _ => {}
                        }
                    }
                }
                Some(GraphMsg::Symbols(syms)) => {
                    for (addr, name, is_machinery) in syms {
                        resolver.insert(addr, name, is_machinery);
                    }
                }
                Some(GraphMsg::TargetConnected { pid, name }) => {'''),
    ...para('//',
        r'This is another copy of the mini graph loop (ws_tests.rs and the wire tests have their own), with extra Stats handling. It adds what main.rs’s Tick arm does: count events as they arrive (events.len() added to events_received before any filtering), apply symbols to the resolver, remember the target’s pid and name from TargetConnected, and on every tick compute symbol_stats and broadcast a Stats message. Its doc comment lists the one deliberate difference: main.rs sends Stats "on a fixed 1s cadence (decoupled from tick_ms)" through STATS_INTERVAL, while the test sends them every tick "so tests don’t need to sleep a full second".'),
    blank,
    ...sec(r'what symbol_stats counts'),
    ...para('//',
        r'symbol_stats walks the live nodes and, for each, finds its effective site (the first frame the resolver does not classify as machinery). If there is one and its resolved name does not start with "0x", the node counts as resolved. If the site is missing, or the name is the hex fallback, it counts as hex_fallback. Dead nodes are not counted. The cost is a pass over every live node whenever it is called. In the daemon that is once per second; in the test it is every tick.'),
    blank,
    ...sec(r'test 1: events the diff cannot see'),
    ...code('rust', r'crates/heaplens-daemon/tests/target_diagnostics_stats.rs · lines 152-173', r'''
/// `graph.rs`'s `drain_diff` doc comment: "Nodes born and freed within the
/// same tick are invisible to the consumer." `events_received` must count
/// both raw events anyway — it is read directly off the incoming event
/// stream, before any diff-visibility filtering — otherwise a target that
/// churns allocations fast enough to always fall within one tick would
/// falsely look like "zero events" to the target-diagnostics banner.
#[tokio::test]
async fn events_received_counts_events_invisible_to_the_diff() {
    let (url, graph_tx, _handle) = start_test_server().await;
    let (mut ws, _) = tokio_tungstenite::connect_async(&url).await.unwrap();
    let _ = ws.next().await.unwrap().unwrap(); // initial snapshot

    graph_tx.send(GraphMsg::Events(vec![make_alloc_ev(0x9000, 100, &[0xAAAA])])).unwrap();
    graph_tx.send(GraphMsg::Events(vec![make_dealloc_ev(0x9000, 150)])).unwrap();
    graph_tx.send(GraphMsg::Tick).unwrap();

    // The diff is empty (born+freed same tick), so is_non_empty_diff
    // suppresses it — the very next message must be the Stats broadcast.
    let json = as_json(ws.next().await.unwrap().unwrap());
    assert_eq!(json["type"], "stats", "diff should be suppressed as empty; stats must still arrive");
    assert_eq!(json["events_received"], 2, "both the alloc and the dealloc must be counted");
}'''),
    ...para('//',
        r'An alloc and a dealloc of the same pointer arrive before one tick. drain_diff suppresses a node born and freed in the same tick, so the diff is empty and is not broadcast. The test therefore expects the very next frame on the socket to be the Stats message, with events_received equal to 2. The doc comment explains the failure it prevents: a target that "churns allocations fast enough to always fall within one tick would falsely look like zero events to the target-diagnostics banner". The counter has to be taken from the raw stream, not from what the diff shows.'),
    blank,
    ...sec(r'test 2: resolved, unresolved, and who is connected'),
    ...code('rust', r'crates/heaplens-daemon/tests/target_diagnostics_stats.rs · lines 178-212', r'''
#[tokio::test]
async fn stats_reports_symbol_resolution_and_handshake_identity() {
    let (url, graph_tx, _handle) = start_test_server().await;
    let (mut ws, _) = tokio_tungstenite::connect_async(&url).await.unwrap();
    let _ = ws.next().await.unwrap().unwrap(); // initial snapshot

    graph_tx
        .send(GraphMsg::Symbols(vec![(0xAAAA, "myapp::alloc_site".to_owned(), false)]))
        .unwrap();
    graph_tx
        .send(GraphMsg::Events(vec![
            make_alloc_ev(0x1000, 100, &[0xAAAA]), // resolves
            make_alloc_ev(0x2000, 200, &[0xBBBB]), // never resolved -> hex fallback
        ]))
        .unwrap();
    graph_tx
        .send(GraphMsg::TargetConnected { pid: 4242, name: "target.exe".to_owned() })
        .unwrap();
    graph_tx.send(GraphMsg::Tick).unwrap();

    // Two allocs => non-empty diff is sent too; find the stats message
    // among the (at most two) messages this tick produces.
    let mut found = false;
    for _ in 0..2 {
        let json = as_json(ws.next().await.unwrap().unwrap());
        if json["type"] == "stats" {
            assert_eq!(json["symbols_resolved"], 1);
            assert_eq!(json["hex_fallback"], 1);
            assert_eq!(json["target_pid"], 4242);
            assert_eq!(json["target_name"], "target.exe");
            found = true;
        }
    }
    assert!(found, "expected a stats message among this tick's broadcasts");
}'''),
    ...para('//',
        r'The test sends a symbol for 0xAAAA, two allocations (one on a stack with 0xAAAA, one on a stack with 0xBBBB the resolver never heard of), and a TargetConnected for pid 4242 and name "target.exe". After a tick it reads up to two messages, because two allocs make a non-empty diff in addition to the Stats message, and finds the Stats among them. The expected values are one resolved, one hex fallback, pid 4242, name "target.exe".'),
    blank,
    ...para('//',
        r'How the unknown address becomes a fallback is worth a sentence. The resolver treats an address it does not know as machinery, so effective_site_index skips it and finds no site at all, and symbol_stats counts a node with no site as hex fallback. In the UI that is the signature of an unsymbolized target: lots of allocations, none of which φ can place. The loop reads at most two messages and does not care which comes first, so the test would pass if Stats came before the diff.'),
    blank,
    ...sec(r'test 3: φ is not disturbed'),
    ...code('rust', r'crates/heaplens-daemon/tests/target_diagnostics_stats.rs · lines 219-249', r'''
#[tokio::test]
async fn diff_content_unaffected_by_new_stats_broadcast() {
    let (url, graph_tx, _handle) = start_test_server().await;
    let (mut ws, _) = tokio_tungstenite::connect_async(&url).await.unwrap();
    let _ = ws.next().await.unwrap().unwrap(); // initial snapshot

    graph_tx
        .send(GraphMsg::Symbols(vec![
            (0xAAAA, "owner_site".to_owned(), false),
            (0xBBBB, "child_site".to_owned(), false),
        ]))
        .unwrap();
    graph_tx.send(GraphMsg::Events(vec![make_alloc_ev(0x1000, 100, &[0xAAAA])])).unwrap();
    graph_tx
        .send(GraphMsg::Events(vec![make_alloc_ev(0x2000, 200, &[0xBBBB, 0xAAAA])]))
        .unwrap();
    graph_tx.send(GraphMsg::Tick).unwrap();

    let json = as_json(ws.next().await.unwrap().unwrap());
    assert_eq!(json["type"], "diff", "diff must still be produced first, alongside the new stats broadcast");
    let add = json["add"].as_array().expect("diff must have an 'add' array");
    assert_eq!(add.len(), 2);
    let owner = add.iter().find(|n| n["ptr"] == 0x1000).expect("owner node");
    let child = add.iter().find(|n| n["ptr"] == 0x2000).expect("child node");
    let owner_edges = owner["edges"].as_array().unwrap();
    assert!(
        owner_edges.contains(&child["id"]),
        "phi ownership inference must be unaffected by the new observability counters — \
         owner_edges={owner_edges:?}, child_id={:?}", child["id"]
    );
}'''),
    ...para('//',
        r'An owner and a child with real symbol names, as in graph_unit.rs, but through the socket and alongside the new Stats broadcast. The first message must be the diff (not the Stats, because the loop sends the diff first), add holds both nodes, and the owner’s edges contain the child’s id. The point is the comment on the test: the new code "runs in the same Tick arm as drain_diff", and this test pins down that the edge output "is unaffected". It would catch a refactor that, say, called symbol_stats before drain_diff in a way that changed the resolver.'),
    blank,
    ...sec(r'how it fits'),
    ...para('//',
        r'main.rs keeps three session variables for this, events_received, target_pid and target_name, set when events and TargetConnected messages arrive. The server serialises Stats with the same JSON machinery as every other GraphMessage, so the Dart side parses it into a TargetDiagnosis and shows the banner. is_non_empty_diff in every test loop returns false for Stats, which keeps heartbeats out of the "is there a diff" question.'),
    blank,
    ...sec(r'limits'),
    ...para('//',
        r'· The mirror is not the code. The test loop re-implements main.rs’s Tick arm, so a change in main.rs (the one-second gate, the order of fields) is not tested here. Only symbol_stats and the server’s serialisation are real.'),
    ...pt('//', r'The disconnect side',
        r'TargetDisconnected is ignored by this loop, and no test checks what happens to target_pid after a disconnect.'),
    ...para('//',
        r'· The target_tx/control_push_tx pair is created and ignored, as in ws_tests.rs; the comment refers the reader there for the rationale.'),
    ...sec(r'history'),
    ...pt('//', r'0edc728 (2026-07-17)',
        r'the file is born with the counters, using a GraphMsg::Handshake variant.'),
    ...pt('//', r'cd348b6 (2026-07-21)',
        r'"reconcile two files the master merge broke without conflict markers": Handshake becomes TargetConnected, the TargetDisconnected arm is added, and server::run gets its new four-argument signature.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/tests/target_diagnostics_stats.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/tests/target_diagnostics_stats.rs'),
  ],
);
