import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/worker/README.md',
  lines: [
    heading('# xyno-scholar-relay — the relay’s own README'),
    blank,
    kv('role', 'operating manual for the Cloudflare Worker in this folder'),
    kv('format', 'Markdown, 72 lines, 5 sections'),
    kv('written', '2026-08-06 in 98e7e48; unchanged since'),
    kv('audience', 'whoever must debug, verify or redeploy the relay'),
    blank,
    ...text(
        'This is the only documentation the relay has, and it is '
        'written to answer four questions in order: why does this '
        'exist, what does it promise, how do I check that it still '
        'behaves, and how do I change it. The top-level README links '
        'here instead of repeating the details, so this file is where '
        'the relay’s guarantees are stated in one place.'),
    ...sec('why it exists, in the file’s own words'),
    ...code('bash', 'worker/README.md · the first section', r'''
A minimal, stateless Cloudflare Worker that relays `chat/completions`
requests from the Xyno Scholar browser app to Mistral's API.'''),
    ...text(
        'The section that follows it explains the CORS problem: a '
        'JSON POST with an Authorization header makes the browser '
        'send an OPTIONS preflight first, Mistral’s endpoint is said '
        'not to answer it reliably, and the failure shows up in the '
        'browser before the request ever reaches Mistral. The Worker '
        'sits in between purely to add the headers Mistral does not '
        'return, nothing else. The page for worker/src/index.js walks '
        'through the code that does this; the point of this README is '
        'that the problem statement is written down in plain language '
        'next to the code.'),
    ...sec('the promises, and where each one is kept'),
    ...text(
        'The “What it does” section is a short list of claims. Each '
        'one can be checked against the 44-line source, and it is '
        'worth doing, because a privacy statement is only as good as '
        'the code that backs it.'),
    ...code('bash', 'worker/README.md · the promises', r'''
- Reads whatever `Authorization` header and JSON body the client sends.
- Forwards them verbatim to `https://api.mistral.ai/v1/chat/completions`.
- **Holds no state.** No API key is ever stored, logged, or persisted by
  the Worker — it passes the `Authorization` header straight through on
  every request and forgets it immediately after. The BYOK model is
  unchanged: the user's Mistral key still lives only in their browser.'''),
    ...bullet('reads the header and body',
        'request.headers.get with an empty-string default, and '
        'request.text() for the body. Nothing else is read from the '
        'request.'),
    ...bullet('forwards them verbatim',
        'the body is never parsed. The upstream call sets exactly two '
        'headers, Content-Type and Authorization.'),
    ...bullet('returns the response with CORS headers',
        'the status is copied from Mistral’s response and the three '
        'Access-Control headers are merged into the reply.'),
    ...bullet('holds no state',
        'no module-level variables are mutated, nothing is written, '
        'wrangler.toml declares no bindings, and there is no logging '
        'statement. The claim matches the file. What the repository '
        'cannot show is that the deployed script is this one.'),
    ...sec('the behaviour table'),
    ...code('bash', 'worker/README.md · endpoints and behaviour', r'''
| Method  | Response |
|---------|----------|
| `OPTIONS` | `204` with CORS headers (preflight) |
| `POST`    | Forwarded to Mistral; returns Mistral's real status + body + CORS headers |
| anything else | `405 Method not allowed` with CORS headers |'''),
    ...text(
        'Three rows, three branches in the code, in the same order. '
        'The phrase “Mistral’s real status” is the important one: the '
        'app’s key handling relies on a 401 or 403 from Mistral '
        'arriving unchanged, because lib/services/mistral_client.dart '
        'turns exactly those two codes into a rejected key and sends '
        'the user back to the unlock screen.'),
    ...sec('local development and the three checks'),
    ...code('bash', 'worker/README.md · verifying the preflight', r'''
# Preflight
curl -i -X OPTIONS http://localhost:8787 \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: Content-Type, Authorization"'''),
    ...text(
        'This reproduces what a browser does before the real call. A '
        'healthy relay answers 204 and echoes the allowed method and '
        'headers. Note that the check can be run without any API key '
        'at all.'),
    ...code('bash', 'worker/README.md · a POST that must fail in the right way', r'''
# POST (with a throwaway/invalid key — should return Mistral's real 401, with CORS headers)
curl -i -X POST http://localhost:8787 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer invalid-key" \'''),
    ...text(
        'This is the cleverest line in the file. A test that needs a '
        'valid secret is a test that tends not to be run. By sending '
        'a deliberately invalid key, the check proves three things at '
        'once with no cost and no credential: the request reached '
        'Mistral, Mistral answered with its own 401, and the answer '
        'came back through the relay with CORS headers. It is the '
        'same check the deploy commit b3d2b1c reports having run '
        'against the live address: preflight 204, invalid-key POST '
        '401 with Mistral’s “Invalid API Key” body.'),
    ...text(
        'The third command, a plain GET, should return 405. Together '
        'the three are the relay’s whole test suite. They are manual, '
        'they are documented, and nothing in the repository runs them '
        'automatically.'),
    ...sec('deploying and redeploying'),
    ...code('bash', 'worker/README.md · the deploy command', r'''
cd worker
CLOUDFLARE_API_TOKEN=<token> npx wrangler deploy'''),
    ...text(
        'The README asks for a token scoped to Workers Scripts: Edit '
        'and says no broader account access is needed. That is least '
        'privilege applied to a token that will sit in a developer’s '
        'shell: it can replace one kind of resource and nothing else. '
        'After the deploy the output prints the live workers.dev '
        'address, which is how the real URL reached '
        'mistral_client.dart in b3d2b1c.'),
    ...text(
        'The closing sentence sets the expectation for future '
        'changes: if the logic ever needs to change, for example a '
        'different upstream URL, edit src/index.js and redeploy the '
        'same way, because there is no build step and no other state '
        'to migrate. For a Worker whose whole state is its source, '
        'that is accurate.'),
    ...sec('what the README does not say'),
    ...bullet('the token on the command line',
        'assigning the token inline puts it in the command text, '
        'which many shells record in their history. An exported '
        'variable or a secrets manager avoids that. The README does '
        'not discuss it.'),
    ...bullet('no pinned tooling',
        'there is no package.json, so npx resolves whichever Wrangler '
        'is current when the command runs.'),
    ...bullet('no statement about abuse',
        'the code allows any origin and has no rate limit, and the '
        'README is silent on that. The page for worker/src/index.js '
        'discusses it.'),
    ...bullet('no operational notes',
        'nothing about where the logs are, how to roll back, or how '
        'to see request volume. For a one-function relay that is a '
        'reasonable omission, and it is also a list of what the next '
        'person would have to discover.'),
    ...sec('why this file is worth having'),
    ...text(
        'Small services tend to rot at the edges: nobody remembers '
        'which account the Worker lives in, which permission the '
        'token needs, or how to prove it still works. This README '
        'answers those in 72 lines, and it ties each promise to '
        'something checkable. For a project whose headline claim is '
        'that a secret never touches a server, putting the '
        'verification steps in the repository next to the code is '
        'part of the security design, not decoration.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
