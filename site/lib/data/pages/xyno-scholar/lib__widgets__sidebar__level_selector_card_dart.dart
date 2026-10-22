import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/sidebar/level_selector_card.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'level_selector_card.dart — how hard should the topic be'),
    cm('//', r'five academic levels as selectable cards with a sentence each'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'choose the AcademicLevel in PreferenceBlock.level'),
    kv(r'language', r'Dart / Flutter, a stateless ConsumerWidget'),
    kv(r'size', r'88 lines, 2 commits'),
    kv(r'options', r'licence, master, memoire, phd, generalPublic'),
    kv(r'default', r'licence, set by PreferenceBlock.initial()'),
    kv(r'history', r'7a200e7 (2026-08-06 09:41), 89a9c12 (09:58)'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'The same subject is a different task at different levels. '
        r'“Stained glass in Chartres” is a weekend read for a '
        r'curious person, a bounded undergraduate paper, or a '
        r'doctorate with a large archive. The model needs to be told '
        r'which. This card sets that, and it does it in a way that '
        r'doesn’t just say the name of a level. Each option is shown '
        r'with a one-sentence description of what the level means for '
        r'the topic, so the user chooses by meaning.'),

    ...sec(r'the levels and their sentences'),
    ...code('dart', r'lib/models/enums.dart · lines 53-65', r'''
  String descriptionEn() => switch (this) {
    AcademicLevel.licence =>
      'Bounded, accessible corpus — no paleography or ancient languages required.',
    AcademicLevel.master =>
      'Specialized historiography, situates the topic within a scholarly debate.',
    AcademicLevel.memoire =>
      'Focused methodology built around one precise, tractable problématique.',
    AcademicLevel.phd =>
      'Original archival contribution, extensive and demanding primary corpus.',
    AcademicLevel.generalPublic =>
      'Jargon-free, accessible to a curious non-specialist reader.',
  };'''),
    ...para('//',
        r'The sentences are in the enum, in French and English, and '
        r'this card only displays them. They are worth reading beside '
        r'the system prompt, which holds the same calibrations for '
        r'the model. The prompt’s line for licence reads “bounded, '
        r'accessible corpus, no paleography or ancient-language '
        r'skills required”, and the card’s says the same in nearly '
        r'the same words. So the user is shown what the model is '
        r'told, and the promise on the screen and the instruction '
        r'behind it are one text twice. That is a good habit for any '
        r'interface that drives a model: the labels double as '
        r'documentation of the prompt.'),
    blank,
    ...para('//',
        r'The order of the enum is the order on screen: licence, master, '
        r'memoire, phd, generalPublic. Grand public comes last, '
        r'although it is the easiest level, because it is not on '
        r'the academic ladder. It is a different axis of audience.'),

    ...sec(r'the widget'),
    ...code('dart', r'lib/widgets/sidebar/level_selector_card.dart · lines 10-36', r'''
class LevelSelectorCard extends ConsumerWidget {
  const LevelSelectorCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferenceBlockProvider);
    final colors = context.colors;
    final s = AppStrings(prefs.language);

    return SidebarCard(
      title: s.levelTitle,
      child: Column(
        children: AcademicLevel.values.map((level) {
          final isSelected = prefs.level == level;
          final label = prefs.language == 'fr'
              ? level.labelFr()
              : level.labelEn();
          final description = prefs.language == 'fr'
              ? level.descriptionFr()
              : level.descriptionEn();

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () =>
                  ref.read(preferenceBlockProvider.notifier).setLevel(level),'''),
    ...para('//',
        r'This is a ConsumerWidget, not a ConsumerStatefulWidget like '
        r'the cards with text boxes, because it owns nothing. The '
        r'selected level is in the preference block, so the build '
        r'method only reads it, compares, and writes back with '
        r'setLevel. Options are generated from AcademicLevel.values, so '
        r'adding a sixth level to the enum adds a sixth card here with '
        r'no change to this file, provided the enum’s switches get '
        r'the new case (Dart’s exhaustive switch forces that at '
        r'compile time). The language test is a plain comparison to '
        r'fr, with anything else falling to English.'),

    ...sec(r'selected and unselected'),
    ...code('dart', r'lib/widgets/sidebar/level_selector_card.dart · lines 37-58', r'''
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isSelected
                      ? colors.teal.withValues(alpha: 0.10)
                      : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? colors.teal : colors.border,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isSelected
                          ? LucideIcons.checkCircle2
                          : LucideIcons.circle,
                      size: 18,
                      color: isSelected ? colors.teal : colors.inkMuted,
                    ),'''),
    ...para('//',
        r'A selected card gets a faint teal fill, a teal border one '
        r'half pixel thicker, and a filled check icon; the others '
        r'have a neutral border and an empty circle. Three cues '
        r'point the same way (colour, thickness, icon), so the '
        r'selection does not rely on colour alone. The icon is the '
        r'radio-button convention, drawn by hand: this is a '
        r'single-choice list, but it is built from an InkWell and a '
        r'Container and not from Flutter’s own radio widgets. The '
        r'file does not say why; one effect is that the whole card '
        r'is the click target and the description can sit beside '
        r'the label.'),
    blank,
    ...para('//',
        r'A detail I would check by running it: the InkWell’s ripple is '
        r'painted on the Material underneath, and the child Container '
        r'has its own decoration drawn above it. On an unselected '
        r'card the fill is transparent, so a ripple should show '
        r'through; on a selected card the tint would cover part of it. '
        r'I did not run the app to see it.'),

    ...sec(r'the text'),
    ...code('dart', r'lib/widgets/sidebar/level_selector_card.dart · lines 60-78', r'''
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: Theme.of(
                              context,
                            ).textTheme.titleSmall?.copyWith(color: colors.ink),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            description,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.inkMuted),
                          ),
                        ],
                      ),
                    ),'''),
    ...para('//',
        r'The label is in the title style, the description is smaller '
        r'and muted. The Expanded makes the text wrap inside the card. '
        r'The styles come from the theme, so the card follows any '
        r'change to app_theme.dart without edits here.'),

    ...sec(r'edge cases'),
    ...pt('//', r'always one selected',
        r'level is a single enum value in the preference block, never '
        r'null. A user cannot deselect: tapping the selected card '
        r'sets the same value again.'),
    ...pt('//', r'wire values',
        r'apiValue gives the strings sent to the model. The enum’s '
        r'fromApiValue falls back to licence for an unknown string, '
        r'the same as the default.'),
    ...pt('//', r'a level that is only a label',
        r'the five names go to the model as one word, for example '
        r'general_public, and the prompt defines each. The card’s '
        r'sentence is not sent, only the name.'),

    ...sec(r'how it is tested'),
    ...para('//',
        r'No test covers this card. Nothing in test/ constructs it. '
        r'The enum’s translations and the apiValue mapping have no '
        r'test either.'),

    ...sec(r'history'),
    ...pt('//', r'7a200e7, 2026-08-06 09:41', r'the scaffold commit.'),
    ...pt('//', r'89a9c12, 2026-08-06 09:58',
        r'import swap to lucide_icons_flutter, to fix the web build. '
        r'checkCircle2 and circle are the icons this file uses.'),
  ],
);
