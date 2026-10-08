import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/tests/ring_integration.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'ring_integration.rs — an event must outlive the thread that made it'),
    cm('//', r'one test, and a sleep that turns out not to matter'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'integration test: a dead thread’s ring is still drainable'),
    kv('language', r'Rust integration test'),
    kv('size', r'28 lines, 1 test'),
    kv('history', r'de6f6a5 (2026-07-01), then small edits in ba1a066, 43fc22e and fa3fe78'),
    kv('exercises', r'ring::push, ring::drain_all, guard::force_enter_permanent'),
    ...sec(r'the property'),
    ...para('//',
        r'A thread that allocates gets its own ring, and when that thread '
        r'exits its ring must not vanish with it. The events it produced '
        r'in its last moments, perhaps the most interesting ones if the '
        r'thread died holding a leak, still have to reach the writer. '
        r'ring.rs arranges that by keeping two strong references to every '
        r'ring: one in the registry and one in the thread’s own slot. When '
        r'the thread exits, only the second is released. This test checks '
        r'the observable result.'),
    ...sec(r'the test'),
    ...code('rust', 'crates/heaplens-alloc/tests/ring_integration.rs · thread_ring_drainable_after_exit', r'''
use heaplens_alloc::ring;
use heaplens_protocol::{AllocEvent, EventKind};

fn ev(n: u64) -> AllocEvent {
    AllocEvent::new(EventKind::Alloc, n, 0, 64, 8, n, [0u64; 16], 0)
}

#[test]
fn thread_ring_drainable_after_exit() {
    let handle = std::thread::spawn(|| {
        ring::push(ev(0xBEEF_CAFE));
    });
    handle.join().unwrap();

    std::thread::sleep(std::time::Duration::from_millis(20));

    // drain_all requires the recursion guard to be permanently set on the
    // calling thread (writer-thread invariant §12.4).
    heaplens_alloc::guard::force_enter_permanent();

    let mut found = false;
    ring::drain_all(usize::MAX, |e| {
        if e.ptr == 0xBEEF_CAFE {
            found = true;
        }
    });
    assert!(found, "event from exited thread must remain drainable");
}'''),
    ...para('//',
        r'A spawned thread pushes one recognisable event, with ptr '
        r'0xBEEF_CAFE, through the public ring::push. That call goes '
        r'through the same path a real allocation takes: it finds the '
        r'current thread’s ring in thread-local storage, creating and '
        r'registering one on first use. The thread then exits and is '
        r'joined. The test pauses 20 ms, sets the recursion guard '
        r'permanently on its own thread, calls drain_all with a cap of '
        r'usize::MAX, and asserts that the event turns up.'),
    blank,
    ...para('//',
        r'Two details are worth reading closely.'),
    blank,
    ...para('//',
        r'The drain call needs force_enter_permanent first. drain_all '
        r'contains a debug_assert that the calling thread has the guard '
        r'set, because the function is documented as writer-thread-only: '
        r'"drain_all must be called only from a thread where the recursion '
        r'guard is permanently set (writer thread)". Commit ba1a066 added '
        r'that assert and, in the same commit, added the '
        r'force_enter_permanent line to this test. The test therefore '
        r'plays the role of the writer thread, with the same precondition.'),
    blank,
    ...para('//',
        r'usize::MAX is the cap argument that fa3fe78 introduced when '
        r'drain_all became capped. Using the largest possible value means '
        r'"no practical limit", so the call behaves like the old unbounded '
        r'drain, which is what the test wants. The diff to this file in '
        r'that commit is that one argument.'),
    ...sec(r'the sleep is not load-bearing'),
    ...para('//',
        r'The 20 ms pause has no comment of its own; its purpose is to let '
        r'the thread’s exit callback run and mark the producer dead. The '
        r'sibling unit test in ring.rs says so in words: "Give TLS '
        r'destructor time to run and mark producer_alive = false". Reading '
        r'drain_all, though, the assertion does not depend on it. The '
        r'function pops every available event from every registered ring '
        r'first, and only afterwards looks at producer_alive to decide '
        r'whether the ring can be removed. So the event is found whether '
        r'or not the callback has run yet. A copy of the test body without '
        r'the sleep, looped 200 times on Linux in a scratch crate, found '
        r'the event every time. What the sleep protects, if anything, is a '
        r'later cleanup that this test does not assert (that the dead ring '
        r'is removed from the registry). It reads as a leftover from the '
        r'first version, written when the thread_local! destructor’s '
        r'timing was a worry. It does no harm, and a 20 ms delay is cheap.'),
    blank,
    ...para('//',
        r'That is a case where a test comment and a test body drift apart. '
        r'It is worth noticing only because the test is a good '
        r'illustration of a general rule about asserting less than you '
        r'wait for.'),
    ...sec(r'what it covers on each platform'),
    ...para('//',
        r'On Linux, where it was run for this page (it passes in 0.02 s), '
        r'push goes through a plain thread_local! holding an Arc<Ring> '
        r'with a Drop impl. On Windows the same call goes through '
        r'FlsGetValue and FlsSetValue and the exit callback registered by '
        r'FlsAlloc, which makes this the cheapest place in the suite where '
        r'that code path runs, from a thread that really exits. It still '
        r'runs in a statically linked test binary, so it cannot reproduce '
        r'the injected-DLL situation that motivated FLS.'),
    blank,
    ...para('//',
        r'The test pushes a single event, so nothing here touches the '
        r'ring-full path or the cap. Those are in ring.rs’s unit tests '
        r'(full_ring_returns_false_and_increments_dropped, '
        r'drain_all_stops_at_the_cap_leaving_the_rest_for_next_call and '
        r'drain_all_cap_can_stop_mid_ring_across_multiple_producers).'),
    ...sec(r'one more thing the test shares with its neighbour'),
    ...para('//',
        r'Because the registry is a process-wide static, this test shares '
        r'it with any other test in the same binary. It is alone in its '
        r'binary, so there is no interference, which is why it needs none '
        r'of the REGISTRY_TEST_LOCK ceremony the unit tests in ring.rs had '
        r'to adopt once there were several of them. That is one quiet '
        r'advantage of keeping integration tests in separate files: each '
        r'file is its own process.'),
    ...sec(r'related'),
    ...pt('//',
        r'ring.rs',
        r'the structures under test and the two-reference trick.'),
    ...pt('//',
        r'multithread_stress.rs',
        r'the same registry under eight producers.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/tests/ring_integration.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/tests/ring_integration.rs'),
  ],
);
