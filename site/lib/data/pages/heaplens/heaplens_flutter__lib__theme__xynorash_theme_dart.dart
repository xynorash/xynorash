import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/theme/xynorash_theme.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'xynorash_theme.dart — a terminal palette in a window'),
    cm('//', r'seven colors lifted from a fastfetch config and everything derived from them'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'palette, typography helpers and the dark ThemeData'),
    kv('language', r'Dart / Flutter'),
    kv('size', r'132 lines, one commit: 1cfb7f9 (2026-07-19)'),
    kv('used by', r'9 other files in lib/ ; main.dart installs darkTheme()'),
    kv('origin', r'xynorash-pwsh/fastfetch/config.jsonc, per the file comment'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'The first version of the UI picked its colors one widget '
        r'at a time, and the class comment records what that '
        r'produced: every widget had hardcoded its own copy of the '
        r'healthy, orphan, hot, connection-status and severity '
        r'colors. This file is the single place that holds them. The '
        r'palette is not designed from scratch; it is the one my '
        r'terminal setup already uses.'),
    ...sec(r'seven colors, copied rather than invented'),
    ...code('dart', 'heaplens_flutter/lib/theme/xynorash_theme.dart · lines 3-17, 19-22, 24-26', r'''
/// XYNORASH color theme — lifted directly from the real fastfetch config
/// at `xynorash-pwsh/fastfetch/config.jsonc` (RGB values below are copied
/// verbatim from that file's `38;2;R;G;B` ANSI true-color codes), so the
/// app's chrome matches the same palette used everywhere else in this
/// setup. Single source of truth: every widget that used to hardcode its
/// own copy of the healthy/orphan/hot/connection-status/severity colors
/// now reads from here instead.
class XynorashTheme {
  XynorashTheme._();

  /// `"keys": "38;2;170;0;255"` — the config's primary accent.
  static const Color purple = Color(0xFFAA00FF);

  /// `"title": "38;2;0;229;255"` — the config's secondary accent.
  static const Color cyan = Color(0xFF00E5FF);
...
  /// Shell/Term/Font/Vol color (`38;2;0;229;170`) — already almost
  /// exactly the app's pre-existing "healthy" teal (0xFF2DD4BF); this is
  /// the theme's precise hue.
  static const Color teal = Color(0xFF00E5AA);
...
  /// CPU/DDR color (`38;2;255;170;0`) — replaces the generic Material
  /// amber previously used for "hot".
  static const Color orange = Color(0xFFFFAA00);'''),
    ...para('//',
        r'The comment makes a checkable promise: the RGB values are '
        r'copied verbatim from the 38;2;R;G;B ANSI true-color codes '
        r'in the fastfetch config. The arithmetic confirms it for '
        r'every color in the file. 170,0,255 is AA00FF, 0,229,255 is '
        r'00E5FF, 0,229,170 is 00E5AA, 255,170,0 is FFAA00, '
        r'255,100,50 is FF6432, 238,0,238 is EE00EE and 255,200,50 '
        r'is FFC832. The comment on teal and coral says something I '
        r'find worth keeping: the earlier teal and '
        r'coral were already close to these, so the change sharpens '
        r'the hue and leaves the meaning alone.'),
    ...para('//',
        r'Two of the seven are not used by anything outside this '
        r'file today: magenta (the disk color) and yellow (the media '
        r'color). They came along with the palette. The others are '
        r'used: cyan in nine places, coral four, teal and orange '
        r'three each, purple once.'),
    ...sec(r'surfaces as layers'),
    ...code('dart', 'heaplens_flutter/lib/theme/xynorash_theme.dart · lines 39-56', r'''
  // --- Surface depth ---------------------------------------------------
  //
  // A vitals-HUD reads as layers of a cockpit display, not one flat gray
  // with lighter rectangles floating on it — each surface below is one
  // genuine step darker/lighter than the next, not just an opacity trick.

  /// True window background — the deepest layer.
  static const Color bgBase = Color(0xFF0A0B0F);

  /// Panels resting directly on the base (right rail, insights panel).
  static const Color bgPanel = Color(0xFF12141B);

  /// The ribbon — one step up again, it's the app's "always on top" HUD bar.
  static const Color bgRibbon = Color(0xFF161822);

  /// Hairline / bracket-frame color at rest (very low alpha, present but
  /// not shouting).
  static Color hudLine({double alpha = 0.35}) => cyan.withValues(alpha: alpha);'''),
    ...para('//',
        r'The surface comment states the visual idea: a heads-up '
        r'display reads as layers of a cockpit, not as one gray with '
        r'lighter rectangles floating on it, so each surface is a '
        r'genuine step lighter than the one beneath. Base is 0A0B0F, '
        r'the panels on it are 12141B, and the ribbon is 161822. The '
        r'hairline color is the cyan at 35 percent alpha by default, '
        r'quiet enough to frame things without drawing the eye. Note '
        r'that bgBase has no reader outside this file: it is '
        r'consumed by darkTheme as the scaffold background.'),
    ...sec(r'typography without a font file'),
    ...code('dart', 'heaplens_flutter/lib/theme/xynorash_theme.dart · lines 60-80', r'''
  /// Monospace family for every technical/numeric value (ptr, size, ts,
  /// byte counts, pid, revision, log lines) — Consolas is present on
  /// every Windows install this app targets; 'monospace' is the
  /// cross-platform fallback. Deliberately not a bundled custom font: no
  /// asset fetch available, and a well-chosen system font applied
  /// *consistently* reads more intentional than an inconsistently-applied
  /// downloaded one.
  static const String monoFamily = 'Consolas';
  static const List<String> monoFallback = ['Cascadia Code', 'monospace'];

  static TextStyle mono({
    double fontSize = 12,
    Color color = Colors.white,
    FontWeight fontWeight = FontWeight.normal,
  }) => TextStyle(
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    fontSize: fontSize,
    color: color,
    fontWeight: fontWeight,
  );'''),
    ...para('//',
        r'The type decision is argued in the comment. Consolas is on '
        r'every Windows machine the app targets, with Cascadia Code '
        r'and the generic monospace as fallbacks, and it is '
        r'deliberately not a bundled font: there was no asset to '
        r'fetch, and a well-chosen system font applied consistently '
        r'reads as more intentional than an inconsistently applied '
        r'download. This lines up with pubspec.yaml, which has no '
        r'fonts section. The mono helper is the way every technical '
        r'value gets drawn (pointers, sizes, timestamps, pids, log '
        r'lines), and eight calls in four widget files use it. '
        r'Nothing outside the theme reads the family constant '
        r'directly.'),
    ...sec(r'the label convention'),
    ...code('dart', 'heaplens_flutter/lib/theme/xynorash_theme.dart · lines 82-97', r'''
  /// Section-header treatment: uppercase + letter-spacing — the
  /// terminal-label convention ("NODE DETAIL", not "Node detail") used
  /// for every panel/section title, achievable with the system sans
  /// alone rather than needing a distinct display face.
  static TextStyle sectionHeader({Color? color, double fontSize = 12}) => TextStyle(
    color: color ?? cyan,
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.6,
  );

  /// Wraps [title] in the `[ TITLE ]` bracket convention and applies
  /// [sectionHeader]'s uppercase/letter-spacing treatment in one call —
  /// the single place this exact bracket format is defined, so every
  /// panel header stays identical if it ever changes.
  static String bracketLabel(String title) => '[ ${title.toUpperCase()} ]';'''),
    ...para('//',
        r'Section titles use uppercase with 1.6 pixels of letter '
        r'spacing and, through bracketLabel, a [ TITLE ] frame, the '
        r'convention a terminal uses for a heading. The comment on '
        r'bracketLabel gives the reason it is a function: it is the '
        r'one place where the bracket format is defined, so every '
        r'panel header stays identical if it ever changes. Its two '
        r'callers are the right rail’s RailSection and the insights '
        r'panel header.'),
    ...sec(r'the ThemeData'),
    ...code('dart', 'heaplens_flutter/lib/theme/xynorash_theme.dart · lines 99-118', r'''
  static ThemeData darkTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: cyan,
      brightness: Brightness.dark,
      primary: cyan,
      secondary: purple,
    );
    return ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: bgBase,
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? cyan : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? cyan.withValues(alpha: 0.5) : null,
        ),
      ),
      sliderTheme: const SliderThemeData(activeTrackColor: cyan, thumbColor: cyan),'''),
    ...para('//',
        r'The dark theme seeds a Material 3 color scheme from cyan '
        r'and then overrides primary to cyan and secondary to '
        r'purple, so the seed generates the neutral tones and the '
        r'two accents are exact. The scaffold background is the base '
        r'layer. Switches, sliders and segmented buttons are '
        r're-skinned in cyan. Nearly all of the shapes in the app '
        r'are custom widgets, as ui_common.dart shows, so this theme '
        r'mostly matters for the stock controls that remain.'),
    ...sec(r'design decisions and trade-offs'),
    ...pt('//', r'constants not tokens',
        r'everything is a static const, so there is no runtime theme '
        r'switching and no light mode. The file defines only the dark '
        r'theme.'),
    ...pt('//', r'a private constructor',
        r'XynorashTheme._() makes the class a namespace that cannot '
        r'be instantiated.'),
    ...pt('//', r'not quite the single source',
        r'two banner colors still live in '
        r'target_status_banner.dart as raw values: an amber and a '
        r'blue (the blue serves two statuses). They are semantic caution and info colors that have '
        r'no counterpart in the fastfetch palette. The node-state '
        r'mapping also has one raw color, a gray for freed nodes, '
        r'which node_colors.dart says has no clear theme mapping.'),
    ...pt('//', r'no test',
        r'there is no test of this file; a changed hue would not '
        r'fail anything. One canvas test asserts that the selection '
        r'ring is XynorashTheme.cyan, which pins one color by name.'),
    ...sec(r'history'),
    ...pt('//', r'1cfb7f9 (2026-07-19)',
        r'feat(flutter): UI refresh. The message lists the shared '
        r'xynorash theme beside the ribbon, insights panel, right '
        r'rail and process picker. It is the file’s only commit.'),
  ],
);
