import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/Cargo.toml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'Cargo.toml — the daemon’s dependency list, in the order it was needed'),
    cm('#', r'six commits, five of them in the first two days, and one library target that exists for the tests'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', r'manifest of heaplens-daemon, the crate that turns the allocation stream into a live ownership graph'),
    kv('language', r'TOML'),
    kv('size', r'33 lines, 6 commits, 2026-07-01 to 2026-07-19'),
    kv('targets', r'one library (heaplens_daemon) and one binary (heaplens-daemon)'),
    kv('dependencies', r'10 normal, 2 dev; tokio, tokio-tungstenite, rusqlite (bundled), windows-sys'),
    ...sec(r'the whole file'),
    ...para('#',
        r'The manifest is short enough to read in one piece. Everything '
        r'below is an explanation of why each line is there, with the '
        r'commit that introduced it.'),
    ...code('toml', 'crates/heaplens-daemon/Cargo.toml · the manifest', r'''
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
    ...sec(r'two targets in one package: why there is a [lib]'),
    ...para('#',
        r'The first version of this file, from the crate scaffold at '
        r'17:06 on 2026-07-01 (commit 23e20df), had a [[bin]] section and '
        r'nothing else. The [lib] section arrived fourteen minutes later, '
        r'in 9843e94, the commit that added graph.rs and its first eight '
        r'unit tests. The commit message gives the reason in one '
        r'sentence: "Add lib.rs to expose crate modules for integration '
        r'tests; main.rs now links the lib."'),
    ...para('#',
        r'The history in between is a small lesson. The scaffold declared '
        r'its modules inside main.rs with plain "mod" lines. At 17:08 a '
        r'commit named "make all modules pub for test access" (f12b3e6) '
        r'changed those five lines to "pub mod", still inside main.rs. '
        r'Twelve minutes after that, 9843e94 deleted them from main.rs '
        r'and moved them into a new src/lib.rs. The reason the first '
        r'attempt could not stand is a property of Cargo: a file under '
        r'tests/ is compiled as a separate crate and can link only a '
        r'library target of its package, never a binary. Marking modules '
        r'pub inside a binary changes nothing for a test. The page for '
        r'src/lib.rs in this crate tells the rest of that story.'),
    ...pt('#', r'the names differ on purpose',
        r'the library is heaplens_daemon with an underscore, which is '
        r'what Rust paths need (every test starts with "use '
        r'heaplens_daemon::..."), and the binary is heaplens-daemon with '
        r'a hyphen, which is the executable name users and other '
        r'components see. injector.rs, for example, tells the user to '
        r'find its sibling "next to heaplens-daemon.exe".'),
    ...pt('#', r'the binary is a thin consumer',
        r'main.rs opens with "use heaplens_daemon::{ anomaly::{...}, '
        r'config::Config, graph::OwnershipGraph, ingest, injector, ... }". '
        r'The same library that the tests exercise is what the shipping '
        r'program runs, so the tests cannot drift from the program by '
        r'testing a copy.'),
    ...sec(r'tokio: a feature list that grew by two words'),
    ...para('#',
        r'The scaffold started with six features: rt-multi-thread, '
        r'macros, net, io-util, sync and time. That is character for '
        r'character the list the Build Spec gives for this crate in '
        r'section 5.9. Two more were added later, each by the commit '
        r'that first needed it.'),
    ...pt('#', r'signal',
        r'added in fe90320 (main.rs, 2026-07-01) for the Ctrl-C arm of '
        r'the graph loop, tokio::signal::ctrl_c().'),
    ...pt('#', r'process',
        r'added in 724695a (2026-07-19) for tokio::process::Command, '
        r'which injector.rs uses to run heaplens-injector.exe as a '
        r'child and await its output without blocking the runtime.'),
    ...para('#',
        r'The rest of the list maps onto the modules: net for the '
        r'WebSocket listener in server.rs; io-util and net for the '
        r'named-pipe reader in ingest.rs, which uses '
        r'tokio::net::windows::named_pipe::ServerOptions; sync for the '
        r'mpsc, broadcast and oneshot channels that connect every task; '
        r'time for the tick interval; rt-multi-thread and macros for '
        r'#[tokio::main].'),
    ...sec(r'the other dependencies, one decision each'),
    ...pt('#', r'heaplens-protocol (path)',
        r'the wire contract: AllocEvent, the frame codec, GraphMessage, '
        r'NodeDto, ControlRequest and ControlResponse. Every other crate '
        r'that talks to the daemon depends on the same path, so a '
        r'change to a message is a compile error on both sides of the '
        r'wire.'),
    ...pt('#', r'anyhow, tracing, tracing-subscriber',
        r'all present from the scaffold. anyhow gives main() and '
        r'store::open() a "?"-friendly result type. tracing-subscriber '
        r'carries the "env-filter" feature, which is what lets '
        r'main.rs build an EnvFilter from RUST_LOG and fall back to "info".'),
    ...pt('#', r'serde_json',
        r'added with main.rs (fe90320). The daemon does not derive '
        r'Serialize itself; the types it sends come from heaplens-protocol. '
        r'It needs serde_json to turn them into text for the WebSocket '
        r'(server.rs) and, in store.rs, to render a node state as the '
        r'same lowercase string the wire uses.'),
    ...pt('#', r'tokio-tungstenite 0.24 and futures-util',
        r'added together in 9174573 with server.rs. tungstenite gives the '
        r'handshake and Message type; futures-util gives SinkExt and '
        r'StreamExt, which server.rs needs for ws_stream.split(), '
        r'send() and next().'),
    ...pt('#', r'rusqlite 0.32 with "bundled"',
        r'added in 88dedac with store.rs. The "bundled" feature compiles '
        r'SQLite from source into the binary, so the daemon needs no '
        r'sqlite3.dll on the machine. The Build Spec asks for exactly '
        r'this, "rusqlite with the bundled feature", in section 5.6.'),
    ...sec(r'windows-sys: the dependency of the last commit'),
    ...para('#',
        r'windows-sys 0.61 is the only dependency added by 724695a, the '
        r'commit that ported the Stage 7 control protocol (process list, '
        r'attach, detach) into this branch. Its four features are '
        r'exactly the four Win32 modules procs.rs imports from, and no '
        r'more:'),
    ...pt('#', r'Win32_Foundation', r'CloseHandle.'),
    ...pt('#', r'Win32_System_Diagnostics_ToolHelp',
        r'CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, '
        r'PROCESSENTRY32W and TH32CS_SNAPPROCESS.'),
    ...pt('#', r'Win32_System_Threading',
        r'OpenProcess, IsWow64Process2 and '
        r'PROCESS_QUERY_LIMITED_INFORMATION.'),
    ...pt('#', r'Win32_System_SystemInformation',
        r'IMAGE_FILE_MACHINE_AMD64 and IMAGE_FILE_MACHINE_UNKNOWN, the '
        r'constants the architecture probe compares against.'),
    ...para('#',
        r'windows-sys is a bindings crate with one cargo feature per API '
        r'namespace, so listing the namespaces by hand is how a '
        r'consumer keeps compile time down. The sibling crate '
        r'heaplens-alloc declares the same dependency only inside a '
        r'Windows-only target table, because it is a library '
        r'that other programs link. This manifest has no such gate, and '
        r'neither does src/lib.rs around "pub mod procs;". The daemon is '
        r'built as a Windows program by construction: it listens on a '
        r'Windows named pipe and enumerates processes with Toolhelp. '
        r'Nothing in the manifest pretends otherwise.'),
    ...sec(r'dev-dependencies: two lines that look redundant'),
    ...para('#',
        r'The [dev-dependencies] section appeared in 88dedac with '
        r'store.rs and has not changed since. It repeats rusqlite with '
        r'"bundled" and lists tokio with "macros", "rt" and "time". '
        r'Both are already available through [dependencies], and '
        r'rt-multi-thread in tokio implies rt, so as far as I can tell '
        r'from the manifest alone the section changes nothing about the '
        r'build. The commit message does not explain it. What it does '
        r'document is what the tests reach for: rusqlite directly '
        r'(store_tests.rs and orphan_persistence.rs open the database file '
        r'themselves with rusqlite::Connection to read back what the '
        r'store thread wrote) and the tokio test macro with timers.'),
    ...sec(r'what is not in the file'),
    ...pt('#', r'no serde',
        r'the Build Spec lists "serde = { version = 1, features = '
        r'[derive] }" in the daemon’s manifest. The implementation never '
        r'needed it, because all derives live in heaplens-protocol.'),
    ...pt('#', r'no [features] and no build.rs',
        r'one build, no switches. Behaviour is chosen at run time from '
        r'environment variables (HEAPLENS_WS_ADDR, HEAPLENS_TICK_MS and '
        r'so on, in config.rs), not at compile time.'),
    ...pt('#', r'no [profile]',
        r'profiles are read only from the workspace root. The root '
        r'Cargo.toml sets "debug = true" under [profile.release], with a '
        r'long comment explaining that without debug info every '
        r'internal call site resolves to the nearest exported symbol and '
        r'phi’s function-name matching is destroyed. That setting '
        r'matters to the daemon’s tests more than to the daemon: the '
        r'cross_process_wire test runs a producer built in the same '
        r'profile as the test itself, found relative to its own '
        r'executable.'),
    ...pt('#', r'version 0.1.0, never bumped',
        r'six commits, no version change. The crate is never published; '
        r'it is one component of a workspace.'),
    ...sec(r'reading the history as a timeline'),
    ...pt('#', r'2026-07-01 17:06 · 23e20df',
        r'scaffold: protocol, tokio (six features), anyhow, tracing, '
        r'tracing-subscriber, one [[bin]].'),
    ...pt('#', r'2026-07-01 17:20 · 9843e94', r'the [lib] section, with graph.rs.'),
    ...pt('#', r'2026-07-01 17:32 · fe90320',
        r'tokio "signal" and serde_json, with main.rs.'),
    ...pt('#', r'2026-07-02 07:45 · 88dedac',
        r'rusqlite and the dev-dependencies, with store.rs.'),
    ...pt('#', r'2026-07-02 07:49 · 9174573',
        r'tokio-tungstenite and futures-util, with server.rs.'),
    ...pt('#', r'2026-07-19 19:57 · 724695a',
        r'tokio "process" and windows-sys, with the control protocol.'),
    ...para('#',
        r'Five of the six commits fall inside about fifteen hours on '
        r'the first two days of the daemon’s life, when each module '
        r'was written in turn. Then the file does not change for seventeen days. '
        r'In that gap the daemon was rewritten in the ways other pages '
        r'describe: phi moved to function-name granularity (43fc22e), the '
        r'orphan timestamps and the Stats heartbeat were added, and the '
        r'ownership search was given two indexes (783b2d3). None of it needed a '
        r'new crate. The architecture settled quickly, and the work '
        r'that followed was about correctness inside it.'),
    ...sec(r'limits'),
    ...pt('#', r'caret requirements everywhere',
        r'every version is a plain caret requirement such as "1", "0.3" '
        r'or "0.61". Exact '
        r'versions come from Cargo.lock at the workspace root. A fresh '
        r'resolve without the lock could move any of them within its '
        r'compatibility range.'),
    ...pt('#', r'tokio-tungstenite is pinned to 0.24',
        r'server.rs sends "Message::Text(json)" with a String. That is '
        r'the shape of the 0.24 API; a later major version of the '
        r'crate would make this a compile error to fix, not a silent '
        r'change.'),
    ...pt('#', r'the dev-dependencies section is unexplained',
        r'see above. Removing it would probably change nothing, but this '
        r'page does not claim that it has been tried.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/Cargo.toml',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/Cargo.toml'),
  ],
);
