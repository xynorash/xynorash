import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/docs/HeapLens_Build_Spec.md',
  lines: [
    heading('# HeapLens — Technical Build Specification'),
    blank,
    ...text('The document the whole project was built from: written '
        'before the first line of Rust, addressed to an autonomous '
        'coding agent, and then amended by every surprise the '
        'implementation found.'),
    blank,
    kv('role', 'single source of truth for architecture, contracts, invariants'),
    kv('audience', 'Claude Code, per its own first line'),
    kv('size', '769 lines · sections 0 to 12'),
    kv('history', '597 lines on 2026-06-24, +171 on 2026-07-08, +1 on 2026-07-17'),
    kv('language', 'English, with French terms for the thesis context'),

    ...sec('what this document is'),
    ...text('Most projects keep their design in someone’s head and '
        'recover it from the code later. HeapLens did the opposite: '
        'the first commit (a55f7c1, 2026-06-24, dated before any '
        'allocator or graph code existed) already contains 597 lines '
        'of this specification, the 407-line UML document and the '
        'protocol plan and design spec. The code was then written '
        'against the text.'),
    ...text('The document addresses its reader directly. The '
        'header names the reader, and the first instruction is a '
        'reading order:'),
    ...code('markdown',
        'docs/HeapLens_Build_Spec.md · opening lines (re-wrapped)', r'''
**Audience:** Claude Code (autonomous development).
> Read this whole document before writing code.
Build in the order given in §9.
Never violate the invariants in §12.'''),
    ...text('That framing explains the style. A spec for an '
        'autonomous reader cannot lean on shared context, so it '
        'states what each unit must not know about, gives exact '
        'byte offsets, fixes the order of work, and lists rules '
        'that may never be broken. The plans in docs/superpowers '
        'carry the same assumption in their headers (three of the '
        'five open with “For agentic workers”). The repository '
        'does not record who typed what. What it does record is '
        'the human side of the loop: decisions marked as locked in '
        'the plans, and fixes accepted only after live checks. The '
        'milestone addendum in the M5 plan closes two visual gates '
        'on “direct user observation”.'),

    ...sec('the structure: four units, two seams'),
    ...text('Section 1 is the part of the document that never '
        'changed, and the one every later decision leans on. There '
        'are four units, each with a single responsibility and, '
        'just as important, a column naming what it must not know '
        'about.'),
    ...bullet('heaplens-protocol', 'pure data and (de)serialization. '
        'It must not know about anything: no threads, no I/O.'),
    ...bullet('heaplens-alloc', 'intercept every allocation and ship '
        'raw events off-process without blocking. It must not know '
        'about graphs, ownership, anomalies or rendering.'),
    ...bullet('heaplens-daemon', 'ingest, build the ownership graph, '
        'detect anomalies, persist, broadcast diffs. It must not '
        'know how the allocator captures events or how Flutter '
        'renders.'),
    ...bullet('heaplens-flutter', 'render the graph and expose '
        'controls. It must not know about Rust, allocators or the '
        'daemon’s internals.'),
    blank,
    ...text('Between the units there are exactly two coupling '
        'points, and the document says so in one sentence:'),
    ...code('markdown', 'docs/HeapLens_Build_Spec.md · §1.2 (trimmed)', r'''
There are exactly **two** coupling contracts. Everything else is private.
1. **Binary frame protocol** (`heaplens-alloc` → `heaplens-daemon`)
2. **JSON diff protocol** (`heaplens-daemon` → `heaplens-flutter`)'''),
    ...text('The rule that follows, stated in §1.2, is that a '
        'change in how two units talk is made in one place, and no '
        'unit parses another’s private structures. It has held. '
        'When the Stage 7 control channel was added, ControlRequest '
        'and ControlResponse went into heaplens-protocol/src/'
        'control.rs, and the Flutter models "already matched the '
        'wire contract exactly" (the wording of commit 724695a), so '
        'the port needed no Dart changes.'),
    ...text('§1.3 gives the reason for the process boundary '
        'that the whole design hangs on: the allocator lives inside '
        'the observed program, the daemon does not, so graph '
        'construction, symbol lookups, persistence and WebSocket '
        'traffic can never slow or destabilize the program being '
        'watched. The named pipe is the only thing between them.'),

    ...sec('the ten invariants'),
    ...text('Section 12 is a list of ten rules under the heading '
        '“never violate”. Each one is a fact about what makes a '
        'heap tracer unsafe to run inside someone else’s process, '
        'which is why they are phrased as absolutes rather than '
        'guidelines.'),
    ...code('markdown', 'docs/HeapLens_Build_Spec.md · §12 (trimmed)', r'''
1. **The allocator never heap-allocates on the critical path**
2. **The allocator never locks** on the critical path. Lock-free ring only.
3. **The allocator never panics** in the host process.
4. **The writer thread permanently holds the recursion guard**
5. **The ring's backing store is allocated via `System` directly**
6. **The daemon never symbolizes**
7. **No unit parses another unit's private types.**
8. **The two seams are the single source of truth.**
9. **No graph/anomaly/persistence work on the ingest hot path**
10. **Flutter knows only JSON.**'''),
    ...text('Why each exists, and where it shows up in the code:'),
    ...bullet('1 and 4 (no allocation, permanent guard)',
        'allocating inside an allocator recurses forever. record() '
        'sets a per-thread flag first, and the writer thread sets it '
        'for life so its own buffers, hash maps and symbol strings '
        'are never recorded.'),
    ...bullet('2 (no locks)',
        'a lock on every allocation serializes every thread in the '
        'host. The ring is lock-free, one per thread. This is the '
        'invariant that reality bent, covered below.'),
    ...bullet('3 (never panic)',
        'a panic inside alloc aborts the host. The recorded rule '
        'is cheap to state and shaped later code: the encoders '
        'return Option instead of panicking (fa3fe78), so a '
        'malformed batch cannot kill the writer thread.'),
    ...bullet('5 (ring from System)',
        'the spec states the rule and not the reason; the obvious '
        'one is that ring storage taken from the global allocator '
        'would be recorded by the very code it feeds.'),
    ...bullet('6 (daemon never symbolizes)',
        'addresses only mean something inside the process that '
        'owns them, so the writer thread resolves names there and '
        'ships ready address-to-name pairs. The daemon only joins.'),
    ...bullet('7, 8, 10 (seams)',
        'the same idea from three sides: the contract lives in '
        'one crate, and the UI sees nothing but JSON.'),
    ...bullet('9 (nothing heavy on ingest)',
        'work is routed over channels to a single owning task, '
        'so there is no shared mutable graph and no lock to contend.'),
    blank,
    ...text('Section 7, cross-cutting rules, adds one that came '
        'from experience rather than design. It was appended on '
        '2026-07-17 (91a41f6) after the same mistake had happened '
        'three times:'),
    ...code('markdown', 'docs/HeapLens_Build_Spec.md · §7 (excerpt)', r'''
a new variant meets an old wildcard that was written when the enum had fewer cases'''),
    ...text('The rule says that when a variant is added to '
        'GraphMsg, GraphMessage or Frame, grep the whole test suite '
        'for matches on that enum and audit every “_ =>” arm. The '
        'compiler catches non-exhaustive matches; it cannot catch a '
        'catch-all silently swallowing a case it was never written '
        'to expect, which is how a real test broke three times. The '
        'commit message calls the note “cheap insurance against the '
        'fourth instance”. Turning a recurring bug into a written '
        'procedure is the habit that makes the rest of this '
        'document credible.'),

    ...sec('section 3: the contract, down to the byte'),
    ...text('The protocol section is where the spec is most '
        'precise. The event record is fixed-size and repr(C), with '
        'the offset of every field written in a comment and the '
        'size enforced at compile time:'),
    ...code('markdown', 'docs/HeapLens_Build_Spec.md · §3.1', r'''
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AllocEvent {
    pub kind: u8,         // @0   EventKind as u8
    pub stack_len: u8,    // @1   number of valid frames in `stack`
    pub _pad: [u8; 2],    // @2   explicit padding
    pub align: u32,       // @4   allocation alignment
    pub ptr: u64,         // @8   allocated pointer (0 on failure)
    pub old_ptr: u64,     // @16  previous pointer (Realloc only, else 0)
    pub size: u64,        // @24  size in bytes
    pub ts_nanos: u64,    // @32  monotonic timestamp (ns since process start)
    pub stack: [u64; 8],  // @40  raw return addresses; unused slots = 0
}                          // total size = 104, align = 8
const _: () = assert!(core::mem::size_of::<AllocEvent>() == 104);'''),
    ...text('Three decisions are visible in that block. Padding '
        'is an explicit field, so the struct has no hidden bytes '
        'and its raw memory can be shipped as-is. The constant '
        '“size” is asserted by the compiler, so a layout drift is '
        'a build error and not a corrupted stream. And time is '
        'monotonic and relative to process start, never wall-clock, '
        'which is what lets the daemon later define “now” as the '
        'newest timestamp it has seen.'),
    ...text('Frames wrap records with a length prefix and a type '
        'byte, little-endian throughout:'),
    ...code('markdown', 'docs/HeapLens_Build_Spec.md · §3.2', r'''
Frame:
  [u32 length]      # number of bytes that follow (type byte + payload)
  [u8  frame_type]
  [payload ...]     # (length - 1) bytes'''),
    ...text('Producer-side batching is also pinned in the text '
        '(§3.3): flush at 64 events or every 1 ms, whichever comes '
        'first, send each symbol once. The writer today still reads:'),
    ...code('rust', 'crates/heaplens-alloc/src/writer.rs · constants (trimmed)', r'''
const BATCH_CAP: usize = 64;
const FLUSH_INTERVAL: Duration = Duration::from_millis(1);'''),
    ...text('The JSON half (§3.4) fixes field names as the '
        'contract (“JSON field names are the contract”) and '
        'defines the snapshot-then-diff pattern: one full state '
        'on connect, then only changes about every 33 ms.'),

    ...sec('where the contract drifted, and why'),
    ...text('A spec this exact is also easy to falsify, and '
        'three parts of its contract changed. None of them is a '
        'failure of planning; each was forced by something only '
        'running code could show.'),
    ...bullet('104 bytes became 168',
        'the event carries 16 return addresses, not 8. 8 frames '
        'could contain zero user frames, because vec![0u8; n] puts '
        'six or more std frames between the allocator shim and the '
        'caller. The comment in event.rs records the reason, and '
        'the size constant is now 168.'),
    ...bullet('the SYMBOLS frame gained a byte',
        'each entry now ends with an is_machinery flag, so the '
        'writer can tell the daemon which frames belong to the '
        'instrumentation and which to the program. §3.2 still '
        'shows the old SymbolDef layout. Both changes landed in '
        '43fc22e on 2026-07-08, the commit that finally made '
        'ownership inference work.'),
    ...bullet('the decoder got more suspicious',
        'the spec says to resync one byte at a time when the '
        'length prefix is absurd. The decoder also checks that '
        'the length is plausible for the frame type (an events '
        'length must be three plus a multiple of the record size) '
        'and cross-checks handshake lengths against the embedded '
        'name length. That tightened the resync until random bytes '
        'rarely look like a frame.'),
    blank,
    ...text('The lesson is not that the numbers were wrong. It is '
        'that every constant in the contract sits in one crate and '
        'one document, so changing 104 to 168 is one edit and a '
        'compile error in every consumer that hard-coded it.'),

    ...sec('section 4: the allocator the spec imagined'),
    ...text('§4 specifies the capture side down to the call '
        'order of record(): check the guard, set it, capture '
        'timestamp and stack, build the event, push to the ring. '
        'It also contains the earliest recorded design uncertainty, '
        'in the paragraph on rings. A strict single-producer ring '
        'assumes one producing thread; real programs have many. The '
        'spec lists options, then picks the simplest correct one: '
        '“one ring per thread … Do not use a Mutex.”'),
    ...text('The guard section is the most interesting in '
        'hindsight. The spec prescribes a thread-local flag. The '
        'weak spot it admits is a different one (if TLS '
        'initialisation itself allocates, the nested call proceeds '
        'once: “acceptable; document it”):'),
    ...code('markdown', 'docs/HeapLens_Build_Spec.md · §4.3 (trimmed)', r'''
use std::cell::Cell;
thread_local! { static IN_ALLOC: Cell<bool> = const { Cell::new(false) }; }'''),
    ...text('That design was implemented as written and worked '
        'for the cooperative allocator for nearly three weeks. It failed '
        'only when Stage 7 loaded the same code from a DLL. On '
        '2026-07-21 (dcc76f2) it was replaced with raw TlsAlloc '
        'and FlsAlloc calls, because rustc may implement '
        'thread_local! with a PE .tls variable that the loader '
        'only wires up reliably for the thread that called '
        'LoadLibraryW. The full '
        'story belongs to the guard.rs page. What matters here is '
        'that the spec’s choice was reasonable for the problem it '
        'was written for and wrong for a problem that did not '
        'exist yet.'),
    ...text('Invariant 2 also bent. Windows documents dbghelp as '
        'unsafe for concurrent calls, and 9c4678e (2026-07-19) '
        'added a global DBGHELP_LOCK around '
        'every call into the backtrace backend, including the '
        'capture on the allocation path. A mutex on the hot path '
        'is exactly what invariant 2 forbids. A week later b5c5aed '
        'turned that lock into a try_lock after a WinDbg-diagnosed '
        'deadlock: a contended or orphaned lock now yields an empty '
        'stack for one event instead of blocking. The invariant '
        'survived by changing its meaning from “never touch a lock” '
        'to “never wait on one”.'),
    ...text('The last notable difference is order of operations. '
        'The spec records Dealloc after System.dealloc. The code '
        'records it before. The commit (69e61dd) gives no reason; '
        'a plausible reading is that once the memory is returned another '
        'thread can receive the same address and record its Alloc '
        'before this thread records the Dealloc, which the daemon '
        'would then apply to the wrong node. That is an inference '
        'from the ordering, not a quoted rationale.'),

    ...sec('section 5: the daemon, and the long paragraph about φ'),
    ...text('The daemon section is also where the document '
        'grew. The original description of ownership inference '
        'was one sentence, whose last two words were the '
        'instruction “Heuristic; document.” When the code finally '
        'met a real compiled binary, that sentence turned into the '
        'longest paragraph in the file, plus five new subsections.'),
    ...text('What the first φ got wrong is told by the M3 plan: '
        'it matched a node’s first stack address against any '
        'address in the new allocation’s stack. Two statements in '
        'the same function have different addresses and the same '
        'name, so nothing linked. The spec’s replacement says this '
        'directly (“exact-address matching produced zero edges for '
        'this exact shape”) and states what an edge now claims:'),
    ...code('markdown',
        'docs/HeapLens_Build_Spec.md · §5.3 (single line, tail)', r'''
Heuristic by design; do not read an edge as a proof of ownership.'''),
    ...text('The tie-break, the one place φ must choose between '
        'candidates, gets its own subsection that refuses to '
        'overstate it:'),
    ...code('markdown', 'docs/HeapLens_Build_Spec.md · §5.3 tie-break', r'''
Among live nodes whose effective-site name matches, **the discriminator is
recency: greatest `ts`, tie-broken by greatest `id`.** This is not a
dynamic-extent or thread-aware check — `Node` carries no thread id, no
call/return bracketing. It is "which same-named node was most recently
allocated," nothing more. Two consequences, both tested:'''),
    ...text('“Both tested” is literal. The subsection names the '
        'tests: one proves recency partitions K sequential '
        'invocations of the same function correctly, one pins the '
        'case where a late child is attributed to a newer '
        'same-name owner. The failure mode is a regression test '
        'rather than a rumour. (A small wording tension: the '
        'mémoire paragraph below says the earliest live '
        'same-function allocation “is the owner”, while the rule '
        'selects the greatest ts among candidates. The first is '
        'best read as describing which allocation ends up the root '
        'and the second as the selection among candidates; the '
        'tests in graph_unit.rs are the arbiter.)'),
    ...text('The thresholds are also stripped of false authority. '
        'The spec says outright that 32 and 5000 were chosen, not '
        'derived:'),
    ...code('markdown', 'docs/HeapLens_Build_Spec.md · Jury Q&A', r'''
- *"Why 32? Why 5 seconds?"* → Both configurable, empirically-chosen,
  structural (not rate-based) heuristics — not derived values. `tau_ms` is a
  visual-fade window, not detection latency.'''),
    ...text('That last clause is what the H1 benchmark later '
        'depends on, with a correction. The spec says a node turns '
        'Orphan structurally, the instant its owner is freed, and '
        'that tau only governs the visual fade. The shipped sweep '
        'is stricter: anomaly.rs marks a node Orphan only once the '
        'node’s own age exceeds tau, so tau does gate the state. '
        'The H1 commit (816c732) resolves it by measuring from the '
        'later of the two conditions, owner-free time or node time '
        'plus tau, so tau is subtracted out. See '
        'docs/bench_results/h1_latency.csv.'),

    ...sec('the φ operating envelope'),
    ...text('Appended on 2026-07-08, this section is the '
        'compact statement of what φ needs from the world: '
        'symbolizable frames. Its core is the instruction that '
        'became a line in Cargo.toml:'),
    ...code('markdown', 'docs/HeapLens_Build_Spec.md · §5.3 debug info', r'''
   build-configuration requirement, not an inference-logic change. **Any
   deployment or benchmark build of HeapLens must carry full debug info
   even in release, or φ's attribution silently degrades to near-zero
   edges without any error** — this is now permanent, not opt-in, and
   applies to every future release build on this workspace, including H2.'''),
    ...text('A second finding in the same section is easy to '
        'misread as a bug: a long-lived container in main ends up '
        'owning everything allocated anywhere in its dynamic '
        'scope, because φ searches the whole ancestor stack, not '
        'just the immediate caller. The document records that the '
        'immediate-caller-only alternative was considered and '
        'rejected because it would blind φ to any relationship '
        'deeper than one frame. It then closes by saying both '
        'properties are shared by stack-based profilers generally. '
        'The same section carries a note for the thesis: φ is '
        'defined over the observed, symbolized call structure, not '
        'over source-level structure.'),

    ...sec('where the spec and the daemon part ways'),
    ...text('Several parts of §5 describe a design that was '
        'simplified when the milestone plans were written, and the '
        'text was not always revised. These are worth knowing '
        'before trusting the spec over the code:'),
    ...bullet('hot clusters',
        '§5.5 describes growth detection per connected component: '
        '“if total size grew > growth_pct over the last window”, '
        'with growth_pct and growth_window_ms in the config. The '
        'M4 plan locked a simpler rule, and anomaly.rs implements it:'),
    ...code('rust', 'crates/heaplens-daemon/src/anomaly.rs · sweep()', r'''
        let is_hot = node.edges_out.len() > config.hot_cluster_threshold;'''),
    ...text('A node is Hot when it has more than 32 children. The '
        'growth fields do not exist in config.rs. The spec itself '
        'calls the threshold “an empirically-chosen fan-out '
        'heuristic”, which describes the shipped rule better than '
        'the §5.5 text does.'),
    ...bullet('persistence',
        '§5.6 specifies an alloc_events table of raw events. The '
        'M4 plan stores processed nodes instead (locked decision '
        'Q1), and store.rs creates a nodes table plus an '
        'orphan_events table added for the H1 measurement.'),
    ...bullet('examples',
        '§8 names three leak programs (leak_rc_cycle, '
        'leak_unbounded, leak_channel) in a top-level examples/ '
        'directory. None exists anywhere in the git history. The '
        'real producers live in crates/heaplens-alloc/examples: '
        'wire_producer, demo_producer, hot_producer, four chaos_* '
        'scenarios and the checkout_service family.'),
    ...bullet('README',
        '§2 draws a README.md at the repository root. There is '
        'none; the project README page in this tree is where the '
        'overview lives.'),
    ...bullet('the app',
        '§6.5 sizes nodes proportional to sqrt(size). The code '
        'uses a log curve and documents why: for sizes of bytes to '
        'kilobytes, sqrt left almost every node pinned at the '
        'minimum radius.'),
    blank,
    ...text('None of this makes the spec less useful. It means '
        'the right way to use it is as the statement of intent and '
        'invariants, with the code and its tests as the statement '
        'of fact.'),

    ...sec('section 9 to 11: milestones and acceptance'),
    ...text('Build order is part of the contract. §9 numbers six '
        'milestones, bottom-up so each layer is testable before '
        'the one above exists, and ends with the rule:'),
    ...code('markdown', 'docs/HeapLens_Build_Spec.md · §9', r'''
Each milestone must compile and pass its tests before the next begins.'''),
    ...text('The milestones map onto the plan documents in '
        'docs/superpowers: M1 protocol, M2 alloc, M3 and M4 the '
        'daemon, M5 Flutter. M6 (integration, three examples, '
        'benchmarks) has no single commit that closes it. '
        'Integration happened milestone by milestone through the '
        'cross-process tests. One benchmark, H1 (detection '
        'latency), has committed results. The spec speaks of '
        'H2’s benchmarks “once unfrozen” and the Stage 7 '
        'document says benchmarks “remain frozen”; the '
        'repository contains no committed H2 numbers.'),
    ...text('§11 ties acceptance to seven criteria from the '
        'thesis cahier des charges, CA1 to CA7: complete capture, '
        'non-blocking return, overhead under target, orphan '
        'detection per the formal definition, detection earlier '
        'than a reference tool, smooth real-time rendering, and '
        'reproducible scenarios. This page does not grade them. '
        'What can be said from the repository is narrower: the '
        'committed H1 measurement covers detection latency on its '
        'own, nothing in the tree compares it with a reference '
        'tool, and no overhead figures are committed.'),

    ...sec('how to read it, and what to take from it'),
    ...bullet('write the invariants first',
        'ten short rules, written before the code, that later '
        'files cite by number (ring.rs: “invariant §12.5”) and that '
        'the M3 plan repeats as global constraints (§12.6, §12.7, '
        '§12.9).'),
    ...bullet('name what each part must not know',
        'the Must NOT know column is the cheapest dependency '
        'graph there is, and the plans restate it as constraints '
        '(the M3 plan forbids the daemon from depending on '
        'heaplens-alloc).'),
    ...bullet('make the document editable by evidence',
        'the big paragraph in §5.3 exists because a real binary '
        'disproved a one-line design. Appending the finding, with '
        'the test names that pin it, kept the spec honest.'),
    ...bullet('separate intent from fact',
        'the spec is still the best statement of what HeapLens is '
        'for. When it disagrees with a test, the test wins, and '
        'the drift list above is the map.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
