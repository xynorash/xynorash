import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/src/guard.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'guard.rs — one bit per thread, and the crash that rewrote it'),
    cm('//', r'why a recursion flag stopped being a thread_local and became a raw '
              r'Win32 TLS slot'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'per-thread re-entrancy flag consulted first by record()'),
    kv('language', r'Rust, with a Windows implementation and a portable fallback'),
    kv('size', r'225 lines (43 of them module documentation), 6 unit tests plus 3 '
              r'integration tests'),
    kv('history', r'4 commits: 974ab1e (2026-07-01), then dcc76f2 (2026-07-21) rewrote the '
              r'storage'),
    kv('related harness', r'crates/heaplens-hook/examples/self_load_concurrency_stress.rs'),
    ...sec(r'the problem: an allocator that allocates'),
    ...para('//',
        r'A global allocator is called by everything, including by itself. '
        r'record(), the function that turns an allocation into an event, '
        r'calls code that allocates: it creates a per-thread ring the '
        r'first time (Arc::new, a Vec push into the registry), it spawns '
        r'the writer thread, and the opt-in check reads an environment '
        r'variable, which on Windows builds an OsString. Each of those '
        r'calls re-enters HeapLensAlloc::alloc, which calls record() '
        r'again. Without protection that is infinite recursion, or a '
        r'deadlock on a lock the outer call is holding.'),
    blank,
    ...para('//',
        r'The fix is a flag per thread: "this thread is already inside '
        r'record, ignore allocations". record() checks it first and '
        r'returns at once if set. If not, it sets the flag, does its work, '
        r'and clears it. The Build Spec writes the rule as invariant 4 of '
        r'its section 12: the writer thread "permanently holds the '
        r'recursion guard, so its own allocations are never recorded". '
        r'Everything in this file serves that one bit.'),
    ...sec(r'the first version, and what the spec said'),
    ...code('rust', 'crates/heaplens-alloc/src/guard.rs · the portable fallback, which is the original design', r'''
/// Non-Windows fallback. This project targets Windows only (named pipes,
/// `RtlAllocateHeap` hooking, etc.) — this branch exists so `cargo check`
/// on a non-Windows dev machine doesn't fail outright, not because it's
/// expected to run for real anywhere.
#[cfg(not(windows))]
mod imp {
    use std::cell::Cell;

    thread_local! {
        static IN_ALLOC: Cell<bool> = const { Cell::new(false) };
    }

    #[inline]
    pub fn is_set() -> bool {
        IN_ALLOC.with(|f| f.get())
    }

    #[inline]
    pub fn set(val: bool) {
        IN_ALLOC.with(|f| f.set(val));
    }
}'''),
    ...para('//',
        r'The first commit, 974ab1e on 2026-07-01, was this and nothing '
        r'else: a thread_local! holding a Cell<bool>, with is_set, set and '
        r'a scoped guard. It is the spec’s section 4.3 design nearly line '
        r'for line, and it is still in the file as the non-Windows '
        r'implementation. The spec anticipated one weak point, that the '
        r'thread-local’s own initialisation might allocate ("the nested '
        r'call sees IN_ALLOC not yet set and proceeds once — acceptable; '
        r'document it"). The weak point that actually bit was a different '
        r'one. The const { Cell::new(false) } form needs no lazy '
        r'initialiser, which, on the usual reading, is the point of '
        r'writing it that way: the flag can be read without running any '
        r'setup code.'),
    blank,
    ...para('//',
        r'This version carried the crate from its first commit on '
        r'2026-07-01 to the fix on 2026-07-21. It was correct for a binary '
        r'that links the allocator crate in at build time, which was the '
        r'only kind of user until the hook DLL (heaplens-hook) arrived on '
        r'2026-07-13 in commit b3a22c2. The Windows hook DLL is not that '
        r'kind of module.'),
    ...sec(r'the crash'),
    ...code('rust', 'crates/heaplens-alloc/src/guard.rs · the module documentation, first half', r'''
//! Per-thread reentrancy flag for `record()`.
//!
//! # Why this isn't a plain `thread_local!`
//!
//! It used to be exactly that — a `thread_local! { static IN_ALLOC:
//! Cell<bool> = ...; }`. That crashed reliably (confirmed via the
//! `self_load_concurrency_stress` regression harness, 2026-07-21 root-cause
//! investigation): any thread other than the one that called
//! `LoadLibraryW` on this DLL segfaulted on its *first* access to that
//! thread-local, deterministically, every run — even reduced to nothing
//! but a single read with everything else in `record()` stubbed out.
//!
//! Root cause: rustc's `thread_local!` on `x86_64-pc-windows-msvc` can
//! implement a thread-local using a genuine PE `.tls`-section variable,
//! accessed directly via the FS/GS segment register ("static"/"implicit"
//! TLS) — the fastest option, and the one the compiler prefers when it
//! can. That mechanism depends on the OS loader having already registered
//! this module's TLS index in *every* thread's TEB — which is only
//! guaranteed for a module that's linked into the process at startup.
//! `heaplens-hook` is never that: it is always loaded via `LoadLibraryW`
//! at runtime (self-load harnesses and real injected targets alike), so
//! any thread the loader didn't specifically retrofit — in practice, every
//! thread except the one that called `LoadLibraryW` — reads a TLS slot
//! that was never set up for this module, which is exactly what
//! segfaulted here.'''),
    ...para('//',
        r'On 2026-07-21 the stress harness self_load_concurrency_stress '
        r'(commit 8b0f962, committed the same day as the fix) reproduced a '
        r'crash that had been seen in the wild. Per its commit message, '
        r'the hooked path crashed reliably under heavy concurrent '
        r'allocation, 48 threads for 8 seconds, while the identical '
        r'unhooked baseline "completes hundreds of millions of alloc/free '
        r'cycles cleanly every time". The corroboration was uncomfortable: '
        r'a real application had crashed with an access violation recorded '
        r'inside the hook DLL, minutes before a Windows kernel bugcheck '
        r'(DPC_WATCHDOG_VIOLATION) on the same machine as the '
        r'investigation.'),
    blank,
    ...para('//',
        r'The root-cause work is in the doc comment above. The method, as '
        r'the commit message for the fix puts it, was reduction: "Reduced '
        r'record() down to a single line at a time until the crash '
        r'isolated to guard::is_set() alone". The observed behaviour was '
        r'stark. A single allocation on the thread that called '
        r'LoadLibraryW always succeeded. The identical allocation on any '
        r'other thread segfaulted on its first access to the thread-local, '
        r'every run, "even reduced to nothing but a single read with '
        r'everything else in record() stubbed out".'),
    blank,
    ...para('//',
        r'The mechanism, as the comment explains: on '
        r'x86_64-pc-windows-msvc rustc may implement thread_local! with a '
        r'genuine PE .tls-section variable reached through a segment '
        r'register. That is the fastest option and the compiler prefers '
        r'it. It works only if the OS loader has registered the module’s '
        r'TLS index in every thread’s TEB, which is guaranteed for a '
        r'module linked into the process at startup. heaplens-hook is '
        r'never that. It is loaded at run time with LoadLibraryW, in the '
        r'self-load harnesses and in real injected targets alike, so every '
        r'thread except the one that did the loading reads a slot nobody '
        r'set up.'),
    ...sec(r'the dead end that the file keeps on purpose'),
    ...code('rust', 'crates/heaplens-alloc/src/guard.rs · the failed first fix', r'''
//! An initial attempt to fix this by giving the thread-local's value type
//! a `Drop` impl (hoping to force rustc onto its other, non-`.tls`-section
//! implementation) did **not** resolve the crash — confirmed by rerunning
//! the identical isolated reduction and observing the same segfault. Do
//! not reintroduce that approach without re-verifying it against the
//! harness first; whatever rustc chooses for a `Drop`-having thread-local
//! on this target, it wasn't clean of the same hazard.'''),
    ...para('//',
        r'The first fix attempt was a reasonable theory: give the '
        r'thread-local’s value type a Drop impl, in the hope that rustc '
        r'would then pick its other implementation, one that registers a '
        r'destructor and does not rely on the static TLS section. The '
        r'author reran the isolated reduction and saw the same segfault. '
        r'The theory was wrong, and the comment says so, with an '
        r'instruction aimed at the next person: "Do not reintroduce that '
        r'approach without re-verifying it against the harness first".'),
    blank,
    ...para('//',
        r'The ring registration had the identical crash for the identical '
        r'reason, even though its value type (RingHandle) had always had a '
        r'real Drop impl. The commit message for the fix points at that as '
        r'the confirmation: "Drop-ness was never the deciding factor". '
        r'Keeping a recorded dead end in the code, not only in the commit '
        r'log, is a small discipline with a large payoff. Anyone who reads '
        r'this file with a plausible cleanup in mind meets the evidence '
        r'against it first.'),
    ...sec(r'the fix: raw Win32 TLS'),
    ...code('rust', 'crates/heaplens-alloc/src/guard.rs · the fix and its validation', r'''
//! The fix that *is* confirmed to work is bypassing `thread_local!`
//! entirely on Windows and driving the raw Win32 dynamic-TLS API directly
//! (`TlsAlloc`/`TlsGetValue`/`TlsSetValue`) — a plain slot-index-based
//! mechanism with no dependency on module linkage or which thread loaded
//! what. This is Microsoft's own documented answer for "a DLL that may be
//! loaded via `LoadLibrary` needs per-thread state" — see
//! `TlsAlloc`'s documentation. Validated by rerunning the full
//! `self_load_concurrency_stress` harness 10 consecutive times, hooked,
//! all clean (see the root-cause investigation report for the run log).'''),
    ...para('//',
        r'The fix is to stop using thread_local! on Windows and use the '
        r'platform’s own dynamic TLS: TlsAlloc, TlsGetValue and '
        r'TlsSetValue. A slot index is just a number; it does not depend '
        r'on which module is linked how, nor on which thread loaded what. '
        r'The comment cites the authority, that this is Microsoft’s own '
        r'documented answer for a DLL that may be loaded with LoadLibrary '
        r'and needs per-thread state.'),
    blank,
    ...para('//',
        r'The validation line is the part worth copying: "rerunning the '
        r'full self_load_concurrency_stress harness 10 consecutive times, '
        r'hooked, all clean". The failure had been deterministic, so one '
        r'clean run proved little. The commit message of the fix (dcc76f2) '
        r'reports a larger tally than the code comment, "20 consecutive '
        r'clean runs across two separate rebuilds, 0 failures", against a '
        r'baseline that "crashed reliably, every run", and adds that the '
        r'replacement was "validated in isolation before being trusted for '
        r'the full fix".'),
    ...code('rust', 'crates/heaplens-alloc/src/guard.rs · the Windows implementation', r'''
#[cfg(windows)]
mod imp {
    use std::sync::OnceLock;
    use windows_sys::Win32::System::Threading::{TlsAlloc, TlsGetValue, TlsSetValue};

    /// Process-wide TLS slot index, allocated once. `OnceLock` itself is a
    /// plain heap-independent static (no TLS, no allocation after the one
    /// `TlsAlloc` call) — safe to read from any thread regardless of when
    /// or how this module was loaded.
    static TLS_INDEX: OnceLock<u32> = OnceLock::new();

    #[inline]
    fn index() -> u32 {
        *TLS_INDEX.get_or_init(|| unsafe { TlsAlloc() })
    }

    /// `TlsGetValue` returns null for a slot that was never set on this
    /// thread — indistinguishable from "explicitly set to null", which is
    /// exactly the "not in alloc" state we want as the default, so no
    /// separate first-access initialization is needed.
    #[inline]
    pub fn is_set() -> bool {
        unsafe { !TlsGetValue(index()).is_null() }
    }

    #[inline]
    pub fn set(val: bool) {
        let v = if val { 1usize as *mut core::ffi::c_void } else { core::ptr::null_mut() };
        unsafe {
            TlsSetValue(index(), v);
        }
    }
}'''),
    ...para('//',
        r'Four details in this small module are all load-bearing.'),
    blank,
    ...para('//',
        r'The slot index is held in a OnceLock<u32>, with the comment that '
        r'it is "a plain heap-independent static (no TLS, no allocation '
        r'after the one TlsAlloc call)". That matters because is_set() is '
        r'the first thing every allocation in the process runs; if reading '
        r'the index allocated, the guard would need a guard.'),
    blank,
    ...para('//',
        r'TlsGetValue returns null for a slot never set on this thread. '
        r'The comment notes that this is "indistinguishable from '
        r'explicitly set to null, which is exactly the ’not in alloc’ '
        r'state we want as the default". So there is no per-thread '
        r'initialisation step at all, which removes the whole class of '
        r'"first access allocates" problems the original spec worried '
        r'about.'),
    blank,
    ...para('//',
        r'set() stores the pointer-sized value 1 or null. The flag is a '
        r'pointer in a slot, not a boxed bool; nothing is allocated.'),
    blank,
    ...para('//',
        r'Finally, the whole module is cfg(windows) with the thread_local! '
        r'version retained for everything else.'),
    ...sec(r'the scoped guard'),
    ...code('rust', 'crates/heaplens-alloc/src/guard.rs · public surface and ScopedGuard', r'''
/// Returns true if the current thread is already inside `record`.
#[inline]
pub fn is_set() -> bool {
    imp::is_set()
}

/// Permanently marks the current thread as inside-allocator.
/// Called once by the writer thread at startup so that none of its own
/// allocations (pipe buffers, symbol resolution, etc.) are ever recorded.
pub fn force_enter_permanent() {
    imp::set(true);
}

/// RAII guard that sets the per-thread recursion flag on creation and clears
/// it on Drop. Panic-safe: Drop runs during stack unwinding, so the flag is
/// always cleared even if code between `enter()` and drop panics.
pub struct ScopedGuard(());

impl ScopedGuard {
    /// Set the recursion flag. Must only be called after confirming `is_set()`
    /// is false — the guard does not check this itself.
    #[inline]
    pub fn enter() -> Self {
        debug_assert!(!is_set(), "ScopedGuard::enter called on a permanently-guarded thread");
        imp::set(true);
        ScopedGuard(())
    }
}

impl Drop for ScopedGuard {
    #[inline]
    fn drop(&mut self) {
        imp::set(false);
    }
}'''),
    ...para('//',
        r'ScopedGuard is an RAII token. enter() sets the flag and returns '
        r'a guard whose Drop clears it. Because the clearing happens in '
        r'Drop, it runs during unwinding too, which is the point of the '
        r'comment "Panic-safe: Drop runs during stack unwinding". The test '
        r'guard_clears_after_panic proves it with catch_unwind. The struct '
        r'has a private unit field, ScopedGuard(()), so the only way to '
        r'get one is through enter().'),
    blank,
    ...para('//',
        r'enter() does not check the flag itself. The doc comment says so: '
        r'"Must only be called after confirming is_set() is false". Since '
        r'commit ba1a066 (2026-07-01, the final-review fixes) a '
        r'debug_assert fires if it is called on a thread that is already '
        r'set, to catch misuse in test builds. In a release build that '
        r'check disappears, and the consequence would be quiet: the Drop '
        r'would clear a flag that was permanent, un-guarding the writer '
        r'thread. The invariant is held by the one caller, record(), which '
        r'checks is_set() on the line before.'),
    blank,
    ...para('//',
        r'force_enter_permanent() is the other half of invariant 4: the '
        r'writer thread calls it as the first thing it does, and never '
        r'clears it, so nothing the writer allocates (its HashMap, its '
        r'buffers, symbol strings) is ever recorded.'),
    ...sec(r'tests'),
    ...code('rust', 'crates/heaplens-alloc/src/guard.rs · unit tests (first four)', r'''
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn starts_clear() {
        // Spawn to get a fresh TLS slot uncontaminated by other tests.
        std::thread::spawn(|| {
            assert!(!is_set(), "guard must start clear on a new thread");
        })
        .join()
        .unwrap();
    }

    #[test]
    fn scoped_guard_sets_and_clears() {
        std::thread::spawn(|| {
            assert!(!is_set());
            let g = ScopedGuard::enter();
            assert!(is_set());
            drop(g);
            assert!(!is_set());
        })
        .join()
        .unwrap();
    }

    #[test]
    fn guard_clears_after_panic() {
        std::thread::spawn(|| {
            let _ = std::panic::catch_unwind(|| {
                let _g = ScopedGuard::enter();
                assert!(is_set());
                panic!("test panic while guard held");
            });
            assert!(!is_set(), "guard must clear even after a panic (Drop ran during unwind)");
        })
        .join()
        .unwrap();
    }'''),
    ...para('//',
        r'Every test spawns a new thread, with the comment "Spawn to get a '
        r'fresh TLS slot uncontaminated by other tests". The flag is per '
        r'thread, so running on the test harness’s own thread would make '
        r'tests depend on each other’s leftovers. The six unit tests cover '
        r'starts clear, set-and-clear, clear-after-panic, the re-entrancy '
        r'check as record() uses it, the permanent flag, and, added with '
        r'the fix, distinct_threads_get_independent_slots.'),
    ...code('rust', 'crates/heaplens-alloc/src/guard.rs · the test added with the fix', r'''
#[test]
fn distinct_threads_get_independent_slots() {
    // The TlsAlloc-based implementation shares one process-wide slot
    // *index*, but TlsGetValue/TlsSetValue are inherently per-thread —
    // this test pins down that setting the flag on one thread never
    // leaks into another's view of it.
    let t1 = std::thread::spawn(|| {
        assert!(!is_set());
        force_enter_permanent();
        assert!(is_set());
    });
    t1.join().unwrap();

    std::thread::spawn(|| {
        assert!(!is_set(), "a fresh thread must not see another thread's flag");
    })
    .join()
    .unwrap();
}'''),
    ...para('//',
        r'That last test exists because the new implementation shares one '
        r'process-wide slot index across threads. Its comment: '
        r'"TlsGetValue/TlsSetValue are inherently per-thread — this test '
        r'pins down that setting the flag on one thread never leaks into '
        r'another’s view of it." Set the flag permanently on thread one, '
        r'join it, and a brand-new thread must still see it clear.'),
    blank,
    ...para('//',
        r'The crate’s unit tests were run on a Linux sandbox for this '
        r'page. All 20 library tests pass (6 of them here), but on Linux '
        r'they exercise the thread_local! fallback, not the Windows code. '
        r'That is the honest limit of these tests. A statically linked '
        r'test binary is exactly the case where the old thread_local! '
        r'worked, so no unit test here could ever have caught the bug.'),
    blank,
    ...para('//',
        r'The bug is covered where it can be: the self-load harness loads '
        r'the hook DLL with LoadLibraryW, then allocates from many '
        r'threads, and the daemon’s hook_self_load_spawned_thread.rs puts '
        r'every scripted allocation on a spawned thread. The fix’s commit '
        r'message explains why the older acceptance gate missed it: '
        r'hook_self_load_wire.rs "never actually exercised this path at '
        r'all: its entire workload runs on the thread that calls '
        r'LoadLibraryW".'),
    ...sec(r'the integration copy'),
    ...para('//',
        r'tests/guard_tests.rs repeats three of these tests through the '
        r'public path (heaplens_alloc::guard::{is_set, ScopedGuard, '
        r'force_enter_permanent}). Its value is not new coverage but a '
        r'check that the module’s API is usable from outside the crate, '
        r'which matters here because lib.rs exports guard as a hidden '
        r'public module so that the hook crate and integration tests can '
        r'reach it.'),
    ...sec(r'limits'),
    ...pt('//',
        r'TlsAlloc is unchecked',
        r'index() uses the value TlsAlloc returns directly. TlsAlloc can '
        r'fail and return TLS_OUT_OF_INDEXES; in that case is_set would '
        r'read a nonsense slot and the guard would never engage. A process '
        r'that has used up its TLS indexes is unusual, but the error path '
        r'is not handled.'),
    ...pt('//',
        r'the guard is not re-entrant by design',
        r'nested ScopedGuard use would clear the outer flag; only a '
        r'debug_assert defends it.'),
    ...pt('//',
        r'one flag per thread',
        r'it cannot tell the allocator’s own allocations from the '
        r'application’s other legitimate re-entrancy, so anything '
        r'allocated while the flag is set is invisible. That is the '
        r'intended cost: the ring, the registry and the writer’s memory '
        r'never show up in the graph.'),
    ...pt('//',
        r'Windows only for real',
        r'the non-Windows branch exists so that cargo check works on a '
        r'development machine, as its own comment says, not because it is '
        r'expected to run anywhere real.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/src/guard.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/src/guard.rs'),
  ],
);
