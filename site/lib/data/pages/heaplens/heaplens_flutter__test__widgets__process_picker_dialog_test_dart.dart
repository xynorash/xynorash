import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/widgets/process_picker_dialog_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'process_picker_dialog_test.dart — choosing a victim, politely'),
    cm('//', r'four widget tests of the attach dialog, driven by a fake daemon'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'pins the picker contract: request the list, disable x86, send attach, handle ok and failure'),
    kv('language', r'Dart, flutter_test widget tests with a fake GraphMessageConnection'),
    kv('size', r'157 lines, 4 testWidgets'),
    kv('history', r'one commit, 1cfb7f9 (2026-07-19), the UI refresh that introduced the dialog'),
    kv('subject', r'lib/widgets/process_picker_dialog.dart'),
    kv('design doc', r'docs/stage7-injection-design.md, section 8 (acceptance gate), as cited in the test'),
    ...sec(r'what the test says about itself'),
    ...para('//', r'The doc comment at the top of the test file is unusually frank. It calls itself a partial acceptance gate for Stage 7 Step 4, and says the rest is a manual run against a real daemon and target. What this file covers is the picker’s UI contract in isolation, driven entirely through fakes with no real daemon or WebSocket. That sets the scope for everything below: these tests prove the dialog sends the right requests and reacts correctly to the right replies. They do not prove injection works.'),
    ...code('dart', r'heaplens_flutter/test/widgets/process_picker_dialog_test.dart · the file header comment', r'''
/// Stage 7 Step 4 acceptance gate (partial — the rest is a manual run
/// against a real daemon+target per docs/stage7-injection-design.md §8):
/// this covers the picker's own UI contract in isolation — it requests the
/// process list on open, sends `AttachTarget` on selection, and surfaces
/// both success (records the attached target, closes) and failure (daemon's
/// own message text, verbatim, dialog stays open) — driven entirely through
/// fakes, no real daemon or WebSocket involved.'''),
    ...sec(r'the dialog'),
    ...code('dart', r'heaplens_flutter/lib/widgets/process_picker_dialog.dart · what the dialog does', r'''
/// Stage 7 Step 4: the attach-target picker. Requests the process list on
/// open, lets the user pick a process, sends `AttachTarget`, and surfaces
/// the result — success closes the dialog and records the attached target;
/// failure (nonexistent/access-denied pid, per §3.3) stays open and shows
/// the daemon's own message text verbatim, not a generic "failed."
///
/// A 32-bit (`arch != "x64"`) process is shown but disabled with an
/// explanatory subtitle rather than hidden — matching §3.3's "this build of
/// HeapLens is 64-bit and cannot attach" message, surfaced *before* the'''),
    ...para('//', r'Open the dialog, it asks the daemon for processes. Pick one, it sends an attach request and waits for the result. Success records the target and closes. Failure stays open and shows the daemon’s own words. A process that is not 64-bit is listed but disabled, with a reason, instead of being hidden. The four tests are one per sentence, which is why they read almost like the doc comment.'),
    ...sec(r'the fixture: a real connection object over a fake socket'),
    ...code('dart', r'heaplens_flutter/test/widgets/process_picker_dialog_test.dart · pumpPicker: the fake connection', r'''
  Future<(ProviderContainer, StreamController<ControlResponse>, List<String>)> pumpPicker(
    WidgetTester tester,
  ) async {
    final controlController = StreamController<ControlResponse>.broadcast();
    addTearDown(controlController.close);
    final sent = <String>[];
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
    addTearDown(fakeConnection.dispose);'''),
    ...para('//', r'The helper builds a real GraphMessageConnection, with a connector that returns a WsFrames whose send function appends to a list called sent. So requests are captured as the exact JSON strings that would go on the wire. A StreamController.broadcast plays the daemon’s control replies. The connection is injected through wsConnectionProvider.overrideWithValue and the reply stream through controlResponseProvider.overrideWith.'),
    ...para('//', r'The use of a stream that never closes is not an accident: the same comment appears in control_bar_test.dart. An empty or closed stream would fire onDone and push the connection into its reconnect path, which clears the send function the tests are trying to observe. The fake daemon must stay connected.'),
    ...code('dart', r'heaplens_flutter/test/widgets/process_picker_dialog_test.dart · pumpPicker: open the dialog', r'''
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          controlResponseProvider.overrideWith((ref) => controlController.stream),
          wsConnectionProvider.overrideWithValue(fakeConnection),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => showProcessPickerDialog(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    // Not pumpAndSettle: the dialog shows an indeterminate
    // CircularProgressIndicator while `_processes` is still null, which
    // animates forever and would make pumpAndSettle time out. A couple of
    // bounded pumps is enough to finish the dialog's own open transition.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    return (container, controlController, sent);
  }'''),
    ...para('//', r'The dialog is opened the way a user would, by tapping a button whose callback calls showProcessPickerDialog. Then comes a careful comment about time. The test does not use pumpAndSettle, because while the process list is still null the dialog shows an indeterminate progress indicator, which animates forever, and pumpAndSettle would time out waiting for the animation to end. Instead: one pump, then one pump of 300 ms, enough for the open transition. The helper returns a Dart record of the container, the reply controller and the sent list, so each test destructures what it needs.'),
    ...sec(r'test 1: ask on open'),
    ...code('dart', r'heaplens_flutter/test/widgets/process_picker_dialog_test.dart · opening the picker requests the process list', r'''
  testWidgets('opening the picker requests the process list and shows returned processes', (tester) async {
    final (_, controlController, sent) = await pumpPicker(tester);

    expect(sent, [
      '{"type":"list_processes"}',
    ]);
    expect(find.byKey(const Key('processPickerList')), findsNothing); // still loading

    controlController.add(const ProcessListResponse([
      ProcessInfo(pid: 111, name: 'target.exe', arch: 'x64'),
      ProcessInfo(pid: 222, name: 'legacy32.exe', arch: 'x86'),
    ]));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('processPickerList')), findsOneWidget);
    expect(find.text('target.exe'), findsOneWidget);
    expect(find.text('legacy32.exe'), findsOneWidget);
  });'''),
    ...para('//', r'The first assertion is on the wire: sent must equal exactly one string, {"type":"list_processes"}. Opened means asked, so no user action is needed. The test also checks that the list widget is not on screen yet, which is the loading state. Then the fake daemon answers with two processes, a 64-bit target.exe and a 32-bit legacy32.exe, the list appears, and both names are on screen.'),
    ...code('dart', r'heaplens_flutter/lib/widgets/process_picker_dialog.dart · the request on open', r'''
      _processes = null;
      _error = null;
    });
    ref.read(wsConnectionProvider).sendRequest(const ListProcessesRequest());
  }'''),
    ...sec(r'test 2: show the 32-bit process, disabled'),
    ...code('dart', r'heaplens_flutter/test/widgets/process_picker_dialog_test.dart · an x86 process is shown disabled, not hidden', r'''
  testWidgets('an x86 process is shown disabled, with an explanatory subtitle, not hidden', (tester) async {
    final (_, controlController, _) = await pumpPicker(tester);

    controlController.add(const ProcessListResponse([
      ProcessInfo(pid: 222, name: 'legacy32.exe', arch: 'x86'),
    ]));
    await tester.pumpAndSettle();

    final tile = tester.widget<ListTile>(find.byKey(const Key('processPickerItem_222')));
    expect(tile.enabled, isFalse);
    expect(find.textContaining('64-bit and cannot attach'), findsOneWidget);
  });'''),
    ...para('//', r'The title says it all: shown, disabled, with a subtitle, not hidden. The test reads the ListTile for pid 222 by its key processPickerItem_222 and asserts enabled is false, then looks for the words 64-bit and cannot attach. The widget doc says why: surface the limit before the user wastes a click on a target that would only fail at attach time. The source uses the architecture string, anything other than x64 is disabled, and the subtitle reads that this build of HeapLens is 64-bit and cannot attach.'),
    ...code('dart', r'heaplens_flutter/lib/widgets/process_picker_dialog.dart · the list tile', r'''
                          key: const Key('processPickerList'),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final p = filtered[i];
                            final attachable = p.arch == 'x64';
                            return ListTile(
                              key: Key('processPickerItem_${p.pid}'),
                              enabled: attachable && !_attaching,
                              title: Text(p.name),
                              subtitle: Text(
                                attachable
                                    ? 'pid ${p.pid} · ${p.arch}'
                                    : 'pid ${p.pid} · ${p.arch} — this build of HeapLens is 64-bit and cannot attach',
                              ),
                              onTap: attachable ? () => _attach(p) : null,
                            );'''),
    ...sec(r'test 3: the happy path'),
    ...code('dart', r'heaplens_flutter/test/widgets/process_picker_dialog_test.dart · selecting a process sends AttachTarget; success records and closes', r'''
  testWidgets('selecting a process sends AttachTarget and a successful reply records + closes', (tester) async {
    final (container, controlController, sent) = await pumpPicker(tester);

    controlController.add(const ProcessListResponse([
      ProcessInfo(pid: 111, name: 'target.exe', arch: 'x64'),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('processPickerItem_111')));
    await tester.pump();

    expect(sent, [
      '{"type":"list_processes"}',
      '{"type":"attach_target","pid":111}',
    ]);

    controlController.add(const AttachResultResponse(ok: true, message: 'attached to pid 111'));
    await tester.pumpAndSettle();

    // Dialog closed.
    expect(find.byKey(const Key('processPickerList')), findsNothing);
    final attached = container.read(attachedTargetProvider);
    expect(attached?.pid, 111);
    expect(attached?.name, 'target.exe');
  });'''),
    ...para('//', r'After the list appears, the test taps pid 111. The sent list must now hold two strings in order: list_processes, then {"type":"attach_target","pid":111}. Then the fake daemon replies attach_result ok true, and the dialog must be closed (the list widget is gone) and attachedTargetProvider must hold pid 111 with the name target.exe.'),
    ...para('//', r'The name is the interesting part. The attach reply carries only a message, not a name, so the dialog has to remember which row was tapped and pass its name to setAttached. This is the reason target_provider.dart says the target is set explicitly. The assertion on the name closes that loop from the other side.'),
    ...code('dart', r'heaplens_flutter/lib/widgets/process_picker_dialog.dart · the attach method', r'''
  Future<void> _attach(ProcessInfo process) async {
    if (process.arch != 'x64' || _attaching) return;
    setState(() {
      _attaching = true;
      _error = null;
    });

    // Start listening for the reply *before* sending, so a very fast daemon
    // reply can't arrive and be missed between the send and the listen.
    final replyFuture = _listenOnce<AttachResultResponse>();
    ref.read(wsConnectionProvider).sendRequest(AttachTargetRequest(process.pid));
    final resp = await replyFuture;
    if (!mounted) return;

    if (resp == null) {
      setState(() {
        _attaching = false;
        _error = 'No response from daemon (timed out).';
      });
      return;
    }
    if (resp.ok) {
      ref.read(attachedTargetProvider.notifier).setAttached(
            AttachedTarget(pid: process.pid, name: process.name),
          );
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _attaching = false;
      _error = resp.message;
    });
  }
'''),
    ...para('//', r'The source of the method makes a subtle point in a comment. It starts listening for the reply before sending the request, so a very fast daemon reply cannot arrive and be missed between the send and the listen. The test cannot reproduce that race, because the fake reply is added after the tap, but the ordering of the sent list is checked.'),
    ...sec(r'test 4: failure stays visible'),
    ...code('dart', r'heaplens_flutter/test/widgets/process_picker_dialog_test.dart · an attach failure surfaces the daemon message verbatim', r'''
  testWidgets('an attach failure surfaces the daemon\'s message verbatim; dialog stays open', (tester) async {
    final (container, controlController, _) = await pumpPicker(tester);

    controlController.add(const ProcessListResponse([
      ProcessInfo(pid: 999999999, name: 'ghost.exe', arch: 'x64'),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('processPickerItem_999999999')));
    await tester.pump();

    controlController.add(const AttachResultResponse(
      ok: false,
      message: 'cannot open process 999999999 — access denied, or the process does not exist.',
    ));
    await tester.pumpAndSettle();

    // Dialog stays open — not a silent no-op.
    expect(find.byKey(const Key('processPickerList')), findsOneWidget);
    expect(
      find.byKey(const Key('processPickerError')),
      findsOneWidget,
    );
    expect(find.textContaining('access denied'), findsOneWidget);
    expect(container.read(attachedTargetProvider), isNull);
  });'''),
    ...para('//', r'A process with pid 999999999 is picked, and the fake daemon answers ok false with cannot open process 999999999 followed by access denied, or the process does not exist. The dialog must remain open (list still found), show a widget with the key processPickerError, and contain the words access denied. The attached target must still be null. The comment in the test says what the alternative would be: a silent no-op. A dialog that closed on failure, or showed generic words, would leave the user guessing why a click did nothing.'),
    ...para('//', r'Exactly the same string is used in control_test.dart, where the model is asserted to carry the message verbatim. Together the two tests cover the path from the daemon’s text to the user’s screen without a rewrite in between.'),
    ...sec(r'a timeout nobody tests'),
    ...code('dart', r'heaplens_flutter/lib/widgets/process_picker_dialog.dart · the reply wait and its timer', r'''
  ///
  /// Uses one `Completer` driven by both the listener and an explicit,
  /// cancelable `Timer` — not `Future.any([completer.future, Future.delayed(...)])`,
  /// which was tried first: `Future.any` doesn't cancel the losing branch's
  /// own `Timer` once the other one wins, so a `Future.delayed` for the
  /// timeout kept running for the full 10s after a normal, fast reply
  /// already resolved things — harmless in the sense that its callback was
  /// a no-op by then, but it leaked a live platform timer for 10s past
  /// every successful attach, caught by `flutter test`'s
  /// "Timer still pending after widget tree disposed" check.
  Future<T?> _listenOnce<T extends ControlResponse>() async {
    final completer = Completer<T?>();
    late final ProviderSubscription<AsyncValue<ControlResponse>> sub;
    sub = ref.listenManual<AsyncValue<ControlResponse>>(controlResponseProvider, (previous, next) {
      next.whenData((resp) {
        if (resp is T && !completer.isCompleted) {
          completer.complete(resp);
        }
      });
    });
    final timer = Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) completer.complete(null);
    });
    final result = await completer.future;
    timer.cancel();
    sub.close();
    return result;
  }
'''),
    ...para('//', r'The source waits for the attach reply with a ten second bound, so a daemon that crashed mid-attach does not leave a spinner on screen forever. The doc comment tells a story worth reading. A first version used Future.any with a Future.delayed, which does not cancel the losing branch, so a timer stayed alive for ten seconds after every normal reply, and flutter test caught it with its pending timer check once the widget tree was disposed. The replacement uses one Completer and an explicit cancelable Timer.'),
    ...para('//', r'No test in this file lets those ten seconds pass. That branch, the No response from daemon (timed out) message, has no assertion. The tests that do receive an attach reply (tests 3 and 4) would be the ones to trip the pending-timer check at teardown if the timer were not cancelled on a normal reply.'),
    ...sec(r'not covered'),
    ...pt('//', r'the search field and refresh', r'the dialog has a filter field (processPickerSearchField) and a refresh button (processPickerRefresh); neither is exercised.'),
    ...pt('//', r'double taps', r'the source returns early if an attach is already in progress; there is no test that taps twice.'),
    ...pt('//', r'the real thing', r'the header comment is right: whether a hook DLL ends up in the target is something only a manual run against a real daemon can show.'),
  ],
);
