import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/h1-harness/src/main.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'main.rs — measuring a detector without touching it'),
    cm('//', r'forty runs, three timestamps read back from the daemon’s own database'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'measures H1, the orphan-detection latency, end to end'),
    kv('language', r'Rust, tokio, tokio-tungstenite, rusqlite (bundled)'),
    kv('size', r'626 lines: 49-line header, 20 + 20 runs, a diagnose mode'),
    kv('history', r'one commit, 816c732, 2026-07-16 14:41 +0300'),
    kv('modes', r'measure (default), diagnose [tau_ms]'),
    kv('output', r'docs/bench_results/h1_latency.csv, 40 rows, 0 failures'),
    kv('tests', r'none; the harness is the experiment'),
    ...sec(r'the question, and the measurement that came before'),
    ...para('//',
        r'H1 is the Build Spec’s name for one number: how long after a '
        r'memory block becomes an orphan does HeapLens say so. An orphan '
        r'is a live allocation whose owner has been freed, and which has '
        r'outlived an age threshold, tau. A leak tool is worth as much as '
        r'its answer to that question, which is why the project wrote '
        r'a harness for it and did not quote a figure from reading the '
        r'code. The numbers and how to read them are on the page for '
        r'docs/bench_results/h1_latency.csv. This page is about the '
        r'instrument: how the harness is built so that its numbers can '
        r'be believed.'),
    blank,
    ...para('//',
        r'It is the second attempt. The commit message that added it '
        r'says it "replaces the earlier discarded H1 attempt, which '
        r'measured a modified pipeline and was dominated by the '
        r'workload’s settle-sleep". Two sins in one sentence. Measuring a '
        r'pipeline you have modified for the purpose of measuring it '
        r'measures the modification. And a workload that sleeps before '
        r'acting puts the sleep into the answer. The harness is shaped '
        r'by avoiding both.'),
    ...sec(r'the header: a contract written before the code'),
    ...code('rust', 'crates/h1-harness/src/main.rs · the header comment', r'''
// h1-harness: H1 detection-latency measurement.
//
// Workload: the existing, already-validated chaos-test orphan scenario
// (crates/heaplens-alloc/examples/chaos_orphan.rs, copied verbatim from the
// dev/chaos_test worktree — not rewritten here). It allocates an owner and
// five children owned by it via phi, sleeps 300ms, frees the owner alone
// (orphaning the children), then holds a 7s heartbeat loop so the daemon
// keeps receiving events (max_ts_seen only advances on alloc, never on
// dealloc — see graph.rs's on_dealloc, deliberately unchanged).
//
// Definition (corrected — see docs/bench_results/h1_report.md for the full
// derivation): the orphan condition is a conjunction of two predicates
// (owner freed AND age > tau), so detection cannot be measured from
// owner-free alone — it must be measured from whichever of the two
// conjuncts completes *last*:
//
//   H1 = orphan_detected_ts_ns - max(owner_free_ts_ns, node_ts_ns + tau_ms*1e6)
//
// All three input timestamps are read back from the daemon's own SQLite
// tables after the run — never inferred, never captured workload-side,
// never a proxy:
//   - owner_free_ts_ns, orphan_detected_ts_ns: orphan_events table
//     (crates/heaplens-daemon/src/store.rs), written by the observability
//     change reviewed in Part 1.
//   - node_ts_ns (the child's own allocation ts): the pre-existing `nodes`
//     table's `ts` column for that node id — this is Node::ts, set once at
//     on_alloc and never mutated, so any row for that id carries the
//     correct value. No further daemon persistence change was needed for
//     this — it reuses data the daemon already stored.
//
// All three timestamps are producer-clock nanoseconds (heaplens-alloc's
// Instant::now() relative to a process-local START, captured inside the
// *same* target process for every event) — same clock domain throughout.
//
// Two configurations are run: tau < the workload's ~300ms settle-gap
// (owner-free is the binding conjunct — reports sweep-cadence-bound
// latency) and tau > the settle-gap (age-past-tau is the binding conjunct
// — reports detection-from-tau-completion latency, expected near one tick).
//
// A `diagnose` mode additionally captures the daemon's own debug-level
// per-tick log (opt-in via RUST_LOG=heaplens_daemon=debug, added as a
// small diagnostic-only daemon change) with harness-side wall-clock
// receipt timestamps, to confirm whether ticks fire on a steady ~tick_ms
// cadence or arrive as a drained backlog — load-bearing for trusting the
// tau-bound config's number as genuine sweep latency.
//
// A failed run (WS orphan diff never observed within the timeout, or an
// inconsistent/missing/unreadable persisted row) is reported as FAILED and
// excluded from the CSV — never fabricated.'''),
    ...para('//',
        r'Read it as a specification, because that is how it was '
        r'written. The workload is not new: it is the existing, '
        r'already-validated chaos_orphan scenario, "copied verbatim ... '
        r'not rewritten here", so the harness measures behaviour that '
        r'other tests had already pinned down. The definition is '
        r'given as a formula and then justified as a conjunction. All '
        r'three timestamps are "read back from the daemon’s own SQLite '
        r'tables after the run — never inferred, never captured '
        r'workload-side, never a proxy". And the final paragraph sets '
        r'the reporting rule: a failed run is "reported as FAILED and '
        r'excluded from the CSV — never fabricated".'),
    blank,
    ...para('//',
        r'Everything the daemon had to add to make this possible is also '
        r'recorded. The commit before the harness, b97b008 (14:40:46 the '
        r'same afternoon, merged with it at 14:41:16), added the '
        r'orphan_events table and threaded the free event’s timestamp '
        r'through the graph. Its message states why: "neither the WS '
        r'diff nor the SQLite store previously emitted a real '
        r'owner-free timestamp to measure from". That change is '
        r'"observability-only: never read by infer_ownership or '
        r'anomaly::sweep’s state predicates, so it cannot influence '
        r'detection timing or outcome", and the existing detection '
        r'tests passed with identical assertions before and after. The '
        r'instrument was not allowed to bend the thing it measured.'),
    ...sec(r'the definition, as code'),
    ...code('rust', 'crates/h1-harness/src/main.rs · the formula', r'''
fn binding_ts_ns(r: &RunResult) -> u64 {
    let tau_bound = r.node_ts_ns + r.tau_ms * 1_000_000;
    r.owner_free_ts_ns.max(tau_bound)
}

fn h1_latency_ms(r: &RunResult) -> f64 {
    (r.orphan_detected_ts_ns as f64 - binding_ts_ns(r) as f64) / 1_000_000.0
}'''),
    ...para('//',
        r'Those eight lines carry a correction the commit message '
        r'records: "The first version of this formula omitted the '
        r'max() and went negative under tau=5ms (tau already satisfied '
        r'~190ms before owner-free in this workload)". The repository '
        r'holds only the corrected formula, so I cannot reconstruct '
        r'the earlier one and will not guess at the mechanism. What '
        r'the final form says is the part I can defend. The orphan '
        r'condition is a conjunction, owner freed and age past tau, so '
        r'a latency has to start from whichever conjunct became true '
        r'last, and max() does exactly that. One number in the message '
        r'does not match the data: the CSV rows put the owner free at '
        r'about 300 ms and the node’s allocation at about 0.1 ms, so '
        r'with tau = 5 ms the age condition was satisfied at about 5 '
        r'ms, roughly 295 ms before the free, not 190. The page for '
        r'the CSV notes the same difference. I trust the rows.'),
    blank,
    ...para('//',
        r'The harness keeps a tripwire for the case the max() was '
        r'supposed to make impossible. After computing the statistics '
        r'it checks:'),
    ...code('rust', 'crates/h1-harness/src/main.rs · the tripwire (inside main)', r'''
        if latencies.iter().any(|&v| v < 0.0) {
            println!("  *** negative H1 value present — the max() fix did not eliminate the negative case; stop and report. ***");
        }'''),
    ...para('//',
        r'The commit says the max() makes a negative result '
        r'"structurally impossible", and the code does not rely on '
        r'that claim. If a negative ever appears, the run prints a loud '
        r'line and tells the operator to "stop and report". It is the '
        r'habit of making an impossibility testable.'),
    blank,
    ...para('//',
        r'My own reasoning suggests why the tripwire is not '
        r'paranoia. The header says max_ts_seen "only advances on '
        r'alloc, never on dealloc". The detection timestamp is that '
        r'value at the detecting tick. In a workload with no '
        r'allocation after the free, an orphan whose age was already '
        r'past tau could be flagged on a tick whose max_ts is still '
        r'earlier than the free’s own timestamp, and the formula would '
        r'go negative anyway. In chaos_orphan the heartbeat '
        r'allocations that follow the free keep that from happening, '
        r'which is a second reason the header takes the trouble to '
        r'describe them.'),
    ...sec(r'anatomy of one run'),
    ...para('//',
        r'main() runs two configurations, N_RUNS = 20 each, and '
        r'run_once() is the whole experiment. These are its steps:'),
    ...pt('//', r'1 fresh everything',
        r'a new database path under the temp directory, deleted if '
        r'present; a new WebSocket port (BASE_WS_PORT 9800 plus a '
        r'running offset, so 9801 to 9840 for forty runs); a fresh '
        r'daemon process.'),
    ...pt('//', r'2 configure through the environment',
        r'HEAPLENS_DB_PATH, HEAPLENS_WS_ADDR, HEAPLENS_TAU_MS, and '
        r'RUST_LOG scoped to this crate only.'),
    ...pt('//', r'3 watch the daemon’s log',
        r'its stdout is piped; a task timestamps every "tick" line the '
        r'moment it is read.'),
    ...pt('//', r'4 wait 300 ms, then start two things',
        r'a WebSocket watcher, and the workload process.'),
    ...pt('//', r'5 wait for the orphan to appear',
        r'the watcher returns the id of the first node that is an '
        r'Orphan with the expected symbol; the wait is bounded at 20 '
        r'seconds.'),
    ...pt('//', r'6 let the store catch up',
        r'sleep another 300 ms so the 100 ms store batch has committed '
        r'the orphan row.'),
    ...pt('//', r'7 stop everything, then read',
        r'kill and wait for both children, await the log-reader task, '
        r'drain its channel, open the database.'),
    ...code('rust', 'crates/h1-harness/src/main.rs · run_once, launching the daemon', r'''
    let ws_port = BASE_WS_PORT + port_offset;
    let ws_addr = format!("127.0.0.1:{ws_port}");
    let db_path = std::env::temp_dir().join(format!("heaplens_h1_tau{tau_ms}_run{run}.db"));
    let _ = std::fs::remove_file(&db_path);

    // RUST_LOG scoped to debug for THIS crate only (not deps) — captures
    // the same per-tick diagnostic line used in `diagnose` mode, but for
    // every statistical run, so cadence evidence exists per-run rather
    // than only in a separate side measurement.
    let mut daemon_child = match Command::new(daemon_exe)
        .env("HEAPLENS_DB_PATH", &db_path)
        .env("HEAPLENS_WS_ADDR", &ws_addr)
        .env("HEAPLENS_TAU_MS", tau_ms.to_string())
        .env("RUST_LOG", "heaplens_daemon=debug")
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .kill_on_drop(true)
        .spawn()
    {
        Ok(c) => c,
        Err(e) => return RunOutcome::Failed { run, tau_ms, reason: format!("daemon spawn failed: {e}") },
    };

    let stdout = daemon_child.stdout.take().expect("piped stdout");
    let start = Instant::now();
    let (tick_tx, tick_rx) = std::sync::mpsc::channel::<(Duration, u64)>();
    let tick_task = tokio::spawn(async move {
        let mut lines = tokio::io::AsyncBufReadExt::lines(tokio::io::BufReader::new(stdout));
        while let Ok(Some(line)) = lines.next_line().await {
            if let Some(max_ts) = parse_max_ts(&line) {
                let _ = tick_tx.send((start.elapsed(), max_ts));
            }
        }
    });'''),
    ...para('//',
        r'Note the two lines that make the environment honest. '
        r'The comment on RUST_LOG says the debug filter is scoped "for '
        r'THIS crate only (not deps)" and applied "for every '
        r'statistical run, so cadence evidence exists per-run rather '
        r'than only in a separate side measurement". And '
        r'kill_on_drop(true) on every child means a panicking harness '
        r'does not leave daemons and workloads running to pollute the '
        r'next run.'),
    ...sec(r'the first dead end: reading a pipe too early'),
    ...code('rust', 'crates/h1-harness/src/main.rs · run_once, after the hit', r'''
    // Store thread batches on a 100ms fixed interval — give it margin to
    // commit the orphan_events row before we read it back.
    tokio::time::sleep(Duration::from_millis(300)).await;

    let _ = daemon_child.kill().await;
    let _ = daemon_child.wait().await;
    let _ = workload_child.kill().await;
    let _ = workload_child.wait().await;

    // The daemon process is dead and its stdout pipe closed, but the task
    // reading that pipe is a separate, concurrently-scheduled tokio task —
    // draining the channel before it's actually finished (it may not have
    // been polled since the last line arrived) silently loses everything
    // still in flight. Await its completion first.
    let _ = tick_task.await;
    let mut ticks: Vec<(Duration, u64)> = Vec::new();
    while let Ok(t) = tick_rx.try_recv() {
        ticks.push(t);
    }

    let result = read_orphan_event(&db_path, node_id, run, tau_ms, &ticks);
    let _ = std::fs::remove_file(&db_path);
    result'''),
    ...para('//',
        r'The comment on the await tells a debugging story in four '
        r'lines. The daemon is dead and its stdout pipe closed, "but '
        r'the task reading that pipe is a separate, concurrently-'
        r'scheduled tokio task". Draining the channel before that task '
        r'finishes "silently loses everything still in flight". The '
        r'bug is quiet by nature: what it loses is the last few tick '
        r'lines, and the detecting tick is near the end of the run, so '
        r'those are the lines that matter. The cure is to await the '
        r'task, and only then drain. Without that ordering I would '
        r'expect the per-run tick gap to be missing for some runs with '
        r'no sign of why.'),
    ...sec(r'the second dead end: colour codes in a pipe'),
    ...code('rust', 'crates/h1-harness/src/main.rs · strip_ansi and parse_max_ts', r'''
/// Strips ANSI SGR escape sequences (`ESC [ ... letter`). tracing_subscriber's
/// default fmt layer colors output unconditionally (no TTY auto-detection),
/// even when stdout is a pipe — so e.g. "max_ts=" is not contiguous in the
/// raw bytes (a reset/color escape is spliced between the field name and
/// the "="), even though a terminal renders it as if it were.
fn strip_ansi(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\u{1b}' && chars.peek() == Some(&'[') {
            chars.next(); // consume '['
            for c2 in chars.by_ref() {
                if c2.is_ascii_alphabetic() {
                    break;
                }
            }
            continue;
        }
        out.push(c);
    }
    out
}

/// Extracts the `max_ts=<n>` value from a `heaplens_daemon`'s debug-level
/// "tick" log line.
fn parse_max_ts(line: &str) -> Option<u64> {
    let plain = strip_ansi(line);
    if !plain.contains("tick") {
        return None;
    }
    let idx = plain.find("max_ts=")?;
    let rest = &plain[idx + "max_ts=".len()..];
    let end = rest.find(|c: char| !c.is_ascii_digit()).unwrap_or(rest.len());
    rest[..end].parse().ok()
}'''),
    ...para('//',
        r'The harness finds ticks by reading the daemon’s log, and the '
        r'log is formatted by tracing_subscriber. The comment explains '
        r'the trap: its default formatter "colors output '
        r'unconditionally (no TTY auto-detection), even when stdout is '
        r'a pipe — so e.g. ‘max_ts=’ is not contiguous in the raw '
        r'bytes (a reset/color escape is spliced between the field '
        r'name and the ‘=’), even though a terminal renders it as if it '
        r'were." A parser written against what the terminal shows '
        r'finds no match in what the pipe delivers. The fix is to '
        r'strip SGR escape sequences before looking for max_ts=, and '
        r'the function is written without a regex dependency.'),
    blank,
    ...para('//',
        r'The lesson is general: what you see is not what you parse. '
        r'The fix is a few lines once understood. The cost is in '
        r'finding it, because the logs look right.'),
    ...sec(r'the trigger is the WebSocket, the measurement is the database'),
    ...code('rust', 'crates/h1-harness/src/main.rs · watch_ws', r'''
async fn watch_ws(ws_url: String, hit_tx: oneshot::Sender<u64>) {
    let (ws_stream, _) = match tokio_tungstenite::connect_async(&ws_url).await {
        Ok(pair) => pair,
        Err(_) => return,
    };
    let (_sink, mut source) = ws_stream.split();

    while let Some(Ok(msg)) = source.next().await {
        let text = match msg {
            Message::Text(t) => t,
            _ => continue,
        };
        let Ok(GraphMessage::Diff { add, update, .. }) = serde_json::from_str(&text) else {
            continue;
        };
        for n in add.iter().chain(update.iter()) {
            if n.symbol == CHILD_SYMBOL && n.state == NodeState::Orphan {
                let _ = hit_tx.send(n.id);
                return;
            }
        }
    }
}'''),
    ...para('//',
        r'The harness uses the WebSocket for one purpose: to know when '
        r'to stop. It connects as an ordinary client, decodes each text '
        r'frame as the project’s own GraphMessage type (the same '
        r'heaplens-protocol crate as the daemon, so a schema '
        r'change breaks the build, not the measurement), and returns '
        r'the id of the first node that has the expected symbol and '
        r'the Orphan state. The time at which the WebSocket saw it is '
        r'never used in the result. That separation is the point: '
        r'a client’s receipt time includes network, scheduling and '
        r'decode delays that belong to the observer, and the H1 '
        r'definition uses only timestamps from inside the system '
        r'being measured.'),
    ...sec(r'reading the evidence back'),
    ...code('rust', 'crates/h1-harness/src/main.rs · read_orphan_event, the consistency checks', r'''
    // The workload orphans all 5 make_children siblings in the same
    // on_dealloc call and the same subsequent sweep, so every row in
    // orphan_events this run should carry identical owner_free/detected
    // timestamps. Read all rows and require exact agreement rather than
    // picking one blindly.
    let mut stmt = match conn.prepare(
        "SELECT node_id, owner_free_ts_ns, orphan_detected_ts_ns, tau_ms FROM orphan_events",
    ) {
        Ok(s) => s,
        Err(e) => return RunOutcome::Failed { run, tau_ms, reason: format!("orphan_events query prepare failed: {e}") },
    };
    let rows: Result<Vec<(i64, i64, i64, i64)>, _> = stmt
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))
        .and_then(Iterator::collect);
    let rows = match rows {
        Ok(r) => r,
        Err(e) => return RunOutcome::Failed { run, tau_ms, reason: format!("orphan_events query failed: {e}") },
    };
    if rows.is_empty() {
        return RunOutcome::Failed {
            run,
            tau_ms,
            reason: format!("orphan_events table empty (WS reported node {node_id} orphaned, but no row persisted)"),
        };
    }
    let (first_id, owner_free, detected, persisted_tau) = rows[0];
    for &(id, of, d, t) in &rows[1..] {
        if of != owner_free || d != detected || t != persisted_tau {
            return RunOutcome::Failed {
                run,
                tau_ms,
                reason: format!(
                    "orphan_events rows disagree: node {first_id} has ({owner_free},{detected},{persisted_tau}), node {id} has ({of},{d},{t})"
                ),
            };
        }
    }
    if persisted_tau as u64 != tau_ms {
        return RunOutcome::Failed {
            run,
            tau_ms,
            reason: format!("persisted tau_ms ({persisted_tau}) != configured tau_ms ({tau_ms})"),
        };
    }'''),
    ...para('//',
        r'This is where the harness refuses to guess. The workload '
        r'orphans five siblings in one free, so there should be five '
        r'rows in orphan_events with identical owner-free, detection '
        r'and tau values. The code reads all of them and requires '
        r'exact agreement, with a message that names the two '
        r'disagreeing nodes, "rather than picking one blindly". It then '
        r'checks that the tau persisted by the daemon equals the tau '
        r'the harness configured: a mismatch would mean the environment '
        r'variable never reached the daemon and the run measured the '
        r'default of 5000 ms, a silent way for a whole configuration to '
        r'be wrong.'),
    ...code('rust', 'crates/h1-harness/src/main.rs · the third timestamp, from a table that already existed', r'''
    // node_ts_ns: reuse the pre-existing `nodes` table rather than adding
    // more daemon persistence. Node::ts is set once at on_alloc and never
    // mutated, so any row for this id carries the correct value.
    let node_ts_ns: Result<i64, _> =
        conn.query_row("SELECT ts FROM nodes WHERE id = ?1 LIMIT 1", [first_id], |r| r.get(0));
    let node_ts_ns = match node_ts_ns {
        Ok(v) => v,
        Err(e) => {
            return RunOutcome::Failed {
                run,
                tau_ms,
                reason: format!("could not read node_ts_ns for node {first_id} from nodes table: {e}"),
            }
        }
    };'''),
    ...para('//',
        r'The third input did not need a daemon change. The comment '
        r'explains that Node::ts "is set once at on_alloc and never '
        r'mutated", so any row of the existing nodes table for that id '
        r'carries the right value. Every use of the daemon’s data '
        r'follows the same rule: reuse what is already persisted '
        r'before adding new instrumentation.'),
    blank,
    ...para('//',
        r'All three timestamps share a clock. The header says they are '
        r'"producer-clock nanoseconds (heaplens-alloc’s Instant::now() '
        r'relative to a process-local START, captured inside the same '
        r'target process for every event)". The daemon’s detection '
        r'timestamp is not its own wall clock but max_ts, the highest '
        r'event time it has seen (main.rs in the daemon: '
        r'orphan_detected_ts_ns: max_ts). One clock domain means there is '
        r'nothing to synchronise and nothing to convert.'),
    ...sec(r'proving the ticks are real'),
    ...para('//',
        r'A subtle risk hides behind that last design choice. The '
        r'daemon’s logical clock only advances when an allocation event '
        r'arrives. A sweep happens every tick (about 33 ms, '
        r'tick_ms), but if the daemon fell behind and then drained a '
        r'queue of backlog, several ticks could fire in a burst, and a '
        r'detection number measured on such a tick would look '
        r'excellent for the wrong reason. So every run records the '
        r'wall-clock gap between the detecting tick and the one before '
        r'it:'),
    ...code('rust', 'crates/h1-harness/src/main.rs · detecting_tick_gap_ms', r'''
/// Wall-clock gap between the tick whose max_ts equals `detected_ts_ns` and
/// the tick immediately preceding it in `ticks` (in capture order). `None`
/// if no exact match is found or it's the first captured tick.
fn detecting_tick_gap_ms(ticks: &[(Duration, u64)], detected_ts_ns: u64) -> Option<f64> {
    let idx = ticks.iter().position(|&(_, max_ts)| max_ts == detected_ts_ns)?;
    if idx == 0 {
        return None;
    }
    let (t_prev, _) = ticks[idx - 1];
    let (t_cur, _) = ticks[idx];
    Some((t_cur.as_secs_f64() - t_prev.as_secs_f64()) * 1000.0)
}'''),
    ...code('rust', 'crates/h1-harness/src/main.rs · the summary of the gap (inside main, trimmed)', r'''
        let gaps: Vec<f64> = successes.iter().filter_map(|r| r.detecting_tick_gap_ms).collect();
        let unmatched = successes.len() - gaps.len();
        if gaps.is_empty() {
            println!("  detecting-tick gap: no runs had a matchable tick log — cannot confirm cadence for this config");
        } else {
            let mut sorted_gaps = gaps.clone();
            sorted_gaps.sort_by(|a, b| a.partial_cmp(b).unwrap());
            let near_zero = gaps.iter().filter(|&&g| g < 5.0).count();
            println!(
                "  detecting-tick gap (ms, per-run, this specific tick): median={:.3} min={:.3} max={:.3} over {}/{} runs ({unmatched} unmatched)",
                median_of(&sorted_gaps),
                sorted_gaps.first().unwrap(),
                sorted_gaps.last().unwrap(),
                gaps.len(),
                successes.len()
            );
            println!("  {near_zero}/{} runs show a <5ms gap before the detecting tick (backlog-drain signature)", gaps.len());
        }'''),
    ...para('//',
        r'The threshold is 5 ms: a gap shorter than that is the '
        r'"backlog-drain signature". The commit message reports the '
        r'result for all forty runs, and I re-derived it from the CSV: '
        r'no run has a gap under 5 ms; the smallest is 19.1 ms, the '
        r'largest 39.9 ms, and the medians are 31.0 ms (tau = 5) and '
        r'35.6 ms (tau = 500), around the 33 ms tick. The commit '
        r'says the gaps "cluster at 19-40ms, matching tick_ms=33", '
        r'and that is what the rows show.'),
    blank,
    ...para('//',
        r'The evidence is cheap, per-run, and necessary. It does not '
        r'prove the daemon’s sweep is perfectly periodic. It does show '
        r'that none of these forty results came from a burst.'),
    ...sec(r'diagnose mode: a separate question'),
    ...code('rust', 'crates/h1-harness/src/main.rs · diagnose_tick_cadence, the verdict', r'''
    let mut sorted = deltas_ms.clone();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let median = median_of(&sorted);
    let near_zero = deltas_ms.iter().filter(|&&d| d < 5.0).count();
    println!(
        "\ninter-tick delta (ms): median={:.3} min={:.3} max={:.3}; {}/{} deltas < 5ms",
        median,
        sorted.first().unwrap(),
        sorted.last().unwrap(),
        near_zero,
        deltas_ms.len()
    );
    if near_zero > deltas_ms.len() / 4 {
        println!(
            "*** a substantial fraction of inter-tick deltas are near-zero — consistent with backlog \
             draining rather than a clean ~tick_ms cadence. Do not trust a tau-bound H1 number without \
             accounting for this. ***"
        );
    } else {
        println!("ticks are firing on a steady cadence close to the configured tick_ms — no evidence of backlog draining.");
    }'''),
    ...para('//',
        r'The second mode answers the cadence question on its own, '
        r'without writing the CSV. It runs the daemon once, collects '
        r'every tick line with a harness-side timestamp, prints the '
        r'first ten and the ones around the hit, and then applies '
        r'a rule: if more than a quarter of the inter-tick deltas are '
        r'under 5 ms, print a warning that the cadence is "consistent '
        r'with backlog draining rather than a clean ~tick_ms cadence" '
        r'and that a tau-bound H1 number should not be trusted. The '
        r'header explains why it exists: it is "load-bearing for '
        r'trusting the tau-bound config’s number as genuine sweep '
        r'latency".'),
    ...sec(r'what the numbers say, in one paragraph'),
    ...para('//',
        r'With tau = 5 ms the owner-free is the binding conjunct, and '
        r'the median H1 is 0.0089 ms (min 0.0078, max 20.277). With '
        r'tau = 500 ms the age condition binds and the median is '
        r'2.569 ms (min 1.896, max 3.280). I computed both from the '
        r'CSV and they match the commit message. 18 of the 20 tau = 5 '
        r'runs are under 0.021 ms; two sit at about 20.2 ms, which is '
        r'one 20 ms heartbeat of the workload, my reading.'),
    blank,
    ...para('//',
        r'What the number is, deserves care. It is a difference of '
        r'two producer-clock timestamps. The commit message is '
        r'direct about it: both numbers are "conditional on this '
        r'workload’s post-trigger event cadence (chaos_orphan’s 20ms '
        r'allocation heartbeat), not a universal daemon constant", '
        r'because the logical clock "only advances on received alloc '
        r'events", making detection latency "bounded by (time to next '
        r'producer event past the binding timestamp) + (time to next '
        r'tick)". That is a deliberate consequence of keeping '
        r'everything in one clock domain rather than adding a '
        r'daemon-side timer. A tau = 5 figure of 9 microseconds is '
        r'therefore not a 33 ms sweep finishing in 9 microseconds. It '
        r'is the producer’s own next event arriving almost at once '
        r'after the free.'),
    ...sec(r'where the harness has aged'),
    ...para('//',
        r'The harness is a snapshot of an experiment, and the project '
        r'has moved since. Reading it today, I found four places where '
        r'it no longer matches the tree around it.'),
    ...pt('//', r'the workload changed under it',
        r'the header says the scenario sleeps 300 ms before freeing '
        r'the owner. Three days after the measurement, commit b000f92 '
        r'(2026-07-19) gave chaos_orphan a 15-second "healthy hold" '
        r'before the free, and the checked-in chaos_orphan.rs now has '
        r'it. The CSV matches the older workload (owner freed near '
        r'300 ms in every row). Run today, the workload frees the '
        r'owner after about 15 s, long after both taus are '
        r'satisfied, so the two configurations would no longer '
        r'differ in their binding conjunct, and the hard-coded split '
        r'in main(), tau_ms < 300 meaning owner-free binds, would '
        r'label them wrongly.'),
    ...pt('//', r'cooperative capture needs an opt-in',
        r'commit a31baeb (2026-07-28) made heaplens-alloc do nothing '
        r'unless HEAPLENS_ENABLE is set. The harness spawns the '
        r'workload without setting it and relies on inheriting '
        r'the environment, so unless the operator exports it, no '
        r'events would flow and every run would end as FAILED after '
        r'the 20-second wait.'),
    ...pt('//', r'a referenced report is missing',
        r'the header points at docs/bench_results/h1_report.md for "the '
        r'full derivation". The repository contains only the CSV. '
        r'The derivation survives in the header and the commit '
        r'message.'),
    ...pt('//', r'paths are relative and Windows-only',
        r'the daemon and workload are expected under '
        r'target/release in the current directory, with .exe '
        r'suffixes, and the CSV is written to a relative path.'),
    blank,
    ...para('//',
        r'None of that invalidates the recorded run, whose method is '
        r'documented in the header and the commit message. It means '
        r'the harness cannot be re-run unchanged, and that is worth '
        r'saying where the numbers are quoted.'),
    ...sec(r'limits of the measurement itself'),
    ...pt('//', r'one scenario',
        r'one owner and five children. It says nothing about graphs '
        r'with thousands of nodes, where the sweep itself costs more.'),
    ...pt('//', r'twenty runs per configuration',
        r'the summary reports median, min and max and no interval. '
        r'The two 20 ms outliers matter in a sample of twenty.'),
    ...pt('//', r'one machine, no warm-up discipline',
        r'the harness does not discard a first run or pin CPU affinity.'),
    ...pt('//', r'a logical-time metric',
        r'H1 as defined is a distance between two event timestamps '
        r'on the producer’s clock. It is not how long a human waits '
        r'for the screen to change.'),
    ...pt('//', r'the cadence check is evidence, not proof',
        r'it sees the gap before one tick per run.'),
    ...sec(r'what to take from it'),
    ...pt('//', r'measure from the system’s own records',
        r'three timestamps from the daemon’s tables beat any number '
        r'captured by an observer.'),
    ...pt('//', r'change the system as little as possible to see it',
        r'the observability commit was proved behaviour-preserving '
        r'by unchanged test assertions.'),
    ...pt('//', r'refuse to fabricate',
        r'failures are printed and excluded, and the harness says '
        r'so in its header.'),
    ...pt('//', r'instrument the instrument',
        r'the tick-gap column is a check on the measurement, not a '
        r'result.'),
    ...pt('//', r'a negative latency is a bug in the definition',
        r'the max() fix and the tripwire that watches for its failure.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/h1-harness/src/main.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/h1-harness/src/main.rs'),
  ],
);
