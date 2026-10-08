import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/README.md',
  summary: 'AI research-topic explorer, client-side only',
  repo: 'xyno-scholar',
  fallbackStars: 0,
  fallbackPushed: '2026-08-06',
  lines: [
    heading('# Xyno Scholar'),
    blank,
    ...text('A research-topic explorer for students in the humanities. '
        'You choose the academic fields a project must live in, '
        'such as History, Catholic Theology and Art History, plus a '
        'level, a tone and a mood, and the app asks a language '
        'model for subjects that genuinely sit at the intersection '
        'of all of them. A broad request returns five to eight '
        'candidate topics. A deep dive turns one into a narrow '
        'topic with a problem statement, a starter bibliography of '
        'three sources, a three-part outline, and a refine loop. '
        'Good topics can be saved to a notebook and exported as '
        'BibTeX. It is a Flutter web app with no backend of its '
        'own: you paste your own Mistral key, and the only server '
        'in the picture is a 44-line Cloudflare Worker that adds '
        'the CORS headers Mistral does not send.'),
    blank,
    kv('language', 'Dart / Flutter Web (UI) · JavaScript (relay Worker)'),
    kv('shape', 'static site on GitHub Pages + one stateless relay'),
    kv('model', 'mistral-large-latest, JSON mode, bring your own key'),
    kv('history', '10 commits, one day: 2026-08-06, 09:41 to 12:54 UTC'),
    kv('code', '46 Dart files, 4,280 lines in lib/; 44 lines of JS'),
    kv('tests', '10 test cases in 3 files, not run by CI'),
    kv('languages', 'French and English UI, French by default'),
    kv('status', 'deployed; relay URL wired in b3d2b1c'),

    ...sec('the problem, and why it is more interesting than it looks'),
    ...text('Asking a model for “a research topic” is easy and '
        'produces generic answers. Asking for topics that engage '
        'every one of several selected disciplines, with no field '
        'dropped and none invented, is a constraint-satisfaction '
        'problem that a model will quietly relax. The prompt that '
        'this project sends is built around refusing that '
        'relaxation. Two of its nine numbered rules address it '
        'directly, and a third addresses citations.'),
    ...code('bash', 'lib/services/mistral_client.dart · the field rules (trimmed)', r'''
1. Never drop a selected field. The user has selected exactly these fields: [$fieldsList].
2. Never add a field the user did not select, and never assume one field implies another
6. Every subject must name REAL, VERIFIABLE events, works, people, or documents.'''),
    ...text('Rule 3, not shown, handles the case where the visitor’s '
        'free text points at a field that is not selected: the '
        'model must ask exactly one short clarifying question and '
        'still return usable topics. The app does not rely on the '
        'model for that detection alone. lib/services/'
        'field_detection.dart is a plain-Dart keyword scan, 50 '
        'accent-stripped French and English trigger words that map '
        'to seven fields, whose file comment says it never assumes '
        'silently: the result is a dismissible suggestion chip, '
        'not an automatic change to the selection.'),
    ...text('The second problem is trust. A model told to cite real '
        'sources will sometimes cite fake ones, and the app has no '
        'way to check. What it does is make checking one click: '
        'every bibliography entry carries search links to Google '
        'Scholar, JSTOR and WorldCat, built from the entry in '
        'lib/widgets/output/tabs/bibliography_tab.dart. The prompt '
        'forbids fabrication; the interface assumes it can '
        'happen.'),
    ...text('The third problem is the architecture. There is no '
        'server to hold a secret, which is a choice, so the key '
        'must live in the visitor’s browser, and the browser '
        'must reach an API that was not designed to be called from '
        'one. Everything else in the project follows from that '
        'pair of constraints.'),

    ...sec('how a request travels'),
    plain('  browser  (Flutter web, static files on GitHub Pages)'),
    plain('     |  POST  Authorization: Bearer <your key>'),
    plain('     |        { model, messages, response_format: json_object }'),
    plain('     v'),
    plain('  Cloudflare Worker  xyno-scholar-relay   (no state, no log)'),
    plain('     |  answers OPTIONS itself, forwards POST, adds CORS headers'),
    plain('     v'),
    plain('  api.mistral.ai/v1/chat/completions'),
    plain('     |  status and body returned unchanged'),
    plain('     v'),
    plain('  browser: strip fences -> jsonDecode -> decode entities'),
    plain('           -> typed models -> providers -> widgets'),
    blank,
    ...text('The relay exists because, per the README, Mistral’s '
        'endpoint does not reliably answer the browser’s CORS '
        'preflight for a JSON POST with an Authorization header. '
        'That claim is the author’s; the repository contains no '
        'captured failure of a direct call. What it does contain is '
        'a verification of the fix, recorded in the commit '
        'message of b3d2b1c: a real preflight returned 204 with '
        'CORS headers, and a POST with a bad key returned Mistral’s '
        '401 with those headers intact.'),
    ...code('js', 'worker/src/index.js · the forwarding core', r'''
    const authHeader = request.headers.get("Authorization") || "";
    const body = await request.text();

    const upstreamResponse = await fetch(MISTRAL_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": authHeader,
      },
      body,
    });'''),
    ...text('The body is never parsed, only two headers are set on '
        'the upstream call, and the response status is copied '
        'back, which matters because the app’s key handling '
        'depends on a 401 or 403 arriving unchanged.'),

    ...sec('the design decisions that carry the project'),
    ...bullet('the key never leaves the browser except in a request',
        'it lives in Riverpod state and, only if the visitor ticks '
        'a box, in sessionStorage, never localStorage. The README '
        'states this in a quoted promise, and '
        'lib/services/session_storage.dart is the 20 lines that '
        'implement it.'),
    ...bullet('the screen is a function of the key',
        'lib/app.dart shows the workbench or the unlock screen '
        'from one ternary on the key state. A rejected key '
        'forgets itself and the app falls back to the lock '
        'screen with no navigation code.'),
    ...bullet('treat the model as an unreliable parser input',
        'JSON mode guarantees syntax, not shape, so the schema is '
        'also spelled out in the prompt, fences are stripped, '
        'HTML entities in any string are decoded, and a failed '
        'parse gets exactly one retry with the bad answer shown '
        'back to the model.'),
    ...bullet('tolerant models',
        'fromJson methods default missing fields to empty values, '
        'so a reply with gaps yields empty sections and not an '
        'exception. Wrong types, such as a list element that is '
        'not a map, still throw.'),
    ...bullet('two error types, one choreography',
        'the client throws ApiKeyRejectedException or a '
        'provider-named API exception, and the generation '
        'controller maps them to state. The first type stayed '
        'through every swap; the second was renamed with each '
        'provider.'),
    ...bullet('deterministic where possible',
        'field suggestions, BibTeX export, and the unlock gate '
        'involve no model call, so they are instant. Only the '
        'gate has a test.'),
    ...bullet('lightweight i18n',
        'a 116-line AppStrings class keyed on a language field, '
        'chosen over the intl tooling, as its own doc comment '
        'says, because there are exactly two languages and one '
        'user.'),
    ...bullet('browser code confined to two files',
        'session_storage.dart and web_download.dart are the only '
        'files that import package:web. The rest of lib/ does not '
        'touch browser APIs, so the models, the client and the '
        'sanitiser run on the plain Dart VM.'),

    ...sec('what the client does with one reply'),
    ...text('The path from raw text to a screen is short enough to '
        'state in full. Each step is a place a model can fail, and '
        'each has an answer in lib/services/mistral_client.dart.'),
    ...bullet('1. build', 'a system prompt with nine numbered rules and '
        'the JSON schema, plus a user turn that is a JSON payload '
        'of preferences, optional free text, an optional deep-dive '
        'title and an instruction. Broad scope asks for five to '
        'eight topics. Narrow scope asks for one topic with exactly '
        'three sources and three parts.'),
    ...bullet('2. send', 'one POST to the relay with model, messages '
        'and response_format. No temperature, top-p or token limit '
        'is set now; the Cerebras and Gemini clients both sent '
        'temperature 1, top-p 0.95 and a 65,000-token cap.'),
    ...bullet('3. classify the status', '401 or 403 means the key was '
        'rejected; any other non-200, or a thrown network error, '
        'becomes a MistralApiException whose message is always safe '
        'to show and never contains the key.'),
    ...bullet('4. extract', 'choices, first message, content string; an '
        'empty choices list or empty content is its own error.'),
    ...bullet('5. clean and parse', 'strip a Markdown fence if present, '
        'jsonDecode, decode entities, cast to a typed map.'),
    ...bullet('6. retry once', 'if step 5 fails, resend the conversation '
        'with the bad answer and a corrective user message, then give '
        'up with “did not return valid JSON, even after a retry”.'),
    ...bullet('7. model', 'GenerationResponse.fromJson builds the typed '
        'result, and the providers publish it to the UI.'),

    ...sec('one day, ten commits'),
    ...text('The whole history fits in an afternoon, which makes it '
        'unusually legible. All times are UTC on 2026-08-06, from '
        'git log.'),
    ...bullet('09:41, 7a200e7 · scaffold',
        'the whole app in one commit: Riverpod providers, '
        'preference panels, free-text field detection, broad and '
        'narrow views, refine flow, BibTeX export, notebook drawer, '
        'a warm parchment theme in Fraunces, Inter and JetBrains '
        'Mono. The first provider is Cerebras, called directly '
        'from the browser. A pull request merge at 09:50 (3ec44db) '
        'brings it to the main line.'),
    ...bullet('09:50, cb25af9 · deploy workflow',
        'GitHub Actions builds the web app and publishes build/web '
        'to Pages with a repository-specific base href.'),
    ...bullet('09:58, 89a9c12 · the first CI failure',
        'the pinned lucide_icons package subclassed IconData, which '
        'is final in newer Flutter, so flutter build web failed on '
        'stable 3.44.8. It was replaced by lucide_icons_flutter, '
        'touching 16 Dart files and the pubspec. The deploy '
        'workflow had existed for eight minutes.'),
    ...bullet('10:28, c1b3d71 · Cerebras, streaming, and a bug',
        'model zai-glm-4.7 with server-sent-event streaming and a '
        'live character counter. The mocked streaming tests exposed '
        'that every valid reply was being rejected, because the '
        'sanitiser returned a Map<dynamic, dynamic>. Fixed in the '
        'same commit, which also created the first client and '
        'sanitiser tests.'),
    ...bullet('10:52, ebafa0f · Gemini',
        'a full provider swap to gemini-3.6-flash with native '
        'structured output, so the count limits became part of a '
        'response schema. Streaming code removed entirely. A merge '
        'of the same work (c52baa9) followed at 10:56.'),
    ...bullet('12:19, 98e7e48 · Mistral and the relay',
        'the swap that created worker/. JSON mode replaced the '
        'schema, the unlock screen was made scrollable after an '
        'overflow, and the Gemini 400 key tests gave way to a 401 '
        'test. It came after a gap of about 82 minutes.'),
    ...bullet('12:54, b3d2b1c · deployed',
        'the Worker went live on a workers.dev address and the '
        'client placeholder was replaced with the real URL, after '
        'a preflight and an invalid-key POST were checked by hand.'),
    ...text('Eight of the ten commits have Claude as git author, '
        'and the two pull-request merges are by the repository '
        'owner. The pressure that decided each swap is not '
        'recorded beyond the commit messages: the history does '
        'not say why either earlier provider was dropped.'),

    ...sec('three providers in three hours, and what did not move'),
    ...text('Cerebras, Gemini and Mistral differ in endpoint, '
        'authentication header, request body, response shape, '
        'streaming and error format. A project that leaked any of '
        'that would have needed rewrites across the tree. This '
        'one needed a rewrite of one service file each time, plus '
        'mechanical edits to the provider, the copy, the unlock '
        'screen and the tests. Among the files that never changed '
        'after the scaffold are lib/main.dart, lib/app.dart and '
        'analysis_options.yaml, each with exactly one commit. The '
        'unlock screen did change, because the key it asks for is '
        'vendor-specific, and the widget test changed one word '
        'per swap.'),
    ...text('What each swap cost is visible in the test file: '
        '237 lines for Cerebras, 364 for Gemini, 312 for Mistral, '
        'and in the shared skeleton of cases that outlived all '
        'three, described on the page for test/'
        'mistral_client_test.dart.'),

    ...sec('a tour of the tree'),
    ...bullet('lib/main.dart, lib/app.dart',
        '31 lines between them. main creates the Riverpod scope; '
        'app picks the screen from the key state.'),
    ...bullet('lib/services/',
        '6 files, 506 lines. The mistral_client (279 lines) is '
        'the heart. Also sanitize, field_detection, bibtex_export, '
        'and the two browser-facing files. No widget code here.'),
    ...bullet('lib/providers/',
        '4 files, 326 lines. Riverpod notifiers for the key, '
        'the preference block, generation and the notebook.'),
    ...bullet('lib/models/',
        '9 files, 636 lines. Plain data classes with fromJson, '
        'four enums with API values and French and English labels, '
        'and a field catalog of 22 disciplines in 5 categories.'),
    ...bullet('lib/screens/',
        '2 files, 359 lines. The unlock screen and the workbench '
        'with its single 900-pixel breakpoint.'),
    ...bullet('lib/widgets/',
        '19 files, 1,941 lines, 45 percent of the code. Sidebar '
        'cards, the output panel with four tabs, the notebook '
        'drawer, the BibTeX dialog and a Markdown renderer.'),
    ...bullet('lib/theme/ and lib/l10n/',
        '3 files, 365 lines of colours, typography and theme; '
        '1 file, 116 lines of bilingual strings.'),
    ...bullet('test/',
        '3 files, 351 lines. Client behaviour with a mock HTTP '
        'client, the sanitiser regression, and a locked-screen '
        'smoke test.'),
    ...bullet('worker/',
        'src/index.js (44 lines), wrangler.toml (3 lines) and its '
        'own README (72 lines). Separate because it deploys to a '
        'different platform with a different tool and shares no '
        'code with the app.'),
    ...bullet('web/',
        'the HTML shell, manifest and icons. Still the generator’s '
        'defaults in content: title xyno_scholar, description “A '
        'new Flutter project.”.'),
    ...bullet('.github/workflows/deploy.yml',
        '49 lines: build with a base href, upload, deploy to Pages.'),
    ...bullet('pubspec.yaml, pubspec.lock, analysis_options.yaml',
        '12 runtime packages, one lint package, no code '
        'generation. The lock file pins exact versions.'),

    ...sec('build and run'),
    ...code('bash', 'README.md · development', r'''
flutter pub get
flutter run -d chrome'''),
    ...code('bash', 'README.md · release', r'''
flutter build web --release'''),
    ...text('The requirement is Flutter stable 3.35 or newer with web '
        'enabled and a key from console.mistral.ai. The key is '
        'not a build input: it is typed into the app at run time. '
        'Output goes to build/web as static files. The deploy '
        'workflow adds a base href for the repository path. The '
        'relay is deployed separately with wrangler from the '
        'worker directory, using a Cloudflare token scoped to '
        'editing Worker scripts, as worker/README.md describes. '
        'The README also sketches a Netlify route; no Netlify '
        'configuration exists in the repository, so only the '
        'Pages route is automated.'),

    ...sec('how it is tested'),
    ...text('Ten test cases: eight on the client (broad and narrow '
        'parsing, refine, fence stripping, one retry, retry '
        'exhausted, 401 and 403), one on the sanitiser, one '
        'smoke test of the locked screen. Nothing runs them '
        'automatically: the deploy workflow does pub get and the '
        'build only, and the README has no testing section.'),
    ...text('I ran the nine plain-Dart tests in a scratch copy and '
        'they pass. I then made 21 small deliberate changes to the client '
        'to see what the suite notices. Seven were caught: the '
        'model name, the response format, the bearer scheme, the '
        '403 mapping, fence stripping, the retry, and the '
        'sanitiser bug. Fourteen were not, among them the relay '
        'URL, treating every HTTP error as a rejected key, the '
        'whole system prompt and the content of the user turn. '
        'The probes were chosen to find gaps, so this is a map '
        'and not a score. The suite protects the '
        'transport and parsing contract and leaves the prompt '
        'unprotected, which is the part most likely to change.'),

    ...sec('key numbers'),
    ...bullet('3 h 13 min', 'from the first scaffold commit to the '
        'deployed relay.'),
    ...bullet('3 providers, 1 retry, 2 error types',
        'the client’s moving parts.'),
    ...bullet('9 rules, 5 to 8 topics, 3 sources, 3 parts',
        'the prompt’s contract with the model.'),
    ...bullet('5 levels, 3 tones, 2 scopes, 4 moods',
        'the preference space, on top of 22 selectable fields.'),
    ...bullet('50 keywords, 7 fields',
        'the client-side implication detector.'),
    ...bullet('46 files, 4,280 lines', 'in lib/; 19 widget files hold '
        '1,941 of them.'),
    ...bullet('0 backends, 1 relay of 44 lines', 'the whole server side.'),

    ...sec('honest limits'),
    ...bullet('the sources are the model’s',
        'nothing verifies a citation. Search links make checking '
        'easy; they do not check.'),
    ...bullet('the counts are only in the prompt',
        'five to eight topics and exactly three sources are not '
        'validated on arrival. The test fixtures themselves '
        'return an empty broad list and the client accepts it.'),
    ...bullet('the relay is open',
        'its CORS header allows any origin and the code has no '
        'origin check or rate limit. A caller still needs a '
        'valid Mistral key, so it is not a free proxy to a paid '
        'account, but it is not locked to this site either.'),
    ...bullet('statelessness is a claim about source code',
        'the Worker as written holds no state and logs nothing. '
        'The repository cannot prove the deployed script is this '
        'one, and the key does transit the relay and Cloudflare '
        'on every request.'),
    ...bullet('state survives the lock',
        'forgetting the key does not clear the last result or the '
        'notebook, which sits in the browser’s persistent '
        'storage through shared_preferences.'),
    ...bullet('no timeout, no cancel, no streaming',
        'a generation is one request with a spinner. No latency '
        'figure is recorded anywhere in the repository.'),
    ...bullet('hard-wired relay address',
        'the Worker URL is a constant in the client, so a fork '
        'must redeploy a relay and edit the source.'),
    ...bullet('generator leftovers',
        'web metadata with default text, an unused '
        'cupertino_icons dependency, and a README deployment '
        'section that is broader than what is automated.'),
    ...bullet('one language mechanism',
        'strings come from AppStrings; MaterialApp has no locale, '
        'so Material’s own labels are probably not localised.'),

    ...sec('what is next'),
    ...text('The cheapest improvements are in the open: run the '
        'analyzer and the tests in the workflow before building, '
        'pin the request body and the relay URL in the client '
        'test, port back the negative test that a plain HTTP '
        'error is not a rejected key, validate the topic counts '
        'or accept them as advisory, and clear generated state '
        'on forget. Larger ideas follow from the same '
        'constraint that shaped everything else: keep the '
        'server side as close to nothing as it is now.'),

    ...sec('where to read next'),
    ...bullet('lib/services/mistral_client.dart',
        'the prompt, the request and the retry, the file most '
        'worth reading.'),
    ...bullet('lib/services/sanitize.dart and test/sanitize_test.dart',
        'the bug that looked like a flaky model.'),
    ...bullet('worker/src/index.js',
        'the whole relay, in 44 lines.'),
    ...bullet('lib/app.dart',
        'the key-driven screen switch.'),
    ...bullet('lib/providers/generation_provider.dart',
        'where errors become state.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
