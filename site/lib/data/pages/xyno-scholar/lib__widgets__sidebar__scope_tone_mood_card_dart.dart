import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/sidebar/scope_tone_mood_card.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'scope_tone_mood_card.dart — how many, how formal, how bold'),
    cm('//', r'three small controls in one card, each one a sentence in the prompt'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'set scope, tone and mood in the preference block'),
    kv(r'language', r'Dart / Flutter, a stateless ConsumerWidget'),
    kv(r'size', r'88 lines, 1 commit, never edited'),
    kv(r'controls', r'Scope: 2 segments · Tone: 3 chips · Mood: 4 chips'),
    kv(r'defaults', r'broad, neutral, curious (PreferenceBlock.initial())'),
    kv(r'history', r'7a200e7 (2026-08-06 09:41)'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'The fields decide what a topic is about. These three controls '
        r'decide how it is delivered. Scope chooses between a menu and '
        r'a deep dive. Tone and mood colour the writing. They belong '
        r'in one card because they are the cheap, reversible choices: '
        r'a user flips them often, to see what changes, while the '
        r'fields and the level stay put. The card’s title is only '
        r'“Scope” (Portée), and the other two controls have '
        r'their own small headings inside it.'),

    ...sec(r'what each setting does downstream'),
    ...code('dart', r'lib/services/mistral_client.dart · lines 104-105', r'''
- If scope is "broad": populate "broadTopics" with 5 to 8 entries, leave "narrowTopic" null.
- If scope is "narrow": populate "narrowTopic" with exactly 3 entries in "starterBibliography" and exactly 3 entries (I, II, III) in "suggestedStructure", leave "broadTopics" an empty array.'''),
    ...code('dart', r'lib/services/mistral_client.dart · lines 56-57', r'''
   - tone playful = light, witty phrasing; tone serious = measured, formal academic phrasing; tone neutral = plain, matter-of-fact phrasing.
   - mood curious = exploratory, open questions; mood provocative = challenges assumptions, bold framing; mood reverent = respectful, careful of sensitive subject matter; mood irreverent = unconventional, willing to poke at orthodoxy.'''),
    ...para('//',
        r'The three controls are not decoration. Each value is turned '
        r'into a word and put in the system prompt, which defines '
        r'it. Scope changes the shape of the whole answer: broad gives '
        r'five to eight topic options for the user to pick from, narrow '
        r'gives one fully developed topic with the three tabs the '
        r'previous pages cover. In the user turn the scope also picks '
        r'the instruction text: “Generate ONE narrow, deep-dive '
        r'topic” or “Generate 5 to 8 broad topic options”. Tone and '
        r'mood are adjectives for the prose, with one sentence each in '
        r'the prompt saying what they mean. The labels on screen are '
        r'the same words, in French and English.'),
    blank,
    ...para('//',
        r'A look at the two axes. Tone is about register: playful, '
        r'serious, neutral. Mood is about stance: curious, '
        r'provocative, reverent, irreverent. Reverent and irreverent '
        r'are a matched pair, one careful of sensitive subject '
        r'matter and the other willing to poke at orthodoxy, and the '
        r'pair fits a project whose default fields include '
        r'theology. The file itself does not comment on that; it is '
        r'my reading of the choice of words.'),

    ...sec(r'the scope control'),
    ...code('dart', r'lib/widgets/sidebar/scope_tone_mood_card.dart · lines 24-47', r'''
          SegmentedButton<Scope>(
            segments: Scope.values
                .map(
                  (scope) => ButtonSegment(
                    value: scope,
                    label: Text(
                      prefs.language == 'fr'
                          ? scope.labelFr()
                          : scope.labelEn(),
                    ),
                  ),
                )
                .toList(),
            selected: {prefs.scope},
            onSelectionChanged: (selection) =>
                notifier.setScope(selection.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? colors.teal.withValues(alpha: 0.16)
                    : null,
              ),
            ),
          ),'''),
    ...para('//',
        r'Scope is exactly two states, so it gets a SegmentedButton, a '
        r'single control with the two options side by side. The '
        r'segments come from Scope.values, and the labels carry the '
        r'consequence, not just the name: “Broad (5–8 options)” and '
        r'“Narrow (deep dive)”, in French “Large (5–8 pistes)” and '
        r'“Ciblé (approfondissement)”. A user learns what the setting '
        r'does before pressing the generate button. The selected set '
        r'is a one-element set, {prefs.scope}: SegmentedButton is '
        r'built to allow multi-select, and the widget is used as '
        r'single-select, so on a change the code takes selection.first. '
        r'The style callback paints the selected segment in the same '
        r'teal tint as the other cards, and returns null for the '
        r'rest to keep the theme’s colour.'),

    ...sec(r'the tone and mood chips'),
    ...code('dart', r'lib/widgets/sidebar/scope_tone_mood_card.dart · lines 48-65', r'''
          const SizedBox(height: 18),
          Text(s.toneTitle, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: Tone.values.map((tone) {
              final selected = prefs.tone == tone;
              return ChoiceChip(
                label: Text(
                  prefs.language == 'fr' ? tone.labelFr() : tone.labelEn(),
                ),
                selected: selected,
                onSelected: (_) => notifier.setTone(tone),
                selectedColor: colors.teal.withValues(alpha: 0.16),
              );
            }).toList(),
          ),'''),
    ...para('//',
        r'Tone and mood use ChoiceChips, the right widget for “exactly '
        r'one of these”. The two blocks are the same eight lines '
        r'with Tone swapped for Mood: lines 66 to 83 repeat the '
        r'structure for four mood values. That duplication is '
        r'small and clear, and a helper that took the enum values '
        r'and the setter would remove it at the price of some '
        r'generic typing. With two uses it is not worth it yet.'),
    blank,
    ...para('//',
        r'One thing about ChoiceChip: tapping the selected chip calls '
        r'onSelected again, and the code sets the same value, so '
        r'nothing changes. A user cannot unset tone or mood. '
        r'That fits the data: the preference block always holds a '
        r'value, and the enums’ fromApiValue methods default to '
        r'neutral, curious and broad.'),

    ...sec(r'a design detail: reading and watching'),
    ...code('dart', r'lib/widgets/sidebar/scope_tone_mood_card.dart · lines 13-17', r'''
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferenceBlockProvider);
    final notifier = ref.read(preferenceBlockProvider.notifier);
    final colors = context.colors;
    final s = AppStrings(prefs.language);'''),
    ...para('//',
        r'The first two lines show the Riverpod idiom clearly. ref.watch '
        r'on the provider subscribes the widget to the value, so the '
        r'card rebuilds when anything in the block changes. ref.read '
        r'on the notifier is a one-off lookup of the object that has '
        r'the setters. The widget fetches the notifier once at the top '
        r'and calls it from all three handlers. The other sidebar '
        r'cards call ref.read each time inside the handler; both work, '
        r'and this one is shorter when several handlers share a '
        r'target.'),

    ...sec(r'edge cases'),
    ...pt('//', r'wide labels',
        r'“Ciblé (approfondissement)” is a long segment label. The '
        r'SegmentedButton shares the card width between its '
        r'segments. In a narrow sidebar I would expect the text to '
        r'wrap or ellipsize; I did not run it at narrow widths.'),
    ...pt('//', r'selection after a generation',
        r'scope is read when you press generate (the user-turn '
        r'instruction depends on it). Changing it afterwards does not '
        r'alter a topic already on screen.'),
    ...pt('//', r'deep dive from a broad result',
        r'a broad result is only on screen if scope was broad, and the '
        r'Deep Dive button on a broad topic calls deepDive in the '
        r'provider. That function passes prefs.copyWith() with no '
        r'arguments (generation_provider.dart line 87), which is a copy '
        r'of the same preferences, still broad. _userTurn then picks '
        r'its instruction from the scope, so, reading the code, the '
        r'request carries deepDiveOnTitle but is worded “Generate 5 to '
        r'8 broad topic options”. Whether the model then returns a '
        r'narrow topic anyway I did not test. Setting scope to narrow '
        r'in that copy looks like what was meant.'),

    ...sec(r'how it is tested'),
    ...para('//',
        r'No test covers the card. The enums are not tested either, '
        r'so a typo in a label would be found by looking. The '
        r'prompt text that gives these values meaning is covered in '
        r'part by the client tests, which feed a response through '
        r'the parser and not the prompt through a judge.'),

    ...sec(r'history'),
    ...pt('//', r'7a200e7, 2026-08-06 09:41',
        r'the scaffold commit. This is the one sidebar card that '
        r'89a9c12 did not touch, because it imports no icons. It has '
        r'not been edited since.'),
  ],
);
