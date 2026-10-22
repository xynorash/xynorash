import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-imports.nvim/.github/workflows/ci.yml',
  lines: [
    cm(r'''#''', r'''──────────────────────────────────────────'''),
    cm(r'''#''', r'''ci.yml — a pinned, checksummed, from-source test rig'''),
    cm(r'''#''', r'''Neovim, rust-analyzer, tree-sitter and lazy.nvim all fixed to a version or commit'''),
    cm(r'''#''', r'''──────────────────────────────────────────'''),
    blank,
    kv(r'''role''', r'''GitHub Actions workflow: run the specs and the smoke test on every push to main and every pull request'''),
    kv(r'''language''', r'''YAML, one job, ubuntu-latest'''),
    kv(r'''size''', r'''66 lines, 1 commit'''),
    kv(r'''pins''', r'''Neovim v0.12.5 with SHA-256, lazy.nvim v11.17.5 by commit, tree-sitter-rust by commit, actions/checkout by commit'''),
    kv(r'''timeout''', r'''30 minutes'''),
    ...sec(r'''why this file exists'''),
    ...para(r'''#''', r'''The specs need more than a checkout. They need Neovim 0.12, the sibling plugin, a tree-sitter Rust parser, rust-analyzer, and the crates of a fixture project already downloaded, because the acceptance cases run a real language server. The plugin requires Neovim 0.12, so this file downloads that release itself instead of relying on whatever the runner image has, and builds the rest of the rig. It was added in 9373a52 on 2026-10-22, the last of the three commits, after the specs it runs.'''),
    blank,
    ...sec(r'''trigger and permissions'''),
    ...code('yaml', r'.github/workflows/ci.yml · lines 3-8', r'''
on:
  push:
    branches: [main]
  pull_request:

permissions:'''),

    ...para(r'''#''', r'''The workflow runs on pushes to main and on pull requests, with the token reduced to contents: read. A test job never needs to write to the repository, so it gets no ability to.'''),
    blank,
    ...sec(r'''pinning: what is fixed and how'''),
    ...code('yaml', r'.github/workflows/ci.yml · lines 11-16', r'''
env:
  NVIM_VERSION: v0.12.5
  NVIM_SHA256: bce0f56eda1f1b1db6eee8f4133d7a38813ea07933837dd1777411ca384c6875
  LAZY_SHA: 85c7ff3711b730b4030d03144f6db6375044ae82 # lazy.nvim v11.17.5
  TS_RUST_SHA: 77a3747266f4d621d0757825e6b11edcbf991ca5 # tree-sitter-rust
'''),

    ...para(r'''#''', r'''Four pins, three kinds. Neovim is pinned by version and by SHA-256 of the tarball, verified before use. lazy.nvim is pinned by a full commit hash with the release in a comment. tree-sitter-rust is pinned by commit. The checkout action is pinned by commit, with the tag in a comment, and persist-credentials is false. A tag can be moved to another commit, while a commit hash and a checksum fix the content; the sibling plugin is the exception, as described below.'''),
    blank,
    ...code('yaml', r'.github/workflows/ci.yml · lines 22-24', r'''
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
        with:
          persist-credentials: false'''),

    ...sec(r'''installing Neovim'''),
    ...code('yaml', r'.github/workflows/ci.yml · lines 26-33', r'''
      - name: Install Neovim (pinned, checksum verified)
        run: |
          curl -fsSL -o nvim.tar.gz "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-x86_64.tar.gz"
          echo "${NVIM_SHA256}  nvim.tar.gz" | sha256sum -c -
          mkdir -p "$HOME/nvim"
          tar -xzf nvim.tar.gz -C "$HOME/nvim" --strip-components=1
          echo "$HOME/nvim/bin" >> "$GITHUB_PATH"
'''),

    ...para(r'''#''', r'''The step downloads the release tarball, checks it with sha256sum -c, which exits non-zero on a mismatch and fails the step, unpacks it with --strip-components=1 into $HOME/nvim, and appends the bin directory to GITHUB_PATH so later steps find nvim. The tarball name is the Linux x86_64 build; the job runs on one platform only, matching the README claim that Linux is the tested platform.'''),
    blank,
    ...sec(r'''the dependency: xyno-rust.nvim'''),
    ...code('yaml', r'.github/workflows/ci.yml · lines 34-39', r'''
      - name: Fetch xyno-rust.nvim (the dependency)
        run: |
          git init -q "$RUNNER_TEMP/xyno-rust.nvim"
          git -C "$RUNNER_TEMP/xyno-rust.nvim" fetch -q --depth 1 https://github.com/xynorash/xyno-rust.nvim.git main
          git -C "$RUNNER_TEMP/xyno-rust.nvim" checkout -q FETCH_HEAD
          echo "XYNO_RUST_DIR=$RUNNER_TEMP/xyno-rust.nvim" >> "$GITHUB_ENV"'''),

    ...para(r'''#''', r'''The plugin depends on its sibling, and the workflow fetches the sibling main branch with a depth-1 fetch into the runner temp directory. XYNO_RUST_DIR is exported through GITHUB_ENV, which tests/run.lua and tests/e2e/init.lua read. This one is not pinned: the dependency is tracked at main on purpose, so the specs show when a change in xyno-rust.nvim breaks this plugin. The cost is that a red run can come from the other repository, which is why it is a named step.'''),
    blank,
    ...sec(r'''rust-analyzer and the fixture crates'''),
    ...code('yaml', r'.github/workflows/ci.yml · lines 41-44', r'''
      - name: Add rust-analyzer and fetch the fixture crates
        run: |
          rustup component add rust-analyzer
          cargo fetch --manifest-path tests/fixtures/deps-lab/Cargo.toml'''),

    ...para(r'''#''', r'''rustup component add rust-analyzer provides a server that matches the toolchain on the runner. cargo fetch on the deps-lab manifest downloads the six dependencies of the fixture (anyhow, clap, serde, serde_json, thiserror, tokio) while the network is surely there. The specs skip when cargo metadata fails offline, so this step is what turns those skips into real runs.'''),
    blank,
    ...sec(r'''building the parser from source'''),
    ...code('yaml', r'.github/workflows/ci.yml · lines 46-55', r'''
      - name: Build the tree-sitter rust parser (pinned commit)
        run: |
          d="$RUNNER_TEMP/ts-rust"
          git init -q "$d"
          git -C "$d" fetch -q --depth 1 https://github.com/tree-sitter/tree-sitter-rust "${TS_RUST_SHA}"
          git -C "$d" checkout -q FETCH_HEAD
          mkdir -p "$RUNNER_TEMP/ts/parser"
          cc -shared -fPIC -O2 -I "$d/src" "$d/src/parser.c" "$d/src/scanner.c" -o "$RUNNER_TEMP/ts/parser/rust.so"

      - name: Specs'''),

    ...para(r'''#''', r'''The rig builds its own Rust parser; a run without one would skip the scan and the flow cases through need_parser. The step fetches the grammar at a pinned commit, compiles parser.c and scanner.c with the system cc into rust.so under a parser/ directory, and the specs find it through XYNO_TEST_RTP, which tests/run.lua appends to the runtime path. No nvim-treesitter is needed and no query files, which matches the plugin: its queries are strings in the engine.'''),
    blank,
    ...sec(r'''the two test steps'''),
    ...code('yaml', r'.github/workflows/ci.yml · lines 55-57, 64-66', r'''
      - name: Specs
        run: XYNO_TEST_RTP="$RUNNER_TEMP/ts" nvim -l tests/run.lua

...
      - name: Smoke test through lazy.nvim
        run: |
          XYNO_LAZY="$RUNNER_TEMP/lazy.nvim" XYNO_TEST_RTP="$RUNNER_TEMP/ts" nvim --headless -u tests/e2e/init.lua -c "luafile tests/e2e/smoke.lua"'''),

    ...para(r'''#''', r'''The first runs the runner, nvim -l tests/run.lua, which starts one headless Neovim per spec. The second fetches lazy.nvim at the pinned commit and runs the smoke test with a minimal init that lets lazy.nvim load the checkout with its dependency. The order matters: the cheap, broad specs run before the second fetch.'''),
    blank,
    ...sec(r'''what the job does not do'''),
    ...pt(r'''#''', r'''No matrix''', r'''one OS, one Neovim. Windows and macOS were run in xynovim, whose results the README quotes with run numbers, but this repository does not claim them.'''),
    ...pt(r'''#''', r'''No lint step''', r'''.stylua.toml exists, but stylua is not run by the workflow.'''),
    ...pt(r'''#''', r'''No caching''', r'''every run downloads Neovim and rebuilds the parser.'''),
    ...sec(r'''history'''),
    ...pt(r'''#''', r'''9373a52 2026-10-22''', r'''"Add README, help file and CI workflow": 66 lines, unchanged since.'''),
  ],
);
