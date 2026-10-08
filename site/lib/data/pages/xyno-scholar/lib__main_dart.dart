import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/main.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'main.dart — the entry point, in three lines of body'),
    cm('//', 'everything else in the app is reached through one ProviderScope'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'program entry: creates the Riverpod container and starts the widget tree'),
    kv('language', 'Dart / Flutter Web'),
    kv('size', '7 lines, 1 function'),
    kv('history', 'one commit (7a200e7, the scaffold); never edited since'),
    kv('reads', 'nothing: no I/O happens before the first frame is requested'),
    ...sec('why a file this small deserves a page'),
    ...para('//',
        'Entry points are where a project shows how it thinks about '
        'start-up. Some apps put dependency wiring, error hooks, '
        'storage initialisation and a splash screen here, and the '
        'file grows to fifty lines. This one does the opposite: the '
        'whole of main.dart is a function whose body is one '
        'statement. That is only possible because the rest of the '
        'program was arranged so that nothing has to happen before '
        'the first frame. The interesting question is therefore '
        'not what the file does but what it is able to leave out.'),
    ...code('dart', 'lib/main.dart · the whole function', r'''
void main() {
  runApp(const ProviderScope(child: XynoScholarApp()));
}'''),
    ...para('//',
        'Two constructors are nested. XynoScholarApp, described in '
        'lib/app.dart, is the root widget. ProviderScope comes from '
        'flutter_riverpod and is the object that owns every piece '
        'of state in the program: the API key, the preference '
        'block, the generation result, the notebook. A provider '
        'declared at file level in lib/providers/ is only a recipe; '
        'the scope is what stores the value the recipe produces, '
        'and it creates each value lazily, on first read.'),
    ...sec('why the scope is created here and not as a global'),
    ...para('//',
        'Riverpod providers are top-level final variables, which '
        'looks like global state. The scope is what keeps them from '
        'being global in the harmful sense: values live in the '
        'container, not in the variable. The consequence is visible '
        'in test/widget_test.dart, which pumps its own '
        'ProviderScope around the same root widget. Each test gets '
        'a fresh container and therefore a fresh, locked app, with '
        'no leftover key from a previous run. The two scope '
        'expressions are character for character the same apart '
        'from the surrounding call; the smoke test is main.dart '
        'without the binding.'),
    ...code('dart', 'test/widget_test.dart · the same two constructors', r'''
    await tester.pumpWidget(const ProviderScope(child: XynoScholarApp()));'''),
    ...sec('what is missing, and why that is safe'),
    ...para('//',
        'A search of lib/ and test/ for the usual start-up '
        'ceremony comes back empty, and each absence has a reason '
        'that can be traced to another file.'),
    ...pt('//', 'no binding initialisation',
        'there is no call to WidgetsFlutterBinding.ensureInitialized. '
        'That call is only required when something asynchronous '
        'touches a platform channel before runApp. Here nothing '
        'does, and runApp prepares the binding itself.'),
    ...pt('//', 'no async main',
        'the function is synchronous. The notebook is stored with '
        'shared_preferences, which is asynchronous, but it is '
        'loaded by an AsyncNotifier on first use, so the UI shows a '
        'loading state instead of main waiting for it.'),
    ...pt('//', 'no error hooks',
        'there is no FlutterError.onError override and no '
        'runZonedGuarded wrapper. Uncaught exceptions go to the '
        'browser console, which is what the framework does by '
        'default.'),
    ...pt('//', 'no URL strategy',
        'no call selects path-based URLs, so the app keeps the '
        'default hash-based routing. It has a single route, so '
        'there is nothing to deep-link to.'),
    ...pt('//', 'no provider overrides',
        'production uses the real MistralClient. The test seam is '
        'the client’s constructor argument and not a scope '
        'override; see test/mistral_client_test.dart.'),
    ...sec('why main can be synchronous: the one start-up read'),
    ...para('//',
        'The only state that must exist before the first screen is '
        'chosen is the API key, because the root widget needs it to '
        'decide between the unlock screen and the workbench. It is '
        'kept in the browser’s sessionStorage when the user opts '
        'in, and that API is synchronous. The key controller reads '
        'it inside its build method.'),
    ...code('dart', 'lib/providers/api_key_provider.dart · the start-up read', r'''
  @override
  ApiKeyState build() {
    final remembered = SessionStorage.readApiKey();
    if (remembered != null && remembered.isNotEmpty) {
      return ApiKeyState(key: remembered, rememberedForSession: true);
    }
    return const ApiKeyState();
  }'''),
    ...para('//',
        'This is the reason the start-up path has no await in it. '
        'Had the key lived in an asynchronous store, the root widget '
        'would need a loading branch, or main would need to read it '
        'first and hand it to the scope as an override. Choosing '
        'sessionStorage for the opt-in convenience (and never '
        'localStorage, as the README states) bought a start-up '
        'sequence with no moving parts as a side effect.'),
    ...sec('the boot sequence, end to end'),
    ...para('//',
        'main.dart is the middle of a chain that starts in HTML and '
        'ends in a decision about which screen to show:'),
    ...pt('//', '1. the page',
        'web/index.html contains a base tag whose href is a '
        'placeholder and one script tag that loads '
        'flutter_bootstrap.js asynchronously.'),
    ...pt('//', '2. the base path',
        'the placeholder is replaced at build time. The deploy '
        'workflow passes the repository name so the static files '
        'resolve under the GitHub Pages subpath.'),
    ...pt('//', '3. main()',
        'the bootstrap script starts the engine and calls the '
        'function above.'),
    ...pt('//', '4. the first build',
        'XynoScholarApp.build watches the key provider, which '
        'constructs the controller, which runs the sessionStorage '
        'read. A fresh tab has nothing stored, so the unlock '
        'screen is shown.'),
    ...code('bash', '.github/workflows/deploy.yml · the build step', r'''
      - name: Build web
        run: flutter build web --release --base-href "/xyno-scholar/"'''),
    ...para('//',
        'Step 2 matters for a reason that has nothing to do with '
        'Dart: if the base href were wrong, flutter_bootstrap.js '
        'and the assets would 404 and main would never run. The '
        'tiny entry point depends on a correct deployment more than '
        'on any code in the file.'),
    ...sec('what this file has lived through'),
    ...para('//',
        'main.dart was created in the scaffold commit 7a200e7 at '
        '09:41 UTC on 2026-08-06. The following eight commits that '
        'day moved the AI integration from Cerebras to Gemini and '
        'then to Mistral behind a Cloudflare Worker, added a '
        'deployment workflow, swapped the icon package and '
        'reworked the unlock screen. None of them touched this file. '
        'git log --follow lists exactly one commit for it. That is '
        'the strongest evidence that the layering works: the vendor '
        'is hidden behind lib/services/mistral_client.dart and the '
        'providers in lib/providers/, so a change of vendor never '
        'reaches the root of the tree.'),
    ...sec('limits and what is next'),
    ...pt('//', 'no failure screen',
        'if building the first frame throws, the visitor sees a '
        'blank page and the console has the stack trace. A small '
        'error widget set through the framework’s error builder '
        'would be the cheapest improvement.'),
    ...pt('//', 'storage access is unguarded',
        'session_storage.dart calls the browser API directly with '
        'no try block. A browser that refuses storage access could '
        'make the key controller’s build throw. I have not '
        'reproduced this, so treat it as a risk and not a '
        'known bug.'),
    ...pt('//', 'nothing measured',
        'there is no start-up timing in the repository. How long '
        'the engine and the web fonts take to arrive is dominated by '
        'the Flutter bootstrap and the Google font CDN, not by this '
        'file.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
