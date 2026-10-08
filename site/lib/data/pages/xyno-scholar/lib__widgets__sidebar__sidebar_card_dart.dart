import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/sidebar/sidebar_card.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'sidebar_card.dart — the shell every preference card sits in'),
    cm('//', '47 lines that decide what “a card” means in this app'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'shared container: a titled Card with an optional trailing widget'),
    kv('language', 'Dart / Flutter, StatelessWidget'),
    kv('size', '47 lines'),
    kv('history', 'one commit, 7a200e7 (2026-08-06 09:41 UTC); never edited since'),
    kv('used by', 'all five cards in lib/widgets/sidebar/'),
    ...sec('why this file exists'),
    ...para('//',
        'Five different controls live in the sidebar: a chip picker '
        'with a text field, a tag list, a hand-built radio list, a '
        'segmented button with two chip groups, and a text area. They '
        'have almost nothing in common as widgets, and yet they must '
        'read as one family of panels. This file is the thing they '
        'have in common. Each card passes a title and a child; the '
        'shell supplies the border, the padding, the title style and '
        'the gap between title and content.'),
    ...para('//',
        'The doc comment on the class says what the shell is for and '
        'what it forbids: “A single visually-distinct card in the '
        'sidebar dock. Multiple of these are stacked, never merged '
        'into one mega-card.” The rule is stated; the reason is not. '
        'My reading is that each card is one decision the user makes '
        '(which fields, what to avoid, how deep, in what voice, with '
        'what angle), and that a boundary between decisions is easier '
        'to scan than one long panel of mixed controls. That is an '
        'interpretation, not a quote.'),

    ...sec('the shell'),
    ...code('dart', 'lib/widgets/sidebar/sidebar_card.dart · constructor', r'''
  const SidebarCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });'''),
    ...para('//',
        'The whole public surface is three parameters, and two of '
        'them are required. title is a plain String rather than a '
        'widget, which keeps every card heading in one typeface and '
        'size and means a card cannot smuggle in a different title '
        'style. child is a Widget because the controls are too '
        'different to describe with data. trailing is optional and, '
        'as the next section shows, currently unused.'),
    ...code('dart', 'lib/widgets/sidebar/sidebar_card.dart · build() (trimmed)', r'''
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: colors.ink),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,'''),
    ...para('//',
        'The layout is a column with a header row and then the '
        'child. The title is wrapped in Expanded so a long heading '
        'wraps inside its own space instead of pushing the trailing '
        'widget off the card; with no trailing widget the Expanded '
        'simply fills the row. The 16 px padding and the 12 px gap '
        'under the header are the only spacing decisions made here; '
        'what happens inside the child, including the 8 and 12 px '
        'gaps the cards place between their own rows, is up to each '
        'card.'),

    ...sec('where the look actually comes from'),
    ...para('//',
        'The shell sets no colour, no border and no radius. It uses '
        'the stock Card widget and lets the app theme say what a '
        'card is:'),
    ...code('dart', 'lib/theme/app_theme.dart · cardTheme', r'''
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
        'Three choices in that block explain the sidebar’s look. '
        'surfaceRaised is pure white on a parchment page, so a card '
        'is lighter than its surroundings; elevation 0 with a one '
        'pixel border replaces a shadow with a line, which is the '
        'warm “academic paper” base the AppColors comment describes; '
        'and margin zero hands all the spacing to the parent, which '
        'is why sidebar.dart places a SizedBox(height: 16) between '
        'cards. A consequence of delegating to the theme: restyle '
        'the card once in app_theme.dart and every sidebar panel '
        'follows.'),
    ...para('//',
        'The title style is a small redundancy worth knowing about. '
        'The code reads titleMedium and then forces its colour to '
        'ink. The theme’s textTheme already defines titleMedium as '
        'the sans face, weight 600, size 15, in ink:'),
    ...code('dart', 'lib/theme/app_typography.dart · titleMedium', r'''
          titleMedium: sans(
            weight: FontWeight.w600,
            fontSize: 15,
            color: colors.ink,
          ),'''),
    ...para('//',
        'So the copyWith(color: colors.ink) restates a colour the '
        'style already has. It is harmless, and it matches the '
        'habit, visible across the widgets, of passing the ink '
        'colour explicitly, but it means the colour is specified in '
        'two places. It does at least go through the colour '
        'extension rather than a literal, as the comment at the top '
        'of app_colors.dart asks of every widget.'),

    ...sec('the trailing slot nobody uses yet'),
    ...para('//',
        'A search of lib/ for “trailing” finds the parameter here '
        'and nothing else except an unrelated sentence in the system '
        'prompt (“No trailing commas”). None of the five cards '
        'passes it. The slot looks designed for a card-level action '
        'such as a reset or a help icon; the repository does not say '
        'what it was for, and no commit adds a user. It is a small '
        'piece of speculative generality that costs one line in the '
        'build method and one conditional.'),

    ...sec('what is inside the five cards'),
    ...para('//',
        'Listing the children shows why the shell stays so thin: '
        'there is nothing to share below the title.'),
    ...pt('//', 'FieldSelectorCard',
        'deletable InputChips for the selection, collapsible '
        'categories of FilterChips, and a text field with a plus '
        'button.'),
    ...pt('//', 'ExcludedFieldsCard',
        'rose-tinted InputChips plus a text field.'),
    ...pt('//', 'LevelSelectorCard',
        'five hand-built InkWell tiles that behave like radio '
        'buttons and show a description each.'),
    ...pt('//', 'ScopeToneMoodCard',
        'a two-way SegmentedButton, then two ChoiceChip groups under '
        'small labels.'),
    ...pt('//', 'FreeTextPanelCard',
        'a three-line text field, amber suggestion rows, and four '
        'ActionChip examples.'),
    blank,
    ...para('//',
        'Each of these is a ConsumerWidget or a ConsumerStatefulWidget '
        'that watches the preference provider on its own, so the shell '
        'does not need to know about Riverpod at all: it imports '
        'only material.dart and the colour extension.'),

    ...sec('two dialects of “card” in one app'),
    ...para('//',
        'The sidebar uses the real Card widget, 12 px radius. The '
        'output side builds its cards by hand from a Container, '
        'with a 10 px radius. The outline tab, the bibliography tab '
        'and the notebook drawer each repeat this recipe:'),
    ...code('dart', 'lib/widgets/output/tabs/outline_tab.dart · the hand-built card', r'''
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.border),
            ),'''),
    ...para('//',
        'Same fill, same border colour, a different radius, and a '
        'different padding (16 in the two tabs, 14 in the notebook '
        'entry, 16 in the sidebar shell). The two radii are close '
        'enough that the eye may not separate them, which is '
        'perhaps why nobody has unified them. The tidy fix would be '
        'to move the Container recipe into a shared widget and let '
        'SidebarCard compose it, or to have the tabs use Card with '
        'the theme’s 12 px radius.'),

    ...sec('what is tested'),
    ...para('//',
        'Nothing. The widget has no logic to test; the sensible '
        'check would be a golden image of the shell, and the '
        'project has none.'),

    ...sec('limits and what is next'),
    ...pt('//', 'no heading semantics',
        'the title is a plain Text; a search of the sidebar and tab '
        'directories finds no Semantics widget, so screen readers '
        'get no heading landmark per card.'),
    ...pt('//', 'one dead parameter',
        'trailing has no caller.'),
    ...pt('//', 'two card recipes',
        'radius 12 in the sidebar, 10 on the output side, padding '
        '14 or 16.'),
    ...pt('//', 'no collapse at the card level',
        'the field card collapses its categories itself; the shell '
        'could offer a chevron so every card folds, which would '
        'matter on the 640 px mobile dock.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
