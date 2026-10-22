import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/tests/ingest_loopback.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'ingest_loopback.rs — encoded bytes in, graph diffs out, without a pipe'),
    cm('//', r'the framing layer and the graph joined in memory'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'integration tests that join encode_events, FrameDecoder and OwnershipGraph'),
    kv('language', r'Rust, tokio::test'),
    kv('size', r'123 lines, 2 tests, six commits (6a95ceb 2026-07-01 to fa3fe78 2026-07-22)'),
    kv('exercises', r'heaplens_protocol::{encode_events, FrameDecoder, Frame}, GraphMsg, OwnershipGraph::{on_alloc, on_dealloc, drain_diff}'),
    kv('does not exercise', r'ingest.rs itself (the named-pipe reader)'),
    ...sec(r'what "loopback" means here'),
    ...para('//',
        r'ingest.rs reads bytes from a named pipe, feeds them to a FrameDecoder and sends GraphMsg values to the graph task. The test file borrows its name from that module but does not use it, since opening a named pipe needs a client process. What it does is replay the same path in memory. Encode events with encode_events, push the bytes into a FrameDecoder, wrap what comes out in GraphMsg::Events, send it over a tokio channel, and have a consumer loop apply it to a graph. The only component skipped is the pipe itself. (cross_process_wire.rs covers that, with a real child process.)'),
    blank,
    ...sec(r'helper: through the codec'),
    ...code('rust', r'crates/heaplens-daemon/tests/ingest_loopback.rs · lines 7-23', r'''
fn make_alloc_event(ptr: u64, size: u64, ts: u64, stack: &[u64]) -> AllocEvent {
    let mut s = [0u64; 16];
    let len = stack.len().min(16);
    s[..len].copy_from_slice(&stack[..len]);
    AllocEvent::new(EventKind::Alloc, ptr, 0, size, 8, ts, s, len as u8)
}

/// Encode events through FrameDecoder round-trip → GraphMsg::Events
fn events_to_msg(events: &[AllocEvent]) -> GraphMsg {
    let bytes = encode_events(events).expect("well under u16::MAX");
    let mut decoder = FrameDecoder::new();
    decoder.push(&bytes);
    match decoder.next().expect("decoder must yield a frame") {
        heaplens_protocol::Frame::Events(evs) => GraphMsg::Events(evs),
        _ => panic!("expected Events frame"),
    }
}'''),
    ...para('//',
        r'events_to_msg encodes a slice of events to a byte buffer with encode_events (it returns an Option, None when the batch holds more than u16::MAX events because the count is a 16-bit field; the .expect says "well under u16::MAX"), pushes the bytes to a new decoder and expects one Events frame. This is what gives the file its value over graph_unit.rs: the events reach the graph after being serialised and parsed, so the wire format, including the AllocEvent byte layout, is part of the test.'),
    blank,
    ...sec(r'test 1: allocs and a tick make one diff'),
    ...code('rust', r'crates/heaplens-daemon/tests/ingest_loopback.rs · lines 25-74', r'''
#[tokio::test]
async fn loopback_alloc_and_tick_produces_diff() {
    let (tx, mut rx) = mpsc::unbounded_channel::<GraphMsg>();

    let ev1 = make_alloc_event(0x1000, 64, 100, &[0xAAAA]);
    let ev2 = make_alloc_event(0x2000, 32, 200, &[0xBBBB, 0xAAAA]);
    tx.send(events_to_msg(&[ev1, ev2])).unwrap();
    tx.send(GraphMsg::Tick).unwrap();
    drop(tx);

    let mut graph = OwnershipGraph::new();
    let mut resolver = Resolver::new();
    resolver.insert(0xAAAA, "owner_site".to_owned(), false);
    resolver.insert(0xBBBB, "leaf_site".to_owned(), false);

    while let Some(msg) = rx.recv().await {
        match msg {
            GraphMsg::Events(events) => {
                for ev in &events {
                    match ev.kind {
                        0 => graph.on_alloc(ev, &resolver),
                        1 => graph.on_dealloc(ev.ptr, ev.ts_nanos),
                        2 => graph.on_realloc(ev.old_ptr, ev.ptr, ev.size, &resolver),
                        _ => {}
                    }
                }
            }
            GraphMsg::Tick => {
                let diff = graph.drain_diff(&resolver);
                match diff {
                    GraphMessage::Diff { add, update, remove, .. } => {
                        assert_eq!(add.len(), 2, "both allocs should be in add");
                        assert!(update.is_empty(), "no updates expected");
                        assert!(remove.is_empty(), "no removes expected");

                        let owner = add.iter().find(|n| n.ptr == 0x1000).unwrap();
                        let child = add.iter().find(|n| n.ptr == 0x2000).unwrap();

                        // φ inference: owner's edges_out contains child's id
                        assert!(owner.edges.contains(&child.id),
                            "owner should have child in edges");
                    }
                    other => panic!("expected Diff, got {other:?}"),
                }
            }
            GraphMsg::Symbols(_) => {}
            GraphMsg::TargetConnected { .. } | GraphMsg::TargetDisconnected { .. } => {}
        }
    }
}'''),
    ...para('//',
        r'Two events go in as one frame: an owner at 0x1000 with stack [0xAAAA] and a child at 0x2000 with stack [0xBBBB, 0xAAAA]. A tick follows, the sender is dropped so the consumer loop ends when the channel drains, and the consumer is the same dispatch main.rs uses: kind 0 to on_alloc, 1 to on_dealloc, 2 to on_realloc.'),
    blank,
    ...para('//',
        r'On Tick it drains a diff and checks three things. Both allocations are in add. update and remove are empty. The owner’s edges contain the child’s id, which is φ working on frames that went through the codec. The resolver is given names for the two addresses first: "owner_site" and "leaf_site".'),
    blank,
    ...sec(r'test 2: a free becomes a remove one tick later'),
    ...code('rust', r'crates/heaplens-daemon/tests/ingest_loopback.rs · lines 76-123', r'''
#[tokio::test]
async fn loopback_dealloc_produces_remove() {
    let (tx, mut rx) = mpsc::unbounded_channel::<GraphMsg>();

    let ev = make_alloc_event(0x1000, 64, 100, &[0xAAAA]);
    tx.send(events_to_msg(&[ev])).unwrap();
    tx.send(GraphMsg::Tick).unwrap();

    // Now dealloc (EventKind::Dealloc)
    let dealloc_ev = AllocEvent::new(EventKind::Dealloc, 0x1000, 0, 0, 0, 200, [0u64; 16], 0);
    tx.send(events_to_msg(&[dealloc_ev])).unwrap();
    tx.send(GraphMsg::Tick).unwrap();
    drop(tx);

    let mut graph = OwnershipGraph::new();
    let resolver = Resolver::new();
    let mut tick_count = 0u32;

    while let Some(msg) = rx.recv().await {
        match msg {
            GraphMsg::Events(events) => {
                for ev in &events {
                    match ev.kind {
                        0 => graph.on_alloc(ev, &resolver),
                        1 => graph.on_dealloc(ev.ptr, ev.ts_nanos),
                        2 => graph.on_realloc(ev.old_ptr, ev.ptr, ev.size, &resolver),
                        _ => {}
                    }
                }
            }
            GraphMsg::Tick => {
                tick_count += 1;
                let diff = graph.drain_diff(&resolver);
                if let GraphMessage::Diff { add, remove, .. } = diff {
                    if tick_count == 1 {
                        assert_eq!(add.len(), 1, "first tick: alloc in add");
                    } else if tick_count == 2 {
                        assert_eq!(remove.len(), 1, "second tick: dealloc in remove");
                    }
                }
            }
            GraphMsg::Symbols(_) => {}
            GraphMsg::TargetConnected { .. } | GraphMsg::TargetDisconnected { .. } => {}
        }
    }

    assert_eq!(tick_count, 2, "should have processed two ticks");
}'''),
    ...para('//',
        r'An alloc, a tick, a dealloc and a tick, with a counter distinguishing the two ticks. The first tick must add one node, the second must remove one. The resolver is empty, so the node has no symbol, which the test does not look at. The final assertion that the tick count is two guards a quieter failure: if the loop ended early the per-tick assertions would never run and the test would pass vacuously. Without that assertion, a consumer that returned before the second tick would still be green.'),
    blank,
    ...sec(r'a weakness'),
    ...para('//',
        r'The assertions inside the loop are in if-let and match arms that only run when the tick count matches. For example, the second test uses if let Diff and then branches on tick_count, so if the first tick returned something other than a diff, nothing would be asserted for it. The tick counter closes part of this gap, not all of it.'),
    blank,
    ...sec(r'the numeric kind dispatch'),
    ...para('//',
        r'Both tests match on ev.kind as a bare 0, 1 or 2, copied from main.rs. The protocol crate has an EventKind enum, which the tests use to construct events, while the receiving side compares raw numbers. If EventKind ever renumbers, the consumers in main.rs and these tests change together, but nothing connects them to the enum automatically.'),
    blank,
    ...sec(r'how it fits'),
    ...para('//',
        r'This is the narrowest end-to-end slice of the daemon: codec plus graph. ws_tests.rs adds the socket. cross_process_wire.rs adds the pipe and a separate producer process. hook_self_load_wire.rs replaces the producer with an injected DLL.'),
    blank,
    ...sec(r'history'),
    ...pt('//', r'6a95ceb (2026-07-01)',
        r'the first version: FrameDecoder round-trip, alloc plus tick, dealloc gives a remove.'),
    ...pt('//', r'43fc22e (2026-07-08)',
        r'the φ function-name change: on_alloc and on_realloc take the resolver, the test registers names for the two addresses, stacks grow from 8 to 16 frames.'),
    ...pt('//', r'b97b008 (2026-07-16)',
        r'on_dealloc takes the timestamp.'),
    ...pt('//', r'0edc728 (2026-07-17)',
        r'the target-diagnostics change: the panic message prints whatever variant arrived, and a Handshake arm was added.'),
    ...pt('//', r'724695a (2026-07-19)',
        r'the two target arms of GraphMsg.'),
    ...pt('//', r'fa3fe78 (2026-07-22)',
        r'encode_events returns an Option (None on overflow of the 16-bit event count), so events_to_msg calls expect.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/tests/ingest_loopback.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/tests/ingest_loopback.rs'),
  ],
);
