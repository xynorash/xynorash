import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-hook/examples/self_load_harness.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'self_load_harness.rs — the Step 1 gate: a program that hooks itself'),
    cm('//', r'a workload with a known shape, printed pointer by pointer, so a test can count exactly what the hook saw'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'target program for the Step 1 acceptance gate of the hook DLL'),
    kv('language', r'Rust, std plus windows-sys (LoadLibraryW, GetProcAddress)'),
    kv('size', r'150 lines'),
    kv('history', r'one commit, b3a22c2 (2026-07-13 12:24 +0300); untouched since'),
    kv('driven by', r'crates/heaplens-daemon/tests/hook_self_load_wire.rs'),
    kv('script', r'50 allocations, 10 + 1 reallocations, 51 frees; then 5 + 5 operations after detach'),
    ...sec(r'why a program that hooks itself'),
    ...para('//',
        r'Stage 7 has two hard problems that look like one. One is whether '
        r'the hook DLL captures heap traffic correctly. The other is '
        r'whether a separate process can get the DLL into a stranger '
        r'program and drive it. The design document (section 8, Step 1) '
        r'separates them on purpose: build the DLL "loaded the easy way", '
        r'by a small program that calls LoadLibraryW on itself and then '
        r'calls the exported attach function directly. That, in the '
        r'document’s words, "isolates ‘does the hook itself work’ '
        r'from ‘does injection work,’ which are separable concerns '
        r'and should not be debugged simultaneously".'),
    blank,
    ...para('//',
        r'This file is that program. It is half of a gate. The other half '
        r'is a test in the daemon crate that starts this executable as a '
        r'child, listens on the real named pipe, and compares what '
        r'arrived with what this program says it did. The same section '
        r'of the design explains why both halves need to exist: a gate '
        r'that only confirms the DLL loads and does not crash "would '
        r'pass with a silently broken capture path".'),
    ...sec(r'a stranger to its own DLL'),
    ...code('rust', 'crates/heaplens-hook/examples/self_load_harness.rs · the header', r'''
//! Step 1 acceptance-gate harness (docs/stage7-injection-design.md §8,
//! Step 1). Loads `heaplens_hook.dll` into *itself* via `LoadLibraryW` — no
//! cross-process injection yet, that is Step 2 — then drives a scripted,
//! precisely-countable allocation workload through the now-hooked
//! `HeapAlloc`/`HeapReAlloc`/`HeapFree`, detaches, and runs a second
//! workload that must produce zero captured events.
//!
//! This binary does not link `heaplens_hook` as a Rust library (it's a
//! cdylib, loaded dynamically like any injection target would load it) and
//! does not use `heaplens-alloc` as its global allocator — its allocations
//! go through the plain `std::alloc::System` (Win32 `HeapAlloc` family),
//! exactly like an uncooperative target's would.'''),
    ...para('//',
        r'Two sentences in that header set up the whole experiment. The '
        r'harness "does not link heaplens_hook as a Rust library", '
        r'because the hook is a cdylib and cannot be linked, so the '
        r'DLL is reached through LoadLibraryW and GetProcAddress "like '
        r'any injection target would load it". And it "does not use '
        r'heaplens-alloc as its global allocator": its allocations go '
        r'to std::alloc::System, which on Windows is the Win32 heap, '
        r'"exactly like an uncooperative target’s would". If this '
        r'program had used the cooperative allocator, any events the '
        r'daemon received could have come from either path, and the gate '
        r'would not have been able to say which.'),
    blank,
    ...para('//',
        r'The three helper functions above main, '
        r'alloc_n, realloc_n and free_n, are the discipline that keeps '
        r'it that way. Each builds a Layout with alignment 8 and calls '
        r'System directly, so a Vec or a Box can never slip an extra '
        r'allocation into the scripted sequence: the only heap calls '
        r'in the workload are the ones the script names. (The println! '
        r'calls are another matter, taken up below.)'),
    ...sec(r'finding the DLL'),
    ...code('rust', 'crates/heaplens-hook/examples/self_load_harness.rs · dll_path', r'''
fn dll_path() -> std::path::PathBuf {
    // This harness builds to target/{profile}/examples/self_load_harness.exe;
    // heaplens_hook.dll (the package's cdylib target) builds one level up,
    // to target/{profile}/heaplens_hook.dll.
    let exe = std::env::current_exe().expect("current_exe");
    exe.parent()
        .and_then(|p| p.parent())
        .expect("cannot determine target profile dir from harness exe path")
        .join("heaplens_hook.dll")
}'''),
    ...para('//',
        r'The comment draws the map. Cargo puts an example at '
        r'target/{profile}/examples/self_load_harness.exe and the '
        r'package’s cdylib one directory up, at '
        r'target/{profile}/heaplens_hook.dll, so the path is the '
        r'executable’s parent’s parent plus a file name. Two calls to '
        r'parent(), no search. That keeps the harness free of '
        r'configuration and ties it to the layout Cargo produces. The '
        r'cost shows up in the daemon test, which has to repeat the '
        r'same arithmetic and tells you what to build first: "cargo '
        r'build --example self_load_harness -p heaplens-hook" and "cargo '
        r'build -p heaplens-hook". Nothing makes Cargo build either one '
        r'when you run the test.'),
    ...sec(r'before and after attach'),
    ...code('rust', 'crates/heaplens-hook/examples/self_load_harness.rs · main, loading and attaching', r'''
fn main() {
    // Pre-attach allocation — never observed by the hook. Reallocated below,
    // after attach, to exercise the realloc-of-unknown-pointer fallback
    // (docs/stage7-injection-design.md §1.4, `Graph::on_realloc`).
    let mut pre_attach_ptr = unsafe { alloc_n(96) };

    let path = dll_path();
    let wpath = to_wide(path.to_str().expect("dll path is valid UTF-8"));

    let hmodule = unsafe { LoadLibraryW(wpath.as_ptr()) };
    assert!(!hmodule.is_null(), "LoadLibraryW failed for {path:?}");

    let attach: AttachFn = unsafe {
        let proc = GetProcAddress(hmodule, b"HeapLensHookAttach\0".as_ptr());
        std::mem::transmute(proc.expect("GetProcAddress(HeapLensHookAttach) failed"))
    };
    let detach: DetachFn = unsafe {
        let proc = GetProcAddress(hmodule, b"HeapLensHookDetach\0".as_ptr());
        std::mem::transmute(proc.expect("GetProcAddress(HeapLensHookDetach) failed"))
    };

    let rc = unsafe { attach() };
    assert_eq!(rc, 0, "HeapLensHookAttach failed with code {rc}");

    // Let the writer thread connect + handshake before generating events.
    std::thread::sleep(std::time::Duration::from_millis(300));'''),
    ...para('//',
        r'The order of those lines is the experiment. The first '
        r'allocation, 96 bytes, happens before the DLL exists in the '
        r'process. No hook sees it. The comment says what it is for: '
        r'it will be reallocated after attach, "to exercise the '
        r'realloc-of-unknown-pointer fallback". The design (section '
        r'1.4) works that case out. A block allocated before attach can '
        r'be resized after it, and the daemon then receives a '
        r'Realloc event whose old pointer it never tracked. The '
        r'document checked the daemon’s on_realloc and found that it '
        r'does not drop the event: it registers the new pointer as a '
        r'fresh node, which is right because a live allocation exists '
        r'now even though its origin was missed. The mirror case, a '
        r'free of an unknown pointer, is dropped. This harness '
        r'produces both, and the test counts both.'),
    blank,
    ...para('//',
        r'Then the type aliases at the top, AttachFn and DetachFn, both '
        r'unsafe extern "system" fn() -> u32, are the signatures of the '
        r'two exports, and the two transmutes turn the raw addresses '
        r'from GetProcAddress into those function types. The harness '
        r'calls the plain HeapLensHookAttach, not the Remote variant. '
        r'That choice matters: HeapLensHookAttachRemote ends by '
        r'terminating its own calling thread, which is right for a '
        r'raw remote thread and fatal for a harness’s main thread. The '
        r'lib.rs page records that merging the two behind a flag broke '
        r'this gate the first time, which is why they are separate '
        r'exports. attach() returning 0 is asserted.'),
    blank,
    ...para('//',
        r'The 300 ms sleep afterwards is a courtesy to a background '
        r'thread. Attach starts the writer thread, which has to find '
        r'and open the named pipe and send its handshake before '
        r'events can flow. The comment says "Let the writer thread '
        r'connect + handshake before generating events." A fixed '
        r'sleep is not a synchronisation, and the ring buffer is what '
        r'makes it good enough: events produced before the pipe is '
        r'open wait in the ring.'),
    ...sec(r'the script'),
    ...code('rust', 'crates/heaplens-hook/examples/self_load_harness.rs · the counted workload', r'''
    // Exactly ALLOC_COUNT Alloc events, sizes cycling through SIZES.
    let mut ptrs: [*mut u8; ALLOC_COUNT] = [std::ptr::null_mut(); ALLOC_COUNT];
    let mut sizes: [usize; ALLOC_COUNT] = [0; ALLOC_COUNT];
    for i in 0..ALLOC_COUNT {
        let size = SIZES[i % SIZES.len()];
        ptrs[i] = unsafe { alloc_n(size) };
        sizes[i] = size;
        println!("ALLOC ptr={:?} size={size}", ptrs[i]);
    }

    // Exactly REALLOC_COUNT Realloc events on tracked pointers.
    for (i, sizes_i) in sizes.iter_mut().enumerate().take(REALLOC_COUNT) {
        let old_ptr = ptrs[i];
        let new_size = *sizes_i * 2;
        ptrs[i] = unsafe { realloc_n(ptrs[i], *sizes_i, new_size) };
        *sizes_i = new_size;
        println!("REALLOC old={old_ptr:?} new={:?} size={new_size}", ptrs[i]);
    }

    // Exactly 1 Realloc event on the untracked pre-attach pointer.
    let untracked_old = pre_attach_ptr;
    pre_attach_ptr = unsafe { realloc_n(pre_attach_ptr, 96, 192) };
    println!("REALLOC_UNTRACKED old={untracked_old:?} new={pre_attach_ptr:?} size=192");

    // Exactly ALLOC_COUNT + 1 Dealloc events.
    for i in 0..ALLOC_COUNT {
        unsafe { free_n(ptrs[i], sizes[i]) };
        println!("FREE ptr={:?}", ptrs[i]);
    }
    unsafe { free_n(pre_attach_ptr, 192) };
    println!("FREE ptr={pre_attach_ptr:?}");'''),
    ...para('//',
        r'The shape is chosen so that every count is a different number, '
        r'which makes a wrong total point at its cause:'),
    ...pt('//', r'50 allocations',
        r'ALLOC_COUNT, with sizes cycling through 32, 64, 128 and 256, '
        r'so the daemon-side size check cannot pass by accident on a '
        r'single repeated value.'),
    ...pt('//', r'10 reallocations of tracked pointers',
        r'REALLOC_COUNT, each doubling the size (32 becomes 64, 256 '
        r'becomes 512). The loop updates sizes[i] so that the matching '
        r'free later uses the size the block now has.'),
    ...pt('//', r'1 reallocation of the untracked pointer',
        r'96 becomes 192, printed with its own marker, '
        r'REALLOC_UNTRACKED, so the test can tell it apart from the '
        r'ten.'),
    ...pt('//', r'51 frees',
        r'the 50 workload pointers plus the pre-attach pointer in its new '
        r'place. The daemon test names this EXPECTED_DEALLOC_COUNT = '
        r'ALLOC_COUNT + UNTRACKED_REALLOC_COUNT.'),
    blank,
    ...para('//',
        r'The total the workload asks for is therefore 50 + 11 + 51 = '
        r'112 heap events. That is the number of events the gate '
        r'must find, and, as the next section explains, it is not the '
        r'number of events the daemon receives. The commit message that '
        r'landed this gate gives the same breakdown in one line: "exactly '
        r'50 allocs, 11 reallocs (10 tracked + 1 exercising the '
        r'realloc-of-unknown-pointer fallback), 51 frees captured by '
        r'pointer identity, zero events after detach".'),
    ...sec(r'why every operation is printed'),
    ...para('//',
        r'Each line of the loops above ends with a println! of the '
        r'operation’s own pointer and size, for example "ALLOC '
        r'ptr=0x1f2e3d size=64". That is not logging. It is the '
        r'hand-off to the test, which parses this program’s standard '
        r'output into the set of facts it expects the daemon to have '
        r'received. The comment in the file explains why the test '
        r'matches by pointer and not by total:'),
    ...code('rust', 'crates/heaplens-hook/examples/self_load_harness.rs · the reason, in the source', r'''
    // ── Scripted, precisely-countable workload (captured) ───────────────
    // Every operation's exact pointer/size is printed to stdout in a
    // simple, parseable form. The capture mechanism hooks HeapAlloc/
    // HeapReAlloc/HeapFree *process-wide* — it cannot distinguish this
    // workload's own calls from Windows' own internal heap traffic
    // triggered as a side effect of the writer thread's pipe I/O (observed
    // empirically: extra captured events with sizes never requested here).
    // The daemon-side test filters to exactly these pointers rather than
    // asserting a brittle global total, so ambient OS-level noise doesn't
    // make the gate flaky. See docs/stage7-injection-design.md §8 Step 1.'''),
    ...para('//',
        r'The hook is on RtlAllocateHeap, a process-wide choke point '
        r'that cannot tell the workload’s calls from anything else '
        r'in the process. The writer thread’s own pipe I/O makes '
        r'Windows allocate on the same heap, and the print calls do the '
        r'same through the C runtime’s stdout buffering. A gate that '
        r'asserted "the daemon received exactly 112 events" would fail '
        r'for reasons unrelated to capture. The gate therefore asks a '
        r'more precise question: for each of the 50 pointers this '
        r'program printed, did an Alloc event arrive with that '
        r'pointer and that size; for each of the 11 reallocation '
        r'pairs, did a Realloc event arrive with that old and new '
        r'pointer; for each of the 51 frees, a Dealloc.'),
    blank,
    ...para('//',
        r'There is a subtlety that a later commit documents for the '
        r'sibling test, and which applies here in principle. Because the '
        r'print calls allocate, an incidental allocation can land on an '
        r'address that the script uses a moment later. Commit 084ddf9 '
        r'(2026-07-26) found it in crates/heaplens-daemon/tests/'
        r'hook_self_load_spawned_thread.rs: address 0x27ff25f61f0 had '
        r'been allocated at size 30 and freed by stdout’s buffering, '
        r'then allocated for real at size 32 by the script, and a test '
        r'that compared the first event it saw for a pointer reported a '
        r'false size mismatch. That test now compares the last event '
        r'per pointer. The test for this file, hook_self_load_wire.rs, '
        r'checks the size of every Alloc event whose pointer is in the '
        r'script, so the same coincidence could, in principle, give '
        r'it a false mismatch too. I did not see it happen and the '
        r'repository does not report it.'),
    ...sec(r'proving that detach removed the hooks'),
    ...code('rust', 'crates/heaplens-hook/examples/self_load_harness.rs · detach and the post-detach workload', r'''
    // Let the writer thread flush the batch before detaching.
    std::thread::sleep(std::time::Duration::from_millis(300));

    let rc = unsafe { detach() };
    assert_eq!(rc, 0, "HeapLensHookDetach failed with code {rc}");

    // ── Post-detach workload — must produce zero captured events ────────
    // Pointers printed with a distinct marker so the test can positively
    // assert they were never captured (proving hooks were actually
    // removed) rather than relying on their absence from the main workload
    // sets, which coincidental pointer reuse could make ambiguous.
    let mut post_ptrs: [*mut u8; 5] = [std::ptr::null_mut(); 5];
    for p in post_ptrs.iter_mut() {
        *p = unsafe { alloc_n(64) };
        println!("POST_DETACH_ALLOC ptr={p:?} size=64");
    }
    for p in post_ptrs {
        unsafe { free_n(p, 64) };
        println!("POST_DETACH_FREE ptr={p:?}");
    }

    // Give the daemon a moment to receive the final captured batch.
    std::thread::sleep(std::time::Duration::from_millis(300));

    println!("self_load_harness: done");
}'''),
    ...para('//',
        r'The second half of the gate. The 300 ms sleep before detach '
        r'is the flush window ("Let the writer thread flush the batch '
        r'before detaching."). detach() returning 0 is asserted. Then the '
        r'program allocates and frees five blocks of 64 bytes, with '
        r'different marker words, POST_DETACH_ALLOC and POST_DETACH_FREE. '
        r'The design is explicit that the right result is not "fewer" '
        r'or "looks quiet" but zero.'),
    blank,
    ...para('//',
        r'The comment on those markers carries the subtle part: the '
        r'pointers are printed with a distinct marker "so the test can '
        r'positively assert they were never captured (proving hooks '
        r'were actually removed) rather than relying on their absence '
        r'from the main workload sets, which coincidental pointer reuse '
        r'could make ambiguous". The Windows heap readily hands a '
        r'just-freed block to the next request of a similar size, so a '
        r'post-detach pointer can equal a pre-detach one. The test '
        r'handles that case with an ordering argument:'),
    ...code('rust', 'crates/heaplens-daemon/tests/hook_self_load_wire.rs · the leak check', r'''
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
        .max();'''),
    ...para('//',
        r'A pointer value match alone "doesn’t prove a leak". What does '
        r'prove one is an event after the last event that belongs to the '
        r'pre-detach script and that touches one of the five post-detach '
        r'pointers. The assertion at the end of the test is built on '
        r'that list and its failure message states what a hit would '
        r'mean: the hooks "were not fully removed by detach".'),
    ...sec(r'what the daemon test asserts'),
    ...pt('//', r'the harness behaved',
        r'it exited with a success status within 15 seconds and printed '
        r'"self_load_harness: done". The parsed output must contain '
        r'exactly 50 ALLOC lines, 11 REALLOC lines (the 10 and the '
        r'untracked one), 51 FREE lines and 5 distinct post-detach '
        r'pointers.'),
    ...pt('//', r'capture is complete',
        r'all 50 pointers appear in Alloc events, all 11 old/new pairs '
        r'in Realloc events and all 51 pointers in Dealloc events.'),
    ...pt('//', r'capture is accurate',
        r'no Alloc event for a scripted pointer has a size other than '
        r'the scripted one.'),
    ...pt('//', r'detach is real',
        r'no event after the pre-detach script touches a post-detach '
        r'pointer.'),
    blank,
    ...para('//',
        r'What it does not assert is as informative. It does not check '
        r'timestamps or their order, the captured stacks, the symbols '
        r'the writer thread sent, or the Handshake frame’s pid. It '
        r'replays the raw events into a fresh ownership graph, so the '
        r'untracked-realloc path through on_realloc does run, but the '
        r'test does not inspect the graph afterwards. The gate is a '
        r'count-and-size gate, which is what the design asked of '
        r'Step 1, and it is honest about being one.'),
    ...sec(r'the hole in it'),
    ...para('//',
        r'Every operation in this file runs on one thread, the one '
        r'that called LoadLibraryW. That is invisible until you know '
        r'about the bug that lived exactly there. On 2026-07-21 a '
        r'multi-threaded stress harness showed that the hook crashed on '
        r'the first hooked allocation of any thread other than the one '
        r'that loaded the DLL. The fix commit, dcc76f2, says it '
        r'plainly: this gate "never actually exercised this path at '
        r'all: its entire workload runs on the thread that calls '
        r'LoadLibraryW, which is exactly why this bug went uncaught until '
        r'a dedicated concurrency stress harness went looking for it". '
        r'The answer was not to change this file. It was to add a '
        r'sibling that does the same work on a spawned thread, '
        r'self_load_spawned_thread.rs, and a test for it.'),
    blank,
    ...para('//',
        r'The lesson is general and cheap to state. A regression '
        r'gate is a model of the failure it expects. This one modelled '
        r'"the hook counts wrongly" and passed. It did not model "the '
        r'hook crashes when the thread is not the loader", because '
        r'nobody had met that failure yet. The file stayed correct; it '
        r'was never complete.'),
    ...sec(r'limits'),
    ...pt('//', r'one thread, one process',
        r'no concurrency, and no cross-process loading. Both are '
        r'covered by other files (self_load_spawned_thread.rs, '
        r'injection_target.rs).'),
    ...pt('//', r'fixed sleeps',
        r'300 ms before the workload and 300 ms before detach are '
        r'timing assumptions. On a loaded machine the writer thread '
        r'could connect later; the ring absorbs it, but the gate would '
        r'have no way to say so.'),
    ...pt('//', r'a Windows-only, build-order-dependent test',
        r'the test file is #![cfg(windows)] and panics with a build '
        r'command if the example or the DLL is missing.'),
    ...pt('//', r'the number 112 is never checked',
        r'by design. A total would be fragile. The cost is that a '
        r'duplicated event, one the hook sent twice, would not be '
        r'noticed: the sets only record that each expected event '
        r'arrived at least once.'),
    ...sec(r'what to take from it'),
    ...pt('//', r'make the workload say what it did',
        r'printing every pointer turns a probabilistic capture into '
        r'something a test can verify by identity.'),
    ...pt('//', r'prove absence with a marker, not with silence',
        r'the post-detach pointers carry their own words so that '
        r'"nothing captured" cannot be confused with "captured under '
        r'another name".'),
    ...pt('//', r'know what the gate cannot see',
        r'a single-threaded workload hid a multi-threaded crash for '
        r'eight days, from 13 July to 21 July.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-hook/examples/self_load_harness.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-hook/examples/self_load_harness.rs'),
  ],
);
