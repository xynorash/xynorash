import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/test/mistral_client_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'mistral_client_test.dart — the client, tested without a network'),
    cm('//', 'eight tests that stand in for a live model, a key and a relay'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'unit tests for MistralClient: parsing, retry, key rejection, request shape'),
    kv('language', 'Dart; flutter_test, package:http MockClient'),
    kv('size', '312 lines, 8 tests, 2 fixtures'),
    kv('history', 'third incarnation of one file: Cerebras, Gemini, Mistral'),
    kv('runs on', 'plain Dart by import graph; confirmed in a scratch harness'),
    ...sec('why this file exists'),
    ...para('//',
        'The client under test talks to a language model through a '
        'relay. A live call needs a paid key, takes seconds, and '
        'returns different text every time, so it cannot be a '
        'regression test. What can be tested deterministically is '
        'everything around the model: how the request is built, how '
        'a reply is cleaned and parsed, what happens when the reply '
        'is malformed, and how an HTTP failure is turned into the '
        'exception the rest of the app understands. This file pins '
        'that surface with canned HTTP responses.'),
    ...para('//',
        'The result is a small suite with a specific character. It '
        'is a transport-and-parsing contract, not a prompt test. '
        'That distinction is the thread through the page, and it is '
        'measured near the end.'),
    ...sec('three lives of one file'),
    ...para('//',
        'The test file has been rewritten for every provider the '
        'app has used, all on 2026-08-06, and the history shows '
        'what a test suite keeps when its subject is replaced.'),
    ...bullet('10:28 UTC, c1b3d71',
        'test/cerebras_client_test.dart is created, 237 lines, with '
        'five tests of a mocked server-sent-event stream: broad '
        'scope, narrow scope, retry once, retry exhausted and a 401. '
        'The same commit created sanitize_test.dart after the mocks '
        'exposed a bug.'),
    ...bullet('10:52 UTC, ebafa0f',
        'replaced by test/gemini_client_test.dart, 364 lines, eight '
        'tests. A refine test appears, and three tests cover how '
        'that API reports a bad key: a 403, a 400 with an '
        'API_KEY_INVALID reason, and a plain 400 that must not be '
        'mistaken for a bad key.'),
    ...bullet('12:19 UTC, 98e7e48',
        'renamed to test/mistral_client_test.dart, 312 lines (52 '
        'fewer than before), eight tests. The two Gemini-only 400 '
        'tests go, a 401 test joins the 403 one, the '
        'request-shape assertions change, and a test for stripping '
        'Markdown code fences arrives.'),
    ...para('//',
        'What survived all three is the skeleton: broad, narrow, '
        'retry, retry exhausted, key rejected. That skeleton is the '
        'client’s real contract, independent of vendor. The details '
        'that changed with each swap, the endpoint shape, the '
        'streaming format and the error body, are exactly what the '
        'client was written to hide from the rest of the app.'),
    ...sec('the seam: an injectable HTTP client'),
    ...para('//',
        'Every test builds a MistralClient with an http.Client '
        'whose behaviour it controls. That is possible because the '
        'constructor takes the client as an optional named '
        'argument and falls back to a real one:'),
    ...code('dart', 'lib/services/mistral_client.dart · the constructor', r'''
  final http.Client _http;

  MistralClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  void dispose() => _http.close();'''),
    ...para('//',
        'In production the provider calls the constructor with '
        'nothing, and closes the client when the container is '
        'disposed:'),
    ...code('dart', 'lib/providers/generation_provider.dart · production wiring', r'''
final mistralClientProvider = Provider<MistralClient>((ref) {
  final client = MistralClient();
  ref.onDispose(client.dispose);
  return client;
});'''),
    ...para('//',
        'No mocking library is involved. package:http ships a '
        'MockClient in http/testing.dart, which takes a function '
        'from request to response. That function is also where a '
        'test records what was sent. This is the cheapest seam '
        'there is, and it is the reason eight tests fit in 312 '
        'lines.'),
    ...sec('the two fixtures'),
    ...code('dart', 'test/mistral_client_test.dart · the response wrapper', r'''
http.Response _chatCompletionResponse(String content) {
  return http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content},
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}'''),
    ...para('//',
        'The doc comment above it says it wraps the content the '
        'way an OpenAI-compatible chat completions reply does, the '
        'shape the relay returns unchanged. The structure is the '
        'minimum the client reads: a choices list whose first '
        'element has a message with a content string. The model’s '
        'JSON travels as a string inside this JSON, which is why '
        'every test passes a JSON string into the helper.'),
    ...code('dart', 'lib/services/mistral_client.dart · what the client reads', r'''
    final choices = chatResponse['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw const MistralApiException('Mistral returned no response content.');
    }
    final message = choices.first['message'] as Map<String, dynamic>?;
    final content = message?['content'] as String?;'''),
    ...code('dart', 'test/mistral_client_test.dart · the preference fixture', r'''
final _preferences = PreferenceBlock(
  fields: const ['history', 'art'],
  level: AcademicLevel.licence,
  tone: Tone.neutral,
  scope: Scope.broad,
  mood: Mood.curious,
  excludedFields: const [],
  language: 'en',
);'''),
    ...para('//',
        'One shared top-level value, copied with copyWith when a '
        'test needs the narrow scope. It uses two fields and '
        'English, not the app’s three default fields and French, '
        'so the tests are not coupled to the defaults in '
        'PreferenceBlock.initial.'),
    ...sec('test 1: the request contract'),
    ...para('//',
        'The first test is the only one that looks at what was '
        'sent. It captures every request in a list, runs one '
        'generate call, and then reads the captured request '
        'back:'),
    ...code('dart', 'test/mistral_client_test.dart · the assertions', r'''
      expect(capturedRequests, hasLength(1));
      final request = capturedRequests.single;
      expect(request.headers['Authorization'], 'Bearer test-key');
      expect(request.headers['x-goog-api-key'], isNull);

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'mistral-large-latest');
      expect(body['response_format'], {'type': 'json_object'});
      expect(body.containsKey('stream'), isFalse);
      expect((body['messages'] as List).first['role'], 'system');'''),
    ...para('//',
        'Against the client’s own request code:'),
    ...code('dart', 'lib/services/mistral_client.dart · the request', r'''
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
      );'''),
    ...bullet('hasLength(1)',
        'exactly one request for a successful call, so the retry '
        'path did not fire by accident.'),
    ...bullet('the Authorization header',
        'the key travels as a bearer token, which is what the '
        'relay copies straight through to Mistral.'),
    ...bullet('the model and the response format',
        'JSON mode is requested and the model is the large '
        'alias. The README describes JSON mode as a guarantee of '
        'syntax only, so these two lines are what keeps the '
        'parse step from receiving prose.'),
    ...bullet('the first message is the system prompt',
        'the schema and rules go in before the user turn. The '
        'test checks the role, not the text.'),
    ...para('//',
        'Two assertions are negative, and they read as scars. '
        'x-goog-api-key is the header the Gemini client used, and '
        'its test asserted the opposite. A stream key absent from '
        'the body is the leftover of two earlier designs, since '
        'the Cerebras client sent stream: true and the Gemini '
        'commit message says it dropped streaming. These are '
        'reasonable guards against a regression to a previous '
        'provider’s shape, but nobody would write them for a '
        'client that had always spoken to Mistral. That is an '
        'inference from the history, not something a comment says.'),
    ...sec('tests 2 and 3: the schema as a contract'),
    ...para('//',
        'The narrow-scope test feeds a complete topic and checks '
        'that the parsed object has three bibliography entries and '
        'three outline parts. The fixture uses all three source '
        'types the prompt allows, book, article and primary_source, '
        'and the three parts I, II and III. It is the schema in '
        'the system prompt written out as data, so the same fact is '
        'stated twice in the repository: once to the model, once to '
        'the test.'),
    ...para('//',
        'The refine test returns a topic that carries the extra '
        'refinementSummary field and asserts on the title and '
        'that summary. It feeds the refined topic back in as the '
        'current one:'),
    ...code('dart', 'test/mistral_client_test.dart · the refine call', r'''
    final client = MistralClient(httpClient: mockClient);
    final updated = await client.refine(
      apiKey: 'test-key',
      prefs: _preferences.copyWith(scope: Scope.narrow),
      currentTopic: NarrowTopic.fromJson(
        jsonDecode(refinedJson)['narrowTopic'] as Map<String, dynamic>,
      ),
      refinementInstruction: 'Shift the period to the 18th century',
    );'''),
    ...para('//',
        'This test therefore proves that a refined reply parses, '
        'and nothing about what is sent. It never looks at the '
        'request, so it cannot tell whether the existing topic and '
        'the instruction were included. The section on what the '
        'tests pin, below, gives the measurement.'),
    ...para('//',
        'The two narrow fixtures are near-identical blocks of about '
        'thirty lines each. A small builder function taking a title '
        'would halve that, at the price of hiding the schema shape '
        'from a reader. The duplication is a defensible choice in a '
        'file whose fixtures are its documentation.'),
    ...sec('test 4: fences, added late'),
    ...para('//',
        'Models told to emit only JSON sometimes wrap it in a '
        'Markdown fence anyway. The client strips one before '
        'parsing:'),
    ...code('dart', 'lib/services/mistral_client.dart · the stripper', r'''
  String _stripCodeFences(String text) {
    var trimmed = text.trim();
    final fenceMatch = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
    ).firstMatch(trimmed);'''),
    ...para('//',
        'The surprise is in the history. This function was in the '
        'very first Cerebras client of the scaffold commit 7a200e7, '
        'but no test in the Cerebras or Gemini versions of this '
        'suite exercised it. The test arrived with the Mistral '
        'swap, in 98e7e48. It feeds the client a fenced reply:'),
    ...code('dart', 'test/mistral_client_test.dart · a fenced reply', r'''
    final mockClient = MockClient((request) async {
      return _chatCompletionResponse('```json\n$validJson\n```');
    });'''),
    ...para('//',
        'Its fixture also contains something quiet. The reply has '
        'scope broad and an empty broadTopics list:'),
    ...code('dart', 'test/mistral_client_test.dart · an empty broad list', r'''
      'broadTopics': <Map<String, dynamic>>[],
      'narrowTopic': null,'''),
    ...para('//',
        'The prompt demands five to eight topics for a broad '
        'request, and the client accepts none without complaint. '
        'The retry fixtures do the same. Nothing on the client '
        'side validates those counts, nor the exactly-three rule '
        'for narrow replies, because the models’ fromJson methods '
        'default a missing list to empty. This is a real change '
        'from the Gemini period, whose commit message says '
        'minItems and maxItems were enforced structurally in the '
        'response schema. Under Mistral’s JSON mode those '
        'limits live only in the prompt text.'),
    ...sec('tests 5 and 6: one retry, no more'),
    ...para('//',
        'The client parses a reply and, if that fails, sends the '
        'conversation again with the bad answer and a corrective '
        'user message appended. The retry test serves garbage first '
        'and valid JSON second, using a counter:'),
    ...code('dart', 'test/mistral_client_test.dart · bad first, good second', r'''
      final mockClient = MockClient((request) async {
        callCount++;
        return _chatCompletionResponse(
          callCount == 1 ? 'this is not JSON at all' : validJson,
        );
      });'''),
    ...code('dart', 'test/mistral_client_test.dart · the retry assertions', r'''
      expect(callCount, 2);
      expect(response.scope, 'broad');'''),
    ...code('dart', 'lib/services/mistral_client.dart · what a retry sends', r'''
      final retryMessages = [
        ...messages,
        {'role': 'assistant', 'content': rawContent},'''),
    ...para('//',
        'callCount equal to two pins exactly one retry: not zero, '
        'and not a loop. The companion test serves non-JSON on '
        'every call and expects a MistralApiException. It does not '
        'assert the count, so it proves that the retry gives up but '
        'not after how many attempts.'),
    ...sec('tests 7 and 8: the unlock loop starts here'),
    ...code('dart', 'test/mistral_client_test.dart · a rejected key', r'''
  test('generate() throws ApiKeyRejectedException on 401', () async {
    final mockClient = MockClient((request) async {
      return http.Response('{"error":"invalid api key"}', 401);
    });

    final client = MistralClient(httpClient: mockClient);
    expect(
      () => client.generate(apiKey: 'bad-key', prefs: _preferences),
      throwsA(isA<ApiKeyRejectedException>()),
    );
  });'''),
    ...para('//',
        'The 403 test is its twin. They are the unit-level half of '
        'a longer chain: the exception type they pin is what the '
        'generation controller catches, which clears the key, which '
        'makes lib/app.dart swap the workbench for the unlock '
        'screen. If this type or its status mapping changed, the '
        'user would see a generic error instead of being asked for '
        'a new key. The 401 body mimics the live check recorded in '
        'commit b3d2b1c, which verified the deployed relay with an '
        'invalid key and got Mistral’s 401 back with CORS headers '
        'intact.'),
    ...para('//',
        'The closures return futures, and the test passes them '
        'to throwsA without an await. To my knowledge package:test '
        'tracks the future of an asynchronous matcher as pending '
        'work for the test, so this is the idiomatic form, not a '
        'forgotten await. I did not find that stated in this '
        'repository.'),
    ...sec('what the tests pin, measured'),
    ...para('//',
        'A test suite is judged by what breaks when the code '
        'does. I copied the pure-Dart parts of the project into a '
        'scratch package outside the repository, with package:test '
        'standing in for flutter_test, and the locked versions of '
        'http and html_unescape. All nine plain-Dart tests (these '
        'eight plus the sanitiser test) pass there. Then I changed '
        'one thing at a time in the copy of the client and ran the '
        'suite. Nothing in the repository was modified.'),
    ...para('//',
        'Caught, each by the test shown:'),
    ...bullet('model name changed',
        'caught by the request-contract test.'),
    ...bullet('response_format removed',
        'caught by the request-contract test.'),
    ...bullet('Bearer changed to another scheme',
        'caught by the request-contract test.'),
    ...bullet('403 no longer treated as a rejected key',
        'caught by the 403 test, alone.'),
    ...bullet('fence stripping disabled',
        'caught by the fence test, alone.'),
    ...bullet('retry removed',
        'caught by the retry-once test. The retry-exhausted test '
        'still passes, because it expects failure.'),
    ...bullet('the sanitiser bug restored',
        'six tests fail: the five that feed valid JSON, and the '
        'sanitiser’s own. Retry-exhausted keeps passing because '
        'it expects failure, and the 401 and 403 tests never '
        'reach the parser.'),
    ...para('//',
        'Not caught, zero failures in every case:'),
    ...bullet('the relay URL replaced with an invalid one',
        'the mock ignores the address. The Gemini test asserted '
        'the exact endpoint; the Mistral port dropped that line, '
        'and at 98e7e48 the URL was a placeholder with a TODO in '
        'the client until b3d2b1c replaced it. Whether that was '
        'the reason is a guess.'),
    ...bullet('any non-200 status made to look like a rejected key',
        'no test sends a 429 or a 500. The Gemini suite had a '
        'plain-400 test for exactly this distinction, and it was '
        'not ported.'),
    ...bullet('the Content-Type header removed',
        'the README names it as one of the two headers that make '
        'the browser send a preflight request, and no test checks '
        'it.'),
    ...bullet('the retry conversation altered',
        'blanking the corrective message, or leaving out the bad '
        'assistant turn, passes. Only the number of calls is '
        'pinned.'),
    ...bullet('the user turn',
        'dropping the free-text focus, the deep-dive title, the '
        'existing topic or the refinement request passes, each '
        'tried on its own.'),
    ...bullet('the whole system prompt',
        'replacing it with an empty string passes. The test checks '
        'only that a system message comes first.'),
    ...bullet('the sanitiser call in the client',
        'removing it entirely passes: no client test contains an '
        'HTML entity. Only the dedicated sanitiser test does.'),
    ...bullet('the empty-choices guard and the refine null check',
        'removing either passes.'),
    ...para('//',
        'The summary is clean enough to state as a rule: the suite '
        'protects the shape of the request’s configuration, the '
        'parsing pipeline, the retry count and the key-rejection '
        'mapping. It does not protect the prompt, the content of '
        'the user turn, the error branches other than the key, or '
        'the destination. Those are the parts most likely to be '
        'edited next.'),
    ...sec('a note on text encoding'),
    ...para('//',
        'Every fixture here is ASCII. The app defaults to French '
        'and the relay returns its body with a Content-Type of '
        'application/json and no charset parameter, so how accented '
        'characters are decoded matters. I checked the locked '
        'version of package:http (1.6.0): its header helper has a '
        'comment saying that application/json with no charset '
        'defaults to UTF-8, and a scratch run decoded a French word '
        'with an accent correctly. So the combination is safe. No '
        'test in the repository would notice if it stopped being '
        'so; one fixture with an accented title would.'),
    ...sec('how it is run'),
    ...para('//',
        'The imports reach only the models, the client and the '
        'sanitiser. By the import graph there is no use of a '
        'browser library, and the scratch harness confirms that it '
        'runs on the plain Dart VM. The README has no testing '
        'section and the deploy workflow does not run tests, so '
        'nothing records the command used or enforces a green '
        'suite before a deploy.'),
    ...sec('limits and what is next'),
    ...pt('//', 'pin the request fully',
        'assert the relay URL and the Content-Type, and check that '
        'the user turn contains the free text, the deep-dive title '
        'and the refine inputs. Each is a one-line expect on the '
        'captured request.'),
    ...pt('//', 'port the lost negative test',
        'a 500 and a 429 must raise MistralApiException and not '
        'ApiKeyRejectedException; this was covered under Gemini '
        'and silently dropped.'),
    ...pt('//', 'cover the transport failure',
        'a MockClient that throws should yield the connection '
        'message; it is one of several user-facing branches with '
        'no test.'),
    ...pt('//', 'validate the counts',
        'either assert in the client that a broad reply has 5 to 8 '
        'topics, or accept that the prompt is the only guard and '
        'say so in a test name.'),
    ...pt('//', 'run it in CI',
        'a single test step ahead of the build in '
        '.github/workflows/deploy.yml would turn all of the above '
        'from advice into a gate.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
