import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/widgets/target_status_banner.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'target_status_banner.dart — telling the user why it looks empty'),
    cm('//', r'a banner with a headline, a tooltip of raw counts and one button'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'renders the TargetDiagnosis as a strip under the control bar'),
    kv('language', r'Dart / Flutter'),
    kv('size', r'93 lines, 4 widget tests'),
    kv('history', r'2 commits: 0edc728 (2026-07-17), ead62bb (2026-07-22)'),
    kv('test', r'test/widgets/target_status_banner_test.dart'),
    kv('reads', r'providers/target_diagnostics_provider.dart'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'The provider decides what is true about the target; this '
        r'widget decides how loudly to say it. The distinction '
        r'matters, because the most common state is that nothing is '
        r'wrong. The banner renders nothing at all while the status '
        r'is capturing, so the healthy case costs no pixels, and the '
        r'interface only speaks when it has a reason to.'),
    ...sec(r'color is meaning'),
    ...code('dart', 'heaplens_flutter/lib/widgets/target_status_banner.dart · lines 9-29', r'''
/// Colors for each non-[TargetStatus.capturing] state — [noEvents] reads as
/// a caution amber (target may simply be idle, not necessarily a problem),
/// [noEdges]/[unsymbolized] read as an informational blue (capturing is
/// working; the limitation is inherent to the target, not an error).
/// [noEdgesOrphaned] reuses the shared orphan coral ([kNodeStateColors]) —
/// same semantic as every other orphan indicator in the app, since this
/// state literally means "most of the graph is orphaned", not a capture
/// problem.
const Map<TargetStatus, Color> _kBannerColors = {
  TargetStatus.noEvents: Color(0xFFB08900),
  TargetStatus.noEdges: Color(0xFF2D6CA6),
  TargetStatus.unsymbolized: Color(0xFF2D6CA6),
  TargetStatus.noEdgesOrphaned: XynorashTheme.coral,
};

const Map<TargetStatus, IconData> _kBannerIcons = {
  TargetStatus.noEvents: Icons.hourglass_empty,
  TargetStatus.noEdges: Icons.hub_outlined,
  TargetStatus.unsymbolized: Icons.hub_outlined,
  TargetStatus.noEdgesOrphaned: Icons.link_off,
};'''),
    ...para('//',
        r'Each non-capturing status gets a color and an icon, and '
        r'the comment explains the semantic choice. No events reads '
        r'as a caution amber, since the target may simply be idle '
        r'and that is not a fault. No edges and unsymbolized read as '
        r'informational blue: capturing works, and the limitation '
        r'belongs to the target, not to an error. The fourth, '
        r'noEdgesOrphaned, reuses the shared orphan coral from the '
        r'node color map, because this state literally means most of '
        r'the graph is orphaned, and that must look like every other '
        r'orphan indicator in the app. The two blues and the amber '
        r'are raw values here, outside the XynorashTheme palette.'),
    ...para('//',
        r'The icons are the quiet half of the same idea: an '
        r'hourglass for waiting, a hub for a graph that has not '
        r'formed, a broken link for the orphaned case.'),
    ...sec(r'dual-level legibility'),
    ...code('dart', 'heaplens_flutter/lib/widgets/target_status_banner.dart · lines 31-54', r'''
/// Honest target-diagnostic banner: explains *why* the graph looks empty or
/// edgeless instead of leaving the user staring at a blank canvas. Renders
/// nothing for [TargetStatus.capturing] (the common, healthy case).
///
/// Dual-level legibility: the plain-language [TargetDiagnosis.message] is
/// what's on screen; the raw counts it was derived from (events, symbols
/// resolved/unresolved, nodes, edges) are one hover away via [Tooltip] and
/// also mirrored into [DebugOverlay] — never lost, never required reading
/// to understand the banner's headline claim.
class TargetStatusBanner extends ConsumerWidget {
  const TargetStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnosis = ref.watch(targetDiagnosticsProvider);
    if (diagnosis.status == TargetStatus.capturing) {
      return const SizedBox.shrink();
    }

    final color = _kBannerColors[diagnosis.status]!;
    final icon = _kBannerIcons[diagnosis.status]!;
    final showMapViewAction = diagnosis.status == TargetStatus.noEdges ||
        diagnosis.status == TargetStatus.unsymbolized ||
        diagnosis.status == TargetStatus.noEdgesOrphaned;'''),
    ...para('//',
        r'The doc comment names the pattern the whole UI follows: '
        r'the plain-language message is what is on screen, and the '
        r'raw counts it came from are one hover away. The headline '
        r'is diagnosis.message, which the model composes from fixed '
        r'sentences, such as the one that names the target and says '
        r'no heap activity was observed. Nothing technical needs to '
        r'be understood to read it. The counts live in a tooltip: '
        r'events, symbols resolved out of total, nodes and edges. A '
        r'person can check the claim against the evidence without '
        r'opening a debugger, and the same numbers are mirrored into '
        r'the debug overlay, as the comment says.'),
    ...sec(r'the button'),
    ...code('dart', 'heaplens_flutter/lib/widgets/target_status_banner.dart · lines 56-92', r'''
    return Material(
      key: const Key('targetStatusBanner'),
      color: color.withValues(alpha: 0.16),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.4))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Tooltip(
          message: 'events=${diagnosis.eventsReceived}  '
              'symbols=${diagnosis.symbolsResolved}/'
              '${diagnosis.symbolsResolved + diagnosis.hexFallback} resolved  '
              'nodes=${diagnosis.nodeCount}  edges=${diagnosis.edgeCount}',
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  diagnosis.message!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              if (showMapViewAction)
                TextButton(
                  key: const Key('switchToMapViewButton'),
                  onPressed: () {
                    ref.read(viewModeProvider.notifier).state = ViewMode.memoryMap;
                  },
                  child: const Text('Switch to Map view'),
                ),
            ],
          ),
        ),
      ),
    );
  }'''),
    ...para('//',
        r'Three of the four statuses show a Switch to Map view '
        r'action, and no events does not. The distinction is by '
        r'cause: with no events there is nothing to show in any '
        r'view, while with allocations arriving but no edges the '
        r'memory map is still informative. The message text for '
        r'those states says the same thing, allocation sizes and '
        r'growth are still available in the Map view, and the button '
        r'makes the sentence actionable by writing '
        r'ViewMode.memoryMap to viewModeProvider. The widget has '
        r'stable keys, targetStatusBanner on the Material and '
        r'switchToMapViewButton on the action, which the tests use.'),
    ...para('//',
        r'The banner is a Material with a 16 percent alpha tint and '
        r'a bottom border at 40 percent, the same '
        r'translucent-fill-plus-hairline treatment the node chip '
        r'uses. A bang operator on diagnosis.message is safe because '
        r'that field is null only when the status is capturing, and '
        r'the early return has already handled that case.'),
    ...sec(r'where it sits'),
    ...para('//',
        r'In main.dart the banner is the second child of the page '
        r'column, directly under the ribbon and above the row that '
        r'holds the center view and the right rail. It sits above '
        r'the graph rather than over it, so it never hides nodes.'),
    ...sec(r'edge cases'),
    ...pt('//', r'stale until a message',
        r'the banner changes only when the provider recomputes, '
        r'which is on a message. A status that should clear because '
        r'the user attached a different target clears when the next '
        r'message arrives.'),
    ...pt('//', r'long messages',
        r'the text is in an Expanded with no max lines, so the '
        r'orphaned message wraps and the strip grows taller. The '
        r'strip has no fixed height.'),
    ...pt('//', r'tooltip target',
        r'the Tooltip wraps the whole row, so hovering anywhere on '
        r'the strip shows the counts, including over the button.'),
    ...pt('//', r'a wording gap',
        r'the plain noEdges message blames the target for lacking '
        r'debug symbols even though only the unsymbolized status has '
        r'a hex-ratio measurement behind it. The noEdges fallback '
        r'therefore speaks with more certainty than its evidence; '
        r'the orphan fix removed the worst case of that, not all of '
        r'it.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'Four widget tests with a stream controller driving a real '
        r'provider tree. Renders nothing while capturing, asserting '
        r'the banner key finds nothing. Shows the no-events message '
        r'once past the window, with the target name and pid. The '
        r'no-edges banner offers Switch to Map view, and tapping it '
        r'moves viewModeProvider from graph. And the regression from '
        r'ead62bb: all nodes orphaned with symbols fully resolved '
        r'shows the orphan-explained message, not the symbol one, '
        r'with text containing currently orphaned, no text '
        r'containing lacks the debug symbols, and still the map '
        r'button.'),
    ...sec(r'history'),
    ...pt('//', r'0edc728 (2026-07-17)',
        r'feat(target-diagnostics): honest target-status banner. '
        r'Adds the file with three colored states and the map '
        r'action.'),
    ...pt('//', r'ead62bb (2026-07-22)',
        r'fix(ui): stop blaming missing debug symbols for an '
        r'orphan-caused low edge ratio. Adds the noEdgesOrphaned '
        r'entries to the color and icon maps, and includes it in the '
        r'map button condition.'),
  ],
);
