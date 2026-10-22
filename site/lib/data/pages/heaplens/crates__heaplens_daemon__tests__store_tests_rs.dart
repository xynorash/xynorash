import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/tests/store_tests.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'store_tests.rs — three ways rows must reach SQLite'),
    cm('//', r'a flush, a timer and a shutdown, checked by opening the database file from the outside'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'integration tests for store.rs'),
    kv('language', r'Rust, tokio::test, rusqlite'),
    kv('size', r'93 lines, 3 tests, two commits (88dedac 2026-07-02, 0d465e5 2026-07-02)'),
    kv('exercises', r'store::open, StoreMsg::{Nodes, Flush, Shutdown}'),
    kv('not covered', r'the state column’s text, orphan events (see orphan_persistence.rs)'),
    ...sec(r'what the store is'),
    ...para('//',
        r'store.rs gives the daemon a persistent trail of nodes. store::open creates the SQLite file and two tables (nodes and orphan_events), then starts a bridge task and a plain OS thread. Messages sent on the returned channel are collected by the thread, which commits them in one transaction every 100 ms, sooner on Flush, and finally on Shutdown. The point of batching is that the graph task must never wait on disk: it sends a message and carries on.'),
    blank,
    ...para('//',
        r'The three tests are one per way a batch reaches disk. Each opens the database file again with its own rusqlite Connection and counts rows, so they test what a later reader would see, not what the store thinks it did.'),
    blank,
    ...sec(r'fixtures'),
    ...code('rust', r'crates/heaplens-daemon/tests/store_tests.rs · lines 7-30', r'''
fn make_dto(id: u64) -> NodeDto {
    NodeDto {
        id,
        ptr: id * 1000,
        size: 64,
        ts: 100,
        symbol: "test".to_owned(),
        live: true,
        state: NodeState::Healthy,
        edges: vec![],
    }
}

fn temp_db_path(name: &str) -> String {
    format!(
        "{}\\heaplens_test_{}.db",
        std::env::temp_dir().display(),
        name
    )
}

fn cleanup(path: &str) {
    let _ = std::fs::remove_file(path);
}'''),
    ...para('//',
        r'make_dto builds a node with id n and ptr n times 1000, a fixed size, timestamp and symbol, live, Healthy, no edges. temp_db_path puts a database named after the test in the system temp directory, using a literal backslash separator, which makes the file Windows-only like the rest of the crate. cleanup removes it, ignoring errors, and each test calls it both before (a stale file from a crashed earlier run would otherwise add rows) and after. A failing assertion panics before the final cleanup, leaving the file; the cleanup-before handles the next run.'),
    blank,
    ...sec(r'test 1: Flush commits immediately'),
    ...code('rust', r'crates/heaplens-daemon/tests/store_tests.rs · lines 32-50', r'''
#[tokio::test]
async fn store_inserts_nodes() {
    let path = temp_db_path("insert");
    cleanup(&path);

    let (tx, _handle) = store::open(&path).unwrap();
    tx.send(StoreMsg::Nodes(vec![make_dto(1), make_dto(2), make_dto(3)]))
        .unwrap();
    tx.send(StoreMsg::Flush).unwrap();
    tokio::time::sleep(Duration::from_millis(300)).await;

    let conn = rusqlite::Connection::open(&path).unwrap();
    let count: i64 = conn
        .query_row("SELECT count(*) FROM nodes", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count, 3);

    cleanup(&path);
}'''),
    ...para('//',
        r'Three nodes are sent, then StoreMsg::Flush, and the test waits 300 ms before counting. Three rows are expected. Flush is handled in the same arm as the timer’s timeout, so it also resets the deadline. The wait is generous because the message must cross two hops (tokio channel to bridge task to std channel to thread) before the commit.'),
    blank,
    ...sec(r'test 2: the timer, with no Flush'),
    ...code('rust', r'crates/heaplens-daemon/tests/store_tests.rs · lines 52-71', r'''
#[tokio::test]
async fn store_batches_on_timer() {
    let path = temp_db_path("batch");
    cleanup(&path);

    let (tx, _handle) = store::open(&path).unwrap();
    for i in 0..50u64 {
        tx.send(StoreMsg::Nodes(vec![make_dto(i)])).unwrap();
    }
    // No Flush — wait for the 100ms batch timer plus margin
    tokio::time::sleep(Duration::from_millis(400)).await;

    let conn = rusqlite::Connection::open(&path).unwrap();
    let count: i64 = conn
        .query_row("SELECT count(*) FROM nodes", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count, 50);

    cleanup(&path);
}'''),
    ...para('//',
        r'Fifty single-node messages and no flush; wait 400 ms (the comment says "wait for the 100ms batch timer plus margin") and expect fifty rows. This is the property that matters in production, since main.rs does not send Flush during normal operation. The commit that followed the first version (0d465e5) changed the batching to a fixed deadline, in its message "so sustained alloc bursts no longer starve the 100ms commit window". The earlier code reset a per-message timeout, so a steady stream of messages could postpone the commit indefinitely. Fifty messages sent in a tight loop do not demonstrate that fix, as they arrive far faster than 100 ms apart, but the test does show timer commits work at all. A test that fed messages for longer than a window would be the one to catch the starvation.'),
    blank,
    ...sec(r'test 3: Shutdown commits what is pending'),
    ...code('rust', r'crates/heaplens-daemon/tests/store_tests.rs · lines 73-93', r'''
#[tokio::test]
async fn store_shutdown_flushes() {
    let path = temp_db_path("shutdown");
    cleanup(&path);

    {
        let (tx, _handle) = store::open(&path).unwrap();
        tx.send(StoreMsg::Nodes(vec![make_dto(99)])).unwrap();
        tx.send(StoreMsg::Shutdown).unwrap();
        tokio::time::sleep(Duration::from_millis(200)).await;
        // tx dropped here
    }

    let conn = rusqlite::Connection::open(&path).unwrap();
    let count: i64 = conn
        .query_row("SELECT count(*) FROM nodes", [], |r| r.get(0))
        .unwrap();
    assert!(count >= 1, "shutdown should flush pending rows, got {count}");

    cleanup(&path);
}'''),
    ...para('//',
        r'One node, then StoreMsg::Shutdown, a 200 ms wait, and the channel dropped at the end of the block. The assertion is count >= 1, with the message "shutdown should flush pending rows". The weak comparison is on purpose or by accident: Shutdown could not insert more than one row, so equality would be stricter and as easy. The thread’s Shutdown arm also handles Disconnected, so even a dropped sender commits pending rows. This test does not tell the two apart.'),
    blank,
    ...para('//',
        r'The returned JoinHandle, which 0d465e5 added so that main could join the store thread before the process exits, "preventing data loss on process exit", is bound to _handle and never joined here. The test sleeps for 200 ms in its place.'),
    blank,
    ...sec(r'the design under test'),
    ...pt('//', r'one thread owns the Connection',
        r'the thread opens and holds the Connection; the module comment and code show one owner, so nothing else needs to lock it.'),
    ...pt('//', r'two queues',
        r'the tokio sender is what async code holds; the std receiver is what the thread can block on with recv_timeout. A small bridge task copies from one to the other.'),
    ...pt('//', r'unchecked_transaction',
        r'each batch of rows is written inside a single transaction (commit_batch in store.rs).'),
    ...pt('//', r'failures are warnings',
        r'a failed commit logs and clears the batch. The data is lost, silently from the caller’s side.'),
    ...sec(r'gaps'),
    ...para('//',
        r'· The state column. 0d465e5 changed it to be written with serde ("healthy", not "Healthy") to match the WebSocket format, and no test reads that column back.'),
    ...pt('//', r'Failure paths',
        r'an unwritable path, a failed commit.'),
    ...para('//',
        r'· Sleep-based timing, so the tests are slow (about 0.9 seconds together) and could flake on a loaded machine.'),
    ...para('//',
        r'· Shared temp path names; two parallel test binaries would collide, though the three paths here are distinct.'),
    ...sec(r'history'),
    ...pt('//', r'88dedac (2026-07-02)',
        r'store.rs and the first tests.'),
    ...pt('//', r'0d465e5 (2026-07-02)',
        r'join handle returned from open, fixed-window batching, serde state format. The tests were adjusted to the new return type of open.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/tests/store_tests.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/tests/store_tests.rs'),
  ],
);
