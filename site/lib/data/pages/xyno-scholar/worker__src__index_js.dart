import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/worker/src/index.js',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'index.js — the whole CORS relay, in 44 lines'),
    cm('//', 'a stateless Worker that exists to add three headers'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'stateless CORS relay between the browser app and Mistral'),
    kv('language', 'JavaScript, one ES module, no dependencies'),
    kv('size', '44 lines, 1 default export, 0 bindings'),
    kv('deployed', '2026-08-06, commit b3d2b1c (workers.dev)'),
    kv('state', 'none: no KV, no secrets, no env vars, no logging'),
    ...sec('why this file exists'),
    ...para('//',
        'The app is a static site with no backend, and the user types '
        'their own Mistral API key into it. That design means the '
        'browser has to call the model provider directly. A browser '
        'will only let a page read a cross-origin response if the '
        'server opts in with CORS headers, and when a request carries '
        'a JSON content type or an Authorization header the browser '
        'first sends an OPTIONS preflight and refuses to send the '
        'real request unless the preflight answer grants it. The '
        'repository’s README states that Mistral’s chat endpoint does '
        'not reliably answer that preflight, so a direct fetch from '
        'the page fails before it reaches Mistral.'),
    ...para('//',
        'CORS is a rule enforced by browsers, not by servers. A '
        'server-to-server call is not subject to it. So the smallest '
        'possible fix is a hop that is not a browser: this Worker '
        'receives the browser’s request, makes the same call from '
        'Cloudflare’s network, and hands the answer back with the '
        'headers the browser needs. It is the whole job, and the file '
        'is short enough that the entire job fits on one screen.'),
    ...para('//',
        'This was a planned contingency before it was a fix. The '
        'README written in the very first scaffold commit (7a200e7), '
        'when the app still called Cerebras directly, ends its CORS '
        'note by saying that if the provider ever changed its policy, '
        'a minimal CORS-passthrough function that holds no secret '
        'would need to sit in front of the API. The Gemini-era README '
        'says the same. The Mistral commit (98e7e48) is where that '
        'sentence became code.'),
    ...sec('the constants'),
    ...code('js', 'worker/src/index.js · the upstream and the headers', r'''
const MISTRAL_URL = "https://api.mistral.ai/v1/chat/completions";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};'''),
    ...pt('//', 'the upstream is a constant',
        'MISTRAL_URL is fixed in the source. Nothing in the incoming '
        'request can choose where the Worker connects: not a header, '
        'not a path, not a query string (the request URL is never '
        'read at all). That makes the relay a one-destination pipe '
        'and rules out the classic open-proxy abuse, in which a relay '
        'is talked into fetching arbitrary hosts.'),
    ...pt('//', 'Allow-Origin is a wildcard',
        'any web page may call this Worker. There is no origin '
        'allowlist. The app sends no cookies and no browser-managed '
        'credentials, so the wildcard is legal, and it keeps the '
        'relay usable from the GitHub Pages site, from localhost '
        'during development and from anywhere else the app is served. '
        'The price is that the Worker is open to any caller; the only '
        'thing standing between a stranger and Mistral is that the '
        'stranger needs a valid Mistral key of their own.'),
    ...pt('//', 'Allow-Headers names Authorization',
        'the two request headers the app sends are listed explicitly. '
        'As far as I know the Fetch standard does not let a wildcard '
        'in Allow-Headers stand in for Authorization, which is a '
        'plausible reason the list is spelled out and not a star. The '
        'repository does not say why.'),
    ...pt('//', 'Allow-Methods lists POST and OPTIONS',
        'exactly the two methods the app uses. The only legitimate '
        'request is a POST, and the preflight that precedes it is an '
        'OPTIONS.'),
    ...sec('the front door: preflight and a method gate'),
    ...code('js', 'worker/src/index.js · fetch() — the first two branches', r'''
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    if (request.method !== "POST") {
      return new Response("Method not allowed", {
        status: 405,
        headers: CORS_HEADERS,
      });
    }'''),
    ...para('//',
        'The preflight is answered by the Worker itself. It never '
        'goes to Mistral, so it cannot fail because of anything '
        'Mistral does or does not support. A 204 with no body and the '
        'three Access-Control headers is exactly what the browser is '
        'waiting for.'),
    ...para('//',
        'Everything that is not a POST gets a 405, and the 405 also '
        'carries the CORS headers. That detail is easy to miss and it '
        'matters for debugging: if an error response lacked CORS '
        'headers, the browser would hide its status and body from the '
        'page and report an opaque network failure instead. With the '
        'headers present, a stray GET shows up in the console as what '
        'it is, a 405 with a readable body. The worker README lists '
        'this behaviour in a table of three rows, and the code has '
        'exactly three outcomes.'),
    ...sec('the passthrough'),
    ...code('js', 'worker/src/index.js · forwarding the call', r'''
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
    ...para('//',
        'Two values leave the incoming request and nothing else does: '
        'the Authorization header and the body. The body is read as '
        'text and sent on as that same text. It is never parsed as '
        'JSON and never re-serialised, so the Worker cannot change '
        'the model, the messages or the response_format the app '
        'chose, and it cannot fail on a malformed payload. The app’s '
        'whole request contract (model, messages, response_format) '
        'therefore lives in lib/services/mistral_client.dart and '
        'nowhere here.'),
    ...para('//',
        'The header is read with a default of an empty string. A '
        'request with no Authorization header is therefore forwarded '
        'with an empty one, and Mistral’s own 401 comes back. That is '
        'the behaviour the app wants: its client treats 401 and 403 '
        'as a rejected key, clears it and returns to the unlock '
        'screen. The Worker adds no authentication of its own and '
        'never inspects the key.'),
    ...para('//',
        'Only Content-Type and Authorization are set on the upstream '
        'call. The browser’s Origin, cookies, user agent and every '
        'other header stop at the relay. Mistral sees a plain '
        'server-side client.'),
    ...sec('the way back'),
    ...code('js', 'worker/src/index.js · returning Mistral’s answer', r'''
    const responseBody = await upstreamResponse.text();

    return new Response(responseBody, {
      status: upstreamResponse.status,
      headers: {
        "Content-Type": "application/json",
        ...CORS_HEADERS,
      },
    });'''),
    ...para('//',
        'The status code is passed through untouched. This is what '
        'lets the app’s error handling work as if the relay were not '
        'there: a 401 from Mistral arrives in the browser as a 401, a '
        '429 as a 429, a 200 as a 200. The commit that deployed the '
        'Worker (b3d2b1c) records the check that proves it: a real '
        'OPTIONS preflight returned 204 with CORS headers, and a POST '
        'with an invalid key returned Mistral’s own 401 “Invalid API '
        'Key” body with the CORS headers intact.'),
    ...para('//',
        'The upstream body is read to the end with text() before '
        'anything is returned, so the response is buffered, not '
        'streamed. That fits the client as it stands today: the '
        'Cerebras version of the app streamed server-sent events '
        '(commit c1b3d71, 10:28 UTC), and the Gemini commit 24 '
        'minutes later removed streaming entirely. If streaming ever '
        'came back, this is the line that would have to change, '
        'because a buffered relay would deliver the whole stream at '
        'the end. This is my reading of the code, not something the '
        'repository states.'),
    ...para('//',
        'Content-Type is forced to application/json for every '
        'response that comes back through this path, whatever Mistral '
        'actually sent. Every body the app expects from this endpoint '
        'is JSON, so the simplification costs nothing for the app.'),
    ...sec('what is deliberately not here'),
    ...pt('//', 'no error handling around the upstream fetch',
        'if Mistral cannot be reached, fetch() throws and nothing '
        'catches it. As I understand Workers, an uncaught exception '
        'becomes a Cloudflare error response that this code does not '
        'decorate with CORS headers, so the browser would see a '
        'failed request and the app would show its generic “Could not '
        'reach Mistral” message. The path was not exercised in the '
        'repository.'),
    ...pt('//', 'no logging',
        'there is no console.log anywhere in the file, which is what '
        'the README’s claim that nothing is logged rests on. It is '
        'true of this source. A deployed Worker also has '
        'platform-level observability settings that live in the '
        'Cloudflare account and cannot be seen from the repository.'),
    ...pt('//', 'no rate limit, no origin check',
        'see the wildcard above. A stranger with their own key can '
        'use this relay for free as a CORS shim to Mistral’s chat '
        'endpoint. The cost to the owner is Worker request volume, '
        'not Mistral spend.'),
    ...pt('//', 'no tests',
        'worker/ holds three files: README.md, src/index.js and '
        'wrangler.toml. There is no package.json, no test runner and '
        'no CI step for it. Verification was manual, with the three '
        'curl commands in worker/README.md.'),
    ...sec('the trust question'),
    ...para('//',
        'The relay is what makes the privacy claim worth reading '
        'carefully. The app’s README says the key is “forwarded on '
        'each request and forgotten immediately after”, and the 44 '
        'lines support that: the key is a local constant inside one '
        'function call, it is passed to one fetch, and it is not '
        'written anywhere. Stateless by construction is a stronger '
        'statement than a policy, because there is nothing to leak '
        'that the code ever keeps.'),
    ...para('//',
        'But a user in a browser cannot see which code is actually '
        'deployed at the workers.dev address that mistral_client.dart '
        'points to. They can read this file; they cannot attest that '
        'it is what runs. The honest summary is that the design '
        'reduces what the operator could do by accident and makes the '
        'intended behaviour easy to audit, while the final guarantee '
        'is the operator’s word. The user can always revoke a Mistral '
        'key from Mistral’s console, which is the practical '
        'mitigation that bring-your-own-key buys.'),
    ...sec('history'),
    ...para('//',
        'One commit created the file and one commit later wired it '
        'in. 98e7e48 (2026-08-06, 12:19 UTC) added '
        'worker/src/index.js, worker/wrangler.toml and '
        'worker/README.md in the same change that replaced Gemini '
        'with Mistral, and left a TODO in mistral_client.dart for the '
        'real URL. b3d2b1c (12:54 UTC) deployed the Worker with '
        'wrangler after registering a workers.dev subdomain for the '
        'account and replaced the placeholder. The file has not '
        'changed since it was first written, which fits a program '
        'with one job.'),
    ...sec('what could come next'),
    ...pt('//', 'restrict the origin',
        'reply with the exact Pages origin instead of a wildcard, '
        'accepting that local development then needs its own entry.'),
    ...pt('//', 'catch the upstream failure',
        'a try/catch that returns a 502 with the CORS headers would '
        'turn a silent network error into a readable one.'),
    ...pt('//', 'pass the body through',
        'returning upstreamResponse.body instead of buffering it '
        'would keep the relay compatible with streaming if the client '
        'ever streams again.'),
    ...pt('//', 'add one test',
        'the three-outcome behaviour is exactly the kind of thing a '
        'ten-line test with a stubbed fetch can pin.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
