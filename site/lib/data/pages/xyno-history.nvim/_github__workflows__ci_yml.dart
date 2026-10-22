import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-history.nvim/.github/workflows/ci.yml',
  lines: [
    cm('#', r'──────────────────────────────────────────'),
    cm('#', r'ci.yml — specs, then the plugin loaded by a pinned lazy.nvim'),
    cm('#', r'a smoke test in the environment users actually have'),
    cm('#', r'──────────────────────────────────────────'),
    kv(r'role', r'GitHub Actions workflow named ci'),
    kv(r'triggers', r'push to main and every pull request'),
    kv(r'size', r'44 lines, one job named test'),
    kv(r'permissions', r'contents: read'),
    kv(r'history', r'added in 40b8c53 (2026-10-22, Add README, help file and CI workflow)'),
    ...sec(r'why this file exists'),
    ...para('#', r'This workflow proves that the plugin loads through a plugin manager. The unit specs run in a bare Neovim and the history spec drives git heavily; the '
        r'smoke test checks the one thing they do not, that lazy.nvim can install the plugin from '
        r'its spec and that the documented commands appear. The workflow runs both.'),
    ...sec(r'pins at the top'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 1-14', r'''
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
'''),
    ...para('#', r'The pins sit in an env block at the workflow level, as in the sandbox and macros '
        r'workflows: the Neovim version and its SHA-256, and a lazy.nvim commit with a comment '
        r'naming the release it is, v11.17.5. A commit hash is used for lazy.nvim because the tag '
        r'could move. The timeout of 20 minutes is longer than the 10 and 15 of the clipboard and '
        r'guard workflows, and shorter than the 30 of the macros workflow, because the history spec '
        r'runs real git, sleeps and child Neovims (the concurrency test allows 100 seconds for six '
        r'of them).'),
    ...sec(r'neovim, verified'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 16-31', r'''
jobs:
  test:
    runs-on: ubuntu-latest
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
    ...para('#', r'The same install idiom as in the siblings: download the release tarball, check the '
        r'digest, unpack, add to the path, with checkout credentials not persisted.'),
    ...sec(r'specs, then the plugin manager'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 33-44', r'''
      - name: Specs
        run: nvim -l tests/run.lua

      - name: Fetch lazy.nvim (pinned commit)
        run: |
          git init -q "$RUNNER_TEMP/lazy.nvim"
          git -C "$RUNNER_TEMP/lazy.nvim" fetch -q --depth 1 https://github.com/folke/lazy.nvim.git "${LAZY_SHA}"
          git -C "$RUNNER_TEMP/lazy.nvim" checkout -q FETCH_HEAD

      - name: Smoke test through lazy.nvim
        run: |
          XYNO_LAZY="$RUNNER_TEMP/lazy.nvim" nvim --headless -u tests/e2e/init.lua -c "luafile tests/e2e/smoke.lua"
'''),
    ...para('#', r'The specs run first. Then lazy.nvim is fetched by hash into the runner’s temp directory, '
        r'with a shallow fetch of that one commit, and the smoke test runs with XYNO_LAZY pointing '
        r'there. The init file and the smoke test do the rest: load, commands, help, and a real '
        r'write that must land on refs/lochist/main.'),
    ...sec(r'what it does not do'),
    ...pt('#', r'No macOS runner', r'the spec header allows macOS, the README declines to claim it, and the workflow runs only '
        r'on ubuntu-latest. The three statements agree.'),
    ...pt('#', r'No help-tags step', r'the smoke test builds the tags itself, so the workflow does not need a separate one.'),
  ],
);
