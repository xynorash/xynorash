import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/sidebar/level_selector_card.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'level_selector_card.dart — five levels, each with its own explanation'),
    cm('//', 'a hand-built radio list that shows the user what the model will be told'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'sidebar card: choose the AcademicLevel that calibrates the corpus'),
    kv('language', 'Dart / Flutter, ConsumerWidget (no local state)'),
    kv('size', '88 lines'),
    kv('history', '2 commits, 7a200e7 (scaffold) and 89a9c12 (icon package import)'),
    kv('reads', 'preferenceBlockProvider (level, language)'),
    kv('writes', 'setLevel() on the preference controller'),
    ...sec('why this card exists'),
    ...para('//',
        'The same subject is a different assignment for a first-year '
        'undergraduate and for a doctoral candidate. The sidebar '
        'therefore asks for a level, and the level changes what the '
        'model is allowed to propose: how deep the historiography, '
        'whether manuscripts in ancient languages are in play, how '
        'large the primary corpus. Without it, a request for '
        '“stained glass and theology” would have no way to say '
        'whether it wants a term paper or a thesis chapter.'),
    ...para('//',
        'Level is the one choice in the sidebar whose options need '
        'explaining. “Licence”, “Master”, “Mémoire” and “Doctorat” '
        'are labels a French student knows, but they do not tell '
        'you what the app will do differently for each. So this '
        'card, unlike the tone and mood chips, shows a sentence '
        'under every option, all five of them at all times.'),

    ...sec('five tiles instead of a radio widget'),
    ...code('dart', 'lib/widgets/sidebar/level_selector_card.dart · reading the enum', r'''
        children: AcademicLevel.values.map((level) {
          final isSelected = prefs.level == level;
          final label = prefs.language == 'fr'
              ? level.labelFr()
              : level.labelEn();
          final description = prefs.language == 'fr'
              ? level.descriptionFr()
              : level.descriptionEn();'''),
    ...para('//',
        'The card iterates AcademicLevel.values, so the list on '
        'screen is the enum, in declaration order: licence, master, '
        'memoire, phd, generalPublic. Adding a sixth level to '
        'enums.dart would add a sixth tile with no change here, '
        'provided the new value also implements the four string '
        'methods the card calls. The order is worth a look. Four '
        'values climb a ladder of training; the fifth, general '
        'public, is not a rung at all but a different reader, and '
        'it sits at the bottom, where a ladder would put “above '
        'doctorate”. That is a presentation quirk rather than a '
        'bug, since selecting it is as simple as selecting any '
        'other.'),
    ...para('//',
        'Notice also what is repeated. The language ternary '
        'prefs.language == "fr" ? x.labelFr() : x.labelEn() occurs '
        'twice here and three times in scope_tone_mood_card.dart. '
        'The field catalog has a tidy label(language) method on its '
        'classes; the enums do not, and every widget that shows an '
        'enum value re-does the branch. Five copies of the same '
        'two-way choice are a small invitation to a typo and the '
        'obvious candidate for a label(String language) method on '
        'each enum.'),
    ...code('dart', 'lib/widgets/sidebar/level_selector_card.dart · the selected look (trimmed)', r'''
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isSelected
                      ? colors.teal.withValues(alpha: 0.10)
                      : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? colors.teal : colors.border,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),'''),
    ...para('//',
        'Selection is shown three ways at once: a pale teal fill '
        '(10 per cent), a solid teal border that is half a pixel '
        'heavier than the grey one, and an icon swap, '
        'checkCircle2 versus an empty circle, coloured teal or muted '
        'grey. Redundant cues are a good habit for a choice that '
        'must never be ambiguous; they also mean a user who cannot '
        'distinguish the teal tint can still read the icon. The '
        'tile’s corner radius, 8 px, matches the InkWell’s, so the '
        'tap highlight follows the shape.'),
    ...code('dart', 'lib/widgets/sidebar/level_selector_card.dart · the tap and the icon (trimmed)', r'''
              onTap: () =>
                  ref.read(preferenceBlockProvider.notifier).setLevel(level),'''),
    ...code('dart', 'lib/widgets/sidebar/level_selector_card.dart · the radio icon', r'''
                    Icon(
                      isSelected
                          ? LucideIcons.checkCircle2
                          : LucideIcons.circle,
                      size: 18,
                      color: isSelected ? colors.teal : colors.inkMuted,
                    ),'''),
    ...para('//',
        'Why hand-build the tile instead of using Flutter’s '
        'RadioListTile? The code does not say. What the custom '
        'version buys is visible: a bordered, tinted block that '
        'uses the same teal recipe as the other selected states in '
        'the app, with a title and a description laid out in a '
        'column. What it costs is that nothing in the file marks '
        'the group as a radio group for assistive technology: a '
        'search of the sidebar directory finds no Semantics widget, '
        'and a plain InkWell does not announce a selected state by '
        'itself.'),

    ...sec('the description is the prompt'),
    ...para('//',
        'The sentences under the labels come from '
        'AcademicLevel.descriptionEn and descriptionFr in '
        'lib/models/enums.dart. Compare them with rule 5 of the '
        'system prompt in lib/services/mistral_client.dart, which '
        'tells the model what to do for each level.'),
    ...code('dart', 'lib/models/enums.dart · the English description of master', r'''
    AcademicLevel.master =>
      'Specialized historiography, situates the topic within a scholarly debate.','''),
    ...code('dart', 'lib/services/mistral_client.dart · rule 5, master', r'''
   - master: specialized historiography, situates the topic within a scholarly debate.'''),
    ...para('//',
        'They are the same sentence. The memoire, phd, licence and '
        'general-public lines match in the same way, with only '
        'small edits (the prompt says “no technical jargon”, the '
        'UI says “Jargon-free”). I read that as intent: the card '
        'shows the user, in plain words, the instruction the model '
        'will receive, so that choosing a level is choosing a '
        'documented behaviour and not a mystery. The cost is that '
        'the same text is maintained in two files, with nothing to '
        'check that they stay aligned. A test that builds the '
        'system prompt for every level and asserts the English '
        'description appears in it would remove that risk.'),
    ...para('//',
        'The wire value is a third spelling. The prompt and the '
        'preference JSON use apiValue, which is licence, master, '
        'memoire, phd and general_public; the general reader is the '
        'only value whose wire spelling differs from its enum name '
        '(generalPublic). The prompt’s opening line also sets a '
        'floor: it describes the user as an undergraduate '
        '(“licence-level and above”), which is consistent with '
        'licence being both the first tile and the default in '
        'PreferenceBlock.initial().'),
    ...para('//',
        'One domain note, from general knowledge rather than from the '
        'repo: in French higher education a mémoire is a piece of '
        'work, the research dissertation written inside a Master, '
        'not a degree. The app lists it as a level because what '
        'changes the model’s output is the shape of the project '
        '(“one precise, tractable problématique”), and that is a '
        'property of a mémoire rather than of a person’s training. '
        'The English label, “Thesis”, keeps that sense.'),

    ...sec('what a change does'),
    ...para('//',
        'Tapping a tile calls setLevel on the preference '
        'controller, which replaces the block with a copy that has '
        'the new level. Nothing is sent to the network; the choice '
        'takes effect on the next Generate or Refine, because both '
        'read the current block at call time. That second point '
        'matters for refinement: the refine request is built with '
        'the current preferences, not the ones in force when the '
        'topic was generated, so switching from licence to phd '
        'between a generation and a refinement changes the level '
        'the model is told to calibrate the refined topic to. '
        'Nothing in the UI warns about this.'),
    ...para('//',
        'There is no “unspecified” option. A level is always '
        'selected, tapping the selected tile re-selects it, and '
        'the model is always given one. That keeps rule 5 total: '
        'the prompt never has to say what to do when no level is '
        'given.'),

    ...sec('what changed over time'),
    ...para('//',
        'Two commits, both on 2026-08-06: 7a200e7 at 09:41 UTC '
        'created the card, and 89a9c12 at 09:58 UTC replaced the '
        'unmaintained lucide_icons import with lucide_icons_flutter, '
        'because the old package extended a Flutter class that had '
        'become final and broke the CI web build. The rest of the '
        'file is the first version; none of the later backend swap '
        'commits (Cerebras, Gemini, Mistral) touched it.'),

    ...sec('what is tested'),
    ...para('//',
        'Nothing in test/ covers the card or the enum. The enum has '
        'a fromApiValue helper that falls back to licence for '
        'unknown input; nothing calls it in the app, which the '
        'enums page notes, so it is also untested.'),

    ...sec('limits and what is next'),
    ...pt('//', 'two copies of the descriptions',
        'enums.dart and the prompt; they match today by authorship, '
        'not by check.'),
    ...pt('//', 'no semantics',
        'radio behaviour is communicated only by icon, border and '
        'fill.'),
    ...pt('//', 'five copies of the language ternary',
        'a label(language) method on each enum would remove them.'),
    ...pt('//', 'uneven bottom space',
        'every tile, including the last, has 8 px of bottom padding, '
        'so this card ends with 24 px under the last tile where '
        'other cards end with 16.'),
    ...pt('//', 'silent effect on refine',
        'changing level between generate and refine changes the '
        'refinement’s calibration without saying so.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
