import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/widgets/target_status_banner_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'target_status_banner_test.dart — telling the user why the canvas is empty'),
    cm('//', r'four widget tests that go from stream message to words on screen'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'pins when the banner appears, what it says, and what its Switch to Map view action does'),
    kv('language', r'Dart, flutter_test widget tests with Riverpod overrides'),
    kv('size', r'162 lines, 4 tests'),
    kv('history', r'created in 0edc728 (2026-07-17); the orphan test came with ead62bb (2026-07-22)'),
    kv('subject', r'lib/widgets/target_status_banner.dart'),
    ...sec(r'the last link in a chain'),
    ...para('//', r'Three files lead up to this one. target_diagnosis_test.dart pins the classifier, target_diagnostics_provider_test.dart pins the notifier that feeds it, and this file checks the widget that turns the result into something visible. So it does not re-test the thresholds; it tests that a diagnosis reaches the screen, with the right words, and that the one action on the banner works.'),
    ...code('dart', r'heaplens_flutter/lib/widgets/target_status_banner.dart · what the widget does', r'''
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnosis = ref.watch(targetDiagnosticsProvider);
    if (diagnosis.status == TargetStatus.capturing) {
      return const SizedBox.shrink();
    }

    final color = _kBannerColors[diagnosis.status]!;
    final icon = _kBannerIcons[diagnosis.status]!;
    final showMapViewAction = diagnosis.status == TargetStatus.noEdges ||
        diagnosis.status == TargetStatus.unsymbolized ||
        diagnosis.status == TargetStatus.noEdgesOrphaned;
'''),
    ...para('//', r'The source is short: watch targetDiagnosticsProvider, return an empty box if the status is capturing, otherwise draw a tinted strip with an icon, the message, a tooltip with the raw counts, and, for the three edge-related statuses, a button that switches to the Map view. The colours are chosen to mean something, amber for no events, blue for limitations inherent to the target, and the shared orphan coral for the orphaned case, because that state literally means most of the graph is orphaned.'),
    ...sec(r'the harness'),
    ...code('dart', r'heaplens_flutter/test/widgets/target_status_banner_test.dart · _pumpBanner', r'''
Future<ProviderContainer> _pumpBanner(
  WidgetTester tester,
  StreamController<GraphMessage> controller,
) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        graphMessageProvider.overrideWith((ref) => controller.stream),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return const MaterialApp(
            home: Scaffold(body: TargetStatusBanner()),
          );
        },
      ),
    ),
  );
  return container;
}'''),
    ...para('//', r'Only graphMessageProvider is overridden. Everything else is real: the graph notifier, the diagnostics notifier, the view mode provider. A single stream message is therefore enough to move the entire chain, and the tests double as an integration check from message to widget.'),
    ...sec(r'invisible when nothing is wrong'),
    ...code('dart', r'heaplens_flutter/test/widgets/target_status_banner_test.dart · renders nothing while capturing', r'''
  testWidgets('renders nothing while capturing (no message yet)', (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    await _pumpBanner(tester, controller);

    expect(find.byKey(const Key('targetStatusBanner')), findsNothing);
  });'''),
    ...para('//', r'Before any message the banner is absent. The test looks for the key targetStatusBanner and expects nothing. The healthy case is the common one, and a stray bar in it would train users to ignore the banner.'),
    ...sec(r'the no-events banner, with a lesson about fake time'),
    ...code('dart', r'heaplens_flutter/test/widgets/target_status_banner_test.dart · no events, past the window', r'''
  testWidgets('shows the no-events message once past the window, with name/pid',
      (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpBanner(tester, controller);

    final notifier = container.read(targetDiagnosticsProvider.notifier);
    var now = DateTime(2026, 1, 1);
    notifier.now = () => now;

    controller.add(const GraphStats(
      ts: 1,
      eventsReceived: 0,
      symbolsResolved: 0,
      hexFallback: 0,
      targetPid: 777,
      targetName: 'idle_target.exe',
    ));
    // The stream -> Riverpod StreamProvider -> ref.listen chain delivers
    // across more than one microtask hop, so a single tester.pump() isn't
    // guaranteed to observe the update in the same frame it arrived on.
    // NOTE: use a second bare pump() here, not `Future.delayed` — under
    // flutter_test's fake-async zone, a real Timer (which is what
    // Future.delayed schedules, even for Duration.zero) never fires unless
    // the fake clock is explicitly advanced, so awaiting one directly
    // deadlocks the test until the runner's outer wall-clock timeout.
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('targetStatusBanner')), findsNothing);

    now = now.add(const Duration(seconds: 4));
    controller.add(const GraphStats(
      ts: 2,
      eventsReceived: 0,
      symbolsResolved: 0,
      hexFallback: 0,
      targetPid: 777,
      targetName: 'idle_target.exe',
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('targetStatusBanner')), findsOneWidget);
    expect(find.textContaining('idle_target.exe'), findsOneWidget);
    expect(find.textContaining('[777]'), findsOneWidget);
    // No-events state has no Map-view action — the Map view doesn't help
    // with "nothing is happening".
    expect(find.byKey(const Key('switchToMapViewButton')), findsNothing);
  });'''),
    ...para('//', r'The test first takes the diagnostics notifier from the container and installs a fake clock, as in the provider tests. Then it sends a zero-event stats message for pid 777, idle_target.exe, and expects no banner: inside the window. The clock moves forward four seconds, a second message arrives, and the banner must now exist, with the name idle_target.exe and [777] in its text. The last assertion is a negative one: there is no Switch to Map view button, with the comment that the Map view does not help with nothing is happening. That matches the showMapViewAction condition in the source, which lists three statuses and leaves noEvents out.'),
    ...para('//', r'The comment in the middle is worth reading closely. It explains why the test pumps twice, and why it does not wait with Future.delayed as the provider tests do. The message goes through a stream, a StreamProvider and a ref.listen, which takes more than one microtask hop, so a single pump may not see it. And in a widget test, Future.delayed creates a real Timer inside flutter_test’s fake-async zone, which never fires unless the fake clock is advanced, so awaiting it hangs the test until the runner’s own timeout. The comment records the symptom and the cure, a second bare pump().'),
    ...sec(r'the no-edges banner and its action'),
    ...code('dart', r'heaplens_flutter/test/widgets/target_status_banner_test.dart · Switch to Map view', r'''
  testWidgets('no-edges banner offers a Switch to Map view action that updates viewModeProvider',
      (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpBanner(tester, controller);

    container.read(graphProvider.notifier).applyDiff(
      GraphSnapshot(ts: 1, nodes: List.generate(10, (i) => _node(id: i))),
    );
    controller.add(const GraphStats(ts: 1, eventsReceived: 500, symbolsResolved: 10, hexFallback: 0));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('targetStatusBanner')), findsOneWidget);
    expect(find.textContaining('no ownership structure could be inferred'), findsOneWidget);
    expect(find.byKey(const Key('switchToMapViewButton')), findsOneWidget);

    expect(container.read(viewModeProvider), ViewMode.graph);
    await tester.tap(find.byKey(const Key('switchToMapViewButton')));
    await tester.pump();
    expect(container.read(viewModeProvider), ViewMode.memoryMap);
  });'''),
    ...para('//', r'Ten edgeless nodes are put in the graph, then a stats message with 500 events and ten resolved symbols arrives. The banner appears, contains no ownership structure could be inferred, and shows the switchToMapViewButton. Then the test closes the loop: viewModeProvider is graph before the tap and memoryMap after it. This is the only place in the suite where the escape hatch is exercised by a real tap. It matters because the message promises that sizes and growth remain available in the Map view; a button that did not go there would be a lie.'),
    ...sec(r'the orphan correction, at widget level'),
    ...code('dart', r'heaplens_flutter/test/widgets/target_status_banner_test.dart · all nodes orphaned', r'''
  testWidgets(
      'all nodes orphaned with symbols fully resolved: shows the '
      'orphan-explained message, not the symbol-envelope one, and still '
      'offers Switch to Map view', (tester) async {
    final controller = StreamController<GraphMessage>();
    addTearDown(() => controller.close());
    final container = await _pumpBanner(tester, controller);

    container.read(graphProvider.notifier).applyDiff(
      GraphSnapshot(
        ts: 1,
        nodes: List.generate(
          10,
          (i) => _node(id: i, state: NodeStateDto.orphan),
        ),
      ),
    );
    controller.add(const GraphStats(ts: 1, eventsReceived: 500, symbolsResolved: 10, hexFallback: 0));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('targetStatusBanner')), findsOneWidget);
    expect(find.textContaining('lacks the debug symbols'), findsNothing);
    expect(find.textContaining('currently orphaned'), findsOneWidget);
    expect(find.byKey(const Key('switchToMapViewButton')), findsOneWidget);
  });'''),
    ...para('//', r'The fix in ead62bb came from a live observation that the banner blamed missing symbols when every node was orphaned. The model test and the provider test each pin their part. This one pins what the user sees: ten orphan nodes, ten resolved symbols, and the banner must not contain lacks the debug symbols, must contain currently orphaned, and must still offer the Map view button. The negative text assertion is the one that would have failed the day the bug was found.'),
    ...sec(r'what is not asserted'),
    ...pt('//', r'the hover', r'the tooltip with the raw counts (events, symbols resolved over total, nodes, edges) is part of the design, but no test hovers over the banner or reads its message.'),
    ...pt('//', r'colour and icon', r'the three colour and icon tables are not checked, so a swap would pass.'),
    ...pt('//', r'the unsymbolized path', r'no widget test reaches the unsymbolized status; it is covered at the model and provider levels.'),
    ...pt('//', r'the debug overlay', r'the same counts are mirrored into a debug overlay according to the widget doc; the overlay is not part of this test.'),
  ],
);
