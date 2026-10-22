import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-crates.nvim/.github/workflows/ci.yml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'ci.yml — a pinned, offline-first CI for a plugin that needs two neighbours'),
    cm('#', r'checksum-verified Neovim, SHA-pinned actions, one Linux job, specs then smoke'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'GitHub Actions workflow, runs on push to main and on every pull request'),
    kv(r'language', r'YAML with bash steps'),
    kv(r'size', r'78 lines, one job with 9 steps, 30 minute timeout'),
    kv(r'platform', r'ubuntu-latest only (the README says Windows and macOS are not claimed)'),
    kv(r'history', r'added in dacc6a0 (2026-10-22) with the README and the help file'),
    ...sec(r'why this file exists'),
    ...para('#', r'The plugin has a test suite that needs: Neovim 0.12, the tree-sitter Rust parser, two sibling plugins, a snacks.nvim checkout for one picker test, lazy.nvim for the smoke test, and rustup with rust-analyzer plus a few registry crates for the live tests. None of that is on a stock runner. The workflow builds it, pins it, and runs the specs. xynovim’s own CI is the model (its history has a commit about getting the suite to pass on a clean machine: fc2062a, 2026-10-14, "CI: make the suite pass on a clean machine"); the shape of this file follows that setup.'),
    blank,
    ...code('yaml', r'.github/workflows/ci.yml · lines 1-21', r'''
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
  SNACKS_SHA: 882c996cf28183f4d63640de0b4c02ec886d01f2 # snacks.nvim main, the commit xynovim is tested with
  TS_RUST_SHA: 77a3747266f4d621d0757825e6b11edcbf991ca5 # tree-sitter-rust

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 30'''),
    ...sec(r'supply chain: everything is pinned except the neighbours'),
    ...para('#', r'The env block holds four pins. NVIM_VERSION v0.12.5 comes with its SHA-256, and the install step verifies it with sha256sum -c, so a tampered release asset fails the job before nvim runs. LAZY_SHA is a commit with the release in a comment (lazy.nvim v11.17.5). SNACKS_SHA is a full commit hash, commented as "snacks.nvim main, the commit xynovim is tested with", so the picker test runs against the version the author actually uses. TS_RUST_SHA pins tree-sitter-rust. The checkout action is pinned by SHA (comment: v4.2.2) with persist-credentials: false, and the job permissions are contents: read. The file does not say why it pins so much; the pattern is the same in every step.'),
    blank,
    ...code('yaml', r'.github/workflows/ci.yml · lines 27-33', r'''
      - name: Install Neovim (pinned, checksum verified)
        run: |
          curl -fsSL -o nvim.tar.gz "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-x86_64.tar.gz"
          echo "${NVIM_SHA256}  nvim.tar.gz" | sha256sum -c -
          mkdir -p "$HOME/nvim"
          tar -xzf nvim.tar.gz -C "$HOME/nvim" --strip-components=1
          echo "$HOME/nvim/bin" >> "$GITHUB_PATH"'''),
    ...para('#', r'The download uses curl -fsSL (fail on HTTP errors, silent, follow redirects), verifies the checksum, extracts with --strip-components=1 into $HOME/nvim and prepends the bin directory to GITHUB_PATH, which is how later steps find the pinned nvim and not a system one.'),
    blank,
    ...code('yaml', r'.github/workflows/ci.yml · lines 35-43', r'''
      - name: Fetch the dependencies (xyno-rust.nvim, xyno-imports.nvim)
        run: |
          for name in xyno-rust.nvim xyno-imports.nvim; do
            git init -q "$RUNNER_TEMP/$name"
            git -C "$RUNNER_TEMP/$name" fetch -q --depth 1 "https://github.com/xynorash/$name.git" main
            git -C "$RUNNER_TEMP/$name" checkout -q FETCH_HEAD
          done
          echo "XYNO_RUST_DIR=$RUNNER_TEMP/xyno-rust.nvim" >> "$GITHUB_ENV"
          echo "XYNO_IMPORTS_DIR=$RUNNER_TEMP/xyno-imports.nvim" >> "$GITHUB_ENV"'''),
    ...para('#', r'The two sibling plugins are cloned the minimal way: git init, fetch --depth 1 of main, checkout of FETCH_HEAD, no history and no full clone. Their paths go into GITHUB_ENV as XYNO_RUST_DIR and XYNO_IMPORTS_DIR, the same variables tests/run.lua and tests/e2e/init.lua read. This is the one place where nothing is pinned: it tracks main. The consequence is the right one for a plugin family that is released together and tested together (a break in xyno-rust.nvim shows up here), and the wrong one for reproducibility (a green run can turn red without a change in this repository). The workflow accepts the first for the second.'),
    blank,
    ...sec(r'the Rust side: components and fixtures'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 52-56', r'''
      - name: Add rust-analyzer and fetch the fixture crates
        run: |
          rustup component add rust-analyzer
          cargo fetch --manifest-path tests/fixtures/deps-lab/Cargo.toml
          cargo fetch --manifest-path tests/fixtures/deps-lab-nofeature/Cargo.toml'''),
    ...para('#', r'rustup component add rust-analyzer gives a real server (the specs tell a real one from rustup’s proxy stub, see H.rust_available), and cargo fetch on the two fixture manifests downloads the crates they list (clap, serde, serde_json and tokio among them) into the registry. The header of crate-features_spec.lua says the fixtures need the registry to hold them offline (cargo metadata --offline) and that those tests skip with a reason when they are missing; this step is what puts them there on CI.'),
    blank,
    ...code('yaml', r'.github/workflows/ci.yml · lines 58-65', r'''
      - name: Build the tree-sitter rust parser (pinned commit)
        run: |
          d="$RUNNER_TEMP/ts-rust"
          git init -q "$d"
          git -C "$d" fetch -q --depth 1 https://github.com/tree-sitter/tree-sitter-rust "${TS_RUST_SHA}"
          git -C "$d" checkout -q FETCH_HEAD
          mkdir -p "$RUNNER_TEMP/ts/parser"
          cc -shared -fPIC -O2 -I "$d/src" "$d/src/parser.c" "$d/src/scanner.c" -o "$RUNNER_TEMP/ts/parser/rust.so"'''),
    ...para('#', r'The Rust parser is built from source because the runner has none. The step fetches the pinned tree-sitter-rust commit and compiles parser.c and scanner.c with the system C compiler into $RUNNER_TEMP/ts/parser/rust.so. That directory is what XYNO_TEST_RTP points at. It is a short script instead of an installation of nvim-treesitter, and it pins the grammar, which is relevant because crate_add’s scan refers to node types by name (scoped_identifier, use_wildcard and token_tree all appear in crate_add.lua).'),
    blank,
    ...sec(r'the two test steps'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 67-68, 76-78', r'''
      - name: Specs
        run: XYNO_TEST_RTP="$RUNNER_TEMP/ts" nvim -l tests/run.lua
...
      - name: Smoke test through lazy.nvim
        run: |
          XYNO_LAZY="$RUNNER_TEMP/lazy.nvim" XYNO_TEST_RTP="$RUNNER_TEMP/ts" nvim --headless -u tests/e2e/init.lua -c "luafile tests/e2e/smoke.lua"'''),
    ...para('#', r'The specs step is one line: XYNO_TEST_RTP set, nvim -l tests/run.lua. The exit code of the runner is the job result. The smoke step first clones lazy.nvim (lines 70-74, same shallow fetch of a pinned commit), then runs nvim --headless -u tests/e2e/init.lua -c "luafile tests/e2e/smoke.lua" with XYNO_LAZY and XYNO_TEST_RTP. The order matters: if the specs fail the smoke test is not reached, and a plugin that does not pass its own specs is not worth installing.'),
    blank,
    ...sec(r'decisions and gaps'),
    ...pt('#', r'Linux only', r'one job on ubuntu-latest. The README’s platform section is explicit that Windows and macOS are not claimed from this repository; xynovim’s CI, where the code came from, had a Windows job that passed overall while the live rust-analyzer flows failed or hung there.'),
    ...pt('#', r'no matrix', r'one Neovim version, the pinned one. A user on a newer release is not tested until the pin moves.'),
    ...pt('#', r'no lint step', r'there is a .stylua.toml in the repository, but no step runs stylua or a Lua linter.'),
    ...pt('#', r'30 minutes', r'the file gives no reason for the number; run.lua waits up to 600000 ms for each spec file.'),
  ],
);
