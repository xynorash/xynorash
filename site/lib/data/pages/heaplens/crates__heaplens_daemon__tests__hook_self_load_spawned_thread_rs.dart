import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/tests/hook_self_load_spawned_thread.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'hook_self_load_spawned_thread.rs — the regression test for the crash on every other thread'),
    cm('//', r'the hook worked on the thread that loaded it and segfaulted on all the rest'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'targeted regression test for the 2026-07-21 thread_local! crash in heaplens-hook'),
    kv('language', r'Rust, tokio multi-thread runtime, Windows only (#![cfg(windows)]); includes its own unit tests'),
    kv('size', r'364 lines, 1 integration test and 5 unit tests, three commits (dcc76f2 2026-07-21, a7438d6 2026-07-21, 084ddf9 2026-07-26)'),
    kv('exercises', r'heaplens_hook.dll via self_load_spawned_thread.exe, ingest::run, find_alloc_size_mismatches'),
    kv('related', r'hook_self_load_wire.rs (the original gate), self_load_concurrency_stress.rs (the broader stress tool)'),
    ...sec(r'the bug it guards'),
    ...para('//',
        r'heaplens-hook is always loaded with LoadLibraryW at runtime, never linked at process start. The commit that fixed the crash (dcc76f2, "eliminate hook-path crash — replace thread_local! with raw TlsAlloc/FlsAlloc") describes the mechanism it reduced to: the reentrancy guard and the per-thread ring registry both used Rust’s thread_local!, and a single hooked allocation on the thread that called LoadLibraryW always succeeded, while the identical allocation on any other thread, even one spawned long after attach, segfaulted on its first access, every run. The commit message records that the first attempted fix (giving the value type a Drop impl) did not work, which ruled that theory out. The fix bypasses thread_local! on Windows in favour of raw TlsAlloc for the guard and FlsAlloc with an explicit shutdown before unload for the ring registry.'),
    blank,
    ...para('//',
        r'The reason it went uncaught is in this file’s opening comment: hook_self_load_wire.rs, the Step 1 gate, ran its whole workload on the main thread, "the same thread that calls LoadLibraryW". A test can only guard what it exercises. This one runs the whole scripted workload on a spawned thread and leaves the main thread to attach, spawn, join and detach.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/hook_self_load_spawned_thread.rs · lines 2-26', r'''
//! Targeted regression test for the 2026-07-21 root-cause investigation.
//!
//! `hook_self_load_wire.rs` (the original Step 1 acceptance gate) never
//! actually exercised a spawned thread's allocations under the hook — its
//! entire scripted workload runs on the process's main thread, the same
//! thread that calls `LoadLibraryW`. That gap is exactly why the bug this
//! test guards against went uncaught until a dedicated concurrency stress
//! harness (`self_load_concurrency_stress.rs`) went looking for it:
//! `heaplens-hook` is always loaded via `LoadLibraryW` at runtime, and its
//! reentrancy guard (a `thread_local!`) and ring registry (also, until the
//! fix, a `thread_local!`) both crashed reliably on the very first hooked
//! allocation from any thread *other than* the one that loaded the DLL —
//! see `guard.rs`/`ring.rs`'s doc comments for the confirmed mechanism and
//! fix (raw `TlsAlloc` for the guard, `FlsAlloc` + explicit pre-unload
//! `shutdown` for the ring registry).
//!
//! This test runs `self_load_spawned_thread.rs` (which does its entire
//! scripted workload on a spawned thread, never main) against a real
//! daemon and asserts *exact* event counts by pointer identity — not just
//! "the process didn't crash," though that alone is most of what this test
//! exists to catch. A gate that only checked exit status would still be a
//! real regression test for this specific bug (it crashed the whole
//! process), but exact pointer-identity matching additionally confirms the
//! *content* wired through correctly for a spawned-thread producer, not
//! just that nothing crashed.'''),
    ...sec(r'what the test asserts'),
    ...para('//',
        r'Two levels, described by the comment as "most of what this test exists to catch" and then more.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/hook_self_load_spawned_thread.rs · lines 261-299', r'''
    // Wait for the harness to exit. This is the core regression assertion:
    // before the fix, this process segfaulted (non-success exit) reliably
    // on the very first allocation from the spawned thread.
    let exit_result =
        tokio::task::spawn_blocking(move || -> std::io::Result<(Option<std::process::ExitStatus>, String)> {
            let deadline = std::time::Instant::now() + Duration::from_secs(15);
            let status = loop {
                match child.try_wait()? {
                    Some(status) => break Some(status),
                    None => {
                        if std::time::Instant::now() >= deadline {
                            let _ = child.kill();
                            break None;
                        }
                        std::thread::sleep(Duration::from_millis(100));
                    }
                }
            };
            let mut out = String::new();
            child_stdout.read_to_string(&mut out)?;
            Ok((status, out))
        })
        .await
        .expect("spawn_blocking panicked");

    let (status, stdout) = exit_result.expect("wait/read error");
    match status {
        Some(status) => assert!(
            status.success(),
            "self_load_spawned_thread exited with non-zero/abnormal status: {status} — \
             this is exactly the failure mode of the bug this test guards against \
             (a segfault on the spawned thread's first hooked allocation)"
        ),
        None => panic!("self_load_spawned_thread did not exit within 15s"),
    }
    assert!(
        stdout.contains("self_load_spawned_thread: done"),
        "harness stdout missing completion marker — output:\n{stdout}"
    );'''),
    ...para('//',
        r'1. The process exits with success. Before the fix this target segfaulted at the first hooked allocation on the spawned thread, so a non-zero exit is the failure signature, and the assertion message says so: "exactly the failure mode of the bug this test guards against". The 15-second kill timer turns a hang into a failure instead of a stuck suite. A completion marker "self_load_spawned_thread: done" is required too. 2. The content got through. The harness prints ALLOC and FREE lines for its 20 allocations, and the daemon side must have captured all 20 allocs and all 20 frees by pointer identity, with correct sizes.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/hook_self_load_spawned_thread.rs · lines 315-363', r'''
    let mut graph = OwnershipGraph::new();
    let resolver = Resolver::new();
    let events = raw_events.lock().unwrap();
    let mut s = Summary::default();
    let expected_frees: std::collections::HashSet<u64> = expected.frees.iter().copied().collect();

    for ev in events.iter() {
        s.total_events_seen += 1;
        match ev.kind {
            0 => {
                graph.on_alloc(ev, &resolver);
                if expected.allocs.contains_key(&ev.ptr) {
                    s.matched_allocs.insert(ev.ptr);
                }
            }
            1 => {
                graph.on_dealloc(ev.ptr, ev.ts_nanos);
                if expected_frees.contains(&ev.ptr) {
                    s.matched_frees.insert(ev.ptr);
                }
            }
            _ => {}
        }
    }
    s.alloc_size_mismatches = find_alloc_size_mismatches(&events, &expected.allocs);

    *summary_for_graph.lock().unwrap() = s;
    let s = summary.lock().unwrap();
    eprintln!(
        "hook_self_load_spawned_thread summary: matched_allocs={} matched_frees={} \
         total_events_seen={} size_mismatches={:?}",
        s.matched_allocs.len(), s.matched_frees.len(), s.total_events_seen, s.alloc_size_mismatches
    );

    assert_eq!(
        s.matched_allocs.len(), ALLOC_COUNT,
        "expected all {ALLOC_COUNT} spawned-thread allocations to be captured by pointer \
         identity, matched {} of {}", s.matched_allocs.len(), expected.allocs.len()
    );
    assert!(
        s.alloc_size_mismatches.is_empty(),
        "captured alloc events with wrong size for a known pointer: {:?}",
        s.alloc_size_mismatches
    );
    assert_eq!(
        s.matched_frees.len(), ALLOC_COUNT,
        "expected all {ALLOC_COUNT} spawned-thread frees to be captured by pointer identity, \
         matched {}", s.matched_frees.len()
    );'''),
    ...para('//',
        r'The matching code is a simpler cousin of the one in hook_self_load_wire.rs: replay raw events into a graph, collect matched pointers, compute size mismatches. There is no realloc workload, no untracked pointer and no post-detach phase, since those concerns belong to the other test. The test is "deliberately small and fast", in the harness’s words.'),
    blank,
    ...sec(r'the flake, and its fix'),
    ...para('//',
        r'The most instructive part of the file is not the integration test but the helper above it.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/hook_self_load_spawned_thread.rs · lines 100-139', r'''
/// For each `(ptr, size)` in `expected`, checks the *last* `kind == 0`
/// (alloc) event captured for that ptr against `expected`'s size — not the
/// first.
///
/// Comparing the first occurrence (this function's predecessor) is unsound:
/// the harness's own `println!` calls after every real `alloc_n`/`free_n`
/// make real `HeapAlloc`/`HeapFree` calls of their own (stdout's internal
/// buffering), which the same active hook faithfully captures too. The
/// allocator can legitimately reuse an address for one of these incidental,
/// short-lived allocations *before* handing that same address out for the
/// harness's own real scripted allocation later in the run — confirmed via
/// direct event-log instrumentation during the 2026-07-26 flake
/// investigation: address `0x27ff25f61f0` was genuinely alloc'd (size 30)
/// and freed by stdout's own buffering, then alloc'd for real (size 32) by
/// the harness, strictly in that order, both captured correctly. Matching
/// the first occurrence for that ptr picks up the unrelated incidental
/// allocation instead of the real one and reports a false size mismatch.
/// The *last* alloc event for a ptr is always the one still live when its
/// matching free (tracked separately, by `expected_frees`) occurs, so it's
/// the one that actually corresponds to what the harness scripted.
fn find_alloc_size_mismatches(
    events: &[heaplens_protocol::AllocEvent],
    expected: &std::collections::HashMap<u64, u64>,
) -> Vec<(u64, u64, u64)> {
    let mut last_alloc_size: std::collections::HashMap<u64, u64> = std::collections::HashMap::new();
    for ev in events {
        if ev.kind == 0 && expected.contains_key(&ev.ptr) {
            last_alloc_size.insert(ev.ptr, ev.size);
        }
    }
    let mut mismatches: Vec<(u64, u64, u64)> = expected
        .iter()
        .filter_map(|(&ptr, &expected_size)| {
            let actual = *last_alloc_size.get(&ptr)?;
            (actual != expected_size).then_some((ptr, expected_size, actual))
        })
        .collect();
    mismatches.sort();
    mismatches
}'''),
    ...para('//',
        r'find_alloc_size_mismatches compares the last alloc event for each expected pointer against the expected size. Its doc comment tells the story of the flake: the harness’s println! calls after each real allocation call HeapAlloc and HeapFree themselves, through stdout’s internal buffering, and the hook captures those too. The allocator may give an address to such an incidental short-lived allocation before giving the same address to the scripted allocation. The comment has the evidence: address 0x27ff25f61f0 was allocated (size 30) and freed by stdout buffering, then allocated for real (size 32), strictly in that order, both captured correctly. Matching the first occurrence picks the unrelated allocation and reports a false size mismatch. "The last alloc event for a ptr is always the one still live when its matching free occurs."'),
    blank,
    ...sec(r'unit tests for the test helper'),
    ...code('rust', r'crates/heaplens-daemon/tests/hook_self_load_spawned_thread.rs · lines 155-183', r'''
    #[test]
    fn a_single_alloc_matching_expected_size_has_no_mismatch() {
        let events = vec![alloc_ev(0x100, 32, 1)];
        let expected = HashMap::from([(0x100, 32)]);
        assert_eq!(find_alloc_size_mismatches(&events, &expected), vec![]);
    }

    #[test]
    fn a_single_alloc_with_wrong_size_is_a_real_mismatch() {
        let events = vec![alloc_ev(0x100, 40, 1)];
        let expected = HashMap::from([(0x100, 32)]);
        assert_eq!(find_alloc_size_mismatches(&events, &expected), vec![(0x100, 32, 40)]);
    }

    /// The exact confirmed scenario: an incidental alloc+free (stdout
    /// buffering, size 30) reuses an address before the harness's own real
    /// scripted alloc (size 32) claims it. Must not report a mismatch —
    /// the *last* alloc event (32) is the one that matters.
    #[test]
    fn address_reused_by_an_incidental_alloc_before_the_real_one_is_not_a_mismatch() {
        let events = vec![
            alloc_ev(0x27ff25f61f0, 30, 100), // incidental (stdout buffering)
            free_ev(0x27ff25f61f0, 200),      // incidental freed
            alloc_ev(0x27ff25f61f0, 32, 300), // the harness's real alloc
            free_ev(0x27ff25f61f0, 400),      // the harness's real free
        ];
        let expected = HashMap::from([(0x27ff25f61f0, 32)]);
        assert_eq!(find_alloc_size_mismatches(&events, &expected), vec![]);
    }'''),
    ...para('//',
        r'A test file with unit tests for its own helper is unusual, and it is what the commit 084ddf9 did: it extracted the function "and added 5 unit tests, including one reproducing the exact confirmed scenario". They sit in a #[cfg(test)] mod. Their names are sentences: a single matching alloc has no mismatch, a single alloc of the wrong size is a real mismatch, an address reused by an incidental alloc before the real one is not a mismatch, a pointer never allocated is absent not a mismatch, and events for untracked pointers are ignored. The third uses the real address and sizes from the investigation. Together they pin both directions: the fix removes the false positive and the second test makes sure it did not remove real detection.'),
    blank,
    ...para('//',
        r'They live in an integration-test crate marked #![cfg(windows)], so they run only on Windows too, even though they do not touch the OS.'),
    blank,
    ...sec(r'edge cases and design decisions'),
    ...para('//',
        r'· Spawned thread only. Attach happens on the main thread, "same as every other self-load harness" in the example’s own comment; only the workload moves. The test does not vary the number of threads; self_load_concurrency_stress.rs does.'),
    ...para('//',
        r'· The sleep-based drain. After the child exits, the test sleeps one second, then aborts ingest. The one second is a fixed margin for the last batch.'),
    ...para('//',
        r'· Exact count assertions on a noisy stream. The pointer matching makes exact counts safe; the unit-tested helper makes the size check safe.'),
    ...para('//',
        r'· Pipe name shared with the daemon and with the other wire tests.'),
    ...sec(r'what it proves about the whole system'),
    ...para('//',
        r'Taken with hook_self_load_wire.rs, the pair says two things: a hook loaded with LoadLibraryW captures exactly the allocations a scripted workload performs when they happen on the loading thread, and it does the same when they happen on a different thread. Without the second, "works on my machine" would have meant "works on the one thread I tried".'),
    blank,
    ...sec(r'history'),
    ...pt('//', r'dcc76f2 (2026-07-21)',
        r'created alongside the thread-local fix (guard.rs, ring.rs, the example and this test in one commit).'),
    ...pt('//', r'a7438d6 (2026-07-21)',
        r'merge repair: the on_dealloc call site updated for master’s two-argument signature.'),
    ...pt('//', r'084ddf9 (2026-07-26)',
        r'"fix hook_self_load_spawned_thread flake — match last alloc event per ptr, not first".'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/tests/hook_self_load_spawned_thread.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/tests/hook_self_load_spawned_thread.rs'),
  ],
);
