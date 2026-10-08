import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/examples/hot_producer.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'hot_producer.rs — one owner, forty children, and the line that makes '
              r'it amber'),
    cm('//', r'the Hot state’s visual-verification gate, built to be looked at for '
              r'thirty seconds'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'slow, watchable scenario for the Hot state'),
    kv('language', r'Rust example binary'),
    kv('size', r'100 lines; 1 owner of 4096 bytes and 40 children of 128 bytes; about '
              r'46 seconds'),
    kv('history', r'3 commits: 43fc22e (2026-07-08), 586a6c4 and b000f92 (2026-07-19)'),
    kv('timeline', r'15 s healthy with 10 children, grow to 40, 30 s hot, free everything'),
    ...sec(r'why it exists'),
    ...para('//',
        r'After the canvas diagnosis, orphan visuals were confirmed by '
        r'direct observation, but one state remained unproven. The M5 '
        r'plan, in commit bb1b4b3, says it plainly: "Hot state remains '
        r'open, carried into Stage 6 — needs a dedicated >32-child '
        r'single-owner producer, since existing producers only ever form '
        r'ownership chains under phi inference." Every earlier program '
        r'built either pairs or a root with a chain beneath it. None made '
        r'one node with more than 32 direct children, which is what the '
        r'daemon’s Hot predicate needs.'),
    blank,
    ...para('//',
        r'hot_producer is that program. It arrived in commit 43fc22e on '
        r'2026-07-08 (the large commit that also fixed the ownership '
        r'inference), and was edited twice more on 2026-07-19.'),
    ...sec(r'the program'),
    ...code('rust', 'crates/heaplens-alloc/examples/hot_producer.rs · make_star', r'''
/// Splits allocation into a healthy `n_healthy` (under the default 32 hot
/// threshold) followed by a 15s healthy hold, then the remaining children
/// that push the total over the threshold. Both batches are pushed from
/// this same call site so every child's captured stack still names
/// `make_star` as an ancestor frame — that's what lets phi attribute all of
/// them to `owner`, not just the first batch (splitting the two pushes into
/// separate functions would give the second batch a different stack shape
/// and break that attribution).
#[inline(never)]
fn make_star(n_healthy: usize, n_total: usize) -> (Vec<u8>, Vec<Vec<u8>>) {
    let mut children = Vec::with_capacity(n_total);
    let owner = vec![0u8; 4096];
    for _ in 0..n_healthy {
        children.push(leaf_alloc(128));
    }

    println!(
        "holding for 15s healthy ({n_healthy} children, under the default 32 threshold) \
         before growing into Hot"
    );
    heartbeat(15);

    for _ in 0..(n_total - n_healthy) {
        children.push(leaf_alloc(128));
    }
    (owner, children)
}'''),
    ...para('//',
        r'make_star(n_healthy, n_total) builds the star in two stages. '
        r'First the children container with Vec::with_capacity(n_total), '
        r'then the 4,096-byte owner, then n_healthy children. It then '
        r'prints a message and holds for 15 seconds, calling the '
        r'heartbeat, so a viewer sees an ordinary, healthy star of ten '
        r'children. Then it pushes the remaining children, 30 of them, to '
        r'reach 40.'),
    blank,
    ...para('//',
        r'The comment on the function says why the second batch is pushed '
        r'from the same function: "Both batches are pushed from this same '
        r'call site so every child’s captured stack still names make_star '
        r'as an ancestor frame — that’s what lets phi attribute all of '
        r'them to owner, not just the first batch (splitting the two '
        r'pushes into separate functions would give the second batch a '
        r'different stack shape and break that attribution)."'),
    ...code('rust', 'crates/heaplens-alloc/examples/hot_producer.rs · main', r'''
/// Slow, watchable scenario closing the M5/M6 Hot visual-verification gate:
/// one owner with 40 children (safely above the default hot_cluster_threshold
/// of 32) held alive for 30s so a human has time to see the owner render
/// amber. Deliberately never frees the owner mid-hold: `anomaly.rs`'s sweep
/// checks Orphan before Hot and Orphan wins if both would match, so freeing
/// the owner early would make its children eligible for Orphan instead of
/// letting the owner sit and be observed as Hot.
///
/// Distinct from `leak_unbounded.rs` (the fast, sleep-free H2 benchmark
/// workload with the same underlying shape) — this file exists purely for
/// human visual confirmation and the demo, not for timing measurement.
fn main() {
    println!("hot_producer: allocating 1 owner + 10 children (healthy — under threshold)");
    let (owner, children) = make_star(10, 40);
    println!(
        "grown to {} children live off one owner — owner should now be Hot/amber; \
         holding for 30s for visual confirmation",
        children.len()
    );
    heartbeat(30);

    println!("freeing owner and children");
    drop(owner);
    drop(children);

    // Wait for the writer thread's flush interval to drain the ring.
    std::thread::sleep(std::time::Duration::from_millis(500));
    println!("hot_producer: done");
}'''),
    ...para('//',
        r'The main function calls make_star(10, 40), reports the child '
        r'count, and then holds for 30 seconds with the heartbeat so a '
        r'person has time to see the owner turn amber. Finally it drops '
        r'the owner and the children, sleeps 500 ms for the writer, and '
        r'prints done. The total is 15 + 30 + 0.5 seconds, about 45.5; the '
        r'commit that added the 15 s hold reports the measured figure '
        r'"hot_producer ran ~46s (15s healthy + 30s hot hold)", "matching '
        r'their coded durations exactly".'),
    ...sec(r'why the owner is never freed during the hold'),
    ...para('//',
        r'The doc comment on main states a rule that is easy to miss: '
        r'"Deliberately never frees the owner mid-hold: anomaly.rs’s sweep '
        r'checks Orphan before Hot and Orphan wins if both would match, so '
        r'freeing the owner early would make its children eligible for '
        r'Orphan instead of letting the owner sit and be observed as Hot." '
        r'In the sweep the Orphan predicate is tested first and Hot only '
        r'if it did not match, so the two states are exclusive per node, '
        r'and the scenario has to keep the owner alive to be observed Hot.'),
    blank,
    ...para('//',
        r'Forty children against a threshold of 32 leaves a margin of '
        r'eight. The predicate is edges_out.len() > hot_cluster_threshold '
        r'and is structural: no time window, no waiting for tau. The '
        r'comment notes that this is why the owner should turn amber "as '
        r'soon as phi has attached all n_children to it, well before the '
        r'hold period ends".'),
    ...sec(r'the same bug as demo_producer, one function over'),
    ...para('//',
        r'Commit 586a6c4 (2026-07-19, "allocate children container before '
        r'owner") is a one-line reorder, and the message says it is the '
        r'"same fix as demo_producer’s make_family (05790cc)". The '
        r'container from Vec::with_capacity allocates at make_star’s own '
        r'call site, as the owner does. When it came second it was the '
        r'newer same-name candidate, so each child attached to the '
        r'container, and the Hot cluster appeared on the wrong node. The '
        r'message reports the live check: "owner now correctly flips amber '
        r'once all 40 children attach".'),
    blank,
    ...para('//',
        r'The capacity argument deserves a look. with_capacity(n_total) '
        r'reserves room for all 40 up front, before the owner exists, so '
        r'no push allocates inside make_star’s own frame once the owner is '
        r'live. Growth by realloc would not have created a rival node '
        r'anyway, since the daemon migrates an existing node on a realloc '
        r'without re-running ownership inference. The danger is the first '
        r'allocation of a lazily grown Vec, which is a fresh node at the '
        r'owner’s call site and, being newer, wins the tie-break. The same '
        r'trap caught the checkout service nine days later, in a different '
        r'shape (see checkout_common.rs).'),
    ...sec(r'comments that point at files that are not here'),
    ...para('//',
        r'The doc comment on main says this program is "Distinct from '
        r'leak_unbounded.rs (the fast, sleep-free H2 benchmark workload '
        r'with the same underlying shape)". A search of the repository '
        r'history, all branches, for any file with that name finds none. '
        r'The Build Spec’s section 8 plans three leak examples '
        r'(leak_rc_cycle, leak_unbounded, leak_channel) but they were '
        r'never committed here. The reference presumably points at a '
        r'worktree or branch that is not part of this repository.'),
    blank,
    ...para('//',
        r'Also, the doc comment above make_star is two comments fused: the '
        r'paragraph about the container’s ordering and the paragraph '
        r'"Splits allocation into a healthy n_healthy ..." run together '
        r'without a blank line, a leftover of how the 15-second hold was '
        r'added in b000f92. Cosmetic, but it reads as one thought when it '
        r'is two.'),
    ...sec(r'limits'),
    ...pt('//',
        r'no assertion',
        r'the check is a person watching for amber.'),
    ...pt('//',
        r'one owner',
        r'the scenario cannot show two competing hot clusters.'),
    ...pt('//',
        r'the gate',
        r'it reports only if HEAPLENS_ENABLE is set or it is attached '
        r'through injection.'),
    ...sec(r'related'),
    ...pt('//',
        r'demo_producer.rs',
        r'the orphan sibling, same pattern, same ordering lesson.'),
    ...pt('//',
        r'chaos_hot.rs',
        r'the one-shot version of the same state.'),
    ...pt('//',
        r'checkout_common.rs',
        r'where the trap came back inside a more realistic service.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/examples/hot_producer.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/examples/hot_producer.rs'),
  ],
);
