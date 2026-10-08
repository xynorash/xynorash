import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/examples/chaos_hot.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'chaos_hot.rs — fifteen healthy seconds, then a cluster that crosses '
              r'the line'),
    cm('//', r'ten children, a long pause, thirty more, and the owner turns amber'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'scenario for the Hot state: an owner whose fan-out exceeds the '
              r'threshold'),
    kv('language', r'Rust example binary'),
    kv('size', r'46 lines; about 18 seconds of runtime'),
    kv('history', r'one commit, b000f92 (2026-07-19), ported from dev/chaos_test'),
    kv('expected outcome', r'the owner’s node flips to Hot once it has more than 32 children'),
    ...sec(r'the scenario'),
    ...para('//',
        r'A node is Hot when it has more outgoing ownership edges than a '
        r'threshold, 32 by default. The predicate is purely structural, '
        r'with no time window, which the file’s header spells out: '
        r'"Owner’s node should flip to Hot (edges_out.len() > 32)". This '
        r'program builds exactly that. It allocates an owner, gives it 10 '
        r'children and holds that for 15 seconds so a viewer sees an '
        r'ordinary healthy star, then adds 30 more children for a total of '
        r'40, which is past 32, and holds for 3 seconds more.'),
    ...sec(r'the program, in order'),
    ...code('rust', 'crates/heaplens-alloc/examples/chaos_hot.rs · make_children and the healthy hold', r'''
#[inline(never)]
fn make_children(n: usize) -> Vec<Box<[u8; 32]>> {
    (0..n).map(|_| Box::new([0u8; 32])).collect()
}

fn main() {
    let owner = Box::new(0u8);
    println!("OWNER_SYMBOL=chaos_hot::main");

    // Healthy hold: 10 children (under the default 32 threshold) for a full
    // 15s, so a human (or a screenshot) sees a plain healthy star before the
    // cluster grows into Hot. Ticks every 20ms rather than a single sleep to
    // keep max_ts_seen advancing.
    let mut children = make_children(10);
    let healthy_start = Instant::now();
    while healthy_start.elapsed() < Duration::from_millis(15_000) {
        let hb = vec![0u8; 8];
        std::hint::black_box(&hb);
        drop(hb);
        std::thread::sleep(Duration::from_millis(20));
    }'''),
    ...para('//',
        r'The owner is a one-byte Box, allocated first. The ordering is '
        r'not incidental: ownership inference only considers nodes that '
        r'are already live, so the owner must exist before its children '
        r'are created. The function make_children is #[inline(never)] so '
        r'that it has a stack frame of its own. Ownership is inferred by '
        r'finding the owner’s call site among the ancestor frames of the '
        r'child’s stack, and an inlined function leaves no frame to find.'),
    blank,
    ...para('//',
        r'The program prints OWNER_SYMBOL=chaos_hot::main for whoever is '
        r'watching, a hint of the name the daemon should show for the '
        r'owner’s call site.'),
    blank,
    ...para('//',
        r'The healthy hold is the loop at the bottom of that excerpt, and '
        r'it has a second job beyond appearance. Each iteration allocates '
        r'and frees a tiny vec![0u8; 8] and sleeps 20 ms. Those events are '
        r'what keep the daemon’s clock moving: the daemon’s notion of '
        r'time, max_ts_seen, advances only when events arrive, and the '
        r'comment says to do it "Ticks every 20ms rather than a single '
        r'sleep to keep max_ts_seen advancing". Without the heartbeat the '
        r'15 seconds would pass without the daemon’s clock moving at all.'),
    ...code('rust', 'crates/heaplens-alloc/examples/chaos_hot.rs · the growth, and the leak', r'''
    // Grow past the threshold (10 + 30 = 40 > 32) — owner should flip Hot.
    children.extend(make_children(30));
    std::mem::forget(children);

    let start = Instant::now();
    while start.elapsed() < Duration::from_millis(3000) {
        let hb = vec![0u8; 8];
        std::hint::black_box(&hb);
        drop(hb);
        std::thread::sleep(Duration::from_millis(20));
    }
    std::mem::forget(owner);
    println!("DONE");
}'''),
    ...para('//',
        r'children.extend(make_children(30)) adds the second batch. Both '
        r'batches come from make_children, so the stack of every child '
        r'includes the same ancestor frame, main, which is the owner’s '
        r'call site. That is what lets the owner collect all 40. Then '
        r'std::mem::forget(children) deliberately leaks the vector so '
        r'those boxes stay live, and the three-second tail keeps the '
        r'heartbeat running so that the daemon sees the final state before '
        r'the program exits. The owner is forgotten as well, so nothing is '
        r'freed and the cluster stays at 40 until the process ends. The '
        r'program prints DONE.'),
    blank,
    ...para('//',
        r'The commit message gives the timing it was checked against: '
        r'"chaos_hot ran ~18s (15s healthy + 3s hot hold), both matching '
        r'their coded durations exactly", verified from real connect and '
        r'disconnect timestamps at the daemon, not from the program’s own '
        r'buffered output.'),
    ...sec(r'why this one did not need the ordering fix its siblings did'),
    ...para('//',
        r'hot_producer.rs and demo_producer.rs both had to be fixed '
        r'because their children’s container, a Vec::with_capacity, was '
        r'allocated in the same function as the owner and, being newer, '
        r'won the tie-break for ownership (see those pages). The port '
        r'message says this file and its three siblings "did not share" '
        r'the bug, "owner and children already allocate at genuinely '
        r'separate call sites in all four". Here the owner is allocated in '
        r'main and the children, along with the vector that holds them, in '
        r'make_children. The only same-name candidate for a child’s owner '
        r'is therefore the owner itself.'),
    blank,
    ...para('//',
        r'There is a subtlety that the file does not write down. The '
        r'second batch ends with children.extend(...), which may '
        r'reallocate the children vector’s buffer from main. That is a '
        r'realloc of an existing node, which moves the node; it does not '
        r'run ownership inference again, so the buffer stays attached to '
        r'the owner it got when it was first allocated. And the heartbeat '
        r'vecs are also allocated in main, with the owner’s call-site '
        r'name, but they live for microseconds and are gone before '
        r'make_children runs.'),
    ...sec(r'reading the numbers'),
    ...para('//',
        r'10 + 30 = 40 children, plus vector buffers that come and go '
        r'(make_children collects into a fresh Vec each time, and the '
        r'second one is freed again once extend has moved its boxes), are '
        r'on the owner’s edge list, so it '
        r'crosses the 32 threshold with a margin of about eight. The first '
        r'batch alone, 10 children and a buffer, sits well under it; that '
        r'is the healthy phase. The threshold’s default is called out in '
        r'the daemon’s config as 32 (override with '
        r'HEAPLENS_HOT_THRESHOLD), and the Build Spec calls it "an '
        r'empirically-chosen fan-out heuristic, not a value derived from '
        r'any model". The file’s author chose 10 and 30 to be clearly on '
        r'either side.'),
    ...sec(r'what it does not check'),
    ...pt('//',
        r'the Hot flip itself',
        r'nothing asserts on it. The scenario is for a human or a '
        r'screenshot, as the commit says.'),
    ...pt('//',
        r'Orphan precedence',
        r'the daemon’s sweep tests Orphan before Hot, so an owner that was '
        r'freed and orphaned its children would never show Hot. The '
        r'program never frees the owner, which is why it forgets it rather '
        r'than dropping it.'),
    ...pt('//',
        r'timing precision',
        r'the 15-second hold is wall-clock, but anomaly timing is '
        r'event-clock; the heartbeat is what reconciles the two.'),
    ...sec(r'related'),
    ...pt('//',
        r'hot_producer.rs',
        r'the same scenario at human pace, built from a different shape, '
        r'with the ordering lesson.'),
    ...pt('//',
        r'checkout_common.rs',
        r'the same cluster inside a more realistic service, where the '
        r'ordering lesson came back.'),
    ...pt('//',
        r'anomaly.rs (daemon)',
        r'the predicate being exercised.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/examples/chaos_hot.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/examples/chaos_hot.rs'),
  ],
);
