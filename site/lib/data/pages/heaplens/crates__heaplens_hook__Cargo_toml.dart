import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-hook/Cargo.toml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'Cargo.toml — twenty lines that decide this crate is a DLL'),
    cm('#', r'crate-type = ["cdylib"] is the whole architecture of Stage 7'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', r'manifest for heaplens-hook, the DLL injected into other processes'),
    kv('language', r'TOML'),
    kv('size', r'20 lines, one commit: b3a22c2 (2026-07-13), never edited since'),
    kv('output', r'heaplens_hook.dll, the file name heaplens-injector hard-codes'),
    kv('resolved', r'minhook 0.9.0 and windows-sys 0.61.2, per the workspace Cargo.lock'),
    ...sec(r'the whole file'),
    ...code('toml', 'crates/heaplens-hook/Cargo.toml · the manifest', r'''
[package]
name = "heaplens-hook"
version = "0.1.0"
edition = "2021"

[lib]
name = "heaplens_hook"
crate-type = ["cdylib"]

[dependencies]
heaplens-protocol = { path = "../heaplens-protocol" }
heaplens-alloc = { path = "../heaplens-alloc" }
minhook = "0.9"
windows-sys = { version = "0.61", features = [
    "Win32_Foundation",
    "Win32_System_Memory",
    "Win32_System_LibraryLoader",
    "Win32_System_SystemInformation",
    "Win32_System_Threading",
] }'''),
    ...para('#',
        r'The file was written once, in the commit that created the crate '
        r'(b3a22c2, "Stage 7 step 1 - heaplens-hook capture DLL, self-load '
        r'acceptance gate"), and the history shows no later edit. Every '
        r'turn of the story told on the lib.rs page, a run of hazards the '
        r'source numbers up to ten, was fixed in source without touching '
        r'this manifest. What the manifest does decide is the shape of '
        r'the thing the source has to live in.'),
    ...sec(r'crate-type = ["cdylib"]: what one line commits you to'),
    ...para('#',
        r'The other crates in the workspace are libraries or ordinary '
        r'executables. This one is a cdylib: a self-contained C-ABI '
        r'dynamic library, a .dll on Windows. The consequences are the '
        r'rest of the project in miniature.'),
    ...pt('#', r'It carries its own Rust runtime',
        r'a cdylib statically includes the standard library and every '
        r'Rust dependency it uses. The DLL that lands inside a target is '
        r'a complete Rust program minus main: its own std::thread, its '
        r'own mpsc channels, its own copy of heaplens-alloc, and, '
        r'because lib.rs declares a #[global_allocator], its own '
        r'allocator. That last point is why the DLL can have a private '
        r'heap at all: the allocator attribute governs only this DLL’s '
        r'copy of the runtime, not the target’s.'),
    ...pt('#', r'Nothing can link it',
        r'with only cdylib in crate-type there is no rlib, so no other '
        r'crate can write "use heaplens_hook". The header of '
        r'self_load_harness says so: "This binary does not link '
        r'heaplens_hook as a Rust library (it’s a cdylib, loaded '
        r'dynamically like any injection target would load it)". The '
        r'test harnesses therefore exercise the real artefact, through '
        r'LoadLibraryW and GetProcAddress, not a test-only back door.'),
    ...pt('#', r'The interface is exports, not functions',
        r'what the injector can call is whatever the source marks '
        r'#[unsafe(no_mangle)] pub extern "system": four functions and '
        r'two statics. Anything else in lib.rs is invisible from '
        r'outside, which is why the exported statics WORKER_TID and '
        r'DETACH_RESULT, read back by ReadProcessMemory, are the '
        r'injector’s only channel for data.'),
    ...pt('#', r'There is no DllMain to configure',
        r'the manifest sets nothing about DllMain, and lib.rs defines '
        r'none (I searched for it; the string appears only in comments '
        r'that explain why none exists). The design decision "never run '
        r'anything under the loader lock" is expressed here by absence.'),
    ...sec(r'the [lib] table, and a name that has to match'),
    ...para('#',
        r'[lib] name = "heaplens_hook" gives the library target an '
        r'underscore name. Cargo would derive the same name from the '
        r'package name by replacing the hyphen, so the line is '
        r'redundant in effect; what it buys, in my reading, is that the '
        r'file name is written down where a person looks for it. It has '
        r'to match the constant in the other crate:'),
    ...code('rust', 'crates/heaplens-injector/src/main.rs · the name the injector looks for', r'''
const DLL_NAME: &str = "heaplens_hook.dll";'''),
    ...para('#',
        r'The examples compute the DLL’s location the same way every '
        r'time: from target/{profile}/examples/x.exe, go up one '
        r'directory to target/{profile}/, and append heaplens_hook.dll. '
        r'The injector looks for it beside its own executable instead, '
        r'which is how the packaged folder lays things out.'),
    ...sec(r'the dependencies, one at a time'),
    ...pt('#', r'heaplens-protocol',
        r'used for exactly one import in lib.rs, EventKind, to tag each '
        r'record() call as Alloc, Realloc or Dealloc. The wire format '
        r'itself is produced by the writer thread inside heaplens-alloc; '
        r'the hook never builds a frame.'),
    ...pt('#', r'heaplens-alloc',
        r'the capture pipeline: record(), the per-thread rings, the '
        r'writer thread. The commit that created this crate made three '
        r'things in heaplens-alloc public for it (ensure_writer_started, '
        r'warm_up_symbol_resolution, request_writer_stop_and_wait), and '
        r'later work added shutdown_ring_storage. The design document '
        r'describes the split plainly: the ring, the event '
        r'construction, the stack capture and the wire framing are '
        r'shared and unmodified, and only the interception mechanism '
        r'differs.'),
    ...pt('#', r'minhook = "0.9"',
        r'Rust bindings to the MinHook inline-hooking library. The lock '
        r'file pins 0.9.0. lib.rs uses four calls: MinHook::'
        r'create_hook_api, enable_all_hooks, disable_all_hooks and '
        r'uninitialize. The design document records the choice of '
        r'inline hooking over import-table patching: an import-table '
        r'hook misses statically linked runtimes and calls through '
        r'function pointers, and the design document’s phrase for why '
        r'that matters is that a "silent undercount is worse than a '
        r'visible one".'),
    ...pt('#', r'windows-sys = 0.61',
        r'raw Win32 bindings with no wrapper layer, with one feature '
        r'switched on per family of functions used. The list is worth '
        r'auditing against the sources, because Cargo does not.'),
    ...sec(r'auditing the windows-sys features'),
    ...para('#',
        r'I searched the crate’s sources and examples for every '
        r'windows_sys import and matched them to the features:'),
    ...pt('#', r'Win32_Foundation',
        r'HANDLE, in lib.rs, the type of the heap handle passed through '
        r'every detour.'),
    ...pt('#', r'Win32_System_Memory',
        r'GetProcessHeap, HeapAlloc, HeapCreate, HeapDestroy, HeapFree '
        r'and HeapReAlloc, the private-heap allocator and the canary.'),
    ...pt('#', r'Win32_System_Threading',
        r'GetCurrentThread, GetCurrentThreadId, SleepEx and '
        r'TerminateThread: the worker’s alertable wait and the '
        r'self-termination in the Remote entry point.'),
    ...pt('#', r'Win32_System_LibraryLoader',
        r'not used by lib.rs at all. Only the three self_load examples '
        r'import it, for LoadLibraryW and GetProcAddress. Examples may '
        r'use a package’s ordinary [dependencies], and there is no '
        r'[dev-dependencies] table, so the feature sits in the list the '
        r'DLL itself is built with.'),
    ...pt('#', r'Win32_System_SystemInformation',
        r'I could not find a use of it anywhere in the crate: not in '
        r'lib.rs, not in any example. It is the one feature in the list '
        r'with no consumer. The injector, a different crate, does use '
        r'this feature for IMAGE_FILE_MACHINE_AMD64; it may have been '
        r'copied from the same planning notes. That is a guess, and the '
        r'cost of the extra feature is a compile-time one only.'),
    ...sec(r'what the manifest does not say'),
    ...pt('#', r'No profile overrides',
        r'the workspace root sets [profile.release] debug = true, with a '
        r'long comment explaining that without debug info every '
        r'internal call site resolves to the nearest exported symbol '
        r'and ownership inference collapses. That setting applies to '
        r'this DLL too, so the shipped hook carries debug info. Commit '
        r'50a9627 (2026-07-28) is a reminder that the DLL’s own frames '
        r'are visible in the stacks it captures: until '
        r'"heaplens_hook::" was classified as machinery in the '
        r'writer, every injected allocation’s nearest frame was '
        r'hook_heap_alloc and ownership collapsed onto that one '
        r'symbol.'),
    ...pt('#', r'No example tables',
        r'there are no [[example]] entries, so Cargo auto-discovers the '
        r'seven files under examples/: self_load_harness, '
        r'self_load_spawned_thread, self_load_concurrency_stress, '
        r'injection_target, owner_freed_while_children_live, '
        r'exit_without_detach_multithreaded and fls_race_repro. Each '
        r'has its own page in this tree.'),
    ...pt('#', r'No rust-version',
        r'lib.rs uses the attribute form #[unsafe(no_mangle)], which '
        r'the compiler accepts in every edition from Rust 1.82. The '
        r'manifest says edition 2021 and states no minimum toolchain, '
        r'so that requirement is implicit.'),
    ...sec(r'one thing to check before trusting the weight'),
    ...para('#',
        r'heaplens-alloc’s own manifest lists iced, ratatui, crossterm '
        r'and rand under ordinary [dependencies] since commit 9693399 '
        r'(2026-07-28), for its demo examples. This crate depends on '
        r'heaplens-alloc, so those crates are in the DLL’s build graph. '
        r'Cargo links what code reaches, and nothing in lib.rs touches a '
        r'GUI, so I would expect none of it to end up in the binary, but '
        r'I have not inspected the DLL, and a library that is injected '
        r'into strangers’ processes is the place where I would want '
        r'that confirmed. The alloc crate’s Cargo.toml page makes the '
        r'same observation from the other side.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-hook/Cargo.toml',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-hook/Cargo.toml'),
  ],
);
