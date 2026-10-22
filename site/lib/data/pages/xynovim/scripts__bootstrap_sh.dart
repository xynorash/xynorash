import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/scripts/bootstrap.sh',
  lines: [
    cm(r'#', '──────────────────────────────────────────'),
    cm(r'#', r'scripts/bootstrap.sh'),
    cm(r'#', r'a fresh machine to the exact plugin commits in lazy-lock.json'),
    cm(r'#', r'install, put the lockfile back, restore, provision, then prove nothing moved'),
    cm(r'#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'first-run installer for the whole configuration (Linux and macOS)'),
    kv(r'language', r'bash, set -euo pipefail'),
    kv(r'size', r'73 lines, added 2026-10-13 (da1d829), two later touches (a3d33c8, fc2062a)'),
    kv(r'steps', r'1/3 Lazy! install · 2/3 Lazy! restore · 3/3 scripts/provision.lua'),
    kv(r'companion', r'scripts/bootstrap.ps1 on Windows, same three steps'),
    ...sec(r'why this file exists'),
    ...para(r'#', r'A Neovim configuration is more than its own files. This one pins every plugin to a commit in lazy-lock.json, and the point of a pin is that a second machine gets the same code as the first. The obvious way to bring up a fresh machine is nvim --headless with Lazy restore, and the obvious way does not work. The header of the script says why, and it is the most useful comment in the file, because it records how lazy.nvim behaves on an empty data directory.'),
    blank,
    ...para(r'#', r'On an empty data directory lazy installs in several rounds, since a plugin’s own specs are only read after it has been cloned. After every round lazy writes lazy-lock.json with only the plugins it knows so far. The pins of the plugins discovered in a later round are therefore dropped, those plugins land on their newest commit, and the lockfile in the checkout is rewritten. A pinned configuration would quietly stop being pinned on exactly the machine where pinning matters most, a fresh one.'),
    blank,
    ...code('bash', r'scripts/bootstrap.sh · lines 1-16', r'''
#!/usr/bin/env bash
# Bootstrap this config on a fresh machine (or an empty XDG data dir) so the
# plugins end up on exactly the commits in lazy-lock.json.
#
# Why two steps: a single `nvim --headless '+Lazy! restore' +qa` on an empty
# data dir installs in several rounds (a plugin's own specs are only read
# after it is cloned) and lazy rewrites lazy-lock.json after every round with
# the plugins it knows so far, which drops the pins of the ones discovered
# later; those land on their newest commit and the lockfile changes. So:
#   1. `Lazy! install` clones everything (the lockfile is rewritten, ignored);
#   2. the original lockfile is put back, then `Lazy! restore` checks out the
#      pinned commits of the now complete plugin set.
# lazy-lock.json is left exactly as it was; the script fails if it is not.
#
# Usage: scripts/bootstrap.sh          (config = the checkout this lives in)
# Env:   XDG_CONFIG_HOME / XDG_DATA_HOME / ... are honoured (fresh dirs work).
'''),
    ...sec(r'the two-step answer'),
    ...para(r'#', r'The script splits the work so that the information in the lockfile survives. Step one lets lazy clone everything and accepts that it will mangle the file. Step two puts the original back, and only then runs restore, which now sees the complete plugin set and the complete list of pins, and checks every plugin out at its pinned commit.'),
    blank,
    ...code('bash', r'scripts/bootstrap.sh · lines 52-64', r'''
orig=$(mktemp)
trap 'rm -f "$orig"' EXIT
cp "$lock" "$orig"

echo "bootstrap: step 1/3, Lazy! install"
nvim --headless '+Lazy! install' +qa
cp "$orig" "$lock"

echo "bootstrap: step 2/3, Lazy! restore"
nvim --headless '+Lazy! restore' +qa

echo "bootstrap: step 3/3, treesitter parsers and Mason tools (LazyVim downloads them lazily on a first start)"
nvim --headless "+luafile $repo/scripts/provision.lua" +qa
'''),
    ...para(r'#', r'The original is held in a temporary file made by mktemp and removed by an EXIT trap, so the copy is cleaned up whether the script finishes or fails. The lockfile in the checkout is the working copy that nvim reads and writes; the temporary file is the truth.'),
    blank,
    ...pt(r'#', r'cp "$orig" "$lock"', r'between the two steps this is the whole trick. It does not repair the lockfile, it replaces it with the bytes that were there at the start.'),
    ...pt(r'#', r'step 3', r'runs scripts/provision.lua inside a headless Neovim. Parsers and Mason tools are fetched lazily by LazyVim on a first start, which is the wrong time for them in an unattended install and in CI. See the page for provision.lua.'),
    ...sec(r'the verdict: the lockfile must not have changed'),
    ...code('bash', r'scripts/bootstrap.sh · lines 66-73', r'''
if cmp -s "$orig" "$lock"; then
  echo "bootstrap: done, lazy-lock.json unchanged."
else
  echo "bootstrap: lazy-lock.json changed during restore (some plugin is not on its pinned commit):" >&2
  diff "$orig" "$lock" >&2 || true
  cp "$orig" "$lock"
  exit 1
fi
'''),
    ...para(r'#', r'The last block is the check that makes the script an assertion and not only an installer. cmp -s compares the saved original with the lockfile after restore and provisioning. If they are identical the script says so and exits 0. If not, some plugin is not on its pinned commit, the script prints a diff to stderr, puts the original back so the checkout stays clean, and exits 1. Restoring before failing is a small courtesy: the caller sees the failure and the working tree is not left dirty.'),
    blank,
    ...sec(r'making sure the config being installed is this checkout'),
    ...code('bash', r'scripts/bootstrap.sh · lines 20-29', r'''
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
lock=$repo/lazy-lock.json

# nvim reads the config from $XDG_CONFIG_HOME/nvim; make sure that is us.
cfg=${XDG_CONFIG_HOME:-$HOME/.config}/nvim
if [ "$(readlink -f "$cfg" 2>/dev/null || true)" != "$(readlink -f "$repo")" ]; then
  echo "bootstrap: $cfg is not this checkout ($repo)." >&2
  echo "  link it first:  ln -s '$repo' '$cfg'" >&2
  exit 1
fi
'''),
    ...para(r'#', r'Neovim reads its configuration from $XDG_CONFIG_HOME/nvim, falling back to ~/.config/nvim. The script resolves both that directory and its own repository with readlink -f and compares them. If they differ it stops and prints the command to fix it, ln -s of the checkout to the config path. The reason is concrete: running headless nvim would otherwise bootstrap whatever configuration lives there, not the one in this repository, and the final lockfile comparison would be comparing the wrong things. The script refuses to link it for you; it only prints the command.'),
    blank,
    ...para(r'#', r'The XDG variables are honoured throughout, which is also what lets the test and CI jobs use fresh directories (the header says so: fresh dirs work).'),
    blank,
    ...sec(r'prerequisites'),
    ...code('bash', r'scripts/bootstrap.sh · lines 31-50', r'''
# Prerequisites. Required to bring the config up and to build/run what Mason
# and the Rust workflow need: git/curl/tar/unzip/gzip (lazy, Mason downloads), gcc
# (treesitter parsers, blink.cmp fallback), node/npm (Mason's markdownlint-cli2,
# markdown-toc, yaml-language-server), cargo/rustup/rust-analyzer (Rust).
if [ "${BOOTSTRAP_SKIP_PREREQS:-}" != 1 ]; then
  missing=()
  for tool in nvim git curl tar unzip gzip gcc npm node cargo rustup rust-analyzer; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  # rustup ships a rust-analyzer proxy even when the component is absent.
  if command -v rust-analyzer >/dev/null 2>&1 && ! rust-analyzer --version >/dev/null 2>&1; then
    missing+=("rust-analyzer (installed as a rustup proxy only: rustup component add rust-analyzer)")
  fi
  if [ ${#missing[@]} -gt 0 ]; then
    echo "bootstrap: missing prerequisites:" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    echo "Install them (or set BOOTSTRAP_SKIP_PREREQS=1 to go on anyway) and rerun." >&2
    exit 1
  fi
fi
'''),
    ...para(r'#', r'The list is the set of programs that something later will need: git, curl, tar, unzip and gzip for lazy and Mason downloads, gcc for treesitter parsers and the blink.cmp fallback, node and npm for the Mason packages written in JavaScript (markdownlint-cli2, markdown-toc, yaml-language-server), and cargo, rustup and rust-analyzer for the Rust workflow the config exists to serve. All missing tools are collected into an array and printed together, so one run tells you everything you have to install, not the first thing.'),
    blank,
    ...para(r'#', r'There is one subtle check. rustup installs a proxy named rust-analyzer even when the component is not installed, so command -v succeeds on a machine that cannot actually run it. The script therefore also runs rust-analyzer --version and reports a rustup proxy only, with the fix, rustup component add rust-analyzer. Setting BOOTSTRAP_SKIP_PREREQS=1 skips the whole block for machines where the check is wrong or the person knows better.'),
    blank,
    ...sec(r'design decisions and trade-offs'),
    ...pt(r'#', r'fail early and loudly', r'set -euo pipefail, an explicit exit 1 on every refusal, messages to stderr. A bootstrap that half-succeeds is worse than one that stops.'),
    ...pt(r'#', r'assert the invariant, not the steps', r'the exit status depends on the lockfile being byte-identical at the end, not on nvim exiting 0. That is the property the whole script is for.'),
    ...pt(r'#', r'no network logic of its own', r'everything that touches the network happens inside Neovim (lazy, Mason, treesitter). The script only orders those steps and guards the lockfile.'),
    ...sec(r'how it is exercised'),
    ...para(r'#', r'CI runs it as the install step before the suite (see the page for .github/workflows/ci.yml), on a clean runner. The commit that fixed the first clean-machine failures, fc2062a (2026-10-14), is the one that added step three; its message says bootstrap now provisions parsers and Mason tools so the suite passes on a clean machine. platforms.yml runs this same file on macOS and scripts/bootstrap.ps1 on Windows.'),
    blank,
    ...sec(r'history'),
    ...pt(r'#', r'da1d829 2026-10-13', r'the script is added, with the CI lockfile check and a health check for prerequisites. The commit title names it: bootstrap script with two-step lockfile restore.'),
    ...pt(r'#', r'a3d33c8 2026-10-13', r'the final loop round adds gzip to the prerequisite list, in both the comment and the for loop (the comment groups it with the lazy and Mason downloads).'),
    ...pt(r'#', r'fc2062a 2026-10-14', r'CI made to pass on a clean machine: bootstrap provisions parsers and Mason tools (step 3/3).'),
    ...pt(r'#', r'ff1c8fa 2026-10-16', r'Windows and macOS portability work. This file is not in that commit’s changes; the PowerShell twin scripts/bootstrap.ps1 is added by it.'),
  ],
);
