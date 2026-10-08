import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-launcher/src/main.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'main.rs — the launcher: two processes, one lifetime'),
    cm('//', r'a Job Object so the daemon cannot outlive the window, and a teardown step that was designed and never written'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'HeapLens.exe, the single entry point of the packaged folder'),
    kv('language', r'Rust, std plus windows-sys, no async, no console window'),
    kv('size', r'139 lines, 6 helper functions and a main'),
    kv('history', r'one commit, 43fc22e, 2026-07-08 14:37 +0300; never edited since'),
    kv('children', r'heaplens-daemon.exe, then heaplens_flutter.exe, both next to it'),
    kv('writes', r'launcher.log and daemon.log, beside the executable'),
    kv('tests', r'none'),
    ...sec(r'the problem: two programs, one icon'),
    ...para('//',
        r'HeapLens is two programs. The daemon (crates/heaplens-daemon) '
        r'owns the named pipe, the ownership graph, the SQLite store and a '
        r'WebSocket server. The Flutter app (heaplens_flutter) draws what '
        r'the daemon sends over that WebSocket. For development each is '
        r'started by hand. For a person who has been handed a folder, '
        r'that is not a product: they would have to start the daemon '
        r'first, wait for it, start the app, and remember to stop the '
        r'daemon afterwards. The launcher does those four things and '
        r'is the only executable such a person needs to double-click.'),
    blank,
    ...para('//',
        r'The part that is not obvious is the last one. A daemon that '
        r'keeps running after the window closes is a process nobody can '
        r'see, holding a named pipe and a TCP port, and the next '
        r'launch would find its port taken. The module comment states '
        r'the requirement in the strong form, and the strong form is '
        r'what shapes the file.'),
    ...code('rust', 'crates/heaplens-launcher/src/main.rs · the module documentation', r'''
//! Single entry point for the packaged HeapLens delivery folder.
//!
//! Spawns the daemon as a child process, waits for its WebSocket port to
//! start accepting connections, then launches the Flutter runner and blocks
//! until it exits. The daemon is assigned to a Windows Job Object with
//! `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` so it is torn down automatically the
//! moment this launcher process ends for *any* reason (clean exit, crash, or
//! being killed directly) — not only on the happy path where this process
//! gets to run its own cleanup code.
#![windows_subsystem = "windows"]'''),
    ...para('//',
        r'"Not only on the happy path where this process gets to run its '
        r'own cleanup code." That clause is the whole design. A launcher '
        r'that stops its daemon by calling kill at the end of main is '
        r'correct only when main reaches its end. If the launcher is '
        r'ended from the task manager, or crashes, no code of '
        r'its own runs at all. The Job Object moves the guarantee out of '
        r'the launcher and into the kernel: the operating system, not '
        r'this program, kills the daemon.'),
    blank,
    ...para('//',
        r'The second attribute, windows_subsystem = "windows", makes the '
        r'executable a GUI-subsystem program, so double-clicking it does '
        r'not open a console window. That is right for something whose '
        r'only visible output should be the Flutter window, and it has '
        r'a price that I come back to in the limits: a program with no '
        r'console has nowhere to print a panic.'),
    ...sec(r'the Job Object, in twenty-eight lines'),
    ...code('rust', 'crates/heaplens-launcher/src/main.rs · create_kill_on_close_job and assign_to_job', r'''
/// Creates a Job Object that kills every process assigned to it as soon as
/// its last handle closes (including implicitly, when this process exits or
/// is terminated). Returns the raw job handle.
fn create_kill_on_close_job() -> HANDLE {
    unsafe {
        let job = CreateJobObjectW(std::ptr::null(), std::ptr::null());
        assert!(!job.is_null(), "CreateJobObjectW failed");

        let mut info: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = std::mem::zeroed();
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;

        let ok = SetInformationJobObject(
            job,
            JobObjectExtendedLimitInformation,
            &info as *const _ as *const core::ffi::c_void,
            std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
        );
        assert!(ok != 0, "SetInformationJobObject failed");
        job
    }
}

fn assign_to_job(job: HANDLE, child: &Child) {
    unsafe {
        let handle = child.as_raw_handle() as HANDLE;
        let ok = AssignProcessToJobObject(job, handle);
        assert!(ok != 0, "AssignProcessToJobObject failed");
    }
}'''),
    ...para('//',
        r'A Job Object is a kernel object that groups processes and can '
        r'apply limits to the group. The one limit used here, '
        r'JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE, says that when the last '
        r'handle to the job is closed, every process still in the job is '
        r'terminated. The function creates an anonymous job (both '
        r'arguments to CreateJobObjectW are null: no security attributes, '
        r'no name), fills a JOBOBJECT_EXTENDED_LIMIT_INFORMATION '
        r'structure that is zeroed except for the one flag, and installs '
        r'it. The zeroed struct is the idiom for a Win32 limit block: '
        r'every limit not named stays off.'),
    blank,
    ...para('//',
        r'What makes the trick work is a line that is not in the code. '
        r'Nothing ever calls CloseHandle on the job. The handle returned '
        r'here lives in main() until the process ends, and when the '
        r'process ends for any reason the operating system closes all of '
        r'its handles, which closes the last handle to the job, which '
        r'kills the members. The doc comment says exactly that: '
        r'"including implicitly, when this process exits or is '
        r'terminated". A leaked handle is the mechanism, not a leak.'),
    blank,
    ...para('//',
        r'Error handling is assert!, which is deliberate for a program '
        r'this small: if the job cannot be created or configured, the '
        r'launcher has not been able to make its central promise, and '
        r'continuing without it would give the daemon the very '
        r'orphan-on-crash behaviour the file exists to prevent. The '
        r'cost of that choice is discussed under limits.'),
    blank,
    ...para('//',
        r'Windows documents that a process created by a member of a job '
        r'joins the same job unless the job allows breakaway, and this '
        r'job sets no breakaway flag. That means the short-lived '
        r'heaplens-injector.exe processes that the daemon spawns '
        r'(crates/heaplens-daemon/src/injector.rs) would be inside the '
        r'job as well. I did not test it and the repository does not '
        r'mention it; it is a consequence of the documented default, and '
        r'it would only matter if the launcher died in the middle of an '
        r'attach.'),
    ...sec(r'waiting for the daemon, honestly'),
    ...code('rust', 'crates/heaplens-launcher/src/main.rs · the constants and wait_for_port', r'''
const DAEMON_EXE: &str = "heaplens-daemon.exe";
const FLUTTER_EXE: &str = "heaplens_flutter.exe";
const WS_ADDR: &str = "127.0.0.1:9999";
const READY_TIMEOUT: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(100);
...
fn wait_for_port(addr: &str, timeout: Duration, daemon: &mut Child, log_file: &mut File) -> bool {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if let Ok(Some(status)) = daemon.try_wait() {
            log(log_file, &format!("daemon exited early with {status} before port came up"));
            return false;
        }
        if TcpStream::connect(addr).is_ok() {
            return true;
        }
        std::thread::sleep(POLL_INTERVAL);
    }
    false
}'''),
    ...para('//',
        r'The Flutter app connects to the daemon over WebSocket the moment '
        r'it starts. If it started before the daemon was listening it '
        r'would show a connection error for no reason a user could fix. '
        r'So the launcher polls: every 100 ms, up to 15 s, try to open a '
        r'TCP connection to the daemon’s WebSocket address, and start the app '
        r'only when that succeeds.'),
    blank,
    ...para('//',
        r'The loop checks two things in each round, and the order is the '
        r'interesting part. First it asks the child whether it has '
        r'already exited (try_wait). If the daemon crashed at startup, '
        r'for example because the port was taken or the database '
        r'could not be opened, the launcher notices on the first poll, '
        r'logs "daemon exited early with {status} before port came up", '
        r'and gives up at once, instead of waiting out 15 seconds for a '
        r'port that will never open. Only then does it try the connection. '
        r'A dead process and a slow process look identical to a port '
        r'probe, so the process check has to come first to tell them '
        r'apart.'),
    blank,
    ...para('//',
        r'The probe is a real connection. Reading the daemon side '
        r'(crates/heaplens-daemon/src/server.rs), an accepted socket '
        r'that closes without speaking is logged as "WS client '
        r'connecting from ..." and then "WS handshake failed for ..." at '
        r'warn level, so I would expect the final, successful probe of '
        r'every launch to leave exactly that pair of lines in '
        r'daemon.log. They are noise from the launcher, not a fault.'),
    blank,
    ...para('//',
        r'The address is a constant. The daemon’s own default in '
        r'config.rs is the same string, "127.0.0.1:9999", and it can be '
        r'overridden with the HEAPLENS_WS_ADDR environment variable. The '
        r'launcher does not read that variable, though the child it '
        r'spawns inherits the environment. Anyone who sets it before '
        r'launching would see the daemon listen on one port and the '
        r'launcher wait on another until the 15 seconds run out. That is '
        r'my reading of the two files; the packaged folder never sets '
        r'the variable.'),
    ...sec(r'main(): the sequence'),
    ...code('rust', 'crates/heaplens-launcher/src/main.rs · main (trimmed)', r'''
fn main() {
    let dir = exe_dir();
    let mut log_file = open_log(&dir, "launcher.log");
...
    let job = create_kill_on_close_job();

    log(&mut log_file, "starting daemon...");
    let daemon_log = open_log(&dir, "daemon.log");
    let mut daemon = Command::new(&daemon_path)
        .current_dir(&dir)
        .stdout(Stdio::from(daemon_log.try_clone().unwrap()))
        .stderr(Stdio::from(daemon_log))
        .spawn()
        .expect("failed to spawn heaplens-daemon.exe");
    assign_to_job(job, &daemon);
...
    if !wait_for_port(WS_ADDR, READY_TIMEOUT, &mut daemon, &mut log_file) {
        log(&mut log_file, "daemon did not become ready in time; killing it and exiting");
        let _ = daemon.kill();
        std::process::exit(1);
    }
    log(&mut log_file, "daemon is ready; launching Flutter app...");

    let mut app = Command::new(&flutter_path)
        .current_dir(&dir)
        .spawn()
        .expect("failed to spawn heaplens_flutter.exe");
    assign_to_job(job, &app);

    // Block until the user closes the app.
    let status = app.wait().expect("failed to wait on heaplens_flutter.exe");
    log(&mut log_file, &format!("Flutter app exited with {status}; stopping daemon"));

    // Explicit teardown on the happy path, in addition to the Job Object's
    // kill-on-close guarantee (which also fires if this process is killed
    // abruptly instead of reaching this line).
    let _ = daemon.kill();
    let _ = daemon.wait();
    log(&mut log_file, "daemon stopped; launcher exiting");
}'''),
    ...para('//',
        r'The shape is a straight line. Open the log, create the job, '
        r'start the daemon with both of its output streams pointing at '
        r'daemon.log (the same file opened twice by try_clone, so the '
        r'two streams interleave in order instead of fighting over the '
        r'file), put the daemon in the job, wait for the port, start the '
        r'app, put it in the job, block on the app, then stop the '
        r'daemon. Both children are given the executable’s own '
        r'directory as their working directory (current_dir), which is '
        r'what lets them find the rest of the folder, and the daemon’s relative '
        r'default database path, heaplens.db, therefore lands in the '
        r'delivery folder.'),
    blank,
    ...para('//',
        r'Three details are worth reading twice.'),
    ...pt('//', r'the app goes in the job too',
        r'assign_to_job(job, &app). If the launcher is killed, the '
        r'window disappears along with the daemon, so there is no state '
        r'in which a Flutter window is open on top of a dead backend.'),
    ...pt('//', r'the happy-path kill is redundant on purpose',
        r'the comment above it says "in addition to the Job Object’s '
        r'kill-on-close guarantee". Both mechanisms exist because they '
        r'cover different cases: the explicit kill is immediate and '
        r'visible in launcher.log, the job covers every case in which '
        r'this line is never reached.'),
    ...pt('//', r'the exit status of the app is logged and ignored',
        r'the launcher always ends quietly after the app closes, whatever '
        r'the app’s status was. Only a failure to start the daemon '
        r'produces exit code 1.'),
    blank,
    ...para('//',
        r'Child::kill on Windows is a hard TerminateProcess. The daemon '
        r'has a graceful path, the ctrl_c arm of its main loop, which '
        r'tells the store thread to commit its last batch '
        r'(crates/heaplens-daemon/src/main.rs). A terminated process '
        r'never reaches it. The store batches on a 100 ms interval, so '
        r'I would expect up to one batch of the final persisted rows to '
        r'be lost at every normal shutdown. Nothing in the repository '
        r'measures it, and for a live graph viewer the rows lost are the '
        r'last tenth of a second of a session.'),
    ...sec(r'the teardown step that was designed and not written'),
    ...para('//',
        r'On 2026-07-13, five days after this file was written, the '
        r'Stage 7 design document (docs/stage7-injection-design.md) took '
        r'a position on what should happen when HeapLens is closed while '
        r'it is attached to another process. Its section 4.6 begins by '
        r'withdrawing its own earlier recommendation. The first draft '
        r'proposed accepting the gap, because a hook left behind is '
        r'provably harmless to the target. The revised text says that '
        r'"harmless to the target’s execution" is not the same '
        r'question as "acceptable to leave behind": closing HeapLens '
        r'would otherwise leave live trampolines in a process the user '
        r'does not own, "removed only whenever that process happens to '
        r'exit on its own", which the document calls a persistent, '
        r'silent modification to third-party software.'),
    ...code('text', 'docs/stage7-injection-design.md · section 4.6, the specified sequence', r'''
1. Flutter app exits (as today).
2. **New:** launcher sends the daemon a `Shutdown` control message (small
   addition to the same WS control channel used for `AttachTarget`/
   `DetachTarget`, §3.1) if a target is currently attached; the daemon runs
   the normal detach sequence (§3.4 steps 1–2, spawn
   `heaplens-injector.exe <pid> --detach`, wait for the pipe to close) in
   response.'''),
    ...para('//',
        r'The sequence has a bounded wait with a fallback to the current '
        r'behaviour, so that, in the document’s words, the change '
        r'"can only improve the common case, never regress the timeout '
        r'case". The reversibility table in section 4.5 then lists the '
        r'scenario as settled:'),
    ...code('text', 'docs/stage7-injection-design.md · section 4.5, the table row', r'''
| HeapLens app closed (via launcher teardown) | Handled — launcher requests a bounded-timeout detach before tearing down the daemon (§4.6). No longer an accepted gap. |'''),
    ...para('//',
        r'I looked for that code and did not find it. The launcher '
        r'above stops at daemon.kill(). The control protocol has no '
        r'message to send:'),
    ...code('rust', 'crates/heaplens-protocol/src/control.rs · ControlRequest', r'''
pub enum ControlRequest {
    ListProcesses,
    AttachTarget { pid: u32 },
    DetachTarget,
}'''),
    ...para('//',
        r'Three variants, none of them Shutdown. The daemon’s ctrl_c arm '
        r'flushes the store and breaks the loop; it does not call '
        r'injector::detach. The launcher file has one commit, from '
        r'before the design, and no later one. The repository contains '
        r'no test of a timeout-and-fallback sequence either, which the '
        r'design’s Step 5 asked for as an isolated gate. A comment in '
        r'the hook, heaplens-hook/src/lib.rs, still refers to "the '
        r'launcher’s own bounded-detach pattern (section 4.6)". That '
        r'pattern is described in the design and absent from the '
        r'launcher.'),
    blank,
    ...para('//',
        r'What actually happens today, as far as the code lets me '
        r'say: with a target attached, closing the window ends the '
        r'Flutter app, the launcher kills the daemon, and the hook '
        r'DLL stays in the target. Its writer thread, which retries the '
        r'pipe every 100 ms (RETRY_SLEEP in heaplens-alloc/src/writer.rs), '
        r'keeps trying to reconnect; hooked allocations keep running '
        r'record(), which walks the stack and pushes onto the thread’s '
        r'ring; and when the ring is full, events are dropped. The '
        r'target keeps working, which is what section 4.3 of the design '
        r'proves. A person who clicks Detach first, using the control in '
        r'the ribbon, leaves nothing behind. I have no measurement of '
        r'the cost of an abandoned hook.'),
    blank,
    ...para('//',
        r'Two later fixes make the leftover state safer than it was when '
        r'the section was written. A target that exits while still hooked '
        r'used to crash or, with several busy threads, hang; both are '
        r'fixed (see the pages for heaplens-hook/src/lib.rs and '
        r'heaplens-hook/examples/exit_without_detach_multithreaded.rs), so '
        r'the "removed whenever that process happens to exit" case is now '
        r'tested to be clean. That narrows the risk. It does not make '
        r'the design’s point wrong, which was about responsibility and '
        r'not only about safety, and it does not implement it.'),
    ...sec(r'what is awkward about the file'),
    ...pt('//', r'panics have nowhere to go',
        r'with the windows subsystem the process has no console, so the '
        r'message of a failed assert! or expect() is not shown to anyone, '
        r'and the process just ends. Every startup check '
        r'(the missing-executable asserts, the two expects on spawn, the '
        r'job asserts) sits before or beside a log call, and none of them '
        r'write the reason to launcher.log. A user whose folder is '
        r'missing heaplens-daemon.exe would see nothing happen. That is '
        r'an inference from how Rust panics and Windows subsystems '
        r'behave; I did not run it.'),
    ...pt('//', r'the logs are truncated on every start',
        r'File::create replaces the file, so only the most recent '
        r'session survives, and a crash followed by a relaunch erases '
        r'the evidence of the crash. The daemon’s tracing output also '
        r'comes with ANSI colour codes even into a pipe, according to '
        r'the comment in h1-harness/src/main.rs, and I would expect the '
        r'same into a file.'),
    ...pt('//', r'readiness means "a socket accepted"',
        r'it does not mean the daemon has finished starting. Because '
        r'the WebSocket server hands each client to the graph task over '
        r'a channel, a client that connects early is served when the '
        r'task is ready, so this has been enough in practice, and I '
        r'know of no failure from it.'),
    ...pt('//', r'the install folder must be writable',
        r'open_log uses expect, so a read-only folder makes the '
        r'launcher panic before it logs anything. The logs are written '
        r'next to the executable by design.'),
    ...pt('//', r'the daemon is a console program',
        r'the launcher sets no creation flags and the daemon has no '
        r'windows_subsystem attribute. Whether Windows shows a console '
        r'window for it, given that its output is redirected, is '
        r'something I did not test and the repository does not say.'),
    ...pt('//', r'no tests',
        r'the Job Object guarantee, the early-exit detection and the '
        r'timeout are checked by running the product. A test would '
        r'need a stub daemon that exits early and one that never '
        r'listens, which is the shape the design’s Step 5 described.'),
    ...sec(r'what to take from it'),
    ...pt('//', r'put the guarantee where it cannot be skipped',
        r'an explicit kill runs only if you reach it; a kernel '
        r'object with kill-on-close runs even when you do not. The file '
        r'does both and says why.'),
    ...pt('//', r'ask the process before you ask the port',
        r'a child that has already died explains a closed port '
        r'better than a timeout does.'),
    ...pt('//', r'a design that is not in the code is a debt, not a '
        r'feature',
        r'section 4.6 reads as finished, and a comment in another crate '
        r'cites it as if it were. The shortest honest fix is either the '
        r'Shutdown message or a sentence in the design saying it was '
        r'not built.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-launcher/src/main.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-launcher/src/main.rs'),
  ],
);
