import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-injector/src/main.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'main.rs — the injector: a small tool whose job is to say no clearly'),
    cm('//', r'two remote threads in, an APC and a FreeLibrary out, a message for every failure'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'one-shot CLI: loads heaplens_hook.dll into a pid and drives it'),
    kv('usage', r'heaplens-injector <pid> --attach | --detach'),
    kv('language', r'Rust over windows-sys, no async, no heaplens crate dependency'),
    kv('size', r'426 lines (415 when ported, +11 for the safety check)'),
    kv('history', r'724695a (2026-07-19), 864167e (2026-07-22)'),
    kv('exit codes', r'0 success, 1 failure with a message on stderr, 2 bad usage'),
    kv('tests', r'none in the crate; exercised through the daemon’s tests and live'),
    ...sec(r'why it is a separate, boring executable'),
    ...code('rust', 'crates/heaplens-injector/src/main.rs · the module documentation', r'''
//! Stage 7 Step 2 (docs/stage7-injection-design.md §8): a standalone,
//! synchronous tool that injects `heaplens_hook.dll` into a target process
//! and drives its exported `HeapLensHookAttachRemote`/detach entry points,
//! then unloads the DLL. No Rust-level dependency on
//! `heaplens-hook` — it locates the DLL and resolves its exports the same
//! way any injector would target an arbitrary DLL: `LoadLibraryW` +
//! `GetProcAddress`, `CreateRemoteThread` to run code in the target.
//!
//! Usage: `heaplens-injector <pid> --attach|--detach`'''),
    ...para('//',
        r'The design document (section 1.3) gives the reason in one '
        r'sentence: injection "is synchronous, Win32-heavy, and '
        r'process-scoped code that has no reason to live inside the '
        r'daemon’s async tokio runtime". Kept as a standalone tool, it '
        r'"can be pointed at any test target PID from a terminal", the '
        r'way the producer examples can be run by hand. The daemon owns '
        r'when to attach, since it already owns the pipe session, and '
        r'delegates the how to a child process (section 3.2), once per '
        r'attach and once per detach. There is no long-lived injector to '
        r'track.'),
    blank,
    ...para('//',
        r'The second sentence of the module comment is easy to skim past: '
        r'there is "no Rust-level dependency on heaplens-hook". The '
        r'injector finds the DLL on disk and resolves its exports as '
        r'"any injector would target an arbitrary DLL". That keeps the '
        r'two sides honest. The only contract between them is the one '
        r'a stranger’s tool would have to rely on: a file name, export '
        r'names, and return codes. The cost is that the contract lives '
        r'in strings and integers on both sides, which the return-code '
        r'section below returns to.'),
    blank,
    ...para('//',
        r'The daemon side of the contract is short enough to read in '
        r'full. It spawns the tool, waits, and turns a failure into one '
        r'string.'),
    ...code('rust', 'crates/heaplens-daemon/src/injector.rs · run() merges both streams into one message (trimmed)', r'''
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
}'''),
    ...para('//',
        r'That is why the injector’s fail() helper (below) prints one '
        r'self-contained sentence to stderr and exits with 1. Commit '
        r'864167e, which wired in the safety check, records the proof '
        r'that this chain works end to end: the refusal for a real '
        r'protected process, Windows Defender, "appeared in both the '
        r'dialog and the verbose-log panel". The Flutter tests carry '
        r'fixtures in the same style, for example control_test.dart’s '
        r'"cannot open process 999999999 — access denied, or the '
        r'process does not exist", and the picker dialog test asserts '
        r'that the text is displayed, not replaced by a generic '
        r'"failed".'),
    ...sec(r'the sequence, in one screen'),
    ...pt('//', r'attach 1: refuse',
        r'safety::check(pid) runs before any injection-capable handle '
        r'is requested. The next page in this tree covers it.'),
    ...pt('//', r'attach 2: look before touching',
        r'open the pid with query-only rights and run IsWow64Process2.'),
    ...pt('//', r'attach 3: open with minimal rights',
        r'five rights, never PROCESS_ALL_ACCESS, never a retry with '
        r'more.'),
    ...pt('//', r'attach 4: plant the path',
        r'VirtualAllocEx a buffer in the target, WriteProcessMemory the '
        r'DLL path into it.'),
    ...pt('//', r'attach 5: load',
        r'CreateRemoteThread with LoadLibraryW as the start address and '
        r'the buffer as its argument. Free the buffer. Check the '
        r'target’s module list to see that the DLL really arrived.'),
    ...pt('//', r'attach 6: arm',
        r'CreateRemoteThread again, at HeapLensHookAttachRemote, whose '
        r'address is the target’s load base plus an offset computed '
        r'locally.'),
    ...pt('//', r'detach',
        r'no new thread: read the worker’s thread id and queue an APC '
        r'to it; poll a result word; then a remote FreeLibrary.'),
    blank,
    ...para('//',
        r'Attach is the conventional two-step: load, then call. The '
        r'reason it is two threads and not one, from section 4.1 of the '
        r'design document, is that the library’s DllMain runs under the '
        r'loader lock, and real work is done only after LoadLibrary has '
        r'returned.'),
    ...sec(r'failing well: one function, one rule'),
    ...code('rust', 'crates/heaplens-injector/src/main.rs · fail()', r'''
/// Every failure path returns a message meant to be shown to the user
/// verbatim (per §3.3) — specific enough to say what went wrong and, where
/// applicable, what to do about it.
fn fail(msg: impl Into<String>) -> ! {
    eprintln!("heaplens-injector: {}", msg.into());
    std::process::exit(1);
}'''),
    ...para('//',
        r'The return type is !, so every call site is a terminator and '
        r'the control flow stays flat: look at the sequence above and '
        r'notice there is no error plumbing in it. The doc comment '
        r'states the rule that the rest of the file obeys. Each message '
        r'is for a human who sees it verbatim, "per section 3.3" in '
        r'the comment’s words, and "specific enough to say what went '
        r'wrong and, where applicable, what to do about it". '
        r'Examples from the file: "access denied opening process 1234 — '
        r'try running HeapLens as Administrator", and the first message '
        r'in the next excerpt, which names the elevation option and '
        r'says that "this tool does not attempt to elevate itself".'),
    ...sec(r'the architecture check'),
    ...code('rust', 'crates/heaplens-injector/src/main.rs · RemoteProcess::open, the probe (trimmed)', r'''
    fn open(pid: u32) -> Self {
        // Architecture check first, via a query-only handle, before any
        // attempt to write to or execute in the target (§3.3). x64 cannot
        // inject into an x86 target — different address space layout,
        // calling convention, and the hook DLL itself is architecture-
        // specific.
        let probe = unsafe { OpenProcess(PROCESS_QUERY_INFORMATION, 0, pid) };
        if probe.is_null() {
            fail(format!(
                "cannot open process {pid} to check its architecture — access denied, or the \
                 process does not exist. If the target requires elevation, re-launch HeapLens \
                 as Administrator; this tool does not attempt to elevate itself."
            ));
        }
        let mut process_machine = 0u16;
        let mut native_machine = 0u16;
        let ok = unsafe { IsWow64Process2(probe, &mut process_machine, &mut native_machine) };
        if ok == 0 {
            unsafe { CloseHandle(probe) };
            fail(format!("IsWow64Process2 failed for process {pid} — cannot verify architecture match"));
        }
        // process_machine != IMAGE_FILE_MACHINE_UNKNOWN means the target is
        // running under WOW64 emulation (i.e. it is a 32-bit process on a
        // 64-bit system) — not native at native_machine's architecture.
        if process_machine != IMAGE_FILE_MACHINE_UNKNOWN || native_machine != IMAGE_FILE_MACHINE_AMD64 {
            unsafe { CloseHandle(probe) };
            fail(format!(
                "target process {pid} is a 32-bit process; this build of HeapLens is 64-bit \
                 and cannot attach"
            ));
        }
        unsafe { CloseHandle(probe) };'''),
    ...para('//',
        r'Order matters here. The first handle requests only '
        r'PROCESS_QUERY_INFORMATION, enough for IsWow64Process2 and '
        r'nothing that can modify the target, and it is closed on every '
        r'path before the real open. The check is a conjunction that '
        r'says what native means: the target must not be running under '
        r'WOW64 and the machine must be AMD64. A 32-bit process on a '
        r'64-bit system would get the sentence the design document '
        r'specifies, "this build of HeapLens is 64-bit and cannot '
        r'attach". The reason for refusing, from the same document, is '
        r'that "the hook DLL itself is architecture-specific".'),
    blank,
    ...para('//',
        r'One thing in this check is stricter than its message. The '
        r'condition also rejects any machine whose native architecture is '
        r'not AMD64, for example an ARM64 Windows host, and in that '
        r'case the user would still read "is a 32-bit process", which '
        r'would be wrong. The daemon’s own probe in procs.rs, which '
        r'uses the same IsWow64Process2 call, is more careful: it '
        r'reports "x86" only for the WOW64 case and "unknown" otherwise. '
        r'I have no evidence the project was ever run on ARM64, so this '
        r'is an observation about the code, not a bug anyone hit. The '
        r'Flutter picker adds a third line of defence by showing '
        r'non-x64 processes disabled with an explanation, so most users '
        r'never reach this message.'),
    ...sec(r'minimal rights, and no second try'),
    ...code('rust', 'crates/heaplens-injector/src/main.rs · the rights', r'''
        let rights = PROCESS_CREATE_THREAD | PROCESS_VM_OPERATION | PROCESS_VM_WRITE | PROCESS_VM_READ | PROCESS_QUERY_INFORMATION;
        let handle = unsafe { OpenProcess(rights, 0, pid) };
        if handle.is_null() {
            fail(format!(
                "access denied opening process {pid} — try running HeapLens as Administrator"
            ));
        }
        RemoteProcess { handle, pid }'''),
    ...para('//',
        r'The five rights are exactly the verbs the sequence uses: '
        r'create a thread, allocate, write and read memory, and query. '
        r'ReadProcessMemory is there for the detach mailbox, '
        r'PROCESS_VM_OPERATION for VirtualAllocEx and VirtualFreeEx. The '
        r'doc comment on the function states the policy as a promise: it '
        r'"never requests PROCESS_ALL_ACCESS and never attempts '
        r'elevation", and a failed OpenProcess "is reported as an '
        r'access-denied condition, not retried with broader rights". '
        r'The design document calls this "a deliberate security '
        r'boundary": if the user needs elevation, they re-launch '
        r'HeapLens elevated themselves.'),
    ...sec(r'a remote thread with a deadline'),
    ...code('rust', 'crates/heaplens-injector/src/main.rs · run_remote_thread', r'''
    fn run_remote_thread(&self, start_addr: *const c_void, param: *mut c_void) -> Result<u32, String> {
        let start: LPTHREAD_START_ROUTINE = Some(unsafe { std::mem::transmute::<*const c_void, unsafe extern "system" fn(*mut c_void) -> u32>(start_addr) });
        let mut tid = 0u32;
        let thread = unsafe {
            CreateRemoteThread(self.handle, std::ptr::null(), 0, start, param, 0, &mut tid)
        };
        if thread.is_null() {
            return Err(format!("CreateRemoteThread failed in process {}", self.pid));
        }
        let wait = unsafe { WaitForSingleObject(thread, REMOTE_THREAD_TIMEOUT_MS) };
        if wait != 0 {
            unsafe { CloseHandle(thread) };
            return Err(format!(
                "remote thread in process {} did not complete within {REMOTE_THREAD_TIMEOUT_MS}ms — \
                 target may have exited or hung",
                self.pid
            ));
        }
        let mut exit_code = 0u32;
        let ok = unsafe { GetExitCodeThread(thread, &mut exit_code) };
        unsafe { CloseHandle(thread) };
        if ok == 0 {
            return Err(format!("GetExitCodeThread failed in process {}", self.pid));
        }
        Ok(exit_code)
    }'''),
    ...para('//',
        r'Every remote call in the file goes through this function, and '
        r'its shape is a small lesson in not trusting another process. '
        r'The wait is bounded at 10 seconds (REMOTE_THREAD_TIMEOUT_MS) '
        r'because the target is somebody else’s program and may be '
        r'suspended, hung or gone. The failure message says as much: '
        r'"target may have exited or hung". The thread’s exit code is '
        r'the return channel, which is why the hook’s attach function '
        r'returns a u32 and why HeapLensHookAttachRemote ends in '
        r'TerminateThread(GetCurrentThread(), result): the exit code '
        r'is how success or the specific failure number gets out.'),
    blank,
    ...para('//',
        r'The weakness of an exit code is its width. A thread start '
        r'routine returns a 32-bit value, and the module handle that '
        r'LoadLibraryW returns is a 64-bit pointer. The next function '
        r'exists because of that, and the attach code ignores the exit '
        r'code of the load thread entirely.'),
    ...sec(r'the module list is the source of truth'),
    ...code('rust', 'crates/heaplens-injector/src/main.rs · find_module_base', r'''
    /// Finds `heaplens_hook.dll`'s loaded base address in the target, if
    /// present. Used both to confirm a `LoadLibraryW` actually landed (its
    /// own thread exit code truncates to 32 bits on x64 and can't be
    /// trusted as a full pointer) and, on detach, to find the module to
    /// unload.
    fn find_module_base(&self) -> Option<*mut u8> {
        let snap = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, self.pid) };
        if snap.is_null() {
            return None;
        }
        let mut entry: MODULEENTRY32W = unsafe { std::mem::zeroed() };
        entry.dwSize = std::mem::size_of::<MODULEENTRY32W>() as u32;
        let mut found = None;
        let mut ok = unsafe { Module32FirstW(snap, &mut entry) };
        while ok != 0 {
            let name_len = entry.szModule.iter().position(|&c| c == 0).unwrap_or(entry.szModule.len());
            let name = String::from_utf16_lossy(&entry.szModule[..name_len]);
            if name.eq_ignore_ascii_case(DLL_NAME) {
                found = Some(entry.modBaseAddr);
                break;
            }
            ok = unsafe { Module32NextW(snap, &mut entry) };
        }
        unsafe { CloseHandle(snap) };
        found
    }'''),
    ...para('//',
        r'The doc comment names the two uses: to "confirm a '
        r'LoadLibraryW actually landed (its own thread exit code '
        r'truncates to 32 bits on x64 and can’t be trusted as a full '
        r'pointer)", and on detach to find the module. It is also the '
        r'idempotence check and the base address for every offset '
        r'calculation, so a Toolhelp module snapshot answers four '
        r'questions: is it loaded, did loading work, where is it, and '
        r'is there anything to detach. The comparison is '
        r'case-insensitive, since Windows file names are.'),
    ...sec(r'computing an address in a process you cannot ask'),
    ...code('rust', 'crates/heaplens-injector/src/main.rs · resolve_offset and the kernel32 address', r'''
/// Loads `path` locally (in this injector's own process) purely to resolve
/// `proc_name`'s offset from the DLL's base — a DLL's internal layout
/// (RVA offsets) is identical across processes loading the same file, so
/// `local_addr - local_base` applied to the target's own load base gives
/// the correct address in the target, without needing the DLL to already
/// be loaded remotely to inspect it.
fn resolve_offset(path: &Path, proc_name: &str) -> Result<(usize, isize), String> {
    let wpath = to_wide(path.to_str().ok_or("dll path is not valid UTF-8")?);
    let local = unsafe { LoadLibraryW(wpath.as_ptr()) };
    if local.is_null() {
        return Err(format!("failed to locally load {path:?} to resolve exports"));
    }
    let cname = format!("{proc_name}\0");
    let proc = unsafe { GetProcAddress(local, cname.as_ptr()) };
    let Some(proc) = proc else {
        unsafe { FreeLibrary(local) };
        return Err(format!("export {proc_name} not found in {path:?}"));
    };
    let offset = proc as usize as isize - local as usize as isize;
    unsafe { FreeLibrary(local) };
    Ok((local as usize, offset))
}

fn load_library_w_addr() -> *const c_void {
    let kernel32 = to_wide("kernel32.dll");
    let h = unsafe { GetModuleHandleW(kernel32.as_ptr()) };
    let proc = unsafe { GetProcAddress(h, b"LoadLibraryW\0".as_ptr()) };
    proc.expect("LoadLibraryW must be resolvable in kernel32.dll") as *const c_void
}'''),
    ...para('//',
        r'The technique is the file’s most interesting trick. To call an '
        r'export of the hook DLL inside the target, the injector needs '
        r'its address there, and the target cannot be asked. But a DLL’s '
        r'internal layout is identical wherever the same file is '
        r'loaded, so loading the DLL in the injector itself, resolving '
        r'the export locally, and subtracting the local base gives a '
        r'relative offset that is valid for any copy. The call site '
        r'adds the offset to the target’s base, found from the module '
        r'list:'),
    ...code('rust', 'crates/heaplens-injector/src/main.rs · call_exported_fn', r'''
fn call_exported_fn(remote: &RemoteProcess, dll: &Path, export: &str) {
    let target_base = remote.find_module_base().unwrap_or_else(|| {
        fail(format!("{DLL_NAME} not found in process {}'s module list", remote.pid))
    });
    let (local_base, offset) = resolve_offset(dll, export).unwrap_or_else(|e| fail(e));
    let target_addr = (target_base as isize + offset) as *const c_void;
    let _ = local_base;

    match remote.run_remote_thread(target_addr, std::ptr::null_mut()) {
        Ok(rc) => report_hook_rc(export, rc, remote.pid),
        Err(e) => fail(e),
    }
}'''),
    ...para('//',
        r'LoadLibraryW itself needs no such arithmetic. The comment on '
        r'run_remote_thread says a start address must be valid "in the '
        r'target’s address space", either "a system-DLL export shared at '
        r'the same base across processes, like LoadLibraryW" or an '
        r'address computed from an offset. That first case is the '
        r'standing assumption of classic injection, that kernel32 is '
        r'mapped at the same address in every process of the same '
        r'architecture on a given boot, and load_library_w_addr reads '
        r'the address from the injector’s own kernel32.'),
    blank,
    ...para('//',
        r'Two small costs are worth knowing. Loading the hook DLL into '
        r'the injector runs the DLL’s own load-time code in the '
        r'injector’s process (no hook is installed, because nothing '
        r'calls attach there), and it is freed at once with '
        r'FreeLibrary. Detach does this three times, for WORKER_TID, '
        r'HeapLensHookDetachApc and DETACH_RESULT. Also, the doc '
        r'comment on run_remote_thread mentions an address computed via '
        r'"local_offset_to_remote". There is no function of that name; '
        r'the arithmetic is inline above. I read it as a name that '
        r'survived from an earlier draft.'),
    ...sec(r'attach, line by line'),
    ...code('rust', 'crates/heaplens-injector/src/main.rs · attach, the refusal and the idempotent path', r'''
fn attach(pid: u32) {
    // Hard exclusion (2026-07-22): refuse before requesting any
    // injection-capable rights on the target — see safety.rs's module doc
    // comment for the three signals checked and why. This is unconditional;
    // there is deliberately no override flag. (Each check's own message
    // already names the pid and says "refusing" — nothing to add here.)
    if let Err(reason) = safety::check(pid) {
        fail(reason);
    }

    let dll = dll_path();
    if !dll.exists() {
        fail(format!("{DLL_NAME} not found at {dll:?} — expected next to heaplens-injector.exe"));
    }
    let remote = RemoteProcess::open(pid);

    if remote.find_module_base().is_some() {
        // Already loaded in this target — HeapLensHookAttach is itself
        // idempotent, so just call it again rather than re-injecting. Uses
        // the `Remote` entry point (see its doc comment in heaplens-hook):
        // hooks may already be active from a prior successful attach, so
        // this raw thread must never return normally.
        println!("heaplens-injector: {DLL_NAME} already loaded in process {pid}, re-invoking attach");
        call_exported_fn(&remote, &dll, "HeapLensHookAttachRemote");
        return;
    }'''),
    ...para('//',
        r'Three decisions are visible. First, the safety check is '
        r'unconditional and first. The comment dates it (2026-07-22) '
        r'and says "there is deliberately no override flag". There is '
        r'no --force in main() either. Second, the DLL must exist next '
        r'to the executable before any injection-capable handle is '
        r'requested, so the cheapest failure comes before real contact '
        r'with the target. Third, if '
        r'the module is already loaded, attach does not load it again; '
        r'it calls the Remote entry point again, which is itself '
        r'idempotent. The comment explains the choice of the Remote '
        r'variant here: hooks "may already be active from a prior '
        r'successful attach, so this raw thread must never return '
        r'normally".'),
    ...code('rust', 'crates/heaplens-injector/src/main.rs · attach, the load (trimmed)', r'''
    // Write the DLL path (wide, null-terminated) into the target so
    // LoadLibraryW can read it there.
    let wpath = to_wide(dll.to_str().unwrap_or_else(|| fail("dll path is not valid UTF-8")));
    let byte_len = wpath.len() * 2;
    let remote_buf = unsafe {
        VirtualAllocEx(remote.handle, std::ptr::null(), byte_len, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE)
    };
    if remote_buf.is_null() {
        fail(format!("VirtualAllocEx failed in process {pid}"));
    }
    let mut written = 0usize;
    let ok = unsafe {
        WriteProcessMemory(remote.handle, remote_buf, wpath.as_ptr() as *const c_void, byte_len, &mut written)
    };
    if ok == 0 || written != byte_len {
        unsafe { VirtualFreeEx(remote.handle, remote_buf, 0, MEM_RELEASE) };
        fail(format!("WriteProcessMemory failed writing the DLL path into process {pid}"));
    }

    let load_library_w = load_library_w_addr();
    match remote.run_remote_thread(load_library_w, remote_buf) {
        Ok(_) => {}
        Err(e) => {
            unsafe { VirtualFreeEx(remote.handle, remote_buf, 0, MEM_RELEASE) };
            fail(e);
        }
    }
    unsafe { VirtualFreeEx(remote.handle, remote_buf, 0, MEM_RELEASE) };

    if remote.find_module_base().is_none() {
        fail(format!("LoadLibraryW ran in process {pid} but {DLL_NAME} is not present in its module list — load failed"));
    }

    // `Remote`, not the plain `HeapLensHookAttach` — this call runs on a
    // fresh `CreateRemoteThread` thread that must never return normally
    // once hooks go live partway through it (see heaplens-hook's doc
    // comment on `HeapLensHookAttachRemote`). Self-load's harness is the
    // only caller of the plain, direct-return `HeapLensHookAttach`.
    call_exported_fn(&remote, &dll, "HeapLensHookAttachRemote");
}'''),
    ...para('//',
        r'Notice the cleanup discipline. The remote buffer is allocated '
        r'MEM_COMMIT | MEM_RESERVE with PAGE_READWRITE (a '
        r'read-write page, never executable: the path is data, the code '
        r'is LoadLibraryW already in the process) and it is released on '
        r'every exit, including both error branches. A short write is '
        r'an error, since the check compares written to the byte '
        r'length. After the load thread returns, success is judged by '
        r'the module list and not by the thread’s result. And the call '
        r'that matters, the last line, is to HeapLensHookAttachRemote '
        r'and not to the plain HeapLensHookAttach, for the reason the '
        r'comment above it gives: this call runs on a fresh remote '
        r'thread "that must never return normally once hooks go live '
        r'partway through it". The self-load harnesses are the only '
        r'callers of the plain export.'),
    ...sec(r'return codes are a contract with sentences'),
    ...code('rust', 'crates/heaplens-injector/src/main.rs · report_hook_rc', r'''
fn report_hook_rc(export: &str, rc: u32, pid: u32) {
    if rc == 0 {
        println!("heaplens-injector: {export} succeeded in process {pid}");
        return;
    }
    let detail = match (export, rc) {
        ("HeapLensHookAttachRemote", 1) => "private heap creation (HeapCreate) failed",
        ("HeapLensHookAttachRemote", 2) => "MinHook::create_hook_api failed for RtlAllocateHeap",
        ("HeapLensHookAttachRemote", 3) => "MinHook::create_hook_api failed for RtlReAllocateHeap",
        ("HeapLensHookAttachRemote", 4) => "MinHook::create_hook_api failed for RtlFreeHeap",
        ("HeapLensHookAttachRemote", 5) => "MinHook::enable_all_hooks failed",
        ("HeapLensHookAttachRemote", 7) => "trampoline canary check failed after enabling hooks — \
             hooks were disabled and torn down automatically; the hook was not left resident",
        ("HeapLensHookDetach", 6) => "writer thread did not stop within the detach timeout — \
             hooks were disabled but trampolines/private heap were left in place rather than \
             risk freeing memory a still-running thread depends on; detach did not fully complete",
        _ => "unknown failure code",
    };
    fail(format!("{export} in process {pid} returned failure code {rc}: {detail}"));
}'''),
    ...para('//',
        r'This function is the other half of lib.rs’s return codes, and '
        r'the pairing is by number. 1 is the private heap, 2, 3 and 4 '
        r'are the three hooks, 5 is enable, 7 is the canary. The match '
        r'key is the pair (export, code), because the same number means '
        r'different things for different exports: 6 is reported only '
        r'for the detach export, where it means the writer thread did '
        r'not stop in time.'),
    blank,
    ...para('//',
        r'Two of the messages promise something specific about the '
        r'state left behind, and that is what makes them useful. The '
        r'canary message says "the hook was not left resident". The '
        r'detach message for 6 says the trampolines and private heap '
        r'"were left in place rather than risk freeing memory a '
        r'still-running thread depends on; detach did not fully '
        r'complete". A user or a calling program can act on those '
        r'sentences. A code with no entry, including the u32::MAX that '
        r'lib.rs returns when it cannot spawn the worker or receive its '
        r'answer, falls to "unknown failure code".'),
    blank,
    ...para('//',
        r'The weakness of the design is the one I flagged at the top. '
        r'The numbers are duplicated across two crates, joined by '
        r'nothing the compiler checks. Adding an eighth code to the hook '
        r'without touching this match would compile cleanly and print '
        r'"unknown failure code". Neither crate has a test that ties '
        r'the two tables together.'),
    ...sec(r'detach: no new thread, one APC, one mailbox'),
    ...para('//',
        r'The doc comment on detach() carries the whole argument, and '
        r'the lib.rs page has the other half of it. In short, a second '
        r'CreateRemoteThread while the hooks are live makes the OS '
        r'notify every DLL of the new thread, and that notification’s '
        r'own heap traffic re-enters the active detour on a thread '
        r'that the runtime never prepared. So the injector queues an '
        r'APC onto the hook’s parked worker instead. It starts by '
        r'finding that worker and the mailbox, both exported statics. '
        r'Note that detach() does not call safety::check; only attach '
        r'does, so a process can always be detached from.'),
    ...code('rust', 'crates/heaplens-injector/src/main.rs · detach, locating the worker and the mailbox', r'''
    let remote = RemoteProcess::open(pid);

    let Some(target_base) = remote.find_module_base() else {
        println!("heaplens-injector: {DLL_NAME} not loaded in process {pid} — nothing to detach");
        return;
    };

    let (_, tid_offset) = resolve_offset(&dll, "WORKER_TID").unwrap_or_else(|e| fail(e));
    let tid_addr = (target_base as isize + tid_offset) as *const c_void;
    let worker_tid = read_remote_i32(&remote, tid_addr).unwrap_or_else(|e| fail(e)) as u32;
    if worker_tid == 0 {
        fail(format!(
            "process {pid} has {DLL_NAME} loaded but no attach worker thread is recorded — \
             was HeapLensHookAttach ever called successfully in this process?"
        ));
    }

    let (_, apc_offset) = resolve_offset(&dll, "HeapLensHookDetachApc").unwrap_or_else(|e| fail(e));
    let apc_addr = (target_base as isize + apc_offset) as usize;
    let apc_fn: unsafe extern "system" fn(usize) = unsafe { std::mem::transmute(apc_addr) };

    let (_, result_offset) = resolve_offset(&dll, "DETACH_RESULT").unwrap_or_else(|e| fail(e));
    let result_addr = (target_base as isize + result_offset) as *mut c_void;'''),
    ...para('//',
        r'There is a guard with a helpful message for the case the '
        r'file is loaded but attach never ran: a worker id of zero '
        r'produces "was HeapLensHookAttach ever called successfully in '
        r'this process?". The statics are read with ReadProcessMemory '
        r'and are four bytes wide, which the function comment notes '
        r'"matches AtomicU32/AtomicI32’s layout".'),
    ...code('rust', 'crates/heaplens-injector/src/main.rs · detach, queue and poll', r'''
    // Reset the sentinel before queuing so a stale value from a prior
    // attach/detach cycle in this same process can't be mistaken for this
    // call's result.
    let pending: i32 = -1;
    let mut written = 0usize;
    let ok = unsafe {
        WriteProcessMemory(remote.handle, result_addr, &pending as *const i32 as *const c_void, 4, &mut written)
    };
    if ok == 0 || written != 4 {
        fail(format!("failed to reset detach-result sentinel in process {pid}"));
    }

    let worker_thread = unsafe { OpenThread(THREAD_SET_CONTEXT, 0, worker_tid) };
    if worker_thread.is_null() {
        fail(format!("OpenThread failed for worker thread {worker_tid} in process {pid}"));
    }
    let queued = unsafe { QueueUserAPC(Some(apc_fn), worker_thread, 0) };
    unsafe { CloseHandle(worker_thread) };
    if queued == 0 {
        fail(format!("QueueUserAPC failed for process {pid}'s attach worker thread"));
    }

    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let rc = loop {
        let v = read_remote_i32(&remote, result_addr).unwrap_or_else(|e| fail(e));
        if v != -1 {
            break v as u32;
        }
        if std::time::Instant::now() >= deadline {
            fail(format!("detach in process {pid} did not complete within 5s"));
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    };
    if rc != 0 {
        report_hook_rc("HeapLensHookDetach", rc, pid);
        return;
    }
    println!("heaplens-injector: HeapLensHookDetach succeeded in process {pid}");'''),
    ...para('//',
        r'The order is deliberate. The result word is reset to the -1 '
        r'sentinel before the APC is queued, with a comment saying '
        r'why: so a stale value from a prior cycle in the same process '
        r'cannot be mistaken for this call’s result. Only then is the '
        r'worker opened, with the narrowest right that allows '
        r'QueueUserAPC, THREAD_SET_CONTEXT, and the APC queued. The '
        r'handle is closed immediately; the APC has been delivered '
        r'to the kernel’s queue. Then polling: every 20 ms, for up to '
        r'5 seconds, read the word and stop when it is not -1.'),
    blank,
    ...para('//',
        r'The two time limits are consistent with each other. The hook '
        r'gives the writer thread 2 seconds to stop, then does a little '
        r'teardown, so a clean detach finishes well inside the 5 '
        r'seconds, and a detach where the writer hangs reports its '
        r'failure code 6 inside the window too. Only a detach that '
        r'never publishes anything, for instance because the worker '
        r'thread no longer exists, runs the poll out, and that is '
        r'reported as "did not complete within 5s".'),
    ...code('rust', 'crates/heaplens-injector/src/main.rs · detach, unload (trimmed)', r'''
    // Unload the DLL from the target now that it has cleanly detached.
    let kernel32 = to_wide("kernel32.dll");
    let h = unsafe { GetModuleHandleW(kernel32.as_ptr()) };
    let free_library = unsafe { GetProcAddress(h, b"FreeLibrary\0".as_ptr()) }
        .unwrap_or_else(|| fail("FreeLibrary must be resolvable in kernel32.dll"));
    match remote.run_remote_thread(free_library as *const c_void, target_base as *mut c_void) {
        Ok(rc) if rc != 0 => println!("heaplens-injector: {DLL_NAME} unloaded from process {pid}"),
        Ok(_) => fail(format!("FreeLibrary returned failure unloading {DLL_NAME} from process {pid}")),
        Err(e) => fail(e),
    }
}'''),
    ...para('//',
        r'Only after a clean 0 does the injector unload the DLL, by '
        r'running FreeLibrary in the target on the base address it '
        r'found at the start. FreeLibrary’s own result is the thread’s '
        r'exit code, a BOOL, so the match reads the nonzero case as '
        r'success, the reverse of the convention for the hook’s own '
        r'codes. If the hook returned any failure code, the function '
        r'ends in report_hook_rc, which exits, so the DLL stays loaded '
        r'with whatever state the failed detach left. That is the safe '
        r'direction: unloading code that a stuck thread might still run '
        r'is the thing the hook’s return 6 exists to prevent.'),
    ...sec(r'main'),
    ...code('rust', 'crates/heaplens-injector/src/main.rs · main', r'''
fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 3 {
        eprintln!("usage: heaplens-injector <pid> --attach|--detach");
        std::process::exit(2);
    }
    let pid: u32 = args[1].parse().unwrap_or_else(|_| fail(format!("invalid pid: {}", args[1])));
    match args[2].as_str() {
        "--attach" => attach(pid),
        "--detach" => detach(pid),
        other => fail(format!("unknown mode {other:?}; expected --attach or --detach")),
    }
}'''),
    ...para('//',
        r'Exactly three arguments or a usage line and exit code 2. A '
        r'non-numeric pid and an unknown mode both go through fail(), '
        r'so they also exit with 1 and a message. There is no '
        r'parsing library and no flag for skipping a check, which is '
        r'the point.'),
    ...sec(r'what the design promised, and what the code does'),
    ...para('//',
        r'Section 3.3 of the design document lists three validations to '
        r'run before touching a target. This is how each landed:'),
    ...pt('//', r'architecture match',
        r'implemented as specified, with IsWow64Process2 on a '
        r'query-only handle and the specified sentence.'),
    ...pt('//', r'access',
        r'implemented as specified: minimal rights, a message that '
        r'suggests Administrator, no elevation attempt, no retry.'),
    ...pt('//', r'target still running',
        r'handled through the live handle: operations on an exited '
        r'process fail, and the failures read "did not complete within '
        r'10000ms" or "WriteProcessMemory failed", not "internal '
        r'error". The design called the race "small but real" for PID '
        r'reuse; the handle closes the window after the open, not '
        r'before it (see limits).'),
    ...pt('//', r'the fourth check, added later',
        r'safety.rs, 2026-07-22, which the design did not contain. It '
        r'refuses processes with driver components, and is the reason '
        r'the commit that landed it could re-enable the attach button.'),
    blank,
    ...para('//',
        r'The Step 2 acceptance gate in the design asks that the three '
        r'validation paths "each produce the specified error message '
        r'rather than crashing the injector or the target". I found no '
        r'automated test that drives those paths: the crate has no '
        r'tests, and the daemon’s hook tests all attach to a healthy '
        r'child. Commit 864167e reports a live run of the refusal path '
        r'against Windows Defender and a clean attach and detach against '
        r'Notepad. The earlier validation across three kinds of real '
        r'target (native Win32, Electron/Chromium, Node.js/V8) is '
        r'stated in the same message, along with a continuous soak of '
        r'about 2 hours and 10 minutes against a real Node.js process.'),
    ...sec(r'limits and open questions'),
    ...pt('//', r'the verdict and the open are separate lookups',
        r'safety::check(pid) judges a pid, and RemoteProcess::open '
        r'opens the pid again afterwards. If that pid is reused by '
        r'another process between the two calls, the verdict applies '
        r'to the wrong process. The window is tiny and I know of no '
        r'occurrence. The design’s own live-handle argument covers '
        r'the time after the open only.'),
    ...pt('//', r'timeouts leave the remote thread running',
        r'on a 10-second timeout the handle is closed and the thread '
        r'is not terminated. That is the right call for a thread '
        r'that might be inside the hook, but it means a timeout '
        r'does not tell you what state the target is in.'),
    ...pt('//', r'a hung target defeats detach',
        r'commit deff3ad found that against a hung multi-threaded '
        r'target the detach fails with "OpenThread failed for worker '
        r'thread", because the parked worker is gone or invalid. The '
        r'tool has no fallback beyond reporting it, and a hang whose '
        r'cause was a lock in the hook was later fixed at its source '
        r'instead (b5c5aed).'),
    ...pt('//', r'the offset trick assumes the file is the image',
        r'offsets come from the file on disk, applied to the loaded '
        r'copy. Windows will not overwrite a DLL while a process has it '
        r'loaded, so the assumption is safe in practice, but the '
        r'injector does not verify it.'),
    ...pt('//', r'toolhelp failure is tested against null',
        r'CreateToolhelp32Snapshot reports failure with '
        r'INVALID_HANDLE_VALUE, which is not a null pointer, so the '
        r'snap.is_null() guards here and in safety.rs would not '
        r'fire. The effect is benign, because the first Module32FirstW '
        r'on a bad handle fails and the loops do not run, so the '
        r'function returns "not found". It is worth knowing because '
        r'the guard reads as if it handled the error.'),
    ...pt('//', r'x64 only, by design',
        r'ARM64 and 32-bit targets are refused; see the architecture '
        r'section for the message that is wrong on ARM64.'),
    ...pt('//', r'no tests of its own',
        r'the crate has no #[test]. Everything runs through the '
        r'daemon’s hook_owner_free_no_crash tests, whose '
        r'spawn_and_attach helper runs the real injector binary, and '
        r'through live use.'),
    ...sec(r'what to take from it'),
    ...pt('//', r'ask before you act',
        r'the safety verdict, the file check, a query-only '
        r'architecture probe, and only then the rights that can change '
        r'another process.'),
    ...pt('//', r'verify by a second source',
        r'the load thread’s exit code is not trusted; the module list '
        r'is read instead.'),
    ...pt('//', r'make messages carry state',
        r'"the hook was not left resident" is a promise a caller can '
        r'rely on; "failed" is not.'),
    ...pt('//', r'prefer not to create what you cannot make safe',
        r'detach reuses a thread that exists instead of creating one '
        r'that would trigger the hazard.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-injector/src/main.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-injector/src/main.rs'),
  ],
);
