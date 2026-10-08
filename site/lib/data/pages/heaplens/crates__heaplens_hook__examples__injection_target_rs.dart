import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-hook/examples/injection_target.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'injection_target.rs — the program that waits to be injected'),
    cm('//', r'the Step 2 target: Step 1’s script, run by a stranger, with windows of time for the injector to act in'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'plain target process for cross-process injection tests'),
    kv('language', r'Rust, std only; links neither heaplens-hook nor heaplens-alloc'),
    kv('size', r'97 lines'),
    kv('history', r'one commit here, 724695a (2026-07-19), ported from feat/stage7-injection'),
    kv('protocol', r'TARGET_PID, ALLOC, REALLOC, REALLOC_UNTRACKED, FREE, WORKLOAD_DONE, POST_DETACH_*'),
    kv('timeline', r'800 ms attach window, script, 300 ms, 2000 ms detach window, post-detach script'),
    kv('driver', r'not in the repository'),
    ...sec(r'where this sits in the plan'),
    ...para('//',
        r'The design document builds Stage 7 in steps, and each step '
        r'has a gate that must pass before the next begins. Step 1 '
        r'proved the hook DLL in isolation, loaded by a program into '
        r'itself (self_load_harness.rs). Step 2 introduces the '
        r'injector, and its gate, in the document’s words, is to take '
        r'"the Step 1 test harness as a plain, unmodified, already-running '
        r'process (no self-attach code path used this time)", have '
        r'heaplens-injector attach to it from outside, and "Confirm '
        r'identical results to Step 1’s gate (event capture correct, '
        r'clean detach) but now via real cross-process injection".'),
    blank,
    ...para('//',
        r'This file is what became of "the Step 1 test harness" in that '
        r'sentence. It is not literally unmodified: the self-load code '
        r'is gone, since nothing in this process ever loads the DLL, and '
        r'synchronisation points have been added so that a separate '
        r'process can act at the right moments. The workload is the same '
        r'shape as Step 1’s, and the header says so. Its first lines '
        r'state the constraints that make the test mean something:'),
    ...code('rust', 'crates/heaplens-hook/examples/injection_target.rs · the header', r'''
//! Stage 7 Step 2 acceptance-gate target (docs/stage7-injection-design.md
//! §8, Step 2). A plain, separate process — built with debug info (dev
//! profile default), no dependency on `heaplens-hook` or `heaplens-alloc`
//! — that an external `heaplens-injector` process attaches to via real
//! `CreateRemoteThread`/`LoadLibraryW` injection. This is the first real
//! cross-process test: Step 1 proved the capture pipeline in isolation via
//! self-load; this proves the injector actually gets a hook DLL into
//! *another* process and that capture still works from there.
//!
//! Prints synchronization markers to stdout so the driving test can inject
//! and detach at the right points without guessing timing, plus the same
//! per-operation ALLOC/REALLOC/FREE/POST_DETACH_* markers Step 1's harness
//! uses, for the same pointer-identity-matching reason (see
//! self_load_harness.rs's module doc).'''),
    ...para('//',
        r'"A plain, separate process", "no dependency on heaplens-hook '
        r'or heaplens-alloc", "built with debug info (dev profile '
        r'default)". Each phrase removes a way for the test to pass '
        r'for the wrong reason. A process that linked the cooperative '
        r'allocator could send events by itself. A process that '
        r'loaded the DLL itself would not need the injector. And debug '
        r'info matters because the daemon’s ownership inference reads '
        r'symbol names from the captured stacks, so a target without '
        r'symbols would make a missing ownership edge ambiguous between '
        r'"injection is broken" and "there is nothing to resolve". The '
        r'design makes this separation its Step 6 rule, and this file '
        r'follows it early: "This is the first real cross-process '
        r'test".'),
    ...sec(r'a conversation conducted over stdout'),
    ...para('//',
        r'The injector and the target are two processes that cannot see '
        r'each other’s state, so the target narrates. The header says '
        r'it "prints synchronization markers to stdout so the driving '
        r'test can inject and detach at the right points without guessing '
        r'timing". There are two kinds of line.'),
    ...pt('//', r'synchronisation markers',
        r'TARGET_PID=<n> at the start, so the driver learns whom to '
        r'attach to without a process search, and WORKLOAD_DONE once the '
        r'scripted burst is finished.'),
    ...pt('//', r'one line per operation',
        r'ALLOC ptr=... size=..., REALLOC old=... new=... size=..., '
        r'REALLOC_UNTRACKED, FREE ptr=..., and after detach '
        r'POST_DETACH_ALLOC and POST_DETACH_FREE. These are identical in '
        r'form to the Step 1 harness’s lines, "for the same '
        r'pointer-identity-matching reason", so that a daemon-side test '
        r'can use the same parser and the same matching logic.'),
    blank,
    ...para('//',
        r'The first line is the more durable idea. TARGET_PID was '
        r'introduced here and then reused. The three targets written '
        r'a week later for the exit-without-detach investigation '
        r'(owner_freed_while_children_live.rs, '
        r'exit_without_detach_multithreaded.rs, fls_race_repro.rs) all '
        r'begin with the same line, and owner_freed says so in its '
        r'header: "mirroring injection_target.rs’s structure '
        r'(TARGET_PID marker, sleep windows for the driving script to '
        r'attach/detach)". The helper in the daemon’s test crate that '
        r'drives those three is the clearest picture of how the '
        r'convention is used:'),
    ...code('rust', 'crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs · reading the marker and attaching', r'''
    let mut target = std::process::Command::new(&target_exe)
        .current_dir(work_dir)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .unwrap_or_else(|e| panic!("failed to spawn {target_name}.exe: {e}"));

    let stdout = target.stdout.take().unwrap();
    let mut reader = BufReader::new(stdout);

    let pid_lines = read_until_marker(&mut reader, "TARGET_PID=", Duration::from_secs(5));
    let pid_line = pid_lines
        .iter()
        .find(|l| l.starts_with("TARGET_PID="))
        .expect("target never printed TARGET_PID");
    let pid: u32 = pid_line.trim_start_matches("TARGET_PID=").parse().unwrap();

    let attach_output = std::process::Command::new(&injector_exe)
        .arg(pid.to_string())
        .arg("--attach")
        .output()
        .expect("failed to spawn heaplens-injector --attach");
    assert!(
        attach_output.status.success(),
        "attach failed: stdout={} stderr={}",
        String::from_utf8_lossy(&attach_output.stdout),
        String::from_utf8_lossy(&attach_output.stderr)
    );

    (target, reader, pid)'''),
    ...para('//',
        r'The driver spawns the target with stdout piped, reads lines '
        r'until one starts with "TARGET_PID=" (bounded at five seconds), '
        r'parses the number, and immediately runs the injector. It does '
        r'not wait for anything else. The attach therefore races the '
        r'target’s first sleep, and that sleep is the target’s side '
        r'of the agreement.'),
    ...sec(r'the windows'),
    ...code('rust', 'crates/heaplens-hook/examples/injection_target.rs · the start and the pre-attach pointer', r'''
fn main() {
    println!("TARGET_PID={}", std::process::id());
    let _ = std::io::Write::flush(&mut std::io::stdout());

    // Window for the driving test to spawn `heaplens-injector --attach`.
    std::thread::sleep(std::time::Duration::from_millis(800));

    let mut pre_attach_ptr = unsafe { alloc_n(96) };'''),
    ...para('//',
        r'The first window is 800 ms: "Window for the driving test to '
        r'spawn heaplens-injector --attach". The injector’s own work, '
        r'a safety check, an architecture probe, a remote LoadLibraryW, '
        r'a module-list read and a remote call of the attach export, all '
        r'has to finish inside that time for the whole script to be '
        r'captured. The comment above the script is candid about it: '
        r'"captured, if attach landed in time". The window is a '
        r'timing assumption, and a slow machine can lose the race. '
        r'A lost race shows up as missing events, which the daemon-side '
        r'count would report.'),
    ...code('rust', 'crates/heaplens-hook/examples/injection_target.rs · the script', r'''
    // ── Scripted, precisely-countable workload (captured, if attach landed
    // in time — same shape as self_load_harness.rs) ─────────────────────
    let mut ptrs: [*mut u8; ALLOC_COUNT] = [std::ptr::null_mut(); ALLOC_COUNT];
    let mut sizes: [usize; ALLOC_COUNT] = [0; ALLOC_COUNT];
    for i in 0..ALLOC_COUNT {
        let size = SIZES[i % SIZES.len()];
        ptrs[i] = unsafe { alloc_n(size) };
        sizes[i] = size;
        println!("ALLOC ptr={:?} size={size}", ptrs[i]);
    }

    for (i, sizes_i) in sizes.iter_mut().enumerate().take(REALLOC_COUNT) {
        let old_ptr = ptrs[i];
        let new_size = *sizes_i * 2;
        ptrs[i] = unsafe { realloc_n(ptrs[i], *sizes_i, new_size) };
        *sizes_i = new_size;
        println!("REALLOC old={old_ptr:?} new={:?} size={new_size}", ptrs[i]);
    }

    let untracked_old = pre_attach_ptr;
    pre_attach_ptr = unsafe { realloc_n(pre_attach_ptr, 96, 192) };
    println!("REALLOC_UNTRACKED old={untracked_old:?} new={pre_attach_ptr:?} size=192");

    for i in 0..ALLOC_COUNT {
        unsafe { free_n(ptrs[i], sizes[i]) };
        println!("FREE ptr={:?}", ptrs[i]);
    }
    unsafe { free_n(pre_attach_ptr, 192) };
    println!("FREE ptr={pre_attach_ptr:?}");'''),
    ...para('//',
        r'The script is Step 1’s. Fifty allocations with sizes cycling '
        r'through 32, 64, 128 and 256. Ten reallocations that double '
        r'the size of the first ten pointers. A reallocation of the '
        r'96-byte block, printed with the marker REALLOC_UNTRACKED. Then '
        r'fifty-one frees. In total, 50 + 11 + 51 = 112 heap events the '
        r'daemon should be able to match by pointer.'),
    blank,
    ...para('//',
        r'There is a subtlety here, and it is a difference from the '
        r'self-load harness that the names hide. In self_load_harness.rs '
        r'the 96-byte block is allocated before LoadLibraryW, so it is '
        r'certainly unknown to the hook, and its later reallocation '
        r'really does exercise the unknown-pointer path through the '
        r'daemon’s on_realloc. In this file the block is allocated '
        r'after the 800 ms sleep, which is the window in which the '
        r'attach is supposed to happen. If the attach lands in time, '
        r'this allocation is captured like any other, and the '
        r'"untracked" reallocation is an ordinary tracked one. It is '
        r'untracked only if the attach is later than 800 ms, in '
        r'which case so are the other fifty allocations. I read this '
        r'as the fallback path not being covered by this file; the '
        r'driver that would have checked is not in the repository, so '
        r'I cannot say what it asserted. The unknown-pointer behaviour is '
        r'still pinned by the self-load gate, which does create the '
        r'condition.'),
    ...code('rust', 'crates/heaplens-hook/examples/injection_target.rs · done, the detach window, and the silent burst', r'''
    // Flush window before signaling the driving test to detach.
    std::thread::sleep(std::time::Duration::from_millis(300));
    println!("WORKLOAD_DONE");
    let _ = std::io::Write::flush(&mut std::io::stdout());

    // Window for the driving test to spawn `heaplens-injector --detach`.
    std::thread::sleep(std::time::Duration::from_millis(2000));

    // ── Post-detach workload — must produce zero captured events ────────
    let mut post_ptrs: [*mut u8; 5] = [std::ptr::null_mut(); 5];
    for p in post_ptrs.iter_mut() {
        *p = unsafe { alloc_n(64) };
        println!("POST_DETACH_ALLOC ptr={p:?} size=64");
    }
    for p in post_ptrs {
        unsafe { free_n(p, 64) };
        println!("POST_DETACH_FREE ptr={p:?}");
    }

    std::thread::sleep(std::time::Duration::from_millis(300));
    println!("injection_target: done");
}'''),
    ...para('//',
        r'The second window is 2000 ms after WORKLOAD_DONE: "Window for '
        r'the driving test to spawn heaplens-injector --detach". The '
        r'post-detach burst, five allocations and frees of 64 bytes with '
        r'their own markers, runs when the window closes whether or not '
        r'a detach has finished. The design requires its result to be '
        r'zero events, "not fewer or looks quiet". That requirement has '
        r'a timing dependence the file does not hide: the burst can '
        r'prove that hooks are gone only if detach completes inside '
        r'the window. The injector itself allows up to 5 seconds for '
        r'the detach result and the hook up to 2 seconds for its writer '
        r'thread to stop. A healthy detach takes milliseconds and the '
        r'window is generous, but the window is shorter than the '
        r'worst case the tools were written to tolerate. A hung detach '
        r'would show up as post-detach events, a false reading of '
        r'"hooks not removed" rather than "detach slow". That is my '
        r'reading of the constants, not a documented incident.'),
    blank,
    ...para('//',
        r'The file ends with a 300 ms sleep so the daemon can receive '
        r'the final batch, then prints "injection_target: done". All '
        r'in, the program lives for about 3.4 seconds plus the time the '
        r'script itself takes, which is small.'),
    ...sec(r'what the driver was, and wasn’t'),
    ...para('//',
        r'The header refers to "the driving test". I searched the '
        r'repository for any reference to injection_target, in Rust, '
        r'Markdown, TOML and Dart, and found none outside this file '
        r'and the comment in owner_freed_while_children_live.rs. No '
        r'test spawns it. No script does either. The Step 2 gate was run, '
        r'by the evidence of the commit that ported it: 724695a reports '
        r'"live end-to-end — process picker populates, real '
        r'attach/detach against a live process (Discord) confirmed via '
        r'daemon log". And 864167e reports validation against three '
        r'architecturally different real targets and a soak of about '
        r'2 hours 10 minutes against a Node.js process. What I cannot '
        r'point to is a committed, repeatable automation of this '
        r'target. The automation that exists grew up around its '
        r'descendants, in hook_owner_free_no_crash.rs, which is where '
        r'the TARGET_PID helper above lives. Two of those descendants '
        r'also point to a file called injection_target_concurrent.rs, '
        r'which exit_without_detach_multithreaded.rs calls the '
        r'long-duration soak. No such file is in the repository, so the '
        r'name is a dangling reference.'),
    blank,
    ...para('//',
        r'The daemon’s own hook test for Step 1, hook_self_load_wire.rs, '
        r'is the model that a Step 2 test would follow almost line for '
        r'line: spawn the target, parse the markers, replay the raw '
        r'events into a graph, match by pointer identity, and check '
        r'that the post-detach pointers never appear after the last '
        r'scripted event. This file already prints exactly what that '
        r'test consumes.'),
    ...sec(r'limits'),
    ...pt('//', r'timing is fixed',
        r'800 ms and 2000 ms are assumptions about a loaded machine. They '
        r'are right often and wrong silently.'),
    ...pt('//', r'single-threaded',
        r'all allocations happen on main, which is the one thread the '
        r'TLS bug did not affect when the DLL is self-loaded. In a '
        r'cross-process injection the loading thread is a short-lived '
        r'remote thread, so every thread in the target is a "different '
        r'thread" from the one that called LoadLibraryW. That makes the '
        r'cross-process run a stronger test of that bug than the '
        r'self-load run, though this file was not written with it in '
        r'mind. That last point is my inference from the mechanism the '
        r'guard.rs comment describes.'),
    ...pt('//', r'no ownership shape',
        r'the allocations are independent blocks, so the file says '
        r'nothing about the daemon’s ownership inference. The Step 6 '
        r'targets in the design, built to produce a star or chain, are '
        r'the checkout and chaos examples of heaplens-alloc.'),
    ...pt('//', r'the target exits normally after detach',
        r'it does not test what happens when the target ends while '
        r'still hooked. That case was found a week later and has its own '
        r'targets.'),
    ...sec(r'what to take from it'),
    ...pt('//', r'let the target narrate',
        r'a process that prints its own pid and its own milestones '
        r'turns a two-process test from timing guesses into reading a '
        r'pipe.'),
    ...pt('//', r'name the window you are depending on',
        r'"Window for the driving test to spawn..." is a comment that '
        r'doubles as a specification.'),
    ...pt('//', r'names that are true only if you win a race',
        r'pre_attach_ptr is pre-attach only if the injector is slow.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-hook/examples/injection_target.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-hook/examples/injection_target.rs'),
  ],
);
