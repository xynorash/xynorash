import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/src/ring.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'ring.rs — a lock-free lane from every allocating thread to one writer'),
    cm('//', r'SPSC rings, a registry, Fiber Local Storage, and a drain loop that '
              r'learned to count'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'per-thread event buffers between the hot path (producers) and the '
              r'writer thread (consumer)'),
    kv('language', r'Rust (unsafe, atomics, Win32 FLS on Windows)'),
    kv('size', r'511 lines: 364 of code and documentation, 147 of tests'),
    kv('history', r'8 commits, 2026-07-01 to 2026-07-22'),
    kv('shape', r'one Ring per thread, CAP = 65,536 slots, each slot a 168-byte '
              r'AllocEvent'),
    ...sec(r'the problem'),
    ...para('//',
        r'record() runs inside every allocation in the observed program '
        r'and has to hand an AllocEvent to the writer thread without '
        r'blocking, without allocating and without taking a lock. Anything '
        r'slower than "write a few words and move on" makes the observed '
        r'program measurably slower, which is the one thing the tool is '
        r'not allowed to do. The Build Spec’s invariants say it flatly: '
        r'the allocator never heap-allocates on the critical path '
        r'(invariant 1), never locks (2), and the ring’s backing store '
        r'comes from System directly, never the global allocator (5), '
        r'because a ring allocated through HeapLensAlloc would record the '
        r'allocation of itself.'),
    blank,
    ...para('//',
        r'The spec also admits the design question this file answers. Real '
        r'programs allocate from many threads, but a strict SPSC ring has '
        r'one producer. It lists the options, "a fixed-capacity '
        r'Michael-Scott-style" queue, or "a sharded ring per thread merged '
        r'by the writer", and names the simplest correct one for the '
        r'prototype: "one ring per thread (thread-local ring), each '
        r'drained by the writer. Document the choice. Do not use a Mutex." '
        r'That is what this file is.'),
    ...sec(r'the ring itself'),
    ...code('rust', 'crates/heaplens-alloc/src/ring.rs · Ring and Ring::new', r'''
/// Ring capacity — must be a power of two.
pub const CAP: usize = 65_536;

/// SPSC lock-free ring buffer. Backing store is allocated via `System`
/// directly (invariant §12.5). The producer owns `tail`; the consumer owns `head`.
pub struct Ring {
    slots: *mut AllocEvent,
    head: AtomicUsize,
    tail: AtomicUsize,
    pub dropped: AtomicU64,
    pub producer_alive: AtomicBool,
}

// SAFETY: The SPSC protocol guarantees that only the producer writes `tail`
// and only the consumer writes `head`. No two threads touch the same slot
// simultaneously. Raw pointer is therefore safe to send/share across threads.
unsafe impl Send for Ring {}
unsafe impl Sync for Ring {}

impl Default for Ring {
    fn default() -> Self {
        Self::new()
    }
}

impl Ring {
    pub fn new() -> Self {
        let layout = Layout::array::<AllocEvent>(CAP).expect("ring layout");
        // SAFETY: layout is non-zero. We check for null (OOM) below.
        let ptr = unsafe { System.alloc_zeroed(layout) };
        if ptr.is_null() {
            handle_alloc_error(layout);
        }
        Ring {
            slots: ptr as *mut AllocEvent,
            head: AtomicUsize::new(0),
            tail: AtomicUsize::new(0),
            dropped: AtomicU64::new(0),
            producer_alive: AtomicBool::new(true),
        }
    }'''),
    ...para('//',
        r'A Ring is a raw pointer to CAP AllocEvent slots plus four '
        r'atomics: head, tail, a dropped counter and a producer_alive '
        r'flag. The producer owns tail and writes slots; the consumer owns '
        r'head and reads them; neither ever writes the other’s index. CAP '
        r'is a power of two (65,536) so wrapping is a mask, not a '
        r'division, the arithmetic written as (tail + 1) & (CAP - 1) in '
        r'push.'),
    blank,
    ...para('//',
        r'The backing store is requested with System.alloc_zeroed(layout) '
        r'and a null result is handed to handle_alloc_error, the standard '
        r'"out of memory" path. The size is worth stating, because it '
        r'follows from the event layout: 65,536 slots of 168 bytes is '
        r'11,010,048 bytes, 10.5 MiB per allocating thread (it was 6.5 MiB '
        r'at the original 104-byte event). Twelve producer threads cost '
        r'about 126 MiB of ring. That is the price of making the hot path '
        r'a few stores, and it is not discussed in the code: the file has '
        r'no comment about it, so it is arithmetic from CAP and '
        r'AllocEvent::SIZE.'),
    blank,
    ...para('//',
        r'The unsafe impl Send and Sync for Ring carry a SAFETY comment '
        r'that states the whole protocol: only the producer writes tail '
        r'and only the consumer writes head, so no two threads touch the '
        r'same slot at the same moment.'),
    ...sec(r'push and pop'),
    ...code('rust', 'crates/heaplens-alloc/src/ring.rs · push (producer) and pop (consumer)', r'''
/// Producer side (hot path). Returns false if ring is full (event dropped).
/// Never allocates, never blocks.
#[inline]
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
}

/// Consumer side (writer thread only). Returns None when ring is empty.
pub fn pop(&self) -> Option<AllocEvent> {
    let head = self.head.load(Ordering::Relaxed);
    if head == self.tail.load(Ordering::Acquire) {
        return None;
    }
    // SAFETY: `head < CAP`; the producer wrote slot[head] before
    // advancing tail (Release), and we observed that advance (Acquire).
    let ev = unsafe { self.slots.add(head).read() };
    self.head.store((head + 1) & (CAP - 1), Ordering::Release);
    Some(ev)
}'''),
    ...para('//',
        r'This is the entire hot path of the buffer. push loads its own '
        r'tail with Relaxed ordering (nobody else writes it), computes '
        r'next, and compares it against head loaded with Acquire. If they '
        r'are equal the ring is full: it bumps dropped and returns false. '
        r'Otherwise it writes the event into slot[tail] and publishes with '
        r'tail.store(next, Release). pop is the mirror image: its own head '
        r'Relaxed, the producer’s tail Acquire, read the slot, publish '
        r'with head.store(..., Release).'),
    blank,
    ...para('//',
        r'The Acquire/Release pairs are the whole synchronisation. The '
        r'producer’s Release store of tail makes the slot write visible to '
        r'any consumer that observes the new tail with Acquire. The '
        r'consumer’s Release store of head tells the producer that the '
        r'slot is free to reuse. No compare-and-swap, no retry loop, no '
        r'fence beyond those, and no waiting: each side does a bounded '
        r'number of operations.'),
    blank,
    ...para('//',
        r'Two judgement calls are visible. First, a full ring drops the '
        r'event and returns false; push never waits. Losing a sample is '
        r'acceptable and stalling the host program is not, and the comment '
        r'says so: "Never allocates, never blocks." Second, the ring '
        r'distinguishes full from empty by keeping one slot unused, so it '
        r'holds exactly CAP - 1 events. The test '
        r'full_ring_returns_false_and_increments_dropped asserts that '
        r'count: pushed == CAP - 1.'),
    blank,
    ...para('//',
        r'The dropped counter is incremented on every loss. Reading the '
        r'repository, nothing but a unit test ever reads it. The Build '
        r'Spec calls shipping it "optional diagnostics", and it was never '
        r'built, so a producer that outruns its writer loses events '
        r'without a trace on the daemon side. A search of the whole '
        r'workspace for readers of the field finds only this file’s tests. '
        r'A scratch run shows what that silence hides (Linux, release '
        r'build, no daemon, so nothing drains): one thread doing 100,000 '
        r'iterations of vec![i as u8; 64] produces about 200,000 events '
        r'(an alloc and a dealloc each), and the drain afterwards '
        r'recovered about 65,550 of them: 65,535 from that thread’s ring '
        r'plus a handful from the main thread. Roughly two thirds were '
        r'dropped, and the program saw nothing. Re-running the same '
        r'scratch program during fact-checking gave 65,551.'),
    ...code('rust', 'crates/heaplens-alloc/src/ring.rs · Drop for Ring', r'''
impl Drop for Ring {
    fn drop(&mut self) {
        let layout = Layout::array::<AllocEvent>(CAP).expect("ring layout");
        // SAFETY: `self.slots` was allocated with this exact layout.
        unsafe { System.dealloc(self.slots as *mut u8, layout) };
    }
}'''),
    ...para('//',
        r'Drop returns the slots with the same Layout the constructor '
        r'used, through System.dealloc. Using the same allocator both ways '
        r'is the other half of invariant 5.'),
    ...sec(r'the registry'),
    ...code('rust', 'crates/heaplens-alloc/src/ring.rs · the global list of rings', r'''
// ── Registry ────────────────────────────────────────────────────────────────

/// All live rings. The writer drains these; producers register at TLS init.
/// A Mutex here is acceptable — producers never touch the registry on the
/// hot path; registration happens once per thread at first `push`.
static REGISTRY: OnceLock<Mutex<Vec<Arc<Ring>>>> = OnceLock::new();

fn registry() -> &'static Mutex<Vec<Arc<Ring>>> {
    REGISTRY.get_or_init(|| Mutex::new(Vec::new()))
}'''),
    ...para('//',
        r'Every ring is also placed in a global registry, a '
        r'Mutex<Vec<Arc<Ring>>> inside a OnceLock. The writer needs a way '
        r'to find all rings, so it must be shared. A Mutex here seems to '
        r'break the "never lock" rule, and the comment answers: "producers '
        r'never touch the registry on the hot path; registration happens '
        r'once per thread at first push". The lock is taken in two places '
        r'only: when a thread’s ring is created, and when the writer '
        r'drains.'),
    blank,
    ...para('//',
        r'There is one subtlety worth knowing. A thread’s very first '
        r'allocation under capture therefore does take that lock. Before '
        r'the 2026-07-22 change below, the writer held it for as long as a '
        r'drain took, and a drain used to run until every ring was empty, '
        r'so a freshly created thread could wait behind it. Capping the '
        r'drain also capped that hold time. That is a reading of the old '
        r'code (the loop ran until empty), not something the commit '
        r'message says.'),
    ...sec(r'per-thread storage: why Fiber Local Storage'),
    ...code('rust', 'crates/heaplens-alloc/src/ring.rs · the thread_ring module documentation', r'''
/// Per-thread ring storage, keyed by Fiber Local Storage rather than a
/// plain `thread_local!`.
///
/// # Why not `thread_local!`
///
/// This used to be exactly that — `thread_local! { static THREAD_RING:
/// RingHandle = ...; }`, with `RingHandle`'s `Drop` impl doing the
/// producer-death signalling described above. That crashed reliably
/// (confirmed via the `self_load_concurrency_stress` regression harness,
/// 2026-07-21 root-cause investigation) on any thread other than the one
/// that called `LoadLibraryW` to load this DLL. Root cause: `heaplens-hook`
/// is always loaded via `LoadLibraryW` at runtime (self-load or real
/// injection, never linked into the process at startup), and a
/// dynamically-loaded module's thread-locals are only reliably wired up
/// for the thread that loaded it — this held even for `RingHandle` despite
/// it having a real `Drop` impl (an earlier fix attempt assumed giving a
/// thread-local's value type a `Drop` impl changes which underlying
/// mechanism rustc/std uses to something safe for this scenario; that
/// assumption was wrong — see `guard.rs`'s doc comment for the full
/// account of that dead end). Full mechanism root-caused via reduction:
/// see the investigation report; not repeated here.
///
/// The fix: bypass `thread_local!` for the ring pointer itself and drive
/// Fiber Local Storage directly (`FlsAlloc`/`FlsGetValue`/`FlsSetValue`) —
/// like `guard.rs`'s `TlsAlloc`-based fix, a slot-index mechanism with no
/// dependency on module linkage or which thread loaded what, confirmed
/// safe from any thread regardless of `LoadLibraryW` timing. Unlike plain
/// `TlsAlloc`, FLS supports a real per-thread exit callback
/// (`FlsAlloc`'s `lpCallback`), which is what preserves this module's
/// existing invariant — a producer thread's ring gets marked dead (and
/// eventually reclaimed by the writer) when that thread exits, without
/// requiring the thread's own cooperation (essential: real injected
/// targets' threads cannot be asked to call an explicit cleanup function
/// before they exit).
#[cfg(windows)]'''),
    ...para('//',
        r'This used to be a thread_local! holding a RingHandle with a Drop '
        r'impl that marked the producer dead on thread exit. It crashed '
        r'for the same reason guard.rs did (the full story is on that '
        r'page): a hook DLL loaded with LoadLibraryW has no reliable '
        r'thread-local setup on threads other than the loader’s. The guard '
        r'fix used TlsAlloc, but the ring has a requirement the guard does '
        r'not, and that decides the choice of mechanism.'),
    blank,
    ...para('//',
        r'Plain TLS has no exit callback. The ring needs one. When a '
        r'thread dies, its ring has to be marked finished so the writer '
        r'can drain what is left and release the memory, and it has to '
        r'happen "without requiring the thread’s own cooperation '
        r'(essential: real injected targets’ threads cannot be asked to '
        r'call an explicit cleanup function before they exit)". Fiber '
        r'Local Storage has what TLS lacks: FlsAlloc takes a callback that '
        r'the OS runs when a thread that set the slot exits. So rings use '
        r'FLS, guard flags use TLS.'),
    ...code('rust', 'crates/heaplens-alloc/src/ring.rs · the slot and its exit callback', r'''
use super::{registry, Ring};

static FLS_INDEX: OnceLock<u32> = OnceLock::new();

/// Called by the OS when a thread (or fiber) that ever set this FLS
/// slot exits. Reconstructs the `Arc<Ring>` this slot owned (the
/// strong reference taken out in `with_ring` below, distinct from the
/// registry's own clone), marks the ring's producer dead, then lets
/// the `Arc` drop — releasing only *this* reference; the registry's
/// clone keeps the `Ring` itself alive until `drain_all` removes it.
unsafe extern "system" fn on_thread_exit(data: *const c_void) {
    if data.is_null() {
        return;
    }
    let ring = unsafe { Arc::from_raw(data.cast::<Ring>()) };
    ring.producer_alive.store(false, Ordering::Release);
}

fn index() -> u32 {
    *FLS_INDEX.get_or_init(|| unsafe { FlsAlloc(Some(on_thread_exit)) })
}'''),
    ...para('//',
        r'The callback on_thread_exit receives the slot’s value, rebuilds '
        r'the Arc with Arc::from_raw, sets producer_alive to false with '
        r'Release, and lets the Arc drop. Each ring has two strong '
        r'references: one in the registry and one that the FLS slot owns. '
        r'The callback releases only the slot’s; the registry’s keeps the '
        r'Ring alive until drain_all removes it. That asymmetry is '
        r'deliberate: the data outlives the thread that produced it, which '
        r'is how events from a thread that exited a microsecond ago are '
        r'still delivered.'),
    ...code('rust', 'crates/heaplens-alloc/src/ring.rs · with_ring', r'''
    /// Runs `f` against the current thread's ring, creating and
    /// registering it on first call. Initialisation allocates (`Arc::new`,
    /// `Vec::push` into the registry) via the global allocator, but the
    /// recursion guard is always set before this runs (called only from
    /// `record()`), so those allocations are suppressed and never
    /// re-enter `record()`.
    #[inline]
    pub fn with_ring<R>(f: impl FnOnce(&Ring) -> R) -> R {
        let idx = index();
        let ptr = unsafe { FlsGetValue(idx) } as *const Ring;
        if !ptr.is_null() {
            // SAFETY: this slot's Arc reference (taken out below, or by a
            // prior call on this same thread) stays alive until this
            // thread exits and `on_thread_exit` runs — which cannot be
            // happening concurrently with this call, since both only ever
            // run on this thread.
            return f(unsafe { &*ptr });
        }
        let ring = Arc::new(Ring::new());
        registry()
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .push(Arc::clone(&ring));
        let raw = Arc::into_raw(ring);
        unsafe { FlsSetValue(idx, raw as *const c_void) };
        // SAFETY: `raw` is the pointer this slot now owns; no other
        // reference to it is dereferenced concurrently (see above).
        f(unsafe { &*raw })
    }
}'''),
    ...para('//',
        r'with_ring is the one entry point on the hot path. It reads the '
        r'slot with FlsGetValue. If it is non-null, it calls the closure '
        r'against the ring immediately: a single FlsGetValue and the push. '
        r'If it is null, this is the thread’s first allocation: it creates '
        r'the Arc, pushes a clone into the registry under the lock, leaks '
        r'one strong reference into the slot with Arc::into_raw, and sets '
        r'the slot. The comment is careful about the allocation this '
        r'causes: "Initialisation allocates (Arc::new, Vec::push into the '
        r'registry) via the global allocator, but the recursion guard is '
        r'always set before this runs", so the nested allocations are '
        r'suppressed by guard.rs.'),
    ...sec(r'a crash that happened after everything worked'),
    ...code('rust', 'crates/heaplens-alloc/src/ring.rs · shutdown()', r'''
/// Explicit, proactive cleanup — call before there's any chance this
/// module gets unloaded (i.e. from `detach_impl`, our own controlled
/// unload point), not left to happen implicitly at process exit.
///
/// Confirmed necessary (root-cause investigation, 2026-07-21): without
/// this, a thread that made *any* hooked allocation and is still alive
/// when the whole process later exits — in practice, the thread that
/// called `attach`/`detach` itself, since even its own `println!`
/// calls while hooks are live route through this same registration —
/// keeps a live FLS registration pointing at `on_thread_exit`, code
/// living inside this DLL. If process teardown unloads/unmaps this DLL
/// before the OS gets around to running that thread's FLS callback,
/// the callback fires into freed/unmapped memory — reliably reproduced
/// as a crash strictly *after* a full clean attach/workload/detach
/// cycle, i.e. after this module's own job was already done.
///
/// `FlsFree` deregisters the index outright, so no future thread exit —
/// including ones we have no way to wait for, e.g. an uncooperative
/// injected target's other threads that are still running when we
/// detach — can invoke this callback again after this call returns,
/// regardless of when the process or this DLL actually goes away.
/// Trade-off, accepted deliberately: any *other* thread that is still
/// alive with an unflushed ring at this exact moment loses its
/// automatic dead-producer detection for that ring (it stays
/// `producer_alive: true` in the registry forever) — a stale entry,
/// not a crash, and no worse than what already happens to any ring
/// whose thread hasn't exited by the time `detach` runs.
pub fn shutdown() {
    let idx = index();
    // Clear our own (the calling thread's) slot directly rather than
    // relying on FlsFree to invoke the callback for it — documented
    // behavior of exactly what FlsFree does for the calling thread's
    // own value differs across doc revisions; doing it explicitly
    // removes any ambiguity.
    let ptr = unsafe { FlsGetValue(idx) };
    if !ptr.is_null() {
        unsafe { on_thread_exit(ptr) };
        unsafe { FlsSetValue(idx, std::ptr::null()) };
    }
    unsafe { FlsFree(idx) };
}'''),
    ...para('//',
        r'The 2026-07-21 fix had a second act. With thread-locals gone and '
        r'the stress test passing, there was still a crash, strictly after '
        r'a complete, clean attach, workload and detach: "after this '
        r'module’s own job was already done". The doc comment gives the '
        r'cause. A thread that made any hooked allocation, and is still '
        r'alive when the process exits (in practice the thread that called '
        r'attach and detach, because even its own println! calls route '
        r'through the hook), has a live FLS registration pointing at '
        r'on_thread_exit, which is code inside this DLL. If process '
        r'teardown unloads the DLL before the OS gets round to running '
        r'that thread’s callback, the callback fires into unmapped memory.'),
    blank,
    ...para('//',
        r'The remedy is to deregister the callback before the DLL can go '
        r'away: FlsFree removes the index outright, so no future thread '
        r'exit can invoke it. The accepted trade-off is written beside it: '
        r'any other thread still alive with an unflushed ring loses '
        r'automatic dead-producer detection, "a stale entry, not a crash". '
        r'shutdown() also clears the calling thread’s own slot by hand, '
        r'because the doc revisions disagree about what FlsFree does for '
        r'the calling thread’s value, and doing it explicitly "removes any '
        r'ambiguity".'),
    blank,
    ...para('//',
        r'The call site is heaplens-hook’s detach path through lib.rs’s '
        r'shutdown_ring_storage(). Choosing a controlled unload point and '
        r'doing the cleanup there, instead of hoping process exit does it '
        r'in the right order, is the principle.'),
    ...sec(r'drain_all and the cap'),
    ...code('rust', 'crates/heaplens-alloc/src/ring.rs · drain_all documentation: the 2026-07-22 incident', r'''
/// Drain up to `max` events total across all registered rings, calling `f`
/// for each.
///
/// # Why capped, not unconditional (2026-07-22 fix)
///
/// This used to drain every ring down to empty, unconditionally, in one
/// call — no matter how much was pending. The writer thread's own batching
/// discipline ("flush every 64 events or 1ms, whichever first",
/// `writer.rs`'s `BATCH_CAP`/`FLUSH_INTERVAL`) only gates *when* to flush
/// the accumulated batch; it never bounded what a single `drain_all` call
/// could stuff into that batch beforehand. Each ring holds up to `CAP - 1`
/// (65,535) events; with N producer threads each with their own ring, a
/// writer thread that falls behind for any reason (a slow pipe write under
/// daemon backpressure, a burst of first-time symbol resolutions, an OS
/// scheduling gap under heavy concurrent load) could return to a
/// `drain_all` call that swept up to `N * 65,535` events in one shot,
/// blowing past not just the intended 64-event batch size but the wire
/// protocol's own `u16` event-count field (`heaplens_protocol::frame`'s
/// `encode_events`) — confirmed as the actual cause of a writer-thread
/// panic (`events count exceeds u16::MAX`) under sustained 12-thread
/// concurrent injection load, which in turn broke clean detach (the
/// panicked thread never reached `mark_writer_stopped()`).
///
/// Capping here makes an oversized batch structurally impossible from this
/// call site, rather than merely handling it gracefully at a higher limit:
/// callers with a batch-size budget (the writer thread) must pass their
/// *remaining* capacity, not drain everything unconditionally. Stopping
/// early — mid-ring, or between rings — is always safe and resumable: a
/// `Ring`'s own head/tail cursors are exactly where a partial drain leaves
/// them, so the next `drain_all` call continues correctly from there. A
/// ring whose producer died is only actually swept from the registry once
/// it drains down to empty — hitting the cap mid-cleanup just defers that
/// removal to a later call, it never skips or corrupts it.
///
/// # Panics (debug builds)
/// Panics if the calling thread has not called `guard::force_enter_permanent()`.
/// This function must only be called from the writer thread.'''),
    ...para('//',
        r'drain_all used to take only a callback and emptied every ring in '
        r'one call. The writer thread batches on a rule of 64 events or 1 '
        r'ms, but that rule only decided when to flush a batch, not how '
        r'much a single drain could put into it. Each ring can hold 65,535 '
        r'events. With N busy producers and a writer that had fallen '
        r'behind for any reason (slow pipe write, a burst of first-time '
        r'symbol resolution, a scheduling gap), a single call could sweep '
        r'N x 65,535 events into one batch. That broke the wire format’s '
        r'u16 event-count field, the encoder panicked, and the panic '
        r'killed the writer thread before it could mark itself stopped, so '
        r'clean detach failed. The incident had been seen under sustained '
        r'load from 12 injected threads.'),
    blank,
    ...para('//',
        r'The doc comment draws the design lesson: capping here "makes an '
        r'oversized batch structurally impossible from this call site, '
        r'rather than merely handling it gracefully at a higher limit". '
        r'The fix is to change the function’s contract. drain_all takes a '
        r'max, callers pass their remaining capacity, and stopping early '
        r'is always safe because a ring’s head and tail are exactly where '
        r'a partial drain leaves them.'),
    ...code('rust', 'crates/heaplens-alloc/src/ring.rs · drain_all', r'''
pub fn drain_all(max: usize, mut f: impl FnMut(AllocEvent)) {
    debug_assert!(
        crate::guard::is_set(),
        "drain_all must be called only from a thread where the recursion guard is permanently set (writer thread)"
    );
    let mut reg = registry()
        .lock()
        .unwrap_or_else(|p| p.into_inner());
    let mut i = 0;
    let mut drained = 0usize;
    while i < reg.len() {
        while drained < max {
            match reg[i].pop() {
                Some(ev) => { f(ev); drained += 1; }
                None => break,
            }
        }
        if drained >= max {
            return; // cap reached — remaining rings/events wait for the next call
        }
        // Ring i is empty (we only get here when the pop-loop above broke on
        // `None`, not on the cap) — same dead-producer check/cleanup as before.
        if !reg[i].producer_alive.load(Ordering::Acquire) {
            // The Acquire on producer_alive synchronizes with the thread's death Release,
            // which transitively happens-after the last push's tail Release.
            // A second drain here picks up any event the first pass missed on weak-memory hardware.
            while drained < max {
                match reg[i].pop() {
                    Some(ev) => { f(ev); drained += 1; }
                    None => break,
                }
            }
            if drained >= max {
                return;
            }
            reg.swap_remove(i);
        } else {
            i += 1;
        }
    }
}'''),
    ...para('//',
        r'Read the control flow with the cap in mind. For each ring the '
        r'inner loop pops until the ring is empty or the budget is spent. '
        r'If the budget is spent, drain_all returns at once, leaving '
        r'everything else for the next call. If the ring emptied, it '
        r'checks producer_alive; for a dead producer it drains once more '
        r'before removing it with swap_remove.'),
    blank,
    ...para('//',
        r'That second drain is a weak-memory detail, added the same day as '
        r'the ring (commit 1f417d1, "second drain after producer_alive '
        r'Acquire sync"). The comment explains: the Acquire load of '
        r'producer_alive synchronises with the dying thread’s Release '
        r'store, which transitively happens-after its last push. Events '
        r'pushed just before the thread died could be missed by the first '
        r'pass on a weakly ordered CPU, so one more pass picks them up. A '
        r'dead ring is removed only when it is both dead and drained to '
        r'empty; hitting the cap partway through cleanup merely defers the '
        r'removal.'),
    blank,
    ...para('//',
        r'The writer now calls it as drain_all(remaining, ...) with '
        r'remaining = BATCH_CAP - batch.len(), so a batch can never exceed '
        r'64. The tests below pin the contract.'),
    ...sec(r'an open fairness question'),
    ...para('//',
        r'Each call starts at ring index 0. If the first registered ring '
        r'always has at least a batch’s worth pending, the budget is spent '
        r'there and later rings are not reached on that call. Under a '
        r'workload where one thread saturates the writer, other threads’ '
        r'events could be delayed, or lost to full rings, which nothing '
        r'reports (see the dropped counter). This comes from reading the '
        r'loop; it was not measured and no test targets it. A rotating '
        r'start index would be the usual remedy.'),
    ...sec(r'tests'),
    ...code('rust', 'crates/heaplens-alloc/src/ring.rs · the registry lock and the basic ring tests', r'''
/// `registry()` is a single process-global `Mutex<Vec<Arc<Ring>>>`, and
/// cargo runs tests in this binary concurrently by default. Any test
/// that pushes a ring into it and then calls `drain_all` is reading and
/// draining state shared with every other such test running at the same
/// time — one test's `drain_all` call can silently drain another's
/// still-pending ring, or leave stray rings behind for a later test to
/// see. Hold this lock for the duration of any test that touches the
/// registry (directly or via `crate::ring::push`) to serialize them
/// against each other; tests that only exercise a standalone `Ring`
/// instance never touch `registry()` and don't need it.
static REGISTRY_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

#[test]
fn push_pop_roundtrip() {
    let ring = Ring::new();
    assert!(ring.push(ev(1)));
    assert!(ring.push(ev(2)));
    assert_eq!(ring.pop().unwrap().ptr, 1);
    assert_eq!(ring.pop().unwrap().ptr, 2);
    assert!(ring.pop().is_none());
}

#[test]
fn fifo_order() {
    let ring = Ring::new();
    for i in 0..10u64 {
        ring.push(ev(i));
    }
    for i in 0..10u64 {
        assert_eq!(ring.pop().unwrap().ptr, i);
    }
}

#[test]
fn full_ring_returns_false_and_increments_dropped() {
    let ring = Ring::new();
    // Fill to capacity-1 (ring has CAP slots but can hold CAP-1 items)
    let mut pushed = 0usize;
    for i in 0..CAP as u64 {
        if ring.push(ev(i)) { pushed += 1; } else { break; }
    }
    assert_eq!(pushed, CAP - 1, "ring holds exactly CAP-1 events when full");
    // Next push must fail and increment dropped
    let before = ring.dropped.load(std::sync::atomic::Ordering::Relaxed);
    assert!(!ring.push(ev(99999)));
    let after = ring.dropped.load(std::sync::atomic::Ordering::Relaxed);
    assert_eq!(after, before + 1);
}'''),
    ...para('//',
        r'The test comment on REGISTRY_TEST_LOCK is a small lesson in '
        r'shared state. registry() is a process-global, and cargo runs a '
        r'test binary’s tests in parallel, so any test that registers a '
        r'ring and drains is draining everyone’s. The lock serialises '
        r'them. It was added in commit fa3fe78 because the problem "only '
        r'surfaced once two new drain_all cap tests joined the existing '
        r'registry test". One registry test had been safe on its own; with '
        r'two more it was not.'),
    blank,
    ...para('//',
        r'full_ring_returns_false_and_increments_dropped fills a ring '
        r'until push returns false, asserts pushed == CAP - 1, then checks '
        r'that exactly one more push fails and that dropped went up by '
        r'exactly one.'),
    ...code('rust', 'crates/heaplens-alloc/src/ring.rs · the cap stops exactly, and loses nothing', r'''
#[test]
fn drain_all_stops_at_the_cap_leaving_the_rest_for_next_call() {
    let _lock = REGISTRY_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let ring = Ring::new();
    for i in 0..10u64 {
        assert!(ring.push(ev(i)));
    }
    registry().lock().unwrap_or_else(|p| p.into_inner()).push(std::sync::Arc::new(ring));

    crate::guard::force_enter_permanent();

    let mut first_pass: Vec<u64> = Vec::new();
    drain_all(4, |e| first_pass.push(e.ptr));
    assert_eq!(first_pass, vec![0, 1, 2, 3], "must stop exactly at the cap, in FIFO order");

    let mut second_pass: Vec<u64> = Vec::new();
    drain_all(100, |e| second_pass.push(e.ptr));
    assert_eq!(
        second_pass, vec![4, 5, 6, 7, 8, 9],
        "the remaining events must still be there on the next call — capping must not drop anything"
    );
}'''),
    ...para('//',
        r'Ten events go into one ring; drain_all(4) must deliver 0, 1, 2, '
        r'3 in FIFO order; the next drain_all(100) must deliver 4 through '
        r'9. The assertion message says what the test is for: "capping '
        r'must not drop anything".'),
    ...code('rust', 'crates/heaplens-alloc/src/ring.rs · the cap is shared across producers', r'''
#[test]
fn drain_all_cap_can_stop_mid_ring_across_multiple_producers() {
    let _lock = REGISTRY_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    // Two separate rings (standing in for two producer threads), each
    // holding more than half the cap — proves the cap is enforced
    // across the *total* drained this call, not reset per-ring, and
    // that a cap hit partway through ring A correctly leaves ring B
    // completely untouched for the next call.
    let ring_a = Ring::new();
    let ring_b = Ring::new();
    for i in 0..6u64 {
        assert!(ring_a.push(ev(100 + i)));
    }
    for i in 0..6u64 {
        assert!(ring_b.push(ev(200 + i)));
    }
    {
        let mut reg = registry().lock().unwrap_or_else(|p| p.into_inner());
        reg.push(std::sync::Arc::new(ring_a));
        reg.push(std::sync::Arc::new(ring_b));
    }

    crate::guard::force_enter_permanent();

    let mut drained: Vec<u64> = Vec::new();
    drain_all(8, |e| drained.push(e.ptr));
    assert_eq!(drained.len(), 8, "must drain exactly the cap, not more");
    assert_eq!(
        &drained[0..6], &[100, 101, 102, 103, 104, 105],
        "ring A must be fully drained first"
    );
    assert_eq!(
        &drained[6..8], &[200, 201],
        "ring B must be drained only up to the remaining cap budget"
    );

    let mut rest: Vec<u64> = Vec::new();
    drain_all(100, |e| rest.push(e.ptr));
    assert_eq!(rest, vec![202, 203, 204, 205], "ring B's remainder must survive to the next call");
}'''),
    ...para('//',
        r'Two rings of six events each. drain_all(8) must return exactly '
        r'eight events: all six of ring A, then the first two of ring B. '
        r'The next call returns B’s remaining four (202 to 205). This '
        r'proves the budget is spent across the whole call and not per '
        r'ring, and that a cut in the middle of ring A or B leaves the '
        r'other untouched.'),
    blank,
    ...para('//',
        r'The crate’s tests were run on a Linux sandbox for this page. All '
        r'six ring tests pass there, using the non-Windows fallback (a '
        r'plain thread_local! with a Drop impl). The Windows FLS code in '
        r'this file is not exercised by them; it is covered by the hook '
        r'crate’s stress and self-load harnesses on a real Windows build.'),
    ...sec(r'limits'),
    ...pt('//',
        r'10.5 MiB per allocating thread',
        r'the cost of the flat ring; a program that spawns thousands of '
        r'short-lived threads allocates and frees that much for each.'),
    ...pt('//',
        r'drops are silent',
        r'dropped is counted and never reported.'),
    ...pt('//',
        r'start-at-zero draining',
        r'the fairness question above.'),
    ...pt('//',
        r'the registry is a Mutex',
        r'acceptable off the hot path, but the first allocation on each '
        r'thread does take it.'),
    ...pt('//',
        r'FlsFree trade-off',
        r'after shutdown(), live threads’ rings are never marked dead, by '
        r'design.'),
    ...pt('//',
        r'main-thread exit is not special-cased',
        r'the original thread_local! version noted that on Windows '
        r'main-thread TLS destructors may not run, and relied on the '
        r'writer’s periodic drain to pick up its events. What the FLS '
        r'version does for the main thread at process exit was not tested.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/src/ring.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/src/ring.rs'),
  ],
);
