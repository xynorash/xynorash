import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/src/lib.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'lib.rs — ten lines that make the daemon testable'),
    cm('//', r'nothing but a list of pub mod, and the reason every one of them is pub'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'library root of heaplens-daemon'),
    kv('language', r'Rust'),
    kv('size', r'10 lines, five commits touch it (9843e94 on 2026-07-01 to 724695a on 2026-07-19)'),
    kv('exports', r'anomaly, config, graph, ingest, injector, msg, procs, resolver, server, store'),
    ...sec(r'the whole file'),
    ...code('rust', r'crates/heaplens-daemon/src/lib.rs · lines 1-10', r'''
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
    ...sec(r'what it is for'),
    ...para('//',
        r'There is no logic in this file. Its job is to turn the daemon from one executable into a crate whose modules other crates can name. Rust integration tests live in tests/ and compile as separate crates, so they see only items the library declares pub. A binary-only daemon would have nothing for them to import.'),
    blank,
    ...para('//',
        r'The history points the same way. The scaffold in 23e20df declared the modules in main.rs, and f12b3e6 ("make all modules pub for test access", 2026-07-01) flipped those declarations to pub mod in main.rs. lib.rs itself first appears in 9843e94 with the five modules that existed then (config, graph, ingest, msg, resolver). After that the list grew as each module was written: anomaly (eaa6162), store (88dedac), server (9174573), and in the Stage 7 port (724695a) injector and procs.'),
    blank,
    ...sec(r'how the pieces named here fit together'),
    ...para('//',
        r'Read the ten names as a pipeline, not a directory listing.'),
    blank,
    ...pt('//', r'ingest',
        r'reads framed bytes from the named pipe the target writes to, decodes them with the protocol crate’s FrameDecoder and sends GraphMsg values down a channel.'),
    ...pt('//', r'msg',
        r'the vocabulary the tasks use to talk: GraphMsg, StoreMsg, ConnectRequest, TargetCmd and the OrphanEventRecord.'),
    ...pt('//', r'graph and resolver',
        r'the ownership graph and the address-to-symbol table. Together they turn raw alloc and dealloc events into nodes and ownership edges.'),
    ...pt('//', r'anomaly',
        r'sweeps the graph on each tick for orphans, hot clusters and allocation storms.'),
    ...pt('//', r'store',
        r'a SQLite thread that batches nodes and orphan events to disk.'),
    ...pt('//', r'server',
        r'the WebSocket edge: snapshot on connect, diffs afterwards, control requests in both directions.'),
    ...pt('//', r'procs and injector',
        r'Stage 7 only: list processes for the picker, and run heaplens-injector.exe to attach or detach a hook DLL.'),
    ...pt('//', r'config',
        r'the knobs every other module reads, including the pipe name and the WebSocket address.'),
    ...sec(r'why this matters for the tests'),
    ...para('//',
        r'Every test file in crates/heaplens-daemon/tests/ opens with use heaplens_daemon::... and each of those paths is one line in this file. The unit-style specs (graph_unit, anomaly_unit, store_tests) call the module functions directly. The loopback and wire tests assemble the same modules main.rs does, ingest, graph, server, store, in the test process, which is only possible because lib.rs exposes them.'),
    blank,
    ...sec(r'what to notice'),
    ...para('//',
        r'Two modules have no direct test: injector and procs. The tests import neither one (a search of the tests directory finds no use of injector::attach, injector::detach or list_processes), and they pass a target_tx whose receiver nothing reads, so control requests are not exercised through the server either. Those two are covered only by running the real daemon with the real injector, as the commit message of 724695a records ("live end-to-end — process picker populates, real attach/detach").'),
    blank,
    ...para('//',
        r'Also, no module is private. The whole internal API is therefore public surface of the crate, so a rename is visible to every test.'),
    blank,
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/src/lib.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/src/lib.rs'),
  ],
);
