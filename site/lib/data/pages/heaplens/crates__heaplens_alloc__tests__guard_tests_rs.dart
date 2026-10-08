import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/tests/guard_tests.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'guard_tests.rs — the recursion guard, tested from the outside'),
    cm('//', r'three tests that repeat the unit tests through the public path'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'integration tests for guard.rs’s public surface'),
    kv('language', r'Rust integration test (a separate crate that depends on '
              r'heaplens-alloc)'),
    kv('size', r'38 lines, 3 tests, one commit (de6f6a5, 2026-07-01) and never edited'),
    kv('exercises', r'heaplens_alloc::guard::{is_set, ScopedGuard, force_enter_permanent}'),
    ...sec(r'what is different about an integration test'),
    ...para('//',
        r'Rust compiles the files in tests/ as separate crates. They can '
        r'reach only what the library exposes publicly. This file imports '
        r'guard’s functions by their public path, use '
        r'heaplens_alloc::guard::{force_enter_permanent, is_set, '
        r'ScopedGuard}, which is a check that lib.rs really does export '
        r'the module. It is marked #[doc(hidden)] pub mod guard, a '
        r'slightly odd combination that exists so that the hook DLL, the '
        r'injector tests and these integration tests can reach internals '
        r'that are not part of the library’s documented API.'),
    blank,
    ...para('//',
        r'The three tests are the same three that guard.rs already has as '
        r'unit tests, rewritten to use the public names. That might look '
        r'redundant, and as new coverage it nearly is. What it adds is the '
        r'boundary check, and a second line of defence for the public '
        r'contract that two other crates (heaplens-hook and the ring '
        r'tests) depend on.'),
    ...sec(r'the tests'),
    ...code('rust', 'crates/heaplens-alloc/tests/guard_tests.rs · the whole file', r'''
use heaplens_alloc::guard::{force_enter_permanent, is_set, ScopedGuard};

#[test]
fn guard_basics_integration() {
    std::thread::spawn(|| {
        assert!(!is_set());
        let g = ScopedGuard::enter();
        assert!(is_set());
        drop(g);
        assert!(!is_set());
    })
    .join()
    .unwrap();
}

#[test]
fn guard_panic_safe_integration() {
    std::thread::spawn(|| {
        let _ = std::panic::catch_unwind(|| {
            let _g = ScopedGuard::enter();
            panic!("intentional");
        });
        assert!(!is_set());
    })
    .join()
    .unwrap();
}

#[test]
fn force_enter_permanent_integration() {
    std::thread::spawn(|| {
        assert!(!is_set());
        force_enter_permanent();
        assert!(is_set());
    })
    .join()
    .unwrap();
}'''),
    ...para('//',
        r'Each test runs in a freshly spawned thread and joins it with '
        r'.join().unwrap(), so assertion failures inside the thread '
        r'propagate to the test result. That structure is not decoration. '
        r'The flag is per thread, so a test that set it on the thread it '
        r'happens to run on could leave it set for whatever runs next '
        r'there. Spawning a thread inside the test sidesteps the question '
        r'and gives each test a clean slate; the unit tests in guard.rs '
        r'say the same: "Spawn to get a fresh TLS slot uncontaminated by '
        r'other tests".'),
    blank,
    ...para('//',
        r'guard_basics_integration walks the happy path: the flag starts '
        r'clear, ScopedGuard::enter sets it, and dropping the guard clears '
        r'it. guard_panic_safe_integration is the one with a purpose: it '
        r'enters the guard inside catch_unwind, panics on purpose, and '
        r'then asserts that the flag is clear afterwards. That is the '
        r'claim in the type’s doc comment, that Drop runs during '
        r'unwinding, tested through the public path. The third, '
        r'force_enter_permanent_integration, covers the call the writer '
        r'thread makes at startup and checks the flag is set afterwards; '
        r'unlike the other two it never clears it, because "permanent" is '
        r'the point. The thread is thrown away, which is also why it '
        r'cannot leak into another test.'),
    ...sec(r'what these tests cannot see'),
    ...para('//',
        r'They run in a test binary that is linked statically. That is '
        r'exactly the situation in which the old thread_local! '
        r'implementation worked perfectly, and so they could never have '
        r'caught the 2026-07-21 crash: the crash needed a DLL loaded with '
        r'LoadLibraryW and a second thread touching the flag. The page for '
        r'guard.rs explains how that bug was found and where it is covered '
        r'(the hook crate’s self-load harnesses and the daemon’s hook_* '
        r'tests). On Linux, where they were run for this page, they test '
        r'the fallback implementation; on Windows they exercise the '
        r'TlsAlloc path, but still only in the friendly, statically linked '
        r'configuration.'),
    blank,
    ...para('//',
        r'Nothing here tests ScopedGuard’s debug_assert (calling enter() '
        r'on an already-guarded thread panics in debug builds). That check '
        r'was added later, in commit ba1a066, and no test provokes it.'),
    ...sec(r'why keep them'),
    ...para('//',
        r'A reasonable reader would ask whether three duplicate tests are '
        r'worth a file. Reasons visible in the repository: they cost '
        r'almost nothing, they check the visibility of the module, and '
        r'they were committed in the same change that introduced the other '
        r'integration tests and the smoke example (de6f6a5, "integration '
        r'tests + alloc_smoke example"), as part of the Build Spec’s test '
        r'plan for this crate: "guard correctness (writer-thread '
        r'allocations never recorded)". The last part of that sentence, '
        r'the writer thread’s allocations never being recorded, is not '
        r'what these tests check. They check the flag; the claim about the '
        r'writer is tested only indirectly, by the examples producing '
        r'sensible graphs.'),
    ...sec(r'related'),
    ...pt('//',
        r'guard.rs',
        r'the implementation and the story of its rewrite.'),
    ...pt('//',
        r'ring_integration.rs',
        r'the other integration test that needs the guard set.'),
    ...pt('//',
        r'multithread_stress.rs',
        r'the test that puts the guard under concurrent load.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/tests/guard_tests.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/tests/guard_tests.rs'),
  ],
);
