import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/tests/cross_process_wire_tui.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'cross_process_wire_tui.rs — the GUI test, copied for a terminal target'),
    cm('//', r'the same two-star assertion, run against a ratatui app, with a few comments that still say GUI'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'end-to-end test that the ratatui demo target produces the console demo’s ownership shapes'),
    kv('language', r'Rust, tokio multi-thread runtime, Windows only (#![cfg(windows)])'),
    kv('size', r'168 lines, 1 test, one commit: 9693399 (2026-07-28)'),
    kv('exercises', r'ingest::run, OwnershipGraph, Resolver, checkout_service_tui.exe (heaplens-alloc example)'),
    kv('differs from the GUI test', r'the executable name, the outer timeout (65 s, not 45 s) and a comment about console rendering'),
    ...sec(r'what it is'),
    ...para('//',
        r'The demo that the project shows is a terminal application: the heaplens-alloc example checkout_service_tui, built with ratatui and crossterm. Its allocation sites live in the same shared helpers as the console and GUI targets (support/checkout_common.rs), but they run inside a terminal UI loop. This test makes the identical claim as cross_process_wire_gui.rs, that a leak star (the pool manager with about 12 connections) and a hot star (the queue owner with up to 40 orders) both appear in the ownership graph built from the pipe. Everything about the harness is shared with that page, so this one concentrates on what differs and on what the copy left behind.'),
    blank,
    ...sec(r'the differences, in the diff'),
    ...code('rust', r'crates/heaplens-daemon/tests/cross_process_wire_tui.rs · lines 35-48', r'''
fn gui_target_path() -> std::path::PathBuf {
    let test_exe = std::env::current_exe().unwrap();
    let target_debug = test_exe.parent().and_then(|p| p.parent()).expect("cannot determine target dir");
    target_debug.join("examples").join("checkout_service_tui.exe")
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn checkout_service_tui_matches_console_topology() {
    let target = gui_target_path();
    if !target.exists() {
        panic!(
            "checkout_service_tui.exe not found at {:?}.\nBuild it first: cargo build --example checkout_service_tui -p heaplens-alloc",
            target
        );'''),
    ...para('//',
        r'The helper is still named gui_target_path, but it returns checkout_service_tui.exe, and the test is checkout_service_tui_matches_console_topology. The name of a function is the first sign that this is a copy.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/cross_process_wire_tui.rs · lines 60-73', r'''
    let mut child = std::process::Command::new(&target)
        .env("HEAPLENS_GUI_AUTOSTART", "1")
        .spawn()
        .unwrap_or_else(|e| panic!("failed to spawn checkout_service_tui: {e}"));

    let graph_handle = tokio::spawn(async move {
        let mut graph = OwnershipGraph::new();
        let mut resolver = Resolver::new();
        // Cover leak (T+15/17s) and hot-cluster grow (T+30/33s) with margin
        // before hot-drain (T+40s) clears the backlog. Wider than the GUI
        // target's window: rendering to an inherited console under the test
        // harness is slower than a native terminal, so real-wall-clock
        // schedule firing can lag noticeably behind the iced target's pace.
        let deadline = tokio::time::Instant::now() + Duration::from_secs(38);'''),
    ...para('//',
        r'Two things here. First, the environment variable is still HEAPLENS_GUI_AUTOSTART. That is correct: the TUI example reads the same variable (checkout_service_tui.rs checks it at three places, and a comment there says it is the same variable that drives the GUI), so the test did not need a new name. Second, the comment promises something the code does not do: "Wider than the GUI target’s window: rendering to an inherited console under the test harness is slower than a native terminal, so real-wall-clock schedule firing can lag noticeably behind the iced target’s pace." The deadline on the next line is still 38 seconds, identical to the GUI test’s.'),
    blank,
    ...code('rust', r'crates/heaplens-daemon/tests/cross_process_wire_tui.rs · lines 127-133', r'''
    match tokio::time::timeout(Duration::from_secs(65), graph_handle).await {
        Ok(Ok(())) => {}
        Ok(Err(e)) => panic!("graph task panicked: {e}"),
        Err(_) => panic!("graph task did not finish within timeout"),
    }

    // GUI never exits on its own — kill it now that sampling is done.'''),
    ...para('//',
        r'What did get wider is the ceiling on awaiting the graph task: 65 seconds, against the GUI test’s 45. That ceiling never matters in a healthy run, since the graph task ends itself at its 38-second deadline; it only bounds a hang. So the comment’s concern (a slow console delaying the T+30 and T+33 growth past the sampling window) is not addressed by the change that was made.'),
    blank,
    ...sec(r'the assertions'),
    ...code('rust', r'crates/heaplens-daemon/tests/cross_process_wire_tui.rs · lines 141-166', r'''
    assert!(s.alloc_count > 0, "no alloc events observed at all — wire/framing failure");
    assert!(
        s.non_machinery_names.len() > 1,
        "expected multiple distinct non-machinery call sites, got {:?}",
        s.non_machinery_names
    );

    // Two independent owner stars are expected: leak's pool_manager (fan-out
    // ~12, allocated in leak_phase_tick) and hot cluster's queue_owner
    // (fan-out ~40 at peak before drain, allocated in hot_phase_tick) — not
    // one combined root like wire_producer's single long-lived container,
    // because these two owners come from two distinct named functions.
    let mut fan_outs: Vec<usize> = s.final_edges.values().map(|e| e.len()).filter(|&n| n > 1).collect();
    fan_outs.sort_unstable();
    eprintln!("Observed fan-outs > 1: {fan_outs:?}");

    let has_leak_star = fan_outs.iter().any(|&n| (8..=14).contains(&n));
    let has_hot_star = fan_outs.iter().any(|&n| n >= 25);

    assert!(
        has_leak_star,
        "expected an owner with fan-out ~12 (leak's pool_manager -> connections), got fan-outs {fan_outs:?}"
    );
    assert!(
        has_hot_star,
        "expected an owner with fan-out >= 25 (hot cluster's queue_owner -> orders, peak 40), got fan-outs {fan_outs:?}"'''),
    ...para('//',
        r'Unchanged from the GUI test: some alloc events, more than one non-machinery name, a fan-out in 8 to 14 (leak) and one of at least 25 (hot). The failure messages are the same strings, including "leak’s pool_manager -> connections" and "queue_owner -> orders, peak 40".'),
    blank,
    ...sec(r'the copy-paste residue'),
    ...para('//',
        r'· The module doc says checkout_service_tui is "the iced GUI demo target" and talks about iced’s Elm-style update loop. The target is ratatui.'),
    ...para('//',
        r'· "a GUI" appears in the never-exits sentence, and GUI appears in the "never exits on its own" and the summary-print strings.'),
    ...para('//',
        r'· The eprintln for the summary says "GUI wire test summary".'),
    ...para('//',
        r'None of these changes behaviour. They would only mislead someone reading a failure. I note them as they are, not as a fix.'),
    blank,
    ...sec(r'a shared resource'),
    ...para('//',
        r'Like every wire test in this crate, it uses the pipe name \\.\pipe\heaplens, the same one a running daemon uses. Cargo runs separate test binaries one after another by default, so the GUI, TUI and console wire tests do not collide in a plain cargo test; two of them started by hand in separate shells would.'),
    blank,
    ...sec(r'why both exist'),
    ...para('//',
        r'The commit message reads "TUI backdrop (ratatui/crossterm, replaces iced GUI)". The GUI test was kept and the TUI test was added beside it, which is why there are two almost identical files. A single test parameterised on the executable name would remove roughly 150 duplicated lines.'),
    blank,
    ...sec(r'history'),
    ...para('//',
        r'One commit, 9693399 (2026-07-28). Never edited since.'),
    blank,
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/tests/cross_process_wire_tui.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/tests/cross_process_wire_tui.rs'),
  ],
);
