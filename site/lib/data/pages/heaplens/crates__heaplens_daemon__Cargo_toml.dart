import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/Cargo.toml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'Cargo.toml — the daemon’s dependency list is its architecture'),
    cm('#', r'a lib and a bin from one package, tokio, SQLite, WebSocket and Win32 snapshots'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', r'manifest for heaplens-daemon, the process that sits between the target and the UIs'),
    kv('language', r'TOML'),
    kv('size', r'33 lines, six commits touch it (23e20df 2026-07-01 to 724695a 2026-07-19)'),
    kv('output', r'heaplens_daemon (library) and heaplens-daemon (binary)'),
    ...sec(r'the whole file'),
    ...code('toml', r'crates/heaplens-daemon/Cargo.toml · lines 1-33', r'''
[package]
name = "heaplens-daemon"
version = "0.1.0"
edition = "2021"

[lib]
name = "heaplens_daemon"
path = "src/lib.rs"

[[bin]]
name = "heaplens-daemon"
path = "src/main.rs"

[dependencies]
heaplens-protocol = { path = "../heaplens-protocol" }
tokio = { version = "1", features = ["rt-multi-thread", "macros", "net", "io-util", "sync", "time", "signal", "process"] }
anyhow = "1"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
serde_json = "1"
tokio-tungstenite = "0.24"
futures-util = "0.3"
rusqlite = { version = "0.32", features = ["bundled"] }
windows-sys = { version = "0.61", features = [
    "Win32_Foundation",
    "Win32_System_Diagnostics_ToolHelp",
    "Win32_System_Threading",
    "Win32_System_SystemInformation",
] }

[dev-dependencies]
rusqlite = { version = "0.32", features = ["bundled"] }
tokio = { version = "1", features = ["macros", "rt", "time"] }'''),
    ...sec(r'why a library and a binary from the same package'),
    ...para('#',
        r'The [lib] and [[bin]] tables point at src/lib.rs and src/main.rs, so one package produces both a crate called heaplens_daemon and an executable called heaplens-daemon. The split is not cosmetic. Every file in this crate’s tests/ directory is compiled as its own crate and can only reach what the library exports, so a daemon that was only a binary could not be integration-tested at all. The history points the same way: the commit f12b3e6 is titled "make all modules pub for test access". The binary then becomes a thin shell, bootstrap, channels, tasks, Ctrl-C, over modules that the tests drive directly.'),
    blank,
    ...sec(r'the dependencies, one reason each'),
    ...pt('#', r'heaplens-protocol',
        r'the only workspace dependency. Frames, AllocEvent, NodeDto, GraphMessage, ControlRequest and ControlResponse all live there, so the daemon and the tests share one definition of the wire types.'),
    ...pt('#', r'tokio',
        r'the feature list covers what the daemon uses: rt-multi-thread and macros for the runtime, net for the TCP listener behind the WebSocket server, io-util for async reads and writes, sync for channels, time for timers, signal for Ctrl-C (main.rs calls tokio::signal::ctrl_c). The last entry, process, arrived with the Stage 7 port (724695a) and is what lets injector.rs spawn heaplens-injector.exe with tokio::process::Command.'),
    ...pt('#', r'tokio-tungstenite and futures-util',
        r'the WebSocket server in server.rs. futures-util supplies SinkExt and StreamExt, which split the socket into the sink and source halves the select loop uses.'),
    ...pt('#', r'rusqlite with the bundled feature',
        r'SQLite compiled from source into the binary, so the daemon needs no system sqlite DLL. Persistence is the store.rs thread.'),
    ...pt('#', r'serde_json',
        r'every WebSocket message is a JSON text frame; the daemon serialises GraphMessage and ControlResponse and parses ControlRequest.'),
    ...pt('#', r'anyhow, tracing, tracing-subscriber',
        r'error plumbing and logging in main.rs; the env-filter feature is what lets the log level be driven by an environment variable.'),
    ...pt('#', r'windows-sys',
        r'the only dependency that makes the crate Windows-only. It arrived in 724695a with exactly four features: Win32_Foundation for CloseHandle, Win32_System_Diagnostics_ToolHelp for the process snapshot, Win32_System_Threading for OpenProcess and IsWow64Process2, and Win32_System_SystemInformation for the machine constants. All of it serves procs.rs.'),
    ...sec(r'what the manifest says about portability'),
    ...para('#',
        r'windows-sys sits under plain [dependencies], not under a [target.’cfg(windows)’.dependencies] table, and procs.rs has no cfg gate. procs.rs says so in its opening comment ("Windows-only"), and it also means this crate does not build on any other platform. That matches the project: the hook DLL, the injector and the pipe path (the default pipe name in the tests is a \\.\pipe\ name) are all Windows. Even the test helpers build their temp database paths with a backslash.'),
    blank,
    ...sec(r'the dev-dependencies'),
    ...para('#',
        r'[dev-dependencies] repeats rusqlite with bundled, and lists tokio with macros, rt and time. The tests use rusqlite directly to open the same database file the store thread wrote and count rows, and use tokio::test and tokio::time::sleep. The rusqlite line is already a normal dependency, so the repeat is redundant, though harmless. Cargo unifies features across a package’s dependency and dev-dependency tables, so the dev tokio list adds nothing the normal list lacks.'),
    blank,
    ...sec(r'which tests lean on which dependency'),
    ...pt('#', r'store_tests.rs and orphan_persistence.rs',
        r'rusqlite, to read back what the store thread wrote.'),
    ...pt('#', r'ws_tests.rs, cross_process_wire.rs and target_diagnostics_stats.rs',
        r'tokio-tungstenite and futures-util on the client side, speaking to a real server::run.'),
    ...sec(r'history'),
    ...para('#',
        r'The manifest was created in the scaffold commit 23e20df on 2026-07-01 and grew one feature at a time as each module landed: graph.rs (9843e94), main.rs (fe90320), store.rs (88dedac, which brought rusqlite), server.rs (9174573, which brought the WebSocket crates), and finally 724695a on 2026-07-19, the commit that ported the Stage 7 control protocol and added tokio’s process feature and windows-sys. The shape of the history is the shape of the daemon: ingest first, then graph, then persistence, then the network edge, then control.'),
    blank,
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/Cargo.toml',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/Cargo.toml'),
  ],
);
