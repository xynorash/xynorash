import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-hook/examples/exit_without_detach_multithreaded.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'exit_without_detach_multithreaded.rs — eight busy threads and a door that closes on them'),
    cm('//', r'the victim program for the one test that found a real deadlock'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'injection target: eight threads allocating in a loop when the process exits, no detach'),
    kv('language', r'Rust, 72 lines, std only (allocation through std::alloc::System)'),
    kv('size', r'72 lines, one commit: deff3ad (2026-07-26)'),
    kv('driven by', r'hook_owner_free_no_crash.rs::multithreaded_exit_without_detach_is_clean'),
    kv('output protocol', r'TARGET_PID=…, WORKLOAD_RUNNING 8 threads, WORKLOAD_DONE, then an exit line'),
    ...sec(r'what it is'),
    ...para('//',
        r'This is not a test; it is a program that a test runs. It is the target that heaplens-injector attaches to, shaped to recreate one exact situation: a process that has worker threads busily allocating through the hooked heap functions, and then exits without anybody calling detach. The module comment gives the reason it had to be a separate program from owner_freed_while_children_live: that earlier repro was single-threaded, with all allocations on main. "Per guard.rs’s TLS-fix doc comment, the old thread_local! defect specifically crashed any thread other than the one that called LoadLibraryW — a target’s own worker threads are exactly that population, and a single-threaded repro can’t exercise it."'),
    blank,
    ...code('rust', r'crates/heaplens-hook/examples/exit_without_detach_multithreaded.rs · lines 1-13', r'''
//! Multi-threaded companion to `owner_freed_while_children_live.rs` for the
//! `hook_owner_free_no_crash.rs` exit-without-detach regression coverage.
//!
//! The original investigation's repro was single-threaded (all allocations
//! on `main`). Per `guard.rs`'s TLS-fix doc comment, the old `thread_local!`
//! defect specifically crashed *any thread other than the one that called
//! `LoadLibraryW`* — a target's own worker threads are exactly that
//! population, and a single-threaded repro can't exercise it. This target
//! closes that gap: several worker threads, each continuously making
//! hooked allocations, still running when the process exits without an
//! explicit detach. Short duration (seconds, not minutes) — this is
//! regression-test coverage, not a long-duration soak
//! (`injection_target_concurrent.rs` already covers that separately).'''),
    ...para('//',
        r'The comment also says what it is not: "regression-test coverage, not a long-duration soak", with another example (injection_target_concurrent.rs, though no file of that name is in the examples directory) mentioned as the soak. Short on purpose: seconds, not minutes.'),
    blank,
    ...sec(r'the script it follows'),
    ...code('rust', r'crates/heaplens-hook/examples/exit_without_detach_multithreaded.rs · lines 20-21, 33-38', r'''
const THREAD_COUNT: usize = 8;
const RUN_MILLIS: u64 = 1500;
...
fn main() {
    println!("TARGET_PID={}", std::process::id());
    let _ = std::io::Write::flush(&mut std::io::stdout());

    // Window for the driving script to attach.
    std::thread::sleep(Duration::from_millis(500));'''),
    ...para('//',
        r'main prints its own process id first, flushed, so the driving test can read TARGET_PID= from the pipe and give it to the injector. Then it sleeps 500 ms: a "window for the driving script to attach". The test has to run the injector and get the DLL in within that half second. That is a timing contract with no handshake.'),
    blank,
    ...code('rust', r'crates/heaplens-hook/examples/exit_without_detach_multithreaded.rs · lines 40-55', r'''
    let stop = Arc::new(AtomicBool::new(false));
    let mut handles = Vec::with_capacity(THREAD_COUNT);
    for _ in 0..THREAD_COUNT {
        let stop = Arc::clone(&stop);
        handles.push(std::thread::spawn(move || {
            while !stop.load(Ordering::Relaxed) {
                let p = unsafe { alloc_n(64) };
                unsafe { free_n(p, 64) };
            }
        }));
    }

    println!("WORKLOAD_RUNNING {THREAD_COUNT} threads");
    let _ = std::io::Write::flush(&mut std::io::stdout());

    std::thread::sleep(Duration::from_millis(RUN_MILLIS));'''),
    ...para('//',
        r'Eight threads are spawned. Each runs while a stop flag is false, which is never set: it allocates 64 bytes with System.alloc and frees them at once, forever. These allocations go through the plain Windows heap (HeapAlloc and friends via System), the very calls the hook intercepts, so each loop turn is one hooked alloc and one hooked free, on a thread that did not load the DLL.'),
    blank,
    ...para('//',
        r'The main thread then prints WORKLOAD_RUNNING and sleeps for 1.5 seconds (RUN_MILLIS) while the workers hammer the hook. Over that time the hook’s capture_stack path, with its process-wide mutex, is entered continuously from eight threads.'),
    blank,
    ...code('rust', r'crates/heaplens-hook/examples/exit_without_detach_multithreaded.rs · lines 57-72', r'''
    // Deliberately do NOT stop/join the worker threads and do NOT call
    // detach — the point is to exit with worker threads still actively
    // making hooked allocations, exactly the scenario this regression test
    // exists to cover. `stop` is never set; the threads are abandoned when
    // the process exits.
    println!("WORKLOAD_DONE");
    let _ = std::io::Write::flush(&mut std::io::stdout());

    // Small window for the driving script to observe WORKLOAD_DONE before
    // this process exits on its own (no detach) — mirrors
    // owner_freed_while_children_live.rs's structure.
    std::thread::sleep(Duration::from_millis(200));

    println!("exit_without_detach_multithreaded: exiting now, no detach, {THREAD_COUNT} threads still live");
    let _ = std::io::Write::flush(&mut std::io::stdout());
}'''),
    ...para('//',
        r'The ending is the whole point. The comment says: "Deliberately do NOT stop/join the worker threads and do NOT call detach — the point is to exit with worker threads still actively making hooked allocations". stop is never set; the threads are abandoned. After printing WORKLOAD_DONE and waiting 200 ms for the driver to read it, main prints a last line and returns, which runs the C runtime’s exit path, ExitProcess, with the workers mid-allocation.'),
    blank,
    ...sec(r'why a tight loop on eight threads'),
    ...para('//',
        r'The hang this program exposed depends on a thread being killed while it holds a lock. The hook’s capture_stack takes a global mutex (DBGHELP_LOCK) for each captured allocation. A thread that is inside capture_stack for a large fraction of its life is very likely to be there when ExitProcess terminates it. That is why the test file’s analysis can say the hang rate here (40 to 60 percent of runs before the fix, 9 of 10 and 7 of 8 in later batches) is higher than for the short-lived threads of fls_race_repro: the loops here spend nearly all their time in the hook, and the short threads there spend almost none.'),
    blank,
    ...para('//',
        r'Eight is simply a constant (THREAD_COUNT); the file gives no derivation for it.'),
    blank,
    ...sec(r'what happened with it'),
    ...para('//',
        r'Before the fix, running this under injection hung roughly half the time, in a way that resisted normal process termination (see hook_owner_free_no_crash.rs for the stack trace and the Win32_Process.Terminate detail). The fix, in heaplens-alloc/src/capture.rs, replaced a blocking lock with try_lock. With it, the driving test passes, and the module comment records 25 manual runs clean against 9 of 10 and 7 of 8 hung before.'),
    blank,
    ...sec(r'design notes and limits'),
    ...para('//',
        r'· No cleanup is the feature. A program that joined its workers would be a different, safe program. The unjoined, unstopped threads are exactly the scenario.'),
    ...para('//',
        r'· The workers allocate and free the same size in lockstep, so the heap does not grow. The target runs for about 2.2 seconds in total whatever happens (500 ms + 1500 ms + 200 ms).'),
    ...pt('//', r'The program has no pipe or daemon logic. The DLL’s writer thread has no one to connect to in the test, and the hang does not need one',
        r'the deadlock is in the capture path, before anything is sent.'),
    ...para('//',
        r'· stdout is flushed explicitly after every marker, so the driver, which reads the markers through a pipe, sees them promptly.'),
    ...para('//',
        r'· The program does not know whether the hook is active. If attach arrives late, the workload runs unhooked and exits cleanly, and the test passes without testing anything.'),
    ...sec(r'history'),
    ...para('//',
        r'One commit, deff3ad (2026-07-26): "re-verify exit-without-detach crash, find new hang defect". The file arrived with the test that uses it and has not changed.'),
    blank,
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-hook/examples/exit_without_detach_multithreaded.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-hook/examples/exit_without_detach_multithreaded.rs'),
  ],
);
