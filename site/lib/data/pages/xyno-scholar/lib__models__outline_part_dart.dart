import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/models/outline_part.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'outline_part.dart — one third of a suggested plan'),
    cm('//', 'a numeral, a title, a description: the smallest model in the app'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'one part of a narrow topic’s three-part outline (I, II or III)'),
    kv('language', 'Dart'),
    kv('size', '25 lines'),
    kv('history', 'one commit, 7a200e7 (2026-08-06); unchanged since'),
    kv('lives inside', 'NarrowTopic.suggestedStructure, rendered by outline_tab.dart'),
    ...sec('why this file exists'),
    ...para('//',
        'A topic and a bibliography tell a student what to study. '
        'The outline tells them how a written work about it could be '
        'built. The prompt asks for exactly three parts, numbered '
        'with Roman numerals, and the tab that shows them is titled '
        '“Plan en 3 parties” in French and “3-Part Outline” in '
        'English (lib/l10n/strings.dart). The form, together with '
        'the words around it (mémoire, problématique, licence), '
        'matches the French-first defaults of the app rather than '
        'any generic notion of an outline, and this class is its '
        'unit.'),
    ...code('dart', 'lib/models/outline_part.dart · the whole data class', r'''
class OutlinePart {
  final String partNumber; // I | II | III
  final String title;
  final String description;

  const OutlinePart({
    required this.partNumber,
    required this.title,
    required this.description,
  });'''),

    ...sec('the numeral comes from the model'),
    ...para('//',
        'partNumber is a String that holds ‘I’, ‘II’ or ‘III’, not an '
        'int. The prompt’s schema spells the allowed values out: '
        '"partNumber": "I"|"II"|"III". It is worth comparing with the '
        'other numbered list in the app. The broad topic cards are '
        'numbered by the widget, which prints the loop index plus one '
        '(see broad_topics_list.dart); the outline parts are numbered '
        'by the model, and the widget prints whatever string it '
        'received. The difference is principled. Broad options are an '
        'unordered menu, so the number is a mere label and the app '
        'can generate it. The outline parts are a sequence with '
        'meaning, I before II before III, and the numeral is data '
        'the model chose together with the title.'),
    ...code('dart', 'lib/services/mistral_client.dart · outline in the JSON schema', r'''
    "suggestedStructure": [
      { "partNumber": "I"|"II"|"III", "title": string, "description": string }
    ]'''),
    ...para('//',
        'The consequence is that the app trusts the order of the '
        'array. It does not sort by partNumber, and if the model '
        'returned the parts as III, I, II the tab would show them '
        'in that order. For the three-element list the prompt '
        'demands this has never been a problem the repository '
        'records, and nothing in the tests exercises it.'),

    ...sec('parsing, again in the same three-line idiom'),
    ...code('dart', 'lib/models/outline_part.dart · fromJson', r'''
  factory OutlinePart.fromJson(Map<String, dynamic> json) {
    return OutlinePart(
      partNumber: json['partNumber']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
    );
  }'''),
    ...para('//',
        'The idiom is the one used by every model class in lib/models: '
        'read the key, convert with toString(), default to the empty '
        'string. For this class that means a part with no numeral '
        'draws an empty badge, and a part with no title draws an '
        'empty heading. The class does not know that three parts '
        'are expected; the count lives in two places that have '
        'nothing to do with it, the prompt and the Gemini-era '
        'schema that was removed (see narrow_topic.dart).'),

    ...sec('where it is shown'),
    ...para('//',
        'The tab turns each part into a card: a circle badge holding '
        'the numeral in the serif face and teal colour, then the '
        'title in serif and the description through the shared '
        'markdown widget. The description, like the bibliography '
        'relevance note and the intersection explanation, may contain '
        'light markdown, because the prompt’s formatting rule '
        'allows “bold/italic/short lists” in prose fields. The '
        'title may not: title fields are, per rule 8, plain text, '
        'and the tab renders them with a Text widget rather than a '
        'markdown one. The parser does nothing to enforce that; '
        'the widget’s choice of Text does.'),

    ...sec('persistence and the refine round trip'),
    ...para('//',
        'toJson writes the three keys under the same names. That '
        'serialization is used in two places, both through '
        'NarrowTopic.toJson: the notebook stores it as part of a '
        'saved topic, and the refine request shows it back to the '
        'model inside existingNarrowTopic. The refine instruction '
        'then insists the answer keep “3 suggestedStructure parts”, '
        'so a refinement that changes the thesis is expected to '
        'return a full replacement plan, not a diff. The summary '
        'of what changed lives in a separate string field on the '
        'topic, refinementSummary, not inside the parts.'),
    ...code('dart', 'lib/models/outline_part.dart · toJson', r'''
  Map<String, dynamic> toJson() => {
    'partNumber': partNumber,
    'title': title,
    'description': description,
  };'''),

    ...sec('what the tests prove'),
    ...para('//',
        'The narrow and refine tests in test/mistral_client_test.dart '
        'build three parts with partNumber I, II and III and assert '
        'only the count (hasLength(3)) for the narrow case. The '
        'refine test checks the refined title and the summary text. '
        'The numerals, the order and the description text are never '
        'asserted.'),

    ...sec('limits and what is next'),
    ...pt('//', 'order is trusted',
        'sorting by partNumber, or assigning numerals in the widget, '
        'would make the display independent of the array order.'),
    ...pt('//', 'count is not a property of the type',
        'the number three is enforced nowhere in Dart.'),
    ...pt('//', 'one structure only',
        'a three-part plan is the only shape on offer; a different '
        'tradition would need a schema change and a prompt change.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
