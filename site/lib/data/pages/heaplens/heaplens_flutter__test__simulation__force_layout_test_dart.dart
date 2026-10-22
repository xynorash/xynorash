import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/simulation/force_layout_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'force_layout_test.dart — physics you can assert on'),
    cm('//', r'the pure-Dart simulation behind the ownership graph, tested without a screen'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'pins radius scaling, spawn positions, fade-out, aggregation hysteresis and collision resolution'),
    kv('language', r'Dart, flutter_test used only for test() and expect()'),
    kv('size', r'486 lines, 17 tests in 8 groups'),
    kv('history', r'9584b71 created it, 7498f32 and fea8519 extended it (all 2026-07-06); 1cfb7f9 (2026-07-19) added radiusForSize and collision groups'),
    kv('subject', r'lib/simulation/force_layout.dart'),
    ...sec(r'a physics engine with no framework in it'),
    ...para('//', r'The graph canvas shows allocations as circles pulled together by springs and pushed apart by repulsion. All of that arithmetic lives in ForceLayout, and ForceLayout was written so it needs nothing from Flutter, no widgets, no networking, no binding. The first comment in this test file says it outright: every test exercises plain Dart objects and would run the same under package:test with no Flutter bindings initialised. That separation is what makes this file possible. It can create a layout, step it two hundred times in a loop, and look at positions, with no WidgetTester and no real time.'),
    ...code('dart', r'heaplens_flutter/test/simulation/force_layout_test.dart · file header and imports', r'''
// Uses `package:flutter_test`'s bare `test()`/`expect()` API (this project's
// standard test runner) but never touches `WidgetTester`, `pumpWidget`, or
// any Flutter binding: `ForceLayout` itself (lib/simulation/force_layout.dart)
// has zero Flutter/widget/networking imports, so every test below exercises
// plain Dart objects and would run identically under `package:test`'s VM
// runner with no Flutter bindings initialized.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:heaplens_flutter/models/node.dart';
import 'package:heaplens_flutter/simulation/force_layout.dart';
import 'package:vector_math/vector_math.dart' show Vector2;'''),
    ...para('//', r'Determinism comes from the constructor. Each layout takes an optional Random, and the tests pass seeded generators (Random(42), Random(7), Random(3)), so the jitter in spawn positions is repeatable. The tests also reach inside: they read layout.simNodes and set position and velocity directly with setValues to build the exact situation they want, then step.'),
    ...sec(r'radiusForSize: a bug fixed with a curve'),
    ...code('dart', r'heaplens_flutter/test/simulation/force_layout_test.dart · radiusForSize group', r'''
  group('radiusForSize', () {
    test('clamps to kMinNodeRadius/kMaxNodeRadius at the extremes', () {
      expect(radiusForSize(0), kMinNodeRadius);
      expect(radiusForSize(1), greaterThanOrEqualTo(kMinNodeRadius));
      expect(radiusForSize(100000000), kMaxNodeRadius);
    });

    test('is monotonically non-decreasing across realistic allocation sizes', () {
      const sizes = [1, 8, 16, 32, 64, 128, 256, 500, 1024, 4096, 65536, 1048576];
      var previous = radiusForSize(0);
      for (final size in sizes) {
        final radius = radiusForSize(size);
        expect(
          radius,
          greaterThanOrEqualTo(previous),
          reason: 'radius must not shrink as size grows (size=$size)',
        );
        previous = radius;
      }
    });

    test(
      'spreads the realistic byte-to-kilobyte range across meaningfully '
      'different radii, not clustered at the floor',
      () {
        // This is the actual bug being fixed: every workload used
        // throughout this project's own testing allocates 1-500 bytes,
        // and the old sqrt-based curve put nearly all of them within a
        // couple pixels of kMinNodeRadius. A 32-byte node and a 500-byte
        // node should now read as visibly different sizes.
        final small = radiusForSize(32);
        final medium = radiusForSize(500);
        final large = radiusForSize(65536);

        expect(medium - small, greaterThan(4.0));
        expect(large - medium, greaterThan(4.0));
      },
    );
  });'''),
    ...para('//', r'The radius of a node tells you its allocation size. The function is a clamp between 5 and 38 pixels, and the group is small but each test has a different job. The first pins the endpoints: size 0 gives the minimum, a hundred million gives the maximum. The second feeds twelve sizes from 1 byte to 1 MiB and asserts the radius never decreases, a monotonic property that catches a typo in any future retuning.'),
    blank,
    ...para('//', r'The third test is the interesting one, and its comment names the bug. Every workload in the project’s own testing allocates between 1 and 500 bytes. The older curve took a square root of the size, and nearly all of those nodes landed within a couple of pixels of the minimum, so the canvas showed a field of identical dots. The source now uses a base-2 logarithm normalised by one megabyte, kLargeSizeReference, so every doubling of size adds the same visual step.'),
    ...code('dart', r'heaplens_flutter/lib/simulation/force_layout.dart · the log2 curve', r'''
double radiusForSize(int size) {
  if (size <= 0) return kMinNodeRadius;
  final t = (math.log(size + 1) / math.ln2) / (math.log(kLargeSizeReference + 1) / math.ln2);
  return (kMinNodeRadius + (kMaxNodeRadius - kMinNodeRadius) * t)
      .clamp(kMinNodeRadius, kMaxNodeRadius);
}'''),
    ...para('//', r'The test asserts that 32 bytes, 500 bytes and 64 KiB differ by more than 4 pixels each step. Working the formula by hand, 32 bytes comes out near 13.3 px, 500 bytes near 19.8 px and 64 KiB near 31.4 px, so the steps are roughly 6.5 and 11.6 px and clear the 4 px bar. The assertion encodes what the user should see, a visible difference, not a specific number, which is why the formula can be re-tuned without breaking it.'),
    ...sec(r'where new nodes appear'),
    ...code('dart', r'heaplens_flutter/test/simulation/force_layout_test.dart · spawn near the owner', r'''
  group('addNode spawn positioning', () {
    test('spawns within jitter radius of owner position', () {
      final layout = ForceLayout(
        centerX: 400,
        centerY: 300,
        random: Random(42),
      );

      final owner = _node(id: 1, edges: [2]);
      final currentNodes = {1: owner, 2: _node(id: 2)};

      layout.addNode(owner, currentNodes);
      // Move the owner's SimNode away from center so we can tell the child
      // spawned near the owner, not near center.
      layout.simNodes[1]!.position.setValues(1000, 1000);

      layout.addNode(currentNodes[2]!, currentNodes);

      final child = layout.simNodes[2]!;
      final ownerPos = layout.simNodes[1]!.position;
      final dist = (child.position - ownerPos).length;

      // kSpawnJitter is applied independently on x and y, so max possible
      // distance from owner is sqrt(2) * kSpawnJitter.
      expect(dist, lessThanOrEqualTo(kSpawnJitter * 1.5));
    });'''),
    ...para('//', r'A new node must not appear at a random place, or the graph would jump around as allocations arrive. The test creates an owner at the centre, then drags the owner’s SimNode to (1000, 1000) so that the centre and the owner are far apart. A child spawned afterwards must be near the owner, within 1.5 times kSpawnJitter. The jitter is applied independently on x and y, as the comment says, so the true maximum is the square root of two times the jitter, about 1.41, and 1.5 is a safe bound. Moving the owner away is the clever part of the setup: a child that wrongly spawned at the centre would otherwise look fine.'),
    ...code('dart', r'heaplens_flutter/test/simulation/force_layout_test.dart · spawn at the centre without an owner', r'''
    test('spawns near canvas center when no owner exists', () {
      final layout = ForceLayout(
        centerX: 400,
        centerY: 300,
        random: Random(7),
      );

      final orphan = _node(id: 5, edges: const []);
      layout.addNode(orphan, {5: orphan});

      final sim = layout.simNodes[5]!;
      final distFromCenter = ((sim.position.x - 400).abs());
      final distFromCenterY = ((sim.position.y - 300).abs());

      expect(distFromCenter, lessThanOrEqualTo(kSpawnJitter));
      expect(distFromCenterY, lessThanOrEqualTo(kSpawnJitter));
    });'''),
    ...para('//', r'With no owner in the node map, the node appears within kSpawnJitter of the canvas centre, 400 by 300 here. The assertions check x and y separately because the jitter box is square. This is the fallback that main.dart’s comments talk about: if the owner lookup sees a stale map, the child lands here instead of near its owner, and the only damage is cosmetic.'),
    ...sec(r'updating a node must not move it'),
    ...code('dart', r'heaplens_flutter/test/simulation/force_layout_test.dart · a size change never moves position or velocity', r'''
  group('updateNode', () {
    test('a size change never moves position or velocity', () {
      final layout = ForceLayout(random: Random(1));
      final node = _node(id: 1, size: 64);
      layout.addNode(node, {1: node});

      final sim = layout.simNodes[1]!;
      sim.position.setValues(123.0, 456.0);
      sim.velocity.setValues(1.5, -2.5);
      final radiusBefore = sim.radius;

      final updated = _node(id: 1, size: 4096);
      layout.updateNode(updated);

      final after = layout.simNodes[1]!;
      expect(after.position.x, equals(123.0));
      expect(after.position.y, equals(456.0));
      expect(after.velocity.x, equals(1.5));
      expect(after.velocity.y, equals(-2.5));
      expect(after.radius, isNot(equals(radiusBefore)));
      expect(after.radius, equals(radiusForSize(4096)));
    });
  });'''),
    ...para('//', r'The daemon sends an update when a node’s size, state or edges change. If updateNode reset the position, the graph would flicker with every update. The test places a node at (123, 456) with velocity (1.5, -2.5), updates its size from 64 to 4096, and checks the position and velocity are exactly the same numbers while the radius changed to radiusForSize(4096). Exact equality on doubles is right here because nothing should have touched them.'),
    ...sec(r'fading out instead of vanishing'),
    ...code('dart', r'heaplens_flutter/test/simulation/force_layout_test.dart · fade then delete', r'''
  group('removeNode fade-out', () {
    test('fades then is deleted after ~1s of simulated steps', () {
      final layout = ForceLayout(random: Random(3));
      final node = _node(id: 9);
      layout.addNode(node, {9: node});

      layout.removeNode(9);

      // Still present immediately after removeNode (fade in progress).
      expect(layout.simNodes.containsKey(9), isTrue);
      expect(layout.simNodes[9]!.fade, equals(1.0));

      // Step in small increments; node should still exist but fade should
      // be decreasing partway through.
      for (var i = 0; i < 5; i++) {
        layout.step(0.1);
      }
      expect(layout.simNodes.containsKey(9), isTrue);
      expect(layout.simNodes[9]!.fade, lessThan(1.0));
      expect(layout.simNodes[9]!.fade, greaterThan(0.0));

      // Push past the fade duration (kFadeDurationSeconds == 1.0s total;
      // 0.5s elapsed above, so 10 more 0.1s steps clears it).
      for (var i = 0; i < 10; i++) {
        layout.step(0.1);
      }
      expect(layout.simNodes.containsKey(9), isFalse);
    });
  });'''),
    ...para('//', r'A freed allocation does not disappear in one frame; it fades for kFadeDurationSeconds, one second. The test checks the three stages: right after removeNode the node is still there with fade exactly 1.0; after five steps of 0.1 seconds the fade is strictly between 0 and 1; after ten more steps the node is gone. The comment does the arithmetic, 0.5 seconds elapsed, then ten steps clear it. Using step(dt) with explicit durations is what removes any need for a clock.'),
    ...code('dart', r'heaplens_flutter/test/simulation/force_layout_test.dart · lastKnownState survives the fade', r'''
  group('removeNode captures lastKnownState for fade rendering', () {
    test('captures the outgoing NodeDto.state onto SimNode.lastKnownState',
        () {
      final layout = ForceLayout(random: Random(3));
      final node = _node(id: 9, state: NodeStateDto.orphan);
      layout.addNode(node, {9: node});

      expect(layout.simNodes[9]!.lastKnownState, isNull);

      layout.removeNode(9);

      expect(layout.simNodes[9]!.lastKnownState, equals(NodeStateDto.orphan));
      // The captured state must survive across the fade, since the painter
      // needs it on every frame until the SimNode is finally deleted.
      layout.step(0.5);
      expect(layout.simNodes[9]!.lastKnownState, equals(NodeStateDto.orphan));
    });'''),
    ...para('//', r'Commit fea8519, titled render freed-node fade ghosts, explains why. By the time a node fades, it is no longer in the live map, so the painter cannot ask what colour it was. removeNode copies the outgoing state onto SimNode.lastKnownState, and the test checks both that it starts as null and that it is still orphan after half a second of stepping.'),
    ...code('dart', r'heaplens_flutter/test/simulation/force_layout_test.dart · an emptied aggregate also captures state', r'''
    test('aggregate bucket emptying out also captures a lastKnownState', () {
      final layout = ForceLayout(random: Random(5));
      for (var i = 0; i < kAggregationThreshold + 1; i++) {
        final n = _node(id: i, symbol: 'sym_${i % 10}');
        layout.addNode(n, {i: n});
      }
      layout.step(0.016);
      expect(layout.isAggregated, isTrue);

      // Drain every member of symbol 'sym_0' (ids 0, 10, 20, ...).
      for (var i = 0; i < kAggregationThreshold + 1; i += 10) {
        layout.removeNode(i);
      }

      // Find the (now fading) aggregate SimNode: any negative-id key still
      // present with a non-null lastKnownState.
      final fadingAgg = layout.simNodes.entries
          .where((e) => e.key < 0 && e.value.lastKnownState != null)
          .toList();
      expect(fadingAgg, isNotEmpty);
    });'''),
    ...para('//', r'The same property for aggregated mode. After the node count passes the threshold, the layout shows one bubble per symbol, with negative ids. The test removes every member of sym_0 and then looks for any negative-id entry that still exists and carries a lastKnownState. The test looks for the entry by pattern, not by id, because the aggregate’s id is internal.'),
    ...sec(r'aggregation: more than 500 nodes become one bubble per symbol'),
    ...code('dart', r'heaplens_flutter/lib/simulation/force_layout.dart · the thresholds', r'''
/// ENF9: once the number of *live* nodes known to the layout exceeds this,
/// [ForceLayout] switches from one [SimNode] per node to one aggregate
/// [SimNode] per distinct `symbol` (summed size, tracked count). See the
/// switch point in [ForceLayout._syncAggregation] — search that method
/// when touching aggregation behavior. Must activate strictly above the
/// threshold, not at or below it.
const int kAggregationThreshold = 500;

/// ENF9 hysteresis: once aggregated, [ForceLayout] does not fall back to
/// individual mode until [ForceLayout.liveNodeCount] drops *below* this
/// (lower) threshold. This creates a dead zone between
/// [kAggregationExitThreshold] and [kAggregationThreshold] where neither
/// transition fires, so live-count churn oscillating near the boundary
/// (e.g. 498, 501, 499, 502...) doesn't repeatedly force a full
/// [ForceLayout._rebuildFromRaw] reset in each direction. Must stay
/// strictly below [kAggregationThreshold].
const int kAggregationExitThreshold = 450;

/// Half-width (px) of the random jitter box used when spawning a node: near'''),
    ...para('//', r'Drawing thousands of circles with springs would be slow and unreadable, so when the number of live nodes exceeds 500, ForceLayout collapses to one SimNode per symbol, with the sizes summed. The doc comment stresses one rule: it must activate strictly above the threshold. Three tests make that precise.'),
    ...code('dart', r'heaplens_flutter/test/simulation/force_layout_test.dart · strictly above', r'''
  group('aggregation (ENF9)', () {
    test('does not activate at exactly the threshold', () {
      final layout = ForceLayout(random: Random(5));
      for (var i = 0; i < kAggregationThreshold; i++) {
        final n = _node(id: i, symbol: 'sym_${i % 10}');
        layout.addNode(n, {i: n});
      }
      layout.step(0.016);

      expect(layout.liveNodeCount, equals(kAggregationThreshold));
      expect(layout.isAggregated, isFalse);
      expect(layout.simNodes.length, equals(kAggregationThreshold));
    });

    test('activates strictly above the threshold, collapsing to one '
        'SimNode per symbol', () {
      final layout = ForceLayout(random: Random(5));
      const symbolCount = 10;
      for (var i = 0; i < kAggregationThreshold + 1; i++) {
        final n = _node(id: i, symbol: 'sym_${i % symbolCount}');
        layout.addNode(n, {i: n});
      }
      layout.step(0.016);

      expect(layout.liveNodeCount, equals(kAggregationThreshold + 1));
      expect(layout.isAggregated, isTrue);
      expect(layout.simNodes.length, equals(symbolCount));
    });'''),
    ...para('//', r'At exactly 500 live nodes, spread over ten symbols, isAggregated is false and there are 500 SimNodes. At 501 it is true, and the SimNode count is ten, one per symbol. Both tests step the layout after adding, because the switch happens inside step, which is also the reason the doc names _syncAggregation.'),
    ...code('dart', r'heaplens_flutter/test/simulation/force_layout_test.dart · hysteresis', r'''
    test(
      'does NOT fall back to individual mode merely dropping back to the '
      'entry threshold — hysteresis dead zone',
      () {
        final layout = ForceLayout(random: Random(5));
        for (var i = 0; i < kAggregationThreshold + 1; i++) {
          final n = _node(id: i, symbol: 'sym_${i % 10}');
          layout.addNode(n, {i: n});
        }
        layout.step(0.016);
        expect(layout.isAggregated, isTrue);

        layout.removeNode(kAggregationThreshold); // back down to threshold
        layout.step(0.016);

        // Still above kAggregationExitThreshold (450), so hysteresis keeps
        // it aggregated instead of thrashing back to individual mode.
        expect(layout.liveNodeCount, equals(kAggregationThreshold));
        expect(layout.isAggregated, isTrue);
      },
    );

    test(
      'hysteresis: stays aggregated in the dead zone, only falls back once '
      'below the exit threshold',
      () {
        final layout = ForceLayout(random: Random(5));
        for (var i = 0; i < kAggregationThreshold + 1; i++) {
          final n = _node(id: i, symbol: 'sym_${i % 10}');
          layout.addNode(n, {i: n});
        }
        layout.step(0.016);
        expect(layout.isAggregated, isTrue);

        // Drop down to 480 (between kAggregationExitThreshold=450 and
        // kAggregationThreshold=500): must NOT switch back to individual.
        for (var i = kAggregationThreshold; i >= 480; i--) {
          layout.removeNode(i);
        }
        layout.step(0.016);
        expect(layout.liveNodeCount, equals(480));
        expect(layout.isAggregated, isTrue);

        // Drop further, below kAggregationExitThreshold=450: now it must
        // fall back to individual mode.
        for (var i = 479; i >= 440; i--) {
          layout.removeNode(i);
        }
        layout.step(0.016);
        expect(layout.liveNodeCount, equals(440));
        expect(layout.isAggregated, isFalse);
      },
    );'''),
    ...para('//', r'The exit threshold of 450 is the subject of the next two. Going back to 500 live nodes after being aggregated must not switch back; the comment says why, churn near the boundary (498, 501, 499, 502) would force a full rebuild each time. The second test is a staircase: remove down to 480, which is in the dead zone, and it must stay aggregated; then remove down to 440, below the exit threshold, and it must return to individual mode. Both sides of the band are asserted, because a test that only checked staying put would pass with the exit threshold missing altogether.'),
    ...code('dart', r'heaplens_flutter/test/simulation/force_layout_test.dart · a fading node survives a rebuild', r'''
    test(
      'a node mid-fade survives a mode-switch rebuild and still deletes '
      'itself once its fade completes',
      () {
        final layout = ForceLayout(random: Random(5));
        for (var i = 0; i < kAggregationThreshold; i++) {
          final n = _node(id: i, symbol: 'sym_${i % 10}');
          layout.addNode(n, {i: n});
        }
        layout.step(0.016);
        expect(layout.isAggregated, isFalse);

        // Start a fade on one individual-mode node, then immediately push
        // live count past the aggregation threshold in the same tick's
        // worth of events (fade begins, then boundary is crossed).
        layout.removeNode(0);
        expect(layout.simNodes.containsKey(0), isTrue);
        expect(layout.simNodes[0]!.fade, equals(1.0));

        // Live count was 500 (not > 500), then dropped to 499 by the
        // removeNode above; add two new nodes to push it to 501, strictly
        // above kAggregationThreshold, before the next step.
        final extraA = _node(id: 999998, symbol: 'sym_new');
        final extraB = _node(id: 999999, symbol: 'sym_new');
        layout.addNode(extraA, {999998: extraA});
        layout.addNode(extraB, {999999: extraB});
        layout.step(0.016); // crosses into aggregated mode -> rebuild

        expect(layout.isAggregated, isTrue);
        // The fading node must have survived the mode-switch rebuild rather
        // than being dropped instantly.
        expect(layout.simNodes.containsKey(0), isTrue);
        expect(layout.simNodes[0]!.fade, lessThanOrEqualTo(1.0));
        expect(layout.simNodes[0]!.fade, greaterThan(0.0));

        // Advance enough simulated time to finish the fade; it must be
        // deleted via the normal _advanceFades path, not left dangling.
        for (var i = 0; i < 20; i++) {
          layout.step(0.1);
        }
        expect(layout.simNodes.containsKey(0), isFalse);
      },
    );'''),
    ...para('//', r'This is the regression from commit 7498f32. Crossing the threshold rebuilds all SimNodes from the raw data, and removeNode has already stripped the raw entry the moment a fade starts, so the rebuild silently dropped the fading node. The test builds 500 nodes, starts a fade on node 0, adds two more to reach 501, and steps once. It asserts the layout is now aggregated, and node 0 is still present with a fade above 0 and at most 1. Finally twenty steps of 0.1 seconds must still delete it by the normal path. The comment about the order of events, fade begins and then the boundary is crossed in the same tick, shows how rare the sequence is and why a general test would not have found it.'),
    ...sec(r'does it behave like physics?'),
    ...code('dart', r'heaplens_flutter/test/simulation/force_layout_test.dart · connected nodes drift toward rest length', r'''
  group('step physics sanity', () {
    test('connected nodes drift toward rest length over time', () {
      final layout = ForceLayout(random: Random(11));
      final a = _node(id: 1, edges: [2]);
      final b = _node(id: 2);
      layout.addNode(a, {1: a, 2: b});
      layout.addNode(b, {1: a, 2: b});

      // Force them far apart initially.
      layout.simNodes[1]!.position.setValues(0, 0);
      layout.simNodes[2]!.position.setValues(500, 0);

      for (var i = 0; i < 200; i++) {
        layout.step(0.016);
      }

      final dist =
          (layout.simNodes[2]!.position - layout.simNodes[1]!.position)
              .length;
      // Should have contracted substantially from 500 toward ~restLength.
      expect(dist, lessThan(500));
    });
  });'''),
    ...para('//', r'The only test of the spring force. Two connected nodes are placed 500 pixels apart and the layout steps 200 times at 16 ms. The assertion is only that the distance is less than 500. That is deliberately weak. It proves springs pull, without fixing the settled distance, which depends on repulsion, gravity and damping. A tight assertion would have to be rewritten every time one of those constants is adjusted.'),
    ...sec(r'no overlapping circles'),
    ...para('//', r'The last group came with the UI refresh (1cfb7f9) and the source constants explain what it fixed. Gravity is kept low on purpose because it fought the collision pass and piled disconnected roots into a clump. Repulsion has a floor on the gap, kMinRepulsionGap, to avoid a force that tends to infinity, and a separate hard pass, _resolveCollisions, moves circles apart using a spatial hash with cells of 2 times the max radius plus a margin, so it can check only a node’s own cell and 8 neighbours.'),
    ...code('dart', r'heaplens_flutter/lib/simulation/force_layout.dart · collision margin and cell size', r'''
const double kCollisionMargin = 3.0;

/// Side length (px) of the spatial-hash grid cell used by
/// [ForceLayout._resolveCollisions]. Sized to `2 * kMaxNodeRadius +
/// kCollisionMargin` so that any pair of nodes close enough to overlap
/// (their radii sum is at most `2 * kMaxNodeRadius`) always falls within
/// one cell of each other — checking a node's own cell plus its 8
/// neighbors is therefore guaranteed to find every real collision
/// candidate, without an O(n^2) all-pairs scan.
const double kCollisionCellSize =
    kMaxNodeRadius * 2 + kCollisionMargin;'''),
    ...code('dart', r'heaplens_flutter/test/simulation/force_layout_test.dart · disconnected roots spread out', r'''
  group('collision resolution (overlap fix)', () {
    test(
      'disconnected roots (no edges) spread out with no overlapping circles',
      () {
        // The reported "blob" case: many healthy roots, no springs holding
        // any of them together, all initially spawned near the same point.
        final layout = ForceLayout(centerX: 400, centerY: 300, random: Random(7));
        final nodes = <int, NodeDto>{
          for (var i = 0; i < 25; i++)
            i: _node(id: i, size: 200 + i * 300, symbol: 'root_$i'),
        };
        for (final node in nodes.values) {
          layout.addNode(node, nodes);
          // Force everyone to spawn on top of each other, worse than the
          // real jittered spawn — the harder version of the reported bug.
          layout.simNodes[node.id]!.position.setValues(400, 300);
        }

        for (var i = 0; i < 400; i++) {
          layout.step(0.016);
        }

        final ids = layout.simNodes.keys.toList();
        for (var i = 0; i < ids.length; i++) {
          for (var j = i + 1; j < ids.length; j++) {
            final a = layout.simNodes[ids[i]]!;
            final b = layout.simNodes[ids[j]]!;
            final dist = (a.position - b.position).length;
            final minDist = a.radius + b.radius;
            expect(
              dist,
              greaterThanOrEqualTo(minDist - 0.5), // small float tolerance
              reason:
                  'nodes ${ids[i]} and ${ids[j]} still overlap after settling',
            );
          }
        }

        // Not just non-overlapping — actually spread into a field, not
        // pinned in a tight pile at the spawn point.
        final maxDistFromCenter = ids
            .map((id) => (layout.simNodes[id]!.position - Vector2(400, 300)).length)
            .reduce(max);
        expect(maxDistFromCenter, greaterThan(60));
      },
    );'''),
    ...para('//', r'The scenario is called the reported blob case in a comment. Twenty-five roots with sizes from 200 to 7,400 bytes, no edges, are all forced onto the same point, which is harsher than the real jittered spawn. After 400 steps, every pair is checked: the distance between centres must be at least the sum of radii minus 0.5, a small tolerance for floating point. A second assertion makes sure the nodes actually spread: the farthest one must be more than 60 pixels from the centre. Without it, a layout that merely froze would satisfy the overlap condition only by luck, but the check makes both conditions explicit.'),
    ...code('dart', r'heaplens_flutter/test/simulation/force_layout_test.dart · a high fan-out star', r'''
    test(
      'high-fan-out star stays a recognizable hub-and-spokes, no overlap, '
      'no central pile-up',
      () {
        // One owner with many children — springs pull children toward the
        // owner, which is exactly the shape collision resolution must not
        // blow apart, while still not letting the children overlap each
        // other or the owner at the center.
        final layout = ForceLayout(centerX: 400, centerY: 300, random: Random(3));
        final childIds = List.generate(40, (i) => i + 1);
        final owner = _node(id: 0, size: 500, edges: childIds);
        final nodes = <int, NodeDto>{
          0: owner,
          for (final id in childIds) id: _node(id: id, size: 300),
        };

        layout.addNode(owner, nodes);
        for (final id in childIds) {
          layout.addNode(nodes[id]!, nodes);
        }

        for (var i = 0; i < 400; i++) {
          layout.step(0.016);
        }

        final ownerPos = layout.simNodes[0]!.position;
        final ownerRadius = layout.simNodes[0]!.radius;

        // No overlap anywhere, including owner-vs-child.
        final ids = layout.simNodes.keys.toList();
        for (var i = 0; i < ids.length; i++) {
          for (var j = i + 1; j < ids.length; j++) {
            final a = layout.simNodes[ids[i]]!;
            final b = layout.simNodes[ids[j]]!;
            final dist = (a.position - b.position).length;
            final minDist = a.radius + b.radius;
            expect(
              dist,
              greaterThanOrEqualTo(minDist - 0.5),
              reason:
                  'nodes ${ids[i]} and ${ids[j]} still overlap after settling',
            );
          }
        }

        // Still a star, not blown apart: every child stays within a bounded
        // radius of the owner, not scattered across the whole canvas. The
        // bound is generous (not exactly kSpringRestLength) because 40
        // non-overlapping child circles physically cannot all pack into a
        // ring at the spring's exact rest length — collision resolution
        // legitimately pushes some further out to make room. What this
        // guards against is the real "blown apart" pathology: children
        // ending up scattered arbitrarily far away.
        for (final id in childIds) {
          final dist = (layout.simNodes[id]!.position - ownerPos).length;
          expect(
            dist,
            lessThan(kSpringRestLength * 5),
            reason: 'child $id drifted far from its owner — star was blown apart',
          );
          expect(
            dist,
            greaterThanOrEqualTo(ownerRadius),
            reason: 'child $id is inside the owner\'s own drawn circle',
          );
        }
      },
    );'''),
    ...para('//', r'One owner with forty children is the shape springs love and collisions hate. Children must not overlap each other or the owner, and each must stay within five rest lengths (400 pixels) of the owner but not inside the owner’s own circle. The long comment explains the bound: forty non-overlapping circles cannot all sit on a ring at exactly the rest length, so collision resolution pushes some outward, and the test guards the pathology of children flung across the canvas, not the exact radius.'),
    ...sec(r'things this file does not cover'),
    ...pt('//', r'speed', r'nothing times the simulation. The spatial hash exists to avoid O(n squared), but with 25 and 41 nodes the tests would pass with an all-pairs scan.'),
    ...pt('//', r'aggregated physics', r'collision and spring behaviour in aggregated mode have no assertions; the aggregation tests only count nodes and flags.'),
    ...pt('//', r'Random seeds', r'several tests rely on a fixed seed for the spawn jitter. If the generator or the order of random calls changes, results change, though the assertions are written as inequalities that should hold for any seed.'),
  ],
);
