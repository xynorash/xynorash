import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/examples/checkout_service.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'checkout_service.rs — a demo that pretends to be a service'),
    cm('//', r'healthy traffic, then a leak, a hot queue and an allocation storm, '
              r'forever, one phase at a time'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'continuous console demo cycling through all three detectable flaws'),
    kv('language', r'Rust example binary (never exits on its own)'),
    kv('size', r'143 lines; the shared logic lives in support/checkout_common.rs'),
    kv('history', r'3 commits: f6ec325 (2026-07-19), 9693399 and a31baeb (2026-07-28)'),
    kv('cycle', r'four 30-second phases, 120 seconds per cycle'),
    ...sec(r'a different kind of example'),
    ...para('//',
        r'The chaos examples are labelled experiments: one flaw each, run '
        r'once, exit. This one is written to look like an ordinary service '
        r'module. Its module doc comment calls it "a stand-in for a real '
        r'e-commerce checkout backend (payment gateway pooling, an order '
        r'queue, metrics logging, plain request handling), written to look '
        r'like an ordinary service module rather than a labeled test '
        r'scenario". The names are the point: request_handler, '
        r'payment_gateway_pool, order_queue, metrics_flush. When the '
        r'HeapLens UI reports a probable leak, it reports it against a '
        r'function called payment_gateway_pool_checkout_connections, which '
        r'is the thing a viewer would see in a real incident, not against '
        r'something named leak_test.'),
    blank,
    ...para('//',
        r'It was added on 2026-07-19 (f6ec325) as "a realistic '
        r'combined-flaw demo" and was later rewired, on the day before the '
        r'thesis demo, to share its logic with the TUI target.'),
    ...sec(r'the cycle'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service.rs · module documentation', r'''
//! `checkout_service` — a stand-in for a real e-commerce checkout backend
//! (payment gateway pooling, an order queue, metrics logging, plain request
//! handling), written to *look* like an ordinary service module rather than
//! a labeled test scenario. Unlike `chaos_orphan`/`chaos_hot`/`chaos_storm`
//! (one flaw each, run once, exit), this program runs forever as a single
//! continuous demo, cycling through all three flaws back-to-back on a fixed
//! 15-second cadence, each in a distinct, realistically-named module:
//!
//!   T+0s   healthy      — `request_handler` serves ordinary requests, no issue.
//!   T+15s  LEAK         — `payment_gateway_pool` drops its pool manager
//!                         while checked-out connections are still held.
//!                         Never cleaned up — a real leak persists forever,
//!                         so these connections stay orphaned across every
//!                         later cycle too (live node count should trend
//!                         upward over the life of the run).
//!   T+30s  HOT CLUSTER   — `order_queue` accepts a backlog that grows past
//!                         a healthy size and keeps growing.
//!   T+45s  ALLOC STORM   — `metrics_flush` bursts a flood of log-write
//!                         allocations far faster than a healthy request
//!                         handler would.
//!   T+60s  → back to healthy, repeat.
//!
//! Every phase transition is announced on stdout so a person watching the
//! console alongside the live graph can see which event is *supposed* to be
//! happening right now and correlate it with what the UI shows.'''),
    ...para('//',
        r'The header documents the plan: healthy, then a leak, then a hot '
        r'cluster, then an allocation storm, and back to the start, "each '
        r'announced on stdout so a person watching the console alongside '
        r'the live graph can see which event is supposed to be happening '
        r'right now and correlate it with what the UI shows".'),
    blank,
    ...para('//',
        r'The header’s timestamps are stale. It says T+0, T+15, T+30, '
        r'T+45, T+60 and a "fixed 15-second cadence". Commit a31baeb on '
        r'2026-07-28 changed the phase length to 30 seconds '
        r'("checkout_service’s phase interval is now 30s (was 15s)") and '
        r'updated the constant, but not the comment. The code is the '
        r'authority:'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service.rs · the phase length and the traffic generator', r'''
const PHASE_MS: u64 = 30_000;

/// Keeps event timestamps advancing during a hold — `heaplens-daemon`'s
/// anomaly age (`max_ts_seen`) only advances via new captured events, never
/// wall-clock, so every phase needs a steady trickle of real allocation
/// traffic even while "waiting."
fn request_handler_serve_for(duration_ms: u64) {
    let start = Instant::now();
    let mut count = 0usize;
    while start.elapsed() < Duration::from_millis(duration_ms) {
        request_handler_handle(count);
        count += 1;
        std::thread::sleep(Duration::from_millis(40));
    }
}'''),
    ...para('//',
        r'PHASE_MS is 30,000. The healthy phase serves for 30 s; the leak '
        r'phase is 2 s plus 28 s; the hot phase is 3 s plus 27 s; the '
        r'storm phase loops for 30 s. So the actual schedule is healthy at '
        r'T+0, leak at T+30, hot cluster at T+60, storm at T+90, and the '
        r'cycle repeats at T+120.'),
    blank,
    ...para('//',
        r'request_handler_serve_for is the traffic generator that runs '
        r'during every hold. Every 40 ms it calls request_handler_handle, '
        r'a 96-byte allocate-and-free, so about 25 requests a second, '
        r'nowhere near the storm threshold of 1,000. The doc comment gives '
        r'the reason a "waiting" phase still needs traffic, one the reader '
        r'of every example here will recognise: the daemon’s anomaly age '
        r'"only advances via new captured events, never wall-clock".'),
    ...sec(r'state that outlives a cycle'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service.rs · main and the accumulators', r'''
fn main() {
    println!("[checkout_service] starting — request_handler online, payment_gateway_pool warm, order_queue idle");
    let _ = std::io::Write::flush(&mut std::io::stdout());

    // Connections leaked by payment_gateway_pool persist across every
    // cycle, deliberately never freed — see the module doc comment.
    let mut leaked_connections: Vec<Vec<u8>> = Vec::new();

    // Recovered order_queue owners/backlog remnants, kept alive (never
    // dropped) after each hot-cluster phase heals. Unlike the leak above,
    // this is not a bug — it's what lets the recovery be *visible* as a
    // "back to healthy" family in the graph rather than the owner and its
    // children vanishing outright the instant the phase ends, which reads
    // identically to "nothing was ever here" rather than "this grew, then
    // came back under control."
    let mut healthy_queue_owners: Vec<Vec<u8>> = Vec::new();
    let mut healthy_backlog_remnants: Vec<Vec<u8>> = Vec::new();'''),
    ...para('//',
        r'Three things are kept alive on purpose, in vectors declared '
        r'outside the loop. leaked_connections collects the connections of '
        r'every leak and is never freed: "Connections leaked by '
        r'payment_gateway_pool persist across every cycle, deliberately '
        r'never freed", because "a real leak persists forever". Two more, '
        r'healthy_queue_owners and healthy_backlog_remnants, keep the '
        r'recovered order queue visible after each heal. The comment is '
        r'explicit that this one is not a bug: it lets the recovery be '
        r'"visible as a ’back to healthy’ family in the graph rather than '
        r'the owner and its children vanishing outright".'),
    blank,
    ...para('//',
        r'The stdout flushes are not decoration. After each announcement '
        r'the program calls std::io::Write::flush(&mut std::io::stdout()). '
        r'When stdout is a pipe it is block-buffered, and a harness that '
        r'reads the pipe would see the phase lines minutes late. The '
        r'chaos_hot commit message makes the same point about relying on '
        r'"the examples’ own buffered stdout" for timing.'),
    ...sec(r'the leak'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service.rs · the leak phase (long print lines elided) (trimmed)', r'''
let mut pool_manager: Option<Vec<u8>> = None;
let mut pending_connections: Option<Vec<Vec<u8>>> = None;
leak_pool_tick(&mut pool_manager, &mut pending_connections, false);
request_handler_serve_for(2_000); // manager and connections visibly live together first
leak_pool_tick(&mut pool_manager, &mut pending_connections, true); // the bug
let mut connections = pending_connections.take().unwrap_or_default();
...
leaked_connections.append(&mut connections);
request_handler_serve_for(PHASE_MS - 2_000);'''),
    ...para('//',
        r'leak_pool_tick(.., false) creates the manager and its 12 '
        r'connections together. The program then keeps serving traffic for '
        r'2 seconds so the pair is visibly alive in the graph, and then '
        r'calls leak_pool_tick(.., true), which drops the manager. The 12 '
        r'connections move into leaked_connections and stay live. For the '
        r'rest of the phase the UI should show twelve orphans. Because the '
        r'accumulator is never emptied, orphans from every earlier cycle '
        r'stay on screen too, so the live node count "should trend upward '
        r'over the life of the run".'),
    blank,
    ...para('//',
        r'A figure from the commit that added it: "Verified live '
        r'end-to-end on a clean daemon: 13 orphaned connections correctly '
        r'reported (’Probable leak at '
        r'checkout_service::payment_gateway_pool_checkout_connections’)". '
        r'The count is 13, not 12; the extra node is probably the vector '
        r'that holds the connections, but the message does not say. When '
        r'the same program was later observed through the injector, commit '
        r'50a9627 reports "12 allocations totaling 1536 bytes lost their '
        r'owner", which is 12 x 128.'),
    ...sec(r'the hot queue'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service.rs · the hot phase (trimmed)', r'''
let _ = std::io::Write::flush(&mut std::io::stdout());
let mut queue_owner: Option<Vec<u8>> = None;
let mut backlog: Vec<Vec<u8>> = Vec::new();
hot_cluster_tick(&mut queue_owner, &mut backlog, false); // still under the healthy threshold
request_handler_serve_for(3_000);
hot_cluster_tick(&mut queue_owner, &mut backlog, true); // now well past it
println!("    order_queue: backlog at {} orders and still growing", backlog.len());
let _ = std::io::Write::flush(&mut std::io::stdout());
request_handler_serve_for(PHASE_MS - 3_000);
...
let remnant_total = hot_cluster_heal(
    &mut queue_owner,
    &mut backlog,
    &mut healthy_queue_owners,
    &mut healthy_backlog_remnants,
);'''),
    ...para('//',
        r'hot_cluster_tick(.., false) starts the queue with its owner and '
        r'10 orders, healthy. After 3 seconds, hot_cluster_tick(.., true) '
        r'adds 30 more, which makes 40, over the threshold of 32. The '
        r'program prints the backlog size, serves for the remaining 27 '
        r'seconds of the phase, and then calls hot_cluster_heal, which '
        r'trims the backlog to 3. The owner flips Hot when the second '
        r'batch lands and returns to Healthy after the heal.'),
    blank,
    ...para('//',
        r'The ordering lesson that this phase needed is in '
        r'checkout_common.rs. The first version of this file (f6ec325) '
        r'built its backlog by taking the Vec that '
        r'order_queue_accept_orders returned, so the vector’s buffer was '
        r'allocated in the helper and growing it later was only a realloc, '
        r'and the commit reports that the queue flipped Hot live. The '
        r'shared hot_cluster_tick written on 2026-07-28 (a31baeb) started '
        r'from an empty Vec::new() instead, and for a few hours the owner '
        r'never turned amber, though the console faithfully printed "40 '
        r'orders and still growing", until d192626 fixed it the same day.'),
    ...sec(r'the storm'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service.rs · the storm phase', r'''
let storm_start = Instant::now();
let mut burst = 0usize;
while storm_start.elapsed() < Duration::from_millis(PHASE_MS) {
    // A burst of unthrottled writes, then a brief pause before the
    // next burst — keeps the storm visibly "ongoing" for the whole
    // phase rather than a single instantaneous spike that's easy to
    // miss.
    storm_burst(2_000);
    burst += 1;
    std::thread::sleep(Duration::from_millis(1_500));
}'''),
    ...para('//',
        r'For 30 seconds the program writes bursts of 2,000 metrics '
        r'entries with a 1.5 second pause between bursts, around twenty '
        r'bursts. The comment explains the pause: "keeps the storm visibly '
        r'’ongoing’ for the whole phase rather than a single instantaneous '
        r'spike that’s easy to miss." Each burst crowds 2,000 allocations '
        r'into a fraction of a millisecond, far above the daemon’s default '
        r'of 1,000 per 1,000 ms, so the daemon logs a storm warning (see '
        r'chaos_storm.rs for how the warning is deduplicated and for a '
        r'caveat about what a "site" means). The last bursts’ events are '
        r'the ones the writer could miss at exit, but this program never '
        r'exits.'),
    ...sec(r'how to run it, and the opt-in'),
    ...para('//',
        r'Since 2026-07-28 the cooperative path needs HEAPLENS_ENABLE (or '
        r'injection). The same day, commit 9693399 re-enabled the UI’s '
        r'attach button (its title says "attach button re-enabled for '
        r'soutenance"), which suggests the demo targets are meant to be '
        r'attached to from the process picker; that is an inference from '
        r'the title, not something the commit message spells out.'),
    ...sec(r'what is and isn’t checked'),
    ...para('//',
        r'Nothing in the repository runs this binary; it is for humans. '
        r'Its shared logic is tested indirectly: the daemon’s '
        r'cross_process_wire_tui.rs drives the TUI target, which calls the '
        r'same four functions, and checks the leak and hot-cluster shapes. '
        r'The storm is not covered by that test. There is no test of the '
        r'cadence, which is how the header and the constant drifted apart.'),
    ...sec(r'limits'),
    ...pt('//',
        r'the header is out of date',
        r'15-second wording against a 30-second constant.'),
    ...pt('//',
        r'unbounded growth, by design',
        r'2,336 bytes a cycle (see checkout_common.rs).'),
    ...pt('//',
        r'no stop condition',
        r'killing the process is the only exit.'),
    ...pt('//',
        r'tied to its shared module',
        r'changing the allocation shape in checkout_common.rs changes what '
        r'this program demonstrates.'),
    ...sec(r'related'),
    ...pt('//',
        r'support/checkout_common.rs',
        r'the rules.'),
    ...pt('//',
        r'checkout_service_tui.rs',
        r'the interactive variant with a scripted 90-second window.'),
    ...pt('//',
        r'chaos_orphan.rs, chaos_hot.rs, chaos_storm.rs',
        r'one flaw each.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/examples/checkout_service.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/examples/checkout_service.rs'),
  ],
);
