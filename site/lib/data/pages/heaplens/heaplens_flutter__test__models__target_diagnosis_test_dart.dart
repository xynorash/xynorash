import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/models/target_diagnosis_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'target_diagnosis_test.dart — when is a blank graph the target’s fault?'),
    cm('//', r'a decision table for the target-status banner, one row per test'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'pins every branch and threshold of TargetDiagnosis.classify'),
    kv('language', r'Dart, flutter_test unit tests'),
    kv('size', r'224 lines, 14 tests in 2 groups'),
    kv('history', r'created in 0edc728 (2026-07-17); extended in ead62bb (2026-07-22) with the orphan cases'),
    kv('subject', r'lib/models/target_diagnosis.dart'),
    kv('consumers', r'target_diagnostics_provider.dart, target_status_banner.dart'),
    ...sec(r'the problem this logic solves'),
    ...para('//', r'After attaching to a program, the user can face an empty graph for four very different reasons. The program might be idle. It might allocate through a heap path HeapLens does not hook. It might allocate plenty but have no debug symbols, so ownership cannot be inferred. Or everything might have been leaked, so no owner is alive to hold an edge. Four causes, one picture: a blank canvas. The commit message of 0edc728 says it wants to stop leaving the user staring at a blank graph, and classify() is the function that picks which explanation to show.'),
    blank,
    ...para('//', r'It is a pure function of nine parameters: event count, symbol counters, node and edge counts, whether the quiet window has passed, the target identity, and an optional orphan count. A pure function with this many interacting thresholds is best tested as a decision table, and that is what this file is. Each test is one row: a set of inputs, the expected status, and the message text the user should see.'),
    ...sec(r'the constants the tests lean on'),
    ...code('dart', r'heaplens_flutter/lib/models/target_diagnosis.dart · the thresholds', r'''
/// Minimum wall-clock time after we start observing a session before "zero
/// events" is treated as a real diagnosis rather than "the daemon just
/// hasn't had a chance to report anything yet". Attach time itself isn't
/// known client-side (the daemon doesn't export a wall-clock attach
/// timestamp — see target_diagnostics_provider.dart), so this is measured
/// from when this client first observed the session, which is an
/// acceptable approximation for a diagnostic banner, not a precision
/// measurement.
const Duration kNoEventsWindow = Duration(seconds: 3);

/// Below this edge-to-node ratio, a nonempty graph is considered to have
/// "no ownership structure" for diagnostic purposes. Not exactly zero, so a
/// handful of incidental phi-ambiguity edges (see graph.rs's documented,
/// accepted misattribution case) don't prevent the diagnosis from firing.
const double kNoEdgesRatioThreshold = 0.05;

/// Above this hex-fallback/total-symbol ratio, effective-site names are
/// considered "predominantly" unresolved.
const double kUnsymbolizedRatioThreshold = 0.8;

/// Above this orphan/node ratio, a low edge ratio is considered explained
/// by orphaning rather than by a symbol/topology problem: most of the
/// graph has lost its owner, so of course there are few owning edges left.
const double kOrphanExplainsNoEdgesRatioThreshold = 0.5;'''),
    ...para('//', r'Four numbers decide everything: a three second window before silence counts as a diagnosis, an edge-to-node ratio of 0.05 below which a graph has no structure, a hex-fallback ratio of 0.8 at or above which a target is unsymbolized, and an orphan ratio of 0.5 at or above which orphaning explains the missing edges. The doc comments give the reasons: the window is measured from when this client first saw the session because the daemon does not export a wall-clock attach time, and the edge ratio is not exactly zero so that a handful of incidental ambiguous edges do not suppress the diagnosis.'),
    ...sec(r'rows 1 to 3: silence'),
    ...code('dart', r'heaplens_flutter/test/models/target_diagnosis_test.dart · zero events, inside the window', r'''
  group('TargetDiagnosis.classify', () {
    test('zero events, before the no-events window: capturing, no message', () {
      final d = TargetDiagnosis.classify(
        eventsReceived: 0,
        symbolsResolved: 0,
        hexFallback: 0,
        nodeCount: 0,
        edgeCount: 0,
        pastNoEventsWindow: false,
        targetPid: 4242,
        targetName: 'target.exe',
      );
      expect(d.status, TargetStatus.capturing);
      expect(d.message, isNull);
    });'''),
    ...para('//', r'With zero events received, the only question is time. Inside the three second window the answer is capturing with a null message: the daemon has simply not had a chance to report. The test asserts message is null, not just the status, because the banner shows nothing exactly when the message is null.'),
    ...code('dart', r'heaplens_flutter/test/models/target_diagnosis_test.dart · zero events, past the window', r'''
    test('zero events, past the no-events window: noEvents with name/pid label', () {
      final d = TargetDiagnosis.classify(
        eventsReceived: 0,
        symbolsResolved: 0,
        hexFallback: 0,
        nodeCount: 0,
        edgeCount: 0,
        pastNoEventsWindow: true,
        targetPid: 4242,
        targetName: 'target.exe',
      );
      expect(d.status, TargetStatus.noEvents);
      expect(d.message, contains('Attached to `target.exe` [4242]'));
      expect(d.message, contains('no heap activity observed'));
      expect(d.message, contains('segment heap'));
    });'''),
    ...para('//', r'Past the window the status becomes noEvents and the message is checked with three contains assertions: the label Attached to `target.exe` [4242], the phrase no heap activity observed, and the words segment heap. That last phrase is the hypothesis the message offers for why a target is silent: the Windows segment heap is a path HeapLens does not hook. The test locks the three pieces so a rewording that drops the one useful hint would fail.'),
    ...code('dart', r'heaplens_flutter/test/models/target_diagnosis_test.dart · no handshake yet', r'''
    test('zero events, past window, no handshake yet: generic "Attached" label', () {
      final d = TargetDiagnosis.classify(
        eventsReceived: 0,
        symbolsResolved: 0,
        hexFallback: 0,
        nodeCount: 0,
        edgeCount: 0,
        pastNoEventsWindow: true,
        targetPid: null,
        targetName: null,
      );
      expect(d.status, TargetStatus.noEvents);
      expect(d.message, startsWith('Attached —'));
    });'''),
    ...para('//', r'The third row covers the identity being null. The stats message carries the target pid and name only after the handshake frame, so before that the label falls back to a plain Attached, and the test asserts the message startsWith Attached with the dash. Without this row, a template that interpolated null would print the word null to the user.'),
    ...sec(r'rows 4 and 5: the edge ratio'),
    ...code('dart', r'heaplens_flutter/test/models/target_diagnosis_test.dart · healthy ratio', r'''
    test('events flowing, healthy edge ratio: capturing, no message', () {
      final d = TargetDiagnosis.classify(
        eventsReceived: 500,
        symbolsResolved: 40,
        hexFallback: 2,
        nodeCount: 100,
        edgeCount: 60,
        pastNoEventsWindow: true,
        targetPid: 1,
        targetName: 'ok.exe',
      );
      expect(d.status, TargetStatus.capturing);
      expect(d.message, isNull);
    });'''),
    ...para('//', r'500 events, 100 nodes, 60 edges: a ratio of 0.6. Status is capturing and there is no message. This is the quiet baseline, and it has to be a test because the banner must disappear when things are fine.'),
    ...code('dart', r'heaplens_flutter/test/models/target_diagnosis_test.dart · near-zero edges, symbols resolved', r'''
    test('events flowing, nodes present, near-zero edges, symbols mostly resolved: noEdges', () {
      final d = TargetDiagnosis.classify(
        eventsReceived: 500,
        symbolsResolved: 90,
        hexFallback: 2,
        nodeCount: 100,
        edgeCount: 1,
        pastNoEventsWindow: true,
        targetPid: 1,
        targetName: 'flat.exe',
      );
      expect(d.status, TargetStatus.noEdges);
      expect(d.message, contains('no ownership structure could be inferred'));
      expect(d.message, contains('Map view'));
      expect(d.message, isNot(contains('Symbols unavailable for this target.')));
    });'''),
    ...para('//', r'One edge among 100 nodes is a ratio of 0.01, below 0.05, and 90 resolved to 2 hex fallbacks is nowhere near the unsymbolized line. The status is noEdges. The message must mention that no ownership structure could be inferred and point to the Map view (the escape hatch, since sizes and growth are still available there), and it must not contain the sentence Symbols unavailable for this target. The isNot(contains(...)) assertion is the part that stops the generic message from claiming certainty it does not have.'),
    ...sec(r'rows 6 to 8: the orphan fix'),
    ...para('//', r'These tests were added by ead62bb, and the commit message explains where they came from. Live testing against checkout_service showed the banner claiming missing debug symbols when 111 of 111 symbols had resolved and zero had fallen back to hex. The real cause was that every node was orphaned. An orphan has no owner by definition, so a graph made entirely of orphans has a near-zero edge ratio for a benign reason that the old branch could not tell apart from a symbol problem. The commit adds a fifth status, noEdgesOrphaned, and a new optional parameter orphanCount.'),
    ...code('dart', r'heaplens_flutter/test/models/target_diagnosis_test.dart · orphans explain the missing edges', r'''
    test('events flowing, nodes present, near-zero edges, symbols fully resolved, '
        'most nodes orphaned: noEdgesOrphaned, not the symbol-envelope message', () {
      final d = TargetDiagnosis.classify(
        eventsReceived: 340226,
        symbolsResolved: 111,
        hexFallback: 0,
        nodeCount: 111,
        edgeCount: 0,
        pastNoEventsWindow: true,
        targetPid: 7048,
        targetName: 'checkout_service',
        orphanCount: 111,
      );
      expect(d.status, TargetStatus.noEdgesOrphaned);
      expect(d.message, isNot(contains('lacks the debug symbols')));
      expect(d.message, contains('111 of 111 allocations are currently orphaned'));
      expect(d.message, contains('Symbols are resolving normally'));
    });'''),
    ...para('//', r'The inputs are lifted from the incident: 340,226 events, 111 symbols resolved, no hex fallback, 111 nodes, no edges, pid 7048, checkout_service, all 111 orphaned. The assertions state the corrected behaviour from both sides: the message must not contain lacks the debug symbols, and it must say 111 of 111 allocations are currently orphaned and Symbols are resolving normally.'),
    ...code('dart', r'heaplens_flutter/test/models/target_diagnosis_test.dart · orphans below the threshold', r'''
    test('near-zero edges with symbols fully resolved but orphan ratio below '
        'threshold: falls back to the original noEdges message, cause unclear', () {
      final d = TargetDiagnosis.classify(
        eventsReceived: 500,
        symbolsResolved: 90,
        hexFallback: 2,
        nodeCount: 100,
        edgeCount: 1,
        pastNoEventsWindow: true,
        targetPid: 1,
        targetName: 'flat.exe',
        orphanCount: 10, // 10% — below kOrphanExplainsNoEdgesRatioThreshold
      );
      expect(d.status, TargetStatus.noEdges);
      expect(d.message, contains('lacks the debug symbols'));
    });'''),
    ...para('//', r'The next row protects the old behaviour. With an orphan ratio of 10 percent, below 0.5, orphaning does not explain the low ratio, so the original noEdges message returns, including lacks the debug symbols. Look at the title: cause unclear. That is an honest limit of the design. In this branch the code has not proven the symbols are missing, it has just not found a better explanation, and the message still asserts it. The test pins the behaviour as it is.'),
    ...code('dart', r'heaplens_flutter/test/models/target_diagnosis_test.dart · unsymbolized wins', r'''
    test('high orphan ratio does not override a genuinely unsymbolized target: '
        'unsymbolized still wins', () {
      final d = TargetDiagnosis.classify(
        eventsReceived: 500,
        symbolsResolved: 2,
        hexFallback: 98,
        nodeCount: 100,
        edgeCount: 0,
        pastNoEventsWindow: true,
        targetPid: 1,
        targetName: 'stripped.exe',
        orphanCount: 90,
      );
      expect(d.status, TargetStatus.unsymbolized);
      expect(d.message, contains('Symbols unavailable for this target.'));
    });'''),
    ...para('//', r'The third orphan row sets orphanCount to 90 of 100 and hex fallback to 98 of 100. Both explanations apply, and the test requires unsymbolized to win. The reason is the line in classify: orphanExplainsNoEdges is computed as not unsymbolized and orphanRatio at or above 0.5. A target without symbols produces orphans and low edge counts for a reason that matters more, so a high orphan ratio must not talk the user out of a real symbol problem.'),
    ...sec(r'rows 9 to 13: unsymbolized and the edges of the table'),
    ...code('dart', r'heaplens_flutter/test/models/target_diagnosis_test.dart · predominantly hex', r'''
    test('events flowing, nodes present, near-zero edges, symbols predominantly hex: unsymbolized', () {
      final d = TargetDiagnosis.classify(
        eventsReceived: 500,
        symbolsResolved: 2,
        hexFallback: 98,
        nodeCount: 100,
        edgeCount: 0,
        pastNoEventsWindow: true,
        targetPid: 1,
        targetName: 'stripped.exe',
      );
      expect(d.status, TargetStatus.unsymbolized);
      expect(d.message, contains('no ownership structure could be inferred'));
      expect(d.message, contains('Symbols unavailable for this target.'));
    });'''),
    ...para('//', r'With 2 resolved and 98 hex fallbacks and no edges the hex ratio is 0.98, so the status is unsymbolized, and the message is the base text plus Symbols unavailable for this target. This is the confirmed version of noEdges, as opposed to the inferred one.'),
    ...code('dart', r'heaplens_flutter/test/models/target_diagnosis_test.dart · zero nodes, events flowing', r'''
    test('zero nodes with events flowing (e.g. all born+freed within a tick): capturing, not noEdges', () {
      final d = TargetDiagnosis.classify(
        eventsReceived: 500,
        symbolsResolved: 10,
        hexFallback: 0,
        nodeCount: 0,
        edgeCount: 0,
        pastNoEventsWindow: true,
        targetPid: 1,
        targetName: 'churny.exe',
      );
      expect(d.status, TargetStatus.capturing, reason: 'noEdges requires nodes to actually be present');
    });'''),
    ...para('//', r'Events keep arriving but nodeCount is 0, say because every allocation was born and freed within one tick. The status must be capturing. The reason string of the expect says why: noEdges requires nodes to actually be present. Without the nodeCount > 0 guard in classify, a division by zero would be avoided by the 0.0 fallback and the edge ratio would be zero, which would then trigger a false noEdges banner on a healthy but fast-churning program.'),
    ...code('dart', r'heaplens_flutter/test/models/target_diagnosis_test.dart · the threshold boundary', r'''
    test('edge ratio right at the threshold is still "no edges" (uses <, not <=, at the boundary below it)', () {
      final d = TargetDiagnosis.classify(
        eventsReceived: 500,
        symbolsResolved: 90,
        hexFallback: 10,
        nodeCount: 100,
        edgeCount: 4, // ratio 0.04 < 0.05 threshold
        pastNoEventsWindow: true,
        targetPid: 1,
        targetName: 'x.exe',
      );
      expect(d.status, TargetStatus.noEdges);
    });

    test('edge ratio above the threshold is capturing, not noEdges', () {
      final d = TargetDiagnosis.classify(
        eventsReceived: 500,
        symbolsResolved: 90,
        hexFallback: 10,
        nodeCount: 100,
        edgeCount: 10, // ratio 0.10 >= 0.05 threshold
        pastNoEventsWindow: true,
        targetPid: 1,
        targetName: 'x.exe',
      );
      expect(d.status, TargetStatus.capturing);
    });'''),
    ...para('//', r'The next two tests sit on either side of 0.05: 4 edges of 100 nodes (0.04) must be noEdges, 10 of 100 (0.10) must be capturing. A caution when reading them: the first test is titled as if it checked the exact boundary and mentions less-than versus less-than-or-equal, but its input of 0.04 is below the threshold, not on it. It does not distinguish the two operators. What it does show is that the threshold sits between 0.04 and 0.10. An input of exactly 5 edges would be the one that pins the operator, and no test has it.'),
    ...code('dart', r'heaplens_flutter/test/models/target_diagnosis_test.dart · raw counts always carried', r'''
    test('raw counts are always carried through regardless of status', () {
      final d = TargetDiagnosis.classify(
        eventsReceived: 7,
        symbolsResolved: 3,
        hexFallback: 4,
        nodeCount: 5,
        edgeCount: 6,
        pastNoEventsWindow: true,
        targetPid: 1,
        targetName: 'x.exe',
      );
      expect(d.eventsReceived, 7);
      expect(d.symbolsResolved, 3);
      expect(d.hexFallback, 4);
      expect(d.nodeCount, 5);
      expect(d.edgeCount, 6);
    });'''),
    ...para('//', r'The last row of the first group has nothing to do with status. Whatever the diagnosis, all five raw counts must be carried on the result. The reason is the banner design noted in the model: a plain message is what most people read, and the exact numbers stay one hover away, in a tooltip and the debug overlay. Distinct values (7, 3, 4, 5, 6) make a swapped field show up immediately.'),
    ...sec(r'the initial value'),
    ...code('dart', r'heaplens_flutter/test/models/target_diagnosis_test.dart · TargetDiagnosis.initial', r'''
  group('TargetDiagnosis.initial', () {
    test('is capturing with no message and all-zero counts', () {
      final d = TargetDiagnosis.initial();
      expect(d.status, TargetStatus.capturing);
      expect(d.message, isNull);
      expect(d.eventsReceived, 0);
      expect(d.nodeCount, 0);
    });
  });'''),
    ...para('//', r'initial() is the state before any stats message has arrived: capturing, no message, all zero. The doc comment in the model gives the reasoning, and it is worth repeating because it is the sort of decision that is easy to get wrong: starting at noEvents would be a claim without evidence, so the app starts silent.'),
    ...sec(r'what to take from the history'),
    ...para('//', r'The first version of classify had four statuses and was right for the cases its author imagined. It took a live run against a real target to find the fifth. Note what the fix did not do: it kept every original test passing and added rows, rather than rewriting the table. That is why the file reads as a layered record: the first five tests are the design, the next three are the correction, and the rest are guards on its edges.'),
  ],
);
