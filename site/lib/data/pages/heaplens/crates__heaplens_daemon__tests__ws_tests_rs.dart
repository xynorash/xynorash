import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/tests/ws_tests.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'ws_tests.rs — the WebSocket contract, from the client’s side of the socket'),
    cm('//', r'a real server::run on a free port, a miniature graph loop behind it, four tests'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'integration tests for server.rs: first message, diffs after it, consistency, two clients'),
    kv('language', r'Rust, tokio::test, tokio-tungstenite client'),
    kv('size', r'238 lines, 4 tests, five commits (8c1406b 2026-07-02 to 724695a 2026-07-19)'),
    kv('exercises', r'server::run, OwnershipGraph, ConnectRequest, GraphMsg, GraphMessage JSON shape'),
    kv('does not exercise', r'the control path (ListProcesses, AttachTarget, DetachTarget) or pushes'),
    ...sec(r'why it exists'),
    ...para('//',
        r'The Flutter client and the TUI both parse what this server sends, and neither is compiled with the daemon. The contract between them is JSON text on a WebSocket. A Rust unit test of GraphMessage serialisation would not catch a server that sends the wrong frame first or forgets the diff arm. These tests put an actual client on an actual socket and read the first messages as serde_json::Value, looking at the field names the Dart side depends on: type, add, remove, nodes, id.'),
    blank,
    ...sec(r'a miniature daemon in 60 lines'),
    ...code('rust', r'crates/heaplens-daemon/tests/ws_tests.rs · lines 32-74', r'''
/// Mini graph loop: handles GraphMsg + ConnectRequest without a store.
/// Tests drive this by sending events + ticks through graph_tx.
async fn run_graph_loop(
    mut graph_rx: mpsc::UnboundedReceiver<GraphMsg>,
    mut connect_rx: mpsc::UnboundedReceiver<ConnectRequest>,
    broadcast_tx: broadcast::Sender<Arc<GraphMessage>>,
) {
    let mut graph = OwnershipGraph::new();
    let resolver = Resolver::new();
    loop {
        tokio::select! {
            msg = graph_rx.recv() => match msg {
                Some(GraphMsg::Events(events)) => {
                    for ev in &events {
                        match ev.kind {
                            0 => graph.on_alloc(ev, &resolver),
                            1 => graph.on_dealloc(ev.ptr, ev.ts_nanos),
                            2 => graph.on_realloc(ev.old_ptr, ev.ptr, ev.size, &resolver),
                            _ => {}
                        }
                    }
                }
                Some(GraphMsg::Symbols(_)) => {}
                Some(GraphMsg::TargetConnected { .. }) | Some(GraphMsg::TargetDisconnected { .. }) => {}
                Some(GraphMsg::Tick) => {
                    let diff = graph.drain_diff(&resolver);
                    if is_non_empty_diff(&diff) {
                        let _ = broadcast_tx.send(Arc::new(diff));
                    }
                }
                None => break,
            },
            req = connect_rx.recv() => {
                if let Some(ConnectRequest { reply }) = req {
                    // Subscribe before snapshot so no diffs are lost.
                    let diff_rx = broadcast_tx.subscribe();
                    let snapshot = graph.snapshot(&resolver);
                    let _ = reply.send((snapshot, diff_rx));
                }
            }
        }
    }
}'''),
    ...para('//',
        r'run_graph_loop is a stand-in for the graph task in main.rs. The doc comment says "handles GraphMsg + ConnectRequest without a store". It does the following.'),
    blank,
    ...pt('//', r'GraphMsg::Events is dispatched by the numeric kind field',
        r'0 to on_alloc, 1 to on_dealloc, 2 to on_realloc. The other message kinds (symbols, target connected and disconnected) are ignored, which is the arm that had to be extended when 724695a added the two target variants.'),
    ...para('//',
        r'· GraphMsg::Tick drains a diff and broadcasts it only if is_non_empty_diff. The real daemon is allowed to skip empty ticks too, and the test wants exactly one message per change, not a stream of empties.'),
    ...para('//',
        r'· A ConnectRequest gets a diff subscription and then a snapshot, in that order. The comment reads "Subscribe before snapshot so no diffs are lost", the same rule main.rs follows (Q6 in its comments). Because the loop is a single task, nothing can interleave between the two calls.'),
    ...para('//',
        r'What it leaves out is everything else the real graph task does: no anomaly sweep, no store, no Stats message, no storm tracking, no control commands. That keeps the tests about the server and the wire format, and means a bug in main.rs’s loop would not show up here.'),
    blank,
    ...sec(r'standing the server up'),
    ...code('rust', r'crates/heaplens-daemon/tests/ws_tests.rs · lines 76-111', r'''
/// Spin up a WS server + mini graph loop in-process.
/// Returns the WS URL, a sender for injecting events/ticks, and the graph-loop handle.
async fn start_test_server() -> (
    String,
    mpsc::UnboundedSender<GraphMsg>,
    tokio::task::JoinHandle<()>,
) {
    // Bind on port 0 to get an OS-assigned free port, then release it.
    let probe = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = probe.local_addr().unwrap().port();
    drop(probe);

    let addr = format!("127.0.0.1:{port}");

    let (graph_tx, graph_rx) = mpsc::unbounded_channel::<GraphMsg>();
    let (connect_tx, connect_rx) = mpsc::unbounded_channel::<ConnectRequest>();
    let (broadcast_tx, _) = broadcast::channel::<Arc<GraphMessage>>(64);
    // These tests don't exercise the control channel — a target_tx with no
    // receiver just means ListProcesses/Attach/Detach requests (none are
    // sent here) would silently no-op rather than panic.
    let (target_tx, _target_rx) = mpsc::unbounded_channel();
    let (control_push_tx, _) = broadcast::channel::<Arc<ControlResponse>>(16);

    tokio::spawn(server::run(addr.clone(), connect_tx, target_tx, control_push_tx));

    let handle = tokio::spawn(run_graph_loop(graph_rx, connect_rx, broadcast_tx));

    // Give the server a moment to bind.
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;

    (format!("ws://{addr}"), graph_tx, handle)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------'''),
    ...para('//',
        r'start_test_server binds port 0 to find a free port, drops that listener and hands the port to server::run. That is a race in principle, since another process could take the port between drop and rebind, but it is the usual trick and the tests run on loopback. The 50 ms sleep after spawning is how the test waits for the server to bind; there is no readiness signal.'),
    blank,
    ...para('//',
        r'The comment about the control channel states a limit: "a target_tx with no receiver just means ListProcesses/Attach/Detach requests (none are sent here) would silently no-op rather than panic". The channel is created and its receiver kept alive in a variable that nothing reads. Reading handle_control_request in server.rs, a request would be accepted by the channel and then the server would wait on a reply oneshot that nothing answers (until the sender is dropped), so "no-op" understates it. No test exercises this. The test needs only that the sends compile and the signature matches the new four-argument server::run, which is the other half of what 724695a changed in this file.'),
    blank,
    ...sec(r'test 1: the first message is a snapshot'),
    ...code('rust', r'crates/heaplens-daemon/tests/ws_tests.rs · lines 113-126', r'''
/// A freshly-connected client must receive a JSON message with `"type": "snapshot"`.
#[tokio::test]
async fn ws_snapshot_has_type_snapshot() {
    let (url, _graph_tx, _handle) = start_test_server().await;
    let (mut ws, _) = tokio_tungstenite::connect_async(&url).await.unwrap();

    let msg = ws.next().await.unwrap().unwrap();
    if let Message::Text(json) = msg {
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed["type"], "snapshot", "first message must be a snapshot");
    } else {
        panic!("expected a Text WebSocket message, got: {msg:?}");
    }
}'''),
    ...para('//',
        r'The smallest possible contract: connect, read one frame, and check that it is a text frame whose type is "snapshot". With an empty graph. This is the guarantee the Flutter provider relies on to initialise its state before applying diffs.'),
    blank,
    ...sec(r'test 2: an alloc and a tick give one diff with one add'),
    ...code('rust', r'crates/heaplens-daemon/tests/ws_tests.rs · lines 128-154', r'''
/// After receiving the initial snapshot, injecting an alloc + tick must produce
/// a diff message with `"type": "diff"` and exactly one entry in `"add"`.
#[tokio::test]
async fn ws_diff_after_alloc() {
    let (url, graph_tx, _handle) = start_test_server().await;
    let (mut ws, _) = tokio_tungstenite::connect_async(&url).await.unwrap();

    // Consume the initial snapshot.
    let _ = ws.next().await.unwrap().unwrap();

    // Inject one alloc, then tick.
    graph_tx.send(GraphMsg::Events(vec![make_alloc_ev(0x1000, 100, 0xAAAA)])).unwrap();
    graph_tx.send(GraphMsg::Tick).unwrap();

    // Allow time for the graph loop + WS forward to complete.
    tokio::time::sleep(std::time::Duration::from_millis(100)).await;

    let msg = ws.next().await.unwrap().unwrap();
    if let Message::Text(json) = msg {
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed["type"], "diff", "second message must be a diff");
        let add = parsed["add"].as_array().expect("diff must have an 'add' array");
        assert_eq!(add.len(), 1, "exactly one node should be in 'add'");
    } else {
        panic!("expected a Text WebSocket message, got: {msg:?}");
    }
}'''),
    ...para('//',
        r'After consuming the snapshot, the test injects one alloc event and a tick through the graph channel, sleeps 100 ms to let the loop run and the socket forward, then reads the next frame. It checks type is "diff" and that add has exactly one entry. The sleep looks redundant: ws.next().await blocks until a frame arrives.'),
    blank,
    ...sec(r'test 3: the snapshot and the diff agree'),
    ...code('rust', r'crates/heaplens-daemon/tests/ws_tests.rs · lines 156-217', r'''
/// Nodes that were alive before a client connected must appear in the snapshot.
/// Deallocating one and ticking must produce a diff whose `"remove"` list contains
/// an id that was present in the original snapshot.
#[tokio::test]
async fn ws_snapshot_then_diff_consistent() {
    let (url, graph_tx, _handle) = start_test_server().await;

    // Pre-allocate 3 nodes before any client connects.
    for i in 0u64..3 {
        graph_tx.send(GraphMsg::Events(vec![
            make_alloc_ev(0x1000 + i * 0x100, 100 + i, 0xAAAA + i),
        ])).unwrap();
    }
    graph_tx.send(GraphMsg::Tick).unwrap();
    tokio::time::sleep(std::time::Duration::from_millis(100)).await;

    // Connect — snapshot must carry all 3 nodes.
    let (mut ws, _) = tokio_tungstenite::connect_async(&url).await.unwrap();
    let snap_msg = ws.next().await.unwrap().unwrap();

    let snapshot_ids: Vec<u64> = if let Message::Text(json) = snap_msg {
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed["type"], "snapshot");
        parsed["nodes"]
            .as_array()
            .expect("snapshot must have a 'nodes' array")
            .iter()
            .map(|n| n["id"].as_u64().expect("node id must be a u64"))
            .collect()
    } else {
        panic!("expected snapshot Text message");
    };

    assert_eq!(snapshot_ids.len(), 3, "snapshot must contain all 3 pre-allocated nodes");

    // Dealloc the first node (ptr 0x1000) and tick.
    let dealloc = AllocEvent::new(EventKind::Dealloc, 0x1000, 0, 0, 0, 200, [0u64; 16], 0);
    graph_tx.send(GraphMsg::Events(vec![dealloc])).unwrap();
    graph_tx.send(GraphMsg::Tick).unwrap();
    tokio::time::sleep(std::time::Duration::from_millis(100)).await;

    let diff_msg = ws.next().await.unwrap().unwrap();
    if let Message::Text(json) = diff_msg {
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed["type"], "diff");

        let removed: Vec<u64> = parsed["remove"]
            .as_array()
            .expect("diff must have a 'remove' array")
            .iter()
            .map(|v| v.as_u64().expect("remove entry must be a u64"))
            .collect();

        assert!(!removed.is_empty(), "diff must remove at least one node");
        assert!(
            removed.iter().all(|rid| snapshot_ids.contains(rid)),
            "every removed id must have been in the snapshot"
        );
    } else {
        panic!("expected diff Text message");
    }
}'''),
    ...para('//',
        r'This is the strongest test in the file. Three allocations happen before any client exists, and a tick makes them part of graph state. A client then connects and its snapshot must hold all three nodes (the test collects their ids). The test then frees the first pointer and ticks, and requires the resulting diff to remove at least one id and every removed id to be in the snapshot. That is the consistency property a UI needs: a diff may only refer to ids the client has been told about. If the snapshot was missing nodes, or ids were renumbered between snapshot and diff, this would fail.'),
    blank,
    ...sec(r'test 4: two clients'),
    ...code('rust', r'crates/heaplens-daemon/tests/ws_tests.rs · lines 219-238', r'''
/// Two clients that connect independently must each receive a snapshot message.
#[tokio::test]
async fn ws_two_clients_both_get_snapshot() {
    let (url, _graph_tx, _handle) = start_test_server().await;

    let (mut ws1, _) = tokio_tungstenite::connect_async(&url).await.unwrap();
    let (mut ws2, _) = tokio_tungstenite::connect_async(&url).await.unwrap();

    let msg1 = ws1.next().await.unwrap().unwrap();
    let msg2 = ws2.next().await.unwrap().unwrap();

    for (i, msg) in [msg1, msg2].into_iter().enumerate() {
        if let Message::Text(json) = msg {
            let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
            assert_eq!(parsed["type"], "snapshot", "client {i} must receive a snapshot");
        } else {
            panic!("client {i}: expected a Text WebSocket message");
        }
    }
}'''),
    ...para('//',
        r'Two clients connect independently and each must receive a snapshot first. It shows the per-client task design in server.rs: each connection makes its own ConnectRequest. It does not check that a diff reaches both clients, though the subject of the commit that added the file (8c1406b) says "snapshot/diff JSON contract, two-client broadcast".'),
    blank,
    ...sec(r'what is not covered'),
    ...pt('//', r'Control requests and pushes',
        r'nothing in this file sends a ControlRequest, so handle_control_request and the push arm of the select loop are untested here.'),
    ...pt('//', r'Lag',
        r'the Lagged branches, which keep a slow client connected after dropping diffs, have no test.'),
    ...para('//',
        r'· A client that disconnects mid-stream, a malformed text frame, or a bind failure.'),
    ...pt('//', r'The Stats message',
        r'GraphMessage has a Stats variant, which is_non_empty_diff treats as not a diff, and no test sends one. target_diagnostics_stats.rs covers it.'),
    ...sec(r'history'),
    ...pt('//', r'8c1406b (2026-07-02)',
        r'the file is born: snapshot and diff JSON contract, two-client test.'),
    ...pt('//', r'43fc22e (2026-07-08)',
        r'on_alloc and on_realloc gained the resolver argument, the stack arrays grew from 8 to 16 frames, and a Symbols arm appeared in the graph loop.'),
    ...pt('//', r'b97b008 (2026-07-16)',
        r'on_dealloc gained its timestamp argument.'),
    ...pt('//', r'0edc728 (2026-07-17)',
        r'the Stats variant joined the non-diff arm of is_non_empty_diff, and a Handshake arm was added to the loop.'),
    ...pt('//', r'724695a (2026-07-19)',
        r'the four-argument server::run with its target and push channels, and the loop gained TargetConnected and TargetDisconnected arms (the current file has no Handshake arm).'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/tests/ws_tests.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/tests/ws_tests.rs'),
  ],
);
