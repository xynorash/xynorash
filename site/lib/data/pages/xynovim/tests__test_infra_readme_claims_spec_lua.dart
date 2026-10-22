import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/test-infra-readme-claims_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'test-infra-readme-claims_spec.lua — the test suite tests itself, and the README that describes it'),
    cm('--', r'a throwaway checkout with throwaway specs run through the real scripts/test.sh, then every claim the documents make'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for scripts/test.sh, scripts/coverage.lua, the four tests/*.lua infrastructure files, the Makefile, and the claims of README.md and CHANGELOG.md'),
    kv(r'language', r'Lua spec, 1853 lines, 112 it() blocks, 4 pending, 32 describe() blocks'),
    kv(r'platform', r'Linux only (it runs scripts/test.sh, which needs GNU timeout and process groups)'),
    kv(r'history', r'9 commits, 2026-10-13 to 2026-10-22'),
    ...sec(r'why this file exists'),
    ...para('--', r'A test suite is software, and its failures should be as trustworthy as its passes. This spec has two jobs. The first is to run scripts/test.sh against a fake checkout with specs written for the purpose: one passes, one fails, one hangs, one crashes, one errors on load, one skips. It then asserts what the output and the exit status say. The second is to compare what the README and CHANGELOG say with what the repository does: every flag, every path, every number that can be computed. The header describes the mechanism: the fake repo is made of symlinks to the real lua, colors and other directories plus copies of the scripts, tests helpers, lock and extras files, so nothing the nested runs do can write into the real checkout; runs are memoised and each test asserts one claim; the hanging spec is killed after --timeout 30.'),
    ...code('lua', r'tests/test-infra-readme-claims_spec.lua · lines 1-11', r'''
-- The test infrastructure itself (scripts/test.sh, scripts/coverage.lua,
-- tests/{harness,helpers,runner,coverage_hook}.lua, Makefile) and the claims
-- README.md / CHANGELOG.md make about it and about the config.
--
-- scripts/test.sh is exercised for real: a throwaway checkout ("fake repo":
-- symlinks to the real lua/, colors/, ... plus COPIES of the scripts, tests
-- helpers, lazy-lock.json and lazyvim.json, so nothing here can write into the
-- real checkout) gets throwaway specs, and test.sh is run against it. Runs are
-- memoised, each `it` asserts one claim of the output. The hanging spec is
-- killed after --timeout 30.
-- xyno-os: linux (runs scripts/test.sh, which needs GNU timeout and process groups)'''),
    ...sec(r'the option handling'),
    ...para('--', r'--list prints every tests/*_spec.lua and runs nothing, and works without nvim and plugins; a pattern keeps only paths containing it, several patterns mean any; no match exits 2 with no spec file matches; an unknown option exits 2; -h and --help print the header usage and exit 0; --timeout without a value fails with a message. Setup errors exit 2 as well: nvim not found, and no plugins in XDG_DATA_HOME with the bootstrap hint.'),
    ...sec(r'a full run on throwaway specs'),
    ...para('--', r'The banner shows the spec count and the timeout, and --timeout beats TEST_TIMEOUT. A run fails (exit 1) if any file fails, times out or crashes. The hang test is the proof of the guard: a spec with a busy loop is reported TIMEOUT and the suite goes on. The test requires the status, zero passed and one failed, the text (TIMEOUT, exit followed by a code matching 1[23][47]; last output), the comment says the busy loop ignores TERM and is killed by -k, and later files still run. Then it reads a pid file the spec wrote and waits for that process to be dead.'),
    ...code('lua', r'tests/test-infra-readme-claims_spec.lua · lines 428-442', r'''
  it("a spec that hangs (busy loop) is reported TIMEOUT and the suite goes on", function()
    local r = run_a()
    local row = H.ok(r.rows["a_hang_spec.lua"], "no result row for the hanging spec:\n" .. r.out)
    H.eq("TIMEOUT", row.status)
    H.eq(0, row.passed)
    H.eq(1, row.failed)
    H.match(r.out, "%(TIMEOUT, exit 1[23][47]; last output%)", false, "busy loop ignores TERM: killed by -k")
    -- later files still ran
    H.eq("PASS", r.rows["d_pass_spec.lua"].status)
    H.eq("PASS", r.rows["i_iso_spec.lua"].status)
    -- the hung nvim is really gone
    local pid = tonumber(vim.trim(read(r.dump .. "/hang.pid")))
    H.ok(pid)
    H.ok(wait_dead(pid), "hung nvim " .. pid .. " still alive")
  end)'''),
    ...para('--', r'Other statuses: a failing assertion is FAIL with a trimmed traceback echoed; an error at load time is FAIL loading; skip_file at load time is a PASS with 1 skipped and its reason echoed; skip(reason) and pending count as skipped with their reasons; and a process that dies without a result line is CRASH with its exit code. Every row has the documented shape and the total adds up; the failed files are listed on one line in run order; a changed lockfile gives a warning.'),
    ...sec(r'cleaning up after tests'),
    ...para('--', r'test.sh signals the process group of every nvim, so a background sleep started by a spec dies with the run, and it kills tmux servers named by the prefix xynotest-<pid>-. The test reads the pid of the sleep process and waits for it to die; if a tmux socket was recorded it must have the expected prefix and the server must be gone.'),
    ...code('lua', r'tests/test-infra-readme-claims_spec.lua · lines 544-556', r'''
  it("signals the process group of every nvim and kills tmux servers named xynotest-<pid>-*", function()
    local r = run_a()
    local pid = tonumber(vim.trim(read(r.dump .. "/sleep.pid")))
    H.ok(pid)
    H.ok(wait_dead(pid), "background sleep " .. pid .. " of a spec survived the run")
    if exists(r.dump .. "/tmux.sock") then
      local sock = vim.trim(read(r.dump .. "/tmux.sock"))
      H.eq("xynotest-" .. r.pid .. "-raw", sock, "prefix is xynotest-<pid of test.sh>")
      local t = sh({ "tmux", "-L", sock, "list-sessions" })
      rm_socket(sock)
      H.not_ok(t.code == 0, "tmux server " .. sock .. " still running")
    end
  end)'''),
    ...sec(r'isolation, measured'),
    ...para('--', r'A spec writes its environment to JSON. The test then requires that XDG config, state and cache and TMPDIR are in a temp work directory named xynotest.<something>, that XDG_CONFIG_HOME/nvim links to the checkout, that XDG_DATA_HOME is the real one (plugins are not reinstalled), that stdpath values follow, that the tmux prefix names the pid of test.sh, that shada and the LSP log were written in the temp state and not in the real one, and that H.tmpdir lives under the temp TMPDIR. The isolation promised in the header of scripts/test.sh is thereby verified, not repeated.'),
    ...code('lua', r'tests/test-infra-readme-claims_spec.lua · lines 558-584', r'''
  it("isolates XDG_CONFIG/STATE/CACHE_HOME and TMPDIR in a temp work dir, keeps XDG_DATA_HOME real", function()
    local r = run_a()
    H.eq("PASS", r.rows["i_iso_spec.lua"].status)
    local d = vim.json.decode(read(r.dump .. "/iso.json"))
    local e, std = d.env, d.std
    local work = vim.fs.dirname(e.XDG_STATE_HOME)
    H.match(vim.fs.basename(work), "^xynotest%.")
    H.eq(work .. "/config", e.XDG_CONFIG_HOME)
    H.eq(work .. "/state", e.XDG_STATE_HOME)
    H.eq(work .. "/cache", e.XDG_CACHE_HOME)
    H.eq(work .. "/tmp", e.TMPDIR)
    H.eq(work .. "/tmp", e.XYNO_TEST_TMP)
    H.eq(r.fake, d.link, "XDG_CONFIG_HOME/nvim links to the checkout")
    H.eq(vim.env.XDG_DATA_HOME or (vim.env.HOME .. "/.local/share"), e.XDG_DATA_HOME, "data stays the real one")
    H.eq(e.XDG_DATA_HOME .. "/nvim", std.data)
    H.eq(work .. "/config/nvim", std.config)
    H.eq(work .. "/state/nvim", std.state)
    H.eq(work .. "/cache/nvim", std.cache)
    H.eq("xynotest-" .. r.pid, e.XYNO_TMUX_PREFIX)
    H.eq(r.fake .. "/tests/i_iso_spec.lua", e.XYNO_SPEC)
    -- state written by the spec (shada, lsp.log location) is inside the work dir
    H.eq(1, d.shada, "shada was written in the temp state dir")
    H.eq(work .. "/state/nvim/", d.lsplog:sub(1, #work + 12))
    H.eq(work .. "/tmp/", d.tmpdir:sub(1, #work + 5), "H.tmpdir() lives in the temp TMPDIR")
    local real_state = (vim.env.HOME or "") .. "/.local/state/nvim"
    H.not_ok(d.lsplog:sub(1, #real_state) == real_state)
  end)'''),
    ...sec(r'coverage tooling'),
    ...para('--', r'The hook writes the JSON dump with repo-relative keys and executed lines; test files and other directories are not in the roots; the classifier names exactly lua, colors, plugin and after, which the test checks by looking for the literal source line and for the absence of a tests pattern; scripts/coverage.lua merges dumps, estimates the denominator by excluding comments, blanks and closers, and prints usage with exit 2 without arguments; and the per-file report adds up to a TOTAL.'),
    ...code('lua', r'tests/test-infra-readme-claims_spec.lua · lines 699-703', r'''
  it("the hook's classifier names exactly those four directories", function()
    local src = read(repo .. "/tests/coverage_hook.lua")
    H.match(src, 'rel:match("^lua/") or rel:match("^colors/") or rel:match("^plugin/") or rel:match("^after/")', true)
    H.no_match(src, 'match("^tests/")', true)
  end)'''),
    ...sec(r'harness and helpers, once more'),
    ...para('--', r'The harness is tested by running throwaway specs: hooks run outer first and inner last; ok, FAIL and SKIP lines use names joined with a greater-than sign, counts, and indented failure detail; after_each runs after a failing test and a failing after_each fails a passing test; the globals exist after install; a describe that errors while registering raises with the group name. The runner ends with XYNO_RESULT and exits 1 on failures, and registers the helpers as xynotest.helpers, not tests.helpers. The helpers have every documented function.'),
    ...sec(r'the Rust probes'),
    ...para('--', r'XYNO_TEST_SKIP_RUST=1 makes rust_available false and need_rust skip with that reason; need_rust skips when rust-analyzer --version fails (the rustup proxy) or cargo is missing; and the real rust_spec skips with three skips under the switch.'),
    ...sec(r'claims that are numbers'),
    ...para('--', r'The existing-specs test runs smoke, harness, routes and rust with test.sh and compares the counts: smoke 6, harness 8, routes 1, and rust 3 (passed or skipped, rerun once alone under heavy load). It reads CHANGELOG.md and requires the text 18 passed on this machine, and checks that the figure is the sum of the four, 6 + 8 + 1 + 3. The README section checks: it documents every flag test.sh implements and test.sh implements each documented flag; the quiet default and the verbose output are compared line by line; the exit statuses 0, 1 and 2 are the ones used; every spec file the README lists exists; every fixture named exists; the isolation claims match; and the CI job runs bootstrap, then test.sh, then the lockfile check.'),
    ...code('lua', r'tests/test-infra-readme-claims_spec.lua · lines 1307-1323', r'''
  it("documents every flag test.sh implements, and test.sh implements each documented flag", function()
    local script = read(repo .. "/scripts/test.sh")
    for _, flag in ipairs({ "--list", "--coverage", "--timeout", "-v" }) do
      H.match(sec, flag, true, "README mentions " .. flag)
      H.match(script, flag, true, "test.sh handles " .. flag)
    end
    H.match(sec, "$TEST_TIMEOUT", true)
    H.match(script, "TEST_TIMEOUT", true)
    H.match(sec, "default 120 s", true)
    H.match(script, "timeout_s=${TEST_TIMEOUT:-120}", true)
    -- -v / --verbose really prints the whole log of every file
    local v = run_real({}, { "/routes_spec", "-v" })
    H.match(v.out, "    | ok   rust_routes.scan_source", true)
    H.match(v.out, "    | XYNO_RESULT passed=1 failed=0 skipped=0", true)
    local q = run_real({}, { "/routes_spec" })
    H.no_match(q.out, "    | ", true, "quiet by default")
  end)'''),
    ...sec(r'claims about the repository'),
    ...para('--', r'Every directory and file in the README layout block exists, file names inside layout lines exist in their directory, every file path the README names resolves, and no backticked repo path points to a missing file (placeholders and removed files excepted). The commands :checkhealth xynovim, :Mason, :Lazy and :LazyExtras exist. The README statement N of M plugins loaded has M equal to the installed plugin count, which equals the number of lazy-lock.json entries.'),
    ...code('lua', r'tests/test-infra-readme-claims_spec.lua · lines 1501-1516', r'''
describe("README mechanical numeric claims", function()
  it("'N of M plugins loaded' matches the plugin count; lazy-lock.json has an entry per plugin", function()
    local C = require("lazy.core.config")
    local actual = 0
    for _ in pairs(C.plugins) do
      actual = actual + 1
    end
    local lock = vim.json.decode(read(repo .. "/lazy-lock.json"))
    local nlock = vim.tbl_count(lock)
    H.eq(actual, require("lazy").stats().count)
    H.eq(actual, nlock, "plugins vs lazy-lock.json entries")
    local loaded, total = readme:match("(%d+) of (%d+) plugins loaded")
    H.ok(loaded, "README states 'N of M plugins loaded'")
    H.ok(tonumber(loaded) < actual)
    H.eq(actual, tonumber(total), "README plugin count vs the installed plugin count")
  end)'''),
    ...sec(r'colours from an independent parser'),
    ...para('--', r'One test rebuilds a JetBrains .icls file from the committed palette, parses it with a small Python script (a separate implementation that resolves baseAttributes chains), and compares at least 35 group colours and italics with what the loaded scheme really defines. The converter that writes the palette and the check that reads it are two different programs.'),
    ...sec(r'the changelog and a removed feature'),
    ...para('--', r'The CHANGELOG starts with [Unreleased] holding Added (test infra) and Removed (Omarchy), lists 1.8.0 down to 0.1.0 with descending versions, has 1.8.0 as the latest release dated 2026-10-13, and mentions Omarchy only in the Removed section and in older entries. The Omarchy removal block checks that the plugin files are gone, that no code reads the omarchy variables or the follow flag, and that the README mentions it nowhere as a feature.'),
    ...code('lua', r'tests/test-infra-readme-claims_spec.lua · lines 1751-1758', r'''
  it("'Omarchy' appears only in the Removed section and in entries older than 1.8.0 or in 1.8.0's history", function()
    local unreleased = changelog:match("\n## %[Unreleased%]\n(.-)\n## %[1%.8%.0%]")
    local before_removed = unreleased:match("^(.-)### Removed")
    H.no_match(before_removed:lower(), "omarchy", true)
    -- historical entries keep their wording
    H.match(changelog:lower(), "omarchy", true)
  end)
end)'''),
    ...sec(r'repo hygiene'),
    ...para('--', r'No tracked file is owned by root (a leftover of running something under sudo); no .DS_Store, log files or editor leftovers; tests/fixtures and the infrastructure are committed; scripts are executable and pass bash -n; and the suite, including its nested runs, left lazy-lock.json and the fixtures unchanged.'),
    ...code('lua', r'tests/test-infra-readme-claims_spec.lua · lines 1805-1816', r'''
  it("no tracked file is owned by root", function()
    local r = git("ls-files", "-z")
    H.eq(0, r.code, r.out)
    local root_owned = {}
    for f in r.stdout:gmatch("([^%z]+)") do
      local st = uv.fs_lstat(repo .. "/" .. f)
      if st and st.uid == 0 then
        root_owned[#root_owned + 1] = f
      end
    end
    H.eq({}, root_owned)
  end)'''),
    ...sec(r'trade-offs'),
    blank,
    ...pt('--', r'Slow and thorough', r'nested test.sh runs make this one of the slowest files, but it is the only place where the exit codes, the timeout kill and the isolation are checked.'),
    ...pt('--', r'Documentation is under test', r'that a README can fail a build is a deliberate choice. site_spec.lua extends it to the website.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created with the 22-spec suite. 98c9bb4, a3d33c8 :: field test rounds.'),
    ...pt('--', r'fc2062a, 0b0eee8, b9363cd (2026-10-14)', r'CI, README showcase and the macros work added their claims.'),
    ...pt('--', r'94ff2dc, ff1c8fa (2026-10-16)', r'website and platform work. 0da94f4 (2026-10-22) :: removal of tools/Dark.icls, "keep only the generated palette".'),
  ],
);
