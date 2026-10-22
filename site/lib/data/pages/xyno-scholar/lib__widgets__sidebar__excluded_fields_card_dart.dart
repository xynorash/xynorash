import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/sidebar/excluded_fields_card.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'excluded_fields_card.dart — telling the model what to stay away from'),
    cm('//', 'a tag box whose contents become one clause of rule 2'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'sidebar card: rose chips for excluded themes plus a text box to add one'),
    kv('language', 'Dart / Flutter, ConsumerStatefulWidget'),
    kv('size', '80 lines'),
    kv('history', '2 commits, 7a200e7 (scaffold) and 89a9c12 (icon package import)'),
    kv('state', 'PreferenceBlock.excludedFields in preferenceBlockProvider'),
    kv('reaches the model', 'as one bracketed list inside rule 2 of the system prompt'),
    ...sec('why this card exists'),
    ...para('//',
        'Choosing what to include is half the question. The other '
        'half is what the user is tired of or cannot use: a '
        'student who wants history and theology but not another '
        'war, or not the twentieth century. The card gives that '
        'negative preference a place. Its hint text, “e.g. war, '
        '20th century…” in English and “ex. guerre, XXe siècle…” in '
        'French (lib/l10n/strings.dart), shows the two kinds of '
        'thing meant: a theme and a period.'),
    ...para('//',
        'It is the smallest of the five cards, and it is also the '
        'one with the least machinery behind it. A tag goes from '
        'the text box into a list, and from the list into a '
        'sentence of the prompt. There is no id, no catalog, no '
        'normalisation. That plainness is the design: an exclusion '
        'is whatever the user writes, because the set of things a '
        'person might want to avoid is open-ended in a way the '
        'catalog of fields is not.'),

    ...sec('themes in the UI, fields in the model'),
    ...para('//',
        'The card’s title is “Thèmes exclus” / “Excluded themes”. '
        'Everywhere below the widget the same data is called '
        'excluded fields: the PreferenceBlock member is '
        'excludedFields, the provider methods are addExcludedTag and '
        'removeExcludedTag, and the prompt calls them “Fields to '
        'actively avoid”. The two vocabularies disagree. A theme '
        '(war) and a period (20th century) are not academic fields '
        'in the sense of the catalog, and a user who reads '
        '“themes” will type themes. The model, told to avoid '
        '“fields”, has to interpret the list charitably. The '
        'mismatch may be harmless in practice, but nothing in the '
        'repository tests what the model does with a theme in that '
        'slot, and it is the kind of naming drift that makes later '
        'changes harder. The commit history has no discussion of '
        'it.'),

    ...sec('the widget'),
    ...code('dart', 'lib/widgets/sidebar/excluded_fields_card.dart · state and submit', r'''
class _ExcludedFieldsCardState extends ConsumerState<ExcludedFieldsCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(WidgetRef ref) {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    ref.read(preferenceBlockProvider.notifier).addExcludedTag(value);
    _controller.clear();
  }'''),
    ...para('//',
        'The card is stateful for exactly one reason: it owns a '
        'TextEditingController, and a controller has to be disposed. '
        'The tags themselves live in the provider. The submit '
        'method trims, ignores a blank, hands the string to the '
        'controller and clears the box. It trims twice, once here '
        'and once inside addExcludedTag in '
        'lib/providers/preference_providers.dart, which also '
        'refuses exact duplicates. Like its twin in the field '
        'card, it takes a WidgetRef parameter that the State '
        'already provides as ref.'),
    ...code('dart', 'lib/widgets/sidebar/excluded_fields_card.dart · the chips (trimmed)', r'''
                children: prefs.excludedFields.map((tag) {
                  return InputChip(
                    label: Text(tag),
                    deleteIcon: const Icon(LucideIcons.x, size: 14),
                    onDeleted: () => ref
                        .read(preferenceBlockProvider.notifier)
                        .removeExcludedTag(tag),
                    backgroundColor: colors.rose.withValues(alpha: 0.08),
                    side: BorderSide(
                      color: colors.rose.withValues(alpha: 0.35),
                    ),
                  );'''),
    ...para('//',
        'Each tag is an InputChip with a cross, the same Material '
        'chip the field card uses for its selection, but filled '
        'with rose instead of teal. Unlike the field card, the '
        'delete callback is unconditional: there is no minimum '
        'number of exclusions, so every chip can be removed and '
        'the list can go back to empty. The label is the tag '
        'exactly as typed, with its capitals and accents intact; '
        'the field card, by contrast, lowercases what it stores.'),
    ...para('//',
        'The chip row is only built when the list is not empty, and '
        'it is wrapped in a 10 px bottom padding that exists only '
        'in that case, so an empty card collapses to its title and '
        'the text box with no stray gap. The text box below it is '
        'the same pattern as in the field card: a TextField with '
        'isDense, a plus button as its suffix icon, and '
        'onSubmitted calling the same handler as the button.'),

    ...sec('rose means “no”'),
    ...para('//',
        'The palette comment in lib/theme/app_colors.dart reserves '
        'rose for “destructive actions, errors, key-rejected '
        'state”. The excluded chips are none of those. They are '
        'rose because an exclusion is the one thing in the sidebar '
        'that says no, and a red-toned chip next to teal ones makes '
        'the polarity legible without a label. It is a deliberate '
        'stretch of the rule, and the app_colors page lists it as '
        'one of the places the palette bends. The tint recipe '
        '(0.08 for the fill, 0.35 for the border) is the same one '
        'the error banner uses, with the border at 0.4 there, and '
        'it is written out by hand in each place.'),

    ...sec('how the tags reach the model'),
    ...code('dart', 'lib/services/mistral_client.dart · building the exclusion list', r'''
    final excludedList = prefs.excludedFields.isEmpty
        ? '(none)'
        : prefs.excludedFields.join(', ');'''),
    ...para('//',
        'This is the only place the list is consumed besides '
        'PreferenceBlock.toJson, which puts the same strings in the '
        'user turn under the key excludedFields. The joined text '
        'is interpolated into rule 2 of the system prompt, whose last '
        'sentence begins “Fields to actively avoid, if any:”, so '
        'with two tags typed it reads, for example, “[war, 20th '
        'century]”. With nothing excluded the model reads '
        '“[(none)]”, an explicit empty case rather than an empty '
        'bracket, which avoids leaving the model to guess whether '
        'the list was forgotten.'),
    ...para('//',
        'Two properties follow from this plumbing, and both are '
        'worth being honest about. First, the exclusion is advisory. '
        'It is one clause in a long prompt. A search of lib/ shows '
        'no other use of the list: nothing filters the response, '
        'nothing checks the returned titles or keywords against the '
        'tags. Whether the model honours “avoid war” is a matter of '
        'its compliance, which the repository does not measure. '
        'Second, the tags are pasted into the prompt in the user’s '
        'own words and language, so an English exclusion typed into '
        'a French session is passed along unchanged and the model '
        'has to bridge them.'),

    ...sec('what the card does not check'),
    ...pt('//', 'no conflict with the selection',
        'nothing compares the exclusions with the selected fields, '
        'so the user can select “history” and also exclude the '
        'word history. The prompt would then say both. The '
        'preference_providers page notes the same gap from the '
        'controller side.'),
    ...pt('//', 'case-sensitive duplicates',
        'addExcludedTag compares exact strings, so war and War '
        'become two chips.'),
    ...pt('//', 'no length limit',
        'a whole sentence can be pasted in and becomes one very wide '
        'chip and one very long list item in the prompt.'),
    ...pt('//', 'no persistence',
        'like the rest of the block, the list is gone on reload.'),

    ...sec('what changed over time'),
    ...para('//',
        'The file has two commits, both on 2026-08-06. 7a200e7 '
        '(09:41 UTC) created it, and 89a9c12 (09:58 UTC) changed the '
        'icon import from lucide_icons to lucide_icons_flutter to '
        'repair the web build; the cross icon on each chip and the '
        'plus in the box are the only two icons it uses. The behaviour is unchanged from the first '
        'version, and it did not need to change when the backend '
        'moved from Cerebras to Gemini to Mistral, because the card '
        'only talks to a provider, not to a model.'),

    ...sec('what is tested'),
    ...para('//',
        'No test covers the card or the exclusion plumbing. The '
        'client test builds a PreferenceBlock with excludedFields '
        'set to an empty list (test/mistral_client_test.dart) and '
        'never asserts on the prompt’s rule 2. A test that '
        'constructs a block with two tags and checks that the '
        'system prompt contains “[war, 20th century]” would pin the '
        'only guarantee the feature makes.'),

    ...sec('limits and what is next'),
    ...pt('//', 'two names for one thing',
        'themes in the UI, fields in the state and prompt; renaming '
        'the state to excludedThemes would remove the drift.'),
    ...pt('//', 'advisory only',
        'there is no post-check that a returned topic avoids the '
        'tags.'),
    ...pt('//', 'raw strings',
        'no case folding, accent folding or conflict check.'),
    ...pt('//', 'duplicated input box',
        'the plus-button TextField here and in the field card could '
        'be one shared widget with a transform callback.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
