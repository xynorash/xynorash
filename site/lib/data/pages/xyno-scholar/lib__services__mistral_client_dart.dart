import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/services/mistral_client.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'mistral_client.dart — the only file that knows a provider'),
    cm('//', 'a strict prompt, one request, and a parser that expects to be lied to'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'builds the prompt, calls the model through the relay, returns parsed topics'),
    kv('language', 'Dart'),
    kv('size', '279 lines: 2 exceptions, 1 client class, 6 private helpers'),
    kv('model', 'mistral-large-latest, JSON mode, no sampling parameters set'),
    kv('rewritten', '3 times in one day: Cerebras, Gemini, Mistral'),
    kv('pinned by', '8 tests in test/mistral_client_test.dart'),
    ...sec('why this file exists'),
    ...para('//',
        'Everything the app knows about talking to a language model '
        'lives here. The sidebar collects preferences, the providers '
        'hold state, the widgets draw topics; none of them knows what '
        'an HTTP request looks like, which model answers, or how the '
        'prompt is worded. They call two methods, generate and '
        'refine, and get typed objects back or one of two exceptions. '
        'That narrow seam is the reason the file could be replaced '
        'wholesale, twice, in a single afternoon without touching a '
        'screen.'),
    ...para('//',
        'It has three jobs. It turns the user’s selections into a '
        'system prompt strict enough to keep the model inside the '
        'user’s chosen fields. It sends that prompt through a '
        'Cloudflare relay and reads the answer. And it treats the '
        'answer with suspicion: stripping fences the model should not '
        'have written, retrying once if the JSON does not parse, and '
        'decoding entities it was told not to emit.'),
    ...sec('one seam, three providers'),
    ...para('//',
        'The git history of this path is unusual: three different '
        'providers in about three hours, all on 2026-08-06. Reading '
        'the sequence shows which parts of the file are essential and '
        'which are replaceable.'),
    ...pt('//', '09:41 UTC, 7a200e7 — Cerebras, llama-3.3-70b',
        'a non-streaming chat/completions call made straight from the '
        'browser with temperature 0.7 and max_tokens 4000. The prompt '
        'already contained all nine rules and the full JSON schema in '
        'prose, and the parser already stripped fences and retried '
        'once on invalid JSON.'),
    ...pt('//', '10:28 UTC, c1b3d71 — Cerebras, zai-glm-4.7',
        'switched to the new model with streaming (server-sent '
        'events), max_tokens 65000, temperature 1 and top_p 0.95, and '
        'a live “receiving N characters” indicator. The commit also '
        'fixed the sanitiser bug (see lib/services/sanitize.dart).'),
    ...pt('//', '10:52 UTC, ebafa0f — Gemini, gemini-3.6-flash',
        'a full swap, no dual-provider path. Gemini’s native '
        'structured output (responseMimeType plus a responseSchema '
        'with minItems and maxItems) replaced the schema in the prose '
        'prompt, so the counts were enforced structurally. Streaming '
        'was dropped. The retry was widened to any failure, and the '
        'client learned Gemini’s error shapes, including a 400 with '
        'API_KEY_INVALID.'),
    ...pt('//', '12:19 UTC, 98e7e48 — Mistral, mistral-large-latest',
        'the version on this page. A Cloudflare Worker relay was '
        'added because, per the commit message, Mistral’s endpoint '
        'does not reliably answer browser CORS preflights. The schema '
        'went back into the prompt, and the retry went back to '
        'invalid-JSON only.'),
    ...para('//',
        'Two facts stand out when the versions are compared. First, '
        'the nine-rule system prompt in this file is character for '
        'character the same as the Cerebras one from the scaffold '
        'commit; a diff of the two prompt bodies is empty. Only the '
        'Gemini version differs, because there the schema text was '
        'replaced by the provider’s structured-output feature. The '
        'prompt is the product; the provider is a plug. Second, the '
        'repository does not record why Cerebras gave way to Gemini '
        'or Gemini to Mistral. The commit messages say what changed '
        'and, for the last swap, what forced a relay; they never say '
        'what was wrong with the provider that was dropped.'),
    ...sec('the contract: two exceptions'),
    ...code('dart', 'lib/services/mistral_client.dart · the two failure types', r'''
/// Thrown when Mistral rejects the API key (401/403). The caller should
/// clear the key and return to the unlock screen.
class ApiKeyRejectedException implements Exception {
  final String message;
  const ApiKeyRejectedException([this.message = 'Your API key was rejected.']);
  @override
  String toString() => message;
}

/// Any other failure talking to Mistral (network, malformed response, etc).
/// The message is always safe to show the user — it never includes the key.
class MistralApiException implements Exception {'''),
    ...para('//',
        'The split between the two types is a design decision about '
        'who reacts. A rejected key is not an error to show in a '
        'banner; it is a state change. The generation provider '
        'catches ApiKeyRejectedException, forgets the key, and the '
        'root widget swaps back to the unlock screen. Everything else '
        'is a message for a dismissible banner. By making them '
        'different classes, the file lets the caller choose the '
        'reaction with an on clause and no string matching.'),
    ...para('//',
        'The second doc comment makes a promise that the code keeps: '
        'no message anywhere in this file interpolates the key. The '
        'only place the key appears at all is the Authorization '
        'header of the request.'),
    ...sec('the endpoint and the model'),
    ...code('dart', 'lib/services/mistral_client.dart · what it talks to', r'''
  static const _relayUrl = 'https://xyno-scholar-relay.xyno-scholar.workers.dev';
  static const _model = 'mistral-large-latest';

  final http.Client _http;

  MistralClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  void dispose() => _http.close();'''),
    ...para('//',
        'The URL is the deployed relay from worker/, not '
        'api.mistral.ai. The doc comment above it gives the reason in '
        'one sentence and points to worker/README.md. The placeholder '
        'URL was replaced with the real one in b3d2b1c, after the '
        'Worker was deployed.'),
    ...para('//',
        'The HTTP client is injected through an optional constructor '
        'parameter and defaults to a real one. That single optional '
        'parameter is the entire testing strategy: the tests pass a '
        'MockClient from package:http/testing and never open a '
        'socket. The provider that owns the client closes it on '
        'dispose.'),
    ...para('//',
        'The model is the floating alias mistral-large-latest, so the '
        'provider can change the model underneath the app. And notice '
        'what is absent from the request later in the file: no '
        'temperature, no top_p, no max_tokens. The second Cerebras '
        'version and the Gemini version pinned temperature 1, top_p '
        '0.95 and 65000 output tokens; this version uses Mistral’s '
        'defaults. The repository does not say why the explicit '
        'settings were dropped.'),
    ...sec('the system prompt, rule by rule'),
    ...para('//',
        'The prompt is built by interpolating the user’s selections '
        'into a fixed template. It opens by casting the model as a '
        'research-topic advisor for an undergraduate-and-above '
        'scholar, then lists nine rules the model must follow without '
        'exception. The first three are the core promise of the '
        'product, which is that selecting several fields means every '
        'suggestion must stand on all of them.'),
    ...code('dart', 'lib/services/mistral_client.dart · rules 1 to 3 (wrapped for display)', r'''
1. Never drop a selected field. The user has selected exactly these fields: [$fieldsList].
EVERY proposed subject must genuinely engage ALL of these fields substantively — not merely be superficially compatible with them.
2. Never add a field the user did not select, and never assume one field implies another
(e.g. theology does not imply art, history does not imply theology, etc).
Fields to actively avoid, if any: [$excludedList].
3. If the user's free-text input conflicts with, or implies, a field that is NOT in the selected list,
ask exactly ONE short clarifying question in the "clarifyingQuestion" field of the JSON response
— but you must STILL provide usable topic options in the same response. Never return a bare question with nothing else.'''),
    ...pt('//', 'rule 1, never drop a field',
        'a multi-field query is easy for a model to quietly collapse '
        'into its favourite field. The prompt says all fields, '
        'substantively, and the word superficially rules out the '
        'cheap answer in which a topic merely does not conflict with '
        'the other fields. The selected fields are passed as ids '
        '(history, catholic_theology, art are the defaults), not as '
        'display labels.'),
    ...pt('//', 'rule 2, never add a field',
        'the symmetrical failure: a model that decides theology '
        'obviously implies art. The example pair is chosen from the '
        'app’s own default fields. The exclusion list comes from a '
        'sidebar card where the user types fields to avoid.'),
    ...pt('//', 'rule 3, ask one question, but still deliver',
        'the app has a detector for fields implied by free text '
        '(lib/services/field_detection.dart), but the model gets a '
        'say too. The prompt allows exactly one clarifying question, '
        'and then forbids stopping there. The phrase never return a '
        'bare question is a response to a known chatbot habit; it '
        'keeps the interface from ever dead-ending on a question, and '
        'the UI shows the question in a banner above whatever topics '
        'came back.'),
    ...code('dart', 'lib/services/mistral_client.dart · rules 4 and 5 (excerpt)', r'''
   - tone playful = light, witty phrasing; tone serious = measured, formal academic phrasing; tone neutral = plain, matter-of-fact phrasing.
   - mood curious = exploratory, open questions; mood provocative = challenges assumptions, bold framing; mood reverent = respectful, careful of sensitive subject matter; mood irreverent = unconventional, willing to poke at orthodoxy.
   - licence: bounded, accessible corpus, no paleography or ancient-language skills required.
   - master: specialized historiography, situates the topic within a scholarly debate.
   - memoire: focused methodology built around one precise, tractable problématique.
   - phd: original archival contribution, extensive and demanding primary corpus.
   - general_public: no technical jargon, accessible to a curious non-specialist.'''),
    ...para('//',
        'Tone and mood are not left to the model’s imagination: each '
        'of the three tones and four moods is defined in a clause, '
        'and each of the five academic levels is defined by what kind '
        'of corpus it can handle. These definitions closely parallel '
        'the one-line descriptions in lib/models/enums.dart that the '
        'level card in the sidebar shows to the user, so what the '
        'user reads when choosing a level is nearly what the model is '
        'told. The level definitions are written in the vocabulary of '
        'a French university (licence, master, mémoire), which is the '
        'app’s audience, and the prompt itself is in English while '
        'the answer language is set by rule 7.'),
    ...code('dart', 'lib/services/mistral_client.dart · rules 6 to 9 (wrapped for display)', r'''
6. Every subject must name REAL, VERIFIABLE events, works, people, or documents.
Never invent anecdotes or fabricate references, titles, or names.
7. Write all output text in this language: "${prefs.language}".
   - Never emit raw HTML tags or HTML/numeric character entities (e.g. "&#128161;", "&amp;") anywhere in any field.
   - Title fields are plain text: no Markdown, no emoji.
9. Your entire response must be a single strictly valid JSON object matching the schema below. No prose outside the JSON.
No markdown code fences around the JSON itself. No trailing commas.'''),
    ...pt('//', 'rule 6, real and verifiable',
        'the most important rule for a research tool, and the one '
        'that nothing in the code can enforce. The prompt asks the '
        'model not to fabricate references, and no function in this '
        'repository checks a single title, author or year. A starter '
        'bibliography from a language model is a list of leads to '
        'check, and the app does not claim otherwise in code.'),
    ...pt('//', 'rule 8, the formatting rules',
        'the reason sanitize.dart exists. The prompt forbids entities '
        'and the sanitiser repairs them anyway. Title fields are '
        'declared plain text, which fits the fact that titles are '
        'drawn with a plain Text widget, and prose fields may use '
        'light Markdown, which fits the markdown renderer that draws '
        'them.'),
    ...pt('//', 'rule 9, JSON only',
        'the prompt asks for no fences and no prose, and the parser '
        'below strips fences anyway. Each rule that matters has a '
        'prompt half and a code half, so the system degrades '
        'gracefully when the model ignores the prompt.'),
    ...sec('why the schema is written out in prose'),
    ...para('//',
        'JSON mode, selected with response_format of type json_object '
        'in the request body, guarantees that the reply is '
        'syntactically valid JSON. It does not guarantee that the '
        'reply has the fields the app expects. The comment on the '
        'retry method says so explicitly. So the prompt spells out '
        'the exact shape, and then the counts that matter:'),
    ...code('dart', 'lib/services/mistral_client.dart · rules for populating the schema (wrapped for display)', r'''
Rules for populating the schema:
- If scope is "broad": populate "broadTopics" with 5 to 8 entries, leave "narrowTopic" null.
- If scope is "narrow": populate "narrowTopic" with exactly 3 entries in "starterBibliography"
and exactly 3 entries (I, II, III) in "suggestedStructure", leave "broadTopics" an empty array.
- Always set "fieldsCovered" at the top level to the full list of fields you engaged with.'''),
    ...para('//',
        'This is the part that moved around between providers. With '
        'Gemini, the same constraints were expressed as minItems and '
        'maxItems in a schema object and enforced by the API: exactly '
        'three bibliography entries, exactly three outline parts, and '
        'at most eight broad topics. (The Gemini commit message '
        'claims a minimum of five broad topics, but the schema in '
        'that file has minItems 0, which the rest of the file implies '
        'was needed because a narrow reply must leave the array '
        'empty.) Here they are a sentence, which a model can ignore, '
        'and nothing on the client verifies them: the models in '
        'lib/models read missing keys as empty strings and short '
        'lists as short lists. The tests assert exactly three '
        'entries, but only because the test data has exactly three. '
        'The honest summary is that the schema is a strong request in '
        'this version, and a guarantee only in the Gemini version.'),
    ...para('//',
        'The refine path repeats the lesson. Its instruction now says '
        'to return the full narrowTopic object, still with exactly 3 '
        'starterBibliography entries and 3 suggestedStructure parts, '
        'which is a clause the Gemini version did not need.'),
    ...sec('the user turn'),
    ...code('dart', 'lib/services/mistral_client.dart · _userTurn (trimmed)', r'''
  Map<String, dynamic> _userTurn({
    required PreferenceBlock prefs,
    required String freeText,
    String? focusTitle,
  }) {
    final payload = {
      'preferences': prefs.toJson(),
      if (freeText.trim().isNotEmpty) 'freeTextFocus': freeText.trim(),
      if (focusTitle != null) 'deepDiveOnTitle': focusTitle,
      'instruction': prefs.scope.apiValue == 'narrow'
    ...
    };
    return {'role': 'user', 'content': jsonEncode(payload)};
  }'''),
    ...para('//',
        'The user message is itself a JSON document: the preference '
        'block, an optional free-text focus, an optional title to '
        'dive into, and a one-line instruction chosen by scope. Two '
        'details are worth reading closely. The free text is included '
        'only if it is non-empty after trimming, so an empty box adds '
        'no noise. And the instruction is selected by the scope '
        'preference, not by anything in the title: a deep dive is '
        'just a generate call with deepDiveOnTitle set, and it is the '
        'scope setting alone that decides whether the model returns a '
        'list or a single topic. That has a consequence for the '
        'generation provider’s deepDive method, discussed on its '
        'page.'),
    ...para('//',
        'Wrapping the user’s text in a labelled JSON field has a side '
        'effect that may or may not have been intended: the model '
        'always sees the free text as the value of a named key, never '
        'as bare instructions. Prompt injection is not a threat model '
        'here anyway; the only person who can type into the box is '
        'the owner of the key.'),
    ...sec('one request'),
    ...code('dart', 'lib/services/mistral_client.dart · _chat (trimmed)', r'''
      response = await _http.post(
        Uri.parse(_relayUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': messages,
          'response_format': {'type': 'json_object'},
        }),
      );
    } catch (_) {
      throw const MistralApiException(
        'Could not reach Mistral. Check your connection and try again.',
      );
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const ApiKeyRejectedException();
    }
    if (response.statusCode != 200) {
      throw MistralApiException(
        'Mistral returned an error (HTTP ${response.statusCode}). Please try again.',
      );
    }'''),
    ...para('//',
        'The request body is three fields. The headers are the pair '
        'the Worker forwards. Failure handling is three rules in '
        'order: any exception from the call (no network, a blocked '
        'request, a relay that is down) becomes the could-not-reach '
        'message; 401 and 403 become the rejected-key exception; '
        'every other non-200 status becomes a generic message with '
        'the status code in it.'),
    ...para('//',
        'Notice what was removed compared with the Gemini version. '
        'That one parsed the error body and showed the provider’s own '
        'message, and had a dedicated function to recognise a 400 '
        'that meant a bad key. This version never reads an error '
        'body. A rate-limit response and a server error both become '
        'the same sentence with a number. It is simpler and less '
        'informative, and the number at least tells the user which '
        'kind of failure it was.'),
    ...para('//',
        'Two things are not here. There is no timeout on the post: a '
        'large-model JSON generation can take a while, and if the '
        'relay hangs the interface waits. And a 403 is treated as a '
        'bad key even though a 403 can mean other things; the cost of '
        'being wrong is that the user is asked to type the key again.'),
    ...sec('reading the reply'),
    ...code('dart', 'lib/services/mistral_client.dart · _extractContent (trimmed)', r'''
    final choices = chatResponse['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw const MistralApiException('Mistral returned no response content.');
    }
    final message = choices.first['message'] as Map<String, dynamic>?;
    final content = message?['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw const MistralApiException('Mistral returned an empty response.');
    }'''),
    ...para('//',
        'The OpenAI-compatible shape: the text lives at '
        'choices[0].message.content. Each step is null-safe and each '
        'failure has its own message, so an empty reply is '
        'distinguishable from a missing one. The test helper in '
        'test/mistral_client_test.dart builds exactly this envelope, '
        'which is how the tests exercise the whole path without a '
        'network.'),
    ...sec('defending against the model: fences and one retry'),
    ...code('dart', 'lib/services/mistral_client.dart · _stripCodeFences (trimmed)', r'''
  String _stripCodeFences(String text) {
    var trimmed = text.trim();
    final fenceMatch = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
    ).firstMatch(trimmed);'''),
    ...para('//',
        'Models like to wrap JSON in a markdown code fence even when '
        'told not to. The regular expression accepts the whole text '
        'as one fenced block, with or without the json tag, and '
        'extracts the inside. It is anchored at both ends, so it only '
        'fires when the entire reply is a fence; a reply with a '
        'sentence of prose before the fence is left alone and goes '
        'down the retry path. A dedicated test, generate() strips '
        'markdown code fences before parsing, exists in the Mistral '
        'test file and did not exist in the Gemini one, presumably '
        'because structured output made fences a non-issue there.'),
    ...code('dart', 'lib/services/mistral_client.dart · the retry (trimmed, long string wrapped)', r'''
    final chatResponse = await _chat(apiKey: apiKey, messages: messages);
    final rawContent = _extractContent(chatResponse);
    final cleaned = _stripCodeFences(rawContent);

    try {
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
      return sanitizeJsonTree(parsed) as Map<String, dynamic>;
    } catch (_) {
      final retryMessages = [
        ...messages,
        {'role': 'assistant', 'content': rawContent},
        {
          'role': 'user',
          'content':
              'Your last message was not valid JSON. Resend your ENTIRE answer again,
              as ONE strictly valid JSON object matching the schema from the system prompt.
              Output nothing except the JSON object: no prose, no markdown code fences.',
        },
      ];'''),
    ...para('//',
        'The retry is a small conversation, not a blind repeat. The '
        'second request contains the original messages, then the '
        'model’s own bad answer as an assistant turn, then a '
        'corrective user turn. Showing the model what it just wrote '
        'is more effective than asking again from scratch, because it '
        'can see what to fix. The same corrective wording appears in '
        'the scaffold commit’s Cerebras client. The Gemini version '
        'dropped it and simply repeated the request, and this version '
        'restored it.'),
    ...para('//',
        'Retrying exactly once is a budget decision. Each attempt is '
        'a full generation call that can be slow and, with a paid '
        'key, costs money. After the second failure the client throws '
        'the invalid-JSON-even-after-a-retry error. Note the scope of '
        'the retry: only a parse failure retries. A network error, a '
        '500 or a 401 on the first call propagates immediately; the '
        'Gemini version retried every kind of failure.'),
    ...para('//',
        'The try block contains the parse, the sanitiser call and the '
        'cast to Map<String, dynamic>. The handler is a bare catch '
        'that does not inspect what it caught, which is exactly how '
        'the sanitiser’s type bug hid as invalid JSON for the first '
        '47 minutes of the project.'),
    ...sec('the two public methods'),
    ...code('dart', 'lib/services/mistral_client.dart · generate', r'''
  Future<GenerationResponse> generate({
    required String apiKey,
    required PreferenceBlock prefs,
    String freeText = '',
    String? deepDiveOnTitle,
  }) async {
    final messages = [
      {'role': 'system', 'content': _systemPrompt(prefs)},
      _userTurn(prefs: prefs, freeText: freeText, focusTitle: deepDiveOnTitle),
    ];
    final json = await _requestJson(apiKey: apiKey, messages: messages);
    return GenerationResponse.fromJson(json);
  }'''),
    ...para('//',
        'generate is the whole happy path in four statements: build a '
        'two-message conversation, request JSON, convert it to a '
        'typed object. The key is a parameter, not a field, so the '
        'client holds no secret between calls; whoever calls it '
        'passes the current key from the key provider.'),
    ...code('dart', 'lib/services/mistral_client.dart · refine (trimmed)', r'''
          'existingNarrowTopic': currentTopic.toJson(),
          'refinementRequest': refinementInstruction,
    ...
    if (response.narrowTopic == null) {
      throw const MistralApiException(
        'Mistral did not return a refined topic.',
      );
    }
    return response.narrowTopic!;'''),
    ...para('//',
        'refine sends the same system prompt, so every rule still '
        'applies to the revised topic, together with the existing '
        'topic as JSON and the user’s instruction. It asks for the '
        'full updated topic plus a refinementSummary field describing '
        'what changed, and it unwraps the reply down to the '
        'NarrowTopic. If the model answers with no narrowTopic, there '
        'is nothing to show and the method throws.'),
    ...sec('what the tests cover and what they do not'),
    ...para('//',
        'Eight tests in test/mistral_client_test.dart use a '
        'MockClient and cover: a broad reply (and the request’s '
        'model, JSON mode and header), a narrow reply, a refine, '
        'fence stripping, a successful retry (two calls), retry '
        'exhaustion, and a 401 and a 403 each mapping to the '
        'rejected-key exception.'),
    ...para('//',
        'Not covered by any test: a network failure, a non-200 status '
        'other than 401 and 403, an empty or missing choices list, a '
        'refine that returns no narrowTopic, the content of the '
        'system prompt, the shape of the user turn and the relay URL. '
        'The prompt, which is the thing that makes the product what '
        'it is, is untested text. There is also no test that runs '
        'against a real model or the real relay. The only live checks '
        'the repository records are the relay’s: the deploy commit '
        'reports a real preflight and an invalid-key POST. Whether '
        'the app was ever run end to end with a valid key is not '
        'recorded.'),
    ...sec('limits and findings'),
    ...pt('//', 'no timeout',
        'the post waits as long as the relay does.'),
    ...pt('//', 'prompt rules are requests',
        'nothing validates that fields were respected, that '
        'references are real, or that counts are right.'),
    ...pt('//', 'errors lose detail',
        'Mistral’s error bodies are never read, so a rate-limit '
        'message and a server error look alike apart from the status '
        'number.'),
    ...pt('//', 'a bare catch around the parse',
        'a genuine bug in the sanitiser or in the cast would still '
        'read as bad JSON.'),
    ...pt('//', 'one retry covers one failure class',
        'a transient 5xx gets no second chance.'),
    ...pt('//', 'trust in the relay',
        'the user’s key goes through a server the user does not '
        'control; see the page for worker/src/index.js.'),
    ...sec('what changed over time'),
    ...para('//',
        'One day, four rewrites of the same seam. The first version '
        'was a complete, working shape: prompt, post, parse, retry. '
        'The second added streaming and sampling settings and was '
        'replaced within 24 minutes. The third swapped the whole '
        'protocol for a provider with native schemas. The fourth went '
        'back to the simplest protocol, added the relay, and restored '
        'the prose schema. What stayed constant is the list of nine '
        'rules, the fence stripper, the retry text and the sanitiser. '
        'What kept changing is exactly what the seam was built to '
        'isolate.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
