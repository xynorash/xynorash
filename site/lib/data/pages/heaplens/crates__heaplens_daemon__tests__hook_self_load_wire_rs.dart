import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/tests/hook_self_load_wire.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'hook_self_load_wire.rs — the Stage 7 gate: count what the hook captured, by pointer'),
    cm('//', r'a DLL loads itself into a child process, runs a scripted workload, detaches; the daemon must have seen exactly that'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'Stage 7, Step 1 acceptance gate for heaplens-hook (docs/stage7-injection-design.md §8)'),
    kv('language', r'Rust, tokio multi-thread runtime, Windows only (#![cfg(windows)])'),
    kv('size', r'371 lines, 1 test, three commits (b3a22c2 2026-07-13, 724695a 2026-07-19, cd348b6 2026-07-21)'),
    kv('exercises', r'heaplens_hook.dll (via the self_load_harness example), ingest::run, OwnershipGraph'),
    kv('needs', r'cargo build -p heaplens-hook, cargo build --example self_load_harness -p heaplens-hook'),
    ...sec(r'where this sits in the architecture'),
    ...para('//',
        r'HeapLens captures allocations in two ways. A cooperative target links heaplens-alloc and uses it as its global allocator. An uncooperative one, any program, is instrumented from outside: heaplens-injector puts heaplens_hook.dll into the process, and the DLL hooks the Windows heap functions (RtlAllocateHeap, RtlReAllocateHeap, RtlFreeHeap), then streams events over the same named pipe in the same frame format. The daemon cannot tell the two apart; its ingest::run reads the same pipe either way. That is the architecture that makes this test possible: a daemon-side test with no injector in it can still prove the hook works.'),
    blank,
    ...para('//',
        r'Step 1 of the Stage 7 plan was the hook alone, without cross-process injection. The DLL’s entry points HeapLensHookAttach and HeapLensHookDetach are called by a harness that loaded the DLL into itself with LoadLibraryW. This test is the gate that step had to pass.'),
    blank,
    ...sec(r'the gate is about exactness'),
    ...code('rust', r'crates/heaplens-daemon/tests/hook_self_load_wire.rs · lines 2-20', r'''
//! Stage 7, Step 1 acceptance gate (docs/stage7-injection-design.md §8).
//!
//! Runs `heaplens-hook`'s self-load harness (`examples/self_load_harness.rs`
//! in the `heaplens-hook` package) as a real subprocess against a real
//! daemon, and asserts *exact* event counts and sizes against the harness's
//! known, scripted workload — not just "some events arrived." A gate that
//! only checked "the process ran without crashing" would pass with a
//! silently broken capture path.
//!
//! The harness prints every scripted operation's exact pointer (and size)
//! to stdout. This test parses that output and matches daemon-side events
//! to it by pointer identity, rather than asserting a raw global count:
//! hooking `RtlAllocateHeap`/`RtlReAllocateHeap`/`RtlFreeHeap` intercepts
//! *every* call to those functions process-wide, including Windows' own
//! internal heap traffic triggered as a side effect of the writer thread's
//! own pipe I/O (confirmed empirically — extra captured events with sizes
//! never requested by the scripted workload). Pointer-identity matching is
//! the only reliable way to isolate "did the workload's own operations get
//! captured correctly" from that ambient, expected noise.'''),
    ...para('//',
        r'The doc comment is blunt about the trap it avoids: "A gate that only checked ‘the process ran without crashing’ would pass with a silently broken capture path." So the test does not count events. It cannot, and the comment explains why: hooking the Rtl heap functions captures "every call to those functions process-wide, including Windows’ own internal heap traffic triggered as a side effect of the writer thread’s own pipe I/O (confirmed empirically — extra captured events with sizes never requested by the scripted workload)". The hook sees its own plumbing. A global count would be brittle noise.'),
    blank,
    ...para('//',
        r'The solution is identity. The harness prints every operation it performs with its exact pointer, and the test matches daemon-side events against those pointers. Extra events are ignored, the scripted ones must all be present, and nothing from after detach may appear.'),
    blank,
    ...sec(r'the contract with the harness'),
    ...code('rust', r'crates/heaplens-daemon/tests/hook_self_load_wire.rs · lines 36-54', r'''
// Must match crates/heaplens-hook/examples/self_load_harness.rs exactly.
const ALLOC_COUNT: usize = 50;
const REALLOC_COUNT: usize = 10;
const UNTRACKED_REALLOC_COUNT: usize = 1;
const EXPECTED_DEALLOC_COUNT: usize = ALLOC_COUNT + UNTRACKED_REALLOC_COUNT;

#[derive(Default, Debug)]
struct Expected {
    /// ptr -> size, for the 50 direct allocations.
    allocs: std::collections::HashMap<u64, u64>,
    /// (old_ptr, new_ptr, size) for the 10 tracked + 1 untracked reallocs.
    reallocs: Vec<(u64, u64, u64)>,
    /// The exact pointers freed, in order (51 total).
    frees: Vec<u64>,
    /// Pointers used by the post-detach workload (5 allocs + 5 frees) —
    /// must NEVER appear in any captured event; their presence would prove
    /// hooks were not actually removed by detach.
    post_detach_ptrs: std::collections::HashSet<u64>,
}'''),
    ...para('//',
        r'The constants say "Must match crates/heaplens-hook/examples/self_load_harness.rs exactly". The workload is 50 allocations (sizes cycling through 32, 64, 128 and 256 bytes), 10 reallocations of tracked pointers, one reallocation of a pointer allocated before the DLL was loaded, and 51 frees. After the frees the harness detaches and performs 5 more allocations and frees that must not be captured. The expected-state struct mirrors it: a map of pointer to size for allocations, a list of (old, new, size) for reallocs, the freed pointers, and a set of post-detach pointers.'),
    blank,
    ...para('//',
        r'The untracked realloc is not a throwaway. A pointer that predates the hook’s installation is unknown to the graph, so its realloc exercises the daemon’s realloc-of-unknown-pointer path (the harness’s comment and the test’s assertion message cite docs §1.4 and Graph::on_realloc). The count of expected frees is 51 because the pre-attach pointer, now reallocated, is freed too.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/hook_self_load_wire.rs · lines 62-98', r'''
fn parse_expected(stdout: &str) -> Expected {
    let mut e = Expected::default();
    for line in stdout.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        match parts.as_slice() {
            ["ALLOC", ptr, size] => {
                let ptr = parse_hex_ptr(ptr.trim_start_matches("ptr="));
                let size: u64 = size.trim_start_matches("size=").parse().unwrap();
                e.allocs.insert(ptr, size);
            }
            ["REALLOC", old, new, size] => {
                let old = parse_hex_ptr(old.trim_start_matches("old="));
                let new = parse_hex_ptr(new.trim_start_matches("new="));
                let size: u64 = size.trim_start_matches("size=").parse().unwrap();
                e.reallocs.push((old, new, size));
            }
            ["REALLOC_UNTRACKED", old, new, size] => {
                let old = parse_hex_ptr(old.trim_start_matches("old="));
                let new = parse_hex_ptr(new.trim_start_matches("new="));
                let size: u64 = size.trim_start_matches("size=").parse().unwrap();
                e.reallocs.push((old, new, size));
            }
            ["FREE", ptr] => {
                let ptr = parse_hex_ptr(ptr.trim_start_matches("ptr="));
                e.frees.push(ptr);
            }
            ["POST_DETACH_ALLOC", ptr, _size] => {
                e.post_detach_ptrs.insert(parse_hex_ptr(ptr.trim_start_matches("ptr=")));
            }
            ["POST_DETACH_FREE", ptr] => {
                e.post_detach_ptrs.insert(parse_hex_ptr(ptr.trim_start_matches("ptr=")));
            }
            _ => {}
        }
    }
    e
}'''),
    ...para('//',
        r'parse_expected reads the harness’s stdout line by line, splitting on whitespace and matching on the tag: ALLOC ptr=… size=…, REALLOC old=… new=… size=…, REALLOC_UNTRACKED, FREE ptr=…, and the post-detach pair. Pointers come from {:?} on a raw pointer, so they are 0x-prefixed hex, parsed back to u64. Any line that does not match is ignored, which lets the harness print anything else.'),
    blank,
    ...sec(r'the pipeline: a collector, not a graph'),
    ...code('rust', r'crates/heaplens-daemon/tests/hook_self_load_wire.rs · lines 164-202', r'''
    // Expected sets are filled in once the child's stdout is fully read,
    // after it exits — but the graph task needs them to filter incoming
    // events. Use a channel: the graph task starts collecting immediately
    // (untouched by "expected" until it arrives) and re-evaluates once the
    // expected set is known. Simpler: buffer all raw events first, process
    // against `Expected` after the child exits and stdout is parsed.
    let raw_events: Arc<Mutex<Vec<heaplens_protocol::AllocEvent>>> = Arc::new(Mutex::new(Vec::new()));
    let raw_events_for_graph = raw_events.clone();
    let graph_handle = tokio::spawn(async move {
        let mut resolver = Resolver::new();
        let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
        loop {
            let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
            if remaining.is_zero() {
                break;
            }
            tokio::select! {
                msg = rx.recv() => match msg {
                    Some(GraphMsg::Symbols(syms)) => {
                        for (addr, name, is_machinery) in syms {
                            resolver.insert(addr, name, is_machinery);
                        }
                    }
                    Some(GraphMsg::Events(events)) => {
                        raw_events_for_graph.lock().unwrap().extend(events);
                    }
                    Some(GraphMsg::TargetConnected { .. }) | Some(GraphMsg::TargetDisconnected { .. }) => {}
                    // No Tick producer runs in this test, but matched
                    // explicitly rather than folded into the wildcard below
                    // — see cross_process_wire.rs's identical comment for
                    // why (this is the same bug class that broke both files
                    // when GraphMsg grew two new variants).
                    Some(GraphMsg::Tick) => {}
                    None => break,
                },
                _ = tokio::time::sleep(remaining) => break,
            }
        }
    });'''),
    ...para('//',
        r'The graph task here does not use the graph. It stores every raw event in a shared vector and applies symbols to a resolver. The comment shows the reasoning: the expected sets are only known once the child’s stdout has been fully read, after it exits, but events arrive while it runs. Rather than a channel to deliver the expectations to the collector, the test buffers everything and replays afterwards. The loop still treats Tick, TargetConnected and TargetDisconnected explicitly, with a comment pointing at cross_process_wire.rs for the bug class (a wildcard arm that turned new GraphMsg variants into a loop exit).'),
    blank,
    ...para('//',
        r'The harness is spawned with its stdout piped. A blocking helper polls try_wait for up to 15 seconds, kills on timeout, and then reads all of stdout, and the test asserts exit success and a completion marker, "self_load_harness: done". The marker matters because a crash after partial output would otherwise leave a plausible-looking transcript.'),
    blank,
    ...para('//',
        r'Before matching, the test checks the transcript itself: 50 ALLOC lines, 11 REALLOC lines, 51 FREE lines and 5 post-detach pointers. If the harness changes without the constants, that fails with a message saying the harness printed the wrong count, which is the right place for the blame.'),
    blank,
    ...sec(r'the post-detach check'),
    ...code('rust', r'crates/heaplens-daemon/tests/hook_self_load_wire.rs · lines 249-251', r'''
    // Drain window for the post-detach workload (must produce zero events).
    tokio::time::sleep(Duration::from_secs(2)).await;
    ingest_handle.abort();'''),
    ...para('//',
        r'A two-second drain follows, during which the post-detach workload runs "and must produce zero events". Then the matching:'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/hook_self_load_wire.rs · lines 270-291', r'''
    // The post-detach workload's pointers can coincidentally equal a
    // pre-detach pointer (Windows' heap allocator readily reuses a
    // just-freed block for the next similarly-sized request) — a pointer
    // *value* match alone doesn't prove a leak. What matters is whether any
    // event *after* the pre-detach workload finished touches one of those
    // pointers. Find the last event index that matches any pre-detach
    // pointer; only events after it are eligible to count as leaks.
    let last_pre_detach_index = events
        .iter()
        .enumerate()
        .filter(|(_, ev)| match ev.kind {
            0 => expected.allocs.contains_key(&ev.ptr),
            1 => expected_frees.contains(&ev.ptr),
            2 => expected_realloc_pairs.contains(&(ev.old_ptr, ev.ptr)),
            _ => false,
        })
        .map(|(i, _)| i)
        .max();

    for (i, ev) in events.iter().enumerate() {
        s.total_events_seen += 1;
        let eligible_for_leak_check = last_pre_detach_index.is_none_or(|last| i > last);'''),
    ...para('//',
        r'This is the subtle part. The heap allocator readily reuses a just-freed block for the next request of similar size, so a post-detach pointer can have the same value as a pre-detach pointer. A pointer match alone proves nothing. The test therefore finds the index of the last event that matches any pre-detach pointer and only considers events after that index eligible as leaks. The idea is sound for the main case. It has a hole worth stating: a captured post-detach event whose pointer happens to equal a pre-detach pointer is itself a "pre-detach match", so it moves last_pre_detach_index forward past itself and escapes the check. The check detects leaks of pointers that are new values, not leaks whose address was reused. It is a one-sided guarantee, and the reuse the comment describes is exactly the case where it is weakest.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/hook_self_load_wire.rs · lines 292-313', r'''
        match ev.kind {
            0 => {
                graph.on_alloc(ev, &resolver);
                if let Some(&expected_size) = expected.allocs.get(&ev.ptr) {
                    s.matched_allocs.insert(ev.ptr);
                    if ev.size != expected_size {
                        s.alloc_size_mismatches.push((ev.ptr, expected_size, ev.size));
                    }
                }
                if eligible_for_leak_check && expected.post_detach_ptrs.contains(&ev.ptr) {
                    s.post_detach_leaks.push(ev.ptr);
                }
            }
            1 => {
                graph.on_dealloc(ev.ptr, ev.ts_nanos);
                if expected_frees.contains(&ev.ptr) {
                    s.matched_frees.insert(ev.ptr);
                }
                if eligible_for_leak_check && expected.post_detach_ptrs.contains(&ev.ptr) {
                    s.post_detach_leaks.push(ev.ptr);
                }
            }'''),
    ...para('//',
        r'For each event the test replays it into an OwnershipGraph, records matches (allocs by pointer, with size comparison; frees by pointer; reallocs by (old, new) pair), and records leaks after the cut-off.'),
    blank,
    ...sec(r'the assertions'),
    ...code('rust', r'crates/heaplens-daemon/tests/hook_self_load_wire.rs · lines 336-370', r'''
    // Exact matches against the harness's own known-good pointers — not
    // just "at least," and not a brittle global total (see module doc).
    assert_eq!(
        s.matched_allocs.len(), ALLOC_COUNT,
        "expected all {ALLOC_COUNT} scripted allocations to be captured by pointer identity, \
         matched {} of {}", s.matched_allocs.len(), expected.allocs.len()
    );
    assert!(
        s.alloc_size_mismatches.is_empty(),
        "captured alloc events with wrong size for a known pointer: {:?}",
        s.alloc_size_mismatches
    );
    assert_eq!(
        s.matched_reallocs.len(), REALLOC_COUNT + UNTRACKED_REALLOC_COUNT,
        "expected all {} scripted reallocs (including the untracked pre-attach-pointer one, \
         §1.4) to be captured by (old_ptr, new_ptr) identity, matched {}",
        REALLOC_COUNT + UNTRACKED_REALLOC_COUNT, s.matched_reallocs.len()
    );
    assert_eq!(
        s.matched_frees.len(), EXPECTED_DEALLOC_COUNT,
        "expected all {EXPECTED_DEALLOC_COUNT} scripted frees to be captured by pointer \
         identity, matched {}", s.matched_frees.len()
    );

    // Positive proof that detach actually removed the hooks: none of the
    // post-detach workload's own pointers were captured as any kind of
    // event. This does not depend on coincidental pointer non-reuse (the
    // way an "absence from the pre-detach sets" check would) — these
    // pointers are checked explicitly, by their own dedicated marker.
    assert!(
        s.post_detach_leaks.is_empty(),
        "captured event(s) touching a post-detach pointer — hooks were not fully removed by \
         detach: {:?}",
        s.post_detach_leaks
    );'''),
    ...para('//',
        r'All exact: 50 of 50 allocations matched by pointer, no size mismatches, 11 of 11 reallocs matched by the (old, new) pair, 51 of 51 frees matched, no leaks. Equality, not "at least": the comment says "not just ‘at least,’ and not a brittle global total".'),
    blank,
    ...sec(r'a flaw I noticed'),
    ...para('//',
        r'The size check at lines 295-299 compares every alloc event for an expected pointer against the expected size. The sibling test, hook_self_load_spawned_thread.rs, found that this is unsound and fixed it in commit 084ddf9: the harness’s own println! calls make heap allocations that the hook faithfully captures, and an address can be used by one of those incidental allocations (size 30, say) before the harness’s scripted allocation (size 32) gets it. Comparing the first, or here every, event for that pointer then reports a false mismatch. The fix, comparing the last alloc event per pointer, lives in that file’s find_alloc_size_mismatches and was not applied here. So this test may carry the same latent flake as the one that was fixed; I have not seen it fail.'),
    blank,
    ...sec(r'what this test cannot see'),
    ...pt('//', r'Cross-thread behaviour',
        r'the whole workload is on the main thread, the one that called LoadLibraryW. That gap is the reason hook_self_load_spawned_thread.rs exists: the hook’s crash was specific to other threads.'),
    ...pt('//', r'Real injection',
        r'the DLL is loaded by the harness itself, not by heaplens-injector. in the daemon tests directory, the hook_owner_free_no_crash tests are the ones that run the real injector.'),
    ...pt('//', r'φ',
        r'events are replayed into a graph but the graph’s output is never asserted.'),
    ...sec(r'history'),
    ...pt('//', r'b3a22c2 (2026-07-13)',
        r'born with the hook crate: "heaplens-hook capture DLL, self-load acceptance gate".'),
    ...pt('//', r'724695a (2026-07-19)',
        r'replaced wholesale with the stage7-injection branch’s version. The commit message says the copy on the UI branch predated the ported lib.rs and "captured zero events against it".'),
    ...pt('//', r'cd348b6 (2026-07-21)',
        r'"reconcile two files the master merge broke without conflict markers": a two-line fix in this file.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/tests/hook_self_load_wire.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/tests/hook_self_load_wire.rs'),
  ],
);
