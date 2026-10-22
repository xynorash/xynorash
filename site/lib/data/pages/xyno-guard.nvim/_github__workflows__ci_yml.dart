import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-guard.nvim/.github/workflows/ci.yml',
  lines: [
    cm('#', r'──────────────────────────────────────────'),
    cm('#', r'ci.yml — the integration tests need the real auto-save plugin'),
    cm('#', r'so CI fetches one exact commit of it'),
    cm('#', r'──────────────────────────────────────────'),
    kv(r'role', r'GitHub Actions workflow named ci'),
    kv(r'triggers', r'push to main and every pull request'),
    kv(r'size', r'45 lines, one job named test, four steps after checkout'),
    kv(r'permissions', r'contents: read'),
    kv(r'history', r'added in 37ca0c1 (2026-10-22, Add README, help page and CI)'),
    ...sec(r'why this file exists'),
    ...para('#', r'Many of the guard’s promises can only be shown with a real auto-save plugin: that a write '
        r'really is refused inside the debounce window, that a deleted file is not recreated, that '
        r'a listener of the Post event sees modified still set. The specs skip those tests when the '
        r'plugin is missing, which would make a green CI run meaningless if CI did not supply it. '
        r'So this workflow does two things that the clipboard plugin’s workflow does not: it '
        r'fetches auto-save.nvim, and it checks the help page by opening it.'),
    ...sec(r'pinned Neovim, as in the other plugins'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 1-30', r'''
name: ci

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
        with:
          persist-credentials: false

      - name: Install Neovim 0.12
        env:
          NVIM_TAG: v0.12.5
          NVIM_SHA256: bce0f56eda1f1b1db6eee8f4133d7a38813ea07933837dd1777411ca384c6875
        run: |
          curl -fsSL -o nvim.tar.gz "https://github.com/neovim/neovim/releases/download/${NVIM_TAG}/nvim-linux-x86_64.tar.gz"
          echo "${NVIM_SHA256}  nvim.tar.gz" | sha256sum -c -
          mkdir -p "$HOME/nvim"
          tar -xzf nvim.tar.gz -C "$HOME/nvim" --strip-components=1
          echo "$HOME/nvim/bin" >> "$GITHUB_PATH"

'''),
    ...para('#', r'The top half is the same pattern as in the other xyno workflows: read-only permissions, a '
        r'job timeout (fifteen minutes here against ten in the clipboard workflow), checkout without '
        r'persisted credentials, and a Neovim release verified against a SHA-256 before it is '
        r'unpacked. The version variable here is called NVIM_TAG and sits in the step that uses it, '
        r'whereas the clipboard workflow keeps NVIM_VERSION at job level. The two values are the '
        r'same release, v0.12.5, and the same checksum.'),
    ...sec(r'fetching the dependency by commit'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 31-38', r'''
      - name: Fetch auto-save.nvim (the specs drive a real auto-save plugin)
        env:
          AUTOSAVE_SHA: 9aabcb8396224dcbf8d51c0c1d620d88a46e89d7
        run: |
          mkdir -p tests/deps/auto-save.nvim
          git -C tests/deps/auto-save.nvim init -q
          git -C tests/deps/auto-save.nvim fetch -q --depth 1 https://github.com/okuuva/auto-save.nvim.git "$AUTOSAVE_SHA"
          git -C tests/deps/auto-save.nvim checkout -q FETCH_HEAD
'''),
    ...para('#', r'The step does not clone a branch. It initialises an empty repository in '
        r'tests/deps/auto-save.nvim, fetches one commit by its full hash with depth 1, and checks '
        r'out FETCH_HEAD. This is the pinning idiom for a repository you do not own: nothing can '
        r'change underneath the hash, and the shallow fetch is quick. The location is where '
        r'tests/run.lua looks by default, so no environment variable is needed in CI.'),
    ...sec(r'running and checking the help'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 40-45', r'''
      - name: Specs
        run: nvim --headless --clean -l tests/run.lua

      - name: Help tags build and the help page resolves
        run: |
          nvim --headless --clean -c "set rtp+=." -c "helptags doc" -c "help xyno-guard" -c "qa!"
'''),
    ...para('#', r'The specs run with --clean so that the user’s config cannot interfere. The last step goes '
        r'further than a tag build: it adds the repository to the runtimepath, runs helptags on '
        r'doc, and then runs :help xyno-guard. If the main tag did not resolve, Neovim would raise '
        r'an error and the headless run would fail, so a broken help file is caught by an actual '
        r'lookup and not merely by a successful helptags.'),
    ...sec(r'what to notice'),
    ...pt('#', r'The dependency is data', r'the commit hash is a constant in the file. Updating the tested version of auto-save.nvim '
        r'is a visible one-line change in review.'),
    ...pt('#', r'No matrix', r'one OS, one Neovim. The README does not claim more than Linux.'),
  ],
);
