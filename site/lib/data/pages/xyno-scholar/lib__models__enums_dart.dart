import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/models/enums.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'enums.dart — the four dials, and the words the model hears'),
    cm('//', 'level, tone, scope, mood: a UI label, a wire value, a prompt term'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'preference vocabulary shared by the sidebar, the JSON request and the system prompt'),
    kv('language', 'Dart'),
    kv('size', '146 lines, four enums'),
    kv('dials', 'AcademicLevel (5 values), Tone (3), Scope (2), Mood (4)'),
    kv('history', 'one commit, 7a200e7 (2026-08-06); not touched by any of the three LLM-provider swaps that followed'),
    ...sec('why this file exists'),
    ...para('//',
        'Xyno Scholar asks a language model for research topics, and four '
        'of the things the user can turn are small closed sets: how '
        'advanced the work is (level), how it should sound (tone), how '
        'many ideas to return (scope) and what attitude to take (mood). '
        'Each of them has to exist in three places at once: as a control '
        'in the sidebar, as a word in the JSON request, and as a named '
        'rule in the system prompt. This file is where the three are '
        'tied together, so that a chip in French and a sentence the '
        'model reads in English are provably the same choice.'),
    blank,
    ...para('//',
        'The reason to model them as enums rather than strings is the '
        'usual one, made sharper by the fact that the other end of the '
        'wire is a language model: a typo in a free string would not '
        'throw, it would just quietly give the model a level it has no '
        'rule for. With an enum the sidebar can only ever offer values '
        'that the prompt in lib/services/mistral_client.dart knows about.'),

    ...sec('the wire value: two ways to spell it'),
    ...para('//',
        'Every enum exposes apiValue, the string that goes into '
        'PreferenceBlock.toJson (see preference_block.dart) and is '
        'interpolated into the system prompt. Three of the enums use the '
        'laziest correct implementation. AcademicLevel cannot:'),
    ...code('dart', 'lib/models/enums.dart · AcademicLevel.apiValue', r'''
  String get apiValue => switch (this) {
    AcademicLevel.licence => 'licence',
    AcademicLevel.master => 'master',
    AcademicLevel.memoire => 'memoire',
    AcademicLevel.phd => 'phd',
    AcademicLevel.generalPublic => 'general_public',
  };'''),
    ...para('//',
        'The prompt’s vocabulary is snake_case: rule 5 lists its levels '
        'as licence, master, memoire, phd and general_public, and the '
        'Dart identifier generalPublic would have produced the wrong '
        'token if the code had used the enum’s name. So this one is a '
        'hand-written switch. Note also what the switch does with the '
        'French word: the identifier and the wire value are both plain '
        'ASCII (memoire), and the accent lives only in the display '
        'label, ‘Mémoire’. The model is never asked to match an accented '
        'token.'),
    ...code('dart', 'lib/models/enums.dart · Tone.apiValue', r'''
enum Tone {
  playful,
  serious,
  neutral;

  String get apiValue => name;'''),
    ...para('//',
        'Tone, Scope and Mood use name directly. That is a coupling worth '
        'knowing about: renaming an enum case in Dart now silently '
        'renames a word in the prompt. No test pins any of these strings '
        '(a search of test/ finds no use of apiValue), so the protection '
        'is the file’s size and the fact that the prompt lists the same '
        'words right next to the rules that define them.'),

    ...sec('the prompt defines each value'),
    ...para('//',
        'The prompt does not just receive the value; it defines it. '
        'Rule 4 spells out what each tone and mood means, rule 5 what '
        'each level means. That makes the UI description and the prompt '
        'rule two renderings of one idea, and it is instructive to put '
        'them side by side. The line the model reads:'),
    ...code('dart', 'lib/services/mistral_client.dart · system prompt, rule 5', r'''
   - licence: bounded, accessible corpus, no paleography or ancient-language skills required.
   - master: specialized historiography, situates the topic within a scholarly debate.
   - memoire: focused methodology built around one precise, tractable problématique.'''),
    ...para('//', 'and the line the student reads under the same radio button:'),
    ...code('dart', 'lib/models/enums.dart · AcademicLevel.descriptionEn()', r'''
    AcademicLevel.licence =>
      'Bounded, accessible corpus — no paleography or ancient languages required.',
    AcademicLevel.master =>
      'Specialized historiography, situates the topic within a scholarly debate.',
    AcademicLevel.memoire =>
      'Focused methodology built around one precise, tractable problématique.','''),
    ...para('//',
        'They are near-copies, which is the right instinct: what the '
        'student is promised on screen is what the model is told. It is '
        'also a duplication with no test holding the two together. If '
        'someone retunes the prompt for the PhD level and forgets '
        'descriptionEn, the sidebar will go on promising something the '
        'model no longer does. Both strings are hand-maintained, in two '
        'files, in three languages if the French descriptions are '
        'counted.'),

    ...sec('labels in two languages'),
    ...para('//',
        'Display text comes as labelFr() and labelEn() method pairs, and '
        'the level enum adds descriptionFr() and descriptionEn(). The '
        'call sites choose with an inline ternary (level_selector_card '
        'and scope_tone_mood_card both do prefs.language == ‘fr’ ? '
        'labelFr() : labelEn()), so the language switch lives in the '
        'widgets, not here. The enum stays a plain value type with no '
        'dependency on the strings class in lib/l10n/strings.dart.'),
    ...code('dart', 'lib/models/enums.dart · AcademicLevel labels', r'''
  String labelFr() => switch (this) {
    AcademicLevel.licence => 'Licence',
    AcademicLevel.master => 'Master',
    AcademicLevel.memoire => 'Mémoire',
    AcademicLevel.phd => 'Doctorat',
    AcademicLevel.generalPublic => 'Grand public',
  };

  String labelEn() => switch (this) {
    AcademicLevel.licence => 'Undergraduate',
    AcademicLevel.master => "Master's",
    AcademicLevel.memoire => 'Thesis',
    AcademicLevel.phd => 'PhD',
    AcademicLevel.generalPublic => 'General public','''),
    ...para('//',
        'Two small details show the cost of string literals in Dart. '
        'The English label for the master’s level is written with double '
        'quotes so the apostrophe needs no escape, and the French '
        'descriptions escape theirs (‘d’une problématique’ appears in the '
        'source as d, backslash, apostrophe, une). The labels are not a '
        'translation table; they are a choice of register. ‘Licence’ is '
        'kept in French in the French UI and becomes ‘Undergraduate’ in '
        'English, while ‘Mémoire’ becomes ‘Thesis’.'),
    blank,
    ...para('//',
        'Scope is the one enum whose label carries a number:'),
    ...code('dart', 'lib/models/enums.dart · Scope labels', r'''
  String labelFr() => switch (this) {
    Scope.broad => 'Large (5–8 pistes)',
    Scope.narrow => 'Ciblé (approfondissement)',
  };

  String labelEn() => switch (this) {
    Scope.broad => 'Broad (5–8 options)',
    Scope.narrow => 'Narrow (deep dive)','''),
    ...para('//',
        'The 5–8 is a third copy of a constant. The prompt says ‘populate '
        'broadTopics with 5 to 8 entries’ and the user turn repeats it '
        'as ‘Generate 5 to 8 broad topic options’. All three must agree '
        'for the UI not to lie, and they are three separate literals in '
        'two files.'),

    ...sec('fromApiValue: the safe default, currently unused'),
    ...para('//',
        'Each enum also has a static parser from a wire string back to a '
        'value, and each parser picks a fallback instead of throwing:'),
    ...code('dart', 'lib/models/enums.dart · fromApiValue', r'''
  static AcademicLevel fromApiValue(String value) {
    return AcademicLevel.values.firstWhere(
      (l) => l.apiValue == value,
      orElse: () => AcademicLevel.licence,
    );
  }'''),
    ...para('//',
        'The fallbacks are licence, neutral, broad and curious, which are '
        'exactly the defaults in PreferenceBlock.initial(). That '
        'consistency is deliberate and sensible: an unknown value '
        'degrades to the app’s resting state rather than to an error '
        'screen. But a search of lib/ and test/ finds no caller for any '
        'of the four parsers. Nothing in the app currently reads these '
        'enums back from a string: preferences are not persisted, and '
        'the model’s reply carries scope as a plain String (see '
        'generation_response.dart), never as this enum. They are '
        'prepared for a round trip that has not been needed yet.'),

    ...sec('how it is exercised'),
    ...para('//',
        'test/mistral_client_test.dart builds its PreferenceBlock from '
        'AcademicLevel.licence, Tone.neutral, Scope.broad and '
        'Mood.curious, and flips to Scope.narrow with '
        'copyWith(scope: Scope.narrow) for the narrow and refine tests. '
        'That is the whole of the automated coverage: the enums are '
        'constructed and passed through, and their string values are '
        'never asserted. The widget test only checks the unlock screen.'),

    ...sec('limits and what is next'),
    ...pt('//', 'wire strings unpinned',
        'a table-driven test over apiValue for every case would turn a '
        'silent prompt change into a failing build.'),
    ...pt('//', 'three sources of truth',
        'level descriptions, tone and mood meanings, and the 5–8 count '
        'live in both this file and the prompt text. The prompt could '
        'be built from these enums’ descriptions to remove one copy.'),
    ...pt('//', 'dead parsers',
        'fromApiValue is untested and uncalled; either wire it to '
        'something or delete it.'),
    ...pt('//', 'language as a string',
        'the fr/en choice is not an enum, so labelFr/labelEn dispatch '
        'by hand at every call site (see preference_block.dart).'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
