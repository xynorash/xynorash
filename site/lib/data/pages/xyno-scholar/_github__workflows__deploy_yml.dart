import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/.github/workflows/deploy.yml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'deploy.yml — from push to a live URL on GitHub Pages'),
    cm('#', 'two jobs, one build flag, and a floating Flutter channel'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'CI/CD: build the Flutter web app and publish it to GitHub Pages'),
    kv('language', 'YAML (GitHub Actions)'),
    kv('size', '49 lines, 2 jobs, 6 steps'),
    kv('added', '2026-08-06 09:50 UTC, commit cb25af9, never edited since'),
    kv('serves at', '/xyno-scholar/ (project site, so a base-href is required)'),
    ...sec('why this file exists'),
    ...para('#',
        'The app is a pile of static files, and the project’s promise '
        'is that it needs no server. GitHub Pages is a free static '
        'host that sits next to the repository, so the shortest path '
        'from a commit to a URL is a workflow that builds the site '
        'and hands the output to Pages. The README already described '
        'this as a manual option (build, push build/web to a gh-pages '
        'branch, pass a base-href for subpaths). The commit that '
        'added this file, cb25af9, replaces those three manual steps '
        'with a pipeline, and its message states the intent: build on '
        'push to main and publish build/web through '
        'upload-pages-artifact and deploy-pages, with the correct '
        'base-href for the repository’s Pages path.'),
    ...sec('when it runs'),
    ...code('ini', '.github/workflows/deploy.yml · triggers', r'''
on:
  push:
    branches: [main]
  workflow_dispatch:'''),
    ...para('#',
        'Two triggers. A push to main deploys automatically, and '
        'workflow_dispatch adds a Run workflow button for '
        're-deploying without a new commit, which is handy after a '
        'flaky build or when something outside the repository changed '
        '(for example a new stable Flutter release). There is no '
        'pull-request trigger, so a branch is never built until it is '
        'merged. The history shows that this is how the project '
        'worked: work happened on a feature branch and Xynorash '
        'merged it through pull requests, #1 at 09:50 UTC and #2 at '
        '10:56 UTC on 2026-08-06.'),
    ...sec('permissions and concurrency'),
    ...code('ini', '.github/workflows/deploy.yml · least privilege and a queue', r'''
permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false'''),
    ...pt('#', 'contents: read',
        'the job may read the repository and do nothing else to it. '
        'It cannot push, tag or open a pull request.'),
    ...pt('#', 'pages: write',
        'needed to publish to GitHub Pages.'),
    ...pt('#', 'id-token: write',
        'lets the job request an OpenID Connect token. The official '
        'deploy-pages action uses that token to prove to Pages that '
        'this workflow run is allowed to publish, so no long-lived '
        'deploy key or personal token is stored in the repository.'),
    ...pt('#', 'group: pages, cancel-in-progress: false',
        'only one Pages deployment runs at a time, and a new push '
        'waits instead of killing the one in flight. Cancelling a '
        'deploy half-way risks a half-published site, so queueing is '
        'the safer failure mode. The cost is that two quick pushes '
        'publish in sequence.'),
    ...sec('the build job'),
    ...code('ini', '.github/workflows/deploy.yml · setting up Flutter', r'''
      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable'''),
    ...para('#',
        'The Flutter SDK is installed from the stable channel, with '
        'no version pinned. That choice is the interesting one in the '
        'file, and the history shows what it cost and what it bought; '
        'see the section on the first failure below. The checkout and '
        'pub get steps around it are the standard two lines.'),
    ...code('ini', '.github/workflows/deploy.yml · the build and the artifact', r'''
      - name: Build web
        run: flutter build web --release --base-href "/xyno-scholar/"

      - name: Upload Pages artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: build/web'''),
    ...para('#',
        'The flag is the other piece of knowledge that makes the '
        'pipeline work. A GitHub Pages project site lives at '
        '/<repository>/, not at the domain root. Flutter’s web '
        'template carries a base element whose href the build tool '
        'fills in, and the template in this repository shows the '
        'placeholder:'),
    ...code('ini', 'web/index.html · the placeholder the flag replaces', r'''
  <base href="$FLUTTER_BASE_HREF">'''),
    ...para('#',
        'With the flag, every asset URL in the built page starts with '
        '/xyno-scholar/, so the JavaScript, the fonts and the icons '
        'are found. Without it, the page would request them from the '
        'domain root and get 404s, which looks like a blank white '
        'page. The README documents the same rule as step three of '
        'its manual Pages recipe. The path is hard-coded to this '
        'repository’s name, so a renamed repository needs a workflow '
        'edit.'),
    ...para('#',
        'The artifact step packages build/web, the release output the '
        'README describes as fully static HTML, JS, CSS and assets. '
        'No environment variable, secret or key is needed at build '
        'time, because the user’s Mistral key is supplied at runtime '
        'in the browser. That is why this workflow has no secrets: '
        'section at all.'),
    ...sec('the deploy job'),
    ...code('ini', '.github/workflows/deploy.yml · publishing', r'''
  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}'''),
    ...para('#',
        'Publishing is a second job so that it can be gated '
        'separately. needs: build means it runs only if the build job '
        'succeeded. The github-pages environment is where GitHub '
        'records deployments and where protection rules, if the owner '
        'ever adds any, would be enforced. The url line copies the '
        'address reported by the deployment step into the '
        'environment, so the run page shows a clickable link to the '
        'live site.'),
    ...sec('the first failure, and the argument for a floating channel'),
    ...para('#',
        'The most useful evidence about this pipeline is a bug it '
        'surfaced. The next commit on the main line, 89a9c12 at 09:58 '
        'UTC, eight minutes after the first merge, says that the '
        'pinned lucide_icons 0.257.0 package subclassed Flutter’s '
        'IconData, which had become a final class in newer stable '
        'releases, and that this broke flutter build web in CI on '
        'Flutter stable 3.44.8 with the message that IconData cannot '
        'be extended outside its library because it is a final class. '
        'The fix swapped to lucide_icons_flutter, which composes '
        'IconData instead of subclassing it, and touched 18 files, '
        'almost all of them a single changed import line.'),
    ...para('#',
        'Note what kind of failure it was. It was not a logic bug in '
        'the app; it was an old package meeting a newer SDK, and the '
        'thing that had moved was the SDK. Because the workflow '
        'tracks the stable channel, it hit the incompatibility on its '
        'first real run. A pinned Flutter version would probably have '
        'kept that first build green and postponed the discovery to '
        'the day someone upgraded locally. The trade-off is the usual '
        'one: a floating channel finds breakage early and makes '
        'builds less reproducible; a pinned version does the '
        'opposite. The repository did not record a decision either '
        'way, and the file has not been edited since.'),
    ...sec('what the pipeline does not do'),
    ...pt('#', 'it never runs the tests',
        'the repository contains ten test cases (eight for the '
        'Mistral client, one for the sanitiser, one widget smoke '
        'test). No step runs flutter test and none runs flutter '
        'analyze. A change that breaks a test would still be '
        'published if it compiles.'),
    ...pt('#', 'it never deploys the Worker',
        'the CORS relay under worker/ is deployed by hand with '
        'wrangler. A site deploy and a relay deploy are independent '
        'events.'),
    ...pt('#', 'it pins nothing',
        'the runner image is ubuntu-latest, the Flutter channel is '
        'stable, and the actions are pinned to major tags (v4, v2, '
        'v3) and not to commit hashes.'),
    ...pt('#', 'it does not cache',
        'each run downloads the SDK and resolves packages from '
        'scratch. For a site this small, that is a cost in minutes '
        'and not in anything else.'),
    ...sec('unknowns'),
    ...para('#',
        'Two things cannot be read from the repository. The first is '
        'whether the Mistral work, the commits after the second '
        'merged pull request (98e7e48 and b3d2b1c), ever reached '
        'main: the clone has a single branch and no main ref, so the '
        'history alone cannot say whether those commits were '
        'published by this workflow. The second is the outcome of any '
        'run. Workflow runs are not stored in git, so every statement '
        'on this page about the pipeline’s behaviour is derived from '
        'the file, the commit messages and the timing of the commits.'),
    ...sec('what could come next'),
    ...pt('#', 'add flutter analyze and flutter test',
        'two lines in the build job would put the test suite on the '
        'publishing path.'),
    ...pt('#', 'pin or matrix the Flutter version',
        'run stable plus a pinned version, so that a stable-channel '
        'break is flagged without blocking a deploy.'),
    ...pt('#', 'deploy the relay from CI',
        'a wrangler step with a repository secret would remove the '
        'manual deploy, at the price of storing a Cloudflare token as '
        'a secret.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
