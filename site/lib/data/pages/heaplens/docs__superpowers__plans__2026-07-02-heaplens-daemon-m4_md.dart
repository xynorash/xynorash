import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/docs/superpowers/plans/2026-07-02-heaplens-daemon-m4.md',
  lines: [
    heading('# heaplens-daemon M4 Implementation Plan'),
    blank,
    ...text('The plan that turned a graph into a product: it '
        'teaches the daemon to recognise orphans, hot clusters '
        'and storms, to remember what it saw in SQLite, and to '
        'tell a UI over a WebSocket. It differs from the earlier '
        'plans in one way that matters: it opens with six locked '
        'decisions, each one a trade-off that later code had to '
        'live with.'),
    blank,
    kv('role', 'Stage 4 build plan: anomalies, persistence, WebSocket (M4)'),
    kv('date', 'dated 2026-07-02, first committed 2026-07-08 (43fc22e)'),
    kv('size', '488 lines · 6 locked decisions · 9 tasks'),
    kv('executed', '07:34 to 08:33 on 2026-07-02, 13 commits'),
    kv('branch', 'dev/phase_4 from 489b5ef; merged 2026-07-06 (3b6b4a2)'),

    ...sec('decisions before tasks'),
    ...text('The header carries a base commit and a section '
        'called Locked Design Decisions. Where the earlier plans '
        'put reasoning into prose around the tasks, this one '
        'front-loads it. Six questions had been asked and '
        'answered, with three refinements; the answers are '
        'stated as rules the executor may not reopen.'),
    ...bullet('Q1, persistence takes processed nodes',
        'the store receives NodeDto values from drain_diff, never '
        'raw events. Storage is decoupled from the capture '
        'format.'),
    ...bullet('Q2, batched writes',
        'one dedicated task owns the SQLite connection, collects '
        'rows for 100 ms, then commits in one transaction.'),
    ...bullet('Q3, time is the producer’s',
        'orphan age uses a rolling maximum of event timestamps. '
        'Covered next.'),
    ...bullet('Q4, orphan wins over hot',
        'the sweep checks orphan first and skips the hot test '
        'for orphans.'),
    ...bullet('Q5, fan-out by broadcast',
        'a tokio broadcast channel of capacity 64 carries diffs '
        'from the graph task to every connected client.'),
    ...bullet('Q6, snapshot and subscribe together',
        'covered below.'),

    ...sec('Q3: never read the clock'),
    ...text('The decision with the largest consequences is the '
        'one that sounds smallest. How old is a node? The answer '
        'the plan locks is “now” minus the node’s timestamp, '
        'where now is the newest timestamp the daemon has seen, '
        'not the daemon’s wall clock:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-02-heaplens-daemon-m4.md · Q3 (trimmed)', r'''
  is the "now" for orphan age: `age = max_ts_seen - node.ts`. Never use daemon wall-clock.
  Events are NOT guaranteed ts-ordered across producer threads, so always `max()`, never assign.'''),
    ...text('The reasoning is sound and unusual. Every timestamp '
        'in the system comes from one clock, the producer’s, so '
        'detection is deterministic, replayable from a recording, '
        'and immune to scheduling jitter inside the daemon. And '
        'because several producer threads feed the stream, events '
        'can arrive out of order, so the update must be a maximum, '
        'never an assignment. The code is exactly that:'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · on_alloc', r'''
        self.max_ts_seen = self.max_ts_seen.max(ev.ts_nanos);'''),
    ...text('Now read what the plan says in Task 5 about where '
        'the update goes. The decision says every event, the task '
        'says otherwise, in a paragraph that begins with a '
        'correction:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-02-heaplens-daemon-m4.md · Task 5 (trimmed)', r'''
Actually: `on_dealloc` doesn't have a ts parameter. Keep `max_ts_seen` update only in
`on_alloc` and `on_realloc` (which have `AllocEvent` structs with `ts_nanos`). Dealloc
events carry no ts. Document this limitation.'''),
    ...text('Two things are wrong with that sentence and one is '
        'right. Wrong: dealloc events do carry a timestamp. '
        'record() stamps every event, including frees, and the '
        'protocol’s event struct has one field for it. The '
        'accurate statement is that on_dealloc was written without '
        'taking a timestamp parameter. Also wrong, mildly: '
        'on_realloc does not update the maximum either; only '
        'on_alloc does, and the final code keeps it that way. '
        'Right: the limitation is real, and it was documented.'),
    ...text('That small decision reaches a long way. Because the '
        'daemon’s clock advances only when an allocation arrives, '
        'a program that stops allocating stops time. An orphan '
        'is flagged only when some later allocation drags the '
        'clock past the threshold. The consequence is visible in '
        'the repository’s only benchmark: the H1 harness header '
        'says its workload keeps allocating “so the daemon keeps '
        'receiving events (max_ts_seen only advances on alloc, '
        'never on dealloc”, and the measured latency is largely '
        'the gap to the next event. A one-line limitation in a '
        'plan became the dominant term in a measurement two '
        'weeks later. See docs/bench_results/h1_latency.csv.'),

    ...sec('Q6: closing a gap between snapshot and stream'),
    ...text('A WebSocket client must receive the current graph '
        'and then every change after it, with nothing missing and '
        'nothing duplicated. If the server builds a snapshot and '
        'then subscribes to the diff channel, a diff can be '
        'broadcast in between and lost. If it subscribes first '
        'and then builds the snapshot, no diff is lost, and any '
        'diff already in the receiver is at worst redundant. The '
        'plan locks the second order and demands that both happen '
        'in the same turn of the graph task so nothing can '
        'interleave. The code carries the rule as a comment:'),
    ...code('rust', 'crates/heaplens-daemon/src/main.rs · connect request', r'''
                    // Q6: subscribe BEFORE taking snapshot so no diffs are lost
                    // between the two operations (no await between them).
                    let diff_rx = broadcast_tx.subscribe();
                    let snapshot = graph.snapshot(&resolver);'''),
    ...text('Because the graph task is the sole owner of the '
        'graph, “the same turn” is a guarantee the language gives '
        'for free: there is no await between the two lines, so '
        'nothing else on that task runs. A lock-based design '
        'would need a critical section here. Ownership by one '
        'task made the invariant a code-reading exercise.'),
    ...text('One behaviour the plan describes and the later plan '
        'misremembers. For a client that falls behind the 64-slot '
        'channel, the plan says to log a warning and carry on: '
        '“some diffs dropped — this is acceptable”. The code does '
        'so:'),
    ...code('rust', 'crates/heaplens-daemon/src/server.rs · diff forwarding', r'''
                        warn!("WS client {peer} lagged by {n} diffs — some dropped");
                        // Continue: keep the connection alive, just note the gap.'''),
    ...text('The Flutter M5 plan, written four days later, says '
        'the opposite: “the daemon disconnects lagged clients by '
        'design (M4 Q6)”, and builds its reconnect logic on the '
        'idea that a reconnect yields a fresh snapshot. The '
        'reconnect logic is sound for a dropped connection. But a '
        'lagged client is not disconnected; it keeps the '
        'connection, misses diffs, and nothing resends a '
        'snapshot. With 33 ms ticks, 64 slots are about two '
        'seconds of slack, so the situation needs a UI stalled '
        'for that long, and no test covers it. Either the '
        'server should close a lagged socket, or the client '
        'should be told it lagged. In server.rs as it stands, '
        'neither happens.'),

    ...sec('the constraints a plan can enforce'),
    ...text('The global constraints list reads like a code '
        'review checklist, and several are about what is '
        'deliberately not built:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-02-heaplens-daemon-m4.md · Global Constraints (trimmed)', r'''
- No `unwrap()`/`expect()` in non-test code (use `?` or `tracing::warn!` + continue).
- No magic numbers in logic — all thresholds from `Config`.
- `NodeState::Freed` is NOT emitted in M4. Only Healthy, Orphan, Hot.
- storm detection only emits `tracing::warn!` — no NodeState change for storm.'''),
    ...text('Reading them against the repository: the Freed '
        'variant is still never emitted, as the plan said it '
        'would not be; a freed node leaves through the diff’s '
        'remove list and the UI animates it away. Storm detection '
        'still only warns. The no-magic-numbers rule produced the '
        'config table in Task 1, six new fields (eight in all) with defaults and '
        'environment overrides, which is how the thresholds in '
        'the H1 harness can be varied without a rebuild.'),
    blank,
    ...text('The no-unwrap rule is checkable, and it holds: every '
        'unwrap() and expect() in the daemon’s source files sits '
        'inside a cfg(test) module. Only unwrap_or_else fallbacks '
        'remain in the running code, which the rule permits.'),

    ...sec('the sweep, as planned and as built'),
    ...text('Task 2 specifies the anomaly sweep with a '
        'precision that the final code kept. The orphan '
        'condition is a conjunction of three facts:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-02-heaplens-daemon-m4.md · Task 2, orphan', r'''
   - Condition: `node.live && node.owner.is_none() && node.had_owner_once`
     `&& max_ts_seen.saturating_sub(node.ts) > config.tau_ms * 1_000_000`'''),
    ...text('And the built version is that, with the Q4 order '
        'made explicit by an if-chain:'),
    ...code('rust', 'crates/heaplens-daemon/src/anomaly.rs · sweep() (trimmed)', r'''
        let is_orphan = node.owner.is_none()
            && node.had_owner_once
            && max_ts_seen.saturating_sub(node.ts) > config.tau_ms * 1_000_000;
        let new_state = if is_orphan {
            NodeState::Orphan
        } else if is_hot {
            NodeState::Hot
        } else {
            NodeState::Healthy
        };'''),
    ...text('Two details deserve attention. First, saturating_sub: '
        'the maximum includes every node’s own timestamp, so the '
        'subtraction should not underflow, but a wrapped u64 '
        'would read as an enormous age and flag a healthy node, '
        'so the defensive form is worth its one word. Second, the final '
        'else. The plan never mentions a reset to Healthy. The '
        'first implementation could only move nodes into Hot or '
        'Orphan; the commit that guarded the assignments (6bd9d6a) '
        'left a TODO for the missing path, and on 2026-07-06 '
        '(338abef) the sweep was changed so that every live node '
        'is re-evaluated each pass. A cluster that shrinks now '
        'heals; an orphan stays orphan because its predicate '
        'cannot become false.'),
    ...text('The plan has another visible revision. Task 2 '
        'first describes storm tracking as part of the sweep, '
        'then stops itself:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-02-heaplens-daemon-m4.md · Task 2', r'''
Actually, revise: the storm tracker state should live outside this function, owned by the
graph task. Add a separate `pub struct StormTracker` in `anomaly.rs`:'''),
    ...text('That correction is the whole architecture in one '
        'move: the sweep is a pure function over nodes, and '
        'anything with its own memory lives in a struct owned by '
        'the one task that is allowed to hold state. A storm is a '
        'rate, which is a property of a site over a time window, '
        'not of any node, so it cannot be computed inside a '
        'sweep of nodes.'),
    ...text('Config says one more thing on the page, and the '
        'comment in the code gets it wrong. config.rs describes '
        'tau_ms as an exponential moving average time constant. '
        'The sweep uses it as a plain age threshold, as the Build '
        'Spec and every test treat it. The doc comment is a '
        'leftover from an earlier idea and misleads anyone who '
        'reads the file first.'),

    ...sec('persistence and the 100 ms window'),
    ...text('The store task is specified in four steps: own the '
        'connection on a dedicated thread, collect for 100 ms, '
        'commit in one transaction, flush early on request, and '
        'commit remaining rows on shutdown. The plan makes an '
        'implementation choice a reviewer would otherwise ask '
        'about: use a dedicated std thread with a std channel '
        'bridged from the async side, so a blocking database '
        'call never stalls the runtime.'),
    ...text('Review found the first version’s subtle defect (0d465e5). '
        'A receive with a timeout per message restarts its clock '
        'with every arrival, so a sustained stream of allocation '
        'bursts would postpone the commit forever. The fix is a '
        'fixed deadline, visible in the code as a comment that is '
        'a warning to the next editor:'),
    ...code('rust', 'crates/heaplens-daemon/src/store.rs · batching', r'''
                    // Do NOT reset deadline — let it fire at the fixed interval.'''),
    ...text('The same commit fixed two quieter problems. The '
        'store thread now returns a join handle so that main can '
        'wait for the final batch at shutdown, preventing data '
        'loss on exit. And the state column is written with the '
        'serde representation (“healthy”), not Rust’s Debug '
        'format (“Healthy”), so a row in the database and a '
        'message on the wire spell the state the same way.'),

    ...sec('order of work and what each task was tested by'),
    ...text('The plan ends with its dependency graph in two '
        'sentences, which is the right amount: tasks 1 to 4 '
        '(config, anomaly, store, server) are independent files '
        'with minimal coupling, task 5 needs the anomaly API, '
        'task 6 needs 3 to 5, tasks 7 and 8 need 6, task 9 is the '
        'final sweep. It could be executed serially or fanned '
        'out. The history shows the former, one after another in '
        'fifty-nine minutes.'),
    ...bullet('anomaly (Task 2)',
        'six unit tests planned, eight present: orphan after tau, '
        'not orphan before it, hot at the threshold, orphan wins '
        'over hot, storm detected, storm window evicts. Added '
        'later: hot resets to healthy, idle sites are pruned.'),
    ...bullet('store (Task 3)',
        'three: rows inserted, batching on the timer with no '
        'flush, flush on shutdown. The plan notes that an '
        'in-memory SQLite database is per connection and could '
        'not be queried from a second one, so tests use a '
        'temporary file.'),
    ...bullet('WebSocket (Task 7)',
        'four, all present: the first message is a snapshot; a '
        'diff follows an allocation; snapshot and diff are '
        'consistent (an id removed was in the snapshot); two '
        'clients both receive a snapshot.'),
    ...bullet('end to end (Task 8)',
        'the cross-process test gains a WebSocket snapshot '
        'assertion. The plan asserts structure only, because '
        '“anomaly state depends on timing”.'),
    blank,
    ...text('The acceptance criteria are phrased as observable '
        'facts, which is the useful form: a client at '
        'ws://127.0.0.1:9999 sees a snapshot then diffs; a SQLite '
        'file appears and fills; an orphan appears with state '
        '“orphan” after tau elapses; a hot cluster appears with '
        'state “hot” past the threshold.'),

    ...sec('limits, and what to take from it'),
    ...bullet('a plan committed late',
        'this plan is dated July 2 and entered the repository on '
        'July 8, inside the commit that also changed φ and added '
        'the launcher. It is a record of intent, reconstructed '
        'rather than a contemporaneous artefact; the commits on '
        'July 2 already follow it.'),
    ...bullet('two statements to distrust',
        'that dealloc events carry no timestamp, and (in the '
        'following plan) that lagged clients are disconnected.'),
    ...bullet('growth detection was dropped',
        'the Build Spec’s growth-rate heuristic is not in this '
        'plan at all. The plan’s config table lists a hot-cluster '
        'fan-out threshold of 32 in its place, which is what the '
        'code uses.'),
    ...bullet('rule of thumb',
        'write the decisions that would be expensive to reopen at '
        'the top, with the reason beside each. When a later '
        'document contradicts one, you can tell which is wrong.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
