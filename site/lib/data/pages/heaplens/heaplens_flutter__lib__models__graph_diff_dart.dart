import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/models/graph_diff.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'graph_diff.dart — the three messages the daemon sends'),
    cm('//', r'a sealed union: snapshot, diff, stats'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'the message-level wire model (daemon to Flutter)'),
    kv('language', r'Dart 3 (sealed and final classes, no codegen)'),
    kv('size', r'111 lines; 2 commits, 2026-07-06 and 2026-07-17'),
    kv('mirrors', r'GraphMessage in crates/heaplens-protocol/src/diff.rs'),
    kv('pinned by', r'test/models/contract_test.dart'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'node.dart models one allocation. This file models the envelope '
        r'it travels in. The daemon pushes JSON text frames over a '
        r'WebSocket, and each frame is one of three things: the whole '
        r'graph (snapshot), a change set against the previous state '
        r'(diff), or a periodic counter report (stats). The Rust side '
        r'calls this a "discriminated union" and tags it inline with a '
        r'"type" field. This file is the Dart half of that union.'),
    ...sec(r'a sealed class instead of freezed'),
    ...code('dart', 'heaplens_flutter/lib/models/graph_diff.dart · GraphMessage', r'''
/// Discriminated union for the two daemon->Flutter message shapes, mirroring
/// `heaplens_protocol::diff::GraphMessage` (see diff.rs). Wire messages are
/// tagged with an inline `"type"` field: "snapshot" or "diff".
///
/// Implemented as a Dart 3 `sealed` class with two subclasses rather than
/// `freezed` (forbidden for this project) — callers get exhaustive-switch
/// checking via `switch (message) { GraphSnapshot s => ..., GraphDiff d => ... }`.
@immutable
sealed class GraphMessage {
  final int ts;

  const GraphMessage({required this.ts});

  /// Parses a decoded JSON map, dispatching on `json['type']`.
  factory GraphMessage.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'snapshot':
        return GraphSnapshot.fromJson(json);
      case 'diff':
        return GraphDiff.fromJson(json);
      case 'stats':
        return GraphStats.fromJson(json);
      default:
        throw FormatException('GraphMessage.fromJson: unknown type "$type"');
    }
  }
}'''),
    ...para('//',
        r'Two things in that excerpt tell a small story. The doc comment '
        r'still says "two message shapes" and "two subclasses", while the '
        r'code has three: the stats case was added later and the prose '
        r'above it was not updated. The behaviour is correct and the '
        r'switch is exhaustive; only the comment lags. The other is the '
        r'phrase "forbidden for this project". The Build Spec offers '
        r'freezed plus json_serializable as one option ("or hand-written '
        r'fromJson"), and the M5 plan locked the second: "No freezed, '
        r'json_serializable, or build_runner anywhere". The payoff of '
        r'that choice is a build with no generated files and no '
        r'build_runner step, at the cost of writing four fromJson '
        r'methods by hand and keeping them honest with a contract test.'),
    blank,
    ...para('//',
        r'The sealed keyword is what gives the exhaustive switch. Dart '
        r'knows every direct subclass of a sealed class lives in this '
        r'library, so a switch over a GraphMessage that omits a case is '
        r'a compile error. This matters more than it looks. The Build '
        r'Spec records, in its cross-cutting rules, that adding a '
        r'variant to GraphMessage "has silently broken a real test three '
        r'times" on the Rust side, because an older wildcard arm quietly '
        r'swallowed the new case. In Dart the compiler does the audit: '
        r'when GraphStats arrived, the code that switches over messages '
        r'(graph_provider.dart, main.dart, right_rail.dart and '
        r'debug_overlay.dart) each needed an explicit arm, and the '
        r'cd348b6 merge fix shows the analyzer catching exactly that in '
        r'right_rail.dart.'),
    ...sec(r'snapshot and diff'),
    ...code('dart', 'heaplens_flutter/lib/models/graph_diff.dart · GraphSnapshot and GraphDiff (trimmed)', r'''
/// Full-state message: `{ "type": "snapshot", "ts": ..., "nodes": [...] }`.
final class GraphSnapshot extends GraphMessage {
  final List<NodeDto> nodes;
...
/// Incremental update: `{ "type": "diff", "ts": ..., "add": [...], "update": [...], "remove": [...] }`.
/// `add`/`update` are full `NodeDto`s; `remove` is a list of node ids.
final class GraphDiff extends GraphMessage {
  final List<NodeDto> add;
  final List<NodeDto> update;
  final List<int> remove;
...
  factory GraphDiff.fromJson(Map<String, dynamic> json) {
    return GraphDiff(
      ts: json['ts'] as int,
      add: (json['add'] as List<dynamic>)
          .map((n) => NodeDto.fromJson(n as Map<String, dynamic>))
          .toList(),
      update: (json['update'] as List<dynamic>)
          .map((n) => NodeDto.fromJson(n as Map<String, dynamic>))
          .toList(),
      remove: (json['remove'] as List<dynamic>).cast<int>(),
    );
  }
}'''),
    ...para('//',
        r'The protocol is snapshot-then-diff. On connect the daemon sends '
        r'one snapshot, then diffs. The M4 plan locks how: the snapshot '
        r'and the subscription to the diff stream are produced in the '
        r'same turn of the graph task (decision Q6, "Atomic '
        r'subscribe+snapshot"), so no change can slip between them. '
        r'Everything in this file leans on that guarantee. A diff carries '
        r'whole NodeDto values for add and update, and only ids for '
        r'remove, which is why GraphDiff.remove is a List<int> while the '
        r'other two are lists of nodes.'),
    blank,
    ...para('//',
        r'What the consumers do with the three lists is a contract the '
        r'type does not express, so tests pin it. In '
        r'graph_provider_test.dart, update for an id the client has '
        r'never seen is an upsert, not a no-op ("add/update are both '
        r'upsert by id"), and a remove for an unknown id is silently '
        r'ignored. A snapshot clears the map before filling it, so a '
        r'reconnect cannot leave ghosts. The plan’s final live check '
        r'was to kill and restart the daemon mid-session and confirm '
        r'"no ghost nodes".'),
    blank,
    ...para('//',
        r'Every message carries ts, hoisted into the base class. In the '
        r'captured fixtures it is of the same order as the node '
        r'timestamps (the snapshot and the add diff both carry 329700, '
        r'while the largest node ts in the snapshot is 270900). A search '
        r'of lib/ finds no code that reads message.ts for ordering or '
        r'logic.'),
    ...sec(r'stats: a third message for honesty'),
    ...code('dart', 'heaplens_flutter/lib/models/graph_diff.dart · GraphStats', r'''
/// Observability message: `{ "type": "stats", "ts": ..., "events_received":
/// ..., "symbols_resolved": ..., "hex_fallback": ..., "target_pid": ...,
/// "target_name": ... }`. Never affects phi/detection on the daemon side —
/// purely a periodic counter snapshot consumed by the target-diagnostics
/// banner (see `providers/target_diagnostics_provider.dart`). `targetPid`/
/// `targetName` are null until the daemon has received a HANDSHAKE frame
/// from the attached target.
final class GraphStats extends GraphMessage {
  final int eventsReceived;
  final int symbolsResolved;
  final int hexFallback;
  final int? targetPid;
  final String? targetName;
...
  factory GraphStats.fromJson(Map<String, dynamic> json) {
    return GraphStats(
      ts: json['ts'] as int,
      eventsReceived: json['events_received'] as int,
      symbolsResolved: json['symbols_resolved'] as int,
      hexFallback: json['hex_fallback'] as int,
      targetPid: json['target_pid'] as int?,
      targetName: json['target_name'] as String?,
    );
  }
}'''),
    ...para('//',
        r'GraphStats arrived with commit 0edc728 (2026-07-17), titled '
        r'"honest target-status banner + daemon observability counters". '
        r'The problem it solves is a blank graph that could mean four '
        r'different things: nothing is happening in the target, the '
        r'target uses a heap path HeapLens does not hook, the target has '
        r'no usable symbols, or ownership simply did not form. The daemon '
        r'now broadcasts counters about once a second (STATS_INTERVAL is '
        r'1000 ms in the daemon’s main.rs): events received, symbols '
        r'resolved, and how many fell back to a hex address. The commit '
        r'is careful about scope: the counters are "observability-only, '
        r'no phi/detection changes", and the daemon’s existing test '
        r'suite passed unchanged. The consumer is '
        r'models/target_diagnosis.dart, which turns the counters into a '
        r'plain-language banner.'),
    blank,
    ...para('//',
        r'The two nullable fields use the wire form of Rust Option, '
        r'which is JSON null. They stay null until the target’s '
        r'handshake frame has been seen, so the banner can say "Attached" '
        r'before it knows the process name. contract_test.dart covers '
        r'both states: a stats message with null pid and name, and one '
        r'with pid 4242 and name target.exe.'),
    ...sec(r'what is deliberately not here'),
    ...pt('//', r'no ordering or sequence number',
        r'a client that misses a frame cannot detect it. Whether that '
        r'can happen is a question about the daemon, not this file: its '
        r'server.rs logs a warning and carries on when a client lags '
        r'behind the broadcast channel (the M4 plan calls dropped diffs '
        r'"acceptable"). The Dart side contains a comment saying the '
        r'daemon disconnects lagged clients, which is not what the '
        r'server code does; see the ws_provider.dart page for that '
        r'discrepancy.'),
    ...pt('//', r'no unknown-type tolerance',
        r'an unknown "type" throws FormatException. That is the strict '
        r'half of the design, and it is reported through onError by the '
        r'connection rather than crashing. Only ControlResponse has a '
        r'unit test for the unknown-type case.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'contract_test.dart parses the real captured payloads through '
        r'GraphMessage.fromJson and checks the runtime types: a '
        r'GraphSnapshot with ts 329700 and 101 nodes, a GraphDiff with '
        r'101 adds, a GraphDiff whose 101 removed ids are all ints '
        r'starting at 405, and a GraphDiff with a single update to an '
        r'orphan. The stats cases are hand-written maps, not captures. '
        r'graph_provider_test.dart separately checks that a GraphStats '
        r'handed to applyDiff changes neither the node map nor the '
        r'revision.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
