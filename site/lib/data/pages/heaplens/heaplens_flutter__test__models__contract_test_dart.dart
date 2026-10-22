import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/models/contract_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'contract_test.dart — real bytes from the daemon, parsed by the real models'),
    cm('//', r'the Dart side of the wire contract, pinned against captured fixtures'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'proves the Dart models read exactly what the Rust daemon writes'),
    kv('language', r'Dart, flutter_test unit tests'),
    kv('size', r'169 lines, 10 tests in 7 groups'),
    kv('history', r'3e09188 (2026-07-06) created it; 65f1c0b (2026-07-06) added the 64-bit test; 0edc728 (2026-07-17) added the GraphStats groups'),
    kv('fixtures', r'test/fixtures/{snapshot,diff_add,diff_remove,diff_orphan}.json + PROVENANCE.md'),
    kv('wire source', r'crates/heaplens-protocol/src/diff.rs'),
    ...sec(r'why a contract test, and why fixtures'),
    ...para('//', r'The daemon is Rust and the UI is Dart, and the only thing joining them is JSON over a websocket. Nothing in either compiler checks that the two agree. If the daemon renames a field, or the Dart model casts it to the wrong type, the failure shows up at runtime, on a user machine, as a blank graph. A contract test is the cheap answer: take real messages from the real daemon, feed them to the real model code, and assert on specific fields.'),
    blank,
    ...para('//', r'The important word is real. An earlier commit (9ac04cd) wrote a build plan and captured fixtures from a live heaplens-daemon session, then 3e09188 wrote the models and this test on top of them. PROVENANCE.md next to the fixtures records how: daemon built from master at 3b6b4a2, a small throwaway Dart websocket client connected to ws://127.0.0.1:9999 while allocation traffic ran in another process. The numbers asserted below (101 nodes, ts 329700, node 571 at pointer 1599777467168) are therefore not made up; they are what came off the wire.'),
    ...sec(r'the fixture loader'),
    ...code('dart', r'heaplens_flutter/test/models/contract_test.dart · loadFixture', r'''
Map<String, dynamic> loadFixture(String name) {
  final raw = File('test/fixtures/$name').readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}'''),
    ...para('//', r'Three lines, and one quiet constraint: the path test/fixtures/ is relative, so flutter test must be run from the heaplens_flutter directory. Reading synchronously is fine in a test and keeps the group bodies simple, because each group parses its fixture once at the top of the group rather than inside every test.'),
    ...sec(r'the enum, and the choice to be lenient'),
    ...code('dart', r'heaplens_flutter/test/models/contract_test.dart · NodeStateDto.fromWire', r'''
  group('NodeStateDto.fromWire', () {
    test('maps all four known wire strings', () {
      expect(NodeStateDto.fromWire('healthy'), NodeStateDto.healthy);
      expect(NodeStateDto.fromWire('orphan'), NodeStateDto.orphan);
      expect(NodeStateDto.fromWire('hot'), NodeStateDto.hot);
      expect(NodeStateDto.fromWire('freed'), NodeStateDto.freed);
    });

    test('falls back to healthy for unknown strings', () {
      expect(NodeStateDto.fromWire('bogus'), NodeStateDto.healthy);
    });
  });'''),
    ...para('//', r'The first group pins two opposite behaviours. The four strings the daemon can send (healthy, orphan, hot, freed) each map to their enum value. And an unknown string maps to healthy instead of throwing. node.dart shows the cost of that choice: it calls debugPrint with the unknown value before defaulting, so the surprise is logged in a debug build.'),
    blank,
    ...para('//', r'Why default instead of reject? A new node state added to the daemon later would otherwise make the whole snapshot fail to parse, and one unfamiliar enum value would blank the entire graph. Showing the node as healthy is the less damaging failure. The test makes the trade explicit so nobody tightens it by accident. Notice the contrast with the message-level parsers, which do throw on an unknown type: a node state is a detail, a message type is the framing.'),
    ...sec(r'snapshot, diff add, diff remove'),
    ...code('dart', r'heaplens_flutter/test/models/contract_test.dart · snapshot.json group', r'''
  group('snapshot.json', () {
    final json = loadFixture('snapshot.json');
    final message = GraphMessage.fromJson(json);

    test('parses as GraphSnapshot with correct type and count', () {
      expect(message, isA<GraphSnapshot>());
      final snapshot = message as GraphSnapshot;
      expect(snapshot.ts, 329700);
      expect(snapshot.nodes, hasLength(101));
    });

    test('spot-checks the first node, including a non-empty edges list', () {
      final snapshot = message as GraphSnapshot;
      final first = snapshot.nodes.first;
      expect(first.id, 571);
      expect(first.ptr, 1599777467168);
      expect(first.size, 256);
      expect(first.ts, 230900);
      expect(first.symbol, '0x7ff74ba66230');
      expect(first.live, true);
      expect(first.state, NodeStateDto.healthy);
      expect(first.edges, [572]);
    });
  });'''),
    ...para('//', r'The snapshot test asserts the dispatch (isA<GraphSnapshot>), the timestamp, and the count of 101. The second test then checks every field of the first node: id 571, ptr, size 256, ts, symbol 0x7ff74ba66230, live, healthy, and edges [572]. That one-node spot check is how a field rename or a swapped type is caught, since the count alone would not notice a node whose ptr became zero. It also deliberately picks a node with a non-empty edges list, because an empty list parses correctly under many wrong implementations.'),
    ...code('dart', r'heaplens_flutter/test/models/contract_test.dart · diff_add.json group', r'''
  group('diff_add.json', () {
    final json = loadFixture('diff_add.json');
    final message = GraphMessage.fromJson(json);

    test('parses as GraphDiff with 101 adds and empty update/remove', () {
      expect(message, isA<GraphDiff>());
      final diff = message as GraphDiff;
      expect(diff.ts, 329700);
      expect(diff.add, hasLength(101));
      expect(diff.update, isEmpty);
      expect(diff.remove, isEmpty);
    });
  });'''),
    ...code('dart', r'heaplens_flutter/test/models/contract_test.dart · diff_remove.json group', r'''
  group('diff_remove.json', () {
    final json = loadFixture('diff_remove.json');
    final message = GraphMessage.fromJson(json);

    test('parses as GraphDiff with 101 removed ids as ints', () {
      expect(message, isA<GraphDiff>());
      final diff = message as GraphDiff;
      expect(diff.ts, 329700);
      expect(diff.add, isEmpty);
      expect(diff.update, isEmpty);
      expect(diff.remove, hasLength(101));
      expect(diff.remove, everyElement(isA<int>()));
      expect(diff.remove.first, 405);
    });
  });'''),
    ...para('//', r'The two diff fixtures are mirror images. diff_add has 101 nodes in add and empty update and remove. diff_remove has the 101 ids, captured when the same allocations were freed together in one drop. The detail that matters is everyElement(isA<int>()): remove carries bare ids, not node objects, and the test pins them as ints so a model that tried to parse them as maps would fail loudly. The first id, 405, is asserted so order is also preserved.'),
    ...sec(r'the orphan fixture, honestly labelled'),
    ...code('dart', r'heaplens_flutter/test/models/contract_test.dart · diff_orphan.json group', r'''
  group('diff_orphan.json', () {
    final json = loadFixture('diff_orphan.json');
    final message = GraphMessage.fromJson(json);

    test('parses update[0] node to NodeStateDto.orphan', () {
      expect(message, isA<GraphDiff>());
      final diff = message as GraphDiff;
      expect(diff.update, hasLength(1));
      final node = diff.update.first;
      expect(node.id, 500);
      expect(node.state, NodeStateDto.orphan);
      expect(node.live, true);
      expect(node.edges, [501]);
    });
  });'''),
    ...para('//', r'This is the one fixture that is not purely captured. PROVENANCE.md says so directly: the capture rig frees an owner and its children in the same drop, so the window where an owner is freed while a child is still live never happened during the session. The orphan node is the real NodeDto of id 500 from diff_add.json with one field, state, hand-flipped from healthy to orphan. Every other field is untouched real data. The fixture exists only to pin the deserialization of NodeStateDto.orphan inside a real update entry, and the document says exactly that and no more.'),
    ...sec(r'GraphStats and the null identity'),
    ...code('dart', r'heaplens_flutter/test/models/contract_test.dart · GraphStats group', r'''
  group('GraphStats.fromJson', () {
    test('parses all fields, including null target identity before handshake', () {
      final json = <String, dynamic>{
        'type': 'stats',
        'ts': 12345,
        'events_received': 7,
        'symbols_resolved': 3,
        'hex_fallback': 4,
        'target_pid': null,
        'target_name': null,
      };
      final message = GraphMessage.fromJson(json);
      expect(message, isA<GraphStats>());
      final stats = message as GraphStats;
      expect(stats.ts, 12345);
      expect(stats.eventsReceived, 7);
      expect(stats.symbolsResolved, 3);
      expect(stats.hexFallback, 4);
      expect(stats.targetPid, isNull);
      expect(stats.targetName, isNull);
    });

    test('parses target identity once present', () {
      final json = <String, dynamic>{
        'type': 'stats',
        'ts': 1,
        'events_received': 0,
        'symbols_resolved': 0,
        'hex_fallback': 0,
        'target_pid': 4242,
        'target_name': 'target.exe',
      };
      final stats = GraphMessage.fromJson(json) as GraphStats;
      expect(stats.targetPid, 4242);
      expect(stats.targetName, 'target.exe');
    });
  });'''),
    ...para('//', r'These two tests arrived with the target-diagnostics work (0edc728). The daemon began broadcasting a stats message every second with events_received, symbols_resolved, hex_fallback, and the pid and name of the attached target. Two cases are pinned. Before the handshake frame has arrived, the target identity is JSON null and must come out as Dart null for both targetPid and targetName. Once present, both come through. The null case is the more valuable one: a model that casts pid with as int would crash on the very first stats message of every session.'),
    blank,
    ...para('//', r'These tests build the JSON as a map literal rather than loading a fixture, because no captured stats message existed when they were written. That is a quiet difference in strength from the other groups: they pin the model against the shape the author believed the daemon sends, not against recorded bytes.'),
    ...sec(r'64 bits survive'),
    ...code('dart', r'heaplens_flutter/test/models/contract_test.dart · NodeDto 64-bit precision', r'''
  group('NodeDto 64-bit precision', () {
    test('preserves full 64-bit integer precision for u64 fields', () {
      // Synthetic test: use values near 64-bit max and at 2^53+1 (smallest
      // integer a double cannot represent exactly). This test ensures that
      // jsonDecode and the `as int` casts preserve full 64-bit precision
      // and don't accidentally round through double representation.
      const largeU64 = 9007199254740993; // 2^53 + 1
      const anotherLargeU64 = 9223372036854775807; // i64 max (near u64 max)

      final json = <String, dynamic>{
        'id': largeU64,
        'ptr': anotherLargeU64,
        'size': largeU64,
        'ts': 1234567890,
        'symbol': 'test_symbol',
        'live': true,
        'state': 'healthy',
        'edges': <int>[],
      };

      final node = NodeDto.fromJson(json);

      // Verify that each u64 field is preserved exactly as-is
      expect(node.id, equals(largeU64));
      expect(node.ptr, equals(anotherLargeU64));
      expect(node.size, equals(largeU64));
      expect(node.ts, equals(1234567890));
    });
  });'''),
    ...para('//', r'The last group answers a worry specific to Dart. Rust ids, pointers and sizes are u64. In Dart for the web, numbers are JavaScript doubles, and anything above 2^53 silently loses its low bits. The test feeds 2^53 + 1, the first integer a double cannot hold, and the i64 maximum, through NodeDto.fromJson and expects them back unchanged. The comment in the test states the purpose: jsonDecode and the as int casts must not round through double. On the Windows desktop target the app ships as, int is a true 64-bit value, so this test passes; it is a tripwire for the day somebody introduces a double conversion or compiles for the web.'),
    ...para('//', r'One honest limit: the values here stop at i64 max, not u64 max. A real 64-bit pointer above 2^63 would be negative if the Dart int wrapped, and this test does not cover that range; the comment itself says the maximum used is only near u64 max.'),
    ...sec(r'what the test cannot tell you'),
    ...pt('//', r'one direction only', r'it checks Dart reading Rust output. Nothing here checks that the Rust side still emits the same keys; that is protected on the Rust side by crates/heaplens-protocol/tests/diff_json.rs.'),
    ...pt('//', r'fixture age', r'the fixtures were captured at one commit of the daemon. If the daemon adds a field, these still parse; if it changes one, only a re-capture would show it.'),
    ...pt('//', r'message types', r'the control channel has its own contract file, control_test.dart, and a routing rule keeping the two from colliding.'),
    ...sec(r'the idea in one sentence'),
    ...para('//', r'The expensive mistakes in a two-language system are the quiet ones, a field that parses to zero or a number that rounds, and this file turns each of them into a red test with a name that says which one it was.'),
  ],
);
