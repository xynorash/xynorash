import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/examples/support/checkout_common.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'checkout_common.rs — the ownership rules, written as a shared module'),
    cm('//', r'five allocation sites and four event triggers that every checkout '
              r'target must call the same way'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'shared allocation sites and event logic for the console, TUI and '
              r'(parked) GUI checkout demos'),
    kv('language', r'Rust, included into each binary with #[path] (not a separate crate)'),
    kv('size', r'160 lines, 87 of them comments'),
    kv('history', r'3 commits, all on 2026-07-28: 9693399, a31baeb, d192626'),
    kv('warning in its own header', r'"do not change allocation shape, frame structure, or timing here"'),
    ...sec(r'what problem this file solves'),
    ...para('//',
        r'HeapLens infers who owns what from call stacks. That works only '
        r'if the program under observation allocates in a shape the '
        r'inference can read, and "the shape" turned out to be fragile: '
        r'one extra Vec, one function split in two, and the graph shows '
        r'the wrong thing or nothing. The checkout demos need that shape '
        r'to be right in three different binaries, a console loop, a '
        r'terminal UI and a GUI, each with completely different control '
        r'flow. The solution is to put every allocation and every event '
        r'trigger in one file and make the binaries call it.'),
    blank,
    ...para('//',
        r'The header says what the file protects: "This is the one part of '
        r'any target that’s already proven to produce correct φ '
        r'attribution; do not change allocation shape, frame structure, or '
        r'timing here without re-validating against the wire test." It is '
        r'included into each example with #[path = '
        r'"support/checkout_common.rs"], so it is compiled into each '
        r'binary and is not a crate of its own. The idea is a single '
        r'source of truth for a thing that cannot be allowed to drift.'),
    ...sec(r'the rules, as the module states them'),
    ...code('rust', 'crates/heaplens-alloc/examples/support/checkout_common.rs · module documentation', r'''
//! Shared allocation sites AND shared event logic for `checkout_service.rs`
//! (console), `checkout_service_tui.rs` (ratatui TUI), and
//! `checkout_service_gui.rs` (iced GUI demo, parked) — included via
//! `#[path]` by each binary, not a separate crate. This is the one part of
//! any target that's already proven to produce correct φ attribution; **do
//! not change allocation shape, frame structure, or timing here** without
//! re-validating against the wire test.
//!
//! Every function here is `#[inline(never)]` for the same reason: phi
//! links a child to an owner by matching the owner's effective call site
//! against the *ancestor frames* of the child's own captured stack, and an
//! inlined function never contributes its own frame to that match.
//!
//! The event-trigger functions below (`leak_pool_tick`, `hot_cluster_tick`,
//! `hot_cluster_heal`, `storm_burst`) own BOTH the owner allocation and its
//! children's allocation calls, in the same function — this is what makes
//! them safe to share across every target regardless of that target's own
//! control flow (a blocking loop for the console, an event-driven tick for
//! the TUI): phi only cares that an owner and its children share the same
//! *immediate calling frame*, and since that frame is now this shared
//! function itself, it stays consistent no matter which binary calls it,
//! or how many times. Do not split an owner's allocation from its
//! children's into two separate functions — see `hot_cluster_tick`'s own
//! doc comment for why the "start" and "grow" calls must stay one function
//! called twice, not two functions.'''),
    ...para('//',
        r'Three rules are packed into those lines.'),
    blank,
    ...para('//',
        r'Every function is #[inline(never)]. The inference links a child '
        r'to an owner by matching the owner’s effective call site against '
        r'the ancestor frames of the child’s captured stack, and "an '
        r'inlined function never contributes its own frame to that match". '
        r'A function the optimiser merges into its caller vanishes from '
        r'the stack, and with it the link.'),
    blank,
    ...para('//',
        r'The event triggers own both the owner and its children’s '
        r'allocation calls, in the same function. That is what makes them '
        r'safe to share. The inference "only cares that an owner and its '
        r'children share the same immediate calling frame", and since that '
        r'frame is now this shared function, it is the same whichever '
        r'binary calls it and however many times.'),
    blank,
    ...para('//',
        r'And a rule about splitting: "Do not split an owner’s allocation '
        r'from its children’s into two separate functions." The reason is '
        r'in hot_cluster_tick, below.'),
    ...sec(r'the leaf allocation sites'),
    ...code('rust', 'crates/heaplens-alloc/examples/support/checkout_common.rs · request_handler_handle and the three allocation helpers', r'''
/// Stand-in for a serialized Response body. Doubles as ordinary healthy
/// traffic in both binaries — matched alloc/dealloc pairs, nothing ever
/// accumulates.
#[inline(never)]
pub fn request_handler_handle(n: usize) {
    let response = vec![0u8; 96];
    std::hint::black_box(&response);
    drop(response);
    let _ = n;
}

/// Each checked-out connection — a real one would hold a socket, auth
/// token, and buffers; `128` bytes stands in for that struct. Caller must
/// allocate the pool manager directly in its own frame first — see the
/// module doc comment.
#[inline(never)]
pub fn payment_gateway_pool_checkout_connections(n: usize) -> Vec<Vec<u8>> {
    (0..n).map(|_| vec![0u8; 128]).collect()
}

/// A real order — a real one would hold line items, a customer id,
/// shipping address; `96` bytes stands in for that struct. Caller must
/// allocate the queue owner directly in its own frame first — see the
/// module doc comment.
#[inline(never)]
pub fn order_queue_accept_orders(n: usize) -> Vec<Vec<u8>> {
    (0..n).map(|_| vec![0u8; 96]).collect()
}

/// A single metrics log entry — small, high-frequency, exactly the shape
/// that turns into a storm when something upstream stops throttling how
/// often it fires.
#[inline(never)]
pub fn metrics_flush_write_entry(n: usize) {
    let entry = vec![0u8; 24];
    std::hint::black_box(&entry);
    drop(entry);
    let _ = n;
}'''),
    ...para('//',
        r'Four small functions, each a stand-in for something a real '
        r'service would do. request_handler_handle allocates a 96-byte '
        r'buffer, a "serialized Response body", and frees it: ordinary '
        r'traffic, with nothing accumulating. '
        r'payment_gateway_pool_checkout_connections makes n connections of '
        r'128 bytes each (the stand-in for a socket, an auth token and '
        r'buffers). order_queue_accept_orders makes n orders of 96 bytes. '
        r'metrics_flush_write_entry makes a 24-byte log entry and frees '
        r'it. The realistic names are deliberate: the checkout service is '
        r'written to look like a service, not a test, and the node labels '
        r'the UI shows (payment_gateway_pool_checkout_connections) are the '
        r'things a viewer would read.'),
    blank,
    ...para('//',
        r'Two of them carry the same instruction in their doc comments: '
        r'"Caller must allocate the pool manager directly in its own frame '
        r'first" and "Caller must allocate the queue owner directly in its '
        r'own frame first". They only make children; the owner has to '
        r'exist, in a frame that is an ancestor of the call, before they '
        r'run.'),
    ...sec(r'the leak'),
    ...code('rust', 'crates/heaplens-alloc/examples/support/checkout_common.rs · leak_pool_tick', r'''
/// Leak trigger, shared by every target. Call once with `release: false` to
/// check out the pool manager and its 12 connections together (so both
/// share this function as their φ-owner call site); call again later with
/// `release: true` to drop the manager while the connections are still
/// held — the bug. The caller owns storing/moving the connections
/// afterward (into a permanent leaked-connections accumulator); this
/// function only performs the allocation/drop pair itself.
#[inline(never)]
pub fn leak_pool_tick(
    pool_manager: &mut Option<Vec<u8>>,
    pending_connections: &mut Option<Vec<Vec<u8>>>,
    release: bool,
) {
    if !release {
        *pool_manager = Some(vec![0u8; 256]);
        *pending_connections = Some(payment_gateway_pool_checkout_connections(12));
    } else {
        *pool_manager = None; // the bug: manager torn down, connections never released
    }
}'''),
    ...para('//',
        r'One function, two calls. With release: false it allocates the '
        r'pool manager (256 bytes) and checks out 12 connections, so the '
        r'manager and its connections share leak_pool_tick as their owner '
        r'site. With release: true it sets the manager to None, which '
        r'frees it while the connections are still held somewhere else. '
        r'That line is the bug the demo exists to show: "the bug: manager '
        r'torn down, connections never released". The caller owns moving '
        r'the connections into a never-freed accumulator, so they stay '
        r'live and become orphans.'),
    blank,
    ...para('//',
        r'How the module got this shape is in commit f6ec325, where '
        r'checkout_service was first written. In its first draft the pool '
        r'manager was created by a helper function, and the connections by '
        r'a second one, each called from main, and neither from the other. '
        r'The message records the consequence: the manager’s call site '
        r'"never appeared as an ancestor frame of any connection’s '
        r'captured stack — phi found no owner to link at all, not ’no '
        r'longer owned’". The distinction matters. A leak is only visible '
        r'if the connections were first owned and then lost their owner; a '
        r'graph in which they never had one shows nothing. The fix was to '
        r'allocate the manager directly in the function that also calls '
        r'the connection helper, so that function appears in each '
        r'connection’s stack and is the manager’s own site.'),
    ...sec(r'the hot cluster, and the line that took two tries'),
    ...code('rust', 'crates/heaplens-alloc/examples/support/checkout_common.rs · hot_cluster_tick', r'''
/// Hot-cluster growth trigger, shared by every target. Call once with
/// `add_extra: false` to allocate the queue owner and its initial 10-order
/// batch (only if not already owned); call again later with
/// `add_extra: true` to add the +30 batch that pushes it past the healthy
/// threshold. Both calls MUST go through this same function — the initial
/// batch and the "+30 more" batch are two separate allocation calls, and
/// phi only credits the queue owner with a child allocation if this
/// function's own frame is an ancestor of that child's captured stack.
/// Splitting "start" and "grow" into two different functions would break
/// that: the +30 batch's ancestor chain would then go through the *other*
/// function's frame, which is not the queue owner's own effective site,
/// and phi would never link it back.
///
/// `backlog.reserve(40)` happens *before* `queue_owner` is allocated, not
/// after — matching `hot_producer.rs`'s own documented safe ordering
/// ("children's own backing storage must be allocated before owner, not
/// after"). `backlog` starts empty (`Vec::new()`), so without this
/// upfront reserve, its first `.extend()` call would grow its own backing
/// array *from inside this same function* — the same effective site as
/// `queue_owner` — making it a more-recently-allocated same-site
/// candidate than `queue_owner` by the time the second (`add_extra`)
/// batch arrives. Phi's recency tie-break would then attribute that
/// batch to backlog's own backing array instead of `queue_owner`,
/// splitting the 40 total children roughly 10/30 across two different
/// nodes, neither of which crosses `hot_cluster_threshold` (32) alone —
/// confirmed as the actual cause of `queue_owner` never flipping Hot in
/// the graph despite the console correctly logging "40 orders and still
/// growing." Reserving the full capacity upfront means every later
/// `.extend()` fits in already-allocated space, so no such reallocation
/// — and no such competing candidate — ever occurs.
#[inline(never)]
pub fn hot_cluster_tick(queue_owner: &mut Option<Vec<u8>>, backlog: &mut Vec<Vec<u8>>, add_extra: bool) {
    if queue_owner.is_none() {
        backlog.reserve(40);
        *queue_owner = Some(vec![0u8; 512]);
        backlog.extend(order_queue_accept_orders(10));
    }
    if add_extra {
        backlog.extend(order_queue_accept_orders(30));
    }
}'''),
    ...para('//',
        r'Two requirements are stacked in this function’s comment. First: '
        r'the "start" and the "grow" calls must go through the same '
        r'function. The first call allocates the 512-byte queue owner and '
        r'a batch of 10 orders; a later call with add_extra: true adds 30 '
        r'more. They are separate allocation calls, and the owner is only '
        r'credited with a child if its own frame is an ancestor of the '
        r'child’s stack. If starting and growing were two different '
        r'functions, the second batch’s ancestors would run through the '
        r'other function’s frame, which is not the owner’s site, and the '
        r'inference would never link it back.'),
    blank,
    ...para('//',
        r'Second: backlog.reserve(40) before the owner. This was added on '
        r'2026-07-28 in commit d192626, titled "hot_cluster_tick’s '
        r'backlog.reserve before owner — fixes Hot never firing". The '
        r'symptom: the console logged "40 orders and still growing" but in '
        r'the graph the queue owner never turned Hot. The bug came in with '
        r'the refactor itself. The original in-main code (f6ec325) built '
        r'the backlog from the Vec that order_queue_accept_orders '
        r'returned, so its buffer was allocated in that helper, at another '
        r'call site, and growing it later was only a realloc; the shared '
        r'version replaced that with an empty Vec::new(). The cause is the '
        r'same ordering trap as in the demo and hot producers, wearing a '
        r'different disguise. backlog starts as Vec::new(), with no '
        r'allocation. Its first extend() allocates a backing array from '
        r'inside this very function, after the owner exists. That array '
        r'has the same effective site as the owner and is newer, so for '
        r'the second batch of 30 it wins the recency tie-break. The 40 '
        r'children were split roughly 10 on the owner and 30 on the '
        r'backlog’s own buffer, "neither of which crosses '
        r'hot_cluster_threshold (32) alone". Reserving the capacity first '
        r'means the buffer is older than the owner and never competes.'),
    blank,
    ...para('//',
        r'The author’s own note on the method is worth repeating. The '
        r'commit says "Verified live: the queue_owner node now renders '
        r'amber and ’Growing cluster’ appears in Insights during the '
        r'hot-cluster phase". The bug was found in a live run, not by a '
        r'test, and it is possible to see why the tests missed it. The '
        r'TUI’s wire test asserts only that some node has a fan-out of at '
        r'least 25. A backlog buffer holding 30 children satisfies that as '
        r'well as an owner holding 40. The test cannot tell the two apart.'),
    ...sec(r'the heal: recovery that stays visible'),
    ...code('rust', 'crates/heaplens-alloc/examples/support/checkout_common.rs · hot_cluster_heal', r'''
/// Hot-cluster recovery, shared by every target. Frees the backlog down to
/// a small healthy depth and moves the owner plus the remaining orders
/// into the caller's permanent "healthy" accumulators, rather than
/// dropping everything — a family that fully vanishes the instant it
/// heals reads identically to "nothing was ever here," not "this grew,
/// then came back under control." Returns the new total remnant count
/// (across every heal so far) for the caller's own logging. No new
/// allocations happen here, so this needs no owner/child call-site care —
/// it's a plain free/move operation.
pub fn hot_cluster_heal(
    queue_owner: &mut Option<Vec<u8>>,
    backlog: &mut Vec<Vec<u8>>,
    healthy_owners: &mut Vec<Vec<u8>>,
    healthy_remnants: &mut Vec<Vec<u8>>,
) -> usize {
    backlog.truncate(3);
    healthy_remnants.append(backlog);
    if let Some(owner) = queue_owner.take() {
        healthy_owners.push(owner);
    }
    healthy_remnants.len()
}'''),
    ...para('//',
        r'The console demo’s earlier recovery freed the owner and the '
        r'entire backlog when the cluster "healed". The message of commit '
        r'a31baeb explains what was wrong with that: "that made the whole '
        r'family vanish from the graph, indistinguishable from ’nothing '
        r'was ever here.’" The new function frees only the excess, '
        r'truncating the backlog to 3 orders, and then moves the owner and '
        r'those 3 orders into accumulators the caller keeps. The family '
        r'shrinks from 40 children to 3 and goes back to Healthy, but it '
        r'is still there. The comment states the principle: a family that '
        r'fully vanishes "reads identically to ’nothing was ever here,’ '
        r'not ’this grew, then came back under control.’"'),
    blank,
    ...para('//',
        r'No allocation happens here, so, as the comment says, it needs '
        r'"no owner/child call-site care". It also means a small, '
        r'permanent growth per cycle: the owner (512 bytes) and 3 orders '
        r'(96 bytes each) stay alive, which is why the console prints '
        r'"orders kept alive across all cycles".'),
    ...sec(r'the storm'),
    ...code('rust', 'crates/heaplens-alloc/examples/support/checkout_common.rs · storm_burst', r'''
/// Alloc-storm burst, shared by every target: `n` unthrottled metrics-flush
/// writes back to back.
#[inline(never)]
pub fn storm_burst(n: usize) {
    for i in 0..n {
        metrics_flush_write_entry(i);
    }
}'''),
    ...para('//',
        r'n unthrottled calls to metrics_flush_write_entry, nothing else. '
        r'It is the simplest function in the file. Whether it constitutes '
        r'a storm depends on how a caller schedules it, and the targets '
        r'differ: the console fires 2,000 per burst, the TUI 120 per '
        r'burst; see those pages.'),
    ...sec(r'how it is checked'),
    ...para('//',
        r'The check is the daemon’s cross-process wire tests: one drives '
        r'the TUI binary and asserts the topology (see the TUI page). They '
        r'assert shape, with deliberately tolerant bounds (a leak star of '
        r'8 to 14 children, a hot star of at least 25), and so they would '
        r'not catch a degradation like the reserve bug on their own. The '
        r'real check is a person watching the live graph: the commit '
        r'messages for d192626, f6ec325 and 50a9627 each end in a '
        r'"verified live" sentence.'),
    ...sec(r'what the file teaches'),
    ...para('//',
        r'The same lesson appears four times in this crate in different '
        r'clothes: demo_producer (container after owner), hot_producer '
        r'(the same), checkout_service’s first draft (manager in a '
        r'helper), and hot_cluster_tick (the lazily grown backlog). Each '
        r'time it was a program that did something perfectly reasonable '
        r'and the owner finder gave a surprising answer. The module doc '
        r'encodes the discipline that follows from it: allocate sibling '
        r'containers first, keep owner and children under one frame, never '
        r'inline, and treat the shape as frozen.'),
    ...sec(r'limits'),
    ...pt('//',
        r'the rules are conventions',
        r'nothing in the compiler stops a caller from violating them; the '
        r'file has no tests of its own.'),
    ...pt('//',
        r'heuristics, not proof',
        r'an edge means "allocated on a call path that passes through the '
        r'owner’s allocating function", which is why these demos have to '
        r'be written with care at all.'),
    ...pt('//',
        r'memory grows by design',
        r'leaked connections accumulate forever, plus the healed owner and '
        r'3 orders per cycle. By arithmetic on the constants that is about '
        r'2.3 KB per 2-minute console cycle (12 x 128 + 3 x 96 + 512 '
        r'bytes), roughly 70 KB an hour.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/examples/support/checkout_common.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/examples/support/checkout_common.rs'),
  ],
);
