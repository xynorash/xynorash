import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/providers/api_key_provider.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'api_key_provider.dart — the lock that is also the router'),
    cm('//', 'the user’s key is app state, and whether it exists decides which screen you see'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'holds the Mistral API key in memory and decides locked or unlocked'),
    kv('language', 'Dart, Riverpod 2.6 (Notifier)'),
    kv('size', '52 lines: 1 state class, 1 controller, 2 providers'),
    kv('persists', 'nothing by default; sessionStorage if the user opts in'),
    kv('tests', 'none directly; the widget test exercises the locked state'),
    ...sec('why this file exists'),
    ...para('//',
        'Bring-your-own-key makes the API key a first-class piece of '
        'application state. Three questions follow from it. Where '
        'does the key live while the app runs? Who is allowed to read '
        'it? And what happens to the interface when it is missing or '
        'wrong? This file answers all three in 52 lines, and the '
        'answer to the third is the most unusual: there is no login '
        'route, no navigator push and no guard. Whether a key exists '
        'is the app’s routing table.'),
    ...sec('the state'),
    ...code('dart', 'lib/providers/api_key_provider.dart · ApiKeyState (trimmed)', r'''
class ApiKeyState {
  final String? key;
  final bool rememberedForSession;

  const ApiKeyState({this.key, this.rememberedForSession = false});

  bool get isUnlocked => key != null && key!.isNotEmpty;'''),
    ...para('//',
        'The state is an immutable value: the key, which can be null, '
        'and a flag recording whether it was mirrored to '
        'sessionStorage. The getter isUnlocked is the one question '
        'the rest of the app asks. Treating null and empty the same '
        'way means a blank string can never unlock the app by '
        'accident.'),
    ...para('//',
        'Two small observations about this class. The flag '
        'rememberedForSession is set in two places and read nowhere '
        'else in lib/: the unlock screen keeps its own local toggle, '
        'so this field is effectively write-only state. And the class '
        'has a copyWith that the controller never calls; every '
        'transition builds a fresh ApiKeyState. Its copyWith also '
        'cannot express clearing the key, because key ?? this.key '
        'keeps the old value when given null. Neither matters while '
        'nothing uses it, and both would matter the day someone did.'),
    ...sec('the controller'),
    ...code('dart', 'lib/providers/api_key_provider.dart · ApiKeyController', r'''
class ApiKeyController extends Notifier<ApiKeyState> {
  @override
  ApiKeyState build() {
    final remembered = SessionStorage.readApiKey();
    if (remembered != null && remembered.isNotEmpty) {
      return ApiKeyState(key: remembered, rememberedForSession: true);
    }
    return const ApiKeyState();
  }

  void setKey(String key, {required bool rememberForSession}) {
    final trimmed = key.trim();
    if (rememberForSession) {
      SessionStorage.writeApiKey(trimmed);
    } else {
      SessionStorage.clearApiKey();
    }
    state = ApiKeyState(key: trimmed, rememberedForSession: rememberForSession);
  }

  void forget() {
    SessionStorage.clearApiKey();
    state = const ApiKeyState();
  }
}'''),
    ...pt('//', 'build()',
        'runs once when the provider is first read. It consults '
        'sessionStorage and starts unlocked if a remembered key is '
        'there. This is the whole mechanism by which a reload in the '
        'same tab skips the unlock screen; a fresh tab finds nothing '
        'and starts locked.'),
    ...pt('//', 'setKey()',
        'trims the key (a key pasted from a console often carries a '
        'trailing space or newline, and a stray whitespace character '
        'would turn every request into a 401), then either writes or '
        'clears the stored copy depending on the toggle, then '
        'publishes the new state. The else branch is deliberate: '
        'unlocking with the toggle off erases a key remembered '
        'earlier, so the option is a revocation as well as a switch.'),
    ...pt('//', 'forget()',
        'clears storage and resets the state to locked. The app bar’s '
        'log-out button calls it, and so does the generation provider '
        'when Mistral rejects the key.'),
    ...para('//',
        'All three methods keep storage and state in step. The order '
        'is storage first, then state, so a listener that reacts to '
        'the new state never sees a state that storage disagrees '
        'with.'),
    ...para('//',
        'Nothing here validates the key. The controller does not call '
        'Mistral to check that the key works; the first generation '
        'request is the check. That keeps the unlock screen instant, '
        'costs no tokens and needs no extra network path. The price '
        'is that a mistyped key is discovered only after the user '
        'presses Generate, and the unlock screen then explains what '
        'happened.'),
    ...sec('the router'),
    ...para('//',
        'The root widget in lib/app.dart watches this provider and '
        'picks a screen with a conditional: the home screen if '
        'isUnlocked, the unlock screen otherwise. Because the choice '
        'is derived from state, every transition between the two '
        'happens by changing the key and nothing else. Logging in is '
        'setKey. Logging out is forget. A rejected key is forget plus '
        'a message.'),
    plain('   user pastes key  -> KeyEntryScreen._submit -> setKey(...)'),
    plain('   state.key set    -> app.dart rebuilds       -> HomeScreen'),
    plain('   Mistral says 401 -> GenerationController    -> forget()'),
    plain('   state.key null   -> app.dart rebuilds       -> KeyEntryScreen'),
    ...para('//',
        'There is no navigation stack to unwind and no screen can be '
        'reached by a URL while locked, because there are no URLs in '
        'the app. A security-minded reader will notice what this does '
        'and does not do: it controls which interface is shown, and '
        'it is not a defence against a determined user with the '
        'developer tools, who owns the key anyway. The thing being '
        'protected is the key from the repository, from the build and '
        'from other people. It is not a gate against its owner.'),
    ...sec('the rejection channel'),
    ...code('dart', 'lib/providers/api_key_provider.dart · the second provider', r'''
/// Set when Mistral rejects the current key. The unlock screen reads this
/// to show a clear "key was rejected" message.
final keyRejectedMessageProvider = StateProvider<String?>((ref) => null);'''),
    ...para('//',
        'When the model provider answers 401 or 403, the generation '
        'controller does three things in order: it stores the '
        'exception’s message here, calls forget(), and returns. The '
        'forget() flips the app to the unlock screen; the unlock '
        'screen finds a non-null value in this provider and shows a '
        'rose-coloured warning above the input. The unlock screen '
        'clears it again when the user submits a new key.'),
    ...para('//',
        'One more detail: the stored value is the exception’s English '
        'text, Your API key was rejected, but the unlock screen does '
        'not display it. It shows its own localised string from '
        'lib/l10n/strings.dart, in French or English according to the '
        'language preference. So the provider is used as a flag, a '
        'nullable string whose only meaningful property is whether it '
        'is null. A boolean would say the same. This has been true in '
        'every version in the history: the scaffold’s unlock screen '
        'already showed its own localised string. The Gemini client '
        'even took the trouble to extract the provider’s error text '
        'into the exception, and this channel carried it, but nothing '
        'ever displayed it.'),
    ...sec('what it deliberately leaves out'),
    ...pt('//', 'no persistence by default',
        'the key is not in localStorage, not in cookies, not in the '
        'build. The README’s promise is that closing the tab clears '
        'it, and a missing branch in this file is the reason that is '
        'true.'),
    ...pt('//', 'no encryption',
        'the optional stored copy is plain text; see '
        'session_storage.dart for why that is not pretended away.'),
    ...pt('//', 'no timeout',
        'an unlocked app stays unlocked until the tab closes or the '
        'user logs out.'),
    ...pt('//', 'no multi-key',
        'one key at a time, no profiles.'),
    ...sec('history'),
    ...para('//',
        'The logic has not changed since the scaffold commit of '
        '2026-08-06. What changed is the sentence in the last doc '
        'comment: at first it named Cerebras and the status codes 401 '
        'and 403, then Gemini (4 lines changed in ebafa0f), then '
        'Mistral (98e7e48). That is a fair picture of how well the '
        'seam holds: three provider swaps and the key lifecycle never '
        'moved.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
