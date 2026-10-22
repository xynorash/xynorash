import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/tests/graph_unit.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'graph_unit.rs — the φ ownership rules, one topology at a time'),
    cm('//', r'eighteen tests that define what “A owns B” means, including two that lock in known imprecision'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'unit specs for graph.rs: φ ownership inference, dealloc, realloc, diff draining, node eviction'),
    kv('language', r'Rust integration test (separate crate over heaplens_daemon)'),
    kv('size', r'591 lines, 18 tests, seven commits (9843e94 2026-07-01 to 4e8868f 2026-07-22)'),
    kv('exercises', r'OwnershipGraph::{on_alloc, on_dealloc, on_realloc, drain_diff, node_by_ptr, nodes, nodes_mut, mark_updated}, Resolver, anomaly::sweep'),
    kv('style', r'no threads, no sockets, no sleeps: events in, a drained diff out'),
    ...sec(r'why this file is the centre of the project'),
    ...para('//',
        r'HeapLens does not see ownership. The target only reports allocations and frees, each with a stack of return addresses. The daemon has to infer who owns whom, and that inference, called φ in the code, is the product. graph_unit.rs is where the rules of φ are written down as executable examples. Each φ test builds a handful of AllocEvents with hand-chosen stacks, feeds them to an OwnershipGraph, drains one diff and asserts which nodes ended up in whose edges list.'),
    blank,
    ...para('//',
        r'The rule being tested, in the words of graph.rs: a new allocation’s owner is the live node, among those whose own allocation site matches a function on the new allocation’s stack above its own site, with the greatest timestamp. "Allocation site" means the first stack frame the resolver does not classify as instrumentation machinery. "Matches" means the function name resolved from the address, not the raw address. The tests are organised by the properties of that rule.'),
    blank,
    ...sec(r'the helpers'),
    ...code('rust', r'crates/heaplens-daemon/tests/graph_unit.rs · lines 7-25', r'''
fn make_ev(kind: EventKind, ptr: u64, old_ptr: u64, size: u64, ts: u64, stack: &[u64]) -> AllocEvent {
    let mut s = [0u64; 16];
    let len = stack.len().min(16);
    s[..len].copy_from_slice(&stack[..len]);
    AllocEvent::new(kind, ptr, old_ptr, size, 8, ts, s, len as u8)
}

/// A resolver where every address in `sites` is classified as genuine caller
/// code (non-machinery). Test stacks are written as `[own_site, ancestor_site,
/// ...]` — with every site in this list, `own_site` lands at effective-site
/// index 0, matching the old tests' shape while going through the new
/// classification-based lookup rather than a raw index.
fn resolver_with_real_sites(sites: &[u64]) -> Resolver {
    let mut r = Resolver::new();
    for &a in sites {
        r.insert(a, format!("site_0x{a:x}"), false);
    }
    r
}'''),
    ...para('//',
        r'make_ev builds an AllocEvent from a slice of stack addresses, truncating at 16 frames. resolver_with_real_sites registers every address in a list as a non-machinery symbol named site_0x… so that a stack such as [leaf, owner] has its own site at index 0 and an ancestor at index 1. This is the doc comment’s point: the tests were rewritten when φ moved from a raw index to "the new classification-based lookup", and the helper keeps their stacks readable. unwrap_diff turns a GraphMessage into the three vectors a test wants and panics with the message on any other variant.'),
    blank,
    ...sec(r'star topology: siblings are not each other’s owners'),
    ...code('rust', r'crates/heaplens-daemon/tests/graph_unit.rs · lines 34-65', r'''
// --- Fix 3(a): star topology ---------------------------------------------
// N children sharing one leaf call site, all owned by one owner further up
// the stack: owner gets N edges_out, and — the actual bug this branch
// fixes — no child ever matches another child (would collapse into a chain
// if sibling exclusion weren't applied).
#[test]
fn phi_star_topology_children_share_owner_not_each_other() {
    let owner_site = 0xAAAA;
    let leaf_site = 0xBBBB;
    let r = resolver_with_real_sites(&[owner_site, leaf_site]);
    let mut g = OwnershipGraph::new();

    let owner_ev = make_ev(EventKind::Alloc, 0x1000, 0, 4096, 100, &[owner_site]);
    g.on_alloc(&owner_ev, &r);

    for i in 0..5u64 {
        let child_ev = make_ev(EventKind::Alloc, 0x2000 + i, 0, 128, 200 + i, &[leaf_site, owner_site]);
        g.on_alloc(&child_ev, &r);
    }

    let diff = g.drain_diff(&r);
    let (add, _, _) = unwrap_diff(diff);

    let owner = add.iter().find(|n| n.ptr == 0x1000).unwrap();
    assert_eq!(owner.edges.len(), 5, "owner should have all 5 children as edges_out");

    for i in 0..5u64 {
        let child = add.iter().find(|n| n.ptr == 0x2000 + i).unwrap();
        assert!(child.edges.is_empty(), "child must not own any sibling");
        assert!(owner.edges.contains(&child.id));
    }
}'''),
    ...para('//',
        r'One owner, five children that all share one leaf call site and all have the owner’s site higher in their stack. The assertions: the owner has exactly five edges, no child has any. The comment says what this guards against: without "sibling exclusion", each child would see the previous child (same leaf site) as a candidate owner and the star would collapse into a chain. The exclusion is that a node’s own site name is not among the names its search looks for.'),
    blank,
    ...sec(r'chain, siblings, roots'),
    ...code('rust', r'crates/heaplens-daemon/tests/graph_unit.rs · lines 67-90', r'''
// --- Fix 3(b): genuine chain (A -> B -> C) --------------------------------
#[test]
fn phi_genuine_chain_a_owns_b_owns_c() {
    let a_site = 0xA000;
    let b_site = 0xB000;
    let c_site = 0xC000;
    let r = resolver_with_real_sites(&[a_site, b_site, c_site]);
    let mut g = OwnershipGraph::new();

    g.on_alloc(&make_ev(EventKind::Alloc, 0x1000, 0, 64, 100, &[a_site]), &r);
    g.on_alloc(&make_ev(EventKind::Alloc, 0x2000, 0, 64, 200, &[b_site, a_site]), &r);
    g.on_alloc(&make_ev(EventKind::Alloc, 0x3000, 0, 64, 300, &[c_site, b_site]), &r);

    let diff = g.drain_diff(&r);
    let (add, _, _) = unwrap_diff(diff);

    let a = add.iter().find(|n| n.ptr == 0x1000).unwrap();
    let b = add.iter().find(|n| n.ptr == 0x2000).unwrap();
    let c = add.iter().find(|n| n.ptr == 0x3000).unwrap();

    assert!(a.edges.contains(&b.id), "A should own B");
    assert!(b.edges.contains(&c.id), "B should own C");
    assert!(!a.edges.contains(&c.id), "A must not directly own C");
}'''),
    ...pt('//', r'phi_genuine_chain_a_owns_b_owns_c',
        r'A to B to C, each allocated with the previous one’s site in its stack. A owns B, B owns C, and A does not directly own C. Ownership is one hop here: C’s stack only mentions B’s site, so A gets no direct edge to C.'),
    ...pt('//', r'phi_sibling_exclusion_identical_site_no_edge',
        r'two nodes at the same single-frame site: no edges either way.'),
    ...pt('//', r'phi_root_when_no_candidate_matches',
        r'one node on its own is a root with no edges.'),
    ...pt('//', r'phi_root_when_stack_is_entirely_machinery',
        r'a stack that holds only a frame classified as machinery has no site at all, so no owner, and the owner of nothing.'),
    ...sec(r'tie-break by recency'),
    ...code('rust', r'crates/heaplens-daemon/tests/graph_unit.rs · lines 142-169', r'''
// --- Fix 3(e): tie-break by greatest ts, among valid candidates only -------
#[test]
fn phi_tiebreak_by_greatest_ts_among_valid_candidates() {
    let owner_site = 0xAAAA;
    let leaf_site = 0xBBBB;
    let decoy_site = 0xEEEE; // a real site that just never appears in the child's stack
    let r = resolver_with_real_sites(&[owner_site, leaf_site, decoy_site]);
    let mut g = OwnershipGraph::new();

    g.on_alloc(&make_ev(EventKind::Alloc, 0x1000, 0, 64, 100, &[owner_site]), &r);
    g.on_alloc(&make_ev(EventKind::Alloc, 0x9000, 0, 64, 150, &[decoy_site]), &r); // never matched
    g.on_alloc(&make_ev(EventKind::Alloc, 0x2000, 0, 64, 200, &[owner_site]), &r); // same site, greater ts

    let c_ev = make_ev(EventKind::Alloc, 0x3000, 0, 32, 300, &[leaf_site, owner_site]);
    g.on_alloc(&c_ev, &r);

    let diff = g.drain_diff(&r);
    let (add, _, _) = unwrap_diff(diff);

    let older = add.iter().find(|n| n.ptr == 0x1000).unwrap();
    let newer = add.iter().find(|n| n.ptr == 0x2000).unwrap();
    let decoy = add.iter().find(|n| n.ptr == 0x9000).unwrap();
    let child = add.iter().find(|n| n.ptr == 0x3000).unwrap();

    assert!(newer.edges.contains(&child.id), "greatest-ts candidate should own the child");
    assert!(!older.edges.contains(&child.id));
    assert!(decoy.edges.is_empty(), "decoy never matched the child's search window");
}'''),
    ...para('//',
        r'Two live nodes at the same owner site (ts 100 and ts 200) and a decoy at another site. A child arrives whose ancestor is that site. The newer one owns it. The decoy, a real site that is simply not in the child’s stack, gets nothing: the candidate set is built from names on the child’s own stack, not from all live nodes. The test name is exact about the order of operations, "greatest ts among valid candidates only": the decoy has a greater ts than the older owner, and the test would catch an implementation that took the maximum before filtering.'),
    blank,
    ...sec(r'the original bug and why it is pinned'),
    ...code('rust', r'crates/heaplens-daemon/tests/graph_unit.rs · lines 171-194', r'''
// --- Regression: the original bug ------------------------------------------
// Two allocations from genuinely different real call sites, both preceded by
// the same shared machinery frame (as every allocation is in production,
// since every event funnels through capture_stack -> record -> alloc). They
// must not be attributed to each other just because they share that leading
// frame — this is exactly the universal-chain failure mode that was found.
#[test]
fn phi_shared_machinery_prefix_does_not_cause_false_ownership() {
    let mut r = Resolver::new();
    r.insert(0xF00D, "heaplens_alloc::record".to_owned(), true);
    r.insert(0xAAAA, "producer::site_a".to_owned(), false);
    r.insert(0xBBBB, "producer::site_b".to_owned(), false);

    let mut g = OwnershipGraph::new();
    g.on_alloc(&make_ev(EventKind::Alloc, 0x1000, 0, 64, 100, &[0xF00D, 0xAAAA]), &r);
    g.on_alloc(&make_ev(EventKind::Alloc, 0x2000, 0, 64, 200, &[0xF00D, 0xBBBB]), &r);

    let diff = g.drain_diff(&r);
    let (add, _, _) = unwrap_diff(diff);
    let first = add.iter().find(|n| n.ptr == 0x1000).unwrap();
    let second = add.iter().find(|n| n.ptr == 0x2000).unwrap();
    assert!(first.edges.is_empty());
    assert!(second.edges.is_empty(), "second alloc must not be chained onto the first via the shared machinery frame");
}'''),
    ...para('//',
        r'The comment calls it "the original bug" and "the universal-chain failure mode". Every real allocation in the target goes through the same instrumentation frames (capture_stack, record, alloc). If those frames counted as call sites, every allocation would share an ancestor with every other, and the graph would become one long chain. Here two allocations from different real sites share the leading machinery frame 0xF00D, flagged true in the resolver. Neither may own the other. The classification, not the stack depth, is what makes φ usable on real binaries.'),
    blank,
    ...sec(r'function-name granularity'),
    ...code('rust', r'crates/heaplens-daemon/tests/graph_unit.rs · lines 196-224', r'''
// --- Fix 2b: function-name granularity -------------------------------------
// Reproduces the exact shape that produced 0 edges against the real
// wire_producer.exe: an owner allocated by one statement in a function, and
// a child allocated (via a helper) by a *different* statement in the same
// function. The owner's own effective-site address and the child's ancestor
// address are deliberately different (addrA != addrB) but both resolve to
// the same function name — only name-based matching can link them.
#[test]
fn phi_links_owner_and_child_via_same_enclosing_function_different_addresses() {
    let addr_a = 0xA1; // owner's own site: `let outer = vec![...]` inside nested_alloc
    let addr_b = 0xA2; // child's ancestor: the `leaf_alloc(...)` call site inside nested_alloc
    let leaf_site = 0xB1;
    assert_ne!(addr_a, addr_b, "the two statements must be genuinely different addresses");

    let mut r = Resolver::new();
    r.insert(addr_a, "producer::nested_alloc".to_owned(), false);
    r.insert(addr_b, "producer::nested_alloc".to_owned(), false); // same function, different IP
    r.insert(leaf_site, "producer::leaf_alloc".to_owned(), false);

    let mut g = OwnershipGraph::new();
    g.on_alloc(&make_ev(EventKind::Alloc, 0x1000, 0, 128, 100, &[addr_a]), &r);
    g.on_alloc(&make_ev(EventKind::Alloc, 0x2000, 0, 64, 200, &[leaf_site, addr_b]), &r);

    let diff = g.drain_diff(&r);
    let (add, _, _) = unwrap_diff(diff);
    let owner = add.iter().find(|n| n.ptr == 0x1000).unwrap();
    let child = add.iter().find(|n| n.ptr == 0x2000).unwrap();
    assert!(owner.edges.contains(&child.id), "owner should own child via shared enclosing function name, despite different exact addresses");
}'''),
    ...para('//',
        r'This is the regression for commit 43fc22e (2026-07-08), "function-name-granularity ownership inference". The comment names the real-world case: against the compiled wire_producer example, address matching produced zero edges. An owner allocated by one statement in nested_alloc and a child allocated through a helper called from a different statement in the same function have different return addresses. They only meet if the matching is by resolved function name. The test sets two different addresses (asserted unequal) to the same name and expects the edge.'),
    blank,
    ...sec(r'the two tests that document imprecision'),
    ...para('//',
        r'Most test files assert what the code gets right. These two assert what it gets wrong and say so in their names and comments. They are the most honest part of the file.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/graph_unit.rs · lines 233-267', r'''
#[test]
fn phi_ambiguity_two_unrelated_containers_in_same_function() {
    let main_site_a = 0xF1; // `let vec_a = vec![...];` in main
    let main_site_b = 0xF2; // `let vec_b = vec![...];` in main, unrelated to vec_a
    let call_site = 0xF3;   // `helper()` call in main, later allocates a child
    let child_site = 0xC1;

    let mut r = Resolver::new();
    r.insert(main_site_a, "producer::main".to_owned(), false);
    r.insert(main_site_b, "producer::main".to_owned(), false);
    r.insert(call_site, "producer::main".to_owned(), false);
    r.insert(child_site, "producer::helper".to_owned(), false);

    let mut g = OwnershipGraph::new();
    // vec_a allocated first, vec_b allocated later (greater ts) — both live,
    // both resolve to "producer::main", neither is actually related to the
    // child that main() later causes helper() to allocate.
    g.on_alloc(&make_ev(EventKind::Alloc, 0x1000, 0, 64, 100, &[main_site_a]), &r);
    g.on_alloc(&make_ev(EventKind::Alloc, 0x2000, 0, 64, 200, &[main_site_b]), &r);

    let child_ev = make_ev(EventKind::Alloc, 0x3000, 0, 32, 300, &[child_site, call_site]);
    g.on_alloc(&child_ev, &r);

    let diff = g.drain_diff(&r);
    let (add, _, _) = unwrap_diff(diff);
    let vec_a = add.iter().find(|n| n.ptr == 0x1000).unwrap();
    let vec_b = add.iter().find(|n| n.ptr == 0x2000).unwrap();
    let child = add.iter().find(|n| n.ptr == 0x3000).unwrap();

    // Documented behavior: the child is attributed to whichever "main"-site
    // node has the greatest ts (vec_b), not to neither (which would be the
    // structurally honest answer, but is not what this design computes).
    assert!(vec_b.edges.contains(&child.id), "greatest-ts candidate wins, even though it has no real relationship to the child — this is the documented ambiguity, not a bug");
    assert!(!vec_a.edges.contains(&child.id));
}'''),
    ...para('//',
        r'Two unrelated vectors allocated directly in main, and then a child that main() causes a helper to allocate. All three resolve to the same name, so both vectors are valid candidates, and the greatest-ts rule picks the later one, "even though it has no real relationship to the child". The comment closes: "this is the documented ambiguity, not a bug". The test’s purpose is to lock the behaviour in, so that a change to φ that improves or worsens it has to touch this test on purpose.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/graph_unit.rs · lines 331-354', r'''
#[test]
fn phi_recency_discriminator_misattributes_late_child_to_newer_same_name_owner() {
    let owner_site = 0xAAAA;
    let leaf_site = 0xBBBB;
    let r = resolver_with_real_sites(&[owner_site, leaf_site]);
    let mut g = OwnershipGraph::new();

    g.on_alloc(&make_ev(EventKind::Alloc, 0x1000, 0, 64, 100, &[owner_site]), &r); // owner1
    g.on_alloc(&make_ev(EventKind::Alloc, 0x2000, 0, 32, 200, &[leaf_site, owner_site]), &r); // child1a: correctly owner1 (only live candidate)
    g.on_alloc(&make_ev(EventKind::Alloc, 0x3000, 0, 64, 300, &[owner_site]), &r); // owner2, now also live and same name

    // owner1's second child arrives after owner2 already exists.
    let late_child = make_ev(EventKind::Alloc, 0x4000, 0, 32, 400, &[leaf_site, owner_site]);
    g.on_alloc(&late_child, &r);

    let diff = g.drain_diff(&r);
    let (add, _, _) = unwrap_diff(diff);
    let owner1 = add.iter().find(|n| n.ptr == 0x1000).unwrap();
    let owner2 = add.iter().find(|n| n.ptr == 0x3000).unwrap();
    let late = add.iter().find(|n| n.ptr == 0x4000).unwrap();

    assert!(owner2.edges.contains(&late.id), "recency tie-break attributes the late child to the newer same-name owner, not its true owner");
    assert!(!owner1.edges.contains(&late.id));
}'''),
    ...para('//',
        r'Two tests state the limits of recency as a discriminator. In the first, eight invocations of the same function each allocate an owner and ten children strictly in sequence. Recency partitions them perfectly: eight owners with ten edges each, and no child claimed twice. In the second, a late child of the first owner arrives after a newer same-named owner exists, and is attributed to the newer one. The comment explains why: Node carries "no thread id, no call/return bracketing, no dynamic extent". Overlapping or concurrent calls to the same function are exactly the case this heuristic cannot untangle, and the comment’s example refers to "the jury’s ‘two threads both in make_family’ question". The pairing is the point: it shows that the error is the exception under the access pattern the producers use, and it names the exception.'),
    blank,
    ...sec(r'dealloc, cascade, realloc'),
    ...code('rust', r'crates/heaplens-daemon/tests/graph_unit.rs · lines 356-387', r'''
// dealloc: child.owner becomes None, child.had_owner_once becomes true
#[test]
fn dealloc_orphans_children() {
    let owner_site = 0xAAAA;
    let leaf_site = 0xBBBB;
    let r = resolver_with_real_sites(&[owner_site, leaf_site]);
    let mut g = OwnershipGraph::new();

    let o_ev = make_ev(EventKind::Alloc, 0x1000, 0, 64, 100, &[owner_site]);
    g.on_alloc(&o_ev, &r);
    let c_ev = make_ev(EventKind::Alloc, 0x2000, 0, 32, 200, &[leaf_site, owner_site]);
    g.on_alloc(&c_ev, &r);

    let _ = g.drain_diff(&r);

    g.on_dealloc(0x1000, 500);

    let diff = g.drain_diff(&r);
    let (_, updated, removed) = unwrap_diff(diff);

    assert!(!removed.is_empty(), "owner should be in removed");
    assert!(!updated.is_empty(), "child should be in updated");

    let update_ids: std::collections::HashSet<u64> = updated.iter().map(|n| n.id).collect();
    for &rid in &removed {
        assert!(!update_ids.contains(&rid), "id {rid} must not be in both update and remove");
    }

    let child_node = g.node_by_ptr(0x2000).expect("child still live");
    assert!(child_node.had_owner_once, "child.had_owner_once must be true after owner freed");
    assert!(child_node.owner.is_none(), "child.owner must be None after owner freed");
}'''),
    ...pt('//', r'dealloc_orphans_children',
        r'drains once to clear the accumulators, frees the owner, drains again. The owner is in remove, the child in update, no id appears in both, and the child’s owner is None while had_owner_once is true. That pair of fields is what anomaly::sweep reads to decide on Orphan. The disjointness check goes back to commit b1f2215, "remove/update/add must be disjoint".'),
    ...pt('//', r'cascaded_dealloc_same_tick_disjoint',
        r'frees child then owner with no drain between. It checks that no id in remove shows up in add or update. Because a node born and freed in one tick is suppressed from add entirely, this test is mostly proving that the diff is self-consistent in the awkward case rather than asserting specific contents.'),
    ...pt('//', r'realloc_migrates_ptr_and_updates_size',
        r'on_realloc keeps the node’s id, moves ptr and updates size, and reports one update. A realloc is not a free plus an alloc, because that would orphan the node’s children.'),
    ...sec(r'the diff plumbing'),
    ...code('rust', r'crates/heaplens-daemon/tests/graph_unit.rs · lines 459-473', r'''
// resolver join: symbol attached at drain_diff time, from the effective site
#[test]
fn drain_diff_attaches_symbol_from_resolver() {
    let mut g = OwnershipGraph::new();
    let ev = make_ev(EventKind::Alloc, 0x1000, 0, 64, 100, &[0xAAAA]);
    let r0 = Resolver::new();
    g.on_alloc(&ev, &r0);

    let mut r = Resolver::new();
    r.insert(0xAAAA, "my_alloc_site".to_owned(), false);

    let diff = g.drain_diff(&r);
    let (add, _, _) = unwrap_diff(diff);
    assert_eq!(add[0].symbol, "my_alloc_site");
}'''),
    ...para('//',
        r'Three small tests on drain_diff: a second drain with no new events is empty (the accumulators clear); the symbol on a NodeDto comes from the resolver at drain time, not at alloc time (the resolver is empty when the event arrives and has a name when the diff is built, so late SYMBOLS frames are picked up); and an address the resolver does not know yields the placeholder symbol "?".'),
    blank,
    ...sec(r'eviction: the memory fix'),
    ...code('rust', r'crates/heaplens-daemon/tests/graph_unit.rs · lines 498-504, 515-526, 531-547, 553-563, 578-590', r'''
#[test]
fn dead_nodes_are_evicted_without_changing_diff_or_orphan_detection() {
    let owner_site = 0xAAAA;
    let leaf_site = 0xBBBB;
    let r = resolver_with_real_sites(&[owner_site, leaf_site]);
    let mut g = OwnershipGraph::new();
    let config = Config {
...
    // ── Tick 1: parent and child both born ──────────────────────────────
    g.on_alloc(&make_ev(EventKind::Alloc, 0x1000, 0, 64, 0, &[owner_site]), &r);
    g.on_alloc(&make_ev(EventKind::Alloc, 0x2000, 0, 32, 1, &[leaf_site, owner_site]), &r);
    let parent_id = g.node_by_ptr(0x1000).unwrap().id;
    let child_id = g.node_by_ptr(0x2000).unwrap().id;

    let diff1 = g.drain_diff(&r);
    let (add1, update1, remove1) = unwrap_diff(diff1);
    assert_eq!(add1.len(), 2, "tick 1: both parent and child must be in add");
    assert!(update1.is_empty() && remove1.is_empty());
    assert_eq!(g.nodes().len(), 2, "tick 1: both nodes present after drain, nothing evicted yet");

...
    g.on_dealloc(0x1000, 10);
    let diff2 = g.drain_diff(&r);
    let (add2, update2, remove2) = unwrap_diff(diff2);
    assert!(add2.is_empty(), "tick 2: nothing new born");
    assert_eq!(remove2, vec![parent_id], "tick 2: parent must be the only removed id");
    assert_eq!(update2.len(), 1, "tick 2: child must be the only updated node");
    assert_eq!(update2[0].id, child_id);

    assert_eq!(
        g.nodes().len(), 1,
        "tick 2: parent must be evicted from self.nodes right after this drain \
         (this is the actual fix under test) — child must remain (still live)"
    );
    let child = g.node_by_ptr(0x2000).expect("child still live and findable by ptr");
    assert!(child.owner.is_none() && child.had_owner_once, "child correctly orphaned by on_dealloc");
    assert_eq!(child.owner_free_ts, Some(10));

...
    const ORPHAN_DETECTED_TS_NS: u64 = 10 + 6_000_000; // owner_free_ts + tau_ms(5ms) + margin
    g.on_alloc(&make_ev(EventKind::Alloc, 0x3000, 0, 8, ORPHAN_DETECTED_TS_NS, &[0xCCCC]), &r);
    let sentinel_id = g.node_by_ptr(0x3000).unwrap().id;

    let max_ts = g.max_ts_seen;
    let changed = sweep(g.nodes_mut(), max_ts, &config);
    assert_eq!(changed, vec![child_id], "only the child's state should flip, to Orphan");
    assert_eq!(g.nodes().get(&child_id).unwrap().state, NodeState::Orphan);
    g.mark_updated(child_id); // exactly what main.rs's Tick handler does for each changed id

    let diff3 = g.drain_diff(&r);
...
    // ── Tick 4: child finally freed too — must also be evicted, proving
    //    the fix applies uniformly, not just to nodes that die alone. ────
    g.on_dealloc(0x2000, ORPHAN_DETECTED_TS_NS + 1);
    let diff4 = g.drain_diff(&r);
    let (add4, update4, remove4) = unwrap_diff(diff4);
    assert!(add4.is_empty() && update4.is_empty());
    assert_eq!(remove4, vec![child_id], "tick 4: child must be the only removed id");

    assert_eq!(
        g.nodes().len(), 1,
        "tick 4: child evicted; only the still-live sentinel remains — \
         the graph does not leak across a full parent+child+orphan lifecycle"
    );'''),
    ...para('//',
        r'The last test was written for commit 4e8868f (2026-07-22), "evict dead nodes from OwnershipGraph, closing unbounded growth". The comment in graph.rs describes what had been wrong: on_dealloc never removed nodes, so every allocation ever seen stayed in the map, ownership inference scanned them all, and one measured run had 102,225 total nodes with 7 live and a daemon 49 seconds behind its own event stream.'),
    blank,
    ...para('//',
        r'The test walks a full life in four ticks and checks nodes().len() at each step: 2 after both are born, 1 after the parent is freed (the diff still reports the parent in remove and the child in update), 2 again when a sentinel allocation advances the clock and sweep flips the child to Orphan, and 1 after the child is freed. The header comment explains why it checks every tick rather than the end: "a test that only checked the final count could pass even if eviction happened too early and silently corrupted a tick’s diff". In tick 3 it also reproduces the main.rs Tick step by calling mark_updated on each changed id. It confirms that orphan detection does not need the dead parent’s struct. Notice that the sentinel’s timestamp, 6,000,010, is written as the "owner_free_ts + tau + margin", while sweep actually compares against the child’s own alloc ts (1). Both are past tau, so the test passes either way. The comment describes a rule slightly different from the one the code applies.'),
    blank,
    ...sec(r'what is not here'),
    ...pt('//', r'Out-of-order or duplicate events',
        r'a dealloc for an unknown pointer is silently ignored by on_dealloc, and no test sends one.'),
    ...para('//',
        r'· A realloc of an unknown pointer.'),
    ...pt('//', r'Pending symbols',
        r'the SiteClass::Pending path, where a node is allocated before its SYMBOLS frame arrives, is only touched indirectly by the symbol-at-drain test.'),
    ...para('//',
        r'· Scale. The eviction test is a behavioural check on four nodes; the 102,225-node figure from graph.rs’s comment is not reproduced here.'),
    ...sec(r'how it fits'),
    ...para('//',
        r'Everything above feeds the object the other tests share. ws_tests.rs and the wire tests run the same OwnershipGraph under a server; anomaly_unit.rs and orphan_persistence.rs run sweep over its nodes; ingest_loopback.rs shows the events path into it. If the graph is wrong, these are the first tests to say so and the only ones that say why.'),
    blank,
    ...sec(r'history'),
    ...pt('//', r'9843e94 (2026-07-01)',
        r'graph.rs with phi inference and eight unit tests.'),
    ...pt('//', r'b1f2215 (2026-07-01)',
        r'remove/update/add made disjoint; node_by_ptr added.'),
    ...pt('//', r'338abef (2026-07-06)',
        r'a clippy lint fix in this file, bundled with the anomaly change.'),
    ...pt('//', r'43fc22e (2026-07-08)',
        r'function-name granularity, and the tests rewritten around the classification-based lookup.'),
    ...pt('//', r'b97b008 (2026-07-16)',
        r'owner_free_ts.'),
    ...pt('//', r'0edc728 (2026-07-17)',
        r'target-diagnostics counters; here only the unwrap_diff helper changed, to print whatever variant arrived instead of assuming a Snapshot.'),
    ...pt('//', r'4e8868f (2026-07-22)',
        r'node eviction, and the four-tick test.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/tests/graph_unit.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/tests/graph_unit.rs'),
  ],
);
