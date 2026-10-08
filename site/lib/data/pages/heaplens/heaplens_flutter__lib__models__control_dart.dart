import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/models/control.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'control.dart — the UI talks back to the daemon'),
    cm('//', r'three requests, four responses, one shared socket'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'models for the attach/detach control channel (Stage 7)'),
    kv('language', r'Dart 3 (sealed classes, hand-written JSON)'),
    kv('size', r'146 lines; one commit (1cfb7f9, 2026-07-19); 12 tests'),
    kv('mirrors', r'crates/heaplens-protocol/src/control.rs'),
    kv('pinned by', r'test/models/control_test.dart, test/providers/ws_provider_test.dart'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'For its first two weeks the Flutter app only listened. The '
        r'daemon pushed graph messages and the UI drew them. Stage 7 of '
        r'the project added process attachment: instead of only watching '
        r'programs that were built with the HeapLens allocator, the user '
        r'can pick a running Windows process and have a hook DLL '
        r'injected into it. Choosing the process is a UI action, so for '
        r'the first time the UI has to send something to the daemon.'),
    blank,
    ...para('//',
        r'The design document (docs/stage7-injection-design.md, section '
        r'3.1) explains where that code should live. A process picker in '
        r'the launcher would mean "building a second, separate UI '
        r'toolkit inside a component designed to be invisible"; the '
        r'Flutter app already has UI and already holds the WebSocket to '
        r'the daemon. And the enumeration of processes belongs in the '
        r'daemon, not in Flutter, "because it’s already the process with '
        r'Win32 access; Flutter stays a pure UI/rendering layer". The '
        r'result is a small, additive protocol on the existing '
        r'connection, "not a new transport, not a new protocol". This '
        r'file is the Dart model of it.'),
    ...sec(r'process info, and an honest third architecture'),
    ...code('dart', 'heaplens_flutter/lib/models/control.dart · ProcessInfo', r'''
class ProcessInfo {
  final int pid;
  final String name;
  /// "x64", "x86", or "unknown" — the daemon reports "unknown" rather than
  /// dropping a process it couldn't query the architecture of (protected/
  /// elevated processes). Callers should treat "unknown" as not-attachable,
  /// same as "x86" — only "x64" is known-safe on this 64-bit build.
  final String arch;
...
  factory ProcessInfo.fromJson(Map<String, dynamic> json) {
    return ProcessInfo(
      pid: json['pid'] as int,
      name: json['name'] as String,
      arch: json['arch'] as String,
    );
  }
}'''),
    ...para('//',
        r'The arch field is a string, not an enum, and it has three '
        r'values rather than two. The Rust doc comment in control.rs '
        r'gives the reason: OpenProcess can fail for protected or '
        r'elevated processes the daemon has no rights to query, and '
        r'"unknown" is reported rather than dropping the process from '
        r'the list. That choice is user-facing. A process that cannot be '
        r'inspected still shows up in the picker, greyed out, instead of '
        r'vanishing and leaving the user wondering whether HeapLens saw '
        r'it. The rule this file records for callers is conservative: '
        r'only "x64" is attachable. The picker implements it with the '
        r'check arch == ’x64’ in two places.'),
    ...sec(r'requests: each variant knows how to serialise itself'),
    ...code('dart', 'heaplens_flutter/lib/models/control.dart · ControlRequest', r'''
sealed class ControlRequest {
  const ControlRequest();

  Map<String, dynamic> toJson();
}

final class ListProcessesRequest extends ControlRequest {
  const ListProcessesRequest();

  @override
  Map<String, dynamic> toJson() => {'type': 'list_processes'};
}

final class AttachTargetRequest extends ControlRequest {
  final int pid;

  const AttachTargetRequest(this.pid);

  @override
  Map<String, dynamic> toJson() => {'type': 'attach_target', 'pid': pid};
}

final class DetachTargetRequest extends ControlRequest {
  const DetachTargetRequest();

  @override
  Map<String, dynamic> toJson() => {'type': 'detach_target'};
}'''),
    ...para('//',
        r'Compare this with graph_diff.dart. The inbound graph '
        r'messages only ever need fromJson, so they have no toJson. '
        r'These outbound requests only ever need toJson, so they have '
        r'no fromJson. Each direction of the wire is modelled once, in '
        r'the direction it is used. The Rust enum behind them is '
        r'#[serde(tag = "type", rename_all = "snake_case")], and the '
        r'string literals above are the snake_case forms of ListProcesses, '
        r'AttachTarget and DetachTarget. (The graph messages, by '
        r'contrast, use lowercase tags: snapshot, diff, stats.)'),
    blank,
    ...para('//',
        r'The exact bytes matter, so tests check them. '
        r'control_test.dart compares the maps, and ws_provider_test.dart '
        r'goes one step further and compares the encoded string that '
        r'leaves the socket: {"type":"attach_target","pid":4242}. '
        r'process_picker_dialog_test.dart does the same for the pair of '
        r'frames the picker sends, {"type":"list_processes"} then '
        r'{"type":"attach_target","pid":111}.'),
    ...sec(r'responses, and the question of what a frame is'),
    ...code('dart', 'heaplens_flutter/lib/models/control.dart · ControlResponse', r'''
sealed class ControlResponse {
  const ControlResponse();

  /// Parses a decoded JSON map, dispatching on `json['type']`.
  factory ControlResponse.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'process_list':
        return ProcessListResponse.fromJson(json);
      case 'attach_result':
        return AttachResultResponse.fromJson(json);
      case 'detach_result':
        return DetachResultResponse.fromJson(json);
      case 'target_exited':
        return TargetExitedResponse.fromJson(json);
      default:
        throw FormatException('ControlResponse.fromJson: unknown type "$type"');
    }
  }

  /// The wire `"type"` tag values this class recognizes — used by the WS
  /// layer to decide whether an incoming frame is a [ControlResponse]
  /// (route here) or a `GraphMessage` (route there) before attempting to
  /// parse it as either, since both shapes share one connection.
  static const List<String> wireTypes = [
    'process_list',
    'attach_result',
    'detach_result',
    'target_exited',
  ];
}'''),
    ...para('//',
        r'The four responses fall into two groups, and the doc comment on '
        r'the class says so. ProcessList, AttachResult and DetachResult '
        r'are replies to a specific request. TargetExited is different in '
        r'kind: an unprompted push, broadcast the moment the daemon sees '
        r'the attached process exit, "the control-channel counterpart to '
        r'how graph diffs are pushed, not polled". The design document '
        r'(section 4.4) gives the motivation: show "target process '
        r'exited" rather than silently sitting on a stale graph. The '
        r'ControlBar turns that push into a snackbar, and '
        r'AttachedTargetNotifier clears its state.'),
    blank,
    ...para('//',
        r'The wireTypes list exists because of a routing problem. '
        r'Graph messages and control responses arrive on the same '
        r'WebSocket, and a frame is just text. The first version of the '
        r'dispatch idea would have been "try to parse it as a '
        r'GraphMessage, and if that throws, try ControlResponse". The '
        r'ws_provider.dart comment rejects that: checking the tag '
        r'against this list first "is unambiguous by construction, unlike '
        r'a try-GraphMessage-then-fall-back approach, which would work '
        r'today only by accident". The price is that the list must be '
        r'kept in step with the switch above. Two tests guard it: the '
        r'list must have exactly four entries and contain the four tags, '
        r'and it must not contain "snapshot" or "diff", described in the '
        r'test as a regression guard against misrouting graph messages '
        r'to the control parser.'),
    ...sec(r'a protocol without request ids'),
    ...para('//',
        r'None of the requests carries a correlation id, and none of '
        r'the replies echoes one. A reply is matched to its request by '
        r'type alone: the picker waits for "the next AttachResult". '
        r'The daemon makes that safe across clients, because server.rs '
        r'sends each reply on the requesting client’s own connection; '
        r'only TargetExited is broadcast. Within one client it is safe '
        r'because the dialog refuses to start a second attach while one '
        r'is in flight (the _attaching flag). It would stop being safe '
        r'if two requests of the same type were ever outstanding on one '
        r'connection, because nothing could tell their replies apart. '
        r'The design document commits to a single attached target at a '
        r'time, which is why this is tolerable.'),
    blank,
    ...para('//',
        r'Another consequence of the strict parser: an unknown response '
        r'type throws FormatException. control_test.dart pins that with '
        r'something_new, under a test name that says it throws "rather '
        r'than silently misparsing". As with graph messages, the throw '
        r'is caught by the connection layer and reported, not fatal.'),
    ...sec(r'what changed over time'),
    ...para('//',
        r'The file arrived complete in 1cfb7f9 (2026-07-19), the large '
        r'UI-refresh commit that also introduced the process picker, '
        r'the target provider and the right rail. The daemon half was '
        r'ported the same day (commit 724695a, "port Stage 7 control '
        r'protocol from feat/stage7-injection"). It has not been '
        r'modified since, while the behaviour around it flipped four '
        r'times: the Attach button was disabled on 2026-07-21 because '
        r'of a hook crash, re-enabled on 2026-07-22, gated again on '
        r'2026-07-26 and re-enabled on 2026-07-28. The models were '
        r'unaffected because the gate is a UI constant, not part of the '
        r'protocol; see widgets/control_bar.dart.'),
    ...sec(r'how it is tested'),
    ...pt('//', r'control_test.dart',
        r'12 tests: ProcessInfo parsing; the three requests’ toJson '
        r'output; each of the four responses including a failed attach '
        r'whose message is carried "verbatim" (the sample text is "cannot '
        r'open process 999999999 — access denied, or the process does not '
        r'exist."); the unknown-type throw; the wireTypes guard.'),
    ...pt('//', r'ws_provider_test.dart',
        r'routes a process_list, an attach_result and a target_exited '
        r'frame to the control callback and a snapshot to the graph '
        r'callback, and checks that a control frame is dropped, not '
        r'errored, when no handler is supplied.'),
    ...sec(r'limits'),
    ...pt('//', r'no request ids',
        r'see above. A reply cannot be tied to a specific request.'),
    ...pt('//', r'strings where enums could be',
        r'arch is compared as a string literal; a fourth architecture '
        r'value would fall into the "not attachable" side by default, '
        r'which is the safe direction.'),
    ...pt('//', r'u32 on the Rust side',
        r'pid is a u32 in control.rs and an int here, which is exact.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
