import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/src/resolver.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'resolver.rs — addresses to names, and a third state for "not yet"'),
    cm('//', r'a 93-line join table whose design is in its three answers'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'address -> (function name, is_machinery) lookup for the graph'),
    kv('language', r'Rust'),
    kv('size', r'93 lines, 38 of them tests'),
    kv('history', r'5 commits, 2026-07-01 to 2026-07-22'),
    kv('fed by', r'GraphMsg::Symbols, from SYMBOLS frames on the pipe'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'Events arrive as raw instruction pointers. φ matches function '
        r'names. Something has to hold the mapping, and the Build Spec '
        r'(section 5.4) is deliberately modest about what: "Pure '
        r'lookup/join. No symbolization is performed here (the '
        r'allocator already did it)." The producer’s writer thread '
        r'resolves each new address once, off the allocation hot path, '
        r'and sends (address, name, is_machinery) in a SYMBOLS frame. '
        r'The daemon only remembers what it was told.'),
    blank,
    ...para('//',
        r'Splitting the work this way keeps debug-info parsing in the '
        r'process that has the modules loaded and out of the daemon, '
        r'which may be a different process, a different privilege '
        r'level, and possibly not even running yet when the producer '
        r'starts. The cost is that the daemon is only ever as '
        r'informed as the last SYMBOLS frame it received. Almost '
        r'everything interesting in this file is about that gap.'),

    ...sec(r'the table'),
    ...code('rust', 'crates/heaplens-daemon/src/resolver.rs · Resolver, insert and name_for', r'''
/// Maps address -> (resolved name, is_machinery). `is_machinery` is supplied
/// by the writer thread (see heaplens-alloc's writer.rs classification) and
/// distinguishes shared allocation-instrumentation frames from genuine
/// caller code, letting the daemon locate a node's real call site without
/// assuming any fixed frame index.
pub struct Resolver {
    map: HashMap<u64, (String, bool)>,
}

impl Default for Resolver {
    fn default() -> Self {
        Self::new()
    }
}

impl Resolver {
    pub fn new() -> Self {
        Resolver { map: HashMap::new() }
    }

    pub fn insert(&mut self, addr: u64, name: String, is_machinery: bool) {
        self.map.insert(addr, (name, is_machinery));
    }

    /// Returns the resolved name for `addr`, or `"0x{addr:x}"` if unknown.
    pub fn name_for(&self, addr: u64) -> String {
        self.map
            .get(&addr)
            .map(|(name, _)| name.clone())
            .unwrap_or_else(|| format!("0x{addr:x}"))
    }
'''),
    ...para('//',
        r'The first version (ca677ce, 2026-07-01) stored just a name, '
        r'as the spec’s HashMap<u64, String> said. The boolean was '
        r'added on 2026-07-08 in the same commit (43fc22e) that '
        r'wired the previously-discarded SYMBOLS frames into the '
        r'daemon at all. The doc comment explains why the flag lives '
        r'next to the name: it lets the daemon "locate a node’s real '
        r'call site without assuming any fixed frame index". Before '
        r'that, the daemon took stack[0] as the call site, which on a '
        r'real trace is always the capture machinery.'),
    blank,
    ...para('//',
        r'name_for never fails: an unknown address renders as '
        r'"0x{addr:x}" (the test pins name_for(0) == "0x0"). The '
        r'hex string is a contract, not a cosmetic: graph.rs counts '
        r'a live node as "hex fallback" by checking whether its '
        r'resolved name starts_with("0x"), and the Flutter banner '
        r'uses that count to say "unsymbolized target".'),

    ...sec(r'who decides what counts as machinery'),
    ...para('//',
        r'Not this file. The writer thread in heaplens-alloc '
        r'classifies each name with a prefix list, and the daemon '
        r'trusts the verdict. The list, as of 2026-07-28:'),
    ...code('rust', 'crates/heaplens-alloc/src/writer.rs · the classifier (trimmed)', r'''
const MACHINERY_PREFIXES: &[&str] = &[
    "heaplens_alloc::",
...
    "heaplens_hook::",
    "backtrace::",
    "alloc::",
    "core::alloc::",
    "core::ptr::drop_in_place",
    "std::collections::",
];
...
const MACHINERY_SHIM_SUBSTRINGS: &[&str] = &[
    "__rust_alloc",
    "__rust_dealloc",
    "__rust_realloc",
    "__rust_no_alloc_shim",
];

fn is_machinery_symbol(name: &str) -> bool {
    MACHINERY_PREFIXES.iter().any(|p| name.starts_with(p))
        || MACHINERY_SHIM_SUBSTRINGS.iter().any(|s| name.contains(s))
}
'''),
    ...para('//',
        r'The second list matches the compiler-generated __rust_alloc '
        r'shims as substrings, because they are namespaced under the '
        r'consuming binary (wire_producer::_::__rust_alloc), and a '
        r'prefix check misclassified them as real code, which per '
        r'its doc comment "produced zero ownership edges against the '
        r'real wire_producer.exe despite the function-name-matching '
        r'fix being logically correct".'),
    blank,
    ...para('//',
        r'Two further lessons about the prefix list are recorded in '
        r'its doc comment and in two commits, and both bear on why φ '
        r'needs an honest resolver. First, the list used to name particular stdlib '
        r'shims (alloc::vec::from_elem and so on) and missed '
        r'Vec::with_capacity, which made a container name itself by '
        r'a frame no child could ever search for (commit e9c73d2; the '
        r'graph.rs page has the full story). The fix was to classify '
        r'the whole alloc:: crate, matched with a trailing "::" so '
        r'that "myapp::allocate_buffer" can never match. Second, on '
        r'2026-07-28 (50a9627) the list was found to be missing '
        r'heaplens_hook::, so under injection every allocation’s '
        r'nearest non-machinery frame was the hook trampoline itself, '
        r'which made "zero real ownership/anomaly data under '
        r'injection, masked as Dominant consumer at heaplens_hook::'
        r'hook_heap_alloc". It had been masked because a '
        r'cooperative producer always connected first and supplied '
        r'the correct stream.'),
    blank,
    ...para('//',
        r'The resolver is just where those two bugs would have been '
        r'visible, if anyone had looked there: the data was right, '
        r'the classification column was wrong.'),

    ...sec(r'three answers, not two'),
    ...code('rust', 'crates/heaplens-daemon/src/resolver.rs · is_machinery and is_known', r'''
/// Returns whether `addr` is classified as shared instrumentation.
/// An address whose SYMBOLS frame hasn't arrived yet is treated as
/// machinery (defer, don't guess) — it will stop being skipped as soon
/// as its real classification arrives, since phi recomputes the
/// effective site fresh on every match rather than caching it.
pub fn is_machinery(&self, addr: u64) -> bool {
    self.map.get(&addr).map(|(_, m)| *m).unwrap_or(true)
}

/// Whether a SYMBOLS frame has arrived for `addr` at all — distinct from
/// `is_machinery`, which treats "unknown" and "known machinery" the same
/// way (both skip). Callers that need to tell "genuinely, permanently
/// machinery" apart from "not resolved yet, could turn out to be real
/// code" — e.g. `graph::classify_effective_site`, deciding whether a
/// node's φ candidacy is stable or still provisional — need this
/// distinction; `is_machinery` alone cannot provide it.
pub fn is_known(&self, addr: u64) -> bool {
    self.map.contains_key(&addr)
}
'''),
    ...para('//',
        r'For any address there are three possible states, and the '
        r'two-method API distinguishes all of them:'),
    ...pt('//', 'known real code',
        r'is_known true, is_machinery false. φ may use it as a '
        r'call site or an owner name.'),
    ...pt('//', 'known machinery',
        r'is_known true, is_machinery true. Skipped, permanently.'),
    ...pt('//', 'unknown',
        r'is_known false, and is_machinery reports true. Skipped '
        r'for now.'),
    blank,
    ...para('//',
        r'The comment on is_machinery gives the policy: an address '
        r'"whose SYMBOLS frame hasn’t arrived yet is treated as '
        r'machinery (defer, don’t guess)". The alternative, treating '
        r'unknown as real code, would let any address that is '
        r'merely not yet resolved become some node’s effective site '
        r'and be matched by name "0x…". The conservative choice '
        r'errs toward missing an edge for a moment instead of '
        r'inventing one.'),
    blank,
    ...para('//',
        r'That policy is correct for a fresh computation and wrong '
        r'for anything persistent, which is why is_known exists. It '
        r'was added on 2026-07-22 (783b2d3) when graph.rs grew the '
        r'site index: an index keyed by "today’s answer" would '
        r'permanently mis-file a node whose address resolves '
        r'tomorrow. The doc comment says exactly that: callers that '
        r'must tell "genuinely, permanently machinery" apart from '
        r'"not resolved yet, could turn out to be real code" need '
        r'is_known, because is_machinery "alone cannot provide it". '
        r'See SiteClass on the graph.rs page.'),
    blank,
    ...para('//',
        r'How often is the third state actually hit? graph.rs says '
        r'pending nodes are rare "in real traffic" because the writer '
        r'resolves every address a batch’s events reference before '
        r'sending that batch. The state exists for the general '
        r'case, and for tests, which insert symbols after events on '
        r'purpose.'),

    ...sec(r'the daemon-side lifecycle'),
    ...pt('//', 'created empty',
        r'Resolver::new() in main.rs at startup.'),
    ...pt('//', 'filled by the Symbols arm',
        r'for (addr, name, is_machinery) in syms { resolver.insert(...) }'),
    ...pt('//', 'never pruned',
        r'No entry is ever removed. The key space is instruction '
        r'addresses seen in captured stacks, so it grows with the '
        r'distinct code locations the target allocates from, not with '
        r'the number of allocations. That is my reasoning from what '
        r'the keys are; the repository has no measurement of the '
        r'table’s size.'),
    ...pt('//', 'replaced on a real target switch',
        r'main.rs assigns resolver = Resolver::new() when '
        r'should_reset_on_attach says the pid is new, and leaves it '
        r'alone otherwise. The b649234 bug (2026-07-26) is the '
        r'resolver being cleared when the producer would never '
        r'resend what it had cleared: a table that is lost while '
        r'its source keeps its own memory is a table that stays '
        r'empty.'),
    ...pt('//', 'last write wins',
        r'insert() overwrites. insert_overwrites_previous pins that '
        r'a later SYMBOLS entry for the same address replaces both '
        r'name and flag.'),

    ...sec(r'how it is tested'),
    ...code('rust', 'crates/heaplens-daemon/src/resolver.rs · two of the four tests (trimmed)', r'''
#[test]
fn unknown_addr_returns_hex_fallback_and_is_machinery() {
    let r = Resolver::new();
    assert_eq!(r.name_for(0x1234), "0x1234");
    assert_eq!(r.name_for(0), "0x0");
    assert!(r.is_machinery(0x1234));
}
...
#[test]
fn machinery_classification_is_queryable_independently_of_name() {
    let mut r = Resolver::new();
    r.insert(0x200, "heaplens_alloc::capture::capture_stack".to_owned(), true);
    r.insert(0x300, "my_crate::do_work".to_owned(), false);
    assert!(r.is_machinery(0x200));
    assert!(!r.is_machinery(0x300));
}
'''),
    ...para('//',
        r'Four unit tests live in the file: a known address returns '
        r'its name and is not machinery; an unknown address returns '
        r'hex and is machinery; insert overwrites; and the '
        r'classification is readable independently of the name '
        r'(capture_stack is machinery, do_work is not). The '
        r'interesting behaviour, the interaction with φ, is tested '
        r'elsewhere: tests/graph_unit.rs has '
        r'drain_diff_uses_placeholder_for_unresolved_symbol (an '
        r'unknown address yields the symbol "?" because nothing is '
        r'an effective site) and graph.rs has the Pending-promotion '
        r'scenario.'),

    ...sec(r'limits'),
    ...pt('//', 'trust, not verification',
        r'The daemon cannot check a name. A producer that sends a '
        r'wrong name (or a wrong flag) silently corrupts φ for that '
        r'address, which is how the heaplens_hook:: omission '
        r'went unnoticed.'),
    ...pt('//', 'addresses are not stable forever',
        r'The map assumes an address means one function for the '
        r'life of the table. A target that unloads and reloads a '
        r'module at a different address, or reuses an address for '
        r'different code, would be described by whichever mapping '
        r'arrived last. I found no handling or test of module '
        r'unload.'),
    ...pt('//', 'no symbol provenance',
        r'Nothing records which frame batch or module a symbol came '
        r'from, so a "0x…" in the UI cannot be traced further here.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
