import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/tests/orphan_persistence.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'orphan_persistence.rs — one orphan, traced from free event to SQLite row'),
    cm('//', r'the timestamps in the database must be the timestamps the target reported, not ones the daemon made up'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'end-to-end test of the H1 observability plumbing: owner-free, sweep, OrphanEventRecord, store'),
    kv('language', r'Rust, tokio::test, rusqlite'),
    kv('size', r'139 lines, 1 test, one commit: b97b008 (2026-07-16)'),
    kv('exercises', r'OwnershipGraph::{on_alloc, on_dealloc, node_by_ptr, nodes, nodes_mut, max_ts_seen}, anomaly::sweep, OrphanEventRecord, store::open'),
    kv('related', r'h1-harness (the latency measurement this table feeds), chaos_orphan (the workload it imitates)'),
    ...sec(r'why it exists'),
    ...para('//',
        r'HeapLens claims to detect an orphan, a child allocation whose owner has been freed, within a bounded time. H1 is the name the project gives to measuring that claim. To measure detection latency you need two timestamps for each orphan: when the owner was actually freed and when the daemon decided the child was orphaned. The first one has to come from the target’s own dealloc event, because anything the daemon invented (a wall-clock reading when it handled the message) would include queueing and scheduling delay and make the measurement measure itself.'),
    blank,
    ...para('//',
        r'Commit b97b008, "persist real owner-free/detection timestamps for orphan transitions", added three things: Node.owner_free_ts set in OwnershipGraph::on_dealloc, an OrphanEventRecord built in the Tick handler of main.rs, and the orphan_events table in the store. This test is the one proof that the three fit together. Nothing in it is mocked: it uses the real graph, the real sweep and the real store thread. Its doc comment says so: "drives a real owner-free -> orphan sequence ... confirms what lands in SQLite is exactly the injected event timestamps — not a derived, approximated, or wall-clock value."'),
    blank,
    ...sec(r'setting the stage'),
    ...code('rust', r'crates/heaplens-daemon/tests/orphan_persistence.rs · lines 38-55', r'''
    let owner_site = 0xAAAA;
    let leaf_site = 0xBBBB;
    let mut r = Resolver::new();
    r.insert(owner_site, "owner_site".to_owned(), false);
    r.insert(leaf_site, "leaf_site".to_owned(), false);

    let config = Config {
        tau_ms: 5, // 5ms -> 5_000_000 ns
        hot_cluster_threshold: 32,
        storm_rate_threshold: 1000,
        storm_window_ms: 1000,
        pipe_name: r"\\.\pipe\heaplens".to_owned(),
        tick_ms: 33,
        ws_addr: "127.0.0.1:9999".to_owned(),
        db_path: "heaplens.db".to_owned(),
    };

    let mut g = OwnershipGraph::new();'''),
    ...para('//',
        r'Two call sites are registered in a Resolver as ordinary non-machinery symbols. The Config is built literally with the fields sweep reads: tau of 5 ms, so 5,000,000 ns, and values for the others that cannot trigger Hot or storm behaviour (a hot threshold of 32). The comment on the tau line shows the arithmetic.'),
    blank,
    ...sec(r'the free, the orphan, the sweep'),
    ...code('rust', r'crates/heaplens-daemon/tests/orphan_persistence.rs · lines 57-81', r'''
    // Owner allocated at ts=0, child allocated at ts=1, owned by it via phi.
    g.on_alloc(&make_ev(EventKind::Alloc, 0x1000, 0, 64, 0, &[owner_site]), &r);
    g.on_alloc(&make_ev(EventKind::Alloc, 0x2000, 0, 32, 1, &[leaf_site, owner_site]), &r);
    let child_id = g.node_by_ptr(0x2000).expect("child registered").id;

    // Owner freed 300ms later — the real dealloc event's ts_nanos, exactly
    // what H1 must measure from.
    const OWNER_FREE_TS_NS: u64 = 300_000_000;
    g.on_dealloc(0x1000, OWNER_FREE_TS_NS);

    assert_eq!(
        g.node_by_ptr(0x2000).expect("child still live").owner_free_ts,
        Some(OWNER_FREE_TS_NS),
        "on_dealloc must record the real event ts on the orphaned child"
    );

    // A later alloc (standing in for chaos_orphan.rs's post-free heartbeat
    // loop) advances max_ts_seen past owner_free_ts + tau — this is what
    // actually gates detection, since on_dealloc deliberately does not
    // touch max_ts_seen (unchanged behavior).
    const ORPHAN_DETECTED_TS_NS: u64 = 333_000_000; // ~one 33ms tick later
    g.on_alloc(&make_ev(EventKind::Alloc, 0x3000, 0, 8, ORPHAN_DETECTED_TS_NS, &[0xCCCC]), &r);

    let max_ts = g.max_ts_seen;
    assert_eq!(max_ts, ORPHAN_DETECTED_TS_NS);'''),
    ...para('//',
        r'The owner is allocated at ts 0 and the child at ts 1, with the owner’s site in the child’s stack, so φ makes the owner the parent. The owner is freed at 300,000,000 ns, "300ms later", standing in, per the doc comment, for "chaos_orphan’s settle-sleep before freeing". The first assertion checks that on_dealloc recorded exactly that value on the orphaned child as owner_free_ts.'),
    blank,
    ...para('//',
        r'Then a third, unrelated allocation arrives at ts 333,000,000. The comment explains why this step exists: it "advances max_ts_seen past owner_free_ts + tau — this is what actually gates detection, since on_dealloc deliberately does not touch max_ts_seen". In this daemon time is whatever the events say, so a dealloc alone does not move the clock and detection needs a later event to arrive. The test asserts max_ts_seen is exactly 333,000,000. In production the "later event" is the target’s other allocations; in chaos_orphan.rs the post-free heartbeat loop plays that part, as the comment notes.'),
    blank,
    ...para('//',
        r'Then:'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/orphan_persistence.rs · lines 83-86', r'''
    // Exactly the sweep() call main.rs's Tick handler makes.
    let changed = sweep(g.nodes_mut(), max_ts, &config);
    assert_eq!(changed, vec![child_id], "child should be the only node whose state changed");
    assert_eq!(g.nodes().get(&child_id).unwrap().state, NodeState::Orphan);'''),
    ...para('//',
        r'sweep is called with the real config and returns exactly the child’s id, and the child’s state is Orphan. The test also confirms no other node changed state.'),
    blank,
    ...sec(r'the glue, copied'),
    ...code('rust', r'crates/heaplens-daemon/tests/orphan_persistence.rs · lines 88-104', r'''
    // Exactly the glue main.rs's Tick handler runs after sweep().
    let mut orphan_events = Vec::new();
    for &id in &changed {
        if let Some(node) = g.nodes().get(&id) {
            if node.state == NodeState::Orphan {
                if let Some(owner_free_ts_ns) = node.owner_free_ts {
                    orphan_events.push(OrphanEventRecord {
                        node_id: id,
                        owner_free_ts_ns,
                        orphan_detected_ts_ns: max_ts,
                        tau_ms: config.tau_ms,
                    });
                }
            }
        }
    }
    assert_eq!(orphan_events.len(), 1);'''),
    ...para('//',
        r'The comment says "Exactly the glue main.rs’s Tick handler runs after sweep()". The test cannot call main.rs, which is a binary, so it replicates a small loop: for each changed id, if the node is Orphan and has an owner_free_ts, push an OrphanEventRecord with node id, owner-free timestamp, max_ts as the detection timestamp, and tau. The cost of this is duplication. If main.rs changes its glue, this test keeps passing against the old copy. The benefit is that the rest of the chain is real. The condition on owner_free_ts is worth reading: an orphan produced some other way (no recorded free) would produce no event.'),
    blank,
    ...sec(r'through the real store thread'),
    ...code('rust', r'crates/heaplens-daemon/tests/orphan_persistence.rs · lines 106-125, 133-137', r'''
    // Persist through the real store thread, exactly as production does.
    let path = temp_db_path("orphan_persistence");
    cleanup(&path);
    let (store_tx, _handle) = store::open(&path).unwrap();
    store_tx.send(StoreMsg::OrphanEvents(orphan_events)).unwrap();
    store_tx.send(StoreMsg::Flush).unwrap();
    tokio::time::sleep(Duration::from_millis(300)).await;

    let conn = rusqlite::Connection::open(&path).unwrap();
    let (persisted_node_id, persisted_owner_free_ts_ns, persisted_orphan_detected_ts_ns, persisted_tau_ms): (
        i64,
        i64,
        i64,
        i64,
    ) = conn
        .query_row(
            "SELECT node_id, owner_free_ts_ns, orphan_detected_ts_ns, tau_ms FROM orphan_events",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
...
    // The H1 formula itself, computed from what actually landed in SQLite.
    let latency_ns = persisted_orphan_detected_ts_ns - persisted_owner_free_ts_ns - (persisted_tau_ms * 1_000_000);
    const EXPECTED_LATENCY_NS: i64 = 28_000_000; // 333ms - 300ms - 5ms
    assert_eq!(latency_ns, EXPECTED_LATENCY_NS);
'''),
    ...para('//',
        r'The records go to store::open’s channel as StoreMsg::OrphanEvents, then a Flush and a 300 ms wait, and the test opens the database itself and reads the single row back as four integers. The assertions compare each persisted value with the original constant: node id, 300,000,000, 333,000,000, and tau 5. Each comparison is after a cast from i64, since SQLite stores integers as signed 64-bit and the code casts from u64 on insert. The test would stay valid for values below 2^63, which every realistic nanosecond count is.'),
    blank,
    ...sec(r'the H1 formula'),
    ...para('//',
        r'The last lines compute latency as detected minus owner_free minus tau in nanoseconds and assert 28,000,000: "333ms - 300ms - 5ms". That is the number H1 would report for this event, a 28 ms overshoot beyond the tau grace period. Writing it into the test fixes the formula in one place: the analysis that reads the orphan_events table has to subtract tau to get the extra latency, and this is the arithmetic it should use.'),
    blank,
    ...sec(r'a mismatch worth knowing about'),
    ...para('//',
        r'The H1 formula subtracts tau from the gap between the free and the detection, as if tau were counted from the owner’s free. The sweep does not count it that way. anomaly.rs compares max_ts_seen minus node.ts, the child’s own allocation timestamp, against tau, and graph.rs’s comment on owner_free_ts says it is "never read by infer_ownership or anomaly::sweep’s state predicates". In this test the child has ts 1, so the sweep flips it as soon as max_ts_seen passes 5,000,001; the 333 ms alloc is far past that. The test comment’s phrase "owner_free_ts + tau" describes a gate that the code does not implement. I note it as an observation about the code; the test only checks that the stored timestamps are the injected ones and that the arithmetic gives 28,000,000.'),
    blank,
    ...sec(r'edge cases not tested'),
    ...para('//',
        r'· Two orphans in one sweep, or an orphan whose owner_free_ts is None (the glue would skip it).'),
    ...pt('//', r'The persistence of the Hot state or of nodes',
        r'store_tests.rs does that.'),
    ...pt('//', r'A second sweep',
        r'because the state is already Orphan the node would not be in the changed list, and no second event is written. That is correct and untested.'),
    ...sec(r'history'),
    ...para('//',
        r'One commit, b97b008 (2026-07-16): "persist real owner-free/detection timestamps for orphan transitions". It is the only commit that touches the file.'),
    blank,
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/tests/orphan_persistence.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/tests/orphan_persistence.rs'),
  ],
);
