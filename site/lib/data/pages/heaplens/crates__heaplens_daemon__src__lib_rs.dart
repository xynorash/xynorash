import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/src/lib.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'lib.rs — ten lines that make the daemon testable'),
    cm('//', r'the module list is the architecture, and its history is the order the daemon was built in'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'library root of heaplens-daemon: declares and exports every module'),
    kv('language', r'Rust'),
    kv('size', r'10 lines, 6 commits, 2026-07-01 to 2026-07-19'),
    kv('used by', r'src/main.rs (the binary) and 12 of the 13 files under tests/'),
    ...sec(r'the whole file'),
    ...code('rust', 'crates/heaplens-daemon/src/lib.rs · the whole file', r'''
pub mod anomaly;
pub mod config;
pub mod graph;
pub mod ingest;
pub mod injector;
pub mod msg;
pub mod procs;
pub mod resolver;
pub mod server;
pub mod store;'''),
    ...para('//',
        r'There is no code in this file, no re-export and no doc comment. '
        r'Its whole job is the word pub. That is worth a page because '
        r'of what it took to get there, and because the list, read in '
        r'the right order, is a map of the daemon.'),
    ...sec(r'why it exists: integration tests cannot link a binary'),
    ...para('//',
        r'The daemon began as a single binary crate. In the scaffold '
        r'commit (23e20df, 2026-07-01 17:06) main.rs declared its own '
        r'modules with plain "mod" lines. Two minutes later a commit '
        r'called "make all modules pub for test access" (f12b3e6, 17:08) '
        r'turned them into "pub mod", still in main.rs. It could '
        r'not help. A file in tests/ is compiled as a separate crate, and '
        r'Cargo lets it link only the package’s library target. A '
        r'binary has no importable items, whatever their visibility.'),
    ...para('//',
        r'At 17:20 the commit that added graph.rs and its first eight '
        r'unit tests (9843e94) fixed it properly. Its message says "Add '
        r'lib.rs to expose crate modules for integration tests; main.rs '
        r'now links the lib." The diff moves the five "pub mod" lines '
        r'out of main.rs, replaces them with a single "use '
        r'heaplens_daemon as _;", and creates this file with the same '
        r'five names. The matching [lib] section went into Cargo.toml in '
        r'the same commit.'),
    ...para('//',
        r'From then on every test says "use heaplens_daemon::graph::'
        r'OwnershipGraph;" and so on, and so does main.rs. That is the '
        r'design consequence: there is one copy of the code, and the '
        r'shipping program and the tests both import it. If the '
        r'daemon had been tested by including its source files into '
        r'test crates, or by driving the binary as a subprocess, the '
        r'tests would be slower and the two could drift.'),
    ...sec(r'the list is alphabetical and the history is not'),
    ...para('//',
        r'The names are sorted, and each new module was inserted at its '
        r'alphabetical place, so the diff history of this file is a '
        r'build log. The order in which the modules actually appeared:'),
    ...pt('//', r'2026-07-01 17:20 · 9843e94',
        r'config, graph, ingest, msg, resolver. The data path in its '
        r'smallest form: pipe in, graph in the middle, nothing out yet.'),
    ...pt('//', r'2026-07-02 · eaa6162', r'anomaly: orphan and hot sweeps, and the storm tracker.'),
    ...pt('//', r'2026-07-02 · 88dedac', r'store: SQLite persistence on its own thread.'),
    ...pt('//', r'2026-07-02 · 9174573', r'server: the WebSocket side.'),
    ...pt('//', r'2026-07-19 · 724695a',
        r'injector and procs, in the commit that ported the Stage 7 '
        r'control protocol (list processes, attach, detach).'),
    ...para('//',
        r'The first eight names (five on 2026-07-01, three more on '
        r'2026-07-02) were the daemon becoming a complete pipeline in '
        r'two days. The last two arrived 17 days later and make the '
        r'daemon a controller of other programs as well as an '
        r'observer of them.'),
    ...sec(r'the same ten names, grouped by what they depend on'),
    ...para('//',
        r'The imports between modules (every "use crate::" line in src/) '
        r'are few, and they give the real layering. Reading them as a '
        r'diagram from the bottom:'),
    ...pt('//', r'vocabulary: config and msg',
        r'config reads the environment into one Config struct. msg '
        r'defines the messages that tasks send each other: GraphMsg, '
        r'TargetCmd, ConnectRequest, StoreMsg and OrphanEventRecord. '
        r'Neither imports another module of the crate.'),
    ...pt('//', r'model: resolver, graph, anomaly',
        r'graph imports resolver; anomaly imports graph (it sweeps '
        r'Node values) and config (for the thresholds). None of the '
        r'three imports msg, server, store or any I/O module. The '
        r'whole ownership model can therefore be built and tested '
        r'with no channel, no socket and no database, which is what '
        r'graph_unit.rs and anomaly_unit.rs do.'),
    ...pt('//', r'edges: ingest, server, store',
        r'each imports msg and nothing else from the crate. ingest '
        r'reads the Windows named pipe and produces GraphMsg; server '
        r'accepts WebSocket clients and exchanges ConnectRequest and '
        r'TargetCmd; store consumes StoreMsg and writes SQLite.'),
    ...pt('//', r'side doors: procs and injector',
        r'they import nothing from the crate at all. procs wraps '
        r'Toolhelp to list processes; injector runs '
        r'heaplens-injector.exe. Both are consumed only by main.rs.'),
    ...para('//',
        r'Nothing connects the groups except main.rs. The edges '
        r'modules do not know about the graph and the graph does not '
        r'know about the edges; the single graph loop in main.rs owns '
        r'the graph and the resolver and sees every message. That '
        r'is the architectural fact lib.rs makes visible by being '
        r'just a list.'),
    ...sec(r'who imports what, from the tests'),
    ...para('//',
        r'The test files exercise the library surface in a way that '
        r'also shows which modules have direct coverage:'),
    ...pt('//', r'anomaly_unit.rs', r'anomaly, config, graph.'),
    ...pt('//', r'graph_unit.rs', r'anomaly, config, graph, resolver.'),
    ...pt('//', r'store_tests.rs', r'msg, store.'),
    ...pt('//', r'orphan_persistence.rs',
        r'anomaly, config, graph, msg, resolver, store.'),
    ...pt('//', r'ws_tests.rs and target_diagnostics_stats.rs',
        r'graph, msg, resolver, server.'),
    ...pt('//', r'ingest_loopback.rs', r'graph, msg, resolver.'),
    ...pt('//', r'the pipe-driven tests',
        r'cross_process_wire_gui.rs, cross_process_wire_tui.rs, '
        r'hook_self_load_wire.rs and hook_self_load_spawned_thread.rs '
        r'import graph, ingest, msg and resolver; cross_process_wire.rs '
        r'adds server.'),
    ...pt('//', r'hook_owner_free_no_crash.rs',
        r'nothing: it only spawns processes, which is why 12 of 13 is '
        r'the count above.'),
    ...para('//',
        r'Two names never appear in a "use heaplens_daemon::" line in '
        r'tests/: procs and injector. They are the only modules '
        r'with no test of their own. Their coverage is the live check '
        r'recorded in the commit that added them (a real attach and '
        r'detach against a running process). The hook tests do run '
        r'heaplens-injector.exe itself, but not the daemon’s wrapper '
        r'around it. The pages for those two files say this again, '
        r'because it is the honest edge of the test suite.'),
    ...sec(r'unit tests that live inside the library'),
    ...para('//',
        r'Making the modules a library also lets a module keep its own '
        r'tests with #[cfg(test)]. msg.rs does so for two small pure '
        r'functions, is_current_target_exit and should_reset_on_attach, '
        r'each with a few cases. They are pulled out of the graph '
        r'loop for exactly that reason: the race they guard needs '
        r'real async timing to reproduce, and a pure function can be '
        r'pinned down without it. graph.rs also has tests in a '
        r'cfg(test) block, including one that compares the indexed '
        r'ownership lookup with a brute-force scan. resolver.rs has '
        r'its own as well.'),
    ...sec(r'what a visibility keyword costs'),
    ...para('//',
        r'Making everything pub is the cheapest way to let tests in, '
        r'and the commit that did it first says as much in its '
        r'title: "make all modules pub for test access". The price '
        r'is that the crate has no private surface. Node’s fields, '
        r'the graph’s accessors nodes() and nodes_mut(), '
        r'and StormTracker’s sites map are all pub, and tests rely '
        r'on that. anomaly_unit.rs builds a Node by struct '
        r'literal and reads tracker.sites.len() directly. That is a '
        r'trade, consciously cheap: the crate is an application '
        r'component, not a library that other people depend on, so '
        r'there is no semver promise to protect. A published library '
        r'would put most of this behind a narrower API.'),
    ...sec(r'limits'),
    ...pt('//', r'no documentation on the exports',
        r'the file has no module-level doc comment. The best '
        r'overview of the crate is the order of its own imports, '
        r'which is why this page spells it out.'),
    ...pt('//', r'order is alphabetical, not architectural',
        r'a reader of the file alone would not learn the layering '
        r'above. It has to be recovered from the imports.'),
    ...pt('//', r'one crate for all of it',
        r'splitting the model (resolver, graph, anomaly) into its own '
        r'crate would make the dependency rule above a compiler-checked '
        r'fact instead of a convention. Nothing in the repository '
        r'suggests that was considered; I note it as a possible direction, '
        r'not as a plan.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/src/lib.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/src/lib.rs'),
  ],
);
