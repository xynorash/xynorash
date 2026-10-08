import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/src/lib.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'lib.rs — the allocator that watches itself'),
    cm('//', r'a GlobalAlloc wrapper, a record() with seven ordered steps, and the '
              r'lifecycle hooks a foreign DLL needs'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'crate root: HeapLensAlloc, record(), writer lifecycle, opt-in gate, '
              r'hooks for heaplens-hook'),
    kv('language', r'Rust (unsafe GlobalAlloc impl, atomics, std::thread)'),
    kv('size', r'336 lines; 191 of the 309 non-blank lines are comments (62 percent)'),
    kv('history', r'10 commits, 2026-07-01 to 2026-07-28'),
    kv('two audiences', r'programs that use #[global_allocator], and the injected hook DLL'),
    ...sec(r'the integration is three lines'),
    ...code('rust', 'crates/heaplens-alloc/src/lib.rs · HeapLensAlloc and its usage doc', r'''
/// A `#[global_allocator]` that intercepts every (de/re)allocation and ships
/// raw `AllocEvent` records off-process via a named pipe, without blocking
/// or allocating on the hot path.
///
/// # Usage
/// ```no_run
/// use heaplens_alloc::HeapLensAlloc;
/// #[global_allocator]
/// static GLOBAL: HeapLensAlloc = HeapLensAlloc::new();
/// ```
///
/// **Linking this in does nothing by itself.** No pipe connection is ever
/// attempted unless the process is run with `HEAPLENS_ENABLE` set (any
/// value) — see `cooperative_capture_enabled`'s doc comment. This is
/// deliberate: HeapLens must never be automatically attached to anything,
/// and a binary that merely links `HeapLensAlloc` is not, by itself, a
/// request to be observed. If enabled, the background writer thread is
/// spawned lazily on first record; it permanently holds the recursion
/// guard so none of its own allocations are ever recorded.
pub struct HeapLensAlloc;

impl HeapLensAlloc {
    pub const fn new() -> Self { HeapLensAlloc }
}

impl Default for HeapLensAlloc {
    fn default() -> Self {
        Self::new()
    }
}'''),
    ...para('//',
        r'The public surface the Build Spec asked for is deliberately '
        r'tiny: "No macros, no other API". A program adds a static of type '
        r'HeapLensAlloc, marks it #[global_allocator], and every '
        r'allocation in the process now passes through this crate. '
        r'HeapLensAlloc::new() is const because a global allocator must be '
        r'constructible in a static. The struct has no fields: all the '
        r'state is in module-level statics, because the allocator is '
        r'invoked before and during everything else and cannot hold '
        r'references to anything that needs initialising.'),
    blank,
    ...para('//',
        r'The doc comment says what it does and, since 2026-07-28, what it '
        r'does not: "Linking this in does nothing by itself." The next '
        r'section is why.'),
    ...sec(r'the allocator impl: wrap System, then tell the ring'),
    ...code('rust', 'crates/heaplens-alloc/src/lib.rs · GlobalAlloc for HeapLensAlloc', r'''
unsafe impl GlobalAlloc for HeapLensAlloc {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let ptr = System.alloc(layout);
        if ptr.is_null() {
            return ptr;
        }
        record(EventKind::Alloc, ptr as u64, 0, layout.size() as u64, layout.align() as u32);
        ptr
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        record(EventKind::Dealloc, ptr as u64, 0, layout.size() as u64, layout.align() as u32);
        System.dealloc(ptr, layout);
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        let new_ptr = System.realloc(ptr, layout, new_size);
        if new_ptr.is_null() {
            return new_ptr;
        }
        record(
            EventKind::Realloc,
            new_ptr as u64,
            ptr as u64,
            new_size as u64,
            layout.align() as u32,
        );
        new_ptr
    }
}'''),
    ...para('//',
        r'Each method delegates the real work to std::alloc::System and '
        r'records an event around it. Three small decisions are visible '
        r'here, and two of them were added after the first draft, in '
        r'commit 69e61dd the same day.'),
    blank,
    ...para('//',
        r'A null result from System.alloc or System.realloc returns '
        r'immediately without recording. A failed allocation is not an '
        r'allocation, and recording a null pointer would invent a node.'),
    blank,
    ...para('//',
        r'In dealloc the event is recorded before System.dealloc runs, not '
        r'after. The commit message says only "dealloc ordering". The '
        r'likely reason, which the code does not state, is a race on '
        r'pointer reuse: the moment the real free returns, another '
        r'thread’s allocator can hand the same address out again. Each '
        r'thread has its own ring, and the writer merges rings, so if the '
        r'Dealloc were recorded after the free, the other thread’s Alloc '
        r'for that same address could reach the writer first, and the '
        r'daemon would see "allocate p, then free p" and remove the new '
        r'node. Recording first makes the Dealloc a statement made while '
        r'the address is still unambiguously ours. realloc records after '
        r'the call, because the new pointer and size are only known then. '
        r'By the same reading it leaves a small window in which the old '
        r'address can be reused before the Realloc is recorded; whether '
        r'that matters in practice was not tested.'),
    blank,
    ...para('//',
        r'alloc_zeroed is not overridden, so vec![0u8; n] reaches the '
        r'default implementation, which calls alloc. That detour is why '
        r'zeroed allocations carry several extra standard-library frames '
        r'in the captured stack (see the event.rs page).'),
    ...sec(r'record(): seven steps in a deliberate order'),
    ...code('rust', 'crates/heaplens-alloc/src/lib.rs · record()', r'''
pub fn record(kind: EventKind, ptr: u64, old_ptr: u64, size: u64, align: u32) {
    // 1. Re-entrancy check — must be the very first thing.
    if guard::is_set() { return; }

    // 2. Acquire guard (panic-safe RAII) — before anything below that
    // might itself allocate. `cooperative_capture_enabled()`'s
    // `std::env::var_os` call is exactly such a case (confirmed: it
    // allocates internally on Windows to build the OsString). Without the
    // guard held first, that nested allocation re-enters `record()` before
    // `guard::is_set()` would see it, which re-enters
    // `cooperative_capture_enabled()`, which calls `OnceLock::get_or_init`
    // recursively while the outer call is still running — documented by
    // `OnceLock` to deadlock or panic. Confirmed empirically: with the
    // check ordered before this guard acquisition, the very first
    // allocation any cooperative process ever makes deadlocks it silently,
    // before even its own first `println!`.
    let _g = guard::ScopedGuard::enter();

    // Never auto-attach: if capture was never explicitly started — neither
    // via cooperative opt-in (HEAPLENS_ENABLE) nor via heaplens-hook's
    // eager ensure_writer_started() call at attach time (which fires
    // WRITER_ONCE before any hook is enabled, so is_completed() is true by
    // the time an injected trampoline ever reaches this function) — bail
    // out now, before any further capture work happens.
    if !WRITER_ONCE.is_completed() && !cooperative_capture_enabled() {
        return;
    }

    // Early-exit if the writer thread failed to spawn; no consumer exists.
    if WRITER_DEAD.load(Ordering::Relaxed) { return; }

    // 3. Timestamp (no alloc).
    let ts = capture::timestamp_nanos();

    // 4. Raw stack capture (no alloc; unsafe justified in capture.rs).
    let (stack, stack_len) = capture::capture_stack();

    // 5. Construct event (no alloc; enforces _pad = [0,0] via AllocEvent::new).
    let ev = AllocEvent::new(kind, ptr, old_ptr, size, align, ts, stack, stack_len);

    // 6. Push to per-thread ring (lock-free, no alloc after TLS init).
    //    Returns false if full — event is silently dropped.
    ring::push(ev);

    // 7. Ensure writer thread is running. Safe under guard: any allocations
    //    inside call_once are suppressed by the guard.
    ensure_writer();

    // _g drops here, clearing the guard even if earlier steps panicked.
}'''),
    ...para('//',
        r'The doc comment lists four invariants, and the body is the '
        r'checklist: (1) check the re-entrancy guard first and return if '
        r'set; (2) enter the scoped guard, before anything that might '
        r'itself allocate; then the opt-in gate and the dead-writer check; '
        r'(3) take a timestamp; (4) capture the raw stack; (5) build the '
        r'AllocEvent through its constructor; (6) push to the per-thread '
        r'ring, silently dropping if full; (7) make sure the writer thread '
        r'exists. The guard clears when _g drops, even if something above '
        r'panicked.'),
    blank,
    ...para('//',
        r'Steps 1 and 2 are the story of the file’s best-documented bug. '
        r'The opt-in gate reads an environment variable, and on Windows '
        r'that allocates (it builds an OsString). The original order '
        r'checked the gate first, then took the guard. The first '
        r'allocation any process ever made therefore called record(), '
        r'which called the gate, which allocated, which re-entered '
        r'record() before the guard was set; the nested call reached the '
        r'gate’s once-only initialiser while the outer call was still '
        r'inside it. The comment records the symptom: "the very first '
        r'allocation any cooperative process ever makes deadlocks it '
        r'silently, before even its own first println!". Moving the guard '
        r'above the gate fixed that. It was confirmed empirically, in the '
        r'comment’s own word, and the reason is now a paragraph so that no '
        r'one tidies the order back.'),
    blank,
    ...para('//',
        r'The gate itself was the second half of the fix, and it has its '
        r'own page of lore.'),
    ...sec(r'never auto-attach'),
    ...code('rust', 'crates/heaplens-alloc/src/lib.rs · the cooperative opt-in', r'''
/// Cooperative auto-connect must never be silent. A `HeapLensAlloc`-linked
/// binary launched with `HEAPLENS_ENABLE` unset does nothing — no pipe
/// connection is ever attempted — regardless of how many allocations it
/// makes. This is the enforcement point for "HeapLens must never be
/// automatically attached to anything": launching such a binary is not, by
/// itself, an explicit request to be observed. Set `HEAPLENS_ENABLE=1`
/// (any value) to opt a specific run in.
///
/// This does not gate `heaplens-hook`'s injection path — attaching via the
/// injector (CLI or the Flutter UI's picker) is already the explicit
/// action; see `ensure_writer_started`'s doc comment for why that path's
/// eager call makes this check a no-op for it.
///
/// Deliberately **not** `OnceLock`: confirmed empirically that
/// `OnceLock::get_or_init`'s closure here (which allocates, via
/// `std::env::var_os`) deadlocks the process on its very first-ever
/// allocation, before even reaching `main()` — even called from behind the
/// reentrancy guard, which normally makes an allocating closure safe here
/// (see `ensure_writer`'s writer-thread-name allocation for the
/// established, working version of that pattern with a plain `Once`).
/// `OnceLock` specifically was the problem, not the ordering; a plain
/// racy-but-idempotent atomic cache, matching this file's own
/// `WRITER_DEAD`/`WRITER_SHOULD_STOP` idiom, has none of that hazard: a
/// reentrant call during initialization just redundantly recomputes the
/// same env lookup and stores the same value, rather than deadlocking.
fn cooperative_capture_enabled() -> bool {
    static INITIALIZED: AtomicBool = AtomicBool::new(false);
    static ENABLED: AtomicBool = AtomicBool::new(false);
    if !INITIALIZED.load(Ordering::Relaxed) {
        ENABLED.store(std::env::var_os("HEAPLENS_ENABLE").is_some(), Ordering::Relaxed);
        INITIALIZED.store(true, Ordering::Relaxed);
    }
    ENABLED.load(Ordering::Relaxed)
}'''),
    ...para('//',
        r'On 2026-07-28 (commit a31baeb) the library stopped capturing by '
        r'default. Before that, a binary that linked HeapLensAlloc '
        r'connected to the daemon the moment it allocated. The doc comment '
        r'states the principle: "HeapLens must never be automatically '
        r'attached to anything: launching such a binary is not, by itself, '
        r'an explicit request to be observed." Capture now needs '
        r'HEAPLENS_ENABLE set in the environment, to any value, including '
        r'an empty string or 0. The check is is_some(), not a truth test.'),
    blank,
    ...para('//',
        r'The implementation is a lesson about initialisation order inside '
        r'an allocator. The first version used OnceLock::get_or_init, '
        r'which seems the obvious tool for a one-time lookup. It '
        r'deadlocked the process on its first allocation, "before even '
        r'reaching main()", and the comment is precise that the problem '
        r'was OnceLock specifically: its closure allocates '
        r'(std::env::var_os), and a re-entrant call during initialisation '
        r'is documented to deadlock or panic. The replacement is two '
        r'relaxed atomics, INITIALIZED and ENABLED. A re-entrant call '
        r'during initialisation just recomputes the same lookup and stores '
        r'the same answer, so the race is benign by construction. It '
        r'matches the idiom already used for the writer’s flags.'),
    blank,
    ...para('//',
        r'Two things follow. First, there is a second route past the gate: '
        r'if the writer was already started (WRITER_ONCE.is_completed()), '
        r'as the hook DLL does eagerly at attach, record() proceeds '
        r'regardless of the variable. Attaching through the injector is '
        r'itself the explicit request. Second, a search of the whole '
        r'repository finds nothing that sets HEAPLENS_ENABLE: no test, '
        r'harness or script. The cooperative end-to-end tests spawn '
        r'example producers that inherit the environment, so they now '
        r'capture only if the person running them has set it. Run on a '
        r'Linux sandbox, the crate’s integration test multithread_stress '
        r'fails with "expected at least one recorded event, got 0" without '
        r'the variable and passes with HEAPLENS_ENABLE=1. The test '
        r'predates the gate and was not updated by the commit that added '
        r'it. The Windows-only daemon tests could not be run for this '
        r'page.'),
    ...sec(r'the shared dbghelp lock'),
    ...code('rust', 'crates/heaplens-alloc/src/lib.rs · DBGHELP_LOCK', r'''
/// Serializes every call into `backtrace`'s Windows backend — both
/// `capture::capture_stack`'s `trace_unsynchronized` (called from every
/// allocating thread, on the hot path) and `writer::run`'s `resolve` calls
/// (called from the single writer thread). `trace_unsynchronized`'s own
/// safety doc already warns it must not be called concurrently from
/// multiple threads "without external synchronisation" — this is that
/// synchronisation, extended to also cover `resolve`, since both
/// ultimately reach `dbghelp.dll`, which Windows documents as not safe for
/// concurrent calls from multiple threads. A single-threaded producer never
/// contends this lock in practice; a multi-threaded one (concurrent
/// allocating threads, or an allocating thread racing the writer thread's
/// own resolve loop) genuinely needs it.
pub(crate) static DBGHELP_LOCK: Mutex<()> = Mutex::new(());'''),
    ...para('//',
        r'One static Mutex serialises every call into the Windows backend '
        r'of the backtrace crate, from both sides: the stack walk on every '
        r'allocating thread and the symbol resolution on the writer '
        r'thread. It came from commit 9c4678e (2026-07-19). The capture.rs '
        r'page tells why the allocating side later switched to try_lock; '
        r'this file just owns the lock. It is pub(crate), so only this '
        r'crate can take it.'),
    ...sec(r'the writer’s lifecycle: four flags and a rule'),
    ...code('rust', 'crates/heaplens-alloc/src/lib.rs · the flags', r'''
static WRITER_ONCE: Once = Once::new();
static WRITER_DEAD: AtomicBool = AtomicBool::new(false);
static WRITER_SHOULD_STOP: AtomicBool = AtomicBool::new(false);
static WRITER_STOPPED: AtomicBool = AtomicBool::new(false);

/// Read by `writer::run`'s loop. Not exposed outside this crate — front-ends
/// request shutdown via `request_writer_stop_and_wait`, they don't poll this
/// directly.
pub(crate) fn writer_should_stop() -> bool {
    WRITER_SHOULD_STOP.load(Ordering::Acquire)
}

/// Set by `writer::run` immediately before it returns.
pub(crate) fn mark_writer_stopped() {
    WRITER_STOPPED.store(true, Ordering::Release);
}'''),
    ...para('//',
        r'Four statics describe the writer: WRITER_ONCE (a std Once: spawn '
        r'exactly once), WRITER_DEAD (the spawn failed), WRITER_SHOULD_STOP and '
        r'WRITER_STOPPED (a polite shutdown handshake). WRITER_DEAD came '
        r'from the review pass in commit ba1a066: if the thread cannot be '
        r'created, record() returns early instead of pushing into a ring '
        r'that nobody will ever drain.'),
    ...code('rust', 'crates/heaplens-alloc/src/lib.rs · ensure_writer', r'''
/// Spawn the writer thread exactly once. Safe to call from the hot path for
/// the cooperative `#[global_allocator]` front-end: after the first
/// successful call_once, subsequent calls are a single atomic load (no
/// allocation, no blocking).
///
/// **Not safe to reach lazily from an injected hook callback** (Stage 7,
/// `heaplens-hook`) — confirmed empirically: spawning a thread from inside
/// a MinHook-detoured `RtlAllocateHeap`/`HeapAlloc` call crashes
/// (`STATUS_ACCESS_VIOLATION`), reproducibly, isolated by disabling every
/// other part of `record()` in turn until only the `std::thread::spawn`
/// call remained implicated. Root cause: `CreateThread`'s synchronous
/// `DLL_THREAD_ATTACH` notifications run on the new thread before it's
/// fully initialized, and something in that bootstrap path re-enters the
/// hooked allocation function while the thread isn't in a state that
/// tolerates it. `heaplens-hook`'s `HeapLensHookAttach` therefore calls
/// `ensure_writer_started()` eagerly, from a normal (non-hook) thread
/// context, before enabling any hook — see `docs/stage7-injection-design.md`
/// §4 (this finding postdates and refines the design's original safety
/// analysis, which did not anticipate this specific hazard). By the time
/// any hook callback reaches this function, `WRITER_ONCE` has already
/// fired, so the call below is a single atomic load — no thread is ever
/// spawned from a hook callback.
///
/// The spawn itself allocates ("heaplens-writer" thread name string), but it
/// runs under the recursion guard, so those allocations are suppressed.
#[inline]
fn ensure_writer() {
    WRITER_ONCE.call_once(|| {
        if std::thread::Builder::new()
            .name("heaplens-writer".to_owned())
            .spawn(writer::run)
            .is_err()
        {
            // Spawn failed (e.g., out of threads). Mark the writer dead so
            // record() can skip the ring push rather than filling the ring
            // silently until it overflows.
            WRITER_DEAD.store(true, Ordering::Relaxed);
        }
    });
}

/// Public entry point for capture front-ends that cannot rely on `record`'s
/// lazy spawn — currently `heaplens-hook`, which must start the writer
/// thread from a normal thread context (its `HeapLensHookAttach`, before
/// any hook is enabled) rather than from inside a hook callback. See the
/// safety note on `ensure_writer` above.
pub fn ensure_writer_started() {
    ensure_writer();
}'''),
    ...para('//',
        r'The writer is spawned lazily from the hot path, from inside '
        r'record() under the guard, and the spawn’s own allocation (the '
        r'thread name string) is suppressed by that guard. After the first '
        r'call it costs one atomic load. The doc comment then carries a '
        r'warning that exists because of Stage 7: lazily spawning a thread '
        r'from inside a MinHook-detoured allocation call crashed with '
        r'STATUS_ACCESS_VIOLATION, reproducibly. The method used to '
        r'isolate it was elimination: "disabling every other part of '
        r'record() in turn until only the std::thread::spawn call remained '
        r'implicated". The cause is that CreateThread delivers '
        r'DLL_THREAD_ATTACH notifications synchronously, on a thread that '
        r'is not fully set up, and something in that path calls the hooked '
        r'allocator.'),
    blank,
    ...para('//',
        r'The fix was an ordering rule, enforced by the new public '
        r'function ensure_writer_started(): the hook DLL starts the writer '
        r'from a normal thread, before it enables any hook. Then '
        r'WRITER_ONCE has already fired by the time any hook callback '
        r'reaches record(), and "no thread is ever spawned from a hook '
        r'callback".'),
    ...code('rust', 'crates/heaplens-alloc/src/lib.rs · stopping, and unwinding the rings', r'''
/// Signals the writer thread to stop and waits (bounded by `timeout`) for
/// it to actually do so. Returns `true` if it stopped in time.
///
/// **Required by `heaplens-hook`'s `HeapLensHookDetach` — and required to
/// be called *after* hooks are disabled, not before.** Confirmed
/// empirically as a fourth, distinct hazard in the same family as the two
/// documented on `ensure_writer` and `warm_up_symbol_resolution`, this one
/// the mirror image of the writer-thread-*creation* hazard: a thread
/// *exiting* naturally also triggers `DLL_THREAD_DETACH` notifications and
/// TLS-destructor cleanup on that thread, which itself performs heap
/// operations. With hooks still active at that moment, those exit-time
/// heap calls route through the detour during the exact window a thread is
/// mid-teardown — isolated via the same disable-one-thing-at-a-time method
/// as the other three hazards, and via diagnostic prints confirming the
/// writer thread returned cleanly from `writer::run` immediately before the
/// crash. The fix: `heaplens-hook`'s `HeapLensHookDetach` calls
/// `MinHook::disable_all_hooks` *before* calling this function, so the
/// writer thread's own exit-time heap traffic goes through the real,
/// unhooked functions. See `docs/stage7-injection-design.md` §4.
pub fn request_writer_stop_and_wait(timeout: std::time::Duration) -> bool {
    WRITER_SHOULD_STOP.store(true, Ordering::Release);
    let deadline = std::time::Instant::now() + timeout;
    while !WRITER_STOPPED.load(Ordering::Acquire) {
        if std::time::Instant::now() >= deadline {
            return false;
        }
        std::thread::sleep(std::time::Duration::from_millis(5));
    }
    true
}

/// Proactively tears down the per-thread ring-registration mechanism
/// itself, ahead of any chance this module gets unloaded. **Required by
/// `heaplens-hook`'s `HeapLensHookDetach`/`HeapLensHookDetachApc`** — see
/// `ring::shutdown`'s doc comment for the full account of the crash this
/// closes (a stale per-thread ring registration whose exit callback lives
/// inside this DLL, invoked after the DLL may have already been unloaded).
/// Safe to call regardless of hook state; does not touch MinHook or the
/// private heap.
pub fn shutdown_ring_storage() {
    ring::shutdown();
}'''),
    ...para('//',
        r'request_writer_stop_and_wait sets the stop flag and polls the '
        r'stopped flag every 5 ms until a deadline, returning whether the '
        r'writer finished in time. It must be called after hooks are '
        r'disabled, not before. That is the fourth hazard in a family '
        r'documented here and in docs/stage7-injection-design.md section '
        r'4: a thread that is exiting performs heap operations '
        r'(DLL_THREAD_DETACH, TLS destructors), and if hooks are still '
        r'live those operations route through the detour in the middle of '
        r'teardown. The mirror image of the spawn crash: creation and exit '
        r'are both dangerous with hooks on. shutdown_ring_storage is a '
        r'one-line forwarder to ring::shutdown, whose FlsFree story is on '
        r'the ring.rs page.'),
    ...code('rust', 'crates/heaplens-alloc/src/lib.rs · warm_up_symbol_resolution', r'''
/// Forces `backtrace::resolve`'s one-time lazy initialization (on Windows,
/// this loads and initializes `dbghelp.dll` — `SymInitialize` and friends)
/// to happen now, synchronously, on the calling (normal) thread.
///
/// **Required before `heaplens-hook` enables any hook.** Confirmed
/// empirically, the same way as the writer-thread-spawn hazard documented
/// on `ensure_writer`: with the writer thread spawned eagerly (fixing that
/// first hazard), the capture pipeline still crashed
/// (`STATUS_ACCESS_VIOLATION`) the first time the writer thread's symbol
/// resolution loop (`writer::run`'s `backtrace::resolve` call) ran with
/// hooks already live — isolated via the same disable-one-thing-at-a-time
/// method, and via diagnostic prints showing the crash follows immediately
/// after the writer thread's first `backtrace::resolve` call. Root cause is
/// the same *class* of hazard as the thread-spawn issue, one layer later:
/// `dbghelp.dll`'s first load/`SymInitialize` does its own heavyweight,
/// first-time OS-level setup (module enumeration, internal allocations),
/// and doing that for the first time while `RtlAllocateHeap` is hooked
/// process-wide is unsafe, whether it happens synchronously inside a hook
/// callback (the earlier hazard) or asynchronously on a background thread
/// racing against active hook traffic (this one). The general rule this
/// establishes for `heaplens-hook`: **any first-time, heavyweight
/// OS/runtime infrastructure initialization the capture pipeline depends
/// on must be forced to completion before `MinHook::enable_all_hooks`**,
/// never left lazy. See `docs/stage7-injection-design.md` §4.
pub fn warm_up_symbol_resolution() {
    // Resolve this very function's own address — always valid, always
    // resolvable, and its result is intentionally discarded. The only goal
    // is forcing whatever one-time setup `backtrace::resolve` performs to
    // run now, on this thread, before any hook exists to race against it.
    let addr = warm_up_symbol_resolution as *const () as *mut std::ffi::c_void;
    let _guard = DBGHELP_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    backtrace::resolve(addr, |_sym| {});
}'''),
    ...para('//',
        r'The second hazard in that family is symbol resolution. The first '
        r'call to backtrace::resolve loads dbghelp.dll and runs '
        r'SymInitialize, which does heavyweight first-time work, module '
        r'enumeration and its own allocations, and doing that while '
        r'RtlAllocateHeap is hooked process-wide is unsafe whether it '
        r'happens inside a hook or on a background thread racing hook '
        r'traffic. The function resolves its own address and discards the '
        r'result, purely to force the setup now, on a normal thread.'),
    blank,
    ...para('//',
        r'The comment condenses all of it into a rule that is the most '
        r'reusable sentence in the file: "any first-time, heavyweight '
        r'OS/runtime infrastructure initialization the capture pipeline '
        r'depends on must be forced to completion before '
        r'MinHook::enable_all_hooks, never left lazy."'),
    ...sec(r'what is tested here, and what is not'),
    ...para('//',
        r'This file has no tests module. Its behaviours are covered from '
        r'outside: tests/multithread_stress.rs drives the allocator with '
        r'eight threads (and needs the opt-in), the examples run it under '
        r'a real daemon, and the daemon’s hook_* tests drive the lifecycle '
        r'functions through the hook DLL on Windows. Nothing tests the '
        r'opt-in gate directly, and nothing asserts the ordering of '
        r'dealloc relative to free, which makes two of the most carefully '
        r'argued decisions in the file depend on comments.'),
    ...sec(r'limits'),
    ...pt('//',
        r'a process-wide lock on the capture path',
        r'DBGHELP_LOCK, see capture.rs.'),
    ...pt('//',
        r'the gate accepts any value',
        r'HEAPLENS_ENABLE=0 enables capture.'),
    ...pt('//',
        r'possible realloc race',
        r'the reading under the allocator impl; untested.'),
    ...pt('//',
        r'documentation outweighs code',
        r'62 percent of the non-blank lines are comments, because most of '
        r'the hard-won facts have nowhere else to live. That is a strength '
        r'for readers and a maintenance cost: the comments make claims '
        r'about other crates (heaplens-hook, graph.rs) that the compiler '
        r'cannot check.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/src/lib.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/src/lib.rs'),
  ],
);
