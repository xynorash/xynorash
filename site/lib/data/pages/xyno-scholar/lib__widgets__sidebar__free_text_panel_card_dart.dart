import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/sidebar/free_text_panel_card.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'free_text_panel_card.dart — the one place the user types a sentence'),
    cm('//', 'a text box, a local second opinion on it, and four examples'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'sidebar card: optional free-text angle, implied-field suggestions, examples'),
    kv('language', 'Dart / Flutter, ConsumerStatefulWidget'),
    kv('size', '162 lines'),
    kv('history', '2 commits, 7a200e7 (scaffold) and 89a9c12 (icon package import)'),
    kv('state', 'freeTextProvider and dismissedFieldSuggestionsProvider'),
    kv('calls', 'detectImpliedFields() from lib/services/field_detection.dart'),
    ...sec('why this card exists'),
    ...para('//',
        'Every other control in the sidebar is a choice among '
        'options the app already knows. This one is the escape '
        'hatch: a period, a place, a specific object, the thing '
        'the user actually has in mind. Its title in strings.dart '
        'is “Angle ou mot-clé (optionnel)” / “Angle or keyword '
        '(optional)”, and its hint says “a period, a place, a '
        'specific object…”. The text goes to the model as '
        'freeTextFocus in the user turn, and rule 3 of the system '
        'prompt tells the model what to do when that text points '
        'at a discipline the user did not select.'),
    ...para('//',
        'That rule is where the card’s second job comes from. The '
        'prompt says that if the free text “conflicts with, or '
        'implies, a field that is NOT in the selected list”, the '
        'model must ask exactly one short clarifying question, '
        'while still returning usable topics. Doing that costs a '
        'whole request and a whole answer. The card therefore does '
        'a cheap version of the same check on the client, before '
        'any request, and offers the result as a suggestion the '
        'user can accept or wave away.'),

    ...sec('the text is state in a provider, the controller is a view of it'),
    ...code('dart', 'lib/widgets/sidebar/free_text_panel_card.dart · initState and the handler', r'''
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(freeTextProvider));
  }'''),
    ...code('dart', 'lib/widgets/sidebar/free_text_panel_card.dart · _setText', r'''
  void _setText(String value) {
    ref.read(freeTextProvider.notifier).state = value;
    ref.read(dismissedFieldSuggestionsProvider.notifier).state = {};
  }'''),
    ...para('//',
        'The truth about what the user typed is freeTextProvider, a '
        'plain StateProvider<String>. The TextEditingController is '
        'seeded from it when the card is built and from then on '
        'only mirrors the keyboard. Two consequences are easy to '
        'miss. First, the generate button never needs to ask this '
        'widget for its text: the controller in '
        'generation_provider.dart reads the provider directly. '
        'Second, the text survives the widget being rebuilt from '
        'scratch. home_screen.dart builds the sidebar in two '
        'different places in the tree, a Row on wide screens and a '
        'Column inside a scroll view below 900 px, so by Flutter’s '
        'element rules resizing a browser window across that '
        'threshold should recreate the card’s State. The text comes '
        'back because the new controller reads it from the '
        'provider; the open categories in the field card and any '
        'half-typed tag in the excluded card do not come back. I '
        'derived this from the code and did not exercise it.'),
    ...para('//',
        'The handler makes two writes on every keystroke: the new '
        'text, and an empty set for the dismissed suggestions. The '
        'doc comment on the provider says why: it holds ids the '
        'user has dismissed “so the chip doesn’t reappear for that '
        'field until the text changes again”. The reset implements '
        'the last four words literally. As a result, dismissal '
        'lasts only until the next character: refuse a suggestion, '
        'type one more letter, and it returns. That is the stated '
        'behaviour, and it is also the main usability edge in this '
        'file.'),

    ...sec('the local second opinion'),
    ...code('dart', 'lib/widgets/sidebar/free_text_panel_card.dart · computing suggestions', r'''
    final suggestions = detectImpliedFields(
      freeText,
      prefs.fields,
    ).where((m) => !dismissed.contains(m.fieldId)).toList();'''),
    ...para('//',
        'The call is made inside build, on every rebuild, with the '
        'current text and the current selection. There is no '
        'debounce, no caching and no async: the function is a '
        'pure scan of a table of 50 keywords '
        '(documented on the field_detection page), so the cost is '
        'invisible. Passing the selection in has a pleasant effect '
        'for free: the moment the user accepts a suggestion, the '
        'field joins prefs.fields, the function stops reporting '
        'it, and the row disappears with no extra state.'),
    ...code('dart', 'lib/widgets/sidebar/free_text_panel_card.dart · one suggestion row (trimmed)', r'''
                decoration: BoxDecoration(
                  color: colors.amber.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colors.amber.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.lightbulb, size: 15, color: colors.amber),
                    const SizedBox(width: 8),'''),
    ...para('//',
        'Each match becomes an amber row with a lightbulb, a '
        'sentence assembled from three TextSpans (the prefix '
        '“Your text seems to mention”, the field’s label in bold, '
        'a full stop), a text button that calls addField, and a '
        'small cross that adds the id to the dismissed set. The '
        'button calls addField, which returns early if the id is '
        'already selected, so a double tap is harmless. The cross '
        'carries a tooltip, “Dismiss” / “Ignorer”; a search of the '
        'sidebar and tab directories finds no other tooltip (the '
        'other buttons are labelled by their text).'),
    ...para('//',
        'Amber is chosen on purpose, I think. In the palette, amber '
        'is the warm accent for emphasis, and the same recipe (0.10 '
        'fill, 0.4 border) appears in lib/widgets/output/'
        'output_panel.dart for the model’s own clarifying question, '
        'with a help-circle icon where this card has a lightbulb. '
        'So there are two layers that say the same thing in the '
        'same colour. The lightbulb is the client’s guess, shown '
        'while typing and free of charge. The help circle is the '
        'model’s question, shown after a request, and it is the '
        'backstop for everything the keyword table misses. The '
        'detector’s own doc comment states the rule they share: '
        'never assume silently; surface the implication as a '
        'dismissible suggestion.'),

    ...sec('examples, and a Flutter detail about controllers'),
    ...code('dart', 'lib/widgets/sidebar/free_text_panel_card.dart · the English examples', r'''
const _examplesEn = [
  'Stained glass windows of Chartres Cathedral in the 13th century',
  'The reception of the Bible in Italian Baroque painting',
  'The Council of Trent and sacred art',
  'Medieval pilgrimage routes and Romanesque architecture',
];'''),
    ...code('dart', 'lib/widgets/sidebar/free_text_panel_card.dart · tapping an example', r'''
              return ActionChip(
                label: Text(example, style: const TextStyle(fontSize: 12)),
                onPressed: () {
                  _controller.text = example;
                  _setText(example);
                },
              );'''),
    ...para('//',
        'The handler does two things that look redundant: it '
        'assigns the controller’s text and then calls _setText. '
        'The second call is not redundant. Flutter’s TextField '
        'reports onChanged only for edits made by the user; '
        'changing the controller’s text from code does not fire '
        'it. If the chip only assigned the controller, the box '
        'would show the example while freeTextProvider stayed '
        'empty, the Generate button would send nothing, and the '
        'suggestion logic would not run. Writing both is how the '
        'view and the state are kept in step when the change '
        'comes from the program rather than from the keyboard.'),
    ...para('//',
        'The examples are four per language, and all four sit in '
        'the territory of the default fields (history, Catholic '
        'theology, art): Chartres glass, the Bible in Baroque '
        'painting, the Council of Trent, pilgrimage routes. They '
        'are plain constants, picked by '
        'prefs.language == "fr", so switching language swaps the '
        'set at once. A French user sees, for example, “Le concile '
        'de Trente et l’art sacré” where the English set has “The '
        'Council of Trent and sacred art”.'),

    ...sec('what the detector says about the examples'),
    ...para('//',
        'Since the examples are the first things a visitor is '
        'likely to click, I ran the real detectImpliedFields '
        'against all eight strings with the default selection '
        '(history, catholic_theology, art). Exactly two produce a '
        'suggestion, the first of each language, and both suggest '
        'architecture, from the keywords cathedrale and cathedral. '
        'The other six produce none: the Bible and painting '
        'examples are already covered by the defaults, and '
        '“Medieval pilgrimage routes and Romanesque architecture” '
        'matches nothing, because the table has no entry for the '
        'word architecture itself, only for buildings such as '
        'cathedral, abbey and basilica.'),
    ...para('//',
        'With only history selected, the picture changes and a '
        'bilingual wrinkle appears. The French “Le concile de Trente '
        'et l’art sacré” suggests catholic_theology from the '
        'keyword concile; its English twin, “The Council of Trent '
        'and sacred art”, suggests nothing, because the table has '
        'concile but no council. The same idea gets a suggestion '
        'in one language and not in the other. It is a small, '
        'measurable inconsistency, and it points at the real '
        'limit of a hand-written keyword table.'),
    ...para('//',
        'The same table produces false positives from substrings. '
        'With the defaults selected, “cooperation between guilds” '
        'suggests music (the keyword opera is inside it) and '
        '“selection of manuscripts” suggests political_science '
        '(election is inside it). The field_detection page lists '
        'more. The user-facing cost is one click on the cross, '
        'and since dismissal resets on the next keystroke, '
        'sometimes more than one.'),

    ...sec('where the text goes'),
    ...code('dart', 'lib/services/mistral_client.dart · the user turn (trimmed)', r'''
      if (freeText.trim().isNotEmpty) 'freeTextFocus': freeText.trim(),'''),
    ...para('//',
        'The key is only sent when there is text, so an untouched '
        'box leaves no trace in the request. There is one flow '
        'that ignores the box entirely: the deep-dive button on a '
        'broad topic calls the controller’s deepDive, which passes '
        'the topic’s keyKeywords joined with commas as the free '
        'text, plus the topic title, and does not read the provider. '
        'The text typed in this card therefore steers only the '
        'first search, not the follow-up.'),

    ...sec('what changed over time'),
    ...para('//',
        'Two commits, both on 2026-08-06: 7a200e7 at 09:41 UTC '
        'created the card, and 89a9c12 at 09:58 UTC swapped the '
        'lucide_icons import for lucide_icons_flutter to repair '
        'the web build. The card never learned about the backend '
        'swaps that followed (Cerebras, Gemini, then Mistral behind '
        'a Cloudflare Worker), and had no reason to: it writes two '
        'providers and reads one function.'),

    ...sec('what is tested'),
    ...para('//',
        'Nothing in test/ builds this card, and nothing tests '
        'field_detection.dart, the more valuable target. A widget '
        'test could type “Chartres cathedral” into the box with '
        'the defaults and expect one suggestion row, tap the cross, '
        'expect it gone, type a letter, expect it back. That test '
        'would pin the reset-on-keystroke behaviour and force a '
        'decision about whether it is desired.'),

    ...sec('limits and what is next'),
    ...pt('//', 'dismissal is short-lived',
        'any keystroke brings a refused suggestion back; keeping '
        'the dismissed set until the field leaves the text would '
        'fix it.'),
    ...pt('//', 'the label hides the cause',
        'the row says “Your text seems to mention Architecture” '
        'but not which word triggered it; the match already '
        'carries the keyword, and the card does not show it.'),
    ...pt('//', 'a fixed table',
        'bilingual gaps (council) and substring hits (opera in '
        'cooperation) cannot be fixed without editing the table.'),
    ...pt('//', 'no clear button',
        'emptying the box means selecting and deleting the text.'),
    ...pt('//', 'examples cannot be edited',
        'they are constants; a user cannot save a favourite angle.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
