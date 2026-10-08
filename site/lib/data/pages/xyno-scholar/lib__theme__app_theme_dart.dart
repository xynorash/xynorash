import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/theme/app_theme.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'app_theme.dart — turning the palette into Material defaults'),
    cm('//', 'one static method that decides how every stock widget looks'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'builds the ThemeData: colour scheme, text theme and twelve component themes'),
    kv('language', 'Dart / Flutter (Material 3)'),
    kv('size', '133 lines; one method, AppTheme.light()'),
    kv('history', 'one commit, 7a200e7 (2026-08-06); never touched afterwards'),
    kv('look', 'flat, bordered, cream: no elevation, hairline borders, 8 and 12 px radii'),
    ...sec('why this file exists'),
    ...para('//',
        'app_colors.dart defines what the colours are; '
        'app_typography.dart defines the type. This file is where '
        'they meet Flutter’s own widgets. Every TextField, button, '
        'chip, tab bar and snack bar the app uses comes from the '
        'Material library, and left alone each would come out in '
        'the default purple-and-white of a sample app. The job '
        'of AppTheme.light() is to make the stock widgets already '
        'look right so that most of the app’s code never styles '
        'anything.'),

    ...sec('step one: a scheme from a seed, then pinned'),
    ...code('dart', 'lib/theme/app_theme.dart · colorScheme', r'''
    final colorScheme = ColorScheme.fromSeed(
      seedColor: colors.amber,
      brightness: Brightness.light,
      primary: colors.amber,
      onPrimary: colors.amberOn,
      secondary: colors.teal,
      onSecondary: colors.tealOn,
      error: colors.rose,
      onError: colors.roseOn,
      surface: colors.surface,
      onSurface: colors.ink,
    );'''),
    ...para('//',
        'fromSeed generates a full Material 3 tonal palette from one '
        'colour; the named arguments then override the roles the '
        'app actually relies on. The result is a hybrid: primary, '
        'secondary, error, surface and their ‘on’ colours are '
        'exactly the brand palette, and every role not named here '
        'is computed from the amber seed. That is a pragmatic way '
        'to avoid specifying every role by hand, with the '
        'trade-off that a widget which reads an unnamed role gets '
        'a colour derived rather than chosen. Candidates for that '
        'gap are widgets with no explicit background, such as the '
        'Dialog behind the BibTeX export; I have not inspected '
        'which role each one reads.'),
    ...code('dart', 'lib/theme/app_theme.dart · the ThemeData skeleton', r'''
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: colors.parchment,
      colorScheme: colorScheme,
      textTheme: textTheme,
      extensions: const [colors],'''),
    ...para('//',
        'The last line is the load-bearing one: extensions registers '
        'the AppColors instance, which is what makes context.colors '
        'work everywhere (see app_colors.dart). The scaffold '
        'background is parchment rather than the scheme’s surface, '
        'so the page is the cream and the cards, drawers and inputs '
        'are brighter on top of it.'),

    ...sec('step two: component themes, grouped by what they say'),
    ...pt('//', 'flat paper',
        'the app bar, the card theme and the elevated button each set '
        'elevation to 0. The app bar keeps scrolledUnderElevation at '
        '0.5 and clears surfaceTintColor, so scrolling content does '
        'not tint it. Depth comes from the 1 px border, not from '
        'shadow.'),
    ...pt('//', 'one corner language',
        'cards use a 12 px radius with a hairline border; buttons '
        'and text inputs use 8 px. Hand-built containers in the '
        'widgets mostly reuse 8 and 12, with some 10 and 14.'),
    ...pt('//', 'amber acts, teal selects',
        'ElevatedButton is amber with white text; TextButton is teal; '
        'the input’s focused border is teal at 1.5 px; tab labels, '
        'the tab indicator and progress indicators are teal.'),
    ...pt('//', 'quiet defaults',
        'the snack bar is ink with parchment text and floats; the '
        'divider and the chip border use the same cream border '
        'colour as cards.'),
    blank,
    ...code('dart', 'lib/theme/app_theme.dart · cards and inputs', r'''
      cardTheme: CardThemeData(
        color: colors.surfaceRaised,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border),
        ),
      ),'''),
    ...para('//',
        'margin: EdgeInsets.zero is the detail that makes the '
        'sidebar spacing predictable. SidebarCard (see '
        'lib/widgets/sidebar/sidebar_card.dart) is a Card, and '
        'Material’s default card margin would add space on '
        'every side; the spacing between sidebar cards is '
        'instead an explicit 16 px SizedBox in sidebar.dart.'),
    ...code('dart', 'lib/theme/app_theme.dart · inputs', r'''
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.teal, width: 1.5),
        ),
        hintStyle: AppTypography.sans(color: colors.inkMuted),'''),

    ...sec('a switch that only overrides when it has to'),
    ...code('dart', 'lib/theme/app_theme.dart · switchTheme', r'''
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? colors.teal : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.teal.withValues(alpha: 0.4)
              : null,
        ),
      ),'''),
    ...para('//',
        'Returning null for the unselected state is the idiomatic '
        'WidgetStateProperty trick: null means “no opinion, use the '
        'framework default”, so only the on state is branded. The '
        'one Switch in the app is the “remember for this browser '
        'session” toggle on the unlock screen, so this is a theme '
        'entry that serves exactly one control.'),

    ...sec('what the theme does not reach'),
    ...para('//',
        'Several widgets repeat styling that could have lived here. '
        'The segmented buttons for language (home_screen.dart) and for '
        'scope (scope_tone_mood_card.dart) each override the selected '
        'background with the same teal at 16 per cent alpha in '
        'their own ButtonStyle; the theme has no '
        'segmentedButtonTheme. The FilterChip and ChoiceChip in the '
        'sidebar pass selectedColor of teal at 0.16 although chipTheme '
        'already sets the same value. Tinted banners (amber, rose, '
        'teal at 8 to 10 per cent) are hand-built Containers in '
        'five different files. A search of lib/ counts 32 uses of '
        'withValues(alpha: …), which is the visible cost of having '
        'no named tint tokens.'),

    ...sec('what is tested'),
    ...para('//',
        'The only test that builds the theme is the widget test, and '
        'only indirectly: pumping XynoScholarApp calls '
        'AppTheme.light() in app.dart. Nothing asserts a colour, a '
        'radius or the extension’s presence. A visual regression '
        'would pass the suite.'),

    ...sec('limits and what is next'),
    ...pt('//', 'light only',
        'a static factory with one constructor; a dark theme would '
        'need a second AppColors palette first.'),
    ...pt('//', 'redundant overrides',
        'chip and segmented-button selected colours are set in '
        'several widgets and could move into the theme.'),
    ...pt('//', 'derived roles',
        'roles not pinned in the ColorScheme come from the amber '
        'seed, so dialogs and menus pick up an unreviewed tint.'),
    ...pt('//', 'fonts at runtime',
        'the text theme asks google_fonts for Inter, Fraunces and '
        'JetBrains Mono; the README states the app needs the network '
        'for them (see app_typography.dart).'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
