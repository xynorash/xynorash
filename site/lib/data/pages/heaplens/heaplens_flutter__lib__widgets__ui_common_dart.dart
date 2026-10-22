import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/widgets/ui_common.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'ui_common.dart — the parts bin of the interface'),
    cm('//', r'toggles sized to their text, corner brackets, and the empty state that speaks'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'shared presentation widgets for the ribbon and the right rail'),
    kv('language', r'Dart / Flutter'),
    kv('size', r'371 lines, one commit: 1cfb7f9 (2026-07-19)'),
    kv('widgets', r'CompactSwitch, CompactSegmented, HudFrame, TopBarCell, MetricTile, EmptyState, RailSection'),
    kv('tested', r'indirectly, through control_bar_test and node_detail_test'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'The UI refresh redesigned the app as a ribbon across the '
        r'top, a rail down the side, and panels in between. Seven '
        r'small pieces recur in those places, and they were pulled '
        r'into one file so that the look of the app is decided in '
        r'one place. Everything here is presentation: no providers, '
        r'no knowledge of nodes or the daemon. It reads colors and '
        r'type from XynorashTheme and nothing else.'),
    ...sec(r'toggles sized to the text beside them'),
    ...code('dart', 'heaplens_flutter/lib/widgets/ui_common.dart · lines 5-12', r'''
/// A toggle sized to actually match the height of the label text it sits
/// next to, rather than the stock Material [Switch]'s fixed proportions.
/// Scaling a real `Switch` down (`Transform.scale`) still left it visibly
/// taller than a 12px label, because Material's switch track has its own
/// fixed minimum size that a naive scale factor doesn't reliably land on
/// — this widget's dimensions are set directly instead, so "match the
/// text" is exact rather than approximated.
class CompactSwitch extends StatelessWidget {'''),
    ...para('//',
        r'The first two widgets exist because, per the doc comment, the '
        r'stock widgets did not match the label height. A Material Switch scaled down '
        r'with Transform.scale was still visibly taller than a '
        r'twelve pixel label, because the switch track has its own '
        r'minimum size and a scale factor does not land on it. So '
        r'CompactSwitch is built from primitives with its size set '
        r'directly: track width is twice the height, the thumb is '
        r'the height minus four, and a 150 millisecond animation '
        r'moves it. The idea is stated as exact rather than '
        r'approximated.'),
    ...code('dart', 'heaplens_flutter/lib/widgets/ui_common.dart · lines 27-57', r'''
  @override
  Widget build(BuildContext context) {
    final width = height * 2;
    final thumbSize = height - 4;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: width,
        height: height,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? XynorashTheme.cyan.withValues(alpha: 0.55) : Colors.white24,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: thumbSize,
            height: thumbSize,
            decoration: BoxDecoration(
              color: value ? XynorashTheme.cyan : Colors.white70,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );'''),
    ...para('//',
        r'CompactSegmented applies the same fix to the view-mode '
        r'toggle: a pill whose height is a parameter, an option list '
        r'generic over the value type, a cyan tint on the selected '
        r'option. The ribbon instantiates it as CompactSegmented of '
        r'ViewMode. The generic type means it is not tied to the '
        r'view enum, but it is only used once. One gap: both widgets '
        r'are a GestureDetector over a container, with no Semantics '
        r'and no focus handling, so they cannot be reached by '
        r'keyboard or announced by a screen reader through anything in '
        r'this file. A later version could add that.'),
    ...sec(r'the signature device'),
    ...code('dart', 'heaplens_flutter/lib/widgets/ui_common.dart · lines 130-136', r'''
/// The app's one signature visual device: a thin sci-fi-HUD corner
/// bracket at each corner of [child], instead of a Material rounded-card
/// border. Applied consistently to every major panel (ribbon, right
/// rail, insights panel, node detail) — restrained (thin stroke, low
/// alpha by default) rather than decorative, the way a real cockpit
/// display's panel edges are functional framing, not ornament.
class HudFrame extends StatelessWidget {'''),
    ...code('dart', 'heaplens_flutter/lib/widgets/ui_common.dart · lines 163-191', r'''
class _HudCornerPainter extends CustomPainter {
  _HudCornerPainter({required this.color, required this.cornerLength, required this.strokeWidth});

  final Color color;
  final double cornerLength;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final len = cornerLength.clamp(0.0, size.shortestSide / 2);

    // Top-left
    canvas.drawLine(Offset(0, len), Offset.zero, paint);
    canvas.drawLine(Offset.zero, Offset(len, 0), paint);
    // Top-right
    canvas.drawLine(Offset(size.width - len, 0), Offset(size.width, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, len), paint);
    // Bottom-left
    canvas.drawLine(Offset(0, size.height - len), Offset(0, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(len, size.height), paint);
    // Bottom-right
    canvas.drawLine(Offset(size.width - len, size.height), Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - len), paint);
  }'''),
    ...para('//',
        r'HudFrame is the one visual idea in the app, and the '
        r'comment calls it restrained: a thin corner bracket at each '
        r'corner instead of a rounded card border. Eight line '
        r'segments, two per corner, at 12 pixels long and 1.4 wide '
        r'by default, in the cyan hairline color at low alpha. The '
        r'comment’s argument is functional: a cockpit display’s '
        r'panel edges are framing, not ornament.'),
    ...para('//',
        r'Details in the painter. The corner length is clamped to '
        r'half the shortest side, so a very small panel does not '
        r'draw brackets that cross over. It paints in the foreground '
        r'painter, above the child, so the brackets stay visible on '
        r'top of panel fills. shouldRepaint compares all three '
        r'fields. It is used by the right rail and the insights '
        r'panel.'),
    ...sec(r'ribbon pieces'),
    ...code('dart', 'heaplens_flutter/lib/widgets/ui_common.dart · lines 200-203', r'''
/// One grouped, visually-separated unit in the top bar (e.g. "attach
/// control", "summary metrics"). A thin vertical divider marks the
/// boundary between cells so related controls read as one group without
/// needing a heavier border around every cell.'''),
    ...code('dart', 'heaplens_flutter/lib/widgets/ui_common.dart · lines 238-243', r'''
/// A plain-language label paired with its technical value — the dual-level
/// legibility pattern used throughout the top bar and right rail: the
/// label is always the human-readable name of the thing, the value is
/// always the real, precise data next to it. An optional [tooltip] gives
/// the plain-sentence definition on hover; the label/value themselves are
/// never replaced by the tooltip, only supplemented.'''),
    ...para('//',
        r'TopBarCell is one grouped unit in the ribbon, with an '
        r'optional vertical divider after it in the purple at 35 '
        r'percent alpha. The padding is 22 by 14, and the comment '
        r'says it grew from 12 by 6 when the ribbon began to span '
        r'the full window, because cells packed to the left looked '
        r'unfinished. MetricTile is the label-and-value pair the '
        r'ribbon uses for its counters: the label is normal text in '
        r'the plain language name, the value is bold monospace, so '
        r'it reads as data. An optional tooltip supplies a '
        r'one-sentence definition without replacing either part. The '
        r'comment calls this dual-level legibility, and it is the '
        r'principle of the whole app: the label tells you what, the '
        r'value tells you exactly.'),
    ...sec(r'empty means something'),
    ...code('dart', 'heaplens_flutter/lib/widgets/ui_common.dart · lines 275-281', r'''
/// An explicit empty/waiting state — used anywhere a panel would otherwise
/// render blank (no target attached, no node selected, daemon not yet
/// connected). Always says what's missing and, where relevant, what to do
/// about it, per the legibility rule that empty panels are never bare.
/// Styled as a terminal prompt line (`> message`) rather than a plain
/// italic sentence — an empty panel in this app reads as "awaiting input",
/// which a prompt communicates more precisely than a caption would.'''),
    ...para('//',
        r'EmptyState is the rule that no panel is ever bare. It '
        r'always says what is missing and, when relevant, what to do '
        r'about it. It is drawn as a terminal prompt line, > '
        r'message, in dim monospace, with an optional icon, because '
        r'an empty panel in this app means awaiting input and a '
        r'prompt says that more precisely than a caption. The tests '
        r'rely on the exact text: node_detail_test expects > no node '
        r'selected.'),
    ...sec(r'the rail section'),
    ...code('dart', 'heaplens_flutter/lib/widgets/ui_common.dart · lines 309-321, 334-369', r'''
/// One always-on, non-collapsible section of the right rail — no chevron,
/// no tap-to-collapse, always showing [child] in full. [muted] demotes a
/// section's visual weight (smaller, dimmer text) for developer-diagnostic
/// content that isn't the primary audience's concern, without hiding it.
///
/// Pass [expand]: true (default false) to have this section grow to fill
/// any remaining vertical space in its parent `Column` — used for the last
/// section (verbose logs) so the rail's total content stretches to fill
/// the window instead of stopping partway down and leaving dead space.
/// Requires the immediate parent to be a `Column`/`Flex`, per `Expanded`'s
/// own contract.
class RailSection extends StatelessWidget {
  const RailSection({
...
  @override
  Widget build(BuildContext context) {
    final titleColor = muted ? Colors.white38 : XynorashTheme.cyan;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Text(
        XynorashTheme.bracketLabel(title),
        overflow: TextOverflow.ellipsis,
        style: XynorashTheme.sectionHeader(color: titleColor, fontSize: muted ? 10 : 12),
      ),
    );
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: child,
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        header,
        if (expand) Expanded(child: body) else body,
        if (!expand) const Divider(height: 1, color: Colors.white12),
      ],
    );

    if (!expand) return content;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1, color: Colors.white12),
          Expanded(child: content),
        ],
      ),
    );'''),
    ...para('//',
        r'RailSection is a titled block: the title through '
        r'bracketLabel and sectionHeader, a body with 12 pixel side '
        r'padding and a hairline divider below. muted lowers the '
        r'title to ten point, dim grey, for developer diagnostics. '
        r'The expand option makes the section an Expanded child with '
        r'the divider above it, for filling leftover space; the '
        r'comment explains it needs a Column parent. As noted in the '
        r'right rail page, nothing uses expand today, so the second '
        r'half of the build method is dead code kept for a layout '
        r'that was dropped.'),
    ...sec(r'edge cases'),
    ...pt('//', r'fixed pixel sizes',
        r'all dimensions are literals, tuned for the desktop window. '
        r'No text scaling or density handling.'),
    ...pt('//', r'HudFrame on tiny areas',
        r'the clamp prevents inverted corners; a zero-size child '
        r'paints nothing meaningful.'),
    ...pt('//', r'Tooltip needs an Overlay',
        r'MetricTile and EmptyState-based tooltips depend on a '
        r'Material app ancestor, which main.dart provides.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'Through its users. control_bar_test.dart taps the keyed '
        r'orphanOnlySwitch, which is the CompactSwitch, and checks '
        r'the view-mode toggle writes the provider. '
        r'node_detail_test.dart finds the EmptyState text. The '
        r'painter and RailSection have no direct test; a pixel '
        r'regression in the brackets would pass.'),
    ...sec(r'history'),
    ...pt('//', r'1cfb7f9 (2026-07-19)',
        r'feat(flutter): UI refresh. The only commit; it creates the '
        r'file as the shared vocabulary of the new layout.'),
  ],
);
