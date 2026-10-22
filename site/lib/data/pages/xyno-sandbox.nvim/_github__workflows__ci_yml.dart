import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-sandbox.nvim/.github/workflows/ci.yml',
  lines: [
    cm('#', r'──────────────────────────────────────────'),
    cm('#', r'ci.yml — install bubblewrap, run the specs, then load through lazy.nvim'),
    cm('#', r'and let the specs that cannot run say so'),
    cm('#', r'──────────────────────────────────────────'),
    kv(r'role', r'GitHub Actions workflow named ci'),
    kv(r'triggers', r'push to main and every pull request'),
    kv(r'size', r'46 lines, one job named test'),
    kv(r'permissions', r'contents: read'),
    kv(r'history', r'added in 03b99f2; Neovim pinned by version and checksum in c85b701 (2026-10-22)'),
    ...sec(r'why this file exists'),
    ...para('#', r'A sandbox plugin can only be tested where a sandbox exists. This workflow runs on '
        r'ubuntu-latest, installs bubblewrap from the distribution, and runs the whole suite. '
        r'Whether the behaviour tests really run depends on whether the runner allows unprivileged '
        r'user namespaces, and the workflow says in a comment what happens when it does not.'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 1-17', r'''
name: ci

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

env:
  NVIM_VERSION: v0.12.5
  NVIM_SHA256: bce0f56eda1f1b1db6eee8f4133d7a38813ea07933837dd1777411ca384c6875
  LAZY_SHA: 85c7ff3711b730b4030d03144f6db6375044ae82 # lazy.nvim v11.17.5

jobs:
  test:
'''),
    ...sec(r'the history of the Neovim step'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 19-31', r'''
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
        with:
          persist-credentials: false

      - name: Install Neovim (pinned, checksum verified)
        run: |
          curl -fsSL -o nvim.tar.gz "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-x86_64.tar.gz"
          echo "${NVIM_SHA256}  nvim.tar.gz" | sha256sum -c -
          mkdir -p "$HOME/nvim"
          tar -xzf nvim.tar.gz -C "$HOME/nvim" --strip-components=1
          echo "$HOME/nvim/bin" >> "$GITHUB_PATH"
'''),
    ...para('#', r'The step was changed by the last commit of the repository, c85b701. Before it, the '
        r'workflow installed whatever the stable release was: it downloaded the tarball and a '
        r'shasum.txt from the same release URL and checked the one against the other. That detects '
        r'a corrupted download but not a tampered release, since both files come from the same '
        r'place and the version moves. The commit pins version v0.12.5 and its SHA-256 in an env '
        r'block at the top, which turns every Neovim upgrade into a reviewed change and makes the '
        r'checksum a real check. The step name changed from stable, checksum verified to pinned, '
        r'checksum verified.'),
    ...sec(r'bubblewrap and the suite'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 33-39', r'''
      - name: Install bubblewrap
        run: sudo apt-get update && sudo apt-get install -y bubblewrap

      - name: Spec suite
        # Specs that need a working sandbox skip with a message on runners that
        # restrict user namespaces.
        run: nvim --version | head -1 && nvim -l tests/run.lua
'''),
    ...para('#', r'Bubblewrap comes from apt. The comment on the spec step explains the contract with the '
        r'tests: specs that need a working sandbox skip with a message on runners that restrict '
        r'user namespaces. The command prints the Neovim version first so that the log shows what '
        r'ran, then runs the runner, which starts one Neovim per spec file.'),
    ...sec(r'the smoke test'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 41-46', r'''
      - name: Smoke test with lazy.nvim
        run: |
          git init -q "$RUNNER_TEMP/lazy.nvim"
          git -C "$RUNNER_TEMP/lazy.nvim" fetch -q --depth 1 https://github.com/folke/lazy.nvim.git "${LAZY_SHA}"
          git -C "$RUNNER_TEMP/lazy.nvim" checkout -q FETCH_HEAD
          LAZY_PATH="$RUNNER_TEMP/lazy.nvim" nvim --headless -u tests/e2e/smoke.lua
'''),
    ...para('#', r'Lazy.nvim is fetched by its commit hash, with a comment naming the release it is, and the '
        r'smoke test runs as an init file. The checkout of lazy.nvim happens after the specs, so a '
        r'failure in the specs is reported first.'),
    ...sec(r'reading a green run'),
    ...para('#', r'A green run on a restricted runner means the structure tests, the fail-closed spec, the '
        r'setup spec and the smoke test passed, and the behaviour tests were skipped with a '
        r'message. A green run on a runner with user namespaces also means that real commands were '
        r'confined as described. The log shows which: skipped tests are printed with the reason.'),
    ...sec(r'history'),
    ...pt('#', r'03b99f2', r'2026-10-22: workflow added with the specs.'),
    ...pt('#', r'79bcfa5', r'2026-10-22: lazy.nvim pinned by commit.'),
    ...pt('#', r'c85b701', r'2026-10-22: Neovim pinned by version and checksum.'),
  ],
);
