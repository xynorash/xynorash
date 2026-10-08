import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/models/narrow_topic.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'narrow_topic.dart — the deliverable: one fully worked-out topic'),
    cm('//', 'eight fields the model writes, each owned by a different part of the UI'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'the deep-dive result: title, pitch, problématique, level notes, intersection, bibliography, outline'),
    kv('language', 'Dart'),
    kv('size', '79 lines'),
    kv('history', 'one commit, 7a200e7 (2026-08-06); shape unchanged through Cerebras, Gemini and Mistral'),
    kv('persisted', 'yes: serialized into the notebook and sent back to the model on refine'),
    ...sec('why this file exists'),
    ...para('//',
        'A broad generation returns a menu of five to eight ideas. '
        'A narrow generation returns one idea worked out far enough to '
        'start a dissertation from: a framing paragraph, the research '
        'question, what the level implies, how the fields intersect, '
        'three starting sources and a three-part plan. NarrowTopic is '
        'that object. It is the most important type in the app, and it '
        'is the only generated type that is ever written to disk or '
        'sent back to the model.'),

    ...sec('field by field: who consumes what'),
    ...para('//',
        'The schema in the system prompt names eight fields (plus '
        'refinementSummary on one path). What makes this model class '
        'readable is that every field has exactly one on-screen home, '
        'so the shape of the data is the shape of the page:'),
    ...pt('//', 'title',
        'plain text headline in NarrowTopicView (the display-small serif '
        'style); also the source of the BibTeX download name.'),
    ...pt('//', 'pitch',
        'markdown paragraph directly under the title; with the title, '
        'it is all the notebook drawer shows of a saved topic.'),
    ...pt('//', 'problematique',
        'the dark pull-quote block (problematique_callout.dart), with '
        'a copy button. Plain text, not markdown.'),
    ...pt('//', 'levelNotes',
        'a bordered parchment box under the pitch: how the topic is '
        'calibrated to the chosen level.'),
    ...pt('//', 'fieldsIntersectionExplanation',
        'the first tab, next to the field chips.'),
    ...pt('//', 'starterBibliography',
        'the second tab, and the input to the BibTeX dialog.'),
    ...pt('//', 'suggestedStructure',
        'the third tab: the three-part plan.'),
    ...pt('//', 'refinementSummary',
        'optional; a teal box above the level notes, shown only after '
        'a refine round.'),
    blank,
    ...para('//',
        'The id field is the exception. The model is asked for one '
        '(‘id’: string) but nothing reads it: a search of lib/ finds '
        'no use of topic.id. The notebook assigns its own uuid per '
        'saved entry (see notebook_entry.dart), so the model-chosen id '
        'is parsed, stored, round-tripped and ignored.'),

    ...sec('the schema it mirrors'),
    ...code('dart', 'lib/services/mistral_client.dart · narrowTopic in the JSON schema', r'''
  "narrowTopic": {
    "id": string,
    "title": string,
    "pitch": string,
    "problematique": string,
    "levelNotes": string,
    "fieldsIntersectionExplanation": string,
    "starterBibliography": ['''),
    ...para('//',
        'The key is problematique without the accent, while all '
        'user-facing copy says ‘problématique’ (the copy button reads '
        '‘Copy problématique’ in the English strings). Machine names '
        'are ASCII; display names are French. The same split exists '
        'for the level value ‘memoire’ in enums.dart.'),

    ...sec('fromJson, written for a model that may vary'),
    ...code('dart', 'lib/models/narrow_topic.dart · fromJson (trimmed)', r'''
  factory NarrowTopic.fromJson(Map<String, dynamic> json) {
    return NarrowTopic(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      pitch: json['pitch']?.toString() ?? '',
      problematique: json['problematique']?.toString() ?? '',
      levelNotes: json['levelNotes']?.toString() ?? '',
      fieldsIntersectionExplanation:
          json['fieldsIntersectionExplanation']?.toString() ?? '',
      ...
      refinementSummary: json['refinementSummary']?.toString(),
    );
  }'''),
    ...para('//',
        'Every required string defaults to the empty string and the '
        'one optional string stays nullable, which gives the rest of '
        'the app a simple contract: a NarrowTopic never has a null '
        'field except refinementSummary. The cost is on the other '
        'side. An empty title renders as an empty headline with no '
        'warning, and the ProblematiqueCallout would draw an empty '
        'dark box. The model class prefers to render something over '
        'refusing to render, and leaves it to the prompt (every '
        'field is described as ‘string’ in the schema) to make '
        'emptiness rare.'),
    ...para('//',
        'The same call sites parse the two lists with the same '
        'idiom as GenerationResponse (cast to a list, map each '
        'element through the child fromJson, default to empty). The '
        'counts are not validated. The prompt demands ‘exactly 3 '
        'entries’ in both lists:'),
    ...code('dart', 'lib/services/mistral_client.dart · rules for populating the schema (wrapped)', r'''
- If scope is "narrow": populate "narrowTopic" with exactly 3 entries in "starterBibliography"
and exactly 3 entries (I, II, III) in "suggestedStructure", leave "broadTopics" an empty array.'''),
    ...para('//',
        'but the class accepts any length, and the tabs render '
        'whatever arrives. This is a story with a history. When the '
        'project briefly used Gemini (commit ebafa0f), the response '
        'schema was passed in Gemini’s own structured-output format '
        'with minItems and maxItems of 3 on both lists, and the '
        'commit message says the counts were “enforced structurally '
        'now instead of only by prose instruction”. The move to '
        'Mistral (98e7e48) went back to JSON mode, which per the '
        'README “only guarantees syntactic validity, not our schema '
        'shape”, so the guarantee returned to being a sentence in '
        'the prompt. The tests assert hasLength(3) on canned data, '
        'which proves the parser, not the model.'),

    ...sec('toJson: two readers, one writer'),
    ...code('dart', 'lib/models/narrow_topic.dart · toJson', r'''
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'pitch': pitch,
    'problematique': problematique,
    'levelNotes': levelNotes,
    'fieldsIntersectionExplanation': fieldsIntersectionExplanation,
    'starterBibliography': starterBibliography.map((e) => e.toJson()).toList(),
    'suggestedStructure': suggestedStructure.map((e) => e.toJson()).toList(),
    if (refinementSummary != null) 'refinementSummary': refinementSummary,
  };'''),
    ...para('//',
        'There are two callers. NotebookEntry.toJson nests this '
        'object so that the notebook can be written to storage, and '
        'MistralClient.refine passes it to the model as '
        '“existingNarrowTopic”. That second use is the reason the '
        'map uses the same keys as the schema the model wrote it in: '
        'the model is shown its own output format back, so it can '
        'return the full object again with the requested change.'),
    ...para('//',
        'The last line is a collection-if. refinementSummary is '
        'omitted when null instead of written as null, which keeps '
        'a never-refined topic’s JSON identical to the schema and '
        'avoids showing the model a null-valued key it might copy. '
        'The side effect: a topic that has been refined carries its '
        'old summary, and refining it again sends that summary back '
        'as part of existingNarrowTopic.'),

    ...sec('copyWith(id) and other loose ends'),
    ...para('//',
        'copyWith takes one parameter, id, and copies the other '
        'eight fields by hand. Nobody calls it; the notebook creates '
        'entries with their own ids and leaves the topic untouched. '
        'It is a leftover of an idea (re-identify a topic when it is '
        'saved) that the notebook design made unnecessary. '
        'Immutability here is real: all fields are final and the lists '
        'are never mutated in place, which is what lets the same '
        'NarrowTopic instance sit in the generation state, in a '
        'notebook entry and inside a refine request without defensive '
        'copies.'),

    ...sec('limits and what is next'),
    ...pt('//', 'counts unenforced',
        'three sources and three parts are a request, not a '
        'guarantee; a length check that triggers one retry would '
        'restore what the Gemini schema used to give.'),
    ...pt('//', 'empty strings render',
        'a blank pitch or problématique is shown, not flagged.'),
    ...pt('//', 'unused id and copyWith',
        'both are parsed or defined and never read.'),
    ...pt('//', 'versioned key, no migration',
        'the notebook stores this shape under xyno_scholar_notebook_v1, '
        'but there is no migration code; renaming a field here means '
        'old entries parse with empty strings, because fromJson fills '
        'absent keys with defaults.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
