import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/models/generation_response.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'generation_response.dart — the top of the contract with the model'),
    cm('//', 'a tolerant reader for one JSON object the app does not control'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'root of the response schema; parses the model’s JSON into typed values'),
    kv('language', 'Dart'),
    kv('size', '39 lines'),
    kv('history', 'one commit, 7a200e7 (2026-08-06); same shape across Cerebras, Gemini and Mistral'),
    kv('pinned by', 'test/mistral_client_test.dart: broad, narrow, refine, fences, retry'),
    ...sec('why this file exists'),
    ...para('//',
        'The model does not return a Dart object. It returns text '
        'that is supposed to be a JSON object, and the app has to '
        'turn that into something widgets can render without '
        'null checks everywhere. This class is the first stop for that '
        'conversion and the place where the app decides how much to '
        'trust what it was sent. The decision it makes is: believe '
        'the shape loosely, and never crash on a missing key.'),
    blank,
    ...para('//',
        'There are two halves to the contract, and they live in two '
        'files that must agree. The prompt in lib/services/'
        'mistral_client.dart tells the model what to produce. This '
        'file (and the model classes it calls) decides what to '
        'accept.'),

    ...sec('the schema the model is given'),
    ...code('dart', 'lib/services/mistral_client.dart · JSON schema in the system prompt (top level)', r'''
{
  "scope": "broad" | "narrow",
  "language": string,
  "fieldsCovered": string[],
  "clarifyingQuestion": string or null,
  "broadTopics": ['''),
    ...para('//',
        'Six keys at the top, and each maps to one field of '
        'GenerationResponse, in the same order. Two of them carry '
        'control flow. scope says which of broadTopics and narrowTopic '
        'is populated. clarifyingQuestion is the escape hatch for '
        'rule 3: when the user’s free text implies a field they did '
        'not select, the model must ask one short question but still '
        'deliver topics in the same reply. The model class has to '
        'carry both the question and the topics at once, which is why '
        'every collection defaults to empty instead of being '
        'mutually exclusive in the type.'),

    ...sec('fromJson: lenient on absence, strict on type'),
    ...code('dart', 'lib/models/generation_response.dart · fromJson', r'''
  factory GenerationResponse.fromJson(Map<String, dynamic> json) {
    return GenerationResponse(
      scope: json['scope']?.toString() ?? 'broad',
      language: json['language']?.toString() ?? 'fr',
      fieldsCovered:
          (json['fieldsCovered'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      clarifyingQuestion: json['clarifyingQuestion']?.toString(),'''),
    ...para('//',
        'Read the idiom closely, because the same three tokens repeat '
        'in every model class of the project. json[key]?.toString() '
        'turns a missing key, an explicit null and a number all into '
        'something safe (null, null, and the number’s text), and the '
        '?? supplies a default. as List? followed by ?.map and ?? '
        'const [] does the same for arrays. A response with no '
        'broadTopics key is therefore an empty list, not an '
        'exception.'),
    blank,
    ...para('//',
        'The defaults are not arbitrary. scope falls back to ‘broad’, '
        'which matches Scope.broad in enums.dart, and language to ‘fr’, '
        'which matches the default in PreferenceBlock.initial(). A '
        'response that lost both would be treated as a French list of '
        'broad topics, the app’s resting state.'),
    ...code('dart', 'lib/models/generation_response.dart · nested objects', r'''
      broadTopics:
          (json['broadTopics'] as List?)
              ?.map((e) => BroadTopic.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      narrowTopic: json['narrowTopic'] != null
          ? NarrowTopic.fromJson(json['narrowTopic'] as Map<String, dynamic>)
          : null,'''),
    ...para('//',
        'Here the leniency stops. Each element is cast with as '
        'Map<String, dynamic>, and a cast that fails throws. The '
        'consequence depends on where this runs. MistralClient.generate '
        'calls GenerationResponse.fromJson after _requestJson has '
        'returned, so it sits outside the retry that protects '
        'against malformed JSON text. A reply that is valid JSON but '
        'has, say, strings where broadTopics objects should be, would '
        'not be retried; the TypeError would reach the catch-all in '
        'GenerationController._run and the user would see the English '
        'message ‘Something went wrong while talking to Mistral.’ '
        'The retry covers bad syntax, not bad shape. That is a '
        'defensible line to draw, but it is a line, and it is not '
        'tested.'),

    ...sec('the UI does not trust scope alone'),
    ...para('//',
        'Even with a parsed response, the output panel does not '
        'simply switch on scope. It checks that the thing the scope '
        'promises is actually there:'),
    ...code('dart', 'lib/widgets/output/output_panel.dart · _ResponseContent', r'''
        if (response.scope == 'narrow' && response.narrowTopic != null)
          NarrowTopicView(
            topic: response.narrowTopic!,
            fieldsCovered: response.fieldsCovered,
            language: response.language,
          )
        else if (response.broadTopics.isNotEmpty)
          BroadTopicsList(topics: response.broadTopics)
        else
          _EmptyState(strings: strings),'''),
    ...para('//',
        'A narrow reply without a narrowTopic falls through to the '
        'broad branch, and a reply with neither falls through to the '
        'empty state. The last case deserves a note: the user sees '
        '“Ready to explore” again with no error, as if nothing had '
        'happened. A model that returns a valid-but-empty object is '
        'silent in the UI.'),

    ...sec('where a GenerationResponse is built by hand'),
    ...para('//',
        'There is a second constructor call site that is not a parse. '
        'The refine endpoint returns a full topic, and the client '
        'extracts only that (MistralClient.refine returns a '
        'NarrowTopic). The controller then wraps it in a fresh '
        'response, borrowing what it cannot get from the reply:'),
    ...code('dart', 'lib/providers/generation_provider.dart · refine', r'''
        response: GenerationResponse(
          scope: 'narrow',
          language: current?.language ?? prefs.language,
          fieldsCovered: current?.fieldsCovered ?? prefs.fields,
          narrowTopic: updated,
        ),'''),
    ...para('//',
        'Two things follow. The refined view keeps the previous '
        'fieldsCovered, so the Intersection tab’s chips come from '
        'the original generation, not from the refined text. And no '
        'clarifyingQuestion is carried over, so the amber question '
        'banner disappears after a refinement. Both are consistent '
        'with a refinement being a narrow, topic-only operation, but '
        'neither is stated anywhere.'),

    ...sec('what the tests prove'),
    ...para('//',
        'Four of the eight tests in test/mistral_client_test.dart '
        'feed a JSON string through MistralClient and assert on '
        'a GenerationResponse (a fifth, the refine test, asserts on the '
        'extracted NarrowTopic). The broad test checks scope == ‘broad’ '
        'and one parsed BroadTopic. The narrow test checks that '
        'narrowTopic is non-null with three bibliography entries and '
        'three outline parts. The fence test wraps the object in '
        'a markdown fence and still expects scope == ‘broad’. '
        'Nothing tests missing keys, wrong types or an empty reply, '
        'which is exactly where this class is interesting.'),

    ...sec('limits and what is next'),
    ...pt('//', 'scope and language are strings',
        'the response carries scope as text where the request '
        'uses an enum; comparing to ‘narrow’ is a typo risk.'),
    ...pt('//', 'shape errors are not retried',
        'moving fromJson inside the retry boundary would give a '
        'wrong-shape reply the same second chance as a bad-syntax one.'),
    ...pt('//', 'silent empty replies',
        'an empty-but-valid object renders the welcome state; a '
        'visible “the model returned nothing” banner would be '
        'kinder.'),
    ...pt('//', 'no toJson',
        'a response is never serialized; only NarrowTopic is, for '
        'the notebook and the refine request.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
