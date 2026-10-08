import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/docs/bench_results/h1_latency.csv',
  lines: [
    heading('# H1: how fast does HeapLens notice an orphan?'),
    blank,
    ...text('Forty real runs of one question, with every timestamp '
        'read back from the daemon’s own database. The result is '
        'a pair of small numbers and a long list of reasons not to '
        'over-read them.'),
    blank,
    kv('role', 'raw results of the H1 detection-latency measurement'),
    kv('format', 'CSV · 10 columns · 40 data rows, no failures'),
    kv('produced by', 'crates/h1-harness, committed with it on 2026-07-16 (816c732)'),
    kv('scenario', 'orphan: one owner and five children, owner freed alone'),
    kv('configs', 'tau = 5 ms and tau = 500 ms, 20 runs each'),

    ...sec('the question'),
    ...text('HeapLens calls an allocation an orphan when its '
        'owner has been freed and it is still alive past an age '
        'threshold, tau. H1 asks how long after the orphan '
        'condition becomes true the system actually flags it. '
        'Quick detection is the practical value of a leak tool '
        'and the claim the thesis measures against a reference.'),
    ...text('The first thing the project decided was what H1 is '
        'not. The Build Spec states that tau (default 5000 ms) '
        'is “not detection latency”: it is the window after which '
        'the UI shows the coral orphan treatment, chosen so a '
        'human can see it. The structural flip to Orphan happens '
        'the first time the sweep runs after the condition holds. '
        'So H1 is measured against the structural transition, and '
        'a reader who confuses the two “will score tau_ms as '
        'measurement lag it isn’t”. One caution on that wording: '
        'the shipped sweep in anomaly.rs only flips a node to '
        'Orphan once the node’s own age exceeds tau, so tau does '
        'gate the state itself. The harness resolves the tension '
        'in the next section by starting the clock at the later of '
        'the two conditions, which subtracts tau out.'),

    ...sec('the definition, and the bug it fixed'),
    ...text('The orphan condition is a conjunction: the owner is '
        'freed and the node’s age exceeds tau. Latency therefore '
        'cannot be measured from the free alone. It has to start '
        'at whichever of the two conditions became true last. The '
        'harness header states it in one line:'),
    ...code('rust', 'crates/h1-harness/src/main.rs · the definition', r'''
//   H1 = orphan_detected_ts_ns - max(owner_free_ts_ns, node_ts_ns + tau_ms*1e6)'''),
    ...text('The same thing as code, a binding timestamp and a '
        'difference:'),
    ...code('rust', 'crates/h1-harness/src/main.rs · binding_ts_ns, h1_latency_ms', r'''
fn binding_ts_ns(r: &RunResult) -> u64 {
    let tau_bound = r.node_ts_ns + r.tau_ms * 1_000_000;
    r.owner_free_ts_ns.max(tau_bound)
}

fn h1_latency_ms(r: &RunResult) -> f64 {
    (r.orphan_detected_ts_ns as f64 - binding_ts_ns(r) as f64) / 1_000_000.0
}'''),
    ...text('The max() is a fix, and the commit message tells '
        'the story. The first version measured from the owner '
        'free alone. With tau = 5 ms the age condition had been '
        'satisfied long before the free (about 190 ms by the '
        'commit message; the final rows put it near 295 ms), '
        'so the sweep’s notion of “detected” could land before the '
        'measurement’s notion of “started”, and the result went '
        'negative. A negative latency is a sign the measurement '
        'is wrong, not a lucky result. With the max() in place a '
        'negative value is structurally impossible, and the '
        'harness prints a loud warning if one ever appears. The '
        'data bears this out: all 40 rows are positive.'),
    ...text('There was also an earlier attempt, discarded. Per '
        'the commit message it “measured a modified pipeline and '
        'was dominated by the workload’s settle-sleep”: it timed '
        'the wrong thing, a sleep inside the test program, '
        'against a system that had been altered to be measured. '
        'The rebuilt harness changes neither.'),

    ...sec('where the timestamps come from'),
    ...text('Every number in the file was recorded by the daemon '
        'itself and read back afterwards. No timing is captured '
        'inside the workload, and no proxy sits on the pipe. The '
        'daemon gained a small table for this, written once per '
        'orphan transition:'),
    ...code('rust', 'crates/heaplens-daemon/src/store.rs · orphan_events', r'''
        CREATE TABLE IF NOT EXISTS orphan_events (
            node_id               INTEGER NOT NULL,
            owner_free_ts_ns      INTEGER NOT NULL,
            orphan_detected_ts_ns INTEGER NOT NULL,
            tau_ms                INTEGER NOT NULL
        );'''),
    ...text('The two timestamps are taken at the two moments '
        'that matter. The free time is stored on the child node '
        'when its owner is deallocated. The detection time is the '
        'daemon’s clock when the sweep flips the node. The code '
        'that records it takes care to say it cannot influence '
        'detection:'),
    ...code('rust', 'crates/heaplens-daemon/src/main.rs · the tick handler (trimmed)', r'''
                    // Observability-only: for nodes that just flipped to
                    // Orphan, pair the owner-free ts (recorded on the node
                    // by on_dealloc, at the moment it happened) with this
                    // tick's ts as the detection ts. sweep() above has
                    // already fully decided `changed` and each node's
                    // `state` — this only reads that decision, it cannot
                    // feed back into it.'''),
    ...text('That comment is the measurement-integrity argument '
        'in miniature. If adding the instrument changed what is '
        'measured, the number would describe a different system. '
        'The harness is built to read the rows, and only the rows, '
        'and the third input, the child’s own allocation time, is '
        'read from the pre-existing nodes table so no further '
        'daemon change was needed.'),

    ...sec('the ten columns'),
    ...code('csv', 'docs/bench_results/h1_latency.csv · header, re-wrapped', r'''
scenario,run,tau_ms,node_ts_ns,owner_free_ts_ns,
orphan_detected_ts_ns,binding_ts_ns,h1_latency_ms,
detecting_tick_gap_ms,ticks_captured'''),
    ...bullet('scenario, run',
        'always “orphan”, and the run number within a config '
        '(1 to 20).'),
    ...bullet('tau_ms',
        'the configured threshold for that run, 5 or 500, passed '
        'to the daemon through its HEAPLENS_TAU_MS variable.'),
    ...bullet('node_ts_ns',
        'when the child was allocated, in the producer’s own '
        'clock, nanoseconds since the target process started. '
        'All 40 values are between 59 and 106 microseconds.'),
    ...bullet('owner_free_ts_ns',
        'when the owner was freed, same clock. The 40 values '
        'range from 300.13 to 300.62 ms.'),
    ...bullet('orphan_detected_ts_ns',
        'the newest producer timestamp the daemon had seen at '
        'the sweep that flipped the node.'),
    ...bullet('binding_ts_ns',
        'max(owner_free, node_ts + tau): the instant the '
        'orphan condition became true. Recomputing it for every '
        'row reproduces the stored value, and the stored '
        'h1_latency_ms matches (detected minus binding) to the '
        'last printed digit.'),
    ...bullet('h1_latency_ms',
        'the headline number, in milliseconds.'),
    ...bullet('detecting_tick_gap_ms',
        'a wall-clock side measurement, explained below.'),
    ...bullet('ticks_captured',
        'how many debug-level tick lines of the daemon’s log the '
        'harness parsed for that run: 28 in every tau = 5 row and '
        '34 in every tau = 500 row.'),
    blank,
    ...text('Two real rows, one per extreme of the data:'),
    ...code('csv', 'docs/bench_results/h1_latency.csv · rows 4 and 28', r'''
orphan,4,5,102700,300251300,320528700,300251300,20.277400,32.770600,28
orphan,8,500,103600,300220900,501999400,500103600,1.895800,39.907300,34'''),

    ...sec('the numbers'),
    ...text('Statistics below are computed directly from the '
        'file with a short script, not copied from the commit '
        'message. They agree with the commit message to the '
        'digit.'),
    plain('  tau_ms   runs   median ms   min ms    max ms'),
    plain('  5        20     0.0089      0.0078    20.2774'),
    plain('  500      20     2.5686      1.8958    3.2804'),
    blank,
    ...bullet('tau = 5 ms, owner-free is the binding condition',
        '18 of 20 runs lie between 7.8 and 20.7 microseconds. '
        'Two runs (4 and 11) are about 20.2 milliseconds, a '
        'thousand times larger.'),
    ...bullet('tau = 500 ms, age is the binding condition',
        'all 20 runs lie between 1.9 and 3.3 milliseconds, mean '
        '2.60.'),
    blank,
    ...text('Both configurations were chosen deliberately so '
        'that each conjunct is the binding one in turn. The '
        'workload frees its owner at about 300 ms. A tau of 5 ms '
        'is long satisfied by then, so the free is last. A tau of '
        '500 ms is not satisfied until about 500 ms, so age is '
        'last. Running only one would leave the other half of the '
        'definition untested.'),

    ...sec('reading the numbers without fooling yourself'),
    ...text('The headline is small, and the tempting reading is '
        '“HeapLens detects an orphan in 9 microseconds”. That '
        'reading is wrong, and the commit message says so. All '
        'three timestamps live in the producer’s clock, and the '
        'daemon’s notion of “now” is the newest timestamp it has '
        'received, not a clock of its own. That design (one clock '
        'domain, no wall-clock mixing) makes detection '
        'deterministic and replayable, with a consequence: '
        'the daemon’s clock only moves when an allocation event '
        'arrives. The commit puts it this way:'),
    ...text('detection latency is bounded by the time to the next '
        'producer event past the binding timestamp, plus the time '
        'to the next tick.'),
    ...text('So H1 measures how long the system’s logical clock '
        'took to pass the point where the orphan condition held. '
        'It depends on the workload’s own event cadence as much as '
        'on the daemon, and the three effects can be separated in '
        'the data.'),
    ...bullet('the 9-microsecond median',
        'the workload frees the owner and immediately allocates '
        'its next heartbeat buffer, so there is an allocation '
        'event about 9 microseconds of producer time after the '
        'free, and the daemon’s clock jumps to it. The number is '
        'the gap between two consecutive events in the program, '
        'not a reaction time (my reading of the data; the commit '
        'does not break it down).'),
    ...bullet('the two 20-millisecond runs',
        'the heartbeat period of the workload is 20 ms. In these '
        'two runs, the likeliest reading is that the first post-free '
        'event reached the daemon after the sweep had already run, so '
        'detection waited for the following heartbeat. The '
        'value, 20.24 and 20.28 ms, is one heartbeat period '
        'plus a fraction of a millisecond. The commit message '
        'reports this spread (max 20.277) without explaining '
        'which runs it came from; the mechanism here is inferred.'),
    ...bullet('the 2.6-millisecond cluster at tau = 500',
        'in every one of the 20 runs, detection falls 201.8 to '
        '202.8 ms after the owner free. By simple arithmetic that is '
        'ten heartbeat periods of about 20.2 ms. The orphan '
        'condition becomes true at about 500.1 ms and the first '
        'event past it lands between 502.0 and 503.4 ms. The '
        'tight cluster is the position of '
        'the workload’s 20 ms grid relative to the 500 ms mark, '
        'which is the same every run, and not a measure of daemon '
        'speed. Changing the heartbeat period or the sleep would '
        'move the number without touching the daemon.'),
    blank,
    ...text('The honest summary: in this workload the daemon adds '
        'no measurable delay beyond waiting for the next event. '
        'It does not show the daemon’s intrinsic speed, and '
        'neither the 9 µs nor the 2.6 ms should be quoted without '
        'the sentence “conditional on a 20 ms heartbeat”.'),

    ...sec('the wall-clock column'),
    ...text('Because the main metric is logical, the harness '
        'also records one real-time fact per run: the gap, '
        'measured by the harness from the daemon’s debug log '
        'lines, between the tick that detected the orphan and the '
        'tick before it. If the daemon had been working through '
        'a backlog, ticks would arrive in clumps and the gap would '
        'be near zero. They do not:'),
    plain('  tau_ms   median gap    min       max      gaps under 5 ms'),
    plain('  5        31.0 ms       19.1      36.3     0 of 20'),
    plain('  500      35.6 ms       30.6      39.9     0 of 20'),
    blank,
    ...text('The configured tick is 33 ms. A median of 31 to 36 '
        'with none close to zero says the detecting tick fired on '
        'normal cadence, which is what justifies reading the '
        'main column as sweep timing and not queue draining. The '
        'real-time ceiling on detection is therefore about one '
        'tick interval plus the producer’s up-to-one-millisecond '
        'batching, which matches the Build Spec’s statement that '
        'the structural flip is “bounded by tick_ms, ~33ms”.'),
    ...text('A cross-check on the two tick counts: 28 versus 34 '
        'captured ticks differ by 6, and 6 times 33 ms is 198 ms, '
        'close to the roughly 202 ms by which detection comes '
        'later at tau = 500 (about 502 ms against about 300 ms). '
        'The columns are consistent with one another.'),

    ...sec('how the harness keeps itself honest'),
    ...bullet('real runs only',
        'a run whose WebSocket never saw the orphan diff within '
        '20 seconds, or whose stored rows are missing or '
        'disagree, is reported as FAILED and left out of the CSV, '
        'never filled in. The file has no failed rows, and its '
        '40 rows are all of them.'),
    ...bullet('consistency check',
        'the workload orphans five siblings in one call, so every '
        'stored row for a run must carry identical timestamps. '
        'The harness reads all of them and demands exact '
        'agreement rather than picking one.'),
    ...bullet('tau round-trip',
        'the tau stored by the daemon must equal the tau the '
        'harness configured.'),
    ...bullet('isolation',
        'each run gets its own daemon process, its own port '
        '(from 9800 up) and its own database file in the temp '
        'directory, deleted afterwards.'),
    ...bullet('a diagnose mode',
        'prints inter-tick wall-clock deltas for a single run, '
        'to look at cadence directly. It does not write the CSV.'),
    blank,
    ...text('A subtler piece of care is in the harness comments. '
        'tracing’s default output colours every line even when '
        'piped, so “max_ts=” is not contiguous in the raw bytes: an '
        'escape sequence sits between the field name and the '
        'equals sign. The parser strips them first. And the task '
        'reading the daemon’s output is awaited to completion '
        'before the channel is drained, because a task that has '
        'not been polled since its last line silently loses '
        'everything still in flight. Details like these are what '
        'separates a measurement from a script that prints '
        'numbers.'),

    ...sec('limits, in order of importance'),
    ...bullet('one workload, one machine',
        'N = 20 per configuration of a single scenario with a '
        '5-child family. Nothing here says how detection behaves '
        'with many threads or a different event rate.'),
    ...bullet('logical, not wall-clock',
        'see above. The wall-clock evidence is a side column, '
        'not a second metric.'),
    ...bullet('the workload has moved on',
        'the CSV reflects the version of chaos_orphan.rs that '
        'slept 300 ms before freeing the owner; the harness '
        'header still describes it:'),
    ...code('rust', 'crates/h1-harness/src/main.rs · header comment (trimmed)', r'''
// five children owned by it via phi, sleeps 300ms, frees the owner alone
// (orphaning the children), then holds a 7s heartbeat loop so the daemon'''),
    ...text('Three days later (b000f92, 2026-07-19) the example '
        'gained a 15-second “healthy hold” before the free, so a '
        'person watching the live UI sees a calm graph first. '
        'Current code reads:'),
    ...code('rust', 'crates/heaplens-alloc/examples/chaos_orphan.rs · today', r'''
    while healthy_start.elapsed() < Duration::from_millis(15_000) {'''),
    ...text('Rerunning the harness today would put the free at '
        'about 15 s. Both 5 ms and 500 ms would then be satisfied '
        'long before it, so both configurations would measure the '
        'same binding condition, and the experiment’s two-sided '
        'design would be lost. The committed numbers are valid for '
        'the committed workload; the harness has not been '
        're-baselined.'),
    ...bullet('a dangling reference',
        'the harness header sends the reader to '
        'docs/bench_results/h1_report.md for the full derivation. '
        'No such file exists in the repository or its history; '
        'the derivation lives in the commit message instead.'),
    ...bullet('no reference tool',
        'the thesis criterion CA5 asks for detection earlier than '
        'a reference tool. This file measures HeapLens alone.'),
    ...bullet('paths are hard-coded',
        'target/release/*.exe, so it measures the release profile '
        'with debug = true and runs only on Windows.'),

    ...sec('what to take from it'),
    ...text('Measure from the moment the condition is true, not '
        'the moment you started watching. Let the system under '
        'test write down its own timestamps, and prove the '
        'instrument is passive. Run both ways the definition can '
        'bind. Exclude failures and say they were excluded. And '
        'then explain what each number would change with, '
        'because a benchmark that cannot say what moves it is '
        'a sample, not a result.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
