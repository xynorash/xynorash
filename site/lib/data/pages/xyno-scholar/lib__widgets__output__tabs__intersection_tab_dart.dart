import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/output/tabs/intersection_tab.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'intersection_tab.dart — why these fields belong in one topic'),
    cm('//', r'the shortest tab, and the one that carries the app’s promise'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'first tab of a narrow topic: the fields and how they meet'),
    kv(r'language', r'Dart / Flutter, one stateless widget'),
    kv(r'size', r'48 lines, 1 commit, never edited'),
    kv(r'input', r'a NarrowTopic, the list of field ids, the language'),
    kv(r'history', r'7a200e7 (2026-08-06 09:41)'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'Xyno Scholar is built on one rule that appears twice in the '
        r'system prompt. Rule 1: “Never drop a selected field. … EVERY '
        r'proposed subject must genuinely engage ALL of these fields '
        r'substantively”. Rule 2: never add a field, and never '
        r'assume one field implies another. The app is for '
        r'interdisciplinary topics, so a subject that touches '
        r'only one of your fields is a failure. This tab is the place '
        r'where the claim is made visible: here are the fields, and here '
        r'is the model’s explanation of how the topic sits across all of '
        r'them.'),

    ...sec(r'the widget, in full'),
    ...code('dart', r'lib/widgets/output/tabs/intersection_tab.dart · lines 7-48', r'''
class IntersectionTab extends StatelessWidget {
  final NarrowTopic topic;
  final List<String> fields;
  final String language;

  const IntersectionTab({
    super.key,
    required this.topic,
    required this.fields,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: fields.map((fieldId) {
              return Chip(
                label: Text(
                  fieldLabel(fieldId, language),
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: colors.teal.withValues(alpha: 0.10),
                side: BorderSide(color: colors.teal.withValues(alpha: 0.3)),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          MarkdownText(topic.fieldsIntersectionExplanation),
        ],
      ),
    );
  }
}'''),
    ...para('//',
        r'Two things are drawn: a row of chips and a block of prose. '
        r'There is no state and no logic beyond a lookup. Both the '
        r'topic and the field list are passed in. They are separate '
        r'arguments on purpose. NarrowTopic does not carry the '
        r'fields; they belong to the response as a whole '
        r'(fieldsCovered), so narrow_topic_view.dart passes them in '
        r'next to the topic.'),

    ...sec(r'the chips'),
    ...para('//',
        r'Each field id goes through fieldLabel(fieldId, language) from '
        r'models/field_catalog.dart. That function walks the default '
        r'catalog, the list of categories and fields, and returns the '
        r'French or English label of the first id that matches. If '
        r'nothing matches it returns the id itself. That is the '
        r'important detail, because the sidebar lets the user add '
        r'custom fields: field_selector_card.dart lowercases the '
        r'text and turns whitespace into underscores before storing '
        r'it. So a custom field typed as “Medieval Law” is stored, and '
        r'shown on this tab, as medieval_law. The built-in fields get '
        r'proper labels; custom ones show their raw id. It works, '
        r'and it is a little rough.'),
    blank,
    ...para('//',
        r'The chip colours come from the theme, not from literals: '
        r'teal at 10 percent for the fill and 30 percent for the '
        r'border. The sidebar’s selected-field chips use teal too, at '
        r'12 and 40 percent. The same colour in both places ties the '
        r'chips on this tab to the selection that produced them.'),

    ...sec(r'the explanation'),
    ...para('//',
        r'MarkdownText(topic.fieldsIntersectionExplanation) renders the '
        r'model’s answer. The name of the field in the model class is '
        r'the same long name, and it defaults to an empty string if '
        r'the model leaves it out, so a missing explanation shows as '
        r'an empty space under the chips, not an error. The renderer '
        r'is the shared one, whose own doc comment lists this field '
        r'first among the prose fields it serves. It decodes HTML '
        r'entities as a safety net and opens links outside the app.'),

    ...sec(r'edge cases'),
    ...pt('//', r'empty field list',
        r'the Wrap draws nothing and the explanation stands alone. In '
        r'practice the sidebar refuses to drop below one selected '
        r'field (toggleField returns early at one), so an empty list '
        r'should not reach here.'),
    ...pt('//', r'fields the model did not engage',
        r'the chips show the response’s fieldsCovered, which the prompt '
        r'tells the model to set to “the full list of fields you '
        r'engaged with”. The tab shows what the model reports, not a '
        r'check that it did. The rule is enforced by the prompt, not by '
        r'code.'),
    ...pt('//', r'after a refine',
        r'the provider keeps the earlier fieldsCovered when it '
        r'replaces the topic, so the chips do not change when the '
        r'explanation does.'),

    ...sec(r'how it is tested'),
    ...para('//',
        r'No widget test covers it. The parse of '
        r'fieldsIntersectionExplanation is exercised by '
        r'test/mistral_client_test.dart through the narrow topic '
        r'fixtures; the rendering is verified by looking at the app.'),

    ...sec(r'history'),
    ...pt('//', r'7a200e7, 2026-08-06 09:41',
        r'the scaffold commit. The file has not been touched by the '
        r'nine commits since, not even by the icon package swap, '
        r'because it imports no icons.'),
  ],
);
