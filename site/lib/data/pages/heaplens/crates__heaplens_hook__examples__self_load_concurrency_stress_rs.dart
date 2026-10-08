import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-hook/examples/self_load_concurrency_stress.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'self_load_concurrency_stress.rs — forty-eight threads and a stopwatch'),
    cm('//', r'built to look for a stall, it found a crash first, and then became the standing repro'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'multi-threaded stress and latency harness for the hook DLL'),
    kv('language', r'Rust, std plus windows-sys (LoadLibraryW, GetProcAddress)'),
    kv('size', r'137 lines'),
    kv('history', r'one commit, 8b0f962 (2026-07-21 22:14 +0300)'),
    kv('load', r'48 threads, 8 seconds each, 64-byte alloc and free pairs, baseline then hooked'),
    kv('reports', r'p50, p99, p999, max, and counts above 1 ms, 10 ms, 100 ms and 1 s'),
    kv('automated', r'no: no test in the repository runs it'),
    ...sec(r'the question it was written to answer'),
    ...para('//',
        r'The harness comes out of a night, 2026-07-21, with two '
        r'facts on the table. A real process, jetbrainsd.exe, had crashed '
        r'with an access violation recorded inside heaplens_hook.dll. '
        r'Minutes later the same machine had bugchecked with '
        r'DPC_WATCHDOG_VIOLATION. The commit that adds this file records '
        r'both and then declines to connect them: "root-causing the '
        r'defect itself is separate, later work". What it does with '
        r'confidence is the first step of an investigation. It builds an '
        r'instrument, something that can put the hook under the kind of '
        r'load a heavy multi-threaded program applies (the header names '
        r'"Chrome/Discord/a JVM"), and measures what an application '
        r'would see.'),
    blank,
    ...para('//',
        r'The measurement is chosen for a stall, not for a slowdown. The '
        r'summary prints a median and two tail percentiles, a maximum, '
        r'and then counts of samples above four thresholds that grow '
        r'by factors of ten: 1 ms, 10 ms, 100 ms and one second. Those '
        r'are the numbers you want if the suspicion is that some call '
        r'under the hook sometimes takes absurdly long. That reading of '
        r'why the thresholds are shaped so is mine; the file does not '
        r'explain them.'),
    ...code('rust', 'crates/heaplens-hook/examples/self_load_concurrency_stress.rs · the header', r'''
//! Diagnostic-only repro harness for the DPC_WATCHDOG_VIOLATION investigation
//! (2026-07-21). Self-load only (like `self_load_harness.rs`) — loads
//! `heaplens_hook.dll` into *itself* via `LoadLibraryW`, never injects into
//! any other process. This is intentional: this investigation's constraint
//! is "example producers only, or a disposable VM" for cross-process
//! testing, and self-load already exercises the exact same
//! `RtlAllocateHeap`/`RtlReAllocateHeap`/`RtlFreeHeap` hook path a real
//! injected target would run, just without touching a second process.
//!
//! Spawns many threads (approximating a heavily multi-threaded target like
//! Chrome/Discord/a JVM) all allocating/freeing rapidly and concurrently
//! under the hook, for a fixed duration. Measures each alloc+free pair's
//! wall-clock latency from *outside* the hook (no modification to hook or
//! heaplens-alloc source — this harness only times calls it makes itself),
//! then reports max/p99/outlier-count, first unhooked (baseline) and then
//! hooked, so the added overhead is directly comparable.
//!
//! Not a fix, not a permanent addition — a one-off diagnostic tool for this
//! investigation, per the same "temporary, clearly marked" discipline as
//! `diag_veh.rs`.'''),
    ...para('//',
        r'Three constraints are packed into it.'),
    ...pt('//', r'self-load only',
        r'"never injects into any other process". The investigation’s '
        r'rule, stated in the header, is "example producers only, or a '
        r'disposable VM" for cross-process testing. Self-load exercises '
        r'"the exact same RtlAllocateHeap/RtlReAllocateHeap/RtlFreeHeap '
        r'hook path a real injected target would run, just without '
        r'touching a second process". The tool is a stand-in for a '
        r'dangerous experiment, not a version of it.'),
    ...pt('//', r'measured from outside',
        r'"no modification to hook or heaplens-alloc source — this '
        r'harness only times calls it makes itself". The observer does not '
        r'touch the observed, so a number it prints cannot be an artefact '
        r'of instrumentation inside the hook.'),
    ...pt('//', r'baseline first',
        r'"first unhooked (baseline) and then hooked, so the added '
        r'overhead is directly comparable". The same function, the same '
        r'process, the same thread count, with and without the DLL.'),
    ...sec(r'the workload'),
    ...code('rust', 'crates/heaplens-hook/examples/self_load_concurrency_stress.rs · run_concurrent_workload', r'''
/// Runs `THREAD_COUNT` threads, each doing tight alloc/free loops for
/// `RUN_DURATION`, recording every single alloc+free pair's latency in
/// nanoseconds. Returns the flattened latency samples from all threads.
fn run_concurrent_workload() -> Vec<u64> {
    let barrier = Arc::new(Barrier::new(THREAD_COUNT));
    let mut handles = Vec::with_capacity(THREAD_COUNT);

    for _ in 0..THREAD_COUNT {
        let barrier = Arc::clone(&barrier);
        handles.push(std::thread::spawn(move || {
            barrier.wait(); // start all threads at (approximately) the same instant
            let mut samples: Vec<u64> = Vec::new();
            let deadline = Instant::now() + RUN_DURATION;
            let layout = Layout::from_size_align(ALLOC_SIZE, 8).unwrap();
            while Instant::now() < deadline {
                let t0 = Instant::now();
                let ptr = unsafe { System.alloc(layout) };
                unsafe { System.dealloc(ptr, layout) };
                samples.push(t0.elapsed().as_nanos() as u64);
            }
            samples
        }));
    }

    let mut all: Vec<u64> = Vec::new();
    for h in handles {
        all.extend(h.join().expect("stress thread panicked"));
    }
    all
}'''),
    ...para('//',
        r'The structure is a standard way to stress a shared resource '
        r'fairly. Forty-eight threads are created first, and each blocks '
        r'on a Barrier until all are ready, so that they start "at '
        r'(approximately) the same instant" and their deadline is '
        r'computed after the barrier, not before. Each thread then loops '
        r'until its deadline: read the clock, allocate 64 bytes, free '
        r'them, read the clock again, record the difference. The '
        r'allocation goes through std::alloc::System, so under the hook '
        r'it reaches RtlAllocateHeap; the free reaches RtlFreeHeap. A '
        r'pair is the unit of measurement: each timed region contains '
        r'two hooked calls, and two chances for the hook to do '
        r'something expensive.'),
    blank,
    ...para('//',
        r'Two details of the timing are careful. The push of the '
        r'sample onto the thread’s vector happens after the elapsed time '
        r'is read, so the vector’s own growth is never inside a timed '
        r'region. And every sample is kept, one u64 per pair, not '
        r'aggregated, because a percentile and a maximum cannot be '
        r'computed from a running mean.'),
    blank,
    ...para('//',
        r'That second choice has a cost the file does not mention. A '
        r'sample is eight bytes, so a hundred million samples is 800 '
        r'MB before the vectors’ growth overhead. The commit message says '
        r'the unhooked baseline of this very workload "completes hundreds '
        r'of millions of alloc/free cycles cleanly every time". The '
        r'harness’s own memory use therefore scales with the throughput '
        r'it is measuring, which is largest in the baseline, the run '
        r'that is supposed to be the quiet control. I have not '
        r'measured the harness’s footprint; this is arithmetic on the '
        r'commit’s count.'),
    ...sec(r'the report'),
    ...code('rust', 'crates/heaplens-hook/examples/self_load_concurrency_stress.rs · summarize', r'''
fn summarize(label: &str, mut samples: Vec<u64>) {
    samples.sort_unstable();
    let n = samples.len();
    if n == 0 {
        println!("[{label}] no samples captured");
        return;
    }
    let p50 = samples[n / 2];
    let p99 = samples[(n * 99) / 100];
    let p999 = samples[((n * 999) / 1000).min(n - 1)];
    let max = samples[n - 1];
    let over_1ms = samples.iter().filter(|&&ns| ns > 1_000_000).count();
    let over_10ms = samples.iter().filter(|&&ns| ns > 10_000_000).count();
    let over_100ms = samples.iter().filter(|&&ns| ns > 100_000_000).count();
    let over_1s = samples.iter().filter(|&&ns| ns > 1_000_000_000).count();
    println!(
        "[{label}] n={n} p50={:.3}us p99={:.3}us p999={:.3}us max={:.3}ms | outliers: >1ms={over_1ms} >10ms={over_10ms} >100ms={over_100ms} >1s={over_1s}",
        p50 as f64 / 1_000.0,
        p99 as f64 / 1_000.0,
        p999 as f64 / 1_000.0,
        max as f64 / 1_000_000.0,
    );
}'''),
    ...para('//',
        r'The samples are sorted once, with sort_unstable, and the '
        r'percentiles are plain index lookups: n/2 for the median, '
        r'n*99/100 for p99, and n*999/1000 clamped to the last element '
        r'for p999. The thresholds are counted with four passes over '
        r'the data. It prints microseconds for the percentiles and '
        r'milliseconds for the maximum, a unit change that suits the '
        r'two regimes: the typical pair is tiny, the interesting worst '
        r'case is not. A run produces two lines, one labelled baseline '
        r'and one hooked, in the same format.'),
    ...sec(r'the run'),
    ...code('rust', 'crates/heaplens-hook/examples/self_load_concurrency_stress.rs · main', r'''
fn main() {
    println!("self_load_concurrency_stress: {THREAD_COUNT} threads, {RUN_DURATION:?} each, alloc_size={ALLOC_SIZE}");

    // ── Baseline: unhooked, plain System allocator ──────────────────────
    println!("\n=== BASELINE (unhooked) ===");
    let baseline = run_concurrent_workload();
    summarize("baseline", baseline);

    // ── Attach (self-load, in-process, no injection) ────────────────────
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
    std::thread::sleep(Duration::from_millis(300)); // writer thread connect grace period

    println!("\n=== HOOKED (concurrent, {THREAD_COUNT} threads) ===");
    let hooked = run_concurrent_workload();
    summarize("hooked", hooked);

    let rc = unsafe { detach() };
    assert_eq!(rc, 0, "HeapLensHookDetach failed with code {rc}");

    println!("\nself_load_concurrency_stress: done");
}'''),
    ...para('//',
        r'main() is the self-load pattern of self_load_harness.rs with '
        r'a different middle. Run the baseline. Load the DLL, resolve the '
        r'two exports, attach (asserting a zero return), wait 300 ms for '
        r'the writer thread to connect, run the same workload again '
        r'under the hook, detach (asserting zero again), print a '
        r'closing line. The assertions mean that a failure to attach or '
        r'detach is a loud failure of the harness, separate from the '
        r'crash it hunts.'),
    blank,
    ...para('//',
        r'On the order of the output: because the process crashed during '
        r'the hooked workload before the fix, I read the code as '
        r'showing the baseline summary and then nothing, since the '
        r'hooked summary is printed only after the workload returns. The '
        r'commit message says as much in other words: the hooked run '
        r'"crashes reliably", the baseline "completes ... cleanly every '
        r'time". The harness was built to measure tail latency and its '
        r'first result was an access violation.'),
    ...sec(r'what it found, and how it was used afterwards'),
    ...para('//',
        r'It found the TLS crash described on the pages for '
        r'self_load_spawned_thread.rs and for heaplens-alloc’s '
        r'guard.rs. The fix, an hour later, was validated against this '
        r'file: the commit reports "20 consecutive clean runs across two '
        r'separate rebuilds, 0 failures (baseline: crashed reliably, '
        r'every run, before this fix)", and guard.rs says it was '
        r'checked "10 consecutive times". The number of runs differs '
        r'between the two accounts: the commit speaks of 20 runs across '
        r'two rebuilds and guard.rs of 10, and the repository does not '
        r'explain the difference.'),
    blank,
    ...para('//',
        r'The two accounts of its purpose also differ, in a way worth '
        r'noticing. The file’s own header says "Not a fix, not a permanent '
        r'addition — a one-off diagnostic tool". The commit that added it '
        r'is titled "standing regression test for confirmed crash '
        r'defect", says it was "intended to start passing once the '
        r'underlying defect is fixed, at which point it should be '
        r'promoted to a real gate", and the later commit 864167e, which '
        r're-enabled the Attach button, cites "a standing self-load '
        r'concurrency stress test". The file kept the first '
        r'description and lived the second. And the promotion never '
        r'happened in the automated sense: no test in the daemon crate '
        r'builds or runs this example. The ones that do cover hooks are '
        r'the Step 1 gate, the spawned-thread gate and the '
        r'exit-without-detach tests. This harness is a tool a person '
        r'runs, and the repository does not record that anyone has run '
        r'it since the fix.'),
    blank,
    ...para('//',
        r'The header also cites a sibling it calls "diag_veh.rs", the '
        r'"temporary, clearly marked" discipline. That file is not in the '
        r'repository. The test header in hook_owner_free_no_crash.rs '
        r'mentions the same kind of tool, a temporary Vectored Exception '
        r'Handler "installed for that investigation", that never caught '
        r'the fault. Both are examples of an investigation tool that '
        r'was written, used, and removed, with only a comment left '
        r'behind.'),
    ...sec(r'limits'),
    ...pt('//', r'it measures the caller, not the capture',
        r'a pair’s latency is what the allocating thread waits. The '
        r'harness does not count how many events the pipeline then '
        r'delivered. With forty-eight producers and a ring of 65,535 '
        r'slots each, a full ring drops events silently by design '
        r'(Ring::push returns false and counts it), so a clean '
        r'latency number says nothing about completeness. The Step 1 gate '
        r'measures that, with one thread.'),
    ...pt('//', r'no recorded output',
        r'the repository keeps the claims (clean runs, zero failures) '
        r'and not the numbers. I cannot quote a hooked p99 for this '
        r'harness because none is written down.'),
    ...pt('//', r'one allocation size, one pattern',
        r'64 bytes, allocate then immediately free, on every thread. That '
        r'is the friendliest possible pattern for a heap and for the '
        r'hook’s per-thread ring. It does not exercise reallocation, '
        r'large blocks, cross-thread frees or short-lived threads. The '
        r'last of those is the subject of fls_race_repro.rs.'),
    ...pt('//', r'baseline and hooked are sequential',
        r'the comparison is made across time in one process; heap state '
        r'after eight seconds of 48-thread churn is not the state before '
        r'it.'),
    ...pt('//', r'the path is brittle',
        r'dll_path() takes the executable’s grandparent and appends '
        r'heaplens_hook.dll, so the DLL has to have been built into the '
        r'same target profile directory first.'),
    ...sec(r'what to take from it'),
    ...pt('//', r'build the instrument before the theory',
        r'a stress harness with a stopwatch is cheap, and it found a '
        r'bug nobody was looking for.'),
    ...pt('//', r'keep the control in the same program',
        r'the unhooked baseline lives in the same binary as the hooked '
        r'run, so the only difference is the DLL.'),
    ...pt('//', r'say what a file is, then check that it is',
        r'the header says "one-off". The history says "standing". When '
        r'a tool outgrows its description, correct the description, or '
        r'wire the tool into the tests.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-hook/examples/self_load_concurrency_stress.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-hook/examples/self_load_concurrency_stress.rs'),
  ],
);
