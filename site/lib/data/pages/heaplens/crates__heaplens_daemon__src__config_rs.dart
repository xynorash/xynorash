import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/src/config.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'config.rs — every threshold in one struct, overridable by env'),
    cm('//', r'eight fields, no magic numbers anywhere else in the daemon'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'startup configuration: defaults plus HEAPLENS_* env overrides'),
    kv('language', r'Rust'),
    kv('size', r'74 lines'),
    kv('history', r'3 commits, 2026-07-01 to 2026-07-02'),
    kv('read', r'once, at startup, by Config::load() in main.rs'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'The daemon makes several judgment calls that are really '
        r'tuning knobs: how long a childless node must live before it '
        r'is called an orphan, how many children make a cluster hot, '
        r'how many allocations a second make a storm. The M4 plan '
        r'that introduced most of these fields sets the rule in its '
        r'global constraints: "No magic numbers in logic — all '
        r'thresholds from Config". config.rs is where that rule '
        r'lives. Everything that decides something takes a '
        r'&Config; nothing in anomaly.rs or main.rs contains a '
        r'bare 5000 or 32.'),
    blank,
    ...para('//',
        r'The Build Spec is blunt about what these numbers are: "an '
        r'empirically-chosen fan-out heuristic, not a value derived '
        r'from any model", with the instruction to state that plainly. '
        r'A struct of overridable defaults is the honest container '
        r'for values like that. The environment-variable overrides '
        r'are not decorative, either. They are what lets one build '
        r'of the daemon be measured under different parameters (see '
        r'the H1 section below).'),

    ...sec(r'the fields'),
    ...code('rust', 'crates/heaplens-daemon/src/config.rs · Config (trimmed)', r'''
pub struct Config {
    /// Named pipe path the daemon listens on.
    /// Default: r"\\.\pipe\heaplens"
    /// Override: env var HEAPLENS_PIPE
    pub pipe_name: String,

    /// Diff/tick interval in milliseconds.
    /// Default: 33 (≈30 Hz)
    /// Override: env var HEAPLENS_TICK_MS
    pub tick_ms: u64,

    /// Exponential moving average time constant in milliseconds.
    /// Default: 5000
    /// Override: env var HEAPLENS_TAU_MS
    pub tau_ms: u64,

    /// Hot cluster threshold (allocation count).
...
    /// Path to the heap snapshot database.
    /// Default: "heaplens.db"
    /// Override: env var HEAPLENS_DB_PATH
    pub db_path: String,
}
'''),
    ...para('//',
        r'All eight, with their consumers:'),
    ...pt('//', 'pipe_name',
        r'default \\.\pipe\heaplens, HEAPLENS_PIPE. Used by '
        r'ingest::run to create the named pipe.'),
    ...pt('//', 'tick_ms',
        r'33 (about 30 Hz), HEAPLENS_TICK_MS. The period of the '
        r'timer task in main.rs, and so of every diff.'),
    ...pt('//', 'tau_ms',
        r'5000, HEAPLENS_TAU_MS. The orphan age threshold in '
        r'anomaly::sweep; also copied into every OrphanEventRecord.'),
    ...pt('//', 'hot_cluster_threshold',
        r'32, HEAPLENS_HOT_THRESHOLD. A node with more live children '
        r'than this is Hot.'),
    ...pt('//', 'storm_rate_threshold',
        r'1000, HEAPLENS_STORM_RATE. Allocations per window above '
        r'which a site is warned about.'),
    ...pt('//', 'storm_window_ms',
        r'1000, HEAPLENS_STORM_WINDOW_MS. The sliding window for the '
        r'storm tracker.'),
    ...pt('//', 'ws_addr',
        r'127.0.0.1:9999, HEAPLENS_WS_ADDR. The WebSocket bind '
        r'address. The default is loopback only, so the UI '
        r'connection is not reachable from other machines unless '
        r'someone changes it.'),
    ...pt('//', 'db_path',
        r'heaplens.db (relative to the working directory), '
        r'HEAPLENS_DB_PATH. The SQLite file store.rs opens.'),

    ...sec(r'the loader'),
    ...code('rust', 'crates/heaplens-daemon/src/config.rs · Config::load (trimmed)', r'''
impl Config {
    pub fn load() -> Self {
        Config {
            pipe_name: std::env::var("HEAPLENS_PIPE")
                .unwrap_or_else(|_| r"\\.\pipe\heaplens".to_owned()),
            tick_ms: std::env::var("HEAPLENS_TICK_MS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(33),
            tau_ms: std::env::var("HEAPLENS_TAU_MS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(5000),
...
            ws_addr: std::env::var("HEAPLENS_WS_ADDR")
                .unwrap_or_else(|_| "127.0.0.1:9999".to_owned()),
            db_path: std::env::var("HEAPLENS_DB_PATH")
                .unwrap_or_else(|_| "heaplens.db".to_owned()),
        }
    }
'''),
    ...para('//',
        r'Numeric fields share one four-line idiom: read the '
        r'variable, drop the error, try to parse, fall back to the '
        r'default. String fields skip the parse. The shape is '
        r'repeated five times without a helper, which is easy to '
        r'read and slightly easy to get wrong; a typo in one copy '
        r'would not be caught by the others.'),
    blank,
    ...para('//',
        r'The important property is what happens with bad input: '
        r'HEAPLENS_TAU_MS=abc is not an error. .ok() discards the '
        r'missing-variable case and .and_then(|v| v.parse().ok()) '
        r'discards the unparseable case, and both end at unwrap_or, '
        r'so the daemon silently runs with the default. That is a '
        r'defensible choice for a developer tool (it never refuses '
        r'to start over a typo) with a real cost: a misspelled value '
        r'looks exactly like a correct one in the logs. Config::load '
        r'logs nothing.'),

    ...sec(r'units: milliseconds in, nanoseconds underneath'),
    ...para('//',
        r'Config speaks milliseconds because that is how a human '
        r'reads "5 seconds". Event timestamps are nanoseconds. The '
        r'conversion is not done here; it is done at each use site, '
        r'by multiplying by 1,000,000. anomaly.rs does it three times '
        r'(tau in sweep, the storm window in record and evict_idle), '
        r'and the tests do it again '
        r'(config.tau_ms * 1_000_000 + 1). The pattern keeps Config '
        r'a plain bag of numbers; the price is that a new consumer '
        r'has to remember which unit the field is in. The field '
        r'names carry the unit (_ms) for exactly that reason.'),

    ...sec(r'a doc comment that is wrong'),
    ...para('//',
        r'One comment in this file does not match the code, and it '
        r'has not since the commit that introduced it (3ad9b98, '
        r'2026-07-02). The doc on tau_ms reads "Exponential moving '
        r'average time constant in milliseconds." Nothing in the '
        r'daemon computes a moving average. tau_ms is a plain age '
        r'threshold: anomaly::sweep compares '
        r'max_ts_seen.saturating_sub(node.ts) against tau_ms * '
        r'1_000_000, and the Build Spec’s own Config sketch says '
        r'"tau_ms: u64, // orphan age threshold (default 5000)". The '
        r'name tau and the word "exponential" look like a leftover '
        r'from an earlier idea. The right reading of the field is '
        r'the spec’s. It is a small thing, and it is the kind of '
        r'drift that makes a reader doubt every other comment.'),

    ...sec(r'configuration in use: the H1 harness'),
    ...para('//',
        r'The overrides earn their place in crates/h1-harness, the '
        r'tool that measures orphan-detection latency (commit '
        r'816c732, 2026-07-16). For each of 40 runs it spawns a '
        r'fresh daemon and sets three of these variables on the '
        r'child process:'),
    ...pt('//', 'HEAPLENS_DB_PATH',
        r'a per-run SQLite file in the temp directory, so runs never '
        r'share rows.'),
    ...pt('//', 'HEAPLENS_WS_ADDR',
        r'a distinct loopback port per run (a base port plus an '
        r'offset), which presumably keeps one run’s daemon from '
        r'colliding with the next.'),
    ...pt('//', 'HEAPLENS_TAU_MS',
        r'5 for twenty runs and 500 for the other twenty. That '
        r'single knob is the experiment: it moves the binding '
        r'conjunct of the orphan condition from owner-free time to '
        r'node age, and gives two different latency distributions '
        r'(medians of 0.0089 ms and 2.569 ms, per the anomaly.rs '
        r'page). Without an env override, that comparison would '
        r'need two builds.'),
    blank,
    ...para('//',
        r'The harness also sets RUST_LOG=heaplens_daemon=debug, '
        r'which turns on the per-tick debug line main.rs logs. That '
        r'is the logging side of configuration, handled by '
        r'tracing_subscriber::EnvFilter in main().'),

    ...sec(r'how it is tested'),
    ...para('//',
        r'It is not, directly. The M4 plan says so in the task that '
        r'created the fields: "No tests needed (config fields are '
        r'trivial defaults; covered by build)". No test calls '
        r'Config::load, sets an environment variable, or checks a '
        r'default. What the tests do is construct Config by hand. '
        r'Three test files (tests/anomaly_unit.rs, tests/graph_unit.rs '
        r'and tests/orphan_persistence.rs) each write out a full '
        r'struct literal with all eight fields, including pipe_name, '
        r'ws_addr and db_path that the test never uses. The fields '
        r'are public and there is no Default impl or builder, so '
        r'adding a ninth field is a compile error in all three at '
        r'once. The same property is also a feature: nobody can '
        r'forget to supply a field.'),

    ...sec(r'limits'),
    ...pt('//', 'silent fallback on bad input',
        r'Described above. A warning when parsing fails would cost '
        r'a few lines.'),
    ...pt('//', 'HEAPLENS_PIPE is daemon-side only',
        r'The producer’s writer thread has its own constant, '
        r'PIPE_PATH = r"\\.\pipe\heaplens", in heaplens-alloc/src/'
        r'writer.rs, and no code reads HEAPLENS_PIPE except this '
        r'file. Overriding the variable on the daemon would leave '
        r'the producer dialling the old name. The default also '
        r'appears as a literal in the PIPE_NAME constant of each '
        r'test that connects to a pipe.'),
    ...pt('//', 'the port is duplicated too',
        r'The launcher (crates/heaplens-launcher/src/main.rs) has '
        r'its own WS_ADDR constant, "127.0.0.1:9999", the same value '
        r'as this file’s default. If the default changed here and '
        r'not there, the launcher would wait on the wrong port.'),
    ...pt('//', 'relative database path, no rotation',
        r'The default "heaplens.db" resolves against whichever '
        r'directory the daemon was started in, and the store '
        r'appends to an existing file rather than starting fresh '
        r'(see store.rs).'),
    ...pt('//', 'read once',
        r'There is no reload. Changing a threshold means restarting '
        r'the daemon, which also loses the in-memory graph.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
