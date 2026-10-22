import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-clipboard.nvim/.github/workflows/ci.yml',
  lines: [
    cm('#', r'──────────────────────────────────────────'),
    cm('#', r'ci.yml — one job, a pinned Neovim, specs and help tags'),
    cm('#', r'everything is pinned and verified, because CI is also an attack surface'),
    cm('#', r'──────────────────────────────────────────'),
    kv(r'role', r'GitHub Actions workflow named ci'),
    kv(r'triggers', r'push to main, and every pull request'),
    kv(r'size', r'35 lines, one job, three steps after checkout'),
    kv(r'permissions', r'contents: read, nothing else'),
    kv(r'history', r'added in 46a5b14 (2026-10-22, Add specs and CI)'),
    ...sec(r'why this file exists'),
    ...para('#', r'The specs are only a guarantee if something runs them on a clean machine. This workflow '
        r'does that and nothing more: it installs the exact Neovim the plugin claims to support, '
        r'runs the suite, and checks that the help file still builds. It is short on purpose, and '
        r'almost every line of it is a decision about trust.'),
    ...sec(r'triggers and permissions'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 1-10', r'''
name: ci

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

'''),
    ...para('#', r'The workflow runs on pushes to main and on pull requests, and it asks for the smallest '
        r'token there is: read access to the repository contents. A workflow that only runs tests '
        r'has no use for write access, so a compromised step cannot push, tag or comment.'),
    ...sec(r'the job and the pinned Neovim'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 11-18', r'''
jobs:
  specs:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    env:
      NVIM_VERSION: v0.12.5
      NVIM_SHA256: bce0f56eda1f1b1db6eee8f4133d7a38813ea07933837dd1777411ca384c6875
    steps:
'''),
    ...para('#', r'The Neovim version is a variable at the top of the job and so is its SHA-256. The timeout '
        r'of 10 minutes bounds a hung test run, which is the failure the harness cannot catch on '
        r'its own. The plugin requires Neovim 0.12 (vim.ui.clipboard.osc52), so CI pins one '
        r'concrete release of it, v0.12.5, rather than stable or nightly. The commit history of the '
        r'sibling sandbox repository shows the same change as a deliberate commit titled to pin '
        r'Neovim v0.12.5 with its checksum.'),
    ...sec(r'checkout without credentials'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 19-22', r'''
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
        with:
          persist-credentials: false

'''),
    ...para('#', r'The checkout action is pinned to a full commit hash with the version in a trailing '
        r'comment, since a tag can be moved and a hash cannot. persist-credentials is false, so the '
        r'token is not left in the repository’s git config for later steps to use.'),
    ...sec(r'installing Neovim and verifying it'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 23-29', r'''
      - name: Install Neovim 0.12
        run: |
          curl -fsSL -o nvim.tar.gz "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-x86_64.tar.gz"
          echo "${NVIM_SHA256}  nvim.tar.gz" | sha256sum -c -
          mkdir -p "$HOME/nvim"
          tar -xzf nvim.tar.gz -C "$HOME/nvim" --strip-components=1
          echo "$HOME/nvim/bin" >> "$GITHUB_PATH"
'''),
    ...para('#', r'The step downloads the release tarball with curl -fsSL, which fails on HTTP errors, '
        r'follows redirects and stays quiet, and then checks it against the recorded checksum with '
        r'sha256sum -c before unpacking anything. If the file differs by a single byte the step '
        r'fails and nothing is extracted. The tarball is unpacked into the home directory with the '
        r'top-level directory stripped, and the bin directory is appended to GITHUB_PATH so that '
        r'later steps find nvim.'),
    ...sec(r'the two checks'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 31-35', r'''
      - name: Specs
        run: nvim -l tests/run.lua

      - name: Help tags build
        run: nvim --headless -u NONE -c 'helptags doc' -c 'qa!'
'''),
    ...para('#', r'The first check runs the whole suite with nvim -l tests/run.lua; the runner prints one '
        r'line per test and exits non-zero on any failure, which is what makes the step fail. The '
        r'second builds the help tags headlessly with -u NONE, so no user config is involved, and '
        r'quits. A malformed tag in doc/xyno-clipboard.txt would fail it.'),
    ...sec(r'what is deliberately absent'),
    ...pt('#', r'No matrix', r'there is one Neovim version and one OS. The plugin is Linux only and its specs skip '
        r'elsewhere, so a matrix would add cost and prove nothing.'),
    ...pt('#', r'No lazy.nvim', r'this repository has no smoke test that loads the plugin through a plugin manager, which '
        r'the history and macros repositories do have; the clipboard module needs no manager.'),
    ...pt('#', r'No stylua check', r'the repository has a .stylua.toml but the workflow does not run the formatter.'),
    ...pt('#', r'No cache', r'the tarball is downloaded on each run; the checksum is what makes that safe.'),
  ],
);
