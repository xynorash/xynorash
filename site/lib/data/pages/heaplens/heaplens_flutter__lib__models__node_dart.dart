import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/models/node.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'node.dart — one allocation, as the UI sees it'),
    cm('//', r'a hand-written mirror of the daemon’s NodeDto'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'the wire model for a single node, plus its lifecycle enum'),
    kv('language', r'Dart'),
    kv('size', r'72 lines; one commit (3e09188, 2026-07-06)'),
    kv('mirrors', r'crates/heaplens-protocol/src/diff.rs (NodeState, NodeDto)'),
    kv('pinned by', r'test/models/contract_test.dart'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'The Flutter app and the Rust daemon share exactly one data '
        r'contract: JSON over a WebSocket. The Build Spec calls it the '
        r'second seam, defined once in diff.rs and "mirrored as Dart '
        r'models". This file is that mirror for the smallest unit, a '
        r'single node. Every pixel in the graph canvas, every cell of '
        r'the memory map, and every line in the node-detail panel starts '
        r'life as one of these objects.'),
    blank,
    ...para('//',
        r'The file does one thing: turn a decoded JSON map into an '
        r'immutable Dart object, with no logic of its own. The rule it '
        r'obeys is stated in the doc comment on the class: field names '
        r'"mirror heaplens_protocol::diff::NodeDto verbatim — this is '
        r'the wire contract".'),
    ...sec(r'the lifecycle enum, and a forgiving parser'),
    ...code('dart', 'heaplens_flutter/lib/models/node.dart · NodeStateDto', r'''
/// Node lifecycle state. Mirrors `heaplens_protocol::diff::NodeState`, which
/// serializes as lowercase: "healthy" | "orphan" | "hot" | "freed".
enum NodeStateDto {
  healthy,
  orphan,
  hot,
  freed;

  /// Maps a wire string to a [NodeStateDto]. Falls back to [healthy] (with
  /// a debug-mode warning) for any string not in the known set, so that
  /// forward-compatible additions to the wire enum don't crash the client.
  static NodeStateDto fromWire(String s) {
    switch (s) {
      case 'healthy':
        return NodeStateDto.healthy;
...
      default:
        debugPrint('NodeStateDto.fromWire: unknown state "$s", defaulting to healthy');
        return NodeStateDto.healthy;
    }
  }
}'''),
    ...para('//',
        r'The four values are the four colours of the UI. In node_colors.dart '
        r'healthy is teal, orphan is coral, hot is amber-orange and freed '
        r'is grey. Orphan is the headline state, a live allocation whose '
        r'owner has been freed, in other words a probable leak.'),
    blank,
    ...para('//',
        r'The interesting decision is the default branch. A strict parser '
        r'would throw on an unknown string. This one logs and answers '
        r'healthy. The M5 plan locks this as decision Q2: "unknown state '
        r'strings map to healthy with a debug log (lenient, '
        r'forward-compatible — matches diff.rs’s lenient-deserialization '
        r'comment)". Rust says the same thing from the other side: the '
        r'diff.rs doc comment says lenient deserialization is deliberate, '
        r'so that additions to NodeDto must not break older '
        r'deserializers. The design is a pair of forgiving ends.'),
    blank,
    ...para('//',
        r'The cost is honest to state. A state the UI does not know is '
        r'drawn as a teal, healthy node, which is the one colour that '
        r'claims nothing is wrong. The code accepts that for the sake of '
        r'not crashing, and two tests lock the behaviour so it cannot '
        r'change by accident: contract_test.dart checks '
        r'fromWire(’bogus’) and graph_provider_test.dart pushes a node '
        r'with "some_future_state" through the whole provider.'),
    ...sec(r'the node itself'),
    ...code('dart', 'heaplens_flutter/lib/models/node.dart · NodeDto', r'''
@immutable
class NodeDto {
  final int id;
  final int ptr;
  final int size;
  final int ts;
  final String symbol;
  final bool live;
  final NodeStateDto state;
  final List<int> edges;
...
  factory NodeDto.fromJson(Map<String, dynamic> json) {
    return NodeDto(
      id: json['id'] as int,
      ptr: json['ptr'] as int,
      size: json['size'] as int,
      ts: json['ts'] as int,
      symbol: json['symbol'] as String,
      live: json['live'] as bool,
      state: NodeStateDto.fromWire(json['state'] as String),
      edges: (json['edges'] as List<dynamic>).cast<int>(),
    );
  }
}'''),
    ...pt('//', r'id',
        r'the daemon’s identifier for the node. Edges and removals refer '
        r'to nodes by this number, never by pointer. The provider keeps '
        r'a Map keyed by it.'),
    ...pt('//', r'ptr',
        r'the allocation address. The memory map sorts by it and the '
        r'detail panel prints it in hex (0x…).'),
    ...pt('//', r'size, ts',
        r'bytes, and a producer-side timestamp. The UI never treats ts '
        r'as wall-clock time. node_detail.dart derives "age" by '
        r'subtracting from a rolling maximum of ts values it has seen, '
        r'the same idea as the daemon’s own max_ts_seen.'),
    ...pt('//', r'symbol',
        r'the resolved call site of the node. In the captured fixtures '
        r'every node carries the hex string 0x7ff74ba66230, meaning the '
        r'producer used for the capture had no usable symbol names; see '
        r'the PROVENANCE page. That hex-fallback situation is exactly '
        r'what target_diagnosis.dart exists to explain.'),
    ...pt('//', r'live',
        r'whether the allocation still exists. Almost every derived '
        r'metric filters on it.'),
    ...pt('//', r'edges',
        r'ids of the nodes this one owns. Ownership is a direction: the '
        r'owner lists its children. The UI derives the owner of a node '
        r'by searching for the one node whose edges contain it, in '
        r'ForceLayout._findOwnerId and in NodeDetail.'),
    ...sec(r'64-bit integers, and why this app is never a web app'),
    ...para('//',
        r'In Rust, id, ptr, size and ts are u64. They go out as bare '
        r'JSON numbers. The doc comment on the Dart class spells out the '
        r'consequence: it is "safe on the Dart VM (64-bit int) but NOT '
        r'safe under dart2js/Flutter web (double, max 2^53)". The '
        r'project resolved this by constraint rather than by code. The '
        r'plan’s decision Q1 says the target is the Dart VM on Windows '
        r'desktop, "never Flutter web", and the scaffold commit '
        r'(56d5e41) created the project with --platforms=windows only. '
        r'diff.rs records the escape route if that ever changes: '
        r'ptr, id and ts would have to become JSON strings.'),
    blank,
    ...para('//',
        r'Because this is the kind of mistake that is invisible until a '
        r'large address arrives, commit 65f1c0b added a synthetic test. '
        r'It feeds NodeDto.fromJson the value 9007199254740993, which is '
        r'2^53 + 1, the smallest integer an IEEE-754 double cannot '
        r'represent, and 9223372036854775807, and asserts the values '
        r'come out exactly. The test comment explains what it catches: a '
        r'cast that "accidentally rounds through double '
        r'representation". The real fixtures stay far below such values; '
        r'the largest ptr in the captured set is around 2.5 trillion, '
        r'which a double would represent exactly. The synthetic test '
        r'exists for the day that stops being true.'),
    ...para('//',
        r'One boundary is visible in that test: the largest value it '
        r'uses is the signed 64-bit maximum. Dart’s int is signed, so a '
        r'Rust u64 above 2^63 - 1 is outside what this model can '
        r'represent. User-mode addresses on 64-bit Windows are well '
        r'below that, so it does not matter in practice, but the model '
        r'does not defend against it.'),
    ...sec(r'what the parser does when the JSON is wrong'),
    ...para('//',
        r'The factory uses plain as casts. A missing field, or one of '
        r'the wrong type, throws at that line. There is no per-field '
        r'default. That is deliberate and safe because the one caller, '
        r'GraphMessageConnection in ws_provider.dart, wraps every parse '
        r'in a try/catch and reports a failure to onError without '
        r'closing the socket. A test there sends the literal text "not '
        r'json" and asserts that exactly one error is reported and the '
        r'next valid snapshot is still delivered.'),
    blank,
    ...para('//',
        r'A detail worth knowing: edges is built with cast<int>(). In '
        r'Dart, List.cast returns a lazily checked view, so a non-integer '
        r'element would raise when it is read, not when the node is '
        r'parsed. The wire format makes this a theoretical concern, but '
        r'the error would surface far from the parser if it ever '
        r'happened.'),
    ...para('//',
        r'NodeDto is @immutable with a const constructor and defines no '
        r'== or hashCode, so two nodes with the same field values are '
        r'not equal. Nothing in the app relies on that: the provider '
        r'compares ids, the sparkline compares sizes, and tests assert '
        r'on fields.'),
    ...sec(r'how it is tested'),
    ...pt('//', r'contract_test.dart',
        r'parses four real captured payloads and checks fields: a '
        r'101-node snapshot (first node id 571, ptr 1599777467168, size '
        r'256, edges [572]), a 101-add diff, a 101-remove diff, and a '
        r'one-node orphan update. The plan sets the rule for these '
        r'tests: if a fixture fails to parse, "that is a protocol bug — '
        r'do not adapt the model to accommodate it".'),
    ...pt('//', r'the 64-bit test',
        r'the synthetic test above.'),
    ...pt('//', r'graph_provider_test.dart',
        r'checks that the lenient fallback survives a trip through the '
        r'provider.'),
    ...sec(r'limits and what is next'),
    ...pt('//', r'no toJson',
        r'the app only receives nodes; it never sends one, so there is '
        r'no serializer to keep in sync.'),
    ...pt('//', r'no schema version',
        r'compatibility rests on both ends ignoring what they do not '
        r'know. A rename of a field would be a silent break until the '
        r'contract test is rerun against a new capture.'),
    ...pt('//', r'the unknown-state default is optimistic',
        r'it errs toward "everything is fine", which is a trade-off '
        r'chosen for robustness rather than a neutral choice.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
