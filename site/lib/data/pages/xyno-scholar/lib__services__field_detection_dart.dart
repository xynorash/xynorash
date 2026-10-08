import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/services/field_detection.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'field_detection.dart — suggest a field, never assume one'),
    cm('//', 'a 50-keyword, bilingual, no-network heuristic and its honest edges'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'spots fields implied by the free-text box but not yet selected'),
    kv('language', 'Dart, pure (no imports, no I/O)'),
    kv('size', '110 lines: 1 result class, 1 keyword table, 2 functions'),
    kv('table', '50 keywords (French and English) mapping to 7 field ids'),
    kv('used by', 'lib/widgets/sidebar/free_text_panel_card.dart'),
    kv('tests', 'none'),
    ...sec('the problem'),
    ...para('//',
        'The product’s core promise is that a topic must stand on '
        'every field the user selected and on no others. The system '
        'prompt in lib/services/mistral_client.dart says so twice: '
        'never drop a selected field, and never add one the user did '
        'not select. That raises a practical question about the '
        'free-text box. Someone who has selected History and Theology '
        'types “the frescoes of Santa Maria Novella”. The text '
        'implies art history. What should the app do?'),
    ...para('//',
        'There are three bad answers. Ignore it, and the model gets '
        'text that points outside the selected fields and has to '
        'guess. Silently add the field, and the app has broken its '
        'own rule about never assuming. Ask the model, and every '
        'keystroke costs a network call. The file takes a fourth '
        'route: a small deterministic function that runs locally on '
        'the text, finds words that imply a field the user has not '
        'selected, and offers a suggestion the user can accept or '
        'dismiss. The model-side rule 3, which allows exactly one '
        'clarifying question, is the backstop for what this heuristic '
        'misses.'),
    ...sec('what it returns'),
    ...code('dart', 'lib/services/field_detection.dart · the contract', r'''
/// Pure Dart, no-API-call detection of fields implied by free text but not
/// currently selected. Never assumes silently — callers must surface this as
/// a dismissible suggestion chip, not an automatic change.
class FieldDetectionMatch {
  final String fieldId;
  final String matchedKeyword;

  const FieldDetectionMatch(this.fieldId, this.matchedKeyword);
}'''),
    ...para('//',
        'The doc comment is the design rule: callers must surface a '
        'match as a dismissible suggestion, not as an automatic '
        'change. The result keeps the matched keyword next to the '
        'field id so a UI could explain why it is asking. The current '
        'card shows only the field’s label and does not use '
        'matchedKeyword; the data is there for a better explanation '
        'later.'),
    ...sec('the keyword table'),
    ...code('dart', 'lib/services/field_detection.dart · the table (trimmed)', r'''
/// keyword (normalized, no accents, lowercase) -> implied field id.
const Map<String, String> _fieldTriggerKeywords = {
  // Art history
  'tableau': 'art',
  'peinture': 'art',
  'peintre': 'art',
  ...
  'painting': 'art',
  'artwork': 'art',
  // Architecture
  'cathedrale': 'architecture',
  'basilique': 'architecture',
  'stained glass': 'architecture',
  // Music
  'musique': 'music',
  'symphonie': 'music',
  'opera': 'music',
  // Theology / religious studies
  'bible': 'catholic_theology',
  'evangile': 'catholic_theology',
  'pape': 'catholic_theology',
  ...'''),
    ...para('//',
        'Fifty keywords map to seven field ids: art (11 keywords), '
        'architecture (9), music (7), catholic_theology (12), law '
        '(4), political_science (3) and philosophy (4). Every target '
        'id exists in the field catalog in '
        'lib/models/field_catalog.dart. Each list is bilingual, '
        'French first and then English, which matches an app whose '
        'default interface language is French and which has an '
        'English mode. The words are concrete nouns that a person '
        'types when describing a subject (a painting, a cathedral, a '
        'gospel), not the names of the disciplines themselves.'),
    ...para('//',
        'Two things the table is not. It is not complete: the catalog '
        'has 22 selectable fields, and only seven can be suggested. '
        'History, which is selected by default, is not a target at '
        'all, nor are literature, church history or biblical studies. '
        'And it is not learned from anything: the comment above the '
        'table fixes its convention (lowercase, no accents) and the '
        'rest is the author’s judgement, with no data behind the '
        'list.'),
    ...sec('normalising the text'),
    ...code('dart', 'lib/services/field_detection.dart · stripping diacritics', r'''
String _stripDiacritics(String input) {
  const from = 'àâäáãåèéêëìíîïòóôöõùúûüçñÀÂÄÁÃÅÈÉÊËÌÍÎÏÒÓÔÖÕÙÚÛÜÇÑ';
  const to = 'aaaaaaeeeeiiiiooooouuuucnAAAAAAEEEEIIIIOOOOOUUUUCN';
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    final index = from.indexOf(char);
    buffer.write(index >= 0 ? to[index] : char);
  }'''),
    ...para('//',
        'French users type with and without accents, and a keyword '
        'table written once should match both cathédrale and '
        'cathedrale. The function maps accented letters to plain ones '
        'with two parallel strings, a table lookup by index. It '
        'iterates over runes, not UTF-16 code units, so a character '
        'outside the basic plane cannot be split. The conversion is '
        'limited to the Latin-1 accents listed: a letter such as the '
        'oe ligature is not handled, and no keyword currently needs '
        'it.'),
    ...para('//',
        'One detail is redundant but harmless: the second half of '
        'each string covers the capital letters, but the caller '
        'lowercases the text before calling, so the capitals never '
        'occur.'),
    ...sec('the matcher'),
    ...code('dart', 'lib/services/field_detection.dart · detectImpliedFields', r'''
List<FieldDetectionMatch> detectImpliedFields(
  String freeText,
  List<String> selectedFieldIds,
) {
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

  return matches.values.toList();
}'''),
    ...para('//',
        'The loop walks the table once. A keyword is skipped when its '
        'field is already selected, which is the whole point of the '
        'function, and when its field already has a match, which '
        'gives at most one suggestion per field however many keywords '
        'hit. Because a Dart map literal keeps insertion order, the '
        'first keyword in the table that appears in the text is the '
        'one reported, and the suggestions come back in table order. '
        'Empty or whitespace-only input returns a constant empty list '
        'immediately.'),
    ...para('//',
        'The cost is fifty substring searches over a short string. It '
        'is called from the card’s build method on every rebuild, '
        'which is harmless at this size and removes any need for '
        'caching or a debounce.'),
    ...sec('the padding that does nothing'),
    ...para('//',
        'The normalised string is wrapped in a leading and a trailing '
        'space. That is the classic first step toward whole-word '
        'matching: if every keyword were also padded with spaces, a '
        'hit could only occur at a word boundary. But the keywords in '
        'the table carry no padding, so contains() is a plain '
        'substring test, and the two spaces change nothing except for '
        'multi-word keywords like “stained glass”, which would have '
        'matched anyway. The padding is a vestige of an intention, or '
        'a placeholder for one; the code does not say which.'),
    ...para('//',
        'Substring matching has a genuine advantage in French: '
        'peinture also matches peintures, and peintre also matches '
        'peintres, so plurals and some inflections are free. It also '
        'has a genuine cost, shown next.'),
    ...sec('what happens on real inputs'),
    ...para('//',
        'I ran the function itself with the Dart SDK on a set of '
        'strings, with History as the only selected field. The '
        'results show the trade-off clearly.'),
    ...pt('//', 'cooperation between guilds',
        'suggests music, because the keyword opera is inside the word '
        'cooperation.'),
    ...pt('//', 'a history of newspapers in Lyon',
        'suggests catholic_theology, because the keyword pape (the '
        'French word for pope) is inside newspapers. The word paper '
        'would trigger it as well.'),
    ...pt('//', 'selection of cathedral plans',
        'suggests political_science through election inside '
        'selection, together with architecture through cathedral.'),
    ...pt('//', 'étoile de Bethléem',
        'suggests art, because toile (canvas) is inside étoile '
        '(star).'),
    ...pt('//', 'hymnal tradition',
        'suggests music through hymn, which is arguably right.'),
    ...para('//',
        'Misses are the other half. The app’s own example texts show '
        'them. With the default fields selected, the French example '
        '“Les vitraux de la cathédrale de Chartres au XIIIe siècle” '
        'does produce a suggestion, architecture, but only because of '
        'cathédrale; the keyword vitrail does not match vitraux, '
        'since French forms that plural irregularly. The example '
        '“Pèlerinages médiévaux et architecture romane” produces no '
        'suggestion at all, because architecture itself is not a '
        'keyword; only building types are. The English example '
        '“Stained glass windows of Chartres Cathedral in the 13th '
        'century” matches cathedral.'),
    ...para('//',
        'So the function is high-recall for the words it knows and '
        'noisy for short stems. The design makes that tolerable: a '
        'wrong suggestion costs a click on the dismiss button, and a '
        'missed one is caught, at least some of the time, by the '
        'model’s rule 3.'),
    ...sec('how the card uses it'),
    ...para('//',
        'In lib/widgets/sidebar/free_text_panel_card.dart the result '
        'is filtered by a set of dismissed field ids, then drawn as '
        'one amber chip per match with the sentence prefix, the '
        'field’s label, an Add button and a close button. Add calls '
        'addField on the preference controller, which appends the id '
        'to the selected fields. Dismiss adds the id to the dismissed '
        'set.'),
    ...para('//',
        'The dismissed set is cleared every time the text changes, '
        'per the comment on the provider in '
        'lib/providers/preference_providers.dart: it holds ids the '
        'user dismissed so the chip does not reappear for that field '
        'until the text changes again. The effect is that dismissal '
        'is sticky only while the user is not typing. Edit one letter '
        'and a suggestion the user already refused comes back.'),
    ...sec('testing'),
    ...para('//',
        'There is no test file for this module. It is the most '
        'testable code in the app, a pure function of two arguments '
        'with no I/O, and it is also the code with the most behaviour '
        'that could regress unnoticed. Three tests would cover most '
        'of it: a selected field is never suggested, a field is '
        'suggested at most once, and accented and unaccented '
        'spellings match the same keyword. A regression test that '
        'records the known false positives would also turn them from '
        'folklore into a documented list.'),
    ...sec('limits and what could come next'),
    ...pt('//', 'precision',
        'the false positives above are real and come from the choice '
        'of substring search over word matching.'),
    ...pt('//', 'coverage',
        'seven of 22 fields, two languages, no synonyms and no '
        'multi-word concepts beyond three phrases.'),
    ...pt('//', 'padding unused',
        'either use it (pad the keywords too) or drop it.'),
    ...pt('//', 'keyword explanation',
        'show matchedKeyword in the chip so a user can see why a '
        'field was suggested.'),
    ...pt('//', 'word-boundary matching',
        'a regular expression with word boundaries, built once from '
        'the table, would remove the stem collisions at the price of '
        'losing the free plurals; storing explicit plural forms in '
        'the table would recover them.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
