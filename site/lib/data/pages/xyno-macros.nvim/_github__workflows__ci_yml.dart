import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-macros.nvim/.github/workflows/ci.yml',
  lines: [
    cm('#', r'──────────────────────────────────────────'),
    cm('#', r'ci.yml — the workflow with the most to provision'),
    cm('#', r'two plugins, a completion engine, a language server, a parser built from source'),
    cm('#', r'──────────────────────────────────────────'),
    kv(r'role', r'GitHub Actions workflow named ci'),
    kv(r'triggers', r'push to main and every pull request'),
    kv(r'size', r'77 lines, one job, nine steps'),
    kv(r'timeout', r'30 minutes (the same value as in the CI files of xyno-crates, xyno-imports, xyno-new and xyno-rust)'),
    kv(r'pins', r'Neovim and checksum, lazy.nvim, blink.cmp, tree-sitter-rust by commit'),
    kv(r'history', r'added in 7ffb48e (2026-10-22, Add README, help file and CI workflow)'),
    ...sec(r'why this file exists'),
    ...para('#', r'The completion tests need a lot of environment: the two plugins this one builds on, a '
        r'real rust-analyzer and a populated cargo registry for the derive discovery, the '
        r'tree-sitter Rust parser for everything that classifies an attribute target, and, for the '
        r'completion-menu specs, blink.cmp itself. A CI run that lacked any of them would pass by '
        r'skipping. This workflow builds all of them, each pinned.'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 11-16', r'''
env:
  NVIM_VERSION: v0.12.5
  NVIM_SHA256: bce0f56eda1f1b1db6eee8f4133d7a38813ea07933837dd1777411ca384c6875
  LAZY_SHA: 85c7ff3711b730b4030d03144f6db6375044ae82 # lazy.nvim v11.17.5
  BLINK_SHA: 78336bc89ee5365633bcf754d93df01678b5c08f # blink.cmp v1.10.2
  TS_RUST_SHA: 77a3747266f4d621d0757825e6b11edcbf991ca5 # tree-sitter-rust
'''),
    ...sec(r'the pins'),
    ...para('#', r'The environment block lists five values: the Neovim version and its checksum, and three commits, '
        r'with comments naming lazy.nvim v11.17.5, blink.cmp v1.10.2 and tree-sitter-rust. The blink.cmp pin '
        r'matches the 1.* version constraint in the README, and the commit that added that '
        r'constraint (9ab48fb) came after this workflow.'),
    ...sec(r'the dependencies'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 35-43', r'''
      - name: Fetch xyno-rust.nvim and xyno-imports.nvim (the dependencies)
        run: |
          for p in rust imports; do
            git init -q "$RUNNER_TEMP/xyno-$p.nvim"
            git -C "$RUNNER_TEMP/xyno-$p.nvim" fetch -q --depth 1 "https://github.com/xynorash/xyno-$p.nvim.git" main
            git -C "$RUNNER_TEMP/xyno-$p.nvim" checkout -q FETCH_HEAD
          done
          echo "XYNO_RUST_DIR=$RUNNER_TEMP/xyno-rust.nvim" >> "$GITHUB_ENV"
          echo "XYNO_IMPORTS_DIR=$RUNNER_TEMP/xyno-imports.nvim" >> "$GITHUB_ENV"
'''),
    ...para('#', r'The two plugin dependencies are fetched from their main branches, not from pinned '
        r'commits, and exposed to the specs through environment variables added to GITHUB_ENV. This '
        r'is the one unpinned input in the workflow: a change to xyno-rust.nvim is tested against this plugin the next '
        r'time this workflow runs.'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 45-55', r'''
      - name: Fetch blink.cmp (pinned commit, for the completion-menu specs)
        run: |
          git init -q "$RUNNER_TEMP/blink.cmp"
          git -C "$RUNNER_TEMP/blink.cmp" fetch -q --depth 1 https://github.com/Saghen/blink.cmp.git "${BLINK_SHA}"
          git -C "$RUNNER_TEMP/blink.cmp" checkout -q FETCH_HEAD
          echo "XYNO_BLINK_DIR=$RUNNER_TEMP/blink.cmp" >> "$GITHUB_ENV"

      - name: Add rust-analyzer and fetch the fixture crates
        run: |
          rustup component add rust-analyzer
          cargo fetch --manifest-path tests/fixtures/deps-lab/Cargo.toml
'''),
    ...para('#', r'blink.cmp comes by commit hash, with a shallow fetch, and the fixture crates are fetched '
        r'with cargo fetch against the fixture manifest so that the derive discovery specs find '
        r'serde_derive, clap_derive and thiserror-impl in the registry. rust-analyzer is added with '
        r'rustup.'),
    ...sec(r'building the parser'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 57-64', r'''
      - name: Build the tree-sitter rust parser (pinned commit)
        run: |
          d="$RUNNER_TEMP/ts-rust"
          git init -q "$d"
          git -C "$d" fetch -q --depth 1 https://github.com/tree-sitter/tree-sitter-rust "${TS_RUST_SHA}"
          git -C "$d" checkout -q FETCH_HEAD
          mkdir -p "$RUNNER_TEMP/ts/parser"
          cc -shared -fPIC -O2 -I "$d/src" "$d/src/parser.c" "$d/src/scanner.c" -o "$RUNNER_TEMP/ts/parser/rust.so"
'''),
    ...para('#', r'The tree-sitter Rust parser is compiled from source in CI: a pinned commit of the grammar '
        r'is fetched, and its parser.c and scanner.c are compiled into a shared object with the '
        r'system C compiler and placed in a directory shaped like a runtimepath entry. '
        r'XYNO_TEST_RTP points the specs and the smoke test at it. The smoke test uses the same directory.'),
    ...sec(r'specs and smoke'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 66-77', r'''
      - name: Specs
        run: XYNO_TEST_RTP="$RUNNER_TEMP/ts" nvim -l tests/run.lua

      - name: Fetch lazy.nvim (pinned commit)
        run: |
          git init -q "$RUNNER_TEMP/lazy.nvim"
          git -C "$RUNNER_TEMP/lazy.nvim" fetch -q --depth 1 https://github.com/folke/lazy.nvim.git "${LAZY_SHA}"
          git -C "$RUNNER_TEMP/lazy.nvim" checkout -q FETCH_HEAD

      - name: Smoke test through lazy.nvim
        run: |
          XYNO_LAZY="$RUNNER_TEMP/lazy.nvim" XYNO_TEST_RTP="$RUNNER_TEMP/ts" nvim --headless -u tests/e2e/init.lua -c "luafile tests/e2e/smoke.lua"
'''),
    ...para('#', r'The specs run with XYNO_TEST_RTP set; the runner starts one Neovim per spec file. Then '
        r'lazy.nvim is fetched by hash, and the smoke test loads the plugin with its dependencies '
        r'through it. The workflow has no matrix and runs on one Linux runner, which matches the '
        r'README: Linux is the only platform claimed.'),
    ...sec(r'what it does not do'),
    ...pt('#', r'No Windows or macOS job', r'the README explains why: the live flows failed or hung there in xynovim’s CI.'),
    ...pt('#', r'Dependencies unpinned', r'the two sibling plugins come from their main branch.'),
  ],
);
