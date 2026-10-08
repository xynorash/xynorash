import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/src/capture.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'capture.rs — a clock and a stack walk, and a lock that must never wait'),
    cm('//', r'the two things record() does that the application can feel'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'produces the timestamp and the raw stack for every AllocEvent'),
    kv('language', r'Rust (backtrace crate; the Windows backend ends in dbghelp.dll)'),
    kv('size', r'157 lines: 99 of code and documentation, 58 of tests'),
    kv('history', r'5 commits, 2026-07-01 to 2026-07-26'),
    kv('called from', r'lib.rs record(), steps 3 and 4, always under the recursion guard'),
    ...sec(r'what it does'),
    ...para('//',
        r'Two functions, both called from record() after the re-entrancy '
        r'guard is set. timestamp_nanos() answers "when", capture_stack() '
        r'answers "from where". Everything else the allocator does is '
        r'bookkeeping around these two. They are also the only parts of '
        r'the hot path whose cost the application can notice: a clock read '
        r'and a walk up the call stack. The Build Spec puts the rule on '
        r'both: no allocation, and "Do not resolve symbols here. Capture '
        r'raw IPs only." Symbol resolution is expensive and allocates, so '
        r'it is the writer thread’s job (writer.rs), done once per new '
        r'address, off the critical path.'),
    ...sec(r'the clock'),
    ...code('rust', 'crates/heaplens-alloc/src/capture.rs · timestamp_nanos', r'''
use std::sync::OnceLock;
use std::time::Instant;

/// Process-start instant, initialised once on first call to `timestamp_nanos`.
/// `OnceLock::get_or_init` does not allocate.
static START: OnceLock<Instant> = OnceLock::new();

/// Monotonic timestamp in nanoseconds since process start.
/// Uses `Instant` (QPC on Windows) — no allocation, no unsafe.
#[inline]
pub fn timestamp_nanos() -> u64 {
    let start = START.get_or_init(Instant::now);
    Instant::now().duration_since(*start).as_nanos() as u64
}'''),
    ...para('//',
        r'A OnceLock<Instant> holds a start instant, set the first time '
        r'the function is called, and each call returns the elapsed '
        r'nanoseconds since then. Three decisions are packed into those '
        r'few lines.'),
    blank,
    ...para('//',
        r'Monotonic, never wall-clock. Instant is a monotonic clock (QPC '
        r'on Windows, per the comment). The Build Spec’s cross-cutting '
        r'rules say it flatly: "Time: monotonic only (Instant), never '
        r'wall-clock, for ts_nanos". Wall-clock time can jump, and a tool '
        r'that orders allocation events must never see time go backwards.'),
    blank,
    ...para('//',
        r'A relative origin. The doc comment says "since process start" '
        r'but the code starts the clock at the first call to '
        r'timestamp_nanos, which is the first captured event. In the H1 '
        r'latency data (docs/bench_results/h1_latency.csv) the first child '
        r'allocation shows node_ts_ns around 60,000 to 105,000, tens of '
        r'microseconds in, which fits an origin set by the first event, '
        r'not by the operating system’s process creation. Each producer '
        r'process has its own zero, and nothing in an event says what it '
        r'is relative to. That is workable because the Stage 7 design '
        r'clears the graph on a target switch (section 3.4), so the daemon '
        r'only ever treats timestamps as one process’s logical clock.'),
    blank,
    ...para('//',
        r'No allocation. OnceLock::get_or_init(Instant::now) does not '
        r'allocate, and the comment records the fact because the lib.rs '
        r'history has a case where it does matter: a OnceLock initialiser '
        r'that allocated deadlocked the very first allocation of a '
        r'process. Instant::now() does not allocate, so this one is safe.'),
    blank,
    ...para('//',
        r'Timestamps are what make the daemon’s anomaly ageing work, and '
        r'that has a consequence which shows up in nearly every example '
        r'program: the daemon’s clock (max_ts_seen) advances only when '
        r'events arrive. A process that sits idle produces no events, so '
        r'no time passes for the daemon. This is why demo_producer and the '
        r'chaos examples allocate a tiny heartbeat buffer every 20 or 500 '
        r'ms during their hold periods.'),
    ...sec(r'the stack walk'),
    ...code('rust', 'crates/heaplens-alloc/src/capture.rs · capture_stack', r'''
#[inline]
pub fn capture_stack() -> ([u64; 16], u8) {
    let mut stack = [0u64; 16];
    let mut count = 0usize;
    // Serialize against every other caller of `backtrace`'s Windows backend
    // (this function, called from every allocating thread, and
    // `writer::run`'s `resolve` calls on the writer thread) — see
    // `crate::DBGHELP_LOCK`'s doc comment for why this is required, not
    // just defensive. A poisoned mutex (some other caller panicked while
    // holding it) is treated the same as an uncontended lock — proceed
    // anyway, a stale/corrupt symbol table is a degraded capture, not a
    // reason to crash the allocation this call is instrumenting. A held
    // (contended or orphaned) lock returns an empty, unresolved capture
    // rather than blocking — see this function's doc comment above.
    let guard = match crate::DBGHELP_LOCK.try_lock() {
        Ok(g) => Some(g),
        Err(std::sync::TryLockError::Poisoned(e)) => Some(e.into_inner()),
        Err(std::sync::TryLockError::WouldBlock) => None,
    };
    let Some(_guard) = guard else {
        return (stack, 0);
    };
    // SAFETY: called single-threaded per-thread, guard is held.
    unsafe {
        backtrace::trace_unsynchronized(|frame| {
            if count < 16 {
                stack[count] = frame.ip() as u64;
                count += 1;
                true  // continue walking
            } else {
                false // stop
            }
        });
    }
    (stack, count as u8)
}'''),
    ...para('//',
        r'The function returns a fixed array of 16 instruction pointers '
        r'and a count. It walks the stack with '
        r'backtrace::trace_unsynchronized, writing each frame’s '
        r'instruction pointer into the array and stopping at 16. There is '
        r'no heap use anywhere: the array lives on the caller’s stack, '
        r'which is the point of choosing [u64; 16] over a Vec.'),
    blank,
    ...para('//',
        r'The doc comment states what it deliberately does not do. It does '
        r'not skip any frames and does not filter. The raw trace "always '
        r'starts inside the shared instrumentation chain (capture_stack -> '
        r'record -> the allocator method)", and how many standard-library '
        r'frames then sit between that chain and the user’s code depends '
        r'on which allocation API was called. The comment names the case '
        r'that forced the width of 16: the zeroed-allocation path of '
        r'vec![0u8; n] "inserts 6+ more non-inlined frames than '
        r'Vec::with_capacity". Finding the real call site is delegated, '
        r'per the comment, to "the daemon (graph.rs effective_site), using '
        r'classifications the writer thread ships in the SYMBOLS frame, '
        r'not by any fixed skip count here". A fixed skip would be right '
        r'for one allocation path and wrong for the next.'),
    blank,
    ...para('//',
        r'The line that makes the function unsafe is the call itself. '
        r'trace_unsynchronized is the variant of backtrace’s walker that '
        r'does not take the crate’s internal lock; its own documentation '
        r'says it must not run concurrently on multiple threads without '
        r'external synchronisation. The SAFETY comment here says "called '
        r'single-threaded per-thread, guard is held", where the guard is '
        r'the mutex guard, not the recursion flag. Two different things '
        r'are called a guard in this crate, and they work together: the '
        r'recursion guard stops the walk from re-entering record(), and '
        r'the mutex guard stops two threads walking at once.'),
    ...sec(r'the lock, in two acts'),
    ...para('//',
        r'The mutex is DBGHELP_LOCK, defined in lib.rs. It exists because '
        r'both stack walking and symbol resolution on Windows go through '
        r'dbghelp.dll, which Microsoft documents as not safe for '
        r'concurrent calls. Everything that touches it, the walk on every '
        r'allocating thread and the writer’s resolve calls, must take the '
        r'same lock.'),
    blank,
    ...para('//',
        r'Act one, 2026-07-19 (commit 9c4678e). The lock was added while '
        r'chasing a different bug: in a release build every allocation’s '
        r'effective site resolved to the same wrong address, so ownership '
        r'inference found no edges and Hot and Orphan never fired. The '
        r'cause turned out to be packaging. dbghelp resolves local symbols '
        r'only when the program’s .pdb sits next to its .exe, and a '
        r'packaged build had shipped without them; system DLL exports kept '
        r'resolving, which made the failure look like a race. The commit '
        r'message records the check that settled it: three clean runs from '
        r'a layout with exe and pdb together, and three collapsed runs of '
        r'the identical binary without the pdb. The lock was added in the '
        r'same commit as a related gap, "not the cause of the '
        r'symbol-collapse bug (chaos_hot.rs, where this was found, is '
        r'effectively single-threaded), but a real gap for genuinely '
        r'multi-threaded producers, worth closing while in this code." '
        r'Using lock() there was reasonable. It was the obvious choice.'),
    blank,
    ...para('//',
        r'Act two, 2026-07-26 (commit b5c5aed). A blocking lock on the '
        r'allocation hot path turned out to be a trap.'),
    ...code('rust', 'crates/heaplens-alloc/src/capture.rs · why it is try_lock and never lock', r'''
/// # `DBGHELP_LOCK` uses `try_lock`, never `lock` — confirmed deadlock fix
///
/// A blocking `.lock()` here can hang forever if `DBGHELP_LOCK` is
/// orphaned: confirmed via WinDbg (exact symbol-resolved stack trace,
/// 2026-07-26 investigation) that `RtlExitUserProcess` abruptly terminates
/// a process's other threads, without running their cleanup, when the
/// process exits with hooks still active (no explicit
/// `heaplens-injector --detach`). If one of those threads was caught
/// holding `DBGHELP_LOCK` — inside this exact function — at that instant,
/// the lock is orphaned permanently: nothing will ever release it. The
/// sole surviving thread then reliably deadlocked here, reached via its
/// own FLS-cleanup-triggered heap free routing back through the still
/// -active hook (`hook_heap_free` -> `record` -> `capture_stack` ->
/// `DBGHELP_LOCK.lock()`), confirmed reproducing 7/8 times in the same
/// investigation's batch runs. `try_lock` cannot hang: if the lock is
/// held (orphaned or merely contended — this branch does not need to
/// know which), this call skips symbolization for this one capture and
/// returns an empty stack instead of blocking. A single degraded capture
/// is harmless — every consumer downstream (the daemon's phi inference,
/// the target-diagnostics banner) already tolerates unresolved/hex
/// -fallback symbols as a normal case. A permanent hang is not harmless.
/// The overwhelmingly common case (lock uncontended) behaves identically
/// to the previous `.lock()` call: `try_lock` succeeds immediately, same
/// as `lock` would have, with no added cost.'''),
    ...para('//',
        r'Windows’ RtlExitUserProcess ends a process’s other threads '
        r'abruptly, without running their cleanup, when the process exits '
        r'with hooks still installed. If one of those threads is killed '
        r'while inside capture_stack holding DBGHELP_LOCK, nothing will '
        r'ever release it. The surviving thread then frees memory during '
        r'its own FLS cleanup, that free goes through the still-installed '
        r'hook, into record(), into capture_stack, and blocks on a lock '
        r'that can never be released. The investigation, done with WinDbg '
        r'and a symbol-resolved stack trace, reproduced it "7/8 times" in '
        r'batches. The commit message gives the baseline as 7 to 9 hung '
        r'out of 8 to 10 runs per batch, 40 to 87.5 percent across '
        r'batches, and the validation after the fix as 45 clean runs: 25 '
        r'by hand with exit codes tracked and 20 through cargo test.'),
    blank,
    ...para('//',
        r'The fix is a handful of lines at the top of the function. A lock '
        r'that cannot be taken does not block; the function returns an '
        r'empty capture and the caller carries on. The comment states the '
        r'trade plainly: "A single degraded capture is harmless ... A '
        r'permanent hang is not harmless." And because it does not need to '
        r'know why the lock is unavailable, orphaned or merely contended, '
        r'one code path covers both.'),
    ...code('rust', 'crates/heaplens-alloc/src/capture.rs · the three outcomes of try_lock', r'''
let guard = match crate::DBGHELP_LOCK.try_lock() {
    Ok(g) => Some(g),
    Err(std::sync::TryLockError::Poisoned(e)) => Some(e.into_inner()),
    Err(std::sync::TryLockError::WouldBlock) => None,
};
let Some(_guard) = guard else {
    return (stack, 0);
};'''),
    ...para('//',
        r'Three cases. A free lock yields a guard. A poisoned lock, one '
        r'whose previous holder panicked, is used anyway: "a stale/corrupt '
        r'symbol table is a degraded capture, not a reason to crash the '
        r'allocation this call is instrumenting". A held lock returns '
        r'(stack, 0), all zeroes and a length of zero.'),
    blank,
    ...para('//',
        r'That last case is the cost of the design, and it deserves to be '
        r'said clearly. With many threads allocating at once, any thread '
        r'that arrives while another is mid-walk records an event with no '
        r'stack. Such an event cannot be attributed to a call site by the '
        r'daemon (effective_site_index returns None for an empty stack), '
        r'so it can only become a node with no call site. The doc comment '
        r'argues downstream code tolerates this, and the daemon’s own '
        r'checks agree (its storm detector, for one, only counts events '
        r'with stack_len above zero). The repository contains no '
        r'measurement of how often the empty case happens, so one was made '
        r'for this page and re-run independently during fact-checking. '
        r'A scratch program (outside the repo, depending on the '
        r'unmodified crate by path) installs HeapLensAlloc, sets '
        r'HEAPLENS_ENABLE, runs N threads each doing 5,000 or 10,000 '
        r'iterations of vec![i as u8; 64], joins them, drains the rings '
        r'with ring::drain_all and counts events whose stack_len is zero. '
        r'On a 4-core Linux sandbox in a release build, with the '
        r'non-Windows backtrace backend, two separate runs gave these '
        r'empty fractions at 5,000 iterations: 2 threads 82 and 82 '
        r'percent, 4 threads 73 and 87, 8 threads 83 and 95, 16 threads '
        r'86 and 96. Six runs of 8 threads at 10,000 iterations ranged '
        r'from 84 to 94 percent. So the figure is noisy, but it is high '
        r'every time once more than one thread allocates. A single '
        r'thread was not clean either: 18 to 29 percent over 5,000 '
        r'iterations, yet only 2.5 percent when the loop ran 100,000 '
        r'iterations (the first 65,535 events fit the ring). About the '
        r'same absolute number of events, around 1,600 to 1,800, came '
        r'back empty in both single-thread runs, which fits an early '
        r'burst rather than a steady rate. The likely cause is the '
        r'writer thread’s one-off symbol warm-up holding the same lock '
        r'while the main thread keeps allocating (an inference; the '
        r'measurement does not isolate it). These are single-machine, '
        r'single-build numbers on a different platform, not a Windows '
        r'measurement, and dbghelp walks are probably slower than Linux '
        r'unwinds, which would only lengthen the window in which the '
        r'lock is held. try_lock is also not free of contention, '
        r'since on a hot lock every allocating thread still performs an '
        r'atomic operation on the same cache line.'),
    ...sec(r'tests'),
    ...code('rust', 'crates/heaplens-alloc/src/capture.rs · the first test and its serial lock', r'''
/// `DBGHELP_LOCK` is a single process-wide static — cargo runs this
/// binary's tests in parallel by default, so a test that deliberately
/// holds it (to prove `capture_stack` doesn't block) would otherwise
/// race a concurrent test that expects it free, producing a spurious
/// empty capture there. Serializes just these two tests against each
/// other; same pattern as `ring.rs`'s `REGISTRY_TEST_LOCK`.
static TEST_SERIAL: std::sync::Mutex<()> = std::sync::Mutex::new(());

/// The confirmed deadlock fix's core guarantee: `capture_stack` must
/// never block, even when `DBGHELP_LOCK` is held elsewhere. Holds the
/// lock on a background thread (standing in for the orphaned-lock
/// scenario — from `capture_stack`'s point of view, an orphaned lock
/// and a merely-busy one are indistinguishable, and don't need to be
/// distinguished) and confirms a concurrent `capture_stack` call
/// returns promptly with an empty, unresolved capture instead of
/// waiting for the lock to free up.
#[test]
fn capture_stack_does_not_block_when_dbghelp_lock_is_held() {
    let _serial = TEST_SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    let held = crate::DBGHELP_LOCK.lock().unwrap_or_else(|e| e.into_inner());

    let (tx, rx) = mpsc::channel();
    let handle = std::thread::spawn(move || {
        let result = capture_stack();
        let _ = tx.send(result);
    });

    // Generous bound for scheduling jitter — the whole point is this
    // must return almost immediately (try_lock, no waiting), not that
    // it merely returns eventually.
    let (stack, count) = rx
        .recv_timeout(Duration::from_secs(2))
        .expect("capture_stack blocked instead of returning promptly while DBGHELP_LOCK was held");

    assert_eq!(count, 0, "a held lock must produce an empty capture, not a real one");
    assert_eq!(stack, [0u64; 16], "a held lock must not partially fill the stack array");

    drop(held);
    handle.join().unwrap();
}'''),
    ...para('//',
        r'The test that pins the fix holds DBGHELP_LOCK on the test '
        r'thread, spawns a second thread that calls capture_stack, and '
        r'waits for its answer with recv_timeout(Duration::from_secs(2)). '
        r'The two-second bound is generous for scheduling jitter, and the '
        r'comment names what is being tested: the call must return "almost '
        r'immediately (try_lock, no waiting), not that it merely returns '
        r'eventually". The result must be count == 0 and an array of all '
        r'zeros, so a half-filled array would also fail.'),
    blank,
    ...para('//',
        r'TEST_SERIAL exists for the same reason as REGISTRY_TEST_LOCK in '
        r'ring.rs. DBGHELP_LOCK is a process-wide static and cargo runs a '
        r'binary’s tests in parallel, so a test that deliberately holds '
        r'the lock would make a concurrent capture_stack test see a '
        r'spurious empty capture. The two tests take a private mutex '
        r'first.'),
    ...code('rust', 'crates/heaplens-alloc/src/capture.rs · the common case still works', r'''
    /// The overwhelmingly common case — lock uncontended — must behave
    /// exactly as the previous blocking `.lock()` call did: succeed
    /// immediately and produce a real, non-empty capture.
    #[test]
    fn capture_stack_captures_normally_when_dbghelp_lock_is_free() {
        let _serial = TEST_SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let (stack, count) = capture_stack();
        assert!(count > 0, "an uncontended lock must still produce a real capture");
        assert_ne!(stack[0], 0, "the first captured frame must be a real, non-null address");
    }
}'''),
    ...para('//',
        r'The second test asserts the opposite: with the lock free, '
        r'capture_stack returns count > 0 and a non-null first frame. '
        r'Without it, a broken implementation that always returned the '
        r'empty case would pass the first test. Both pass on a Linux '
        r'sandbox (the crate’s 20 library tests were run there); the '
        r'non-Windows backtrace backend has no dbghelp, so the lock still '
        r'serialises but the deadlock scenario itself is Windows-specific. '
        r'The real regression test is the daemon’s '
        r'hook_owner_free_no_crash.rs, in which the same commit un-ignored '
        r'multithreaded_exit_without_detach_is_clean.'),
    ...sec(r'limits'),
    ...pt('//',
        r'empty captures under contention',
        r'described above; in the Linux run most multi-threaded events had '
        r'no stack.'),
    ...pt('//',
        r'a global lock on a per-allocation path',
        r'even though try_lock never waits, it serialises stack walks '
        r'across all threads, so at most one thread walks at a time; the '
        r'others get no stack.'),
    ...pt('//',
        r'16 frames',
        r'a deeper allocation context than 16 frames is truncated, and the '
        r'oldest (outermost) frames, the ones nearest main, are the ones '
        r'lost.'),
    ...pt('//',
        r'relative clock',
        r'described above.'),
    ...pt('//',
        r'Windows in practice',
        r'the walk uses whatever the backtrace crate’s backend offers; the '
        r'non-Windows path exists so the crate compiles elsewhere.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/src/capture.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/src/capture.rs'),
  ],
);
