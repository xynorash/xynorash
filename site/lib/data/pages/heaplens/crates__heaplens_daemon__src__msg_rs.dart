import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/src/msg.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'msg.rs — what the daemon’s tasks say to each other'),
    cm('//', r'five message types, two pure decisions, and a race pinned down'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'the channel vocabulary between ingest, graph loop, server and store'),
    kv('language', r'Rust'),
    kv('size', r'175 lines, about 50 of them in-file tests'),
    kv('history', r'9 commits, 2026-07-01 to 2026-07-26'),
    kv('pattern', r'single-owner task + channels + oneshot replies, no locks'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'The Build Spec’s concurrency rule is stated in its list of '
        r'invariants: "No global mutable singletons with locks on any '
        r'hot path. Use channels + single-owner tasks." The daemon is '
        r'that rule in practice. One task, the graph loop in main.rs, '
        r'owns the graph, the resolver and the session state. '
        r'Everything else talks to it by sending a value down a channel. '
        r'msg.rs is where those values are defined, so reading this one '
        r'file tells you every way the rest of the daemon can influence '
        r'the model.'),
    blank,
    ...para('//',
        r'Who sends what, to whom:'),
    ...pt('//', 'GraphMsg',
        r'ingest.rs and the timer task, to the graph loop, over an '
        r'unbounded mpsc.'),
    ...pt('//', 'TargetCmd',
        r'a WebSocket client task in server.rs, to the graph loop, '
        r'each carrying a oneshot sender for the reply.'),
    ...pt('//', 'ConnectRequest',
        r'a new WebSocket client task, to the graph loop, carrying a '
        r'oneshot sender for a snapshot and a diff subscription.'),
    ...pt('//', 'StoreMsg',
        r'the graph loop, to the SQLite thread in store.rs.'),
    ...pt('//', 'OrphanEventRecord',
        r'a payload inside StoreMsg, built by the graph loop at the '
        r'moment a node turns Orphan.'),

    ...sec(r'GraphMsg: the stream into the model'),
    ...code('rust', 'crates/heaplens-daemon/src/msg.rs · GraphMsg', r'''
/// Messages sent from the ingest task to the graph task via mpsc.
pub enum GraphMsg {
    /// A batch of allocation events decoded from a single pipe frame.
    Events(Vec<AllocEvent>),
    /// (addr, resolved name, is_machinery) tuples from a SYMBOLS frame — the
    /// writer resolves and classifies addresses off its own hot path; the
    /// daemon just records the classification into its Resolver.
    Symbols(Vec<(u64, String, bool)>),
    /// Periodic tick from the timer — triggers drain_diff and log emission.
    Tick,
    /// A pipe client completed its HANDSHAKE frame — informational
    /// confirmation that a session actually started for this pid (§4.4).
    /// Also the sole source of `target_pid`/`target_name` for the
    /// target-diagnostics stats banner (main.rs) — master's now-removed
    /// `GraphMsg::Handshake` carried the identical (pid, name) pair from the
    /// same `Frame::Handshake` in ingest.rs; folding it into this variant
    /// avoids sending two messages for one frame.
    TargetConnected { pid: u64, name: String },
    /// The pipe connection for `pid` closed — §4.4's target-exit detection.
    ///
    /// Carries the pid specifically (not just "the pipe closed") because a
    /// target *switch* (`TargetCmd::Attach` while one is already live)
    /// detaches the old target and immediately attaches a new one — the old
    /// target's pipe-close event is detected asynchronously by `ingest.rs`
    /// and can arrive *after* the graph loop has already moved on to
    /// tracking the new pid. Without the pid here, that late event would be
    /// indistinguishable from the new target exiting, incorrectly clearing
    /// `attached_pid` and broadcasting a spurious `TargetExited` for a
    /// target that just successfully attached and is still running.
    TargetDisconnected { pid: u64 },
}
'''),
    ...para('//',
        r'Events and Symbols mirror the wire frames decoded in '
        r'heaplens-protocol (Frame::Events, Frame::Symbols). Tick is the '
        r'timer’s heartbeat, sent through the same channel so that '
        r'data and ticks arrive in one order. The last two variants, '
        r'TargetConnected and TargetDisconnected, are the daemon’s view '
        r'of a producer’s session, and each has a story.'),

    ...sec(r'TargetConnected: one frame, one message'),
    ...para('//',
        r'The HANDSHAKE frame carries the producer’s pid and process '
        r'name. Originally ingest.rs decoded it and threw it away; the '
        r'comment in the first version said "Handshake is '
        r'informational". Two features then wanted it independently. '
        r'The target-diagnostics work (0edc728, 2026-07-17) forwarded '
        r'it as GraphMsg::Handshake to label a banner. The stage 7 '
        r'injection work had its own variant for the same frame, '
        r'TargetConnected, a session-start confirmation (it reached '
        r'this branch in the 724695a port on 2026-07-19). When the two '
        r'branches met, the variants were merged: the doc comment says '
        r'that folding "avoids sending two messages for one frame". '
        r'The merge itself needed a follow-up commit (cd348b6, '
        r'2026-07-21) because two test files "auto-merged cleanly (no '
        r'conflict markers) because they only touch call sites, not '
        r'the definitions that changed".'),

    ...sec(r'the wildcard that swallowed a variant (three times)'),
    ...para('//',
        r'Handshake forwarding was the third entry in a pattern the '
        r'Build Spec now records as a standing rule. The spec lists '
        r'the three: Symbols, then a control-target variant, then '
        r'Handshake forwarding. Commit 91a41f6 (2026-07-17): '
        r'"Handshake forwarding (feat/target-diagnostics) tripped this '
        r'for the third time - a new GraphMsg/GraphMessage/Frame variant '
        r'meeting an old test’s catch-all arm written before that '
        r'variant existed. Cheap insurance against the fourth '
        r'instance." The rule it added to the spec: when adding a '
        r'variant to GraphMsg, GraphMessage or Frame, grep the whole '
        r'test suite for every match on that enum and audit each '
        r'`_ =>` arm. The spec names the failure precisely: the '
        r'wildcard’s fallback is often `break` or "treat as '
        r'disconnect", and it "fires for a message that’s neither '
        r'malformed nor a real end-of-stream". The compiler cannot '
        r'catch this, because a wildcard is exhaustive by construction.'),
    blank,
    ...para('//',
        r'The tests carry the same lesson in comments. In '
        r'tests/cross_process_wire.rs the TargetConnected and '
        r'TargetDisconnected arm is followed by this explanation: the '
        r'HANDSHAKE "must not be treated as end-of-stream by the '
        r'catch-all below (it isn’t a connection close)". In '
        r'tests/hook_self_load_wire.rs the Tick variant is matched '
        r'explicitly, "rather than folded into the wildcard below", '
        r'because it is "the same bug class that broke both files when '
        r'GraphMsg grew two new variants".'),

    ...sec(r'TargetDisconnected and the stale-event race'),
    ...para('//',
        r'The pid in TargetDisconnected looks redundant: the daemon '
        r'only has one pipe client at a time. It is not. The doc '
        r'comment on the variant explains the sequence that makes it '
        r'necessary. Switching targets detaches the old one and '
        r'immediately attaches the new one. The old target’s pipe '
        r'close is noticed "asynchronously by ingest.rs and can arrive '
        r'after the graph loop has already moved on to tracking the '
        r'new pid". An event that only says "the pipe closed" would be '
        r'indistinguishable from the new target exiting, and the loop '
        r'would clear attached_pid and broadcast a spurious '
        r'TargetExited for a process that just attached and is '
        r'running fine.'),
    blank,
    ...para('//',
        r'The rule that resolves it is one line.'),
    ...code('rust', 'crates/heaplens-daemon/src/msg.rs · is_current_target_exit', r'''
/// Whether a `TargetDisconnected { pid }` event (see its doc comment above)
/// should be treated as "the currently-attached target exited" — i.e.
/// whether `attached_pid` should be cleared and `TargetExited` broadcast.
///
/// Pulled out as a small, pure, directly-testable function specifically
/// because the race it guards against — a *stale* disconnect for an old
/// target arriving after a switch has already moved `attached_pid` on to a
/// new one — only reproduces under real async timing in the full daemon,
/// which is not something a fast, deterministic test can reliably force.
/// Pinning the actual decision rule down here means the invariant survives
/// even if nobody manages to reproduce the timing again.
pub fn is_current_target_exit(attached_pid: Option<u32>, disconnected_pid: u64) -> bool {
    attached_pid.map(u64::from) == Some(disconnected_pid)
}
'''),
    ...para('//',
        r'Its doc comment gives the reason for pulling a one-liner out '
        r'into a named, public function: the race it guards against '
        r'"only reproduces under real async timing in the full daemon, '
        r'which is not something a fast, deterministic test can '
        r'reliably force. Pinning the actual decision rule down here '
        r'means the invariant survives even if nobody manages to '
        r'reproduce the timing again." That is a small, general '
        r'technique worth stealing: when a concurrency bug cannot be '
        r'made to happen on demand, test the decision it turns on, '
        r'not the timing.'),
    ...code('rust', 'crates/heaplens-daemon/src/msg.rs · the two cases that matter', r'''
#[test]
fn stale_disconnect_for_a_pid_that_is_no_longer_attached_is_ignored() {
    // The exact race this guards against: a switch already moved
    // `attached_pid` on to a new target (9999) by the time the OLD
    // target's (4242) disconnect event is processed. Must not be
    // mistaken for the new target exiting.
    assert!(!is_current_target_exit(Some(9999), 4242));
}

#[test]
fn disconnect_for_the_new_target_after_a_switch_is_still_a_real_exit() {
    assert!(is_current_target_exit(Some(9999), 9999));
}
'''),
    ...para('//',
        r'The test comments name the scenario with the actual pids '
        r'(old target 4242, new target 9999). A stale disconnect for '
        r'4242 while 9999 is attached is ignored; a disconnect for '
        r'9999 is a real exit. The other two tests cover the matching '
        r'pid and the no-target-attached case.'),

    ...sec(r'should_reset_on_attach: the bug that stayed silent'),
    ...para('//',
        r'The second pure function exists because of the most '
        r'expensive kind of bug: one that produces no error. Until '
        r'2026-07-26, TargetCmd::Attach always cleared the graph, '
        r'resolver and storm tracker before injecting. For a '
        r'genuinely new process that is correct (the Stage 7 design '
        r'section 3.4: "merging its nodes into the previous target’s '
        r'topology would produce a graph that mixes two programs’ '
        r'allocations into one nonsensical structure"). But '
        r'checkout_service.exe dials the daemon by itself through its '
        r'#[global_allocator]. Attaching to the same pid adds '
        r'injection on top of a process already being observed, so '
        r'the reset discarded symbols the producer would never '
        r'resend:'),
    ...pt('//', 'the producer side',
        r'the writer thread’s symbol_cache dedupes SYMBOLS frames '
        r'within a connection, so it resends nothing it already '
        r'reported. (It does clear that cache when it reconnects; this '
        r'case is a live connection that the daemon did not drop.)'),
    ...pt('//', 'the daemon side',
        r'a target that reuses a small fixed set of allocation sites '
        r'ended up with those addresses permanently unresolved, '
        r'giving "no phi edges, no orphan/hot detection, for the rest '
        r'of the session, without ever knowing anything is wrong".'),
    ...pt('//', 'the evidence',
        r'confirmed against checkout_service.exe; the fix was verified '
        r'live through the real control protocol, with symbols '
        r'staying resolved and orphan and hot transitions firing '
        r'through the attach (commit b649234).'),
    ...code('rust', 'crates/heaplens-daemon/src/msg.rs · should_reset_on_attach (trimmed)', r'''
/// Whether a `TargetCmd::Attach { pid, .. }` should clear graph/resolver
/// state before injecting.
///
...
pub fn should_reset_on_attach(current_target_pid: Option<u64>, pid: u32) -> bool {
    current_target_pid != Some(pid as u64)
}
'''),
    ...para('//',
        r'The parameter is the daemon’s target_pid, set by the most '
        r'recent TargetConnected, not attached_pid. The distinction is '
        r'the point: target_pid says who is sending data right now, '
        r'by either route, and the doc comment is explicit that the '
        r'daemon "doesn’t distinguish" a cooperative handshake from an '
        r'injected hook’s handshake. If the requested pid is the '
        r'sender, nothing about the address space is new.'),
    ...code('rust', 'crates/heaplens-daemon/src/msg.rs · attach_reset_tests', r'''
#[cfg(test)]
mod attach_reset_tests {
    use super::should_reset_on_attach;

    #[test]
    fn attaching_to_a_pid_already_being_observed_does_not_reset() {
        // The exact checkout_service.exe scenario: already cooperatively
        // connected (target_pid == 4242), then Attach is requested for the
        // same pid.
        assert!(!should_reset_on_attach(Some(4242), 4242));
    }

    #[test]
    fn attaching_to_a_different_pid_resets() {
        assert!(should_reset_on_attach(Some(4242), 9999));
    }

    #[test]
    fn attaching_with_no_prior_target_resets() {
        assert!(should_reset_on_attach(None, 9999));
    }
}
'''),
    ...para('//',
        r'The three tests are the truth table of the rule: same pid '
        r'does not reset, different pid resets, no prior target '
        r'resets. The first test’s comment names the exact scenario: '
        r'"already cooperatively connected (target_pid == 4242), then '
        r'Attach is requested for the same pid".'),

    ...sec(r'TargetCmd and ConnectRequest: asking the owner'),
    ...code('rust', 'crates/heaplens-daemon/src/msg.rs · TargetCmd', r'''
/// Messages sent from WS control-request handling (`server.rs`) to the
/// graph task, which is the single owner of both graph state (so it can
/// clear it on a target switch, §3.4) and the "which pid is currently
/// attached" session state.
pub enum TargetCmd {
    ListProcesses { reply: oneshot::Sender<Vec<ProcessInfo>> },
    Attach { pid: u32, reply: oneshot::Sender<Result<(), String>> },
    Detach { reply: oneshot::Sender<Result<(), String>> },
}
'''),
    ...code('rust', 'crates/heaplens-daemon/src/msg.rs · ConnectRequest', r'''
/// Request sent to the graph task when a new WebSocket client connects.
/// The graph task replies with a snapshot and a broadcast receiver for diffs.
pub struct ConnectRequest {
    pub reply: oneshot::Sender<(GraphMessage, broadcast::Receiver<Arc<GraphMessage>>)>,
}
'''),
    ...para('//',
        r'Because only the graph loop may read the graph, a client '
        r'that wants something from it cannot call a function; it '
        r'sends a message that includes a oneshot channel for the '
        r'answer, then awaits the receiver. TargetCmd uses '
        r'Result<(), String> replies, and an error string becomes the '
        r'message field of the AttachResult or DetachResult that '
        r'server.rs sends back to the client. ConnectRequest '
        r'returns two things at once: a snapshot and a broadcast '
        r'receiver. Building both inside the loop, with no await '
        r'between them, is what makes the pair atomic (decision Q6 of '
        r'the M4 plan); the receiver is created first, then the '
        r'snapshot, so nothing broadcast afterwards can be missed.'),
    blank,
    ...para('//',
        r'One width mismatch is visible in the types and worth '
        r'knowing: TargetCmd carries pid as u32, while '
        r'GraphMsg::TargetConnected and TargetDisconnected carry u64 '
        r'(the HANDSHAKE frame’s pid field is u64). is_current_target_'
        r'exit and should_reset_on_attach each convert at the '
        r'boundary instead of changing either side.'),

    ...sec(r'OrphanEventRecord and StoreMsg: persistence as messages'),
    ...code('rust', 'crates/heaplens-daemon/src/msg.rs · OrphanEventRecord and StoreMsg', r'''
/// One node's orphan-state transition, captured at the instant the
/// transition happens. Both timestamps come straight from data the daemon
/// already has in hand — `owner_free_ts_ns` from the dealloc event that
/// orphaned the node (`AllocEvent::ts_nanos`, threaded through
/// `OwnershipGraph::on_dealloc`), `orphan_detected_ts_ns` from
/// `OwnershipGraph::max_ts_seen` at the tick where `anomaly::sweep` flipped
/// the node's state. Neither is inferred or measured wall-clock side —
/// this exists purely so H1 (detection-latency measurement) has a real
/// pair of timestamps to difference, instead of a workload-side proxy.
pub struct OrphanEventRecord {
    pub node_id: u64,
    pub owner_free_ts_ns: u64,
    pub orphan_detected_ts_ns: u64,
    pub tau_ms: u64,
}

/// Messages sent to the store task.
pub enum StoreMsg {
    /// A batch of node snapshots to persist.
    Nodes(Vec<NodeDto>),
    /// A batch of orphan-transition events to persist.
    OrphanEvents(Vec<OrphanEventRecord>),
    /// Trigger an early commit of the current batch (used in tests).
    Flush,
    /// Commit remaining batch and exit the store thread.
    Shutdown,
}
'''),
    ...para('//',
        r'The record is the H1 measurement’s raw material. Its doc '
        r'comment is exact about where each timestamp comes from: '
        r'owner_free_ts_ns from "the dealloc event that orphaned the '
        r'node (AllocEvent::ts_nanos, threaded through '
        r'OwnershipGraph::on_dealloc)", orphan_detected_ts_ns from '
        r'"OwnershipGraph::max_ts_seen at the tick where '
        r'anomaly::sweep flipped the node’s state". Neither is a '
        r'daemon wall-clock reading, "this exists purely so H1 '
        r'(detection-latency measurement) has a real pair of '
        r'timestamps to difference, instead of a workload-side proxy". '
        r'tau_ms rides along in each record, which lets a stored row '
        r'carry its own tau into the latency formula.'),
    blank,
    ...para('//',
        r'StoreMsg has four variants. Flush is documented as "used in '
        r'tests"; production code relies on the store thread’s own '
        r'100 ms deadline. Shutdown exists so main.rs can ask for a '
        r'final commit before it joins the thread. The store thread '
        r'also exits when the channel disconnects, so Shutdown is an '
        r'explicit request, not the only exit.'),

    ...sec(r'how it is tested'),
    ...para('//',
        r'Seven unit tests live in this file in two modules, '
        r'attach_reset_tests (3) and target_disconnect_tests (4). All '
        r'seven are the two pure functions’ truth tables. The channel '
        r'types themselves have no tests and need none: they are '
        r'exercised by every integration test that builds a graph '
        r'loop, which is why a change to a variant breaks tests loudly '
        r'at compile time, at least where the match is exhaustive.'),

    ...sec(r'limits'),
    ...pt('//', 'messages are matched by pid alone',
        r'Both functions compare pids. A process that exited and had '
        r'its pid reused by an unrelated process would look like the '
        r'same target. The window is small in practice, but nothing '
        r'here guards it.'),
    ...pt('//', 'no way to tell injected from cooperative',
        r'The doc comment on should_reset_on_attach says so itself. '
        r'The daemon sees a handshake and a pid, never the capture '
        r'mechanism. That is the right simplicity for the current '
        r'rules and a limit for any future rule that cares.'),
    ...pt('//', 'senders ignore failures',
        r'Throughout main.rs, sends are written `let _ = tx.send(...)`. '
        r'A dropped receiver is treated as "nobody is listening", '
        r'which is correct for broadcast and for shutdown, and quietly '
        r'lossy for a store thread that has died.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
