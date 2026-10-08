import '../../models/project.dart';
import '../authoring.dart';

final Buffer xynoScholarBuffer = Buffer(
  id: 'xyno-scholar',
  fileName: 'xyno_scholar.dart',
  icon: '\u{e798}',
  filetype: 'dart',
  repo: 'xyno-scholar',
  summary: 'AI research-topic explorer · client-side only',
  fallbackStars: 0,
  fallbackPushed: '2026-08-06',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'xyno-scholar — research-topic discovery for scholars'),
    cm('//', 'Flutter web · pure client-side · no backend'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('purpose', 'refine interdisciplinary research topics'),
    kv('fields', 'History · Theology · Art History — user-editable'),
    kv('model', 'mistral-large-latest, JSON mode'),
    kv('constraint', 'no server, no stored secrets'),

    ...sec('the problem'),
    ...para('//',
        'Choosing a research topic is a search problem with a '
        'catch: the interesting subjects sit at the intersection '
        'of fields — say history, theology and art history — and '
        'a naive assistant will happily drift toward whichever '
        'field is easiest and quietly drop the others. A student '
        'also needs different things depending on level: a '
        'bounded corpus for a licence, a precise problématique '
        'for a mémoire, original archival work for a PhD.'),
    blank,
    ...para('//',
        'So the app is less “ask a chatbot” and more “constrain '
        'a model tightly, then make its output structured enough '
        'to use”: it returns topics, a research question, an '
        'outline and a starter bibliography as data, which the UI '
        'turns into tabs, a notebook and a BibTeX export.'),

    ...sec('the hard constraint: no backend'),
    ...para('//',
        'It is a single-user tool, so running a server means '
        'paying for, securing and maintaining infrastructure that '
        'protects nothing worth protecting. The app is static '
        'files; the user brings their own Mistral key. That '
        'decision makes two problems appear, and the rest of the '
        'architecture is the answer to them.'),
    blank,
    ...pt('//', 'problem 1 — CORS',
        'Mistral’s chat endpoint does not reliably answer the '
        'browser’s preflight request for a JSON POST with an '
        'Authorization header, so a direct fetch fails before '
        'reaching Mistral.'),
    ...pt('//', 'problem 2 — the key',
        'a key typed into a web page must not end up in a build, '
        'a repo or long-lived storage.'),

    ...sec('the relay: the smallest server that works'),
    ...para('//',
        'The CORS problem is solved with a Cloudflare Worker, and '
        'the interesting property is how little it does. It adds '
        'the permissive headers a browser needs, answers the '
        'preflight itself, and otherwise forwards the request '
        'byte-for-byte:'),
    ...code('js', 'worker/src/index.js (trimmed)', r'''
export default {
  async fetch(request) {
    if (request.method === "OPTIONS") {
      return new Response(null,
        { status: 204, headers: CORS_HEADERS });
    }
    if (request.method !== "POST") {
      return new Response("Method not allowed",
        { status: 405, headers: CORS_HEADERS });
    }

    const authHeader = request.headers.get("Authorization") || "";
    const body = await request.text();

    const upstreamResponse = await fetch(MISTRAL_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json",
                 "Authorization": authHeader },
      body,
    });
    // ... return body + CORS headers, same status
  },
};'''),
    ...para('//',
        'There are no environment variables, no secrets and no '
        'storage. The Authorization header arrives with the '
        'request and leaves with the same request; the Worker '
        'cannot leak what it never keeps. That is a stronger '
        'privacy statement than any policy: the relay is '
        'stateless by construction, and short enough to read in '
        'one screen. It stores nothing and logs nothing — the '
        'whole behaviour is the forty lines above.'),

    ...sec('the key never touches disk'),
    ...code('dart', 'lib/providers/api_key_provider.dart (trimmed)', r'''
void setKey(String key, {required bool rememberForSession}) {
  final trimmed = key.trim();
  if (rememberForSession) {
    SessionStorage.writeApiKey(trimmed);
  } else {
    SessionStorage.clearApiKey();
  }
  state = ApiKeyState(key: trimmed,
      rememberedForSession: rememberForSession);
}

void forget() {
  SessionStorage.clearApiKey();
  state = const ApiKeyState();
}'''),
    ...para('//',
        'The default is memory only: close the tab and it is '
        'gone. An opt-in toggle mirrors it to sessionStorage — '
        'which survives a refresh but not a closed tab — and the '
        'wrapper around the browser API is documented as never '
        'used for localStorage, the persistent store. The '
        'reasoning is blast radius: anything in localStorage is '
        'readable by any script that later runs on the origin, '
        'indefinitely; sessionStorage bounds the exposure to one '
        'browsing session.'),
    blank,
    ...para('//',
        'Errors are written with the same care. Exceptions the '
        'user can see are built to never contain the key, and '
        'a 401 or 403 from Mistral is a distinct exception type '
        'whose handler wipes the key and returns to the unlock '
        'screen with a clear message, so a bad key never leaves '
        'the app in a half-working state:'),
    ...code('dart', 'lib/providers/generation_provider.dart (trimmed)', r'''
try {
  final response = await call();
  state = state.copyWith(isLoading: false, response: response);
} on ApiKeyRejectedException catch (e) {
  ref.read(keyRejectedMessageProvider.notifier).state = e.message;
  ref.read(apiKeyProvider.notifier).forget();
  state = state.copyWith(isLoading: false, clearError: true);
} on MistralApiException catch (e) {
  state = state.copyWith(isLoading: false, error: e.message);
}'''),

    ...sec('making a language model obey rules'),
    ...para('//',
        'The system prompt is a spec, not a pleasantry. It is '
        'numbered, uses “strictly, without exception”, and '
        'states the behaviours that matter most as rules with '
        'concrete failure cases:'),
    ...code('dart', 'lib/services/mistral_client.dart · system prompt (excerpt)', r'''
1. Never drop a selected field. The user has selected
   exactly these fields: [$fieldsList]. EVERY proposed
   subject must genuinely engage ALL of these fields
   substantively — not merely be superficially compatible.
2. Never add a field the user did not select, and never
   assume one field implies another (e.g. theology does not
   imply art ...).
3. If the user's free-text input conflicts with, or implies,
   a field that is NOT in the selected list, ask exactly ONE
   short clarifying question ... but you must STILL provide
   usable topic options in the same response.
6. Every subject must name REAL, VERIFIABLE events, works,
   people, or documents. Never invent anecdotes or fabricate
   references.'''),
    ...para('//',
        'Rule 3 shows the design philosophy. A model asked to '
        '“ask a clarifying question when unsure” will often '
        'return only the question, leaving the user with nothing. '
        'The rule demands both in one response, so the worst '
        'case is still useful. Rule 6 is the honest limit of the '
        'approach: a model can still invent a reference, which '
        'is why the bibliography is framed as a starter list to '
        'verify, not a citation source.'),
    blank,
    ...para('//',
        'The level rule calibrates difficulty rather than topic: '
        'licence is a bounded, accessible corpus with no '
        'paleography; master situates the work in a historiographic '
        'debate; mémoire builds around one tractable '
        'problématique; PhD demands original archival '
        'contribution; general public bans jargon. Tone and '
        'mood are enumerated values, each mapped to what it '
        'should sound like, so “playful” and “reverent” mean '
        'something repeatable.'),

    ...sec('structured output you cannot trust blindly'),
    ...para('//',
        'The request sets JSON mode. That guarantees syntactic '
        'validity — not that the object has the shape the UI '
        'expects, so the exact schema is also written into the '
        'prompt, with exact counts (3 bibliography entries, 3 '
        'outline parts). And since even valid JSON can fail to '
        'arrive, the client is defensive in layers:'),
    ...code('dart', 'lib/services/mistral_client.dart (trimmed)', r'''
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
    {'role': 'user', 'content':
        'Your last message was not valid JSON. Resend your '
        'ENTIRE answer again, as ONE strictly valid JSON object '
        'matching the schema ...'},
  ];
  // one retry, then a clear MistralApiException
}'''),
    ...pt('//', 'strip fences',
        'models sometimes wrap JSON in code fences despite being '
        'told not to; one regex removes them.'),
    ...pt('//', 'one retry',
        'the retry includes the model’s own bad answer plus a '
        'precise correction, which fixes malformed output far '
        'more reliably than re-sending the original request. Only '
        'one retry — a second failure becomes a visible error '
        'instead of a loop that burns the user’s credits.'),
    ...pt('//', 'sanitize',
        'the next section.'),

    ...sec('a bug you only find by reading a stack trace'),
    ...code('dart', 'lib/services/sanitize.dart (trimmed)', r'''
dynamic sanitizeJsonTree(dynamic value) {
  if (value is String) return _unescape.convert(value);
  if (value is Map) {
    // Built explicitly (rather than via `value.map(...)`)
    // because promoting a `dynamic` value to `Map` via
    // `is Map` loses the `<String, dynamic>` type arguments,
    // so `.map()` silently returns `Map<dynamic, dynamic>` —
    // which then fails the `as Map<String, dynamic>` cast at
    // every call site.
    final result = <String, dynamic>{};
    value.forEach((key, v) {
      result[key as String] = sanitizeJsonTree(v);
    });
    return result;
  }
  if (value is List) return value.map(sanitizeJsonTree).toList();
  return value;
}'''),
    ...para('//',
        'Why sanitize at all? Despite a prompt rule forbidding '
        'HTML entities, a model occasionally emits “&amp;” or a '
        'numeric emoji entity, and the UI would print it '
        'literally. The fix walks the decoded JSON and decodes '
        'every string, once, before any widget sees it. The '
        'comment in the middle is the lesson: Dart’s type '
        'promotion drops generic type arguments, so the “obvious” '
        'map() one-liner type-checks and then fails at runtime. '
        'Writing the loop out is the boring, correct version.'),

    ...sec('suggesting fields without deciding for the user'),
    ...para('//',
        'If the user types “cathédrale” while only history is '
        'selected, they probably want architecture involved. '
        'The app should notice, but never assume — rule 2 of the '
        'prompt forbids exactly that. So detection is pure, local '
        'Dart (no API call), and its output is a suggestion the '
        'user can dismiss:'),
    ...code('dart', 'lib/services/field_detection.dart (trimmed)', r'''
const Map<String, String> _fieldTriggerKeywords = {
  'tableau': 'art',
  'cathedrale': 'architecture',
  'liturgie': 'catholic_theology',
  'cathedral': 'architecture',
  // ...
};

List<FieldDetectionMatch> detectImpliedFields(
    String freeText, List<String> selectedFieldIds) {
  final normalized = ' ${_stripDiacritics(freeText.toLowerCase())} ';
  final selected = selectedFieldIds.toSet();
  final matches = <String, FieldDetectionMatch>{};

  _fieldTriggerKeywords.forEach((keyword, fieldId) {
    if (selected.contains(fieldId) ||
        matches.containsKey(fieldId)) return;
    if (normalized.contains(keyword)) {
      matches[fieldId] = FieldDetectionMatch(fieldId, keyword);
    }
  });
  return matches.values.toList();
}'''),
    ...para('//',
        'Keywords are stored accent-stripped and lowercase in '
        'French and English, because the user writes in either '
        'and “cathédrale” must match “cathedrale”. At most one '
        'suggestion per field, never one for a field already '
        'selected. A keyword table is crude — and deliberately '
        'so: it is instant, free, explainable and testable, and '
        'the model still gets the final say through its '
        'clarifying question.'),

    ...sec('turning output into something usable'),
    ...para('//',
        'A topic is only useful if it can leave the app. The '
        'bibliography exports to BibTeX, with the details that '
        'make an export actually import cleanly:'),
    ...code('dart', 'lib/services/bibtex_export.dart (trimmed)', r'''
String _bibtexEscape(String value) =>
    value.replaceAll('{', '(').replaceAll('}', ')');

String _entryType(String type) => switch (type) {
  'book' => 'book',
  'article' => 'article',
  'primary_source' => 'misc',
  _ => 'misc',
};

// book -> publisher, article -> journal,
// primary source -> howpublished + note'''),
    ...para('//',
        'Braces would terminate a BibTeX field early, so they are '
        'neutralised; each source type maps to the field BibTeX '
        'expects for it (publisher, journal, howpublished); '
        'citation keys are built from the first author’s name and '
        'year, with the entry’s position added to keep them '
        'unique. Saved topics '
        'go into a notebook, persisted locally, with space for '
        'personal notes — and a refine step sends the current '
        'topic back with an instruction and gets the full topic '
        'plus a summary of what changed.'),

    ...sec('shipping and checking it'),
    ...para('//',
        'Because it is static files, deployment is a build and a '
        'copy; the repo carries a GitHub Pages workflow that '
        'builds with the right base href for the repository '
        'path, and the README documents Netlify drag-and-drop as '
        'the alternative. Tests cover the parts that can break '
        'without anyone noticing: the client’s retry and error '
        'mapping against a mocked HTTP layer, and the sanitizer.'),
    blank,
    ...para('//',
        'What I would say about it: the interesting engineering '
        'is not the model call, it is everything that makes the '
        'call safe to depend on — a relay that cannot leak, a key '
        'that cannot persist, a prompt that states its own '
        'failure cases, parsing that assumes the model will '
        'sometimes be wrong, and suggestions that never decide '
        'for the user.'),
    blank,
    link('→ github.com/XNash/xyno-scholar',
        'https://github.com/XNash/xyno-scholar'),
  ],
);
