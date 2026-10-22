import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-history.nvim/tests/e2e/smoke.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'smoke.lua — does the plugin work when a plugin manager loads it?'),
    cm('--', r'lazy.nvim, setup(), commands, help, and a real :write that lands on a ref'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'end-to-end check, 48 lines, paired with tests/e2e/init.lua (20 lines)'),
    kv(r'language', r'Lua, run inside a headless Neovim started with a minimal init'),
    kv(r'run with', r'XYNO_LAZY=/path/to/lazy.nvim nvim --headless -u tests/e2e/init.lua -c "luafile tests/e2e/smoke.lua"'),
    kv(r'history', r'added in b6b25d9 (2026-10-22)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The 65 unit-style specs load the module by adding the repository to the runtimepath and '
        r'calling require. They would all pass if the plugin were broken for the way it is actually '
        r'installed: a wrong module name in the lazy.nvim spec, a missing main field, a help file '
        r'that does not resolve, a setup that is never called. The smoke test closes that gap by '
        r'loading the plugin the way a user does, through lazy.nvim, and then doing the one thing '
        r'the plugin is for.'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 1-3', r'''
-- End-to-end smoke test (see tests/e2e/init.lua): the plugin is loaded by lazy.nvim,
-- setup() ran, every documented command exists, :help xyno-history resolves, and a
-- :write in a git repository produces a snapshot on refs/lochist/.
'''),
    ...sec(r'loading through lazy.nvim'),
    ...para('--', r'The init file is separate, in tests/e2e/init.lua. It puts the lazy.nvim clone given in '
        r'XYNO_LAZY on the runtimepath and calls lazy.setup with the repository as a local plugin, '
        r'using dir. The spec is lazy = false, has empty opts and names its main module '
        r'xyno_history, so lazy calls setup for it. The options of lazy are tuned to be quiet and '
        r'hermetic: missing plugins are not installed, the update checker and change detection are '
        r'off, and the runtimepath is not reset, so the plugin is visible to the test.'),
    ...sec(r'the tiny check helper'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 4-10', r'''
local failures = {}
local function check(name, ok, detail)
  io.stdout:write(("%s %s%s\n"):format(ok and "ok  " or "FAIL", name, (not ok and detail) and (": " .. tostring(detail)) or ""))
  if not ok then
    failures[#failures + 1] = name
  end
end
'''),
    ...para('--', r'check prints ok or FAIL with the name, records failures, and moves on, so one failure '
        r'does not hide the others. The output format is the same as the unit runner’s, which keeps '
        r'a CI log uniform.'),
    ...sec(r'what it asserts, in order'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 12-23', r'''
check("lazy.nvim loaded xyno_history", package.loaded["xyno_history"] ~= nil)
for _, c in ipairs({ "LocalHistory", "LocalHistoryRestore", "LocalHistoryPrune" }) do
  check("command :" .. c, vim.fn.exists(":" .. c) == 2)
end
check("autocmd group xyno_history", #vim.api.nvim_get_autocmds({ group = "xyno_history" }) >= 3)

local repo = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))))
vim.cmd("helptags " .. vim.fn.fnameescape(repo .. "/doc"))
local ok, err = pcall(vim.cmd, "help xyno-history")
check(":help xyno-history", ok, err)
check(":help xyno-history-api", (pcall(vim.cmd, "help xyno-history-api")))
vim.cmd("only")
'''),
    ...para('--', r'First the module is loaded, which proves lazy ran setup. Then each of the three commands '
        r'must exist with value 2, Vim’s code for a command that is fully defined, and the autocmd '
        r'group must hold at least three autocmds, one for each of the two save events and one for '
        r'exit. Then the help is built into tags and opened with :help for both the main tag and '
        r'the API tag, which proves that the doc file ships a resolvable tag set.'),
    ...sec(r'the real thing'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 25-42', r'''
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local function git(...)
  local r = vim.system({ "git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", ... }, { cwd = dir, text = true }):wait(30000)
  return r.code == 0 and vim.trim(r.stdout) or nil
end
git("init", "-q", "-b", "main")
vim.fn.writefile({ "one" }, dir .. "/a.txt")
git("add", "-A")
git("commit", "-q", "-m", "init")
vim.cmd.edit(vim.fn.fnameescape(dir .. "/a.txt"))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "two" })
vim.cmd.write()
local landed = vim.wait(15000, function()
  return git("rev-parse", "-q", "--verify", "refs/lochist/main") ~= nil
end, 50)
check("a :write snapshots to refs/lochist/main", landed)
check("the snapshot holds the saved text", git("show", "refs/lochist/main:a.txt") == "two")
'''),
    ...para('--', r'The last part creates a temporary git repository, commits a file with a throwaway '
        r'identity and gpg signing off, opens the file, replaces the text, and writes. Then it '
        r'waits up to 15 seconds, polling every 50 milliseconds, for refs/lochist/main to exist, '
        r'and checks that the content of the file in that ref is the text that was written. Because '
        r'the snapshot is asynchronous, the wait is the correct shape of the assertion.'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 43-48', r'''
vim.fn.delete(dir, "rf")

if #failures > 0 then
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
'''),
    ...para('--', r'Any failure ends with cquit 1 so that CI turns red; success quits with qa!. The temporary '
        r'repository is deleted before either.'),
    ...sec(r'a limit worth stating'),
    ...para('--', r'The smoke test starts Neovim with the minimal init and not with a distribution, so it '
        r'does not show how the plugin behaves next to an auto-save plugin or a picker. That '
        r'interplay is tested in the spec with a simulated event only.'),
    ...sec(r'history'),
    ...pt('--', r'b6b25d9', r'2026-10-22, with the unit specs.'),
  ],
);
