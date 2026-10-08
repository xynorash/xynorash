import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/docs/superpowers/plans/2026-07-01-heaplens-alloc.md',
  lines: [
    heading('# HeapLens Stage 2 — heaplens-alloc Implementation Plan'),
    blank,
    ...text('The plan for the part of HeapLens that is allowed '
        'no mistakes: code that runs inside every allocation of '
        'someone else’s program. It was written, executed in '
        'fifty-six minutes, and then slowly corrected by three '
        'weeks of reality. The distance between what it says and '
        'what the code does today is a map of what was hard.'),
    blank,
    kv('role', 'task-by-task build plan for Stage 2, the allocator crate'),
    kv('date', '2026-07-01, committed 15:25 (5eae219)'),
    kv('size', '1,213 lines · 8 tasks · full code for every module'),
    kv('executed', '15:28 to 16:21 the same afternoon, 14 commits'),
    kv('depends on', 'heaplens-protocol (Stage 1)'),

    ...sec('what the stage must achieve'),
    ...text('The goal sentence says it all: a global allocator '
        'that intercepts every allocation and ships raw event '
        'records off-process over a Windows named pipe, “without '
        'allocating or locking on the hot path”. Everything else '
        'is mechanism. The architecture paragraph names the '
        'mechanism in one breath: wrap the system allocator; call '
        'record() on every operation; under a per-thread RAII '
        'recursion guard capture a timestamp and up to eight raw '
        'stack addresses; push onto a per-thread lock-free ring; '
        'let one background writer thread drain every ring, '
        'resolve symbols in-process, and flush frames to the pipe.'),
    ...text('Before any task the plan lists global constraints, '
        'and they are the Build Spec’s invariants restated in the '
        'plan’s own words so the executor sees them on every '
        'page:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-01-heaplens-alloc.md · Global Constraints (trimmed)', r'''
- No heap allocation on the critical path (`record` and everything it calls)
- No locks on the critical path: lock-free ring only for the producer.
- Never panic in the host process. All error paths are silent returns or `abort`.
- The writer thread permanently holds the recursion guard (first thing it does on entry).'''),
    ...text('The acceptance checklist at the end turns the last '
        'one into something grep can check: “Writer thread: first '
        'line is guard::force_enter_permanent()”. A rule that can '
        'be verified by reading one line gets verified.'),

    ...sec('the shape: interfaces first'),
    ...text('The file map lists five source files and one '
        'example, with the signatures that cross module '
        'boundaries written down before the modules exist:'),
    ...bullet('guard',
        'is_set() -> bool, ScopedGuard::enter(), '
        'force_enter_permanent().'),
    ...bullet('ring',
        'push(AllocEvent) -> bool for the producer, '
        'drain_all(FnMut(AllocEvent)) for the writer.'),
    ...bullet('capture',
        'timestamp_nanos() and capture_stack().'),
    ...bullet('writer',
        'run(), the thread entry point.'),
    blank,
    ...text('Each task then repeats Consumes and Produces lines, '
        'so the dependency chain is explicit. That is what lets '
        'these eight tasks be handed to separate workers: no '
        'module needs another’s internals.'),

    ...sec('the tasks, and what became of each'),
    ...text('Commit times below are from the repository. The '
        'stage went from plan to “clippy clean” in fifty-six '
        'minutes (15:25 to 16:21), with 14 commits after the '
        'plan itself.'),
    ...bullet('Task 1, scaffold (15:28)',
        'a crate that builds with stub modules. The plan lists '
        'windows-sys as a dependency. The final review pass '
        'removed it as unused (ba1a066): the writer opens the '
        'pipe through std::fs and needs no Win32 call.'),
    ...bullet('Task 2, guard (15:30)',
        'five tests first, then a thread-local flag with a '
        'panic-safe RAII guard. Covered in detail below.'),
    ...bullet('Task 3, ring (15:32, fixed 15:37)',
        'the lock-free ring and the per-thread registry. The '
        'push and pop code survived unchanged; the registry '
        'drain had a race, found in five minutes.'),
    ...bullet('Task 4, capture (15:40)',
        'timestamps and raw stack walks. Eight frames became '
        'sixteen on 2026-07-08.'),
    ...bullet('Task 5, record() (15:42, fixed 15:45)',
        'the allocator itself. Null guards and a reordered '
        'dealloc arrived three minutes later.'),
    ...bullet('Task 6, writer (15:47, fixed 15:52 and 15:53)',
        'connect, handshake, batch, resolve, flush. The '
        'reconnect logic was wrong in a way that matters.'),
    ...bullet('Task 7, tests and the smoke example (15:55, 15:59)',
        'integration tests plus alloc_smoke. One test could not '
        'fail.'),
    ...bullet('Task 8, clippy (16:01)',
        'clean under -D warnings, then a final review commit at '
        '16:21 with six fixes.'),

    ...sec('task 2: the guard, and the three-week assumption'),
    ...text('The plan’s guard is the obvious Rust: a '
        'thread_local Cell<bool>, set on entry and cleared in a '
        'Drop impl so even a panic cannot leave it stuck.'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-01-heaplens-alloc.md · Task 2 (trimmed)', r'''
thread_local! {
    static IN_ALLOC: Cell<bool> = const { Cell::new(false) };
}'''),
    ...text('It worked for 20 days. The tests the plan wrote '
        '(starts clear on a fresh thread, sets and clears, clears '
        'after a panic, re-entrant call blocked, permanent mode '
        'stays set) all passed, and all five are still in '
        'guard.rs. The assumption '
        'underneath them was that a thread-local lives on every '
        'thread. That is true for a program that links the crate '
        'at startup and false for a DLL loaded later with '
        'LoadLibrary, which is exactly what Stage 7 does. On '
        '2026-07-21 the plan’s three lines became this:'),
    ...code('rust', 'crates/heaplens-alloc/src/guard.rs · imp (Windows)', r'''
    static TLS_INDEX: OnceLock<u32> = OnceLock::new();
        *TLS_INDEX.get_or_init(|| unsafe { TlsAlloc() })
        unsafe { !TlsGetValue(index()).is_null() }'''),
    ...text('The test suite was not wrong, just silent about the '
        'unlisted case. Every plan test runs on threads the '
        'process created; none runs on a thread the loader never '
        'told about this module. The lesson for a plan is that '
        '“the tests pass” is a statement about the cases you '
        'thought of, and the interesting hazards live in how the '
        'code will be loaded, not in what it computes.'),

    ...sec('task 3: a race in the registry drain, fixed in five minutes'),
    ...text('The ring’s producer side needed no change. The push '
        'and pop functions in the plan are identical, comments '
        'included, to the ones in ring.rs today: relaxed load of '
        'the tail, acquire load of the head, write, release store '
        'of the new tail.'),
    ...code('rust', 'crates/heaplens-alloc/src/ring.rs · push() (trimmed)', r'''
        let tail = self.tail.load(Ordering::Relaxed);
        let next = (tail + 1) & (CAP - 1);
        if next == self.head.load(Ordering::Acquire) {'''),
    ...text('What changed was the writer’s side. The plan’s '
        'drain_all emptied each ring, checked whether the '
        'producing thread was dead, and if so removed the ring '
        'from the registry:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-01-heaplens-alloc.md · Task 3 drain_all (trimmed)', r'''
    while i < reg.len() {
        while let Some(ev) = reg[i].pop() {
            f(ev);
        }
        if !reg[i].producer_alive.load(Ordering::Acquire) {
            reg.swap_remove(i); // dead + empty: reclaim slot'''),
    ...text('Between the pop loop saying “empty” and the flag '
        'saying “dead”, the producer could push one more event '
        'and exit. The ring would then be removed with that '
        'event still in it. Five minutes after the first commit, '
        '1f417d1 added a second drain after the acquire load '
        'that observes death:'),
    ...code('rust', 'crates/heaplens-alloc/src/ring.rs · drain_all (trimmed)', r'''
            // The Acquire on producer_alive synchronizes with the thread's death Release,
            // which transitively happens-after the last push's tail Release.'''),
    ...text('The commit’s comment frames it as a weak-memory '
        'problem. The same sequence is also a plain interleaving '
        'race that needs no weak hardware, which is an interpretation '
        'and not the comment’s. Either way the repair is the same, and '
        'the only reason it is cheap is that thread exit is rare.'),
    ...text('Later the function gained a parameter. Under '
        'sustained multi-thread load an uncapped drain swept '
        'every thread’s full ring into one batch, over the wire '
        'format’s 16-bit event count, and panicked the writer '
        '(fa3fe78). drain_all(max, f) now takes the batch’s '
        'remaining capacity. The plan’s version of the problem '
        'was invisible at eight threads and ten thousand '
        'iterations.'),

    ...sec('tasks 5 and 6: record() and the writer'),
    ...text('The plan’s record() has seven steps, and step 3 is '
        '“ensure the writer thread is running”. The first '
        'committed version put it last instead, after the push:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-01-heaplens-alloc.md · Task 5, step 3', r'''
    // 3. Ensure writer thread is running. Safe under guard: any allocations'''),
    ...code('rust', 'crates/heaplens-alloc/src/lib.rs · record()', r'''
    // 7. Ensure writer thread is running. Safe under guard: any allocations'''),
    ...text('No commit explains the move. The effect is that '
        'the first event is already in the ring before the '
        'thread that will drain it is spawned. The same function '
        'later acquired the opt-in check (HEAPLENS_ENABLE) and '
        'the explicit entry points the hook DLL needs, and its '
        'comments grew into essays about deadlocks; the skeleton '
        'is still the plan’s.'),
    ...text('Three small fixes in the first ten minutes show the '
        'kind of mistake a plan this detailed still contains.'),
    ...bullet('null returns (69e61dd)',
        'a failed allocation returned a null pointer, which the '
        'plan recorded as an event. The code now returns early on '
        'null for alloc and realloc.'),
    ...bullet('dealloc order (69e61dd)',
        'the plan records the free after returning the memory to '
        'the system. The code records first. The commit does not '
        'say why. A plausible reading: once memory is returned, another '
        'thread may be handed the same address and record its '
        'allocation before this thread records the free, so the '
        'daemon would see the pair in the wrong order.'),
    ...bullet('reconnect (29b1458)',
        'the plan’s writer keeps its symbol cache across '
        'reconnects, with a comment saying why:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-01-heaplens-alloc.md · Task 6 (trimmed)', r'''
        // Fell through 'send → reconnect. symbol_cache is preserved across
        // reconnects so we don't re-emit already-sent symbol definitions.'''),
    ...text('That reasoning is backwards. A new connection means a '
        'new daemon session with an empty symbol table, and '
        'addresses the writer believes were “already sent” will '
        'never be defined there. The fix is one line at the top '
        'of the loop (symbol_cache.clear()), committed five '
        'minutes after the writer, and the same class of bug '
        'came back in a more expensive form on 2026-07-26 when the '
        'daemon reset itself on a re-attach and the writer’s '
        'per-connection cache never re-sent anything (b649234).'),

    ...sec('task 7: a test that could not fail'),
    ...text('The plan’s multi-threaded stress test spawns eight '
        'threads, each allocating ten thousand small vectors, '
        'joins them, and then ends with this comment instead of '
        'an assertion:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-01-heaplens-alloc.md · Task 7 (trimmed)', r'''
    // If we reach here without deadlock or abort, the test passes.'''),
    ...text('A deadlock test that finishes proves no deadlock, '
        'and that has value. But the test header also promises '
        'a bounded-memory check, and the body checked nothing '
        'about events. The review commit (699c3cf) states what '
        'was missing: it was fixing the test, in the commit’s words, '
        'to fulfil “the spec requirement for both (1) draining and '
        '(2) meaningful assertion on the drained event count”. '
        'The test now drains the rings after the '
        'join and asserts at least one event was captured. '
        'Today it also sets the recursion guard first, because a '
        'debug assertion in drain_all rejects any caller that is '
        'not the writer thread.'),
    ...text('The same task contains a self-correction inside the '
        'plan itself, a sign of how these documents were written '
        'by iterating on the page:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-01-heaplens-alloc.md · Task 7 (trimmed)', r'''
But wait: `guard`, `ring`, `capture` are private modules in `lib.rs`.'''),
    ...text('Integration tests live outside the crate and cannot '
        'see private modules, so the plan marks guard and ring '
        'public with doc(hidden). The same document names the file '
        'ring_tests.rs in one place and creates ring_integration.rs '
        'in another; the repository has the latter. The plan is '
        'executable, not flawless, and the executor was expected '
        'to reconcile the two.'),

    ...sec('the final review pass'),
    ...text('Commit ba1a066, at 16:21, bundles six fixes from '
        'a review of the whole stage. Its message is a list, and '
        'every item is an invariant defended:'),
    ...bullet('writer busy-spin',
        'a branch structure let a batch with fewer than 64 events '
        'and no flush due loop without sleeping. Collapsed to a '
        'single else-sleep.'),
    ...bullet('drain_all guard',
        'a debug assertion that the caller holds the permanent '
        'recursion guard, so the writer-only rule is enforced and '
        'not just documented.'),
    ...bullet('ScopedGuard::enter',
        'a debug assertion that it is not called on a '
        'permanently-guarded thread.'),
    ...bullet('writer spawn failure',
        'a WRITER_DEAD flag, so record() stops filling a ring '
        'that nothing will ever drain.'),
    ...bullet('unused dependency',
        'windows-sys removed.'),
    ...bullet('tests',
        'updated to satisfy the new assertions.'),
    blank,
    ...text('Note the pattern: each review fix converts an '
        'implicit assumption into a check that fails loudly in a '
        'debug build, which is what the later TLS and hook '
        'investigations came to rely on.'),

    ...sec('what the plan could not know'),
    ...bullet('the DLL case',
        'thread_local! and lazy thread spawning are fine in a '
        'statically linked allocator and fatal in a hook loaded '
        'at run time. Four public functions now exist for the '
        'hook (ensure_writer_started, warm_up_symbol_resolution, '
        'request_writer_stop_and_wait, shutdown_ring_storage).'),
    ...bullet('stack depth',
        'the plan captures up to eight frames; the real number is '
        'sixteen, because zero-initialised allocations push six '
        'std frames above user code.'),
    ...bullet('symbols are not neutral',
        'the writer resolves a name and nothing else. The real '
        'one also classifies each frame as machinery or program '
        'code, serialises dbghelp behind a lock, and needs the '
        'PDB file next to the executable.'),
    ...bullet('consent',
        'linking the allocator now does nothing by itself: '
        'cooperative capture needs HEAPLENS_ENABLE.'),
    blank,
    ...text('None of that makes the plan a failure. It shows '
        'where the plan’s model of the world ended, and every '
        'extension was possible because the plan’s boundaries '
        '(guard, ring, capture, writer) were clean enough to '
        'extend one at a time.'),

    ...sec('limits, and what to take from it'),
    ...bullet('no post-implementation notes',
        'unlike the Stage 3 plan, this one was never amended. '
        'The knowledge sits in commit messages and in doc '
        'comments, which for guard.rs and ring.rs have grown into '
        'long accounts of the crashes behind them.'),
    ...bullet('plan code is not the repository',
        'about the only module whose body survived verbatim is '
        'the ring’s push and pop.'),
    ...bullet('timing of the review',
        'two bugs the stage hid (the TLS assumption and the '
        'uncapped drain) were found weeks later, under conditions '
        'no Stage 2 test created.'),
    blank,
    ...text('The portable lesson: put the invariants at the top '
        'of the plan, make every module’s interface explicit, '
        'and expect the hardest bugs to be in what the plan '
        'assumed about its environment. The assumptions deserve '
        'a section of their own, and in this project, eventually, '
        'they got one in every doc comment.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
