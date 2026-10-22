import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/src/procs.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'procs.rs — the list behind the attach picker'),
    cm('//', r'a toolhelp snapshot, one OpenProcess per row, and a promise never to drop a process for being unreadable'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'enumerate running processes (pid, exe name, architecture) for the attach-target picker'),
    kv('language', r'Rust, Win32 through windows-sys'),
    kv('size', r'68 lines, one commit: 724695a (2026-07-19), never edited since'),
    kv('public API', r'list_processes() -> Vec<ProcessInfo>'),
    kv('called from', r'the TargetCmd::ListProcesses arm of main.rs, inside tokio::task::spawn_blocking'),
    ...sec(r'why it exists'),
    ...para('//',
        r'Attaching to a running program starts with choosing one. The Flutter client has a process-picker dialog; when it opens it sends a ListProcesses control request over the WebSocket, and whatever list comes back is what the user can pick from. This file builds that list. The module comment ties it to the design: "process enumeration for the attach-target picker. Windows-only, same toolhelp-snapshot technique heaplens-injector already uses to find a loaded module."'),
    blank,
    ...para('//',
        r'The row type, ProcessInfo { pid, name, arch }, is not defined here: it comes from heaplens-protocol, so the same struct serialises to JSON for the UI and is the return type of the TargetCmd::ListProcesses reply channel.'),
    blank,
    ...sec(r'probing the architecture'),
    ...code('rust', r'crates/heaplens-daemon/src/procs.rs · lines 1-39', r'''
//! Stage 7 Step 3 (docs/stage7-injection-design.md §3): process enumeration
//! for the attach-target picker. Windows-only, same toolhelp-snapshot
//! technique `heaplens-injector` already uses to find a loaded module.

use windows_sys::Win32::Foundation::CloseHandle;
use windows_sys::Win32::System::Diagnostics::ToolHelp::{
    CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W, TH32CS_SNAPPROCESS,
};
use windows_sys::Win32::System::SystemInformation::{IMAGE_FILE_MACHINE_AMD64, IMAGE_FILE_MACHINE_UNKNOWN};
use windows_sys::Win32::System::Threading::{IsWow64Process2, OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION};

use heaplens_protocol::ProcessInfo;

/// Best-effort architecture probe. `OpenProcess` legitimately fails for
/// protected/elevated/system processes the daemon has no rights to query —
/// that is reported as `"unknown"`, not treated as an enumeration failure
/// (dropping the process from the list would be worse: the user could never
/// see, let alone attach to, anything they don't already have rights to).
fn probe_arch(pid: u32) -> String {
    let handle = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid) };
    if handle.is_null() {
        return "unknown".to_owned();
    }
    let mut process_machine = 0u16;
    let mut native_machine = 0u16;
    let ok = unsafe { IsWow64Process2(handle, &mut process_machine, &mut native_machine) };
    unsafe { CloseHandle(handle) };
    if ok == 0 {
        return "unknown".to_owned();
    }
    if process_machine != IMAGE_FILE_MACHINE_UNKNOWN {
        // Running under WOW64 emulation — a 32-bit process on this 64-bit system.
        "x86".to_owned()
    } else if native_machine == IMAGE_FILE_MACHINE_AMD64 {
        "x64".to_owned()
    } else {
        "unknown".to_owned()
    }
}'''),
    ...para('//',
        r'probe_arch reports an architecture string per process (the code does not say why the picker wants it; the module comment only says best-effort). It works in three steps.'),
    blank,
    ...pt('//', r'OpenProcess with PROCESS_QUERY_LIMITED_INFORMATION',
        r'the weakest access right that still lets IsWow64Process2 answer. A null handle means the daemon is not allowed to look, which happens for protected, elevated and system processes.'),
    ...pt('//', r'IsWow64Process2',
        r'fills in two machine codes. If the process machine is anything but IMAGE_FILE_MACHINE_UNKNOWN, the process runs under WOW64 emulation and is reported as "x86". If it is unknown (meaning not emulated) and the native machine is AMD64, it is "x64".'),
    ...pt('//', r'everything else',
        r'a failed call, or a non-AMD64 host, gives "unknown". There is no "arm64" label, so on an ARM Windows host every native process would read as "unknown".'),
    ...para('//',
        r'CloseHandle is called straight after the query, before the result is inspected, so there is no path that leaks the handle.'),
    blank,
    ...sec(r'the decision in the doc comment'),
    ...para('//',
        r'The comment above probe_arch carries the one design decision in the file. An unreadable process is reported as "unknown" and kept, because "dropping the process from the list would be worse: the user could never see, let alone attach to, anything they don’t already have rights to." The alternative would be filtering the list down to what can be probed; the comment rejects that. Keeping the row means a later attach attempt on it is still possible, and any failure would come back as the injector’s own message.'),
    blank,
    ...sec(r'walking the snapshot'),
    ...code('rust', r'crates/heaplens-daemon/src/procs.rs · lines 40-68', r'''

/// Lists every running process visible to a `CreateToolhelp32Snapshot`
/// snapshot, with a best-effort architecture probe per process. Never
/// panics on a single process's probe failure — an inaccessible or
/// already-exited process is reported with `arch: "unknown"`, not dropped
/// or fatal to the whole call.
pub fn list_processes() -> Vec<ProcessInfo> {
    let snap = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) };
    if snap.is_null() {
        return Vec::new();
    }

    let mut entry: PROCESSENTRY32W = unsafe { std::mem::zeroed() };
    entry.dwSize = std::mem::size_of::<PROCESSENTRY32W>() as u32;

    let mut out = Vec::new();
    let mut ok = unsafe { Process32FirstW(snap, &mut entry) };
    while ok != 0 {
        let name_len = entry.szExeFile.iter().position(|&c| c == 0).unwrap_or(entry.szExeFile.len());
        let name = String::from_utf16_lossy(&entry.szExeFile[..name_len]);
        let pid = entry.th32ProcessID;
        if pid != 0 {
            out.push(ProcessInfo { pid, name, arch: probe_arch(pid) });
        }
        ok = unsafe { Process32NextW(snap, &mut entry) };
    }
    unsafe { CloseHandle(snap) };
    out
}'''),
    ...pt('//', r'CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)',
        r'one atomic copy of the process table. Everything after it works on that copy, so a process that exits during the loop still appears with whatever the snapshot recorded, and the later OpenProcess for it simply fails, which probe_arch turns into "unknown". This is why the doc comment promises "an inaccessible or already-exited process is reported with arch: unknown, not dropped or fatal to the whole call".'),
    ...pt('//', r'PROCESSENTRY32W zeroed, then dwSize set',
        r'the Win32 contract: the structure’s size field must be filled in before Process32FirstW, or the call fails.'),
    ...pt('//', r'the name',
        r'szExeFile is a fixed UTF-16 array; the code finds the first zero with position and decodes up to it with from_utf16_lossy, so an unpaired surrogate becomes a replacement character instead of a panic.'),
    ...pt('//', r'pid 0 is skipped',
        r'the code skips it without saying why; pid 0 is the System Idle Process pseudo-entry on Windows.'),
    ...pt('//', r'Process32NextW',
        r'the loop continues while it returns non-zero. CloseHandle on the snapshot ends it.'),
    ...para('//',
        r'The function is synchronous and makes up to one OpenProcess per process, so main.rs does not call it on the graph task. Its comment: "Process enumeration does per-process OpenProcess/IsWow64Process2 syscalls (procs.rs) — run it off this task so a slow system doesn’t stall the graph loop’s other work." It wraps the call in tokio::task::spawn_blocking and uses unwrap_or_default on the join result, so a panicked blocking task yields an empty list rather than killing the loop.'),
    blank,
    ...sec(r'a bug I noticed'),
    ...para('//',
        r'procs.rs:48 checks the failure of CreateToolhelp32Snapshot with snap.is_null(). That API reports failure by returning INVALID_HANDLE_VALUE, which is -1 and not null, so the early return to an empty Vec never fires. If the snapshot call fails, the code would go on to call Process32FirstW with the invalid handle, which fails and yields an empty list through the while loop not running, and then CloseHandle is called on the invalid value. In practice the result is the same empty list, so it is a harmless wrong check rather than a crash, but the intended guard does not guard anything. OpenProcess, by contrast, does return null on failure, so the check at line 21 is right.'),
    blank,
    ...sec(r'edge cases'),
    ...pt('//', r'Duplicates and ordering',
        r'the list is in snapshot order, not sorted and not de-duplicated. Many processes share an exe name; the pid is the identity. The Rust side does no sorting.'),
    ...pt('//', r'The daemon itself',
        r'it is not filtered out, so the user can see the daemon in the picker.'),
    ...pt('//', r'Permissions',
        r'a daemon started without elevation will see many system processes as "unknown".'),
    ...pt('//', r'WOW64 label',
        r'"x86" is any emulated process, not specifically a 32-bit x86 one.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'There is no automated test: nothing under crates/heaplens-daemon/tests calls list_processes, and ws_tests.rs builds its test server with a target_tx whose receiver (_target_rx) nothing reads, so a ListProcesses request would never reach this code. The evidence of it working is the commit message of 724695a: "live end-to-end — process picker populates, real attach/detach against a live process". The repository has no such test.'),
    blank,
    ...sec(r'history'),
    ...para('//',
        r'One commit, 724695a (2026-07-19), when the Stage 7 control protocol was ported so the already-built picker dialog would work.'),
    blank,
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/src/procs.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/src/procs.rs'),
  ],
);
