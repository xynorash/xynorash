import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/models/field_catalog.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'field_catalog.dart — 22 disciplines, and a label lookup that never fails'),
    cm('//', 'the list the sidebar offers, and the ids the model is told about'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'default catalog of selectable academic fields, grouped in five categories'),
    kv('language', 'Dart'),
    kv('size', '168 lines; 5 categories, 22 fields, each with French and English text'),
    kv('history', 'one commit, 7a200e7 (2026-08-06); unchanged since'),
    kv('wire format', 'only the field id travels to the model; labels and categories stay in the UI'),
    ...sec('why this file exists'),
    ...para('//',
        'The product idea is the intersection of fields: the default '
        'selection is History, Catholic Theology and Art History, and '
        'every proposal must engage all of them. For that the sidebar '
        'needs something to select from. This file is that list, and '
        'it is the reason a student who has never heard the word '
        '“fieldsCovered” can still see, on every generated topic, which '
        'disciplines it claims to touch.'),
    blank,
    ...para('//',
        'It is deliberately plain data. Two small value classes and one '
        'const list, with no behaviour beyond picking the French or the '
        'English string:'),
    ...code('dart', 'lib/models/field_catalog.dart · the two value classes (trimmed)', r'''
class FieldOption {
  final String id;
  final String labelFr;
  final String labelEn;
  ...
  String label(String language) => language == 'fr' ? labelFr : labelEn;
}

/// A collapsible category of related fields, shown in the sidebar checklist.
class FieldCategory {
  final String id;
  final String titleFr;
  final String titleEn;
  final List<FieldOption> fields;
  ...
  String title(String language) => language == 'fr' ? titleFr : titleEn;
}'''),
    ...para('//',
        'Anything that is not exactly ‘fr’ gets English. That is the '
        'same rule AppStrings uses (see lib/l10n/strings.dart), so the '
        'two stay consistent for free; it also means a typo in a '
        'language code degrades to English rather than to a crash.'),

    ...sec('the catalog itself'),
    ...para('//',
        'Five categories, listed in the order the sidebar shows them: '
        'Humanities & History (history, literature, philosophy, '
        'linguistics, archaeology); Theology & Religious Studies '
        '(catholic_theology, religious_studies, church_history, '
        'biblical_studies); Arts, Architecture & Culture (art, '
        'architecture, music, cinema); Social Sciences & Law (sociology, '
        'political_science, law, anthropology, economics); and Sciences, '
        'Environment & Interdisciplinary (environmental_history, '
        'history_of_science, geography, medicine_history).'),
    ...code('dart', 'lib/models/field_catalog.dart · one category', r'''
  FieldCategory(
    id: 'theology_religion',
    titleFr: 'Théologie & Sciences religieuses',
    titleEn: 'Theology & Religious Studies',
    fields: [
      FieldOption(
        id: 'catholic_theology',
        labelFr: 'Théologie catholique',
        labelEn: 'Catholic theology',
      ),
      FieldOption(
        id: 'religious_studies',
        labelFr: 'Sciences des religions',
        labelEn: 'Religious studies',
      ),
      FieldOption(
        id: 'church_history',
        labelFr: 'Histoire de l\'Église',
        labelEn: 'Church history',
      ),'''),
    ...para('//',
        'Two observations about what the list says about the product. '
        'First, it is a humanities catalog: the last category is named '
        '“Sciences”, but its four members are environmental history, '
        'history of science, geography and history of medicine. There is '
        'no natural-science discipline in the defaults, which matches '
        'the README’s description of a scholar working in History, '
        'Catholic Theology and Art History. Second, the ids are chosen '
        'to be words a model understands without help, because they are '
        'what the model actually reads.'),

    ...sec('ids are the contract, labels are decoration'),
    ...para('//',
        'When the user presses Generate, the selection reaches the '
        'model as a list of ids, not labels. The system prompt builds '
        'its first rule from them:'),
    ...code('dart', 'lib/services/mistral_client.dart · system prompt, rules 1 and 2 (wrapped)', r'''
1. Never drop a selected field. The user has selected exactly these fields: [$fieldsList].
EVERY proposed subject must genuinely engage ALL of these fields substantively
2. Never add a field the user did not select, and never assume one field implies another
Fields to actively avoid, if any: [$excludedList].'''),
    ...para('//',
        'With the default preferences the bracket reads [history, '
        'catholic_theology, art]. The prompt’s own example (‘theology '
        'does not imply art’) is phrased in the vocabulary of these '
        'ids. The reply comes back in the same vocabulary: '
        'broadTopics[].fieldsCovered and the top-level fieldsCovered '
        'are lists of ids, and the UI turns them back into labels. '
        'That return trip is the other half of this file.'),
    ...code('dart', 'lib/models/field_catalog.dart · fieldLabel', r'''
/// Look up a display label for any field id, including custom user-added
/// fields that aren't part of the default catalog (falls back to the id).
String fieldLabel(String fieldId, String language) {
  for (final category in kDefaultFieldCatalog) {
    for (final field in category.fields) {
      if (field.id == fieldId) return field.label(language);
    }
  }
  return fieldId;
}'''),
    ...para('//',
        'Returning the id when nothing matches is a small decision with '
        'two payoffs. It makes custom fields work without any '
        'registration step, and it makes the display robust to the '
        'model: if the reply says ‘Art history’ instead of ‘art’, the '
        'chip simply shows ‘Art history’. Four widgets call it: the '
        'selected-chips row and the suggestion banner in the sidebar, '
        'the chips on each broad topic, and the chips in the '
        'Intersection tab. The lookup is a linear scan over 22 items, '
        'run once per chip per build, which is nothing.'),

    ...sec('custom fields: “editable” has a catch'),
    ...para('//',
        'The doc comment on the catalog calls it a “default, editable '
        'catalog” and says users may add any custom field. In the '
        'code, the catalog is a const list and is never modified. A '
        'custom field is created by the text box at the bottom of '
        'FieldSelectorCard, which does this:'),
    ...code('dart', 'lib/widgets/sidebar/field_selector_card.dart · _submitCustomField', r'''
    final id = raw.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    ref.read(preferenceBlockProvider.notifier).addField(id);'''),
    ...para('//',
        'So a user who types “Musique médiévale” adds the id '
        'musique_médiévale to the selection. The model receives that '
        'string in rule 1, which is fine, since a language model reads '
        '“musique_médiévale” as well as any label. But the chip in the '
        'sidebar, which calls fieldLabel, shows the id itself, '
        'underscore and lowercase included, because the lookup finds '
        'nothing and falls back. The custom field is functionally '
        'complete and cosmetically raw.'),
    blank,
    ...para('//',
        'The same lookup labels the free-text suggestions. '
        'lib/services/field_detection.dart maps keywords to catalog '
        'ids (cathedral to architecture, hymn to music), and the '
        'amber banner in the sidebar names the suggested field by '
        'calling fieldLabel with the id it was given.'),

    ...sec('state kept next to the catalog'),
    ...para('//',
        'Category ids never leave the UI. The only consumer of '
        'FieldCategory.id is the sidebar’s set of expanded categories, '
        'seeded with the first category only:'),
    ...code('dart', 'lib/widgets/sidebar/field_selector_card.dart', r'''
  final Set<String> _expandedCategories = {kDefaultFieldCatalog.first.id};'''),
    ...para('//',
        'Notice the interaction with the defaults. The initial '
        'selection (history, catholic_theology, art) spans three '
        'categories, but only the first starts expanded. That works '
        'because the card shows the selected fields as removable '
        'chips above the catalog, so what is selected never depends on '
        'what is open. The catalog is for adding; the chip row is for '
        'seeing and removing.'),

    ...sec('what holds it together, and what does not'),
    ...para('//',
        'There is no test for this file. Nothing checks that ids are '
        'unique across categories, that each entry has both labels, or '
        'that the ids in the default selection actually exist in the '
        'catalog. The last point is the one that would bite: '
        'PreferenceBlock.initial() hard-codes three ids as strings '
        '(see preference_block.dart). Rename ‘art’ here and the '
        'default selection would still send it to the model but the '
        'chip would show the bare id.'),

    ...sec('limits and what is next'),
    ...pt('//', 'catalog is not editable',
        'the const list cannot be changed at runtime; custom fields '
        'live only in the selection and show as snake_case ids.'),
    ...pt('//', 'a label for custom fields',
        'keeping the typed text as the label while storing the '
        'snake_case id would fix the raw look in one place.'),
    ...pt('//', 'humanities bias',
        'no natural or formal science is offered, which suits the '
        'intended user but not a general tool.'),
    ...pt('//', 'language as a string',
        'label() and title() compare to ‘fr’; an enum would make '
        'the third language a compile-time conversation.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
