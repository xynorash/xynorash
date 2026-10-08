import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-hook/examples/owner_freed_while_children_live.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'owner_freed_while_children_live.rs — a repro for a theory that turned out to be wrong'),
    cm('//', r'the workload never crashed; the crash was in how the program ended, and this file is now the test for that'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'injection target that frees an owner while its children are live'),
    kv('language', r'Rust, std only; links neither heaplens-hook nor heaplens-alloc'),
    kv('size', r'113 lines'),
    kv('history', r'one commit, deff3ad (2026-07-26 03:11 +0300), brought from feat/stage7-injection'),
    kv('script', r'1 owner (96 B), 8 children (64 B), free owner, 20 rounds of churn, then free the rest'),
    kv('driven by', r'two tests in crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs'),
    ...sec(r'a crash with a suspect'),
    ...para('//',
        r'The story starts with an observation by the project’s author, '
        r'recorded in the header of the test file that drives this one: '
        r'a crash with exit status 0xC0000005, an access violation, seen '
        r'during real cross-process injection on what the notes call '
        r'"case 2", an owner freed while children remain live. (The '
        r'repository defines no other cases.) It is an attractive '
        r'suspect. The daemon’s ownership graph treats a freed owner '
        r'specially: its children become orphans. A bug in the hook that '
        r'was tied to that transition would explain why this particular '
        r'pattern crashed.'),
    blank,
    ...para('//',
        r'This file is the experiment built to test that suspect, and '
        r'its header says exactly what it is:'),
    ...code('rust', 'crates/heaplens-hook/examples/owner_freed_while_children_live.rs · the header', r'''
//! Stage 7 hook-crash repro target (docs/stage7-injection-design.md, hook
//! owner-free crash diagnosis). A plain, separate process — no dependency
//! on heaplens-hook or heaplens-alloc — built for real cross-process
//! injection via `heaplens-injector --attach`, mirroring
//! injection_target.rs's structure (TARGET_PID marker, sleep windows for
//! the driving script to attach/detach).
//!
//! Workload pattern ("case 2" as reconstructed): an owner allocation is
//! made first, then several children whose allocation call stack differs
//! from the owner's (so phi's ownership inference has something to link),
//! then the owner alone is freed while the children remain live — followed
//! by continued heap churn (realloc/alloc/free) so that any hook-side
//! reentrancy or bookkeeping bug tied to freeing an "owner" node while
//! children are still tracked gets more than one chance to fire.
//!
//! No fix is attempted here — this is a repro target only, driven under
//! the temporary diagnostic VEH added to heaplens-hook for this
//! investigation.'''),
    ...para('//',
        r'Read the second paragraph as a specification of the '
        r'workload. The program makes an owner allocation first, then '
        r'several children whose call stack differs from the owner’s, '
        r'"so that phi’s ownership inference has something to link". Then '
        r'it frees the owner alone while the children live, and keeps '
        r'churning, so that "any hook-side reentrancy or bookkeeping bug '
        r'tied to freeing an ‘owner’ node while children are still '
        r'tracked gets more than one chance to fire". The last '
        r'paragraph is a scoping decision: "No fix is attempted here '
        r'— this is a repro target only". It was to be driven "under the '
        r'temporary diagnostic VEH added to heaplens-hook for this '
        r'investigation", a vectored exception handler that would log '
        r'the fault if one occurred. That handler is not in the current '
        r'lib.rs. It was added, used and removed.'),
    ...sec(r'the script'),
    ...code('rust', 'crates/heaplens-hook/examples/owner_freed_while_children_live.rs · the owner and the children', r'''
#[inline(never)]
unsafe fn make_owner() -> *mut u8 {
    unsafe { alloc_n(96) }
}

#[inline(never)]
unsafe fn make_children() -> Vec<*mut u8> {
    (0..8).map(|_| unsafe { alloc_n(64) }).collect()
}'''),
    ...para('//',
        r'Two functions, both marked #[inline(never)]. My reading is '
        r'that the attribute is there for the ownership inference, not '
        r'for the hook. The '
        r'daemon attributes ownership at function-name granularity, '
        r'from the symbol names in the captured call stacks. If the '
        r'compiler inlined make_owner and make_children into main, the '
        r'two kinds of allocation would resolve to the same function '
        r'and could not be told apart. The same precaution appears in '
        r'the heaplens-alloc examples, where the workspace manifest '
        r'says "#[inline(never)] on the producer examples’ '
        r'allocation-site functions is still correct practice". The '
        r'owner is one block of 96 bytes. The children are eight blocks '
        r'of 64.'),
    ...code('rust', 'crates/heaplens-hook/examples/owner_freed_while_children_live.rs · the operation under test and the churn', r'''
    // ── Owner allocated first, so phi's ownership inference (which only
    // considers already-live nodes) can assign it as the children's
    // effective owner. ──────────────────────────────────────────────────
    let owner = unsafe { make_owner() };
    println!("ALLOC owner ptr={owner:?} size=96");

    let children = unsafe { make_children() };
    for c in &children {
        println!("ALLOC child ptr={c:?} size=64");
    }

    std::thread::sleep(Duration::from_millis(300));

    // ── The operation under test: free the owner while children remain
    // live. If there is a hook-side bug tied specifically to this
    // transition (as opposed to ordinary alloc/free traffic), this is
    // where it would fire. ──────────────────────────────────────────────
    unsafe { free_n(owner, 96) };
    println!("FREE owner ptr={owner:?}");

    // ── Continued churn after the owner-free, so a reentrancy/bookkeeping
    // bug gets repeated chances rather than just one. ───────────────────
    let mut churn_ptrs: Vec<(*mut u8, usize)> = Vec::new();
    for round in 0..20 {
        let p = unsafe { alloc_n(48) };
        churn_ptrs.push((p, 48));
        println!("ALLOC churn round={round} ptr={p:?} size=48");

        if let Some((last_ptr, last_size)) = churn_ptrs.pop() {
            let new_size = last_size * 2;
            let new_ptr = unsafe { realloc_n(last_ptr, last_size, new_size) };
            println!("REALLOC churn round={round} old={last_ptr:?} new={new_ptr:?} size={new_size}");
            churn_ptrs.push((new_ptr, new_size));
        }

        std::thread::sleep(Duration::from_millis(30));
    }
    for (p, size) in churn_ptrs {
        unsafe { free_n(p, size) };
        println!("FREE churn ptr={p:?}");
    }'''),
    ...para('//',
        r'The comments in the middle section name each step. The owner '
        r'is allocated first, "so phi’s ownership inference (which only '
        r'considers already-live nodes) can assign it as the children’s '
        r'effective owner". After a 300 ms pause, "the operation under '
        r'test": free the owner while the children remain live. "If '
        r'there is a hook-side bug tied specifically to this transition '
        r'(as opposed to ordinary alloc/free traffic), this is where it '
        r'would fire."'),
    blank,
    ...para('//',
        r'The churn loop is the "more than one chance" clause made '
        r'concrete. Twenty rounds, 30 ms apart: allocate 48 bytes, take '
        r'the block back off the list, reallocate it to 96, put it back. '
        r'Each round therefore produces an Alloc and a Realloc event after '
        r'the owner has gone, and the 30 ms sleep keeps the daemon’s '
        r'clock advancing, which matters because the daemon computes '
        r'ages from event timestamps, not from wall time. At the end the '
        r'churn blocks, 96 bytes each, are freed, and the children are '
        r'freed "last, well after the owner — confirms the process survives '
        r'past the owner-free/churn window before we declare success".'),
    blank,
    ...para('//',
        r'The program prints every pointer it handles, the way the Step 1 '
        r'and Step 2 targets do, and ends the same way injection_target.rs '
        r'does: a 300 ms flush pause, the marker WORKLOAD_DONE, and a '
        r'2000 ms window "for the driving script to spawn '
        r'heaplens-injector --detach". The whole run is about four '
        r'seconds.'),
    ...sec(r'what the experiment said'),
    ...para('//',
        r'The workload does not crash. The test file that drives it '
        r'opens its account with the sentence that matters most: the '
        r'owner-freed-while-children-live workload itself "never '
        r'crashed — it completed and printed its final marker every '
        r'time, whether or not a daemon was listening. The crash was '
        r'**not** in that pattern." The theory that motivated this file '
        r'was refuted by the file.'),
    blank,
    ...para('//',
        r'What did reproduce was something else. The target process '
        r'exited normally, by falling off the end of main, while the '
        r'hooks were still installed, with no detach before its own '
        r'exit, and that reliably ended with exit status 0xC0000005. '
        r'The pattern was not the trigger; the ending of the run was. '
        r'The repository does not say how the original observed run '
        r'ended, so I read the pattern as a coincidence of what that '
        r'workload happened to be. This is the mechanism by which an '
        r'experiment designed to catch one bug becomes the repro for '
        r'another, and it explains why a file named for the owner-free '
        r'transition is used by a test named for exit without detach.'),
    blank,
    ...para('//',
        r'The diagnostic handler gave a clue and no answer. The test '
        r'file’s header says it "never caught the fault (no log entry) — consistent '
        r'with a __fastfail-driven crash, which bypasses SEH/VEH by '
        r'design". I should flag that the two halves of that sentence '
        r'pull in different directions. 0xC0000005 is an ordinary '
        r'access violation, which a vectored handler normally sees, '
        r'while a fast-fail terminates with a different status. The '
        r'repository does not resolve the tension, and it records no '
        r'debugger session for the original crash.'),
    ...sec(r'how it stopped crashing, and why the file stayed'),
    ...para('//',
        r'The sequence of 2026-07-26 reads like a case file, and the '
        r'three commit times say how fast it moved.'),
    ...pt('//', r'02:42',
        r'commit 306e8fc switches the Attach button off again, citing a '
        r'"confirmed DLL_PROCESS_DETACH crash": a target that exits '
        r'while the hooks are installed crashes "reliably" with an '
        r'access violation, and the hook "has no DLL_PROCESS_DETACH '
        r'safety handling".'),
    ...pt('//', r'03:11',
        r'twenty-nine minutes later, commit deff3ad brings this file '
        r'and two siblings to master, and re-tests: 15 of 15 clean '
        r'exits for this very target. "Root-cause correlation", the '
        r'message calls it: the original investigation was done about '
        r'two and a half hours before the thread-local fix, and that '
        r'fix replaced a mechanism that crashed on any thread other '
        r'than the one that called LoadLibraryW. A dying process’s '
        r'worker and writer threads are exactly that population.'),
    ...pt('//', r'07:13',
        r'commit b5c5aed fixes the different defect the same '
        r'investigation had uncovered, a hang in the multi-threaded '
        r'variant of this scenario. See '
        r'exit_without_detach_multithreaded.rs.'),
    blank,
    ...para('//',
        r'A correlation is not a proof, and the commit says "correlation". '
        r'The fix that made the original exit crash disappear was made '
        r'for a different symptom, and nobody ran the original crash '
        r'under a debugger to see the same fault disappear for the '
        r'stated reason. What the project did instead is the sound '
        r'engineering response to a cause that cannot be proved: turn '
        r'the scenario into a standing test. The file stayed as the '
        r'repro for that test.'),
    ...sec(r'the two tests that use it'),
    ...code('rust', 'crates/heaplens-daemon/tests/hook_owner_free_no_crash.rs · target_exit_without_detach_is_clean', r'''
/// The scenario that used to crash reliably (`0xC0000005`), re-verified as
/// clean on master — see this file's module doc comment for the full
/// timeline/root-cause correlation with the TLS/FLS fix. No longer
/// `#[ignore]`d: this is now an assertion of desired, confirmed-working
/// behavior, not a tracked known-issue.
#[test]
fn target_exit_without_detach_is_clean() {
    let work_dir = std::env::temp_dir().join(format!("heaplens_owner_free_nocrash_repro_{}", std::process::id()));
    std::fs::create_dir_all(&work_dir).unwrap();

    let (mut target, mut reader, _pid) = spawn_and_attach("owner_freed_while_children_live", &work_dir);

    let workload_lines = read_until_marker(&mut reader, "WORKLOAD_DONE", Duration::from_secs(10));
    assert!(
        workload_lines.iter().any(|l| l.starts_with("WORKLOAD_DONE")),
        "target did not reach WORKLOAD_DONE — got: {workload_lines:?}"
    );

    // No detach — let the target exit on its own, hooks still active.
    let status = target.wait_timeout_or_kill(Duration::from_secs(5)).expect("target did not exit");
    assert!(
        status.success(),
        "target crashed on exit without detach (status={status:?}) — this scenario used to be a \
         confirmed, reliable crash (0xC0000005) and was verified clean before this test was \
         written as an assertion; if this fails, something regressed — see this file's module \
         doc comment for the full history"
    );

    let _ = std::fs::remove_dir_all(&work_dir);
}'''),
    ...para('//',
        r'The test spawns this target and attaches the real injector. '
        r'It waits for WORKLOAD_DONE, then deliberately does nothing: '
        r'"No detach — let the target exit on its own, hooks still '
        r'active". It gives the target five seconds to exit and asserts '
        r'a success status. The failure message is a short history in its '
        r'own right: "this scenario used to be a confirmed, reliable '
        r'crash (0xC0000005) and was verified clean before this test was '
        r'written as an assertion; if this fails, something regressed".'),
    blank,
    ...para('//',
        r'Its sibling in the same file, detach_before_target_exit_is_clean, '
        r'uses the same target and the same attach, but sends '
        r'heaplens-injector --detach after WORKLOAD_DONE and requires the '
        r'target to exit cleanly afterwards. Together the pair covers '
        r'both endings of one workload: a polite one, and the one a '
        r'user produces by closing the program under observation.'),
    blank,
    ...para('//',
        r'The daemon is not running in either test. The hook’s '
        r'writer thread retries the pipe every 100 ms and finds nothing '
        r'to connect to. The test therefore covers the hooks '
        r'without a consumer, which is a state the real product produces '
        r'whenever the daemon is closed with a target still attached '
        r'(see the page for the launcher).'),
    ...sec(r'limits'),
    ...pt('//', r'the name describes a hypothesis, not a finding',
        r'the file is named for a pattern that did not matter. The '
        r'header explains the origin, but a newcomer who sees '
        r'"owner_freed_while_children_live" in a test list could '
        r'reasonably assume the owner-free transition is what is '
        r'being protected.'),
    ...pt('//', r'single-threaded',
        r'every allocation happens on main. The worker-thread variant '
        r'is exit_without_detach_multithreaded.rs, and it exists because '
        r'this target could not exercise the population the thread-local '
        r'fix concerned.'),
    ...pt('//', r'it checks the exit status, nothing else',
        r'no events are inspected. The daemon is absent. A hook that '
        r'exited cleanly and captured nothing would pass.'),
    ...pt('//', r'timing windows',
        r'the 800 ms attach window and 300 ms and 2000 ms pauses are the '
        r'same kind of assumption as in injection_target.rs. Here they '
        r'cost little here, but a late attach would leave part of the '
        r'workload unhooked and the test would still pass, since it '
        r'only checks the exit status.'),
    ...sec(r'what to take from it'),
    ...pt('//', r'an experiment built to confirm can refute',
        r'this one did, and the test header records the refutation '
        r'in its first paragraph.'),
    ...pt('//', r'keep the repro after the theory dies',
        r'the target is still the right program for the real bug.'),
    ...pt('//', r'say "correlation" when it is one',
        r'the commit and the test header keep the line between what '
        r'was shown and what was inferred.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-hook/examples/owner_freed_while_children_live.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-hook/examples/owner_freed_while_children_live.rs'),
  ],
);
