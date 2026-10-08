import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/examples/demo_producer.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'demo_producer.rs — a minute of calm, a freed owner, twenty orphans'),
    cm('//', r'the scenario built when a blank canvas turned out to be a timing '
              r'problem'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'slow, watchable orphan scenario; the thesis-defence demo script'),
    kv('language', r'Rust example binary'),
    kv('size', r'91 lines; 1 owner of 4096 bytes and 20 children of 128 bytes; about 80 '
              r'seconds'),
    kv('history', r'3 commits: ee766f3, bb1b4b3 (both 2026-07-07), 05790cc (2026-07-19)'),
    kv('timeline', r'T+0 allocate, T+60 s free owner, T+80 s free children'),
    ...sec(r'why it was written'),
    ...para('//',
        r'After the Flutter graph canvas was merged (M5, 2026-07-07), the '
        r'first live run showed nothing: a blank canvas. The M5 plan '
        r'records the diagnosis in commit bb1b4b3 (2026-07-07): not a '
        r'rendering defect but "timing", specifically "wire_producer’s '
        r'sub-2s burst-and-free lifecycle". The test workload allocated '
        r'and freed its whole graph in under two seconds, so by the time a '
        r'person looked at the screen the nodes were gone. The fix was '
        r'threefold: a debug overlay, a blank-canvas regression test, and '
        r'this program.'),
    blank,
    ...para('//',
        r'The commit that added it (ee766f3) says why in two sentences: '
        r'"wire_producer’s whole burst-and-free cycle completes in under 2 '
        r'seconds, which is fine for wire-format testing but useless for a '
        r'human to actually watch. demo_producer holds 1 owner + 20 '
        r'children alive for 60s, then frees the owner (orphaning the '
        r'children, which should persist as coral) — giving a real window '
        r'for visual confirmation of live rendering." It adds that it is '
        r'"also the intended thesis demo scenario, not throwaway". A later '
        r'docs commit (bb1b4b3) wrote that into the file header: the '
        r'timeline "maps directly to the demo script". The demo is for the '
        r'soutenance, the thesis defence.'),
    ...sec(r'the timeline'),
    ...code('rust', 'crates/heaplens-alloc/examples/demo_producer.rs · main', r'''
/// Slow, watchable scenario for the M5 canvas visual-verification gate (and
/// the thesis demo): one long-lived owner with ~20 children, held alive for
/// a full minute (enough time for a human to actually look at the screen),
/// then the owner is freed — orphaning the children, which should persist
/// on screen (coral, per `NodeStateDto.orphan`) rather than disappearing
/// with it. Unlike `wire_producer.rs` (which allocates and frees everything
/// within ~2 seconds, purely to exercise the wire format), this scenario is
/// designed to still be on screen when a human checks it.
///
/// This is the soutenance/thesis demo scenario. Timeline maps directly to
/// the demo script: T+0s family allocated (owner + 20 children appear);
/// T+60s owner freed (children flip to coral/orphan — confirmed live,
/// fix/canvas-render investigation); T+80s children freed (fade out, ~1s).
fn main() {
    println!("demo_producer: allocating 1 owner + 20 children");
    let (owner, children) = make_family(20);
    println!(
        "holding for 60s (owner + {} children all live) — heartbeat every 500ms \
         to keep max_ts_seen advancing",
        children.len()
    );
    heartbeat(60);

    println!("freeing owner — remaining children should become orphans");
    drop(owner);
    println!("holding orphaned children for 20s for visual confirmation");
    heartbeat(20);

    println!("freeing children");
    drop(children);

    // Wait for the writer thread's flush interval to drain the ring.
    std::thread::sleep(std::time::Duration::from_millis(500));
    println!("demo_producer: done");
}'''),
    ...para('//',
        r'There are three beats. At T+0 the program calls make_family(20): '
        r'one owner and twenty children appear. It then holds for 60 '
        r'seconds, calling heartbeat(60). At T+60 it drops the owner and '
        r'the children become orphans, which the UI draws in coral. It '
        r'holds the orphaned children for 20 more seconds. At T+80 it '
        r'drops the children, which fade out over about a second in the '
        r'UI. A final 500 ms sleep lets the writer thread flush. The whole '
        r'run is roughly 80.5 seconds.'),
    blank,
    ...para('//',
        r'The numbers are chosen for a human in a room. Sixty seconds is '
        r'long enough to talk over the healthy star; twenty is long enough '
        r'to point at the coral nodes; the child count of 20 stays safely '
        r'below the Hot threshold of 32 (hot_producer.rs is the one that '
        r'crosses it), so the picture stays an orphan story and not a Hot '
        r'one. Each printed line announces what is about to happen, so a '
        r'presenter and the screen can be kept in step.'),
    ...sec(r'the heartbeat'),
    ...code('rust', 'crates/heaplens-alloc/examples/demo_producer.rs · heartbeat', r'''
/// Keeps event timestamps advancing during a hold period. Anomaly age
/// (`max_ts_seen` in heaplens-daemon) is computed from event timestamps
/// only, never wall-clock — a hold period with zero new events never
/// accrues age no matter how much real time passes (discovered during the
/// M5 Task 10 live run). A steady trickle of tiny, immediately-freed
/// allocations keeps the event stream alive so the daemon's anomaly sweep
/// actually has timestamps to compare `tau_ms` against.
fn heartbeat(seconds: u64) {
    let ticks = seconds * 2; // one heartbeat every 500ms
    for _ in 0..ticks {
        let buf = vec![0u8; 16];
        std::thread::sleep(std::time::Duration::from_millis(500));
        drop(buf);
    }
}'''),
    ...para('//',
        r'The most important function in the file is the least visible. '
        r'During a hold the program does nothing: it sleeps. But the '
        r'daemon does not know about wall-clock time. Its notion of "now" '
        r'is max_ts_seen, the largest producer timestamp among events it '
        r'has received, and ages are computed from that. The comment says '
        r'it was found the hard way: "a hold period with zero new events '
        r'never accrues age no matter how much real time passes '
        r'(discovered during the M5 Task 10 live run)".'),
    blank,
    ...para('//',
        r'So every 500 ms the heartbeat allocates a 16-byte buffer, '
        r'sleeps, and frees it. That trickle is what moves the daemon’s '
        r'clock; without it, 60 seconds of sleeping would be zero seconds '
        r'of daemon time, and the children would never reach the age at '
        r'which they count as orphans. It is a clean illustration of how a '
        r'design decision (time comes only from events, never from a '
        r'second clock) leaks into the way a demo must be written. The '
        r'Build Spec’s rule is "monotonic only, never wall-clock", and the '
        r'cost is that a quiet process looks frozen.'),
    blank,
    ...para('//',
        r'The heartbeat’s allocations come from a separate function, so '
        r'their call site is heartbeat and not make_family. They cannot '
        r'compete with the owner for ownership of anything.'),
    ...sec(r'the bug in the order of two lines'),
    ...code('rust', 'crates/heaplens-alloc/examples/demo_producer.rs · leaf_alloc and make_family', r'''
/// Allocates at a leaf call site whose captured stack includes the caller's
/// frame — see `wire_producer.rs`'s `nested_alloc` for why this shape lets
/// phi ownership inference attach a child to its owner.
#[inline(never)]
fn leaf_alloc(n: usize) -> Vec<u8> {
    vec![0u8; n]
}

/// One owner allocation, followed by `n_children` leaf allocations from the
/// same call site inside this frame — phi should infer all of them as owned
/// by `owner`.
///
/// The `children` container's own backing storage (`Vec::with_capacity`)
/// must be allocated *before* `owner`, not after: it allocates at this same
/// call site (`make_family`), so it is also a same-symbol candidate phi
/// considers when attributing each child. Phi's tie-break picks the most
/// recent same-symbol candidate — if `Vec::with_capacity` ran after `owner`,
/// it would win that tie-break instead of `owner`, and every child would be
/// (mis)attributed to the children container itself rather than to `owner`.
/// Since that container isn't freed until `children` is dropped — at the
/// same time as the children themselves — the owner-freed/children-orphaned
/// transition this scenario exists to demonstrate would never actually be
/// observable: everything would appear to die together in one bulk removal
/// instead of orphaning at T+60s. Allocating it first gives `owner` the
/// later timestamp, so it correctly wins the tie-break.
#[inline(never)]
fn make_family(n_children: usize) -> (Vec<u8>, Vec<Vec<u8>>) {
    let mut children = Vec::with_capacity(n_children);
    let owner = vec![0u8; 4096];
    for _ in 0..n_children {
        children.push(leaf_alloc(128));
    }
    (owner, children)
}'''),
    ...para('//',
        r'make_family allocates the children’s container '
        r'(Vec::with_capacity), then the owner, then twenty children by '
        r'calling leaf_alloc. For a long time the first two lines were the '
        r'other way round, and the demo did not work. Commit 05790cc '
        r'(2026-07-19) explains in its message and in the doc comment '
        r'above the function.'),
    blank,
    ...para('//',
        r'The ownership inference links a child to the most recently '
        r'allocated live node whose allocating function appears among the '
        r'child’s ancestor frames. The owner and the container are both '
        r'allocated inside make_family, so both are candidates for every '
        r'leaf_alloc child, and the more recent one wins. With the '
        r'original order (owner first, then container), the container was '
        r'newer. Every child was therefore attributed to the container, '
        r'not to the owner. The container lives exactly as long as the '
        r'children do, since both are dropped together at the end. So when '
        r'the program freed the owner at T+60, nothing was orphaned: the '
        r'children’s real owner in the graph was still alive. "Everything '
        r'would appear to die together in one bulk removal instead of '
        r'orphaning at T+60s", in the file’s words. The demo’s whole '
        r'point, the orphan transition, was invisible.'),
    blank,
    ...para('//',
        r'The fix swaps the two lines. With the container allocated first, '
        r'the owner is the newer node and wins each tie. The commit '
        r'reports the live check: "orphans now render distinctly (coral) '
        r'partway through the hold, with the daemon’s insights panel '
        r'correctly reporting the leak."'),
    blank,
    ...para('//',
        r'There is a general rule hiding in here, and it recurs in this '
        r'crate: allocate any sibling container before the owner, or the '
        r'owner can lose the tie-break. It came back in hot_producer.rs on '
        r'the same day (586a6c4) and again in checkout_common.rs on '
        r'2026-07-28 (d192626). That recurrence is the argument for '
        r'writing the rule in the comment, which this commit did.'),
    blank,
    ...para('//',
        r'The comment is honest about what the rule is not. It is a '
        r'property of the inference’s recency tie-break, not of Rust or of '
        r'correct program structure. Real programs do not allocate their '
        r'containers in a convenient order, so on a real target this '
        r'ambiguity is one of the reasons an edge is a heuristic and not a '
        r'proof. The Build Spec says it directly: "Heuristic by design; do '
        r'not read an edge as a proof of ownership."'),
    ...sec(r'what the daemon sees'),
    ...para('//',
        r'Twenty children of 128 bytes under one owner of 4,096, plus a '
        r'container, plus a flicker of 16-byte heartbeat nodes every half '
        r'second. At T+60 the owner’s Dealloc clears each child’s owner '
        r'link. With the children already about 60 s old, far beyond the '
        r'default tau of 5 s, the next sweep, within a 33 ms tick, makes '
        r'all twenty Orphan. At T+80 the children are freed and leave the '
        r'graph.'),
    ...sec(r'limits'),
    ...pt('//',
        r'hand-timed',
        r'the 60 and 20 second holds are constants chosen for a '
        r'presentation, not derived from tau; they happen to be much '
        r'longer than the default 5-second tau.'),
    ...pt('//',
        r'heartbeat nodes',
        r'every 500 ms a short-lived node appears in the graph, which is '
        r'faint noise on an otherwise quiet screen.'),
    ...pt('//',
        r'no assertion',
        r'nothing checks the outcome. A person confirms by looking.'),
    ...pt('//',
        r'the gate',
        r'since 2026-07-28 the program reports only if HEAPLENS_ENABLE is '
        r'set or it is attached through injection.'),
    ...sec(r'related'),
    ...pt('//',
        r'wire_producer.rs',
        r'the burst-and-free workload this replaced for demos.'),
    ...pt('//',
        r'hot_producer.rs',
        r'the sibling that crosses the Hot threshold.'),
    ...pt('//',
        r'chaos_orphan.rs',
        r'the fast version used for latency measurement.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/examples/demo_producer.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/examples/demo_producer.rs'),
  ],
);
