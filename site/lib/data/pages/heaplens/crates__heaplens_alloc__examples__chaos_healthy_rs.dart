import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/examples/chaos_healthy.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'chaos_healthy.rs — the control experiment'),
    cm('//', r'matched allocations, a pause, and nothing at all should happen'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'negative control for the chaos scenarios: no leak, no cluster, no '
              r'storm'),
    kv('language', r'Rust example binary'),
    kv('size', r'16 lines; 20 allocations over about one second'),
    kv('history', r'one commit, b000f92 (2026-07-19), ported from the chaos-test worktree'),
    kv('expected outcome', r'every node Healthy, every node freed, no warnings'),
    ...sec(r'why a program that does nothing wrong is worth keeping'),
    ...para('//',
        r'The chaos examples exist to make the detectors fire. '
        r'chaos_orphan makes an orphan, chaos_hot a hot cluster, '
        r'chaos_storm an allocation storm. Each tells you the detector can '
        r'say yes. None of them tells you the detector can say no. A tool '
        r'that raises every alarm on every program is worth no more than '
        r'one that raises none. This file is the other half of the test: a '
        r'program that is, by design, entirely well-behaved, to be run '
        r'against the same daemon and watched for false positives.'),
    blank,
    ...para('//',
        r'The port message in commit b000f92 lists it with the others and '
        r'singles it out in a sentence: "chaos_healthy: unchanged — it’s '
        r'always healthy by design". The other three got a 15-second '
        r'healthy hold bolted on at the front so that a viewer could see '
        r'normal behaviour before the anomaly. This one is normal '
        r'behaviour all the way through, so it needed no hold.'),
    ...sec(r'the program'),
    ...code('rust', 'crates/heaplens-alloc/examples/chaos_healthy.rs · the whole file', r'''
// Chaos scenario: healthy baseline. Matched alloc/dealloc pairs, no
// leaks, no large clusters, no storm. Nothing should ever anomaly-flip.
use heaplens_alloc::HeapLensAlloc;

#[global_allocator]
static GLOBAL: HeapLensAlloc = HeapLensAlloc::new();

fn main() {
    for _ in 0..20 {
        let v = vec![0u8; 64];
        std::hint::black_box(&v);
        drop(v);
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    println!("DONE");
}'''),
    ...para('//',
        r'Twenty iterations. Each allocates a zero-filled 64-byte Vec, '
        r'passes a reference through std::hint::black_box so the compiler '
        r'cannot elide the allocation, drops it explicitly, and sleeps 50 '
        r'ms. Then it prints DONE. The total run time is about a second '
        r'(20 x 50 ms) plus startup.'),
    blank,
    ...para('//',
        r'The details that look like noise are not. black_box keeps the '
        r'allocation real. The explicit drop(v) makes the pairing visible: '
        r'every alloc is followed by its dealloc before the next one '
        r'begins, so at most one of the program’s own nodes is alive at a '
        r'time. The sleep keeps the allocation rate at about 20 per '
        r'second, a small fraction of the storm threshold of 1,000 per '
        r'second. And vec![0u8; 64] is the zeroed allocation path, the one '
        r'that carries several extra standard-library frames, so even this '
        r'trivial program exercises the machinery classification: the '
        r'daemon has to skip the plumbing to find main as the call site.'),
    ...sec(r'what the daemon should conclude'),
    ...para('//',
        r'Reading the detector logic in the daemon (anomaly.rs), a node is '
        r'Orphan only if it has had an owner once and lost it, and Hot '
        r'only if it has more than hot_cluster_threshold (32) outgoing '
        r'edges; a storm needs more than 1,000 allocations at one site '
        r'inside a 1,000 ms window. This program trips none: each vec is '
        r'created with no live owner (the previous one is already freed, '
        r'and none of its own siblings is alive), has no children, and is '
        r'freed. The expected picture is a single node that appears and '
        r'disappears twenty times, always Healthy, and no storm warning in '
        r'the log.'),
    ...sec(r'what it is not'),
    ...para('//',
        r'It is not an automated test. Nothing in the repository runs it '
        r'and asserts on the result; no harness greps for its output or '
        r'checks that no state flipped. The H1 harness uses chaos_orphan, '
        r'the wire tests use wire_producer and the checkout programs, and '
        r'the other chaos examples are run by hand ("verified live against '
        r'dist/v3’s daemon", in the commit message). So the control exists '
        r'as a program a person can run and look at.'),
    blank,
    ...para('//',
        r'It also has no trailing sleep. Most of the other producers in '
        r'this directory (demo_producer, hot_producer, wire_producer, '
        r'chaos_storm and the chaos scenarios that hold at the end) '
        r'finish with a pause so the writer thread has time to '
        r'flush, because the process does not join the writer on exit; '
        r'only alloc_smoke, which has no daemon to feed, exits at once '
        r'too. '
        r'This one exits as soon as DONE is printed, so the last '
        r'allocation or two may never reach the daemon. For a scenario '
        r'whose whole assertion is "nothing happens", that cannot cause a '
        r'false alarm, but it is a reminder that capture is best-effort at '
        r'the end of a process’s life.'),
    ...sec(r'a note on the opt-in'),
    ...para('//',
        r'Like every example here, it only reports to a daemon if '
        r'HEAPLENS_ENABLE is set in its environment (or if it is attached '
        r'through injection). Run bare, it produces nothing, healthy or '
        r'otherwise.'),
    ...sec(r'related'),
    ...pt('//',
        r'chaos_hot.rs, chaos_orphan.rs, chaos_storm.rs',
        r'the positive cases.'),
    ...pt('//',
        r'demo_producer.rs',
        r'the slow, human-paced version of the orphan story.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/examples/chaos_healthy.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/examples/chaos_healthy.rs'),
  ],
);
