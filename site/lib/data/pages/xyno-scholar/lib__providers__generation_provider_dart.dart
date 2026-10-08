import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/providers/generation_provider.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'generation_provider.dart — the state machine between a button and a model'),
    cm('//', 'loading, error, result, and the one failure that changes screens'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'runs generate, deep dive and refine, and publishes their state to the UI'),
    kv('language', 'Dart, Riverpod 2.6 (Notifier)'),
    kv('size', '150 lines: 1 state class, 1 controller with 4 actions, 2 providers'),
    kv('renamed', '3 times, once per provider swap (cerebras, gemini, mistral)'),
    kv('tests', 'none directly; the client under it has 8'),
    ...sec('why this file exists'),
    ...para('//',
        'The model client in lib/services/mistral_client.dart is '
        'deliberately dumb about the interface: it takes arguments, '
        'returns a typed object or throws. The widgets are '
        'deliberately dumb about the network: they show what they are '
        'given. Something has to sit between a press of the Generate '
        'button and a card of topics on screen, hold the in-between '
        'states, and decide what each kind of failure should do. This '
        'controller is that something. It reads the preferences and '
        'the key at the moment of the call, hands them to the client, '
        'and turns the outcome into one of four things the UI can '
        'render: nothing yet, loading, a result, or an error banner. '
        'A fifth outcome, a rejected key, leaves the screen '
        'altogether.'),
    ...sec('the state'),
    ...code('dart', 'lib/providers/generation_provider.dart · GenerationState (trimmed)', r'''
class GenerationState {
  final bool isLoading;
  final String? error;
  final GenerationResponse? response;
  final bool isRefining;'''),
    ...para('//',
        'Four fields cover every situation. response is the last '
        'successful result and stays in place while a new request '
        'runs. isLoading says a call is in flight. error carries a '
        'message to show in the banner. isRefining narrows isLoading '
        'to the refine tab’s own button, so the sidebar’s spinner and '
        'the refine tab’s spinner do not both light up when only one '
        'thing was pressed.'),
    ...code('dart', 'lib/providers/generation_provider.dart · copyWith', r'''
  GenerationState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
    GenerationResponse? response,
    bool? isRefining,
  }) {
    return GenerationState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      response: response ?? this.response,
      isRefining: isRefining ?? this.isRefining,
    );
  }'''),
    ...para('//',
        'The extra clearError parameter is a standard Dart '
        'workaround. In copyWith, passing null means keep the old '
        'value, so there is no way to say set this field to null. A '
        'boolean flag makes the intent explicit: clearError: true '
        'wins over any error argument. The same limitation applies to '
        'response, which can be replaced but not cleared through '
        'copyWith; the reset method sidesteps it by returning a brand '
        'new state.'),
    ...para('//',
        'Keeping the old response while loading is a deliberate '
        'user-interface choice with a visible effect. The output '
        'panel shows the big spinner only when isLoading is true and '
        'there is no response yet; on a second generation the '
        'previous topics stay on screen while the sidebar button '
        'shows its small spinner. Nothing flashes blank.'),
    ...sec('one runner for generate and deep dive'),
    ...code('dart', 'lib/providers/generation_provider.dart · _run', r'''
  Future<void> _run(Future<GenerationResponse> Function() call) async {
    final apiKey = ref.read(apiKeyProvider).key;
    if (apiKey == null || apiKey.isEmpty) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await call();
      state = state.copyWith(isLoading: false, response: response);
    } on ApiKeyRejectedException catch (e) {
      ref.read(keyRejectedMessageProvider.notifier).state = e.message;
      ref.read(apiKeyProvider.notifier).forget();
      state = state.copyWith(isLoading: false, clearError: true);
    } on MistralApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Something went wrong while talking to Mistral.',
      );
    }
  }'''),
    ...para('//',
        'The method takes the work as a closure, so both generate and '
        'deepDive share the same bookkeeping: set loading and clear '
        'the previous error, run, then publish either the response or '
        'the failure. There are three kinds of failure and each has '
        'its own arm.'),
    ...pt('//', 'ApiKeyRejectedException',
        'not an error state at all. The arm records the rejection '
        'message, calls forget() on the key controller, and clears '
        'the loading flag. The forget() makes the root widget swap to '
        'the unlock screen, which sees the rejection flag and shows '
        'its warning. The user never sees a banner; they see the door '
        'they must go back through.'),
    ...pt('//', 'MistralApiException',
        'the client’s safe-to-show messages (could not reach Mistral, '
        'an HTTP status, an unreadable or empty reply, invalid JSON '
        'after a retry). They land in the banner unchanged.'),
    ...pt('//', 'anything else',
        'a generic sentence. This arm matters more than it looks, '
        'because of where the typed parsing happens. The client '
        'returns GenerationResponse.fromJson(json), and the models '
        'cast nested values with as. If the model returns valid JSON '
        'in the wrong shape (a string where a list belongs), the cast '
        'throws a TypeError that is not a MistralApiException. The '
        'retry loop in the client has already finished by then, so a '
        'wrong-shaped answer is never retried; it ends up here as the '
        'generic message. Only invalid syntax gets a second chance.'),
    ...para('//',
        'The first line of the method is a guard: with no key the '
        'method returns without doing anything. The buttons already '
        'hide behind the locked screen, so this is belt and braces.'),
    ...sec('deep dive, and a question mark'),
    ...code('dart', 'lib/providers/generation_provider.dart · deepDive (trimmed)', r'''
  Future<void> deepDive(BroadTopic topic) async {
    final apiKey = ref.read(apiKeyProvider).key;
    final prefs = ref.read(preferenceBlockProvider);
    final client = ref.read(mistralClientProvider);
    await _run(
      () => client.generate(
        apiKey: apiKey!,
        prefs: prefs.copyWith(),
        freeText: topic.keyKeywords.join(', '),
        deepDiveOnTitle: topic.title,
      ),
    );
  }'''),
    ...para('//',
        'The Deep Dive button on a broad topic calls this. It reuses '
        'the whole generation path with two changes: the free text '
        'becomes the topic’s keywords, and the topic’s title is '
        'passed as deepDiveOnTitle. The sidebar’s free-text box is '
        'not read here, so a deep dive follows the topic that was '
        'clicked and not whatever the user last typed.'),
    ...para('//',
        'Now the question mark. The call passes prefs.copyWith() with '
        'no arguments, which is a plain copy of the preferences, not '
        'a change. As the client builds the user turn, the '
        'instruction it sends is chosen by prefs.scope: narrow asks '
        'for one deep-dive topic, anything else asks for five to '
        'eight broad options. Nothing in lib/ sets the scope to '
        'narrow on the way into a deep dive; the scope only changes '
        'when the user moves the toggle in the sidebar, and its '
        'default is broad. Reading the code, a deep dive started with '
        'the default settings would send the instruction to generate '
        'broad topic options together with a title to focus on. The '
        'empty copyWith() looks like the place where a scope: '
        'Scope.narrow override was meant to go. I read this from the '
        'code and did not run the app against a live model, so I '
        'cannot say what Mistral returns in that case; it is the '
        'first thing I would test.'),
    ...sec('refine, which is not quite a runner'),
    ...code('dart', 'lib/providers/generation_provider.dart · refine (trimmed)', r'''
    state = state.copyWith(isLoading: true, isRefining: true, clearError: true);
    try {
      final updated = await client.refine(
        apiKey: apiKey,
        prefs: prefs,
        currentTopic: topic,
        refinementInstruction: instruction,
      );
      final current = state.response;
      state = state.copyWith(
        isLoading: false,
        isRefining: false,
        response: GenerationResponse(
          scope: 'narrow',
          language: current?.language ?? prefs.language,
          fieldsCovered: current?.fieldsCovered ?? prefs.fields,
          narrowTopic: updated,
        ),
      );'''),
    ...para('//',
        'Refine repeats the structure of _run instead of calling it, '
        'with a different tail. It needs the isRefining flag, and it '
        'does not replace the old response with whatever came back; '
        'it rebuilds one. The client returns only the updated '
        'NarrowTopic, so the controller wraps it in a fresh '
        'GenerationResponse with scope narrow, borrowing language and '
        'fieldsCovered from the current response (or, if there is '
        'none, from the preferences). The clarifying question and the '
        'broad-topics list are dropped, which is right for a screen '
        'that now shows a single refined topic.'),
    ...para('//',
        'The cost of the copy is duplicated error handling. The three '
        'catch arms are written out a second time, with different '
        'generic text (Something went wrong while refining this '
        'topic), and a change to the key-rejection choreography has '
        'to be made in two places. A small refactor would pass the '
        'post-processing in as a second closure and let _run own all '
        'the arms.'),
    ...sec('wiring'),
    ...code('dart', 'lib/providers/generation_provider.dart · the client provider', r'''
final mistralClientProvider = Provider<MistralClient>((ref) {
  final client = MistralClient();
  ref.onDispose(client.dispose);
  return client;
});'''),
    ...para('//',
        'The client is created lazily, once, and closed when the '
        'container is disposed. This provider is also the replacement '
        'seam: a test or a different environment can override '
        'mistralClientProvider with a client built on a mock HTTP '
        'client. The controller itself never sees the key as part of '
        'its state. It reads it from the key provider at the moment '
        'of each call and passes it down as an argument, so the key '
        'is held in state by exactly one object, the key controller.'),
    ...para('//',
        'The UI side of the contract is small. The sidebar’s Generate '
        'button disables itself while isLoading is true, as do the '
        'Deep Dive buttons and the refine presets. That is where '
        'double submission is prevented: not in the controller, which '
        'has no re-entrancy guard of its own. The banner’s dismiss '
        'button calls clearError, the only action besides the three '
        'that call the model. A reset method exists and is never '
        'called, so the previous result survives a log-out within the '
        'same page session.'),
    ...sec('what this file has lived through'),
    ...para('//',
        'In the span of one day this file was renamed and edited by '
        'each provider swap, and every change was mechanical: the '
        'client type and its exception class. One change was larger '
        'and was undone. In c1b3d71 (10:28 UTC) streaming support '
        'added a streamedChars field, an onProgress callback threaded '
        'through generate, deepDive and refine, and a changed '
        'signature for _run. The output panel and two buttons showed '
        'a live “receiving N characters” count. In ebafa0f, 24 '
        'minutes later, the Gemini swap removed all of it, and the '
        'signature went back to a plain closure. What survived the '
        'round trip unchanged is the shape of the state machine '
        'itself.'),
    ...para('//',
        'The identical error choreography across Cerebras, Gemini and '
        'Mistral is the strongest evidence for the layering. Three '
        'different providers with three different error shapes all '
        'arrive at the controller as the same two exception types.'),
    ...sec('testing and limits'),
    ...pt('//', 'no direct tests',
        'the controller’s behaviour (state transitions, the '
        'key-rejection hand-off, the refine merge) is not pinned. A '
        'ProviderContainer with an overridden client would make each '
        'of those a short test.'),
    ...pt('//', 'a possible deep-dive defect',
        'see above; untested and unconfirmed.'),
    ...pt('//', 'duplicated error arms',
        'in _run and refine.'),
    ...pt('//', 'no cancellation',
        'a request cannot be abandoned, and a second press is '
        'prevented only by the disabled button.'),
    ...pt('//', 'stale results after log-out',
        'the generation state is not reset when the key is forgotten.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
