import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-hook/examples/fls_race_repro.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'fls_race_repro.rs — two hundred threads racing the end of the world'),
    cm('//', r'a targeted attempt to reproduce a hazard the code documents but nobody has seen'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'injection target: many short-lived, unjoined threads, then an immediate hard exit, no detach'),
    kv('language', r'Rust, 51 lines, std only (allocation through std::alloc::System)'),
    kv('size', r'51 lines, one commit: deff3ad (2026-07-26)'),
    kv('driven by', r'hook_owner_free_no_crash.rs::fls_race_exit_without_detach_is_clean'),
    kv('result so far', r'30 of 30 clean runs, 6,000 race attempts, no crash (the test’s module comment)'),
    ...sec(r'the hazard being chased'),
    ...para('//',
        r'heaplens-alloc keeps one ring buffer per producer thread, found through Fiber Local Storage. ring.rs’s doc comment says that, unlike plain TlsAlloc, FLS supports a per-thread exit callback (FlsAlloc’s lpCallback), which is how a dead thread’s ring gets marked dead and later reclaimed. The FLS callback is a function pointer into heaplens_hook.dll.'),
    blank,
    ...para('//',
        r'Here is the hazard. If the process is torn down, and the DLL is unmapped, while some thread is mid-exit and its FLS callback has yet to run, the callback would run code in an address range that no longer exists. ring.rs documents this in its thread_ring::shutdown doc comment, and the test file calls it a "specific, named, still-unconfirmed hazard". It depends on "Windows’ informal (not guaranteed) unmap-vs-FLS-callback ordering". shutdown clears the calling thread’s slot explicitly and calls FlsFree, which are the mitigations; this program is the experiment that asks whether the mitigations are enough, or the theory is wrong.'),
    blank,
    ...code('rust', r'crates/heaplens-hook/examples/fls_race_repro.rs · lines 1-14', r'''
//! Targeted repro for a specific, named, still-unconfirmed hazard in
//! ring.rs's own doc comment: a live FLS registration (its exit callback
//! lives inside heaplens_hook.dll) could in principle fire *after* the DLL
//! is unmapped, if a thread that made a hooked allocation is still mid-exit
//! exactly as the process tears down and Windows' informal (not guaranteed)
//! unmap-vs-FLS-callback ordering doesn't cooperate.
//!
//! Not a general stress test — general concurrent load (see
//! injection_target_concurrent.rs) doesn't target this specific window.
//! This maximizes it directly: spawn many short-lived threads, each
//! registering exactly one fresh FLS slot (one hooked allocation) then
//! exiting immediately, *never joined* by main — so their own natural
//! thread-exit (and FLS callback) races the process's own hard, immediate
//! exit (and DLL unmap) as tightly as possible. No explicit detach.'''),
    ...sec(r'how the program maximises the window'),
    ...para('//',
        r'The comment is clear that this is "not a general stress test". General concurrent load does not target this window. This program aims at it from three directions at once.'),
    blank,
    ...code('rust', r'crates/heaplens-hook/examples/fls_race_repro.rs · lines 19-19, 26-41', r'''
const THREADS_PER_RUN: usize = 200;
...
fn main() {
    println!("TARGET_PID={}", std::process::id());
    let _ = std::io::Write::flush(&mut std::io::stdout());

    // Window for the driving script to attach.
    std::thread::sleep(Duration::from_millis(500));

    for _ in 0..THREADS_PER_RUN {
        // Spawned, never joined -- dropping the JoinHandle detaches it, the
        // thread keeps running independently. That's the point: its exit
        // (and FLS callback) is left to race the process's own teardown.
        std::thread::spawn(|| {
            let p = unsafe { alloc_n(32) };
            std::hint::black_box(p);
        });
    }'''),
    ...pt('//', r'Many threads',
        r'THREADS_PER_RUN is 200, so there are 200 chances per run for a thread to be mid-exit.'),
    ...para('//',
        r'· Each registers exactly one fresh FLS slot. Each thread makes one allocation through System (32 bytes, kept alive with black_box so it is not optimised away), and since that allocation goes through the hooked heap function, it is that first hooked allocation on a brand-new thread that creates the thread’s ring and registers the FLS value with its exit callback. The thread then ends at once, so its callback becomes due almost immediately.'),
    ...para('//',
        r'· Never joined. std::thread::spawn returns a JoinHandle that the loop drops, which detaches the thread; the comment says the thread "keeps running independently". The main thread never waits for any of them.'),
    ...para('//',
        r'The threads do not free their allocation, which is harmless here: the process is about to end, and the point is the FLS registration, not the memory.'),
    blank,
    ...code('rust', r'crates/heaplens-hook/examples/fls_race_repro.rs · lines 43-51', r'''
    println!("SPAWNED {THREADS_PER_RUN} unjoined threads, hard-exiting immediately, no detach");
    let _ = std::io::Write::flush(&mut std::io::stdout());

    // Hard, immediate exit -- skips Rust's normal unwind/cleanup, closer to
    // how real process teardown (ExitProcess) actually happens, maximizing
    // concurrency pressure between the spawned threads' own exits and this
    // process's teardown/DLL-unmap sequence.
    std::process::exit(0);
}'''),
    ...para('//',
        r'Then the main thread prints SPAWNED and calls std::process::exit(0) with nothing in between. The comment explains the choice of a hard exit: it "skips Rust’s normal unwind/cleanup, closer to how real process teardown (ExitProcess) actually happens, maximizing concurrency pressure between the spawned threads’ own exits and this process’s teardown/DLL-unmap sequence". Like the multi-threaded sibling, it starts with TARGET_PID= and a 500 ms sleep as the attach window.'),
    blank,
    ...sec(r'what the test around it concluded'),
    ...para('//',
        r'The test that runs it (fls_race_exit_without_detach_is_clean) attaches the real injector, waits for the SPAWNED marker, and asserts the process exits successfully. The module comment records the result: 30 clean runs of 200 threads each, 6,000 race attempts in all, and "No reproducing evidence for this theoretical gap". That is an absence of evidence. It does not prove the ordering is safe on every Windows build, and the comment never claims it does.'),
    blank,
    ...para('//',
        r'It also records the useful side effect. The same investigation had said that continuous, longer-lived threads (the other example) hung 40 to 60 percent of the time, while these short threads did not hang at all. The rate difference was part of the diagnosis: threads spend very little of their short lives inside capture_stack, so they are rarely caught holding its mutex. The program that was meant to find one bug acted as the control for another.'),
    blank,
    ...sec(r'limits'),
    ...para('//',
        r'· Only one allocation per thread, so a thread has one hooked call and then exits. A thread that is exiting while inside capture_stack (the other bug) is possible but rare here.'),
    ...para('//',
        r'· 200 threads at once is a lot of work for spawn, and some may not even have started when std::process::exit runs. Those never register an FLS slot, so the effective number of attempts per run may be below 200. The "6,000 attempts" is therefore an upper bound on how many races were truly staged.'),
    ...para('//',
        r'· Timing is up to the scheduler. Nothing coordinates the exit with any particular thread state.'),
    ...para('//',
        r'· If the injection arrives after the 500 ms window, the program runs unhooked and passes trivially.'),
    ...sec(r'history'),
    ...para('//',
        r'One commit, deff3ad (2026-07-26). It arrived with the test that drives it, and has not changed.'),
    blank,
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-hook/examples/fls_race_repro.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-hook/examples/fls_race_repro.rs'),
  ],
);
