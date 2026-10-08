import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/models/target_diagnosis.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'target_diagnosis.dart — why does the graph look empty?'),
    cm('//', r'a pure classifier from five counters to five honest states'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'turns daemon counters and graph shape into a diagnosis'),
    kv('language', r'Dart (pure function, no Flutter widgets)'),
    kv('size', r'188 lines; 2 commits (0edc728 on 2026-07-17, ead62bb on 2026-07-22)'),
    kv('tested by', r'test/models/target_diagnosis_test.dart (14 tests)'),
    kv('rendered by', r'widgets/target_status_banner.dart'),
    ...sec(r'the problem: a blank canvas that means four different things'),
    ...para('//',
        r'A memory profiler that shows an empty graph has failed at the '
        r'one moment the user needs it most. After process attachment '
        r'arrived, "empty" stopped being one situation. The graph can be '
        r'empty or edgeless because the target is idle; because it '
        r'allocates through a heap path HeapLens does not hook; because '
        r'the target has no debug symbols, so ownership cannot be '
        r'inferred; or because ownership did form and then every owner '
        r'was freed. The first three are limits of the tool and the '
        r'target; the last is the tool working and finding a leak.'),
    blank,
    ...para('//',
        r'The commit that introduced this file (0edc728) puts the goal '
        r'in one sentence: distinguish "capturing / no-events / '
        r'no-edges / unsymbolized for an attached target instead of '
        r'leaving the user staring at a blank graph". This file is the '
        r'brain of that feature. It is a single static function over '
        r'plain numbers, which is why it can be tested exhaustively '
        r'without a widget, a timer or a socket.'),
    ...sec(r'the vocabulary'),
    ...code('dart', 'heaplens_flutter/lib/models/target_diagnosis.dart · TargetStatus (doc comments trimmed)', r'''
enum TargetStatus {
...
  capturing,
...
  noEvents,
...
  noEdges,
...
  unsymbolized,
...
  noEdgesOrphaned,
}'''),
    ...pt('//', r'capturing',
        r'events are arriving and/or the graph looks healthy. The banner '
        r'renders nothing. The doc comment is firm that healthy is the '
        r'common case and should be silent.'),
    ...pt('//', r'noEvents',
        r'attached, but zero allocation events over a window. The '
        r'target may be idle, or use a heap path HeapLens does not hook.'),
    ...pt('//', r'noEdges',
        r'allocations and nodes exist but almost no ownership edges '
        r'formed. "phi could not build topology for this target."'),
    ...pt('//', r'unsymbolized',
        r'the same low edge ratio, but confirmed rather than inferred: '
        r'the effective-site names are mostly hex fallbacks.'),
    ...pt('//', r'noEdgesOrphaned',
        r'the same low edge ratio again, but explained by a benign '
        r'cause: symbols resolve fine and most live nodes are orphaned. '
        r'An orphan has no owning edge by definition, so a mostly '
        r'orphaned graph has a near-zero edge ratio even though phi '
        r'worked perfectly.'),
    blank,
    ...para('//',
        r'Why do three states share one symptom? Ownership edges come '
        r'from the daemon’s phi function, which matches resolved '
        r'function names (see the daemon’s graph.rs: an unresolved '
        r'address "has no name and cannot match anything"). A target '
        r'with only hex names therefore produces no edges, a target '
        r'whose owners were all freed produces no edges either, and '
        r'from the outside the graph is edgeless in both cases. The '
        r'classifier’s job is to use a second signal, the symbol '
        r'counters, to tell them apart.'),
    ...sec(r'four named constants, each with a stated reason'),
    ...code('dart', 'heaplens_flutter/lib/models/target_diagnosis.dart · thresholds', r'''
const Duration kNoEventsWindow = Duration(seconds: 3);
...
const double kNoEdgesRatioThreshold = 0.05;

/// Above this hex-fallback/total-symbol ratio, effective-site names are
/// considered "predominantly" unresolved.
const double kUnsymbolizedRatioThreshold = 0.8;
...
const double kOrphanExplainsNoEdgesRatioThreshold = 0.5;'''),
    ...pt('//', r'3 seconds of silence',
        r'the doc comment says the window is measured from when this '
        r'client first observed the session, because the daemon does not '
        r'export a wall-clock attach timestamp. It calls this "an '
        r'acceptable approximation for a diagnostic banner, not a '
        r'precision measurement". Since stats arrive about once a second '
        r'and the diagnosis is recomputed only when a message arrives, '
        r'the banner can appear between roughly three and four seconds '
        r'after the first stats message; that timing is my inference, '
        r'not a measurement.'),
    ...pt('//', r'0.05 edges per node',
        r'not exactly zero, "so a handful of incidental phi-ambiguity '
        r'edges (see graph.rs’s documented, accepted misattribution '
        r'case) don’t prevent the diagnosis from firing". That refers '
        r'to the daemon’s doc comment on its function-name matching, '
        r'which admits that two unrelated containers allocated in the '
        r'same function become indistinguishable candidates.'),
    ...pt('//', r'0.8 hex share',
        r'"predominantly" unresolved. No justification beyond the word '
        r'is given; it is a chosen cut-off, not a derived one.'),
    ...pt('//', r'0.5 orphan share',
        r'if at least half the live nodes are orphans, the low edge '
        r'ratio is attributed to orphaning. Again a cut-off, in the same '
        r'family as the daemon’s hot-cluster threshold of 32, which '
        r'the Build Spec labels "an empirically-chosen fan-out '
        r'heuristic, not a value derived from any model".'),
    ...sec(r'the classifier'),
    ...code('dart', 'heaplens_flutter/lib/models/target_diagnosis.dart · TargetDiagnosis.classify (trimmed)', r'''
  static TargetDiagnosis classify({
    required int eventsReceived,
    required int symbolsResolved,
    required int hexFallback,
    required int nodeCount,
    required int edgeCount,
    required bool pastNoEventsWindow,
    required int? targetPid,
    required String? targetName,
    // Defaults to 0 (never explains a low edge ratio) so existing callers
    // that don't yet track orphan count keep their original classification.
    int orphanCount = 0,
  }) {
    if (eventsReceived == 0) {
      if (!pastNoEventsWindow) {
...
      }
      final label = (targetName != null && targetPid != null)
          ? 'Attached to `$targetName` [$targetPid]'
          : 'Attached';
...
    }

    final edgeRatio = nodeCount == 0 ? 0.0 : edgeCount / nodeCount;
    final totalSymbols = symbolsResolved + hexFallback;
    final hexRatio = totalSymbols == 0 ? 0.0 : hexFallback / totalSymbols;
    final unsymbolized = totalSymbols > 0 && hexRatio >= kUnsymbolizedRatioThreshold;
    final orphanRatio = nodeCount == 0 ? 0.0 : orphanCount / nodeCount;
    final orphanExplainsNoEdges =
        !unsymbolized && orphanRatio >= kOrphanExplainsNoEdgesRatioThreshold;

    if (nodeCount > 0 && edgeRatio < kNoEdgesRatioThreshold) {
      if (orphanExplainsNoEdges) {
...
      }'''),
    ...para('//',
        r'Read the order of the checks as the argument of the function. '
        r'First, no events at all: either the window has not elapsed '
        r'(capturing, silent) or it has (noEvents). Everything after '
        r'that assumes events are flowing. Then three ratios, each '
        r'guarded against division by zero. Then a nested decision for '
        r'the low-edge case, with the most specific explanation winning:'),
    ...pt('//', r'unsymbolized beats orphaned',
        r'orphanExplainsNoEdges starts with !unsymbolized. If the '
        r'symbols really are hex, saying "your orphans explain it" would '
        r'hide the true cause. A test covers it by giving 90 orphans of '
        r'100 nodes and 98 hex symbols of 100, and expecting '
        r'unsymbolized.'),
    ...pt('//', r'zero nodes is not "no edges"',
        r'the branch requires nodeCount > 0. A target that allocates and '
        r'frees everything inside one daemon tick can have thousands of '
        r'events and zero live nodes; the test names this case "all '
        r'born+freed within a tick" and expects capturing, because '
        r'"noEdges requires nodes to actually be present".'),
    ...pt('//', r'the orphan count defaults to zero',
        r'the parameter comment says so: older callers that do not '
        r'supply it keep the original classification. It is a '
        r'backwards-compatible addition, made when the orphan branch was '
        r'bolted on five days after the first version.'),
    ...sec(r'the bug that created a fifth state'),
    ...para('//',
        r'ead62bb (2026-07-22) is the most instructive commit in this '
        r'file’s history, and its message is a short post-mortem. The '
        r'noEdges branch used to fire whenever the edge-to-node ratio was '
        r'low, "without checking whether symbols were actually '
        r'unresolved". Live visual verification against '
        r'checkout_service.exe caught it: with resolved=111/111 and '
        r'hex_fallback=0, a fully resolved run, the banner still claimed '
        r'a missing-symbols problem. "The real cause was that every node '
        r'had become orphaned (no owner, so no owning edge), which '
        r'produces the exact same low edge ratio for an entirely '
        r'different, benign reason."'),
    blank,
    ...para('//',
        r'Two things are notable. The bug was a wrong diagnosis rather '
        r'than a crash, so no test could have caught it before a human '
        r'read the screen next to the numbers. And the regression test '
        r'is built from the real incident: the test named '
        r'"symbols fully resolved, most nodes orphaned" uses '
        r'eventsReceived 340226, 111 symbols resolved, 0 hex, 111 nodes, '
        r'0 edges, 111 orphans, pid 7048 and the name '
        r'checkout_service. Those are the observed numbers, kept as the '
        r'fixture. The new message reads "No live ownership edges — 111 '
        r'of 111 allocations are currently orphaned (leaked). Symbols '
        r'are resolving normally."'),
    blank,
    ...para('//',
        r'The same commit records a second suspicion that did not '
        r'survive inspection: that a selected orphan node lost its coral '
        r'fill. It "did not reproduce on inspection" or under pixel '
        r'sampling, so the commit added only a defensive regression '
        r'test (in graph_canvas_test.dart) and no code change. Recording '
        r'a hypothesis as disproved is part of the evidence trail.'),
    ...sec(r'what the user reads, and the limit that remains'),
    ...code('dart', 'heaplens_flutter/lib/models/target_diagnosis.dart · the two edgeless messages (trimmed)', r'''
          message: 'No live ownership edges — $orphanCount of $nodeCount '
              'allocations are currently orphaned (leaked). Symbols are '
              'resolving normally. Allocation sizes and growth are still '
              'available in the Map view.',
...
      const base = 'Capturing allocations, but no ownership structure could '
          'be inferred — this target lacks the debug symbols HeapLens needs '
          'to build topology. Allocation sizes and growth are still '
          'available in the Map view.';
...
        status: unsymbolized ? TargetStatus.unsymbolized : TargetStatus.noEdges,
        message: unsymbolized ? '$base Symbols unavailable for this target.' : base,'''),
    ...para('//',
        r'Both messages end by pointing at the Map view, and the banner '
        r'widget offers a one-tap "Switch to Map view" for the three '
        r'edgeless states. The reasoning is in the text: the memory map '
        r'does not need edges, so sizes and growth stay useful when '
        r'topology cannot be built.'),
    blank,
    ...para('//',
        r'There is one remaining wrinkle, and it is visible in the code '
        r'above. The residual noEdges status (low edge ratio, not mostly '
        r'hex, not mostly orphans) reuses the base message, which says '
        r'the target "lacks the debug symbols". But in that branch the '
        r'hex ratio is below 0.8 by construction, so the data does not '
        r'support the claim. The test for this branch even shows it: 90 '
        r'resolved symbols against 2 hex, yet the message contains '
        r'"lacks the debug symbols". The test title calls it "cause '
        r'unclear". It is the same family of mistake ead62bb fixed, '
        r'narrowed to the leftover case; the enum doc for noEdges says '
        r'only that phi could not build topology. I would flag it as a '
        r'known wording limit rather than a bug, but a future fix would '
        r'be a fourth message for "low edges, cause unknown".'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'target_diagnosis_test.dart has 14 tests, all on plain values. '
        r'The cases:'),
    ...pt('//', r'zero events',
        r'before the window (capturing, no message), after the window '
        r'with a name and pid (message contains "Attached to '
        r'`target.exe` [4242]" and "segment heap"), and after the window '
        r'with no handshake (message starts with "Attached —").'),
    ...pt('//', r'healthy',
        r'500 events, 100 nodes, 60 edges is capturing.'),
    ...pt('//', r'the edgeless family',
        r'noEdges, noEdgesOrphaned, the below-threshold orphan ratio '
        r'falling back to noEdges, unsymbolized winning over orphaned, '
        r'and plain unsymbolized.'),
    ...pt('//', r'boundaries',
        r'4 edges in 100 nodes (0.04) is noEdges; 10 in 100 (0.10) is '
        r'capturing. The test title says "right at the threshold", but '
        r'the value tested is 0.04, so the exact 0.05 boundary is not '
        r'pinned.'),
    ...pt('//', r'counts pass through',
        r'the raw counts are carried on every result regardless of '
        r'status, which is what the banner tooltip and the debug overlay '
        r'rely on.'),
    ...sec(r'limits'),
    ...pt('//', r'wall-clock window',
        r'measured client-side from the first stats message, as above.'),
    ...pt('//', r'segment heap is named, not proven',
        r'the noEvents text suggests the Windows segment heap as an '
        r'example of an unhooked heap path. I found that phrase only in '
        r'this file and its test, not in the Stage 7 design document, '
        r'which discusses hooking the ntdll Rtl heap functions. Treat '
        r'it as the author’s example.'),
    ...pt('//', r'thresholds are heuristics',
        r'0.05, 0.8 and 0.5 are plain constants with no calibration '
        r'data behind them in the repository.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
