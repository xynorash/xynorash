import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/.github/workflows/ci.yml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'ci.yml - a pinned, checksummed, headless test job'),
    cm('#', r'specs plus a lazy.nvim smoke test on ubuntu'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the repository’s only workflow'),
    kv(r'language', r'GitHub Actions YAML (62 lines)'),
    kv(r'triggers', r'push to main, pull_request'),
    kv(r'jobs', r'one: test (ubuntu-latest, 30 minute timeout)'),
    kv(r'added', r'6947749, 2026-10-22, "Add README, help file and CI workflow"'),
    ...sec(r'why this file exists'),
    ...para('#', r'The specs of this plugin need a lot from the machine: a specific Neovim, the rust-analyzer binary, cargo, and two tree-sitter parsers (rust for routes and navigation, yaml for ActJob). The workflow therefore installs or builds each of them explicitly. The workflow builds the whole toolchain from pinned sources and then runs the same two commands the README documents. Everything that can drift is pinned to a version or a commit.'),
    ...sec(r'pins as environment'),
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
  TS_RUST_SHA: 77a3747266f4d621d0757825e6b11edcbf991ca5 # tree-sitter-rust
  TS_YAML_SHA: a1c4812a73ec5e089de8e441fdea3a921e8d5079 # tree-sitter-yaml'''),
    ...para('#', r'The top is conservative. permissions: contents: read is least privilege for a job that only tests. NVIM_VERSION is v0.12.5, the same 0.12 series as the plugin’s minimum, and it comes with a SHA-256 of the tarball. The lazy.nvim commit and the two tree-sitter grammars are full 40-character commit hashes, each with a comment naming what it is (lazy.nvim v11.17.5, tree-sitter-rust, tree-sitter-yaml). A tag can be moved; a commit hash cannot.'),
    ...sec(r'Neovim, verified'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 19-35', r'''
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 30
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

      - name: Add rust-analyzer'''),
    ...para('#', r'Checkout is pinned to a commit with a trailing comment for the version (v4.2.2) and persist-credentials: false, so the token is not left in the git config of the workspace. Neovim is downloaded from the GitHub release, checked with sha256sum -c (the step title says "checksum verified") and unpacked into the home directory, which is then added to PATH through GITHUB_PATH. If the release asset were replaced, the job would fail at that line instead of testing the wrong editor.'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 37-38', r'''
      - name: Build the tree-sitter parsers (pinned commits)'''),
    ...para('#', r'rust-analyzer comes from rustup component add. The specs that start a real rust-analyzer (for example the rust-nav spec and the code_actions block) need it; the workflow itself does not install a toolchain beyond that step.'),
    ...sec(r'parsers built from source'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 40-51', r'''
          build() {
            d="$RUNNER_TEMP/ts-$1"
            git init -q "$d"
            git -C "$d" fetch -q --depth 1 "$2" "$3"
            git -C "$d" checkout -q FETCH_HEAD
            mkdir -p "$RUNNER_TEMP/ts/parser"
            cc -shared -fPIC -O2 -I "$d/src" "$d/src/parser.c" "$d/src/scanner.c" -o "$RUNNER_TEMP/ts/parser/$1.so"
          }
          build rust https://github.com/tree-sitter/tree-sitter-rust "${TS_RUST_SHA}"
          build yaml https://github.com/tree-sitter-grammars/tree-sitter-yaml "${TS_YAML_SHA}"

      - name: Specs'''),
    ...para('#', r'There is no nvim-treesitter in CI. A small shell function does what is needed: initialise an empty repository, fetch exactly one commit at depth 1, check it out, and compile parser.c and scanner.c into a shared library named after the language, placed in a parser directory under RUNNER_TEMP. Nothing else about tree-sitter is installed. That directory is what the specs get through XYNO_TEST_RTP, which tests/run.lua appends to the runtimepath. Fetching by hash means the grammar the specs see is the grammar the authors saw.'),
    ...sec(r'the two test steps'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 53-54', r'''
      - name: Fetch lazy.nvim (pinned commit)'''),
    ...para('#', r'The specs step is the README command with the parser directory exported: nvim -l tests/run.lua. The runner spawns one headless Neovim per spec file, prints ok, FAIL or SKIP lines, and exits non-zero on any failure, so the job fails without any extra glue.'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 56-62', r'''
          git init -q "$RUNNER_TEMP/lazy.nvim"
          git -C "$RUNNER_TEMP/lazy.nvim" fetch -q --depth 1 https://github.com/folke/lazy.nvim.git "${LAZY_SHA}"
          git -C "$RUNNER_TEMP/lazy.nvim" checkout -q FETCH_HEAD

      - name: Smoke test through lazy.nvim
        run: |
          XYNO_LAZY="$RUNNER_TEMP/lazy.nvim" nvim --headless -u tests/e2e/init.lua -c "luafile tests/e2e/smoke.lua"'''),
    ...para('#', r'The second step is end to end. lazy.nvim is fetched at its pinned commit the same way as the grammars, and the plugin is started through it with tests/e2e/init.lua and tests/e2e/smoke.lua. The unit specs load modules by hand; this step proves the thing a user does, which is to install the plugin with a plugin manager and call setup. It sets XYNO_LAZY so the init file knows where the clone is.'),
    ...sec(r'what the job does not do'),
    ...pt('#', r'no matrix', r'one operating system. The README says the same: Linux is tested here, Windows and macOS are not.'),
    ...pt('#', r'no formatter or linter step', r'a .stylua.toml exists in the repository, but the workflow does not run stylua.'),
    ...pt('#', r'no caching', r'every run builds the parsers; each parser is compiled from parser.c and scanner.c.'),
    ...pt('#', r'no secrets', r'the job needs none and has read-only permissions.'),
    ...sec(r'history'),
    ...para('#', r'The workflow was added in 6947749 (2026-10-22, 09:20 +03:00) after the specs commit 7c1d2d9. xynovim has its own CI workflow, whose history shows related changes: fc2062a (2026-10-14) "make the suite pass on a clean machine", dc846f6 (2026-10-14) a 40 minute job timeout, and the platform workflow from ff1c8fa (2026-10-16). Here the timeout is 30 minutes and the workflow has no Mason or bootstrap step.'),
  ],
);
