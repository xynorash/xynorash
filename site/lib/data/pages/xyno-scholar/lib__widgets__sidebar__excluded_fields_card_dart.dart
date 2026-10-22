import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/sidebar/excluded_fields_card.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'excluded_fields_card.dart — the “not this” list'),
    cm('//', r'a tag box for themes the topics must stay away from'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'sidebar card that edits PreferenceBlock.excludedFields'),
    kv(r'language', r'Dart / Flutter, a ConsumerStatefulWidget with Riverpod'),
    kv(r'size', r'80 lines, 2 commits'),
    kv(r'writes', r'addExcludedTag and removeExcludedTag on the preference notifier'),
    kv(r'history', r'7a200e7 (2026-08-06 09:41), 89a9c12 (09:58)'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'Most of the sidebar says what you want: fields, level, tone. '
        r'This card says what you do not. Anyone who has asked a '
        r'search engine or a model for ideas knows the problem: it '
        r'keeps coming back to the obvious things. A student who is '
        r'tired of the Second World War does not want to see it in '
        r'five of eight suggestions. The placeholder shows the idea: '
        r'“e.g. war, 20th century…” (in French, “ex. guerre, XXe '
        r'siècle…”). These are a theme and a period, which is why the '
        r'card’s title is “Excluded themes” (Thèmes exclus).'),

    ...sec(r'where the tags go'),
    ...code('dart', r'lib/services/mistral_client.dart · lines 45-47', r'''
    final excludedList = prefs.excludedFields.isEmpty
        ? '(none)'
        : prefs.excludedFields.join(', ');'''),
    ...code('dart', r'lib/services/mistral_client.dart · line 53', r'''
2. Never add a field the user did not select, and never assume one field implies another (e.g. theology does not imply art, history does not imply theology, etc). Fields to actively avoid, if any: [$excludedList].'''),
    ...para('//',
        r'The tags are joined with commas and placed into rule 2 of the '
        r'system prompt, under the words “Fields to actively avoid”. '
        r'There is nothing else. The model is asked, in prose, to '
        r'keep away; the code does not check the answer for the '
        r'excluded words. So this card is a request to the model, not '
        r'a filter. A tag the model ignores will still appear in '
        r'a topic.'),
    blank,
    ...para('//',
        r'A naming gap is visible here. The card calls them themes, the '
        r'data and the prompt call them fields (excludedFields, “fields '
        r'to actively avoid”). The hint text gives themes and '
        r'periods, not academic fields, and the prompt’s rule about '
        r'fields is mostly about not adding disciplines. I read the '
        r'model as handling both fine, since the instruction is plain '
        r'language, but the label and the name are two words for '
        r'one thing.'),

    ...sec(r'submitting a tag'),
    ...code('dart', r'lib/widgets/sidebar/excluded_fields_card.dart · lines 16-30', r'''
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
        r'The state class owns a single TextEditingController and '
        r'disposes it. _submit trims, ignores blanks, adds the tag via '
        r'the notifier and empties the box. The parameter is named ref '
        r'and takes the same name as the State’s own ref property, '
        r'so inside the function it shadows it. It is harmless, since '
        r'the caller passes the State’s ref in, but it is the kind of '
        r'thing a linter would call out.'),
    blank,
    ...para('//',
        r'The notifier does its own checking. This is its half:'),
    ...code('dart', r'lib/providers/preference_providers.dart · lines 26-36', r'''
  void addExcludedTag(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty || state.excludedFields.contains(trimmed)) return;
    state = state.copyWith(excludedFields: [...state.excludedFields, trimmed]);
  }

  void removeExcludedTag(String tag) {
    state = state.copyWith(
      excludedFields: state.excludedFields.where((t) => t != tag).toList(),
    );
  }'''),
    ...para('//',
        r'The notifier trims again and refuses duplicates, so the check '
        r'is in two places. The duplicate test is exact: “war” and '
        r'“War” are two different tags. State is replaced, never '
        r'mutated: a new list is built each time, which is what '
        r'makes Riverpod notice the change. And the card clears the '
        r'box even when the notifier ignored a duplicate, so '
        r're-typing a tag you already have empties the box and '
        r'shows no message.'),

    ...sec(r'the chips and the box'),
    ...code('dart', r'lib/widgets/sidebar/excluded_fields_card.dart · lines 43-75', r'''
          if (prefs.excludedFields.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
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
                  );
                }).toList(),
              ),
            ),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: s.excludedHint,
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(LucideIcons.plus, size: 18),
                onPressed: () => _submit(ref),
              ),
            ),
            onSubmitted: (_) => _submit(ref),
          ),'''),
    ...para('//',
        r'The chips appear only when there is at least one tag, so an '
        r'empty list takes no space. Each chip is an InputChip with an '
        r'x to delete it. The colour is the telling choice: rose, '
        r'at 8 percent fill and 35 percent border. The selected fields '
        r'in the neighbouring card are teal. So “wanted” and '
        r'“unwanted” differ in colour at a glance, with no need to read '
        r'the title. The box accepts a tag two ways: the plus button, '
        r'or Enter (onSubmitted). Enter matters on a keyboard: the '
        r'user can type several tags in a row without reaching for '
        r'the mouse.'),
    blank,
    ...para('//',
        r'The card watches the whole preference block, not just the '
        r'excluded list, so it rebuilds when any preference changes. '
        r'It does that to get the language for AppStrings. The cost '
        r'is a handful of widgets, which is nothing here.'),

    ...sec(r'where it sits'),
    ...para('//',
        r'sidebar.dart stacks five cards in one scroll column, '
        r'16 pixels apart: fields, excluded fields, level, '
        r'scope/tone/mood, then free text. Excluded themes is second, '
        r'right under the field selector, which is where a user '
        r'who has just chosen what they want will look for what to '
        r'rule out. SidebarCard, the shared frame, gives it the title.'),

    ...sec(r'edge cases'),
    ...pt('//', r'no persistence in this file',
        r'the preference block starts from PreferenceBlock.initial() '
        r'(an empty excluded list), so the list is empty each time '
        r'the app starts. This file does nothing to store it.'),
    ...pt('//', r'long tags',
        r'the Wrap lets a long tag take a line of its own. Nothing '
        r'limits the length.'),
    ...pt('//', r'a tag that clashes with a selected field',
        r'nothing stops the user excluding a theme that a chosen '
        r'field is all about. The two instructions go to the model '
        r'together and it has to reconcile them.'),

    ...sec(r'how it is tested'),
    ...para('//',
        r'No test covers it. test/widget_test.dart checks the unlock '
        r'screen only. The notifier methods this card calls are not '
        r'unit-tested either. The verification is by use.'),

    ...sec(r'history'),
    ...pt('//', r'7a200e7, 2026-08-06 09:41', r'the scaffold commit.'),
    ...pt('//', r'89a9c12, 2026-08-06 09:58',
        r'the lucide_icons import became lucide_icons_flutter, which '
        r'fixed the web build; the x and plus icons here keep their '
        r'names.'),
  ],
);
