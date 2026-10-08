import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/worker/wrangler.toml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'wrangler.toml — three lines that name, find and pin the relay'),
    cm('#', 'the entire deployment configuration of the Worker'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'Cloudflare Wrangler config for the relay Worker'),
    kv('language', 'TOML'),
    kv('size', '3 lines'),
    kv('added', '2026-08-06, commit 98e7e48; first deployed in b3d2b1c'),
    kv('absent', 'vars, secrets, KV, routes, account id: all of them'),
    ...sec('the whole file'),
    ...code('toml', 'worker/wrangler.toml', r'''
name = "xyno-scholar-relay"
main = "src/index.js"
compatibility_date = "2024-09-23"'''),
    ...para('#',
        'Wrangler is Cloudflare’s command-line tool for Workers. '
        'Given this file and an API token it uploads one script and '
        'gives it a public address. Everything a Worker usually needs '
        'a configuration file for (environment variables, secret '
        'bindings, storage bindings, scheduled triggers, custom '
        'routes) is missing here, and that absence is the most '
        'informative thing about the file.'),
    ...sec('line by line'),
    ...pt('#', 'name = "xyno-scholar-relay"',
        'the script’s name inside the Cloudflare account, and also '
        'the first label of its public hostname. The URL the app '
        'calls is the name, then the account’s workers.dev subdomain, '
        'then workers.dev. lib/services/mistral_client.dart holds '
        'that URL as a constant: '
        'https://xyno-scholar-relay.xyno-scholar.workers.dev. The '
        'middle label, xyno-scholar, is the subdomain registered for '
        'the account during deployment; the commit message of b3d2b1c '
        'says a workers.dev subdomain was registered for the account '
        'just before the deploy. Renaming the Worker here would '
        'therefore change the address and break the app until the '
        'constant is updated.'),
    ...pt('#', 'main = "src/index.js"',
        'the entry point, relative to this file. Wrangler bundles '
        'from here. Because index.js imports nothing, the bundle is '
        'the file itself; worker/README.md says as much: there is no '
        'build step.'),
    ...pt('#', 'compatibility_date = "2024-09-23"',
        'a Workers-specific setting that freezes the runtime’s '
        'behaviour at a given day, so that platform changes '
        'introduced after that date do not silently alter a deployed '
        'script. The repository does not explain why this date was '
        'chosen. It sits nearly two years before the commit date of '
        '2026-08-06, which suggests a value copied from a template or '
        'an older example and not a deliberately current one; I '
        'cannot prove that from the history.'),
    ...sec('what the missing keys prove'),
    ...para('#',
        'A privacy claim that depends on code is easier to believe '
        'when the configuration around the code is just as empty. The '
        'repository’s promise is that the relay never stores or logs '
        'the user’s Mistral key. Here is what would have to appear in '
        'this file for a Worker to keep anything between requests, '
        'and does not.'),
    ...pt('#', 'no [vars] or secrets',
        'nothing is injected at deploy time. The Worker has no key of '
        'its own to leak, because it has no key of its own. Every '
        'credential it handles arrives in a request and leaves in a '
        'request.'),
    ...pt('#', 'no storage bindings',
        'no KV namespace, Durable Object, D1 database or R2 bucket is '
        'declared. Without a binding, a Worker has no built-in '
        'durable place to write to, so storage inside Cloudflare is '
        'ruled out by configuration and not just by the absence of '
        'code. (The script could still call some outside service with '
        'fetch, which is why the source file has to be read as well.)'),
    ...pt('#', 'no routes or custom domain',
        'the Worker is served only on its default workers.dev '
        'address. There is no domain to manage, no certificate to '
        'renew and nothing to mis-route.'),
    ...pt('#', 'no account_id',
        'Wrangler takes the account from the token or from an '
        'interactive login, so this file is safe to commit: it names '
        'no account. The deploy instructions in worker/README.md use '
        'an environment variable for the token instead of any file.'),
    ...sec('how it was used'),
    ...para('#',
        'Deployment is a manual, one-command act and is documented in '
        'worker/README.md: change into worker/ and run npx wrangler '
        'deploy with a CLOUDFLARE_API_TOKEN that has only the Workers '
        'Scripts: Edit permission. The output prints the live '
        'address. The deploy commit b3d2b1c records the follow-up: '
        'the real URL replaced a placeholder in mistral_client.dart, '
        'and the live Worker was checked with a real preflight (204 '
        'and CORS headers) and a POST with an invalid key (401 and '
        'Mistral’s body, CORS headers intact).'),
    ...para('#',
        'The Worker is not part of the GitHub Pages workflow. '
        '.github/workflows/deploy.yml builds and publishes only the '
        'Flutter site; it never calls Wrangler. The two halves of the '
        'system therefore deploy independently, which suits how '
        'rarely the relay needs to change, and it also means a change '
        'to src/index.js reaches users only when someone runs the '
        'deploy command by hand.'),
    ...para('#',
        'Local development uses the same file: npx wrangler dev '
        'serves the Worker on port 8787, and the three curl checks in '
        'worker/README.md exercise the preflight, the forwarded POST '
        'and the 405. The .gitignore gained two lines in 98e7e48 for '
        'the by-products of that command: worker/.wrangler/ and '
        'worker/node_modules/.'),
    ...sec('limits'),
    ...pt('#', 'Wrangler is not pinned',
        'there is no package.json in worker/, so npx fetches '
        'whichever Wrangler version is current each time it is run. '
        'That is fine for a three-line config and a one-off deploy, '
        'and it is a source of drift if the config ever grows.'),
    ...pt('#', 'the date is not explained',
        'a comment saying why 2024-09-23 was picked, or when it '
        'should be moved forward, would help the next reader.'),
    ...pt('#', 'no environments',
        'there is a single production Worker. Experiments happen '
        'locally with wrangler dev or directly in production.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
