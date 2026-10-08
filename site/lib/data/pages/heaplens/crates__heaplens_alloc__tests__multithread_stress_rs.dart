import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/tests/multithread_stress.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'multithread_stress.rs — eight threads, one real assertion, and a gate '
              r'that now needs a key'),
    cm('//', r'the only test that runs HeapLensAlloc as the process allocator under '
              r'concurrency'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'installs HeapLensAlloc as the global allocator and hammers it from 8 '
              r'threads'),
    kv('language', r'Rust integration test'),
    kv('size', r'38 lines, 1 test; 80,000 allocations of 64 bytes'),
    kv('history', r'4 commits: de6f6a5, 699c3cf (2026-07-01), ba1a066 (2026-07-01), '
              r'fa3fe78 (2026-07-22)'),
    kv('needs', r'HEAPLENS_ENABLE in the environment, since 2026-07-28'),
    ...sec(r'what it is for'),
    ...para('//',
        r'Most of the crate is tested as parts: the ring, the guard, the '
        r'classifier. This is the one test that puts the whole machine '
        r'together in a single binary. The test file declares '
        r'HeapLensAlloc as its #[global_allocator], so every allocation '
        r'made by the test harness, the threads and the standard library '
        r'goes through record(), and then it lets eight threads allocate '
        r'and free as fast as they can. The question it answers is the '
        r'blunt one from the Build Spec’s test plan: "stress test ... '
        r'asserting no deadlock, bounded memory, drop-counter behavior '
        r'under saturation".'),
    ...sec(r'the test'),
    ...code('rust', 'crates/heaplens-alloc/tests/multithread_stress.rs · concurrent_allocs_no_deadlock', r'''
// Many threads allocating concurrently. Uses HeapLensAlloc as global allocator.
// Asserts: no deadlock (test completes), bounded memory (dropped counter works),
// and no host process crash.

use heaplens_alloc::HeapLensAlloc;

#[global_allocator]
static GLOBAL: HeapLensAlloc = HeapLensAlloc::new();

#[test]
fn concurrent_allocs_no_deadlock() {
    const THREADS: usize = 8;
    const ITERS: usize = 10_000;

    let handles: Vec<_> = (0..THREADS)
        .map(|_| {
            std::thread::spawn(|| {
                for i in 0..ITERS {
                    let v: Vec<u8> = vec![i as u8; 64];
                    std::hint::black_box(v);
                }
            })
        })
        .collect();

    for h in handles {
        h.join().expect("thread must not panic");
    }

    // drain_all requires the recursion guard to be permanently set on the
    // calling thread (writer-thread invariant §12.4).
    heaplens_alloc::guard::force_enter_permanent();

    // Drain all recorded events and assert that at least one was captured.
    let mut count = 0usize;
    heaplens_alloc::ring::drain_all(usize::MAX, |_ev| { count += 1; });
    assert!(count > 0, "expected at least one recorded event, got 0");
}'''),
    ...para('//',
        r'Each of 8 threads runs 10,000 iterations of let v: Vec<u8> = '
        r'vec![i as u8; 64], passed to std::hint::black_box so the '
        r'optimiser cannot delete the allocation. Each iteration is an '
        r'alloc and a dealloc, so the workload is 80,000 allocations and '
        r'80,000 frees across the threads. The main thread then joins them '
        r'all, with .expect("thread must not panic"), sets its own '
        r'recursion guard permanently (the same precondition the writer '
        r'thread meets, because drain_all debug-asserts it), and drains '
        r'every ring, counting events.'),
    blank,
    ...para('//',
        r'The only conditions that can fail the test are a thread '
        r'panicking, the test hanging, or the count being zero. That last '
        r'assertion has a history. The first version, in commit de6f6a5, '
        r'ended with the comment "If we reach here without deadlock or '
        r'abort, the test passes." and nothing else. A review fix in '
        r'699c3cf the same day added the drain and the count: "fulfilling '
        r'the spec requirement for both (1) draining and (2) meaningful '
        r'assertion on the drained event count". A test that cannot fail '
        r'for the wrong reason is worth more than one that passes by '
        r'surviving.'),
    ...sec(r'what the header promises and what is asserted'),
    ...para('//',
        r'The comment at the top of the file says it asserts: "no deadlock '
        r'(test completes), bounded memory (dropped counter works), and no '
        r'host process crash". The first and third hold: completion is the '
        r'evidence, and a crash would take the test process with it. The '
        r'middle one is not asserted. Nothing in the file reads the '
        r'dropped counter, and the workload cannot reach the saturation '
        r'that would make it move. Each thread produces about 20,000 '
        r'events and a ring holds 65,535, so no ring fills. The Build '
        r'Spec’s phrase for the other half of the plan is "drop-counter '
        r'behavior under saturation", and this test never saturates '
        r'anything.'),
    blank,
    ...para('//',
        r'The workload was measured in a scratch program outside the repo '
        r'that uses the crate unchanged (a Linux sandbox, 4 cores, release '
        r'build, the non-Windows backends). It ran the same 8 threads by '
        r'10,000 iterations of the same allocation and drained the rings '
        r'afterwards. The result, over several runs: 160,060 to 160,070 '
        r'events recorded (one run counted 80,036 allocs and 80,034 '
        r'deallocs), which is the expected 2 per iteration plus 60 to 70 '
        r'extra events from thread spawning and the harness. Nothing was '
        r'dropped. The rings alone are 8 threads at 10.5 MiB, at least '
        r'84 MiB.'),
    blank,
    ...para('//',
        r'The same scratch run had a less comfortable number. Of the '
        r'roughly 160,000 events, between 134,541 and 150,917 (84 to 94 '
        r'percent, over six runs by two sessions) had stack_len equal to '
        r'zero. That is the try_lock '
        r'behaviour from capture.rs, shown at work: with eight threads '
        r'allocating at once, most captures find DBGHELP_LOCK held and '
        r'return an empty stack. The assertion count > 0 does not look at '
        r'stacks, so this test is blind to it. The numbers are Linux '
        r'numbers and indicative only.'),
    blank,
    ...para('//',
        r'A second scratch run shows saturation, which the test does not: '
        r'with one thread doing 100,000 iterations (about 200,000 events), '
        r'the drain recovered about 65,550 (65,535 of them from that '
        r'thread’s ring). The ring filled and the rest were dropped '
        r'silently.'),
    ...sec(r'the gate, and why the test fails today without a key'),
    ...code('rust', 'crates/heaplens-alloc/tests/multithread_stress.rs · the drain and the one count assertion', r'''
// drain_all requires the recursion guard to be permanently set on the
// calling thread (writer-thread invariant §12.4).
heaplens_alloc::guard::force_enter_permanent();

// Drain all recorded events and assert that at least one was captured.
let mut count = 0usize;
heaplens_alloc::ring::drain_all(usize::MAX, |_ev| { count += 1; });
assert!(count > 0, "expected at least one recorded event, got 0");'''),
    ...para('//',
        r'On 2026-07-28 commit a31baeb made capture opt-in: record() '
        r'returns before capturing anything unless HEAPLENS_ENABLE is set '
        r'or the writer was already started. This file was not touched by '
        r'that commit. Running it on Linux without the variable gives:'),
    blank,
    cm('//', r'thread ’concurrent_allocs_no_deadlock’ panicked at'),
    cm('//', r'  crates/heaplens-alloc/tests/multithread_stress.rs:37:5:'),
    cm('//', r'expected at least one recorded event, got 0'),
    blank,
    ...para('//',
        r'With HEAPLENS_ENABLE=1 it passes, in 0.06 s. A scratch run of '
        r'the same workload without the variable recorded 0 events, which '
        r'confirms the gate is doing its job. So the file as committed is '
        r'out of step with the library: under a plain cargo test it fails, '
        r'with a message that does not say why. The fix is one line, '
        r'setting the variable before the first allocation or, since the '
        r'gate is read lazily and cached, in the test’s environment. It '
        r'was left unchanged here, and the Windows-specific parts could '
        r'not be run.'),
    ...sec(r'why a stress test belongs here at all'),
    ...para('//',
        r'The test binary’s very first allocation goes through record() '
        r'with the guard taken before the opt-in check, the ordering whose '
        r'absence once deadlocked the first allocation any process made '
        r'(the lib.rs page tells that story). The test does not exercise '
        r'the Windows-only failures (the thread-local crash only appears '
        r'in a DLL loaded at run time). Those are covered by the hook '
        r'crate’s self-load harness.'),
    ...sec(r'things the test does not do'),
    ...pt('//',
        r'apply sustained load',
        r'80,000 allocations finish in well under a second. The Build Spec '
        r'asked for millions.'),
    ...pt('//',
        r'saturate a ring',
        r'see above.'),
    ...pt('//',
        r'run with a daemon',
        r'the writer thread is spawned, finds no pipe, and retries every '
        r'100 ms forever, so it never drains. If a daemon were listening, '
        r'the writer would drain concurrently and the final count would be '
        r'smaller, though almost certainly not zero.'),
    ...pt('//',
        r'check the content of events',
        r'only the count.'),
    ...pt('//',
        r'run on Windows in this review',
        r'it was run on Linux; the same logic applies, but the '
        r'thread-local and FLS code differ.'),
    ...sec(r'related'),
    ...pt('//',
        r'lib.rs',
        r'record() and the opt-in gate.'),
    ...pt('//',
        r'ring.rs',
        r'the structure being filled.'),
    ...pt('//',
        r'capture.rs',
        r'the lock behind the empty stacks.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/tests/multithread_stress.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/tests/multithread_stress.rs'),
  ],
);
