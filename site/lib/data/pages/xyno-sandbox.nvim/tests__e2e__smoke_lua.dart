import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-sandbox.nvim/tests/e2e/smoke.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'smoke.lua — lazy.nvim loads the plugin, the surface exists, nothing errors'),
    cm('--', r'one file that is both the init file and the test'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'end-to-end smoke test through lazy.nvim'),
    kv(r'language', r'Lua, run as the init file of a headless Neovim'),
    kv(r'size', r'63 lines'),
    kv(r'run with', r'LAZY_PATH=/path/to/lazy.nvim nvim --headless -u tests/e2e/smoke.lua'),
    kv(r'history', r'added in 03b99f2 (2026-10-22, Add specs, a smoke test and CI)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The specs require the module directly. They cannot notice that the plugin, installed the '
        r'way the README says, fails to load: a wrong main module name, a missing command, an error '
        r'thrown during setup. The smoke test installs the plugin through lazy.nvim from the '
        r'checkout and checks that what the README promises is there. Unlike the history plugin’s '
        r'smoke test, it is a single file that serves as the init file (-u) as well as the checks.'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 1-4', r'''
-- End-to-end smoke test: lazy.nvim loads the plugin from this checkout through
-- `dir =`, setup() runs, and every documented command exists.
--   LAZY_PATH=<lazy.nvim checkout> nvim --headless -u tests/e2e/smoke.lua
-- Run it with a clean XDG environment so nothing from a personal config leaks.
'''),
    ...sec(r'the checkout and the error collector'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 5-23', r'''
local repo = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))))
if repo == "" or repo == "." then
  repo = vim.uv.cwd()
end
local lazy_path = assert(vim.env.LAZY_PATH, "LAZY_PATH is not set")
vim.opt.runtimepath:prepend(lazy_path)

local function fail(msg)
  io.stdout:write("FAIL " .. msg .. "\n")
  os.exit(1)
end

local errors = {}
local orig = vim.notify
vim.notify = function(msg, level)
  if level and level >= vim.log.levels.ERROR then
    errors[#errors + 1] = msg
  end
end
'''),
    ...para('--', r'The repository root is computed from the script’s own location, with a fallback to the '
        r'current directory. LAZY_PATH is mandatory and asserted, and is put on the runtimepath '
        r'first so that require("lazy") works. A fail function writes FAIL and exits with 1. Then '
        r'vim.notify is replaced by a collector that keeps only messages at ERROR level or above, '
        r'so that the test can say at the end whether setup complained.'),
    ...sec(r'loading'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 25-31', r'''
require("lazy").setup({
  { dir = repo, name = "xyno-sandbox.nvim", main = "xyno_sandbox", opts = {} },
}, { lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json", install = { missing = false }, checker = { enabled = false } })

-- lazy.nvim loads `opts` plugins on startup (VimEnter in headless -l mode is not
-- fired, so load explicitly)
require("lazy").load({ plugins = { "xyno-sandbox.nvim" } })
'''),
    ...para('--', r'lazy.setup is given the checkout as a local plugin with dir, a name, the main module and '
        r'empty opts, and the lockfile is placed in the state directory so that the test does not '
        r'write into the repository. Missing plugins are not installed and the update checker is '
        r'off. The comment on the next line records a detail of headless mode: loading in -l mode '
        r'does not fire VimEnter, so opts-only plugins are not loaded by themselves, and the script '
        r'loads the plugin explicitly. Without that line the commands would not exist and the test '
        r'would fail for a reason that has nothing to do with the plugin.'),
    ...sec(r'checks'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 33-58', r'''
for _, cmd in ipairs({ "XynoSandboxStatus", "XynoSandboxRun" }) do
  if vim.fn.exists(":" .. cmd) ~= 2 then
    fail("command missing: " .. cmd)
  end
end
local ok, sb = pcall(require, "xyno_sandbox")
if not ok then
  fail("require xyno_sandbox: " .. tostring(sb))
end
for _, fn in ipairs({ "setup", "status", "wrap", "run", "scrub_names", "readonly_paths" }) do
  if type(sb[fn]) ~= "function" then
    fail("missing function: " .. fn)
  end
end
local st = sb.status()
if not vim.tbl_contains({ "bwrap", "refused", "unsandboxed" }, st.mode) then
  fail("odd status mode: " .. tostring(st.mode))
end
local seen = {}
vim.notify = function(msg)
  seen[#seen + 1] = msg
end
vim.cmd("XynoSandboxStatus")
if not (seen[1] and seen[1]:find("xyno-sandbox:", 1, true)) then
  fail("XynoSandboxStatus printed nothing")
end
'''),
    ...para('--', r'Both commands must exist with value 2. The module must load with pcall. Six functions '
        r'must exist on it: setup, status, wrap, run, scrub_names and readonly_paths, the five functions of the README’s Lua API plus setup. The status must be one of bwrap, '
        r'refused or unsandboxed. Then vim.notify is swapped for a recorder and :XynoSandboxStatus '
        r'is run; at least one message with the plugin prefix must appear. Finally the error '
        r'collector must be empty.'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 59-63', r'''
if #errors > 0 then
  fail("errors during load: " .. table.concat(errors, "; "))
end
io.stdout:write("OK smoke: status=" .. st.mode .. "\n")
os.exit(0)
'''),
    ...para('--', r'The last lines print OK with the mode that this machine reports and exit 0. The mode in '
        r'the line is useful in CI logs: on a runner where user namespaces are restricted it shows '
        r'bwrap but the spec suite will have skipped the behaviour tests. Note that the smoke test '
        r'accepts any of the three modes, so it passes on a machine without bubblewrap; its job is '
        r'loading, not sandboxing.'),
    ...sec(r'history'),
    ...pt('--', r'03b99f2', r'2026-10-22, with the specs and the CI workflow.'),
  ],
);
