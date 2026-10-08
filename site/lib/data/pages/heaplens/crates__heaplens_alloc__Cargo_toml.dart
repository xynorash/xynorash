import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/Cargo.toml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'Cargo.toml — a dependency list that tells the project’s story'),
    cm('#', r'from a light in-process library to a crate that also carries a GUI '
              r'toolkit'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', r'manifest for heaplens-alloc, the crate linked into the observed '
              r'process'),
    kv('language', r'TOML'),
    kv('size', r'15 lines, 4 commits, 2026-07-01 to 2026-07-28'),
    kv('dependencies', r'heaplens-protocol, backtrace, iced, rand, ratatui, crossterm; '
              r'windows-sys on Windows'),
    ...sec(r'the whole file'),
    ...code('toml', 'crates/heaplens-alloc/Cargo.toml · the manifest', r'''
[package]
name = "heaplens-alloc"
version = "0.1.0"
edition = "2021"

[dependencies]
heaplens-protocol = { path = "../heaplens-protocol" }
backtrace = "0.3"
iced = { version = "0.13", features = ["tokio"] }
rand = "0.8"
ratatui = "0.29"
crossterm = "0.28"

[target.'cfg(windows)'.dependencies]
windows-sys = { version = "0.61", features = ["Win32_System_Threading"] }'''),
    ...para('#',
        r'Read from the top, this is two different crates. The first half '
        r'(heaplens-protocol, backtrace and a Windows-only slice of '
        r'windows-sys) is the library: what has to be linked into somebody '
        r'else’s process. The second half (iced, rand, ratatui and '
        r'crossterm) is the demo programs. They share one manifest because '
        r'the demos live in this crate’s examples/ directory, and examples '
        r'can draw on [dependencies] and [dev-dependencies] alike.'),
    ...sec(r'how it started: light on purpose'),
    ...para('#',
        r'The Build Spec’s section 4.7 gives the intended dependency list '
        r'for this crate and then a sentence that explains the philosophy: '
        r'"std provides OnceLock, Instant, thread. No tokio here — the '
        r'observed process must stay light." The original manifest (commit '
        r'8fc54a7, 2026-07-01) was exactly that: the protocol crate, '
        r'backtrace, and windows-sys 0.59 with three features '
        r'(Win32_Foundation, Win32_Storage_FileSystem, '
        r'Win32_System_Pipes), which the spec offered as one way to open '
        r'the pipe (CreateFileW), the other being std::fs::OpenOptions.'),
    ...sec(r'the Windows crate that left and came back'),
    ...para('#',
        r'Commit ba1a066 (2026-07-01, "final review fixes") removed '
        r'windows-sys as unused. The writer thread turned out not to need '
        r'any pipe API at all, because a Windows named pipe can be opened '
        r'with std::fs::OpenOptions on its path, \\.\pipe\heaplens. For '
        r'almost three weeks the crate depended on nothing but the '
        r'protocol and backtrace.'),
    blank,
    ...para('#',
        r'Then on 2026-07-21 (commit dcc76f2) windows-sys returned, in a '
        r'different shape: a target-specific table, '
        r'[target.’cfg(windows)’.dependencies], with one feature, '
        r'Win32_System_Threading, and a newer version (0.61). That feature '
        r'is where TlsAlloc, TlsGetValue, TlsSetValue and FlsAlloc live. '
        r'The reason is the crash story on the guard.rs and ring.rs pages: '
        r'thread_local! could not be trusted inside a DLL loaded with '
        r'LoadLibraryW, so the crate drives the Win32 slot APIs directly. '
        r'The cfg(windows) table is what lets the crate still compile on '
        r'other platforms, which is also why the guard and ring modules '
        r'keep a thread_local! fallback and why the crate’s tests can run '
        r'on Linux.'),
    blank,
    ...para('#',
        r'The feature list is as small as it can be, one feature for one '
        r'family of calls, the same minimalism as the protocol crate’s '
        r'manifest.'),
    ...sec(r'the day it gained a toolkit'),
    ...para('#',
        r'On 2026-07-28 (commit 9693399, "TUI backdrop ... replaces iced '
        r'GUI") four lines were added to [dependencies]: iced with the '
        r'tokio feature, rand, ratatui and crossterm. The motivating '
        r'context is in the examples: checkout_service_gui.rs is an iced '
        r'GUI demo target, and checkout_service_tui.rs is a terminal '
        r'replacement. The TUI’s own header explains why the author moved '
        r'away from iced: the GUI’s "wgpu/winit dependency surface is '
        r'implicated in an undiagnosed injection-path crash", so the '
        r'replacement "avoids that dependency surface entirely: no '
        r'GPU/windowing threads, just a terminal redraw loop".'),
    blank,
    ...para('#',
        r'Three things about that change are worth stating.'),
    blank,
    ...para('#',
        r'The lock file shows the scale. In that one commit Cargo.lock '
        r'went from 100 packages to 485 (counting the name entries at the '
        r'commit and at its parent), and the diffstat lists 6,001 '
        r'insertions overall, with 4,858 changed lines in the lock file '
        r'alone.'),
    blank,
    ...para('#',
        r'The dependencies are in [dependencies], not [dev-dependencies]. '
        r'Examples can use dev-dependencies, which are built only for '
        r'tests and examples, so a library consumer would not compile '
        r'them. As written, every crate that depends on heaplens-alloc '
        r'builds the whole toolkit, and heaplens-hook, which is injected '
        r'into other people’s processes, is one of those crates. Cargo '
        r'links only what code reaches, so the toolkit would not be '
        r'expected to end up inside the DLL; no binary was inspected for '
        r'this page. What was measured: on a Linux host, cargo tree '
        r'-e normal lists 377 distinct crates under heaplens-alloc, '
        r'including tokio (pulled in by iced’s tokio feature, despite the '
        r'spec’s "No tokio here"), wgpu and winit, against 10 under '
        r'heaplens-protocol; and a scratch release build of a program that '
        r'merely depended on the crate spent almost three minutes '
        r'compiling iced and its tree, where the protocol crate alone '
        r'builds in seconds. It is exactly the kind of drift the Build Spec’s '
        r'"the observed process must stay light" was written to prevent, '
        r'and the manifest does not mention the demos at all. This is a '
        r'reading, not a recorded decision. Moving the four lines to '
        r'[dev-dependencies] looks like a one-line fix.'),
    blank,
    ...para('#',
        r'rand is unused. A search of the crate’s sources and examples '
        r'finds no use of it. It was added in the same commit as the '
        r'others, perhaps in anticipation of the TUI, and never used. The '
        r'iced GUI example is still in the tree, and the TUI commit '
        r'message says it was replaced, yet iced is still a dependency: '
        r'the GUI example is described as "parked".'),
    ...sec(r'related'),
    ...pt('#',
        r'the protocol crate’s Cargo.toml',
        r'the opposite discipline, ten lines unchanged since the first '
        r'day.'),
    ...pt('#',
        r'guard.rs and ring.rs',
        r'why windows-sys came back.'),
    ...pt('#',
        r'checkout_service_gui.rs and checkout_service_tui.rs',
        r'what the toolkit crates are for.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/Cargo.toml',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/Cargo.toml'),
  ],
);
