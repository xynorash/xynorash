import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/providers/preference_providers.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'preference_providers.dart — the form, as one immutable value'),
    cm('//', 'every sidebar card edits a slice of it; the prompt is built from it'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'state for all sidebar choices, the free-text box and dismissed suggestions'),
    kv('language', 'Dart, Riverpod 2.6 (Notifier, StateProvider)'),
    kv('size', '59 lines: 1 controller with 8 methods, 3 providers'),
    kv('defaults', 'history, catholic_theology, art · licence · neutral · broad · curious · fr'),
    kv('persists', 'nothing: a reload returns to the defaults'),
    ...sec('why this file exists'),
    ...para('//',
        'The left column of the app is a form with seven kinds of '
        'input: which fields to combine, which to avoid, the academic '
        'level, the scope, the tone, the mood and a free-text box, '
        'plus a language toggle in the app bar. The model sees all of '
        'them, and the generation controller needs all of them at the '
        'instant the button is pressed. Rather than scatter the '
        'values across widgets, the app keeps them in one immutable '
        'object, PreferenceBlock (lib/models/preference_block.dart), '
        'and this file owns the single provider that holds it and the '
        'small set of methods allowed to change it.'),
    ...para('//',
        'That shape has two benefits that matter here. The cards stay '
        'thin: each one reads the block and calls one setter. And the '
        'prompt stays honest: the client serialises the same block '
        'with toJson() and interpolates its parts into the system '
        'prompt, so what the user sees selected is, by construction, '
        'exactly what the model is told.'),
    ...sec('the starting point'),
    ...code('dart', 'lib/models/preference_block.dart · the defaults', r'''
  static PreferenceBlock initial() => const PreferenceBlock(
    fields: ['history', 'catholic_theology', 'art'],
    level: AcademicLevel.licence,
    tone: Tone.neutral,
    scope: Scope.broad,
    mood: Mood.curious,
    excludedFields: [],
    language: 'fr',
  );'''),
    ...para('//',
        'The controller’s build() returns this value and nothing '
        'else; no storage is read. The defaults are the project’s '
        'intent in miniature: a licence-level student, the three '
        'fields the README names (History, Catholic Theology, Art '
        'History), a neutral tone, a curious mood, a broad search and '
        'a French interface. The language default has a visible '
        'consequence before anything is typed: the unlock screen '
        'reads it, so the first thing a visitor sees is French, and '
        'the widget test looks for the French sentence Entrez votre '
        'clé API Mistral.'),
    ...sec('the controller and its two invariants'),
    ...code('dart', 'lib/providers/preference_providers.dart · fields', r'''
class PreferenceController extends Notifier<PreferenceBlock> {
  @override
  PreferenceBlock build() => PreferenceBlock.initial();

  /// Adds or removes a field. Refuses to remove the last remaining field.
  void toggleField(String fieldId) {
    if (state.fields.contains(fieldId)) {
      if (state.fields.length <= 1) return;
      state = state.copyWith(
        fields: state.fields.where((f) => f != fieldId).toList(),
      );
    } else {
      state = state.copyWith(fields: [...state.fields, fieldId]);
    }
  }

  void addField(String fieldId) {
    if (state.fields.contains(fieldId)) return;
    state = state.copyWith(fields: [...state.fields, fieldId]);
  }'''),
    ...para('//',
        'Invariant one: there is always at least one selected field. '
        'The prompt’s first rule says the user has selected exactly '
        'these fields and that every topic must engage all of them; '
        'an empty list would make that sentence meaningless and the '
        'request nonsense. The check lives in the controller, which '
        'is the right place for an invariant, and the card repeats it '
        'for the user’s benefit: the delete cross on a field chip is '
        'disabled when only one remains, and a small hint says at '
        'least one field is required. The duplication is deliberate '
        'defence in depth, not drift.'),
    ...para('//',
        'Invariant two: no duplicates. toggleField adds or removes; '
        'addField only adds, and does nothing if the id is present. '
        'The distinction exists because the free-text suggestion chip '
        'needs an add that is safe to repeat, while a checkbox needs '
        'a toggle. State is always replaced with a new list built '
        'from the old, never mutated, which is what lets Riverpod '
        'notice the change.'),
    ...para('//',
        'Field ids are open-ended strings. The sidebar’s custom-field '
        'box turns whatever the user types into an id by lowercasing '
        'it and replacing runs of whitespace with underscores, and '
        'addField accepts it. A custom field therefore reaches the '
        'prompt as a snake_case id, and the label lookup (fieldLabel '
        'in lib/models/field_catalog.dart) falls back to showing the '
        'id itself when it is not in the catalog. The 22 catalogued '
        'fields have French and English names; anything else is shown '
        'as typed and passed to the model as an id.'),
    ...sec('the exclusion list'),
    ...code('dart', 'lib/providers/preference_providers.dart · excluded tags', r'''
  void addExcludedTag(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty || state.excludedFields.contains(trimmed)) return;
    state = state.copyWith(excludedFields: [...state.excludedFields, trimmed]);
  }'''),
    ...para('//',
        'Excluded fields are free text, not ids: the user types what '
        'to avoid and it becomes a chip. The method trims, ignores '
        'blanks and ignores exact duplicates. The text lands in rule '
        '2 of the system prompt (fields to actively avoid, if any) as '
        'written. One thing is not checked: nothing compares the '
        'exclusion list with the selected fields, so a user could '
        'select a field and also type its name as an exclusion. The '
        'two lists use different vocabularies (ids on one side, free '
        'text on the other), which makes an automatic check hard, and '
        'the model is left to resolve the contradiction.'),
    ...sec('the simple setters'),
    ...code('dart', 'lib/providers/preference_providers.dart · one-line setters', r'''
  void setLevel(AcademicLevel level) => state = state.copyWith(level: level);
  void setTone(Tone tone) => state = state.copyWith(tone: tone);
  void setScope(Scope scope) => state = state.copyWith(scope: scope);
  void setMood(Mood mood) => state = state.copyWith(mood: mood);'''),
    ...para('//',
        'The remaining choices are enums from lib/models/enums.dart, '
        'so there is nothing to validate: an invalid value is '
        'unrepresentable. Each setter replaces one field of an '
        'immutable block with copyWith, and every widget watching the '
        'block rebuilds. The scope setter matters more than it looks, '
        'because the client picks its instruction (a single deep-dive '
        'topic or five to eight options) from the scope alone; see '
        'the generation provider page for what that means for the '
        'Deep Dive button.'),
    ...para('//',
        'setLanguage is the same idea with one broader effect. The '
        'language is a preference, so it travels in the block to the '
        'model and tells rule 7 of the prompt which language to write '
        'in, while the same value drives AppStrings for the '
        'interface. One toggle in the app bar changes both the labels '
        'and the language of the generated content, which would be '
        'two settings in a less compact design.'),
    ...sec('two providers outside the block'),
    ...code('dart', 'lib/providers/preference_providers.dart · free text and dismissals', r'''
final freeTextProvider = StateProvider<String>((ref) => '');

/// Field ids the user has explicitly dismissed from the free-text
/// implied-field suggestion, so the chip doesn't reappear for that field
/// until the text changes again.
final dismissedFieldSuggestionsProvider = StateProvider<Set<String>>(
  (ref) => {},
);'''),
    ...para('//',
        'The free text is not part of the block. It is sent to the '
        'model under a separate key of the user message '
        '(freeTextFocus), because it describes this query, not a '
        'standing preference, and because the suggestion logic in '
        'lib/services/field_detection.dart needs to read it on every '
        'keystroke. The second provider is pure interface state: '
        'which suggestion chips the user has closed. The free-text '
        'card resets it to an empty set whenever the text changes, so '
        'a dismissal lasts only until the next edit.'),
    ...para('//',
        'Both use StateProvider, the lightweight provider for a '
        'single replaceable value. It is the right tool for a string '
        'and a set that have no behaviour of their own, and the rest '
        'of the file shows when it is not enough: anything with '
        'rules, like the field list, gets a Notifier.'),
    ...sec('how it is read'),
    ...para('//',
        'The generation controller reads the block with ref.read at '
        'the moment of each call, not with watch, so a request always '
        'carries the preferences as they were when the button was '
        'pressed, and a change made while a request is in flight '
        'cannot alter that request. The sidebar cards use watch, so '
        'they redraw as the values change. The same block, converted '
        'by toJson(), is the preferences entry in the user turn of '
        'the prompt, and the three fields that the system prompt '
        'interpolates (selected fields, excluded fields, tone, mood, '
        'level, language) come from it too.'),
    ...sec('what is not here'),
    ...pt('//', 'persistence',
        'nothing is saved. Reloading the page forgets a carefully '
        'chosen combination of fields. Saving the block next to the '
        'notebook would be a natural small feature; the repository '
        'shows no sign it was considered.'),
    ...pt('//', 'validation across lists',
        'selected versus excluded, see above.'),
    ...pt('//', 'tests',
        'no test touches this file. The two invariants are one-liners '
        'to test with a ProviderContainer.'),
    ...pt('//', 'history',
        'one commit, the scaffold. None of the three provider swaps '
        'changed it, which is the point of keeping preferences '
        'independent of the model client.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
