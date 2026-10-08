import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/src/main.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'main.rs — the daemon’s one graph loop'),
    cm('//', r'ingest, timer, server and store around one owner of all state'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'process entry point and the graph loop that owns all state'),
    kv('language', r'Rust, tokio multi-thread runtime'),
    kv('size', r'354 lines'),
    kv('history', r'14 commits, 2026-07-01 to 2026-07-26'),
    kv('binary', r'heaplens-daemon.exe (the lib half is lib.rs)'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'Everything else in crates/heaplens-daemon is a part with one '
        r'job: ingest.rs decodes a named pipe, graph.rs holds the model, '
        r'anomaly.rs classifies nodes, store.rs writes SQLite, server.rs '
        r'speaks WebSocket. main.rs is where those parts become a '
        r'running program, and where the one rule that makes them '
        r'composable is enforced: a single task owns the graph, '
        r'the resolver and the session state, and nothing else may touch '
        r'them. The loop comment says so in one line: "Graph loop — '
        r'single-threaded owner of all graph state."'),
    blank,
    ...para('//',
        r'That rule is why graph.rs has no locks, why a WebSocket '
        r'client gets its snapshot through a request to this loop '
        r'instead of reading the graph, and why attaching to a new '
        r'process can reset everything with one assignment. It is also '
        r'the source of this file’s sharpest limits, listed at the end.'),

    ...sec(r'the shape of the process'),
    cm('//', r''),
    cm('//', r'  ingest::run ── GraphMsg::Events / Symbols ──────┐'),
    cm('//', r'  (named pipe)    TargetConnected / Disconnected   │'),
    cm('//', r'  timer task ───── GraphMsg::Tick every tick_ms ───┤'),
    cm('//', r'                                                   ▼'),
    cm('//', r'  server clients ─ ConnectRequest ───────────▶  graph loop'),
    cm('//', r'  (one task each)  TargetCmd ─────────────────▶ (this file)'),
    cm('//', r'                                                   │'),
    cm('//', r'        ┌───────────────────┬──────────────────────┤'),
    cm('//', r'        ▼                   ▼                      ▼'),
    cm('//', r'  store thread        broadcast<GraphMessage>  broadcast<ControlResponse>'),
    cm('//', r'  (SQLite batches)    (cap 64: diff, stats,    (cap 16: TargetExited)'),
    cm('//', r'                       empty snapshot)'),
    cm('//', r''),
    ...para('//',
        r'The setup is a numbered list in the source, with steps "5b" and '
        r'"5c" squeezed in later: those are the control channels that '
        r'arrived with the stage 7 injection work (2026-07-19), a '
        r'small visible fossil of the order things were built in.'),
    ...code('rust', 'crates/heaplens-daemon/src/main.rs · startup, channels and WS server', r'''
// 2. Load config.
let config = Config::load();

// 3. Open SQLite store — returns a tokio mpsc sender and a join handle for
//    the store thread so we can wait for the final batch commit on shutdown.
let (store_tx, store_join) = store::open(&config.db_path)?;

// 4. Broadcast channel for WS diffs (capacity 64).
//    The initial receiver is intentionally dropped; clients subscribe via broadcast_tx.subscribe().
let (broadcast_tx, _) = broadcast::channel::<Arc<GraphMessage>>(64);

// 5. Connect-request channel (WS clients request snapshot + subscription).
let (connect_tx, mut connect_rx) = mpsc::unbounded_channel::<ConnectRequest>();

// 5b. Target-control channel (Stage 7 §3: WS clients request process
//     list / attach / detach; the graph task is the single owner of both
//     graph state and "which pid is currently attached" session state).
let (target_tx, mut target_rx) = mpsc::unbounded_channel::<TargetCmd>();

// 5c. Control-push broadcast (Stage 7 §4.4): unprompted daemon→client
//     notifications, currently just `TargetExited`, mirroring the
//     existing graph-diff broadcast pattern rather than a request/reply.
let (control_push_tx, _) = broadcast::channel::<Arc<ControlResponse>>(16);

// 6. WS server.
tokio::spawn(server::run(config.ws_addr.clone(), connect_tx, target_tx, control_push_tx.clone()));
'''),
    ...para('//',
        r'Two channel types are in play. The path from ingest to the '
        r'graph loop (GraphMsg), the connect-request channel and the '
        r'target-command channel are unbounded mpsc: a slow graph loop '
        r'never blocks a sender, in particular never blocks the pipe '
        r'reader. (That is my reading of the intent; main.rs does not '
        r'spell it out.) The two outbound paths to clients are tokio '
        r'broadcast channels with small fixed capacities, 64 graph '
        r'messages and 16 control pushes. The M4 plan fixes the 64 '
        r'(decision Q5) without giving a reason; server.rs shows the '
        r'effect, a client that falls behind gets a Lagged(n) error '
        r'and loses those messages rather than making the graph loop '
        r'wait. The price of both choices is in the limits section.'),

    ...sec(r'the timer and the ingest task'),
    ...code('rust', 'crates/heaplens-daemon/src/main.rs · ingest task and the tick timer', r'''
// 7. Ingest channel.
let (tx, mut rx) = mpsc::unbounded_channel::<GraphMsg>();

// 8. Ingest task — clone tx before moving it.
let tick_tx = tx.clone();
tokio::spawn(ingest::run(config.pipe_name.clone(), tx));

// 9. Timer task — fires GraphMsg::Tick every tick_ms milliseconds.
let tick_ms = config.tick_ms;
tokio::spawn(async move {
    let mut interval = tokio::time::interval(tokio::time::Duration::from_millis(tick_ms));
    loop {
        interval.tick().await;
        if tick_tx.send(GraphMsg::Tick).is_err() {
            break;
        }
    }
});
'''),
    ...para('//',
        r'The tick is just another message on the same channel as the '
        r'data, not a separate timer arm in the loop. One consequence '
        r'is that ticks and events share a single order, the order in '
        r'which the channel received them, so a diff covers exactly the '
        r'events queued ahead of its Tick. The default tick is 33 ms '
        r'(about 30 Hz, from config.rs).'),

    ...sec(r'state the loop owns'),
    ...code('rust', 'crates/heaplens-daemon/src/main.rs · graph, resolver, session and observability state', r'''
// 10. Graph state.
let mut graph = OwnershipGraph::new();
let mut resolver = Resolver::new();
let mut storm_tracker = StormTracker::new();
let mut warned_sites: std::collections::HashSet<u64> = std::collections::HashSet::new();

// 11. Attach-session state (Stage 7 §3.4: single target at a time).
let mut attached_pid: Option<u32> = None;

// Observability-only state for the Flutter target-diagnostics banner
// (see heaplens_flutter/lib/providers/target_diagnostics_provider.dart).
// None of this is read by phi or anomaly::sweep.
let mut events_received: u64 = 0;
let mut target_pid: Option<u64> = None;
let mut target_name: Option<String> = None;
let mut last_stats_sent = std::time::Instant::now();
const STATS_INTERVAL: std::time::Duration = std::time::Duration::from_millis(1000);
'''),
    ...para('//',
        r'The first four lines are the model. The rest is deliberately '
        r'labelled: events_received, target_pid, target_name and '
        r'last_stats_sent are "Observability-only state for the Flutter '
        r'target-diagnostics banner ... None of this is read by phi or '
        r'anomaly::sweep." The word "Observability-only" opens a '
        r'comment four times in this file and three times in graph.rs. '
        r'It is a design rule stated repeatedly: counters may describe the system, they may never '
        r'feed back into a decision. tests/target_diagnostics_stats.rs '
        r'has a test that exists only to hold the daemon to it.'),

    ...sec(r'events: one dispatch, three kinds'),
    ...code('rust', 'crates/heaplens-daemon/src/main.rs · handling GraphMsg::Events', r'''
msg = rx.recv() => match msg {
    Some(GraphMsg::Events(events)) => {
        // Observability-only: counts every raw event as it
        // arrives, before any diff-visibility filtering — so it
        // stays accurate even for nodes born and freed within
        // the same tick, which drain_diff never surfaces (see
        // its doc comment). Read only by the Stats broadcast
        // below, never by phi or anomaly::sweep.
        events_received += events.len() as u64;
        for ev in &events {
            match ev.kind {
                0 => {
                    graph.on_alloc(ev, &resolver);
                    // Storm detection on alloc events with a non-empty stack.
                    if ev.stack_len > 0
                        && storm_tracker.record(ev.stack[0], ev.ts_nanos, &config)
                        && warned_sites.insert(ev.stack[0])
                    {
                        warn!(
                            addr = ev.stack[0],
                            "allocation storm at site 0x{:x}", ev.stack[0]
                        );
                    }
                }
                1 => graph.on_dealloc(ev.ptr, ev.ts_nanos),
                2 => graph.on_realloc(ev.old_ptr, ev.ptr, ev.size, &resolver),
                _ => {}
            }
        }
    }
'''),
    ...para('//',
        r'ev.kind is matched as a raw u8 (0 alloc, 1 dealloc, 2 realloc), '
        r'mirroring the repr(u8) EventKind in heaplens-protocol; the '
        r'tests copy the same match, which is a small duplication '
        r'accepted for the sake of a loop that stays flat.'),
    blank,
    ...para('//',
        r'The count comes first and on purpose. events_received is '
        r'incremented by the raw length of the frame before any filter, '
        r'so a target that allocates and frees inside one tick, which '
        r'drain_diff never reports, still shows as active. The test '
        r'events_received_counts_events_invisible_to_the_diff builds '
        r'exactly that case: an alloc and a dealloc inside one tick, an '
        r'empty diff, and a Stats message whose events_received is 2.'),
    blank,
    ...para('//',
        r'Storm detection runs on allocs with a non-empty stack. The '
        r'tracker is keyed on ev.stack[0], the raw first frame. '
        r'warned_sites.insert(ev.stack[0]) suppresses repeat warnings, '
        r'and the set is cleared on every Tick, so a storm that '
        r'persists produces at most one warning per site per tick '
        r'(commit 822fd37, 2026-07-02, "per-tick storm warning '
        r'dedup"). A storm is only a log line: the M4 plan states '
        r'"storm detection only emits tracing::warn! — no NodeState '
        r'change for storm".'),
    blank,
    ...para('//',
        r'A caution on that key, from my reading of two files rather '
        r'than from a run. capture.rs says the raw trace "always starts '
        r'inside the shared instrumentation chain", so stack[0] is '
        r'probably the same machinery frame for every allocation. If so, '
        r'the per-site tracker behaves as one process-wide allocation '
        r'rate counter. Nothing in the repository tests the main.rs '
        r'integration of the storm tracker; anomaly_unit.rs tests the '
        r'tracker in isolation with hand-picked addresses.'),

    ...sec(r'symbols and the target session'),
    ...code('rust', 'crates/heaplens-daemon/src/main.rs · Symbols, TargetConnected, TargetDisconnected', r'''
Some(GraphMsg::Symbols(syms)) => {
    for (addr, name, is_machinery) in syms {
        resolver.insert(addr, name, is_machinery);
    }
}
Some(GraphMsg::TargetConnected { pid, name }) => {
    info!("attach session confirmed: pid={pid} name={name}");
    // Also the sole feed for the target-diagnostics stats
    // banner's pid/name — master's separate Handshake
    // message carried the identical (pid, name) pair from
    // the same underlying frame (see msg.rs); folded in
    // here rather than sending it twice.
    target_pid = Some(pid);
    target_name = Some(name);
}
Some(GraphMsg::TargetDisconnected { pid }) => {
    // A pipe disconnect for the *currently tracked* pid means
    // that target exited. The pid check (not just "a pipe
    // closed") is load-bearing: during a target switch, the
    // old target's pipe-close event is detected
    // asynchronously by `ingest.rs` and can arrive after
    // `attached_pid` has already moved on to the newly
    // attached target. Without this check, that stale event
    // would incorrectly clear `attached_pid` and broadcast
    // `TargetExited` for the new target — which just
    // attached successfully and is still running.
    if is_current_target_exit(attached_pid, pid) {
        attached_pid = None;
        target_pid = None;
        target_name = None;
        info!("target pid={pid} exited or disconnected");
        let _ = control_push_tx.send(Arc::new(ControlResponse::TargetExited { pid: pid as u32 }));
    }
}
'''),
    ...para('//',
        r'Symbols are pure bookkeeping: each (addr, name, is_machinery) '
        r'goes into the resolver. Everything φ knows about names '
        r'arrives through this three-line arm, and nothing in the '
        r'daemon resolves a symbol itself (the allocator’s writer '
        r'thread does, off its hot path).'),
    blank,
    ...para('//',
        r'TargetDisconnected carries the pid on purpose. The comment '
        r'explains the race it closes: during a target switch, the '
        r'old target’s pipe-close is noticed asynchronously by '
        r'ingest.rs and "can arrive after attached_pid has already '
        r'moved on to the newly attached target", and without the pid '
        r'check that stale event would clear attached_pid and '
        r'broadcast a TargetExited for a process that just attached '
        r'and is still running. The decision lives in a pure function, '
        r'is_current_target_exit in msg.rs, because the race "only '
        r'reproduces under real async timing" and cannot be forced '
        r'reliably in a fast test.'),

    ...sec(r'the tick: sweep, mark, drain, persist, broadcast'),
    ...code('rust', 'crates/heaplens-daemon/src/main.rs · the Tick arm', r'''
Some(GraphMsg::Tick) => {
    warned_sites.clear();
    // Anomaly sweep — returns ids of nodes whose state changed.
    let max_ts = graph.max_ts_seen;
    // Diagnostic only (opt-in via RUST_LOG=heaplens_daemon=debug,
    // silent at the default "info" level, no behavior change):
    // lets an external observer reconstruct real wall-clock tick
    // cadence during a run, to distinguish steady ~tick_ms sweep
    // timing from queue-backlog draining. Not part of detection.
    debug!(max_ts, "tick");
    storm_tracker.evict_idle(max_ts, &config);
    let changed = sweep(graph.nodes_mut(), max_ts, &config);

    // Observability-only: for nodes that just flipped to
    // Orphan, pair the owner-free ts (recorded on the node
    // by on_dealloc, at the moment it happened) with this
    // tick's ts as the detection ts. sweep() above has
    // already fully decided `changed` and each node's
    // `state` — this only reads that decision, it cannot
    // feed back into it.
    let mut orphan_events: Vec<OrphanEventRecord> = Vec::new();
    for &id in &changed {
        graph.mark_updated(id);
        if let Some(node) = graph.nodes().get(&id) {
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
    if !orphan_events.is_empty() {
        let _ = store_tx.send(StoreMsg::OrphanEvents(orphan_events));
    }

    let diff = graph.drain_diff(&resolver);

    // Forward new/updated nodes to the store.
    if let GraphMessage::Diff { ref add, ref update, .. } = diff {
        let dtos: Vec<_> = add.iter().chain(update.iter()).cloned().collect();
        if !dtos.is_empty() {
            let _ = store_tx.send(StoreMsg::Nodes(dtos));
        }
    }

    // Broadcast non-empty diffs to WS clients.
    if is_non_empty_diff(&diff) {
        let _ = broadcast_tx.send(Arc::new(diff));
    }
'''),
    ...para('//',
        r'The order inside the arm is load-bearing.'),
    ...pt('//', '1. evict_idle, then sweep',
        r'storm_tracker.evict_idle(max_ts, ...) prunes call sites that '
        r'have gone quiet (commit 338abef, 2026-07-06: "StormTracker.'
        r'sites also grew unbounded"). sweep then re-evaluates every '
        r'live node and returns the ids whose state changed.'),
    ...pt('//', '2. mark_updated for each changed id',
        r'A state change is not a graph mutation, so the node is not '
        r'in the updated set yet. Marking it here is what puts an '
        r'orphan transition into the very diff built three lines '
        r'later.'),
    ...pt('//', '3. build the orphan-event records',
        r'For nodes that just became Orphan and carry an owner_free_ts '
        r'(set by on_dealloc), the loop pairs that timestamp with '
        r'max_ts as the detection time and sends an '
        r'OrphanEventRecord to the store. The comment: sweep "has '
        r'already fully decided changed and each node’s state — this '
        r'only reads that decision, it cannot feed back into it".'),
    ...pt('//', '4. drain_diff, then fan out',
        r'The diff goes to the store (adds and updates only, as '
        r'NodeDtos), and, if non-empty, to every WebSocket client '
        r'through the broadcast channel. Empty diffs are never sent; '
        r'is_non_empty_diff at the bottom of the file is the filter.'),
    blank,
    ...para('//',
        r'The debug! line near the top ("tick") was added with the H1 '
        r'measurement (816c732). Its comment says it lets an observer '
        r'"distinguish steady ~tick_ms sweep timing from queue-backlog '
        r'draining". The sentence implies a failure mode the authors '
        r'were worried about: a graph loop that falls behind its '
        r'unbounded channel works through queued ticks back to back. '
        r'The measurement found no such bursts: per the H1 commit '
        r'"0/40 runs show a <5ms gap before the detecting tick; gaps '
        r'cluster at 19-40ms, matching tick_ms=33".'),

    ...sec(r'the stats heartbeat'),
    ...code('rust', 'crates/heaplens-daemon/src/main.rs · Stats on a 1 s cadence', r'''
if last_stats_sent.elapsed() >= STATS_INTERVAL {
    last_stats_sent = std::time::Instant::now();
    let (symbols_resolved, hex_fallback) = graph.symbol_stats(&resolver);
    let stats = GraphMessage::Stats {
        ts: max_ts,
        events_received,
        symbols_resolved,
        hex_fallback,
        target_pid,
        target_name: target_name.clone(),
    };
    let _ = broadcast_tx.send(Arc::new(stats));
}
'''),
    ...para('//',
        r'The target-diagnostics banner in the Flutter app has to '
        r'distinguish "attached, capturing", "attached, no events", '
        r'"no edges" and "unsymbolized". The case it most needs to '
        r'detect, no heap activity, is exactly the case where the '
        r'graph produces no diffs, so stats cannot ride on diffs. The '
        r'comment says it is "decoupled from tick_ms so this is a '
        r'steady heartbeat, not a per-tick spam". The cadence check '
        r'happens inside the Tick arm, so the real interval is 1 s '
        r'rounded up to the next tick.'),
    blank,
    ...para('//',
        r'Stats travel on the same broadcast channel as diffs, typed '
        r'GraphMessage::Stats. That is why is_non_empty_diff has to '
        r'say, explicitly, that Snapshot and Stats are never "diffs" '
        r'(the match arm returns false for both).'),

    ...sec(r'a client connects: snapshot and subscription, atomically'),
    ...code('rust', 'crates/heaplens-daemon/src/main.rs · ConnectRequest', r'''
req = connect_rx.recv() => {
    if let Some(ConnectRequest { reply }) = req {
        // Q6: subscribe BEFORE taking snapshot so no diffs are lost
        // between the two operations (no await between them).
        let diff_rx = broadcast_tx.subscribe();
        let snapshot = graph.snapshot(&resolver);
        let _ = reply.send((snapshot, diff_rx));
    }
},
'''),
    ...para('//',
        r'This is the M4 plan’s decision Q6, "Atomic subscribe+'
        r'snapshot". A new client needs the current state and then every '
        r'later diff, with nothing lost in between. Because the loop is '
        r'single-threaded and there is no await between subscribe() and '
        r'snapshot(), no tick can broadcast a diff in the gap. One '
        r'subtlety follows from the code: the snapshot reflects '
        r'events processed since the last Tick, and the next diff '
        r'will report those same changes again. So the first diff '
        r'after a snapshot can repeat an add or remove the snapshot '
        r'already accounts for, and a client has to apply diffs '
        r'idempotently. (I did not check the Dart side; it is not in '
        r'this crate.)'),

    ...sec(r'attach, detach and the single-target transition'),
    ...para('//',
        r'TargetCmd comes from the WebSocket handler. docs/stage7-'
        r'injection-design.md section 3.4 specifies the transition: '
        r'detach the old target, wait for its pipe to close, clear '
        r'the graph, then attach the new one. The code follows that '
        r'order, with one visible difference noted below.'),
    ...code('rust', 'crates/heaplens-daemon/src/main.rs · TargetCmd::Attach', r'''
Some(TargetCmd::Attach { pid, reply }) => {
    // §3.4: clean single-target transition. Detach the
    // old target first (if any) before touching the new
    // one or the graph.
    if let Some(old_pid) = attached_pid.take() {
        if let Err(e) = injector::detach(old_pid).await {
            warn!("detach of previous target {old_pid} before switching failed: {e}");
            // Continue anyway — refusing to attach the
            // new target over an imperfect old detach
            // would strand the user with no way to
            // switch targets at all.
        }
    }

    // Clear graph state before attaching — but only if
    // `pid` isn't the process the daemon is already
    // observing (typically via its own cooperative
    // pipe connection). Attaching to an *already-known*
    // pid is adding injection on top of the same
    // address space, not switching to a new one — see
    // `should_reset_on_attach`'s doc comment for why
    // resetting in that case silently and permanently
    // breaks symbol resolution for the rest of the
    // session. Broadcast the empty state immediately on
    // a genuine reset: diffs only carry changes, so
    // without this, already-connected clients would keep
    // showing the old target's stale nodes until the new
    // target's own first diff.
    if should_reset_on_attach(target_pid, pid) {
        graph = OwnershipGraph::new();
        resolver = Resolver::new();
        storm_tracker = StormTracker::new();
        warned_sites.clear();
        let empty = graph.snapshot(&resolver);
        let _ = broadcast_tx.send(Arc::new(empty));
    }

    match injector::attach(pid).await {
        Ok(()) => {
            attached_pid = Some(pid);
            let _ = reply.send(Ok(()));
        }
        Err(e) => {
            let _ = reply.send(Err(e));
        }
    }
}
'''),
    ...pt('//', 'a failed detach does not block the switch',
        r'The comment: "refusing to attach the new target over an '
        r'imperfect old detach would strand the user with no way to '
        r'switch targets at all."'),
    ...pt('//', 'the reset is conditional',
        r'should_reset_on_attach(target_pid, pid) decides. Commit '
        r'b649234 (2026-07-26) fixed an unconditional reset. A '
        r'cooperative target such as checkout_service.exe dials the '
        r'daemon itself; attaching to the same pid on top adds '
        r'instrumentation to a process already observed. Resetting '
        r'threw away the resolver, but the target’s writer thread '
        r'dedupes SYMBOLS frames per connection and "has no signal that '
        r'the daemon just forgot everything", so it never re-sent '
        r'addresses it had already reported. A target that reuses a '
        r'small fixed set of allocation sites then had them '
        r'permanently unresolved: "no phi edges, no orphan/hot '
        r'detection, for the rest of the session", with no error. The '
        r'fix is verified, per the commit, live over the real control '
        r'protocol.'),
    ...pt('//', 'a genuine reset is announced',
        r'Diffs only carry changes, so connected clients would keep '
        r'drawing the old target’s nodes until the new target’s first '
        r'diff. The loop broadcasts an empty snapshot immediately, which '
        r'is why the broadcast channel’s element type has to be able to '
        r'carry a Snapshot at all.'),
    ...pt('//', 'where the code departs from the design',
        r'Section 3.4 step 2 says to wait for the existing pipe '
        r'connection to close. The code does not wait on the pipe: it '
        r'relies on injector::detach returning only when the one-shot '
        r'injector process exits, and tolerates a late pipe-close '
        r'through the pid check described above. That is a '
        r'deliberate-looking simplification, but I found no comment '
        r'that says so.'),
    ...code('rust', 'crates/heaplens-daemon/src/main.rs · TargetCmd::Detach', r'''
Some(TargetCmd::Detach { reply }) => {
    match attached_pid.take() {
        Some(pid) => match injector::detach(pid).await {
            Ok(()) => {
                let _ = reply.send(Ok(()));
            }
            Err(e) => {
                // Restore tracking so a retry (or the
                // next attach's own detach-old step)
                // can try again, rather than silently
                // losing track of a still-live target.
                attached_pid = Some(pid);
                let _ = reply.send(Err(e));
            }
        },
        None => {
            let _ = reply.send(Ok(())); // idempotent no-op
        }
    }
}
'''),
    ...para('//',
        r'Detach is idempotent when nothing is attached, and restores '
        r'attached_pid when the injector reports an error, so that '
        r'"a retry (or the next attach’s own detach-old step) can try '
        r'again, rather than silently losing track of a still-live '
        r'target".'),

    ...sec(r'listing processes'),
    ...code('rust', 'crates/heaplens-daemon/src/main.rs · TargetCmd::ListProcesses', r'''
Some(TargetCmd::ListProcesses { reply }) => {
    // Process enumeration does per-process OpenProcess/
    // IsWow64Process2 syscalls (procs.rs) — run it off
    // this task so a slow system doesn't stall the graph
    // loop's other work while it walks the process list.
    let processes = tokio::task::spawn_blocking(procs::list_processes)
        .await
        .unwrap_or_default();
    let _ = reply.send(processes);
}
'''),
    ...para('//',
        r'procs::list_processes does an OpenProcess and IsWow64Process2 '
        r'per process, so it runs under spawn_blocking: the Win32 '
        r'calls are kept off the async worker threads. Note what is '
        r'not claimed: the loop still awaits the result inside its own '
        r'arm, so the graph loop itself pauses for as long as the '
        r'enumeration takes. See the limits.'),

    ...sec(r'shutdown'),
    ...code('rust', 'crates/heaplens-daemon/src/main.rs · ctrl_c and the final store flush', r'''
            _ = tokio::signal::ctrl_c() => {
                info!("shutting down");
                let _ = store_tx.send(StoreMsg::Shutdown);
                break;
            },
        }
    }

    // Drop the sender so the store thread sees Disconnected (or it already
    // received Shutdown from the ctrl_c arm) and flushes its final batch.
    drop(store_tx);
    let _ = store_join.join();

    Ok(())
}
'''),
    ...para('//',
        r'Ctrl-C asks the store thread to flush (StoreMsg::Shutdown), '
        r'leaves the loop, drops its sender and joins the thread. The '
        r'join handle was added in commit 0d465e5 (2026-07-02) with '
        r'the message "preventing data loss on process exit". The test '
        r'store_shutdown_flushes in tests/store_tests.rs covers the '
        r'store half of it.'),

    ...sec(r'how it is tested'),
    ...para('//',
        r'The loop itself has no direct test; main.rs is a binary and '
        r'integration tests link only the library. What is tested is '
        r'what the loop calls, and the decisions it makes were pulled '
        r'out into pure functions in msg.rs so they could be.'),
    ...pt('//', 'tests re-implement the loop',
        r'tests/ws_tests.rs and tests/target_diagnostics_stats.rs each '
        r'contain a run_graph_loop that "mirrors main.rs’s Tick-arm '
        r'handling closely enough", differing in that the stats test '
        r'sends Stats on every tick instead of once a second so the '
        r'test does not need to sleep.'),
    ...pt('//', 'glue is replicated, not shared',
        r'The orphan-record construction in the Tick arm is copied in '
        r'tests/orphan_persistence.rs, whose comment says it '
        r'"replicates that handler’s small glue step". If the two '
        r'drifted, the test would still pass. That is the honest cost '
        r'of keeping main() a binary.'),

    ...sec(r'limits'),
    ...pt('//', 'awaits inside the loop',
        r'ListProcesses, Attach and Detach await inside their match '
        r'arms. In tokio::select!, the body of a chosen arm runs in '
        r'the loop’s own task, so while the injector child is running '
        r'(server.rs says "up to a few seconds") the loop processes no '
        r'events or ticks. Events keep queueing in the unbounded '
        r'channel meanwhile, and the next ticks arrive late and in a '
        r'burst. Nothing here is a bug in the sense of a wrong '
        r'answer, but the 33 ms cadence is not kept during an attach.'),
    ...pt('//', 'unbounded queues',
        r'The 2026-07-22 commits record a peak backlog of about 808k '
        r'queued messages before the index fixes and about 335k '
        r'after, with memory rising under sustained load. Layer 3 '
        r'brought it to tens of thousands and back to zero within '
        r'seconds of detach, but the channel is still unbounded by '
        r'design: a producer faster than the loop is absorbed by '
        r'memory, not by back-pressure.'),
    ...pt('//', 'WebSocket bind failure leaves a spinning loop (my reading)',
        r'server::run returns when the bind fails, which drops the '
        r'only senders of the connect and target channels. Their '
        r'receivers then resolve to None immediately, forever, and '
        r'the select! has no guard for a closed channel. Both arms '
        r'handle None by doing nothing, so the loop would spin at '
        r'full speed while still serving the other arms. A reduced '
        r'test of that select! shape does spin; I did not run the '
        r'daemon with an occupied port.'),
    ...pt('//', 'cooperative exits are quiet',
        r'The TargetExited broadcast and the clearing of target_pid '
        r'and target_name sit inside the is_current_target_exit '
        r'branch, so they happen only for a pid that was attached '
        r'through AttachTarget. A cooperative producer that simply '
        r'disconnects leaves its pid and name in the stats until a '
        r'new target replaces them. (Reading the code; the Flutter '
        r'side may mask it.)'),
    ...pt('//', 'target exit does not call detach',
        r'tests/hook_owner_free_no_crash.rs states it plainly: the '
        r'TargetDisconnected handling "does not call injector::detach '
        r'when a target exits on its own". That is why the multi-'
        r'threaded exit-without-detach hang found on 2026-07-26 was a '
        r'live exposure and not only a test concern.'),
    ...pt('//', 'one target at a time',
        r'attached_pid is an Option, by design: the stage 7 design '
        r'confirms a single-target scope.'),

    ...sec(r'timeline of the file'),
    ...pt('//', '2026-07-01', r'fe90320: bootstrap, mpsc, ingest and timer tasks, graph loop, Ctrl-C.'),
    ...pt('//', '2026-07-02', r'f70f979 adds the store, the broadcast channel, the WebSocket server and connect requests; 822fd37 dedupes storm warnings; 0d465e5 adds the store join handle.'),
    ...pt('//', '2026-07-06', r'338abef: evict_idle once per tick.'),
    ...pt('//', '2026-07-08', r'43fc22e: the Symbols arm, once SYMBOLS frames are no longer discarded.'),
    ...pt('//', '2026-07-16', r'b97b008: OrphanEventRecord creation in the Tick arm for H1.'),
    ...pt('//', '2026-07-17', r'0edc728: events_received, the Stats heartbeat, and a Handshake message (later folded into TargetConnected).'),
    ...pt('//', '2026-07-19', r'724695a: the target channel, TargetCmd handling and the control-push broadcast, ported from the stage 7 branch.'),
    ...pt('//', '2026-07-26', r'b649234: conditional reset on attach.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
