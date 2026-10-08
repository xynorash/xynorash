import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-hook/src/lib.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'lib.rs — a Rust DLL that lives inside someone else’s process'),
    cm('//', r'ten numbered hazards, and one rule: nothing heavy while a hook is live'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'the capture front-end for injected, uncooperative processes'),
    kv('language', r'Rust, built as a cdylib: heaplens_hook.dll'),
    kv('size', r'567 lines: 298 of comment, 228 of code, 41 blank'),
    kv('exports', r'4 functions (Attach, AttachRemote, Detach, DetachApc), 2 statics'),
    kv('history', r'3 commits: b3a22c2 (294 lines), 724695a (559), dcc76f2 (567)'),
    kv('tests', r'none inside the file; driven as a subprocess by 6 daemon tests'),
    kv('depends on', r'heaplens-alloc (record, writer, rings), minhook 0.9, windows-sys'),
    ...sec(r'the problem: observing a program you did not compile'),
    ...para('//',
        r'The first way HeapLens sees a heap is cooperative. The program '
        r'links heaplens-alloc and declares it as its #[global_allocator], '
        r'so every allocation passes through code the author controls. '
        r'That cannot work for a program that is already running and was '
        r'built by someone else. Stage 7 of the project, whose design '
        r'document states the goal as letting a user "pick a running '
        r'Windows process and observe its heap in HeapLens without '
        r'recompiling or relinking the target", needs another way in. The '
        r'only way into a finished program is to get a library loaded into '
        r'it, and the only way to see its allocations is to intercept the '
        r'functions that serve them. This file is that library.'),
    blank,
    ...para('//',
        r'Everything downstream is unchanged by design. The hook drives the '
        r'same record(), the same per-thread ring, the same writer thread, '
        r'the same named pipe and the same wire format as a cooperative '
        r'producer, so, in the design document’s words, "from the '
        r'daemon’s point of view, an injected target is indistinguishable '
        r'from a cooperative producer". The entire difficulty of the file '
        r'is therefore not capture. It is being a guest: running on '
        r'threads you did not create, inside the most frequently called '
        r'function in the process, while Windows delivers loader and '
        r'thread notifications to your code at moments you do not choose.'),
    blank,
    ...para('//',
        r'The stakes explain the tone of the comments. A mistake here does '
        r'not fail a test, it crashes a program the user did not write. On '
        r'the night of 2026-07-21 the commit that added the stress harness '
        r'(8b0f962) recorded that a live process, jetbrainsd.exe, had '
        r'crashed with an access violation "recorded as occurring directly '
        r'inside heaplens_hook.dll", minutes before a Windows kernel '
        r'bugcheck (DPC_WATCHDOG_VIOLATION) on the same machine. The '
        r'repository records those two events as adjacent. It does not '
        r'claim that one caused the other, and neither do I. It is the '
        r'reason the attach button was switched off within minutes, and '
        r'the reason the rest of this page reads like a safety case.'),
    ...sec(r'the shape of the DLL: four exports, two statics, no DllMain'),
    ...code('rust', 'crates/heaplens-hook/src/lib.rs · the module documentation', r'''
//! Stage 7 capture front-end for injected (uncooperative) processes.
//!
//! Loaded into a target process by `heaplens-injector` and driven via the
//! exported entry points below — never from `DllMain`, per
//! `docs/stage7-injection-design.md` §4.1 (loader-lock deadlock hazard).
//! `HeapLensHookAttach`/`HeapLensHookAttachRemote` install MinHook
//! trampolines on `RtlAllocateHeap`/`RtlReAllocateHeap`/`RtlFreeHeap` and
//! drive the same capture pipeline (`heaplens_alloc::record`, the ring
//! buffer, the writer thread) that the cooperative `#[global_allocator]`
//! producer uses — only the interception mechanism differs. Two attach
//! entry points exist (rather than one) because a raw `CreateRemoteThread`
//! thread and a normal in-process thread have different constraints on how
//! they may safely return — see `HeapLensHookAttachRemote`'s doc comment.
//! `HeapLensHookDetach` (in-process callers) and `HeapLensHookDetachApc`
//! (the `QueueUserAPC`-driven path `heaplens-injector` actually uses, see
//! `WORKER_TID`'s doc comment) both remove the hooks and leave the target
//! exactly as if this DLL had never loaded.'''),
    ...para('//',
        r'Three decisions are packed into those seventeen lines. The first '
        r'is the absence of DllMain. Windows calls a DLL’s DllMain while '
        r'it holds the loader lock, and installing hooks, creating '
        r'threads or opening a pipe under that lock is a known deadlock. '
        r'The design document (section 4.1) therefore specifies two-step '
        r'injection: one remote thread runs LoadLibraryW, which loads the '
        r'DLL and returns, and a second remote thread calls an exported '
        r'function, at which point the loader lock has long been '
        r'released. This file defines no DllMain at all. Its two mentions '
        r'of the word are both comments.'),
    blank,
    ...para('//',
        r'The second is that there are two attach functions where one '
        r'would seem enough. The module comment says only that a raw '
        r'CreateRemoteThread thread "and a normal in-process thread have '
        r'different constraints on how they may safely return". The '
        r'sections below explain what that means; it took a fix that '
        r'did not fix to find out.'),
    blank,
    ...para('//',
        r'The third is that detach is also doubled, and that the variant '
        r'the injector uses is not a thread start routine at all. '
        r'HeapLensHookDetachApc has the shape of a queued asynchronous '
        r'procedure call, and returns nothing. Its result travels through '
        r'a static the injector reads from outside the process.'),
    blank,
    ...pt('//', r'HeapLensHookAttach',
        r'for callers that are already normal threads inside the target. '
        r'The three self-load programs call it directly after '
        r'GetProcAddress. Returns normally.'),
    ...pt('//', r'HeapLensHookAttachRemote',
        r'the CreateRemoteThread start routine the injector uses. Does '
        r'the same work but never returns.'),
    ...pt('//', r'HeapLensHookDetach',
        r'runs the whole teardown on the calling thread. For in-process '
        r'callers.'),
    ...pt('//', r'HeapLensHookDetachApc',
        r'the same teardown, run on the DLL’s own parked worker thread '
        r'when the injector queues an APC to it.'),
    ...pt('//', r'WORKER_TID, DETACH_RESULT',
        r'two exported atomics. The first tells the injector which '
        r'thread to queue the APC to. The second is where the result '
        r'comes back, starting at -1 for "pending".'),
    ...sec(r'choosing the layer: ntdll, not kernelbase'),
    ...para('//',
        r'The first design draft said to hook kernelbase!HeapAlloc and its '
        r'two siblings. The design document, revised after the first '
        r'implementation, records what happened: hooking those "produced '
        r'a reproducible STATUS_ACCESS_VIOLATION on the very first call '
        r'after MinHook::enable_all_hooks() succeeded". MinHook reported '
        r'success at every step. The trampoline it generated was broken '
        r'the instant it was invoked.'),
    blank,
    ...para('//',
        r'The method that separated cause from suspicion is worth '
        r'copying. A control probe hooked a simple, non-allocating export, '
        r'GetTickCount, with the identical create, enable and detour '
        r'pattern. It worked: correct trampoline call, correct return '
        r'value, no crash. That rules out a usage mistake in the '
        r'surrounding code and narrows the fault to something specific '
        r'about HeapAlloc’s prologue on that Windows build. One layer '
        r'down, at ntdll!RtlAllocateHeap, which HeapAlloc wraps, the '
        r'same probe method found it stable, and so did the full '
        r'acceptance gate. The commit message says the same thing in one '
        r'line: "hooking one layer lower ... is stable".'),
    blank,
    ...code('rust', 'crates/heaplens-hook/src/lib.rs · attach_impl, hook creation (first of three, trimmed)', r'''
    let alloc_orig = match unsafe {
        MinHook::create_hook_api("ntdll.dll", "RtlAllocateHeap", hook_heap_alloc as *mut c_void)
    } {
        Ok(p) => p,
        Err(_) => {
            ATTACHED.store(false, Ordering::Release);
            return 2;
        }
    };
    ORIG_HEAP_ALLOC.store(alloc_orig, Ordering::Release);'''),
    ...para('//',
        r'create_hook_api returns the trampoline, a pointer to a relocated '
        r'copy of the function’s first instructions that jumps back into '
        r'the original. The file stores it in an AtomicPtr, because '
        r'detours on any thread will load it, and uses it for two jobs: '
        r'every detour calls the real function through it, and the DLL’s '
        r'own allocator uses it to reach the real heap without passing '
        r'through its own detour.'),
    blank,
    ...para('//',
        r'The design document gives three reasons for the Rtl layer '
        r'beyond stability. Hooking CRT malloc as well would double-count '
        r'every CRT allocation, because malloc calls this layer. The layer '
        r'also catches code that bypasses the CRT and calls Win32 heap '
        r'functions directly, and it avoids per-CRT-version symbol '
        r'variance (static against dynamic CRT, debug against release). '
        r'The price is stated in the same breath: it observes heap '
        r'operations, not CRT semantics, so calloc’s zeroing is invisible '
        r'as a distinct step, and it sees ambient traffic. The writer '
        r'thread’s own pipe I/O causes Windows-internal heap calls, which '
        r'is why the self-load harness comments say it saw "extra '
        r'captured events with sizes never requested here" and why the '
        r'daemon-side gate matches events to the workload by pointer '
        r'identity instead of asserting a raw total.'),
    ...sec(r'the detours: run the real thing first, then record'),
    ...code('rust', 'crates/heaplens-hook/src/lib.rs · the allocation detour', r'''
// ── Hook detours ────────────────────────────────────────────────────────
//
// Each detour calls straight through to the trampoline (the real function,
// MinHook-relocated — never re-enters our own patched code), then drives
// the shared capture pipeline via `heaplens_alloc::record`, which checks
// the per-thread reentrancy guard as its very first action.

unsafe extern "system" fn hook_heap_alloc(hheap: HANDLE, dwflags: u32, dwbytes: usize) -> *mut c_void {
    let trampoline = ORIG_HEAP_ALLOC.load(Ordering::Acquire);
    let real: HeapAllocFn = unsafe { std::mem::transmute(trampoline) };
    let ptr = unsafe { real(hheap, dwflags, dwbytes) };
    if dwbytes == CANARY_SIZE {
        // The attach-time canary (below): proves this detour actually ran
        // and the trampoline actually produced a real allocation. Not a
        // real event — never recorded, so it never reaches the wire.
        CANARY_HIT.store(true, Ordering::Release);
        return ptr;
    }
    if !ptr.is_null() {
        heaplens_alloc::record(EventKind::Alloc, ptr as u64, 0, dwbytes as u64, 0);
    }
    ptr
}'''),
    ...code('rust', 'crates/heaplens-hook/src/lib.rs · the free detour', r'''
unsafe extern "system" fn hook_heap_free(hheap: HANDLE, dwflags: u32, lpmem: *const c_void) -> i32 {
    let trampoline = ORIG_HEAP_FREE.load(Ordering::Acquire);
    let real: HeapFreeFn = unsafe { std::mem::transmute(trampoline) };
    let result = unsafe { real(hheap, dwflags, lpmem) };
    if result != 0 {
        // §1.4: an unknown-pointer free (pre-attach allocation) is handled
        // downstream by `Graph::on_dealloc` returning early — nothing to
        // special-case here.
        heaplens_alloc::record(EventKind::Dealloc, lpmem as u64, 0, 0, 0);
    }
    result
}'''),
    ...para('//',
        r'The shape is the same for all three. Load the trampoline, call '
        r'the real function, and only if it succeeded hand the outcome to '
        r'heaplens_alloc::record. A null allocation is not recorded, and '
        r'a free is recorded only when the real free reported success '
        r'(result != 0). Recording after the fact means the event '
        r'describes something that actually happened to the heap, never '
        r'an attempt. record() then does the cheap checks first: the '
        r'per-thread reentrancy guard is its very first action (the '
        r'comment above the detours says so), then the opt-in test, the '
        r'timestamp, the raw stack capture and the lock-free push onto '
        r'the thread’s ring.'),
    blank,
    ...para('//',
        r'The Realloc detour passes both pointers, new and old, which is '
        r'what lets the daemon cope with the case injection makes common. '
        r'A block allocated before attach can be reallocated after it. '
        r'The design document verified, against the daemon’s '
        r'Graph::on_realloc, that an unknown old pointer falls through to '
        r'on_alloc and registers the new pointer as a fresh node, which '
        r'is right because a live allocation exists now even though its '
        r'origin was missed. A free of an unknown pointer, by contrast, is '
        r'dropped in on_dealloc, because there is nothing left to track. '
        r'The comment inside hook_heap_free points at exactly that '
        r'asymmetry and says nothing needs special-casing here.'),
    blank,
    ...para('//',
        r'One ordering difference deserves a note, and it is my reading '
        r'rather than something the file discusses. The cooperative '
        r'allocator records a Dealloc before it calls System.dealloc: '
        r'commit 69e61dd, whose subject says "dealloc ordering" and whose '
        r'body is empty, swapped those two lines on the day '
        r'heaplens-alloc was written. A natural reason is '
        r'that once memory is freed another thread can be handed the same '
        r'address and record its allocation first. The hook cannot copy '
        r'that order, since it wants to know whether the free succeeded, '
        r'so it records after. I did not find the window addressed in '
        r'the hook, and I did not find a test that pins it down.'),
    ...sec(r'the canary: "enable succeeded" proves nothing'),
    ...code('rust', 'crates/heaplens-hook/src/lib.rs · the canary constants', r'''
// A size no real caller would ever request, used to prove the trampoline
// actually works end to end (real call -> detour invoked -> real function
// executed -> detour returns the correct result) before trusting the hook
// with a real target. MinHook reporting "enable succeeded" is not
// sufficient evidence on its own — that is exactly the failure mode found
// hooking the kernelbase!HeapAlloc layer (§1.1): every install/enable step
// reported success while the generated trampoline was broken, and the
// first real call after enable crashed. See `HeapLensHookAttach`'s canary
// check, run once per attach, before any real capture is trusted.
const CANARY_SIZE: usize = 0xC0FFEE;
static CANARY_HIT: AtomicBool = AtomicBool::new(false);'''),
    ...para('//',
        r'The kernelbase experience left a rule. A hook library cannot '
        r'treat its own success codes as evidence, so attach runs a '
        r'proof against itself. After enabling the hooks it allocates '
        r'0xC0FFEE bytes, which is 12,648,430, a little over 12 MiB, '
        r'through the real process heap, so the request goes through the '
        r'detour. The detour recognises the size, sets CANARY_HIT and '
        r'returns without recording, so the canary never reaches the '
        r'wire. Attach then checks both that the pointer is non-null and '
        r'that the flag was set.'),
    ...code('rust', 'crates/heaplens-hook/src/lib.rs · attach_impl, step 4', r'''
    // 4. Canary: prove the trampoline actually works before trusting it
    //    with a real target. A broken trampoline must never stay resident
    //    — fail clean and detach rather than leave a corrupting hook
    //    installed. Uses the real (now-hooked) process heap directly, not
    //    the private heap, so this genuinely exercises the detour path a
    //    real caller would take.
    CANARY_HIT.store(false, Ordering::Release);
    let canary_ptr = unsafe { HeapAlloc(GetProcessHeap(), 0, CANARY_SIZE) };
    let canary_ok = !canary_ptr.is_null() && CANARY_HIT.load(Ordering::Acquire);
    if !canary_ptr.is_null() {
        unsafe { HeapFree(GetProcessHeap(), 0, canary_ptr as *const c_void) };
    }
    if !canary_ok {
        let _ = unsafe { MinHook::disable_all_hooks() };
        let _ = heaplens_alloc::request_writer_stop_and_wait(std::time::Duration::from_secs(2));
        MinHook::uninitialize();
        ORIG_HEAP_ALLOC.store(std::ptr::null_mut(), Ordering::Release);
        ORIG_HEAP_REALLOC.store(std::ptr::null_mut(), Ordering::Release);
        ORIG_HEAP_FREE.store(std::ptr::null_mut(), Ordering::Release);
        let heap = PRIVATE_HEAP.swap(std::ptr::null_mut(), Ordering::AcqRel);
        if !heap.is_null() {
            unsafe { HeapDestroy(heap as HANDLE) };
        }
        ATTACHED.store(false, Ordering::Release);
        return 7;
    }

    0
}'''),
    ...para('//',
        r'If the canary fails, the hooks are disabled, the writer is '
        r'stopped (bounded at two seconds), MinHook is uninitialised, '
        r'the trampolines and the private heap are released, and attach '
        r'returns 7. The injector turns that code into a sentence that '
        r'promises something specific: "hooks were disabled and torn down '
        r'automatically; the hook was not left resident". The principle '
        r'is fail clean, and the comment in the code states it as a '
        r'rule: a broken trampoline "must never stay resident". It is '
        r'the one outcome that corrupts a stranger’s process, so the '
        r'code prefers to refuse the attach.'),
    blank,
    ...para('//',
        r'What the canary proves is narrower than it looks. It exercises '
        r'the allocation detour and its trampoline. The cleanup free goes '
        r'through the free detour, so that path runs too, but nothing '
        r'asserts on it, and nothing exercises the realloc detour at all. '
        r'Also, a size is a magic number: a target that really requested '
        r'exactly 12,648,430 bytes while hooks were live would have that '
        r'one allocation silently go unrecorded. That loses an event; it '
        r'cannot corrupt anything.'),
    ...sec(r'a private heap, and a small state machine hiding in an allocator'),
    ...para('//',
        r'The DLL contains Rust code that allocates: channels, vectors, '
        r'the writer’s batch buffers, everything heaplens-alloc does. If '
        r'those allocations landed on the heap being observed, they would '
        r'reach the detour, and the design document’s answer in section '
        r'4.2 is a private heap created with HeapCreate at attach time. '
        r'The file makes the DLL’s own #[global_allocator] a thin wrapper '
        r'around it.'),
    ...code('rust', 'crates/heaplens-hook/src/lib.rs · the ordering invariant and the statics', r'''
// ── Private heap allocator (§4.2: internal bookkeeping never lands on the ─
//    target's own default heap, isolating our footprint from what the
//    target — or its own diagnostics — would see as its heap contents).
//
// Ordering invariant this module depends on: `PRIVATE_HEAP` is set *before*
// hooks are created/enabled in `HeapLensHookAttach`, and cleared *after*
// hooks are disabled/removed in `HeapLensHookDetach`. This guarantees the
// fallback branch below (`heap.is_null()`) — which calls the plain,
// unpatched `HeapAlloc`/`GetProcessHeap` — only ever executes while no hook
// is installed, so it can never recurse into our own detour.

static PRIVATE_HEAP: AtomicPtr<c_void> = AtomicPtr::new(std::ptr::null_mut());
static ORIG_HEAP_ALLOC: AtomicPtr<c_void> = AtomicPtr::new(std::ptr::null_mut());
static ORIG_HEAP_REALLOC: AtomicPtr<c_void> = AtomicPtr::new(std::ptr::null_mut());
static ORIG_HEAP_FREE: AtomicPtr<c_void> = AtomicPtr::new(std::ptr::null_mut());
static ATTACHED: AtomicBool = AtomicBool::new(false);'''),
    ...code('rust', 'crates/heaplens-hook/src/lib.rs · PrivateHeapAlloc::alloc (trimmed)', r'''
unsafe impl std::alloc::GlobalAlloc for PrivateHeapAlloc {
    unsafe fn alloc(&self, layout: std::alloc::Layout) -> *mut u8 {
        let size = layout.size().max(1);
        let heap = PRIVATE_HEAP.load(Ordering::Acquire);
        if heap.is_null() {
            // Bootstrap window (before HeapCreate in attach, or after
            // HeapDestroy in detach): no hook is installed here, so the
            // plain Win32 call below is the real, unpatched function.
            return unsafe { HeapAlloc(GetProcessHeap(), 0, size) as *mut u8 };
        }
        let trampoline = ORIG_HEAP_ALLOC.load(Ordering::Acquire);
        if trampoline.is_null() {
            // Private heap exists but hooks aren't installed yet (mid-attach).
            return unsafe { HeapAlloc(heap as HANDLE, 0, size) as *mut u8 };
        }
        let f: HeapAllocFn = unsafe { std::mem::transmute(trampoline) };
        unsafe { f(heap as HANDLE, 0, size) as *mut u8 }
    }'''),
    ...para('//',
        r'Read alloc() as a three-state machine whose state is two '
        r'atomics. While PRIVATE_HEAP is null, nothing is hooked, so the '
        r'plain HeapAlloc on the process heap is the real, unpatched '
        r'function and cannot recurse. Once the heap exists but the '
        r'trampoline does not, the allocator calls HeapAlloc on the '
        r'private heap, still unhooked. In steady state it calls the '
        r'trampoline, the real RtlAllocateHeap, with the private heap’s '
        r'handle, so the allocation never enters the detour. That is the '
        r'design document’s point in section 4.2: the guard flag is one '
        r'defence, and "even if the guard were somehow bypassed, the '
        r'hook’s internal allocations physically cannot reach the hooked '
        r'functions".'),
    blank,
    ...para('//',
        r'The invariant in the comment is what keeps the first state '
        r'honest: PRIVATE_HEAP is set before hooks are created, and '
        r'cleared after they are disabled, so the fallback branch only '
        r'runs while no hook exists. The same shape, with the same '
        r'null-check on the trampoline, appears in dealloc and realloc. '
        r'It is the file’s most compact piece of reasoning and the one '
        r'whose limits I discuss at the end.'),
    ...sec(r'attach_impl: the order is a requirement, not a preference'),
    ...code('rust', 'crates/heaplens-hook/src/lib.rs · attach_impl, steps 1 and 2', r'''
fn attach_impl() -> u32 {
    if ATTACHED.swap(true, Ordering::AcqRel) {
        return 0; // already attached — idempotent
    }

    // 1. Private heap first (§4.2), using the real, not-yet-hooked HeapCreate.
    let heap = unsafe { HeapCreate(0, 0, 0) };
    if heap.is_null() {
        ATTACHED.store(false, Ordering::Release);
        return 1;
    }
    PRIVATE_HEAP.store(heap as *mut c_void, Ordering::Release);

    // 2. Force every piece of heavyweight, first-time infrastructure setup
    //    the capture pipeline depends on to complete now, from this normal
    //    thread context — before any hook is installed. Two hazards
    //    confirmed empirically, same class, same fix pattern:
    //    (a) spawning the writer thread lazily from inside a hook callback
    //        (the cooperative allocator's approach, safe there) crashes
    //        here, because CreateThread's synchronous DLL_THREAD_ATTACH
    //        bootstrap on the new thread reenters the not-yet-stable hooked
    //        allocation path;
    //    (b) even with the writer thread spawned eagerly, its first
    //        `backtrace::resolve` call (dbghelp.dll load + SymInitialize)
    //        still crashed once hooks were live, for the same underlying
    //        reason one layer later.
    //    See the safety notes on `heaplens_alloc::ensure_writer` and
    //    `heaplens_alloc::warm_up_symbol_resolution`. By the time any hook
    //    callback below fires, both are already warm, so nothing on the
    //    hot path performs first-time OS-level initialization.
    heaplens_alloc::warm_up_symbol_resolution();
    heaplens_alloc::ensure_writer_started();
    // Give the writer thread a brief head start to reach its own connect
    // loop before hooks go live, reducing (not eliminating — the ring
    // buffer tolerates this) the chance its first real batch races hook
    // installation.
    std::thread::sleep(std::time::Duration::from_millis(50));'''),
    ...para('//',
        r'The comment in step 2 is the compressed result of two '
        r'investigations, each done the same way the commit message '
        r'describes: "each confirmed by disabling one thing at a time '
        r'until the crash disappeared". The cooperative allocator starts '
        r'its writer thread lazily, from inside the first record() call, '
        r'and that is safe there because record() runs on an ordinary '
        r'thread making an ordinary allocation. Inside a detour it is '
        r'not. CreateThread delivers DLL_THREAD_ATTACH to every loaded '
        r'DLL on the new thread, synchronously, before the thread is '
        r'fully initialised, and that bootstrap makes heap calls, which '
        r're-enter the hooked path while it is not yet stable. Crash. '
        r'Starting the writer eagerly, before any hook exists, fixed it, '
        r'and exposed the second case one layer later: the writer’s first '
        r'backtrace::resolve loads dbghelp.dll and runs SymInitialize, '
        r'which does heavyweight first-time setup, and doing that for '
        r'the first time while RtlAllocateHeap is hooked process-wide '
        r'crashed too. Hence the general rule the alloc crate’s doc '
        r'comment states: any first-time, heavyweight initialisation the '
        r'pipeline depends on must finish before enable_all_hooks.'),
    blank,
    ...para('//',
        r'The design document adds a warning that deserves to be '
        r'quoted, because it is about testing: reverting to lazy '
        r'initialisation "to simplify" would reintroduce a '
        r'target-crashing bug "invisible to any test run in a warm '
        r'process". A harness that had already loaded dbghelp elsewhere '
        r'would pass. The 50 ms sleep after the writer starts is honest '
        r'about its own limits: it reduces, "not eliminating", the chance '
        r'that the writer’s first batch races hook installation, and the '
        r'ring buffer tolerates the race that remains.'),
    blank,
    ...para('//',
        r'The failure codes are a contract with the injector, whose '
        r'report_hook_rc maps them to sentences:'),
    ...pt('//', r'1', r'HeapCreate failed, so there is no private heap.'),
    ...pt('//', r'2, 3, 4', r'MinHook could not create the hook for '
        r'RtlAllocateHeap, RtlReAllocateHeap or RtlFreeHeap respectively.'),
    ...pt('//', r'5', r'enable_all_hooks failed.'),
    ...pt('//', r'7', r'the canary failed and everything was torn down.'),
    ...pt('//', r'6', r'never returned by attach. It belongs to detach: '
        r'the writer would not stop within two seconds.'),
    ...sec(r'the thread that must never return'),
    ...para('//',
        r'The injector starts attach with CreateRemoteThread, which '
        r'creates a bare OS thread: no C runtime initialisation, no '
        r'Rust thread setup. The file’s answer is two layers, and the '
        r'first is a shared core.'),
    ...code('rust', 'crates/heaplens-hook/src/lib.rs · attach_and_wait', r'''
fn attach_and_wait() -> u32 {
    let (tx, rx) = std::sync::mpsc::channel();
    let spawned = std::thread::Builder::new().spawn(move || {
        WORKER_TID.store(unsafe { GetCurrentThreadId() }, Ordering::Release);
        let rc = attach_impl();
        let _ = tx.send(rc);
        loop {
            unsafe { SleepEx(u32::MAX, 1) };
        }
    });
    if spawned.is_err() {
        return u32::MAX;
    }
    rx.recv().unwrap_or(u32::MAX)
}'''),
    ...para('//',
        r'The raw thread does nothing but spawn a real Rust thread and '
        r'block for its answer. That worker does the work (attach_impl) '
        r'and then does not exit: it sends its result and enters an '
        r'infinite alertable wait, SleepEx(INFINITE, TRUE), forever. The '
        r'comment above it gives the reason as the sixth hazard. The '
        r'worker’s natural exit "crashed even after attach_impl’s entire '
        r'body completed successfully", because a thread exiting runs '
        r'DLL_THREAD_DETACH and TLS cleanup, which performs heap '
        r'operations that route through hooks that must stay live. '
        r'Elsewhere the fix for that class of problem was to disable '
        r'the hooks first; here that would undo the attach. The only '
        r'remaining option is that the thread never exits: "One '
        r'permanently-parked thread per attach is an acceptable, '
        r'one-time cost". The wait being alertable is not incidental. It '
        r'is what lets detach reuse the same thread later.'),
    blank,
    ...para('//',
        r'The doc comments on this function are a fossil record, and '
        r'worth a moment. The paragraph that begins "Returns 0 on '
        r'success" and talks about the sixth hazard describes '
        r'HeapLensHookAttach as it was before Remote was split out, so I '
        r'read it as having been left behind when attach_and_wait took '
        r'over the body. The comments are not wrong. They are stacked in '
        r'the order the discoveries were made.'),
    blank,
    ...code('rust', 'crates/heaplens-hook/src/lib.rs · HeapLensHookAttachRemote', r'''
#[unsafe(no_mangle)]
pub unsafe extern "system" fn HeapLensHookAttachRemote() -> u32 {
    let result = attach_and_wait();
    heaplens_alloc::guard::force_enter_permanent();
    // SAFETY / DO NOT REORDER: this call is only lock-free because nothing
    // between `attach_and_wait()` returning and this line touches a lock or
    // the heap — see docs/stage7-injection-design.md §4.1 ("fifth hazard")
    // for the full proof. `attach_and_wait()`'s `rx.recv()` has already
    // *returned* (its `Receiver::drop` already ran, uninterrupted, as part
    // of that normal return) and `force_enter_permanent()` is a
    // `const`-initialized fast-TLS store with no allocation. If you add ANY
    // code between the two lines above and this `TerminateThread` call —
    // including something that looks allocation-free — re-verify the proof
    // before assuming it still holds: `TerminateThread` skips all normal
    // cleanup (no unwind, no Drop, no lock release), so anything left
    // locked here stays locked for the rest of the target's process
    // lifetime.
    unsafe { TerminateThread(GetCurrentThread(), result) };
    // Per Win32 docs, TerminateThread does not return when the target is
    // the calling thread. This is unreachable in practice; parking keeps
    // the (never-taken) fallback well-defined rather than returning
    // through the now-abandoned normal path.
    loop {
        std::thread::park();
    }
}'''),
    ...para('//',
        r'This is the ninth hazard, and its story is the best lesson in '
        r'the file. The doc comment above the function says the ninth was '
        r'found "after the eighth’s fix (force_enter_permanent) failed to '
        r'resolve an identical crash on this path". The eighth fix '
        r'marked the raw thread permanently guarded so that none of its '
        r'own heap frees after attach could be captured. Diagnostics '
        r'then showed every one of those frees correctly suppressed, '
        r'with no capture_stack ever attempted, yet the process still '
        r'died with the same STATUS_STACK_BUFFER_OVERRUN signature. A '
        r'fix that does not fix is evidence: the fault was not in '
        r'anything record() does. It was in the act of returning. A '
        r'normal return from a CreateRemoteThread start routine makes '
        r'the OS call ExitThread, which delivers DLL_THREAD_DETACH to '
        r'every loaded DLL on that thread, deep inside ntdll’s '
        r'thread-shutdown path, on a thread the CRT never initialised. '
        r'The comment calls the fault code a /GS stack-cookie mismatch, '
        r'"consistent with an actual overrun".'),
    blank,
    ...para('//',
        r'The fix is architectural, in the comment’s own words, not '
        r'"another point patch": never let this thread "reach that '
        r'teardown sequence at all". TerminateThread on the calling '
        r'thread is '
        r'documented to skip DLL_THREAD_DETACH, normally a liability '
        r'because per-thread cleanup leaks, and here exactly the needed '
        r'property, since this thread only spawned a worker and waited. '
        r'The exit code is still set from the result, so the '
        r'injector’s GetExitCodeThread read is unaffected. And because '
        r'TerminateThread skips every unwind and drop, the comment '
        r'turns the proof into an instruction: DO NOT REORDER, with '
        r'the argument that nothing between the receive and the '
        r'terminate touches a lock or the heap. That is a good habit: '
        r'put the invariant next to the line that depends on it, in '
        r'capital letters, with the proof or a pointer to it.'),
    blank,
    ...para('//',
        r'The two attach functions are separate exports for a reason the '
        r'comment states from experience. Merging them behind a flag '
        r'broke the Step 1 gate the first time: the self-load harness '
        r'calls HeapLensHookAttach on its own long-lived main thread, '
        r'and an unconditional TerminateThread there "kills that thread '
        r'(and its still-pending workload) outright".'),
    ...sec(r'the hazard ledger'),
    ...para('//',
        r'The source numbers its hazards in comments. Collecting them in '
        r'one place, with the numbers the source uses and the evidence '
        r'it gives, shows the pattern. Nearly every one is a thread-lifecycle '
        r'notification, or a piece of first-use setup, that touches '
        r'the heap while a hook is live.'),
    blank,
    ...pt('//', r'wrong layer',
        r'kernelbase!HeapAlloc: crash on the first call after enable. '
        r'Fix: hook ntdll. Found by the GetTickCount control probe.'),
    ...pt('//', r'writer spawned lazily',
        r'DLL_THREAD_ATTACH on the new thread re-enters the hook. Fix: '
        r'ensure_writer_started before any hook.'),
    ...pt('//', r'dbghelp first use',
        r'SymInitialize under a live hook. Fix: '
        r'warm_up_symbol_resolution before any hook.'),
    ...pt('//', r'writer exits under a live hook (fourth)',
        r'its DLL_THREAD_DETACH heap traffic goes through the detour. '
        r'Fix: disable hooks first, then stop the writer.'),
    ...pt('//', r'real work on a raw thread (fifth)',
        r'STATUS_STACK_BUFFER_OVERRUN although the same code worked '
        r'in-process. Fix: the raw thread only spawns and joins.'),
    ...pt('//', r'worker thread exit (sixth)',
        r'crash after a fully successful attach. Fix: the worker never '
        r'exits and parks in an alertable wait.'),
    ...pt('//', r'second CreateRemoteThread',
        r'creating the detach thread at all triggers '
        r'DLL_THREAD_ATTACH into the live hook; confirmed with a body '
        r'reduced to "return 42". Fix: queue an APC to the worker. The '
        r'source does not number this one.'),
    ...pt('//', r'return of the raw thread (eighth, ninth)',
        r'force_enter_permanent did not help; the return itself was '
        r'the fault. Fix: TerminateThread on self, in a separate '
        r'export.'),
    ...pt('//', r'spawning inside in-process Detach (tenth)',
        r'the new thread’s DLL_THREAD_ATTACH reenters the active '
        r'detour before detach_impl can disable it. Fix: run '
        r'detach_impl on the caller’s thread.'),
    ...pt('//', r'thread_local! (not numbered)',
        r'crash on any thread other than the one that called '
        r'LoadLibraryW. Fix lives in guard.rs and ring.rs, plus one '
        r'call here.'),
    ...pt('//', r'exit without detach (not numbered)',
        r'an orphaned DBGHELP_LOCK. Fix lives in capture.rs.'),
    blank,
    ...para('//',
        r'The numbering skips seven in the surviving text. The '
        r'second-CreateRemoteThread problem sits where a seventh would, '
        r'but I cannot confirm that was its number. There is also a '
        r'dangling reference: the DO NOT REORDER comment points to '
        r'section 4.1 of the design document ("fifth hazard") for the '
        r'full proof, and the committed design document stops at a '
        r'fourth hazard. The argument is in the comment next to the '
        r'line, but the cross-reference does not resolve.'),
    ...sec(r'detach, part one: a mailbox and an APC'),
    ...code('rust', 'crates/heaplens-hook/src/lib.rs · the cross-process detach handshake', r'''
// ── Cross-process detach handshake (§8 Step 2) ─────────────────────────
//
// `heaplens-injector` cannot safely run `HeapLensHookDetach` via a second
// `CreateRemoteThread` call while hooks are active: creating that thread
// at all — regardless of what code it runs — makes the OS deliver
// `DLL_THREAD_ATTACH` to every loaded DLL on it (including `ucrtbase`'s own
// per-thread setup) *before* our code gets control, and that notification's
// own heap traffic reenters our still-active detour on a `CreateRemoteThread`
// -created "raw" thread — the same class of stack-walk hazard documented on
// `HeapLensHookAttach`'s own exit path, just at start instead of end.
// Confirmed empirically: even a `HeapLensHookDetach` body reduced to an
// immediate `return 42` (no spawn, no real work) still crashed identically
// whenever hooks were active at the moment the injector's second
// `CreateRemoteThread` call created the thread — proving the fault is in the
// automatic notification, not anything this module's code does.
//
// The fix avoids creating a second raw thread at all: `attach_impl`'s own
// worker thread (already alive, already a normal, properly CRT-initialized
// Rust thread — safe by construction, unlike a `CreateRemoteThread` thread)
// parks itself in an *alertable* wait instead of an inert one, and exposes
// its OS thread ID here so `heaplens-injector` can `QueueUserAPC` detach
// work directly onto it from outside the process — no new thread, so no
// `DLL_THREAD_ATTACH` hazard. `HeapLensHookDetachApc` below is the queued
// callback; `DETACH_RESULT` is how the injector (which cannot receive a
// return value from a queued APC) reads the outcome back via
// `ReadProcessMemory`, polling until it leaves its `-1` "pending" sentinel.
#[unsafe(no_mangle)]
pub static WORKER_TID: AtomicU32 = AtomicU32::new(0);
#[unsafe(no_mangle)]
pub static DETACH_RESULT: AtomicI32 = AtomicI32::new(-1);'''),
    ...para('//',
        r'The conventional detach would have the injector run one more '
        r'CreateRemoteThread against an exported detach function. That '
        r'fails for the reason the comment gives: creating the thread '
        r'at all makes the OS deliver '
        r'DLL_THREAD_ATTACH to every loaded DLL, including ucrtbase’s '
        r'own per-thread setup, before any of this code gets control, '
        r'and that notification’s heap traffic reenters the still-active '
        r'detour on a raw thread. The comment records the experiment '
        r'that settled it: a HeapLensHookDetach body reduced to "an '
        r'immediate return 42 (no spawn, no real work)" still crashed '
        r'whenever hooks were active at the moment the thread was '
        r'created. The fault was in the notification, not in any code '
        r'the file runs.'),
    blank,
    ...para('//',
        r'So the injector creates no thread. It reads WORKER_TID out of '
        r'the target with ReadProcessMemory, opens that thread with '
        r'THREAD_SET_CONTEXT, queues HeapLensHookDetachApc to it, and '
        r'polls DETACH_RESULT, which it first reset to -1. A queued APC '
        r'has no return channel, and the sentinel makes a stale value '
        r'from an earlier cycle impossible to mistake for this one. The '
        r'APC runs on a thread that is already alive, already a proper '
        r'Rust thread, and parked in an alertable wait, which is what '
        r'SleepEx(INFINITE, TRUE) was for.'),
    blank,
    ...code('rust', 'crates/heaplens-hook/src/lib.rs · the APC entry point', r'''
#[unsafe(no_mangle)]
pub unsafe extern "system" fn HeapLensHookDetachApc(_param: usize) {
    let rc = detach_impl();
    DETACH_RESULT.store(rc as i32, Ordering::Release);
}'''),
    ...para('//',
        r'It is five lines because it is a mailbox write around the '
        r'real function. The result is stored with Release ordering '
        r'and read by a different process, which is the only reason an '
        r'atomic is involved.'),
    ...sec(r'detach, part two: the order is the whole point'),
    ...code('rust', 'crates/heaplens-hook/src/lib.rs · detach_impl, the load-bearing lines (trimmed)', r'''
fn detach_impl() -> u32 {
    if !ATTACHED.swap(false, Ordering::AcqRel) {
        return 0; // not attached — idempotent no-op
    }
...
    let _ = unsafe { MinHook::disable_all_hooks() };
...
    let stopped = heaplens_alloc::request_writer_stop_and_wait(std::time::Duration::from_secs(2));
    if !stopped {
        // Hooks are already disabled (safe either way at this point), but
        // do NOT free MinHook's trampolines or the private heap: the
        // writer thread may still be executing code that depends on both.
        // Leave ATTACHED false — a stuck writer thread means this DLL
        // instance cannot cleanly detach; the caller should not retry into
        // the same, already-compromised state.
        return 6;
    }
...
    heaplens_alloc::shutdown_ring_storage();
...
    MinHook::uninitialize();

    ORIG_HEAP_ALLOC.store(std::ptr::null_mut(), Ordering::Release);
    ORIG_HEAP_REALLOC.store(std::ptr::null_mut(), Ordering::Release);
    ORIG_HEAP_FREE.store(std::ptr::null_mut(), Ordering::Release);

    let heap = PRIVATE_HEAP.swap(std::ptr::null_mut(), Ordering::AcqRel);
    if !heap.is_null() {
        unsafe { HeapDestroy(heap as HANDLE) };
    }

    0
}'''),
    ...para('//',
        r'Detach is attach in reverse, and the reverse is not '
        r'symmetrical by accident. The idempotence swap on ATTACHED '
        r'comes first, so a second detach is a no-op. Then:'),
    ...pt('//', r'disable the hooks',
        r'before anything else. disable_all_hooks un-redirects the '
        r'three functions but does not free the trampolines, so '
        r'PrivateHeapAlloc, which the writer thread still uses, keeps '
        r'working through this window.'),
    ...pt('//', r'stop the writer, bounded',
        r'now its exit-time DLL_THREAD_DETACH traffic goes through the '
        r'real, unhooked functions. That ordering is the fourth '
        r'hazard’s fix. The two-second timeout, the comment says, '
        r'mirrors "the launcher’s own bounded-detach pattern (section '
        r'4.6)": never let a hung wait block teardown indefinitely. The '
        r'launcher page explains that the launcher never received that '
        r'step.'),
    ...pt('//', r'if the writer does not stop, do less, not more',
        r'return 6 without freeing the trampolines or the private '
        r'heap, because the writer may still be executing code that '
        r'depends on both, and leave ATTACHED false so nobody retries '
        r'into a compromised state. The design document’s reasoning '
        r'is that freeing either "out from under a thread that may '
        r'still be executing code depending on either is worse than '
        r'leaving the hook installed".'),
    ...pt('//', r'tear down ring storage',
        r'one call added by the TLS fix, dcc76f2, explained next.'),
    ...pt('//', r'only then uninitialise MinHook and destroy the heap',
        r'in that order, with the three trampoline pointers set to '
        r'null in between so that no stale pointer survives.'),
    ...sec(r'the TLS and FLS crash, as it touched this file'),
    ...para('//',
        r'On the evening of 2026-07-21 the new stress harness '
        r'(self_load_concurrency_stress, 48 threads for 8 seconds) '
        r'crashed reliably under the hook and ran cleanly unhooked. The '
        r'fix, dcc76f2, landed fifty-eight minutes after the harness '
        r'commit. The diagnosis lives on the guard.rs and ring.rs pages: '
        r'rustc may implement thread_local! with a PE .tls variable '
        r'that only works for modules the loader linked at startup, and '
        r'this DLL never is. A first attempted fix, giving the value a '
        r'Drop impl, did not help, and the commit message says so, which '
        r'is how that dead end got recorded. The cure was raw TlsAlloc '
        r'for the guard and raw FlsAlloc for the ring registry.'),
    blank,
    ...para('//',
        r'lib.rs gained ten lines and lost two, all for the second crash '
        r'the first fix uncovered. A stale FLS registration, set by '
        r'hooked allocations inside the harness’s own println! calls, '
        r'had its callback inside this DLL; if the process unloaded the '
        r'DLL first, the callback ran into unmapped memory, after an '
        r'otherwise clean attach, workload and detach. The remedy is the '
        r'one call detach_impl now makes, '
        r'heaplens_alloc::shutdown_ring_storage(), which does FlsFree '
        r'and deregisters the index outright. ring.rs accepts the '
        r'trade-off: a thread still alive with an unflushed ring loses '
        r'automatic dead-producer detection, "a stale entry, not a '
        r'crash".'),
    ...sec(r'exit without detach: two defects, found in one night'),
    ...para('//',
        r'The last chapter is not in this file, and it is the one '
        r'that most changed what the file is trusted to do. A target '
        r'that exits normally while the hooks are still installed is '
        r'the ordinary case for a program the user did not detach. On '
        r'2026-07-26 at 02:42 commit 306e8fc switched the attach button '
        r'off again, citing a "confirmed DLL_PROCESS_DETACH crash" and '
        r'adding that the hook "has no DLL_PROCESS_DETACH safety '
        r'handling". Within half an hour, deff3ad re-tested the exact '
        r'repro against the fixed build and reported the original crash '
        r'did not reproduce (15 clean runs of the single-threaded '
        r'target, and 30 runs of fls_race_repro, which is 6,000 '
        r'race attempts). It also found something worse: with '
        r'several worker threads continuously allocating, the target '
        r'did not crash but hung, roughly 40 to 60 percent of runs, and '
        r'resisted Stop-Process and taskkill; only a WMI Terminate '
        r'worked.'),
    blank,
    ...para('//',
        r'A symbol-resolved WinDbg stack, taken non-invasively because '
        r'an invasive attach was itself found to make the hang '
        r'disappear, put the sole surviving thread in '
        r'heaplens_alloc::capture::capture_stack, reached through '
        r'hook_heap_free, from the CRT’s own FLS cleanup during '
        r'RtlExitUserProcess. The mechanism is on the pages for '
        r'exit_without_detach_multithreaded.rs and capture.rs: '
        r'RtlExitUserProcess kills the other threads without cleanup, '
        r'one of them dies holding the global DBGHELP_LOCK, and the '
        r'survivor’s hooked free then blocks on that orphaned lock '
        r'forever. The fix, b5c5aed at 07:13, changed one '
        r'.lock() to .try_lock() in capture_stack. Nothing in lib.rs '
        r'changed. The file’s share in the story is that it is the '
        r'route by which a free reaches capture_stack at that moment '
        r'at all, because hooks stay installed after the injector '
        r'exits.'),
    blank,
    ...para('//',
        r'On 2026-07-28 at 02:38 the attach button was enabled again '
        r'(9693399, whose message gives the reason as "for '
        r'soutenance"). Its doc comment in control_bar.dart now lists '
        r'both defects as fixed and validated, and keeps the flag as a '
        r'single gate so that any future regression can be disabled '
        r'"the same visible, honest way".'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'There is not one #[test] in this file. A cdylib that patches '
        r'process-global functions cannot be unit-tested in a process '
        r'that also runs other tests, so every test loads the real DLL '
        r'into a separate process.'),
    ...pt('//', r'self_load_harness and hook_self_load_wire',
        r'the Step 1 acceptance gate: exactly 50 allocations, 11 '
        r'reallocations (10 tracked, 1 on a pre-attach pointer), '
        r'51 frees, matched by pointer identity, then zero events '
        r'from a second workload after detach.'),
    ...pt('//', r'the spawned-thread example and its daemon test',
        r'the targeted regression test for the TLS crash: every '
        r'allocation is on a spawned thread. The commit message '
        r'points out that the original gate never exercised this, '
        r'because its whole workload ran on the thread that called '
        r'LoadLibraryW.'),
    ...pt('//', r'self_load_concurrency_stress.rs',
        r'48 threads, 8 seconds, baseline then hooked, kept as the '
        r'standing repro. After the fix: 20 consecutive clean runs '
        r'across two rebuilds.'),
    ...pt('//', r'hook_owner_free_no_crash.rs',
        r'four tests with real injection: detach before exit, exit '
        r'without detach, multi-threaded exit without detach, and the '
        r'FLS-race repro. None is ignored any more.'),
    blank,
    ...para('//',
        r'The Step 1 design had a sentence that set the bar, and all '
        r'of the above is held to it: a gate that only confirms the DLL '
        r'loads and does not crash "would pass with a silently broken '
        r'capture path". Fixed workload in, exact counts out, before '
        r'and after detach.'),
    ...sec(r'limits and open questions'),
    ...pt('//', r'rollback is asymmetric',
        r'only the canary failure (7) tears everything down. After '
        r'return codes 2 to 5, the code resets ATTACHED but leaves '
        r'the private heap assigned, the writer thread running, and '
        r'any hook already created in MinHook’s table. A second '
        r'attach would call HeapCreate again and assign a new heap '
        r'to PRIVATE_HEAP. I found no test for those paths, and they '
        r'are not known to have occurred.'),
    ...pt('//', r'the allocator picks a heap by global state',
        r'dealloc and realloc choose between the process heap, the '
        r'private heap and the trampoline by reading PRIVATE_HEAP at '
        r'the moment of the call, not by knowing where the pointer '
        r'came from. A block allocated in one state and freed in '
        r'another would be handed to the wrong heap. The file does '
        r'not say how it guarantees no block crosses a transition, '
        r'and the gates passing is the evidence that none does in '
        r'practice.'),
    ...pt('//', r'alignment is ignored',
        r'alloc takes layout.size() and drops layout.align(). HeapAlloc '
        r'guarantees 16-byte alignment on x64, so only a type '
        r'aligned more strictly than that could be mis-served. A '
        r'search of every crate in the workspace for repr(align found '
        r'none, but std and the dependencies were not audited.'),
    ...pt('//', r'the real footprint is larger than the private heap',
        r'ring.rs sizes each per-thread ring at 65,536 slots of '
        r'168-byte events, which is 11,010,048 bytes, exactly '
        r'10.5 MiB, and says its backing store comes from '
        r'System directly. In my understanding of std, System on '
        r'Windows is the process heap, so I read that as the '
        r'target’s default heap, allocated under the guard so it '
        r'is never recorded. The design document’s sentence that '
        r'ring buffer storage comes from the private heap does not '
        r'describe that. I have not measured it. For a target with '
        r'48 allocating threads the arithmetic gives about 504 MiB '
        r'of ring.'),
    ...pt('//', r'one parked thread per attach call',
        r'the design says detach leaves "no leftover threads". The '
        r'code accepts one per attach, and attach_and_wait spawns a '
        r'new worker even on the idempotent path, overwriting '
        r'WORKER_TID. Detach does not wake the worker to exit, and '
        r'after the injector’s FreeLibrary the code it is sleeping in '
        r'is unmapped. My reading is that this is harmless as long as '
        r'nothing ever wakes it, and nothing in the file does.'),
    ...pt('//', r'the hook covers three functions',
        r'allocators that do not go through the NT heap, such as '
        r'a runtime that manages its own arenas over VirtualAlloc, '
        r'would be invisible by construction. That is my '
        r'inference from the hook points, not a documented '
        r'finding. The commit messages report clean attaches '
        r'against native Win32, Electron and Node.js targets.'),
    ...pt('//', r'x64 only',
        r'the injector refuses 32-bit targets, and this DLL is a '
        r'single architecture.'),
    ...sec(r'what to take from it'),
    ...pt('//', r'run a control probe',
        r'hooking GetTickCount separated "I am using MinHook '
        r'wrong" from "this function’s prologue is special".'),
    ...pt('//', r'make success prove itself',
        r'the canary checks the thing that matters, a working '
        r'trampoline, not the library’s success code.'),
    ...pt('//', r'a fix that does not fix is data',
        r'force_enter_permanent failing located the fault in the '
        r'return itself.'),
    ...pt('//', r'tests must sit in the gap',
        r'the first gate ran its whole workload on the loading '
        r'thread, which is exactly where the bug was not.'),
    ...pt('//', r'when you cannot make something safe, do less',
        r'return 6, the parked worker and the canary rollback all '
        r'choose a smaller, certain state over a larger, '
        r'uncertain one.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-hook/src/lib.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-hook/src/lib.rs'),
  ],
);
