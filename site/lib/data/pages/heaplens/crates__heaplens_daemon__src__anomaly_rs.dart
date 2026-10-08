import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/src/anomaly.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'anomaly.rs — deciding which nodes are suspicious'),
    cm('//', r'one pure sweep, one precedence rule, one rate tracker'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'classifies live nodes as healthy, hot or orphan; tracks storms'),
    kv('language', r'Rust, no I/O, no locks'),
    kv('size', r'112 lines of code and docs; tests in tests/anomaly_unit.rs'),
    kv('history', r'4 commits, 2026-07-02 to 2026-07-06'),
    kv('time source', r'max_ts_seen, the stream’s own clock'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'The graph says who owns what. Nothing in it says which of those '
        r'facts is worth showing to a person. anomaly.rs is the layer '
        r'that turns structure into signal, and it does so with exactly '
        r'two predicates and one tracker:'),
    ...pt('//', 'Orphan',
        r'a node that had an owner, lost it, and has been alive longer '
        r'than tau. The leak signal.'),
    ...pt('//', 'Hot',
        r'a node with more than hot_cluster_threshold live children. '
        r'The growing-cluster signal.'),
    ...pt('//', 'storm',
        r'an allocation site whose rate in a window exceeds a '
        r'threshold. A log line only; it never changes a NodeState.'),
    blank,
    ...para('//',
        r'The file is short on purpose. The M4 plan that specified it '
        r'sets the tone: "No magic numbers in logic — all thresholds '
        r'from Config", and "YAGNI: implement exactly what each task '
        r'specifies". The interesting part is not the amount of code; '
        r'it is how many bugs and design decisions fit in 112 lines.'),

    ...sec(r'what the spec asked for, and what was built'),
    ...para('//',
        r'docs/HeapLens_Build_Spec.md section 5.5 describes three '
        r'heuristics. Orphan is "node.live && node.owner.is_none() && '
        r'had_owner_once && (now - node.ts) > tau", which is what '
        r'shipped. Hot, in the spec, is a rate: for each connected '
        r'component, "if total size grew > growth_pct over the last '
        r'window". Storm is "if allocations from one symbol exceed '
        r'storm_rate per second".'),
    blank,
    ...para('//',
        r'The implementation of Hot is simpler and structural: '
        r'edges_out.len() > hot_cluster_threshold. No components, no '
        r'growth percentage, no window. The Build Spec’s later '
        r'section on structural predicates owns that decision in '
        r'plain words: "hot_cluster_threshold (default 32, '
        r'HEAPLENS_HOT_THRESHOLD env override): an empirically-chosen '
        r'fan-out heuristic, not a value derived from any model. State '
        r'this plainly rather than implying derivation." And in the '
        r'jury Q&A for "why 32? why 5 seconds?": "Both configurable, '
        r'empirically-chosen, structural (not rate-based) heuristics '
        r'— not derived values."'),

    ...sec(r'sweep: one pass, one decision per node'),
    ...code('rust', 'crates/heaplens-daemon/src/anomaly.rs · sweep', r'''
/// Run one anomaly sweep over all live nodes. Returns the ids of nodes whose
/// state changed this pass.
///
/// Every live node is re-evaluated against the full predicate chain each
/// sweep (Q4 invariant):
///   1. Orphan — checked first; wins if matched.
///   2. Hot — only evaluated when Orphan did not match.
///   3. Otherwise — Healthy. This is the reset path: a node whose Hot
///      predicate no longer holds (e.g. its cluster shrank back under
///      threshold) returns to Healthy on the next sweep. Orphan is
///      effectively sticky not because state is frozen, but because its
///      predicate (`owner.is_none() && had_owner_once`, age monotonically
///      increasing) cannot become false once true.
///
/// Storm detection is handled separately via [`StormTracker::record`] and
/// does not set `NodeState`.
pub fn sweep(nodes: &mut HashMap<u64, Node>, max_ts_seen: u64, config: &Config) -> Vec<u64> {
    let mut changed: Vec<u64> = Vec::new();

    for node in nodes.values_mut() {
        if !node.live {
            continue;
        }

        let is_orphan = node.owner.is_none()
            && node.had_owner_once
            && max_ts_seen.saturating_sub(node.ts) > config.tau_ms * 1_000_000;
        let is_hot = node.edges_out.len() > config.hot_cluster_threshold;

        let new_state = if is_orphan {
            NodeState::Orphan
        } else if is_hot {
            NodeState::Hot
        } else {
            NodeState::Healthy
        };

        if node.state != new_state {
            node.state = new_state;
            changed.push(node.id);
        }
    }

    changed
}
'''),
    ...para('//',
        r'The function takes the node map directly, not the graph '
        r'(the M4 plan: "a mutable reference to the node map (not the '
        r'full graph struct)"), which keeps it testable with a '
        r'hand-built HashMap of Nodes and nothing else. It returns the '
        r'ids whose state changed so the caller can mark them updated '
        r'and have the change ride in the very next diff; main.rs does '
        r'exactly that, between sweep and drain_diff.'),
    blank,
    ...para('//',
        r'Three things in the body are worth slowing down for.'),
    ...pt('//', 'every live node is re-evaluated, every sweep',
        r'There is no incremental bookkeeping, no dirty set. The '
        r'doc comment calls this the "Q4 invariant". The cost is one '
        r'linear pass over the live nodes every tick (33 ms by '
        r'default). The commit history shows no measurement of that '
        r'pass at large node counts; the 2026-07-22 profiles that '
        r'found other costs dominating (see graph.rs) imply it was not '
        r'the bottleneck for the workloads they ran.'),
    ...pt('//', 'only transitions are reported',
        r'if node.state != new_state guards the push. Without it every '
        r'orphan would be reported as changed on every pass and would '
        r'ride in every diff forever.'),
    ...pt('//', 'the age is the child’s age',
        r'max_ts_seen.saturating_sub(node.ts) is the time since the '
        r'orphan candidate was itself allocated, not the time since its '
        r'owner was freed. A child orphaned long after it was born is '
        r'eligible on the very next sweep. saturating_sub protects the '
        r'case where an event arrives with a timestamp ahead of the '
        r'rolling maximum; the age is then zero, not a wrapped huge '
        r'number.'),

    ...sec(r'precedence: orphan wins over hot'),
    ...para('//',
        r'A node can satisfy both predicates at once: an owner freed '
        r'while it still has more than 32 children. The M4 plan settled '
        r'the question as decision Q4, "Orphan wins over Hot", and '
        r'asked for the order to be commented in code. In the first '
        r'version that was literally a `continue` after tagging the '
        r'orphan; since 338abef it is the shape of the if/else chain, '
        r'which makes the precedence impossible to bypass by editing '
        r'one branch.'),
    blank,
    ...para('//',
        r'Why orphan outranks hot is a product argument more than a '
        r'technical one: an orphaned node is a probable leak, and a '
        r'leak is the thing the tool exists to find, while a large fan-'
        r'out is only a candidate for attention. The test pins it:'),
    ...code('rust', 'crates/heaplens-daemon/tests/anomaly_unit.rs · orphan_wins_over_hot', r'''
/// When a node satisfies both Orphan and Hot conditions, Orphan must win (Q4).
#[test]
fn orphan_wins_over_hot() {
    let config = test_config();
    let max_ts_seen = config.tau_ms * 1_000_000 + 1;
    // had_owner_once=true, owner=None, ts=0, edges_out > threshold
    let node = make_node(4, 0, true, false, true, config.hot_cluster_threshold + 1);
    let mut nodes = single_node_map(node);

    let changed = sweep(&mut nodes, max_ts_seen, &config);

    assert_eq!(changed, vec![4]);
    assert_eq!(nodes[&4].state, NodeState::Orphan);
}
'''),
    ...para('//',
        r'Note that the node in that test is orphaned and hot, '
        r'because the tag lives on the node that lost its owner, while '
        r'hotness is about the node’s own children. The same node can '
        r'hold both facts only if it is a former child that is itself '
        r'a container.'),

    ...sec(r'three versions of one loop'),
    ...para('//',
        r'The sweep reached its present form in four commits over five '
        r'days, and each step fixed something real.'),
    ...pt('//', 'eaa6162 (2026-07-02): the first version',
        r'Orphan and Hot assigned and pushed to the changed list on '
        r'every pass, with `continue` for orphan-wins-over-hot.'),
    ...pt('//', '6bd9d6a (2026-07-02): guard the transitions',
        r'Orphan and Hot assignments only push to changed when the '
        r'state actually changes. The same commit adds the line '
        r'"TODO: reset state to Healthy when conditions no longer hold '
        r'(not yet implemented — spec is silent on reset)". The TODO is '
        r'honest about the gap; the gap lasted four days.'),
    ...pt('//', '338abef (2026-07-06): the reset path',
        r'The message: "sweep() had no reset branch: a node tagged Hot '
        r'stayed Hot even after its cluster shrank below threshold, '
        r'since only Orphan/Hot were ever assigned and Healthy was '
        r'unreachable once left." The fix re-evaluates every live node '
        r'through orphan, then hot, then Healthy, "matching the locked '
        r'Q4 sweep design". Orphan needs no special reset handling '
        r'because of the argument in the doc comment: its predicate '
        r'"cannot become false once true", since age only grows and '
        r'neither the owner nor had_owner_once ever reverts. The test '
        r'that came with it, hot_resets_to_healthy_when_cluster_'
        r'shrinks, fills a cluster, sweeps, shrinks it by one and '
        r'sweeps again.'),
    blank,
    ...para('//',
        r'The lesson the commit history illustrates is the usual one '
        r'for state machines: if you can enter a state you must define '
        r'how to leave it, and a sweep that only ever assigns is a '
        r'sweep that is missing half its states.'),

    ...sec(r'the time source (and what tau does and does not mean)'),
    ...para('//',
        r'The sweep takes max_ts_seen as an argument. It has no access '
        r'to a wall clock, by decision Q3: "Never use daemon wall-'
        r'clock." The graph’s rolling maximum of event timestamps is '
        r'"now", which means detection runs on the producer’s clock '
        r'and only moves when events arrive. A quiet target does not '
        r'age anything. tests/orphan_persistence.rs and the chaos_'
        r'orphan example both account for this; graph.rs has the '
        r'details, including that only alloc events advance the clock.'),
    blank,
    ...para('//',
        r'The meaning of tau is described two ways in the repository, '
        r'and the code decides between them. The Build Spec’s section '
        r'on structural predicates says tau_ms is "not detection '
        r'latency" and that the 5-second window "governs when the '
        r'visual fade/coral treatment shows in the UI". But sweep '
        r'applies the tau comparison itself, as the third clause of '
        r'the orphan predicate, and the H1 commit (816c732) describes '
        r'it as "a conjunction (owner freed AND age > tau)", measuring '
        r'latency from "whichever conjunct completes last":'),
    ...pt('//', 'H1 formula (from that commit)',
        r'orphan_detected_ts_ns - max(owner_free_ts_ns, node_ts_ns + '
        r'tau_ms * 1e6). Its first version omitted the max() and went '
        r'negative under tau = 5 ms, because tau had already been '
        r'satisfied about 190 ms before the owner was freed in that '
        r'workload.'),
    ...pt('//', 'measured, tau = 5 ms',
        r'median 0.0089 ms over 20 runs (min 0.0078, max 20.277). The '
        r'owner-free event was the binding conjunct.'),
    ...pt('//', 'measured, tau = 500 ms',
        r'median 2.569 ms over 20 runs (min 1.896, max 3.280). The age '
        r'clause was the binding conjunct.'),
    blank,
    ...para('//',
        r'The commit adds the qualifier that matters: both figures '
        r'are "conditional on this workload’s post-trigger event '
        r'cadence" (chaos_orphan’s 20 ms heartbeat), "not a universal '
        r'daemon constant". The one 20 ms outlier in the 5 ms group is '
        r'consistent with the next event after the binding '
        r'timestamp arriving a heartbeat later. Whichever way the '
        r'prose is read, the predicate in this file is what ships, '
        r'and it is the one the numbers measure.'),

    ...sec(r'hot, and its entanglement with φ'),
    ...para('//',
        r'The hot predicate counts edges_out, the owner side of the '
        r'arcs φ infers. That makes it exactly as accurate as φ. A '
        r'commit on 2026-07-28, d192626, is a clean illustration. The '
        r'checkout_service demo grows a hot cluster of 40 children, '
        r'and Hot never fired. The message: the backlog Vec was '
        r'created empty and grew from inside the same function as '
        r'queue_owner, so its first backing-array reallocation landed '
        r'after queue_owner and was "a more-recently-allocated same-'
        r'site candidate by the time the second (+30) batch arrived. '
        r'Phi’s recency tie-break then attributed that batch to '
        r'backlog’s own backing array instead of queue_owner, splitting '
        r'the 40 total children roughly 10/30 across two different '
        r'nodes — neither crossing hot_cluster_threshold (32) alone".'),
    blank,
    ...para('//',
        r'The sweep was right the whole time; it was handed the wrong '
        r'fan-out. The fix was in the demo (reserve the vector before '
        r'allocating the owner), not here. It is a useful reminder '
        r'that a threshold on an inferred quantity inherits the '
        r'inference’s error. See graph.rs for the recency rule.'),

    ...sec(r'StormTracker: a sliding window per call site'),
    ...code('rust', 'crates/heaplens-daemon/src/anomaly.rs · StormTracker and record() (trimmed)', r'''
/// Tracks per-call-site allocation rates to detect allocation storms.
///
/// Each entry maps `stack[0]` (the top call-site address) to a ring of
/// nanosecond timestamps that fall within the current storm window.
pub struct StormTracker {
    /// stack[0] addr → ring of ts_nanos values within the current window.
    pub sites: HashMap<u64, VecDeque<u64>>,
}
...
    /// Record a new alloc at `addr` with timestamp `ts` (nanoseconds).
    ///
    /// Evicts entries older than `storm_window_ms`, then appends `ts`.
    /// Returns `true` when this site's in-window count now exceeds
    /// `storm_rate_threshold`.
    pub fn record(&mut self, addr: u64, ts: u64, config: &Config) -> bool {
        let window_ns = config.storm_window_ms * 1_000_000;
        let deque = self.sites.entry(addr).or_default();
        while let Some(&front) = deque.front() {
            if ts.saturating_sub(front) > window_ns {
                deque.pop_front();
            } else {
                break;
            }
        }
        deque.push_back(ts);
        deque.len() as u64 > config.storm_rate_threshold
    }
'''),
    ...para('//',
        r'record() slides the window forward by popping timestamps '
        r'older than the window from the front, pushes the new one on '
        r'the back, and reports a storm when the deque holds more than '
        r'storm_rate_threshold entries (defaults: 1000 allocations in '
        r'a 1000 ms window). Because timestamps arrive in roughly '
        r'increasing order, expiring from the front is enough. The '
        r'strict greater-than means exactly the threshold is not a '
        r'storm; storm_tracker_detects_storm records threshold + 1.'),
    blank,
    ...para('//',
        r'The second function exists because of a leak, found by '
        r'reading rather than by a crash:'),
    ...code('rust', 'crates/heaplens-daemon/src/anomaly.rs · evict_idle', r'''
/// Evict sites whose entries have all fallen outside the storm window
/// relative to `max_ts_seen`. Call once per Tick so the site map does not
/// grow unbounded with every distinct allocation site ever seen — sites
/// that stop allocating are pruned instead of retained forever.
pub fn evict_idle(&mut self, max_ts_seen: u64, config: &Config) {
    let window_ns = config.storm_window_ms * 1_000_000;
    self.sites.retain(|_, deque| {
        while let Some(&front) = deque.front() {
            if max_ts_seen.saturating_sub(front) > window_ns {
                deque.pop_front();
            } else {
                break;
            }
        }
        !deque.is_empty()
    });
}
'''),
    ...para('//',
        r'Commit 338abef: "StormTracker.sites also grew unbounded: a '
        r'site’s stale entries were only evicted when that same site '
        r'was recorded again, so addresses that stopped allocating '
        r'lingered in the map for the daemon’s lifetime." evict_idle '
        r'runs once per Tick against max_ts_seen, again the stream’s '
        r'clock, so pruning is as quiet as the target. The test '
        r'storm_tracker_evict_idle_prunes_stale_sites records two '
        r'sites, jumps the clock past the window and expects the map '
        r'to be empty.'),

    ...sec(r'what the storm tracker really tracks (a caution)'),
    ...para('//',
        r'The tracker is keyed on stack[0] and its doc comment calls '
        r'that "the top call-site address". main.rs passes ev.stack[0] '
        r'unfiltered. The capture code, however, documents that the '
        r'raw trace "always starts inside the shared instrumentation '
        r'chain (capture_stack -> record -> the allocator method)", and '
        r'graph.rs goes to some length to skip those frames when it '
        r'wants a real call site. If stack[0] really is a machinery '
        r'frame for every allocation, the "per-site" tracker collapses '
        r'to one process-wide allocation counter. I reached that by '
        r'reading two files, not by running the daemon, and no test '
        r'covers the integration, so treat it as an open question. '
        r'If correct, the fix would be to key on the effective site '
        r'the way graph.rs does.'),
    blank,
    ...para('//',
        r'A second property by arithmetic: record() never caps the '
        r'deque, so a site that allocates a million times a second '
        r'holds a million u64 timestamps, about 8 MB, for each '
        r'window it stays hot.'),

    ...sec(r'how it is tested'),
    ...para('//',
        r'tests/anomaly_unit.rs has 8 tests, built on a Config with '
        r'tiny thresholds so each boundary is one number: tau_ms = 5, '
        r'hot_cluster_threshold = 2, storm_rate_threshold = 3, '
        r'storm_window_ms = 100. The boundary tests come in pairs that '
        r'straddle the line by one nanosecond: orphan_after_tau '
        r'sets max_ts_seen = tau * 1,000,000 + 1, and not_orphan_'
        r'before_tau sets it to tau * 1,000,000 - 1. The exact boundary '
        r'(age == tau) is not tested; the predicate is strictly '
        r'greater-than. The test file has its own page.'),

    ...sec(r'limits'),
    ...pt('//', 'roots are never orphans',
        r'The orphan predicate needs had_owner_once. A leaked '
        r'allocation that φ never attached to an owner is invisible '
        r'to this detector. It finds children that lost their owner.'),
    ...pt('//', 'hot is a count, not a growth rate',
        r'A cluster that sits at 33 children for an hour is Hot; one '
        r'that grows from 1 to 31 in a second is not. The Build '
        r'Spec’s original growth-percentage idea was not built.'),
    ...pt('//', 'thresholds are defaults, not derivations',
        r'32 children, 5000 ms, 1000 allocations per 1000 ms. The '
        r'spec says so itself. All are overridable by environment '
        r'variable (see config.rs).'),
    ...pt('//', 'NodeState::Freed is unused',
        r'The M4 plan: "NodeState::Freed is NOT emitted in M4. Only '
        r'Healthy, Orphan, Hot." A freed node leaves the graph by '
        r'appearing in a diff’s remove list instead.'),
    ...pt('//', 'storms are not visible to the UI',
        r'Detection ends in a tracing::warn! line. No wire message '
        r'carries it, and I found no Flutter code that consumes a '
        r'storm.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
