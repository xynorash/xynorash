import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'hook_owner_free_no_crash.rs — four ways a target can leave while the hook is still in it'),
    cm('//', r'a crash that vanished, a hang found and fixed with WinDbg, and the tests that stand behind the Attach button'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'regression tests for exit-without-detach under real cross-process injection'),
    kv('language', r'Rust, plain #[test] (no async), Windows only (#![cfg(windows)]); a 138-line module comment is the investigation log'),
    kv('size', r'407 lines, 4 tests, two commits (deff3ad 2026-07-26, b5c5aed 2026-07-26)'),
    kv('exercises', r'heaplens-injector.exe, heaplens_hook.dll, and four examples from heaplens-hook'),
    kv('does not use', r'a daemon: no pipe server runs, the hook’s writer thread has nobody to talk to'),
    ...sec(r'what question it answers'),
    ...para('//',
        r'The Attach button lets a user inject heaplens_hook.dll into a running program. The program will sooner or later exit while the DLL is still hooked in, because the user closed it, or it crashed, or the daemon was not there to ask for a detach. The daemon does not help: this file’s last paragraph states that main.rs’s TargetDisconnected handling "does not call injector::detach when a target exits on its own — it only clears attached_pid and broadcasts TargetExited". So "exit without detach" is not a corner case; it is the normal way an attached program ends. These four tests are what, in the file’s words, "stand behind re-enabling the ‘Attach to Process’ UI gate".'),
    blank,
    ...para('//',
        r'The file is unusual because it carries its own lab notebook. The 138-line module comment narrates three findings in order, and the tests are the permanent form of the conclusions.'),
    blank,
    ...sec(r'the investigation, in the order the comment tells it'),
    ...code('rust', r'crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs · lines 6-22', r'''
//! ## Original finding (2026-07-21/22, `feat/stage7-injection`)
//!
//! The owner-freed-while-children-live workload itself (owner alloc, 8
//! children alloc, owner free while children live, 20 rounds of
//! alloc/realloc/free churn, children free) never crashed — it completed
//! and printed its final marker every time, whether or not a daemon was
//! listening. The crash was **not** in that pattern.
//!
//! The real, reliably-reproducing mechanism found: the target process
//! exiting normally (falling off the end of `main`) while
//! `RtlAllocateHeap`/`RtlReAllocateHeap`/`RtlFreeHeap` hooks were still
//! installed — i.e. `heaplens-injector --detach` was never called before
//! the target's own process exit — reliably terminated with exit status
//! `0xC0000005` (STATUS_ACCESS_VIOLATION). A temporary diagnostic Vectored
//! Exception Handler installed for that investigation never caught the
//! fault (no log entry) — consistent with a `__fastfail`-driven crash,
//! which bypasses SEH/VEH by design.'''),
    ...para('//',
        r'First finding (2026-07-21 and 22, on the feat/stage7-injection branch). The reported crash was an access violation (0xC0000005) on "case 2", an owner freed while its children are still live. The investigation found that the workload itself never crashed, whether or not a daemon was listening. The crash was not in the ownership pattern. It was in the target exiting normally with the Rtl heap hooks still installed. A diagnostic vectored exception handler never fired, which the comment reads as consistent with a __fastfail, a crash path that bypasses SEH and VEH by design.'),
    blank,
    ...para('//',
        r'Second finding, 2026-07-26, on master. The original investigation predates the TLS/FLS fix by about two and a half hours (cf6dccc at 20:41, 8cc0f1c at 23:12 the same evening) and nobody had re-tested this scenario against the fixed build. The comment links the two: the old thread_local! crashed on first access from any thread other than the one that called LoadLibraryW, and a dying process’s worker threads are exactly that population. Re-tested with the real injector: 15 of 15 clean exits for the single-threaded repro; 30 of 30 clean runs, 6,000 race attempts in total, for the FLS race repro. The wording on the second is careful: "No reproducing evidence for this theoretical gap". It does not say the hazard is impossible.'),
    blank,
    ...para('//',
        r'Third finding, same day: a new defect, a hang and not a crash.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs · lines 52-76', r'''
//! ## NEW finding, same investigation: multi-threaded exit-without-detach
//! can HANG (not crash)
//!
//! `exit_without_detach_multithreaded.exe` (several worker threads
//! *continuously* making hooked allocations in a tight loop, still live
//! when the process exits, never joined, no detach) does not crash — but
//! roughly 40-60% of runs (observed across ~15 attempts, several batches)
//! the process never terminates at all. Confirmed by direct observation,
//! not assumption:
//! - `Process.HasExited` stays false past a 15s wait; CPU time (queried via
//!   `Get-Process`) **plateaus** within the first couple of seconds and
//!   never grows again, even minutes later — consistent with the worker
//!   threads becoming *blocked*, not spinning.
//! - The hung process resists termination by three independent
//!   mechanisms tried in sequence: PowerShell `Stop-Process -Force`
//!   (reports success, process persists), `taskkill /F` (reports "no
//!   running instance" while `tasklist` simultaneously shows it still
//!   running), and finally `Invoke-CimMethod ... -MethodName Terminate`
//!   (WMI `Win32_Process.Terminate`), which did eventually succeed.
//! - `heaplens-injector --detach` against a hung instance fails with
//!   `OpenThread failed for worker thread <tid> in process <pid>` — the
//!   DLL's own persistent worker thread (`attach_impl`'s spawned thread,
//!   normally parked via alertable `SleepEx` and reused via `QueueUserAPC`
//!   for detach) appears to be gone or invalid, breaking the normal detach
//!   path too.'''),
    ...para('//',
        r'With several worker threads continuously allocating when the process exits, roughly 40 to 60 percent of runs never terminated. The comment lists the observations that make it a deadlock and not a spin: CPU time plateaus within seconds and never grows; the process resisted Stop-Process and taskkill /F (which reported it as not running while tasklist still listed it) and died only to WMI’s Win32_Process.Terminate; and the injector’s own --detach failed with an OpenThread error because the DLL’s worker thread was gone.'),
    blank,
    ...sec(r'the root cause'),
    ...code('rust', r'crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs · lines 80-103', r'''
//! Confirmed via WinDbg Preview (`cdbX64.exe -pv`, non-invasive attach —
//! invasive attach was itself found to disturb the hang, reliably making
//! it exit right as `DebugActiveProcess`-based attach completed, 3/3
//! times; non-invasive attach doesn't). Symbol-resolved stack trace of
//! the sole surviving ("main") thread, reproduced identically on two
//! separate hung instances:
//!
//! ```text
//! ntdll!NtWaitForAlertByThreadId
//! ntdll!RtlWaitOnAddress
//! KERNELBASE!WaitOnAddress
//! heaplens_hook!std::sys::sync::mutex::futex::Mutex::lock_contended
//! heaplens_hook!heaplens_alloc::capture::capture_stack   <- blocked here
//! heaplens_hook!heaplens_alloc::record
//! heaplens_hook!heaplens_hook::hook_heap_free
//! ucrtbase!free_base
//! ucrtbase!destroy_fls
//! ntdll!RtlpFlsDataCleanup
//! ntdll!LdrShutdownProcess
//! ntdll!RtlExitUserProcess
//! KERNEL32!ExitProcessImplementation
//! ucrtbase!common_exit
//! <target's own main>
//! ```'''),
    ...para('//',
        r'A non-invasive WinDbg attach (invasive attach itself disturbed the hang: it made the process exit as the attach completed, 3 of 3 times) produced the same stack on two hung instances. The surviving thread is inside ExitProcess, running FLS cleanup, which frees a buffer; the free goes through the still-installed hook, hook_heap_free, which calls record, which calls capture_stack, which blocks on a mutex.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs · lines 105-126', r'''
//! Confirmed mechanism: `RtlExitUserProcess` abruptly terminates the other
//! worker threads without running their cleanup. If one was caught inside
//! `capture_stack`, holding `heaplens_alloc::DBGHELP_LOCK` (a process-wide
//! `Mutex<()>`, acquired on every hooked allocation from every thread —
//! see `capture.rs`), that lock is now orphaned permanently. The sole
//! surviving thread's own FLS cleanup then frees a fiber-local buffer;
//! since hooks were never disabled (no explicit detach), that free routes
//! through `hook_heap_free` -> `record` -> `capture_stack`, which tries to
//! acquire the same orphaned lock and blocks forever. This explains the
//! rate difference from `fls_race_repro.exe` precisely: threads spending a
//! larger fraction of their lifetime inside `capture_stack` (continuous
//! looping) have proportionally higher odds of being caught mid-lock at
//! the instant of abrupt termination than short-lived, mostly-idle ones.
//!
//! Fixed in `heaplens-alloc/src/capture.rs`: `capture_stack` now uses
//! `DBGHELP_LOCK.try_lock()` instead of `.lock()` — a held lock (orphaned
//! or merely contended, indistinguishable and both handled identically)
//! yields an empty, unresolved capture instead of blocking. Cannot
//! deadlock regardless of *why* the lock is unavailable. Re-validated: 25
//! manual runs (mixed batch/individual, exit codes explicitly checked)
//! all clean post-fix, on the same machine and binaries that showed 9/10
//! and 7/8 hung pre-fix.'''),
    ...para('//',
        r'The mechanism, step by step. capture_stack takes DBGHELP_LOCK, a process-wide mutex, on every hooked allocation of every thread, because the Windows symbol machinery is not thread safe. When the process exits, RtlExitUserProcess kills the other threads without running any cleanup. If one of those threads was inside capture_stack holding the lock at that instant, the lock is orphaned for good. The survivor then needs the same lock to record its own cleanup free, and waits forever. That explains the rate: threads that live inside capture_stack most of the time (the continuously looping workers) are the likelier ones to be caught holding it, while the short-lived idle threads of the FLS repro are rarely caught.'),
    blank,
    ...para('//',
        r'The fix is one call. capture_stack uses try_lock instead of lock. If the lock is held, "orphaned or merely contended, indistinguishable and both handled identically", the capture returns empty and unresolved instead of blocking. It cannot deadlock regardless of why the lock is unavailable, and the uncontended path is unchanged. The cost is that a contended capture records an allocation without a stack. The fix was committed as b5c5aed with two unit tests in capture.rs; it removed the #[ignore] that deff3ad had put on the hang test, because an unconditionally asserted hang test "would otherwise non-deterministically hang the test suite and leak unkillable processes on every run", in deff3ad’s own message.'),
    blank,
    ...para('//',
        r'Before the fix the hang was reproduced 9 of 10 and 7 of 8 times; after, the comment records 25 clean manual runs.'),
    blank,
    ...sec(r'the shared plumbing'),
    ...code('rust', r'crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs · lines 146-157', r'''
fn target_debug_dir() -> std::path::PathBuf {
    let test_exe = std::env::current_exe().unwrap();
    test_exe
        .parent()
        .and_then(|p| p.parent())
        .expect("cannot determine target dir from test exe path")
        .to_path_buf()
}

fn target_path(name: &str) -> std::path::PathBuf {
    target_debug_dir().join("examples").join(format!("{name}.exe"))
}'''),
    ...para('//',
        r'target_path finds the example in target/<profile>/examples/ and the injector at target/<profile>/heaplens-injector.exe, both relative to the test’s own location. The assertions that they exist carry the build command, which here says cargo build --release (while the tests will also work with a debug profile if the pieces are built the same way; the profile directory is whichever one the test itself is in).'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs · lines 163-190', r'''
fn read_until_marker(
    reader: &mut BufReader<std::process::ChildStdout>,
    marker: &str,
    timeout: Duration,
) -> Vec<String> {
    let deadline = std::time::Instant::now() + timeout;
    let mut lines = Vec::new();
    let mut line = String::new();
    loop {
        line.clear();
        if std::time::Instant::now() >= deadline {
            break;
        }
        match reader.read_line(&mut line) {
            Ok(0) => break,
            Ok(_) => {
                let trimmed = line.trim_end().to_string();
                let hit = trimmed.starts_with(marker);
                lines.push(trimmed);
                if hit {
                    break;
                }
            }
            Err(_) => break,
        }
    }
    lines
}'''),
    ...para('//',
        r'read_until_marker reads the child’s stdout line by line until a line starts with a marker or the deadline passes. It checks the deadline between reads, and a read_line that blocks cannot be interrupted, so a target that goes silent would block the test until the pipe closes.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs · lines 192-234', r'''
fn spawn_and_attach(
    target_name: &str,
    work_dir: &std::path::Path,
) -> (std::process::Child, BufReader<std::process::ChildStdout>, u32) {
    let target_exe = target_path(target_name);
    let injector_exe = injector_path();
    assert!(
        target_exe.exists(),
        "build the example first: cargo build --release -p heaplens-hook --example {target_name}"
    );
    assert!(injector_exe.exists(), "build the injector first: cargo build --release -p heaplens-injector");

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

    (target, reader, pid)
}'''),
    ...para('//',
        r'spawn_and_attach is the common setup. It spawns the target in a private temp directory with stdout piped and stderr discarded, reads until TARGET_PID=, and runs the real heaplens-injector.exe <pid> --attach, asserting success with both streams in the failure message. All four tests use this, so each of them runs through the actual injection path: OpenProcess, a remote thread, LoadLibraryW, the DLL’s attach.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs · lines 388-407', r'''
trait WaitTimeoutOrKill {
    fn wait_timeout_or_kill(&mut self, timeout: Duration) -> std::io::Result<std::process::ExitStatus>;
}

impl WaitTimeoutOrKill for std::process::Child {
    fn wait_timeout_or_kill(&mut self, timeout: Duration) -> std::io::Result<std::process::ExitStatus> {
        let deadline = std::time::Instant::now() + timeout;
        loop {
            if let Some(status) = self.try_wait()? {
                return Ok(status);
            }
            if std::time::Instant::now() >= deadline {
                let _ = self.kill();
                let _ = self.wait();
                return Err(std::io::Error::new(std::io::ErrorKind::TimedOut, "process did not exit in time"));
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    }
}'''),
    ...para('//',
        r'wait_timeout_or_kill is the guard that makes a hang a failure. It polls try_wait every 50 ms, and at the deadline kills the process, waits for it and returns a TimedOut error. The tests call it with 5 seconds and .expect(...) the result, so a hung target fails the test with "target did not exit" and does not leave a zombie, except when the process resists kill, as the comment’s own account says a hung one can.'),
    blank,
    ...sec(r'the four tests'),
    ...code('rust', r'crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs · lines 241-271', r'''
#[test]
fn detach_before_target_exit_is_clean() {
    let work_dir = std::env::temp_dir().join(format!("heaplens_owner_free_clean_{}", std::process::id()));
    std::fs::create_dir_all(&work_dir).unwrap();

    let (mut target, mut reader, pid) = spawn_and_attach("owner_freed_while_children_live", &work_dir);

    let workload_lines = read_until_marker(&mut reader, "WORKLOAD_DONE", Duration::from_secs(10));
    assert!(
        workload_lines.iter().any(|l| l.starts_with("WORKLOAD_DONE")),
        "target did not reach WORKLOAD_DONE — got: {workload_lines:?}"
    );

    let injector_exe = injector_path();
    let detach_output = std::process::Command::new(&injector_exe)
        .arg(pid.to_string())
        .arg("--detach")
        .output()
        .expect("failed to spawn heaplens-injector --detach");
    assert!(
        detach_output.status.success(),
        "detach failed: stdout={} stderr={}",
        String::from_utf8_lossy(&detach_output.stdout),
        String::from_utf8_lossy(&detach_output.stderr)
    );

    let status = target.wait_timeout_or_kill(Duration::from_secs(5)).expect("target did not exit after detach");
    assert!(status.success(), "target exited abnormally even after a clean detach: {status:?}");

    let _ = std::fs::remove_dir_all(&work_dir);
}'''),
    ...para('//',
        r'detach_before_target_exit_is_clean is the control: run the owner-freed-while-children-live workload, wait for WORKLOAD_DONE, run the injector with --detach, expect success and a clean exit within 5 seconds. It shows the baseline works, and the comment says it matches "what real daemon-driven attach/detach cycles already do".'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs · lines 278-302', r'''
#[test]
fn target_exit_without_detach_is_clean() {
    let work_dir = std::env::temp_dir().join(format!("heaplens_owner_free_nocrash_repro_{}", std::process::id()));
    std::fs::create_dir_all(&work_dir).unwrap();

    let (mut target, mut reader, _pid) = spawn_and_attach("owner_freed_while_children_live", &work_dir);

    let workload_lines = read_until_marker(&mut reader, "WORKLOAD_DONE", Duration::from_secs(10));
    assert!(
        workload_lines.iter().any(|l| l.starts_with("WORKLOAD_DONE")),
        "target did not reach WORKLOAD_DONE — got: {workload_lines:?}"
    );

    // No detach — let the target exit on its own, hooks still active.
    let status = target.wait_timeout_or_kill(Duration::from_secs(5)).expect("target did not exit");
    assert!(
        status.success(),
        "target crashed on exit without detach (status={status:?}) — this scenario used to be a \
         confirmed, reliable crash (0xC0000005) and was verified clean before this test was \
         written as an assertion; if this fails, something regressed — see this file's module \
         doc comment for the full history"
    );

    let _ = std::fs::remove_dir_all(&work_dir);
}'''),
    ...para('//',
        r'target_exit_without_detach_is_clean is the original reported scenario: same workload, no detach, the process exits by itself with hooks live. It must exit with status success. The failure message is long and explicit about the history: the scenario "used to be a confirmed, reliable crash (0xC0000005) ... if this fails, something regressed".'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs · lines 331-353', r'''
#[test]
fn multithreaded_exit_without_detach_is_clean() {
    let work_dir = std::env::temp_dir().join(format!("heaplens_mt_exit_nocrash_{}", std::process::id()));
    std::fs::create_dir_all(&work_dir).unwrap();

    let (mut target, mut reader, _pid) = spawn_and_attach("exit_without_detach_multithreaded", &work_dir);

    let workload_lines = read_until_marker(&mut reader, "WORKLOAD_DONE", Duration::from_secs(10));
    assert!(
        workload_lines.iter().any(|l| l.starts_with("WORKLOAD_DONE")),
        "target did not reach WORKLOAD_DONE — got: {workload_lines:?}"
    );

    // No detach — worker threads still live and allocating, target exits
    // on its own.
    let status = target.wait_timeout_or_kill(Duration::from_secs(5)).expect("target did not exit");
    assert!(
        status.success(),
        "target crashed on exit without detach, worker threads still live (status={status:?})"
    );

    let _ = std::fs::remove_dir_all(&work_dir);
}'''),
    ...para('//',
        r'multithreaded_exit_without_detach_is_clean is the one that found the hang: eight worker threads allocating in a tight loop, never joined, no detach. It is the test whose fix needed WinDbg. See the exit_without_detach_multithreaded page for the target.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs · lines 362-383', r'''
#[test]
fn fls_race_exit_without_detach_is_clean() {
    let work_dir = std::env::temp_dir().join(format!("heaplens_fls_race_{}", std::process::id()));
    std::fs::create_dir_all(&work_dir).unwrap();

    let (mut target, mut reader, _pid) = spawn_and_attach("fls_race_repro", &work_dir);

    let workload_lines = read_until_marker(&mut reader, "SPAWNED", Duration::from_secs(5));
    assert!(
        workload_lines.iter().any(|l| l.starts_with("SPAWNED")),
        "target did not reach the SPAWNED marker — got: {workload_lines:?}"
    );

    // The target calls std::process::exit() immediately after printing
    // SPAWNED — no detach, 200 unjoined threads racing process teardown.
    let status = target.wait_timeout_or_kill(Duration::from_secs(5)).expect("target did not exit");
    assert!(
        status.success(),
        "target crashed under the targeted FLS-race repro (status={status:?}) — the theoretical \
         hazard documented on ring.rs's thread_ring::shutdown may have actually reproduced; \
         see this file's module doc comment"
    );'''),
    ...para('//',
        r'fls_race_exit_without_detach_is_clean runs fls_race_repro, which spawns 200 short-lived unjoined threads and calls std::process::exit immediately, to hit the theoretical window described on ring.rs’s thread_ring::shutdown. It waits for the SPAWNED marker.'),
    blank,
    ...sec(r'what the tests do not prove'),
    ...para('//',
        r'· That the hook was active during the workload. The tests check that the injector reported success, not that any event was captured, and no pipe server is running. The target waits 500 ms after printing its pid before starting work, and the attach has to finish inside that window for the workload to run hooked. If attach is slower, a test can pass without having exercised the hook.'),
    ...para('//',
        r'· Rate. A hang that appears in 40 to 60 percent of runs is caught on a single run about half the time before the fix, and a regression that appears 5 percent of the time would pass most runs. These are single-shot tests.'),
    ...para('//',
        r'· Different Windows versions. The FLS and DLL-unmap ordering the second finding worries about is described as "informal, not guaranteed"; one machine’s clean runs do not settle it.'),
    ...para('//',
        r'· Only exit paths with a normal process exit (main returning or std::process::exit). A target killed from outside is not tested.'),
    ...sec(r'why it is a good test file anyway'),
    ...para('//',
        r'The tests are short because the module comment does the explaining; every assertion message points back to it. The history of a bug, including the dead ends (a diagnostic handler that never fired, an invasive debugger that cured the hang) is kept next to the code that guards against its return. A reader debugging a failure six months from now starts with the stack trace and the reason try_lock is there.'),
    blank,
    ...sec(r'history'),
    ...pt('//', r'deff3ad (2026-07-26)',
        r'"re-verify exit-without-detach crash, find new hang defect": adds the file with the multi-threaded test marked #[ignore]; its commit message says the Attach button stays disabled because the hang is "more severe than the crash it replaces".'),
    ...pt('//', r'b5c5aed (2026-07-26)',
        r'"replace blocking DBGHELP_LOCK.lock() with try_lock() in capture_stack": the module comment is rewritten with the WinDbg root cause, and the #[ignore] is removed.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs'),
  ],
);
