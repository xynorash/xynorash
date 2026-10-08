import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/examples/checkout_service_tui.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'checkout_service_tui.rs — the demo that had to be a terminal'),
    cm('//', r'a scripted 90-second incident in a ratatui UI, chosen because a GPU '
              r'toolkit was the suspect'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'interactive terminal target for the thesis demo: press s, watch '
              r'HeapLens find a leak, a hot queue and a storm'),
    kv('language', r'Rust, ratatui 0.29 and crossterm 0.28'),
    kv('size', r'572 lines; 512 non-blank, of which only 32 are comments'),
    kv('history', r'2 commits, both 2026-07-28: 9693399 (added), a31baeb (shared event '
              r'functions)'),
    kv('schedule', r'leak at 15 s and 17 s, hot at 30 s, 33 s and 40 s, storm 45 to 60 s, '
              r'scripted window ends at 90 s'),
    ...sec(r'why a terminal'),
    ...para('//',
        r'The demo has a constraint that surprises people the first time: '
        r'it cannot be a Flutter app. The GUI sibling’s header gives the '
        r'reason in one sentence. "Flutter’s Dart VM heap is invisible to '
        r'a Rust #[global_allocator] — a Flutter-based demo target would '
        r'show nothing on HeapLens." The thing being watched has to be a '
        r'native Rust binary that links HeapLensAlloc, or be injected '
        r'into, and it has to look like a believable application.'),
    blank,
    ...para('//',
        r'The first answer was an iced GUI (checkout_service_gui.rs). On '
        r'2026-07-28, the day of the commit, it was replaced as the main '
        r'target by this file. The header gives the reason: the GUI’s '
        r'"wgpu/winit dependency surface is implicated in an undiagnosed '
        r'injection-path crash; this target avoids that dependency surface '
        r'entirely: no GPU/windowing threads, just a terminal redraw '
        r'loop". The program remains "a single native Rust binary" with '
        r'HeapLensAlloc as the global allocator; only the dependency '
        r'surface changed. The word "undiagnosed" is honest: the '
        r'repository does not claim to know the cause, only that removing '
        r'the suspect removed the risk.'),
    ...sec(r'the same behaviour as the console, with a script'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service_tui.rs · module documentation', r'''
//! `checkout_service_tui` — a ratatui/crossterm TUI wrapper around the same
//! allocation logic as `checkout_service.rs` (console) and
//! `checkout_service_gui.rs` (iced GUI, parked — its `wgpu`/`winit`
//! dependency surface is implicated in an undiagnosed injection-path crash;
//! this target avoids that dependency surface entirely: no GPU/windowing
//! threads, just a terminal redraw loop). `HeapLensAlloc` is still the
//! `#[global_allocator]`, and this remains a single native Rust binary.
//!
//! Timing model is identical to checkout_service_gui.rs's: idle ambient
//! traffic pre-start, a deterministic 90s scripted window post-start
//! (leak@15s, hot-cluster@30s/33s/40s, storm@45s/60s), then bounded
//! ambient-indefinite traffic — see SCHEDULE below.'''),
    ...para('//',
        r'It is a wrapper, in the header’s words, "around the same '
        r'allocation logic as checkout_service.rs (console) and '
        r'checkout_service_gui.rs". The timing model has three regimes. '
        r'Before the user presses s, only ambient healthy traffic. After '
        r's, a deterministic 90-second scripted window. After that, '
        r'bounded ambient traffic forever.'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service_tui.rs · the script', r'''
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ScriptEvent {
    LeakCheckout,
    LeakRelease,
    HotStart,
    HotGrow,
    HotDrain,
    StormStart,
    StormEnd,
    ScriptedWindowEnd,
}

const SCHEDULE: &[(u64, ScriptEvent)] = &[
    (15_000, ScriptEvent::LeakCheckout),
    (17_000, ScriptEvent::LeakRelease),
    (30_000, ScriptEvent::HotStart),
    (33_000, ScriptEvent::HotGrow),
    (40_000, ScriptEvent::HotDrain),
    (45_000, ScriptEvent::StormStart),
    (60_000, ScriptEvent::StormEnd),
    (90_000, ScriptEvent::ScriptedWindowEnd),
];'''),
    ...para('//',
        r'The schedule is a table of (millisecond offset, event) pairs, '
        r'and the program walks it as time passes. The shape mirrors the '
        r'console’s phases, compressed: the leak is checked out at 15 s '
        r'and released at 17 s (two seconds with the manager and its '
        r'connections visibly live, as in the console); the hot cluster '
        r'starts at 30 s with 10 orders, grows by 30 at 33 s, and is '
        r'healed at 40 s, so the owner is visible as Hot for seven '
        r'seconds; the storm runs from 45 to 60 s; and at 90 s the script '
        r'ends and the program says so.'),
    blank,
    ...para('//',
        r'A scripted schedule has a cost the console loop does not: the '
        r'events are due at wall-clock moments, but the program only '
        r'advances in ticks. fire_due_script_events handles that by firing '
        r'everything whose time has come, in order, with a cursor into the '
        r'table.'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service_tui.rs · fire_due_script_events', r'''
fn fire_due_script_events(&mut self) {
    let Some(run_start) = self.run_start else { return };
    let elapsed_ms = run_start.elapsed().as_millis() as u64;
    while self.scripted_done_through < SCHEDULE.len()
        && SCHEDULE[self.scripted_done_through].0 <= elapsed_ms
    {
        let (_, event) = SCHEDULE[self.scripted_done_through];
        self.scripted_done_through += 1;
        match event {
            ScriptEvent::LeakCheckout => {
                self.phase = Phase::FuiteActive;
                self.log("EVENT: FLAW — payment_gateway_pool checking out 12 connections (leak incoming)");
                self.leak_phase_tick(false);
            }
            ScriptEvent::LeakRelease => self.leak_phase_tick(true),
            ScriptEvent::HotStart => {
                self.phase = Phase::GrappeEnCroissance;
                self.log("EVENT: FLAW — order_queue backlog growing past healthy size (hot cluster)");
                self.hot_phase_tick(false);
            }
            ScriptEvent::HotGrow => self.hot_phase_tick(true),
            ScriptEvent::HotDrain => {
                let remnant_total = hot_cluster_heal(
                    &mut self.queue_owner,
                    &mut self.backlog,
                    &mut self.healthy_queue_owners,
                    &mut self.healthy_backlog_remnants,
                );
                self.hot_extra_added = false;
                self.log(format!(
                    "order_queue: backlog drained, back to a healthy depth ({remnant_total} orders kept alive across all cycles)"
                ));
                self.phase = Phase::Nominal;
            }
            ScriptEvent::StormStart => {
                self.phase = Phase::RafaleDeTraitement;
                self.storm_active = true;
                self.log("EVENT: FLAW — metrics_flush bursting log writes far above the healthy rate (allocation storm)");
            }
            ScriptEvent::StormEnd => {
                self.storm_active = false;
                self.phase = Phase::Nominal;
                self.log(format!(
                    "metrics_flush: {} unthrottled bursts written this phase",
                    self.storm_bursts_this_run
                ));
            }
            ScriptEvent::ScriptedWindowEnd => {
                self.log("scripted window complete — moving to ambient indefinite traffic");
            }
        }
    }
}'''),
    ...para('//',
        r'The loop condition is the whole mechanism: while the next '
        r'scheduled offset is at or before the elapsed time, take it, '
        r'advance the cursor, and match on the event. Each arm sets the '
        r'phase for the UI, logs a line, and calls the shared function '
        r'from checkout_common.rs. HotDrain calls hot_cluster_heal and '
        r'stores the owner and the 3 surviving orders in permanent '
        r'accumulators, so the healed family stays on screen.'),
    ...sec(r'the tick'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service_tui.rs · tick()', r'''
fn tick(&mut self) {
    self.tick_count += 1;
    self.this_tick_alloc_events = 0;

    if !self.started && self.tick_count == 2 && std::env::var_os("HEAPLENS_GUI_AUTOSTART").is_some() {
        self.start();
    }

    if self.started {
        self.fire_due_script_events();
    }

    let in_scripted_window = self
        .run_start
        .map(|rs| rs.elapsed() < Duration::from_millis(SCHEDULE.last().unwrap().0))
        .unwrap_or(false);
    let ambient_indefinite = self.started && !in_scripted_window;

    if self.storm_active {
        if self.tick_count % 3 == 0 {
            self.storm_burst(120);
        }
    } else {
        self.ambient_tick(2);
        if self.tick_count % 6 == 0 {
            self.spawn_order();
        }
    }

    if ambient_indefinite {
        let jitter = (self.tick_count.wrapping_mul(2654435761) >> 24) % 37;
        if jitter == 0 {
            self.ambient_tick(40);
        }
        if jitter == 5 {
            let mini = checkout_common::order_queue_accept_orders(6);
            drop(mini);
        }
    }

    self.advance_order_statuses();
    self.throughput_history.push_back(self.this_tick_alloc_events);
    while self.throughput_history.len() > MAX_SPARK_BARS {
        self.throughput_history.pop_front();
    }
}'''),
    ...para('//',
        r'Every 150 ms (TICK_MS) the program advances. It optionally '
        r'autostarts, fires due events, and then generates the background '
        r'traffic. During the storm it does 120 metrics writes on every '
        r'third tick. Otherwise it does ambient traffic: two '
        r'request_handle calls per tick, and a fake order row every sixth '
        r'tick. After the scripted window it adds a seeded-looking jitter:'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service_tui.rs · jitter after the scripted window', r'''
if ambient_indefinite {
    let jitter = (self.tick_count.wrapping_mul(2654435761) >> 24) % 37;
    if jitter == 0 {
        self.ambient_tick(40);
    }
    if jitter == 5 {
        let mini = checkout_common::order_queue_accept_orders(6);
        drop(mini);
    }
}'''),
    ...para('//',
        r'(tick_count * 2654435761) >> 24, modulo 37, is a pseudo-random '
        r'number with no dependency on the rand crate. The constant is '
        r'0x9E3779B1, the widely used Knuth multiplicative-hash constant '
        r'derived from the golden ratio. When the result is 0 the program '
        r'does a 40-request blip; when it is 5 it allocates and '
        r'immediately frees a small batch of 6 orders. If the values are '
        r'evenly spread, each happens once per 37 ticks on average, about '
        r'every 5.5 seconds. The comment that goes with the GUI twin '
        r'states the intent: "Jittered, bounded extra traffic. Never '
        r'accumulates — orders complete and free at a rate that keeps the '
        r'view readable. The leak accumulator is deliberately exempt." '
        r'Notably, rand was added to the crate’s Cargo.toml in the same '
        r'commit and is not used here.'),
    ...sec(r'the arithmetic of the storm'),
    ...para('//',
        r'Here is something worked out from the code, not from a run. The '
        r'storm arm fires storm_burst(120) when tick_count is a multiple '
        r'of 3. At 150 ms per tick that is a burst of 120 allocations '
        r'about every 450 ms (more, if drawing takes time), which is '
        r'roughly 267 allocations a second. The daemon’s StormTracker '
        r'counts allocations at one site inside a window of 1,000 ms and '
        r'flags a storm above 1,000. Three bursts fit in a window, so the '
        r'in-window count peaks near 360. That is below the threshold of '
        r'1,000.'),
    blank,
    ...para('//',
        r'So with the default daemon settings the TUI’s storm phase would '
        r'not raise the daemon’s storm warning, though the phase label '
        r'says "rafale de traitement" and the throughput sparkline spikes. '
        r'The console variant bursts 2,000 at a time and does cross it. '
        r'Unless the demo is launched with HEAPLENS_STORM_RATE lowered (a '
        r'variable the daemon reads), the UI’s allocation-storm insight '
        r'would not appear for this target. The target was not run for '
        r'this page and how the demo was launched is not recorded in the '
        r'repository; this is a reading to check, not a result. There is a '
        r'further complication: the tracker is keyed on the first captured '
        r'address, which in a Linux probe was the same for every '
        r'allocation (see the chaos_storm.rs page). If the same holds on '
        r'Windows, every allocation in the process counts toward one '
        r'bucket, including the allocations of the terminal redraw itself, '
        r'and the arithmetic above is only a lower bound. The wire test '
        r'for this target only asserts the leak and hot shapes, so nothing '
        r'in the repository would catch it.'),
    ...sec(r'validation hooks'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service_tui.rs · run(), and the headless switch', r'''
fn run(terminal: &mut ratatui::Terminal<ratatui::backend::CrosstermBackend<Stdout>>, state: &mut State) -> std::io::Result<()> {
    // Validation-only: HEAPLENS_GUI_AUTOSTART (same env var that drives
    // autostart) also skips the actual terminal draw and event::poll here.
    // Rendering to an inherited console under an automated test harness can
    // be far slower than a native terminal, which starves the real-time
    // schedule loop and lets multiple T+Ns events become due in the same
    // tick — their alloc+free events then land in the same daemon diff
    // batch and cancel out (drain_diff's documented same-window
    // cancellation), hiding real peak topology from an observer. The
    // schedule itself is still driven by real Instant::now(), so this only
    // removes console I/O from the loop, not timing accuracy.
    let headless = std::env::var_os("HEAPLENS_GUI_AUTOSTART").is_some();

    loop {
        if !headless {
            terminal.draw(|f| ui(f, state))?;

            if event::poll(Duration::from_millis(TICK_MS))? {
                if let Event::Key(key) = event::read()? {
                    match key.code {
                        KeyCode::Char('q') | KeyCode::Esc => state.quit = true,
                        KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => state.quit = true,
                        KeyCode::Char('s') => state.start(),
                        _ => {}
                    }
                }
            }
        } else {
            std::thread::sleep(Duration::from_millis(TICK_MS));
        }

        if state.quit {
            return Ok(());
        }

        state.tick();
    }'''),
    ...para('//',
        r'The event loop draws the UI, waits up to 150 ms for a key (q, '
        r'Esc or Ctrl-C quits, s starts), and ticks. The detail to notice '
        r'is the variable HEAPLENS_GUI_AUTOSTART. When it is set, the '
        r'program starts itself on the second tick, logs to stderr, and '
        r'also skips drawing and polling for input entirely. The comment '
        r'gives the reason, and it is a good lesson in how a test harness '
        r'can corrupt the thing it is measuring: "Rendering to an '
        r'inherited console under an automated test harness can be far '
        r'slower than a native terminal, which starves the real-time '
        r'schedule loop and lets multiple T+Ns events become due in the '
        r'same tick — their alloc+free events then land in the same daemon '
        r'diff batch and cancel out (drain_diff’s documented same-window '
        r'cancellation), hiding real peak topology from an observer."'),
    blank,
    ...para('//',
        r'That is a precise chain of causes. A slow console makes a tick '
        r'late; late ticks make events pile up; events that pile up land '
        r'in one batch; and the daemon’s diff builder deliberately hides '
        r'anything born and freed within one batch. The daemon’s own '
        r'comment in drain_diff says "Nodes born and freed within the same '
        r'tick are invisible to the consumer." So the observer sees '
        r'nothing of a phase that happened too fast. The fix is to take '
        r'rendering out of the loop when testing; the schedule itself '
        r'still runs from real Instant::now(), so "this only removes '
        r'console I/O from the loop, not timing accuracy".'),
    blank,
    ...para('//',
        r'The variable is named GUI because the TUI evidently inherited it '
        r'from the GUI target. It is documented as validation-only; '
        r'presenters never set it.'),
    ...sec(r'the interface'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service_tui.rs · the layout', r'''
fn ui(f: &mut Frame, s: &State) {
    let root = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(0)])
        .split(f.area());

    draw_header(f, root[0], s);

    let body = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(70), Constraint::Percentage(30)])
        .split(root[1]);

    let left = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Min(8),
            Constraint::Length(3),
            Constraint::Length(6),
            Constraint::Min(6),
        ])
        .split(body[0]);

    draw_orders(f, left[0], s);
    draw_gauge(f, left[1], s);
    draw_sparkline(f, left[2], s);
    draw_log(f, left[3], s);

    draw_controller(f, body[1], s);
}'''),
    ...para('//',
        r'The screen is a header, then a 70/30 split. The left column '
        r'stacks an orders list, a pool gauge, a throughput sparkline and '
        r'a journal; the right column is the controller. Everything the '
        r'user sees is in French: "Commandes en direct", "Pool de '
        r'connexions (payment_gateway_pool)", "Débit (metrics_flush)", '
        r'"Journal", "Contrôleur de test", "Démarrer", "Quitter", and the '
        r'phase names "fuite active", "grappe en croissance", "rafale de '
        r'traitement". The audience for the demo is a French-language '
        r'jury, a thesis defence, and the program is dressed for it. The '
        r'header shows "Système opérationnel" in a green badge no matter '
        r'what is going on, which makes the point of the whole demo: the '
        r'application’s own dashboard says everything is fine.'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service_tui.rs · the pool gauge', r'''
fn draw_gauge(f: &mut Frame, area: Rect, s: &State) {
    let checked_out = s.leaked_connections.len() + s.pool_manager.as_ref().map(|_| 12).unwrap_or(0);
    let color = if checked_out == 0 {
        Color::Green
    } else if checked_out < 40 {
        Color::Yellow
    } else {
        Color::Red
    };
    let ratio = (checked_out as f64 / 80.0).min(1.0);
    let gauge = Gauge::default()
        .block(Block::default().borders(Borders::ALL).title(" Pool de connexions (payment_gateway_pool) "))
        .gauge_style(Style::default().fg(color))
        .ratio(ratio)
        .label(format!("{checked_out} connexions retenues"));
    f.render_widget(gauge, area);
}'''),
    ...para('//',
        r'The gauge is the one widget with a real connection to the leak. '
        r'It counts leaked connections plus 12 if the manager is still '
        r'live, shows the ratio against 80, and turns green below 1, '
        r'yellow below 40 and red at or above 40. The application’s own '
        r'view of the leak is a number, rising with every cycle; HeapLens’ '
        r'view is the graph that says which allocations are lost and why.'),
    ...sec(r'what the test does with it'),
    ...para('//',
        r'The daemon’s cross_process_wire_tui.rs spawns this binary with '
        r'HEAPLENS_GUI_AUTOSTART=1, watches for 38 seconds (wider than the '
        r'GUI’s window because a headless console is slower), kills it, '
        r'and, after checking that events arrived and that more than one '
        r'call-site name was seen, asserts two things: some node has a '
        r'fan-out between 8 and 14 (the leak’s manager with its 12 '
        r'connections) and some node has a fan-out of 25 or more (the hot '
        r'queue at its peak of 40). Its own comments are stale in one '
        r'detail: it still says the target is "the iced GUI demo target" '
        r'and the helper is called gui_target_path.'),
    blank,
    ...para('//',
        r'The thresholds are loose by design. As noted on the '
        r'checkout_common.rs page, a node with 30 children satisfies the '
        r'hot assertion as well as one with 40, which is how the lazily '
        r'grown backlog bug passed through unnoticed.'),
    ...sec(r'limits'),
    ...pt('//',
        r'the storm may not register',
        r'see the arithmetic above.'),
    ...pt('//',
        r'the opt-in',
        r'cooperative capture needs HEAPLENS_ENABLE; the intended route '
        r'for the demo is attaching from the UI’s picker.'),
    ...pt('//',
        r'raw mode without a safety net',
        r'main enables raw mode and the alternate screen, runs, then '
        r'restores them. There is no panic hook in the file, so a panic '
        r'inside the loop would, as far as the code shows, leave the '
        r'terminal in raw mode.'),
    ...pt('//',
        r'display numbers are approximate',
        r'the throughput bars count events the program believes it made (1 '
        r'plus the connections, and so on), not what the allocator '
        r'recorded.'),
    ...pt('//',
        r'no tests of the UI',
        r'the only automated check is the topology assertion above.'),
    ...sec(r'related'),
    ...pt('//',
        r'support/checkout_common.rs',
        r'the four event functions this file calls.'),
    ...pt('//',
        r'checkout_service.rs',
        r'the console version of the same story.'),
    ...pt('//',
        r'checkout_service_gui.rs',
        r'the parked iced version.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/examples/checkout_service_tui.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/examples/checkout_service_tui.rs'),
  ],
);
