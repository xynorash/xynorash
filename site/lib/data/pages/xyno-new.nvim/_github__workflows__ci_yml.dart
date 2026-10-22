import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-new.nvim/.github/workflows/ci.yml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'.github/workflows/ci.yml — one job, everything pinned'),
    cm('#', r'a pinned Neovim, a pinned lazy.nvim, the sibling plugin, and two test commands'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'CI for pushes to main and pull requests'),
    kv(r'language', r'GitHub Actions YAML, 51 lines, one job on ubuntu-latest'),
    kv(r'pins', r'Neovim v0.12.5 with a SHA-256, lazy.nvim by commit, actions/checkout by commit'),
    kv(r'runs', r'nvim -l tests/run.lua, then the lazy.nvim smoke test'),
    kv(r'history', r'added in 5f7578c (2026-10-22) with the README and the help file'),
    ...sec(r'why this file exists'),
    ...para('#', r'A plugin that shells out to cargo, curl and unzip has two ways to rot: Neovim changes under it, and its own tools change under it. This workflow tests against one Neovim version that is named, downloaded and verified, and runs the same two commands the README tells a user to run. It is the only CI file in the repository. In xynovim, ff1c8fa added a platforms workflow (.github/workflows/platforms.yml); the README here points to that CI for what it says about Windows and macOS. This repository’s own workflow tests Linux only.'),
    ...sec(r'triggers and permissions'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 1-8', r'''
name: ci

on:
  push:
    branches: [main]
  pull_request:

permissions:'''),
    ...para('#', r'Pushes to main and every pull request. permissions: contents: read limits the workflow token to reading repository contents.'),
    ...sec(r'the pins'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 10-13', r'''

env:
  NVIM_VERSION: v0.12.5
  NVIM_SHA256: bce0f56eda1f1b1db6eee8f4133d7a38813ea07933837dd1777411ca384c6875'''),
    ...para('#', r'Three environment values carry the reproducibility of the whole workflow. NVIM_VERSION is an exact release, v0.12.5, and the plugin demands 0.12 at runtime (init.lua checks has("nvim-0.12")), so CI tests the line the plugin claims as its minimum, at a specific patch release. NVIM_SHA256 is the checksum of the Linux tarball. LAZY_SHA is a commit, not a tag, with the tag it corresponds to in a comment (v11.17.5): a tag can be moved, a commit hash cannot. The checkout action is pinned the same way, by commit with its version in a comment, and persist-credentials: false is set on the checkout step.'),
    ...sec(r'installing Neovim and verifying it'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 25-31', r'''
      - name: Install Neovim (pinned, checksum verified)
        run: |
          curl -fsSL -o nvim.tar.gz "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-x86_64.tar.gz"
          echo "${NVIM_SHA256}  nvim.tar.gz" | sha256sum -c -
          mkdir -p "$HOME/nvim"
          tar -xzf nvim.tar.gz -C "$HOME/nvim" --strip-components=1
          echo "$HOME/nvim/bin" >> "$GITHUB_PATH"'''),
    ...para('#', r'The tarball is downloaded with curl -fsSL (fail on HTTP errors, follow redirects), and sha256sum -c - reads the expected line from stdin; a mismatch ends the step with a non-zero exit. The archive is unpacked with --strip-components=1 into $HOME/nvim and its bin directory is appended to GITHUB_PATH, which is how a step puts a program on the path of the steps after it. Using the release tarball instead of a package manager or a setup action means the binary under test is the one the maintainers published, and the hash proves it.'),
    ...sec(r'the dependency, and lazy.nvim'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 33-39, 40', r'''
      - name: Fetch xyno-rust.nvim (the dependency)
        run: git clone -q --depth 1 https://github.com/xynorash/xyno-rust.nvim.git "$RUNNER_TEMP/xyno-rust.nvim"

      - name: Fetch lazy.nvim (pinned commit)
        run: |
          git init -q "$RUNNER_TEMP/lazy.nvim"
          git -C "$RUNNER_TEMP/lazy.nvim" fetch -q --depth 1 https://github.com/folke/lazy.nvim.git "${LAZY_SHA}"
          git -C "$RUNNER_TEMP/lazy.nvim" checkout -q FETCH_HEAD'''),
    ...para('#', r'xyno-rust.nvim is cloned shallow from its default branch, unpinned. The consequence is that a change in the sibling can turn the build here red without any change in this repository. lazy.nvim is fetched differently: git init, fetch one commit by hash with --depth 1, check out FETCH_HEAD. Fetching a single commit by its full hash is the way to get a pinned tree without cloning history.'),
    ...para('#', r'Both are placed under $RUNNER_TEMP, outside the checkout, and handed to the tests through two environment variables, XYNO_RUST and XYNO_LAZY, which tests/run.lua and tests/e2e/init.lua read. That is the interface between CI and the test code.'),
    ...sec(r'the specs'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 42-46', r'''
      - name: Specs
        run: |
          git config --global user.name ci
          git config --global user.email ci@example.invalid
          XYNO_RUST="$RUNNER_TEMP/xyno-rust.nvim" nvim -l tests/run.lua'''),
    ...para('#', r'Git needs an identity for any command that makes a commit, and the specs create repositories, so a throwaway name and an example.invalid address are set globally on the runner. Then the runner: every spec in its own headless Neovim, a RESULT line, and a non-zero exit if anything failed. The workflow installs none of cargo, curl, unzip or python3; it relies on the runner image having them. The README says specs that need one of them skip with a message when it is missing, so a runner image without cargo would shrink the pass count instead of failing the build.'),
    ...sec(r'the smoke test'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 48-51', r'''
      - name: Smoke test through lazy.nvim
        run: |
          XYNO_LAZY="$RUNNER_TEMP/lazy.nvim" XYNO_RUST="$RUNNER_TEMP/xyno-rust.nvim" \
            nvim --headless -u tests/e2e/init.lua -c "luafile tests/e2e/smoke.lua"'''),
    ...para('#', r'The last step starts Neovim with tests/e2e/init.lua as its init file, so lazy.nvim, not the spec runner, puts the plugin and its dependency on the runtimepath. It answers a different question from the specs: does the plugin install the way the README says? The backslash continuation splits the two environment assignments from the command; both are variables for that one process only.'),
    ...sec(r'what is not here'),
    ...pt('#', r'No Windows or macOS job', r'the README says Windows branches are unverified and macOS is unclaimed. A matrix would be the way to change that statement.'),
    ...pt('#', r'No lint job', r'a .stylua.toml exists in the repository but the workflow does not run stylua.'),
    ...pt('#', r'No release automation', r'the workflow only runs tests; the repository has one tag, v0.1.0, on 5f7578c.'),
    ...sec(r'history'),
    ...para('#', r'Added in 5f7578c on 2026-10-22, the third and last commit of the repository, together with the README and doc/xyno-new.txt. The job’s timeout-minutes is 30; no other timing is recorded in the file.'),
  ],
);
