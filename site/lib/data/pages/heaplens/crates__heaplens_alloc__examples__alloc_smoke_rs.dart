import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/examples/alloc_smoke.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'alloc_smoke.rs — the host must survive having no one to talk to'),
    cm('//', r'nineteen lines that check the cheapest and most important promise'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'smoke test: allocate in a loop with no daemon running'),
    kv('language', r'Rust example binary'),
    kv('size', r'19 lines; 1,000 rounds, 3 allocations each'),
    kv('history', r'one commit, de6f6a5 (2026-07-01), never edited'),
    kv('pass condition', r'it prints one line and exits'),
    ...sec(r'the promise being checked'),
    ...para('//',
        r'HeapLens runs inside someone else’s program. The first rule of '
        r'that is that the host must never be worse off for the tool being '
        r'present: "must not crash, hang, or abort", in the words of this '
        r'file’s header. The most likely way to break the rule is the dull '
        r'one. The daemon is not running. The writer thread cannot open '
        r'the named pipe. If it blocked, panicked, or let the rings fill '
        r'and grow memory without bound, the program being observed would '
        r'suffer for a daemon that was never there.'),
    blank,
    ...para('//',
        r'This file checks that case on its own, with nothing else in the '
        r'way. There is no daemon, no pipe, no test harness. A program '
        r'that allocates 3,000 small blocks and says it is done.'),
    ...sec(r'the program'),
    ...code('rust', 'crates/heaplens-alloc/examples/alloc_smoke.rs · the whole file', r'''
// Smoke test: run with no daemon. The writer retries the pipe connection in
// the background. The host process must not crash, hang, or abort.
// Events are produced into the ring and dropped when it fills.

use heaplens_alloc::HeapLensAlloc;

#[global_allocator]
static GLOBAL: HeapLensAlloc = HeapLensAlloc::new();

fn main() {
    let rounds = 1_000;
    for i in 0..rounds {
        // Allocate and immediately drop a variety of sizes.
        let _s: String = format!("hello-{i}");
        let _v: Vec<u64> = (0..16).collect();
        let _b: Box<[u8; 128]> = Box::new([i as u8; 128]);
    }
    println!("alloc_smoke: {rounds} rounds completed — no crash, no hang.");
}'''),
    ...para('//',
        r'It installs HeapLensAlloc as the global allocator and runs 1,000 '
        r'rounds. Each round makes three allocations of different shapes: '
        r'a String from format!, a Vec<u64> collected from a range of 16, '
        r'and a Box holding a 128-byte array, all dropped at the end of '
        r'the round. The mix is deliberate: three different allocation '
        r'paths, three different sizes. The output line is the test’s '
        r'whole assertion. If you see it, the host survived.'),
    blank,
    ...para('//',
        r'What the loop produces was measured with a scratch copy of the '
        r'same loop, outside the repo, run on Linux with the non-Windows '
        r'backends. With capture enabled, the 1,000 rounds generated '
        r'3,003 or 3,004 alloc events (two runs) and 3,001 dealloc '
        r'events, no reallocs. The sizes '
        r'are as expected: 2,000 allocations of 128 bytes (the Vec<u64> is '
        r'16 x 8 and the Box is 128), and 1,000 of 12 bytes, the String '
        r'that format! sizes for "hello-" plus a number. The handful of '
        r'extras (one allocation each of 4, 15 and 544 bytes, plus 1,024 '
        r'in one of the two runs) are '
        r'presumably the runtime’s own. About 6,000 events is far below '
        r'the ring’s 65,535 capacity, so the program never even fills a '
        r'ring, and the interesting part, what happens to the writer, is '
        r'entirely in the background.'),
    ...sec(r'what happens behind the scenes'),
    ...para('//',
        r'With capture enabled, the first allocation inside record() '
        r'passes the gate and spawns the writer thread. The writer sets '
        r'its recursion guard, warms up the symbol resolver, and enters '
        r'its connect loop: try to open \\.\pipe\heaplens, fail, sleep 100 '
        r'ms, try again, forever. Meanwhile events pile up in the main '
        r'thread’s ring, nobody drains them, and the ring is bounded, so '
        r'memory does not grow. If the ring filled, the extra events would '
        r'be dropped at the cost of one counter increment each. At process '
        r'exit the writer thread is simply killed with the process; it is '
        r'never joined.'),
    blank,
    ...para('//',
        r'That is the entire protocol the header describes: "The writer '
        r'retries the pipe connection in the background. ... Events are '
        r'produced into the ring and dropped when it fills."'),
    ...sec(r'an old test that became a different test'),
    ...para('//',
        r'This file predates the 2026-07-28 change that made capture '
        r'opt-in (commit a31baeb). Today, run without HEAPLENS_ENABLE, '
        r'record() returns before spawning the writer or touching the '
        r'ring. Running the loop that way records zero events, and by the '
        r'code no writer thread is spawned. The example still prints its '
        r'success line, so it still passes, but what it now demonstrates '
        r'by default is the disabled path: a binary that links the '
        r'allocator and does nothing at all. To exercise the retry loop, '
        r'the case the header describes, set HEAPLENS_ENABLE (any value) '
        r'in the environment first. The header’s text has not been updated '
        r'to say so.'),
    blank,
    ...para('//',
        r'That is a small instance of a general hazard in smoke tests: a '
        r'check that passes trivially after the thing it was meant to '
        r'check was switched off. The pass condition here (a printed line) '
        r'cannot tell the two apart. A stronger version would assert '
        r'something observable about the writer: that the thread exists, '
        r'or that the ring received events.'),
    ...sec(r'the run time'),
    ...para('//',
        r'On the Linux sandbox, in a debug build, the whole loop takes '
        r'between 2 and 5 ms with the allocator capturing and 1 to 3 ms '
        r'without (two sessions). It is a '
        r'measurement of one process on a different platform, not a '
        r'performance claim. It does show that nothing in the path blocks: '
        r'3,000 allocations, 3,000 frees, and a writer thread that is busy '
        r'failing to connect cost a few milliseconds.'),
    ...sec(r'what it does not cover'),
    ...pt('//',
        r'a daemon that appears later',
        r'the retry loop is the only code that runs when the daemon starts '
        r'after the program. The launcher starts the daemon first, so a '
        r'program usually finds it there; but any cooperative program run '
        r'by hand before the daemon depends on the retry loop, and nothing '
        r'here checks that connecting later works.'),
    ...pt('//',
        r'multi-threaded programs',
        r'one thread only. See multithread_stress.rs.'),
    ...pt('//',
        r'a daemon that disappears',
        r'write failures and reconnects are not exercised.'),
    ...pt('//',
        r'Windows',
        r'where the failure modes that matter are. The named pipe path '
        r'only exists there.'),
    ...sec(r'related'),
    ...pt('//',
        r'writer.rs',
        r'the connect loop being exercised.'),
    ...pt('//',
        r'lib.rs',
        r'the opt-in gate that now decides whether any of it happens.'),
    ...pt('//',
        r'multithread_stress.rs',
        r'the concurrent version of the same idea.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/examples/alloc_smoke.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/examples/alloc_smoke.rs'),
  ],
);
