import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-hook/examples/self_load_spawned_thread.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'self_load_spawned_thread.rs — the regression test for a bug that needed one thread to the side'),
    cm('//', r'the whole workload runs on a spawned thread, because the bug lived everywhere except the thread that loaded the DLL'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'self-load target that does all its allocation on a spawned thread'),
    kv('language', r'Rust, std plus windows-sys (LoadLibraryW, GetProcAddress)'),
    kv('size', r'102 lines'),
    kv('history', r'one commit, dcc76f2 (2026-07-21 23:12 +0300), the fix it guards'),
    kv('driven by', r'crates/heaplens-daemon/tests/hook_self_load_spawned_thread.rs'),
    kv('script', r'20 allocations and 20 frees on one spawned thread, attach and detach on main'),
    ...sec(r'the evening this file was written for'),
    ...para('//',
        r'On 2026-07-21 the hook DLL had been running against real '
        r'programs. A process called jetbrainsd.exe had crashed with an '
        r'access violation recorded "directly inside heaplens_hook.dll", '
        r'minutes before a Windows kernel bugcheck, DPC_WATCHDOG_VIOLATION, '
        r'on the same machine. The repository records those two events '
        r'side by side and does not claim that one caused the other. It '
        r'does record what the project did next, to the minute:'),
    ...pt('//', r'22:14',
        r'commit 8b0f962 adds the multi-threaded stress harness, '
        r'self_load_concurrency_stress.rs, which crashes reliably with the '
        r'hook on and runs cleanly with it off.'),
    ...pt('//', r'22:21',
        r'commit 823dac7 turns the Attach button off in the interface, '
        r'seven minutes later, with a tooltip that explains why.'),
    ...pt('//', r'23:12',
        r'commit dcc76f2 fixes the crash, and adds this file and a daemon '
        r'test for it. Fifty-eight minutes after the harness.'),
    blank,
    ...para('//',
        r'This file is the part of the fix that stays. The harness at '
        r'22:14 is a diagnostic: forty-eight threads, eight seconds, '
        r'tail latencies. What was needed after the fix was something '
        r'small, fast and deterministic that a test run could keep '
        r'forever. The header of this file says that is its job:'),
    ...code('rust', 'crates/heaplens-hook/examples/self_load_spawned_thread.rs · the header', r'''
//! Regression test for the 2026-07-21 root-cause investigation
//! (`self_load_concurrency_stress.rs`'s finding): every allocation in this
//! harness's scripted workload happens on a **spawned** thread, never the
//! main thread — the main thread only attaches, spawns, joins, and
//! detaches. `self_load_harness.rs` (the original Step 1 acceptance gate)
//! never exercised this: its entire scripted workload runs on the process's
//! main thread, the same thread that calls `LoadLibraryW`. That gap is
//! exactly why the bug this file guards against was never caught until a
//! dedicated concurrency stress harness went looking for it — see
//! `guard.rs`/`ring.rs`'s doc comments for the confirmed mechanism
//! (`thread_local!`/plain `FlsAlloc` usage unsafe from any thread other
//! than the one that loaded this DLL) and the fix (raw `TlsAlloc` for the
//! reentrancy guard, `FlsAlloc` with an explicit pre-unload `shutdown` for
//! the ring registry).
//!
//! Deliberately small and fast (a handful of operations, not a multi-second
//! stress run) — this is the *targeted*, deterministic regression test for
//! the specific mechanism; `self_load_concurrency_stress.rs` remains the
//! broader stress/repro tool for the same underlying class of bug.'''),
    ...para('//',
        r'The last paragraph is the design statement. "Deliberately small '
        r'and fast (a handful of operations, not a multi-second stress '
        r'run)", "the targeted, deterministic regression test for the '
        r'specific mechanism". The stress harness remains as "the '
        r'broader stress/repro tool for the same underlying class of '
        r'bug". Two tools, two jobs: one finds, one pins.'),
    ...sec(r'the bug, in the words of the code it was found in'),
    ...para('//',
        r'The hook is a DLL that is always loaded at run time, through '
        r'LoadLibraryW, never linked into a process at startup. The '
        r'reentrancy guard in heaplens-alloc, the flag that stops '
        r'the capture code from capturing its own allocations, was a '
        r'thread_local!. On this platform that can compile to a fast, '
        r'direct access to a per-thread slot, and the slot is only '
        r'wired up for every thread if the loader knew about the module '
        r'at process start. Here is the account in the guard’s own '
        r'documentation:'),
    ...code('rust', 'crates/heaplens-alloc/src/guard.rs · the root cause (trimmed)', r'''
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
//! segfaulted here.
...
//! An initial attempt to fix this by giving the thread-local's value type
//! a `Drop` impl (hoping to force rustc onto its other, non-`.tls`-section
//! implementation) did **not** resolve the crash — confirmed by rerunning
//! the identical isolated reduction and observing the same segfault. Do
//! not reintroduce that approach without re-verifying it against the
//! harness first; whatever rustc chooses for a `Drop`-having thread-local
//! on this target, it wasn't clean of the same hazard.'''),
    ...para('//',
        r'Two things in that account are worth pausing on.'),
    ...pt('//', r'the reduction',
        r'the commit message for dcc76f2 describes how it was isolated: '
        r'"Reduced record() down to a single line at a time until the '
        r'crash isolated to guard::is_set() alone: a single allocation '
        r'on the thread that called LoadLibraryW always succeeds; the '
        r'identical single allocation on any other thread — including '
        r'one spawned well after attach completes — segfaults on its '
        r'first access, every run." That sentence is also this file’s '
        r'specification. A thread that is not the loader makes one '
        r'hooked allocation and the process dies.'),
    ...pt('//', r'the dead end',
        r'the first fix tried was to give the thread-local’s value type '
        r'a Drop implementation, in the hope that it would make rustc pick '
        r'its other implementation. It did not. The message says so, the '
        r'guard’s comment says so, and it adds an instruction: "Do not '
        r'reintroduce that approach without re-verifying it against the '
        r'harness first". A second structure, the per-thread ring '
        r'registration in ring.rs, had a real Drop impl all along and '
        r'crashed in the same way once the first was fixed, which is how '
        r'the commit concludes that Drop-ness "was never the deciding '
        r'factor".'),
    blank,
    ...para('//',
        r'The cure was to leave thread_local! entirely: raw TlsAlloc, '
        r'TlsGetValue and TlsSetValue for the guard, and raw FlsAlloc for '
        r'the ring registration. Both are slot-index schemes with no '
        r'dependence on module linkage. The pages for guard.rs and '
        r'ring.rs in heaplens-alloc tell that half. What matters here is '
        r'how the fix was made to stay fixed.'),
    ...sec(r'the program'),
    ...code('rust', 'crates/heaplens-hook/examples/self_load_spawned_thread.rs · main', r'''
fn main() {
    let path = dll_path();
    let wpath = to_wide(path.to_str().expect("dll path is valid UTF-8"));

    let hmodule = unsafe { LoadLibraryW(wpath.as_ptr()) };
    assert!(!hmodule.is_null(), "LoadLibraryW failed for {path:?}");

    let attach: AttachFn = unsafe {
        let proc = GetProcAddress(hmodule, b"HeapLensHookAttach\0".as_ptr());
        std::mem::transmute(proc.expect("GetProcAddress(HeapLensHookAttach) failed"))
    };
    let detach: DetachFn = unsafe {
        let proc = GetProcAddress(hmodule, b"HeapLensHookDetach\0".as_ptr());
        std::mem::transmute(proc.expect("GetProcAddress(HeapLensHookDetach) failed"))
    };

    // Attach happens on the main thread — same as every other self-load
    // harness. The point of divergence from self_load_harness.rs is next.
    let rc = unsafe { attach() };
    assert_eq!(rc, 0, "HeapLensHookAttach failed with code {rc}");
    std::thread::sleep(std::time::Duration::from_millis(300));

    // The entire scripted workload runs on a SPAWNED thread — this is the
    // exact shape that crashed reliably before the fix (confirmed via
    // reduction down to a single allocation on a single spawned thread).
    let worker = std::thread::spawn(|| {
        let mut ptrs: [*mut u8; ALLOC_COUNT] = [std::ptr::null_mut(); ALLOC_COUNT];
        let mut sizes: [usize; ALLOC_COUNT] = [0; ALLOC_COUNT];
        for i in 0..ALLOC_COUNT {
            let size = SIZES[i % SIZES.len()];
            ptrs[i] = unsafe { alloc_n(size) };
            sizes[i] = size;
            println!("ALLOC ptr={:?} size={size}", ptrs[i]);
        }
        for i in 0..ALLOC_COUNT {
            unsafe { free_n(ptrs[i], sizes[i]) };
            println!("FREE ptr={:?}", ptrs[i]);
        }
    });
    worker.join().expect("spawned workload thread panicked");

    std::thread::sleep(std::time::Duration::from_millis(300));

    let rc = unsafe { detach() };
    assert_eq!(rc, 0, "HeapLensHookDetach failed with code {rc}");

    std::thread::sleep(std::time::Duration::from_millis(300));

    println!("self_load_spawned_thread: done");
}'''),
    ...para('//',
        r'The main thread does four things and allocates nothing the '
        r'script knows about: load the DLL and look up the two exports '
        r'(the same pattern as self_load_harness.rs), attach, start a '
        r'worker, wait for it, detach. The comment on the attach call '
        r'is the whole point of the file: "Attach happens on the main '
        r'thread — same as every other self-load harness. The point of '
        r'divergence from self_load_harness.rs is next." What comes next '
        r'is the worker, and the comment above it:'),
    ...pt('//', r'the workload runs on the spawned thread',
        r'"this is the exact shape that crashed reliably before the fix '
        r'(confirmed via reduction down to a single allocation on a '
        r'single spawned thread)".'),
    ...pt('//', r'the script is smaller than the Step 1 script',
        r'20 allocations of sizes cycling through 32, 64, 128 and 256, '
        r'then 20 frees. No reallocations, no pre-attach pointer, no '
        r'post-detach burst. Those are the Step 1 harness’s concerns and '
        r'they are already covered there. This file isolates one '
        r'variable: which thread.'),
    ...pt('//', r'the thread is joined before detach',
        r'worker.join() returns after the worker has exited. Its exit, '
        r'with the thread’s per-thread cleanup and the fiber-local '
        r'callback that marks its ring as dead, therefore happens while the '
        r'hooks are still installed, which is a state the original gate '
        r'never reached on any thread but main.'),
    blank,
    ...para('//',
        r'The sleeps are the same kind of timing assumption as in the '
        r'Step 1 harness: 300 ms for the writer thread to connect, 300 '
        r'ms after the join for the batch to flush, and 300 ms after '
        r'detach before printing "self_load_spawned_thread: done". '
        r'The last one is not decoration. dcc76f2 found a second, '
        r'separate crash once the first was gone: a stale '
        r'fiber-local registration, set on the main thread by the '
        r'hooked allocations inside its own println! calls, whose '
        r'callback lives in the DLL, could fire after the DLL was '
        r'unmapped at process exit, "strictly after a full clean '
        r'attach/workload/detach cycle". The cure was an explicit '
        r'shutdown_ring_storage() inside detach. The shape of this '
        r'program, println! calls on the main thread while the hooks '
        r'are live, followed by detach, followed by an orderly exit, '
        r'is the shape in which that second crash happens, so the file '
        r'covers it as well, though its header does not claim to.'),
    ...sec(r'the test that drives it'),
    ...para('//',
        r'The daemon crate carries the other half, '
        r'crates/heaplens-daemon/tests/hook_self_load_spawned_thread.rs, '
        r'which runs this program as a child against a real named-pipe '
        r'server, parses its ALLOC and FREE lines, and asserts three '
        r'things by pointer identity: all 20 allocations arrived, none '
        r'with a wrong size, and all 20 frees arrived. The constant it '
        r'uses is annotated "Must match crates/heaplens-hook/examples/'
        r'self_load_spawned_thread.rs exactly", a contract kept by a '
        r'comment, not by the compiler.'),
    blank,
    ...para('//',
        r'The test carries a lesson of its own, learned five days after '
        r'it was written. On 2026-07-26 it started to flake. Commit '
        r'084ddf9 explains: the scripted program prints after each '
        r'operation, those prints allocate through the same hook, and '
        r'the heap may reuse an address for an incidental short-lived '
        r'allocation before handing it out for a scripted one. The '
        r'investigation found a concrete case. Address 0x27ff25f61f0 '
        r'was allocated at size 30 and freed by stdout’s buffering, and '
        r'only then allocated at size 32 by the script, in that order, '
        r'with both events captured correctly. The test had compared the '
        r'first event it saw for each pointer, and so reported a size '
        r'mismatch that did not exist.'),
    ...code('rust', 'crates/heaplens-daemon/tests/hook_self_load_spawned_thread.rs · the fix', r'''
fn find_alloc_size_mismatches(
    events: &[heaplens_protocol::AllocEvent],
    expected: &std::collections::HashMap<u64, u64>,
) -> Vec<(u64, u64, u64)> {
    let mut last_alloc_size: std::collections::HashMap<u64, u64> = std::collections::HashMap::new();
    for ev in events {
        if ev.kind == 0 && expected.contains_key(&ev.ptr) {
            last_alloc_size.insert(ev.ptr, ev.size);
        }
    }
    let mut mismatches: Vec<(u64, u64, u64)> = expected
        .iter()
        .filter_map(|(&ptr, &expected_size)| {
            let actual = *last_alloc_size.get(&ptr)?;
            (actual != expected_size).then_some((ptr, expected_size, actual))
        })
        .collect();
    mismatches.sort();
    mismatches
}'''),
    ...para('//',
        r'The function now keeps the last Alloc event for each scripted '
        r'pointer, because the last one is the allocation still live '
        r'when the matching free arrives. The commit extracted it so it '
        r'could be unit-tested without a process, and added five tests '
        r'for it, including one that reproduces the confirmed scenario. '
        r'Their names read as a specification: a single alloc with the '
        r'expected size has no mismatch; a single alloc with the wrong '
        r'size is a real mismatch; an address reused by an incidental '
        r'alloc before the real one is not a mismatch; a pointer never '
        r'allocated is absent, not a mismatch; events for untracked '
        r'pointers are ignored. The commit also reports 15 consecutive '
        r'clean reruns of the integration test, and says it had failed '
        r'within its first attempt once diagnostics were switched on, so '
        r'the fix was verified against a flake that could be made to '
        r'fail on demand.'),
    ...sec(r'what this file proves and what it does not'),
    ...pt('//', r'proves',
        r'a thread that did not load the DLL can allocate under the '
        r'hook without crashing, that those events reach the daemon '
        r'with the right pointers and sizes, and that a worker thread '
        r'can exit while the hooks are live.'),
    ...pt('//', r'does not prove: contention',
        r'one worker thread is not the 48 of the stress harness, and a '
        r'race that needs two threads to collide would pass here. That '
        r'is the stress harness’s job, and the two files are kept for '
        r'that reason.'),
    ...pt('//', r'does not prove: exit without detach',
        r'this program detaches before it ends. The exit-without-detach '
        r'targets, written five days later, cover the other order.'),
    ...pt('//', r'does not prove: cross-process behaviour',
        r'like the Step 1 harness it loads the DLL into itself; the '
        r'remote-thread path is injection_target.rs’s territory.'),
    ...sec(r'what to take from it'),
    ...pt('//', r'when a bug hid from your gate, add a gate',
        r'do not rewrite the old one. The Step 1 harness stayed as it was '
        r'and a sibling was added for the missing dimension.'),
    ...pt('//', r'write down the dead end beside the fix',
        r'the guard’s comment tells the next engineer which approach '
        r'was tried and failed, and how to re-test it. A dead end '
        r'recorded costs a paragraph; the same dead end retried costs an '
        r'evening.'),
    ...pt('//', r'a test that flakes is a finding, not noise',
        r'084ddf9 turned a flaky assertion into a unit-tested function '
        r'and a recorded mechanism.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-hook/examples/self_load_spawned_thread.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-hook/examples/self_load_spawned_thread.rs'),
  ],
);
