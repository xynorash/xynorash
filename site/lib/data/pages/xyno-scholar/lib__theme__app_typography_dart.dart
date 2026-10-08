import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/theme/app_typography.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'app_typography.dart — a book face for ideas, a clean face for the machine'),
    cm('//', 'Fraunces, Inter and JetBrains Mono, mapped onto Material’s type scale'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'the only place font families are named; builds the app’s TextTheme'),
    kv('language', 'Dart / Flutter with google_fonts'),
    kv('size', '109 lines; three style factories and one text theme'),
    kv('history', 'one commit, 7a200e7 (2026-08-06); never touched afterwards'),
    kv('families', 'Fraunces (serif), Inter (sans), JetBrains Mono (mono)'),
    ...sec('why this file exists'),
    ...para('//',
        'Typography is where this app’s “scholarly but not stuffy” '
        'tone is carried most directly. The content is prose, a lot '
        'of it, generated and variable in length, and a student will '
        'read it for minutes at a time. The design splits the '
        'job between three families, each given a clear domain, and '
        'this file is the only place their names appear. A search '
        'of lib/ for GoogleFonts outside this file finds nothing.'),
    ...code('dart', 'lib/theme/app_typography.dart · the three factories', r'''
  /// Serif display font — headings, topic titles, the problématique quote.
  static TextStyle serif({
...
  /// Sans-serif — UI chrome and body prose.
  static TextStyle sans({
...
  /// Monospace — JSON inspector / technical bits.
  static TextStyle mono({'''),
    ...para('//',
        'The doc comments are the design brief in three lines. '
        'Serif for the things a scholar would call a title and for '
        'the one sentence the whole product exists to produce, the '
        'problématique. Sans for everything that is chrome or '
        'running text. Mono for anything technical. One comment is '
        'stale: no JSON inspector exists in the app. Mono is used '
        'in exactly three places, and none is a JSON view.'),

    ...sec('where each family actually shows up'),
    ...pt('//', 'Fraunces (serif)',
        'ten direct call sites: the app bar title, the problématique '
        'callout (italic, weight 500, 19 px), bibliography titles, '
        'outline titles and numerals, notebook titles, and the '
        'markdown blockquote and h1 to h3. In addition every display '
        'and headline slot of the text theme is serif, which '
        'covers the topic titles on broad cards and the narrow '
        'topic headline.'),
    ...pt('//', 'Inter (sans)',
        'every title, body and label style in the text theme, so '
        'all buttons, fields, chips and tabs; markdown paragraphs '
        'at 15 px with a 1.55 line height.'),
    ...pt('//', 'JetBrains Mono',
        'the API key field on the unlock screen, the BibTeX dialog’s '
        'selectable text, and inline code in markdown. Showing the key '
        'in monospace makes characters such as l and 1 or O and 0 '
        'distinguishable while the user checks what they pasted; '
        'that reason is my reading, the code only shows the choice.'),

    ...sec('the three factories'),
    ...code('dart', 'lib/theme/app_typography.dart · serif', r'''
  static TextStyle serif({
    FontWeight weight = FontWeight.w600,
    FontStyle style = FontStyle.normal,
    double? fontSize,
    Color? color,
  }) => GoogleFonts.fraunces(
    fontWeight: weight,
    fontStyle: style,
    fontSize: fontSize,
    color: color,
  );'''),
    ...para('//',
        'serif defaults to weight 600 and is the only factory that '
        'takes a font style, because it is the only one used in '
        'italic (the problématique and the blockquote). sans '
        'defaults to 400 and mono to 400; none of them hardcodes a '
        'size or a colour, so a call site states both or inherits.'),

    ...sec('the text theme'),
    ...code('dart', 'lib/theme/app_typography.dart · the scale (excerpt)', r'''
    final base = GoogleFonts.interTextTheme();
    return base
        .copyWith(
          displayLarge: serif(
            weight: FontWeight.w600,
            fontSize: 40,
            color: colors.ink,
          ),
          displayMedium: serif(
            weight: FontWeight.w600,
            fontSize: 32,
            color: colors.ink,
          ),
          displaySmall: serif(
            weight: FontWeight.w600,
            fontSize: 26,
            color: colors.ink,
          ),'''),
    ...para('//',
        'The scale starts from Inter’s own text theme and replaces '
        'the display and headline slots (40, 32, 26 and 24, 20, '
        '18 px) with serif. The title slots (18, 15, 13) and body '
        'slots (16, 14, 12) stay sans; bodySmall, labelMedium and '
        'labelSmall are declared in muted ink. In the widgets the '
        'mapping is clean: displaySmall is the narrow topic headline '
        'and the app name on the unlock screen; headlineSmall is a '
        'card or dialog title; titleMedium is the heading of each '
        'sidebar card; labelLarge is the sub-label above the tone and '
        'mood chips.'),
    ...code('dart', 'lib/theme/app_typography.dart · colour pass', r'''
        .apply(bodyColor: colors.ink, displayColor: colors.ink);'''),
    ...para('//',
        'The final apply is meant as a safety net so that no style '
        'falls back to Material’s black. One consequence is worth '
        'flagging, and it is my reading of how TextTheme.apply '
        'behaves, not something I ran: apply replaces the colour of '
        'every style it touches, so the muted ink declared a few '
        'lines earlier on bodySmall, labelMedium and labelSmall '
        'would be overwritten by the ink passed to bodyColor. The '
        'call sites that want muted text all say so explicitly '
        '(textTheme.bodySmall with copyWith(color: colors.inkMuted) '
        'appears on the unlock screen, in the level cards and in the '
        'bibliography tab), '
        'which is consistent with the theme default not delivering '
        'it.'),

    ...sec('the cost: fonts from a CDN'),
    ...para('//',
        'google_fonts fetches the font files at runtime. The README '
        'states the consequence directly in its fonts section: '
        'the app loads Fraunces, Inter and JetBrains Mono from '
        'Google’s font CDN, and a normal internet connection in '
        'the visitor’s browser is all that is required. For an app '
        'whose whole function is a call to a remote model, offline '
        'use was never a goal, so the trade is cheap: no font files '
        'in the repository, no asset registration in pubspec.yaml, '
        'and the cost is a first-paint flash while the fonts '
        'arrive. Bundling them as assets would remove the network '
        'dependency at the price of binary files in the repo.'),

    ...sec('what is not here'),
    ...para('//',
        'There is no type scale for the markdown output beyond the '
        'stylesheet in markdown_text.dart, which sets its own '
        'sizes (15 for paragraphs, 22, 19 and 17 for headings). '
        'Many chips and buttons pass a raw TextStyle(fontSize: 12) '
        'or 11 or 13 at the call site instead of a theme slot. '
        'Fonts are therefore centralised by family, but sizes are '
        'not centralised by role. Nothing in test/ asserts any '
        'typography.'),

    ...sec('limits and what is next'),
    ...pt('//', 'network-dependent text',
        'before the fonts load, and in any environment that blocks '
        'the CDN, text renders in a fallback face.'),
    ...pt('//', 'stale mono comment',
        'the JSON inspector it mentions does not exist.'),
    ...pt('//', 'sizes at call sites',
        'twelve-pixel chip labels and similar are literals, not '
        'theme roles.'),
    ...pt('//', 'no variable-font tuning',
        'weights are chosen from the family’s named weights only.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
