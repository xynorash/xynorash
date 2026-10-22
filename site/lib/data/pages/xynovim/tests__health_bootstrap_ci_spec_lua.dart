import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/health-bootstrap-ci_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'health-bootstrap-ci_spec.lua — the setup scripts, the CI file and the prerequisites list are code, so they get tests'),
    cm('--', r'stub executables on a fake PATH, a stub nvim for bootstrap.sh, a stub smoke step, and pins checked by regex'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/xynovim/health.lua, scripts/bootstrap.sh, .github/workflows/ci.yml, Makefile, stylua.toml, .gitignore, LICENSE and the README prerequisite lists'),
    kv(r'language', r'Lua spec, 1013 lines, 62 it() blocks, 18 describe() blocks'),
    kv(r'platform', r'Linux and macOS (an xyno-os header: sh stubs and scripts/bootstrap.sh)'),
    kv(r'network', r'one test needs a real fresh install and runs only with XYNO_TEST_NETWORK=1'),
    kv(r'history', r'10 commits, 2026-10-13 to 2026-10-22'),
    ...sec(r'why this file exists'),
    ...para('--', r'Most of what keeps a configuration usable on a second machine is not in the editor: the health check that says what is missing, the bootstrap that installs plugins from the lockfile, the CI workflow that proves it. Those pieces are code, with the same ability to rot as any other, and they are the pieces nobody runs often. The header lists them. The strategy: health.check() is unit-tested with vim.health stubbed and a PATH of stub executables, bootstrap.sh runs in a temp checkout with a stub nvim, and only the one test that needs a network is opt-in.'),
    ...code('lua', r'tests/health-bootstrap-ci_spec.lua · lines 1-5', r'''
-- :checkhealth xynovim (lua/xynovim/health.lua), scripts/bootstrap.sh, the CI workflow,
-- Makefile, stylua.toml, .gitignore, LICENSE and the README prerequisite lists.
-- health.check() is unit-tested with vim.health stubbed and a fake PATH of stub
-- executables; bootstrap.sh runs in a temp "checkout" with a stub nvim. The one
-- test that needs the network (a real fresh install) runs only with XYNO_TEST_NETWORK=1.'''),
    ...sec(r'the health check on a fake PATH'),
    ...para('--', r'run_check calls the real health module with a recording replacement for vim.health and a directory of stub executables as the PATH. The stubs are shell scripts, so a test can make a tool missing, present, noisy or broken at will. The test of the table says that there are 23 entries and that each has the documented severity (some tools are errors if missing, the rest warnings). A missing tool is reported as <bin> not found: purpose with a hint; a found tool as name (PATH) first line of --version: purpose, with the line cut at 80 characters, falling back to stderr when stdout is empty; the Mason tools bacon-ls, codelldb and taplo are looked up in Mason’s bin first and a tool found only there counts only for those.'),
    ...code('lua', r'tests/health-bootstrap-ci_spec.lua · lines 137-144', r'''
  it("has 23 entries with the documented severities", function()
    local tools = section(rec, "xynovim: external tools")
    H.eq(23, #tools)
    for _, bin in ipairs(HEALTH_BINS) do
      local r = H.ok(rec_for(rec, bin), "no record for " .. bin)
      H.eq(ERRORS[bin] and "error" or "warn", r.kind, bin .. " severity")
    end
  end)'''),
    ...sec(r'the rustup proxy trap'),
    ...para('--', r'rustup installs a rust-analyzer executable even when the component is not installed. It exists on PATH but exits with an error, so a naive which says the tool is there. The health test makes the stub print component not installed and exit 1, then requires an error, a message that begins with rust-analyzer found (PATH: ...) but --version fails, and the advice rustup component add rust-analyzer. The same rule appears in helpers.rust_available and in bootstrap.sh.'),
    ...code('lua', r'tests/health-bootstrap-ci_spec.lua · lines 254-260', r'''
  it("a rustup-style rust-analyzer proxy (version fails) is an error with the rustup advice", function()
    local rec = run_check(stubdir(all_stubs({ ["rust-analyzer"] = "echo 'error: component not installed' >&2\nexit 1\n" })))
    local r = rec_for(rec, "rust-analyzer")
    H.eq("error", r.kind)
    H.match(r.msg, "^rust%-analyzer found %(PATH: .*/rust%-analyzer%) but `%-%-version` fails: language server")
    H.eq("rustup component add rust-analyzer", r.advice)
  end)'''),
    ...sec(r'nothing but nvim, git and timeout'),
    ...para('--', r'The minimal PATH test links only git, timeout and nvim into a directory and runs the check. Every other tool must be reported missing, git must be ok, and the rust toolchain section must contain one warning, rustup not found, with the advice components cannot be checked; install rustup, returning early instead of failing. Another group asks rustup for the stable toolchain components, warns with the rustup command for each missing one (clippy, llvm-tools), checks the wasm32-unknown-unknown target, and warns stable toolchain not installed when rustup fails.'),
    ...code('lua', r'tests/health-bootstrap-ci_spec.lua · lines 273-292', r'''
  it("with only nvim, git and timeout everything else is missing and rustup warns, returning early", function()
    local dir = H.tmpdir() .. "/min"
    vim.fn.mkdir(dir, "p")
    for _, b in ipairs({ "git", "timeout" }) do
      vim.uv.fs_symlink(vim.fn.exepath(b), dir .. "/" .. b)
    end
    vim.uv.fs_symlink(vim.v.progpath, dir .. "/nvim")
    local rec = run_check(dir)
    H.eq("ok", rec_for(rec, "git").kind)
    for _, b in ipairs(HEALTH_BINS) do
      if b ~= "git" then
        H.match(rec_for(rec, b).msg, "^" .. vim.pesc(b) .. " not found: ", false, b)
      end
    end
    local tc = section(rec, "xynovim: rust toolchain")
    H.eq(1, #tc)
    H.eq("warn", tc[1].kind)
    H.eq("rustup not found", tc[1].msg)
    H.eq("components cannot be checked; install rustup", tc[1].advice)
  end)'''),
    ...sec(r'bootstrap.sh in a temp checkout'),
    ...para('--', r'mkcheckout builds a throwaway checkout, a config directory and a stub nvim whose behaviour is switched by environment variables (FAKE_INSTALL, FAKE_RESTORE) and which logs its calls. The checks: the script is executable, uses strict mode and parses with bash -n; shellcheck finds nothing when installed; paths are quoted and no bare rm -rf, with a trap that removes the temp copy. If nvim is not linked to the checkout the script exits 1, naming the config directory and printing the ln -s hint, and the stub log is empty: nvim must not run. It falls back to ~/.config/nvim when XDG_CONFIG_HOME is unset, and accepts a config that is the checkout itself.'),
    ...code('lua', r'tests/health-bootstrap-ci_spec.lua · lines 450-460', r'''
  it("exits 1 naming the config dir and prints the ln -s hint when nvim is not linked to the checkout", function()
    local c = mkcheckout({ nolink = true })
    local other = c.root .. "/other"
    vim.fn.mkdir(other, "p")
    vim.uv.fs_symlink(other, c.root .. "/cfg/nvim")
    local r = c:run({ BOOTSTRAP_SKIP_PREREQS = "1" })
    H.eq(1, r.code)
    H.has(r.stderr, ("bootstrap: %s/cfg/nvim is not this checkout (%s)."):format(c.root, c.ck))
    H.has(r.stderr, ("ln -s '%s' '%s/cfg/nvim'"):format(c.ck, c.root))
    H.eq({}, log_lines(c), "nvim must not run")
  end)'''),
    ...sec(r'two-step restore'),
    ...para('--', r'Plugin installation happens in two steps, install then restore, with the original lockfile put back between them so that restore sees what the lockfile says. If the lockfile changed after restore, some plugin is not on its pinned commit. The test makes the stub change it, runs the script and requires exit 1, the message lazy-lock.json changed during restore (some plugin is not on its pinned commit):, a diff with the old and new commit lines, no done message, and the original lockfile content back on disk. The follow-up tests check that the temp copy is removed on success and on failure, also when a step fails under set -e.'),
    ...code('lua', r'tests/health-bootstrap-ci_spec.lua · lines 575-584', r'''
  it("a changed lockfile after restore: prints the diff, puts the original back and exits 1", function()
    local c = mkcheckout()
    local r = c:run({ BOOTSTRAP_SKIP_PREREQS = "1", FAKE_INSTALL = "1", FAKE_RESTORE = "1" })
    H.eq(1, r.code)
    H.has(r.stderr, "bootstrap: lazy-lock.json changed during restore (some plugin is not on its pinned commit):")
    H.has(r.stderr, '< {"a": {"commit": "1111"}}')
    H.has(r.stderr, '> {"a": {"commit": "2222"}}')
    H.no_match(r.stdout, "done, lazy-lock.json unchanged", true)
    H.eq(LOCK_ORIG, table.concat(vim.fn.readfile(c.lock), "\n") .. "\n")
  end)'''),
    ...sec(r'prerequisites'),
    ...para('--', r'Bootstrap checks twelve programs (nvim, git, curl, tar, unzip, gzip, gcc, npm, node, cargo, rustup and rust-analyzer), lists every missing one and exits 1 before touching nvim, reports a rust-analyzer that is only a rustup proxy, and BOOTSTRAP_SKIP_PREREQS=1 skips the check. The same switch appears in the PowerShell twin (see scripts-portable_spec.lua).'),
    ...sec(r'the CI file'),
    ...para('--', r'ci.yml is parsed as text. It is named ci, triggers on push to main and pull requests, has read-only contents permission and one job named smoke on ubuntu-latest with a 40 minute timeout (commit dc846f6 set it). Every third-party action must be pinned to a full 40-character commit hash: the test collects all uses: references and checks both the shape and the length. checkout has persist-credentials false. The steps run in a documented order. The startup smoke step is extracted and run with a stub: a quiet, fast nvim passes and prints headless startup: N ms; any stderr output fails and is shown; and a startup over 3000 ms fails with startup slower than 3000 ms. YAML must parse, and actionlint and zizmor must be clean when installed.'),
    ...code('lua', r'tests/health-bootstrap-ci_spec.lua · lines 702-710, 759-776', r'''
  it("has no unpinned third-party action", function()
    local n = 0
    for ref in ci:gmatch("uses:%s*([^%s#]+)") do
      n = n + 1
      H.match(ref, "^[%w_.-]+/[%w_./-]+@%x+$")
      H.eq(40, #ref:match("@(%x+)$"), ref .. " must be pinned to a full commit hash")
    end
    H.ok(n >= 1)
  end)
...
    it("passes for a quiet, fast nvim", function()
      local r = run_smoke("exit 0\n")
      H.eq(0, r.code, r.stdout .. r.stderr)
      H.match(r.stdout, "headless startup: %d+ ms")
    end)

    it("fails on any stderr output, and shows it", function()
      local r = run_smoke("echo 'E5108: Lua error boom' >&2\nexit 0\n")
      H.eq(1, r.code)
      H.has(r.stdout, "E5108: Lua error boom")
    end)

    it("fails when startup takes more than 3000 ms", function()
      local r = run_smoke("sleep 3.2\nexit 0\n")
      H.eq(1, r.code)
      H.has(r.stdout, "startup slower than 3000 ms")
    end)
  end)'''),
    ...sec(r'the small files'),
    ...para('--', r'The Makefile declares test and coverage as PHONY, test runs scripts/test.sh $(ARGS), coverage adds --coverage, and make -n expands to the script calls with ARGS. stylua.toml is spaces, width 2, column 120, and stylua --check lua/ uses it with style drift informational only. .gitignore ignores tt.*, .tests, doc/tags, debug, .repro, foo.*, *.log and data (also at any depth), and does not ignore ordinary files. The LICENSE test checks four anchor phrases of the Apache License 2.0, which matches commit 724c508 (2026-10-22), "Keep xynovim itself under Apache-2.0 (MIT is for the xyno-* plugins)".'),
    ...code('lua', r'tests/health-bootstrap-ci_spec.lua · lines 899-906', r'''
  it("LICENSE is the Apache License 2.0", function()
    local l = read("LICENSE")
    H.has(l, "Apache License\n")
    H.has(l, "Version 2.0, January 2004")
    H.has(l, "http://www.apache.org/licenses/")
    H.has(l, "TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION")
  end)
end)'''),
    ...sec(r'README against reality'),
    ...para('--', r'The last blocks compare the README prerequisite bullets with the health tool table and with bootstrap: every tool the README names is checked by health or by bootstrap, or explained; wgsl-analyzer and cargo-expand are checked by :checkhealth. lazy.lua is checked for the checker and luarocks being off, island-dark as the install colourscheme, and cloning lazy.nvim stable from the official repository when it is missing.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created. 98c9bb4, a3d33c8, 25086fd :: field test rounds.'),
    ...pt('--', r'fc2062a, dc846f6 (2026-10-14)', r'CI on a clean machine, 40 minute timeout.'),
    ...pt('--', r'ff1c8fa, 9641d08 (2026-10-16)', r'Windows and macOS, so this file became Linux and macOS only.'),
    ...pt('--', r'536e5cc, 724c508 (2026-10-22)', r'voice review and the Apache-2.0 licence line.'),
  ],
);
