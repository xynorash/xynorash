import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/providers/ws_provider.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'ws_provider.dart — the one WebSocket, and how it survives'),
    cm('//', r'reconnect with backoff, two typed streams, one send path'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'owns the connection to the daemon; decodes frames into messages'),
    kv('language', r'Dart (Riverpod 2.6.1, web_socket_channel 2.4.5)'),
    kv('size', r'275 lines; 4 commits, 2026-07-06 to 2026-07-19'),
    kv('tested by', r'test/providers/ws_provider_test.dart (18 tests)'),
    kv('endpoint', r'ws://127.0.0.1:9999 (a top-level const)'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'Everything the UI knows arrives through this file. The daemon '
        r'listens on a WebSocket, sends a snapshot as soon as a client '
        r'connects, and then pushes diffs, stats and control replies on '
        r'the same connection. The UI must hold that connection, parse '
        r'what comes in, send control requests back, and, the hard '
        r'part, keep working when the daemon is not there yet, goes away, '
        r'or restarts. The user story from the plan’s last task is '
        r'concrete: "Kill and restart the daemon mid-session; confirm the '
        r'app reconnects, receives a fresh snapshot, and shows no ghost '
        r'nodes."'),
    blank,
    ...para('//',
        r'The file is built in layers, from the most testable to the '
        r'least: a pure backoff function, a tiny value type for one '
        r'open connection, a plain class that runs the reconnect loop, '
        r'and only at the bottom the Riverpod providers that tie it to '
        r'the app. Each layer has one reason to exist.'),
    ...sec(r'layer 1: backoff as a pure function'),
    ...code('dart', 'heaplens_flutter/lib/providers/ws_provider.dart · reconnectBackoff', r'''
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
    ...para('//',
        r'The sequence is 500, 1000, 2000, 4000, then 5000 ms forever. '
        r'The test pins each step, the cap at attempts 4, 5 and 100, and '
        r'two hostile inputs: attempt -1 returns 500 ms, and attempt 2^30 '
        r'does not throw. The clamp of the shift at 10 is arithmetic '
        r'hygiene: the cap is reached at attempt 4, so shifts above 10 '
        r'never change the result. The code comment gives the reason '
        r'for the clamp as overflow for "pathologically large attempt '
        r'counts (a client that’s been offline for a long time)".'),
    blank,
    ...para('//',
        r'There is no jitter. For a single local client talking to a '
        r'daemon on 127.0.0.1 that is the right call; the usual reason '
        r'for jitter, many clients retrying in lockstep, does not apply. '
        r'The cap of 5 seconds is the other half of the policy: once '
        r'the delay reaches it, a daemon that comes back is noticed at '
        r'the next retry, at most five seconds later.'),
    ...sec(r'layer 2: a value type that makes the socket fakeable'),
    ...code('dart', 'heaplens_flutter/lib/providers/ws_provider.dart · WsFrames and the real connector (trimmed)', r'''
class WsFrames {
  const WsFrames(this.stream, this.close, [this.send = _noopSend]);

  /// Raw incoming frames (JSON text, per the daemon wire protocol).
  final Stream<dynamic> stream;

  /// Tears down the underlying connection, if any.
  final void Function() close;

  /// Sends a raw outbound text frame (encoded JSON) — Stage 7 §3's control
  /// requests (`ListProcesses`/`AttachTarget`/`DetachTarget`).
  final void Function(String text) send;
}

/// Opens one connection attempt. Called again by [GraphMessageConnection]
/// each time it needs to (re)connect.
typedef WsConnector = WsFrames Function();

/// Default connector: opens a real WebSocket to [kDaemonWsUrl].
WsFrames _connectToDaemon() {
  final channel = WebSocketChannel.connect(Uri.parse(kDaemonWsUrl));
  return WsFrames(
    channel.stream,
    () => channel.sink.close(),
    (text) => channel.sink.add(text),
  );
}'''),
    ...para('//',
        r'WsFrames is three things in one object: a stream of incoming '
        r'text, a way to close, a way to send. It exists so the '
        r'reconnect loop never touches WebSocketChannel directly. A '
        r'test supplies a connector that returns a StreamController’s '
        r'stream and a closure that flips a flag, and the whole loop '
        r'runs with no network. The commit message for a1fc55d says the '
        r'only untested line is "the one-line real '
        r'WebSocketChannel.connect call", and that is still true: '
        r'_connectToDaemon is the one function nothing exercises, except '
        r'indirectly by one test below.'),
    blank,
    ...para('//',
        r'The send slot has a default, _noopSend, with its own story in '
        r'the comment: every call site written before Stage 7 Step 4 '
        r'built a WsFrames from just (stream, close), and a defaulted '
        r'positional parameter kept all of them valid "without a mass '
        r'rewrite". It is a small example of extending a type without '
        r'touching its old users.'),
    ...sec(r'layer 3: the reconnect loop'),
    ...code('dart', 'heaplens_flutter/lib/providers/ws_provider.dart · GraphMessageConnection._connect', r'''
  void _connect() {
    if (_disposed) return;
    onStatus(ConnectionStatus.connecting);

    late WsFrames frames;
    try {
      frames = connector();
    } catch (e, st) {
      onError(e, st);
      _scheduleReconnect();
      return;
    }
    _closeCurrent = frames.close;
    _sendCurrent = frames.send;

    _sub = frames.stream.listen(
      (raw) {
        // Any message, including the very next one after a reconnect,
        // means the connection is healthy again.
        _attempt = 0;
        onStatus(ConnectionStatus.connected);
        try {
          final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
          final type = decoded['type'] as String?;
          if (type != null && ControlResponse.wireTypes.contains(type)) {
            onControlMessage?.call(ControlResponse.fromJson(decoded));
          } else {
            onMessage(GraphMessage.fromJson(decoded));
          }
        } catch (e, st) {
          onError(e, st);
        }
      },
      onError: (Object e, StackTrace st) {
        onError(e, st);
        _scheduleReconnect();
      },
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );
  }'''),
    ...para('//',
        r'Four decisions are packed into this method.'),
    ...pt('//', r'connected means "a frame arrived"',
        r'the status flips to connected on the first message, not when '
        r'the socket opens, and the attempt counter resets at the same '
        r'moment. A socket that opens and delivers nothing is not '
        r'counted as healthy. That is only viable because of the '
        r'daemon’s behaviour: server.rs sends the snapshot immediately '
        r'after accepting a client, so a healthy connection always '
        r'produces a first frame.'),
    ...pt('//', r'two kinds of failure are kept apart',
        r'a frame that fails to parse is reported to onError but does '
        r'not touch the connection, so one bad message cannot cause a '
        r'reconnect storm. A stream error or a stream that ends does '
        r'schedule a reconnect. The test "malformed frame reports an '
        r'error but does not kill the connection" sends the text "not '
        r'json" and then a valid snapshot and expects one error and one '
        r'message.'),
    ...pt('//', r'routing before parsing',
        r'the frame is decoded to a map, its type tag is read, and only '
        r'then does the code choose between ControlResponse and '
        r'GraphMessage. The class comment explains why this is better '
        r'than "try one, fall back to the other": the check is '
        r'"unambiguous by construction". A control frame arriving with '
        r'no handler registered is dropped silently, which a test also '
        r'pins.'),
    ...pt('//', r'cancelOnError: true',
        r'after a stream error the subscription cancels itself, so the '
        r'onDone callback will not also fire. That is what stops a '
        r'single failure from scheduling two reconnects.'),
    blank,
    ...code('dart', 'heaplens_flutter/lib/providers/ws_provider.dart · _scheduleReconnect and sendRequest', r'''
  void _scheduleReconnect() {
    if (_disposed) return;
    _closeCurrent?.call();
    _sendCurrent = null;
    onStatus(ConnectionStatus.disconnected);
    final delay = backoff(_attempt);
    _attempt++;
    _retryTimer = Timer(delay, _connect);
  }
...
  void sendRequest(ControlRequest request) {
    final send = _sendCurrent;
    if (send == null) return;
    send(jsonEncode(request.toJson()));
  }'''),
    ...para('//',
        r'The first line of _scheduleReconnect, _closeCurrent?.call(), '
        r'came from a fix: b2746ec, "close previous connection before '
        r'scheduling reconnect". Before it, a dropped connection was '
        r'abandoned without being closed, which "left socket resources '
        r'in a half-open state, accumulating over long sessions". A '
        r'dedicated test records the order of calls and asserts that '
        r'the close of connection 1 happens before the connector is '
        r'called for connection 2.'),
    blank,
    ...para('//',
        r'sendRequest is the other deliberate simplification: while the '
        r'socket is down, requests are dropped, not queued. The doc '
        r'comment argues that an action taken during a reconnect window '
        r'"has nothing live to reach yet", and that the picker surfaces '
        r'the connection status so this "should be rare in practice, '
        r'not a silent black hole". A test confirms that sending while '
        r'the connector throws returns normally. The cost is that a '
        r'click made in the wrong half-second is lost without an error.'),
    ...sec(r'layer 4: providers over one shared connection'),
    ...code('dart', 'heaplens_flutter/lib/providers/ws_provider.dart · _wsBundleProvider (trimmed)', r'''
final _wsBundleProvider = Provider<_WsBundle>((ref) {
  final graphController = StreamController<GraphMessage>.broadcast();
  final controlController = StreamController<ControlResponse>.broadcast();

  final connection = GraphMessageConnection(
    onStatus: (status) =>
        ref.read(connectionStatusProvider.notifier).state = status,
    onMessage: graphController.add,
    onControlMessage: controlController.add,
    onError: (e, st) {
      graphController.addError(e, st);
      controlController.addError(e, st);
    },
  );
...
  Future.microtask(connection.start);

  ref.onDispose(() {
    connection.dispose();
    graphController.close();
    controlController.close();
  });

  return _WsBundle(connection, graphController, controlController);
});'''),
    ...para('//',
        r'One connection, two broadcast controllers. The comment on '
        r'_WsBundle gives the reason for sharing: independent providers '
        r'would "double the daemon’s connection count per Flutter client '
        r'and the reconnect/backoff state to keep in sync, for no '
        r'benefit". Errors are pushed to both streams, so any consumer '
        r'of either sees a failure as an AsyncValue.error. The verbose '
        r'log panel uses exactly that to print "ERROR (graph stream)".'),
    ...para('//',
        r'Three public providers sit on top: graphMessageProvider and '
        r'controlResponseProvider are StreamProviders over the two '
        r'controllers, wsConnectionProvider exposes the connection '
        r'object so widgets can call sendRequest, and '
        r'connectionStatusProvider (a StateProvider of the enum '
        r'connecting, connected, disconnected) lets the control bar '
        r'show a dot without subscribing to every graph message.'),
    ...sec(r'the bug that only a real run could find'),
    ...code('dart', 'heaplens_flutter/lib/providers/ws_provider.dart · the microtask comment', r'''
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
    ...para('//',
        r'The commit that fixed it, 1179bf1, puts the severity plainly: '
        r'the bug "crashed the app immediately on every real launch". The task '
        r'that found it was the plan’s last one, the live end-to-end run '
        r'against the real daemon (M5 Task 10). Every earlier test '
        r'overrode graphMessageProvider with a fake stream, so the real '
        r'provider body had never executed in a test. The moral is '
        r'written into the commit message: tests that replace the '
        r'boundary cannot catch a bug that lives in the boundary.'),
    blank,
    ...para('//',
        r'The regression test is the interesting artefact. It creates a '
        r'plain ProviderContainer with no overrides, reads the real '
        r'graphMessageProvider, asserts the read does not throw, then '
        r'waits 50 ms so the deferred connection attempt (to a port '
        r'where, as the test comment says, nothing is "almost '
        r'certainly" listening) runs and fails harmlessly. This is the '
        r'one test that touches the real WebSocketChannel.connect line.'),
    ...sec(r'a comment that disagrees with the daemon'),
    ...para('//',
        r'The class comment justifies the retry loop like this: "The '
        r'daemon intentionally disconnects clients that fall behind on '
        r'its broadcast channel (a lag-based disconnect policy — see '
        r'M4)." The M5 plan says the same and cites "M4 Q6". Checking '
        r'the other side does not confirm it. In M4’s plan, decision Q6 '
        r'is "Atomic subscribe+snapshot", and the plan’s own text for '
        r'lag says the daemon should log a warning and treat dropped '
        r'diffs as "acceptable". The shipped crates/heaplens-daemon/src/'
        r'server.rs does exactly that: on RecvError::Lagged it logs '
        r'"lagged by n diffs — some dropped" and carries on, with the '
        r'comment "keep the connection alive, just note the gap". It '
        r'only breaks the loop when the channel is closed or a send '
        r'fails.'),
    blank,
    ...para('//',
        r'What this means: the reconnect machinery is still necessary '
        r'and correct for the cases that do drop the socket (a daemon '
        r'restart, a crash, the launcher shutting down). But the "lagged '
        r'client is disconnected and re-synced by a new snapshot" story '
        r'in the comment is not how the code behaves. A client that '
        r'lags simply misses some diffs and receives no corrective '
        r'snapshot. The paused_provider.dart comment makes the related '
        r'assumption that missed diffs are repaired by "the next '
        r'snapshot (e.g. after a reconnect) or subsequent diffs". Since '
        r'diffs carry whole NodeDto values for add and update, later '
        r'updates repair most gaps, but a missed remove would leave a '
        r'node on screen until the next snapshot. I am reporting this '
        r'as a documentation discrepancy found by reading both sides, '
        r'not as an observed failure.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'ws_provider_test.dart has 18 tests in six groups, all but one '
        r'driven by fakes:'),
    ...pt('//', r'reconnectBackoff (3)',
        r'doubling from 500 ms, the 5 s cap, and no overflow for -1 or '
        r'2^30.'),
    ...pt('//', r'GraphMessageConnection (7)',
        r'connecting then connected and one decoded message; reconnect '
        r'after the stream closes, then self-heal on the next snapshot; '
        r'reconnect after a stream error; the malformed frame; backoff '
        r'receives attempts 0 then 1; close before reconnect; dispose '
        r'stops further reconnects.'),
    ...pt('//', r'control dispatch (4)',
        r'a process_list frame reaches the control callback and not '
        r'the graph one; an attach_result and a snapshot on one stream '
        r'each route correctly; a target_exited push; a control frame '
        r'with no handler is dropped, not errored.'),
    ...pt('//', r'sendRequest (2)',
        r'the exact string {"type":"attach_target","pid":4242} reaches '
        r'the fake send; sending while never connected is a silent no-op.'),
    ...pt('//', r'real provider (1)',
        r'the initialization-order regression described above.'),
    blank,
    ...para('//',
        r'Note the one weak test: "connectionStatusProvider defaults to '
        r'disconnected" asserts only that the enum contains the value '
        r'disconnected. It does not read the provider’s initial state, '
        r'so it does not check what its name says. The default itself '
        r'is visible on the provider definition at the top of the file.'),
    ...sec(r'limits'),
    ...pt('//', r'fixed endpoint',
        r'kDaemonWsUrl is a const. The daemon’s address can be changed '
        r'with the HEAPLENS_WS_ADDR environment variable (config.rs), '
        r'but nothing on the Flutter side reads it, so the two can '
        r'disagree. The comment on the constant says a later task may '
        r'make it configurable.'),
    ...pt('//', r'no queue, no ids',
        r'requests are dropped while disconnected and replies are '
        r'matched by type; see models/control.dart.'),
    ...pt('//', r'status changes at the first frame',
        r'the connecting state can last as long as the daemon takes to '
        r'send a first frame, not just the TCP handshake.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
