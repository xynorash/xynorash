import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/docs/stage7-injection-design.md',
  lines: [
    heading('# Stage 7 — Process Attachment via Injection (Design)'),
    blank,
    ...text('How to observe the heap of a program you did not '
        'write and cannot rebuild, designed on paper before a line '
        'was coded, reviewed, and then corrected by the code it '
        'described. Eight sections, 847 lines, four commits on one '
        'day.'),
    blank,
    kv('role', 'design and staged build plan for attaching to live processes'),
    kv('date', '2026-07-13, four commits: 484 lines grew to 847'),
    kv('shipped as', 'heaplens-hook (cdylib) + heaplens-injector + a control channel'),
    kv('still says', '“DESIGN ONLY — not implemented”, which is no longer true'),
    kv('method', 'decide, review, build one gated step, revise the doc'),

    ...sec('the question'),
    ...text('Up to this stage HeapLens works only for programs '
        'that choose to be watched: they link the capture '
        'allocator in as their #[global_allocator]. That needs '
        'source access and a rebuild. The goal of Stage 7 is a '
        'process picker: choose any running Windows process and '
        'see its heap.'),
    ...code('markdown', 'docs/stage7-injection-design.md · the goal', r'''
Goal: let a user pick a running Windows process and observe its heap in
HeapLens without recompiling or relinking the target.'''),
    ...text('The difficulty is not drawing a graph. It is that '
        'every allocation in the target now has to be observed from '
        'outside its source code, from inside its address space, '
        'without ever making the target crash. A tool that '
        'crashes its own test program is a bug; one that crashes '
        'somebody else’s process is an incident. Almost every '
        'decision in this document is shaped by that asymmetry.'),

    ...sec('how the document was written'),
    ...text('The git history of this single file is a short '
        'course in design review. All four commits are dated '
        '2026-07-13.'),
    ...bullet('13b5115, the draft (484 lines)',
        'locks two decisions with their reasoning, specifies the '
        'attach and detach lifecycle, and confirms that the wire '
        'protocol needs no schema change. The commit message ends '
        '“No implementation.”'),
    ...bullet('339efd8, revised per review (+235, −33)',
        'three corrections. A claim about realloc of an unknown '
        'pointer was checked against the real graph.rs. A '
        'recommendation to accept a teardown gap was withdrawn and '
        'made in-scope work. And the detail-surfacing UI ideas '
        'were moved out of the stage entirely so a test failure '
        'in injection could not be confused with a rendering '
        'change. It also adds the six-step staged plan in §8.'),
    ...bullet('fc87292, gates tightened (+70, −20)',
        'step 1’s acceptance test must assert exact counts and '
        'sizes from a scripted workload, and step 5 is split into '
        'what can be proven now and what must wait for a real '
        'target.'),
    ...bullet('a680f8c, revised to match step 1 (+151, −40)',
        'three claims turned out to be wrong once code existed, '
        'and the document was rewritten the same day so that, in '
        'the commit’s words, it “doesn’t lie about the code it’s '
        'supposed to describe”.'),
    blank,
    ...text('The revision in the last commit is visible in the '
        'text itself. The document does not quietly fix its '
        'earlier claims. Each corrected passage says “Revised '
        'from the initial draft” and states what was wrong. '
        'That is rarer than it should be, and it is what makes '
        'the rest of the document trustworthy.'),
    ...text('What it did not do is stay current. The status '
        'paragraph at the top was never edited:'),
    ...code('markdown', 'docs/stage7-injection-design.md · status (unchanged since 13b5115)', r'''
Status: **DESIGN ONLY — not implemented.** This document specifies the
architecture; no code has been written against it. Benchmarks remain frozen
and unaffected by this stage. No branch has been created for this work.'''),
    ...text('Both heaplens-hook and heaplens-injector exist in the '
        'workspace, and the packaged v5 build exercised them '
        '(864167e), so read the sentence as a timestamp for the '
        'first commit, not as the current state. Later sections '
        'below note further places where what was built differs '
        'from what was written.'),

    ...sec('decision one: one target at a time'),
    ...text('The scope is a single target process, matching the '
        'daemon’s single-connection pipe loop. The document is '
        'candid about what multi-target would cost: a '
        'per-connection task model in ingest.rs, a '
        'source-process discriminator in the graph and in '
        'NodeDto, and PID filtering and colouring in Flutter. '
        'The consequence for behaviour is spelled out in §3.4 as '
        'an ordered transition. Selecting a new target runs: '
        'detach the old, wait for the pipe to close, clear the '
        'graph, attach the new one.'),
    ...text('Clearing the graph is called “the correctness-'
        'critical step”, not a cosmetic reset: a new process is a '
        'new, unrelated address space, and merging its nodes into '
        'the previous topology would produce a structure that mixes '
        'two programs. The code later hit the mirror image of this '
        'rule. b649234 (2026-07-26) found that clearing the '
        'graph on attach was wrong when the pid was already '
        'being observed through its own cooperative pipe, because '
        'the writer’s per-connection symbol cache then never '
        're-sent the addresses the daemon had just forgotten. The '
        'fix made the reset conditional on the pid actually '
        'changing.'),

    ...sec('decision two: how to intercept, and what was rejected'),
    ...text('The mechanism is an inline (trampoline) hook, using '
        'the MinHook library through the minhook crate, on three '
        'functions in ntdll: RtlAllocateHeap, RtlReAllocateHeap and '
        'RtlFreeHeap. The reasoning is given as two rejections.'),
    ...text('Import-table hooking is rejected because its failure '
        'is invisible:'),
    ...code('markdown', 'docs/stage7-injection-design.md · why not IAT hooking', r'''
**Why not IAT hooking:** IAT hooking only intercepts calls that go through
the target's import table. It misses statically-linked CRTs (every MSVC
`/MT` binary), calls made through function pointers, and delay-loaded
imports. For the actual goal — observing real, uncooperative third-party
binaries — those blind spots aren't a degraded signal, they're a *silent
undercount*: the tool would report a heap graph that's missing an unknown
fraction of allocations, with no way to tell how much.'''),
    ...text('The principle is general and worth keeping: prefer '
        'the failure you can see. A tool that reports less than '
        'the truth without saying so is worse than one that '
        'refuses.'),
    ...text('Hooking the C runtime’s malloc is rejected because '
        'it sits above the same layer on Windows. Hooking both '
        'would double-count every CRT allocation, and the symbol '
        'names differ by CRT version and linkage. The Rtl*Heap '
        'functions are the common sink: they catch CRT-backed and '
        'direct Win32 allocation alike. The stated cost is that '
        'the tool sees heap operations, not C semantics, so a '
        'calloc’s zeroing is invisible. The document judges '
        'that acceptable for “a memory-topology tool, not a '
        'CRT-semantics tool”.'),

    ...sec('the layer that looked right and was not'),
    ...text('The first draft named a different layer: '
        'kernelbase!HeapAlloc and its siblings. It was chosen on '
        'paper and was wrong. The failure is the most instructive '
        'passage in the document, both for what happened and for '
        'how it was isolated:'),
    ...code('markdown', 'docs/stage7-injection-design.md · §1.1 (trimmed)', r'''
system, not a style choice.** Hooking `kernelbase!HeapAlloc`/`HeapReAlloc`/
`HeapFree` directly produced a reproducible `STATUS_ACCESS_VIOLATION` on
the very first call after `MinHook::enable_all_hooks()` succeeded — MinHook
reports success at every step (hook creation, enable), but the generated
trampoline is broken the instant it's invoked. Isolated via a control
probe: hooking a simple, non-allocating export (`GetTickCount`) with the
identical create/enable/detour pattern worked correctly (correct trampoline
call, correct return value, no crash), which rules out a usage mistake and
narrows the failure to something specific about `HeapAlloc`'s prologue
shape on this Windows build.'''),
    ...text('Three things to take from it. Success codes are not '
        'evidence: every MinHook call reported success while the '
        'trampoline was broken. A control experiment is how you '
        'tell “I am using the library wrong” from “this target '
        'is special”: the identical code path on a harmless '
        'function worked. And the response to a surprise was to '
        'move one layer down and re-run the same experiment, not '
        'to add workarounds.'),
    ...text('The lesson was kept in the code. The hook DLL now '
        'verifies itself at attach time with a canary: it makes '
        'one allocation of a size no real caller would use, checks '
        'that its own detour ran, and rolls the whole hook back if '
        'it did not. The comment above the constant says why:'),
    ...code('rust', 'crates/heaplens-hook/src/lib.rs · the canary', r'''
// A size no real caller would ever request, used to prove the trampoline
// actually works end to end (real call -> detour invoked -> real function
// executed -> detour returns the correct result) before trusting the hook
// with a real target. MinHook reporting "enable succeeded" is not
// sufficient evidence on its own — that is exactly the failure mode found
// hooking the kernelbase!HeapAlloc layer (§1.1): every install/enable step'''),
    ...text('Moving down a layer has a price, and the document '
        'states it rather than hiding it. Rtl*Heap is process-wide, '
        'so it also sees the capture pipeline’s own incidental '
        'heap traffic and whatever Windows allocates on the '
        'writer thread’s behalf. The raw event stream is therefore '
        'not one-to-one with the target’s own calls, and the '
        'acceptance test matches events by pointer identity, not '
        'by a global count. The document calls this “a more honest '
        'capture surface… not a worse one”.'),

    ...sec('decision three: change nothing downstream'),
    ...text('The best decision in the document is a negative '
        'one. The existing frame protocol already carries '
        'everything: a handshake with a pid, events, symbols. The '
        'hook DLL emits exactly the bytes a cooperative producer '
        'emits, so from the daemon’s point of view an injected '
        'target is indistinguishable from a program that linked the '
        'allocator. The document concludes that the protocol, the '
        'daemon’s ingest and graph, φ and the Flutter app are '
        'unchanged, and that all new code is upstream of the pipe.'),
    ...text('That held up. The one place a field got used for '
        'the first time was the handshake: the daemon had been '
        'decoding the pid and name and discarding them, and §1.2 '
        'proposes activating them. 0edc728 did so on 2026-07-17, '
        'forwarding them into a target-status banner, with the '
        'commit confirming ownership inference and detection '
        'behaved byte-for-byte as before. When the control '
        'channel was ported into the UI branch (724695a), the '
        'commit message reports the Flutter control models '
        '“already matched the wire contract exactly”, so the '
        'port needed no Dart changes at all.'),

    ...sec('two new crates, and why the injector is its own process'),
    ...bullet('heaplens-hook',
        'a cdylib that statically links MinHook and reuses the '
        'allocator crate’s capture code as a library: the ring, '
        'record(), the writer, symbol resolution, framing. The '
        'design says the capture logic is shared and unmodified; '
        'only the interception differs.'),
    ...bullet('heaplens-injector',
        'a small synchronous binary that opens the target, loads '
        'the DLL and drives its exported entry points. The daemon '
        'spawns it as a short-lived child, one run per attach and '
        'one per detach.'),
    blank,
    ...text('Keeping the injector out of the daemon is argued '
        'in two sentences: injection is synchronous, Win32-heavy, '
        'process-scoped code with no business in the async '
        'runtime, and a standalone tool can be pointed at any pid '
        'from a terminal, exactly like the producer examples. The '
        'payoff arrived later. Because the injector prints a '
        'specific reason when it refuses, and the daemon captures '
        'that text and returns it in the attach reply, the UI can '
        'show the real reason a process was rejected. 864167e '
        'records confirming that live against a protected '
        'Windows Defender process.'),

    ...sec('the lifecycle is the hard part'),
    ...text('Most of the design’s length goes on one question: '
        'in what order may the hook DLL initialise and tear down '
        'things? The answer was found by crashing, one thing at a '
        'time, and the document keeps the evidence. The attach '
        'order is a hard requirement:'),
    ...code('markdown', 'docs/stage7-injection-design.md · §1.3 attach order', r'''
  order:
  1. Create the private heap (§4.2).
  2. Start the writer thread (`heaplens_alloc::ensure_writer_started`).
  3. Warm `backtrace::resolve`'s one-time init
     (`heaplens_alloc::warm_up_symbol_resolution`).
  4. **Only then** install and enable the MinHook hooks.'''),
    ...text('Two hazards sit behind steps 2 and 3, both crashes '
        'with the same shape. Starting a thread from inside a '
        'hook callback re-enters the half-stable hooked path during '
        'the new thread’s DLL_THREAD_ATTACH bootstrap. And the '
        'writer’s first symbol lookup loads dbghelp and calls '
        'SymInitialize, which does heavyweight first-use work that '
        'allocates while the hook is live. Both are cured the same '
        'way, by forcing the work to finish before any hook exists. '
        '(The code in attach_impl warms symbol resolution before '
        'starting the writer, the reverse of the written order of '
        'steps 2 and 3; the invariant, everything before any hook, '
        'is what matters.)'),
    ...text('The document then explains why nobody should '
        '“simplify” this back:'),
    ...code('markdown', 'docs/stage7-injection-design.md · §1.3 the warning', r'''
  This ordering is a hard requirement, not an optimization — reverting to
  lazy initialization "to simplify" would reintroduce a target-crashing bug
  invisible to any test run in a warm process (a test harness that already
  triggered dbghelp/thread-pool warmup elsewhere wouldn't reproduce it). A'''),
    ...text('That last clause is the real insight: a test that '
        'passes in a warm process proves nothing about the first '
        'call in a cold one. The same idea reappears in the '
        'acceptance gates below.'),
    ...text('Detach is the same problem in reverse and gets its '
        'own order, the fourth hazard. A thread that exits '
        'naturally runs DLL_THREAD_DETACH and TLS cleanup, which '
        'performs heap operations; if hooks are still live those '
        'operations route through the detour while the thread is '
        'mid-teardown. So hooks go first:'),
    ...code('markdown', 'docs/stage7-injection-design.md · §4.1 detach order', r'''
1. `MinHook::disable_all_hooks` — un-redirects the three hooked functions
2. Signal the writer thread to stop and wait, bounded by a timeout, for it
   to actually exit (`heaplens_alloc::request_writer_stop_and_wait`). Its
   own exit-time heap traffic now goes through the real, unhooked
   functions, not a detour — this is *why* step 1 must happen first, not
   an independent nicety.
3. Only once the writer is confirmed stopped: `MinHook::uninitialize`
   (frees the trampolines) and destroy the private heap.'''),
    ...text('There is a refusal built in. If the writer does not '
        'stop within the timeout, detach does not go on to free '
        'the trampolines or the heap, because freeing them under a '
        'thread that may still be running code that uses them is '
        'worse than leaving the hook installed. Failing to a '
        'safe, ugly state beats failing to a fast, crashing one.'),

    ...sec('where the design was overtaken'),
    ...text('Two things in the document did not survive contact '
        'with the full system, and one grew beyond it. None was '
        'backported.'),
    ...text('First, the detach mechanism. §4.1 has the injector '
        'call HeapLensHookDetach through a second CreateRemoteThread. '
        'That was tried and it crashed, in a way the author took '
        'care to reduce to its cause. The comment in the hook '
        'source records the reduction:'),
    ...code('rust', 'crates/heaplens-hook/src/lib.rs · cross-process detach', r'''
// Confirmed empirically: even a `HeapLensHookDetach` body reduced to an
// immediate `return 42` (no spawn, no real work) still crashed identically
// whenever hooks were active at the moment the injector's second
// `CreateRemoteThread` call created the thread — proving the fault is in the
// automatic notification, not anything this module's code does.'''),
    ...text('A function that does nothing and still crashes '
        'proves the fault is not in the function. Creating a '
        'remote thread makes Windows deliver DLL_THREAD_ATTACH to '
        'every loaded module on it, and that notification’s own '
        'allocations hit the live detour on a thread that is not '
        'yet in a state to tolerate it. The fix avoids creating a '
        'thread at all:'),
    ...code('rust', 'crates/heaplens-hook/src/lib.rs · the APC route (trimmed)', r'''
// The fix avoids creating a second raw thread at all: `attach_impl`'s own
// worker thread (already alive, already a normal, properly CRT-initialized
// Rust thread — safe by construction, unlike a `CreateRemoteThread` thread)
// parks itself in an *alertable* wait instead of an inert one, and exposes
// its OS thread ID here so `heaplens-injector` can `QueueUserAPC` detach'''),
    ...text('The injector now queues an asynchronous procedure '
        'call onto the DLL’s own worker thread and reads the '
        'result back out of the target’s memory, since an APC '
        'cannot return a value. The design’s thread-creation '
        'step is simply not how it works. By the time the hook '
        'source settled, a comment in it was counting “a tenth, '
        'distinct hazard” of the same family; the design listed '
        'four.'),
    ...text('Second, the launcher teardown. §4.6 is a '
        'well-argued section. The first draft accepted that '
        'closing HeapLens while attached would leave live '
        'trampolines in someone else’s process. The review '
        'withdrew that, in a sentence worth quoting:'),
    ...code('markdown', 'docs/stage7-injection-design.md · §4.6', r'''
**Revised from the initial draft, which proposed accepting this as a gap —
that recommendation is wrong and is withdrawn.** "Harmless to the target's
execution" (§4.2/§4.3 prove the target keeps running correctly with an
abandoned hook) is not the same question as "acceptable to leave behind."'''),
    ...text('The distinction is the point: being provably safe '
        'to leave behind is not the same as being acceptable to '
        'leave behind. The specified fix was a Shutdown control '
        'message and a bounded wait before the launcher kills the '
        'daemon. It is not in the tree. The control '
        'protocol has three request types (list, attach, '
        'detach), the daemon’s only Shutdown is an internal '
        'message to its storage thread, and the launcher goes from '
        'the app exiting straight to killing the daemon. A comment '
        'in the hook source does mention “the launcher’s own '
        'bounded-detach pattern (§4.6)”, so it may exist on a '
        'branch that never reached master. On master as it reads, '
        'closing HeapLens with a target attached still leaves '
        'the hook resident until the target exits, while §4.5’s '
        'table marks that case “Handled”. Treat that row as the '
        'document’s intent, and the later exit-without-detach '
        'work, below, as the project’s answer to the '
        'consequences.'),

    ...text('Third, validation. §3.3 lists three checks before '
        'the injector touches a target: architecture match, '
        'minimal access rights, and still-running. It also fixes '
        'a security boundary: no elevation, ever. What shipped '
        'adds a whole layer the document never mentions. On '
        '2026-07-22, with Attach about to be re-enabled, '
        'safety.rs landed (864167e), refusing processes that '
        'carry kernel-driver components: VPN clients, anti-cheat, '
        'security products and virtualisation hosts. Its header '
        'explains the motive in one clause: it is “the same hard '
        'exclusion this project’s own testing has followed all '
        'along, now enforced by the tool itself instead of '
        'relying on the operator to remember it every time”. '
        'The entry point is three vetoes, any one of which '
        'refuses:'),
    ...code('rust', 'crates/heaplens-injector/src/safety.rs · check', r'''
pub fn check(pid: u32) -> Result<(), String> {
    if let Some(reason) = check_protection_level(pid) {
        return Err(reason);
    }
    if let Some(reason) = check_loaded_modules(pid) {
        return Err(reason);
    }
    if let Some(reason) = check_process_name(pid) {
        return Err(reason);
    }
    Ok(())
}'''),
    ...text('The order runs from most general to most specific. '
        'Process protection level needs no list of vendors at '
        'all, so it covers products nobody enumerated; a loaded '
        'vendor DLL fingerprints the userspace half of a '
        'driver-backed product; a process-name denylist comes '
        'last because, in the source’s own words, it is trivially '
        'spoofable and incomplete by construction. And the checks '
        'run with the weakest handle that can answer, so the '
        'refusal itself never needs injection-capable access to '
        'the thing being refused. The whole module is the design’s '
        'own principle, prefer the failure you can see, applied '
        'to the injector’s decision to act.'),

    ...sec('reentrancy, and an assumption that held until it did not'),
    ...text('Inside the hook, the capture code runs on the '
        'target’s own threads at the moment they allocate. If '
        'capturing allocates, it recurses. §4.2 says the hook '
        'uses two defences: the same per-thread guard flag as the '
        'cooperative allocator, and a private heap created at '
        'attach time that MinHook never touches, so that even a '
        'bypassed guard could not reach the hooked functions. The '
        'second is the mechanism; the first is the fast path.'),
    ...text('The document says the hook “uses the identical '
        'pattern” as heaplens-alloc’s guard. That turned out to be '
        'true to a fault. The guard was a thread_local!, which '
        'worked in a program that linked the allocator and failed '
        'in a DLL loaded afterwards with LoadLibrary. On '
        '2026-07-21 the self-load stress harness crashed every '
        'run, a crash in heaplens_hook.dll was recorded in a '
        'live process, and a Windows bugcheck on the same machine '
        'prompted the investigation. The UI’s Attach button was '
        'disabled that day (823dac7) with a tooltip saying why, '
        'and root-caused the same evening: dcc76f2 replaced '
        'thread_local! with TlsAlloc and FlsAlloc, with twenty '
        'consecutive clean runs of a 48-thread, 8-second hooked '
        'stress run as the acceptance evidence.'),

    ...sec('honest about symbols'),
    ...text('§2 is the shortest section and the one the '
        'thesis leans on. Ownership inference needs function '
        'names; an injected target is usually a release build '
        'with no debug info; so φ will find few or no edges. The '
        'document refuses to bury this and lists precisely what '
        'survives:'),
    ...code('markdown', 'docs/stage7-injection-design.md · §2 what still works', r'''
**What still works against a symbol-stripped injected target:**
- Allocation capture itself (size, pointer, timestamp, raw stack depth) —
  unaffected; this doesn't require symbol names.
- The memory-map / node-count / size-over-time view — unaffected, since it
  doesn't depend on ownership edges.'''),
    ...text('The section goes on to list orphan timing and '
        'fan-out flags as unaffected, because they use time and '
        'counts. The code disagrees, and this is a place where '
        'the document was overtaken by the implementation. '
        'anomaly.rs marks a node orphan only if it once had an '
        'owner, and hot only if it has more than 32 outgoing '
        'edges, and both facts come from φ. The commit that '
        'documented the packaging bug (9c4678e) describes exactly '
        'this symptom: with every site collapsed, φ found no '
        'edges and Hot and Orphan never fired. So against a '
        'symbol-stripped target the ownership edges degrade, and '
        'with them the orphan and hot verdicts. What does survive '
        'is capture, the memory map and size tracking. The '
        'document frames the degradation as expected behaviour:'),
    ...code('markdown', 'docs/stage7-injection-design.md · §2 the framing', r'''
profiler that requires debug info to show ownership, applied to a target
that has none, is expected to show none — and that is a correct, legible
degradation, not a bug to chase.'''),
    ...text('Step 6 turns that into a test order. The first '
        'injected target must be one the project built, with '
        'debug info, so that missing edges can only mean broken '
        'injection. Only then is a stripped third-party binary '
        'tried, where missing edges are the prediction. The '
        'document explains why:'),
    ...code('markdown', 'docs/stage7-injection-design.md · §8 step 6', r'''
**This sequencing matters and must not be skipped or reordered.** Two
different failure modes look identical on screen — "injection captured
nothing because injection is broken" and "injection captured allocations
correctly but φ correctly shows zero ownership edges because the target
has no debug info" — and testing against a stripped binary first would
make it impossible to tell which one occurred.'''),
    ...text('A related catch appears in §5. The user had '
        'reported no lines between nodes, and the obvious '
        'suspect was the renderer. The investigation read the '
        'painter, saw it draws every edge the daemon reports with '
        'no suppression logic, and traced the symptom to the same '
        'missing-debug-info collapse documented in Cargo.toml. '
        'It is a clean example of reading the code that would have '
        'to be wrong before touching it.'),

    ...sec('the gates'),
    ...text('Each of the six steps has an acceptance gate and a '
        'rule not to start the next step until it passes. The '
        'discipline worth copying is how specific the gates are. '
        'Step 1 builds the hook DLL and tests it by loading it '
        'into its own process, so “does the hook work” is '
        'separated from “does injection work”. Its gate '
        'asserts, it does not observe: a scripted workload with a '
        'fixed number of allocs, reallocs (including one on an '
        'untracked pointer) and frees; exact size matches; and '
        'then zero captured events after detach, “not fewer or '
        'looks quiet”. The implementation commit (b3a22c2) '
        'reports the shape it measured: exactly 50 allocs, 11 '
        'reallocs, 51 frees, zero after detach.'),
    ...text('Step 5 shows the other virtue, refusing to claim '
        'more than was proven. The launcher’s timeout logic can '
        'be tested with a stub; whether a real hook is gone from a '
        'real target cannot be, until step 6 exists. So step 5 is '
        'marked partial on purpose, with the missing assertion '
        'moved to an explicit item in step 6.'),

    ...sec('what happened after the design'),
    ...text('The design promised an incremental, gated build. '
        'The history shows the gates doing their job, and also '
        'that the finish line moved. Dates are commit dates.'),
    ...bullet('2026-07-13, b3a22c2',
        'step 1 lands, with four distinct hazards found by '
        'disabling one thing at a time.'),
    ...bullet('2026-07-19, 724695a',
        'the control protocol, process listing and injector are '
        'ported onto the UI branch. The Flutter picker needed no '
        'protocol work.'),
    ...bullet('2026-07-21',
        'a hooked, multi-threaded stress harness (8b0f962) '
        'reproduces a crash; Attach is disabled (823dac7); the '
        'thread-local root cause is fixed (dcc76f2).'),
    ...bullet('2026-07-22',
        'a chain of fixes found by running a 12-thread injected '
        'target under load: dead nodes were never evicted, a '
        'writer-thread panic on a batch that overflowed the '
        '16-bit event count, an unbounded channel backlog, and '
        'two O(N) scans in the graph. Per the commit messages, throughput '
        'rose from about 61–65 thousand events a second to about '
        '1.0–1.1 million, and peak memory fell from about 8.9 GB '
        'to under 400 MB, returning to a ~39 MB baseline after '
        'detach. Attach is re-enabled (864167e) after validation '
        'against a native Win32 app, an Electron app and a '
        'Node.js process, and a driver-exclusion check in the '
        'injector lands with it.'),
    ...bullet('2026-07-26',
        'a second defect: a target that exits without a detach '
        'crashed (306e8fc re-gates Attach). After the TLS fix that '
        'crash no longer reproduced (15 of 15 clean) but a hang '
        'did, 40 to 60 percent of runs (deff3ad). WinDbg showed a '
        'lock orphaned by a thread killed mid-capture, fixed by '
        'turning the lock into a try_lock (b5c5aed): 45 clean runs.'),
    ...bullet('2026-07-28',
        'Attach is re-enabled at 02:38 in 9693399, a one-line '
        'commit that says “soutenance” (the thesis defence). That '
        'morning 50a9627 fixes a missed classification of the '
        'hook’s own trampoline frames, which had collapsed every '
        'injected allocation onto one shared symbol. The commit '
        'says the bug probably predates the day and was masked '
        'until cooperative capture became opt-in (a31baeb).'),
    blank,
    ...text('The design’s line about its own safety argument is '
        'borne out the hard way: the sections written most '
        'carefully (lifecycle order, reentrancy) are exactly the '
        'ones that later needed fixes, because the hazards were '
        'in how Windows loads and tears down threads, which a '
        'design review cannot enumerate. The gates and the '
        'standing regression harnesses are what caught them.'),

    ...sec('limits, and what to take from it'),
    ...bullet('known limits in the design',
        'x64 targets only (an IsWow64Process2 check refuses '
        'others); no elevation, ever, by design; one target at a '
        'time; and the injected view starts at attach, because '
        'allocations before attach produced no event.'),
    ...bullet('timestamps',
        'per §1.4 the hook rebases its clock to attach time, not '
        'process start. The daemon treats timestamps as opaque '
        'and relative, so nothing changes, but the numbers mean '
        '“time since attach”.'),
    ...bullet('unknown frees',
        'a free of a pointer allocated before attach is dropped; '
        'a realloc of one is kept and registered as a new node. '
        'The document verifies the second against graph.rs and '
        'records the asymmetry as intentional.'),
    ...bullet('what to take from it',
        'put the reason next to the decision; test the cold path; '
        'let a revised document say what it got wrong; and make '
        'the failure of the clever thing visible instead of '
        'silent.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
