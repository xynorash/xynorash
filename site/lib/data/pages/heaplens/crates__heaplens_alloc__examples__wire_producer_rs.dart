import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/examples/wire_producer.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'wire_producer.rs — forty lines that exposed four bugs'),
    cm('//', r'the workload behind the end-to-end test, and the adversarial shape it '
              r'gives the owner finder'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'test workload for the whole pipe: allocator, writer, wire format, '
              r'daemon, ownership inference'),
    kv('language', r'Rust example binary'),
    kv('size', r'40 lines; 100 owner/child pairs; about 0.6 seconds of runtime'),
    kv('history', r'one commit, 2acccba (2026-07-02), never edited'),
    kv('driven by', r'crates/heaplens-daemon/tests/cross_process_wire.rs'),
    ...sec(r'why it exists'),
    ...para('//',
        r'By 2026-07-02 the project had a protocol crate, an allocator '
        r'crate with a writer thread, and a daemon that could ingest and '
        r'model. What it did not have was proof that the three worked '
        r'together across a real process boundary. wire_producer is that '
        r'proof’s workload: a tiny program that is run as a separate '
        r'process, allocates a known number of things in a known shape, '
        r'and exits. The daemon’s integration test (cross_process_wire.rs, '
        r'added in the same commit and titled "cross-process wire test — '
        r'pipe end-to-end, phi inference on real stacks") spawns it, '
        r'listens on the real named pipe, and asserts on what arrives.'),
    blank,
    ...para('//',
        r'It is the opposite of the later demo programs: it is not meant '
        r'to be watched. It allocates and frees everything in about half a '
        r'second. A Flutter canvas diagnosis a few days later found out '
        r'exactly what that means for a human, see demo_producer.rs.'),
    ...sec(r'the program'),
    ...code('rust', 'crates/heaplens-alloc/examples/wire_producer.rs · leaf_alloc and nested_alloc', r'''
/// Allocates at a leaf call site. `#[inline(never)]` ensures this frame
/// appears in the stack captured by the global allocator, giving φ inference
/// a distinct stack[0] to match against the caller's allocation.
#[inline(never)]
fn leaf_alloc(n: usize) -> Vec<u8> {
    vec![0u8; n]
}

/// Allocates an outer buffer, then calls leaf_alloc. Because leaf_alloc's
/// captured stack includes this frame's PC, φ should infer that the outer
/// buffer owns the inner one — assuming the outer alloc happened first and
/// its stack[0] appears somewhere in leaf_alloc's stack.
#[inline(never)]
fn nested_alloc(n: usize) -> (Vec<u8>, Vec<u8>) {
    let outer = vec![0u8; n];       // outer: stack[0] = nested_alloc's frame
    let inner = leaf_alloc(n / 2);  // inner: stack includes nested_alloc's frame
    (outer, inner)
}'''),
    ...para('//',
        r'Two functions, both #[inline(never)]. leaf_alloc allocates a '
        r'Vec. nested_alloc allocates an outer buffer and then calls '
        r'leaf_alloc for an inner one half the size. The shape is the '
        r'smallest that creates a real ownership relationship: the inner '
        r'allocation happens while the outer one is live, and the inner’s '
        r'call stack passes through nested_alloc, the function that made '
        r'the outer. That is the whole signal the ownership inference '
        r'needs, and each function exists as a separate #[inline(never)] '
        r'frame because an inlined call leaves no frame to match.'),
    ...code('rust', 'crates/heaplens-alloc/examples/wire_producer.rs · main', r'''
fn main() {
    // Perform > 64 allocs to force at least one count-triggered flush (batch cap = 64).
    // 100 × nested_alloc = 200 Box/Vec allocs + Vec reallocations ≫ 64 events.
    let mut items: Vec<(Vec<u8>, Vec<u8>)> = Vec::with_capacity(100);
    for _ in 0..100 {
        items.push(nested_alloc(128));
    }

    // Hold briefly, then drop to generate dealloc events.
    std::thread::sleep(std::time::Duration::from_millis(100));
    drop(items);

    // Wait for the writer thread's 1ms flush interval to drain the ring.
    // The writer retries at 100µs; 500ms is >> the maximum latency.
    std::thread::sleep(std::time::Duration::from_millis(500));
}'''),
    ...para('//',
        r'main creates a container with Vec::with_capacity(100) and calls '
        r'nested_alloc a hundred times, pushing each pair into it. Then it '
        r'sleeps 100 ms, drops everything to generate the dealloc events, '
        r'and sleeps 500 ms more to let the writer flush.'),
    blank,
    ...para('//',
        r'The comments give the numbers. "Perform > 64 allocs to force at '
        r'least one count-triggered flush (batch cap = 64). 100 x '
        r'nested_alloc = 200 Box/Vec allocs + Vec reallocations >> 64 '
        r'events." The 64 is the writer’s BATCH_CAP, so the program is '
        r'sized to exercise both flush triggers, the full-batch one and, '
        r'through the sleeps, the 1 ms timer. The trailing comment, "The '
        r'writer retries at 100µs; 500ms is >> the maximum latency", is '
        r'the same lesson as every other producer’s final sleep: the '
        r'writer is not joined on exit.'),
    blank,
    ...para('//',
        r'The test counts exactly 202 allocations every run: 100 outers, '
        r'100 inners, the items buffer, and one more allocation that the '
        r'test does not attribute. Its comment notes that alloc_count '
        r'"stays exactly 202 every run".'),
    ...sec(r'the shape it gives the inference'),
    ...para('//',
        r'The program is deceptively adversarial. The daemon’s inference '
        r'("phi") links a new allocation to a live node whose allocating '
        r'function appears among the new allocation’s ancestor frames, '
        r'taking the most recently allocated candidate when several match. '
        r'Here that produces a three-level structure, which the test’s '
        r'comments explain at length. The items container, allocated in '
        r'main and live for the whole run, is a genuine long-lived '
        r'ancestor of everything. Each outer is therefore owned by it; and '
        r'each outer owns its own inner via leaf_alloc. The result is a '
        r'chain root, outer, inner, not the flat pairs one might draw on a '
        r'whiteboard. The test records that an earlier version "asserted '
        r'’no owner is ever owned,’ encoding an idealized flat-pairs '
        r'picture that only held because a since-fixed debug-info gap ... '
        r'collapsed all symbol resolution to a single name and hid this '
        r'ancestry entirely".'),
    blank,
    ...para('//',
        r'It is also the worst case for the tie-break. Around a hundred '
        r'outer buffers from the same call site are live at once and none '
        r'is freed until the end. For each inner, the correct owner is the '
        r'most recently allocated outer, and that holds only if events '
        r'arrive in strict order. The test calls the workload "a '
        r'specifically adversarial shape": when batching or ring timing '
        r'jitters, an inner can be credited to an older sibling, so one '
        r'outer ends up with no child and another with two. Nothing is '
        r'lost (the count of allocations is steady at 202); the credit is '
        r'redistributed.'),
    blank,
    ...para('//',
        r'The numbers from the test make this concrete. Over 18 '
        r'consecutive runs on 2026-07-26 the root’s reported child count '
        r'ranged from 24 to 47, never the roughly 100 one would expect, '
        r'while the allocation count and the set of distinct call-site '
        r'names did not vary at all. The test’s threshold was recalibrated '
        r'from an assumed 100, through 50, to a MIN_STAR_OWNERS of 15, '
        r'"set with real margin below the observed floor".'),
    ...code('rust', 'crates/heaplens-daemon/tests/cross_process_wire.rs · the floor the test settled on', r'''
// Calibrated against real observed behavior (2026-07-26: 18 consecutive
// runs, root's own child count ranged 24-47, never below 24), not the
// originally-assumed ~100 (nor the old, never-reliably-met 50). Set
// with real margin below the observed floor — low enough to never be a
// false failure from ordinary redistribution jitter, high enough that
// it still only passes when φ has built substantial, genuine
// multi-level structure (dozens of correctly-inferred parent-child
// pairs), not a handful of isolated fragments or a collapsed/empty
// result.
const MIN_STAR_OWNERS: usize = 15;
assert!(
    root_children.len() >= MIN_STAR_OWNERS,
    "expected the root container to own ≥ {MIN_STAR_OWNERS} `outer` buffers, got {} \
     (root id {root_id})",
    root_children.len()
);'''),
    ...para('//',
        r'That is an unusually honest piece of test engineering. The '
        r'assertion is as strict as the observed behaviour allows and no '
        r'stricter, the shortfall is explained in the file next to it, and '
        r'the invariants that really must hold regardless of timing are '
        r'kept exact: no more than two children per outer, leaves have no '
        r'children, and no node has two owners.'),
    ...sec(r'four bugs, exposed by running this program'),
    ...para('//',
        r'This small program was the first thing to run through the whole '
        r'pipeline with real stack frames. Comments in writer.rs, graph.rs '
        r'and the workspace Cargo.toml name it as the binary on which four '
        r'separate defects were observed. The first three were fixed in '
        r'commit 43fc22e on 2026-07-08, the fourth five days later:'),
    blank,
    ...pt('//',
        r'exact addresses did not link anything',
        r'the first matching compared the instruction address of the '
        r'owner’s allocation with addresses in the child’s stack. Two '
        r'statements in the same function have different addresses, so '
        r'nested_alloc’s outer and leaf_alloc’s ancestor frame never '
        r'matched. The daemon’s graph.rs comment says it was "confirmed '
        r'empirically against a real compiled binary (0 edges from '
        r'wire_producer’s nested_alloc ...)". The fix moved matching to '
        r'function names.'),
    ...pt('//',
        r'release builds lost the names',
        r'Rust’s default release profile omits debug info, so internal '
        r'functions resolved to the nearest exported symbol, "observed: '
        r'all collapsed onto wire_producer::main". The workspace '
        r'Cargo.toml now sets [profile.release] debug = true, with the '
        r'observation in its comment.'),
    ...pt('//',
        r'compiler shims hid the call site',
        r'__rust_alloc and its siblings are namespaced under the consuming '
        r'binary, observed as wire_producer::_::__rust_alloc, and were '
        r'mistaken for caller code. Fixed with substring matching in '
        r'writer.rs.'),
    ...pt('//',
        r'Vec::with_capacity was not "machinery"',
        r'the items container itself resolved to '
        r'alloc::vec::Vec::with_capacity instead of wire_producer::main, '
        r'so nothing could match it. The writer.rs list was replaced by '
        r'the whole alloc:: prefix on 2026-07-13, and the end-to-end test '
        r'is what reported it (root fan-out assertion failing with 0 '
        r'candidates).'),
    blank,
    ...para('//',
        r'By the commit messages and comments, each was found by running '
        r'against a real compiled binary rather than by a unit test of one '
        r'crate.'),
    ...sec(r'comments that outlived the design'),
    ...para('//',
        r'Two comments in this file describe the first design. leaf_alloc '
        r'is documented as "giving φ inference a distinct stack[0] to '
        r'match against the caller’s allocation", and nested_alloc’s lines '
        r'say "outer: stack[0] = nested_alloc’s frame". Both are from the '
        r'era of exact-address matching. The current design does not use '
        r'stack[0]: the daemon skips machinery frames, takes the first '
        r'real frame as the allocation’s site, and matches function names. '
        r'The program still does what it was written to do; the '
        r'explanation attached to it is a day-one explanation. This is the '
        r'kind of drift the header of every producer here tries to '
        r'prevent, and it happens even in a 40-line file.'),
    ...sec(r'the gate'),
    ...para('//',
        r'Like the other cooperative examples, it captures only if '
        r'HEAPLENS_ENABLE is set in its environment (since 2026-07-28). '
        r'The test spawns it with Command::new(&producer).spawn() and does '
        r'not set the variable. The Windows test could not be run for this '
        r'page; reading the code, an inherited environment without the '
        r'variable would produce no events, and the test’s own first '
        r'assertion, alloc_count >= 100, would fail with the message '
        r'"possible wire/framing failure". It is a question for whoever '
        r'next runs the suite.'),
    ...sec(r'limits'),
    ...pt('//',
        r'short-lived by design',
        r'the whole run is over before a person could look.'),
    ...pt('//',
        r'one thread',
        r'no concurrency, so none of the multi-producer paths run.'),
    ...pt('//',
        r'exact count and exact shape',
        r'the test’s assertions depend on this file not changing its '
        r'allocation pattern.'),
    ...sec(r'related'),
    ...pt('//',
        r'crates/heaplens-daemon/tests/cross_process_wire.rs',
        r'the consumer of this workload.'),
    ...pt('//',
        r'demo_producer.rs',
        r'the same ownership shape, slowed to human pace.'),
    ...pt('//',
        r'writer.rs',
        r'the classifier the fourth bug changed.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/examples/wire_producer.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/examples/wire_producer.rs'),
  ],
);
