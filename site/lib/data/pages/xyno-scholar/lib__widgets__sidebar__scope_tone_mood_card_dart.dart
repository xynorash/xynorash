import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/sidebar/scope_tone_mood_card.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'scope_tone_mood_card.dart — one card, three different dials'),
    cm('//', 'scope changes the shape of the answer; tone and mood change its voice'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'sidebar card: Scope (broad or narrow), Tone (3 values), Mood (4 values)'),
    kv('language', 'Dart / Flutter, ConsumerWidget (no local state)'),
    kv('size', '88 lines'),
    kv('history', 'one commit, 7a200e7 (2026-08-06 09:41 UTC); unchanged since'),
    kv('controls', 'SegmentedButton<Scope> and two ChoiceChip groups'),
    kv('writes', 'setScope, setTone, setMood on the preference controller'),
    ...sec('why three controls share a card'),
    ...para('//',
        'The three enums behind this card look alike, short lists '
        'with a label in each language, but they do very different '
        'jobs, and the page is easier to read once that is clear.'),
    ...pt('//', 'Scope',
        'chooses what kind of answer comes back: five to eight broad '
        'topic options, or one deep-dive topic with a problématique, '
        'a bibliography and an outline.'),
    ...pt('//', 'Tone',
        'playful, serious or neutral: how the prose sounds.'),
    ...pt('//', 'Mood',
        'curious, provocative, reverent or irreverent: the stance '
        'the topics take toward their subject.'),
    blank,
    ...para('//',
        'The file groups them because each is a small closed choice '
        'with no explanation needed beyond its label, which makes '
        'them cheap to stack. The card’s heading, though, is only '
        '“Scope” / “Portée” (strings.dart: scopeTitle). Tone and '
        'mood get their own small sub-labels, “Tone” and “Mood”, '
        'but scope has none because it borrows the card’s title. '
        'The class name, ScopeToneMoodCard, is the honest one; the '
        'screen label under-describes what is inside.'),

    ...sec('scope: the dial that rewrites the response'),
    ...code('dart', 'lib/widgets/sidebar/scope_tone_mood_card.dart · the scope control (trimmed)', r'''
          SegmentedButton<Scope>(
            segments: Scope.values
                .map(
                  (scope) => ButtonSegment(
                    value: scope,'''),
    ...code('dart', 'lib/widgets/sidebar/scope_tone_mood_card.dart · selection and tint', r'''
            selected: {prefs.scope},
            onSelectionChanged: (selection) =>
                notifier.setScope(selection.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? colors.teal.withValues(alpha: 0.16)
                    : null,
              ),
            ),'''),
    ...para('//',
        'A SegmentedButton is Material’s control for a small '
        'mutually exclusive set, and two options is its natural '
        'size. Its selected value is a Set, hence the braces around '
        'prefs.scope and the .first on the way back. The style '
        'override is worth reading closely. It returns a teal tint '
        'only for the selected state and null otherwise, and null '
        'means “use the theme’s default for this state”, so the '
        'unselected segments are left alone. The language toggle in '
        'the app bar (home_screen.dart) uses the same recipe, down '
        'to the 0.16 alpha, so the two segmented controls look like '
        'one family.'),
    ...code('dart', 'lib/models/enums.dart · scope labels', r'''
    Scope.broad => 'Broad (5–8 options)',
    Scope.narrow => 'Narrow (deep dive)','''),
    ...para('//',
        'The labels carry facts. “5–8 options” is the number the '
        'system prompt asks for in broad mode (“5 to 8 entries”), '
        'so the user learns the '
        'size of the answer from the control itself, in French '
        'too: “Large (5–8 pistes)” and “Ciblé (approfondissement)”. '
        'The numbers are written in two places, the label and the '
        'prompt, and nothing ties them together.'),
    ...para('//',
        'How scope turns into a request is spread over two '
        'files, and seeing both is what makes this card matter.'),
    ...code('dart', 'lib/services/mistral_client.dart · the instruction that depends on scope (trimmed)', r'''
      'instruction': prefs.scope.apiValue == 'narrow'
      ...'''),
    ...para('//',
        'The user turn carries an instruction chosen by that test: '
        '“Generate ONE narrow, deep-dive topic (scope="narrow")” '
        'for narrow, “Generate 5 to 8 broad topic options '
        '(scope="broad")” otherwise, each followed by “following '
        'the rules and schema exactly”. It tells the model which '
        'shape to return, and '
        'the response then carries its own scope field. '
        'OutputPanel shows NarrowTopicView with four tabs when the '
        'response says narrow and has a narrowTopic, and '
        'BroadTopicsList when broad topics came back. So this one segmented control '
        'decides which of two very different screens the user will '
        'see next, and it is the only choice in the sidebar that '
        'does.'),
    ...para('//',
        'There is a consequence in the deep-dive flow that I only '
        'know from reading the code. The Deep Dive button on a '
        'broad topic calls deepDive in generation_provider.dart, '
        'which passes prefs.copyWith() with no arguments, so the '
        'scope stays whatever the sidebar says. If the sidebar is '
        'still on Broad, the instruction above still asks for five '
        'to eight broad options, together with the chosen topic’s '
        'title as deepDiveOnTitle. Whether the model then returns '
        'one narrow topic or a fresh broad list is up to how it '
        'weighs those two signals; the code does not force it. '
        'prefs.copyWith(scope: Scope.narrow) is the obvious change '
        'if a forced deep dive is wanted. I have not run this '
        'against the model, so I flag it as a likely rough edge, '
        'not a confirmed bug. The broad_topics_list page lists the '
        'same concern from the button’s side.'),

    ...sec('tone and mood: two dials with a prompt behind them'),
    ...code('dart', 'lib/widgets/sidebar/scope_tone_mood_card.dart · tone chips (trimmed)', r'''
              return ChoiceChip(
                label: Text(
                  prefs.language == 'fr' ? tone.labelFr() : tone.labelEn(),
                ),
                selected: selected,
                onSelected: (_) => notifier.setTone(tone),
                selectedColor: colors.teal.withValues(alpha: 0.16),
              );'''),
    ...para('//',
        'Tone and mood use ChoiceChip, Material’s single-select '
        'chip, in a Wrap with 6 px spacing. The callback ignores the '
        'boolean that onSelected supplies and always calls the '
        'setter. That makes the group behave like radio buttons: '
        'tapping the chosen chip tells the chip it is being '
        'deselected, but the card replies by selecting the same '
        'value again, so one value is always active. The '
        'enums have a default for each (neutral, curious), the '
        'provider starts there, and the prompt never has to handle '
        '“no tone”.'),
    ...para('//',
        'Rule 4 of the prompt defines every value in a single '
        'line. For tone it reads “tone playful = light, witty '
        'phrasing; tone serious = measured, formal academic '
        'phrasing; tone neutral = plain, matter-of-fact phrasing”, '
        'and the mood line does the same for curious, '
        'provocative, reverent and irreverent (the last two '
        'defined as “respectful, careful of sensitive subject '
        'matter” and “unconventional, willing to poke at '
        'orthodoxy”). The user sees none of this. The level card '
        'prints a description under every option; this card shows '
        'only one-word chips. For tone, one word is enough. For '
        'mood, “Révérencieux” and “Irrévérencieux” are close to '
        'self-explanatory in French, but “Reverent” and “Irreverent” '
        'do not say that reverent here means “careful of sensitive '
        'subject matter”. That is an asymmetry in the interface: '
        'the level, whose labels are the more obvious, gets the '
        'explanations, and the mood, whose labels are the more '
        'ambiguous, does not.'),
    ...para('//',
        'The combination space is small and enumerable: 2 scopes '
        'times 3 tones times 4 moods is 24 voice settings, 120 once '
        'the five levels from the neighbouring card are counted. '
        'The prompt handles it by defining each value in words '
        'instead of branching, so there is no code that depends on '
        'the combination. Nothing records how the model’s output '
        'actually changes between, say, serious/reverent and '
        'playful/irreverent; there is no evaluation set in the '
        'repository.'),

    ...sec('a pattern that repeats three times'),
    ...para('//',
        'Each of the three controls follows the same recipe: read '
        'the value from the block, map the enum’s values to widgets, '
        'compare each to the selection, call the setter in the '
        'callback. The labels come through the repeated language '
        'ternary that level_selector_card.dart also uses. The '
        'notifier is obtained once at the top of build with '
        'ref.read(preferenceBlockProvider.notifier), which is the '
        'right call for something used only in callbacks: it does '
        'not subscribe the card to the notifier object. The block '
        'itself is watched, so a change to any preference rebuilds '
        'this card, which is cheap at this size.'),

    ...sec('what changed over time'),
    ...para('//',
        'One commit created the file: 7a200e7, the scaffold on '
        '2026-08-06 at 09:41 UTC. It has no icons, so the '
        'lucide_icons_flutter import fix (89a9c12) did not touch it, '
        'and none of the three provider swaps that followed '
        '(Cerebras, Gemini, Mistral) needed it to change. The file '
        'in the repository today is its first version.'),

    ...sec('what is tested'),
    ...para('//',
        'Nothing in test/ builds the card or checks the enums’ '
        'labels. mistral_client_test.dart exercises both scopes at '
        'the client level, one test with a broad response and one '
        'with a narrow response, but through the parsing of canned '
        'JSON, not through the sidebar.'),

    ...sec('limits and what is next'),
    ...pt('//', 'a heading that says less than the card does',
        '“Scope” covers tone and mood as well.'),
    ...pt('//', 'unexplained mood values',
        'the prompt defines them; the UI does not show the '
        'definitions, though the level card shows its.'),
    ...pt('//', 'deep dive may not be narrow',
        'it inherits the sidebar scope; see above.'),
    ...pt('//', 'numbers in two places',
        '“5–8” lives in the label and the prompt.'),
    ...pt('//', 'no test',
        'a widget test that taps each chip and asserts the '
        'provider’s block would pin the radio-like behaviour.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
