import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/docs/superpowers/plans/2026-07-06-heaplens-flutter-m5.md',
  lines: [
    heading('# heaplens_flutter M5 — Build Plan'),
    blank,
    ...text('The plan for the only part of HeapLens a person '
        'looks at. It is short, strict about what the app may '
        'know, and has an addendum that matters more than the '
        'plan: after the milestone shipped with every test green, '
        'a human opened it and saw an empty canvas. The way that '
        'was investigated is the best lesson in the five plans.'),
    blank,
    kv('role', 'Stage 5 build plan: the Flutter client (milestone M5)'),
    kv('date', 'plan 2026-07-06 20:24 (9ac04cd); addendum 2026-07-07 09:09'),
    kv('size', '345 lines · 5 locked decisions · 10 tasks · 1 addendum'),
    kv('executed', '20:28 to 23:08 on 2026-07-06, 19 commits after the plan'),
    kv('branch', 'dev/phase_5 from 3b6b4a2; merged 2026-07-07 08:24 (1493a4c)'),

    ...sec('the boundary the plan draws'),
    ...text('Two lines at the top say the most important thing '
        'about the design of the app:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-06-heaplens-flutter-m5.md · concern boundary', r'''
**Concern boundary:** the app knows only the JSON contract on `ws://127.0.0.1:9999`
(`heaplens-protocol`'s `diff.rs`). No Rust knowledge, no daemon-internals
assumptions.'''),
    ...text('Scope is the heaplens_flutter directory alone, with '
        'no Rust changes allowed on the branch. That constraint '
        'is what makes the work parallelisable, and it makes a '
        'second kind of test possible: any mismatch between what '
        'the daemon sends and what the app parses is, by '
        'construction, a protocol bug and not an app bug.'),

    ...sec('groundwork: real fixtures'),
    ...text('Before any Dart model existed the plan commits four '
        'JSON files captured from a live daemon: a snapshot with '
        '101 live nodes, an add diff with 101 nodes, a remove diff '
        'freeing the same 101, and an orphan diff. A sidecar, '
        'PROVENANCE.md, says exactly how they were produced, and '
        'is unusually frank about the one that was not fully real:'),
    ...code('markdown', 'heaplens_flutter/test/fixtures/PROVENANCE.md · diff_orphan.json', r'''
- `diff_orphan.json` — the `update[0]` entry is a **real captured `NodeDto`**
  (same node as `diff_add.json` id `500`), with only the `state` field
  hand-flipped from `"healthy"` to `"orphan"`. The capture rig frees an'''),
    ...text('The reason is stated: the capture rig frees an owner '
        'and its children together, so the owner-freed-but-child-'
        'alive window that defines an orphan never occurred '
        'naturally. The fixture exists to pin one thing, how the '
        '“orphan” string deserialises, and every other field is '
        'unmodified. A fabricated value is acceptable in a test '
        'if the file says which value and why.'),
    ...text('The first task then uses these as the contract:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-06-heaplens-flutter-m5.md · Task 1 (trimmed)', r'''
- If any fixture fails to parse or a field is silently dropped, that is a
  **protocol bug** — do not adapt the model to accommodate it; report it
  instead of "fixing" the model to hide a real mismatch.'''),
    ...text('That instruction guards against the most natural '
        'mistake in client work: when the data does not fit your '
        'model, bend the model. Here the executor is told to stop '
        'and report. It follows the Stage 1 principle that the '
        'contract lives in one place.'),

    ...sec('five locked decisions'),
    ...bullet('Q1, desktop only',
        'Dart VM on Windows, never Flutter web, because pointer-'
        'sized numbers as JSON numbers are unsafe under dart2js. '
        'The plan cites the seam note in diff.rs by name.'),
    ...bullet('Q2, hand-written models',
        'field names mirror diff.rs exactly (id, ptr, size, ts, '
        'symbol, live, state, edges); unknown state strings fall '
        'back to healthy with a debug log; no freezed, no '
        'json_serializable, no build_runner. Lenient parsing, '
        'because the Rust side deserialises leniently too.'),
    ...bullet('Q3, a revision counter',
        'covered next.'),
    ...bullet('Q4, physics apart from data',
        'the layout engine owns its own map of simulated nodes '
        '(position, velocity, radius, fade) separate from the '
        'wire data. A field update never moves a node. A removed '
        'node fades for about a second, on the simulation’s '
        'clock, before it is deleted.'),
    ...bullet('Q5, four widgets',
        'graph canvas, memory map, control bar, node detail.'),

    ...sec('Q3: state that is deliberately not immutable'),
    ...text('Riverpod’s convention is that state is an immutable '
        'value. The plan breaks it on purpose. The graph provider '
        'holds a private mutable map and exposes only a counter '
        'as its state, and the rule for consumers is stated as a '
        'hard constraint: “revision is the only value any '
        'provider watches off graph_provider.dart — never watch '
        'the map itself”. The code carries the justification where '
        'a future cleanup would trip over it:'),
    ...code('dart', 'heaplens_flutter/lib/providers/graph_provider.dart · class doc (trimmed)', r'''
/// INTENTIONAL DESIGN (locked decision, see M5 task-3 brief Q3): this
/// `Notifier`'s state is the `revision` int, *not* the node map itself. The
/// node map ([_nodes]) is a private `Map<int, NodeDto>` that is mutated in
/// place on every [applyDiff] call.'''),
    ...text('The reason, in the same comment, is performance: '
        'the daemon can push around thirty diffs a second, and '
        'copying a large map that often is waste. A counter '
        'tells a widget when to repaint; the data is read '
        'fresh from the notifier. The cost is a rule that '
        'cannot be enforced by types, only by a loud comment '
        '(“Do NOT “fix” this back into an immutable map”) and by '
        'a review fix that hands out an unmodifiable view '
        '(872430a). One message bumps the counter once, however '
        'many nodes it touches:'),
    ...code('dart', 'heaplens_flutter/lib/providers/graph_provider.dart · applyDiff (end)', r'''
    state = state + 1;'''),
    ...text('A later addition shows the rule being respected. '
        'When the daemon started sending Stats messages, the '
        'switch gained a case that returns before the bump, with '
        'a comment explaining that session counters must not '
        'trigger repaints. The plan left the shape of the message '
        'union to the implementer. The code chose a sealed class '
        'with one subclass per message kind, and stats became the '
        'third, which lets the compiler check every switch:'),
    ...code('dart', 'heaplens_flutter/lib/models/graph_diff.dart · GraphMessage', r'''
sealed class GraphMessage {
      case 'stats':
        return GraphStats.fromJson(json);'''),

    ...sec('constraints that bind every task'),
    ...text('Nine global constraints keep ten tasks consistent. '
        'Three are worth singling out.'),
    ...bullet('pure layout',
        'no widget imports in simulation/force_layout.dart. It '
        'can be tested without a widget tester, and was: the '
        'layout test is the longest test file in the app, 486 '
        'lines.'),
    ...bullet('aggregation above 500 live nodes',
        'one aggregate per symbol instead of one circle per node, '
        'documented at the call site. The code kept the idea and '
        'added a refinement the plan did not ask for: a '
        'hysteresis band, so that churn near the boundary does '
        'not flip between modes.'),
    ...code('dart', 'heaplens_flutter/lib/simulation/force_layout.dart · thresholds', r'''
const int kAggregationThreshold = 500;
const int kAggregationExitThreshold = 450;'''),
    ...bullet('no silent catch',
        'Dart’s catch-and-ignore is banned; the one place errors '
        'are expected, the WebSocket reconnect, must back off and '
        'not crash. The backoff is named in a comment in '
        'ws_provider.dart: exponential from 500 ms, doubling, '
        'capped at 5 s.'),
    blank,
    ...text('The same file contains a case of a plan being '
        'overruled by evidence, and documenting it. The plan says '
        'node radius is proportional to sqrt(size). The code uses '
        'a logarithm, and its comment explains why with numbers:'),
    ...code('dart', 'heaplens_flutter/lib/simulation/force_layout.dart · radiusForSize (comment)', r'''
/// Log-scaled, not `sqrt`-scaled. This is a real fix, not a cosmetic
/// tweak: the allocation sizes this app actually renders span bytes to
/// low kilobytes (every workload used throughout this project's own
/// testing — 1 to a few hundred bytes), and `sqrt` barely moves for that'''),

    ...sec('how it was executed'),
    ...text('Commit times from 2026-07-06: scaffold at 20:16, the '
        'plan at 20:24, Task 1 at 20:28, the final integration of '
        'Task 9 at 22:11, and a last fix at 23:08. Nineteen '
        'commits after the plan in under three hours, '
        'with the review fix after each task landing a few '
        'minutes behind it. What those fixes caught is a list of '
        'the bugs a plan cannot see:'),
    ...bullet('b2746ec, WebSocket reconnect',
        'the previous socket was not closed before scheduling '
        'the next attempt, leaving half-open sockets to '
        'accumulate over long sessions.'),
    ...bullet('872430a, encapsulation',
        'the notifier handed out its mutable map directly.'),
    ...bullet('7498f32, layout',
        'a node mid-fade was silently dropped at the exact '
        'moment the 500-node boundary was crossed. Fixed, plus '
        'the hysteresis band above.'),
    ...bullet('7b3b9c7, canvas',
        'the tap handler assumed the node it hit still existed.'),
    ...bullet('cbb34ae, memory map',
        'infinite available width crashed with an “Infinity or '
        'NaN to int” error on floor(). A default column count '
        'and a test with unbounded constraints.'),
    ...bullet('0661725, node detail',
        'the displayed age snapped toward zero when the node '
        'carrying the maximum timestamp was removed, because the '
        'maximum was recomputed from live nodes each build. '
        'Fixed by remembering a monotonic maximum, mirroring '
        'the daemon’s own max_ts_seen pattern.'),
    ...bullet('4ad9349, pause',
        'the pause gate on the listener had no test, so removing '
        'it would have passed everything.'),

    ...sec('task 10: the step a human does'),
    ...text('Task 10 is flagged in the plan as “not a subagent '
        'task”: the controlling session runs it against a real '
        'daemon and a real producer, with the Windows Flutter '
        'toolchain. It found something every test had missed. The '
        'commit message for 1179bf1 explains that the graph '
        'message provider’s build function started the WebSocket '
        'connection synchronously, and the connection’s first '
        'action wrote to another provider before the first one’s '
        'build had returned. Riverpod forbids that and throws in '
        'debug mode. In the message’s words, “this crashed the '
        'app immediately on every real launch”.'),
    ...text('Why a green suite had not noticed: “Every existing '
        'test overrides graphMessageProvider with a fake stream, '
        'bypassing this exact code path”. The fix defers the call '
        'to a microtask, and the regression test reads the real, '
        'unoverridden provider. (The quoted lines are from the '
        'commit message, not from the plan file.) It is the '
        'cleanest example in the repo of why a live run is a '
        'separate gate from a test suite: fakes agree with the '
        'code that wrote them.'),

    ...sec('the addendum: tests green, canvas empty'),
    ...text('After the merge, a person ran the app against the '
        'real daemon and saw the control bar and nothing else. The '
        'plan’s addendum records the rule it set itself: the '
        'earlier evidence was all indirect, so the merged '
        'acceptance was overridden until a direct look said '
        'otherwise.'),
    ...text('The diagnosis was methodical. A full read of the '
        'path from WebSocket to painter found no structural '
        'defect. Screenshots were off the table by a standing '
        'instruction, so the investigation built an instrument '
        'instead: an on-screen overlay that shows every stage of '
        'the pipeline, so a human can localise a break to one of '
        'five seams. Its doc comment states the purpose:'),
    ...code('dart', 'heaplens_flutter/lib/debug/debug_overlay.dart · class doc (trimmed)', r'''
/// Standing on-screen diagnostic instrument (added for the fix/canvas-render
/// investigation; kept for every future visual gate, not removed once this
/// bug is fixed). Makes every stage of the daemon -> canvas pipeline
/// observable directly on screen'''),
    ...text('The finding was anticlimactic and exact:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-06-heaplens-flutter-m5.md · addendum', r'''
**Root cause: timing, not a code defect.** The live trace with'''),
    ...text('The only producer that existed, wire_producer, '
        'allocates and frees everything in under two seconds. By '
        'the time a person looked, the graph was legitimately '
        'empty. The fix was a program built for humans: '
        'demo_producer holds one owner and twenty children alive '
        'for sixty seconds, frees the owner so the children '
        'orphan, and keeps a 500 ms heartbeat so the daemon’s '
        'clock keeps moving. The addendum names its role: it is '
        '“the thesis/soutenance demo scenario”.'),
    ...text('Then comes the part that makes the addendum worth '
        'reading. The bug was not in the code, but the test suite '
        'was still at fault:'),
    ...code('markdown', 'docs/superpowers/plans/2026-07-06-heaplens-flutter-m5.md · addendum (trimmed)', r'''
every existing test (77 passing) asserted "no
exception" or hit-test/selection behavior — none asserted the painter
actually drew anything, so a genuinely dead render path could have passed
the whole suite.'''),
    ...text('The regression test it added asserts the painter '
        'draws no circles for an empty graph and draws circles '
        'once populated, using the framework’s paints matcher. '
        'And it was validated the right way: temporarily comment '
        'out the drawing call and confirm the test fails. A test '
        'you have not seen fail has not earned trust.'),

    ...sec('visual gates, honestly closed'),
    ...text('M5 carried three visual-verification gates into the '
        'next stage. The addendum scores them without rounding up:'),
    ...bullet('fade rendering of freed nodes',
        'closed, confirmed by direct user observation.'),
    ...bullet('orphan visuals (coral with a pulsing ring)',
        'closed, confirmed by direct user observation: children '
        'flipped to coral at T+60 s in the demo scenario.'),
    ...bullet('hot state (amber, more than 32 edges)',
        'still open. φ produced chains, not stars, for every '
        'existing producer; no producer made a genuine single-'
        'owner star past the threshold.'),
    blank,
    ...text('The third was closed later by work the plan could '
        'not have predicted: hot_producer and chaos_hot, then a '
        'one-line ordering fix (d192626, 2026-07-28) after which '
        'the commit reports a queue node rendering amber and a '
        '“Growing cluster” insight appearing. Twenty-one days '
        'from an honest “still open” to a verified close.'),

    ...sec('what the plan became'),
    ...bullet('tests',
        'the plan’s milestone counted 59, then 77 tests. A grep '
        'for test and testWidgets calls under test/ finds 146 '
        'today.'),
    ...bullet('surface',
        'the four planned widgets became ten files in '
        'lib/widgets/ with an insights panel, a right rail, a '
        'process-picker dialog and a target-status banner, none '
        'of them in the plan. The UI refresh (1cfb7f9, 2026-07-19) '
        'redesigned the control bar into a top ribbon.'),
    ...bullet('the lag assumption',
        'Task 2 justifies reconnect-with-backoff by saying “the '
        'daemon disconnects lagged clients by design (M4 Q6), and '
        'reconnecting yields a fresh snapshot”. The M4 plan and '
        'server.rs say a lagged client is warned about and kept. '
        'The reconnect logic is right for a dropped socket; the '
        'premise about lag is not what the daemon does.'),

    ...sec('limits, and what to take from it'),
    ...bullet('a plan cannot test its own environment',
        'two of the three biggest M5 defects (the provider '
        'initialisation crash and the empty canvas) were in the '
        'gap between a test double and a real run.'),
    ...bullet('screenshots were forbidden, so the evidence is '
        'indirect',
        'the closure of the gates rests on a person’s '
        'observation recorded in a plan file; the repository '
        'holds no image of the result.'),
    ...bullet('rule of thumb',
        'when something looks broken and the code is fine, build '
        'an instrument that shows each stage, and only then '
        'decide. Then ask why the tests could not have seen it.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
