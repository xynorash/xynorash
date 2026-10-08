import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/docs/superpowers/plans/2026-07-01-heaplens-daemon-m3.md',
  lines: [
    heading('# heaplens-daemon M3 Implementation Plan'),
    blank,
    ...text('The plan that built the first half of the daemon: '
        'a named-pipe server, the ownership graph, and the diff '
        'it computes. It is one of two plans amended after '
        'execution (the Flutter M5 plan gained a post-merge '
        'addendum), and its amendment (three bugs '
        'and one law about timing) is the most useful part. It '
        'also contains the first version of φ, the function the '
        'whole project turns on, which the project later threw '
        'away.'),
    blank,
    kv('role', 'Stage 3 build plan: ingest, graph, φ, diff (milestone M3)'),
    kv('date', 'plan 2026-07-01 17:04 (faa66c8); notes 2026-07-02 00:53'),
    kv('size', '1,326 lines · 8 tasks · post-implementation notes'),
    kv('executed', '17:06 to 17:36 on 2026-07-01, 11 commits'),
    kv('branch', 'dev/phase_3, merged 2026-07-02 07:18 (489b5ef)'),

    ...sec('the scope, drawn as a fence'),
    ...text('The goal sentence names what is in and, in the same '
        'line, what is out:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-01-heaplens-daemon-m3.md · Goal (trimmed)', r'''
named pipe ingest, ownership graph with φ inference
No WebSocket, no SQLite, no anomaly detection.'''),
    ...text('The architecture paragraph fixes the concurrency '
        'model: three Tokio tasks. One accepts the pipe and '
        'decodes frames, one owns the graph and resolver and '
        'processes messages, one sends a tick every 33 ms. The '
        'graph task owns all model state, so there are no locks '
        'on the hot path. Messages are the only coupling.'),
    ...text('The global constraints turn the Build Spec’s '
        'invariants into things the executor can violate by '
        'accident, and forbids each:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-01-heaplens-daemon-m3.md · Global Constraints (trimmed)', r'''
- Working branch: `dev/phase_3`. Do NOT touch `master`.
- No `tokio-tungstenite`, no `rusqlite`, no `serde_json` — those are M4.
- `heaplens-daemon` must NOT depend on `heaplens-alloc`.
- Invariant §12.9: no graph/anomaly/persistence work on the ingest hot path — route via `mpsc`.'''),
    ...text('Three kinds of fence appear. A branch rule keeps '
        'unreviewed work off master. A dependency rule keeps the '
        'next milestone’s libraries out of this one, and keeps '
        'the consumer from linking the producer, which would '
        'collapse the process boundary at compile time. An '
        'invariant rule keeps ingest from doing work. The rules '
        'are cheap to state and each prevents a class of mistake '
        'that is expensive to undo.'),

    ...sec('the module plan'),
    ...text('Six files, each with one job, written so the '
        'dependencies point one way:'),
    ...bullet('config.rs',
        'two fields, pipe_name and tick_ms, with environment '
        'overrides (HEAPLENS_PIPE, HEAPLENS_TICK_MS).'),
    ...bullet('msg.rs',
        'the GraphMsg enum: Events, Symbols, Tick. The one '
        'channel type between the ingest task and the graph task.'),
    ...bullet('resolver.rs',
        'a map from address to name, with a hex fallback '
        'for unknown addresses. The Build Spec’s “the daemon '
        'never symbolizes” as a map and one lookup function.'),
    ...bullet('graph.rs',
        'Node, OwnershipGraph, φ, on_alloc, on_dealloc, '
        'on_realloc, drain_diff.'),
    ...bullet('ingest.rs',
        'the accept loop and decoder.'),
    ...bullet('main.rs',
        'wiring and Ctrl-C.'),
    blank,
    ...text('main.rs is a stub until the end and the tests '
        'reach graph and resolver through a library target, '
        'which the plan’s first commits make public (“fix(daemon): '
        'make all modules pub for test access”, f12b3e6). The '
        'graph commit (9843e94) adds a lib.rs “to expose crate '
        'modules for integration tests”, which is why the daemon '
        'is still a library plus a binary.'),

    ...sec('tests first, properly this time'),
    ...text('Task 4 builds the graph and is the plan’s strictest '
        'TDD step. The tests come first, as a separate file, '
        'and the plan says what the next command must do:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-01-heaplens-daemon-m3.md · Task 4, Step 2', r'''
- [ ] **Step 2: Run tests — expect compile failure (graph module is a stub)**
Expected: compile error — `OwnershipGraph` not found. This confirms the tests are real.'''),
    ...text('The Stage 1 plan said “verify they pass”. This one '
        'insists on watching them fail first, and the reason is '
        'in the sentence: a test that has never failed has not '
        'been shown to be able to. Eight graph tests are specified '
        'up front: ownership found by stack overlap, root when '
        'nothing matches, tie-break by greatest timestamp, '
        'children orphaned on dealloc, realloc keeps its id, '
        'second drain empty, symbol attached from the resolver, '
        'hex fallback for unknown symbols.'),

    ...sec('the first φ'),
    ...text('The plan’s ownership inference is three lines of '
        'logic and one doc comment. A new allocation’s owner is '
        'the live node whose first stack address appears '
        'anywhere in the new stack, preferring the most recent:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-01-heaplens-daemon-m3.md · Task 4, φ (trimmed)', r'''
    /// Among candidates, prefer greatest `ts`; tie-break by greatest `id`.
    fn infer_ownership(&self, new_stack: &[u64; 8], stack_len: u8) -> Option<u64> {
            .filter(|n| n.live && n.stack_len > 0 && search_set.contains(&n.stack[0]))
            .max_by_key(|n| (n.ts, n.id))'''),
    ...text('Every unit test passed against synthetic stacks '
        'built by hand: owner has stack [0xAAAA], child has '
        '[0xBBBB, 0xAAAA], so the owner is found. Against a real '
        'compiled program the rule linked almost nothing, because '
        'two allocation statements in one function carry '
        'different addresses. A real compiled producer exposed '
        'that, and a rewrite on 2026-07-08 (43fc22e) matched '
        'resolved function names instead, excluding the new '
        'node’s own frame.'),
    ...text('Compare the plan’s version with the code that '
        'replaced it. Almost every line changed, but one idea '
        'did not: recency, with the id as the tie-breaker. The '
        'selection key is the same pair, applied to a '
        'pre-narrowed candidate set:'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · infer_ownership (trimmed)', r'''
                let key = (node.ts, node.id);
                if best.map_or(true, |b| key > b) {'''),
    ...text('That continuity is the point of writing the plan '
        'at all. The plan fixed the interface (a function from '
        'a stack to an optional owner) and the tie-break, then '
        'left the matching rule free to be wrong and be '
        'replaced. The graph unit tests grew from eight to '
        'eighteen, most of the new ones about φ, and a dedicated one now '
        'names its limitation: a late child of an earlier owner '
        'is attributed to a newer same-name owner.'),

    ...sec('the three bugs recorded after the fact'),
    ...text('The plan’s last section, dated the next day, is '
        'unusual: it keeps the bugs. Its stated purpose is that '
        'they are “non-obvious constraints and correctness '
        'decisions that M4 authors must know before touching the '
        'graph or the drain loop”.'),
    ...text('Bug 1, the diff that contradicted itself. The first '
        'drain_diff filtered the update list against the add '
        'list only. A node could therefore appear in update and '
        'remove at once (a parent whose edge list was tidied and '
        'which was also freed in the same tick), or in add and '
        'remove (born and freed in one tick). Both violate the '
        'protocol: the notes say a Flutter consumer that never '
        'received a node in add must never receive its id in '
        'remove. '
        'The fix is three rules of strict disjointness:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-01-heaplens-daemon-m3.md · Bug 1 fix', r'''
- `add` = nodes in `added` that are NOT in `removed_set`
- `update` = nodes in `updated` that are NOT in `added_set` AND NOT in `removed_set`
- `remove` = ids in `removed` that are NOT in `added_set` (nodes the consumer never saw)'''),
    ...text('Those rules are still in the code, with a comment '
        'that restates the consequence:'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · drain_diff (trimmed)', r'''
        // Nodes born and freed within the same tick are invisible to the consumer.
        // Only remove nodes the consumer has previously seen (not born this tick).'''),
    ...text('Bug 2, the invariant nobody tested. The field '
        'had_owner_once is the single signal orphan detection '
        'reads in the next milestone, and nothing asserted it. '
        'The fix is an accessor (node_by_ptr) so integration '
        'tests can see the field, and two assertions:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-01-heaplens-daemon-m3.md · Bug 2 fix', r'''
assert!(child_node.had_owner_once);
assert!(child_node.owner.is_none());'''),
    ...text('Bug 3, a flag cleared too early. The pipe server '
        'sets first_pipe_instance(true) on its first creation so '
        'a second daemon cannot silently share the pipe. The '
        'first implementation cleared its “first” flag before the '
        'create call returned. If that create failed, every retry '
        'dropped the exclusivity guarantee. The fix moved one '
        'assignment into the success arm, and the code still has '
        'it there:'),
    ...code('rust', 'crates/heaplens-daemon/src/ingest.rs · the pipe create loop', r'''
                Ok(s) => {
                    first = false;
                    s
                }'''),
    ...text('The note on this bug is candid about its coverage: '
        '“No automated test — requires OS-level pipe contention. '
        'Verified by inspection. This is a known-uncovered path; '
        'any refactor of the ingest::run create loop must preserve '
        'the first = false placement.” Writing down what is not '
        'tested, and the '
        'invariant a refactor must keep, is worth more than a '
        'test that pretends.'),

    ...sec('the law: drain cadence is load-bearing'),
    ...text('The most interesting section is not a bug but a '
        'consequence of fixing Bug 1. Once born-and-freed nodes '
        'are suppressed, when you drain changes what you see:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-01-heaplens-daemon-m3.md · Drain cadence (trimmed)', r'''
> Nodes allocated and freed within the same drain window are correctly suppressed
**Rule:** drain per tick, not on shutdown.'''),
    ...text('The cross-process test found it. Run a producer '
        'that allocates and frees everything in under two '
        'seconds, drain once at the end, and the graph reports '
        'zero nodes, because every node was born and died inside '
        'one window. The test now drains after each batch, '
        'mimicking the daemon’s own tick.'),
    ...text('The same fact came back three weeks later. The '
        'cross-process test went red after an unrelated cap on '
        'drain batches because it tracked each node’s last-seen '
        'edge list, which for a producer that frees everything '
        'before exit is its torn-down state. The fix (fa3fe78) '
        'records the peak edge list per node. It is the same '
        'law seen from the other side: what you observe depends '
        'on where you cut the stream.'),

    ...sec('the proof the plan asks for, and the numbers it got'),
    ...text('Unit tests cannot show that two real processes '
        'interoperate, so the stage ends with one that can. A '
        'child process, wire_producer, uses the allocator crate '
        'with #[inline(never)] nested calls to make non-trivial '
        'stacks; the test hosts the daemon’s ingest loop and '
        'connects over the real named pipe. The recorded first run:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-01-heaplens-daemon-m3.md · cross-process results', r'''
- `alloc_count: 202` — observed ≥ 202 nodes (minimum threshold: 100)
- `nodes_with_edges: 200` — φ inference fired on 200 of 202 nodes using real captured stacks
- FrameDecoder resyncs: **0** — all frames decoded cleanly'''),
    ...text('Zero resyncs means the Stage 1 decoder and Stage 2 '
        'encoder agreed byte for byte on a live pipe, which is '
        'the integration the contract crate exists to make '
        'boring.'),
    ...text('The 200-of-202 edge count needs a caveat that '
        'this page owes the reader: it describes the first '
        'φ. The edge assertions were rewritten on 2026-07-08 once '
        'matching moved to function names, and again on '
        '2026-07-26 (71c6240) to a topology check that matches '
        'what φ actually guarantees. The test is named the same; '
        'its meaning has changed twice.'),

    ...sec('what did not match the plan'),
    ...bullet('the integration test file',
        'the plan names it integration.rs. The repository has '
        'ingest_loopback.rs (6a95ceb), which tests the '
        'encode-decode-graph path without a real pipe, as the '
        'plan reasoned a real pipe was “OS resource requirements '
        'and timing sensitivity”.'),
    ...bullet('ingest::run',
        'planned to return an anyhow Result; it returns nothing '
        'and instead sends TargetConnected and TargetDisconnected '
        'messages, added later for target tracking.'),
    ...bullet('on_dealloc',
        'the plan’s version scans every node to find children. '
        'That linear scan, plus a matching one in φ, made '
        'ingestion cost grow with history until 2026-07-22 '
        '(4e8868f, 783b2d3, 97576bc). The final code keeps an '
        'owner index and a site index.'),
    ...bullet('test count',
        'the plan expects 13 tests. graph_unit.rs alone has 18 '
        'today.'),
    blank,
    ...text('The plan also contains traces of being written by '
        'thinking aloud: one step first says the expected result '
        'is 7 passing tests, then in the same sentence counts '
        'again and arrives at 11. The numbers in the final '
        'checklist (13) are right, and the sentence is left as '
        'written. It is a reminder that these documents were '
        'drafted quickly and then executed with checks, not '
        'proofread into infallibility.'),

    ...sec('limits, and what to take from it'),
    ...bullet('the plan’s φ was a placeholder',
        'the Build Spec had already called φ a heuristic, and the '
        'plan contained no test against a real compiled stack. '
        'The first such test was the cross-process one, about '
        'seven hours later.'),
    ...bullet('uncovered paths stay uncovered',
        'the pipe-exclusivity path still has no automated test.'),
    ...bullet('rule of thumb',
        'when you fix a correctness bug in a stream, ask what '
        'else its fix makes observable. Making the diff '
        'disjoint made time part of the output.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
