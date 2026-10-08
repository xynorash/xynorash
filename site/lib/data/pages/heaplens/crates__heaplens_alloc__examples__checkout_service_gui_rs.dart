import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-alloc/examples/checkout_service_gui.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'checkout_service_gui.rs — the iced window that was parked on the day '
              r'it was committed'),
    cm('//', r'a native GUI demo target, kept in the tree after a terminal took its '
              r'job'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'iced (Elm-style) GUI wrapper around the checkout scenario; parked in '
              r'favour of the TUI'),
    kv('language', r'Rust, iced 0.13 (wgpu, winit), HeapLensAlloc as the global allocator'),
    kv('size', r'564 lines; the view() function alone is about 140'),
    kv('history', r'one commit, 9693399 (2026-07-28), the same commit that added the TUI '
              r'replacing it'),
    kv('status', r'"parked" in the TUI’s and the shared module’s own words'),
    ...sec(r'why a GUI that is a Rust program'),
    ...para('//',
        r'The header explains a constraint that shapes this whole '
        r'directory: "This target exists because Flutter’s Dart VM heap is '
        r'invisible to a Rust #[global_allocator] — a Flutter-based demo '
        r'target would show nothing on HeapLens. This binary links '
        r'HeapLensAlloc directly and drives the exact same checkout_common '
        r'allocation sites as the console version, from an iced Elm-style '
        r'app instead of a loop { }."'),
    blank,
    ...para('//',
        r'HeapLens’ own UI is a Flutter app. If the demo target were a '
        r'Flutter app too, its allocations would happen inside the Dart '
        r'VM’s heap, which never touches the Rust global allocator, so the '
        r'tool would have nothing to observe. The demo target therefore '
        r'has to be native Rust (or be injected into). iced is a Rust GUI '
        r'toolkit built on the Elm architecture: state, messages, an '
        r'update function and a view function. It was the natural choice '
        r'for a program that has to look like an application with buttons '
        r'and a dashboard.'),
    ...sec(r'the Elm shape'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service_gui.rs · module documentation', r'''
//! `checkout_service_gui` — an iced-based, production-realistic GUI wrapper
//! around the same allocation logic as `checkout_service.rs` (the console
//! fallback). This target exists because Flutter's Dart VM heap is invisible
//! to a Rust `#[global_allocator]` — a Flutter-based demo target would show
//! nothing on HeapLens. This binary links `HeapLensAlloc` directly and
//! drives the exact same `checkout_common` allocation sites as the console
//! version, from an iced Elm-style app instead of a `loop { }`.
//!
//! Timing model:
//!   - Idle (pre "Démarrer"): ambient healthy traffic only, indefinitely.
//!   - Scripted (T+0..90s post "Démarrer"): deterministic schedule matching
//!     checkout_service.rs's own phase shapes (leak / hot cluster / storm),
//!     compressed into a fixed 90s window instead of an infinite 15s-cycle
//!     repeat — see SCHEDULE below.
//!   - Ambient-indefinite (T+90s+): jittered, bounded ambient traffic. The
//!     leaked connections from the scripted leak keep accumulating forever
//!     by design (that's the point of a leak); everything else stays
//!     bounded so the UI stays readable over a long run.
use heaplens_alloc::HeapLensAlloc;'''),
    ...para('//',
        r'There are two messages, Tick and StartPressed. update changes '
        r'the state, view draws it, and a subscription (iced::time::every, '
        r'150 ms) delivers ticks. main is a few lines:'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service_gui.rs · main', r'''
fn main() -> iced::Result {
    iced::application("Checkout Ops Console", State::update, State::view)
        .subscription(State::subscription)
        .theme(|_state: &State| Theme::Dark)
        .run()
}'''),
    ...para('//',
        r'The program is a state machine that advances on a timer, and '
        r'that fits the scenario perfectly: a scripted incident is a '
        r'timeline, and a tick that checks "is anything due?" is all it '
        r'takes.'),
    blank,
    ...para('//',
        r'The timing model is the same as the TUI’s: ambient healthy '
        r'traffic before the Start button is pressed, then a deterministic '
        r'90-second script, then bounded jittered traffic forever. The '
        r'header describes it as "compressed into a fixed 90s window '
        r'instead of an infinite 15s-cycle repeat". The schedule is '
        r'identical:'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service_gui.rs · SCHEDULE', r'''
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
        r'It is the same eight events at the same offsets as in '
        r'checkout_service_tui.rs. Both files carry their own copy of the '
        r'table; nothing shares it.'),
    ...sec(r'the part that is not shared'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service_gui.rs · the owner funnels', r'''
// ── Owner-allocation funnels ────────────────────────────────────────
// Both call sites for a given owner's children route through the SAME
// named function so phi's ancestor-frame matching sees a consistent
// effective site for the owner, exactly like `main`'s loop body does
// for the console version. Do not split these into separate methods.

#[inline(never)]
fn leak_phase_tick(&mut self, release: bool) {
    if !release {
        self.pool_manager = Some(vec![0u8; 256]);
        let connections = payment_gateway_pool_checkout_connections(12);
        self.this_tick_alloc_events += 1 + connections.len() as u32;
        // Held live alongside pool_manager until release, matching the
        // console version's 2s hold before the manager is dropped.
        self.leaked_connections_pending = Some(connections);
    } else if let Some(conns) = self.leaked_connections_pending.take() {
        self.pool_manager = None; // the bug: manager torn down first
        let n = conns.len();
        self.leaked_connections.extend(conns);
        self.log(format!(
            "payment_gateway_pool: manager freed — {n} connections now orphaned and will never be released"
        ));
    }
}

#[inline(never)]
fn hot_phase_tick(&mut self, add_extra: bool) {
    if self.queue_owner.is_none() {
        self.queue_owner = Some(vec![0u8; 512]);
        let initial = order_queue_accept_orders(10);
        self.this_tick_alloc_events += 1 + initial.len() as u32;
        self.backlog.extend(initial);
    }
    if add_extra && !self.hot_extra_added {
        let extra = order_queue_accept_orders(30);
        self.this_tick_alloc_events += extra.len() as u32;
        self.backlog.extend(extra);
        self.hot_extra_added = true;
        self.log(format!("order_queue: backlog at {} orders and still growing", self.backlog.len()));
    }
}

#[inline(never)]
fn storm_burst(&mut self, n: usize) {
    for i in 0..n {
        metrics_flush_write_entry(i);
    }
    self.this_tick_alloc_events += n as u32;
    self.storm_bursts_this_run += 1;
}'''),
    ...para('//',
        r'This is where the GUI differs from the later TUI and console. '
        r'Those two now call leak_pool_tick, hot_cluster_tick and '
        r'storm_burst from checkout_common.rs. The GUI keeps its own '
        r'copies, as methods on State: leak_phase_tick allocates the pool '
        r'manager (a 256-byte vec) and then calls the shared '
        r'payment_gateway_pool_checkout_connections(12); hot_phase_tick '
        r'allocates the 512-byte queue owner and calls the shared '
        r'order_queue_accept_orders. The comment above them gives the '
        r'reasoning: "Both call sites for a given owner’s children route '
        r'through the SAME named function so phi’s ancestor-frame matching '
        r'sees a consistent effective site for the owner ... Do not split '
        r'these into separate methods."'),
    blank,
    ...para('//',
        r'The rule is right, and it is the same rule as everywhere else. '
        r'But look at what the shared module later learned.'),
    ...sec(r'what the GUI never received'),
    ...para('//',
        r'The shared module changed twice after this file was written, on '
        r'the same day, and the GUI got neither change. The GUI was not '
        r'run for this page, so what follows is a reading of the code '
        r'against the commit messages:'),
    blank,
    ...pt('//',
        r'the heal',
        r'HotDrain here still does this:'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service_gui.rs · HotDrain, the old way', r'''
ScriptEvent::HotDrain => {
    self.backlog.clear();
    self.queue_owner = None;
    self.hot_extra_added = false;
    self.log("order_queue: backlog drained, back to a healthy depth");
    self.phase = Phase::Nominal;
}'''),
    ...para('//',
        r'backlog.clear() and queue_owner = None free everything, owner '
        r'and orders alike. Commit a31baeb changed the console and the TUI '
        r'to a "heal in place": free the excess, keep the owner and a few '
        r'orders alive, because freeing everything "made the whole family '
        r'vanish from the graph, indistinguishable from ’nothing was ever '
        r'here.’" The GUI would still make the family vanish.'),
    blank,
    ...pt('//',
        r'the reserve',
        r'hot_phase_tick starts from self.backlog, a field that begins as '
        r'an empty Vec::new(), and extends it from inside the method after '
        r'the owner exists, with no reserve. That is the exact shape that '
        r'commit d192626 diagnosed in the shared version: the backlog’s '
        r'first buffer is allocated at the owner’s call site, is newer '
        r'than the owner, and wins the tie-break for the second batch of '
        r'30, so the owner is left with about 10 children and does not '
        r'reach the hot threshold of 32. By that reading the GUI would not '
        r'show the owner turning Hot.'),
    blank,
    ...para('//',
        r'It is only a reading because the daemon test for this target '
        r'(cross_process_wire_gui.rs, added in the same commit) would not '
        r'necessarily notice: it asserts a leak star with fan-out between '
        r'8 and 14 and a "hot star" of 25 or more children, and a backlog '
        r'buffer holding 30 children satisfies the second as well as a '
        r'real hot owner would.'),
    ...sec(r'a window as a dashboard'),
    ...code('rust', 'crates/heaplens-alloc/examples/checkout_service_gui.rs · subscription', r'''
fn subscription(&self) -> Subscription<Message> {
    iced::time::every(Duration::from_millis(TICK_MS)).map(Message::Tick)
}'''),
    ...para('//',
        r'The view is conventional iced. A header row with the title, a '
        r'green "Système opérationnel" badge, and elapsed seconds. A left '
        r'column with the live order list, a pool gauge (a progress_bar '
        r'over 0 to 80, coloured by how many connections are held), a '
        r'"throughput" sparkline built from a row of fixed-width '
        r'containers whose heights are the events counted per tick '
        r'(clamped to between 2 and 150 pixels, last 36 ticks), and a '
        r'scrollable journal. A right column with the "Contrôleur de test" '
        r'panel, the green "Démarrer" button, a countdown to the next '
        r'scheduled event and a coloured phase label. Strings are French '
        r'because the audience is.'),
    blank,
    ...para('//',
        r'The badge is hard-coded green. It never changes, whatever the '
        r'scenario does. That is the demo’s point: the application’s own '
        r'dashboard is cheerful and wrong, and the heap tool is the one '
        r'that notices.'),
    ...sec(r'why it was parked'),
    ...para('//',
        r'The TUI’s header gives the reason in a sentence, and the shared '
        r'module repeats it ("iced GUI demo, parked"): the GUI’s '
        r'"wgpu/winit dependency surface is implicated in an undiagnosed '
        r'injection-path crash". Attaching the hook DLL to a process that '
        r'loads a GPU stack and creates windowing threads was suspected of '
        r'crashing it. The suspicion was never resolved, and replacing the '
        r'GUI with a terminal UI removed the variable. The file stayed in '
        r'the tree, with its test, and with iced still listed in '
        r'Cargo.toml.'),
    blank,
    ...para('//',
        r'The history is compressed to a single day. Both the GUI and the '
        r'TUI first appear in commit 9693399 on 2026-07-28, titled "TUI '
        r'backdrop (ratatui/crossterm, replaces iced GUI) + attach button '
        r're-enabled for soutenance". The GUI never had an earlier commit '
        r'in this repository; it was committed already parked. It reads as '
        r'work the author built and then set aside before the thesis '
        r'defence, kept in the tree rather than deleted.'),
    ...sec(r'things to know before reusing it'),
    ...pt('//',
        r'the dependency cost',
        r'building this example compiles iced, wgpu and winit. A first '
        r'Linux test build of the crate took 1 minute 23 seconds and its '
        r'log is full of wgpu, naga and winit compilation, and the commit '
        r'that added the toolkit grew the lock file from 100 packages to '
        r'485.'),
    ...pt('//',
        r'two copies of the script',
        r'SCHEDULE exists here and in the TUI.'),
    ...pt('//',
        r'the autostart hook',
        r'like the TUI it honours HEAPLENS_GUI_AUTOSTART, a '
        r'validation-only switch that starts the scripted window by itself '
        r'on the second tick so a test can drive it without a mouse.'),
    ...pt('//',
        r'the opt-in',
        r'cooperative capture needs HEAPLENS_ENABLE, or attach through the '
        r'injector.'),
    ...sec(r'limits'),
    ...pt('//',
        r'staleness',
        r'it lags the shared module, as above.'),
    ...pt('//',
        r'needs a GPU stack',
        r'it cannot run where wgpu cannot initialise.'),
    ...pt('//',
        r'no UI tests',
        r'only the topology assertion in the daemon’s wire test.'),
    ...sec(r'related'),
    ...pt('//',
        r'checkout_service_tui.rs',
        r'the terminal replacement.'),
    ...pt('//',
        r'support/checkout_common.rs',
        r'the shared logic the GUI only partly uses.'),
    ...pt('//',
        r'Cargo.toml',
        r'where iced still lives.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-alloc/examples/checkout_service_gui.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-alloc/examples/checkout_service_gui.rs'),
  ],
);
