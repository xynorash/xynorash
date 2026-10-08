import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-injector/Cargo.toml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'Cargo.toml — a tool that nothing depends on, on purpose'),
    cm('#', r'one dependency, eight Win32 feature flags, and a binary name that is a runtime contract'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', r'manifest for heaplens-injector, the one-shot attach/detach CLI'),
    kv('language', r'TOML'),
    kv('size', r'20 lines, one commit: 724695a (2026-07-19), never edited since'),
    kv('output', r'heaplens-injector.exe, found by file name by the daemon and by tests'),
    kv('resolved', r'windows-sys 0.61.2 (Cargo.lock)'),
    ...sec(r'the whole file'),
    ...code('toml', 'crates/heaplens-injector/Cargo.toml · the manifest', r'''
[package]
name = "heaplens-injector"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "heaplens-injector"
path = "src/main.rs"

[dependencies]
windows-sys = { version = "0.61", features = [
    "Win32_Foundation",
    "Win32_Security",
    "Win32_System_Threading",
    "Win32_System_Memory",
    "Win32_System_Diagnostics_Debug",
    "Win32_System_Diagnostics_ToolHelp",
    "Win32_System_LibraryLoader",
    "Win32_System_SystemInformation",
] }'''),
    ...para('#',
        r'The crate arrived in the commit that ported the Stage 7 control '
        r'protocol from the feat/stage7-injection branch, and the '
        r'manifest has not been touched since: every change after that, '
        r'including the safety check that is the most important '
        r'addition to the crate, fitted inside these eight features. '
        r'The manifest is short because the tool is deliberately '
        r'small, and what it does not contain is its main design '
        r'decision.'),
    ...sec(r'a binary with no project dependencies'),
    ...para('#',
        r'There is no heaplens crate in the [dependencies] table, and '
        r'that is not an oversight. The first lines of main.rs say '
        r'so: the tool has "no Rust-level dependency on heaplens-hook" '
        r'and treats the DLL "the same way any injector would target an '
        r'arbitrary DLL". The other half of that sentence is that '
        r'nothing depends on the injector either. The daemon starts it '
        r'as a child process by file name, and so do the tests. The '
        r'name in the [[bin]] table is therefore a runtime contract, '
        r'checked by nobody until the day it is wrong:'),
    ...code('rust', 'crates/heaplens-daemon/src/injector.rs · the name the daemon expects', r'''
const INJECTOR_EXE: &str = "heaplens-injector.exe";'''),
    ...code('rust', 'crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs · what happens when it was not built', r'''
    assert!(injector_exe.exists(), "build the injector first: cargo build --release -p heaplens-injector");'''),
    ...para('#',
        r'That second line is the price of the arrangement, paid in '
        r'the open. Because the daemon’s crate does not list the injector, '
        r'running the daemon’s tests does not build it. A fresh clone has to '
        r'be told, by an assertion message, to build the injector '
        r'first. The daemon’s own injector_path() has a similar message '
        r'for the case in which the executable is not next to the '
        r'daemon.'),
    blank,
    ...para('#',
        r'The benefit is stated in an earlier commit. When the project '
        r'shipped without cross-process attachment (823dac7, '
        r'2026-07-21), the message says the release was built with '
        r'"heaplens-injector.exe/heaplens_hook.dll" excluded "from the '
        r'build entirely (cargo build --exclude, not just skipped '
        r'from packaging)". A workspace member that no other member '
        r'depends on can be left out of a build by name, and that is '
        r'what made the strongest form of the safe option available: '
        r'the capability was absent from the delivered folder, with a '
        r'disabled Attach button and a tooltip as the second, visible '
        r'layer. The manifest shape, a leaf, is what allowed that.'),
    ...sec(r'a crate with no async runtime'),
    ...para('#',
        r'The daemon is a tokio program. The injector is not, and '
        r'its module comment calls it "a standalone, synchronous '
        r'tool". The design document gives the reasoning: injection is '
        r'"synchronous, Win32-heavy, and process-scoped code that has '
        r'no reason to live inside the daemon’s async tokio runtime". '
        r'The dependency table is the evidence that the separation '
        r'held. There is no tokio, no argument-parsing crate, no logging '
        r'crate and no error crate. main() counts its three arguments '
        r'with args.len() != 3 and every failure goes through one '
        r'function that prints a line and exits.'),
    ...sec(r'auditing the eight features'),
    ...para('#',
        r'windows-sys exposes each family of Win32 functions behind a '
        r'Cargo feature, and Cargo will not tell you which are unused. '
        r'I matched each to the imports in main.rs and safety.rs:'),
    ...pt('#', r'Win32_Foundation',
        r'CloseHandle, FreeLibrary and HANDLE in main.rs; CloseHandle in '
        r'safety.rs.'),
    ...pt('#', r'Win32_System_Threading',
        r'the largest consumer. main.rs imports CreateRemoteThread, '
        r'GetExitCodeThread, IsWow64Process2, OpenProcess, OpenThread, '
        r'QueueUserAPC, WaitForSingleObject, the five PROCESS_* rights '
        r'and THREAD_SET_CONTEXT. safety.rs adds GetProcessInformation, '
        r'ProcessProtectionLevelInfo and the protection-level types.'),
    ...pt('#', r'Win32_System_Memory',
        r'VirtualAllocEx and VirtualFreeEx with MEM_COMMIT, MEM_RELEASE, '
        r'MEM_RESERVE and PAGE_READWRITE: the buffer that carries the '
        r'DLL path into the target.'),
    ...pt('#', r'Win32_System_Diagnostics_Debug',
        r'ReadProcessMemory and WriteProcessMemory: writing the path, '
        r'and the detach mailbox in both directions.'),
    ...pt('#', r'Win32_System_Diagnostics_ToolHelp',
        r'CreateToolhelp32Snapshot and the Module32 and Process32 walkers. '
        r'The module walk finds the hook’s base address; safety.rs also '
        r'uses a process walk for its name check.'),
    ...pt('#', r'Win32_System_LibraryLoader',
        r'GetModuleHandleW, GetProcAddress and LoadLibraryW: the '
        r'address of kernel32’s LoadLibraryW and FreeLibrary, and the '
        r'local load of the hook DLL to compute export offsets.'),
    ...pt('#', r'Win32_System_SystemInformation',
        r'IMAGE_FILE_MACHINE_AMD64 and IMAGE_FILE_MACHINE_UNKNOWN for '
        r'the architecture check. (The hook crate lists this feature too '
        r'and I found no use of it there.)'),
    ...pt('#', r'Win32_Security',
        r'no source line imports anything from the Security module. My '
        r'reading is that it is required by the signature of '
        r'CreateRemoteThread, whose second parameter is a pointer to a '
        r'SECURITY_ATTRIBUTES structure; the code passes std::ptr::'
        r'null() for it. windows-sys gates each function behind every '
        r'feature its types come from, which would make this the one '
        r'feature that is needed without being named. I could not check '
        r'that against the windows-sys sources here, because they are '
        r'not in the local registry, so treat it as an explanation and '
        r'not as a finding.'),
    ...sec(r'what is absent, and what that means for the tool'),
    ...pt('#', r'no [profile] overrides',
        r'the workspace root sets [profile.release] debug = true, and it '
        r'applies to the injector like every other member. The '
        r'injector carries symbols that it does not need.'),
    ...pt('#', r'no target-specific section',
        r'unlike heaplens-alloc, which keeps windows-sys in a '
        r'Windows-only target table, this manifest puts it in the plain '
        r'table. The crate is Windows-only in every line; on another '
        r'operating system it will fail at the import line rather than '
        r'at resolution. For a tool whose whole subject is '
        r'CreateRemoteThread that is honest, and it spares a '
        r'pointless cfg.'),
    ...pt('#', r'one binary, no library',
        r'there is no [lib] table. Nothing can import the injector’s '
        r'logic, which means the safety module cannot be unit-tested from '
        r'a sibling test crate, a limit that the safety.rs page notes '
        r'from the other side: the file has no tests of its own.'),
    ...pt('#', r'no dependency on minhook',
        r'hooking is the DLL’s job. The injector only loads it, calls '
        r'its exports and unloads it, so the crate that links the '
        r'hooking library and the crate that decides when to run it '
        r'share nothing but a file name and a few export names.'),
    ...sec(r'a contract made of strings'),
    ...para('#',
        r'Because nothing connects the crates at compile time, the '
        r'agreement between them is a set of strings and integers that '
        r'only runtime exercises:'),
    ...pt('#', r'the binary name',
        r'"heaplens-injector" here, "heaplens-injector.exe" in the '
        r'daemon and in the tests.'),
    ...pt('#', r'the library name',
        r'DLL_NAME in main.rs is "heaplens_hook.dll", which equals the '
        r'[lib] name of the hook crate with a suffix.'),
    ...pt('#', r'the export names',
        r'HeapLensHookAttachRemote, HeapLensHookDetachApc, WORKER_TID and '
        r'DETACH_RESULT, passed to GetProcAddress as byte strings.'),
    ...pt('#', r'the return codes',
        r'the numbers 1 to 7 that the hook returns and report_hook_rc '
        r'turns into sentences.'),
    blank,
    ...para('#',
        r'A rename on one side compiles and fails at injection time. '
        r'Every one of these is covered only when the real injector is '
        r'run against a real hook DLL, which the daemon’s hook tests do. '
        r'That is why those tests spawn the true binaries and not a '
        r'mock, and why they say so in the assertion messages.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-injector/Cargo.toml',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-injector/Cargo.toml'),
  ],
);
