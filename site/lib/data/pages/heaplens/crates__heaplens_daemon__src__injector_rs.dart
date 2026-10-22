import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/src/injector.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'injector.rs — the daemon asks a short-lived child to do the dangerous part'),
    cm('//', r'attach and detach as one spawned process each, with every failure turned into a string for the UI'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'the daemon’s side of Stage 7 attach/detach: spawn heaplens-injector.exe, wait, report'),
    kv('language', r'Rust (async, tokio::process)'),
    kv('size', r'62 lines, one commit: 724695a (2026-07-19), never edited since'),
    kv('public API', r'attach(pid) and detach(pid), both async fn returning Result<(), String>'),
    kv('called from', r'the TargetCmd::Attach and TargetCmd::Detach arms of main.rs’s graph loop'),
    ...sec(r'why the daemon does not inject by itself'),
    ...para('//',
        r'Getting a DLL into another process means OpenProcess, VirtualAllocEx, writing a path, CreateRemoteThread on LoadLibraryW, and then, on detach, a very careful unwinding. That is all in the heaplens-injector crate, which the daemon deliberately does not link against. The module comment spells out the resulting contract: heaplens-injector is "a synchronous, one-shot CLI tool — it runs the attach or detach sequence to completion and exits; there is no long-lived injector process to track after a call returns."'),
    blank,
    ...para('//',
        r'Treating the injector as a child process buys isolation. If the remote-thread dance fails badly, it is the injector that dies, not the daemon with its ownership graph and SQLite thread and every connected UI. It also means the daemon needs no unsafe code for injection at all, and the only thing it has to understand about the injector is its command line (heaplens-injector <pid> --attach or --detach) and its exit status.'),
    blank,
    ...sec(r'the top of the module'),
    ...code('rust', r'crates/heaplens-daemon/src/injector.rs · lines 1-25', r'''
//! Stage 7 Step 3 (docs/stage7-injection-design.md §3.2): the daemon's own
//! orchestration of `heaplens-injector.exe` as a short-lived child process.
//! `heaplens-injector` is a synchronous, one-shot CLI tool — it runs the
//! attach or detach sequence to completion and exits; there is no long-lived
//! injector process to track after a call returns.

use std::path::PathBuf;

use tokio::process::Command;

const INJECTOR_EXE: &str = "heaplens-injector.exe";

/// Resolves `heaplens-injector.exe`'s path relative to this daemon's own
/// executable — the same "ships next to me" convention every other
/// component pair in this project uses (see `heaplens-injector`'s own
/// `dll_path()`, `heaplens-launcher`'s `exe_dir()`).
fn injector_path() -> Result<PathBuf, String> {
    let exe = std::env::current_exe().map_err(|e| format!("cannot determine daemon's own exe path: {e}"))?;
    let dir = exe.parent().ok_or("daemon exe has no parent directory")?;
    let path = dir.join(INJECTOR_EXE);
    if !path.exists() {
        return Err(format!("{INJECTOR_EXE} not found at {path:?} — expected next to heaplens-daemon.exe"));
    }
    Ok(path)
}'''),
    ...sec(r'finding the executable'),
    ...para('//',
        r'injector_path asks the operating system for the daemon’s own path with std::env::current_exe, takes its parent directory and joins the constant heaplens-injector.exe. The doc comment names the convention: it is "the same ’ships next to me’ convention every other component pair in this project uses", with heaplens-injector’s own dll_path() and heaplens-launcher’s exe_dir() given as the two siblings. The hook DLL sits next to the injector, the injector sits next to the daemon, and so the whole install is one folder.'),
    blank,
    ...para('//',
        r'There are three distinct failure messages in the function and each is written for a person reading a dialog, not a log: the OS could not give an exe path, the exe has no parent directory, or, the one a user will really hit, the file is not there. That last one prints the path it looked at and says what was expected: "expected next to heaplens-daemon.exe". Nothing falls back to PATH, on purpose or by omission; the code simply does not try.'),
    blank,
    ...sec(r'running it and reading the outcome'),
    ...code('rust', r'crates/heaplens-daemon/src/injector.rs · lines 26-62', r'''

async fn run(pid: u32, mode: &str) -> Result<(), String> {
    let exe = injector_path()?;
    let output = Command::new(&exe)
        .arg(pid.to_string())
        .arg(mode)
        .output()
        .await
        .map_err(|e| format!("failed to spawn {INJECTOR_EXE}: {e}"))?;

    if output.status.success() {
        return Ok(());
    }
    let mut msg = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    let stderr = String::from_utf8_lossy(&output.stderr);
    let stderr = stderr.trim();
    if !stderr.is_empty() {
        if !msg.is_empty() {
            msg.push_str(" | ");
        }
        msg.push_str(stderr);
    }
    if msg.is_empty() {
        msg = format!("{INJECTOR_EXE} exited with {}", output.status);
    }
    Err(msg)
}

/// Runs `heaplens-injector <pid> --attach` to completion.
pub async fn attach(pid: u32) -> Result<(), String> {
    run(pid, "--attach").await
}

/// Runs `heaplens-injector <pid> --detach` to completion.
pub async fn detach(pid: u32) -> Result<(), String> {
    run(pid, "--detach").await
}'''),
    ...para('//',
        r'Three points in run are worth stopping on.'),
    blank,
    ...pt('//', r'Command::new(&exe).arg(pid.to_string()).arg(mode).output().await',
        r'output() captures stdout and stderr and waits for exit, all asynchronously. The calling task is suspended, not a thread, so the daemon’s runtime keeps serving the pipe and the WebSocket meanwhile. The tokio process feature in Cargo.toml exists for this one call.'),
    ...pt('//', r'success is exit status zero and nothing else',
        r'on success the captured text is thrown away. The caller gets Ok(()) and the UI shows its own "attached to pid N" string, built in server.rs, not anything the injector said.'),
    ...pt('//', r'failure message assembly',
        r'the injector prints human-readable failures. Per its own source, fail() writes "heaplens-injector: <message>" to stderr and exits with code 1, while a few informational lines go to stdout via println. run() joins stdout (trimmed) and stderr (trimmed, if non-empty) with " | ", and if both are empty it falls back to "heaplens-injector.exe exited with <status>". So a crash that prints nothing still produces a non-empty message.'),
    ...sec(r'attach and detach are two lines each'),
    ...para('//',
        r'attach and detach differ only in the string passed as the second argument: --attach or --detach. Everything else, spawn, wait, collect, is shared in run. The injector’s own usage line is heaplens-injector <pid> --attach|--detach and it exits with code 2 on a bad one, which run would surface through the same fallback path.'),
    blank,
    ...sec(r'how the graph loop uses it'),
    ...para('//',
        r'main.rs’s graph task owns the session state "which pid is currently attached" (attached_pid) and is the only caller of these functions. Reading that code:'),
    blank,
    ...pt('//', r'Attach',
        r'if attached_pid is set, it first calls injector::detach on the old pid; a failure there is logged as a warning and the attach continues, because refusing "would strand the user with no way to switch targets at all", in the handler’s own words. Then, unless the new pid is the one the daemon is already receiving data for, it resets the graph, resolver and storm tracker. Then injector::attach(pid): Ok records attached_pid and replies Ok, Err forwards the message to the UI.'),
    ...pt('//', r'Detach',
        r'injector::detach(pid); on failure attached_pid is restored so that a retry is possible. With nothing attached, detach is an idempotent no-op that never reaches this module.'),
    ...para('//',
        r'While run is awaited, the graph task is parked in that match arm, so no ticks, events or other commands are processed until the injector returns. server.rs’s comment says this can take "up to a few seconds" and says the await blocks only the one client’s task. That is true of the WebSocket side, but in main.rs the Attach arm is awaited inside the graph loop’s select, so it is the whole graph task that waits. The injector’s own detach has a 5 second timeout on the target, so the worst case is bounded, but it is real.'),
    blank,
    ...sec(r'design decisions and trade-offs'),
    ...pt('//', r'errors are strings, not an enum',
        r'the only consumer is the UI dialog, which shows text. A typed error would need a mapping layer that nothing uses. The cost is that callers cannot branch on the kind of failure.'),
    ...pt('//', r'no timeout of its own',
        r'run waits as long as the child runs. It relies on the injector to bound itself (its source has explicit waits and timeouts), so a hung injector would hang the attach.'),
    ...pt('//', r'no process tracking after return',
        r'by design nothing outlives the call, so there is no kill-on-exit logic, no handle table, nothing to leak.'),
    ...pt('//', r'stdout is trusted as text',
        r'from_utf8_lossy means odd bytes become replacement characters rather than failing the error path.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'It is not, directly. No file in crates/heaplens-daemon/tests imports heaplens_daemon::injector, and the test servers are created with a target_tx whose receiver is never read, so attach requests cannot reach this code from the tests. The injector’s behaviour is exercised from the other direction, by the hook tests that load heaplens_hook.dll into a real child process (hook_self_load_wire.rs, hook_self_load_spawned_thread.rs, hook_owner_free_no_crash.rs) and, in 724695a’s commit message, by a live attach and detach against a running application.'),
    blank,
    ...sec(r'history'),
    ...para('//',
        r'One commit, 724695a on 2026-07-19: "port Stage 7 control protocol from feat/stage7-injection". The branch with the UI (an Attach button and process picker) and the branch with the daemon-side control protocol had been developed as siblings from the same base; this commit brought procs.rs, injector.rs and the server’s request-read loop across so the picker, in the commit’s words, "just started working".'),
    blank,
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/src/injector.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/src/injector.rs'),
  ],
);
