import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/examples/chaos_storm.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'chaos_storm.rs — two thousand allocations, no sleeps, and a process '
              r'that exits too fast'),
    cm('//', r'the scenario that found out the writer is not joined on exit'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'scenario for allocation-storm detection'),
    kv('language', r'Rust example binary'),
    kv('size', r'48 lines; about 16 seconds of runtime'),
    kv('history', r'one commit, b000f92 (2026-07-19), ported from dev/chaos_test'),
    kv('expected outcome', r'the daemon logs an "allocation storm" warning; no node changes state'),
    ...sec(r'a different kind of anomaly'),
    ...para('//',
        r'Orphans and hot clusters are properties of nodes: a node is, or '
        r'is not, in a state. A storm is a property of a rate. The '
        r'daemon’s StormTracker keeps a deque of timestamps per site, '
        r'drops those older than a window (1,000 ms by default), and '
        r'reports a storm when more than a threshold (1,000 by default) '
        r'remain. It sets no NodeState. The header makes the point, which '
        r'also tells you how to verify the scenario: "StormTracker::record '
        r'does not set NodeState (see anomaly.rs) — it’s logged via warn! '
        r'in main.rs’s graph loop. This scenario is verified by grepping '
        r'the daemon’s own log output for ’allocation storm’, not via '
        r'WS/NodeState."'),
    ...sec(r'the program'),
    ...code('rust', 'crates/heaplens-alloc/examples/chaos_storm.rs · one call site, slow and then fast', r'''
#[inline(never)]
fn storm_alloc(n: usize) {
    let v = vec![0u8; 16];
    std::hint::black_box(&v);
    drop(v);
    let _ = n;
}

fn main() {
    // Healthy hold: the same call site, but at a slow, sparse rate (well
    // under the default 1000/sec threshold) for a full 15s, so a human (or
    // a screenshot) sees ordinary healthy activity before the storm hits.
    let healthy_start = std::time::Instant::now();
    let mut i = 0usize;
    while healthy_start.elapsed() < std::time::Duration::from_millis(15_000) {
        storm_alloc(i);
        i += 1;
        std::thread::sleep(std::time::Duration::from_millis(50));
    }

    // 2000 allocations at one call site, no sleeps — far exceeds the'''),
    ...para('//',
        r'storm_alloc is one small function, marked #[inline(never)], that '
        r'allocates a 16-byte zeroed vec, black_boxes it and drops it. It '
        r'exists as a function so there is exactly one call site to count. '
        r'For the first fifteen seconds main calls it every 50 ms, which '
        r'is 20 calls a second, far below the threshold of 1,000. The '
        r'comment states the purpose: "the same call site, but at a slow, '
        r'sparse rate ... so a human sees ordinary healthy activity before '
        r'the storm hits."'),
    blank,
    ...para('//',
        r'Then the storm. The loop for i in 0..2000 calls it 2,000 times '
        r'with nothing between the calls. Each call is one alloc and one '
        r'free, and the tracker counts allocs, so 2,000 events land in a '
        r'few hundred microseconds or less, comfortably more than 1,000 '
        r'within one 1,000 ms window.'),
    ...sec(r'the bug in the test, which turned out to be a bug in the lifecycle'),
    ...code('rust', 'crates/heaplens-alloc/examples/chaos_storm.rs · the sleep that makes the scenario work', r'''
    for i in 0..2000 {
        storm_alloc(i);
    }

    // The alloc loop itself finishes in well under a millisecond, faster
    // than the writer thread's own flush cycle — without this, the
    // process (and its pipe connection) can exit before most of the 2000
    // events are ever sent, so the daemon never accumulates enough events
    // at this site to cross the storm threshold. Confirmed directly: a
    // manual run without this sleep showed the pipe connect+disconnect
    // ~4ms apart with zero storm warning logged. Same root cause as H2's
    // writer-teardown finding (writer isn't joined on exit).
    std::thread::sleep(std::time::Duration::from_millis(500));
    println!("DONE");
}'''),
    ...para('//',
        r'The last lines are the interesting ones. After the burst the '
        r'program sleeps for 500 ms before printing DONE, and the comment '
        r'explains why it has to: "The alloc loop itself finishes in well '
        r'under a millisecond, faster than the writer thread’s own flush '
        r'cycle — without this, the process (and its pipe connection) can '
        r'exit before most of the 2000 events are ever sent, so the daemon '
        r'never accumulates enough events at this site to cross the storm '
        r'threshold."'),
    blank,
    ...para('//',
        r'The author did not guess. The comment records an observation: '
        r'"Confirmed directly: a manual run without this sleep showed the '
        r'pipe connect+disconnect ~4ms apart with zero storm warning '
        r'logged." And names the root cause: "Same root cause as H2’s '
        r'writer-teardown finding (writer isn’t joined on exit)." The '
        r'writer thread is a detached background thread. When main '
        r'returns, the process ends and takes the writer with it, '
        r'regardless of what is still in the rings. A burst shorter than '
        r'the writer’s flush cycle can be entirely lost.'),
    blank,
    ...para('//',
        r'This is why demo_producer, hot_producer and wire_producer end '
        r'with a short sleep and a comment about letting the writer '
        r'drain. It is also '
        r'the same limit that shows up in writer.rs (no flush on shutdown) '
        r'and ring.rs (drops are silent). Capture is best-effort at the '
        r'end of a program’s life. For an observability tool aimed at '
        r'long-running programs that is the right trade, since cooperative '
        r'shutdown would require the host’s cooperation. For a 2,000-event '
        r'demo that finishes in under a millisecond, it is the difference '
        r'between a storm and nothing.'),
    ...sec(r'what a "site" really is'),
    ...para('//',
        r'The header says "A single call site allocates far faster than '
        r'storm_rate_threshold". The detector, though, is not keyed on the '
        r'caller’s function. In the daemon’s main.rs, the call is '
        r'storm_tracker.record(ev.stack[0], ...), keyed on the first '
        r'captured instruction pointer. As capture.rs documents, the raw '
        r'trace "always starts inside the shared instrumentation chain", '
        r'so stack[0] is a frame inside the allocator’s own capture code, '
        r'not the program’s call site.'),
    blank,
    ...para('//',
        r'A scratch program (outside the repo) checked that on Linux: 153 '
        r'allocation events from three different call sites (plus a few '
        r'from the runtime) in the same process all carried the same '
        r'stack[0], an address inside backtrace’s trace_unsynchronized '
        r'called from capture_stack. If Windows behaves the same, and the '
        r'capture.rs comment says it should, the tracker is counting every '
        r'allocation in the process as one site, so a "storm" means the '
        r'whole process allocated more than 1,000 times in a second. For '
        r'this example, whose only fast allocations come from storm_alloc, '
        r'the two readings give the same answer. The difference would only '
        r'show in a program that spreads its allocations over many call '
        r'sites. Whether this is an intended simplification is not clear '
        r'from the daemon’s tests, and it is outside this crate, so it is '
        r'recorded here as a question, not a finding.'),
    blank,
    ...para('//',
        r'The daemon does deduplicate: warned_sites is cleared on every '
        r'tick, so one warning per 33 ms tick at most while the rate stays '
        r'above the threshold.'),
    ...sec(r'runtime'),
    ...para('//',
        r'Fifteen seconds of 50 ms sleeps, then the burst, then 500 ms: '
        r'about 15.5 s plus startup, which fits the roughly 16 s given '
        r'above. The commit does not report a measured duration for this '
        r'one, only for chaos_hot and hot_producer.'),
    ...sec(r'limits'),
    ...pt('//',
        r'verification is by log grep',
        r'no UI state changes, so the UI shows nothing for this scenario '
        r'beyond the allocation traffic.'),
    ...pt('//',
        r'exit race',
        r'the trailing sleep is a workaround, sized by experiment (500 ms '
        r'against a 1 ms flush interval), not a guarantee.'),
    ...pt('//',
        r'one site',
        r'see above.'),
    ...sec(r'related'),
    ...pt('//',
        r'anomaly.rs (daemon)',
        r'StormTracker.'),
    ...pt('//',
        r'writer.rs',
        r'why the writer is not joined, and what is lost at exit.'),
    ...pt('//',
        r'checkout_service.rs',
        r'the storm phase inside a realistic service, as bursts of 2,000 '
        r'with pauses.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/examples/chaos_storm.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/examples/chaos_storm.rs'),
  ],
);
