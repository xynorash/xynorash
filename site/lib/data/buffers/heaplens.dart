import '../../models/project.dart';
import '../authoring.dart';

final Buffer heaplensBuffer = Buffer(
  id: 'heaplens',
  fileName: 'heaplens.rs',
  icon: '\u{e7a8}',
  filetype: 'rust',
  repo: 'heaplens',
  summary: 'live heap inspector · Rust + Flutter',
  fallbackStars: 0,
  fallbackPushed: '2026-07-28',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'heaplens — a live heap inspector for native Windows'),
    cm('//', 'see what your allocator sees, as it happens'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('lang', 'Rust (capture + daemon) · Dart/Flutter (UI)'),
    kv('target', 'Windows x86_64 native processes'),
    kv('shape', '7-crate Cargo workspace + Flutter desktop app'),
    kv('method', 'spec → plan → tests → code, docs in the repo'),

    ...sec('the question it answers'),
    ...para('//',
        'Most heap tools tell you how much memory a program uses. '
        'A leak is a different question: which allocation is still '
        'alive after the thing that was supposed to own it is gone? '
        'heaplens treats the heap as a graph. Nodes are live '
        'allocations, edges are “this one was allocated on behalf of '
        'that one”, and a leak is a node whose owner was freed while '
        'it stayed alive. Once you phrase it that way, leak '
        'detection becomes a graph property you can watch change in '
        'real time, instead of a number you diff after the fact.'),
    blank,
    ...para('//',
        'The design pressure is the opposite of a profiler: the '
        'observed program must barely notice it. That single '
        'constraint explains most of what follows — the lock-free '
        'ring, the separate daemon process, why symbols are '
        'resolved before they cross the pipe, and why so many '
        'decisions are written down as invariants.'),

    ...sec('architecture, and why it is split'),
    plain(r'  target process'),
    plain(r'   ↓ heaplens-alloc | -hook     (capture)'),
    plain(r'   ↓ named pipe · binary frames'),
    plain(r'   ↓ heaplens-daemon            (model)'),
    plain(r'   ↓ WebSocket · JSON diffs ~33 ms'),
    plain(r'   ↓ heaplens_flutter           (view)'),
    blank,
    ...para('//',
        'Capture runs inside the observed process; everything else '
        'runs outside it. That boundary is deliberate: graph '
        'building, symbol lookup, SQLite and WebSocket traffic can '
        'never slow or crash the program being watched, because the '
        'only thing the program does is push a fixed-size record '
        'into memory it owns. The pipe is the airlock.'),
    blank,
    ...para('//',
        'Only two contracts cross a boundary: the binary frame '
        'protocol (capture → daemon) and the JSON diff protocol '
        '(daemon → UI). Each is defined once, in heaplens-protocol, '
        'and the UI knows nothing about Rust, pointers or the '
        'daemon’s internals. When something must change between two '
        'units, the contract changes in exactly one place.'),

    ...sec('the hot path: record()'),
    ...para('//',
        'Every allocation in the program passes through one '
        'function. The rules it lives by are written as invariants '
        'in the spec: never allocate, never lock, never panic. '
        'Allocating inside the allocator recurses forever, a lock '
        'serializes every thread in the process, and a panic in '
        'alloc aborts the host. Read the order of operations with '
        'that in mind:'),
    ...code('rust', 'heaplens-alloc/src/lib.rs · record() (trimmed)', r'''
pub fn record(kind: EventKind, ptr: u64, old_ptr: u64,
              size: u64, align: u32) {
    // 1. Re-entrancy check — the very first thing.
    if guard::is_set() { return; }

    // 2. Acquire the guard (panic-safe RAII) before
    //    anything below that might itself allocate.
    let _g = guard::ScopedGuard::enter();

    // Never auto-attach: bail out unless capture was
    // explicitly started.
    if !WRITER_ONCE.is_completed()
        && !cooperative_capture_enabled() { return; }

    // 3. Timestamp (no alloc).
    let ts = capture::timestamp_nanos();
    // 4. Raw stack capture (no alloc).
    let (stack, stack_len) = capture::capture_stack();
    // 5. Construct event (no alloc).
    let ev = AllocEvent::new(kind, ptr, old_ptr, size,
                             align, ts, stack, stack_len);
    // 6. Push to per-thread ring (lock-free).
    ring::push(ev);
    // 7. Ensure the writer thread is running.
    ensure_writer();
}'''),
    ...para('//',
        'The ordering of steps 1 and 2 is not cosmetic. The '
        'opt-in check reads an environment variable, and reading '
        'an environment variable allocates on Windows. With the '
        'check placed before the guard, the very first allocation '
        'any process made re-entered record(), which re-entered '
        'the once-initialised flag while the outer call still held '
        'it — a silent deadlock before main() could print a single '
        'line. The comment in the source records that this was '
        'confirmed empirically, not guessed; the fix was to move '
        'one line, and the reason is now a paragraph so nobody '
        '“tidies” it back.'),
    blank,
    ...para('//',
        'The opt-in itself is a safety decision: a binary linked '
        'with heaplens does nothing until HEAPLENS_ENABLE is set, '
        'so the tool can never attach itself to anything by '
        'accident.'),

    ...sec('the ring buffer'),
    ...para('//',
        'Each thread owns a single-producer, single-consumer ring; '
        'the writer thread is the only consumer. SPSC is the '
        'cheapest correct design here: the producer owns the tail '
        'index, the consumer owns the head, and a pair of '
        'Acquire/Release atomics is the entire synchronization.'),
    ...code('rust', 'heaplens-alloc/src/ring.rs · push() (trimmed)', r'''
/// Producer side (hot path). Returns false if ring
/// is full (event dropped). Never allocates, never blocks.
#[inline]
pub fn push(&self, ev: AllocEvent) -> bool {
    let tail = self.tail.load(Ordering::Relaxed);
    let next = (tail + 1) & (CAP - 1);
    if next == self.head.load(Ordering::Acquire) {
        self.dropped.fetch_add(1, Ordering::Relaxed);
        return false;
    }
    // The producer owns slot[tail]; the consumer won't
    // read it until the Release store below.
    unsafe { self.slots.add(tail).write(ev) };
    self.tail.store(next, Ordering::Release);
    true
}'''),
    ...para('//',
        'Two judgement calls hide in there. First, a full ring '
        'drops the event and bumps a counter instead of waiting: '
        'losing a sample is acceptable, stalling the host '
        'application is not, and the counter keeps the loss '
        'visible rather than silent. Second, CAP is a power of '
        'two so wrap-around is a mask, not a modulo, and the '
        'backing store is requested from System directly — if it '
        'came from the global allocator the ring would record the '
        'allocation of itself.'),

    ...sec('a dead end worth keeping: thread-locals'),
    ...para('//',
        'The recursion guard started as the obvious thing — a '
        'thread_local Cell<bool>. It crashed deterministically on '
        'every thread except the one that loaded the DLL. The '
        'investigation notes in the source explain why: on '
        'x86_64-pc-windows-msvc, rustc can implement a '
        'thread_local with a real PE .tls variable reached through '
        'the segment register, and that only works if the loader '
        'registered the module’s TLS index on every thread at '
        'process start. A hook DLL loaded later with LoadLibraryW '
        'never gets that for threads it did not load on.'),
    blank,
    ...para('//',
        'The first fix attempt — give the value a Drop impl, '
        'hoping rustc would pick a different mechanism — did not '
        'work, and the source says so, with an instruction not to '
        'reintroduce it without re-verifying. The fix that held '
        'was to skip thread_local! entirely and drive the Win32 '
        'API directly, which is the documented answer for DLLs:'),
    ...code('rust', 'heaplens-alloc/src/guard.rs', r'''
static TLS_INDEX: OnceLock<u32> = OnceLock::new();

fn index() -> u32 {
    *TLS_INDEX.get_or_init(|| unsafe { TlsAlloc() })
}

/// TlsGetValue returns null for a slot never set on this
/// thread — indistinguishable from "explicitly set to
/// null", which is exactly the default we want.
pub fn is_set() -> bool {
    unsafe { !TlsGetValue(index()).is_null() }
}'''),
    ...para('//',
        'The same story repeats for the ring itself, which needs a '
        'callback when a thread dies so its ring can be marked '
        'finished. Plain TLS has no exit callback, so that slot '
        'uses Fiber Local Storage, whose FlsAlloc accepts one. '
        'Validation was not “it ran once”: the self-load '
        'concurrency stress harness had to pass ten consecutive '
        'runs.'),
    blank,
    ...para('//',
        'There is a follow-on hazard documented as well. If a '
        'thread that made a hooked allocation is still alive when '
        'the process tears down, its FLS callback points into this '
        'DLL — which may already be unmapped. So detach calls '
        'FlsFree explicitly, deregistering the callback before the '
        'code it points at can disappear. The accepted trade-off '
        'is written next to it: another still-running thread loses '
        'automatic dead-producer detection, which leaves a stale '
        'entry rather than a crash.'),

    ...sec('the wire format'),
    ...para('//',
        'The unit of transfer is one fixed-size, repr(C) record. '
        'Fixed size means the writer never formats anything on the '
        'hot path and the reader can validate a stream by '
        'arithmetic alone.'),
    ...code('rust', 'heaplens-protocol/src/event.rs (trimmed)', r'''
#[repr(C)]
pub struct AllocEvent {
    pub kind:      u8,
    pub stack_len: u8,
    pub _pad:      [u8; 2],
    pub align:     u32,
    pub ptr:       u64,
    pub old_ptr:   u64,
    pub size:      u64,
    pub ts_nanos:  u64,
    /// 16 frames (up from 8): the zeroed-allocation path
    /// inserts 6+ non-inlined std frames between the shared
    /// instrumentation and the real call site, so 8 frames
    /// can contain zero user frames.
    pub stack:     [u64; 16],
}

const _: () = assert!(
    core::mem::size_of::<AllocEvent>() == AllocEvent::SIZE);'''),
    ...para('//',
        'Padding is an explicit field so there are no hidden '
        'bytes, and the size is asserted at compile time — a '
        'layout drift is a build error, not a corrupted stream at '
        'runtime. The stack depth went from 8 to 16 after a real '
        'failure: with vec![0u8; n] the standard library puts '
        'several frames of its own between the instrumentation and '
        'your code, so an 8-frame capture could hold no user frame '
        'at all and ownership inference had nothing to match. '
        'The current record is 168 bytes.'),
    blank,
    ...para('//',
        'Frames wrap records: a length prefix, a type byte '
        '(handshake, events, symbols) and a payload. The decoder '
        'is built for the failure it will eventually meet — a '
        'stream that is truncated or corrupted mid-flight. Instead '
        'of dying, it slides forward one byte and tries again, but '
        'only accepts a header that is plausible for its type:'),
    ...code('rust', 'heaplens-protocol/src/frame.rs', r'''
if !Self::is_plausible_header(length, ftype) {
    self.buf.drain(0..1);   // resync: slide one byte
    continue;
}

// Events: length = 1(type) + 2(count) + count * SIZE
0x01 => {
    length >= 3
        && (length - 3).is_multiple_of(AllocEvent::SIZE as u32)
}'''),
    ...para('//',
        'Plausibility is what makes resync safe. Random garbage '
        'rarely produces a length that is both under the 8 MiB cap '
        'and exactly 3 + n × 168, so the decoder converges back '
        'onto the next real frame boundary. Handshake frames add a '
        'second cross-check, comparing the length field with the '
        'embedded name length. There are separate test suites for '
        'round-trip, partial reads, multiple frames and resync, '
        'because each is a different way the pipe can hand you '
        'bytes.'),

    ...sec('symbols are resolved before the pipe'),
    ...para('//',
        'Addresses mean nothing to the UI, so someone has to turn '
        'them into function names. That someone is the producer’s '
        'writer thread, once per new address, on a thread that '
        'holds the recursion guard permanently so its own work is '
        'never recorded. The daemon just joins address → name. '
        'Doing it in the producer keeps debug-symbol machinery out '
        'of the daemon, and keeps a daemon restart from losing '
        'names — and it forces serializing dbghelp, which Windows '
        'documents as not thread-safe.'),
    blank,
    ...para('//',
        'Each symbol is also tagged as “machinery” — frames that '
        'belong to the instrumentation or the standard library’s '
        'allocation internals rather than to the program. Ownership '
        'inference skips machinery to find the real call site. The '
        'prefix list is a record of bugs:'),
    ...code('rust', 'heaplens-alloc/src/writer.rs (trimmed)', r'''
const MACHINERY_PREFIXES: &[&str] = &[
    "heaplens_alloc::",
    // The injection trampoline crate. Missing this prefix
    // collapses every injected allocation's effective site
    // onto the single shared hook frame, destroying all
    // ownership structure under injection specifically.
    "heaplens_hook::",
    "backtrace::",
    "alloc::",
    "core::alloc::",
    // ...
];'''),
    ...para('//',
        'That comment is the whole debugging story: the UI showed '
        '“dominant consumer at heaplens_hook::hook_heap_alloc” and '
        'zero edges for an injected target, while the same program '
        'run cooperatively resolved real business functions. The '
        'bug had been masked for a long time because cooperative '
        'capture also auto-connected and arrived first — it only '
        'surfaced after cooperative capture became opt-in.'),

    ...sec('attaching without recompiling'),
    ...para('//',
        'A global allocator needs your source. To observe a '
        'program you cannot rebuild, heaplens-hook is a DLL that '
        'patches three functions in ntdll with inline trampoline '
        'hooks via MinHook. The three design questions each have a '
        'recorded answer:'),
    blank,
    ...pt('//', 'why inline hooks',
        'IAT hooking misses statically linked CRTs, function '
        'pointers and delay-loaded imports. On a third-party '
        'binary that would be a silent undercount — a graph with '
        'an unknown fraction of allocations missing — which is '
        'worse than an honest limit.'),
    ...pt('//', 'why ntdll, not kernelbase',
        'the first design hooked kernelbase!HeapAlloc. Hooks '
        'installed with every call reporting success, then the '
        'first allocation crashed. A control probe hooking a '
        'trivial export with the identical code worked, which '
        'ruled out misuse and isolated the fault to that '
        'function’s prologue. Hooking RtlAllocateHeap, one layer '
        'down, is stable — and also the common sink under CRT '
        'malloc, so nothing is counted twice.'),
    ...pt('//', 'why not DllMain',
        'loader-lock deadlocks. Attach and detach are explicit '
        'exported entry points.'),
    ...code('rust', 'heaplens-hook/src/lib.rs · detour (trimmed)', r'''
unsafe extern "system" fn hook_heap_alloc(
    hheap: HANDLE, dwflags: u32, dwbytes: usize,
) -> *mut c_void {
    let trampoline = ORIG_HEAP_ALLOC.load(Ordering::Acquire);
    let real: HeapAllocFn = unsafe { std::mem::transmute(trampoline) };
    let ptr = unsafe { real(hheap, dwflags, dwbytes) };
    if dwbytes == CANARY_SIZE {
        // attach-time canary: proves this detour ran.
        CANARY_HIT.store(true, Ordering::Release);
        return ptr;
    }
    if !ptr.is_null() {
        heaplens_alloc::record(EventKind::Alloc,
            ptr as u64, 0, dwbytes as u64, 0);
    }
    ptr
}'''),
    ...para('//',
        'The detour always calls the real function first and '
        'records the result second, so the host sees identical '
        'behaviour. Attach has a canary: it makes one allocation '
        'of a magic size and checks that its own detour ran, so '
        '“hooks installed” is verified rather than assumed — a '
        'direct lesson from the kernelbase episode where setup '
        'reported success and was broken.'),
    blank,
    ...para('//',
        'Ordering inside attach is the other half. Every '
        'heavyweight, first-time initialisation — the writer '
        'thread, the first symbol resolve that loads dbghelp — is '
        'forced to complete before any hook exists, because doing '
        'it lazily from inside a hook crashed: creating a thread '
        'triggers DLL_THREAD_ATTACH for every loaded module, and '
        'that notification’s own allocations re-enter a '
        'half-stable detour. The private heap used for the hook’s '
        'own bookkeeping is created first for the same reason: '
        'heaplens must not add to, or be observed in, the '
        'target’s heap.'),
    blank,
    ...para('//',
        'Detach hit the same wall from the other side. A second '
        'CreateRemoteThread to run cleanup crashed even when the '
        'function body was reduced to “return 42”, which proves '
        'the fault is the OS’s automatic thread-attach '
        'notifications, not the code. The injector therefore '
        'queues an APC onto a worker thread the hook already '
        'owns. The design doc keeps the reduction that proved it.'),

    ...sec('refusing to attach: injector safety'),
    ...para('//',
        'Injecting a DLL into the wrong process is not a bug, it '
        'is an incident. Anti-cheat drivers, VPN clients and '
        'antivirus engines treat it as hostile, and some games ban '
        'for it. So the injector checks before it opens any '
        'injection-capable handle, using three independent '
        'signals, any of which can veto:'),
    ...code('rust', 'heaplens-injector/src/safety.rs', r'''
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
    ...pt('//', 'protection level',
        'the generic one: protected-process status needs no name '
        'list, so it covers vendors nobody enumerated.'),
    ...pt('//', 'loaded modules',
        'anti-cheat and VPN products load a userspace SDK DLL '
        'that talks to their kernel driver. The driver is never in '
        'a process’s module list, but its userspace half is.'),
    ...pt('//', 'process name',
        'a plain denylist — admitted in the source to be '
        'spoofable and incomplete, so it is the last resort, not '
        'the defence.'),
    ...code('rust', 'safety.rs · fail closed (excerpt)', r'''
if handle.is_null() {
    return Some(format!(
        "cannot query process {pid}'s protection level \
         (access denied) — refusing rather than assuming \
         it is safe; a process this tool cannot even \
         query is treated as excluded"
    ));
}'''),
    ...para('//',
        'The principle is fail closed. If it cannot establish that '
        'a process is safe, the answer is no. The checks also use '
        'the weakest handle that works, so even the “no” never '
        'required elevated access to the thing being refused.'),

    ...sec('the daemon and φ: who owns what'),
    ...para('//',
        'The hardest question in the project is inferring '
        'ownership from nothing but call stacks. φ is the answer: '
        'the live allocation whose enclosing function appears in '
        'the new allocation’s stack, most recent wins.'),
    ...code('rust', 'heaplens-daemon/src/graph.rs · φ (trimmed)', r'''
let search_set: HashSet<String> = new_stack[own_idx + 1..len]
    .iter().copied()
    .filter(|&a| a != 0 && !resolver.is_machinery(a))
    .map(|a| resolver.name_for(a))
    .collect();

let mut best: Option<(u64, u64)> = None; // (ts, id)
for name in &search_set {
    let Some(ids) = self.site_index.get(name) else { continue };
    for &cid in ids {
        let Some(node) = self.nodes.get(&cid) else { continue };
        if !node.live { continue; }
        let key = (node.ts, node.id);
        if best.map_or(true, |b| key > b) { best = Some(key); }
    }
}
best.map(|(_, id)| id)'''),
    ...pt('//', 'function, not instruction',
        'two allocation statements in the same function have '
        'different addresses, so exact matching linked nothing — '
        'zero edges against a real compiled binary. Matching '
        'resolved names fixed it, at a stated price: an edge now '
        'means “allocated on a call path through the owner’s '
        'function”, not “at its exact site”.'),
    ...pt('//', 'own site excluded',
        'the search set starts after the new node’s own frame, so '
        'siblings from the same call site never claim each other.'),
    ...pt('//', 'the index',
        'this loop used to scan every node on every allocation. '
        'Profiling put roughly half of all graph-task time there '
        'under sustained load. The site index narrows candidates to '
        'the names in the search set; a pending set keeps it '
        'correct when symbols arrive late.'),
    blank,
    ...para('//',
        'The limitation is not hidden, it has a test with an '
        'honest name:'),
    ...code('rust', 'tests/graph_unit.rs (condensed)', r'''
#[test]
fn phi_recency_discriminator_misattributes_late_child_to_newer_same_name_owner() {
    // owner1, child1a (correctly owner1), then owner2 …
    g.on_alloc(&make_ev(Alloc, 0x1000, 0, 64, 100, &[owner_site]), &r);
    g.on_alloc(&make_ev(Alloc, 0x3000, 0, 64, 300, &[owner_site]), &r);

    // owner1's second child arrives after owner2 exists.
    g.on_alloc(&late_child, &r);

    assert!(owner2.edges.contains(&late.id),
        "recency tie-break attributes the late child to the \
         newer same-name owner, not its true owner");
    assert!(!owner1.edges.contains(&late.id));
}'''),
    ...para('//',
        'Recency only knows “which same-named node was allocated '
        'last”. Two threads interleaving inside one allocating '
        'function can therefore be mixed up. The spec calls φ a '
        'heuristic “by design”, the test pins the failure, and the '
        'sequential case the producers actually exercise is pinned '
        'by its sibling test. Know where a heuristic breaks, say '
        'so, and make the breakage a regression test rather than '
        'a rumour.'),

    ...sec('anomaly detection'),
    ...code('rust', 'heaplens-daemon/src/anomaly.rs', r'''
let is_orphan = node.owner.is_none()
    && node.had_owner_once
    && max_ts_seen.saturating_sub(node.ts)
        > config.tau_ms * 1_000_000;
let is_hot = node.edges_out.len() > config.hot_cluster_threshold;

let new_state = if is_orphan {
    NodeState::Orphan
} else if is_hot {
    NodeState::Hot
} else {
    NodeState::Healthy
};'''),
    ...pt('//', 'precedence',
        'every live node is re-evaluated every sweep, orphan '
        'first. Orphan is “sticky” without any frozen state: its '
        'predicate cannot become false, because age only grows. '
        'Hot is allowed to heal — if a cluster shrinks it returns '
        'to Healthy.'),
    ...pt('//', 'time source',
        'age is computed against max_ts_seen, the newest '
        'timestamp from the producer’s own monotonic clock — never '
        'wall-clock. Detection is then deterministic and '
        'replayable, and not at the mercy of scheduler jitter in '
        'the daemon.'),
    ...pt('//', 'hot',
        'fan-out above a threshold (default 32 children), a '
        'deliberately simple structural signal that is configurable '
        'and called a heuristic, not a derived constant.'),
    ...pt('//', 'tau',
        'the age window (default 5 s) before a node with a dead '
        'owner is shown as a leak. It is for human observability, '
        'not detection speed — which is why the benchmark below '
        'subtracts it.'),
    blank,
    ...para('//',
        'Storms are different: they are a rate, not a state of a '
        'node. A per-call-site deque of timestamps is trimmed to '
        'a sliding window (default 1 s) and the site is flagged '
        'when it holds more than 1000. A cleanup pass evicts sites '
        'that went idle so the map cannot grow without bound — '
        'unbounded growth in a leak detector would be the '
        'embarrassing kind.'),

    ...sec('the app'),
    ...para('//',
        'The daemon sends one snapshot on connect, then only '
        'diffs about every 33 ms, and the UI applies them to a '
        'node map. Rendering choices are about being readable '
        'when thousands of things move:'),
    ...code('dart', 'simulation/force_layout.dart', r'''
double radiusForSize(int size) {
  if (size <= 0) return kMinNodeRadius;
  final t = (math.log(size + 1) / math.ln2) /
      (math.log(kLargeSizeReference + 1) / math.ln2);
  return (kMinNodeRadius + (kMaxNodeRadius - kMinNodeRadius) * t)
      .clamp(kMinNodeRadius, kMaxNodeRadius);
}'''),
    ...para('//',
        'Radius follows the logarithm of size. A linear scale '
        'turns a 1 MiB buffer into a screen-filling disc and '
        'every small allocation into a dot; a log curve keeps '
        '“there is a big one here” visible without erasing the '
        'rest. Springs pull owners and children together, '
        'repulsion keeps unrelated nodes apart, and there is a '
        'second view — a memory map with one cell per node, '
        'ordered by address — for when topology is the wrong '
        'question.'),
    ...code('dart', 'insights/insight_rules.dart (trimmed)', r'''
const double kDominantConsumerFraction = 0.20;

final totalLiveBytes =
    live.fold<int>(0, (sum, n) => sum + n.size);
for (final n in live) {
  final fraction = n.size / totalLiveBytes;
  if (fraction >= kDominantConsumerFraction) {
    insights.add(Insight(
      id: 'dominant:${n.id}',
      severity: InsightSeverity.info,
      title: 'Dominant consumer at ${n.symbol}',
      // ...
    ));
  }
}'''),
    ...para('//',
        'The insights panel is plain, deterministic rules over '
        'data the client already holds — no model, no daemon '
        'round-trip, and never re-deriving φ. Orphans are grouped '
        'by call site, because a leak at one place is one thing to '
        'fix, not forty list rows. Wording is graded: orphans are '
        'stated plainly, a dominant consumer is an observation, '
        'because only one of those is a claim about a bug.'),

    ...sec('shipping it as one program'),
    ...para('//',
        'A user should not have to start a daemon, then an app, '
        'then remember to stop both. The launcher does it and, '
        'more interestingly, guarantees cleanup:'),
    ...code('rust', 'heaplens-launcher/src/main.rs (trimmed)', r'''
let mut info: JOBOBJECT_EXTENDED_LIMIT_INFORMATION =
    std::mem::zeroed();
info.BasicLimitInformation.LimitFlags =
    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;

SetInformationJobObject(job, JobObjectExtendedLimitInformation,
    &info as *const _ as *const core::ffi::c_void, /* … */);'''),
    ...para('//',
        'The daemon lives in a Windows Job Object that kills it '
        'when the job handle closes — which the OS does when the '
        'launcher ends for any reason, including a crash or a '
        'kill. Cleanup code in the launcher would only run on the '
        'happy path; this runs on all of them. The launcher then '
        'polls the daemon’s WebSocket port until it accepts '
        'connections (and gives up early if the daemon exits '
        'first) before opening the UI.'),

    ...sec('measuring it honestly'),
    ...para('//',
        'The benchmark harness measures orphan-detection latency '
        'from timestamps the daemon itself recorded — never from '
        'the workload’s side, never a proxy. The subtle part is '
        'the definition. An orphan needs two conditions at once '
        '(owner freed, and age past tau), so latency cannot be '
        'measured from the free alone:'),
    ...code('rust', 'h1-harness/src/main.rs', r'''
//   H1 = orphan_detected_ts_ns
//        - max(owner_free_ts_ns, node_ts_ns + tau_ms*1e6)'''),
    ...para('//',
        'Measure from whichever condition completed last, or the '
        'age window gets reported as lag it never was. Two '
        'configurations run so each condition is the binding one '
        'in turn. Over 20 runs: with tau = 5 ms, median 9 µs and '
        'worst case about 20 ms; with tau = 500 ms, median 2.6 ms '
        'after tau elapses. The occasional 20 ms outlier is the '
        'scale of a sweep tick, so that — not the median — is '
        'the honest number to quote.'),

    ...sec('testing, and what is not done'),
    ...para('//',
        '100+ Rust tests and 140+ Dart tests. Beyond unit suites: '
        'multi-thread allocator stress, cross-process wire tests '
        'over a real named pipe, and hook scenarios for each '
        'documented failure — owner freed while children live, '
        'exit without detach, self-load from a spawned thread. '
        'Fixes to the thread-local crash were accepted only after '
        'ten consecutive clean runs of the self-load stress '
        'harness.'),
    blank,
    ...pt('//', 'limits, stated',
        'one target process at a time; Windows x86_64 only; φ is '
        'a heuristic; raw hooked event streams are not 1:1 with '
        'the target’s own calls, because Windows adds its own '
        'heap traffic (so the end-to-end test matches events by '
        'pointer identity rather than by count).'),
    ...pt('//', 'in the repo',
        'docs/ has the build spec, UML, a 48 KB injection design '
        'with its dead ends, and per-milestone plans and specs.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
