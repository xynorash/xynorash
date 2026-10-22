import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/sidebar/free_text_panel_card.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'free_text_panel_card.dart — say it in your own words'),
    cm('//', r'an angle box that listens, and offers to add the field it hears'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'optional free-text focus, plus implied-field suggestions'),
    kv(r'language', r'Dart / Flutter, a ConsumerStatefulWidget with Riverpod'),
    kv(r'size', r'162 lines, 2 commits'),
    kv(r'state it owns', r'freeTextProvider and dismissedFieldSuggestionsProvider'),
    kv(r'uses', r'detectImpliedFields (services/field_detection.dart)'),
    kv(r'history', r'7a200e7 (2026-08-06 09:41), 89a9c12 (09:58)'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'Checkboxes can say which fields; they cannot say which '
        r'cathedral. The last sidebar card is an open text box, titled '
        r'“Angle or keyword (optional)”, with the hint “e.g. a '
        r'period, a place, a specific object…”. What you type is sent '
        r'to the model as freeTextFocus. But the card has a second job, '
        r'which is the interesting one. Free text can contradict the '
        r'field selection. Type “the paintings of Rubens” with only '
        r'history and theology selected, and your sentence implies art, '
        r'a field you have not chosen. The system prompt has a rule '
        r'for this (rule 3: ask exactly one clarifying question). This '
        r'card answers it earlier and without a model call.'),

    ...sec(r'the examples'),
    ...code('dart', r'lib/widgets/sidebar/free_text_panel_card.dart · lines 11-23', r'''
const _examplesFr = [
  'Les vitraux de la cathédrale de Chartres au XIIIe siècle',
  'La réception de la Bible dans la peinture baroque italienne',
  'Le concile de Trente et l\'art sacré',
  'Pèlerinages médiévaux et architecture romane',
];

const _examplesEn = [
  'Stained glass windows of Chartres Cathedral in the 13th century',
  'The reception of the Bible in Italian Baroque painting',
  'The Council of Trent and sacred art',
  'Medieval pilgrimage routes and Romanesque architecture',
];'''),
    ...para('//',
        r'Four example topics per language, shown as chips that fill '
        r'the box with one tap. They are all in the territory of the '
        r'default selection, history, Catholic theology and art: '
        r'Chartres, the Bible in painting, Trent and sacred art, '
        r'pilgrimage and Romanesque architecture. A new user sees '
        r'what the app was made to find. The last one, '
        r'architecture, is not in the default selection, so '
        r'tapping it should make the card offer to add that field. '
        r'It shows the suggestion feature on the first click. That '
        r'is my reading of the choice, since the file does not say '
        r'it.'),

    ...sec(r'owning the text'),
    ...code('dart', r'lib/widgets/sidebar/free_text_panel_card.dart · lines 32-50', r'''
class _FreeTextPanelCardState extends ConsumerState<FreeTextPanelCard> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(freeTextProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setText(String value) {
    ref.read(freeTextProvider.notifier).state = value;
    ref.read(dismissedFieldSuggestionsProvider.notifier).state = {};
  }'''),
    ...para('//',
        r'The text lives in a provider, not in the widget. The '
        r'controller is created in initState from the provider’s '
        r'value, so if the card is rebuilt from nothing (a '
        r'layout change that remounts the sidebar, for example) the '
        r'text is still there. The generation provider reads '
        r'freeTextProvider directly when you press generate, which '
        r'is why the value must be in shared state and not trapped in '
        r'a controller. The pattern is the reverse of the excluded-'
        r'themes card, whose list is in the notifier and whose '
        r'half-typed text is not.'),
    blank,
    ...para('//',
        r'_setText has a second line that matters: every change to the '
        r'text empties the set of dismissed suggestions. The provider’s '
        r'own comment gives the intent: a dismissed chip should not '
        r'reappear “until the text changes again”. In code, “changes” '
        r'means any keystroke. If you dismiss “add Architecture” and '
        r'type another letter, the suggestion returns while the keyword '
        r'is still in the sentence. That is consistent with the '
        r'comment, and a little eager. It means a dismissal lasts '
        r'only until the next key.'),

    ...sec(r'detecting a field'),
    ...code('dart', r'lib/widgets/sidebar/free_text_panel_card.dart · lines 61-64', r'''
    final suggestions = detectImpliedFields(
      freeText,
      prefs.fields,
    ).where((m) => !dismissed.contains(m.fieldId)).toList();'''),
    ...para('//',
        r'On every build, the card asks detectImpliedFields for the '
        r'fields that the text implies and the selection lacks, then '
        r'drops the dismissed ones. The function is pure Dart, with '
        r'no network. Its doc comment states the rule: it must '
        r'“never assume silently”, so callers show a dismissible chip '
        r'and do not change the selection themselves. This card is '
        r'that caller.'),
    blank,
    ...code('dart', r'lib/services/field_detection.dart · lines 96-109', r'''
  if (freeText.trim().isEmpty) return const [];

  final normalized = ' ${_stripDiacritics(freeText.toLowerCase())} ';
  final selected = selectedFieldIds.toSet();
  final matches = <String, FieldDetectionMatch>{};

  _fieldTriggerKeywords.forEach((keyword, fieldId) {
    if (selected.contains(fieldId) || matches.containsKey(fieldId)) return;
    if (normalized.contains(keyword)) {
      matches[fieldId] = FieldDetectionMatch(fieldId, keyword);
    }
  });

  return matches.values.toList();'''),
    ...para('//',
        r'The algorithm is a table scan. The text is lowercased and '
        r'stripped of accents, so “cathédrale” matches the keyword '
        r'cathedrale. A table of 50 keywords, French and English, '
        r'maps each to a field id: tableau, peinture, painting to '
        r'art; cathedrale, vitrail, abbey to architecture; bible, '
        r'concile, papal to catholic_theology; and so on across '
        r'music, law, political science and philosophy. A field '
        r'already selected is skipped, and each field is suggested '
        r'at most once.'),
    blank,
    ...para('//',
        r'One limit in the code is worth knowing. The text is padded '
        r'with a space on each side, which suggests word-boundary '
        r'matching was intended, but none of the keywords carry '
        r'spaces at the ends, and the test is plain contains(). So '
        r'it matches inside words. Reading the code, “selection” '
        r'would trigger election (political science), “cooperation” '
        r'would trigger opera (music), and “étoile” would trigger '
        r'toile (art). I have not run it on these; I am reading the '
        r'condition. The cost is a spurious suggestion chip, which the '
        r'user can dismiss, and the design (never change silently) '
        r'is what keeps that cheap.'),

    ...sec(r'the suggestion row'),
    ...code('dart', r'lib/widgets/sidebar/free_text_panel_card.dart · lines 100-136', r'''
                        TextSpan(
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: colors.ink),
                          children: [
                            TextSpan(text: '${s.fieldSuggestionPrefix} '),
                            TextSpan(
                              text: label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        ref
                            .read(preferenceBlockProvider.notifier)
                            .addField(match.fieldId);
                      },
                      child: Text(s.addField),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 14),
                      tooltip: s.dismiss,
                      onPressed: () {
                        ref
                            .read(dismissedFieldSuggestionsProvider.notifier)
                            .state = {
                          ...dismissed,
                          match.fieldId,
                        };
                      },
                    ),'''),
    ...para('//',
        r'Each suggestion is a row in amber, the same colour the '
        r'bibliography tab uses for its type chip, with a lightbulb '
        r'icon: “Your text seems to mention Architecture.” followed '
        r'by two actions. The sentence is built from three spans so '
        r'the field name can be bold. “Add field” calls addField on '
        r'the shared preferences, which also makes the suggestion '
        r'disappear on the next build, since the field is now '
        r'selected. The x adds the field id to the dismissed set, '
        r'copied and extended, never mutated, with the tooltip '
        r'“Dismiss” (Ignorer).'),

    ...sec(r'the example chips'),
    ...code('dart', r'lib/widgets/sidebar/free_text_panel_card.dart · lines 148-156', r'''
            children: examples.map((example) {
              return ActionChip(
                label: Text(example, style: const TextStyle(fontSize: 12)),
                onPressed: () {
                  _controller.text = example;
                  _setText(example);
                },
              );
            }).toList(),'''),
    ...para('//',
        r'Tapping an example does two things: it sets the controller, '
        r'so the box shows the text, and calls _setText, so the '
        r'provider and the suggestion logic see it. Setting '
        r'controller.text does not fire onChanged, so the second '
        r'call is needed. Forgetting it would leave the box and the '
        r'state out of step, a classic Flutter bug.'),

    ...sec(r'edge cases'),
    ...pt('//', r'empty or blank text',
        r'detectImpliedFields returns an empty list at once, and the '
        r'card shows no suggestions.'),
    ...pt('//', r'language of the keywords',
        r'the table mixes French and English keywords, independent of '
        r'the interface language, so a French sentence in an English '
        r'UI still gets suggestions.'),
    ...pt('//', r'a Catholic default',
        r'the theology keywords (pape, concile, encyclique) all map to '
        r'catholic_theology, and no keyword maps to the more general '
        r'religious_studies. That is consistent with what the app '
        r'was first built for.'),

    ...sec(r'how it is tested'),
    ...para('//',
        r'Nothing tests this card or detectImpliedFields. The test '
        r'folder has the client, the sanitiser and the unlock screen. '
        r'The substring matching described above is the sort of thing '
        r'a test with a handful of sentences would pin down.'),

    ...sec(r'history'),
    ...pt('//', r'7a200e7, 2026-08-06 09:41', r'the scaffold commit.'),
    ...pt('//', r'89a9c12, 2026-08-06 09:58',
        r'the lucide_icons_flutter import; the lightbulb and x icons '
        r'keep their names.'),
  ],
);
