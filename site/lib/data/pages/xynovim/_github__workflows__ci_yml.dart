import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/.github/workflows/ci.yml',
  lines: [
    cm(r'#', '──────────────────────────────────────────'),
    cm(r'#', r'.github/workflows/ci.yml'),
    cm(r'#', r'the Linux gate'),
    cm(r'#', r'bootstrap from the lockfile, start silently, pass the whole suite, leave the lockfile alone'),
    cm(r'#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the main continuous-integration workflow'),
    kv(r'language', r'GitHub Actions YAML'),
    kv(r'size', r'62 lines, one job (smoke), five commits, 2026-10-09 to 2026-10-14'),
    kv(r'runs on', r'ubuntu-latest, every push to main and every pull request'),
    kv(r'timeout', r'40 minutes for the job'),
    ...sec(r'why this file exists'),
    ...para(r'#', r'An editor configuration can fail in ways that nobody sees until the next fresh machine: a plugin spec that errors, a lockfile that is out of date, a require loop, a dependency on something that happened to be installed locally. The workflow reproduces the experience of a stranger who clones the repository on an empty Linux machine and runs the documented install. It starts with that and then adds everything the project can say about correctness: the startup is silent and fast, and the suite of specs passes.'),
    blank,
    ...code('yaml', r'.github/workflows/ci.yml · lines 1-14', r'''
name: ci

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  smoke:
    runs-on: ubuntu-latest
    timeout-minutes: 40
'''),
    ...para(r'#', r'The permission is read-only for contents, set at the top, so no step can write to the repository. The trigger is push to main and every pull request, and the name ci is the one the README badge uses. The job has a long timeout, 40 minutes, raised from 15 by dc846f6 (2026-10-14), a commit whose title is about the 40 minute job timeout; by then the job also ran the bootstrap and the full suite.'),
    blank,
    ...sec(r'steps 1 to 3: a clean machine'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 15-33', r'''
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
        with:
          persist-credentials: false

      - name: Install Neovim stable
        run: |
          curl -fsSL -o nvim.tar.gz https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz
          mkdir -p "$HOME/nvim"
          tar -xzf nvim.tar.gz -C "$HOME/nvim" --strip-components=1
          echo "$HOME/nvim/bin" >> "$GITHUB_PATH"

      - name: Use the checkout as the Neovim config
        run: |
          mkdir -p "$HOME/.config"
          ln -s "$GITHUB_WORKSPACE" "$HOME/.config/nvim"

      - name: Add rust-analyzer (a prerequisite the bootstrap script checks)
        run: rustup component add rust-analyzer clippy
'''),
    ...para(r'#', r'The checkout is pinned to a full commit SHA with the version in a comment (v4.2.2), and does not keep credentials in the git config afterwards (persist-credentials: false). Neovim comes from the stable release tarball. That is a moving target, unlike the pinned and checksum-verified Neovim of platforms.yml. The difference is visible in the files: this job takes whatever stable currently is, while platforms.yml fixes Neovim to v0.12.5 (neither file states a reason).'),
    blank,
    ...para(r'#', r'The checkout becomes the configuration by a symlink in the home config directory, because that is where Neovim looks. rust-analyzer and clippy are added with rustup, and the step name says why: it is a prerequisite that the bootstrap script checks for (see scripts/bootstrap.sh). The step was added by da1d829 when the bootstrap script was introduced, and clippy was added to the list by fc2062a on 2026-10-14.'),
    blank,
    ...sec(r'step 4 and 5: the lockfile is a contract'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 35-39', r'''
      - name: Restore plugins from the lockfile
        run: scripts/bootstrap.sh

      - name: Lockfile unchanged
        run: git diff --exit-code lazy-lock.json
'''),
    ...para(r'#', r'scripts/bootstrap.sh does the two-step install and compares the lockfile itself. The explicit git diff --exit-code lazy-lock.json afterwards is a second, independent check with a different way of failing: it compares against what git has committed, not against a copy made at the start of the script. If the committed lockfile is stale, for instance after a plugin was updated and the lockfile not committed, the job stops here, before the slow part.'),
    blank,
    ...sec(r'step 6: the startup smoke test'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 41-53', r'''
      - name: Startup smoke test
        run: |
          # Shared runners are noisy, so the time bound is generous: it only
          # catches regressions like a blocking network call or a require
          # loop. Any message on stderr (a failed plugin spec, a Lua error)
          # fails the job.
          start=$(date +%s%N)
          nvim --headless +qa 2> "$RUNNER_TEMP/startup.log"
          end=$(date +%s%N)
          ms=$(( (end - start) / 1000000 ))
          echo "headless startup: ${ms} ms"
          if [ -s "$RUNNER_TEMP/startup.log" ]; then cat "$RUNNER_TEMP/startup.log"; exit 1; fi
          if [ "$ms" -gt 3000 ]; then echo "startup slower than 3000 ms"; exit 1; fi
'''),
    ...para(r'#', r'The test is simple on purpose. nvim --headless +qa starts the full configuration and quits. Standard error is redirected to a log file, and any byte in it fails the job and prints the log: the workflow comment gives a failed plugin spec and a Lua error as examples. The time is measured with nanosecond timestamps, and over 3000 ms fails. The comment explains why the bound is generous: shared runners are noisy and the check only exists to catch a regression like a blocking network call or a require loop. The log is written to RUNNER_TEMP and not in the workspace, a change made by fc2062a, so the log is not a stray file inside the checkout.'),
    blank,
    ...sec(r'steps 7 and 8: the suite and the lockfile again'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 55-62', r'''
      - name: Spec suite
        # tests/*_spec.lua, each file in its own headless nvim with a hard
        # timeout. Specs whose tool is missing (bwrap cannot create a sandbox
        # on runners that restrict user namespaces) skip with a message.
        run: scripts/test.sh

      - name: Lockfile still unchanged after the specs
        run: git diff --exit-code lazy-lock.json
'''),
    ...para(r'#', r'scripts/test.sh runs every tests/*_spec.lua in its own headless Neovim with a hard timeout. The comment lists the expected exception: specs whose tool is missing skip with a message, with bubblewrap as the example, since a runner may forbid user namespaces and the agent sandbox then cannot be created. A skipped test is printed; it does not turn the job red, and the exit code of test.sh is 0 when skips are the only non-passes. The last step is the lockfile check again, because a spec can trigger a plugin update.'),
    blank,
    ...sec(r'design decisions and trade-offs'),
    ...pt(r'#', r'one job', r'the steps share one Neovim, plugin and data directory; a second job would have to install them again.'),
    ...pt(r'#', r'fail on stderr', r'the strictest possible definition of a clean start, and also the simplest.'),
    ...pt(r'#', r'stable Neovim here, pinned elsewhere', r'Linux follows the stable channel; Windows and macOS use a pinned version with a verified checksum.'),
    ...pt(r'#', r'no matrix', r'the other operating systems are a separate workflow, platforms.yml, so that this job stays as fast and as stable as it was. The platforms file says so in its header.'),
    ...sec(r'history'),
    ...pt(r'#', r'bdd0225 2026-10-09', r'the first version: install Neovim stable, link the config, Lazy restore, the startup smoke test. 15-minute timeout.'),
    ...pt(r'#', r'da1d829 2026-10-13', r'rust-analyzer step, scripts/bootstrap.sh replaces the plain restore, and the lockfile check.'),
    ...pt(r'#', r'cf2b8e1 2026-10-13', r'the spec suite step and the second lockfile check.'),
    ...pt(r'#', r'fc2062a 2026-10-14', r'clean-machine fixes: clippy joins rust-analyzer, and the startup log moves to RUNNER_TEMP.'),
    ...pt(r'#', r'dc846f6 2026-10-14', r'timeout 40 minutes, together with an import-engine fix that walked no directories without ripgrep.'),
  ],
);
