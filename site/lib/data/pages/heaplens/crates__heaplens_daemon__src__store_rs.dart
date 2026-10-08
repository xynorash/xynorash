import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/src/store.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'store.rs — SQLite persistence off the hot path'),
    cm('//', r'one thread, one connection, one commit every 100 ms'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'writes node snapshots and orphan transitions to a SQLite file'),
    kv('language', r'Rust, rusqlite (bundled SQLite), std::thread'),
    kv('size', r'153 lines'),
    kv('history', r'3 commits, 2026-07-02 to 2026-07-16'),
    kv('tables', r'nodes (+ idx_ts) and orphan_events'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'The graph lives in memory and the UI sees it live. SQLite '
        r'is the daemon’s memory of what happened. The Build Spec '
        r'(section 5.6) frames it as the project’s "data management" '
        r'angle and fixes two rules: use rusqlite with the bundled '
        r'feature, and "Writes happen on a dedicated task fed by a '
        r'channel, never in the ingest or graph hot path. Batch inserts '
        r'in a transaction every ~100 ms." The M4 plan turns those into '
        r'two numbered decisions. Q1: the store receives processed '
        r'NodeDto values from drain_diff, "never raw AllocEvent", which '
        r'"decouples persistence from the event format". Q2: 100 ms '
        r'batched transactions with one dedicated task owning the '
        r'Connection.'),
    blank,
    ...para('//',
        r'What the store ended up doing differs from the spec in a '
        r'way worth knowing. The spec sketched an alloc_events table of '
        r'raw events and a query(window) function for historical '
        r'questions like bytes per symbol over a window. The shipped '
        r'store has no query function at all. It writes two tables and '
        r'lets other tools open the file. The one consumer in the '
        r'repository is the H1 harness (crates/h1-harness), which '
        r'opens the file with rusqlite and reads orphan_events and a '
        r'node timestamp back. The Flutter app does not touch SQLite.'),

    ...sec(r'the schema'),
    ...code('rust', 'crates/heaplens-daemon/src/store.rs · open(), the schema', r'''
let conn = Connection::open(path)?;

conn.execute_batch(
    "CREATE TABLE IF NOT EXISTS nodes (
        id      INTEGER NOT NULL,
        ptr     INTEGER NOT NULL,
        size    INTEGER NOT NULL,
        ts      INTEGER NOT NULL,
        symbol  TEXT    NOT NULL,
        state   TEXT    NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_ts ON nodes(ts);
    CREATE TABLE IF NOT EXISTS orphan_events (
        node_id               INTEGER NOT NULL,
        owner_free_ts_ns      INTEGER NOT NULL,
        orphan_detected_ts_ns INTEGER NOT NULL,
        tau_ms                INTEGER NOT NULL
    );",
)?;
'''),
    ...para('//',
        r'Three properties of this schema are easy to miss.'),
    ...pt('//', 'it is a history, not a state table',
        r'nodes has no primary key. main.rs sends every added and '
        r'every updated NodeDto from each tick’s diff, so one '
        r'allocation produces one row when it appears and another '
        r'each time it is touched afterwards: when it gains a child, '
        r'when it loses its owner, when its state flips, when it is '
        r'reallocated. An owner with a growing cluster is rewritten '
        r'every tick in which a child arrives. Reading the table '
        r'gives a log of snapshots; the latest row per id is the '
        r'current state.'),
    ...pt('//', 'frees are not recorded',
        r'Only add and update go to the store. A dealloc leaves the '
        r'diff’s remove list and nothing else, so the table cannot '
        r'tell you when an allocation ended, and the live and edges '
        r'fields of NodeDto are not columns.'),
    ...pt('//', 'ts is the allocation time',
        r'The ts column is the node’s own allocation timestamp (the '
        r'producer’s clock, in nanoseconds), repeated on every '
        r'row for that node, not the time of the update. idx_ts '
        r'therefore orders by when things were allocated. Node ids '
        r'restart from 0 for every daemon run (and for every real '
        r'target switch, because the graph is rebuilt), and no '
        r'column identifies the run, so ids are only unique within '
        r'one run of one target. The H1 harness copes by giving each '
        r'run its own database file.'),
    blank,
    ...para('//',
        r'The second table is the H1 measurement’s evidence: '
        r'(node_id, owner_free_ts_ns, orphan_detected_ts_ns, '
        r'tau_ms), added on 2026-07-16 in b97b008 for the detection-'
        r'latency work. The orphan_persistence test shows a row '
        r'whose three timestamps equal the injected event '
        r'timestamps exactly.'),

    ...sec(r'a thread, a bridge, and why they are both there'),
    ...code('rust', 'crates/heaplens-daemon/src/store.rs · channels, bridge task, store thread', r'''
let (std_tx, std_rx) = std_mpsc::channel::<StoreMsg>();
let (tokio_tx, mut tokio_rx) = tokio_mpsc::unbounded_channel::<StoreMsg>();

// Bridge: tokio receiver → std sender
tokio::spawn(async move {
    while let Some(msg) = tokio_rx.recv().await {
        if std_tx.send(msg).is_err() {
            break;
        }
    }
});

// Store thread: owns Connection, batches inserts every 100ms on a fixed deadline.
let handle = thread::spawn(move || {
    let batch_interval = Duration::from_millis(100);
    let mut batch: Vec<heaplens_protocol::NodeDto> = Vec::new();
    let mut orphan_batch: Vec<crate::msg::OrphanEventRecord> = Vec::new();
    let mut deadline = std::time::Instant::now() + batch_interval;

    loop {
'''),
    ...para('//',
        r'The producer side is a tokio unbounded channel, so the graph '
        r'loop can send without awaiting. The consumer side is a '
        r'plain std::thread that owns the rusqlite Connection '
        r'(rusqlite is blocking, so it does not belong on the '
        r'async runtime). The two are joined by a small tokio task '
        r'that forwards every message into a std mpsc channel.'),
    blank,
    ...para('//',
        r'Why the extra hop is not spelled out in the source. My '
        r'reading: the thread needs recv_timeout to implement the '
        r'100 ms deadline, which std::sync::mpsc has and the tokio '
        r'receiver does not, while the graph loop needs a sender '
        r'that never blocks and works from async code. The bridge '
        r'reconciles the two at the cost of one more queue and one '
        r'more task. Two consequences follow. open() must be '
        r'called inside a tokio runtime, because it calls '
        r'tokio::spawn (main.rs does, and so do the tests via '
        r'#[tokio::test]). And the store has two unbounded queues '
        r'in series, so a slow SQLite never slows the graph loop '
        r'but turns into memory instead.'),

    ...sec(r'batching on a fixed deadline'),
    ...code('rust', 'crates/heaplens-daemon/src/store.rs · the store thread loop', r'''
let handle = thread::spawn(move || {
    let batch_interval = Duration::from_millis(100);
    let mut batch: Vec<heaplens_protocol::NodeDto> = Vec::new();
    let mut orphan_batch: Vec<crate::msg::OrphanEventRecord> = Vec::new();
    let mut deadline = std::time::Instant::now() + batch_interval;

    loop {
        let now = std::time::Instant::now();
        let timeout = if now >= deadline {
            Duration::ZERO
        } else {
            deadline - now
        };

        match std_rx.recv_timeout(timeout) {
            Ok(StoreMsg::Nodes(dtos)) => {
                batch.extend(dtos);
                // Do NOT reset deadline — let it fire at the fixed interval.
            }
            Ok(StoreMsg::OrphanEvents(records)) => {
                orphan_batch.extend(records);
                // Same fixed-interval batching as the Nodes path above.
            }
            Ok(StoreMsg::Flush) | Err(std_mpsc::RecvTimeoutError::Timeout) => {
                if !batch.is_empty() {
                    if let Err(e) = commit_batch(&conn, &batch) {
                        warn!("store commit failed: {e}");
                    }
                    batch.clear();
                }
                if !orphan_batch.is_empty() {
                    if let Err(e) = commit_orphan_batch(&conn, &orphan_batch) {
                        warn!("store orphan-event commit failed: {e}");
                    }
                    orphan_batch.clear();
                }
                deadline = std::time::Instant::now() + batch_interval;
            }
'''),
    ...para('//',
        r'A batch is committed when the deadline passes, which is '
        r'reset only after a commit. The comment on the Nodes arm is '
        r'the whole lesson: "Do NOT reset deadline — let it fire at '
        r'the fixed interval." It is the fix in commit 0d465e5 '
        r'(2026-07-02, the day the file was written). The message: '
        r'"Batch flush uses a fixed-deadline timer instead of per-'
        r'message recv_timeout, so sustained alloc bursts no longer '
        r'starve the 100ms commit window". The earlier shape called '
        r'recv_timeout(100ms) afresh for each loop turn, which '
        r'only times out when no message arrives for a full '
        r'100 ms. At 30 diffs a second, that is never. The commit '
        r'would be deferred for as long as the burst lasted, with '
        r'the batch growing without bound.'),
    blank,
    ...para('//',
        r'The shape is simple to state: timeout = deadline - now, '
        r'clamped to zero. Every message is a chance to accumulate; '
        r'the commit happens on the first Timeout after the '
        r'deadline, and Flush commits early.'),
    blank,
    ...para('//',
        r'One subtlety remains, from reading the code and not from '
        r'any test. The commit arm runs on Timeout or Flush only. '
        r'recv_timeout with a zero timeout returns an already-queued '
        r'message rather than timing out, so once the deadline has '
        r'passed the commit waits for the queue to be momentarily '
        r'empty. The thread drains messages (a Vec::extend each) '
        r'much faster than they arrive at diff rates, so in normal '
        r'operation the wait is negligible. A producer that outran '
        r'the thread would push the commit out as the queue stayed '
        r'full. Nothing measures the margin.'),

    ...sec(r'commit: one transaction per batch'),
    ...code('rust', 'crates/heaplens-daemon/src/store.rs · commit_batch', r'''
fn commit_batch(conn: &Connection, batch: &[heaplens_protocol::NodeDto]) -> Result<()> {
    let tx = conn.unchecked_transaction()?;
    for dto in batch {
        // Serialize state using serde so the DB value matches the WS wire format
        // (e.g. "healthy" not "Healthy").
        let state_str = serde_json::to_value(&dto.state)
            .ok()
            .and_then(|v| v.as_str().map(str::to_owned))
            .unwrap_or_else(|| format!("{:?}", dto.state));
        tx.execute(
            "INSERT INTO nodes (id, ptr, size, ts, symbol, state) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![
                dto.id as i64,
                dto.ptr as i64,
                dto.size as i64,
                dto.ts as i64,
                &dto.symbol,
                state_str
            ],
        )?;
    }
    tx.commit()?;
    Ok(())
}
'''),
    ...para('//',
        r'Everything in a batch goes in one transaction, which is '
        r'the point of Q2: SQLite pays its per-commit durability '
        r'cost once per 100 ms instead of once per row. The code '
        r'sets no PRAGMA, so SQLite’s defaults apply (a rollback '
        r'journal, and a sync at commit). At one commit per 100 ms '
        r'that is at most ten per second. This was not measured '
        r'here.'),
    blank,
    ...para('//',
        r'The state column deserves its three-line expression. '
        r'The first version wrote the Rust Debug name ("Healthy"). '
        r'0d465e5 changed it to serialize through serde so the '
        r'database value matches the WebSocket wire format '
        r'("healthy"): the comment says "so the DB value matches the '
        r'WS wire format (e.g. "healthy" not "Healthy")". Two '
        r'formats for one concept would have forced every reader of '
        r'the file to know which producer wrote it. The Debug '
        r'fallback only fires if serialization somehow fails.'),
    blank,
    ...para('//',
        r'Other details: unchecked_transaction takes &Connection '
        r'(a regular transaction() needs &mut), a good fit for a '
        r'helper that borrows the connection immutably; the cost is '
        r'that nesting is not caught by the borrow checker, and '
        r'nothing here nests. The u64 values are stored with "as '
        r'i64", which would wrap above 2^63. Pointers on x64 user '
        r'space, ids and nanosecond timestamps are far below that. '
        r'And each row is inserted through tx.execute with a SQL '
        r'string, which in rusqlite prepares the statement on '
        r'every call. A prepared-statement cache would avoid '
        r're-parsing it per row; whether that matters at these '
        r'volumes is unmeasured.'),

    ...sec(r'failure policy: log and move on'),
    ...para('//',
        r'A failed commit prints one warning and, in the periodic '
        r'arm, the batch is cleared regardless (batch.clear() sits '
        r'outside the error check). That batch is lost. The '
        r'reasoning the code implies is that persistence is '
        r'secondary to the live view: a disk problem should degrade '
        r'history, not stop the graph. The cost is that a '
        r'persistent failure, say a locked file or a full disk, '
        r'drops every batch and the only trace is a stream of '
        r'"store commit failed" lines.'),

    ...sec(r'shutdown'),
    ...para('//',
        r'The last arm handles two causes with one body: an '
        r'explicit StoreMsg::Shutdown, and the channel '
        r'disconnecting (all senders gone). Both commit whatever is '
        r'pending and exit. main.rs sends Shutdown on Ctrl-C, then '
        r'drops its sender and joins the thread; the join handle '
        r'was added in 0d465e5 specifically "preventing data loss '
        r'on process exit". Without the join, the process could '
        r'finish exiting before the final transaction.'),
    blank,
    ...para('//',
        r'The doc comment on open() says it "Returns the sender '
        r'channel". It returns a pair, the sender and the '
        r'JoinHandle, since 0d465e5 did not update the sentence. A '
        r'small stale comment, but it sits on the one function '
        r'whose return value main.rs must not ignore.'),

    ...sec(r'how it is tested'),
    ...para('//',
        r'tests/store_tests.rs has three tests, each opening a '
        r'real file in the temp directory, sending messages and '
        r'reading the table back with rusqlite:'),
    ...pt('//', 'store_inserts_nodes',
        r'sends three DTOs and a Flush, sleeps 300 ms, expects 3 rows.'),
    ...pt('//', 'store_batches_on_timer',
        r'sends 50 one-node messages with no Flush, sleeps 400 ms, '
        r'expects 50 rows, which exercises the 100 ms deadline.'),
    ...pt('//', 'store_shutdown_flushes',
        r'sends a node and Shutdown and expects at least one row. '
        r'The assertion is "count >= 1", weaker than it could be.'),
    blank,
    ...para('//',
        r'tests/orphan_persistence.rs covers the second table '
        r'end to end with exact timestamp equality. All four tests '
        r'rely on sleeps (200 to 400 ms) rather than a completion '
        r'signal, which is simple and slightly timing-dependent. '
        r'The tests build their paths with a backslash '
        r'("{temp_dir}\\heaplens_test_{name}.db"), a Windows-style '
        r'separator.'),

    ...sec(r'limits'),
    ...pt('//', 'no query API, no retention',
        r'The file grows for as long as the daemon runs and is '
        r'appended to across runs (CREATE TABLE IF NOT EXISTS, no '
        r'truncation). Nothing prunes it.'),
    ...pt('//', 'the history is lossy by design',
        r'No frees, no edges, no run identifier. It is enough for '
        r'the H1 measurement and for post-hoc inspection of '
        r'states, not for replaying a session.'),
    ...pt('//', 'a failed batch is gone',
        r'See above.'),
    ...pt('//', 'two unbounded queues',
        r'If SQLite falls behind, rows accumulate in memory. The '
        r'2026-07-22 load investigation measured the graph '
        r'task and the ingest channel; no figure for the store '
        r'queue appears in any commit message I read.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
