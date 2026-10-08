import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/src/graph.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'graph.rs — the ownership graph and φ, its inference rule'),
    cm('//', r'turns a flat stream of allocations into "who owns what"'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'the model: nodes, ownership edges, per-tick diffs, snapshots'),
    kv('language', r'Rust, single-threaded, no locks'),
    kv('size', r'870 lines: about 600 of code and docs, 268 of in-file tests'),
    kv('history', r'14 commits touch it, 2026-07-01 to 2026-07-22'),
    kv('owner', r'the graph loop in main.rs is the only caller, one thread'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'The allocator side of HeapLens sends the daemon a flat stream: '
        r'a pointer, a size, a timestamp and up to 16 raw instruction '
        r'pointers per event (AllocEvent in heaplens-protocol/src/event.rs, '
        r'168 bytes). Nothing in that stream says which allocation owns '
        r'which. A Vec’s backing buffer and the Strings inside it look '
        r'like unrelated blocks to the heap.'),
    blank,
    ...para('//',
        r'graph.rs rebuilds the missing structure. The Build Spec calls it '
        r'"the heart and the realization of GrapheTas = (N, A, φ)": N is '
        r'the set of live allocations, A the directed owner-to-child arcs, '
        r'and φ the inference rule that decides which arcs exist. It also '
        r'owns the bookkeeping that turns that model into the two things '
        r'the UI consumes: a full snapshot on connect and a small diff '
        r'every tick. The spec states the concurrency model in one '
        r'sentence: "The graph task owns this struct and processes '
        r'commands from an mpsc receiver. No locks." main.rs is that task.'),
    blank,
    ...para('//',
        r'The file is the place where most of the project’s hard-won '
        r'lessons ended up. Its doc comments are unusually long because '
        r'each one records a bug that was real: a universal chain, a '
        r'name that could never match, a graph that never forgot a dead '
        r'node, an index that made removal slower than the work it '
        r'served. This page walks through them in the order they '
        r'happened.'),

    ...sec(r'the node'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · Node', r'''
pub struct Node {
    pub id: u64,
    pub ptr: u64,
    pub size: u64,
    pub ts: u64,
    pub live: bool,
    pub stack: [u64; 16],
    pub stack_len: u8,
    /// Id of the node that owns this one (φ inference result).
    pub owner: Option<u64>,
    /// Ids of nodes this node owns.
    pub edges_out: Vec<u64>,
    /// True once an owner was assigned and then freed — used by M4 orphan detection.
    pub had_owner_once: bool,
    /// Current anomaly classification; updated by anomaly::sweep.
    pub state: NodeState,
    /// `ts_nanos` of the dealloc event that freed this node's owner, if any —
    /// set once in `on_dealloc` when the owner is freed and this node is
    /// orphaned. Observability-only: never read by `infer_ownership` or
    /// `anomaly::sweep`'s state predicates, so it cannot influence detection
    /// timing or outcome. Exists so H1 (detection-latency measurement) has a
    /// real owner-free timestamp to measure from instead of inferring one.
    pub owner_free_ts: Option<u64>,
    /// This node's own classification in `site_index`/`pending_site_ids`
    /// (2026-07-22 processing-ceiling fix) — computed once at insertion by
    /// `classify_effective_site` and otherwise stable (see `SiteClass`'s doc
    /// comment). Stored on the node so eviction (`drain_diff`) knows which
    /// index bucket to clean up without recomputing anything.
    pub site_class: SiteClass,
}
'''),
    ...para('//',
        r'Three fields are worth reading closely. owner and edges_out are '
        r'the two directions of the same arc, kept in sync by hand: the '
        r'graph never stores an edge anywhere else. had_owner_once '
        r'exists because the orphan rule in anomaly.rs needs to tell '
        r'"never had an owner" (a root, perfectly normal) from "had one '
        r'and lost it" (a suspect). And owner_free_ts and site_class are '
        r'both additions made late, each justified in its own doc '
        r'comment: the first is observability-only and promises never '
        r'to be read by inference or by the sweep predicates, the '
        r'second is the cache that makes the 2026-07-22 speed-up '
        r'possible.'),

    ...sec(r'φ, first draft: the universal chain'),
    ...para('//',
        r'The first φ, written on 2026-07-01 (commit 9843e94), took a new '
        r'allocation’s whole stack as a set of raw addresses and picked '
        r'the live node whose stack[0] was in that set, newest first. '
        r'That is a reasonable idea on paper. On real traces it fails '
        r'because of how the capture works: capture.rs documents that the '
        r'raw trace "always starts inside the shared instrumentation '
        r'chain (capture_stack -> record -> the allocator method)". '
        r'Every allocation therefore shares the same first frames, so '
        r'any two allocations look related to each other. The '
        r'project’s tests give the result a name: the "universal-chain '
        r'failure mode".'),
    blank,
    ...para('//',
        r'The regression test that guards this still carries the '
        r'scar: tests/graph_unit.rs describes two allocations from '
        r'different real call sites that share one machinery frame and '
        r'calls attributing them to each other "exactly the universal-'
        r'chain failure mode that was found". The next sections are '
        r'the rules that replaced the raw-address match, all landed '
        r'together in commit 43fc22e (2026-07-08), whose message lists '
        r'"four layered bugs preventing phi from ever producing real '
        r'edges": stack capture widened from 8 to 16 frames, the '
        r'previously discarded SYMBOLS frames wired into the resolver, '
        r'matching moved to function-name granularity with a recency '
        r'tie-break, and shim classification fixed for consumer-'
        r'namespaced __rust_alloc symbols.'),

    ...sec(r'rule 1: find the real call site (the effective site)'),
    ...para('//',
        r'Instead of trusting stack[0], φ walks the stack from the '
        r'capture point outward and takes the first frame that is not '
        r'machinery and not zero. Machinery is decided by the writer '
        r'thread on the allocator side (heaplens-alloc/src/writer.rs) '
        r'and shipped to the daemon in the SYMBOLS frame as a boolean '
        r'per address; the resolver stores it.'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · effective_site_index', r'''
fn effective_site_index(stack: &[u64; 16], stack_len: u8, resolver: &Resolver) -> Option<usize> {
    (0..stack_len as usize).find(|&i| {
        let addr = stack[i];
        addr != 0 && !resolver.is_machinery(addr)
    })
}
'''),
    ...para('//',
        r'Two details matter. The index is recomputed on demand, not '
        r'frozen on the node, so a SYMBOLS frame that arrives late '
        r'changes the answer the next time it is asked. And an address '
        r'the resolver has never heard of counts as machinery '
        r'(resolver.rs: "defer, don’t guess"), so it is skipped rather '
        r'than guessed at. Section "stale answers" below is about what '
        r'that choice costs.'),

    ...sec(r'rule 2: match function names, not instruction addresses'),
    ...para('//',
        r'The second rule is the most consequential. Two allocation '
        r'statements in one function sit at different instruction '
        r'addresses, so exact-address matching can never link a '
        r'container allocated by one statement to children allocated by '
        r'a helper called from another. The doc comment on '
        r'effective_site_name records the evidence: against a real '
        r'compiled binary, wire_producer’s nested_alloc produced "0 '
        r'edges", even though the ancestor frame genuinely passed '
        r'through the owner’s enclosing function. backtrace::resolve '
        r'maps any address to the symbol of its containing function, so '
        r'matching on resolved names links the case.'),
    blank,
    ...para('//',
        r'The cost is stated in the same comment, deliberately. An edge '
        r'no longer claims "allocated at the owner’s exact site"; it '
        r'claims "allocated on a call path that passes through the '
        r'owner’s allocating function". That is weaker, and the file '
        r'says so instead of hiding it.'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · infer_ownership, building the search set (trimmed)', r'''
fn infer_ownership(&mut self, new_stack: &[u64; 16], stack_len: u8, resolver: &Resolver) -> Option<u64> {
    let len = stack_len as usize;
    let own_idx = match Self::effective_site_index(new_stack, stack_len, resolver) {
        Some(i) => i,
        None => return None,
    };

    let search_set: HashSet<String> = new_stack[own_idx + 1..len]
        .iter()
        .copied()
        .filter(|&a| a != 0 && !resolver.is_machinery(a))
        .map(|a| resolver.name_for(a))
        .collect();

    if search_set.is_empty() {
        return None;
    }
'''),
    ...para('//',
        r'The slice new_stack[own_idx + 1..len] is rule 3 in disguise: '
        r'it starts after the new node’s own effective site.'),

    ...sec(r'rule 3: exclude your own site, then prefer the newest'),
    ...para('//',
        r'If a node searched its own call site too, every allocation '
        r'from a loop would match the previous iteration’s allocation '
        r'and siblings would chain. Starting the search set after the '
        r'node’s own effective site fixes that: siblings from one call '
        r'site share the same own site, which is excluded, while a '
        r'genuine owner further up the stack is not. '
        r'tests/graph_unit.rs pins three shapes: a star (five children '
        r'sharing one leaf site all hang off one owner and none owns '
        r'another), a chain (A owns B owns C, but A does not own C '
        r'directly) and "sibling exclusion" (two nodes with the same '
        r'site and no owner above them get no edge).'),
    blank,
    ...para('//',
        r'When several live nodes qualify, the tie-break is recency: '
        r'the greatest ts, then the greatest id. The key is built once '
        r'and compared as a tuple.'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · infer_ownership, the candidate loop', r'''
let mut best: Option<(u64, u64)> = None; // (ts, id) — same tie-break key as the old max_by_key
for name in &search_set {
    let Some(ids) = self.site_index.get(name) else { continue };
    for &cid in ids {
        let Some(node) = self.nodes.get(&cid) else { continue };
        if !node.live {
            continue;
        }
        let key = (node.ts, node.id);
        if best.map_or(true, |b| key > b) {
            best = Some(key);
        }
    }
}
best.map(|(_, id)| id)
'''),
    ...para('//',
        r'Note what is absent. Node carries no thread id and no '
        r'call/return bracketing. The Build Spec’s section "φ’s '
        r'tie-break rule, stated precisely" says it flatly: the '
        r'discriminator is "which same-named node was most recently '
        r'allocated, nothing more".'),

    ...sec(r'what an edge does and does not claim'),
    ...para('//',
        r'Because the rule is recency over function names, it has a '
        r'documented success case and a documented failure case, and '
        r'both are tests rather than prose.'),
    ...pt('//', 'works: sequential invocations',
        r'phi_k_invocations_of_same_function_partition_by_recency_when_'
        r'sequential allocates 8 owners of one symbol, each followed by '
        r'its own 10 children, and asserts that every owner ends with '
        r'exactly its own 10 and no child is claimed twice. This is the '
        r'shape wire_producer and the demo producers produce.'),
    ...pt('//', 'fails: a late child',
        r'phi_recency_discriminator_misattributes_late_child_to_newer_'
        r'same_name_owner builds owner1, its first child, owner2, and '
        r'then owner1’s second child. The second child is attributed '
        r'to owner2. The test asserts the wrong answer on purpose and '
        r'the comment above it says: "accepted cost of function-'
        r'granularity + recency tie-break, not a bug".'),
    ...pt('//', 'fails: two unrelated containers',
        r'phi_ambiguity_two_unrelated_containers_in_same_function: '
        r'vec_a and vec_b are both allocated directly in main, a later '
        r'child belongs to neither, and the child is credited to '
        r'whichever is newer. The comment says it "documents/locks in '
        r'the actual (imprecise) behavior rather than asserting '
        r'correctness that the design cannot provide".'),
    blank,
    ...para('//',
        r'There is also field evidence of the imprecision. '
        r'tests/cross_process_wire.rs runs the real wire_producer, '
        r'whose 100 simultaneously live "outer" buffers all come from '
        r'one call site. Over 18 consecutive runs on 2026-07-26 the '
        r'root container reported between 24 and 47 children instead of '
        r'the roughly 100 a perfect inference would give, while the '
        r'allocation count stayed at exactly 202. The test’s comment '
        r'calls the shortfall "a redistribution/capture artifact of this '
        r'specific adversarial workload shape, not lost or corrupted '
        r'data"; the commit message (71c6240) is more cautious and says '
        r'the size of the gap was "not root-caused further here". The '
        r'tie-break was deliberately left alone, and the test’s '
        r'threshold was recalibrated to 15 instead.'),
    blank,
    ...para('//',
        r'One more consequence is chosen, not accidental: the search '
        r'covers the whole remaining stack, not only the immediate '
        r'caller. A long-lived container allocated in main therefore '
        r'owns every allocation made within its dynamic scope, and '
        r'those allocations own their own children, giving a real '
        r'two-level chain. The Build Spec records the rejected '
        r'alternative: an immediate-caller-only search "would blind φ to '
        r'any ownership relationship deeper than one stack frame, '
        r'which is worse than the chain-accumulation property it '
        r'would avoid".'),

    ...sec(r'the invariant that broke once'),
    ...para('//',
        r'A node names itself by its effective site; a child looks for '
        r'owners by a set of names built from its own stack. Those are '
        r'two separate computations over two different stacks, and '
        r'nothing in the type system forces them to agree. They '
        r'agree today because both go through the same skip-machinery '
        r'rule.'),
    blank,
    ...para('//',
        r'On 2026-07-13 they stopped agreeing. The writer’s machinery '
        r'list named specific stdlib shims one by one '
        r'(alloc::vec::from_elem and friends) and did not include '
        r'Vec::with_capacity. So wire_producer’s items = '
        r'Vec::with_capacity(100) resolved its own effective site to '
        r'"alloc::vec::Vec::with_capacity" instead of "wire_producer::'
        r'main": the owner named itself by a name no child’s search set '
        r'could ever contain. The end-to-end test caught it as a root '
        r'fan-out assertion failing with zero candidates. The fix '
        r'(commit e9c73d2, in the allocator crate) classifies the whole '
        r'alloc:: crate as plumbing instead of enumerating shims, and '
        r'the commit message gives the principle: naming constructors '
        r'one at a time "guarantees the next stdlib idiom (Box::new, '
        r'HashMap::with_capacity...) reopens the same bug".'),
    blank,
    ...para('//',
        r'The daemon-side half of that commit is a test that states the '
        r'invariant directly instead of observing it through edges.'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · owner_effective_site_name_matches_the_name_a_childs_search_set_looks_for (trimmed)', r'''
fn owner_effective_site_name_matches_the_name_a_childs_search_set_looks_for() {
    let mut r = Resolver::new();
    // Owner's own stack: a stdlib allocation-plumbing frame (machinery)
    // sitting in front of the owner's real call site — exactly the
    // Vec::with_capacity shape (own_idx must skip past the plumbing
    // frame to reach the real site, not stop on it).
    r.insert(0xAAA1, "alloc::vec::Vec<T>::with_capacity".to_owned(), true);
    r.insert(0xAAA2, "myapp::main".to_owned(), false);
    // Child's own stack: its own real site, then the SAME real
    // ancestor site the owner names itself by.
    r.insert(0xBBB1, "myapp::helper".to_owned(), false);

    let mut owner_stack = [0u64; 16];
    owner_stack[0] = 0xAAA1;
    owner_stack[1] = 0xAAA2;
    let owner_name = OwnershipGraph::effective_site_name(&owner_stack, 2, &r)
        .expect("owner must resolve to a real effective site, not the machinery frame");
    assert_eq!(
        owner_name, "myapp::main",
        "owner's effective site must skip the machinery frame and land on its real call site"
    );

...
    assert!(
        child_search_set.contains(&owner_name),
        "the owner's effective site name must appear in the child's search set — \
         got owner_name={owner_name:?}, child_search_set={child_search_set:?}"
    );
'''),
    ...para('//',
        r'The doc comment on that test says why it exists in a '
        r'sentence worth keeping: a future change to either computation '
        r'that breaks the agreement should fail here, "not three '
        r'stages later against a real target".'),

    ...sec(r'stale answers: unknown is not the same as machinery'),
    ...para('//',
        r'The resolver treats unknown and known-machinery the same way '
        r'(both are skipped), which is right for a fresh recomputation. '
        r'It is wrong to bake into a persistent index. An address that '
        r'is merely unresolved today may resolve tomorrow to real code, '
        r'possibly at an earlier stack position than the scan landed '
        r'on, and a node indexed under today’s premature answer would '
        r'silently never be found as an owner. SiteClass encodes the '
        r'difference: Resolved and NoSite are final, Pending is '
        r'provisional.'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · SiteClass', r'''
#[derive(Clone, Debug, PartialEq)]
pub enum SiteClass {
    /// A real (non-machinery) effective site was found, and nothing skipped
    /// on the way to it was merely unresolved — this name is final.
    Resolved(String),
    /// Every address considered (up to `stack_len`) is either `0` or known
    /// machinery — this node structurally has no effective site, and that
    /// can never change (mirrors `effective_site_index` returning `None`
    /// when every address is *definitively* classified).
    NoSite,
    /// At least one address considered before a `Resolved`/`NoSite`
    /// conclusion could be reached is still unknown to the resolver. Not
    /// safe to index anywhere permanent yet — re-classified opportunistically
    /// in `infer_ownership` until it resolves one way or the other.
    Pending,
}
'''),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · classify_effective_site', r'''
fn classify_effective_site(stack: &[u64; 16], stack_len: u8, resolver: &Resolver) -> SiteClass {
    for i in 0..stack_len as usize {
        let addr = stack[i];
        if addr == 0 {
            continue;
        }
        if !resolver.is_known(addr) {
            return SiteClass::Pending;
        }
        if !resolver.is_machinery(addr) {
            return SiteClass::Resolved(resolver.name_for(addr));
        }
        // Known machinery — keep scanning past it, same as
        // `effective_site_index`.
    }
    SiteClass::NoSite
}
'''),
    ...para('//',
        r'classify_effective_site needs one more query than '
        r'effective_site_index did: is_known(addr), added to the '
        r'resolver in the same commit (783b2d3) for exactly this '
        r'purpose.'),

    ...sec(r'the day the daemon fell 49 seconds behind'),
    ...para('//',
        r'On 2026-07-22, between 02:13 and 03:56 local time, three daemon '
        r'commits (with one allocator-side fix between the first and '
        r'second) attacked what the messages call a memory and '
        r'performance defect, in three layers. Each layer was found by '
        r'measuring after the previous one.'),
    blank,
    ...pt('//', 'layer 1: nothing ever left the map (4e8868f)',
        r'on_dealloc set live = false and removed the pointer mapping '
        r'but never removed the Node. Every allocation the daemon had '
        r'ever seen stayed in the HashMap for the life of the process, '
        r'and infer_ownership scanned all of them, so total ingestion '
        r'cost was O(N squared) in events processed. The commit '
        r'records the evidence: "total_nodes reached 102,225 with '
        r'live_nodes at 7 on a provably alloc/free-balanced workload, '
        r'and the daemon fell 49 seconds behind its own event '
        r'stream". The fix evicts each id in the removed accumulator '
        r'from the map inside drain_diff.'),
    ...pt('//', 'layer 2: two O(N) scans (783b2d3)',
        r'Profiling found on_alloc and on_dealloc consuming about 98 '
        r'percent of graph-task time under sustained load, roughly half '
        r'of it infer_ownership’s per-allocation scan and most of the '
        r'rest on_dealloc’s children scan, "the actual cause of the '
        r'~475-1000 msgs/s processing ceiling". The fix adds two '
        r'incrementally maintained reverse indexes, owner_index and '
        r'site_index.'),
    ...pt('//', 'layer 3: the index removal was the new bottleneck (97576bc)',
        r'Memory was still climbing. Instrumented timing showed that '
        r'removing a dying node from a site_index Vec bucket with '
        r'retain was O(bucket size), and with only a handful of '
        r'distinct call sites in the synthetic targets those buckets '
        r'held a very large number of nodes. That one call was '
        r'"~63-65% of all graph-task wall time". Changing the bucket '
        r'type from Vec to HashSet made removal O(1) on average.'),
    blank,
    ...para('//',
        r'The measured numbers, all from the commit messages and all '
        r'for the same 12-thread sustained-injection scenario:'),
    ...pt('//', 'infer_ownership per call',
        r'13.5 us down to 1.1 us, about 12.5x faster after layer 2.'),
    ...pt('//', 'graph-task time in on_alloc and on_dealloc',
        r'about 98 percent down to about 28 percent after layer 2.'),
    ...pt('//', 'raw event throughput',
        r'61-65k per second to 330-440k per second after layer 2; to '
        r'roughly 1.0-1.1 million per second after layer 3 (the share '
        r'of wall time spent in eviction fell from 63-65 percent to '
        r'about 3 percent).'),
    ...pt('//', 'backlog and memory',
        r'after layer 2 the peak queued backlog fell from about 808k '
        r'to about 335k messages and the post-load drain rate rose '
        r'from about 475 to about 5,237 per second; after layer 3 '
        r'peak external memory stayed under about 400 MB (about 5 GB '
        r'after layer 2, about 8.9 GB before any fix), channel depth '
        r'peaked in the tens of thousands, and memory returned to the '
        r'~39 MB baseline with the channel at exactly 0 within seconds '
        r'of detach.'),
    blank,
    ...para('//',
        r'Layer 2’s own message is honest about its limit: it reports '
        r'"a real but partial improvement, not a full fix", and names '
        r'drain_diff as the new dominant cost. Layer 3 is the follow-up '
        r'that found the actual culprit inside eviction rather than '
        r'inside diff construction (the commit measured about 4 percent '
        r'for building NodeDtos, resolver lookups included).'),

    ...sec(r'the two indexes'),
    ...para('//',
        r'owner_index and site_index are declared with doc comments '
        r'that explain not just what they hold but when their entries '
        r'may be removed, which is the part that is easy to get wrong.'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · OwnershipGraph fields (trimmed)', r'''
pub struct OwnershipGraph {
    /// All nodes, keyed by id.
    nodes: HashMap<u64, Node>,
    /// Maps live pointer → node id (removed on dealloc).
    by_ptr: HashMap<u64, u64>,
    next_id: u64,
    // Diff accumulators — cleared by drain_diff.
    added: Vec<u64>,
    updated: HashSet<u64>,
    removed: Vec<u64>,
    /// Rolling max of ev.ts_nanos across all received events. Used as Diff.ts.
    pub max_ts_seen: u64,
...
    owner_index: HashMap<u64, Vec<u64>>,
...
    site_index: HashMap<String, HashSet<u64>>,
...
    pending_site_ids: HashSet<u64>,
}
'''),
    ...para('//',
        r'owner_index maps an owner id to the ids of its live children. '
        r'It exists so on_dealloc can find a dying node’s children in '
        r'O(children) instead of scanning every node. Its entries are '
        r'cleaned immediately on dealloc, never deferred.'),
    blank,
    ...para('//',
        r'site_index maps a stable effective-site name to the ids of '
        r'nodes classified under it, so infer_ownership can ask "which '
        r'live nodes could match name X" in O(candidates for X). Its '
        r'cleanup is deferred to eviction, deliberately mirroring '
        r'self.nodes: a node that died this tick must remain a '
        r'filterable candidate (the n.live check) rather than vanish, '
        r'for the same reason the map keeps it that long.'),
    blank,
    ...para('//',
        r'pending_site_ids holds nodes whose class is still Pending. '
        r'Its doc comment is candid about why it exists: in real '
        r'traffic it is almost always empty "(the writer resolves every '
        r'address a batch’s events reference before sending that '
        r'batch)", so the re-check is cheap, and it exists "for '
        r'correctness in the general case, not as an optimization".'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · infer_ownership, promoting Pending nodes', r'''
let pending_ids: Vec<u64> = self.pending_site_ids.iter().copied().collect();
for pid in pending_ids {
    let reclass = match self.nodes.get(&pid) {
        Some(node) => Self::classify_effective_site(&node.stack, node.stack_len, resolver),
        None => continue, // defensive: shouldn't happen, pending ids are evicted alongside self.nodes
    };
    match reclass {
        SiteClass::Pending => {} // still unresolved, leave as-is
        SiteClass::Resolved(name) => {
            self.pending_site_ids.remove(&pid);
            self.site_index.entry(name.clone()).or_default().insert(pid);
            if let Some(node) = self.nodes.get_mut(&pid) {
                node.site_class = SiteClass::Resolved(name);
            }
        }
        SiteClass::NoSite => {
            self.pending_site_ids.remove(&pid);
            if let Some(node) = self.nodes.get_mut(&pid) {
                node.site_class = SiteClass::NoSite;
            }
        }
    }
}
'''),
    ...para('//',
        r'Every call re-classifies the Pending set before consulting '
        r'the index. That is what lets a late symbol be found on the '
        r'very next allocation, "matching pre-fix behavior exactly '
        r'rather than approximating it". An optimisation that quietly '
        r'narrowed behavior would have been faster and wrong.'),

    ...sec(r'on_alloc and on_dealloc, after the fix'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · on_alloc (trimmed)', r'''
pub fn on_alloc(&mut self, ev: &AllocEvent, resolver: &Resolver) {
    self.max_ts_seen = self.max_ts_seen.max(ev.ts_nanos);
    let id = self.next_id;
    self.next_id += 1;

    let owner_id = self.infer_ownership(&ev.stack, ev.stack_len, resolver);
    let site_class = Self::classify_effective_site(&ev.stack, ev.stack_len, resolver);
...
    // Register as a child of the owner.
    if let Some(oid) = owner_id {
        if let Some(owner) = self.nodes.get_mut(&oid) {
            owner.edges_out.push(id);
            self.updated.insert(oid);
        }
        self.owner_index.entry(oid).or_default().push(id);
    }

    // Index this node's own site so it can be found as a candidate
    // owner for future allocations — mirrors exactly what the old
    // full-scan would have found by recomputing `effective_site_name`
    // for this node on every later `infer_ownership` call.
    match site_class {
        SiteClass::Resolved(name) => {
            self.site_index.entry(name).or_default().insert(id);
        }
        SiteClass::Pending => {
            self.pending_site_ids.insert(id);
        }
        SiteClass::NoSite => {}
    }

    self.nodes.insert(id, node);
    self.by_ptr.insert(ev.ptr, id);
    self.added.push(id);
'''),
    ...para('//',
        r'on_alloc registers the new node as a child of its owner in '
        r'both directions, then files it under its site class. The '
        r'order matters: infer_ownership runs before the node exists, '
        r'so a node can never be its own owner.'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · on_dealloc (trimmed)', r'''
pub fn on_dealloc(&mut self, ptr: u64, ts_nanos: u64) {
    let id = match self.by_ptr.remove(&ptr) {
        Some(id) => id,
        None => return,
    };

    self.removed.push(id);

    // Collect (and clear) this node's children via the owner index —
    // replaces the old full self.nodes.values() scan. Removing the
    // whole bucket here is correct, not just convenient: every child
    // found is about to have its own `owner` cleared below, so none of
    // them belongs under this key (or any key) in the index afterward
    // regardless — no per-child list surgery needed.
    let children: Vec<u64> = self.owner_index.remove(&id).unwrap_or_default();

    for cid in children {
        if let Some(child) = self.nodes.get_mut(&cid) {
            child.owner = None;
            child.had_owner_once = true;
            // Observability-only: records which dealloc caused this —
            // does not feed into ownership or anomaly-state logic.
            child.owner_free_ts = Some(ts_nanos);
        }
        self.updated.insert(cid);
    }
...
    // Remove this node from its owner's edges_out list and owner-index
    // bucket alike — same mutation, same moment, for the same reason.
    let owner_id = self.nodes.get(&id).and_then(|n| n.owner);
    if let Some(oid) = owner_id {
        if let Some(owner) = self.nodes.get_mut(&oid) {
            owner.edges_out.retain(|&e| e != id);
            self.updated.insert(oid);
        }
        if let Some(v) = self.owner_index.get_mut(&oid) {
            v.retain(|&e| e != id);
        }
    }

    if let Some(node) = self.nodes.get_mut(&id) {
        node.live = false;
    }
'''),
    ...para('//',
        r'The whole owner_index bucket is removed in one call, with a '
        r'comment explaining why that is correct rather than just '
        r'convenient: every child found is about to have its owner '
        r'cleared, so none of them belongs under that key afterward '
        r'regardless. The orphaned children get had_owner_once = true '
        r'(the flag the sweep needs) and owner_free_ts (see below), '
        r'and go into the updated set so the UI hears about them.'),

    ...sec(r'drain_diff: a diff the consumer can apply blindly'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · drain_diff, building add/update/remove', r'''
pub fn drain_diff(&mut self, resolver: &Resolver) -> GraphMessage {
    let ts = self.max_ts_seen;

    let added_set: HashSet<u64> = self.added.iter().copied().collect();
    let removed_set: HashSet<u64> = self.removed.iter().copied().collect();

    // Nodes born and freed within the same tick are invisible to the consumer.
    let add: Vec<NodeDto> = self.added.iter()
        .filter(|&&id| !removed_set.contains(&id))
        .filter_map(|&id| self.nodes.get(&id))
        .map(|n| Self::node_to_dto(n, resolver))
        .collect();

    let update: Vec<NodeDto> = self.updated.iter()
        .filter(|&&id| !added_set.contains(&id) && !removed_set.contains(&id))
        .filter_map(|&id| self.nodes.get(&id))
        .map(|n| Self::node_to_dto(n, resolver))
        .collect();

    // Only remove nodes the consumer has previously seen (not born this tick).
    let remove: Vec<u64> = self.removed.iter()
        .filter(|&&id| !added_set.contains(&id))
        .copied()
        .collect();
'''),
    ...para('//',
        r'Three rules make the diff safe to apply without any extra '
        r'reconciliation on the client. Nodes born and freed inside '
        r'the same tick appear in none of the lists, so the client '
        r'never hears about a node that never existed for it. A node '
        r'in remove is not also in update (a node freed this tick '
        r'would otherwise be updated and removed at once). And remove '
        r'only lists ids the client previously saw, never ones born '
        r'this tick. Commit b1f2215 (2026-07-01) added these after a '
        r'cascaded-dealloc case showed overlap; tests/graph_unit.rs '
        r'keeps it as cascaded_dealloc_same_tick_disjoint.'),
    blank,
    ...para('//',
        r'Eviction happens at the end of the same function. The comment '
        r'that justifies the exact position is longer than the code, '
        r'because the fix was only acceptable once every reader of '
        r'self.nodes had been checked rather than assumed.'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · drain_diff, eviction', r'''
for id in self.removed.drain(..) {
    if let Some(node) = self.nodes.get(&id) {
        match &node.site_class {
            SiteClass::Resolved(name) => {
                if let Some(v) = self.site_index.get_mut(name) {
                    v.remove(&id);
                    if v.is_empty() {
                        self.site_index.remove(name);
                    }
                }
            }
            SiteClass::Pending => {
                self.pending_site_ids.remove(&id);
            }
            SiteClass::NoSite => {}
        }
    }
    self.nodes.remove(&id);
}

GraphMessage::Diff { ts, add, update, remove }
'''),
    ...para('//',
        r'The accounting in the comment: add and update already '
        r'exclude any id in removed_set before reading the map, remove '
        r'never reads the map, sweep and infer_ownership both filter on '
        r'live first, and on_dealloc has already unlinked a node in both '
        r'directions by the time it reaches removed. Evicting earlier '
        r'(inside on_dealloc) would also be safe by that accounting, '
        r'but "would remove a node mid-tick, before add/update have run '
        r'for it this same tick" and leave "strictly less margin for a '
        r'future change to this function". The eviction test in '
        r'tests/graph_unit.rs drives a full parent, child and orphan '
        r'lifecycle across four ticks and checks the map size at every '
        r'step, precisely so a too-early eviction cannot pass.'),

    ...sec(r'the time source: the stream’s clock, never the wall clock'),
    ...para('//',
        r'Every timestamp the daemon compares comes from the events. '
        r'ev.ts_nanos is produced on the allocator side by '
        r'timestamp_nanos() in capture.rs: monotonic nanoseconds since a '
        r'start instant initialised on first use, via Instant (QPC on '
        r'Windows). The '
        r'graph keeps max_ts_seen, a rolling maximum of those values, '
        r'and anomaly::sweep treats it as "now". The M4 plan states '
        r'the rule: "Never use daemon wall-clock", and "Events are NOT '
        r'guaranteed ts-ordered across producer threads, so always '
        r'max(), never assign". on_alloc applies it on its first line.'),
    blank,
    ...para('//',
        r'One honest wrinkle. The plan says the rolling maximum is '
        r'taken over "ALL events (alloc, dealloc, realloc)". The '
        r'implementation updates max_ts_seen only in on_alloc. '
        r'on_dealloc receives ts_nanos but uses it only for '
        r'owner_free_ts, and tests/orphan_persistence.rs says outright '
        r'that "on_dealloc deliberately does not touch max_ts_seen". '
        r'The H1 commit (816c732) states the consequence: the clock '
        r'"only advances on received alloc events", which makes '
        r'detection latency "bounded by (time to next producer event '
        r'past the binding timestamp) + (time to next tick)". It is '
        r'the price of keeping everything in one clock domain instead '
        r'of adding an independent daemon-side timer. The chaos_orphan '
        r'example works with it on purpose: its comment says it ticks '
        r'every 20ms "to keep max_ts_seen advancing".'),

    ...sec(r'observability code that is not allowed to decide anything'),
    ...para('//',
        r'Two later additions follow the same discipline, and both '
        r'announce it in their doc comments. owner_free_ts records, on '
        r'each child orphaned by a dealloc, the ts_nanos of that '
        r'dealloc. It is "never read by infer_ownership or '
        r'anomaly::sweep’s state predicates, so it cannot influence '
        r'detection timing or outcome", and exists so the H1 latency '
        r'measurement has a real timestamp to difference instead of a '
        r'workload-side proxy.'),
    blank,
    ...para('//',
        r'symbol_stats, added with the target-diagnostics banner '
        r'(0edc728), counts live nodes whose effective site resolves '
        r'to a real name versus a hex fallback. It reuses the same '
        r'effective_site_index and name_for computation node_to_dto '
        r'uses, so it "cannot diverge from what the wire actually '
        r'sends".'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · symbol_stats', r'''
pub fn symbol_stats(&self, resolver: &Resolver) -> (u64, u64) {
    let mut resolved = 0u64;
    let mut hex_fallback = 0u64;
    for n in self.nodes.values().filter(|n| n.live) {
        let is_hex = match Self::effective_site_index(&n.stack, n.stack_len, resolver) {
            Some(i) => resolver.name_for(n.stack[i]).starts_with("0x"),
            None => true,
        };
        if is_hex {
            hex_fallback += 1;
        } else {
            resolved += 1;
        }
    }
    (resolved, hex_fallback)
}
'''),
    ...para('//',
        r'A node with no locatable site counts as hex fallback along '
        r'with a node whose address was simply never resolved. The UI '
        r'banner can tell "unsymbolized target" from other zero-edge '
        r'causes with that one pair of numbers.'),

    ...sec(r'how it is tested'),
    ...para('//',
        r'Three test modules (four tests) live in this file; the larger '
        r'set is in tests/graph_unit.rs (18 tests), which has its own '
        r'page.'),
    ...pt('//', 'symbol_stats_tests (2 tests)',
        r'live nodes only, resolved versus hex fallback, an empty '
        r'graph reporting (0, 0).'),
    ...pt('//', 'invariant_tests (1 test)',
        r'the owner-name-matches-search-set invariant above.'),
    ...pt('//', 'index_consistency_tests (1 test)',
        r'the proof that the indexed infer_ownership returns the '
        r'same answer as the code it replaced.'),
    blank,
    ...para('//',
        r'The last one deserves a closer look. Rather than trust the '
        r'new index because the old tests still pass, the test keeps a '
        r'"byte-for-byte replica of the pre-fix infer_ownership" that '
        r'scans every node, and asserts both agree after every step of '
        r'a scenario.'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · brute_force_infer_ownership', r'''
fn brute_force_infer_ownership(
    nodes: &HashMap<u64, Node>,
    new_stack: &[u64; 16],
    stack_len: u8,
    resolver: &Resolver,
) -> Option<u64> {
    let len = stack_len as usize;
    let own_idx = OwnershipGraph::effective_site_index(new_stack, stack_len, resolver)?;
    let search_set: HashSet<String> = new_stack[own_idx + 1..len]
        .iter()
        .copied()
        .filter(|&a| a != 0 && !resolver.is_machinery(a))
        .map(|a| resolver.name_for(a))
        .collect();
    nodes
        .values()
        .filter(|n| {
            n.live
                && OwnershipGraph::effective_site_name(&n.stack, n.stack_len, resolver)
                    .is_some_and(|name| search_set.contains(&name))
        })
        .max_by_key(|n| (n.ts, n.id))
        .map(|n| n.id)
}
'''),
    ...para('//',
        r'The scenario covers the cases the index design has to defend: '
        r'a plain owner and child; a node whose site is unresolved at '
        r'creation (it must land in pending_site_ids, not site_index); '
        r'the symbol arriving, after which the next allocation must '
        r'promote that node and find it as owner; a dealloc, after '
        r'which owner_index must be clear immediately; and a '
        r'drain_diff, after which site_index must hold no reference to '
        r'the evicted node.'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · the eviction check', r'''
// Step 5: drain_diff evicts the dead owner. site_index must hold no
// reference to it afterward — the exact bug this test would have
// caught immediately had eviction cleanup been missing.
let _ = g.drain_diff(&r);
assert!(
    g.site_index.values().all(|ids| !ids.contains(&owner_id)),
    "evicted node must not remain in site_index under any name"
);
assert!(!g.nodes.contains_key(&owner_id), "evicted node must be gone from self.nodes");
assert_index_matches_brute_force(&mut g, &probe_owner_leaf(), 2, &r);
'''),
    ...para('//',
        r'The comment above the test names the failure it was built '
        r'to catch: "the test that would have failed immediately had '
        r'the site index not been cleaned up at the eviction point".'),

    ...sec(r'limits and open questions'),
    ...pt('//', 'φ is a heuristic, by the file’s own account',
        r'The Build Spec: "Heuristic by design; do not read an edge as '
        r'a proof of ownership". Concurrent calls into one function '
        r'and unrelated containers in one function are both '
        r'misattributed by design.'),
    ...pt('//', 'it needs symbols',
        r'φ matches names. The Build Spec records that without debug '
        r'info backtrace::resolve collapses internal call sites onto '
        r'the nearest exported symbol (everything resolved to '
        r'"wire_producer::main"), producing zero edges with no error. '
        r'The workspace sets [profile.release] debug = true for that '
        r'reason, "permanent, not opt-in".'),
    ...pt('//', 'roots never become orphans',
        r'had_owner_once is true only if an owner was inferred at '
        r'allocation or one was freed under the node. A leaked '
        r'allocation φ never attached to an owner is not an orphan by '
        r'this model. The detector finds children that lost their '
        r'owner, not every leak.'),
    ...pt('//', 'a visibility horizon of 16 frames',
        r'AllocEvent holds 16 frames, and the instrumentation chain '
        r'and std plumbing consume some of them (event.rs notes the '
        r'zeroed-alloc path inserts "6+ non-inlined std frames"). An '
        r'owner whose function is deeper than the captured window '
        r'cannot be seen.'),
    ...pt('//', 'one Vec::retain per child free (my reading of the code)',
        r'on_dealloc removes a child from its owner’s edges_out and '
        r'owner_index bucket with retain over a Vec. That is the same '
        r'shape as the site_index bug fixed in 97576bc, at the scale '
        r'of children per owner instead of nodes per call site. For '
        r'the fan-outs in the tests (12 to 100) it is irrelevant; for '
        r'an owner with a very large number of live children, '
        r'freeing them one by one would cost O(k squared). Nothing in '
        r'the repository measures this.'),
    ...pt('//', 'the diff pays for every node it touches',
        r'node_to_dto re-derives the effective site name for each '
        r'node in each diff, and snapshot() walks all live nodes on '
        r'every client connect. Both are linear in what they emit, '
        r'which the layer-3 profile found to be a small share.'),
    ...pt('//', 'dead code kept on purpose',
        r'effective_site_name is #[allow(dead_code)]: no production '
        r'code calls it any more, and it stays because a test pins '
        r'that a Resolved class’s name equals what it computes.'),
    blank,
    ...para('//',
        r'The shortest summary of this file: a heuristic written '
        r'down as precisely as a theorem, with a test for every place '
        r'the heuristic is allowed to be wrong.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
