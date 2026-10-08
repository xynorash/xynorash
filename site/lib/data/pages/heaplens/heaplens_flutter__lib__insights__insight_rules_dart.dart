import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/insights/insight_rules.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'insight_rules.dart — plain-language findings from the graph'),
    cm('//', r'three deterministic rules, no AI, no round-trip'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'turns the node map into a short list of actionable findings'),
    kv('language', r'Dart (pure function, no widgets)'),
    kv('size', r'118 lines; one commit (1cfb7f9, 2026-07-19)'),
    kv('rendered by', r'widgets/insights_panel.dart'),
    kv('tests', r'none of its own (see the testing section)'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'A graph full of coloured circles shows that something is '
        r'wrong. It does not say what to do about it. The UI refresh '
        r'added a panel called Insights & Suggestions, and this file is '
        r'its engine: a function from the current node map to a list of '
        r'findings, each with a severity, a one-line title, a longer '
        r'explanation with a concrete suggestion, and the node it is '
        r'about.'),
    blank,
    ...para('//',
        r'The doc comment draws the boundary in three clauses: the '
        r'findings are "deterministic, rule-based", with "no AI, no '
        r'daemon round-trip", and computed "purely" from data the client '
        r'already holds. The last clause is the important one for '
        r'architecture. The file "never re-derives φ or the '
        r'orphan/hot classification itself, only reads it". The '
        r'daemon decides which nodes are orphaned or hot (phi and the '
        r'anomaly sweep live in crates/heaplens-daemon); the UI turns '
        r'those verdicts into advice. Duplicating the classification '
        r'client-side would create two sources of truth.'),
    ...sec(r'the shape of a finding'),
    ...code('dart', 'heaplens_flutter/lib/insights/insight_rules.dart · Insight', r'''
enum InsightSeverity { critical, warning, info }
...
class Insight {
  const Insight({
    required this.id,
    required this.severity,
    required this.title,
    required this.detail,
    required this.implicatedNodeId,
  });

  /// Stable key (not a display value) so the selected-insight provider can
  /// survive a rebuild that recomputes the same insight from fresh data.
  final String id;
  final InsightSeverity severity;

  /// Short list-item title (severity dot + this, in the left column).
  final String title;

  /// Full explanation + concrete suggestion, shown in the right column.
  final String detail;'''),
    ...para('//',
        r'The id field carries the weight. Insights are recomputed '
        r'from scratch on every graph revision, up to thirty times a '
        r'second, so any identity based on list position would flicker. '
        r'The id is built from the finding’s subject: orphan:symbol, '
        r'hot:node-id, dominant:node-id. The panel stores the selected id, '
        r'not an index, and falls back to the first finding when the '
        r'selected one stops applying.'),
    ...sec(r'rule one: orphans, grouped by call site'),
    ...code('dart', 'heaplens_flutter/lib/insights/insight_rules.dart · computeInsights, orphans (trimmed)', r'''
  // --- Orphan leak: high-confidence, worded plainly (not hedged) ---
  // Grouped by symbol — a leak at one call site is one actionable item,
  // not N separate list rows for N allocations from the same place.
  final orphansBySymbol = <String, List<NodeDto>>{};
  for (final n in live) {
    if (n.state == NodeStateDto.orphan) {
      orphansBySymbol.putIfAbsent(n.symbol, () => []).add(n);
    }
  }
...
    final totalBytes = group.fold<int>(0, (sum, n) => sum + n.size);
    // Representative node for "select in graph" — the largest one, since
    // that's the most consequential single allocation to look at first.
    final representative = group.reduce((a, b) => a.size >= b.size ? a : b);
...
        id: 'orphan:$symbol',
        severity: InsightSeverity.critical,
        title: 'Probable leak at $symbol',
        detail: 'Probable leak: ${group.length} allocation${group.length == 1 ? '' : 's'} '
            'totaling $totalBytes bytes lost their owner and were never freed. '
            'Site: $symbol.','''),
    ...para('//',
        r'The grouping is the thoughtful part. An application that '
        r'leaks in a loop produces hundreds of orphans with the same '
        r'symbol; listing them separately would bury the one thing a '
        r'developer can act on, the call site. So the rule groups by '
        r'symbol, sums the bytes, and picks the largest member as the '
        r'node to select when the user clicks the finding.'),
    blank,
    ...para('//',
        r'The wording is a deliberate choice, flagged in the comment: '
        r'"high-confidence, worded plainly (not hedged)". The title says '
        r'"Probable leak", which is hedged in one word, and the body '
        r'states the facts: this many allocations, this many bytes, '
        r'their owner was freed, they were not. The state chip’s '
        r'tooltip in node_colors.dart is softer ("likely a leak"). '
        r'The two are consistent in spirit; neither claims certainty.'),
    ...sec(r'rule two: a hot cluster'),
    ...code('dart', 'heaplens_flutter/lib/insights/insight_rules.dart · computeInsights, hot (trimmed)', r'''
  // --- Unbounded growth: hot clusters. Worded as a hedged suggestion —
  // structural signal, not a certainty like an orphan. ---
  for (final n in live) {
    if (n.state == NodeStateDto.hot) {
...
          id: 'hot:${n.id}',
          severity: InsightSeverity.warning,
          title: 'Growing cluster at ${n.symbol}',
          detail: 'Cluster at ${n.symbol} has grown to ${n.edges.length} children and keeps '
              'growing — likely an unbounded collection; check whether entries are ever removed.','''),
    ...para('//',
        r'Here the file contrasts itself with the orphan rule. The '
        r'comment says the finding is "worded as a hedged suggestion — '
        r'structural signal, not a certainty like an orphan". It is. '
        r'The body says "likely an unbounded collection", not "is".'),
    blank,
    ...para('//',
        r'The state itself comes from the daemon. In the daemon’s '
        r'anomaly.rs a node is hot when it has more children than the '
        r'hot-cluster threshold, which defaults to 32 in config.rs and '
        r'which the Build Spec calls "an empirically-chosen fan-out '
        r'heuristic, not a value derived from any model". One wording '
        r'detail deserves a second look. The text says the cluster "keeps '
        r'growing", but the rule checks only that the node is in the hot '
        r'state, and hot is a count threshold, not a rate. A cluster '
        r'that reached 33 children and stopped would still read as '
        r'growing. I would call the claim slightly stronger than the '
        r'test behind it.'),
    ...sec(r'rule three: one allocation that dominates'),
    ...code('dart', 'heaplens_flutter/lib/insights/insight_rules.dart · the dominant-consumer rule', r'''
/// Minimum fraction of total live bytes one node must hold to be flagged
/// as a dominant consumer. Empirically chosen (structural heuristic, like
/// the daemon's own hot-cluster/storm thresholds), not derived.
const double kDominantConsumerFraction = 0.20;
...
  final totalLiveBytes = live.fold<int>(0, (sum, n) => sum + n.size);
  if (totalLiveBytes > 0) {
    for (final n in live) {
      final fraction = n.size / totalLiveBytes;
      if (fraction >= kDominantConsumerFraction) {
        final pct = (fraction * 100).toStringAsFixed(0);'''),
    ...para('//',
        r'This is the one rule that does not read a daemon verdict; '
        r'it computes a share from sizes. It is also the one the file '
        r'itself calls an observation rather than a problem: "worded as '
        r'an observation, not a problem claim", severity info. The '
        r'threshold, 20 percent of live bytes, is openly labelled '
        r'"empirically chosen", the same honesty as the daemon’s '
        r'constants.'),
    blank,
    ...para('//',
        r'The edge behaviour follows from the arithmetic and is worth '
        r'knowing. With a single live node the share is 100 percent, so '
        r'the finding fires for any lone allocation. With exactly five '
        r'equal nodes each holds 20 percent and the comparison is >=, '
        r'so all five fire. For the captured fixture, a 2400-byte owner '
        r'and 100 children of 128 and 256 bytes, total live bytes are '
        r'21,600 and the owner holds about 11 percent, so nothing fires. '
        r'These are consequences of the code, not tested behaviour.'),
    ...sec(r'ordering, and why there is no sort'),
    ...para('//',
        r'The function returns findings in the order its three loops '
        r'append them: all orphan findings, then hot findings, then '
        r'dominant consumers. That order happens to be critical, '
        r'warning, info, so the list reads most urgent first without '
        r'a sort step. Inside a rule the order follows the node map’s '
        r'iteration order. The function is "pure and synchronous", in '
        r'the doc comment’s words, "safe to call on every build; the '
        r'caller decides how often that is".'),
    ...sec(r'testing, honestly'),
    ...para('//',
        r'There is no insight_rules_test.dart and no test for '
        r'InsightsPanel. The only coverage is incidental: '
        r'test/widget_test.dart builds the whole HeapLensApp, which '
        r'includes the panel, and one of its snapshots contains an '
        r'orphan node, so computeInsights runs at least once with the '
        r'orphan branch live. That test asserts no exception and '
        r'nothing about the text. The wording, the grouping, the 20 '
        r'percent boundary and the ordering are unpinned. Because the '
        r'function is pure and takes a plain Map, it is one of the '
        r'easiest things in the codebase to test, which makes the gap '
        r'a matter of time rather than difficulty.'),
    ...sec(r'limits and what is next'),
    ...pt('//', r'three rules, no storm rule',
        r'the daemon also detects allocation storms, but it only logs '
        r'a warning and sets no node state (its M4 plan: "storm '
        r'detection only emits tracing::warn!"), so there is nothing '
        r'for this file to read.'),
    ...pt('//', r'advice is generic',
        r'the suggestions name a site and a quantity, not a fix. '
        r'"Check whether entries are ever removed" is as specific as '
        r'it gets.'),
    ...pt('//', r'English strings inline',
        r'titles and details are formatted in code, with a hand-rolled '
        r'plural for allocation.'),
    ...pt('//', r'the nullable node id',
        r'implicatedNodeId is typed int? with a comment about a race, '
        r'but every rule currently sets it.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
