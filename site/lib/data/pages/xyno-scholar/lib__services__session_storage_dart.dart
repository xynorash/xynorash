import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/services/session_storage.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'session_storage.dart — where the API key may rest, and where it may not'),
    cm('//', '20 lines that draw the line between sessionStorage and localStorage'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'reads, writes and clears the opt-in remembered API key'),
    kv('language', 'Dart, using package:web (browser only)'),
    kv('size', '20 lines, 1 class, 3 static methods'),
    kv('storage', 'window.sessionStorage under the key xyno_scholar_api_key'),
    kv('callers', 'lib/providers/api_key_provider.dart only'),
    kv('tests', 'none'),
    ...sec('the decision this file encodes'),
    ...para('//',
        'The app has no backend, so the user brings their own Mistral '
        'key and types it in. That raises the obvious question of how '
        'long the page may remember it. There are three honest '
        'answers, and the repository’s README states which one it '
        'picked: the key lives only in the browser’s memory for the '
        'current session, optionally mirrored to sessionStorage if '
        'the user opts in, and never in localStorage. Closing the tab '
        'clears it.'),
    ...para('//',
        'This tiny file is where the second tier lives. The first '
        'tier, memory, costs nothing and needs no code: it is a field '
        'in the key controller’s state. The third tier, localStorage, '
        'is the one the project refuses. What remains is this '
        'wrapper, whose own doc comment repeats the rule: used only '
        'for the optional remember-for-this-browser-session toggle, '
        'never for permanent persistence of the API key.'),
    ...sec('the whole file'),
    ...code('dart', 'lib/services/session_storage.dart', r'''
class SessionStorage {
  static const _apiKeyStorageKey = 'xyno_scholar_api_key';

  static void writeApiKey(String key) {
    web.window.sessionStorage.setItem(_apiKeyStorageKey, key);
  }

  static String? readApiKey() {
    return web.window.sessionStorage.getItem(_apiKeyStorageKey);
  }

  static void clearApiKey() {
    web.window.sessionStorage.removeItem(_apiKeyStorageKey);
  }
}'''),
    ...para('//',
        'Three static methods around one constant. There is no state, '
        'no caching and no serialisation: the key is a plain string '
        'stored under a namespaced name. The prefix xyno_scholar_ is '
        'not decoration. A browser’s storage is shared by every page '
        'on the same origin, and an origin is a scheme, a host and a '
        'port, with no path. If the app is served from a GitHub Pages '
        'address for a user, other project sites of the same user are '
        'the same origin, and a distinctive key name at least '
        'prevents two apps from overwriting each other’s entries. The '
        'notebook uses the same convention with its key '
        'xyno_scholar_notebook_v1.'),
    ...sec('why sessionStorage and not localStorage'),
    ...para('//',
        'The difference is lifetime and scope. sessionStorage belongs '
        'to one browser tab: it survives a reload and in-tab '
        'navigation, and it is discarded when the tab or window is '
        'closed. localStorage survives restarts and is shared by '
        'every tab on the origin. For a secret that can spend the '
        'user’s money, the first is the right default: if the opt-in '
        'toggle is on, a reload does not force the user to paste the '
        'key again, and nothing outlives the tab. The unlock screen’s '
        'toggle says exactly that, in its label: remember for this '
        'browser session.'),
    ...para('//',
        'Neither is a vault. Any script running on the page can read '
        'either storage, so the real protection is the set of scripts '
        'that run on the page. The app’s own README is candid about '
        'what is loaded from outside: web fonts from Google’s font '
        'CDN, and by default the CanvasKit renderer from Google’s CDN '
        'too. Those are within the trust boundary whenever the key is '
        'stored. When the toggle is off, the key is in memory only, '
        'which is the same exposure to scripts but no exposure to '
        'storage inspection, to a browser profile on disk or to a '
        'later visitor on the same machine.'),
    ...sec('how the key controller uses it'),
    ...para('//',
        'lib/providers/api_key_provider.dart is the only caller, and '
        'it uses the three methods at the three moments that matter.'),
    ...pt('//', 'build()',
        'on startup, reads the stored key. If one exists and is not '
        'empty, the app starts unlocked with the remembered flag set, '
        'which is how a reload in the same tab skips the unlock '
        'screen.'),
    ...pt('//', 'setKey(key, rememberForSession)',
        'writes the trimmed key if the toggle is on, and clears the '
        'stored key if it is off. The else branch matters: unlocking '
        'a second time with the toggle off removes a previously '
        'remembered key, so turning the option off is a real '
        'revocation and not just a skipped write.'),
    ...pt('//', 'forget()',
        'clears storage and resets the state. The log-out icon in the '
        'app bar calls it, and so does the generation provider when '
        'Mistral rejects the key, which is why a rejected key cannot '
        'silently reappear on the next reload.'),
    ...para('//',
        'Keeping the three operations behind one small class means no '
        'other file in lib/ knows the key’s storage name, and a '
        'change of policy (for instance, removing the opt-in '
        'entirely) is a change to this file and one controller.'),
    ...sec('why a class of static methods'),
    ...para('//',
        'The methods are static, so callers cannot substitute a fake. '
        'A test that wants to run the key controller without a '
        'browser has no seam to inject one. Today that matters less '
        'because there is no test for the controller at all, but it '
        'explains how the pieces are shaped: package:web is confined '
        'to two files, this one and web_download.dart, and everything '
        'else in the app is plain Dart that can be exercised without '
        'a browser. The one exception is that the key controller '
        'calls these statics from build(), so anything that '
        'constructs that controller touches the browser API. The '
        'widget test in test/widget_test.dart pumps the whole app and '
        'therefore reaches this code. I could not confirm from the '
        'repository whether that runs outside a browser; no test '
        'results are recorded.'),
    ...para('//',
        'package:web is the interop layer for browser APIs that the '
        'Dart tooling steers new code towards in place of dart:html. '
        'The pubspec declares it as a direct dependency; the '
        'repository does not discuss the choice.'),
    ...sec('what can go wrong'),
    ...pt('//', 'storage that throws',
        'the methods have no try/catch. Browsers can throw when '
        'storage access is blocked, for example under strict '
        'site-data settings. In that situation the call in build() '
        'would throw during startup. The code does not guard it, and '
        'nothing in the repository says it was tried.'),
    ...pt('//', 'a shared origin',
        'a project site on GitHub Pages shares an origin with the '
        'owner’s other Pages sites. That is a property of how '
        'browsers define origin, not something the repository '
        'mentions, and it is a reason to keep the toggle off on a '
        'machine that is not one’s own.'),
    ...pt('//', 'the key sits in clear text',
        'stored as typed. There is no obfuscation, which would only '
        'be theatre against a script that can read the same storage.'),
    ...pt('//', 'no expiry',
        'the key stays until the tab closes or the user logs out. '
        'There is no inactivity timeout.'),
    ...sec('history and tests'),
    ...para('//',
        'The file has one commit: the scaffold, 7a200e7. The provider '
        'that calls it changed only in a doc comment when the '
        'provider moved from Cerebras to Gemini and then Mistral; the '
        'storage logic is as it was on the first day. No test '
        'exercises the file. The class is simple enough that a test '
        'would mostly check the browser, but a small browser-side '
        'test would pin the one property the README promises: after '
        'logging out, the stored value is gone.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
