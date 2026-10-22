import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/providers/ws_provider_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'ws_provider_test.dart — the one socket that everything depends on'),
    cm('//', r'reconnect, routing, outbound requests and a regression only a live run could find'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'pins the websocket plumbing: backoff, reconnect loop, frame routing, sendRequest, provider init'),
    kv('language', r'Dart, flutter_test; fake connectors and StreamControllers, no real socket except one test'),
    kv('size', r'455 lines, 18 tests in 6 groups'),
    kv('history', r'a1fc55d (2026-07-06) created it; b2746ec and 1179bf1 (2026-07-06) added a test each; 1cfb7f9 (2026-07-19) added control-message dispatch and sendRequest'),
    kv('subject', r'lib/providers/ws_provider.dart'),
    ...sec(r'why the plumbing is a plain class'),
    ...para('//', r'Everything the app shows comes through one websocket to the daemon at ws://127.0.0.1:9999. If that connection misbehaves, the UI is blank and nothing explains why. So the connection logic was written to be testable without a network: GraphMessageConnection is a plain class, not a provider, and it takes a connector function that returns a WsFrames value (a stream of raw frames, a close callback, and since Stage 7 a send callback). The doc comment says this directly: no real socket or real timers required. Almost every test below hands it a StreamController in place of a socket.'),
    ...code('dart', r'heaplens_flutter/lib/providers/ws_provider.dart · WsFrames', r'''
/// A single opened connection's raw frame stream, a way to tear it down, and
/// a way to send an outbound frame. Kept as a small value type (rather than
/// exposing [WebSocketChannel] directly through the reconnect loop) so
/// [GraphMessageConnection] can be unit tested with a fake connector that
/// never touches a real socket.
class WsFrames {
  const WsFrames(this.stream, this.close, [this.send = _noopSend]);

  /// Raw incoming frames (JSON text, per the daemon wire protocol).
  final Stream<dynamic> stream;

  /// Tears down the underlying connection, if any.
  final void Function() close;'''),
    ...sec(r'backoff, as a pure function'),
    ...code('dart', r'heaplens_flutter/test/providers/ws_provider_test.dart · reconnectBackoff', r'''
  group('reconnectBackoff', () {
    test('starts at 500ms and doubles', () {
      expect(reconnectBackoff(0), const Duration(milliseconds: 500));
      expect(reconnectBackoff(1), const Duration(milliseconds: 1000));
      expect(reconnectBackoff(2), const Duration(milliseconds: 2000));
      expect(reconnectBackoff(3), const Duration(milliseconds: 4000));
    });

    test('caps at 5s', () {
      expect(reconnectBackoff(4), const Duration(milliseconds: 5000));
      expect(reconnectBackoff(5), const Duration(milliseconds: 5000));
      expect(reconnectBackoff(100), const Duration(milliseconds: 5000));
    });

    test('does not throw or overflow for negative/huge attempt counts', () {
      expect(reconnectBackoff(-1), const Duration(milliseconds: 500));
      expect(() => reconnectBackoff(1 << 30), returnsNormally);
    });
  });'''),
    ...code('dart', r'heaplens_flutter/lib/providers/ws_provider.dart · the function under test', r'''
/// Computes the delay before reconnect attempt number [attempt] (0-indexed:
/// the first retry after an initial connection failure/drop is attempt 0).
/// Exponential backoff from 500ms, doubling each attempt, capped at 5s.
///
/// Factored out as a pure, dependency-free function so it can be unit
/// tested without touching a socket or a timer.
Duration reconnectBackoff(int attempt) {
  const base = Duration(milliseconds: 500);
  const cap = Duration(milliseconds: 5000);
  // Clamp the shift amount so this can't overflow for pathologically large
  // attempt counts (a client that's been offline for a long time).
  final shift = attempt < 0 ? 0 : (attempt > 10 ? 10 : attempt);
  final scaled = base * (1 << shift);
  return scaled > cap ? cap : scaled;
}'''),
    ...para('//', r'Three tests pin the curve. 500 ms doubling through 1, 2 and 4 seconds; capped at 5 seconds from attempt 4 onwards, including attempt 100; and no exceptions for odd inputs. The last test is the one that justifies the function being factored out. The source clamps the shift to 10 before computing base times 1 shifted left, and the comment says it is there so a client offline for a long time cannot overflow. The test calls reconnectBackoff(1 shl 30) and expects returnsNormally, and a negative attempt gives the base delay of 500 ms. Without the clamp, the shift would grow with the attempt count.'),
    ...sec(r'a fixture with four recording lists'),
    ...code('dart', r'heaplens_flutter/test/providers/ws_provider_test.dart · setUp and buildConnection', r'''
  group('GraphMessageConnection', () {
    late List<ConnectionStatus> statuses;
    late List<GraphMessage> messages;
    late List<Object> errors;
    late List<ControlResponse> controlMessages;

    setUp(() {
      statuses = [];
      messages = [];
      errors = [];
      controlMessages = [];
    });

    GraphMessageConnection buildConnection({
      required WsConnector connector,
      Duration Function(int)? backoff,
    }) {
      return GraphMessageConnection(
        connector: connector,
        backoff: backoff ?? (_) => Duration.zero,
        onStatus: statuses.add,
        onMessage: messages.add,
        onError: (e, st) => errors.add(e),
        onControlMessage: controlMessages.add,
      );
    }'''),
    ...para('//', r'The group records everything the connection reports into four lists: statuses, messages, errors and control messages. buildConnection supplies a zero backoff by default so reconnects happen at the next microtask turn, and tests that care about the backoff pass their own. The onError callback keeps only the error object, not the stack trace.'),
    ...sec(r'the happy path and what connected means'),
    ...code('dart', r'heaplens_flutter/test/providers/ws_provider_test.dart · connecting, then connected', r'''
    test('emits connecting then connected, decodes a message', () async {
      final controller = StreamController<dynamic>();
      var closed = false;
      final connection = buildConnection(
        connector: () => WsFrames(controller.stream, () => closed = true),
      );

      connection.start();
      // connect() runs synchronously up to the listen() call.
      expect(statuses, [ConnectionStatus.connecting]);

      controller.add(_snapshotJson);
      await Future<void>.delayed(Duration.zero);

      expect(statuses, [ConnectionStatus.connecting, ConnectionStatus.connected]);
      expect(messages, hasLength(1));
      expect(messages.single, isA<GraphSnapshot>());

      connection.dispose();
      await controller.close();
      expect(closed, isTrue);
    });'''),
    ...para('//', r'Note the first assertion: right after connection.start() the statuses are just [connecting]. The comment explains why that can be asserted synchronously, connect runs synchronously up to the listen call. Then a snapshot is delivered and the status becomes connected. Look at when: the source sets connected on the first frame received, not when the socket opens. A comment in the listener says why, any message, including the very next one after a reconnect, means the connection is healthy again. The same callback resets the attempt counter to zero, which is the reason the backoff curve starts over after any successful frame.'),
    ...para('//', r'The tail of the test is also an assertion: dispose, close the controller, and closed must be true. Disposing must call the close callback of the current connection, or a real socket would leak.'),
    ...sec(r'reconnecting, twice over'),
    ...code('dart', r'heaplens_flutter/test/providers/ws_provider_test.dart · reconnect after onDone', r'''
    test('reconnects after the stream closes (onDone), self-healing on '
        'the next snapshot', () async {
      final firstController = StreamController<dynamic>();
      final secondController = StreamController<dynamic>();
      var callCount = 0;

      final connection = buildConnection(
        connector: () {
          callCount++;
          final stream = callCount == 1 ? firstController.stream : secondController.stream;
          return WsFrames(stream, () {});
        },
      );

      connection.start();
      expect(callCount, 1);

      // Simulate the daemon dropping this client (lag-based disconnect).
      await firstController.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(callCount, 2);
      expect(
        statuses,
        [
          ConnectionStatus.connecting,
          ConnectionStatus.disconnected,
          ConnectionStatus.connecting,
        ],
      );

      // Fresh snapshot arrives on the new connection — self-healing.
      secondController.add(_snapshotJson);
      await Future<void>.delayed(Duration.zero);
      expect(statuses.last, ConnectionStatus.connected);
      expect(messages, hasLength(1));

      connection.dispose();
      await secondController.close();
    });'''),
    ...para('//', r'The daemon can drop a client, and the comment in the test names the case: a lag-based disconnect. The test closes the first controller, waits two turns of the event loop, and expects the connector to have been called a second time and the status sequence to be exactly connecting, disconnected, connecting. Then a snapshot on the second connection yields connected and exactly one message. The title says self-healing: the doc comment in the source relies on the daemon sending a fresh snapshot to every new client, so a consumer that replaces its state on each snapshot ends up correct after a reconnect.'),
    ...code('dart', r'heaplens_flutter/test/providers/ws_provider_test.dart · reconnect after an error', r'''
    test('reconnects after a stream error, does not terminate', () async {
      final firstController = StreamController<dynamic>();
      final secondController = StreamController<dynamic>();
      var callCount = 0;

      final connection = buildConnection(
        connector: () {
          callCount++;
          final stream = callCount == 1 ? firstController.stream : secondController.stream;
          return WsFrames(stream, () {});
        },
      );

      connection.start();
      firstController.addError(StateError('lagged out'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(callCount, 2);
      expect(errors, hasLength(1));
      expect(statuses, contains(ConnectionStatus.disconnected));

      connection.dispose();
      await firstController.close();
      await secondController.close();
    });'''),
    ...para('//', r'A stream error is a second route to the same place. A StateError named lagged out goes through onError, which reports it and schedules a reconnect. The test expects the error to be reported once, the connector to be called again, and disconnected to appear in the status list. The source subscribes with cancelOnError true, so after one error the subscription is finished, and reconnecting is the only way forward. That is why the title says it does not terminate.'),
    ...code('dart', r'heaplens_flutter/test/providers/ws_provider_test.dart · a malformed frame', r'''
    test('malformed frame reports an error but does not kill the connection', () async {
      final controller = StreamController<dynamic>();
      final connection = buildConnection(
        connector: () => WsFrames(controller.stream, () {}),
      );

      connection.start();
      controller.add(_badJson);
      await Future<void>.delayed(Duration.zero);
      controller.add(_snapshotJson);
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(messages, hasLength(1));

      connection.dispose();
      await controller.close();
    });'''),
    ...para('//', r'The opposite case: a bad frame must not cost the connection. The literal not json goes through jsonDecode inside a try block in the listener, which reports the error and returns. The next valid snapshot arrives on the same connection. The final expectations are one error and one message, and no reconnect is checked or needed. The distinction is deliberate, a transport error ends the connection, a decoding error ends only the frame.'),
    ...sec(r'ordering and counting'),
    ...code('dart', r'heaplens_flutter/test/providers/ws_provider_test.dart · backoff attempts increase', r'''
    test('backoff function receives increasing attempt numbers', () async {
      final controllers = [
        StreamController<dynamic>(),
        StreamController<dynamic>(),
        StreamController<dynamic>(),
      ];
      var callCount = 0;
      final backoffAttempts = <int>[];

      final connection = buildConnection(
        connector: () {
          final stream = controllers[callCount].stream;
          callCount++;
          return WsFrames(stream, () {});
        },
        backoff: (attempt) {
          backoffAttempts.add(attempt);
          return Duration.zero;
        },
      );

      connection.start();
      await controllers[0].close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await controllers[1].close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(backoffAttempts, [0, 1]);

      connection.dispose();
      await controllers[2].close();
    });'''),
    ...para('//', r'A custom backoff function records the attempt numbers it is given, and returns zero. After two drops it must have been called with [0, 1]. This pins that _attempt is incremented in _scheduleReconnect after reading it, and not reset by a drop. The reset only happens when a frame arrives, which no frame did here.'),
    ...code('dart', r'heaplens_flutter/test/providers/ws_provider_test.dart · close before reconnect', r'''
    test('close callback fires before scheduling reconnect', () async {
      final firstController = StreamController<dynamic>();
      final secondController = StreamController<dynamic>();
      var connectorCallCount = 0;
      final closeCallOrder = <String>[];

      final connection = buildConnection(
        connector: () {
          connectorCallCount++;
          closeCallOrder.add('connector_call_$connectorCallCount');
          final stream = connectorCallCount == 1 ? firstController.stream : secondController.stream;
          return WsFrames(
            stream,
            () {
              closeCallOrder.add('close_called_$connectorCallCount');
            },
          );
        },
      );

      connection.start();
      expect(connectorCallCount, 1);
      expect(closeCallOrder, ['connector_call_1']);

      // Trigger reconnect via onDone.
      await firstController.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Verify the order: first connection's close should be called before
      // the second connector is called.
      expect(connectorCallCount, 2);
      expect(
        closeCallOrder,
        [
          'connector_call_1',
          'close_called_1', // First connection closed
          'connector_call_2', // Before second connection opened
        ],
      );

      connection.dispose();
      await secondController.close();
    });'''),
    ...para('//', r'This test came from commit b2746ec, titled close previous connection before scheduling reconnect. It records the order of events in a list: connector call 1, close called 1, connector call 2. The point is resource hygiene. The commit message says that without the explicit close, socket resources were left half-open and accumulated over long sessions. Recording order rather than counts is the only way to test a sequence.'),
    ...code('dart', r'heaplens_flutter/test/providers/ws_provider_test.dart · dispose stops reconnects', r'''
    test('dispose stops further reconnect attempts', () async {
      final controller = StreamController<dynamic>();
      var callCount = 0;

      final connection = buildConnection(
        connector: () {
          callCount++;
          return WsFrames(controller.stream, () {});
        },
      );

      connection.start();
      expect(callCount, 1);
      connection.dispose();
      await controller.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // dispose() must prevent the scheduled reconnect from firing.
      expect(callCount, 1);
    });'''),
    ...para('//', r'After dispose, closing the stream must not cause another connect. Source: _scheduleReconnect and _connect both start with a check of _disposed, and dispose cancels the retry timer. The test has the stream finish after disposing and checks callCount is still 1 after two turns. A reconnect loop that keeps running after the owner is gone is the classic leak in this kind of code.'),
    ...sec(r'one connection, two kinds of message'),
    ...para('//', r'Stage 7 added control responses on the same socket. The listener now checks whether a frame carries one of ControlResponse.wireTypes and, if so, sends it to onControlMessage; anything else goes to onMessage as a GraphMessage. The next group tests the routing from the outside.'),
    ...code('dart', r'heaplens_flutter/test/providers/ws_provider_test.dart · routing', r'''
    test('a process_list frame routes to onControlMessage, not onMessage', () async {
      final controller = StreamController<dynamic>();
      final connection = buildConnection(() => WsFrames(controller.stream, () {}));
      connection.start();

      controller.add(_processListJson);
      await Future<void>.delayed(Duration.zero);

      expect(controlMessages, hasLength(1));
      expect(controlMessages.single, isA<ProcessListResponse>());
      expect(messages, isEmpty);
      expect(errors, isEmpty);

      connection.dispose();
      await controller.close();
    });

    test('an attach_result and a snapshot on the same stream each route correctly', () async {
      final controller = StreamController<dynamic>();
      final connection = buildConnection(() => WsFrames(controller.stream, () {}));
      connection.start();

      controller.add(_attachResultJson);
      controller.add(_snapshotJson);
      await Future<void>.delayed(Duration.zero);

      expect(controlMessages, hasLength(1));
      expect(controlMessages.single, isA<AttachResultResponse>());
      expect(messages, hasLength(1));
      expect(messages.single, isA<GraphSnapshot>());
      expect(errors, isEmpty);

      connection.dispose();
      await controller.close();
    });'''),
    ...para('//', r'A process_list frame must reach onControlMessage and not onMessage, with no errors. The second test sends an attach_result and a snapshot back to back on one stream and expects each to land in its own list. Both are added before a single await, so ordering within a turn is also exercised. The next test sends target_exited and checks the pid through a cast.'),
    ...code('dart', r'heaplens_flutter/test/providers/ws_provider_test.dart · no handler supplied', r'''
    test('a control frame is dropped (not errored) if onControlMessage is not supplied', () async {
      final controller = StreamController<dynamic>();
      final localMessages = <GraphMessage>[];
      final localErrors = <Object>[];
      final connection = GraphMessageConnection(
        connector: () => WsFrames(controller.stream, () {}),
        backoff: (_) => Duration.zero,
        onStatus: (_) {},
        onMessage: localMessages.add,
        onError: (e, st) => localErrors.add(e),
        // onControlMessage intentionally omitted.
      );
      connection.start();

      controller.add(_processListJson);
      await Future<void>.delayed(Duration.zero);

      expect(localErrors, isEmpty, reason: 'a recognized control type with no handler should be a silent no-op, not an error');
      expect(localMessages, isEmpty);

      connection.dispose();
      await controller.close();
    });'''),
    ...para('//', r'onControlMessage is optional in the constructor. If it is omitted, a recognised control frame is dropped silently, and the test requires localErrors to be empty with a reason string: a recognized control type with no handler should be a silent no-op, not an error. Without the null-aware call in the source, the frame would fall to the graph parser and be reported as an unknown type. The constructor having this default is what keeps every pre-Stage-7 call site valid, which the _noopSend comment also says.'),
    ...sec(r'sending'),
    ...code('dart', r'heaplens_flutter/test/providers/ws_provider_test.dart · sendRequest encodes and forwards', r'''
  group('GraphMessageConnection.sendRequest', () {
    test('encodes the request and forwards it to the current connection\'s send function', () async {
      final sent = <String>[];
      final controller = StreamController<dynamic>();
      final connection = GraphMessageConnection(
        connector: () => WsFrames(controller.stream, () {}, sent.add),
        backoff: (_) => Duration.zero,
        onStatus: (_) {},
        onMessage: (_) {},
        onError: (e, st) {},
      );
      connection.start();

      connection.sendRequest(const AttachTargetRequest(4242));

      expect(sent, hasLength(1));
      expect(sent.single, '{"type":"attach_target","pid":4242}');

      connection.dispose();
      await controller.close();
    });'''),
    ...para('//', r'The first outbound test passes a third constructor argument to WsFrames, a send function that appends to a list, and then sends an AttachTargetRequest(4242). The list must hold exactly one string, {"type":"attach_target","pid":4242}. This is the wire format asserted at the string level, the other end of control_test.dart, which checks the map. Key order is part of the assertion, so a change in jsonEncode ordering would show here.'),
    ...code('dart', r'heaplens_flutter/test/providers/ws_provider_test.dart · no-op while disconnected', r'''
    test('is a silent no-op while not connected (no current send function)', () async {
      final connection = GraphMessageConnection(
        connector: () => throw StateError('never connects'),
        backoff: (_) => Duration.zero,
        onStatus: (_) {},
        onMessage: (_) {},
        onError: (e, st) {},
      );
      connection.start(); // connector throws; onError'd internally, no send is ever set.

      expect(() => connection.sendRequest(const DetachTargetRequest()), returnsNormally);

      connection.dispose();
    });'''),
    ...para('//', r'The second test builds a connection whose connector throws, calls start, which catches the error and schedules a reconnect, then calls sendRequest and expects returnsNormally. The doc comment in the source records the decision: while disconnected, requests are dropped, there is no queueing, because a user action during a reconnect window has nothing live to reach. The test cannot show that the user is told; it only shows nothing crashes.'),
    ...sec(r'a test that does not test what it says'),
    ...code('dart', r'heaplens_flutter/test/providers/ws_provider_test.dart · connectionStatusProvider', r'''
  group('connectionStatusProvider', () {
    test('defaults to disconnected', () {
      // Sanity check on the initial value a later task's control bar would
      // see before any connection attempt updates it.
      expect(ConnectionStatus.values, contains(ConnectionStatus.disconnected));
    });
  });'''),
    ...para('//', r'Honest note on this group. The test is called defaults to disconnected, but its body only asserts that the ConnectionStatus enum contains disconnected. It never reads connectionStatusProvider. The provider is declared with ConnectionStatus.disconnected as its initial value (ws_provider.dart line 23), so the claim is likely true, but this test would pass with any initial value. The comment inside admits it is a sanity check.'),
    ...sec(r'the regression that only a live run could find'),
    ...code('dart', r'heaplens_flutter/test/providers/ws_provider_test.dart · the real provider', r'''
  group('graphMessageProvider (real, unoverridden)', () {
    test(
      'initializing the real provider does not throw '
      '"modify other providers during initialization"',
      () async {
        // Regression test for a bug only caught by a live run against the
        // real daemon: GraphMessageConnection.start() used to be called
        // synchronously inside graphMessageProvider's own build function,
        // and its first action is to write ConnectionStatus.connecting into
        // connectionStatusProvider — a second provider — before this
        // provider's build had returned. Riverpod asserts against exactly
        // this ("Providers are not allowed to modify other providers during
        // their initialization"). Every other test in this file/suite
        // overrides graphMessageProvider with a fake stream, so none of them
        // exercise the real provider's build function or would have caught
        // this. Here we deliberately do NOT override it, forcing the real
        // connector to run (against a real-but-almost-certainly-unreachable
        // local port so the test doesn't depend on a live daemon).
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Merely reading the provider triggers its build function. The
        // fix defers connection.start() to a microtask, so this read must
        // not throw synchronously.
        expect(() => container.read(graphMessageProvider), returnsNormally);

        // Let the deferred microtask (and the resulting real connection
        // attempt, which will fail since nothing is listening) run without
        // throwing back into the test.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
    );'''),
    ...para('//', r'The last test is the best commented in the suite, and it is there because of commit 1179bf1. Every other test overrides graphMessageProvider with a fake stream, so none of them ran the real provider’s build function. In a live run against the real daemon, Riverpod threw its rule against modifying other providers during initialization: connection.start() ran synchronously inside the build, and its first act was to write ConnectionStatus.connecting into connectionStatusProvider.'),
    ...code('dart', r'heaplens_flutter/lib/providers/ws_provider.dart · the fix in the provider', r'''
  // Deferred to a microtask: `connection.start()` synchronously calls
  // `onStatus` (writing to `connectionStatusProvider`) before this
  // provider's own build function would otherwise have returned. Riverpod
  // forbids a provider modifying another provider's state while it is
  // still building ("Providers are not allowed to modify other providers
  // during their initialization") and throws in debug mode if this
  // happens — this only surfaces with the real connector (every existing
  // test overrides `graphMessageProvider` with a fake stream, bypassing
  // this code path entirely), so it was only caught by a live run against
  // the real daemon.
  Future.microtask(connection.start);'''),
    ...para('//', r'The fix is one line, Future.microtask(connection.start), with a comment explaining it. The regression test constructs a bare ProviderContainer with no overrides, reads graphMessageProvider inside expect(..., returnsNormally), then waits fifty milliseconds so the microtask and the failing real connection attempt can run without throwing back into the test. It deliberately uses the real port; the comment says it is almost certainly unreachable so the test does not need a live daemon. The assumption that nothing listens on 9999 is a small environmental dependence of the test.'),
    ...sec(r'what to take from it'),
    ...para('//', r'Groups two to four are the specification of a reconnect loop: status transitions, error handling, ordering of close and connect, and disposal. They are written with fake time (zero backoff) and event-loop turns, which makes them fast and deterministic. The last test is the reminder of what fakes cannot do: it exists because the fakes bypassed the real provider, and the bug was only found by running the app (the commit message says it crashed the app on every real launch).'),
  ],
);
