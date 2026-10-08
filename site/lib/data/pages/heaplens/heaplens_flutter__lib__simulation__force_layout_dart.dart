import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/simulation/force_layout.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'force_layout.dart — the physics behind the ownership graph'),
    cm('//', r'springs, repulsion, a hard collision pass, fades and aggregation'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'pure-Dart force-directed layout; positions, radii, fades'),
    kv('language', r'Dart (dart:math and vector_math only, no Flutter imports)'),
    kv('size', r'715 lines; 5 commits, 2026-07-06 to 2026-07-19'),
    kv('tested by', r'test/simulation/force_layout_test.dart (17 tests, 486 lines)'),
    kv('ticked by', r'main.dart at ~30 Hz; drawn by widgets/graph_canvas.dart'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'The daemon tells the UI which allocations exist and which one '
        r'owns which. It says nothing about where to put them on a '
        r'screen. Somebody has to decide that, continuously, as nodes '
        r'appear, grow and vanish, and the decision has to look stable '
        r'enough that a person can follow one allocation with their '
        r'eyes. This file is that somebody.'),
    blank,
    ...para('//',
        r'The Build Spec’s section 6.4 gives the brief: repulsion '
        r'between all visible nodes, attraction along edges, gravity '
        r'toward the centre, velocity damping, "pure layout math — no '
        r'networking, no widgets", and an escape hatch for scale: "O(n²); '
        r'cap at ~500 visible, else aggregate by symbol". Each of those '
        r'phrases has a counterpart in the code below, and several have '
        r'a later correction.'),
    blank,
    ...para('//',
        r'The file’s boundary is stated at the top of the class '
        r'comment: "Pure-Dart (no dart:ui, no widget imports, no '
        r'networking)". That one rule buys a lot. The 17 tests run as '
        r'plain objects with a seeded Random, and the class never has '
        r'to know when it is being drawn: it only advances its own '
        r'clock when step is called.'),
    ...sec(r'the physical vocabulary'),
    ...code('dart', 'heaplens_flutter/lib/simulation/force_layout.dart · SimNode', r'''
class SimNode {
  Vector2 position;
  Vector2 velocity;
  double radius;
...
  double fade;
...
  NodeStateDto? lastKnownState;

  SimNode({
    required this.position,
    required this.velocity,
    required this.radius,
    this.fade = 1.0,
    this.lastKnownState,
  });
}'''),
    ...para('//',
        r'A SimNode is five fields and no identity: no id, no symbol, '
        r'no edge list. The doc comment calls this a "locked design '
        r'(Q4)" and explains that ForceLayout keeps all bookkeeping in '
        r'side maps keyed by the same id, "so this struct stays a pure '
        r'physics value type". The layout is therefore two parallel '
        r'worlds: simNodes (where things are) and _rawNodes (what the '
        r'daemon last said about each), joined only by id. Keep that '
        r'in mind, because most of the file’s hard cases are about '
        r'keeping the two consistent.'),
    blank,
    ...para('//',
        r'The odd field is lastKnownState. It is null for the whole life '
        r'of a normal node and filled in only at the instant a fade '
        r'begins. It exists because of the bug found in the final review '
        r'of milestone M5 (fea8519): the painter needed a live NodeDto '
        r'to draw anything, but the same step that starts a fade also '
        r'deletes the NodeDto from the graph provider’s map. The fade '
        r'therefore ran for a full second with nothing on screen. '
        r'Capturing the state onto the SimNode lets the painter draw a '
        r'fading ghost from simNodes alone.'),
    ...sec(r'tuning constants'),
    ...pt('//', r'kSpringRestLength = 80.0, kSpringStrength = 0.06',
        r'the spring along each ownership edge.'),
    ...pt('//', r'kRepulsionStrength = 3000.0',
        r'pairwise inverse-square repulsion.'),
    ...pt('//', r'kGravityStrength = 0.012',
        r'a gentle pull to the centre. It started at 0.02 and was '
        r'lowered in the UI refresh, with the reason in the comment: '
        r'"enough to hold the graph on-screen, not enough to fight the '
        r'collision pass and pile disconnected roots back into a clump".'),
    ...pt('//', r'kVelocityDamping = 0.85',
        r'multiplied into the velocity every step.'),
    ...pt('//', r'kMinNodeRadius = 5.0, kMaxNodeRadius = 38.0',
        r'earlier 4.0 and 40.0.'),
    ...pt('//', r'kMinRepulsionGap = 2.0, kCollisionMargin = 3.0',
        r'the two numbers that keep the repulsion finite and the '
        r'circles from touching.'),
    ...pt('//', r'kFadeDurationSeconds = 1.0',
        r'a removed node fades for one second of simulated time.'),
    ...pt('//', r'kAggregationThreshold = 500, kAggregationExitThreshold = 450',
        r'see the aggregation section.'),
    ...pt('//', r'kSpawnJitter = 20.0',
        r'a new node lands within a 40 by 40 px box of its target point.'),
    blank,
    ...para('//',
        r'None of these has an experiment behind it in the repository. '
        r'They are tuned by looking, and the commit messages say so '
        r'where it matters (the overlap fix was "the reported blob '
        r'bug", found in the running app).'),
    ...sec(r'sizing a circle: from sqrt to a logarithm'),
    ...code('dart', 'heaplens_flutter/lib/simulation/force_layout.dart · radiusForSize', r'''
double radiusForSize(int size) {
  if (size <= 0) return kMinNodeRadius;
  final t = (math.log(size + 1) / math.ln2) / (math.log(kLargeSizeReference + 1) / math.ln2);
  return (kMinNodeRadius + (kMaxNodeRadius - kMinNodeRadius) * t)
      .clamp(kMinNodeRadius, kMaxNodeRadius);
}'''),
    ...para('//',
        r'The original, from the M5 plan and the Build Spec, was a '
        r'square root: radius proportional to sqrt(size), clamped to '
        r'4..40. It looks sensible, since area then grows with size. '
        r'The UI-refresh commit (1cfb7f9) replaced it, and the doc '
        r'comment calls the change "a real fix, not a cosmetic tweak". '
        r'The allocation sizes this project actually draws are '
        r'"1 to a few hundred bytes". For those, sqrt barely moves '
        r'(sqrt(500) is about 22, sqrt(32) about 6) while a handful of '
        r'larger outliers hit the clamp, so almost every node sat near '
        r'the floor with the occasional maxed-out blob. A log2 curve '
        r'maps each doubling of size to the same number of pixels.'),
    blank,
    ...para('//',
        r'Worked through the formula (my arithmetic, not a repository '
        r'result), radius in px for the old and the new curve:'),
    ...pt('//', r'32 B', r'5.7 old, 13.3 new'),
    ...pt('//', r'128 B', r'11.3 old, 16.6 new'),
    ...pt('//', r'256 B', r'16.0 old, 18.2 new'),
    ...pt('//', r'500 B', r'22.4 old, 19.8 new'),
    ...pt('//', r'2400 B', r'40.0 (clamped) old, 23.5 new'),
    ...pt('//', r'64 KiB', r'40.0 (clamped) old, 31.4 new'),
    ...pt('//', r'1 MiB', r'40.0 old, 38.0 new (the reference point)'),
    blank,
    ...para('//',
        r'The 2400-byte owner and its 128 and 256-byte children in the '
        r'captured fixtures are exactly this regime: under the old curve '
        r'the owner was a maximum-size disc and the children small; '
        r'under the new one they are 23.5 px against 16.6 and 18.2. The '
        r'test that guards the change is named after the symptom, "spreads '
        r'the realistic byte-to-kilobyte range ... not clustered at the '
        r'floor". It requires 500 B to be more than 4 px larger than 32 B, '
        r'and 64 KiB more than 4 px larger than 500 B. A second test '
        r'requires the radius to be monotonically non-decreasing over '
        r'twelve sizes from 1 byte to 1 MiB.'),
    ...sec(r'entering and leaving: the public mutation API'),
    ...code('dart', 'heaplens_flutter/lib/simulation/force_layout.dart · addNode and removeNode', r'''
  void addNode(NodeDto node, Map<int, NodeDto> currentNodes) {
    _rawNodes[node.id] = node;
    _fadeRemaining.remove(node.id); // defensive: re-added after a fade start

    if (_aggregated) {
      _addToAggregate(node);
      return;
    }

    final ownerId = _findOwnerId(node.id, currentNodes);
    simNodes[node.id] = SimNode(
      position: _spawnPosition(ownerId),
      velocity: Vector2.zero(),
      radius: radiusForSize(node.size),
    );
  }
...
  void removeNode(int id) {
    final outgoing = _rawNodes.remove(id);

    if (_aggregated) {
      _removeFromAggregate(id);
      return;
    }

    if (simNodes.containsKey(id) && !_fadeRemaining.containsKey(id)) {
      _fadeRemaining[id] = kFadeDurationSeconds;
      simNodes[id]!.lastKnownState = outgoing?.state ?? NodeStateDto.freed;
    }
  }'''),
    ...pt('//', r'spawn near the owner',
        r'a new node starts within the jitter box of its owner’s '
        r'current position, found by scanning for the other node whose '
        r'edges contain the new id. With no owner, or an owner without '
        r'a SimNode yet, it starts near the canvas centre. This matters '
        r'more than any force: as the next section shows, the forces '
        r'are slow, so where a node starts largely decides where it '
        r'ends up. The test places an owner at (1000, 1000), adds the '
        r'child, and requires the child within 1.5 times the jitter '
        r'of the owner.'),
    ...pt('//', r'updates never move a node',
        r'updateNode only refreshes the radius. The test sets a '
        r'position (123, 456) and velocity (1.5, -2.5), updates the '
        r'size from 64 to 4096, and asserts both are unchanged while '
        r'the radius becomes radiusForSize(4096). A node growing must '
        r'not teleport.'),
    ...pt('//', r'removal starts a countdown, it does not delete',
        r'the SimNode stays until step has advanced the fade to zero. '
        r'The fade clock is the simulation’s, not the wall clock: the '
        r'constant’s comment says it is "never" advanced by real time '
        r'or by when the remove event arrived. That makes it testable '
        r'with fake steps: five steps of 0.1 leave the fade strictly '
        r'between 0 and 1; ten more delete the node.'),
    blank,
    ...code('dart', 'heaplens_flutter/lib/simulation/force_layout.dart · resetFrom (trimmed)', r'''
  void resetFrom(List<NodeDto> nodes, Map<int, NodeDto> currentNodes) {
    final newIds = nodes.map((n) => n.id).toSet();
    final staleIds =
        _rawNodes.keys.where((id) => !newIds.contains(id)).toList();
    for (final id in staleIds) {
      removeNode(id);
    }
    for (final node in nodes) {
      if (_rawNodes.containsKey(node.id)) {
        updateNode(node);
      } else {
        addNode(node, currentNodes);
      }
    }
  }'''),
    ...para('//',
        r'resetFrom was added during the final wiring (23b80e4) to '
        r'handle a snapshot. The doc comment contrasts it with the '
        r'internal hard reset: "existing tracked nodes that are still '
        r'present keep their SimNode (position/velocity untouched ...), '
        r'so most nodes surviving a reconnect don’t visually jump". '
        r'Nodes that disappeared fade out; new ones spawn. After a '
        r'daemon restart, then, the picture dissolves and re-forms '
        r'instead of snapping.'),
    ...sec(r'the forces, and an honest look at how slow they are'),
    ...code('dart', 'heaplens_flutter/lib/simulation/force_layout.dart · _applyForces, repulsion (trimmed)', r'''
    // Pairwise repulsion, O(n^2). Radius-aware: computed from the gap
    // between drawn *edges* (distance - (r_i + r_j)), not center-to-center
    // distance. A point-distance model treats two big nodes whose circles
    // already overlap as "far enough" once their centers clear a fixed
    // distance — this is the root cause of the reported blob overlap.
...
        final dist = math.sqrt(distSq);
        final dir = delta / dist;
        final gap = dist - (aSim.radius + bSim.radius);
...
        final effectiveGap = math.max(gap, kMinRepulsionGap);
        final forceMag = kRepulsionStrength / (effectiveGap * effectiveGap);
        forces[aId] = forces[aId]! + dir * forceMag;
        forces[bId] = forces[bId]! + dir * -forceMag;'''),
    ...para('//',
        r'The first version used kRepulsionStrength / distSq, a '
        r'textbook Coulomb force on centre-to-centre distance. It '
        r'failed visibly: with nodes of different sizes, two big discs '
        r'could overlap while their centres were "far enough apart on '
        r'paper". The fix measures the gap between the drawn edges '
        r'instead, and floors it at kMinRepulsionGap so two touching '
        r'discs produce a large but finite push rather than a division '
        r'by zero. The comment is explicit about what the force is not: '
        r'the hard guarantee that circles never actually overlap, it '
        r'says, belongs to _resolveCollisions and not to this force.'),
    blank,
    ...code('dart', 'heaplens_flutter/lib/simulation/force_layout.dart · springs, gravity, integration', r'''
          final delta = target.position - self.position;
          final dist = math.max(delta.length, 0.0001);
          final dir = delta / dist;
          final stretch = dist - kSpringRestLength;
          final force = dir * (kSpringStrength * stretch);
          forces[id] = forces[id]! + force;
          forces[targetId] = forces[targetId]! - force;
...
    // Gentle gravity to center.
    final center = Vector2(centerX, centerY);
    for (final id in ids) {
      final self = simNodes[id]!;
      forces[id] = forces[id]! + (center - self.position) * kGravityStrength;
    }

    // Integrate: semi-implicit Euler with velocity damping.
    for (final id in ids) {
      final sim = simNodes[id]!;
      sim.velocity = (sim.velocity + forces[id]! * dt) * kVelocityDamping;
      sim.position = sim.position + sim.velocity * dt;
    }'''),
    ...para('//',
        r'Two notes on the integrator. First, the plan and the Build '
        r'Spec both say "Verlet integration"; the code and its comment '
        r'say "semi-implicit Euler with velocity damping". The two are '
        r'close relatives and the difference is harmless here, but the '
        r'name in the documents is not what is implemented. Second, '
        r'springs run only in individual mode, because aggregates '
        r'"don’t carry a meaningful edge list" (the guard is in the '
        r'file). Mass is implicitly 1 for every node regardless of '
        r'radius.'),
    blank,
    ...para('//',
        r'The scale of the forces deserves a sober look, because it '
        r'explains design choices elsewhere. Velocity gains force times '
        r'dt per step, and position gains velocity times dt. At the '
        r'30 Hz that main.dart uses, dt is 0.033 s, so a spring '
        r'stretched by 100 px (force 6.0) adds about 0.2 px/s of '
        r'velocity per step, which moves the node about 0.007 px in '
        r'that same step, before the 0.85 damping. This is arithmetic '
        r'from the constants, not a measurement. I also integrated the '
        r'two-node case outside the repository with these constants as '
        r'a rough check: starting 500 px apart, the pair had closed '
        r'only to roughly 437 px after 200 steps (about 6.6 s at 30 '
        r'Hz). Treat that figure as my estimate. The consequence is '
        r'that the spring and gravity forces are gentle drifts. A '
        r'node ends up where it was spawned (next to its owner) and '
        r'where the collision pass pushes it.'),
    blank,
    ...para('//',
        r'The test for spring behaviour is consistent with that '
        r'reading, and also modest. "connected nodes drift toward rest '
        r'length over time" puts two nodes 500 px apart, runs 200 '
        r'steps of 0.016 s, and asserts only that the distance is '
        r'less than 500. The comment above the assertion says "should '
        r'have contracted substantially from 500 toward ~restLength", but '
        r'the assertion does not check "substantially". If the '
        r'springs stopped working but gravity still pulled the pair '
        r'together, the test could still pass. It is worth '
        r'knowing what it does not pin.'),
    ...sec(r'the hard pass: collisions as a constraint'),
    ...code('dart', 'heaplens_flutter/lib/simulation/force_layout.dart · _resolveCollisions and _separatePair (trimmed)', r'''
    final grid = <int, List<int>>{};
    int cellIndex(double x, double y) {
      final cx = (x / kCollisionCellSize).floor();
      final cy = (y / kCollisionCellSize).floor();
...
      const offset = 1 << 20;
      return (cx + offset) * (1 << 21) + (cy + offset);
    }
...
          for (final otherId in bucket) {
            // Process each unordered pair exactly once regardless of
            // which cell/neighbor-offset combination finds it first.
            if (otherId <= id) continue;
            _separatePair(id, otherId);
          }
...
    final minDist = a.radius + b.radius + kCollisionMargin;
    if (dist >= minDist) return; // not overlapping, nothing to do
...
    final overlap = minDist - dist;
    // Inverse-size weighting: a node's own share of the correction is
    // proportional to the *other* node's radius, so the bigger of the two
    // barely moves and the smaller one does most of the separating.
    final totalRadius = a.radius + b.radius;
    final aShare = totalRadius > 0 ? b.radius / totalRadius : 0.5;
    final bShare = totalRadius > 0 ? a.radius / totalRadius : 0.5;

    a.position = a.position + dir * (overlap * aShare);
    b.position = b.position - dir * (overlap * bShare);'''),
    ...para('//',
        r'This is the part of the file that actually keeps the picture '
        r'readable. The doc comment on the method diagnoses why forces '
        r'alone cannot: a soft spring-and-repel system "can settle into '
        r'equilibrium with circles still overlapping", and the comment '
        r'says this is exactly the reported blob bug, because '
        r'disconnected nodes have no spring pulling them apart. So after '
        r'the forces run, a positional '
        r'constraint directly moves any two circles that are closer than '
        r'the sum of their radii plus a 3 px margin. Corrections are '
        r'shared by inverse radius, so a large owner "isn’t shoved '
        r'around by a swarm of tiny children".'),
    blank,
    ...para('//',
        r'The spatial hash replaces an all-pairs scan. The cell size is '
        r'2 * kMaxNodeRadius + kCollisionMargin, which is 79 px. The '
        r'reasoning in the constant’s comment can be checked: two '
        r'circles overlap only if their centres are closer than the sum '
        r'of their radii plus the margin, which is at most 79 px, so '
        r'they can differ by at most one cell on each axis, and '
        r'checking a node’s own cell plus its eight neighbours finds '
        r'every candidate. The cell coordinates are packed into one int '
        r'with an offset of 2^20 so that negative coordinates do not '
        r'collide with positive ones.'),
    blank,
    ...para('//',
        r'One honest qualification. The pass visits each pair once per '
        r'step and does not iterate, so resolving one pair can create '
        r'an overlap with a third node that is only repaired on the '
        r'next step. The words "hard guarantee" describe the '
        r'steady state, not each frame. The tests accordingly let '
        r'the simulation settle (400 steps of 0.016 s) before '
        r'checking, and use a tolerance of half a pixel against the '
        r'sum of the radii, without the 3 px margin.'),
    blank,
    ...para('//',
        r'Two scenarios in the tests were chosen from real failures. '
        r'The first spawns 25 disconnected roots with sizes from 200 to '
        r'7400 bytes, forces them all onto the same point, and demands '
        r'that after settling no two overlap and at least one is more '
        r'than 60 px from the centre ("actually spread into a field, not '
        r'pinned in a tight pile"). The second is a hub with 40 '
        r'children: no overlap, every child between the owner’s radius '
        r'and five spring lengths (400 px) from the owner. The comment '
        r'explains the generous bound: 40 non-overlapping circles '
        r'"physically cannot all pack into a ring at the spring’s '
        r'exact rest length".'),
    ...sec(r'when there are too many: aggregation (ENF9)'),
    ...code('dart', 'heaplens_flutter/lib/simulation/force_layout.dart · _syncAggregation', r'''
  void _syncAggregation() {
    final count = liveNodeCount;
    final shouldAggregate = _aggregated
        ? count >= kAggregationExitThreshold
        : count > kAggregationThreshold;
    if (shouldAggregate == _aggregated) return;
    _aggregated = shouldAggregate;
    _rebuildFromRaw();
  }'''),
    ...para('//',
        r'ENF9 is the requirement name used in the plan: when the live '
        r'node count exceeds 500, draw one aggregate per symbol (summed '
        r'size) instead of one disc per allocation. The reason is cost. '
        r'Repulsion is O(n squared); at 500 nodes that is 124,750 '
        r'pairs per step, thirty steps a second. Above it, the number '
        r'of distinct call-site symbols is a far smaller n. The '
        r'switch point is documented in a banner comment, as the plan '
        r'required, and the test suite pins both sides of the '
        r'boundary: exactly 500 stays individual (500 sim nodes), 501 '
        r'aggregates (10 sim nodes for 10 symbols).'),
    blank,
    ...para('//',
        r'The second version added hysteresis (7498f32). Entering '
        r'aggregated mode still needs strictly more than 500; leaving it '
        r'needs fewer than 450. The commit message gives the reason: '
        r'"churn oscillating near the boundary no longer thrashes '
        r'between modes", because each switch is a full rebuild. A '
        r'test removes nodes down to 500 and checks it stays aggregated; '
        r'another goes to 480 (still aggregated) and then to 440 (back '
        r'to individual).'),
    blank,
    ...code('dart', 'heaplens_flutter/lib/simulation/force_layout.dart · _rebuildFromRaw (trimmed)', r'''
  void _rebuildFromRaw() {
    final fadingSimNodes = <int, SimNode>{
      for (final id in _fadeRemaining.keys)
        if (simNodes.containsKey(id)) id: simNodes[id]!,
    };
    final fadingRemaining = Map<int, double>.from(_fadeRemaining);
...
    simNodes.clear();
    _fadeRemaining.clear();
    _symbolToAggId.clear();
    _aggMembers.clear();
    _nextSyntheticId = preservedMinId < 0 ? preservedMinId - 1 : -1;
...
    simNodes.addAll(fadingSimNodes);
    _fadeRemaining.addAll(fadingRemaining);
  }'''),
    ...para('//',
        r'The first version of this method had a bug that the commit '
        r'message describes precisely: it "was silently dropping any '
        r'SimNode mid-fade at the exact moment the 500-node aggregation '
        r'boundary was crossed, since removeNode() already strips the '
        r'raw id/aggregate membership the instant fade begins". A fading '
        r'node exists only in simNodes and _fadeRemaining, so rebuilding '
        r'from _rawNodes forgot it. The fix snapshots the fading nodes '
        r'first and restores them last, and also moves the next '
        r'synthetic id below any preserved one so a fresh aggregate id '
        r'cannot collide with a fading old one. The test adds 500 nodes, '
        r'starts a fade on one, adds two more to cross 500, and checks '
        r'the fading node survives with 0 < fade <= 1 and is deleted '
        r'after 20 further steps of 0.1.'),
    blank,
    ...para('//',
        r'Aggregates live in the same simNodes map under synthetic '
        r'negative ids, which is why the tests identify them by "any '
        r'negative-id key". An emptied bucket fades out as freed (grey), '
        r'which the code comments call "the least-surprising fade '
        r'color".'),
    ...sec(r'a gap: aggregates are simulated, but nothing draws them'),
    ...para('//',
        r'Reading the whole UI side by side with this file turns up a '
        r'gap, and it is better stated than hidden. Outside the tests, '
        r'nothing reads isAggregated or aggregateCount. The painter in '
        r'widgets/graph_canvas.dart looks up a SimNode for each real '
        r'NodeDto by its real id, and in aggregated mode simNodes is '
        r'keyed by negative synthetic ids. By that reading, with more '
        r'than 500 live nodes the canvas would paint its background '
        r'grid and no nodes, while the physics quietly runs on the '
        r'aggregates. The plan’s "count badge" does not exist either. '
        r'The Map view, which does not use the layout, is unaffected. '
        r'I reached this by reading the code, not by running the app '
        r'with 500 live nodes, so it is an inference. What is certain '
        r'is that the aggregation behaviour is tested only at the '
        r'ForceLayout level, and no widget test paints in aggregated '
        r'mode.'),
    ...sec(r'a fixed centre'),
    ...para('//',
        r'ForceLayout takes centerX and centerY in its constructor, '
        r'defaulting to (400, 300), and forceLayoutProvider constructs '
        r'it with the defaults. The gravity well and owner-less spawns '
        r'are therefore fixed in the layout’s own coordinates. On a wide '
        r'window that point is far from the middle of the viewport; '
        r'graph_canvas.dart compensates by translating the view, and '
        r'its comments record a measurement from a real screenshot: a '
        r'1540 px graph area with the well fixed at x = 400 put the '
        r'cluster in roughly the left quarter.'),
    ...sec(r'what changed over time'),
    ...pt('//', r'9584b71, 2026-07-06',
        r'first version: owner-aware spawn, radius-only updates, '
        r'simulated-clock fades, ENF9 aggregation above 500. 451 lines '
        r'and 8 tests.'),
    ...pt('//', r'7498f32, 2026-07-06',
        r'preserve mid-fade nodes across rebuilds; add the 450 exit '
        r'threshold.'),
    ...pt('//', r'23b80e4, 2026-07-06',
        r'resetFrom, for snapshots (29 lines).'),
    ...pt('//', r'fea8519, 2026-07-06',
        r'lastKnownState, so fades are visible (27 lines).'),
    ...pt('//', r'1cfb7f9, 2026-07-19',
        r'195 lines: log radius, radius-aware repulsion, the collision '
        r'pass with its spatial hash, new gravity and radius limits.'),
    ...sec(r'limits'),
    ...pt('//', r'repulsion is O(n squared)',
        r'with Map lookups and a Vector2 allocation per pair. Fine at '
        r'500, and that is exactly why the aggregation cap exists.'),
    ...pt('//', r'owner lookup is a scan',
        r'_findOwnerId walks every node per added node. Cheap per diff, '
        r'quadratic on a 100-node batch.'),
    ...pt('//', r'physics is frame-rate dependent',
        r'damping is applied per step, not per second, so the feel '
        r'depends on the tick rate main.dart chooses.'),
    ...pt('//', r'one pass of collisions',
        r'settles over frames, not within one.'),
    ...pt('//', r'aggregates are not drawn',
        r'see the gap section above.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
