import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/widgets/control_bar_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'control_bar_test.dart — the ribbon at the top, and one button with a history'),
    cm('//', r'eleven widget tests, including the gate that was closed, opened, closed and opened again'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'pins the control bar: connection status, counters, pause, filters, view toggle, attach and detach'),
    kv('language', r'Dart, flutter_test widget tests with Riverpod overrides'),
    kv('size', r'332 lines, 11 tests (7 top-level, 4 in an attach/detach group)'),
    kv('history', r'0309d9e (2026-07-06) created it; 1cfb7f9 (2026-07-19) reworked it for the ribbon; 31bc7ee, 864167e, 306e8fc (2026-07-21..26) and 9693399 (2026-07-28) toggled the attach gate'),
    kv('subject', r'lib/widgets/control_bar.dart'),
    ...sec(r'what the control bar is'),
    ...para('//', r'ControlBar is the strip across the top of the window: connection status, live counters, the pause button, the filters, the view toggle, and the attach and detach controls. It owns no data of its own. Every control reads a provider or writes one, which is the reason its tests are shaped the way they are: put the widget in a tree, poke a provider or tap a control, and assert on the provider on the other side. The widget is verified by what it does to the rest of the app, not by pixels.'),
    ...sec(r'the harness'),
    ...code('dart', r'heaplens_flutter/test/widgets/control_bar_test.dart · _pumpControlBar', r'''
Future<ProviderContainer> _pumpControlBar(
  WidgetTester tester,
  StreamController<GraphMessage> controller, {
  List<Override> extraOverrides = const [],
}) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        graphMessageProvider.overrideWith((ref) => controller.stream),
        // ControlBar unconditionally `ref.listen`s controlResponseProvider
        // (Stage 7 §4.4's target-exit banner) — which builds it even when a
        // test doesn't care about it. Left unoverridden, that would build
        // the *real* provider and open a real WebSocket connection attempt
        // during every test in this file. An empty, never-emitting stream
        // is a safe default; tests that do care override it themselves via
        // extraOverrides.
        controlResponseProvider.overrideWith((ref) => const Stream.empty()),
        ...extraOverrides,
      ],
      child: Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return const MaterialApp(
            home: Scaffold(body: ControlBar()),
          );
        },
      ),
    ),
  );
  return container;
}'''),
    ...para('//', r'Every test goes through one helper. It overrides graphMessageProvider with a controllable stream, exactly like the other widget tests, and wraps ControlBar in a MaterialApp and Scaffold, because the Material widgets inside need a theme and a surface. A Consumer captures the ProviderContainer so tests can read and write providers.'),
    blank,
    ...para('//', r'The second override has a long comment and it is a lesson. ControlBar listens to controlResponseProvider unconditionally, for the snackbar shown when the target exits. Left alone, the first test would build the real provider, and the real provider opens a real WebSocket connection attempt. The helper overrides it with Stream.empty(), safe because it never emits, and lets a test that cares pass its own replacement through extraOverrides. A hidden network side effect in a unit test would be both slow and unreliable; the comment records that it was found, not guessed.'),
    ...sec(r'connection status'),
    ...code('dart', r'heaplens_flutter/test/widgets/control_bar_test.dart · status labels', r'''
  testWidgets('connection status displays correctly for each state',
      (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpControlBar(tester, controller);

    container.read(connectionStatusProvider.notifier).state =
        ConnectionStatus.connecting;
    await tester.pump();
    expect(find.text('Connecting…'), findsOneWidget);

    container.read(connectionStatusProvider.notifier).state =
        ConnectionStatus.connected;
    await tester.pump();
    expect(find.text('Connected'), findsOneWidget);

    container.read(connectionStatusProvider.notifier).state =
        ConnectionStatus.disconnected;
    await tester.pump();
    expect(find.text('Disconnected'), findsOneWidget);
  });'''),
    ...para('//', r'The test writes the three ConnectionStatus values into connectionStatusProvider in turn, and after each one expects the matching text: Connecting with a Unicode ellipsis, Connected, Disconnected. Because the text is looked up with findsOneWidget, it also guarantees that only one label is on screen at a time. The dot colour next to the label is not asserted; the source keeps it in a lookup table, kConnectionStatusColors.'),
    ...sec(r'live counters'),
    ...code('dart', r'heaplens_flutter/test/widgets/control_bar_test.dart · counters follow the graph', r'''
  testWidgets('live counters reflect the graph provider derived getters',
      (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpControlBar(tester, controller);

    final healthy = _node(id: 1, size: 100);
    final orphan = _node(id: 2, size: 50, state: NodeStateDto.orphan);
    container.read(graphProvider.notifier).applyDiff(
          GraphSnapshot(ts: 1, nodes: [healthy, orphan]),
        );
    await tester.pump();

    expect(find.text('Nodes: '), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // liveNodeCount
    expect(find.text('1'), findsOneWidget); // orphanCount
    expect(find.text('150'), findsOneWidget); // totalLiveBytes
  });'''),
    ...para('//', r'The test applies a snapshot with two nodes through the real graph notifier, one healthy of 100 bytes and one orphan of 50, and expects to find the numbers 2 (live nodes), 1 (orphans) and 150 (live bytes). This is the widget half of graph_provider_test.dart’s derived getters: that file checks the arithmetic, this one checks the bar is wired to it and rebuilds on a new revision.'),
    ...para('//', r'A fragility to know about: the lookups are find.text(‘2’) and find.text(‘1’) with findsOneWidget, so they pass only while no other widget in the ribbon shows the bare text 1 or 2. They would break if another counter happened to take one of those values.'),
    ...sec(r'pause is a real gate'),
    ...code('dart', r'heaplens_flutter/test/widgets/control_bar_test.dart · pause and resume', r'''
  testWidgets(
      'pause gates applyDiff: a message arriving while paused does not '
      'change graph state, one arriving after resume does', (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpControlBar(tester, controller);

    expect(container.read(pausedProvider), isFalse);

    // Pause via the button.
    await tester.tap(find.byKey(const Key('pauseResumeButton')));
    await tester.pump();
    expect(container.read(pausedProvider), isTrue);

    final revisionBefore = container.read(graphProvider);
    controller.add(GraphSnapshot(ts: 1, nodes: [_node(id: 1)]));
    await tester.pump();
    await tester.pump();

    // Paused: the message must be dropped, not applied.
    expect(container.read(graphProvider), revisionBefore);
    expect(container.read(graphProvider.notifier).nodes, isEmpty);

    // Resume via the button.
    await tester.tap(find.byKey(const Key('pauseResumeButton')));
    await tester.pump();
    expect(container.read(pausedProvider), isFalse);

    controller.add(GraphSnapshot(ts: 2, nodes: [_node(id: 1)]));
    await tester.pump();
    await tester.pump();

    // Resumed: the next message must be applied.
    expect(container.read(graphProvider), revisionBefore + 1);
    expect(container.read(graphProvider.notifier).nodes.containsKey(1), isTrue);
  });'''),
    ...para('//', r'The test works through the actual button. It taps the pauseResumeButton and checks pausedProvider is true. Then it pushes a snapshot through the stream. The revision must be unchanged and the node map empty, because the message was dropped and not queued. After a second tap, the next snapshot is applied, the revision goes up by exactly one, and node 1 is present. Two details make it strong: it records revisionBefore so it does not rely on a magic number, and it checks that a message sent while paused is lost rather than delayed by sending a different snapshot after resuming (ts 2) and only expecting that one.'),
    ...para('//', r'This is the only test that exercises the pause gate inside graph_provider.dart; graph_provider_test.dart has none. It pumps twice after each stream event.'),
    ...sec(r'four controls that write to a provider'),
    ...code('dart', r'heaplens_flutter/test/widgets/control_bar_test.dart · view mode', r'''
  testWidgets('view mode toggle updates viewModeProvider', (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpControlBar(tester, controller);

    expect(container.read(viewModeProvider), ViewMode.graph);

    await tester.tap(find.text('Memory Map'));
    await tester.pump();

    expect(container.read(viewModeProvider), ViewMode.memoryMap);
  });'''),
    ...code('dart', r'heaplens_flutter/test/widgets/control_bar_test.dart · min-size slider', r'''
  testWidgets('min-size slider updates minSizeFilterProvider', (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpControlBar(tester, controller);

    expect(container.read(minSizeFilterProvider), 0);

    final sliderFinder = find.byKey(const Key('minSizeSlider'));
    await tester.drag(sliderFinder, const Offset(50, 0));
    await tester.pump();

    expect(container.read(minSizeFilterProvider), greaterThan(0));
  });'''),
    ...code('dart', r'heaplens_flutter/test/widgets/control_bar_test.dart · orphan switch and search field', r'''
  testWidgets('orphan-only switch updates orphanOnlyFilterProvider',
      (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpControlBar(tester, controller);

    expect(container.read(orphanOnlyFilterProvider), isFalse);

    await tester.tap(find.byKey(const Key('orphanOnlySwitch')));
    await tester.pump();

    expect(container.read(orphanOnlyFilterProvider), isTrue);
  });

  testWidgets('symbol search field updates symbolSearchFilterProvider',
      (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpControlBar(tester, controller);

    expect(container.read(symbolSearchFilterProvider), '');

    await tester.enterText(
      find.byKey(const Key('symbolSearchField')),
      'alloc::vec',
    );
    await tester.pump();

    expect(container.read(symbolSearchFilterProvider), 'alloc::vec');
  });'''),
    ...para('//', r'Four short tests share one structure: read the provider default, act on the control, read the provider again. Tapping the text Memory Map flips viewModeProvider from graph to memoryMap. Dragging the slider by 50 pixels moves minSizeFilterProvider from 0 to something above zero. Tapping the orphan switch flips orphanOnlyFilterProvider from false to true. Entering alloc::vec into the search field sets symbolSearchFilterProvider to the same string, starting from the empty string. The slider assertion is deliberately loose, greaterThan(0), since the exact value depends on the slider geometry in the test window. The controls are found by Key (minSizeSlider, orphanOnlySwitch, symbolSearchField), which is how the widget tests stay independent of layout.'),
    ...sec(r'attach and detach'),
    ...code('dart', r'heaplens_flutter/test/widgets/control_bar_test.dart · nothing attached', r'''
  group('attach/detach control (Stage 7 §3/Step 4)', () {
    testWidgets('shows "Attach to Process…" when nothing is attached', (tester) async {
      final controller = StreamController<GraphMessage>();
      addTearDown(() => controller.close());
      await _pumpControlBar(tester, controller);

      expect(find.byKey(const Key('attachButton')), findsOneWidget);
      expect(find.byKey(const Key('detachButton')), findsNothing);
    });'''),
    ...para('//', r'With no target attached, the bar offers the attach button and no detach button. This test only checks presence, and the next one exists because presence is not enough.'),
    ...sec(r'a button that has been closed, opened, closed and opened'),
    ...para('//', r'This is the part of the file with the most history, and it can only be understood with the dates.'),
    ...pt('//', r'2026-07-21, 31bc7ee', r'a coverage gap is closed. The old tests checked the button by key, never whether it was disabled. The new test asserted onPressed was exactly null, the tooltip carried the exact disabled reason, and kAttachEnabled was false. The commit message gives the reason: a future edit could silently re-enable attachment, or water down the explanation, without failing anything.'),
    ...pt('//', r'2026-07-22, 864167e', r'the gate is flipped to true. The commit says the hook defect behind the gate was root-caused and fixed and lists its evidence: a self-load concurrency stress test, a long soak against a real Node.js process, and injection validated on three different real targets. It also adds a pre-attach check that refuses processes with kernel-driver components.'),
    ...pt('//', r'2026-07-26, 306e8fc', r'the gate is closed again, honestly and specifically. A second, different defect was confirmed: a target that exits normally while the hooks are still installed crashes with an access violation. The commit re-scopes this test back to the disabled branch and updates the tooltip to name the finding.'),
    ...pt('//', r'2026-07-28, 9693399', r'the gate is open again, in a commit that also adds a terminal-UI demo backdrop. The comment in control_bar.dart says both confirmed defects are fixed and validated on that branch.'),
    ...code('dart', r'heaplens_flutter/lib/widgets/control_bar.dart · the gate and its two texts', r'''
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
    'software) for safety.';
'''),
    ...para('//', r'The source keeps the flag as a single flippable constant. Its comment explains the policy: the gate stays so that any future regression can be disabled the same visible, honest way, present but disabled with a reason, never silently removed. Both tooltip texts live next to it. The current test pins the enabled branch.'),
    ...code('dart', r'heaplens_flutter/test/widgets/control_bar_test.dart · the enabled branch is pinned', r'''
    // Coverage gap flagged after the injection-safety-gate merge (2026-07-21):
    // the tests above only ever checked presence/absence of the button by
    // key, never whether it was actually *disabled*/*enabled*, nor what the
    // tooltip actually says. A future edit could silently flip the button's
    // behavior, or water down/drop the explanation, without failing
    // anything — this closes that gap.
    //
    // Re-scoped 2026-07-28 when kAttachEnabled flipped back to true (both
    // confirmed hook defects behind the two prior disable periods are fixed
    // and validated on this branch — see control_bar.dart's doc comment).
    // This pins the *enabled*-branch behavior. A future re-disable of the
    // gate should update this test back to the disabled-branch version (see
    // git history), not leave it silently asserting the wrong branch.
    testWidgets(
        'Attach button is genuinely enabled (onPressed is set) and carries '
        'the exact, specific validated-scope tooltip while kAttachEnabled '
        'is true', (tester) async {
      final controller = StreamController<GraphMessage>();
      addTearDown(() => controller.close());
      await _pumpControlBar(tester, controller);

      // Pin the real, current gate state this test's assertions depend on —
      // if this ever flips back, the assertions below intentionally stop
      // matching production behavior, which is exactly the point.
      expect(kAttachEnabled, isTrue,
          reason: 'this test asserts the *enabled* branch; it must be '
              'updated (or a companion disabled-state test added) if this '
              'flag ever flips back to false');

      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('attachButton')),
      );
      expect(
        button.onPressed,
        isNotNull,
        reason: 'must be genuinely enabled (onPressed set), not left null',
      );

      final tooltip = tester.widget<Tooltip>(
        find.byKey(const Key('attachEnabledTooltip')),
      );
      expect(
        tooltip.message,
        kAttachEnabledInfo,
        reason: 'the enabled-info tooltip text must match exactly — a '
            'future edit that waters down or vagues-up the validated-scope '
            'explanation must fail here, not pass silently',
      );
    });'''),
    ...para('//', r'Read the long comment above the test: it is addressed to a future maintainer. It says the test now asserts the enabled branch and that a future re-disable of the gate should update it back to the disabled version, found in git history, rather than leave it silently asserting the wrong branch. To make that hard to miss, the test starts with expect(kAttachEnabled, isTrue) and a reason string that says the same. Then it asserts three things on the widget tree and not on the constants: the ElevatedButton’s onPressed is not null, a Tooltip with the key attachEnabledTooltip exists, and its message is exactly kAttachEnabledInfo. The key itself changes with the gate, so a disabled tooltip would not even be found.'),
    ...para('//', r'The commit message for 31bc7ee says why no test flips the flag: it is a genuine top-level const baked into a private widget, so a test cannot change it. The consequence is that one of the two branches is always untested in a given commit, and the history above is the proof that it matters.'),
    ...code('dart', r'heaplens_flutter/test/widgets/control_bar_test.dart · attached: name, pid and Detach', r'''
    testWidgets('shows the attached target\'s name/pid and a Detach button once attached',
        (tester) async {
      final controller = StreamController<GraphMessage>();
      addTearDown(() => controller.close());
      final container = await _pumpControlBar(tester, controller);

      container.read(attachedTargetProvider.notifier).setAttached(
            const AttachedTarget(pid: 4242, name: 'target.exe'),
          );
      await tester.pump();

      expect(find.byKey(const Key('attachButton')), findsNothing);
      expect(find.byKey(const Key('attachedTargetLabel')), findsOneWidget);
      expect(find.text('target.exe (pid 4242)'), findsOneWidget);
      expect(find.byKey(const Key('detachButton')), findsOneWidget);
    });'''),
    ...para('//', r'Once setAttached has been called, the attach button is gone, a label with the key attachedTargetLabel is present, the text target.exe (pid 4242) is on screen, and the detach button is there. All it needs is a state change in target_provider.'),
    ...code('dart', r'heaplens_flutter/test/widgets/control_bar_test.dart · Detach sends the request and clears', r'''
    testWidgets('tapping Detach sends DetachTargetRequest and clears the attached target',
        (tester) async {
      final controller = StreamController<GraphMessage>();
      addTearDown(() => controller.close());
      final sent = <String>[];
      // A never-closing stream, not `Stream.empty()` — an empty stream
      // completes (fires `onDone`) as soon as it's listened to, which would
      // immediately trigger GraphMessageConnection's reconnect path and
      // clear the very `_sendCurrent` this test needs `sendRequest` to
      // forward through, before the tap below ever happens.
      final neverCloses = StreamController<dynamic>();
      addTearDown(neverCloses.close);
      final fakeConnection = GraphMessageConnection(
        connector: () => WsFrames(neverCloses.stream, () {}, sent.add),
        backoff: (_) => Duration.zero,
        onStatus: (_) {},
        onMessage: (_) {},
        onError: (e, st) {},
      );
      fakeConnection.start();
      addTearDown(fakeConnection.dispose);

      final container = await _pumpControlBar(
        tester,
        controller,
        extraOverrides: [
          wsConnectionProvider.overrideWithValue(fakeConnection),
        ],
      );

      container.read(attachedTargetProvider.notifier).setAttached(
            const AttachedTarget(pid: 4242, name: 'target.exe'),
          );
      await tester.pump();

      await tester.tap(find.byKey(const Key('detachButton')));
      await tester.pump();

      expect(sent, [jsonEncode(const DetachTargetRequest().toJson())]);
      // Detach is optimistic client-side (target_provider.dart's doc) — the
      // attached target clears immediately, before any daemon reply.
      expect(container.read(attachedTargetProvider), isNull);
      expect(find.byKey(const Key('attachButton')), findsOneWidget);
    });'''),
    ...para('//', r'The most elaborate test in the file. The bar must send a DetachTargetRequest through the real connection object and clear the attached state at once. To observe the send, the test builds a GraphMessageConnection with a fake connector whose WsFrames carries a send function that appends to a list, and injects it with wsConnectionProvider.overrideWithValue. After tapping detach, sent must equal the JSON for the request, and the attached target must be null with the attach button visible again.'),
    ...para('//', r'The comment on neverCloses is another hard-won detail. An empty stream completes the moment it is listened to, and that triggers the connection’s reconnect path, which clears the very send function the test needs. So the fake uses a StreamController that is never closed. Here a test double behaved like a real network failure by accident.'),
    ...para('//', r'The assertion that the target is cleared before any reply is the optimistic behaviour documented in target_provider.dart, covered further in target_provider_test.dart.'),
    ...sec(r'things left out'),
    ...pt('//', r'dead text', r'kAttachDisabledReason is still defined while the gate is open, and no test reads it. It is only reachable when the gate is closed.'),
    ...pt('//', r'the picker', r'tapping Attach opens the process picker; that dialog has its own test file.'),
    ...pt('//', r'the target-exit snackbar', r'the control bar also listens for the target exit push; the helper silences it with an empty stream, and none of these tests exercise that snackbar.'),
  ],
);
