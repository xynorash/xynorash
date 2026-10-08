import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/widgets/graph_canvas.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'graph_canvas.dart — drawing the ownership graph'),
    cm('//', r'a pannable virtual canvas and a painter that never lies'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'renders SimNodes + NodeDtos; tap-to-select; pan and zoom'),
    kv('language', r'Dart / Flutter (CustomPainter, InteractiveViewer)'),
    kv('size', r'530 lines; 7 commits, 2026-07-06 to 2026-07-19'),
    kv('tested by', r'test/widgets/graph_canvas_test.dart (7 widget tests)'),
    kv('reads', r'ForceLayout.simNodes, graphProvider nodes, 3 filter providers'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'force_layout.dart knows where every circle is and how big it '
        r'is. graph_provider.dart knows what each node means: its '
        r'state, its edges, whether it is live. Neither can draw. This '
        r'file joins the two, by node id, and turns them into pixels: '
        r'edges first, then nodes on top, a pulsing ring around orphans, '
        r'a ring around the selected node, and a fading ghost for a '
        r'node that has just gone.'),
    blank,
    ...para('//',
        r'It also owns the interaction. A tap selects the node under '
        r'the pointer, panning moves the view, three small buttons '
        r'zoom. The selection it writes (selectedNodeIdProvider) is what '
        r'the node-detail panel and the sparkline read.'),
    blank,
    ...para('//',
        r'The most important sentence about this file is in a test, '
        r'not in the code. It is the title of a regression test added '
        r'on 2026-07-07: "77 tests passed with a blank canvas, none of '
        r'them asserted anything was actually painted". The story of '
        r'that sentence shapes the end of this page.'),
    ...sec(r'two data sources, joined by id'),
    ...code('dart', 'heaplens_flutter/lib/widgets/graph_canvas.dart · GraphCanvas.build', r'''
    // Watched purely to know *when* to rebuild/repaint; read the fresh node
    // map below rather than caching it across revisions.
    ref.watch(graphProvider);
    final nodes = ref.read(graphProvider.notifier).nodes;
    final selectedId = ref.watch(selectedNodeIdProvider);
...
    final minSize = ref.watch(minSizeFilterProvider);
    final orphanOnly = ref.watch(orphanOnlyFilterProvider);
    final symbolSearchLower =
        ref.watch(symbolSearchFilterProvider).toLowerCase();

    final visibleNodes = <int, NodeDto>{
      for (final entry in nodes.entries)
        if (_passesRenderFilters(
          entry.value,
          minSize: minSize,
          orphanOnly: orphanOnly,
          symbolSearchLower: symbolSearchLower,
        ))
          entry.key: entry.value,
    };'''),
    ...para('//',
        r'The widget watches the revision int purely as a trigger and '
        r'reads the data fresh, the contract graph_provider.dart '
        r'documents. The filtered map is passed to the painter as a '
        r'ready-made value, so the painter itself, by its own doc '
        r'comment, "has no filtering opinion".'),
    blank,
    ...para('//',
        r'The three filters (minimum size, orphans only, substring '
        r'search) come from the ribbon. For a while they did nothing '
        r'in this view. fea8519 fixed it: the graph is the default '
        r'view, but the filters had only been wired into the memory '
        r'map, "so these controls previously had no visible effect '
        r'unless the user switched to the memory map". The predicate '
        r'_passesRenderFilters is kept "in exact lockstep" with the '
        r'memory map’s copy of the same rules. Notice that it is '
        r'copied, not shared: widgets/memory_map.dart repeats the '
        r'four conditions inline. The comment states the intent to '
        r'keep them identical; nothing enforces it except the two '
        r'files’ tests.'),
    ...sec(r'a virtual canvas, centred by hand'),
    ...code('dart', 'heaplens_flutter/lib/widgets/graph_canvas.dart · the viewer and the centring', r'''
  void _scheduleCentering(Size viewportSize) {
    if (viewportSize.isEmpty || viewportSize == _lastCenteredSize) return;
    _lastCenteredSize = viewportSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dx = viewportSize.width / 2 - widget.layout.centerX;
      final dy = viewportSize.height / 2 - widget.layout.centerY;
      final transform = Matrix4.translationValues(dx, dy, 0);
      _initialTransform = transform;
      setState(() => _transformController.value = transform);
    });
  }
...
          InteractiveViewer(
            key: const Key('graphScrollView'),
            transformationController: _transformController,
            constrained: false,
            panEnabled: true,
            scaleEnabled: false,
            boundaryMargin: const EdgeInsets.all(400),
            minScale: _minScale,
            maxScale: _maxScale,
            child: SizedBox('''),
    ...para('//',
        r'Three layout bugs are encoded here, each with a comment '
        r'recording the symptom.'),
    ...pt('//', r'nodes pushed off-screen were unreachable',
        r'the first version sized the CustomPaint to exactly the '
        r'viewport, so any node the layout pushed outside it was '
        r'"clipped, with no way to scroll to it". The canvas is now a '
        r'fixed 1600 by 1200 virtual surface (kGraphVirtualWidth and '
        r'kGraphVirtualHeight), panned by an InteractiveViewer with '
        r'constrained: false.'),
    ...pt('//', r'the graph hugged the left edge',
        r'the force layout’s gravity well sits at a fixed point '
        r'(400, 300), which is not the middle of a wide window. The '
        r'comment cites "a real screenshot": a graph area about 1540 px '
        r'wide with the well at x = 400 put "the whole cluster in '
        r'roughly the left quarter". The fix translates the view so '
        r'the well lands in the viewport centre.'),
    ...pt('//', r'resizing drifted it off-centre again',
        r'centring ran once, on first layout. Growing the window left '
        r'the old offset in place. It now re-runs whenever the viewport '
        r'size changes, tracked in _lastCenteredSize, and the comment '
        r'accepts the cost: a resize re-centres "even if the user had '
        r'panned away", a deliberate trade for "predictable centering".'),
    blank,
    ...para('//',
        r'Zoom is the odd one out. scaleEnabled is false, which turns '
        r'off pinch, trackpad and wheel zoom, and zoom is driven only '
        r'by the plus, minus and reset buttons through the shared '
        r'TransformationController. The comment gives two reasons: '
        r'predictability, and that gesture zoom would fight the two-axis '
        r'panning gestures. It also records a subtlety that cost time to '
        r'learn. The viewer clamps any value assigned to its '
        r'controller into its own configured scale bounds, so leaving '
        r'minScale and maxScale at their defaults would "silently '
        r'discard the buttons’ work". The bounds are 0.5 to 3.0, with '
        r'a step of 1.25. Reset goes back to the centred transform, '
        r'not to the identity, which "would snap back to the same '
        r'off-center position".'),
    ...sec(r'hit-testing a moving target'),
    ...code('dart', 'heaplens_flutter/lib/widgets/graph_canvas.dart · _handleTapUp (trimmed)', r'''
    int? bestId;
    var bestDist = double.infinity;
    for (final entry in widget.layout.simNodes.entries) {
      final sim = entry.value;
      final dist = (sim.position - tapPos).length;
      if (dist <= sim.radius && dist < bestDist) {
        bestDist = dist;
        bestId = entry.key;
      }
    }
...
    if (bestId != null) {
      final nodes = ref.read(graphProvider.notifier).nodes;
      final node = nodes[bestId];
      if (node != null &&
          _passesRenderFilters(
            node,
            minSize: ref.read(minSizeFilterProvider),
            orphanOnly: ref.read(orphanOnlyFilterProvider),
            symbolSearchLower:
                ref.read(symbolSearchFilterProvider).toLowerCase(),
          )) {
        ref.read(selectedNodeIdProvider.notifier).state = bestId;
      }
    }'''),
    ...para('//',
        r'The hit test walks the SimNodes, not the painted circles, and '
        r'picks the closest centre among those whose radius contains '
        r'the tap. Because the GestureDetector sits inside the '
        r'InteractiveViewer’s child, the tap position is already in '
        r'scene coordinates, the same space the simulation uses, so '
        r'pan and the centring transform need no inverse mapping.'),
    blank,
    ...para('//',
        r'The second half is a guard added in 7b3b9c7. '
        r'A SimNode can exist without a NodeDto: right after a '
        r'removal it is a fading ghost. Selecting it would put an id in '
        r'selectedNodeIdProvider that has no data behind it. The guard '
        r'requires a node in the map, and the later filter work added '
        r'a second requirement, that the node passes the current '
        r'filters, because "a node hidden by a filter shouldn’t be '
        r'selectable via tap either". Two tests pin the two halves: '
        r'one taps a pinned SimNode with no NodeDto and expects no '
        r'selection, and one taps a node under a minimum-size filter '
        r'and expects none, while the larger node stays tappable.'),
    ...sec(r'the painter'),
    ...code('dart', 'heaplens_flutter/lib/widgets/graph_canvas.dart · GraphPainter._paintNodes (trimmed)', r'''
      final center = Offset(sim.position.x, sim.position.y);
      final baseColor = colorForState(node.state);
      final alpha = node.state == NodeStateDto.freed ? sim.fade : 1.0;
      final clampedAlpha = alpha.clamp(0.0, 1.0);
...
      final glowPaint = Paint()
        ..color = baseColor.withValues(alpha: 0.30 * clampedAlpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sim.radius * 0.55);
      canvas.drawCircle(center, sim.radius * 1.1, glowPaint);

      final fillPaint = Paint()..color = baseColor.withValues(alpha: clampedAlpha);
      canvas.drawCircle(center, sim.radius, fillPaint);

      if (node.state == NodeStateDto.orphan) {
...
        final ringRadius = sim.radius + pulseValue * (sim.radius * 0.8 + 6);
        final ringAlpha = (1.0 - pulseValue).clamp(0.0, 1.0);
...
        canvas.drawCircle(center, ringRadius, ringPaint);
      }

      if (id == selectedId) {
...
        canvas.drawCircle(center, sim.radius + 3, selectionPaint);
      }'''),
    ...para('//',
        r'Paint order, back to front: the faint background grid, the '
        r'edges, then for every node a blurred glow, a crisp fill, an '
        r'orphan ring if the node is an orphan, and a selection ring '
        r'if it is selected, and finally the fading ghosts. The '
        r'order is not decoration; the last widget test depends on '
        r'it, as the testing section shows.'),
    ...pt('//', r'colour is state, always',
        r'the fill is colorForState(node.state) from node_colors.dart, '
        r'the one place the healthy, orphan, hot and freed palette is '
        r'defined. The commit that introduced the memory map pulled it '
        r'out of this file (07b2011) for exactly that reason.'),
    ...pt('//', r'the orphan pulse runs on the render clock',
        r'a 1200 ms AnimationController, repeating, supplies a 0 to 1 '
        r'phase. The ring grows outward by 0.8 of the radius plus 6 px '
        r'while its alpha falls from 1 to 0. The plan was explicit '
        r'that it should animate "off the render clock, not the '
        r'physics clock", which is why the physics timer in main.dart '
        r'does not drive repaints.'),
    ...pt('//', r'the selection ring is additive',
        r'selection draws a cyan glow and a cyan stroke over the '
        r'state colour. A regression test added in ead62bb protects '
        r'the rule. Its suspicion was that a selected orphan lost its '
        r'coral fill; the commit says that "did not reproduce on '
        r'inspection", so the test only guards the property.'),
    ...pt('//', r'the grid is a ruler',
        r'48 px lines at an alpha of 0.035. The comment says it is "a '
        r'scale reference for the canvas, the same reason a cockpit '
        r'display or oscilloscope grids its background, not decoration '
        r'for its own sake".'),
    blank,
    ...code('dart', 'heaplens_flutter/lib/widgets/graph_canvas.dart · _paintFadingGhosts', r'''
  void _paintFadingGhosts(Canvas canvas) {
    for (final entry in simNodes.entries) {
      final id = entry.key;
      if (nodes.containsKey(id)) continue; // already painted above
      final sim = entry.value;
      final lastState = sim.lastKnownState;
      if (lastState == null) continue; // not a fading ghost

      final center = Offset(sim.position.x, sim.position.y);
      final baseColor = colorForState(lastState);
      final fillPaint = Paint()
        ..color = baseColor.withValues(alpha: sim.fade.clamp(0.0, 1.0));
      canvas.drawCircle(center, sim.radius, fillPaint);
    }
  }'''),
    ...para('//',
        r'The ghost pass is the visible half of a fix described in '
        r'force_layout.dart. When the daemon removes a node, the same '
        r'step in main.dart both deletes its NodeDto from the '
        r'provider’s map and starts the layout’s one-second fade. The '
        r'main painter loop needs a NodeDto to paint anything, so the '
        r'fade was running off-screen. The doc comment says it plainly: '
        r'"Without this pass, SimNode.fade would count down entirely '
        r'off-screen". The ghost reads its colour from the '
        r'lastKnownState the layout captured, and its alpha from the '
        r'fade. A widget test removes a node, steps the layout half a '
        r'second, and asserts the SimNode is still present with 0 < '
        r'fade < 1 and that the widget paints without throwing.'),
    blank,
    ...para('//',
        r'The painter’s shouldRepaint returns true unconditionally, '
        r'and the AnimationBuilder rebuilds it every frame because of '
        r'the orphan pulse. Each frame therefore repaints the whole '
        r'1600 by 1200 surface, including a fresh Paint with a blur '
        r'mask for every node’s glow. That is simple and correct, and '
        r'the RepaintBoundary at the top keeps it from invalidating '
        r'other panels, but I found no frame-time measurement for it '
        r'in the repository.'),
    ...sec(r'the blank canvas that tests could not see'),
    ...para('//',
        r'The M5 milestone was merged with 77 passing tests and a '
        r'live run recorded as successful. Then a person looked at the '
        r'running app and saw only the control bar: no nodes. The '
        r'plan’s addendum describes the situation and the decision to '
        r'treat the human observation as overriding the merged '
        r'acceptance, because all the earlier evidence was "indirect".'),
    blank,
    ...para('//',
        r'The investigation produced three artefacts. First, a '
        r'standing debug overlay (ac78534) that prints, on screen, each '
        r'stage of the pipeline from socket status to the timestamp of '
        r'the last paint, and for this file one static field, '
        r'GraphPainter.lastPaintAt, so the overlay can tell whether the '
        r'paint pipeline is being driven at all. Second, a slow demo '
        r'producer, because the live trace found "no code-level '
        r'rendering bug": the only existing producer finished its whole '
        r'allocate-then-free cycle in under two seconds, so a human '
        r'checking afterwards saw an empty canvas, correctly. Third, the '
        r'regression test (091d71f), which adds one line to this file, '
        r'a Key on the CustomPaint so the test can find it.'),
    blank,
    ...para('//',
        r'The commit message of that test records how it was '
        r'validated: "Sanity-checked by temporarily commenting out the '
        r'node drawCircle call: the new test fails exactly as expected". '
        r'The lesson, written into the test title, is that a suite of '
        r'tests asserting "no exception" and "tap selects" can pass '
        r'around a dead render path. flutter_test’s paints matcher '
        r'records the real drawing calls, and the test requires '
        r'drawCircle to be absent for an empty graph and present once '
        r'a node arrives.'),
    ...sec(r'a gap, and a nuance'),
    ...pt('//', r'above 500 live nodes the painter finds nothing to draw',
        r'when the layout is aggregated its SimNodes are keyed by '
        r'negative synthetic ids, but this painter looks each real '
        r'NodeDto up by its real id and skips it when no SimNode '
        r'exists. By reading the code, an aggregated graph paints the '
        r'grid and nothing else, and no widget uses isAggregated. '
        r'This is an inference, not an observation; see the '
        r'force_layout.dart page.'),
    ...pt('//', r'edges can point at filtered nodes',
        r'the edge loop iterates the filtered map, but looks the '
        r'target up in simNodes without checking the filter. An edge '
        r'from a visible owner to a filtered-out child is still drawn, '
        r'ending at the hidden child’s position. Again from reading, '
        r'not from a test.'),
    ...pt('//', r'a static for diagnostics',
        r'lastPaintAt is a static mutable DateTime, written on every '
        r'paint. It is shared by every painter instance; fine for one '
        r'canvas, and documented as diagnostic-only.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'graph_canvas_test.dart has seven widget tests: paints a small '
        r'graph without throwing; tap selects the node at a known '
        r'position; tap on a ghost with no NodeDto selects nothing; a '
        r'removed node keeps painting while it fades; the minimum-size '
        r'filter hides a node from painting and hit-testing without '
        r'changing the node map; the paints-a-circle regression; and '
        r'the selected orphan keeps its coral fill and gains the cyan '
        r'ring. See the test’s own page for the details of the paints '
        r'sequences.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
