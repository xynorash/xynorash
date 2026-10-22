import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/.github/workflows/pages.yml',
  lines: [
    cm(r'#', '──────────────────────────────────────────'),
    cm(r'#', r'.github/workflows/pages.yml'),
    cm(r'#', r'build the site and force-push it as one orphan commit'),
    cm(r'#', r'the deployment history is deliberately not kept'),
    cm(r'#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'publishes the website to the gh-pages branch'),
    kv(r'language', r'GitHub Actions YAML with a bash step'),
    kv(r'size', r'85 lines, two commits (94ff2dc, b989c1f)'),
    kv(r'triggers', r'push to main touching site, docs/media, README.md, the build script or this file · manual dispatch'),
    kv(r'serves', r'https://xynorash.github.io/xynovim/ from the gh-pages branch, root folder'),
    ...sec(r'why this file exists'),
    ...para(r'#', r'GitHub Pages can be fed in two ways: by a workflow that uploads an artifact and calls the deploy-pages action, or from a branch. This workflow takes the second one, and the header explains the choice. main holds only the source: site/, scripts/build-site.py and docs/media/. gh-pages holds only the built site, as a single orphan commit that every deployment replaces by a force push. The reason is in the comment: the media is, by its estimate, about 20 MB, and a history of deployments would bloat the repository.'),
    blank,
    ...code('yaml', r'.github/workflows/pages.yml · lines 1-12', r'''
# The website (https://xynorash.github.io/xynovim/) is served by GitHub Pages
# from the dedicated branch `gh-pages` (root), not through the Actions
# deploy-pages mechanism.
#
# Branch model: `main` holds the source (site/, scripts/build-site.py,
# docs/media/); `gh-pages` holds ONLY the built site (the branch root is the
# site root, with .nojekyll), as a single orphan commit that every deployment
# replaces with a force push. That is deliberate: the media is about 20 MB and
# a history of deployments would bloat the repository.
#
# To (re)point Pages at the branch: Settings > Pages > Build and deployment >
# Source "Deploy from a branch" > Branch gh-pages, folder / (root).
'''),
    ...para(r'#', r'The last paragraph of the header says how to point Pages at the branch, which is a setting that lives outside the repository and cannot be recreated from files. The header comment is where it is recorded.'),
    blank,
    ...sec(r'when it runs'),
    ...code('yaml', r'.github/workflows/pages.yml · lines 13-31', r'''
name: pages

on:
  push:
    branches: [main]
    paths:
      - "site/**"
      - "docs/media/**"
      - "README.md"
      - "scripts/build-site.py"
      - ".github/workflows/pages.yml"
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: pages
  cancel-in-progress: false
'''),
    ...para(r'#', r'The workflow runs on pushes to main whose changes touch one of five paths: the site, the media, the README (the numbers on the page come from it), the build script and the workflow itself. A push that only changes a Lua module does not redeploy. workflow_dispatch allows a manual run. The permissions of the whole workflow are read-only, and the concurrency group named pages with cancel-in-progress set to false serialises deployments: a second push waits for the first instead of killing it halfway through a force push.'),
    blank,
    ...sec(r'the guard and the job'),
    ...code('yaml', r'.github/workflows/pages.yml · lines 33-48', r'''
jobs:
  publish:
    # forks have no Pages branch to feed; only main is ever published
    if: github.repository == 'xynorash/xynovim' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    timeout-minutes: 15
    permissions:
      contents: write # pushes the gh-pages branch, nothing else
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
          fetch-depth: 0 # the sitemap's lastmod dates come from git history

      - name: Build the site and check its links and assets
        run: python3 scripts/build-site.py --out _site --check
'''),
    ...para(r'#', r'The job only runs on the main repository and on the main branch. The comment gives the reason: forks have no Pages branch to feed. Write access is granted for this job alone (contents: write, with a comment that it pushes the gh-pages branch and nothing else). The checkout does not persist the token and fetches the full history, because the sitemap’s lastmod dates are derived from git (see scripts/build-site.py); fetch-depth 0 was added in b989c1f when the sitemap appeared. The build runs with --check so a dangling link or a missing anchor fails the job before anything is published.'),
    blank,
    ...para(r'#', r'The checkout action is pinned to a different commit than in the other two workflows: the pages file pins v7.0.1 while ci.yml and platforms.yml pin v4.2.2. The files do not say whether that is deliberate.'),
    blank,
    ...sec(r'the publish step'),
    ...code('yaml', r'.github/workflows/pages.yml · lines 50-62', r'''
      - name: Publish _site to the gh-pages branch
        # zizmor and a reviewer will notice the force push: it is the design
        # (one orphan commit, see the top of the file). The token is passed to
        # one `git push` through an env var and a one-shot http.extraheader; it
        # is never written to a git config, and the checkout did not persist it.
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          branch=gh-pages
          remote="https://github.com/${GITHUB_REPOSITORY}.git"
          short=${GITHUB_SHA::7}
'''),
    ...para(r'#', r'The comment names its audience: zizmor, a static analyser for workflows, and a reviewer will notice a force push, and that it is the design. It also states how the token is handled: passed to one git push through an environment variable and a single-use http.extraheader, never written to a git config, and the checkout did not persist it. The shell runs with set -euo pipefail.'),
    blank,
    ...code('yaml', r'.github/workflows/pages.yml · lines 63-72', r'''
          before=$(git ls-remote --heads "$remote" "refs/heads/$branch" | cut -f1)
          echo "remote $branch before: ${before:-<absent>}"

          cd _site
          git init -q -b "$branch"
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add -A
          git commit -q -m "Deploy ${short} from main"
          local_sha=$(git rev-parse HEAD)
'''),
    ...para(r'#', r'Before changing anything the step prints the current head of gh-pages on the remote (or absent), so a log shows what was replaced. Then in _site it creates a new repository on a branch named gh-pages, configures the identity of the Actions bot, commits everything with a message of the form Deploy <short sha> from main, and remembers the commit id.'),
    blank,
    ...code('yaml', r'.github/workflows/pages.yml · lines 74-85', r'''
          auth=$(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 -w0)
          echo "::add-mask::$auth"
          # the only refspec of the job: it cannot touch another branch
          git -c "http.extraheader=Authorization: Basic ${auth}" push --force "$remote" "HEAD:refs/heads/${branch}"

          after=$(git ls-remote --heads "$remote" "refs/heads/$branch" | cut -f1)
          echo "remote $branch after:  ${after}"
          if [ "$after" != "$local_sha" ]; then
            echo "gh-pages is not at the commit just pushed" >&2
            exit 1
          fi
          git ls-remote --heads "$remote" | cut -f2 | sort
'''),
    ...para(r'#', r'The token is turned into a basic-auth header with base64 and announced as a mask with ::add-mask:: so that the encoded form is hidden in the log too (the script computes the header value itself, and ::add-mask:: masks a given string). The push has a single refspec, HEAD to refs/heads/gh-pages, and the comment spells out the consequence: it cannot touch any other branch. After the push the step asks the remote for the head of the branch again and fails if it is not the commit just made, so a silent rejection cannot pass as a success. The last line lists the heads on the remote for the log.'),
    blank,
    ...sec(r'design decisions and trade-offs'),
    ...pt(r'#', r'orphan commit', r'the published branch is always exactly one commit; the media (about 20 MB, per the header comment) is not multiplied by every deployment.'),
    ...pt(r'#', r'force push on a dedicated branch', r'risky anywhere else, and harmless on a branch that holds no source. The workflow narrows the risk further with one refspec.'),
    ...pt(r'#', r'verify after push', r'the job compares the remote with the local commit, an explicit end-to-end check of the thing that matters.'),
    ...pt(r'#', r'narrow permissions', r'read by default, write for one job, token never persisted.'),
    ...sec(r'how it is tested'),
    ...para(r'#', r'tests/site_spec.lua has a describe block named after this file with seven tests. Two lint it with actionlint and zizmor, and skip with a message when the tool is not installed. The others state the design in executable form: every action is pinned by full SHA and no third-party deploy action is used; permissions are read by default and write only in the publish job; the workflow never runs on pull requests, runs on push to main with the path filter and on manual dispatch, and only in this repository; it only ever pushes to the branch gh-pages with the token in a one-shot header; and the repository ignores _site/. The comment in the workflow about zizmor is therefore also a promise that the test checks.'),
    blank,
    ...sec(r'history'),
    ...pt(r'#', r'94ff2dc 2026-10-16', r'added with the site, the build script and the specs.'),
    ...pt(r'#', r'b989c1f 2026-10-22', r'technical SEO: fetch-depth 0 for the sitemap dates.'),
  ],
);
