import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/widgets/insights_panel.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'insights_panel.dart — a findings list with a detail pane'),
    cm('//', r'where computeInsights meets the screen'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'two-column Insights & Suggestions panel under the graph'),
    kv('language', r'Dart / Flutter'),
    kv('size', r'198 lines; one commit (1cfb7f9, 2026-07-19)'),
    kv('reads', r'insights/insight_rules.dart, graphProvider'),
    kv('writes', r'selectedNodeIdProvider'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'insight_rules.dart computes what is worth saying. This file '
        r'says it. The class comment describes the panel in one '
        r'sentence: "deterministic, rule-based observations computed '
        r'from the graph’s current node map ... not AI, not a daemon '
        r'round-trip. Two columns: a selectable list on the left, full '
        r'detail + suggestion on the right."'),
    blank,
    ...para('//',
        r'It sits in the lower part of the centre column in main.dart, '
        r'below the graph or map, taking two parts of the five the '
        r'column splits into (flex 2 against the graph’s flex 3), and '
        r'always full width of that column.'),
    ...sec(r'selection that survives recomputation'),
    ...code('dart', 'heaplens_flutter/lib/widgets/insights_panel.dart · _InsightsPanelState.build (trimmed)', r'''
    ref.watch(graphProvider);
    final nodes = ref.read(graphProvider.notifier).nodes;
    final insights = computeInsights(nodes);

    Insight? selected;
    for (final i in insights) {
      if (i.id == _selectedInsightId) {
        selected = i;
        break;
      }
    }
    // The previously-selected insight resolved (e.g. the leak was fixed,
    // or the hot cluster cooled down) — fall back to the first remaining
    // insight rather than showing a stale detail pane for something that
    // no longer applies.
    selected ??= insights.isEmpty ? null : insights.first;'''),
    ...para('//',
        r'The panel recomputes every finding on every graph revision. '
        r'That is cheap, as noted on the rules page, but it means '
        r'the list is a fresh set of objects each time. The panel keeps '
        r'only a string, _selectedInsightId, and looks the finding up '
        r'again in the new list, which is why Insight.id is a stable key '
        r'rather than a display value.'),
    blank,
    ...para('//',
        r'The fallback comment describes a user-facing case: a leak '
        r'fixed in the monitored program makes its finding disappear. '
        r'The detail pane then moves to the first remaining finding, or '
        r'to "No insight selected" when none remain, instead of showing '
        r'a stale explanation. One subtlety: the stored id is not '
        r'cleared when the fallback applies, so if the same finding '
        r'reappears later it becomes the selection again.'),
    ...sec(r'cross-referencing the graph'),
    ...code('dart', 'heaplens_flutter/lib/widgets/insights_panel.dart · selecting a finding', r'''
                          onSelect: (insight) {
                            setState(() => _selectedInsightId = insight.id);
                            if (insight.implicatedNodeId != null) {
                              ref.read(selectedNodeIdProvider.notifier).state =
                                  insight.implicatedNodeId;
                            }
                          },'''),
    ...para('//',
        r'Clicking a finding does two things. It selects it in the '
        r'panel and it writes the implicated node’s id to '
        r'selectedNodeIdProvider, the same provider the graph canvas '
        r'and the memory map write on a tap. The node-detail panel, the '
        r'size sparkline and the selection ring in the graph all read '
        r'that provider, so one click on "Probable leak at ..." '
        r'highlights the biggest leaked allocation, shows its fields and '
        r'draws its size history. The class comment says as much: "so '
        r'this panel and the graph/node-detail panel stay '
        r'cross-referenced".'),
    blank,
    ...para('//',
        r'It is a one-way link. Tapping a node in the graph does not '
        r'select a finding, and nothing scrolls the canvas to bring the '
        r'node into view. Because the canvas is a pannable surface, the '
        r'selected node can be selected and off-screen at once.'),
    ...sec(r'severity gets its own colours'),
    ...code('dart', 'heaplens_flutter/lib/widgets/insights_panel.dart · kInsightSeverityColors', r'''
/// Severity -> color. Deliberately its own mapping (not reused from
/// `node_colors.dart`'s state-color language) — an insight's severity is
/// a different axis than a node's Healthy/Orphan/Hot state, even though
/// critical/warning happen to share the same [XynorashTheme] coral/orange
/// hues as orphan/hot for the same "how urgent" intuition.
const Map<InsightSeverity, Color> kInsightSeverityColors = {
  InsightSeverity.critical: XynorashTheme.coral,
  InsightSeverity.warning: XynorashTheme.orange,
  InsightSeverity.info: XynorashTheme.teal,
};'''),
    ...para('//',
        r'The comment is a small lesson in naming a design decision. '
        r'Two maps with overlapping values invite someone to "tidy" them '
        r'into one. The comment explains why they are separate: '
        r'severity and node state are different axes, and the shared '
        r'hues are a coincidence of the "how urgent" intuition. '
        r'Note one consequence: info is teal, the same teal as healthy '
        r'nodes, so a dominant-consumer finding does not read as a '
        r'problem.'),
    ...sec(r'the list and the detail'),
    ...pt('//', r'the list',
        r'a ListView.builder of InkWell rows, each a coloured dot and a '
        r'one-line title that ellipsises. The selected row has an '
        r'8 percent white wash. Rows carry the key insightItem_ plus the '
        r'id, which lets tests address them once they exist.'),
    ...pt('//', r'the detail',
        r'a scrollable column with the severity dot, the title in bold '
        r'and the full explanation in 13 px dim text. The space '
        r'between is empty: there is no separate suggestion field, '
        r'because the suggestion is part of the sentence the rule '
        r'builds ("check whether entries are ever removed").'),
    ...pt('//', r'the empty state',
        r'an EmptyState with a check icon and "No active insights". '
        r'This follows the app’s rule that a panel is never blank; '
        r'every panel states why it is empty.'),
    ...pt('//', r'the frame',
        r'HudFrame draws corner brackets around the whole panel and the '
        r'header uses XynorashTheme.bracketLabel, which uppercases the '
        r'title and wraps it as "[ INSIGHTS & SUGGESTIONS ]".'),
    ...sec(r'testing and limits'),
    ...para('//',
        r'No test targets this widget by name. The panel is built '
        r'whenever widget_test.dart pumps the full app, which only '
        r'proves it does not throw. The rule-level gaps are described '
        r'on the insight_rules.dart page.'),
    ...pt('//', r'the list is not sorted by size or recency',
        r'order follows the rule order described there.'),
    ...pt('//', r'no dismiss or snooze',
        r'a finding stays until the data stops producing it.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
