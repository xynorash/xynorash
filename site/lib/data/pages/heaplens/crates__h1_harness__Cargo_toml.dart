import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/h1-harness/Cargo.toml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'Cargo.toml — the manifest of an experiment'),
    cm('#', r'one dependency on the project, and a deliberate refusal to link the rest'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', r'manifest for h1-harness, the detection-latency measurement'),
    kv('language', r'TOML'),
    kv('size', r'17 lines, one commit: 816c732 (2026-07-16), never edited since'),
    kv('output', r'h1-harness.exe, a binary that is run by hand, not a test'),
    kv('resolved', r'tokio-tungstenite 0.24.0, rusqlite 0.32.1, libsqlite3-sys 0.30.1 (Cargo.lock)'),
    ...sec(r'the whole file'),
    ...code('toml', 'crates/h1-harness/Cargo.toml · the manifest', r'''
[package]
name = "h1-harness"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "h1-harness"
path = "src/main.rs"

[dependencies]
heaplens-protocol = { path = "../heaplens-protocol" }
tokio = { version = "1", features = ["rt-multi-thread", "macros", "net", "io-util", "sync", "time", "process", "fs"] }
tokio-tungstenite = "0.24"
futures-util = "0.3"
serde_json = "1"
anyhow = "1"
rusqlite = { version = "0.32", features = ["bundled"] }'''),
    ...para('#',
        r'It is seventeen lines, and the interesting part is the list of '
        r'things that are not in it. The harness measures how long the '
        r'daemon takes to notice an orphan (the page for '
        r'crates/h1-harness/src/main.rs tells the whole story). The '
        r'manifest encodes the rule behind that measurement: observe '
        r'the real system from outside, and link as little of it as '
        r'possible.'),
    ...sec(r'what the harness does not depend on'),
    ...para('#',
        r'There are four heaplens crates the harness could have '
        r'pulled in, and it takes exactly one.'),
    ...pt('#', r'heaplens-daemon: not a dependency',
        r'the daemon crate has a library target (the lib section of '
        r'crates/heaplens-daemon/Cargo.toml, with name heaplens_daemon), '
        r'so the harness could have run the graph, the sweep and the '
        r'store in its own process. It does not. It starts the shipped '
        r'binary, and main.rs checks for the file before doing '
        r'anything:'),
    ...code('rust', 'crates/h1-harness/src/main.rs · the two executables it needs', r'''
    let cwd = std::env::current_dir()?;
    let daemon_exe = cwd.join("target/release/heaplens-daemon.exe");
    let workload_exe = cwd.join("target/release/examples/chaos_orphan.exe");
    if !daemon_exe.exists() {
        anyhow::bail!("daemon not built: {}", daemon_exe.display());
    }
    if !workload_exe.exists() {
        anyhow::bail!("workload not built: {}", workload_exe.display());
    }'''),
    ...para('#',
        r'The measured thing is the release-profile daemon, the same '
        r'program a user gets in the delivery folder, driven over its '
        r'real WebSocket and persisting into its real SQLite file. The '
        r'commit message that added the crate is explicit about the '
        r'alternative it rejected: the "earlier discarded H1 attempt" '
        r'"measured a modified pipeline". Linking the library would '
        r'have measured a copy of the logic inside the harness. A '
        r'consequence is that Cargo knows nothing about the order: the '
        r'daemon and the workload must be built first by hand, and the '
        r'two bail! messages are the only enforcement.'),
    ...pt('#', r'heaplens-alloc: not a dependency',
        r'the workload, chaos_orphan, is a separate executable that '
        r'links heaplens-alloc as its global allocator. The harness '
        r'process does not link the capture allocator, so it is not '
        r'itself a producer on the pipe.'),
    ...pt('#', r'windows-sys: not a dependency',
        r'there is no Win32 call in the crate. Nothing in it is '
        r'conditional on the operating system, yet it cannot run '
        r'anywhere but Windows, because the paths above end in .exe. '
        r'Child processes are cleaned up with tokio’s '
        r'kill_on_drop(true) and an explicit kill and wait at the end '
        r'of each run.'),
    ...pt('#', r'an argument parser: not a dependency',
        r'main() reads std::env::args().nth(1) and treats the string '
        r'"diagnose" as the second mode. There is no clap, because '
        r'there are two modes and one optional number.'),
    ...sec(r'heaplens-protocol: the one that is'),
    ...para('#',
        r'The single path dependency is used for two types, and the '
        r'choice is the reason a protocol change cannot silently '
        r'invalidate a measurement:'),
    ...code('rust', 'crates/h1-harness/src/main.rs · the only project import', r'''
use heaplens_protocol::{GraphMessage, NodeState};'''),
    ...para('#',
        r'watch_ws decodes each WebSocket text frame as a GraphMessage '
        r'and looks for a node whose state is NodeState::Orphan. These '
        r'are the same definitions the daemon serialises. If someone '
        r'renames a variant or changes the shape of Diff, the harness '
        r'stops compiling instead of waiting 20 seconds for an orphan '
        r'it can no longer recognise and reporting FAILED. A shared '
        r'type is a cheap test of agreement between producer and '
        r'observer.'),
    ...sec(r'tokio: eight features, two of them unused by this file'),
    ...para('#',
        r'The feature list is longer than it needs to be, and '
        r'checking it against the source is the kind of audit that '
        r'Cargo does not do for you. I matched each feature to a '
        r'line of main.rs:'),
    ...pt('#', r'rt-multi-thread and macros',
        r'#[tokio::main] on main(), whose default runtime flavor is '
        r'the multi-threaded one.'),
    ...pt('#', r'process',
        r'tokio::process::Command, used to start the daemon and the '
        r'workload, with kill_on_drop and an async kill().await and '
        r'wait().await.'),
    ...pt('#', r'sync',
        r'tokio::sync::oneshot, the channel that carries the first '
        r'orphan node id from the WebSocket watcher back to run_once.'),
    ...pt('#', r'time',
        r'tokio::time::timeout and sleep: the 20-second watch limit '
        r'and the 300 ms pauses.'),
    ...pt('#', r'io-util',
        r'AsyncBufReadExt::lines on a BufReader over the daemon’s '
        r'piped stdout, which is how tick lines are read.'),
    ...pt('#', r'net',
        r'no line of main.rs names tokio::net. The feature is still '
        r'enabled, and would be enabled without being listed: '
        r'tokio-tungstenite 0.24.0 has default features connect and '
        r'handshake, and its connect feature turns on tokio/net '
        r'(I read its manifest in the local registry). So this entry is '
        r'redundant but harmless.'),
    ...pt('#', r'fs',
        r'unused. Every file operation in main.rs goes through '
        r'std::fs: remove_file, create_dir_all and write. The tokio '
        r'file API is not called. Nothing downstream needs this feature '
        r'either.'),
    blank,
    ...para('#',
        r'The set looks like the daemon’s own tokio features with '
        r'signal removed and fs added. That is an observation about two '
        r'manifests, not a statement about how this one was written.'),
    ...sec(r'sqlite, once'),
    ...para('#',
        r'rusqlite 0.32 with the bundled feature is how the harness reads '
        r'the three timestamps back. Bundled means the SQLite C source '
        r'is compiled into the binary, so the machine needs no SQLite '
        r'library. The daemon asks for the same version with the same '
        r'feature in its dependencies and again in its '
        r'dev-dependencies, so Cargo.lock holds a single rusqlite 0.32.1 '
        r'and a single libsqlite3-sys 0.30.1 for the whole workspace: '
        r'the file the harness opens is read by the same SQLite build '
        r'that wrote it, which removes one class of "the reader '
        r'disagrees with the writer" doubt from the measurement.'),
    ...pt('#', r'what it reads',
        r'the orphan_events table and the nodes table of a database file '
        r'under the temp directory, after the daemon has been killed. The '
        r'database is a throwaway: the path is unique to the run and '
        r'is deleted at the end of run_once.'),
    ...sec(r'where it sits in the workspace'),
    ...para('#',
        r'The workspace root lists "crates/h1-harness" as a member, so '
        r'a plain cargo build --release builds the harness too, and '
        r'it picks up the root manifest’s [profile.release] with '
        r'debug = true. For the harness itself that is irrelevant. It '
        r'matters for what it launches: the root profile is the reason '
        r'the release daemon and the release workload carry symbols '
        r'at all, and the workload’s call-site names are what the harness '
        r'matches (the constant CHILD_SYMBOL is "chaos_orphan::'
        r'make_children"). The root manifest’s own comment explains '
        r'why: without debug info the ownership function collapses. '
        r'So the measurement only works because of a setting in a '
        r'file the harness never mentions.'),
    ...sec(r'what the manifest cannot tell you'),
    ...pt('#', r'the order of builds',
        r'nothing in Cargo makes h1-harness wait for the daemon or the '
        r'workload. A fresh clone that runs the harness first gets a '
        r'clear message, which is the right way to fail, and not a '
        r'dependency, which would have forced the daemon to be linked.'),
    ...pt('#', r'that the harness can be re-run today',
        r'the manifest is stable, the program is not: as the main.rs '
        r'page explains, the workload it was written for has since '
        r'changed, and the opt-in variable HEAPLENS_ENABLE now gates '
        r'cooperative capture. The recorded CSV in docs/bench_results '
        r'predates both.'),
    ...pt('#', r'a rust-version',
        r'none is declared. watch_ws uses let-else, which needs a '
        r'compiler of Rust 1.65 or later; the manifest does not say '
        r'so.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/h1-harness/Cargo.toml',
        'https://github.com/xynorash/heaplens/blob/master/crates/h1-harness/Cargo.toml'),
  ],
);
