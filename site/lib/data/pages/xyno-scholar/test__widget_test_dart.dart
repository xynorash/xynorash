import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/test/widget_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'widget_test.dart — one smoke test for the locked app'),
    cm('//', 'a fresh visitor must land on the unlock screen, in French'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'the repository’s only widget test: first-run smoke test'),
    kv('language', 'Dart, flutter_test'),
    kv('size', '13 lines, 1 test'),
    kv('history', '3 commits: created in 7a200e7, then one-word edits in ebafa0f and 98e7e48'),
    kv('covers', 'lib/app.dart, the locked branch; transitively the unlock screen'),
    ...sec('what it asserts'),
    ...para('//',
        'The file is the standard Flutter smoke test, trimmed to '
        'the one fact that matters for this app: with no stored '
        'key, the first thing a visitor sees is the screen that '
        'asks for one. There is no counter to tap and no default '
        'scaffold left over.'),
    ...code('dart', 'test/widget_test.dart · the test', r'''
  testWidgets('Shows the API key unlock screen on first run', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: XynoScholarApp()));
    await tester.pumpAndSettle();

    expect(find.text('Entrez votre clé API Mistral'), findsOneWidget);
  });'''),
    ...para('//',
        'Three steps. pumpWidget builds the real root widget inside '
        'a fresh ProviderScope, exactly as lib/main.dart does. '
        'pumpAndSettle keeps advancing frames until none are '
        'pending, which lets the first build and any initial '
        'animation finish. Then the assertion looks for one Text '
        'widget with an exact string. findsOneWidget fails on zero '
        'and on two, so a duplicated title would also be caught.'),
    ...sec('everything that must be true for it to pass'),
    ...para('//',
        'A one-line assertion rests on a chain of facts spread over '
        'five files. Reading the chain is the quickest way to see '
        'how the app is wired, and it shows how many things this '
        'test quietly pins.'),
    ...pt('//', 'no key at start-up',
        'the key controller reads sessionStorage in its build '
        'method. In a fresh browser profile it is empty, so the '
        'state is the default one and isUnlocked is false. '
        'lib/app.dart therefore chooses the unlock screen.'),
    ...pt('//', 'French is the default language',
        'the preference block starts with language set to fr, '
        'which is why the test searches for French text.'),
    ...pt('//', 'the string table maps to that title',
        'AppStrings builds the unlock title from the language.'),
    ...code('dart', 'lib/models/preference_block.dart · the default language', r'''
    language: 'fr',
  );'''),
    ...code('dart', 'lib/l10n/strings.dart · the title the test looks for', r'''
  String get unlockTitle =>
      _fr ? 'Entrez votre clé API Mistral' : 'Enter your Mistral API key';'''),
    ...para('//',
        'So the test is also an implicit check that the app opens '
        'in French. If someone changed the default language to en, '
        'this test would fail even though the app would be '
        'working as intended, and the failure message would point '
        'at the title and not at the language. That is the price '
        'of asserting on user-visible copy.'),
    ...sec('a test edited twice for the same reason'),
    ...para('//',
        'The history is short and instructive. The file was born in '
        'the scaffold commit 7a200e7 asserting the title '
        'Entrez votre clé API Cerebras. When the provider changed '
        'to Gemini (ebafa0f), the diff for this file was a single '
        'line replacing the word Cerebras with Gemini. When it '
        'changed to Mistral (98e7e48), the diff was again a single '
        'line. Nothing else in the file has ever changed.'),
    ...para('//',
        'That pattern is a trade-off made visible. A literal in '
        'the assertion pins the real copy, so a typo or a lost '
        'translation would be caught, but it makes the test '
        'brittle against deliberate copy changes, and both vendor '
        'swaps broke it in exactly that way. There are '
        'two cheaper alternatives, and the choice between them is '
        'a matter of taste:'),
    ...pt('//', 'compute the expected text',
        'build the string from AppStrings with the French language '
        'and compare. It survives wording changes and still '
        'fails if the wrong screen appears, but it no longer '
        'checks the copy itself.'),
    ...pt('//', 'find the screen by type',
        'ask for the KeyEntryScreen widget. It is the most '
        'robust against text edits and states the intent most '
        'directly: the routing, not the wording, is under test.'),
    ...sec('what it does not cover'),
    ...para('//',
        'There is exactly one widget test in the repository. The '
        'following behaviours of the root widget and its screens '
        'are not exercised by any test:'),
    ...bullet('unlocking',
        'typing a key and pressing Continue, and the app switching '
        'to the workbench.'),
    ...bullet('the rejection path',
        'the unlock screen showing the “key rejected” banner after '
        'a failed request.'),
    ...bullet('forgetting',
        'the app-bar button taking the visitor back to the lock '
        'screen.'),
    ...bullet('the language toggle',
        'switching between French and English.'),
    ...bullet('the workbench itself',
        'the sidebar, the output panel and the notebook drawer '
        'are never built in any test.'),
    ...sec('the environment question'),
    ...para('//',
        'This test imports lib/app.dart, which imports the unlock '
        'screen and the key provider, which imports the '
        'sessionStorage wrapper:'),
    ...code('dart', 'lib/services/session_storage.dart · the browser import', r'''
import 'package:web/web.dart' as web;'''),
    ...para('//',
        'That package is built on dart:js_interop, which exists '
        'only on web compilers. In a scratch experiment with a '
        'standalone Dart SDK, a script that imports '
        'dart:js_interop fails on the VM with “is not available on '
        'this platform”. If the same rule applies to the Flutter '
        'test runner, this file would need to be run in a browser '
        'with flutter test --platform chrome, and a plain flutter '
        'test would fail to compile it. I could not run Flutter '
        'here, so this is unconfirmed. The repository records '
        'nothing about how the tests are run: the README has no '
        'testing section, and the deploy workflow never runs them.'),
    ...para('//',
        'The other two test files are in a different position. '
        'test/mistral_client_test.dart reaches only the models, the '
        'client and the sanitiser, and test/sanitize_test.dart '
        'reaches only html_unescape. By the import graph neither '
        'touches package:web, so they are plain-Dart tests. That '
        'split is a quiet payoff of keeping every browser call '
        'inside two small files, session_storage.dart and '
        'web_download.dart.'),
    ...para('//',
        'A second, smaller risk is fonts. The theme builds its '
        'text styles through google_fonts, which fetches font '
        'files over the network at run time, and the test does not '
        'configure that package. A search finds no use of its '
        'runtime-fetching switch anywhere in lib/ or test/. How '
        'google_fonts behaves under the test runner was not '
        'checked.'),
    ...sec('limits and what is next'),
    ...pt('//', 'single branch',
        'a second test that overrides the key provider with a '
        'non-empty key would cover the workbench branch of '
        'lib/app.dart.'),
    ...pt('//', 'not in CI',
        '.github/workflows/deploy.yml runs pub get and the build. '
        'A test step before the build, with the deploy job '
        'depending on it, would turn this smoke test into a gate.'),
    ...pt('//', 'brittle to copy',
        'see above; one of the two alternatives would end the '
        'string churn.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
