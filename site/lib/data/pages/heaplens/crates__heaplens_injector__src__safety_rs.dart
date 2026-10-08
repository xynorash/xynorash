import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-injector/src/safety.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'safety.rs — a rule the operator used to remember, now a function'),
    cm('//', r'three read-only signals, any one of them says no, the strongest fails closed'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'pre-attach exclusion check: refuse driver-bearing processes'),
    kv('language', r'Rust over windows-sys (Toolhelp snapshots, process info)'),
    kv('size', r'263 lines, the first 49 of them module documentation'),
    kv('history', r'one commit, 864167e, 2026-07-22 11:14 +0300'),
    kv('data', r'60 process names (23 VPN, 9 anti-cheat, 17 security, 11 virtualization), 5 module names'),
    kv('tests', r'none; verified live, see below'),
    ...sec(r'the problem: from a habit to a guarantee'),
    ...para('//',
        r'By 2026-07-21 the project could attach to almost any process on '
        r'a Windows machine, and the cost of a mistake was another '
        r'person’s program. The record from that evening is on '
        r'the lib.rs page: a stress harness that crashed the hook, a '
        r'real process that crashed inside the hook DLL, and, minutes '
        r'later on the same machine, a kernel bugcheck. The repository '
        r'notes the adjacency and does not claim a cause. What it did '
        r'before this file existed was rely on discipline. The stress '
        r'harness states the rule that testing followed: its '
        r'constraint is "example producers only, or a disposable VM" '
        r'for cross-process testing.'),
    blank,
    ...para('//',
        r'safety.rs turns that rule into code. Its module comment says '
        r'so in its first paragraph, quoted here in full because it is '
        r'the thesis of the file.'),
    ...code('rust', 'crates/heaplens-injector/src/safety.rs · the opening paragraph', r'''
//! Pre-attach exclusion check (2026-07-22): refuses to inject into any
//! process that has a kernel-mode driver component, or belongs to a
//! category of software known to (VPN/network-filter clients, anti-cheat,
//! security/AV products, virtualization hosts) — the same hard exclusion
//! this project's own testing has followed all along, now enforced by the
//! tool itself instead of relying on the operator to remember it every time.
//!'''),
    ...para('//',
        r'The sentence trails off in the source, at "known to '
        r'(VPN/network-filter clients, ...)". The harm is never spelled '
        r'out in the '
        r'file, and I will not invent it. What the surrounding record '
        r'supports is a plain reading: software that has a kernel-mode '
        r'driver sits close to the operating system, and putting a '
        r'hook into its user-mode half is a risk that this project had '
        r'already decided not to take by hand. The commit that landed '
        r'the file, 864167e, puts it this way: the check "is what makes '
        r'shipping this responsible now", because it refuses such '
        r'processes automatically, "not left to the user to '
        r'remember".'),
    ...sec(r'three signals, a union of reasons to say no'),
    ...code('rust', 'crates/heaplens-injector/src/safety.rs · check()', r'''
/// Refuses (with a specific, printable reason) if `pid` matches any
/// exclusion signal. `Ok(())` means none of the three checks fired — it is
/// not a positive guarantee the process has no kernel driver, only that
/// none of these specific, safe, read-only checks found one.
pub fn check(pid: u32) -> Result<(), String> {
    if let Some(reason) = check_protection_level(pid) {
        return Err(reason);
    }
    if let Some(reason) = check_loaded_modules(pid) {
        return Err(reason);
    }
    if let Some(reason) = check_process_name(pid) {
        return Err(reason);
    }
    Ok(())
}'''),
    ...para('//',
        r'The structure is a chain of early returns, and the module '
        r'comment names what that means: "Any one of them matching is a '
        r'refusal — this is a union of ‘reasons to say no,’ not a '
        r'vote." That choice shapes everything else. In a vote, a weak '
        r'signal needs the others to agree. In a union, a weak signal '
        r'costs nothing to include, because the worst it can do is add '
        r'a refusal. So the three signals are ordered "from most '
        r'general to most specific", and each one catches what the '
        r'previous cannot.'),
    blank,
    ...para('//',
        r'The doc comment on check() is careful about what success '
        r'means: "Ok(()) means none of the three checks fired — it is '
        r'not a positive guarantee the process has no kernel driver, '
        r'only that none of these specific, safe, read-only checks '
        r'found one." Commit 864167e repeats the same limit in its '
        r'account of the shipped README: "best-effort (a general signal '
        r'plus a necessarily-incomplete denylist), not a formal '
        r'guarantee".'),
    ...sec(r'the constraint that organises the file'),
    ...code('rust', 'crates/heaplens-injector/src/safety.rs · the design constraint', r'''
//! # Design constraint: no handle upgrade before the verdict
//! Every check here uses `PROCESS_QUERY_LIMITED_INFORMATION` at most (or no
//! handle to the target at all, for the Toolhelp32-based checks) — strictly
//! less than the injection-capable rights `RemoteProcess::open` requests.
//! The point is that this module runs, and can refuse, *before* the
//! injector ever asks Windows for `PROCESS_CREATE_THREAD`/`PROCESS_VM_WRITE`
//! on an excluded process, not just before it uses them.'''),
    ...para('//',
        r'The refusal itself must not need the dangerous rights. Windows '
        r'asks for access rights when a handle is opened, so the check '
        r'uses PROCESS_QUERY_LIMITED_INFORMATION at most, or no handle '
        r'at all for the Toolhelp-based signals. The comment does not '
        r'say why asking would itself be a problem; the principle is '
        r'least privilege. The point it makes is subtle: the module "can refuse, before '
        r'the injector ever asks Windows for PROCESS_CREATE_THREAD/'
        r'PROCESS_VM_WRITE on an excluded process, not just before it '
        r'uses them". A refusal that has already requested the rights '
        r'has still done the thing it was meant to avoid.'),
    blank,
    ...para('//',
        r'The wiring in main.rs honours the same order: safety::check '
        r'is the first thing attach() does, ahead of the existence '
        r'check for the DLL and ahead of RemoteProcess::open, whose '
        r'rights are the injection-capable ones. And detach() does '
        r'not call it, so a process that was attached can always be '
        r'detached.'),
    ...sec(r'signal 1: the process’s own protection level'),
    ...code('rust', 'crates/heaplens-injector/src/safety.rs · check_protection_level', r'''
/// Signal 1 — process protection level. Opens the most limited handle that
/// can answer this question (`PROCESS_QUERY_LIMITED_INFORMATION`) and closes
/// it immediately after; never escalates to injection-capable rights here.
fn check_protection_level(pid: u32) -> Option<String> {
    let handle = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid) };
    if handle.is_null() {
        // Can't query — most likely a protected/elevated process this tool
        // has no rights to inspect at all, which is itself exactly the
        // signal this check exists to catch. Fail closed: refuse rather
        // than silently skip the check.
        return Some(format!(
            "cannot query process {pid}'s protection level (access denied) — refusing rather \
             than assuming it is safe; a process this tool cannot even query is treated as \
             excluded"
        ));
    }
    let mut info = PROCESS_PROTECTION_LEVEL_INFORMATION { ProtectionLevel: 0 };
    let ok = unsafe {
        GetProcessInformation(
            handle,
            ProcessProtectionLevelInfo,
            &mut info as *mut _ as *mut core::ffi::c_void,
            std::mem::size_of::<PROCESS_PROTECTION_LEVEL_INFORMATION>() as u32,
        )
    };
    unsafe { CloseHandle(handle) };
    if ok == 0 {
        // Query genuinely failed (not "access denied to open" — this is a
        // failure of the info call itself on an already-open handle).
        // Treat the same as unknown/unsafe rather than assume None.
        return Some(format!(
            "GetProcessInformation(ProcessProtectionLevelInfo) failed for process {pid} — \
             refusing rather than assuming it is unprotected"
        ));
    }
    if info.ProtectionLevel != PROTECTION_LEVEL_NONE {
        return Some(format!(
            "process {pid} is a protected process (protection level {}) — third-party software \
             has no legitimate reason to run protected other than belonging to exactly the \
             excluded category (anti-malware engines, system-security components); refusing",
            info.ProtectionLevel
        ));
    }
    None
}'''),
    ...para('//',
        r'This is the signal the module comment ranks "most general, most '
        r'reliable". Windows 8.1 and later report whether a process is a '
        r'Protected Process or a Protected Process Light. The reasoning '
        r'in the comment is why the signal works: "third-party software '
        r'has no legitimate reason to run protected unless it’s exactly '
        r'this excluded category". Anti-malware engines run at the '
        r'anti-malware light level precisely so nothing can tamper with '
        r'them, "which is the same property that makes DLL injection '
        r'into them meaningless to attempt and worth refusing '
        r'outright". Best of all, it needs no name list. It "generalizes '
        r'to vendors never explicitly enumerated below, which the other '
        r'two signals cannot do."'),
    blank,
    ...para('//',
        r'Read the function for its failure handling, because that is '
        r'where it is most deliberate. There are three ways to get no '
        r'answer, and every one is a refusal:'),
    ...pt('//', r'the handle cannot be opened',
        r'the comment says this is "most likely a protected/elevated '
        r'process this tool has no rights to inspect at all, which is '
        r'itself exactly the signal this check exists to catch. Fail '
        r'closed: refuse rather than silently skip the check."'),
    ...pt('//', r'the information call fails on an open handle',
        r'"Treat the same as unknown/unsafe rather than assume None."'),
    ...pt('//', r'the level is anything other than none',
        r'refuse, and put the numeric level in the message, so a log '
        r'reader can see which kind of protection it was.'),
    blank,
    ...para('//',
        r'The handle is closed immediately after the one query, before '
        r'the result is even examined. Commit 864167e records a live '
        r'confirmation: the attach against Windows Defender, "a real '
        r'protected process", was refused, and its exact reason appeared '
        r'in the UI dialog and in the verbose-log panel. That is the '
        r'path this function serves, tested on the real thing.'),
    ...sec(r'signal 2: a vendor’s DLL in the process'),
    ...code('rust', 'crates/heaplens-injector/src/safety.rs · check_loaded_modules', r'''
/// Signal 2 — loaded module names. No handle to the target opened by this
/// function at all; `CreateToolhelp32Snapshot` manages its own access.
fn check_loaded_modules(pid: u32) -> Option<String> {
    let snap = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, pid) };
    if snap.is_null() {
        return None; // no modules visible (process may have exited, or be inaccessible) — Signal 1/3 cover the rest
    }
    let mut entry: MODULEENTRY32W = unsafe { std::mem::zeroed() };
    entry.dwSize = std::mem::size_of::<MODULEENTRY32W>() as u32;
    let mut found = None;
    let mut ok = unsafe { Module32FirstW(snap, &mut entry) };
    while ok != 0 {
        let name_len = entry.szModule.iter().position(|&c| c == 0).unwrap_or(entry.szModule.len());
        let name = String::from_utf16_lossy(&entry.szModule[..name_len]);
        if DENYLIST_MODULE_NAMES.iter().any(|d| name.eq_ignore_ascii_case(d)) {
            found = Some(format!(
                "process {pid} has {name} loaded — a known driver-backed vendor SDK module \
                 (anti-cheat/VPN userspace client); refusing"
            ));
            break;
        }
        ok = unsafe { Module32NextW(snap, &mut entry) };
    }
    unsafe { CloseHandle(snap) };
    found
}'''),
    ...para('//',
        r'The comment on signal 2 contains the sentence that makes it '
        r'clear what is actually being detected. A kernel driver "is '
        r'never in a process’s module list — drivers live in kernel '
        r'address space, not any process’s — so this checks for the '
        r'userspace half of the pair, not the driver directly." Some '
        r'anti-cheat and VPN products link a vendor DLL into the '
        r'user-mode process that talks to their driver, and that DLL '
        r'is visible. The matching list is short and exact: five file '
        r'names, which by their names are the EasyAntiCheat and '
        r'BattlEye client libraries (the file does not label them), '
        r'compared case-insensitively on the file name alone. The snapshot is the same module walk that main.rs uses '
        r'to confirm the hook loaded, and no handle to the target is '
        r'opened here.'),
    ...sec(r'signal 3: the process name'),
    ...code('rust', 'crates/heaplens-injector/src/safety.rs · the process-name denylist (trimmed)', r'''
/// Process image names (case-insensitive, no path) known to belong to
/// VPN/network-filter clients, anti-cheat, security/AV products, or
/// virtualization hosts. Incomplete by construction — see the module doc
/// comment's Signal 3 section. Extend this list as specific products are
/// identified; do not remove entries without a specific reason.
const DENYLIST_PROCESS_NAMES: &[&str] = &[
    // VPN / network-filter clients
    "exitlag.exe",
    "nordvpn.exe",
...
    // Anti-cheat
    "easyanticheat.exe",
    "easyanticheat_eos_setup.exe",
    "beservice.exe",
    "bedaisy.exe",
    "battleye.exe",
    "vgc.exe",
    "vgtray.exe",
    "faceit.exe",
    "faceitclient.exe",
...
    // Virtualization hosts
    "vmware.exe",
    "vmware-vmx.exe",
    "vmware-authd.exe",
    "vmnat.exe",
    "vboxheadless.exe",
    "virtualbox.exe",
    "vboxsvc.exe",
    "vmms.exe",
    "vmwp.exe",
    "qemu-system-x86_64.exe",
    "qemu-system-x86_64w.exe",
];'''),
    ...para('//',
        r'The list has 60 names in four groups, which I counted from the '
        r'source: 23 VPN and network-filter clients, 9 anti-cheat '
        r'executables, 17 security and antivirus products, and 11 '
        r'virtualization hosts. Some entries contain spaces '
        r'("mullvad vpn.exe"), a reminder that these are real file '
        r'names collected one by one. The doc comment is honest about '
        r'what a list can be: "Incomplete by construction", to be '
        r'extended as products are identified, with the instruction not '
        r'to remove entries "without a specific reason". The module '
        r'comment puts it more bluntly: the signal is "trivially '
        r'spoofable (rename the exe) and incomplete by construction", and '
        r'it is "explicitly the fallback ... weaker but still better '
        r'than relying on the operator to remember", not the primary '
        r'defence.'),
    ...code('rust', 'crates/heaplens-injector/src/safety.rs · check_process_name (trimmed)', r'''
/// Signal 3 — process image name. No handle to the target opened by this
/// function; system-wide process snapshot, filtered by pid.
fn check_process_name(pid: u32) -> Option<String> {
    let snap = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) };
    if snap.is_null() {
        return None;
    }
    let mut entry: PROCESSENTRY32W = unsafe { std::mem::zeroed() };
    entry.dwSize = std::mem::size_of::<PROCESSENTRY32W>() as u32;
    let mut found = None;
    let mut ok = unsafe { Process32FirstW(snap, &mut entry) };
    while ok != 0 {
        if entry.th32ProcessID == pid {
            let name_len = entry.szExeFile.iter().position(|&c| c == 0).unwrap_or(entry.szExeFile.len());
            let name = String::from_utf16_lossy(&entry.szExeFile[..name_len]);
            if DENYLIST_PROCESS_NAMES.iter().any(|d| name.eq_ignore_ascii_case(d)) {
                found = Some(format!(
                    "process {pid} ({name}) matches the maintained denylist of known \
                     driver-bearing software (VPN/network-filter, anti-cheat, security/AV, \
                     virtualization); refusing"
                ));
            }
            break;
        }
        ok = unsafe { Process32NextW(snap, &mut entry) };
    }
    unsafe { CloseHandle(snap) };
    found
}'''),
    ...para('//',
        r'Notice that this one takes a system-wide process snapshot and '
        r'filters it by pid, which the comment points out "needs no '
        r'handle to the target process at all". The loop breaks at the '
        r'first match of the pid, because pids are unique within a '
        r'snapshot, and the denylist test runs only on that entry.'),
    ...sec(r'who fails open and who fails closed'),
    ...para('//',
        r'The three functions treat their own errors differently, and '
        r'the difference is deliberate:'),
    ...pt('//', r'signal 1 fails closed',
        r'cannot open, or cannot query: refuse.'),
    ...pt('//', r'signal 2 fails open',
        r'if the snapshot cannot be taken it returns None, with the '
        r'comment "no modules visible (process may have exited, or be '
        r'inaccessible) — Signal 1/3 cover the rest".'),
    ...pt('//', r'signal 3 fails open',
        r'same shape: a failed snapshot returns None.'),
    blank,
    ...para('//',
        r'It is consistent with the union rule. The primary signal '
        r'carries the safety argument, so it must not silently pass '
        r'when it cannot do its job. The auxiliary signals can only add '
        r'refusals, so when they have nothing to say, saying nothing is '
        r'correct. Signal 2’s comment makes the dependency explicit: '
        r'the other signals "cover the rest".'),
    ...sec(r'what the check does not do, and what I would test'),
    ...pt('//', r'it has no unit tests',
        r'the file contains no #[test]. The decision in each function '
        r'is a comparison of a name or a number against a list, so '
        r'extracting that comparison would make it testable without '
        r'touching real processes. The live evidence (the Defender '
        r'refusal, a clean Notepad) is real but not repeatable by a '
        r'build.'),
    ...pt('//', r'the verdict is a lookup, not a handle',
        r'check(pid) judges a pid and returns. The injector then opens '
        r'that pid again. If the pid were reused between the two calls, '
        r'the verdict would be about a different process. The window '
        r'is a few milliseconds and I know of no occurrence.'),
    ...pt('//', r'protection level is necessary, not sufficient',
        r'a driver-bearing product that does not run its user-mode '
        r'process as PP or PPL (I would expect most VPN clients and '
        r'game processes to be in that group) is caught only by the '
        r'module and name lists.'),
    ...pt('//', r'the module list is two vendors',
        r'EasyAntiCheat and BattlEye clients, by name. The process '
        r'list has more anti-cheat executables (vgc.exe, vgtray.exe, '
        r'two FACEIT names), but nothing of theirs is on the module '
        r'list.'),
    ...pt('//', r'a failed Toolhelp snapshot is checked against null',
        r'CreateToolhelp32Snapshot reports failure with '
        r'INVALID_HANDLE_VALUE, so the is_null() guards in signals 2 '
        r'and 3 do not fire. The effect is benign: a bad handle makes '
        r'the first Module32FirstW or Process32FirstW fail, the loop '
        r'does not run, and the function returns None, which is the '
        r'intended result of the guard. Still, the guard reads as if it '
        r'handled the error and does not.'),
    ...pt('//', r'refusal text says "access denied"',
        r'for signal 1, an OpenProcess failure can also mean the pid '
        r'does not exist. The message does say "access denied" and '
        r'treats the cause as unknown ("refusing rather than assuming '
        r'it is safe"), which is consistent, but a user whose target '
        r'exited may be told something unhelpful.'),
    ...sec(r'how it fits into the story'),
    ...para('//',
        r'The attach button had been switched off on 2026-07-21 at 22:21 '
        r'(823dac7) after the crash investigation, and switched on '
        r'again on 2026-07-22 at 11:14 in the very commit that added '
        r'this file. The commit message lists four reasons to trust '
        r'the change: the TLS and FLS crash fixed and held by a '
        r'standing stress test and by injection under load, a '
        r'three-stage memory and performance chain fixed and proven '
        r'to plateau in a soak of about 2 hours and 10 minutes '
        r'against a real Node.js process, validation against three '
        r'architecturally distinct real targets (native Win32, '
        r'Electron/Chromium, Node.js/V8), and, last, this check. It '
        r'describes the safety check as "previously implemented and '
        r'validated but not yet committed", which explains why the '
        r'file arrived complete and in one commit.'),
    blank,
    ...para('//',
        r'The UI states the capability in the same restrained terms. '
        r'The tooltip the button carries, kAttachEnabledInfo in '
        r'control_bar.dart, reads: "Process attachment is enabled and '
        r'validated against controlled, standard, non-kernel-driver '
        r'software. HeapLens automatically refuses processes with '
        r'kernel-mode driver components (VPN/anti-cheat/security '
        r'software) for safety." That wording is as strong as the file '
        r'beneath it supports and no stronger: validated against '
        r'controlled targets, refuses a recognised category.'),
    ...sec(r'what to take from it'),
    ...pt('//', r'encode the rule you follow by hand',
        r'a rule that depends on someone remembering it is a rule that '
        r'fails on the busiest day.'),
    ...pt('//', r'make the refusal cheaper than the act',
        r'a safety check that requests dangerous rights has already '
        r'done part of the dangerous thing.'),
    ...pt('//', r'fail closed on the strong signal only',
        r'weak signals that can only add refusals can fail open '
        r'without weakening the whole.'),
    ...pt('//', r'say what a denylist is',
        r'"incomplete by construction" in the doc comment is worth '
        r'more than a longer list.'),
    ...pt('//', r'show the user the reason',
        r'the refusal text travels, unchanged, from this file to a '
        r'dialog, and that path was tested on a real protected '
        r'process.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-injector/src/safety.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-injector/src/safety.rs'),
  ],
);
