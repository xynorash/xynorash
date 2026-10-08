import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/theme/app_colors.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'app_colors.dart — a warm paper, and four colours with one meaning each'),
    cm('//', 'the single source of truth for every hue in the app'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'ThemeExtension holding the palette; widgets read it as context.colors'),
    kv('language', 'Dart / Flutter'),
    kv('size', '123 lines; 14 colours, one palette (light)'),
    kv('history', 'one commit, 7a200e7 (2026-08-06); never touched afterwards'),
    kv('rule it states', 'no widget hardcodes a hue; accents are semantic, not decorative'),
    ...sec('the idea'),
    ...para('//',
        'The app is a reading tool for scholars, so the palette aims '
        'at paper, not at a brand: a warm cream page, near-black '
        'warm ink, hairline borders in a darker cream, and then a '
        'small number of accents. The doc comment on the class says '
        'what the discipline is:'),
    ...code('dart', 'lib/theme/app_colors.dart · the intent', r'''
/// Semantic accent colors, each with exactly one meaning, layered on top of
/// a warm "academic paper" base. Keep this the single source of truth for
/// color so no widget hardcodes a hue directly.
class AppColors extends ThemeExtension<AppColors> {'''),
    ...para('//',
        'Two claims in that comment can be checked against the '
        'rest of the repository. The first, single source of truth, '
        'holds: a search for Colors. and Color(0x outside this file '
        'finds only two uses, both of Colors.transparent (the app '
        'bar’s surface tint in app_theme.dart and the unselected '
        'level card’s fill in level_selector_card.dart). Every hue '
        'in the UI comes from here. The second, one meaning per '
        'accent, holds with a few honest exceptions that the next '
        'sections list.'),

    ...sec('the palette'),
    ...code('dart', 'lib/theme/app_colors.dart · AppColors.light', r'''
  static const light = AppColors(
    parchment: Color(0xFFF6F1E6),
    surface: Color(0xFFFFFDF8),
    surfaceRaised: Color(0xFFFFFFFF),
    ink: Color(0xFF2A2722),
    inkMuted: Color(0xFF6B6459),
    border: Color(0xFFE1D8C4),
    amber: Color(0xFFB8863E),
    amberOn: Color(0xFFFFFFFF),
    teal: Color(0xFF2F5D62),
    tealOn: Color(0xFFFFFFFF),
    success: Color(0xFF3F7D53),
    successOn: Color(0xFFFFFFFF),
    rose: Color(0xFFAE3E36),
    roseOn: Color(0xFFFFFFFF),
  );'''),
    ...para('//',
        'Six neutrals and four accents, each accent with an ‘on’ '
        'colour for text that sits on it (all white). The three '
        'surfaces form a stack: parchment is the page, surface is a '
        'slightly lighter cream used for the app bar, the drawer and '
        'text fields, and surfaceRaised is pure white for cards. '
        'Depth is expressed by brightness and a one-pixel border '
        'rather than by shadow, which matches app_theme.dart, where '
        'the app bar, cards and buttons all set elevation to zero.'),

    ...sec('what each accent means, and where it breaks its own rule'),
    ...pt('//', 'amber, warm: primary actions and emphasis',
        'the stock ElevatedButton, the book logo, the numbered '
        'circles on broad topics, the bibliography type chips, the '
        'clarifying-question banner and the field-suggestion banner '
        'in the sidebar. Eight files use it. It is the colour of '
        '“look here”.'),
    ...pt('//', 'teal, cool: interactive and active states',
        'selected tabs, focused inputs, links, selected chips and '
        'the segmented buttons, progress spinners. It is the most '
        'used accent (twelve files). It also appears on things '
        'that are not interactive: the field chips on topic cards and '
        'the badge on each outline part are teal-tinted. In practice teal '
        'also means “belongs to the topic’s structure”.'),
    ...pt('//', 'success, green: save only',
        'the comment says “reserved only for save/success actions”, '
        'and the reservation is kept to the letter: colors.success is '
        'referenced exactly once in the whole project, on the Save to '
        'Notebook button in narrow_topic_view.dart.'),
    ...pt('//', 'rose, red: destructive actions and errors',
        'the unlock screen’s key-rejected box, the output panel’s '
        'error banner, the notebook’s trash icon and its load-error '
        'text. One use bends the stated scope: the excluded-theme '
        'chips in the sidebar are rose-tinted. They are negations, not '
        'errors, but it is a reasonable extension of “don’t”.'),
    blank,
    ...para('//',
        'The counts come from a search of lib/. They are a snapshot '
        'of the code at the last commit, not something the project '
        'enforces; there is no test that fails when a widget reaches '
        'for the wrong accent.'),

    ...sec('contrast, computed from the hex values'),
    ...para('//',
        'The repository records no accessibility audit, so these '
        'figures are mine: WCAG relative-luminance contrast ratios '
        'computed from the hex codes above. Ink on parchment is 13.2 '
        'to 1, so body text is comfortable. Muted ink on parchment '
        'is 5.2 to 1 and on white 5.9 to 1, both above the 4.5 to 1 '
        'guideline for small text. Teal on parchment is 6.5 to 1, '
        'so links and tab labels pass. White on teal is 7.3, on '
        'rose 5.9 and on success 4.9, all fine.'),
    blank,
    ...para('//',
        'The weak spot is amber. White on amber is 3.2 to 1, which '
        'clears the 3 to 1 bar for large text and UI components but '
        'not the 4.5 to 1 bar for normal text, and that pair is the '
        'label of every primary button (Generate topics, Refine '
        'topic, Download .bib). Amber used as text is 3.2 to 1 on '
        'white and 2.9 to 1 on parchment; the numerals inside the '
        'broad-topic circles are amber on a pale amber tint of the '
        'same hue, which is lower still. A darker amber for text '
        'roles, or dark text on the amber buttons, would close the '
        'gap without changing the look.'),

    ...sec('why a ThemeExtension and not just a ColorScheme'),
    ...para('//',
        'Flutter’s ColorScheme has fixed roles (primary, secondary, '
        'surface, error and so on). It has no slot for “parchment”, '
        '“ink muted” or “success”. A ThemeExtension is the framework’s '
        'way to hang custom tokens on a ThemeData, and it makes the '
        'palette reachable from any BuildContext with a type-safe '
        'getter:'),
    ...code('dart', 'lib/theme/app_colors.dart · access', r'''
extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}'''),
    ...para('//',
        'That one extension is why 21 files in lib/ read colours '
        'with final colors = context.colors. The force-unwrap is safe '
        'because AppTheme.light() registers the extension in '
        'ThemeData.extensions (see app_theme.dart); a widget tested '
        'under a bare MaterialApp would throw there.'),

    ...sec('the boilerplate half of the file'),
    ...para('//',
        'More than half of the 123 lines are copyWith and lerp, which '
        'a ThemeExtension must implement, each listing all fourteen '
        'fields by hand:'),
    ...code('dart', 'lib/theme/app_colors.dart · lerp (trimmed)', r'''
  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      parchment: Color.lerp(parchment, other.parchment, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      ...
    );
  }'''),
    ...para('//',
        'lerp exists so the framework can animate between two '
        'themes. There is only one theme, and MaterialApp in app.dart '
        'passes no darkTheme, so lerp is required by the contract '
        'but nothing in the app exercises it. Adding a colour means '
        'touching the declaration, the constructor, light, copyWith '
        'and lerp.'),

    ...sec('limits and what is next'),
    ...pt('//', 'light theme only',
        'there is no dark palette; the whole design assumes a '
        'cream page.'),
    ...pt('//', 'amber text contrast',
        'white-on-amber at 3.2 to 1 is under the small-text guideline '
        'for the primary button.'),
    ...pt('//', 'no tint tokens',
        'tinted fills are written as colors.x.withValues(alpha: …) at '
        'the call site: 32 occurrences in lib/ with eight different '
        'alpha values (0.08 to 0.4). A handful of named tints would '
        'make the one-meaning rule easier to keep.'),
    ...pt('//', 'semantic drift',
        'teal on non-interactive chips and rose on excluded themes '
        'are small departures from the comment at the top.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
