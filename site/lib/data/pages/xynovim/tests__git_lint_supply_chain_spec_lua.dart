import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/git-lint-supply-chain_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'git-lint-supply-chain_spec.lua — parsers for cargo-deny and cargo-machete, tested on canned output'),
    cm('--', r'diffview base selection, gitsigns on untracked files, and linters that audit dependencies and workflows'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/plugins/diffview.lua, gitsigns.lua and supply-chain.lua (nvim-lint sources cargo-deny, cargo-machete, actionlint, zizmor)'),
    kv(r'language', r'Lua spec, 937 lines, 43 it() blocks, 2 pending, 13 describe() blocks'),
    kv(r'method', r'parser and condition units use canned tool output and need no tool; integration tests skip when the tool or the cached advisory database is missing'),
    kv(r'neighbour', r'coverage.lua is covered by dap-neotest-coverage_spec.lua'),
    kv(r'history', r'6 commits, 2026-10-13 to 2026-10-21'),
    ...sec(r'why this file exists'),
    ...para('--', r'A supply-chain linter has two halves. One half runs an external tool and cannot be tested without it. The other half turns its output into editor diagnostics and decides whether to run at all. This spec concentrates on the second half, where most of the bugs are, using canned output, and keeps real runs as a small, skippable layer. The header says which parts live outside the repository (global git config for mergiraf, delta, zdiff3, rerere and the dft and dlog aliases) and are not testable here, and the pending entries at the end repeat that.'),
    ...code('lua', r'tests/git-lint-supply-chain_spec.lua · lines 1-7', r'''
-- lua/plugins/diffview.lua, gitsigns.lua, supply-chain.lua (nvim-lint sources:
-- cargo-deny, cargo-machete, actionlint, zizmor). coverage.lua is covered by
-- dap-neotest-coverage_spec.lua. Parser/condition units use canned output and
-- need no tool; the integration tests skip when the tool (or the cached
-- advisory DB) is missing. Global git config (mergiraf, delta, zdiff3, rerere,
-- dft/dlog aliases) and the README per-repo opt-ins live outside the repo and
-- are not testable here (see the pending tests at the end).'''),
    ...sec(r'choosing the diff base'),
    ...para('--', r'leader g V opens a diff against the base branch. The base is chosen among remote refs and the tests state the order: origin/HEAD wins over origin/main and origin/master; origin/main over origin/master; origin/master when it is the only one; outside a git repository a WARN says not a git repository and not no origin; and without any origin ref one WARN, no DiffviewOpen and no git error. The first test builds a scratch repository with refs for main and master, points origin/HEAD at master with symbolic-ref, presses the key through a recorder and requires the command DiffviewOpen origin/HEAD...HEAD, so it was origin/HEAD that decided, not the name main.'),
    ...code('lua', r'tests/git-lint-supply-chain_spec.lua · lines 123-131', r'''
    it("origin/HEAD wins over origin/main and origin/master", function()
      local dir = scratch_repo()
      for _, r in ipairs({ "main", "master" }) do
        H.git(dir, "update-ref", "refs/remotes/origin/" .. r, "HEAD")
      end
      H.git(dir, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/master")
      local cmds = press()
      H.eq({ "DiffviewOpen origin/HEAD...HEAD" }, cmds)
    end)'''),
    ...sec(r'gitsigns and files git does not know'),
    ...para('--', r'A new file in a repository without commits gets no signs by default. The plugin opts set attach_to_untracked to true, and a test creates an untracked file in a repo without commits and requires three signs, and zero without the override. This is the kind of option that is easy to lose in a refactor and impossible to notice by eye.'),
    ...sec(r'where the workflow linters may run'),
    ...para('--', r'actionlint and zizmor understand only GitHub workflow files. The condition test asks for each linter whether it runs for a set of file names: yes for /p/.github/workflows/ci.yml and nested yaml files; no for /p/ci.yml, docker-compose.yaml, /p/.github/dependabot.yml and /p/github/workflows/ci.yml. The last case shows that the match is on the dotted directory, not on a path that merely looks similar.'),
    ...code('lua', r'tests/git-lint-supply-chain_spec.lua · lines 231-246', r'''
describe("actionlint / zizmor condition", function()
  for _, name in ipairs({ "actionlint", "zizmor" }) do
    it(name .. " only runs under /.github/workflows/", function()
      local l = linter(name)
      local function cond(f)
        return l.condition({ filename = f, dirname = vim.fs.dirname(f) })
      end
      H.ok(cond("/p/.github/workflows/ci.yml"))
      H.ok(cond("/p/.github/workflows/sub/x.yaml"))
      H.not_ok(cond("/p/ci.yml"))
      H.not_ok(cond("/p/docker-compose.yaml"))
      H.not_ok(cond("/p/.github/dependabot.yml"))
      H.not_ok(cond("/p/github/workflows/ci.yml"))
    end)
  end
end)'''),
    ...sec(r'cargo-deny: a parser with many edge cases'),
    ...para('--', r'cargo-deny prints JSON lines. The parser tests give it text and compare diagnostics. The severities map error, warning, note and help to ERROR, WARN, INFO and HINT, and unknown ones to WARN. In Cargo.lock the line is the name line of the package with that name and version; in Cargo.toml the line of the dependency comes from the graph or from the wildcard label (line and column minus 1), clamped when it is past the end of a short manifest such as a virtual workspace root; wildcard on Cargo.lock is skipped; a JSON null line, truthy as vim.NIL, does not crash the parser; and malformed lines, summaries and blanks are ignored. When cargo-deny itself fails, for example on a broken deny.toml, silence would be wrong. A log record at level ERROR becomes a diagnostic at line 0 with code deny-failed and severity WARN, and two ERROR records give one warning.'),
    ...code('lua', r'tests/git-lint-supply-chain_spec.lua · lines 418-433', r'''
  it("a `log` entry with level ERROR (broken deny.toml, unreachable source) becomes a line-0 WARN 'deny-failed'", function()
    local r = parse(
      "Cargo.toml",
      TOML,
      json_lines({
        { type = "log", fields = { level = "INFO", message = "just chatter" } },
        { type = "log", fields = { level = "ERROR", message = "failed to parse config from 'deny.toml'" } },
      })
    )
    H.eq(1, #r)
    H.eq(0, r[1].lnum)
    H.eq(SEV.WARN, r[1].severity)
    H.eq("cargo-deny", r[1].source)
    H.eq("deny-failed", r[1].code)
    H.match(r[1].message, "failed to parse config", true)
  end)'''),
    ...sec(r'cargo-machete'),
    ...para('--', r'The condition runs only for Cargo.toml. The parser reads output where a package header is followed by the unused dependency names, matches relative and absolute paths to the manifest of the current buffer only (a sibling crate’s manifest is ignored), and places the diagnostic on the dependency line. The tricky case is a dotted or quoted key: serde.workspace = true and "time".workspace = true must each land on their own line, not on line 1. The test builds the manifest and the tool output and requires lines 4 and 5.'),
    ...code('lua', r'tests/git-lint-supply-chain_spec.lua · lines 640-645', r'''
    it("dotted and quoted dependency keys (`serde.workspace = true`) get their own line, not line 1", function()
      local b = named_buf(d .. "/Cargo.toml", { "[package]", 'name = "p"', "", "[dependencies]", "serde.workspace = true", '"time".workspace = true' })
      local out = table.concat({ "p -- ./Cargo.toml:", "\tserde", "\ttime", "" }, "\n")
      local r = linter("cargo_machete").parser(out, b)
      H.eq({ 4, 5 }, { r[1].lnum, r[2].lnum })
    end)'''),
    ...sec(r'real tools, when present'),
    ...para('--', r'The integration layer runs cargo-deny on a scratch crate and expects RUSTSEC-2020-0071 on the time line and the wildcard on the serde line, and the same for Cargo.lock minus the wildcard. A broken deny.toml in a real crate gives deny-failed instead of silence, with the failing-parse message. cargo-machete finds two unused dependencies once each in a scratch crate. Both skip with a message if the tool or its advisory database is not cached.'),
    ...code('lua', r'tests/git-lint-supply-chain_spec.lua · lines 794-804', r'''
  it("a broken deny.toml gives a deny-failed diagnostic instead of silence", function()
    local d = deny_crate()
    write(d .. "/deny.toml", "this is [[ broken")
    local b = H.open(d .. "/Cargo.toml")
    local l = lint_until(b, "cargo_deny", "cargo-deny", function(x)
      return #x >= 1
    end, "cargo-deny failure diagnostic")
    H.eq("deny-failed", l[1].code)
    H.eq(SEV.WARN, l[1].severity)
    H.match(l[1].message, "failed to parse config", true)
  end)'''),
    ...sec(r'the workflow is linted by what it tests'),
    ...para('--', r'The last test runs actionlint and zizmor on this repository own .github/workflows/ci.yml. zizmor is called with the same invocation as the nvim-lint definition: --format json-v1 and the file on stdin. It parses the JSON and requires zero findings in the regular persona. The CI file of the project therefore has to pass the same linters that the editor offers to its users.'),
    ...code('lua', r'tests/git-lint-supply-chain_spec.lua · lines 915-928', r'''
  it("this repo's .github/workflows/ci.yml is clean under actionlint and zizmor", function()
    need_tool("actionlint")
    need_tool("zizmor")
    local ci = H.repo .. "/.github/workflows/ci.yml"
    local a = vim.system({ "actionlint", ci }, { text = true }):wait(60000)
    H.eq(0, a.code, "actionlint: " .. (a.stdout or "") .. (a.stderr or ""))
    -- the exact invocation of the nvim-lint zizmor definition (stdin)
    local z = vim.system({ "zizmor", "--format", "json-v1", "-" }, { text = true, stdin = table.concat(vim.fn.readfile(ci), "\n") .. "\n" }):wait(120000)
    local ok, list = pcall(vim.json.decode, z.stdout)
    H.ok(ok, "zizmor output: " .. tostring(z.stdout) .. tostring(z.stderr))
    H.eq(0, #list, "zizmor (regular persona) findings: " .. vim.inspect(vim.tbl_map(function(x)
      return x.ident
    end, list)))
  end)'''),
    ...sec(r'pending, with reasons'),
    ...para('--', r'Two pending entries close the file: the global git config (mergiraf, delta, zdiff3, rerere, aliases, lazygit leader g g and git-delta) lives in the user global gitconfig, outside the repository, with binaries checked by :checkhealth xynovim; and the README per-repo opt-ins (.git-blame-ignore-revs, lefthook.yml) are documentation only.'),
    ...code('lua', r'tests/git-lint-supply-chain_spec.lua · lines 933-937', r'''
pending(
  "global git config (mergiraf, delta, zdiff3, rerere, dft/dlog aliases), lazygit <leader>gg and git-delta availability",
  "lives in the user's global ~/.gitconfig, outside the repo; the binaries are checked by :checkhealth xynovim"
)
pending("README per-repo opt-ins (.git-blame-ignore-revs, lefthook.yml)", "documentation only, no code to run")'''),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created.'),
    ...pt('--', r'98c9bb4 (2026-10-13), 3f868dd (2026-10-13), f31e013 (2026-10-14)', r'field test rounds; the third lists "deny fallback and parser".'),
    ...pt('--', r'b474307 (2026-10-15)', r'macros and dependencies field test fixes. d3e1442 (2026-10-21) :: path spelling on Windows and macOS.'),
  ],
);
