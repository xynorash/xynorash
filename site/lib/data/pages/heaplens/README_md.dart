import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/README.md',
  summary: 'live heap inspector for native Windows (Rust + Flutter)',
  repo: 'heaplens',
  fallbackStars: 0,
  fallbackPushed: '2026-07-28',
  lines: [
    heading('# HeapLens'),
    blank,
    ...text('A live heap inspector for native Windows programs. '
        'It records the allocations a program makes, infers which '
        'allocation is responsible for which from the call stacks, '
        'and draws the result as a graph that moves in real time. '
        'A leak is a node whose owner was freed while it stayed '
        'alive, and it turns coral on the screen while the program '
        'is still running. Written in Rust for the part that sits '
        'inside the observed process and the part that models the '
        'heap, and in Dart with Flutter for the part you look at. '
        'It was built as a Master’s thesis project (the UML '
        'document in docs/ is headed “Mémoire de Master en '
        'Informatique”), spec first, in the 34 days between the '
        'first and the last commit.'),
    blank,
    kv('language', 'Rust (capture, daemon, hook, injector) · Dart/Flutter (UI)'),
    kv('target', 'Windows x86-64, native processes'),
    kv('shape', '7-crate Cargo workspace + 1 Flutter desktop app'),
    kv('history', '136 commits, 2026-06-24 to 2026-07-28, on 14 distinct days'),
    kv('tests', '109 Rust test functions · 146 Dart test calls (grep counts)'),
    kv('docs', 'build spec, UML, 5 plans, 1 design spec, 1 stage design'),
    kv('status', 'working; cross-process attach gated twice, then re-enabled'),

    ...sec('the problem, and why it is hard'),
    ...text('Most heap tools answer “how much memory does this '
        'program use?” A leak is a different question: which '
        'allocation is still alive after the thing that was '
        'supposed to own it is gone? HeapLens treats the heap as '
        'a graph. Nodes are live allocations. An edge means “this '
        'allocation was made on behalf of that one”. An orphan is '
        'a node whose owner has been freed and which is older than '
        'a threshold, counted from its own allocation. Once you '
        'phrase it that way, leak '
        'detection becomes a property of a graph you can watch '
        'change, and not a number you diff afterwards.'),
    ...text('Three things make that difficult, and they are what '
        'the repository is really about.'),
    ...bullet('the observer must not be noticed',
        'the capture code runs inside every allocation of the '
        'target program. The spec’s invariants (section 12 of the '
        'Build Spec) say it may not allocate, may not wait on a lock '
        'and may not panic. '
        'Everything else follows from that: a lock-free ring, a '
        'separate daemon process, symbols resolved before they '
        'leave the target. The hot path section shows one place '
        'where the history broke the no-lock rule and repaired it.'),
    ...bullet('ownership is not recorded anywhere',
        'the allocator knows addresses and sizes. Nothing says '
        'who owns what. HeapLens infers it from the names of the '
        'functions on the call stack, which makes the whole '
        'picture depend on whether a binary can name its own '
        'functions.'),
    ...bullet('observing a program you cannot rebuild',
        'the second mode injects a DLL into a running process '
        'and hooks the Windows heap functions. A mistake there '
        'does not crash your test program. It crashes someone '
        'else’s.'),

    ...sec('the system in one picture'),
    plain('  target process'),
    plain('    |  heaplens-alloc (linked in)  or  heaplens-hook (injected)'),
    plain('    |  per-thread lock-free ring -> writer thread'),
    plain('    v  named pipe \\\\.\\pipe\\heaplens, binary frames'),
    plain('  heaplens-daemon'),
    plain('    |  pipe ingest -> graph task (owner of all state)'),
    plain('    |  phi ownership inference, anomaly sweep, SQLite store'),
    plain('    v  WebSocket ws://127.0.0.1:9999, JSON snapshot + diffs'),
    plain('  heaplens_flutter'),
    plain('       force-directed graph, memory map, insights, picker'),
    blank,
    ...text('Capture runs inside the observed process and '
        'everything else runs outside it. The boundary is '
        'deliberate: graph building, symbol lookups, SQLite and '
        'WebSocket traffic can never slow or destabilise the '
        'program being watched, because the only thing it does is '
        'push a fixed-size record into memory it owns. The pipe '
        'is the airlock. Exactly two contracts cross a boundary: '
        'the binary frame protocol from capture to daemon, and the '
        'JSON protocol between daemon and UI, which since the '
        'process picker also carries a few control requests and '
        'responses on the same WebSocket. Both are defined '
        'once, in heaplens-protocol, and the UI knows nothing of '
        'Rust, pointers or the daemon’s internals.'),
    ...code('rust', 'crates/heaplens-protocol/src/event.rs · the record that crosses the pipe (trimmed)', r'''
    /// 16 frames (up from 8): the zeroed-allocation path (`vec![0u8; n]`,
    /// the idiom used throughout this project's producers) inserts 6+
    /// non-inlined std frames between the shared instrumentation and the
    /// real call site, so 8 frames can contain zero user frames. Consumers
    ...
    pub stack:     [u64; 16],
}

const _: () = assert!(core::mem::size_of::<AllocEvent>() == AllocEvent::SIZE);'''),
    ...text('One fixed-size record per allocation, with explicit '
        'padding, and a size the compiler checks. The 168 bytes '
        'are 40 bytes of header fields plus sixteen 8-byte return '
        'addresses. The Build Spec still describes the original '
        '104-byte record with eight frames; commit 43fc22e widened '
        'it on 2026-07-08, and the comment above gives the reason: '
        'the zeroed-allocation path behind vec![0u8; n] puts six or '
        'more standard-library frames between the instrumentation '
        'and the real call site, so eight frames could hold no '
        'user frame at all. The assert turns any drift between the '
        'struct and the wire constant into a compile error.'),

    ...sec('a tour of the tree'),
    ...text('Everything below is a real path in the repository. '
        'There is no README.md at its root; this page stands in '
        'for one.'),
    ...bullet('Cargo.toml, Cargo.lock',
        'the workspace (7 members) and its one profile override, '
        '[profile.release] debug = true, whose comment is the '
        'diagnosis of a bug that produced no error. See the '
        'Cargo.toml page.'),
    ...bullet('.gitignore',
        'seven lines, added only on 2026-07-08, excluding /target/, '
        '/dist/ (where the packaged build lives), the Flutter build '
        'directories and heaplens.db, the daemon’s default '
        'database file.'),
    ...bullet('crates/heaplens-protocol',
        'the contract. event.rs, frame.rs, diff.rs, control.rs. '
        'Depends on serde and nothing else (serde_json only as a '
        'dev-dependency); five test files pin framing, partial '
        'reads, multi-frame pushes, resync and JSON shape.'),
    ...bullet('crates/heaplens-alloc',
        'capture: lib.rs (the allocator and record()), guard.rs '
        '(per-thread recursion flag), ring.rs (lock-free SPSC ring '
        'plus registry), capture.rs (timestamp and stack walk), '
        'writer.rs (drain, resolve symbols, frame, send). '
        'examples/ holds eleven programs: alloc_smoke, '
        'wire_producer, demo_producer, hot_producer, four chaos_* '
        'scenarios and the three checkout_service variants, most '
        'of them written to be watched on screen.'),
    ...bullet('crates/heaplens-daemon',
        'the model: ingest.rs (pipe to frames), resolver.rs '
        '(address to name), graph.rs (φ, nodes, diffs), '
        'anomaly.rs (orphan, hot, storm), store.rs (SQLite), '
        'server.rs (WebSocket), procs.rs and injector.rs (process '
        'list and attach), config.rs, main.rs. Thirteen test '
        'files, including cross-process tests that run a real '
        'producer over a real pipe.'),
    ...bullet('crates/heaplens-hook',
        'a cdylib loaded into a target. MinHook detours on '
        'ntdll’s RtlAllocateHeap, RtlReAllocateHeap and '
        'RtlFreeHeap, a private heap, eager initialisation, and '
        'an APC-driven detach. Seven examples are the harnesses '
        'and repro programs used to test it.'),
    ...bullet('crates/heaplens-injector',
        'a short-lived binary that loads the hook into a pid. '
        'safety.rs decides whether it is allowed to.'),
    ...bullet('crates/heaplens-launcher',
        'HeapLens.exe: start the daemon, wait for its port, start '
        'the UI, and tie the daemon to the launcher’s lifetime '
        'with a Windows Job Object.'),
    ...bullet('crates/h1-harness',
        'the detection-latency measurement. Reads its inputs '
        'back from the daemon’s own database.'),
    ...bullet('heaplens_flutter',
        'the app: lib/ with models, providers (Riverpod), a pure-'
        'Dart force layout, widgets (graph canvas, memory map, '
        'control ribbon, node detail, insights panel, process '
        'picker), plus test/ and a Windows runner.'),
    ...bullet('docs',
        'the build spec, the UML model, a stage-7 design, the H1 '
        'results, and docs/superpowers with five plans and one '
        'design spec. The pages in this tree explain each.'),
    blank,
    ...text('The separation follows the failure domains. The '
        'protocol crate is the only one both sides link. The '
        'allocator crate runs in someone else’s address space, so '
        'it is small and was specified to carry no async runtime '
        '(the manifest has since weakened that, see the limits). '
        'The daemon is '
        'a normal Tokio program. The hook and injector are '
        'separate crates because one is a DLL that must be '
        'loaded into a process and the other a tool that loads '
        'it, and they have different lifetimes, different '
        'privileges and different ways of dying.'),

    ...sec('the hot path'),
    ...text('Every allocation passes through one function, and '
        'the rules for the code beneath it are the strictest in the '
        'repo. The ring is a single-producer, single-consumer '
        'queue per thread: the producer owns the tail, the '
        'consumer the head, and one release store publishes a '
        'slot.'),
    ...code('rust', 'crates/heaplens-alloc/src/ring.rs · push() (trimmed)', r'''
    pub fn push(&self, ev: AllocEvent) -> bool {
        let tail = self.tail.load(Ordering::Relaxed);
        let next = (tail + 1) & (CAP - 1);
        if next == self.head.load(Ordering::Acquire) {
            self.dropped.fetch_add(1, Ordering::Relaxed);
            return false;
        }
        // SAFETY: `tail < CAP`; slots is a valid array of CAP elements.
        // The producer owns slot[tail]; the consumer won't read it until
        // the tail store (Release) below makes the write visible.
        unsafe { self.slots.add(tail).write(ev) };
        self.tail.store(next, Ordering::Release);
        true
    }'''),
    ...text('A full ring drops the event and bumps a counter '
        'instead of waiting: losing a sample is acceptable, '
        'stalling the host is not. One slot is always left empty to '
        'tell full from empty, which is why 65,536 slots hold at '
        'most 65,535 events. The backing storage is taken '
        'from the system allocator directly; invariant 5 of the '
        'Build Spec forbids ever taking it from the global '
        'allocator, which this crate replaces. The guard that stops '
        'record() recursing into itself is a per-thread flag, and '
        'how that flag is stored turned out to be the root of the '
        'crash that first gated the Attach button (see the section '
        'on attaching).'),
    ...text('The invariant that capture never takes a lock was '
        'broken once, on purpose, and repaired later. On '
        '2026-07-19 commit 9c4678e put a global mutex, '
        'DBGHELP_LOCK, around every call into the backtrace '
        'library, because its stack walk and symbol resolution both '
        'reach dbghelp.dll, which Windows documents as not safe for '
        'concurrent calls. On 2026-07-26 a WinDbg stack trace showed '
        'what that cost: when a process exits with the hook still '
        'installed, the OS kills its other threads without cleanup, '
        'and a thread killed while holding the lock orphans it; the '
        'surviving thread then frees memory, re-enters the hook, and '
        'waits on the dead lock forever. Commit b5c5aed swapped '
        'lock() for try_lock(). Before the change 7 to 9 runs out of '
        'each batch of 8 to 10 hung; afterwards 45 runs in a row '
        'were clean.'),
    ...code('rust', 'crates/heaplens-alloc/src/capture.rs · capture_stack() (trimmed)', r'''
    let guard = match crate::DBGHELP_LOCK.try_lock() {
        Ok(g) => Some(g),
        Err(std::sync::TryLockError::Poisoned(e)) => Some(e.into_inner()),
        Err(std::sync::TryLockError::WouldBlock) => None,
    };
    let Some(_guard) = guard else {
        return (stack, 0);
    };'''),
    ...text('A held lock now yields one empty capture instead of a '
        'wait. The function does not need to know whether the lock '
        'is orphaned or merely busy; the commit message says a '
        'single degraded capture is harmless and a permanent hang is '
        'not. Two unit tests in capture.rs pin both halves: it never '
        'blocks while the lock is held, and it still captures '
        'normally when the lock is free.'),
    ...text('Consent is part of the design, but only from '
        '2026-07-28 (commit a31baeb). Before that, any binary that '
        'linked the allocator tried to connect to a daemon. Now '
        'linking it in does nothing by itself:'),
    ...code('rust', 'crates/heaplens-alloc/src/lib.rs · HeapLensAlloc doc (trimmed)', r'''
/// **Linking this in does nothing by itself.** No pipe connection is ever
/// attempted unless the process is run with `HEAPLENS_ENABLE` set (any'''),
    ...text('The commit also records a trap on the way: the first '
        'implementation cached the environment lookup in a '
        'OnceLock, whose initialiser allocates, and that deadlocked '
        'the very first allocation any such process ever made, '
        'before main(). A plain atomic cache, which at worst '
        'recomputes the same value, replaced it.'),

    ...sec('inferring ownership: φ'),
    ...text('Given a new allocation and its call stack, which '
        'live allocation owns it? The answer HeapLens settled on '
        'is the live node whose allocating function appears '
        'above the new one on the stack, most recent first. The '
        'search set is the names of the caller frames, with the '
        'new node’s own frame and the instrumentation machinery '
        'excluded:'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · infer_ownership (trimmed)', r'''
        let search_set: HashSet<String> = new_stack[own_idx + 1..len]
            .iter()
            .copied()
            .filter(|&a| a != 0 && !resolver.is_machinery(a))
            .map(|a| resolver.name_for(a))
            .collect();'''),
    ...text('Candidates are narrowed through an index by name, '
        'and ties go to the newest:'),
    ...code('rust', 'crates/heaplens-daemon/src/graph.rs · the tie-break', r'''
                let key = (node.ts, node.id);
                if best.map_or(true, |b| key > b) {'''),
    ...text('The history of this function is a compact history of '
        'the project’s lessons. The first version matched exact '
        'addresses and produced zero edges on a real binary, '
        'because two allocation statements in one function have '
        'different addresses. Matching moved to function names on '
        '2026-07-08, in a commit (43fc22e) that fixed four layered '
        'bugs at once: stack capture widened to 16 frames, the '
        'previously discarded symbol frames wired into the '
        'resolver, name-level matching with a recency tie-break, '
        'and shim classification for consumer-namespaced allocator '
        'symbols. A later change replaced a full scan of every '
        'node with two indexes; its commit message reports the '
        'per-call cost of inference falling about twelve-fold, from '
        '13.5 to 1.1 microseconds.'),
    ...text('The tie-break is only recency: greatest timestamp, '
        'then greatest id. The Build Spec states that there is no '
        'thread id and no call/return bracketing, and it says what '
        'that buys and what it costs. Eight owners of the same '
        'function, each followed by ten children, are partitioned '
        'correctly (phi_k_invocations_of_same_function_partition_by_'
        'recency_when_sequential). The failure case has a test with '
        'an honest name, and a comment that says the design cannot '
        'do better:'),
    ...code('rust', 'crates/heaplens-daemon/tests/graph_unit.rs · the documented failure mode (trimmed)', r'''
// The documented failure mode: a child logically belonging to an EARLIER
// owner, but allocated AFTER a newer same-name owner already exists (e.g.
// two overlapping/concurrent calls to the same function — the jury's "two
// threads both in make_family" question), gets attributed to the newer
// owner. Recency has no notion of "which owner's dynamic extent this
// allocation falls within" — only "which same-named node was most recently
// allocated." This is the accepted cost of function-granularity + recency
// tie-break, not a bug; the K-invocation test above shows it's the exception,
// not the common case, for the access pattern this project's producers use.
#[test]
fn phi_recency_discriminator_misattributes_late_child_to_newer_same_name_owner() {'''),
    ...text('The limitation did bite the project’s own demos, three '
        'times. On 2026-07-19 commits 05790cc and 586a6c4 fixed '
        'demo_producer and hot_producer: the Vec holding the '
        'children was allocated at the same call site as the owner '
        'and, being newer, won the tie-break, so every child '
        'attached to the container and the owner-freed transition '
        'the demo exists to show never happened. The same day '
        'checkout_service’s first version found no owner at all, '
        'because its manager and its helper were both called from '
        'main but neither from the other. And on 2026-07-28 '
        'commit d192626 explained why the hot-cluster phase never '
        'turned amber: a Vec that grew inside the owner’s own '
        'function reallocated after the owner was allocated, became '
        'the newest same-site candidate, and took the second batch '
        'of children, splitting 40 children roughly 10 and 30 '
        'between two nodes while the console correctly said “40 '
        'orders and still growing”. Neither node crossed the '
        'threshold of 32. The cure in every case was to allocate '
        'the children’s storage first and the owner second.'),

    ...sec('what counts as a problem'),
    ...text('Three detectors, all configurable. The Build Spec files '
        'them under heuristics and says the thresholds are '
        'empirically chosen, not derived:'),
    ...code('rust', 'crates/heaplens-daemon/src/anomaly.rs · sweep() (trimmed)', r'''
        let is_orphan = node.owner.is_none()
            && node.had_owner_once
            && max_ts_seen.saturating_sub(node.ts) > config.tau_ms * 1_000_000;'''),
    ...bullet('orphan',
        'owner freed and node age beyond tau (default 5 s). The '
        'age is the node’s own: the newest producer timestamp '
        'minus the timestamp of the node’s allocation, never a '
        'wall clock, so the verdict does not depend on when the '
        'daemon happens to run. A long-lived child whose owner is '
        'freed is therefore an orphan at the next sweep. The spec '
        'adds that tau was chosen so the coral treatment is '
        'visible to a human in a demo, not as a measure of '
        'detection speed. The H1 commit defines orphan as a '
        'conjunction of the two conditions.'),
    ...bullet('hot cluster',
        'a node with more than 32 children (default). Orphan wins '
        'when both match, and a node whose cluster shrinks back '
        'under the threshold returns to healthy on the next sweep '
        '(commit 338abef).'),
    ...bullet('storm',
        'more than 1,000 allocations within a 1-second window at '
        'one site (defaults). It logs at most one warning per site '
        'per tick and sets no node state. The key is the first raw frame of '
        'each allocation, stack[0]; capture.rs says raw traces '
        'start inside the shared instrumentation chain, which '
        'suggests the key is shared by many call sites. That is an '
        'inference from the comments, not something observed.'),
    blank,
    ...text('The UI turns these into three plain-language '
        'findings: a probable leak, grouped by call site and '
        'worded without hedging; a growing cluster, worded as a '
        'suggestion; and a dominant consumer, an observation with '
        'a 20 percent threshold that the code calls “empirically '
        'chosen”. The wording is graded on purpose: the source '
        'comments describe the first as high confidence, the second '
        'as a structural signal and not a certainty, and the third '
        'as informational. The rules live in insight_rules.dart and '
        'only read the state the daemon computed.'),

    ...sec('attaching to programs you did not write'),
    ...text('The second capture mode loads heaplens_hook.dll '
        'into a running process. The design for it was written '
        'on 2026-07-13 (docs/stage7-injection-design.md, four '
        'commits that day) and then corrected by the first code '
        'that tried it. Its decisions: inline hooks on ntdll’s '
        'heap functions and not the import table, which would '
        'silently undercount calls through static CRTs and '
        'function pointers; a private heap for the hook’s own '
        'memory; and eager initialisation of the writer thread and '
        'of symbol resolution before any hook goes live. The '
        'document records its own corrections: the first draft '
        'hooked kernelbase’s HeapAlloc, which crashed on the first '
        'call even though MinHook reported success, and the same '
        'code hooking GetTickCount worked, which ruled out a usage '
        'mistake and moved the hooks down to ntdll.'),
    ...text('The refusal logic is younger than the design. The '
        'document validates architecture, access rights and a '
        'still-running target, but the protection-level check, the '
        'module fingerprint and the denylist in safety.rs landed '
        'on 2026-07-22, in the commit that re-enabled the Attach '
        'button. The module’s stated constraint is that it runs, '
        'and can refuse, before the injector asks Windows for '
        'thread-creation or memory-write rights on the target, and '
        'attach() calls it first, with no override flag. It fails '
        'closed:'),
    ...code('rust', 'crates/heaplens-injector/src/safety.rs · check (trimmed)', r'''
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
    ...code('rust', 'crates/heaplens-injector/src/safety.rs · check_protection_level (trimmed)', r'''
    let handle = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid) };
    if handle.is_null() {
        // Can't query — most likely a protected/elevated process this tool
        ...
        // signal this check exists to catch. Fail closed: refuse rather
        // than silently skip the check.'''),
    ...text('A process the tool cannot even query is treated as '
        'excluded. Protection level, loaded vendor modules and a '
        'name denylist are three independent vetoes, and the '
        'weakest, the denylist, is described in the source as '
        'trivially spoofable and incomplete by construction.'),
    ...text('The Attach button in the UI is the project’s '
        'barometer, and its flips are all in the log.'),
    ...bullet('2026-07-21 22:21, disabled (823dac7)',
        'a self-contained stress harness showed the hook crashing '
        'every run under heavy multi-threaded allocation, while '
        'the identical unhooked workload completed hundreds of '
        'millions of allocate and free cycles. The investigation '
        'had started from a Windows DPC_WATCHDOG_VIOLATION '
        'bugcheck on the machine that ran an injected target; a '
        'live process had crashed inside heaplens_hook.dll '
        'minutes earlier. The button stayed visible with a '
        'tooltip giving the reason, on purpose.'),
    ...bullet('2026-07-21 23:12, root cause (dcc76f2)',
        'the hook is always loaded with LoadLibraryW, and rustc’s '
        'thread_local! on this target can use a static TLS slot '
        'that the loader only wires up for the loading thread, so '
        'every other thread crashed on its first access. Giving '
        'the value a Drop impl, the first guess, changed nothing, '
        'and guard.rs still warns against trying it again. The '
        'fix was raw TlsAlloc in guard.rs and FlsAlloc in ring.rs, '
        '20 clean runs of the 48-thread, 8-second harness against '
        'a baseline that crashed every time. The commit also '
        'notes that the original acceptance gate, '
        'hook_self_load_wire.rs, never exercised the path: its '
        'whole workload ran on the thread that loaded the DLL. A '
        'new test allocates only on spawned threads.'),
    ...bullet('2026-07-22 11:14, re-enabled (864167e)',
        'after the daemon fixes of that night, a soak of about '
        '2 hours 10 minutes against a Node.js process, clean '
        'attach and detach on a native Win32 program, an '
        'Electron program and a Node.js program, and a refusal '
        'against Windows Defender whose reason appeared in the '
        'dialog.'),
    ...bullet('2026-07-26 02:42, disabled again (306e8fc)',
        'a target that exits with the hook still installed '
        'crashed reliably, per an investigation on a separate '
        'branch. Re-verifying on master 30 minutes later (deff3ad) '
        'found that crash already gone, which the commit '
        'attributes to the TLS fix, '
        'and a worse defect: multi-threaded targets hung 40 to 60 '
        'percent of the time on exit, and the hung processes '
        'resisted Stop-Process and taskkill. The cause was the '
        'orphaned lock described in the hot path section.'),
    ...bullet('2026-07-28 02:38, re-enabled (9693399)',
        'in a one-line commit about the terminal demo. The '
        'evidence for this flip is in the commits before it; the '
        'commit itself carries none.'),
    blank,
    ...text('Detach has its own constraint, recorded in the '
        'injector source: creating a second remote thread inside '
        'a hooked target triggers a crash during thread attach, '
        'so detach queues an APC onto the worker thread that the '
        'hook already runs and reads the result back through '
        'ReadProcessMemory. The design document still describes '
        'the second remote thread.'),

    ...sec('four commits in two hours: profiling the daemon'),
    ...text('Attach was re-enabled only after the daemon survived '
        'sustained load, and the log of 2026-07-22 between 02:13 and '
        '03:56 reads as a profiling notebook. Each commit message '
        'names the measurement that justified the next step.'),
    ...bullet('4e8868f, 02:13, evict dead nodes',
        'on_dealloc never removed a node from the map, so every '
        'allocation ever seen stayed in memory and every new '
        'allocation scanned all of them. On a balanced workload '
        'the daemon held 102,225 nodes with 7 live, and fell 49 '
        'seconds behind its own event stream. The fix evicts in '
        'drain_diff, after the diff is built, and its test checks '
        'the node count and the diff at each of four ticks, so '
        'eviction cannot be both safe and too early.'),
    ...bullet('fa3fe78, 02:41, cap the drain',
        'under 12-thread load a lagging writer drained every ring '
        'to empty in one call, exceeded the wire format’s 65,535 '
        'event count, and panicked; a panicked writer never '
        'acknowledges a stop request, which broke detach. The '
        'drain now takes a maximum, and the encoders return None '
        'instead of panicking. The test that then failed turned '
        'out to be wrong, not φ: it recorded each node’s last '
        'edge list, which for a producer that frees everything is '
        'the torn-down state, so it now records the peak.'),
    ...bullet('783b2d3, 03:39, two reverse indexes',
        'profiling put on_alloc and on_dealloc at about 98 percent '
        'of graph-task time. An owner-to-children index and a '
        'site-name-to-nodes index replaced the scans: inference '
        'fell from 13.5 to 1.1 microseconds per call and '
        'throughput rose from about 61 thousand to 330 to 440 '
        'thousand events a second. The commit says plainly that '
        'memory still rose under load and was “not chased down '
        'further here”.'),
    ...bullet('97576bc, 03:56, a Vec became a HashSet',
        'the next profile found that removing one dying node from '
        'a popular bucket with Vec::retain took 63 to 65 percent of '
        'all graph-task time, because a few call sites hold huge '
        'numbers of nodes. A HashSet made the removal O(1). '
        'Throughput reached about 1.0 to 1.1 million events a '
        'second, peak memory stayed under about 400 MB (against '
        'about 8.9 GB before the night’s fixes), and memory and '
        'queue depth returned to baseline within seconds of '
        'detach.'),
    blank,
    ...text('The shape is the lesson: fix the defect you can '
        'prove, re-measure, and write down what is still not fixed. '
        'graph.rs keeps the reasoning in its doc comments, including '
        'why site_index defers removal to the same point as the node '
        'map itself.'),

    ...sec('shipping it as one program'),
    ...text('A user should not start a daemon, then an app, then '
        'remember to stop both. The launcher does it, and it '
        'guarantees cleanup by delegating it to the operating '
        'system instead of to its own code:'),
    ...code('rust', 'crates/heaplens-launcher/src/main.rs · create_kill_on_close_job (trimmed)', r'''
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;'''),
    ...text('The daemon and the app are both assigned to a Job '
        'Object that kills its members when the launcher’s last '
        'handle closes: on a clean exit, a crash or a kill. On the '
        'normal path the launcher also stops the daemon by hand; '
        'the Job Object covers the paths where that code never '
        'runs. The packaged build has a rule that is easy to miss: '
        'each executable must ship beside its .pdb file. On '
        '2026-07-19 a packaged release build resolved every '
        'allocation site to the same wrong address, so φ found no '
        'edges and nothing ever turned hot or orphaned. The fix '
        'commit (9c4678e) reports 3 of 3 runs resolving correctly '
        'with the .exe and .pdb together and 3 of 3 collapsing '
        'without the .pdb, and puts the requirement in a doc '
        'comment on writer::run so the next packaging step does '
        'not drop the file again.'),

    ...sec('how it was built'),
    ...text('The method is visible in docs/. Four of the five plans '
        'were committed before the code they describe: a task list '
        'with the files to touch, the code, the command that '
        'proves each step and the commit message to use. The '
        'exception is the daemon M4 plan: its header is dated '
        '2026-07-02 and names base commit 489b5ef, but git first '
        'sees the file on 2026-07-08, six days after the code, so '
        'the history cannot show it coming first. The stages, by '
        'commit time (all times +03:00):'),
    ...bullet('protocol, 2026-06-24 21:17 to 21:44',
        '16 commits in 27 minutes; the plan and the design spec '
        'are in the first one. Eleven of the plan’s twelve commit '
        'messages appear verbatim in the log. The test written to '
        'pin the resync rule was committed together with a '
        'stricter decoder than the spec described.'),
    ...bullet('allocator, 2026-07-01 15:25 to 16:21',
        'the plan, then 14 commits. A second drain pass for a dead '
        'producer’s ring, so no events are lost, was added five '
        'minutes after the ring was written.'),
    ...bullet('daemon M3, 2026-07-01 17:04 to 17:36',
        'the plan, then 11 commits. The cross-process wire test '
        'followed at 00:42 and a post-implementation section was '
        'added to the plan 11 minutes later: three bugs, a '
        'constraint on drain timing, and the wire test as proof.'),
    ...bullet('daemon M4, 2026-07-02 07:34 to 08:33',
        'anomalies, SQLite and the WebSocket server in 13 '
        'commits, merged on 2026-07-06.'),
    ...bullet('Flutter M5, 2026-07-06 20:28 to 23:08',
        'scaffold and plan, then 19 commits. A live run found a '
        'launch crash that a green test suite could not see: every '
        'test replaced the stream provider with a fake, so none '
        'ran the real start-up path (1179bf1).'),
    blank,
    ...text('The spec says in its first lines that its audience is '
        'an autonomous coding agent. The repository does not '
        'record who typed what. What the '
        'documents do show is a specification that fixes the '
        'seams and the invariants, plans whose decisions are '
        'marked as locked, and commit messages that keep '
        'verifying against the running system (“confirmed live”, '
        '“verified live”). That may be why the documents are '
        'unusually explicit: they were the interface to the '
        'executor.'),

    ...sec('timeline'),
    ...bullet('2026-06-24',
        'workspace, protocol crate, build spec, UML, first plan '
        'and design spec.'),
    ...bullet('2026-07-01',
        'allocator and daemon ingest + graph in one afternoon.'),
    ...bullet('2026-07-02',
        'cross-process wire test over a real pipe; anomaly '
        'detection, SQLite and the WebSocket server.'),
    ...bullet('2026-07-06 and 07',
        'the Flutter app in an evening; the blank-canvas '
        'investigation, a debug overlay, a demo producer and a '
        'regression test that asserts the painter paints.'),
    ...bullet('2026-07-08',
        'φ reworked to function names, the launcher, '
        '[profile.release] debug = true, the first .gitignore.'),
    ...bullet('2026-07-13',
        'the Stage 7 design in four commits, then the hook DLL’s '
        'first step, whose acceptance gate matches 50 allocations, '
        '11 reallocations and 51 frees by pointer identity and '
        'requires zero captured events after detach.'),
    ...bullet('2026-07-16 to 17',
        'the H1 latency harness and results; a target-status '
        'banner so a blank graph explains itself.'),
    ...bullet('2026-07-19',
        'UI refresh, the control channel and process picker, the '
        'chaos scenarios, the checkout_service demo, and the PDB '
        'finding.'),
    ...bullet('2026-07-21 to 22',
        'attach gated, the thread-local crash found and fixed; a '
        'chain of four daemon and writer fixes; attach re-enabled '
        'with a safety check.'),
    ...bullet('2026-07-26',
        'attach re-gated for an exit-without-detach crash; '
        're-verification finds the crash gone and a hang instead; '
        'the try_lock fix.'),
    ...bullet('2026-07-28',
        'cooperative capture made opt-in; trampoline frames '
        'classified as machinery; a hot-cluster ordering fix; '
        'a terminal demo front-end; attach re-enabled for the '
        'soutenance (the commit’s own word).'),

    ...sec('key numbers'),
    ...bullet('168 bytes', 'per captured event (16 frames of stack).'),
    ...bullet('65,536 slots', 'per thread ring, 65,535 usable.'),
    ...bullet('64 events or 1 ms', 'batch flush rule on the writer.'),
    ...bullet('33 ms', 'daemon tick and diff cadence.'),
    ...bullet('5 s, 32, 1,000 per second',
        'default orphan age, hot fan-out and storm rate.'),
    ...bullet('500 nodes', 'the UI switches to one aggregate per '
        'symbol above this, back below 450.'),
    ...bullet('0.0089 ms and 2.57 ms',
        'median H1 detection latency, tau of 5 ms and 500 ms, 20 '
        'runs each, 0 failures. Logical time, conditional on the '
        'workload’s 20 ms allocation heartbeat; two tau = 5 ms '
        'runs took about 20 ms, one heartbeat.'),
    ...bullet('~61 thousand to ~1.0 million events a second',
        'daemon processing rate before and after the profiling-'
        'driven fixes, per the commit messages of 2026-07-22.'),
    ...bullet('~8.9 GB to under 400 MB',
        'peak memory under the same 12-thread load, returning to '
        'a ~39 MB baseline after detach.'),
    ...bullet('13,034 lines of Rust, 9,155 of Dart',
        'including tests and examples. About 6,800 lines of '
        'Markdown documents.'),

    ...sec('building and running'),
    ...text('Assembled from the plans, the harness and the '
        'launcher source and have not been run for this page. '
        'Windows is required.'),
    ...bullet('workspace',
        'cargo build --release, then cargo test --workspace. '
        'Release builds carry debug info on purpose; keep each '
        '.pdb beside its .exe.'),
    ...bullet('daemon',
        'cargo run -p heaplens-daemon. It listens on the pipe '
        '\\\\.\\pipe\\heaplens and ws://127.0.0.1:9999 and writes '
        'heaplens.db in the working directory. Every setting has '
        'a HEAPLENS_* environment override (pipe, tick, tau, hot '
        'threshold, storm rate and window, WebSocket address, '
        'database path).'),
    ...bullet('a program to watch',
        'set HEAPLENS_ENABLE to any value, then cargo run '
        '--example demo_producer -p heaplens-alloc. It holds an '
        'owner and twenty children for sixty seconds, frees the '
        'owner, and the children turn coral.'),
    ...bullet('the app',
        'from heaplens_flutter, flutter run -d windows. In a '
        'packaged folder, HeapLens.exe starts the daemon and the '
        'app together.'),
    ...bullet('the measurement',
        'build the daemon and the chaos_orphan example in '
        'release, then run the h1-harness binary from the '
        'repository root. It expects the executables under '
        'target/release.'),

    ...sec('what this repository teaches'),
    ...bullet('prefer the failure you can see',
        'import-table hooking rejected because it silently '
        'undercounts; the injector refuses what it cannot query.'),
    ...bullet('run the control experiment',
        'the kernelbase hook looked like a usage error until the '
        'same code worked on GetTickCount.'),
    ...bullet('make the limitation a test',
        'φ’s misattribution has a test that names it.'),
    ...bullet('a green suite is not a running system',
        'the launch crash hid behind tests that all replaced the '
        'stream provider with a fake. The blank canvas turned out '
        'to be a producer that lived two seconds, but 77 passing '
        'tests had asserted nothing about painting, so a test '
        'using flutter_test’s paints matcher was added and checked '
        'by commenting out the draw call.'),
    ...bullet('write the invariants first',
        'the ten invariants of Build Spec section 12 were written '
        'before any code, and the source cites them by number '
        '(ring.rs: “invariant §12.5”). The history shows one that '
        'was broken and repaired: the dbghelp lock.'),
    ...bullet('keep the instrument passive',
        'the orphan timestamps are recorded by code the comment '
        'swears cannot feed back into detection.'),
    ...bullet('initialise before you hook',
        'every first-time, heavyweight setup runs before the '
        'first hook is live; a warm test cannot show a cold bug.'),
    ...bullet('gate, and re-gate, honestly',
        'the Attach button was turned off twice, each time with '
        'a commit explaining what was found.'),

    ...sec('honest limits'),
    ...bullet('platform and scope',
        'Windows x86-64 only; one target at a time; 32-bit '
        'processes are refused.'),
    ...bullet('φ is a heuristic',
        'a late child can be attributed to a newer owner with '
        'the same function name; without debug info the graph '
        'degrades toward isolated roots, and the tool says so.'),
    ...bullet('the injected view starts at attach',
        'allocations made earlier are invisible, and frees of '
        'unknown pointers are dropped.'),
    ...bullet('benchmark gaps',
        'the repo holds one measurement (H1), on one workload, in '
        'logical time. There are no committed overhead numbers '
        'and no comparison with a reference tool, and the H1 '
        'harness has not been re-baselined since the example it '
        'runs changed.'),
    ...bullet('documents that are behind the code',
        'the Stage 7 design still says “not implemented”; the '
        'Build Spec still shows 104-byte events and a growth '
        'detector that was never built; config.rs calls tau an '
        'EMA constant.'),
    ...bullet('design intent not found in code',
        'the launcher-teardown detach in the Stage 7 design has '
        'no Shutdown message in the control protocol, and the '
        'launcher kills the daemon directly. A lagged WebSocket '
        'client is kept, not disconnected, though the Flutter '
        'plan assumes otherwise.'),
    ...bullet('housekeeping',
        'demo-only dependencies (iced, ratatui, crossterm, rand) '
        'sit in heaplens-alloc’s [dependencies], though the '
        'spec said that crate would have no tokio, and iced '
        'brings its tokio feature with it. The commit that added '
        'them (9693399) inserted 4,415 lines into Cargo.lock and '
        'removed 443. A stale “Stage 4” TODO remains in the '
        'workspace members.'),

    ...sec('what is next'),
    ...text('Taken from the repository’s own notes, not '
        'invented:'),
    ...bullet('detail surfacing (Stage 7b)',
        'always-visible node labels, arrowheads on ownership '
        'edges, a searchable list of owner-to-child pairs. '
        'Designed in §5.2 of the Stage 7 document and deliberately '
        'kept out of the injection work.'),
    ...bullet('the overhead benchmark',
        'the spec requires it to run against the shipped '
        'debug = true profile once unfrozen.'),
    ...bullet('multi-target monitoring',
        'needs a per-connection ingest model and a source '
        'discriminator in the graph; scoped out on purpose.'),
    ...bullet('the launcher’s bounded detach',
        'specified in §4.6, so that closing HeapLens does not '
        'leave a hook behind.'),
    blank,
    ...text('Where to start reading: this page, then '
        'docs/HeapLens_Build_Spec.md for intent, '
        'crates/heaplens-alloc/src/ring.rs and guard.rs for the '
        'hot path, crates/heaplens-daemon/src/graph.rs for φ, '
        'docs/stage7-injection-design.md for the hook, and '
        'docs/bench_results/h1_latency.csv for how a number '
        'should be handled.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
