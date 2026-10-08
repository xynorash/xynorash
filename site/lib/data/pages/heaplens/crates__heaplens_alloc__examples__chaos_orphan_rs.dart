import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/examples/chaos_orphan.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'chaos_orphan.rs — free the owner, keep the children, and time the '
              r'detector'),
    cm('//', r'the workload behind the H1 latency numbers, and the day its timeline '
              r'changed'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'scenario for the Orphan state; also the workload for the H1 '
              r'detection-latency measurement'),
    kv('language', r'Rust example binary'),
    kv('size', r'53 lines; owner plus 5 children of 64 bytes; about 22 seconds of '
              r'runtime'),
    kv('history', r'816c732 (2026-07-16, added with the H1 harness), b000f92 (2026-07-19, '
              r'15 s hold; a git log of the file shows only this one, because it is '
              r'on the UI branch where the file is new)'),
    kv('expected outcome', r'the five children flip to Orphan after the owner is freed'),
    ...sec(r'the scenario'),
    ...para('//',
        r'The central idea of HeapLens is a leak defined as a node that '
        r'outlived its owner. This program makes exactly one. It allocates '
        r'an owner, then five children that the daemon will attribute to '
        r'it, holds the family for a while, frees only the owner, and '
        r'leaves the children alive. The header says what the viewer '
        r'should see: "Children should flip to Orphan once tau_ms '
        r'elapses."'),
    blank,
    ...para('//',
        r'Two details of the first lines carry the reasoning. The owner is '
        r'allocated first, with the stated reason "so φ’s ownership '
        r'inference, which only considers already-live nodes, can assign '
        r'it". And the owner is a raw pointer: Box::into_raw(owner) gives '
        r'a pointer the program can free later, at a time of its choosing, '
        r'and the safety comment spells out the discipline ("freed exactly '
        r'once, here").'),
    ...sec(r'the program'),
    ...code('rust', 'crates/heaplens-alloc/examples/chaos_orphan.rs · owner, children, and the healthy hold', r'''
#[inline(never)]
fn make_children() -> Vec<Box<[u8; 64]>> {
    (0..5).map(|_| Box::new([0u8; 64])).collect()
}

fn main() {
    let owner = Box::new(0u8);
    let owner_ptr: *mut u8 = Box::into_raw(owner);
    println!("OWNER_PTR=0x{:x}", owner_ptr as u64);
    println!("CHILD_SYMBOL=chaos_orphan::make_children");

    let children = make_children();

    // Healthy hold: owner + children all live, nothing orphaned yet — a
    // human (or a screenshot) watching the graph should see a plain healthy
    // star for a full 15s before anything changes. Ticks every 20ms (not a
    // single sleep) to keep max_ts_seen advancing — anomaly age is computed
    // from event timestamps only, never wall-clock (see demo_producer.rs).
    let healthy_start = Instant::now();
    while healthy_start.elapsed() < Duration::from_millis(15_000) {
        let hb = vec![0u8; 8];
        std::hint::black_box(&hb);
        drop(hb);
        std::thread::sleep(Duration::from_millis(20));
    }'''),
    ...para('//',
        r'The program prints two lines for whatever is observing it: '
        r'OWNER_PTR=0x... (the owner’s address) and '
        r'CHILD_SYMBOL=chaos_orphan::make_children. These are for a '
        r'harness or a human to cross-check against what the daemon '
        r'reports, node for node. Then make_children builds five Box<[u8; '
        r'64]> values, in a function marked #[inline(never)] so the '
        r'children’s stack contains an ancestor frame the owner’s call '
        r'site can match.'),
    blank,
    ...para('//',
        r'The healthy hold follows. For fifteen seconds the program '
        r'allocates and drops a tiny vec![0u8; 8] every 20 ms, the same '
        r'heartbeat the other scenarios use. The comment gives the reason '
        r'in one sentence: "anomaly age is computed from event timestamps '
        r'only, never wall-clock". If the program slept, the daemon’s '
        r'clock, which only advances when events arrive, would stand '
        r'still, and no node would ever age.'),
    ...code('rust', 'crates/heaplens-alloc/examples/chaos_orphan.rs · the free, and the tail', r'''
// SAFETY: owner_ptr came from Box::into_raw immediately above and is
// freed exactly once, here.
unsafe {
    drop(Box::from_raw(owner_ptr));
}
std::mem::forget(children);

let start = Instant::now();
while start.elapsed() < Duration::from_millis(7000) {
    let hb = vec![0u8; 8];
    std::hint::black_box(&hb);
    drop(hb);
    std::thread::sleep(Duration::from_millis(20));
}
println!("DONE");'''),
    ...para('//',
        r'Then the free. unsafe { drop(Box::from_raw(owner_ptr)) } returns '
        r'the owner to the allocator, producing the Dealloc event that '
        r'orphans the children. std::mem::forget(children) leaks the '
        r'children’s vector so they stay live. The final loop runs the '
        r'heartbeat for another seven seconds (the 7000 ms in the code), '
        r'which gives the daemon time to run its anomaly sweeps and for a '
        r'human to see the change, and the program prints DONE.'),
    ...sec(r'what orphaning means in the daemon'),
    ...para('//',
        r'The sweep that decides this lives in the daemon’s anomaly.rs. A '
        r'live node is an Orphan when it has no owner now, it had one '
        r'once, and its age exceeds the time constant: the code is '
        r'owner.is_none() && had_owner_once && max_ts_seen - node.ts > '
        r'tau_ms * 1_000_000. The time constant tau_ms defaults to 5,000 '
        r'ms. The H1 harness defines orphaning the same way, as a '
        r'conjunction of two conditions (owner freed AND age beyond tau). '
        r'The Build Spec reads differently: it says a node becomes Orphan '
        r'structurally the moment its owner frees, and that the five '
        r'seconds only governs "when the visual fade/coral treatment shows '
        r'in the UI". The sweep at HEAD matches the harness, not that '
        r'paragraph, so the documents and the code are not fully in '
        r'agreement about what tau does.'),
    blank,
    ...para('//',
        r'Note what node.ts is: the child’s own allocation time, not the '
        r'time the owner was freed. That detail changes what this program '
        r'shows after the 2026-07-19 edit, below.'),
    ...sec(r'the file changed under a benchmark'),
    ...para('//',
        r'This file arrived on 2026-07-16 in commit 816c732, the commit '
        r'that added the H1 harness (crates/h1-harness), and it was '
        r'"copied verbatim from the dev/chaos_test worktree". In that '
        r'version there was no 15-second hold. The program allocated the '
        r'family, slept 300 ms, freed the owner, and ran the heartbeat for '
        r'seven seconds. The H1 results in '
        r'docs/bench_results/h1_latency.csv are consistent with that: in '
        r'all 40 rows owner_free_ts_ns is about 300,000,000 ns, i.e. 300 '
        r'ms.'),
    blank,
    ...para('//',
        r'The harness measured the time from whichever condition completed '
        r'last (owner freed, or age exceeding tau) to the daemon marking '
        r'the orphan. Its commit message reports 20 runs each at two '
        r'settings: tau of 5 ms, where owner-free is the binding '
        r'condition, median 0.0089 ms (min 0.0078, max 20.277), and tau of '
        r'500 ms, where age is binding, median 2.569 ms (min 1.896, max '
        r'3.280). It also notes both numbers are "conditional on this '
        r'workload’s post-trigger event cadence (chaos_orphan’s 20ms '
        r'allocation heartbeat)", not constants of the daemon, because the '
        r'daemon’s clock only advances on received events. Recomputing the '
        r'medians from the CSV gives the same figures: 0.0089 and 2.5686 '
        r'ms. Two of the twenty tau=5 ms runs show about 20.2 ms, which '
        r'matches the 20 ms heartbeat interval; the commit’s own account '
        r'of the latency bound is that detection waits for the next '
        r'producer event past the binding timestamp, plus the next tick.'),
    blank,
    ...para('//',
        r'Three days later, on 2026-07-19, commit b000f92 replaced the 300 '
        r'ms sleep with the 15-second hold you see above, so a person '
        r'watching the live graph sees a healthy star before the anomaly. '
        r'The sleep(300ms) is gone. By the formula above, the children are '
        r'15 s old by the time the owner is freed, far past the default 5 '
        r's tau and past the harness’s 500 ms, so for any tau below 15 s '
        r'the owner-free is now always the last condition to be satisfied. '
        r'The regime that the 500 ms row measured, with age as the binding '
        r'condition, can no longer be produced by this file. The harness '
        r'comment still describes the workload as one that "sleeps 300ms". '
        r'That is a reading of the formula and the diff, not something the '
        r'repository states. The CSV is still a correct record of what was '
        r'run on 2026-07-16; the example it was run against has since '
        r'moved on.'),
    ...sec(r'how it is used'),
    ...para('//',
        r'Three places in the repo depend on its shape. The H1 harness '
        r'runs target/release/examples/chaos_orphan.exe as its workload. '
        r'The daemon’s orphan_persistence test picks its numbers to '
        r'"mirror the real chaos_orphan.rs shape" with a gap of about 300 '
        r'ms between the children and the owner’s free, which is the shape '
        r'from before 2026-07-19. And checkout_service.rs’s header names '
        r'it as the one-flaw-then-exit counterpart of the continuous demo.'),
    ...sec(r'the daemon-side picture'),
    ...para('//',
        r'Five children of 64 bytes each hang off one owner. make_children '
        r'also allocates the Vec’s own 40-byte buffer (five pointers) '
        r'before the boxes: a scratch run of the same function logged '
        r'allocations of 1 byte (the owner), then 40, then five of 64. So '
        r'the star is the owner plus six candidate nodes, not five. When '
        r'the owner’s Dealloc arrives, the graph '
        r'clears each child’s owner link, the sweep sees owner.is_none() '
        r'with had_owner_once true, and the first sweep after that, within '
        r'a tick of 33 ms, marks all five Orphan, since in the current '
        r'file they are old enough already. Nodes that are Orphan are '
        r'never reset: the sweep’s own comment notes that Orphan is '
        r'"effectively sticky not because state is frozen, but because its '
        r'predicate ... cannot become false once true".'),
    ...sec(r'limits'),
    ...pt('//',
        r'no assertion',
        r'it prints; nothing checks the outcome (the H1 harness reads '
        r'results from the daemon’s database).'),
    ...pt('//',
        r'one family',
        r'five children is enough for a picture, not for a statistic.'),
    ...pt('//',
        r'the benchmark drift',
        r'described above.'),
    ...pt('//',
        r'sleep granularity',
        r'the heartbeat’s 20 ms is wall-clock sleep; on a loaded machine '
        r'it can stretch, which stretches the detector’s worst case.'),
    ...sec(r'related'),
    ...pt('//',
        r'demo_producer.rs',
        r'the same orphan story at 60 seconds, for presentation.'),
    ...pt('//',
        r'crates/h1-harness (daemon side)',
        r'how the numbers were produced.'),
    ...pt('//',
        r'anomaly.rs (daemon)',
        r'the predicate.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/examples/chaos_orphan.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/examples/chaos_orphan.rs'),
  ],
);
