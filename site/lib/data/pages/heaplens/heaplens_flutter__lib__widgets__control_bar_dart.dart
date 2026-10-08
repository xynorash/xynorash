import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/widgets/control_bar.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'control_bar.dart — the ribbon, and a button with a conscience'),
    cm('//', r'counters, filters, view toggle, attach and detach'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'the top ribbon: status, metrics, controls, target identity, filters'),
    kv('language', r'Dart / Flutter'),
    kv('size', r'507 lines; 6 commits, 2026-07-06 to 2026-07-28'),
    kv('tested by', r'test/widgets/control_bar_test.dart (11 tests)'),
    kv('writes', r'pausedProvider, viewModeProvider, 3 filter providers, attach state'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'This is the one place a user’s hands meet the application. '
        r'Everything else in the UI is a view of daemon state. The '
        r'ribbon is where the user changes what the views show (filters, '
        r'graph or map), freezes them (pause), points HeapLens at a '
        r'process (attach) and reads the headline numbers (owners, '
        r'nodes, orphans, bytes). It is also the file whose history '
        r'is the most honest about the project’s hardest problem: a '
        r'button that worked, was switched off for safety, was '
        r'switched on again, and was switched off again.'),
    ...sec(r'five cells, two lines each'),
    ...para('//',
        r'The class comment lists the layout. The first version (0309d9e, '
        r'2026-07-06) was a flat single-line bar. The UI refresh '
        r'(1cfb7f9, 2026-07-19) rebuilt it as a ribbon of five bordered '
        r'cells, "matching the wireframe template exactly":'),
    ...pt('//', r'cell 1', r'Attach (line 1) and connection state (line 2).'),
    ...pt('//', r'cell 2', r'Owners and Nodes (line 1), Orphans and Bytes (line 2).'),
    ...pt('//', r'cell 3', r'pause and the minimum-size slider (line 1); render mode and the Graph/Map toggle (line 2).'),
    ...pt('//', r'cell 4', r'process name (line 1), PID (line 2), or "No target attached".'),
    ...pt('//', r'cell 5', r'Orphans only (line 1) and Search symbol (line 2).'),
    blank,
    ...para('//',
        r'A sentence in the class comment states a refactoring rule '
        r'that is easy to miss: "Every raw/technical value from the '
        r'flat single-line layout is retained — this changes '
        r'grouping/labeling/legibility only. All existing Keys are '
        r'preserved." The tests identify widgets by Key (pauseResumeButton, '
        r'minSizeSlider, orphanOnlySwitch, symbolSearchField), so a '
        r'redesign that kept the keys left those lookups valid.'),
    ...sec(r'colour and words for connection state'),
    ...code('dart', 'heaplens_flutter/lib/widgets/control_bar.dart · connection status maps', r'''
const Map<ConnectionStatus, Color> kConnectionStatusColors = {
  ConnectionStatus.connected: XynorashTheme.teal,
  ConnectionStatus.connecting: XynorashTheme.orange,
  ConnectionStatus.disconnected: XynorashTheme.coral,
};

/// Human-readable label for each [ConnectionStatus], surfaced as plain text
/// (in addition to the colored dot) so status is not conveyed by color alone.
const Map<ConnectionStatus, String> kConnectionStatusLabels = {
  ConnectionStatus.connected: 'Connected',
  ConnectionStatus.connecting: 'Connecting…',
  ConnectionStatus.disconnected: 'Disconnected',
};'''),
    ...para('//',
        r'Two design rules are visible. Connection state reuses the '
        r'palette of node state (teal, amber, coral) so "is the '
        r'connection okay" reads like "is the node okay": the comment '
        r'says the colour language stays consistent. And the colour is '
        r'never alone. The label is always printed next to the dot, '
        r'"so status is not conveyed by color alone". The same rule '
        r'drives NodeStateChip in node_colors.dart. Their tests assert '
        r'on the text: connecting shows "Connecting…", and so on.'),
    ...sec(r'counters that cost nothing to keep'),
    ...code('dart', 'heaplens_flutter/lib/widgets/control_bar.dart · build, state read (trimmed)', r'''
    final status = ref.watch(connectionStatusProvider);
    // Watched purely to know *when* to rebuild for updated counters; the
    // actual counts are read fresh from the notifier's derived getters,
    // per the documented graph_provider.dart contract.
    ref.watch(graphProvider);
    final notifier = ref.read(graphProvider.notifier);
    final paused = ref.watch(pausedProvider);
...
    ref.listen<AsyncValue<ControlResponse>>(controlResponseProvider, (previous, next) {
      next.whenData((resp) {
        if (resp is TargetExitedResponse) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Target process (pid ${resp.pid}) exited')),
          );
        }
      });
    });'''),
    ...para('//',
        r'The ribbon follows the graph-provider contract to the letter: '
        r'watch the revision, read the notifier’s getters fresh. The '
        r'four metrics are Owners (live nodes with children), Nodes '
        r'(live), Orphans, and Bytes (summed live size). Orphans turns '
        r'coral when the count is above zero, "orphan = coral '
        r'everywhere (graph nodes, the state chip, and here)", and each '
        r'tile has a plain-sentence tooltip. The tooltip for Orphans is '
        r'taken from kNodeStateDescriptions, so the definition is '
        r'written once.'),
    blank,
    ...para('//',
        r'The ref.listen at the bottom is a small piece of product '
        r'thinking, and its comment gives the reason: the graph itself '
        r'"doesn’t visibly announce" that the target that produced '
        r'these nodes is gone, so a target-exited push from the daemon '
        r'becomes a one-time snackbar instead of a silent state change.'),
    ...sec(r'pause drops, filters hide'),
    ...pt('//', r'pause',
        r'the button toggles pausedProvider. The effect lives '
        r'elsewhere: graph_provider.dart and the orchestrator in '
        r'main.dart both check the flag and drop messages. A widget '
        r'test pins the observable behaviour end to end: it presses '
        r'pause, pushes a snapshot and checks the revision did not '
        r'change and the map is empty; then presses resume, pushes '
        r'another and expects the revision to rise by one.'),
    ...pt('//', r'minimum size',
        r'a real Material Slider from 0 to 4096 bytes with a custom '
        r'SliderTheme (2 px track, 5 px thumb). A comment says it '
        r'stays a real Slider "since the existing test drags it, and a '
        r'continuous-drag control is worth keeping Material’s real '
        r'gesture handling for". The test drags it 50 px and expects '
        r'the filter to become greater than zero.'),
    ...pt('//', r'orphans only and search',
        r'a CompactSwitch and a TextField that write the two other '
        r'filter providers. The filters are rendering-only: as '
        r'filter_providers.dart insists, they never touch the node '
        r'map, so counters keep reflecting true daemon state.'),
    ...pt('//', r'render mode',
        r'a CompactSegmented between Graph and Memory Map, writing '
        r'viewModeProvider.'),
    blank,
    ...para('//',
        r'The two custom widgets, CompactSwitch and CompactSegmented, '
        r'live in ui_common.dart. They exist because stock Material '
        r'controls were visibly taller than the 12 px labels beside '
        r'them, and scaling a real Switch "doesn’t reliably land on" the '
        r'right size. Their heights are set directly: 14 for the switch '
        r'and 20 for the segmented toggle.'),
    ...sec(r'a ribbon that has to decide between Row and Wrap'),
    ...code('dart', 'heaplens_flutter/lib/widgets/control_bar.dart · the layout choice', r'''
          child: LayoutBuilder(
            builder: (context, constraints) {
              final naturalWidth = _measureNaturalWidth(cells);
              if (constraints.maxWidth >= naturalWidth) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: cells,
                );
              }
              return Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: cells,
              );
            },
          ),
...
  static double _measureNaturalWidth(List<Widget> cells) {
    return cells.length * 320.0;
  }'''),
    ...para('//',
        r'The comment above that code explains a real trade-off. A Row '
        r'with spaceBetween spreads the five cells across the full '
        r'ribbon, which looks right, but it hard-overflows if the window '
        r'is narrower than the cells’ combined fixed widths (the 180 px '
        r'slider, the 140 px search field). A Wrap degrades to several '
        r'lines. Rather than measure the cells, the code uses a '
        r'deliberately conservative constant, 320 px per cell, and '
        r'explains the asymmetry of the error: guessing too low "would '
        r'pick Row for a window that’s actually too narrow for it and '
        r'hard-overflow", while guessing too high "only means a '
        r'genuinely-wide-enough window still gets the safe Wrap '
        r'fallback ... a visual miss, not a crash". The comment adds '
        r'that 320 stays "well above the 800px default test viewport", '
        r'so the tests keep exercising the Wrap path.'),
    blank,
    ...para('//',
        r'One consequence is worth working out. Five cells at 320 px is '
        r'1600 px. The Windows runner in this repository creates its '
        r'window at 1280 by 720 (windows/runner/main.cpp). By that '
        r'arithmetic, at the default window size the ribbon takes the '
        r'Wrap path, and only a window of 1600 px or wider gets the '
        r'spread-out Row. The comment’s claim that 320 per cell is '
        r'"well below a typical desktop window’s width" is true for a '
        r'maximised monitor and not for the default size. I have not '
        r'seen the app at either size, so this is a reading, not an '
        r'observation.'),
    ...sec(r'the attach button, and the gate'),
    ...code('dart', 'heaplens_flutter/lib/widgets/control_bar.dart · the gate', r'''
/// Cross-process attachment (2026-07-28): re-enabled. Both confirmed hook
/// defects behind the two prior disable periods are fixed and validated on
/// this branch: the concurrent-allocation crash (fixed 2026-07-22) and the
/// exit-without-detach DLL_PROCESS_DETACH crash (root-caused and fixed via
/// raw TlsAlloc/FlsAlloc in place of thread_local!, see heaplens-alloc's
/// guard.rs/ring.rs doc comments). `kAttachEnabled` stays a single
/// flippable gate (not deleted) so any future regression can be disabled
/// the same visible, honest way — present but disabled with a reason,
/// never silently removed.
const bool kAttachEnabled = true;
const String kAttachDisabledReason =
    'Process attachment is temporarily disabled — a confirmed crash occurs '
    'if the attached process exits normally without an explicit Detach '
    'first. Fix in progress. Cooperative capture (used by all bundled '
    'example producers) is unaffected.';
const String kAttachEnabledInfo =
    'Process attachment is enabled and validated against controlled, '
    'standard, non-kernel-driver software. HeapLens automatically refuses '
    'processes with kernel-mode driver components (VPN/anti-cheat/security '
    'software) for safety.';'''),
    ...para('//',
        r'Attaching HeapLens to someone else’s running process means '
        r'injecting a DLL that hooks the Windows heap functions. It '
        r'is the most dangerous capability in the project, and this '
        r'constant is its circuit breaker. The comment’s principle is '
        r'the interesting part: when the feature is unsafe, do not '
        r'delete the button, "present but disabled with a reason, never '
        r'silently removed". The history of the flag is a compact case '
        r'study in doing that.'),
    blank,
    ...pt('//', r'2026-07-21, 823dac7: disabled',
        r'the commit cites a confirmed, reproducible defect found '
        r'during a DPC_WATCHDOG_VIOLATION investigation: the hook path '
        r'(detours on RtlAllocateHeap, RtlReAllocateHeap and RtlFreeHeap) '
        r'"crashes reliably under heavy concurrent multi-threaded '
        r'allocation", reproduced with a self-contained stress harness, '
        r'and corroborated by a live process that crashed inside '
        r'heaplens_hook.dll before a kernel bugcheck. The button '
        r'stayed visible and disabled with a tooltip. The next commit, '
        r'31bc7ee, closed a test gap: the existing tests only checked '
        r'the button’s presence, never whether it was actually disabled. '
        r'The new test asserted onPressed was exactly null and that the '
        r'tooltip text matched the constant.'),
    ...pt('//', r'2026-07-22, 864167e: enabled',
        r'the commit lays out an evidence chain, not a revert. The '
        r'TLS/FLS corruption that caused the original crash was fixed '
        r'and proved by a standing stress test and by real injection '
        r'under load. A chain of memory and performance fixes was '
        r'proved to plateau, not merely improve, in a soak of about '
        r'2 hours 10 minutes against a real Node.js process. Injection '
        r'was validated against three different real targets (native '
        r'Win32, Electron/Chromium, Node.js/V8). And a new '
        r'pre-attach check refuses processes with kernel-mode driver '
        r'components. The tooltip was changed to state that scope '
        r'honestly, and the commit states its own bounds: the '
        r'validated duration is roughly two hours continuous, not '
        r'indefinite, and driver detection is "best-effort".'),
    ...pt('//', r'2026-07-26, 306e8fc: disabled again',
        r'a second, distinct defect: a target that exits normally '
        r'while the hooks are still installed, without an explicit '
        r'detach, crashes with STATUS_ACCESS_VIOLATION, "100%-'
        r'reproducing". The root cause given is that the hook DLL had '
        r'no DLL_PROCESS_DETACH safety handling. The earlier fix "remains '
        r'correct and in place". The tooltip was rewritten to name the '
        r'actual finding rather than a generic message.'),
    ...pt('//', r'2026-07-28, 9693399: enabled',
        r'the commit title is "demo: TUI backdrop ... + attach button '
        r're-enabled for soutenance". The comment above the constant '
        r'says the exit-without-detach crash was root-caused and fixed '
        r'by using raw TlsAlloc/FlsAlloc in place of thread_local!.'),
    blank,
    ...code('dart', 'heaplens_flutter/lib/widgets/control_bar.dart · _AttachControl (trimmed)', r'''
      final button = ElevatedButton.icon(
        key: const Key('attachButton'),
        icon: const Icon(Icons.link, size: 16),
        label: const Text('Attach'),
        onPressed: kAttachEnabled ? () => showProcessPickerDialog(context) : null,
      );
...
      return Tooltip(
        key: Key(kAttachEnabled ? 'attachEnabledTooltip' : 'attachDisabledTooltip'),
        message: kAttachEnabled ? kAttachEnabledInfo : kAttachDisabledReason,
        child: button,
      );
...
          onPressed: () {
            ref.read(wsConnectionProvider).sendRequest(const DetachTargetRequest());
            ref.read(attachedTargetProvider.notifier).clear();
          },'''),
    ...para('//',
        r'A tooltip is present in both states, "replaced, never removed" '
        r'in the comment’s words, and the keys differ so a test can '
        r'tell which branch is live. When attached, the control '
        r'swaps to a label (name and pid) and a Detach icon button. '
        r'Detach is optimistic: it sends the request and clears the '
        r'local state at once, without waiting for the daemon’s '
        r'DetachResult, which, if it arrives with ok: true, would '
        r'find nothing left to clear. The test that taps Detach '
        r'checks the exact JSON frame and the cleared state.'),
    blank,
    ...para('//',
        r'The tests follow the flag. At its first disable, the '
        r'attach test asserted the disabled branch; at each flip it '
        r'was rewritten. Today it asserts the enabled branch and, '
        r'in its first lines, that kAttachEnabled is true, with a '
        r'reason string that tells the next person who flips the '
        r'flag to update or add a companion test. A consequence: with '
        r'the flag on, no test exercises the disabled branch '
        r'(kAttachDisabledReason and the null onPressed), so that '
        r'code is currently dead and unguarded. The commit 31bc7ee '
        r'gave a reason it could not test both branches at once: the '
        r'flag is a top-level const baked into a private widget with '
        r'"no injectable seam", and adding one would be a production '
        r'change it chose not to make unprompted.'),
    ...sec(r'what changed over time'),
    ...pt('//', r'0309d9e, 2026-07-06', r'first version: flat bar with status, counters, pause, filters and view toggle. Written by a sub-agent that hit an API error before writing tests; the commit says the files were verified and the tests finished directly.'),
    ...pt('//', r'1cfb7f9, 2026-07-19', r'the five-cell ribbon, attach/detach controls, target identity, snackbar; 502 lines changed.'),
    ...pt('//', r'823dac7, 31bc7ee, 864167e, 306e8fc, 9693399', r'the gate story above, from 2026-07-21 to 2026-07-28.'),
    ...sec(r'limits'),
    ...pt('//', r'wrap versus row is a heuristic',
        r'a constant, not a measurement; see above.'),
    ...pt('//', r'the gate is compile-time',
        r'flipping kAttachEnabled needs a rebuild; the comment calls it '
        r'a single flippable gate.'),
    ...pt('//', r'status text assumes English',
        r'every label is a string literal; there is no localisation.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
