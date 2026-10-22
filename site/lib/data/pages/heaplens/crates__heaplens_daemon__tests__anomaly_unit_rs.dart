import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/tests/anomaly_unit.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'anomaly_unit.rs — the three-state sweep and the storm window, pinned down'),
    cm('//', r'eight tests, no I/O, a hand-built Node per case'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'unit specs for anomaly.rs: sweep() and StormTracker'),
    kv('language', r'Rust integration test (separate crate over heaplens_daemon)'),
    kv('size', r'212 lines, 8 tests, five commits (eaa6162 2026-07-02 to 783b2d3 2026-07-22)'),
    kv('exercises', r'heaplens_daemon::anomaly::{sweep, StormTracker}, config::Config, graph::{Node, SiteClass}'),
    kv('runs', r'everywhere the crate builds; no pipe, no socket, no clock'),
    ...sec(r'what is being specified'),
    ...para('//',
        r'anomaly.rs is the part of the daemon that decides what colour a node is on screen. Once per tick, sweep() walks every live node and re-assigns one of three states: Orphan, Hot or Healthy. Separately, StormTracker keeps a sliding window of allocation timestamps per call site and says when a site is allocating faster than a threshold. These eight tests pin down both: one nanosecond on either side of tau, one edge above the hot threshold (and exactly the threshold in the reset test), one entry above the storm threshold.'),
    blank,
    ...sec(r'the fixtures'),
    ...code('rust', r'crates/heaplens-daemon/tests/anomaly_unit.rs · lines 12-56', r'''
fn test_config() -> Config {
    Config {
        tau_ms: 5,
        hot_cluster_threshold: 2,
        storm_rate_threshold: 3,
        storm_window_ms: 100,
        pipe_name: r"\\.\pipe\heaplens".to_owned(),
        tick_ms: 33,
        ws_addr: "127.0.0.1:9999".to_owned(),
        db_path: "heaplens.db".to_owned(),
    }
}

fn make_node(
    id: u64,
    ts: u64,
    live: bool,
    has_owner: bool,
    had_owner_once: bool,
    edges_out_count: usize,
) -> Node {
    Node {
        id,
        ptr: id,
        size: 64,
        ts,
        live,
        stack: [0u64; 16],
        stack_len: 0,
        owner: if has_owner { Some(9999) } else { None },
        edges_out: vec![0u64; edges_out_count],
        had_owner_once,
        state: NodeState::Healthy,
        owner_free_ts: None,
        // anomaly::sweep never reads site_class — irrelevant to what these
        // tests exercise, so an arbitrary stable value is fine.
        site_class: SiteClass::NoSite,
    }
}

fn single_node_map(node: Node) -> HashMap<u64, Node> {
    let mut m = HashMap::new();
    m.insert(node.id, node);
    m
}'''),
    ...para('//',
        r'test_config is chosen for small numbers: tau of 5 ms, a hot-cluster threshold of 2, a storm rate of 3 within 100 ms. Every boundary in the tests is then written as an expression of the config (config.tau_ms * 1_000_000 + 1), not as a literal, so changing the config changes the test with it.'),
    blank,
    ...para('//',
        r'make_node builds a graph::Node by hand. Its parameters are exactly the fields the sweep reads: the allocation timestamp, whether the node is live, whether it has an owner, whether it ever had one (had_owner_once) and how many children it owns (edges_out). The rest is filler. The comment on site_class says why it is arbitrary: "anomaly::sweep never reads site_class". That field was added later for the graph’s site index, and the test builds a NoSite value because the struct needs one. The 2026-07-22 commit (783b2d3, the incremental-index change) is the reason this file was touched last.'),
    blank,
    ...sec(r'orphan: the tau boundary'),
    ...code('rust', r'crates/heaplens-daemon/tests/anomaly_unit.rs · lines 62-91', r'''
/// A node past the tau threshold should be tagged Orphan and its id returned.
#[test]
fn orphan_after_tau() {
    let config = test_config();
    // tau_ms = 5 → threshold_ns = 5_000_000
    // max_ts_seen = 5_000_001 → delta = 5_000_001 > 5_000_000  ✓
    let max_ts_seen = config.tau_ms * 1_000_000 + 1;
    let node = make_node(1, 0, true, false, true, 0);
    let mut nodes = single_node_map(node);

    let changed = sweep(&mut nodes, max_ts_seen, &config);

    assert_eq!(changed, vec![1]);
    assert_eq!(nodes[&1].state, NodeState::Orphan);
}

/// A node just under the tau threshold must stay Healthy.
#[test]
fn not_orphan_before_tau() {
    let config = test_config();
    // max_ts_seen = 4_999_999 → delta = 4_999_999 which is NOT > 5_000_000
    let max_ts_seen = config.tau_ms * 1_000_000 - 1;
    let node = make_node(2, 0, true, false, true, 0);
    let mut nodes = single_node_map(node);

    let changed = sweep(&mut nodes, max_ts_seen, &config);

    assert!(changed.is_empty());
    assert_eq!(nodes[&2].state, NodeState::Healthy);
}'''),
    ...para('//',
        r'The predicate in sweep is owner.is_none() && had_owner_once && max_ts_seen.saturating_sub(node.ts) > tau_ms * 1_000_000. Two tests bracket the last term. At exactly tau plus one nanosecond the node becomes Orphan and its id is returned in the changed list. At tau minus one it stays Healthy and the list is empty. The comparison in sweep is a strict greater-than. Note that these two probes (tau plus one, tau minus one) sit on either side of the threshold but would not distinguish > from >=; only a probe at exactly tau would. No test here uses exactly tau.'),
    blank,
    ...para('//',
        r'Notice what the clock is. max_ts_seen is the largest event timestamp the graph has seen, not a wall-clock reading. The daemon has no clock of its own for anomaly detection: time is whatever the target’s events say. A target that stops allocating therefore stops time for the sweep. The tests encode that by passing max_ts_seen as a plain number.'),
    blank,
    ...para('//',
        r'Notice also what the age is measured from. The delta is max_ts_seen minus node.ts, the node’s own allocation timestamp, not the time its owner was freed (node.ts is set at allocation, and owner_free_ts is documented in graph.rs as "never read by ... anomaly::sweep’s state predicates"). So tau is the minimum age of a node before it can be called an orphan, not a grace period after its owner dies. The two coincide in the tests because the node is created at ts 0.'),
    blank,
    ...sec(r'hot and the precedence rule'),
    ...code('rust', r'crates/heaplens-daemon/tests/anomaly_unit.rs · lines 93-120', r'''
/// A node with edges_out count above hot_cluster_threshold should be tagged Hot.
#[test]
fn hot_cluster_at_threshold() {
    let config = test_config();
    // hot_cluster_threshold = 2 → need edges_out.len() > 2 → use 3
    let node = make_node(3, 0, true, false, false, config.hot_cluster_threshold + 1);
    let mut nodes = single_node_map(node);

    let changed = sweep(&mut nodes, 0, &config);

    assert_eq!(changed, vec![3]);
    assert_eq!(nodes[&3].state, NodeState::Hot);
}

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
}'''),
    ...para('//',
        r'Hot is edges_out.len() > hot_cluster_threshold, strictly greater: the test uses threshold plus one. A node with exactly the threshold number of children is not hot.'),
    blank,
    ...para('//',
        r'orphan_wins_over_hot builds a node that satisfies both, and asserts Orphan. The test’s doc comment tags it "(Q4)"; sweep’s own doc comment calls the evaluation order the "Q4 invariant". The reason the order matters is visible in the code: new_state is an if-else chain, Orphan first, so a leaked container that also has a lot of children is reported as the more serious problem. Without this test, someone reordering the chain would change what the UI shows without breaking anything else.'),
    blank,
    ...sec(r'the reset path'),
    ...code('rust', r'crates/heaplens-daemon/tests/anomaly_unit.rs · lines 122-141', r'''
/// A Hot node whose cluster shrinks back under threshold must return to
/// Healthy on the next sweep — the reset path is the `else` branch, not a
/// special case.
#[test]
fn hot_resets_to_healthy_when_cluster_shrinks() {
    let config = test_config();
    let node = make_node(5, 0, true, false, false, config.hot_cluster_threshold + 1);
    let mut nodes = single_node_map(node);

    // First sweep: tag Hot.
    let changed = sweep(&mut nodes, 0, &config);
    assert_eq!(changed, vec![5]);
    assert_eq!(nodes[&5].state, NodeState::Hot);

    // Cluster shrinks back under threshold.
    nodes.get_mut(&5).unwrap().edges_out = vec![0u64; config.hot_cluster_threshold];
    let changed = sweep(&mut nodes, 0, &config);
    assert_eq!(changed, vec![5]);
    assert_eq!(nodes[&5].state, NodeState::Healthy);
}'''),
    ...para('//',
        r'This test exists because of a bug fix. The commit 338abef (2026-07-06) is titled "anomaly — reset Hot to Healthy, evict idle storm sites". Before it, a node that went Hot stayed Hot forever, because the sweep only ever set a state and never cleared one. The test tags a node Hot, shrinks its edges_out to exactly the threshold, sweeps again and expects both a changed id and the state Healthy. The doc comment on the test says it precisely: "the reset path is the else branch, not a special case".'),
    blank,
    ...para('//',
        r'The same reasoning applies to Orphan, as the doc comment on sweep explains: it is sticky "not because state is frozen, but because its predicate ... cannot become false once true". Once a node is past tau with no owner, time only moves forward, so nothing resets it. '),
    blank,
    ...sec(r'storm detection'),
    ...code('rust', r'crates/heaplens-daemon/tests/anomaly_unit.rs · lines 143-186', r'''
/// Recording storm_rate_threshold + 1 allocs within the window triggers storm detection.
#[test]
fn storm_tracker_detects_storm() {
    let config = test_config();
    // storm_rate_threshold = 3 → need 4 calls to exceed it
    let mut tracker = StormTracker::new();
    let addr = 0xDEAD_BEEF_u64;
    let count = config.storm_rate_threshold + 1; // 4

    let mut result = false;
    for i in 0..count {
        // Space events 1 ns apart, all within the 100 ms window.
        result = tracker.record(addr, i, &config);
    }

    assert!(result, "storm should be detected after {count} calls within window");
}

/// Old entries outside the window are evicted; after eviction a single new
/// entry should NOT exceed the threshold.
#[test]
fn storm_tracker_evicts_old() {
    let config = test_config();
    // storm_rate_threshold = 3, storm_window_ms = 100 → window_ns = 100_000_000
    let mut tracker = StormTracker::new();
    let addr = 0xCAFE_BABE_u64;
    let threshold = config.storm_rate_threshold; // 3
    let window_ns = config.storm_window_ms * 1_000_000; // 100_000_000

    // Fill window with exactly storm_rate_threshold entries (not yet storming).
    for i in 0..threshold {
        tracker.record(addr, i, &config);
    }

    // Advance time past the window so all previous entries are stale.
    let late_ts = window_ns + 1_000_001;
    let result = tracker.record(addr, late_ts, &config);

    // Only 1 entry should remain in the deque after eviction — below threshold.
    assert!(
        !result,
        "after eviction only one entry remains; should not exceed threshold"
    );
}'''),
    ...para('//',
        r'StormTracker.record(addr, ts, config) trims entries older than the window from the front of that site’s deque, pushes the new timestamp and reports whether the deque is now longer than storm_rate_threshold.'),
    blank,
    ...pt('//', r'storm_tracker_detects_storm',
        r'threshold plus one calls, one nanosecond apart, so all fall within the 100 ms window; the last call must return true. The loop keeps only the final return value.'),
    ...pt('//', r'storm_tracker_evicts_old',
        r'exactly threshold calls (not yet a storm), then one call at window plus 1.000001 ms. All older entries are stale and are evicted, one entry remains, and the answer is false. This is the test that proves the window slides.'),
    ...sec(r'idle-site pruning'),
    ...code('rust', r'crates/heaplens-daemon/tests/anomaly_unit.rs · lines 188-212', r'''
/// A site that stops allocating must be pruned from the map entirely once
/// its entries fall outside the storm window — otherwise the map grows
/// unbounded with every distinct call site ever seen over the daemon's
/// lifetime.
#[test]
fn storm_tracker_evict_idle_prunes_stale_sites() {
    let config = test_config();
    let window_ns = config.storm_window_ms * 1_000_000;
    let mut tracker = StormTracker::new();

    tracker.record(0xAAAA, 0, &config);
    tracker.record(0xBBBB, 0, &config);
    assert_eq!(tracker.sites.len(), 2);

    // Advance max_ts_seen well past the window without recording anything
    // new for either site.
    let max_ts_seen = window_ns + 1_000_001;
    tracker.evict_idle(max_ts_seen, &config);

    assert!(
        tracker.sites.is_empty(),
        "idle sites should be pruned from the map, got {} remaining",
        tracker.sites.len()
    );
}'''),
    ...para('//',
        r'The last test is also from 338abef. record only evicts when the same site allocates again, so a site that goes quiet would sit in the map forever, and the map would grow with every distinct call site seen for the life of the daemon. evict_idle(max_ts_seen) is the tick-time counterpart: it trims every deque against the global clock and drops the sites whose deque ends up empty. The test records two sites at ts 0, advances past the window and expects an empty map. It reads tracker.sites directly, which is why the field is pub in anomaly.rs.'),
    blank,
    ...sec(r'what is not tested here'),
    ...pt('//', r'A dead node',
        r'sweep skips nodes with live false, and no test passes one.'),
    ...pt('//', r'A tie between two checks',
        r'the boundary is covered for tau and for hot separately, never both at the boundary.'),
    ...pt('//', r'evict_idle keeping a live site',
        r'the test checks that stale sites go but never that a recently active site survives. A version of evict_idle that cleared the map on every call would pass.'),
    ...pt('//', r'main.rs’s glue',
        r'how changed ids become diff updates and how a StormTracker result becomes a warning. The orphan_persistence page covers the first half of that glue.'),
    ...sec(r'how it fits the larger system'),
    ...para('//',
        r'anomaly.rs is called from the Tick handler in main.rs on the graph task. Its output is a list of ids; main.rs marks those nodes updated so the next drain_diff re-sends them with their new state, and the Flutter graph canvas colours them. The same Orphan transition is what the H1 latency harness measures, and what orphan_persistence.rs writes to SQLite. These unit tests are the layer beneath all of that: if one of them fails, no end-to-end test is the right place to look.'),
    blank,
    ...sec(r'history'),
    ...pt('//', r'eaa6162 (2026-07-02)',
        r'anomaly.rs and its first tests.'),
    ...pt('//', r'338abef (2026-07-06)',
        r'Hot resets to Healthy; idle storm sites evicted. The reset and prune tests come from here.'),
    ...pt('//', r'43fc22e (2026-07-08)',
        r'the φ function-name-granularity change; in this file it only widened the fixture’s stack array from 8 to 16 entries.'),
    ...pt('//', r'b97b008 (2026-07-16)',
        r'owner_free_ts added to Node, so make_node gained a field.'),
    ...pt('//', r'783b2d3 (2026-07-22)',
        r'the incremental-index performance change, which added site_class to the fixture.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/tests/anomaly_unit.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/tests/anomaly_unit.rs'),
  ],
);
