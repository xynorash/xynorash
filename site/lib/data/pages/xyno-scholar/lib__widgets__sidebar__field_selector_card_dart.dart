import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/sidebar/field_selector_card.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'field_selector_card.dart — choosing which disciplines to cross'),
    cm('//', 'the largest card, and the one that sets the difficulty of the request'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'sidebar card: selected-field chips, a collapsible catalog, a custom-field box'),
    kv('language', 'Dart / Flutter, ConsumerStatefulWidget'),
    kv('size', '157 lines'),
    kv('history', '2 commits, 7a200e7 (scaffold) and 89a9c12 (icon package import)'),
    kv('state', 'selection in preferenceBlockProvider; open categories in the widget'),
    kv('catalog', '22 fields in 5 categories (lib/models/field_catalog.dart)'),
    ...sec('why this card matters most'),
    ...para('//',
        'Xyno Scholar exists to propose research topics that sit '
        'between disciplines. The first rule of the system prompt in '
        'lib/services/mistral_client.dart says what that means: '
        'every proposed subject “must genuinely engage ALL of these '
        'fields substantively — not merely be superficially '
        'compatible with them”, and rule 2 forbids adding a field the '
        'user did not select. So the list this card edits is not a '
        'filter or a hint; it is the constraint the whole request is '
        'built on. Each field added makes the model’s job harder, '
        'and removing the last one would leave it with no constraint '
        'at all.'),
    ...para('//',
        'That explains why this is the only card with real '
        'structure. It has to let someone pick two or three fields '
        'out of a catalog quickly, see at a glance what is picked '
        'even when most of the catalog is folded away, and add a '
        'discipline the catalog has never heard of. The file does '
        'those three jobs in three stacked blocks, separated by '
        'dividers: the selection, the catalog, the custom box.'),

    ...sec('two kinds of state, kept in two places'),
    ...code('dart', 'lib/widgets/sidebar/field_selector_card.dart · widget state', r'''
  final _customFieldController = TextEditingController();
  final Set<String> _expandedCategories = {kDefaultFieldCatalog.first.id};'''),
    ...para('//',
        'The selection itself is not here. It lives in the '
        'PreferenceBlock behind preferenceBlockProvider, because '
        'the prompt needs it. What lives in this widget is purely '
        'presentational: the text being typed in the custom box and '
        'which categories are open. Neither is ever sent to the '
        'model, and neither belongs in the contract, so they are '
        'ordinary State fields rather than providers. That is why '
        'the class is a ConsumerStatefulWidget and its siblings '
        'level_selector_card and scope_tone_mood_card, which keep '
        'no local state, are plain ConsumerWidgets.'),
    ...para('//',
        'The expanded set stores category ids, not titles. Ids are '
        'language-independent, so flipping the FR/EN toggle in the '
        'app bar relabels every category without collapsing any of '
        'them. Only the first category, Humanities & History, '
        'starts open. That choice interacts with the defaults in '
        'an interesting way: the initial selection is history, '
        'catholic_theology and art, and only history lives in the '
        'open category. The other two sit inside folded ones, which '
        'is exactly the situation the selected-chips row at the top '
        'of the card exists to cover.'),

    ...sec('the selection row'),
    ...code('dart', 'lib/widgets/sidebar/field_selector_card.dart · the chosen fields (trimmed)', r'''
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
                );'''),
    ...para('//',
        'Each chosen field is an InputChip, Material’s chip with a '
        'delete affordance, labelled through fieldLabel so that '
        'catalog ids show as “Histoire” or “History” and custom ids '
        'fall back to the raw string. The list being mapped is '
        'prefs.fields.toSet(). Dart’s default Set keeps insertion '
        'order, so the chips appear in the order the user chose '
        'them, not in catalog order, and a field added later from '
        'the free-text suggestion lands at the end.'),
    ...para('//',
        'The conditional on onDeleted is the interesting line. When '
        'only one field remains, onDeleted is null, and Flutter '
        'does not draw a delete icon for a chip with no delete '
        'callback, so the last chip simply loses its cross. This is '
        'the UI half of a rule that appears in three layers:'),
    ...pt('//', 'the chip',
        'the last one cannot be deleted from the selection row.'),
    ...pt('//', 'the hint',
        'a small muted line saying at least one field must stay '
        'selected, shown whenever one or fewer remain.'),
    ...pt('//', 'the controller',
        'toggleField in preference_providers.dart returns early '
        'when asked to remove the only field, which also protects '
        'the FilterChips in the catalog below, since tapping the '
        'sole selected one calls the same method.'),
    blank,
    ...code('dart', 'lib/widgets/sidebar/field_selector_card.dart · the hint', r'''
          if (prefs.fields.length <= 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                s.atLeastOneField,'''),
    ...para('//',
        'Repeating a rule in the widget and the controller looks '
        'redundant, but each covers a gap the other leaves. The '
        'controller guarantees the invariant whatever a future '
        'caller does; the widget keeps the user from clicking '
        'something that silently does nothing. Without the hint, a '
        'tap on the sole selected FilterChip would produce no '
        'visible change at all. Because FilterChip’s selected '
        'value is controlled by state, it simply stays selected; '
        'the hint explains why.'),

    ...sec('the catalog: an accordion that allows many open'),
    ...code('dart', 'lib/widgets/sidebar/field_selector_card.dart · expanding a category (trimmed)', r'''
                InkWell(
                  onTap: () => setState(() {
                    if (isExpanded) {
                      _expandedCategories.remove(category.id);
                    } else {
                      _expandedCategories.add(category.id);
                    }
                  }),'''),
    ...para('//',
        'Each of the five categories is a row with a chevron '
        '(chevronDown when open, chevronRight when closed, from the '
        'Lucide icon set) and the category title. Tapping toggles '
        'membership of the id in the set, inside setState, so '
        'several categories can be open at once. A strict '
        'one-at-a-time accordion would have forced a choice between '
        'seeing History and seeing Theology while picking both, '
        'which is the whole point of the app. The code does not '
        'record that reasoning; it is the reading that fits the '
        'behaviour.'),
    ...code('dart', 'lib/widgets/sidebar/field_selector_card.dart · one catalog chip (trimmed)', r'''
                        return FilterChip(
                          label: Text(field.label(prefs.language)),
                          selected: isSelected,
                          onSelected: (_) => ref
                              .read(preferenceBlockProvider.notifier)
                              .toggleField(field.id),
                          selectedColor: colors.teal.withValues(alpha: 0.16),
                          checkmarkColor: colors.teal,
                        );'''),
    ...para('//',
        'Inside an open category the fields are FilterChips, '
        'Material’s toggle chip: a checkmark appears on selection and '
        'the fill takes a teal tint. The callback ignores the bool '
        'that onSelected supplies and calls toggleField, so the '
        'chip’s visual state is always a function of the stored '
        'selection and never of its own internal state. That is '
        'what lets the same field be changed from three places '
        '(this chip, the delete cross in the row above and the '
        '“Add field” button in the free-text card) without the '
        'views disagreeing.'),
    ...para('//',
        'The teal is the app’s “interactive and active” colour, but '
        'note the tints: the chosen-field chip uses 0.12 for its '
        'fill and 0.4 for its border, the catalog chip uses 0.16 for '
        'its selected fill. Neither value is wrong; they are two '
        'of at least four teal tint levels in the app, and the '
        'intersection tab page has the full tally.'),

    ...sec('the custom field box'),
    ...code('dart', 'lib/widgets/sidebar/field_selector_card.dart · _submitCustomField', r'''
  void _submitCustomField(WidgetRef ref, String language) {
    final raw = _customFieldController.text.trim();
    if (raw.isEmpty) return;
    final id = raw.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    ref.read(preferenceBlockProvider.notifier).addField(id);
    _customFieldController.clear();
  }'''),
    ...para('//',
        'Anything the catalog lacks can be typed here. The text is '
        'trimmed, an empty string is ignored, and the rest is '
        'turned into an id by lowercasing and replacing each run '
        'of whitespace with one underscore. addField then appends '
        'it unless it is already present. The field_catalog page '
        'covers what that means for display: a custom field '
        'appears in the chip row as its snake_case id, because '
        'fieldLabel falls back to the id when it finds no catalog '
        'entry.'),
    ...para('//',
        'Two behaviours follow directly from the three lines that '
        'matter. Typing an English catalog id such as law or '
        'history is not a custom field at all: the id equals a '
        'catalog id, so the entry selects that catalog field and '
        'the matching FilterChip lights up. Typing the French word '
        'is different: “Droit” becomes the id droit, which is not '
        'the catalog id law, so it creates a second, custom field '
        'with no relation to the catalog one. In a bilingual app '
        'that is a quiet leak; the ids are English, the labels '
        'bilingual, and the box accepts either language without '
        'telling the two apart.'),
    ...pt('//', 'an unused parameter',
        'the method takes a language argument and never reads it, '
        'and receives the WidgetRef although a ConsumerState '
        'already has one. Both look like leftovers; the scaffold '
        'commit is the only one that touched this code, so there is '
        'no history to say what the language argument was for.'),
    ...pt('//', 'one handler, two triggers',
        'the plus button and the keyboard’s submit action call the '
        'same method.'),
    blank,
    ...code('dart', 'lib/widgets/sidebar/field_selector_card.dart · the box (trimmed)', r'''
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
        'The plus is a suffix icon inside the field, so the whole '
        'control is one rounded input, styled by the theme’s '
        'inputDecorationTheme (filled with the surface colour, '
        'teal border when focused). The excluded-themes card builds '
        'an almost identical box; the two were written side by '
        'side in the scaffold commit and have not been merged into '
        'a shared widget.'),
    ...para('//',
        'One more consequence worth stating: the string a user '
        'types ends up inside the system prompt, because '
        'mistral_client.dart builds the field list with '
        'prefs.fields.join(", ") and interpolates it into rule 1. '
        'In an app where each person supplies their own key and '
        'only affects their own request, that is the user steering '
        'their own query rather than a security hole, but it is '
        'the reason a custom field is more powerful than its '
        'little box suggests. Nothing limits the length of the '
        'text.'),

    ...sec('what changed over time'),
    ...para('//',
        'Two commits touch the file, and only one changes '
        'meaning. 7a200e7 (2026-08-06 09:41 UTC) is the scaffold. '
        '89a9c12 (09:58 UTC) changes a single import line, from '
        'package:lucide_icons to package:lucide_icons_flutter. Its '
        'message explains why: the 2023-era lucide_icons package '
        'subclassed Flutter’s IconData, which later Flutter '
        'releases made final, and that broke flutter build web in '
        'CI. The replacement “composes IconData instead of '
        'subclassing it” and keeps the same LucideIcons API, so no '
        'other line moved. Everything described above is therefore '
        'the first design, unchanged.'),

    ...sec('what is tested'),
    ...para('//',
        'Nothing at the widget level. The only widget test checks '
        'the unlock screen. The behaviour the card relies on, the '
        'last-field guard, lives in a controller that has no test '
        'either. A short test that builds the card, taps the sole '
        'selected FilterChip and asserts the selection did not '
        'change would pin all three layers at once.'),

    ...sec('limits and what is next'),
    ...pt('//', 'no cap on the selection',
        'neither toggleField nor addField limits the count, and '
        'rule 1 asks the model to engage all of them in every topic. '
        'Eight selected fields is an almost unsatisfiable request '
        'and nothing warns about it.'),
    ...pt('//', 'no search',
        '22 fields are scannable; a longer catalog would need a '
        'filter box.'),
    ...pt('//', 'custom fields look raw',
        'they render as snake_case ids and cannot be re-opened for '
        'editing, only deleted.'),
    ...pt('//', 'English ids, bilingual box',
        'typing the French name of a catalog field creates a '
        'duplicate custom field.'),
    ...pt('//', 'a selection that is lost on reload',
        'the block is never persisted, so a refresh returns to '
        'history, catholic_theology and art.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
