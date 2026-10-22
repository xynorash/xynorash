import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/tests/cross_process_wire_gui.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'cross_process_wire_gui.rs — the same φ shapes, from inside a GUI event loop'),
    cm('//', r'a thirty-eight second run against a scripted iced window that never exits on its own'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'end-to-end test that the iced GUI demo target produces the same ownership shapes as the console demo'),
    kv('language', r'Rust, tokio multi-thread runtime, Windows only (#![cfg(windows)])'),
    kv('size', r'165 lines, 1 test, one commit: 9693399 (2026-07-28)'),
    kv('exercises', r'ingest::run, OwnershipGraph, Resolver, checkout_service_gui.exe (heaplens-alloc example)'),
    kv('sibling', r'cross_process_wire.rs (the template), cross_process_wire_tui.rs (the near-copy)'),
    ...sec(r'why a second wire test'),
    ...para('//',
        r'cross_process_wire.rs drives wire_producer, a program whose allocations happen in a plain loop in main. The project’s demo target, the checkout service, is different in two ways that could change what φ sees. It has two separate allocation scenarios (a leak and a hot cluster). And the GUI version runs them from inside iced’s Elm-style update loop, which puts a framework’s call frames between main and the allocation sites. The doc comment states the question: does the GUI target "produce the same phi ownership shapes as checkout_service.rs (the console version) despite running its allocation sites from inside iced’s own Elm-style update loop instead of a plain loop { } in main"?'),
    blank,
    ...para('//',
        r'The test is therefore about stack shape rather than throughput. If iced’s frames were classified wrongly, or the function-name matching broke on a deeper stack, the demo target would draw the wrong graph, and the unit tests, which use hand-written stacks, would not say so.'),
    blank,
    ...sec(r'how it differs from the template'),
    ...code('rust', r'crates/heaplens-daemon/tests/cross_process_wire_gui.rs · lines 2-12', r'''
//! Validates that `checkout_service_gui` (the iced GUI demo target) produces
//! the same phi ownership shapes as `checkout_service.rs` (the console
//! version) despite running its allocation sites from inside iced's own
//! Elm-style update loop instead of a plain `loop { }` in `main`. Modeled on
//! `cross_process_wire.rs`'s ingest/graph harness, adapted for a target that
//! never exits on its own (a GUI) and has two independent owner stars
//! (leak's `pool_manager`, hot cluster's `queue_owner`) rather than one.
//!
//! Drives the scripted window via `HEAPLENS_GUI_AUTOSTART=1` — a
//! validation-only hook in the GUI binary that starts the deterministic
//! T+15s/30s/33s schedule without a real mouse click.'''),
    ...para('//',
        r'The doc comment names three adaptations. The target never exits on its own, so the test samples for a fixed window and then kills it. There are two independent owner stars (the leak’s pool_manager and the hot cluster’s queue_owner) instead of one root. And the scripted scenario is started by an environment variable: HEAPLENS_GUI_AUTOSTART=1 is described as "a validation-only hook in the GUI binary that starts the deterministic T+15s/30s/33s schedule without a real mouse click". In checkout_service_gui.rs the hook is checked on the second tick of the app.'),
    blank,
    ...para('//',
        r'The harness is also smaller than its template. It has no WebSocket server, no ConnectRequest handling and no diff broadcast, since only the pipe and graph are under test.'),
    blank,
    ...sec(r'the run'),
    ...code('rust', r'crates/heaplens-daemon/tests/cross_process_wire_gui.rs · lines 55-70', r'''
    let ingest_tx = tx.clone();

    let ingest_handle = tokio::spawn(ingest::run(PIPE_NAME.to_owned(), ingest_tx));
    tokio::time::sleep(Duration::from_millis(100)).await;

    let mut child = std::process::Command::new(&target)
        .env("HEAPLENS_GUI_AUTOSTART", "1")
        .spawn()
        .unwrap_or_else(|e| panic!("failed to spawn checkout_service_gui: {e}"));

    let graph_handle = tokio::spawn(async move {
        let mut graph = OwnershipGraph::new();
        let mut resolver = Resolver::new();
        // Cover leak (T+15/17s) and hot-cluster grow (T+30/33s) with margin
        // before hot-drain (T+40s) clears the backlog.
        let deadline = tokio::time::Instant::now() + Duration::from_secs(38);'''),
    ...para('//',
        r'The pipe server starts first, then the child with the autostart variable. The graph loop gets a 38-second deadline. Its comment gives the schedule it is covering: the leak at T+15 s and T+17 s, the hot-cluster growth at T+30 s and T+33 s, "with margin before hot-drain (T+40s) clears the backlog". The deadline lands between the second growth step and that drain.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/cross_process_wire_gui.rs · lines 92-115', r'''
                    Some(GraphMsg::Events(events)) => {
                        for ev in &events {
                            match ev.kind {
                                0 => { graph.on_alloc(ev, &resolver); alloc_count += 1; }
                                1 => graph.on_dealloc(ev.ptr, ev.ts_nanos),
                                2 => graph.on_realloc(ev.old_ptr, ev.ptr, ev.size, &resolver),
                                _ => {}
                            }
                        }
                        let diff = graph.drain_diff(&resolver);
                        if let heaplens_protocol::GraphMessage::Diff { add, update, .. } = diff {
                            for n in add.iter().chain(update.iter()) {
                                let entry = final_edges.entry(n.id).or_default();
                                if n.edges.len() > entry.len() {
                                    *entry = n.edges.clone();
                                }
                            }
                        }
                    }
                    Some(GraphMsg::TargetConnected { .. }) | Some(GraphMsg::TargetDisconnected { .. }) => continue,
                    _ => break,
                },
                _ = tokio::time::sleep(remaining) => break,
            }'''),
    ...para('//',
        r'The loop is the same peak-tracking arrangement as cross_process_wire.rs: apply events, drain a diff, and for every node in add or update keep the longest edge list seen. The comment at the top of Summary refers back to that file for why it is the maximum and not the latest value. The handshake and disconnect arms use continue, so they do not end the loop.'),
    blank,
    ...sec(r'the assertions'),
    ...code('rust', r'crates/heaplens-daemon/tests/cross_process_wire_gui.rs · lines 124-133', r'''
    match tokio::time::timeout(Duration::from_secs(45), graph_handle).await {
        Ok(Ok(())) => {}
        Ok(Err(e)) => panic!("graph task panicked: {e}"),
        Err(_) => panic!("graph task did not finish within timeout"),
    }

    // GUI never exits on its own — kill it now that sampling is done.
    let _ = child.kill();
    let _ = child.wait();
    ingest_handle.abort();'''),
    ...para('//',
        r'The test waits for the graph task with a 45-second ceiling, then kills the child and waits for it, and aborts the ingest task. Killing is the normal end of this test, not a failure path.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/cross_process_wire_gui.rs · lines 138-165', r'''
    assert!(s.alloc_count > 0, "no alloc events observed at all — wire/framing failure");
    assert!(
        s.non_machinery_names.len() > 1,
        "expected multiple distinct non-machinery call sites, got {:?}",
        s.non_machinery_names
    );

    // Two independent owner stars are expected: leak's pool_manager (fan-out
    // ~12, allocated in leak_phase_tick) and hot cluster's queue_owner
    // (fan-out ~40 at peak before drain, allocated in hot_phase_tick) — not
    // one combined root like wire_producer's single long-lived container,
    // because these two owners come from two distinct named functions.
    let mut fan_outs: Vec<usize> = s.final_edges.values().map(|e| e.len()).filter(|&n| n > 1).collect();
    fan_outs.sort_unstable();
    eprintln!("Observed fan-outs > 1: {fan_outs:?}");

    let has_leak_star = fan_outs.iter().any(|&n| (8..=14).contains(&n));
    let has_hot_star = fan_outs.iter().any(|&n| n >= 25);

    assert!(
        has_leak_star,
        "expected an owner with fan-out ~12 (leak's pool_manager -> connections), got fan-outs {fan_outs:?}"
    );
    assert!(
        has_hot_star,
        "expected an owner with fan-out >= 25 (hot cluster's queue_owner -> orders, peak 40), got fan-outs {fan_outs:?}"
    );
}'''),
    ...para('//',
        r'· some alloc events arrived, so the wire works at all.'),
    ...para('//',
        r'· more than one distinct non-machinery name, the same collapse canary as the console test.'),
    ...pt('//', r'a fan-out between 8 and 14 inclusive',
        r'the leak’s pool manager owning its 12 connections. The shared helper in the examples (support/checkout_common.rs) allocates the manager and then calls payment_gateway_pool_checkout_connections(12).'),
    ...pt('//', r'a fan-out of at least 25',
        r'the hot cluster’s queue owner, which gets an initial batch of 10 orders and 30 more later, a peak of 40.'),
    ...para('//',
        r'The window for the leak star is a tolerance, not a promise of exactly 12: the same recency tie-break that cross_process_wire.rs documents can move a child between same-named siblings. A window of 8 to 14 absorbs that. The hot threshold of 25, against a peak of 40, is similarly lenient.'),
    blank,
    ...para('//',
        r'What the test does not assert: that the two stars are distinct nodes (the two owners come from two named functions, leak_phase_tick and hot_phase_tick, so they should be), that the leaked connections end up in the Orphan state (anomaly detection decides that, and sweep is not run here), or any timing beyond the sampling window.'),
    blank,
    ...sec(r'edge cases and failure modes'),
    ...para('//',
        r'· A fixed 38-second sampling window plus startup, much longer than the fixed waits in the other daemon tests.'),
    ...pt('//', r'Needs the example built',
        r'cargo build --example checkout_service_gui -p heaplens-alloc. The panic message says so.'),
    ...para('//',
        r'· The target is an iced window application; the test has no skip logic if a window cannot be created.'),
    ...para('//',
        r'· Shares the pipe name \\.\pipe\heaplens with the daemon and the other wire tests.'),
    ...pt('//', r'Timing',
        r'the schedule runs on the child’s wall clock; if the machine is slow, a scenario can slip past the 38-second window. The TUI sibling’s comment makes exactly this concern, but only widens the outer timeout (see its page).'),
    ...sec(r'history'),
    ...para('//',
        r'One commit, 9693399 (2026-07-28): "demo: TUI backdrop (ratatui/crossterm, replaces iced GUI) + attach button re-enabled for soutenance". That commit added the GUI and TUI targets and both wire tests together, so this file has never been edited.'),
    blank,
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/tests/cross_process_wire_gui.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/tests/cross_process_wire_gui.rs'),
  ],
);
