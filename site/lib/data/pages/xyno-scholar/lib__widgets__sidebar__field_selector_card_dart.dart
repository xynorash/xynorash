import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/sidebar/field_selector_card.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'field_selector_card.dart — pick the disciplines to cross'),
    cm('//', r'the first card in the sidebar, and the one the whole app is about'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'choose and add academic fields; edits PreferenceBlock.fields'),
    kv(r'language', r'Dart / Flutter, a ConsumerStatefulWidget with Riverpod'),
    kv(r'size', r'157 lines, 2 commits'),
    kv(r'data', r'kDefaultFieldCatalog: 6 categories, 23 fields, each in fr and en'),
    kv(r'history', r'7a200e7 (2026-08-06 09:41), 89a9c12 (09:58)'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'The app generates research topics at the intersection of '
        r'several fields, and the system prompt demands that every '
        r'topic engage all of them. So the field list is the main input. '
        r'The default selection says what the app was first made '
        r'for: PreferenceBlock.initial() starts with history, '
        r'catholic_theology and art. This card is the control '
        r'that changes that list. It has three jobs: show what is '
        r'selected, offer a catalogue to choose from, and let the '
        r'user add a field the catalogue lacks.'),

    ...sec(r'the state'),
    ...code('dart', r'lib/widgets/sidebar/field_selector_card.dart · lines 17-33', r'''
class _FieldSelectorCardState extends ConsumerState<FieldSelectorCard> {
  final _customFieldController = TextEditingController();
  final Set<String> _expandedCategories = {kDefaultFieldCatalog.first.id};

  @override
  void dispose() {
    _customFieldController.dispose();
    super.dispose();
  }

  void _submitCustomField(WidgetRef ref, String language) {
    final raw = _customFieldController.text.trim();
    if (raw.isEmpty) return;
    final id = raw.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    ref.read(preferenceBlockProvider.notifier).addField(id);
    _customFieldController.clear();
  }'''),
    ...para('//',
        r'The widget keeps two pieces of local state that do not belong '
        r'in the shared preferences: a text controller, and the set of '
        r'category ids that are expanded. Which section is open is '
        r'a matter of the display, so it stays here and is lost '
        r'when the widget goes. Initially only the first category is '
        r'open, so a first-time user sees a short list and not 23 '
        r'chips.'),
    blank,
    ...para('//',
        r'The custom-field function turns what you type into an id: '
        r'trim, lowercase, and every run of whitespace becomes one '
        r'underscore. “Medieval Law” becomes medieval_law. The '
        r'second parameter, language, is accepted and never used in '
        r'the body, a leftover from a version that probably needed '
        r'it. Two consequences of the id design. The id is what '
        r'goes into the prompt, so the model reads medieval_law. And '
        r'fieldLabel falls back to the raw id for anything not in the '
        r'catalogue, so the chip for a custom field shows '
        r'medieval_law, underscore and all, in the sidebar and on the '
        r'Intersection tab. Typed accents survive lowercase, but '
        r'two spellings of the same idea become two ids.'),

    ...sec(r'selected fields at the top'),
    ...code('dart', r'lib/widgets/sidebar/field_selector_card.dart · lines 47-74', r'''
          if (selected.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: selected.map((fieldId) {
                return InputChip(
                  label: Text(fieldLabel(fieldId, prefs.language)),
                  onDeleted: prefs.fields.length > 1
                      ? () => ref
                            .read(preferenceBlockProvider.notifier)
                            .toggleField(fieldId)
                      : null,
                  deleteIcon: const Icon(LucideIcons.x, size: 14),
                  backgroundColor: colors.teal.withValues(alpha: 0.12),
                  side: BorderSide(color: colors.teal.withValues(alpha: 0.4)),
                );
              }).toList(),
            ),
          if (prefs.fields.length <= 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                s.atLeastOneField,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: colors.inkMuted),
              ),
            ),'''),
    ...para('//',
        r'The chips are the current answer to “what am I crossing?”. '
        r'The most important line is the guard on onDeleted: when '
        r'only one field is left, the callback is null and Flutter '
        r'draws the chip without a working x. The same rule is enforced '
        r'a second time in the notifier, whose toggleField returns '
        r'early if removing would leave none. The UI hides the '
        r'control, and the state refuses the operation. The note '
        r'“At least one field must stay selected.” appears when '
        r'there is one or none, so the user sees why the x went away.'),

    ...sec(r'the catalogue'),
    ...code('dart', r'lib/widgets/sidebar/field_selector_card.dart · lines 78-90', r'''
          ...kDefaultFieldCatalog.map((category) {
            final isExpanded = _expandedCategories.contains(category.id);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => setState(() {
                    if (isExpanded) {
                      _expandedCategories.remove(category.id);
                    } else {
                      _expandedCategories.add(category.id);
                    }
                  }),'''),
    ...code('dart', r'lib/widgets/sidebar/field_selector_card.dart · lines 115-134', r'''
                if (isExpanded)
                  Padding(
                    padding: const EdgeInsets.only(left: 22, bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: category.fields.map((field) {
                        final isSelected = selected.contains(field.id);
                        return FilterChip(
                          label: Text(field.label(prefs.language)),
                          selected: isSelected,
                          onSelected: (_) => ref
                              .read(preferenceBlockProvider.notifier)
                              .toggleField(field.id),
                          selectedColor: colors.teal.withValues(alpha: 0.16),
                          checkmarkColor: colors.teal,
                        );
                      }).toList(),
                    ),
                  ),'''),
    ...para('//',
        r'The catalogue is rendered by mapping over six categories. Each '
        r'has a header row that toggles the set: tap, setState, '
        r'the chevron points down or right. When a category is '
        r'expanded its fields appear as FilterChips indented by 22 '
        r'pixels. A FilterChip is the right widget for a '
        r'multi-select: it carries its own checkmark, and toggling one '
        r'calls toggleField, which adds or removes. This one function '
        r'serves both the catalogue chips and the x on the top chips, '
        r'so there is one rule for the minimum of one.'),
    blank,
    ...para('//',
        r'The widget shows both the selection and the catalogue, so a '
        r'field in an open category appears twice: once as a selected '
        r'FilterChip, once at the top. This is deliberate redundancy. '
        r'The top row is a summary you can always see; the catalogue is '
        r'where you browse, and you may have it collapsed.'),

    ...sec(r'the custom field box'),
    ...code('dart', r'lib/widgets/sidebar/field_selector_card.dart · lines 141-152', r'''
          TextField(
            controller: _customFieldController,
            decoration: InputDecoration(
              hintText: s.addCustomFieldHint,
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(LucideIcons.plus, size: 18),
                onPressed: () => _submitCustomField(ref, prefs.language),
              ),
            ),
            onSubmitted: (_) => _submitCustomField(ref, prefs.language),
          ),'''),
    ...para('//',
        r'The box is the same shape as the excluded-themes box: a '
        r'plus button and Enter. “Add a custom field…” (Ajouter un '
        r'champ personnalisé…) is the hint. The notifier’s addField '
        r'skips an id that is already present. The catalogue file '
        r'says why custom fields exist: it is “fully generic — '
        r'users may add any custom field via free text on top of this '
        r'list.” There is no list that could hold every discipline, and '
        r'the app does not pretend there is.'),

    ...sec(r'edge cases'),
    ...pt('//', r'a custom field that duplicates a built-in',
        r'typing “Art” gives the id art, which is already selected '
        r'by default, and addField ignores it. Typing “Histoire” gives '
        r'histoire, which is not the id history, and so is added as a '
        r'separate custom field.'),
    ...pt('//', r'order',
        r'selected is a Set built from the list, which keeps insertion '
        r'order, so chips appear in the order they were added.'),
    ...pt('//', r'the language switch',
        r'labels come from prefs.language on every build, so changing '
        r'the language relabels every chip without any extra code.'),

    ...sec(r'how it is tested'),
    ...para('//',
        r'No test covers this card. Of the app’s three test files, the '
        r'widget test checks only the unlock screen. The one '
        r'guard that is most worth a test, the minimum of one field, '
        r'lives in the notifier and has none.'),

    ...sec(r'history'),
    ...pt('//', r'7a200e7, 2026-08-06 09:41', r'the scaffold commit.'),
    ...pt('//', r'89a9c12, 2026-08-06 09:58',
        r'the icon package swap. Same icon names; only the import line '
        r'changed.'),
  ],
);
