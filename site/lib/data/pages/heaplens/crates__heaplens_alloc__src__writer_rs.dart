import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/src/writer.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'writer.rs — the one thread allowed to be slow'),
    cm('//', r'drain, resolve, classify, frame, send; and a machinery list that is '
              r'really a record of bugs'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'background writer thread: connects to the daemon and ships HANDSHAKE, '
              r'SYMBOLS and EVENTS frames'),
    kv('language', r'Rust (std, backtrace, heaplens-protocol)'),
    kv('size', r'410 lines: the thread loop (to line 187), the classifier (189 to 287), '
              r'tests (289 on)'),
    kv('history', r'12 commits, 2026-07-01 to 2026-07-28'),
    kv('pipe', r'\\.\pipe\heaplens, opened as a plain file; batches of up to 64 events '
              r'or 1 ms'),
    ...sec(r'why there is a separate thread at all'),
    ...para('//',
        r'Every rule on the allocation hot path is a prohibition: do not '
        r'allocate, do not lock, do not panic, do not block. Something has '
        r'to do the things those rules forbid: format strings, resolve '
        r'symbols through dbghelp, write to a pipe that might block. This '
        r'file is where all of it happens, on a thread that is not the '
        r'application’s. The Build Spec states the division of labour in '
        r'section 4.6, and gives the reason for putting symbol resolution '
        r'here and not in the daemon: addresses are only meaningful inside '
        r'the observed process, and "the daemon does no symbolization".'),
    blank,
    ...para('//',
        r'The thread is spawned lazily by lib.rs (or eagerly by the hook '
        r'DLL) and runs this module’s run() for the life of the process.'),
    ...sec(r'startup: a guard that never lets go, and a symbolizer that must be '
              r'ready'),
    ...code('rust', 'crates/heaplens-alloc/src/writer.rs · the constants', r'''
const PIPE_PATH: &str = r"\\.\pipe\heaplens";
const BATCH_CAP: usize = 64;
const FLUSH_INTERVAL: Duration = Duration::from_millis(1);
const RETRY_SLEEP: Duration = Duration::from_millis(100);
const POLL_SLEEP: Duration = Duration::from_micros(100);'''),
    ...para('//',
        r'Four numbers and a path define the thread’s tempo. A batch is at '
        r'most 64 events (BATCH_CAP). It is flushed after 1 ms '
        r'(FLUSH_INTERVAL) even if smaller, so a quiet program still '
        r'reports within a millisecond. If the daemon is not there yet, '
        r'the connect loop retries every 100 ms (RETRY_SLEEP). And when '
        r'there is nothing to do, the thread sleeps 100 microseconds '
        r'between polls (POLL_SLEEP). The first two come straight from the '
        r'Build Spec’s batching rules (64 events or 1 ms, "whichever comes '
        r'first").'),
    ...code('rust', 'crates/heaplens-alloc/src/writer.rs · the entry point and its long comment', r'''
/// The writer thread entry point. Spawned once via `WRITER_ONCE` in lib.rs.
///
/// The guard is permanently held from the top of this function so that none
/// of the writer's own allocations (HashMap, Vec, String) are recorded.
pub fn run() {
    // Invariant §12.4: writer thread permanently holds the recursion guard.
    crate::guard::force_enter_permanent();

    // Force `backtrace::resolve`'s one-time lazy setup (on Windows,
    // `dbghelp.dll` load + `SymInitialize`) to complete now, synchronously,
    // before this thread's main loop makes its first real resolve() call
    // below, for the same reason `heaplens-hook`'s injected path already
    // calls this explicitly before enabling hooks — see
    // `warm_up_symbol_resolution`'s doc comment.
    //
    // Note: local-symbol resolution (this crate's own module, and any
    // consuming binary's own code) additionally requires that binary's
    // `.pdb` file be present next to its `.exe` at runtime — `dbghelp`
    // searches the executable's own directory. This was the actual cause of
    // a symbol-collapse bug that looked like a resolution race (every
    // address resolving to the same address or an unrelated symbol, system-
    // DLL exports like `BaseThreadInitThunk` unaffected since those don't
    // need a local `.pdb`): a packaged release build had shipped `.exe`
    // files without their matching `.pdb`s. Any packaging step for a
    // release build must ship both.
    crate::warm_up_symbol_resolution();'''),
    ...para('//',
        r'The first statement is force_enter_permanent(), which makes the '
        r'writer’s own allocations (its HashMap, its Vecs, the strings it '
        r'formats) invisible to record() for the rest of the thread’s '
        r'life. That is invariant 4 of the spec, and without it the writer '
        r'would record its own work and feed itself.'),
    blank,
    ...para('//',
        r'The second is warm_up_symbol_resolution(), and the comment '
        r'attached to it is a debugging story in its own right. On '
        r'2026-07-19 (commit 9c4678e) the project hit a bug in release '
        r'builds where every allocation’s effective site resolved to the '
        r'same wrong address, so ownership inference found no edges and '
        r'the Hot and Orphan states never fired. It looked like a race in '
        r'symbol resolution. It was packaging: dbghelp finds a program’s '
        r'own symbols only when the matching .pdb sits next to the .exe, '
        r'and a packaged build had shipped executables without them. '
        r'System DLL exports such as BaseThreadInitThunk still resolved, '
        r'which is what made the symptom look like a resolution race '
        r'instead of a missing file. The comment ends with the requirement '
        r'for whoever packages the next release: "Any packaging step for a '
        r'release build must ship both." The commit verified it the blunt '
        r'way: three clean runs from a layout with the exe and pdb '
        r'together, and three collapsed runs of the identical binary '
        r'without the pdb.'),
    ...sec(r'connecting without ever failing the host'),
    ...code('rust', 'crates/heaplens-alloc/src/writer.rs · connect and handshake', r'''
loop {
    if crate::writer_should_stop() {
        crate::mark_writer_stopped();
        return;
    }
    symbol_cache.clear();

    // ── Connect ─────────────────────────────────────────────────────────
    let mut pipe = loop {
        if crate::writer_should_stop() {
            crate::mark_writer_stopped();
            return;
        }
        match OpenOptions::new().read(true).write(true).open(PIPE_PATH) {
            Ok(f) => break BufWriter::new(f),
            Err(_) => thread::sleep(RETRY_SLEEP),
        }
    };

    // ── Handshake ────────────────────────────────────────────────────────
    let pid = std::process::id() as u64;
    let name = process_name();
    let handshake = encode_handshake(pid, &name);
    if pipe.write_all(&handshake).is_err() || pipe.flush().is_err() {
        continue; // reconnect
    }'''),
    ...para('//',
        r'The pipe is opened with '
        r'OpenOptions::new().read(true).write(true).open(PIPE_PATH). A '
        r'Windows named pipe can be opened like a file, which is why the '
        r'crate needs no pipe-specific API; the original plan listed '
        r'windows-sys features for pipes, and commit ba1a066 removed that '
        r'dependency as unused. If the open fails (no daemon yet), the '
        r'thread sleeps 100 ms and tries again, and both loops check the '
        r'stop flag first so the thread can be asked to leave. The host '
        r'program is not slowed by a missing daemon, and alloc_smoke.rs '
        r'exists to prove it: "run with no daemon ... The host process '
        r'must not crash, hang, or abort."'),
    blank,
    ...para('//',
        r'symbol_cache.clear() sits at the top of the outer loop, so after '
        r'a reconnect every address is re-resolved and re-sent. It was '
        r'added in commit 29b1458, as a one-line fix right after the first '
        r'version: a new daemon session starts with an empty resolver, so '
        r'a cache that remembered "already sent" would leave it with '
        r'addresses it can never name. The comment at the bottom of the '
        r'function was updated in 051fde5 to match.'),
    blank,
    ...para('//',
        r'The first frame is always the handshake: the process id and the '
        r'executable’s file stem (process_name() is '
        r'current_exe().file_stem()). If writing it fails, the loop '
        r'continues to reconnect. This frame is what the daemon later used '
        r'to know which process a session belongs to; for a long time the '
        r'daemon decoded it and threw it away.'),
    ...sec(r'the event loop'),
    ...code('rust', 'crates/heaplens-alloc/src/writer.rs · drain and decide when to flush', r'''
let mut batch: Vec<AllocEvent> = Vec::with_capacity(BATCH_CAP);
let mut new_syms: Vec<(u64, String, bool)> = Vec::new();
let mut last_flush = Instant::now();

'send: loop {
    // Drain all rings into batch — capped at the *remaining* room in
    // this batch, never unconditionally. An uncapped drain here is
    // exactly what let a producer backlog under sustained load blow
    // past both the intended BATCH_CAP and the wire protocol's own
    // u16 event-count field, panicking the writer thread — see
    // `ring::drain_all`'s doc comment for the full mechanism.
    let remaining = BATCH_CAP.saturating_sub(batch.len());
    crate::ring::drain_all(remaining, |ev| batch.push(ev));

    let should_flush =
        batch.len() >= BATCH_CAP || last_flush.elapsed() >= FLUSH_INTERVAL;

    if should_flush && !batch.is_empty() {
        // Resolve new instruction pointers (off critical path).'''),
    ...para('//',
        r'Each iteration drains the rings into batch, capped at the '
        r'batch’s remaining room, and then decides whether to flush: '
        r'because the batch is full, or because a millisecond has passed '
        r'since the last flush. The cap argument is the 2026-07-22 fix '
        r'described on the ring.rs page: before it, the call was uncapped, '
        r'a backlog could produce a batch larger than the wire protocol’s '
        r'u16 count field, and the writer panicked. The comment in this '
        r'file is explicit about the connection: "An uncapped drain here '
        r'is exactly what let a producer backlog under sustained load blow '
        r'past both the intended BATCH_CAP and the wire protocol’s own u16 '
        r'event-count field".'),
    ...code('rust', 'crates/heaplens-alloc/src/writer.rs · resolving only what is new', r'''
for ev in &batch {
    for i in 0..ev.stack_len as usize {
        let addr = ev.stack[i];
        if addr == 0 || symbol_cache.contains_key(&addr) {
            continue;
        }
        let mut name = format!("0x{addr:x}");
        {
            // See `crate::DBGHELP_LOCK`'s doc comment —
            // required to avoid racing capture_stack's own
            // trace_unsynchronized calls on allocating
            // threads, not just defensive.
            let _guard = crate::DBGHELP_LOCK.lock().unwrap_or_else(|e| e.into_inner());
            backtrace::resolve(addr as *mut _, |sym| {
                if let Some(n) = sym.name() {
                    name = n.to_string();
                }
            });
        }
        let is_machinery = is_machinery_symbol(&name);
        symbol_cache.insert(addr, name.clone());
        new_syms.push((addr, name, is_machinery));
    }
}'''),
    ...para('//',
        r'For every event in the batch, for every stack address, the '
        r'writer skips addresses it has already resolved (a HashMap<u64, '
        r'String>), and resolves the rest. The default name is the hex '
        r'address itself, format!("0x{addr:x}"), and it is overwritten '
        r'only if backtrace::resolve finds a name. That hex fallback is '
        r'the contract with the daemon: an unresolved frame is never an '
        r'error, only a name that happens to look like an address, and the '
        r'daemon counts these (the hex_fallback counter in the Stats '
        r'message).'),
    blank,
    ...para('//',
        r'Resolution happens under DBGHELP_LOCK.lock(), a blocking lock, '
        r'taken per address. The capture side takes the same lock with '
        r'try_lock (see the capture.rs page) because a blocked allocating '
        r'thread is unacceptable. The writer thread has the opposite '
        r'situation: it can afford to wait, and it holds the lock across '
        r'each backtrace::resolve call. While it holds it, every '
        r'allocating thread’s capture_stack returns an empty stack. The '
        r'new name is also run through is_machinery_symbol before it is '
        r'stored, and the flag travels with the name.'),
    ...code('rust', 'crates/heaplens-alloc/src/writer.rs · the SYMBOLS frame', r'''
// Emit SYMBOLS frame for newly-seen addresses.
if !new_syms.is_empty() {
    let refs: Vec<(u64, &str, bool)> = new_syms
        .iter()
        .map(|(a, n, m)| (*a, n.as_str(), *m))
        .collect();
    match encode_symbols(&refs) {
        Some(frame) => {
            if pipe.write_all(&frame).is_err() {
                new_syms.clear();
                batch.clear();
                break 'send; // reconnect
            }
        }
        None => {
            // Defense in depth — should be structurally
            // unreachable now that drain_all caps what a
            // batch (and therefore new_syms, bounded by it)
            // can ever accumulate; see its doc comment. Drop
            // rather than panic: a lost SYMBOLS frame just
            // means those addresses get re-resolved and
            // re-sent on a later batch (symbol_cache is
            // additive, never assumes a name arrives exactly
            // once) — far preferable to killing this thread,
            // which is exactly what broke clean detach here.
            eprintln!(
                "heaplens-alloc writer: dropping oversized SYMBOLS batch ({} entries, exceeds u16::MAX)",
                refs.len()
            );
        }
    }
    new_syms.clear();
}'''),
    ...para('//',
        r'Newly resolved symbols are sent before the events that reference '
        r'them, in their own frame, so the daemon can resolve names the '
        r'moment it sees the events. Note the new return type of the '
        r'encoder. encode_symbols returns an Option; on Some the frame is '
        r'written, and if the write fails the thread clears its buffers '
        r'and breaks to the reconnect loop; on None (an oversized batch, '
        r'"structurally unreachable now") it logs and drops, with the '
        r'reasoning in the comment: a lost SYMBOLS frame only means those '
        r'addresses get re-resolved and re-sent on a later batch, because '
        r'the symbol cache is additive. Far better than the alternative '
        r'the comment names, killing the thread.'),
    ...code('rust', 'crates/heaplens-alloc/src/writer.rs · the EVENTS frame and the idle branch', r'''
            // Emit EVENTS frame.
            match encode_events(&batch) {
                Some(frame) => {
                    if pipe.write_all(&frame).is_err() || pipe.flush().is_err() {
                        batch.clear();
                        break 'send; // reconnect
                    }
                }
                None => {
                    // Same defense-in-depth rationale as the SYMBOLS
                    // case above — this is the exact condition that
                    // used to panic this thread under sustained
                    // 12-thread injection load (confirmed 2026-07-22).
                    // Dropping one batch's worth of capture data is a
                    // bounded, silent data-quality issue; a panicked
                    // writer thread never reaches mark_writer_stopped,
                    // which is what actually broke clean detach.
                    eprintln!(
                        "heaplens-alloc writer: dropping oversized EVENTS batch ({} events, exceeds u16::MAX)",
                        batch.len()
                    );
                }
            }

            batch.clear();
            last_flush = Instant::now();
        } else {
            if crate::writer_should_stop() {
                crate::mark_writer_stopped();
                return;
            }
            thread::sleep(POLL_SLEEP);
        }
    }
    // Fell through 'send → reconnect. symbol_cache is cleared at the top
    // of the reconnect loop so all addresses are re-resolved and re-sent.
}'''),
    ...para('//',
        r'Then the events frame, written and flushed together. A failed '
        r'write breaks out to reconnect and the batch is cleared. An '
        r'encode failure, the case that used to panic, now prints a '
        r'message and drops that one batch: "Dropping one batch’s worth of '
        r'capture data is a bounded, silent data-quality issue; a panicked '
        r'writer thread never reaches mark_writer_stopped, which is what '
        r'actually broke clean detach." The last branch is the idle path. '
        r'If no flush is due, the thread checks the stop flag and then '
        r'sleeps for POLL_SLEEP. Commit ba1a066 collapsed two separate '
        r'sleeping arms into this one else, to remove a busy spin when the '
        r'batch held a few events but was not yet due.'),
    ...sec(r'what the loop does not do'),
    ...para('//',
        r'It does not flush on shutdown. When the stop flag is seen in the '
        r'idle branch the thread marks itself stopped and returns, and up '
        r'to 63 events that are younger than a millisecond, plus whatever '
        r'remains in the rings, are not sent. It does not join on process '
        r'exit either. The chaos_storm example documents the consequence '
        r'from the other side: a program that finishes its allocation loop '
        r'in under a millisecond can exit before most of its 2,000 events '
        r'are sent, so the example sleeps 500 ms before ending, and '
        r'demo_producer, hot_producer and wire_producer all end with a '
        r'comment about waiting for the writer thread’s flush interval to '
        r'drain the ring. Capture is best-effort at the edges of a '
        r'process’s life.'),
    blank,
    ...para('//',
        r'It also polls. With nothing to do the thread wakes every 100 '
        r'microseconds. The cost was not measured, but it is a design that '
        r'spends a little CPU to keep latency to the daemon low, and the '
        r'choice of 100 microseconds is not discussed in the code.'),
    ...sec(r'the machinery list: a ledger of three bugs'),
    ...code('rust', 'crates/heaplens-alloc/src/writer.rs · the classifier’s design principle', r'''
/// Prefixes of resolved symbol names that belong to the shared allocation
/// instrumentation chain, or to the standard library's own allocation
/// plumbing, rather than genuine caller code. These are always
/// fully-qualified crate paths, so a leading-prefix match is correct.
///
/// **Design principle, not an accreted list of specific method names.**
/// The classifier's job is: given a captured frame, is this frame part of
/// the machinery *between* the allocator sink and the user's actual call
/// site, or is it the user's call site? Every function inside the `alloc`
/// crate is machinery by construction — it is the standard library's own
/// allocation implementation (`Vec`, `Box`, `String`, `raw_vec`, `slice`,
/// the `alloc`/`alloc_zeroed`/`realloc` entry points themselves), never
/// user code, regardless of which specific method is called
/// (`Vec::with_capacity` is exactly as much machinery as `vec![]`'s
/// `from_elem` path — both are frames the user's code passes *through* on
/// the way to the heap, not frames the user wrote). The bare `"alloc::"`
/// prefix (matched with the trailing `::`, never as a bare substring)
/// covers the whole crate in one rule instead of naming each container
/// type's constructor individually — the previous version of this list
/// named `alloc::vec::from_elem`/`spec_from_elem` specifically (the
/// zeroed-`vec![]` path) but missed `alloc::vec::Vec::with_capacity` (a
/// different, equally-machinery path through the same crate), which broke
/// φ's root-attribution for any container built via `Vec::with_capacity`
/// instead of `vec![]` — confirmed via `wire_producer`'s `items:
/// Vec::with_capacity(100)` resolving its own effective site to
/// `alloc::vec::Vec::<T>::with_capacity` instead of `wire_producer::main`,
/// which then could never match any child's search set (computed by the
/// same skip-machinery rule, but never containing that literal frame name
/// as an ancestor). `std::collections::` is the same principle applied to
/// `HashMap`/`BTreeMap`/`VecDeque` and friends, which wrap `alloc`
/// internally under their own `std::collections::` module path rather
/// than surfacing as `alloc::` frames directly.
///
/// A bare crate-name prefix like this is only safe because it is matched
/// with the trailing `::` against a fully-qualified path — `"alloc::"`
/// cannot match `myapp::allocate_buffer` (that starts with `"myapp::"`),
/// and `"std::collections::"` cannot match `myapp::collections::Foo`. See
/// the false-positive guard tests below; extending this list to a new
/// stdlib namespace should always add a matching guard for the nearest
/// plausible user-code collision.
const MACHINERY_PREFIXES: &[&str] = &['''),
    ...para('//',
        r'The writer attaches one bit to every symbol: is this frame '
        r'machinery, instrumentation or standard-library allocation '
        r'plumbing that sits between the allocator and the user’s code, or '
        r'is it the user’s code? The daemon takes the first non-machinery '
        r'frame of a stack as the allocation’s call site, and the whole '
        r'ownership graph is built on those call sites. A wrong bit in '
        r'either direction breaks the graph quietly: if real user code is '
        r'called machinery, the call site vanishes; if plumbing is called '
        r'user code, every allocation looks like it came from the same '
        r'standard-library function.'),
    blank,
    ...para('//',
        r'The doc comment states the rule in its second paragraph, and it '
        r'came out of a failure. The classifier "is not an accreted list '
        r'of specific method names". Every function inside the alloc crate '
        r'is machinery by construction, so one prefix rule covers the '
        r'whole crate. The earlier list named the zeroed-vec path '
        r'(alloc::vec::from_elem and spec_from_elem) and missed '
        r'Vec::with_capacity, a different path through the same crate. '
        r'That one gap meant a container built with with_capacity named '
        r'itself by a standard-library frame instead of its enclosing '
        r'function, so no child’s search could ever match it, and '
        r'ownership inference silently failed for it. The rule that '
        r'trailing :: must always be matched, never a bare substring, is '
        r'what makes the prefix safe against names such as '
        r'myapp::allocate_buffer.'),
    ...code('rust', 'crates/heaplens-alloc/src/writer.rs · MACHINERY_PREFIXES', r'''
const MACHINERY_PREFIXES: &[&str] = &[
    "heaplens_alloc::",
    // The injection trampoline crate — MinHook-detoured
    // RtlAllocateHeap/RtlReAllocateHeap/RtlFreeHeap all route through
    // heaplens_hook's own hook_heap_* functions before reaching
    // heaplens_alloc::record. Missing this prefix collapses every
    // injected allocation's effective site onto the single shared hook
    // frame (it's the nearest non-machinery-looking frame above the
    // capture pipeline for literally every hooked call), destroying all
    // ownership structure under injection specifically — confirmed via a
    // live injected run showing "Dominant consumer at
    // heaplens_hook::hook_heap_alloc" and zero inferred edges, while the
    // exact same target's cooperative-capture run resolved real business
    // logic call sites correctly. This gap was previously masked because
    // every cooperative-capable target also auto-connected cooperatively
    // regardless of injection, so the (correct) cooperative stream always
    // arrived first; it only became visible once cooperative auto-connect
    // required explicit opt-in (HEAPLENS_ENABLE) and injection became the
    // sole data source for an unopted-in target.
    "heaplens_hook::",
    "backtrace::",
    "alloc::",
    "core::alloc::",
    "core::ptr::drop_in_place",
    "std::collections::",
];'''),
    ...para('//',
        r'The list is short now, and its comments record the history. The '
        r'two bugs that shaped it:'),
    blank,
    ...para('//',
        r'Bug one, 2026-07-13. The ad-hoc list missed Vec::with_capacity. '
        r'The fix landed as commit e9c73d2 on a development branch only, '
        r'and was never carried to master. The effect, in the message of '
        r'the cherry-pick that rescued it (3460752, 2026-07-16): it left '
        r'cross_process_wire_end_to_end red on the mainline. The '
        r'repository holds the same change twice, as e9c73d2 and 1f01a15, '
        r'because it was applied on two branches. The failure had been '
        r'caught by an end-to-end test, with an assertion on root fan-out '
        r'finding "0 candidates", and then reproduced "identically with '
        r'heaplens-alloc reverted to master’s exact code, confirming it '
        r'predates this branch’s other work".'),
    blank,
    ...para('//',
        r'Bug two, 2026-07-28. The heaplens_hook:: entry. The comment is '
        r'the longest in the list because the failure it prevents was hard '
        r'to see. Under injection, every hooked allocation passes through '
        r'heaplens_hook’s trampolines before reaching record(). Without '
        r'the prefix, each allocation’s nearest non-machinery frame was '
        r'hook_heap_alloc, so every allocation in the target looked like '
        r'it came from one function, and there were no ownership edges at '
        r'all: the UI showed "Dominant consumer at '
        r'heaplens_hook::hook_heap_alloc". What made it hard to find is in '
        r'the comment: every cooperative-capable target also '
        r'auto-connected cooperatively, so the correct data arrived first '
        r'and injection’s broken classification was never the actual '
        r'source. It surfaced the day cooperative capture became opt-in '
        r'(HEAPLENS_ENABLE) and injection became the only data source for '
        r'a target that had not opted in. The commit message records the '
        r'live verification: an injected checkout_service.exe now reports '
        r'"Probable leak at '
        r'checkout_service::checkout_common::payment_gateway_pool_checkout_connections '
        r'— 12 allocations totaling 1536 bytes lost their owner" (12 '
        r'connections of 128 bytes each).'),
    ...code('rust', 'crates/heaplens-alloc/src/writer.rs · shims and the process name', r'''
/// Compiler-generated `__rust_alloc`/`__rust_dealloc`/`__rust_realloc`/
/// `__rust_no_alloc_shim_is_unstable_v2` shims — unlike the crate-internal
/// machinery above, these are namespaced under the *consuming* binary's own
/// module path (observed: `wire_producer::_::__rust_alloc`, not a bare or
/// `alloc::`-prefixed symbol), so they must be matched as a substring
/// anywhere in the name, not a prefix. Confirmed necessary empirically: a
/// prefix-only check silently misclassified these as real caller code,
/// which made every node's effective site collapse onto this shim (the same
/// failure mode as the original unfiltered-stack[0] bug, one layer out) and
/// produced zero ownership edges against the real wire_producer.exe despite
/// the function-name-matching fix being logically correct.
const MACHINERY_SHIM_SUBSTRINGS: &[&str] = &[
    "__rust_alloc",
    "__rust_dealloc",
    "__rust_realloc",
    "__rust_no_alloc_shim",
];

fn is_machinery_symbol(name: &str) -> bool {
    MACHINERY_PREFIXES.iter().any(|p| name.starts_with(p))
        || MACHINERY_SHIM_SUBSTRINGS.iter().any(|s| name.contains(s))
}

fn process_name() -> String {
    std::env::current_exe()
        .ok()
        .and_then(|p| {
            p.file_stem()
                .map(|s| s.to_string_lossy().into_owned())
        })
        .unwrap_or_else(|| "unknown".to_owned())
}'''),
    ...para('//',
        r'The third mechanism is different in kind. The __rust_alloc, '
        r'__rust_dealloc and __rust_realloc shims, plus '
        r'__rust_no_alloc_shim..., are generated by the compiler, and the '
        r'comment says that they are namespaced under the consuming '
        r'binary’s own module path: observed as '
        r'wire_producer::_::__rust_alloc. They can’t be matched by prefix, '
        r'so they are matched by substring. A prefix-only check "silently '
        r'misclassified these as real caller code", which collapsed every '
        r'node’s effective site onto the shim, the same failure as the '
        r'original unfiltered stack[0] bug, one layer out. This was commit '
        r'43fc22e (2026-07-08), the same day the stack grew from 8 to 16 '
        r'frames. Substring matching is riskier, and the tests below keep '
        r'it from over-reaching.'),
    ...sec(r'tests: guards against the opposite bug'),
    ...code('rust', 'crates/heaplens-alloc/src/writer.rs · injection trampolines and shims', r'''
fn classifies_injection_trampoline_as_machinery() {
    // Regression: confirmed via a live injected checkout_service.exe run
    // that heaplens_hook's own MinHook trampolines were NOT in
    // MACHINERY_PREFIXES — every hooked allocation's effective site
    // collapsed onto "heaplens_hook::hook_heap_alloc" (the nearest
    // non-machinery-looking frame above the capture pipeline for every
    // single hooked call), producing zero real ownership edges under
    // injection specifically, even though the exact same allocation
    // sites resolved correctly via cooperative capture. See
    // MACHINERY_PREFIXES's own doc comment for why this was previously
    // masked rather than caught earlier.
    assert!(is_machinery_symbol("heaplens_hook::hook_heap_alloc"));
    assert!(is_machinery_symbol("heaplens_hook::hook_heap_realloc"));
    assert!(is_machinery_symbol("heaplens_hook::hook_heap_free"));
    // False-positive guard: a user crate literally named "heaplens_hook_app"
    // must not collide — the check requires the trailing "::", not a bare
    // "heaplens_hook" substring.
    assert!(!is_machinery_symbol("heaplens_hook_app::main"));
}

#[test]
fn classifies_consumer_namespaced_rust_alloc_shims_as_machinery() {
    // Regression: confirmed via a real wire_producer.exe run that these
    // shims are namespaced under the *consuming* binary's own module
    // path, not under a bare or `alloc::`-prefixed symbol — a
    // prefix-only check silently missed them and made every node's
    // effective site collapse onto this shim, producing zero real
    // ownership edges end-to-end despite correct φ matching logic.
    assert!(is_machinery_symbol("wire_producer::_::__rust_alloc"));
    assert!(is_machinery_symbol("wire_producer::_::__rust_alloc_zeroed"));
    assert!(is_machinery_symbol("some_other_producer::_::__rust_dealloc"));
    assert!(is_machinery_symbol("demo_producer::_::__rust_realloc"));
    assert!(is_machinery_symbol("__rustc[8068f81614cfe5c]::__rust_no_alloc_shim_is_unstable_v2"));
}'''),
    ...para('//',
        r'The test file is mostly a list of strings. The point is not the '
        r'strings but the direction of the errors they guard. Each time '
        r'the classifier was widened, the author added the nearest '
        r'plausible user-code name that must still not match: '
        r'"heaplens_hook_app::main" next to heaplens_hook::, '
        r'"myapp::allocate_buffer", "myapp::Allocator::new" and '
        r'"myapp::reallocate_pool" next to the __rust_ shims, and '
        r'"myapp::collections::MyCollection::new" next to '
        r'std::collections::. The comment explains the stance for the shim '
        r'substrings: the check is keyed on "__rust_" plus a known '
        r'operation, never on a bare "alloc", because a .contains("alloc") '
        r'fix would reintroduce the bug in the opposite direction.'),
    ...code('rust', 'crates/heaplens-alloc/src/writer.rs · no false positives, and the next idiom is covered (long string elided) (trimmed)', r'''
#[test]
fn does_not_classify_real_caller_code_as_machinery() {
    assert!(!is_machinery_symbol("wire_producer::nested_alloc"));
    assert!(!is_machinery_symbol("wire_producer::leaf_alloc"));
    assert!(!is_machinery_symbol("wire_producer::main"));
    assert!(!is_machinery_symbol("demo_producer::make_family"));
    assert!(!is_machinery_symbol("my_crate::foo::Bar::do_work"));
    // The check is keyed on "__rust_" + known op, never on bare "alloc" —
    // a function whose NAME happens to contain "alloc" as an English word
    // must not be swallowed into machinery. This is the failure mode a
    // `.contains("alloc")` fix would reintroduce, in the opposite
    // direction from the original bug (real user frames misclassified as
    // machinery instead of the reverse).
    assert!(!is_machinery_symbol("myapp::allocate_buffer"));
    assert!(!is_machinery_symbol("myapp::Allocator::new"));
    assert!(!is_machinery_symbol("myapp::reallocate_pool"));
    // std::collections:: false-positive guard: a user module literally
    // named "collections" must not collide with the stdlib prefix —
    // the check requires the full "std::collections::" path, not a
    // bare "collections" substring.
    assert!(!is_machinery_symbol("myapp::collections::MyCollection::new"));
    assert!(!is_machinery_symbol("collections::helpers::build"));
}
...
/// Regression for the `Vec::with_capacity` bug: `MACHINERY_PREFIXES`
/// previously named `alloc::vec::from_elem`/`spec_from_elem`
/// specifically (the `vec![]` zeroed-alloc path) but missed
/// `alloc::vec::Vec::with_capacity` — an equally-machinery path through
/// the same `alloc` crate, just a different constructor. That gap made
/// any container built via `Vec::with_capacity` (rather than `vec![]`)
/// resolve its own effective site to the stdlib frame instead of the
/// user's enclosing function, breaking φ's root-attribution for it.
/// The fix widens the check to the whole `alloc` crate as one rule
/// (see `MACHINERY_PREFIXES`'s doc comment) rather than naming
/// container constructors one at a time — this test asserts several
/// stdlib allocation idioms all classify as machinery under that rule,
/// specifically so the *next* idiom (not listed here) is covered by
/// construction rather than requiring another bug report to add it.
#[test]
fn classifies_stdlib_container_constructors_as_machinery_not_just_vec_from_elem() {
...
    assert!(is_machinery_symbol("alloc::vec::Vec<u8>::from_iter<alloc::vec::IntoIter<u8>>"));
    assert!(is_machinery_symbol("alloc::boxed::Box<u8>::new"));
    assert!(is_machinery_symbol("alloc::string::String::with_capacity"));
    assert!(is_machinery_symbol(
        "std::collections::hash::map::HashMap<alloc::string::String,u32>::with_capacity"
    ));
}'''),
    ...para('//',
        r'does_not_classify_real_caller_code_as_machinery is the guard '
        r'list. '
        r'classifies_stdlib_container_constructors_as_machinery_not_just_vec_from_elem '
        r'is the regression for the with_capacity bug, and its doc comment '
        r'states the purpose beyond the case: to assert "several stdlib '
        r'allocation idioms all classify as machinery under that rule, '
        r'specifically so the next idiom (not listed here) is covered by '
        r'construction rather than requiring another bug report". All six '
        r'writer tests pass in the Linux run (these do not need Windows).'),
    ...sec(r'limits'),
    ...pt('//',
        r'string matching on demangled names',
        r'the classifier depends on how the toolchain names things. One '
        r'test contains '
        r'__rustc[8068f81614cfe5c]::__rust_no_alloc_shim_is_unstable_v2, '
        r'which has a compiler hash in it, a reminder that the names are '
        r'not a stable interface.'),
    ...pt('//',
        r'an unbounded symbol cache',
        r'symbol_cache only grows within a connection. Distinct addresses '
        r'are bounded by the program’s code, so it is not a leak in '
        r'practice, but there is no eviction.'),
    ...pt('//',
        r'events at the edges',
        r'lost at exit and at detach, as above.'),
    ...pt('//',
        r'polling',
        r'100 microsecond sleeps; unmeasured.'),
    ...pt('//',
        r'eprintln! in the thread',
        r'errors go to stderr, which a GUI target may not have.'),
    ...pt('//',
        r'one writer for the whole process',
        r'with many producer threads, one thread resolves, frames and '
        r'writes everything. The drain cap keeps batches sane but it does '
        r'not make the writer faster; a sustained overload shows up as '
        r'full rings and silent drops.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/src/writer.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/src/writer.rs'),
  ],
);
