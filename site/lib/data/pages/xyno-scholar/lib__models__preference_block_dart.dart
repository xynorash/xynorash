import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/models/preference_block.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'preference_block.dart — everything the user can turn, as one value'),
    cm('//', 'an immutable record that becomes both prompt text and request JSON'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'the full set of user preferences that drive every generation call'),
    kv('language', 'Dart'),
    kv('size', '62 lines; seven fields, copyWith, toJson, initial()'),
    kv('history', 'one commit, 7a200e7 (2026-08-06); unchanged through three provider swaps'),
    kv('defaults', 'history + catholic_theology + art, licence, neutral, broad, curious, French'),
    ...sec('why this file exists'),
    ...para('//',
        'Every control in the sidebar writes to one place, and every '
        'request to the model reads from one place. This class is that '
        'place. It exists so that the answer to “what did the user ask '
        'for?” is a single immutable value that can be copied, '
        'serialized, interpolated into a prompt and compared, rather '
        'than a handful of loose providers that have to be gathered at '
        'the moment of the call.'),
    ...code('dart', 'lib/models/preference_block.dart · the fields', r'''
/// The full set of user preferences that drive every generation call.
class PreferenceBlock {
  final List<String> fields;
  final AcademicLevel level;
  final Tone tone;
  final Scope scope;
  final Mood mood;
  final List<String> excludedFields;
  final String language; // "fr" | "en"'''),
    ...para('//',
        'Four of the seven are the enums from enums.dart. The two '
        'lists are field ids (field_catalog.dart) and free-form '
        'excluded tags. The seventh, language, is the odd one out: a '
        'String with a comment saying what it may contain, where the '
        'other dials have types. Eleven places in the codebase '
        'compare it to ‘fr’ by hand, and each of them silently treats '
        'every other value as English.'),

    ...sec('what is deliberately not in the block'),
    ...para('//',
        'The free-text angle (“a period, a place, a specific '
        'object…”) is not a field here. It lives in its own provider, '
        'freeTextProvider, and travels in the request under a '
        'different key. The split is visible in the user turn that '
        'MistralClient builds:'),
    ...code('dart', 'lib/services/mistral_client.dart · _userTurn', r'''
    final payload = {
      'preferences': prefs.toJson(),
      if (freeText.trim().isNotEmpty) 'freeTextFocus': freeText.trim(),
      if (focusTitle != null) 'deepDiveOnTitle': focusTitle,'''),
    ...para('//',
        'The block is the standing configuration; the free text and '
        'the deep-dive title are properties of one request. A '
        'deep dive replaces the free text with the chosen topic’s '
        'keywords (see broad_topic.dart) without touching the '
        'preferences, which would be awkward if the angle were a field '
        'of the block. The API key is also outside it, in '
        'apiKeyProvider, for a stronger reason: this object is '
        'serialized into the request body and into the system prompt, '
        'and nothing secret should ever be one method call away from '
        'either.'),

    ...sec('toJson: the second copy of the preferences'),
    ...code('dart', 'lib/models/preference_block.dart · toJson', r'''
  Map<String, dynamic> toJson() => {
    'fields': fields,
    'level': level.apiValue,
    'tone': tone.apiValue,
    'scope': scope.apiValue,
    'mood': mood.apiValue,
    'excludedFields': excludedFields,
    'language': language,
  };'''),
    ...para('//',
        'The preferences reach the model twice. This JSON goes into '
        'the user message, and the same values are interpolated into '
        'the system prompt: the field list in rule 1, the excluded '
        'list in rule 2, tone and mood in rule 4, the level in rule 5 '
        'and the language in rule 7. Both the generate path and the '
        'refine path call toJson (the refine request carries '
        '“preferences” as well), so a refinement is judged against the '
        'same constraints as the first answer. Whether the redundancy '
        'helps is not measured anywhere in the repository; the code '
        'only shows that it is there.'),
    ...para('//',
        'The keys are camelCase JSON names on the wire (excludedFields, '
        'not excluded_fields), consistent with the response schema in '
        'the prompt (fieldsCovered, keyKeywords). The enum values on '
        'the wire are the apiValue strings, so the request says '
        '“general_public” and “memoire”, never “generalPublic”.'),

    ...sec('copyWith and the invariants that live elsewhere'),
    ...para('//',
        'The class is a plain immutable value with a hand-written '
        'copyWith that takes every field as an optional parameter. '
        'Every mutation in the app is a copy. The rules about what '
        'a valid block is are not in the class; they are in the '
        'controller that owns it, lib/providers/preference_providers.dart:'),
    ...code('dart', 'lib/providers/preference_providers.dart · toggleField', r'''
  /// Adds or removes a field. Refuses to remove the last remaining field.
  void toggleField(String fieldId) {
    if (state.fields.contains(fieldId)) {
      if (state.fields.length <= 1) return;'''),
    ...para('//',
        'That guard is the reason an empty field list can never reach '
        'the prompt, where rule 1 would read “selected exactly these '
        'fields: []”. The sidebar mirrors it in the UI: the delete icon '
        'on the last remaining chip is null, and a hint appears saying '
        'at least one field must stay selected. Two layers, one '
        'invariant. Note that the model itself has no assertion; a '
        'block constructed directly, as the tests do, is not checked.'),

    ...sec('initial(): whose defaults these are'),
    ...code('dart', 'lib/models/preference_block.dart · initial', r'''
  static PreferenceBlock initial() => const PreferenceBlock(
    fields: ['history', 'catholic_theology', 'art'],
    level: AcademicLevel.licence,
    tone: Tone.neutral,
    scope: Scope.broad,
    mood: Mood.curious,
    excludedFields: [],
    language: 'fr','''),
    ...para('//',
        'These are the owner’s own use case baked in as the resting '
        'state: the README describes a licence-level scholar working '
        'in History, Catholic Theology and Art History, and the app '
        'opens in French. The consequence shows in the single widget '
        'test, which pumps the whole app and expects the French unlock '
        'title, “Entrez votre clé API Mistral”. That test is a canary '
        'for this default: change the initial language and it fails.'),
    blank,
    ...para('//',
        'Nothing persists the block. A search of lib/ finds exactly two '
        'storage users: the notebook (shared_preferences) and the '
        'optional session-only API key. Preferences are in memory, so '
        'reloading the page puts the language back to French and the '
        'fields back to the three defaults, and since the unlock '
        'screen has no language switch (see lib/screens/'
        'key_entry_screen.dart), an English-speaking user meets French '
        'on every fresh load until they have entered a key.'),

    ...sec('how it is tested'),
    ...para('//',
        'test/mistral_client_test.dart constructs a block directly '
        '(fields history and art, licence, neutral, broad, curious, '
        'English) and uses copyWith(scope: Scope.narrow) for the narrow '
        'and refine cases. Because the mock client returns canned '
        'JSON, the tests prove that a block can be built and passed '
        'to the client, and that the call shape is right (model name, '
        'response_format, a system message first). They do not assert '
        'on the serialized preferences or on the prompt text.'),

    ...sec('limits and what is next'),
    ...pt('//', 'no persistence',
        'a refresh resets everything, including the language.'),
    ...pt('//', 'language is a string',
        'an enum with a fromCode parser would remove eleven '
        'hand-written comparisons.'),
    ...pt('//', 'no toJson test',
        'a golden test of the serialized block would pin the wire '
        'vocabulary that the prompt depends on.'),
    ...pt('//', 'lists are shared by reference',
        'copyWith passes the same list object through; the controller '
        'always builds a new list before copying, which is what keeps '
        'it safe today.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
