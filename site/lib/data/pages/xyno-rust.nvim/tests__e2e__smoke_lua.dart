import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/tests/e2e/smoke.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'tests/e2e/smoke.lua — does it work when installed the way a user installs it?'),
    cm('--', r'lazy.nvim loads the checkout, setup() runs, commands exist, :help resolves, one crate round trip'),
    cm('--', r'──────────────────────────────────────────'),
    blank,
    kv(r'role', r'end-to-end smoke test, run after the spec suite in CI'),
    kv(r'language', r'Lua, run with nvim --headless -u tests/e2e/init.lua -c "luafile tests/e2e/smoke.lua"'),
    kv(r'size', r'52 lines, 27 checks, 1 commit (7c1d2d9)'),
    kv(r'needs', r'a clone of lazy.nvim in XYNO_LAZY; the doc/ directory of the repo; no cargo, no rust-analyzer'),
    kv(r'output', r'one line per check, ok or FAIL, and exit code 1 if any failed'),
    kv(r'companion', r'tests/e2e/init.lua (20 lines), the minimal init that makes lazy.nvim load this checkout'),
    ...sec(r'why this file exists'),
    ...para('--', r'The specs in tests/ load the modules with require and call setup() themselves. That '
        r'proves the code works when someone calls it. It does not prove the plugin works when '
        r'somebody installs it: that the directory layout is what a plugin manager expects, that '
        r'lazy.nvim finds the main module and calls setup() with the opts table, that the user '
        r'commands exist after a normal startup, that the help file is in a place where :help finds '
        r'it, and that a Rust buffer in a plain crate gets sensible answers.'),
    ...para('--', r'smoke.lua is that check. It treats the repository as a black box installed through '
        r'lazy.nvim, and asks only what a first-time user would find out in their first minute: are '
        r'the commands there, does :help work, does :RustContext say something sensible. It is '
        r'small on purpose. Anything that needs a corner case belongs in a spec.'),
    ...sec(r'the init that loads the plugin'),
    ...code('lua', r'tests/e2e/init.lua · lines 1-20', r'''
-- Minimal init for the end-to-end smoke test: lazy.nvim loads this checkout
-- through `dir =` and calls setup(). XYNO_LAZY is the path of a lazy.nvim clone.
-- Run:  XYNO_LAZY=/path/to/lazy.nvim nvim --headless -u tests/e2e/init.lua -c "luafile tests/e2e/smoke.lua"
local repo = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))))
vim.o.swapfile = false
vim.opt.rtp:prepend(assert(vim.env.XYNO_LAZY, "XYNO_LAZY not set"))
require("lazy").setup({
  {
    dir = repo,
    name = "xyno-rust.nvim",
    lazy = false,
    opts = {},
    main = "xyno_rust",
  },
}, {
  install = { missing = false },
  checker = { enabled = false },
  change_detection = { enabled = false },
  performance = { reset_packpath = false, rtp = { reset = false } },
})
'''),
    ...para('--', r'The init file is the part that makes the test an end-to-end test. It prepends the '
        r'lazy.nvim clone given in XYNO_LAZY to the runtimepath (assert fails with the message '
        r'XYNO_LAZY not set if it is missing), and calls require("lazy").setup with one plugin '
        r'spec: dir = repo, so lazy.nvim installs from the checkout and not from GitHub, name '
        r'xyno-rust.nvim, lazy = false so it loads at startup, opts = {} and main = "xyno_rust". '
        r'With opts present, lazy.nvim calls require("xyno_rust").setup({}), the same call a user’s '
        r'config makes.'),
    ...para('--', r'The options of lazy itself are a lesson in isolation. install.missing is false (no '
        r'downloading), the update checker and change detection are off, and '
        r'performance.reset_packpath and rtp.reset are false so that the runtimepath prepared by '
        r'the test is not wiped. The repo path is derived from the file’s own location with three '
        r'dirname calls.'),
    ...sec(r'header and the check helper'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 4-12', r'''
local failures = {}
local function check(name, ok, detail)
  io.stdout:write(("%s %s%s\n"):format(ok and "ok  " or "FAIL", name, (not ok and detail) and (": " .. tostring(detail)) or ""))
  if not ok then
    failures[#failures + 1] = name
  end
end

check("lazy.nvim loaded xyno_rust", package.loaded["xyno_rust"] ~= nil)
'''),
    ...para('--', r'check prints ok or FAIL with the name of the check, plus the detail on failure, and '
        r'collects failing names in a list. The test does not stop at the first failure; it runs '
        r'everything and decides at the end. One run therefore tells you everything that is broken.'),
    ...sec(r'loading, commands and autocmd groups'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 12-20', r'''
check("lazy.nvim loaded xyno_rust", package.loaded["xyno_rust"] ~= nil)
for _, c in ipairs({ "RustContext", "RustTargets", "RustTools", "ActJob", "RustNew", "RustRoutes", "RustRestart" }) do
  check("command :" .. c, vim.fn.exists(":" .. c) == 2)
end
check("autocmd group xyno_rust_lsp_status", #vim.api.nvim_get_autocmds({ group = "xyno_rust_lsp_status" }) >= 3)
check("autocmd group xyno_rust_restart", #vim.api.nvim_get_autocmds({ group = "xyno_rust_restart" }) >= 3)
for _, m in ipairs({ "fsutil", "rust_context", "code_actions", "crate_meta", "lsp_status", "rust_restart", "rust_tasks", "rust_routes", "rust_nav" }) do
  check("require xyno_rust." .. m, (pcall(require, "xyno_rust." .. m)))
end
'''),
    ...pt('--', r'lazy.nvim loaded xyno_rust', r'package.loaded has the module, which means lazy really ran the plugin spec and called setup.'),
    ...pt('--', r'seven commands', r'for each of RustContext, RustTargets, RustTools, ActJob, RustNew, RustRoutes and '
        r'RustRestart, vim.fn.exists(":Name") must be 2. The same list is in tests/init_spec.lua, '
        r'so a command added to the plugin has to be added to both.'),
    ...pt('--', r'two autocmd groups', r'xyno_rust_lsp_status and xyno_rust_restart must each hold at least three autocmds. This '
        r'is proof that setup() reached the status and restart modules, which are the two with '
        r'global effects.'),
    ...pt('--', r'every module requires cleanly', r'nine module names are required inside pcall: fsutil, rust_context, code_actions, '
        r'crate_meta, lsp_status, rust_restart, rust_tasks, rust_routes and rust_nav. A syntax '
        r'error in any of them shows up here as a failed check with its own name. The list does not '
        r'contain init (already loaded) or deps (helper for the pickers).'),
    ...para('--', r'That makes 1 + 7 + 2 + 9 = 19 checks before the help block, 5 help checks and 3 crate '
        r'checks after it: 27 in all.'),
    ...sec(r'the help file'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 22-28', r'''
local repo = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))))
vim.cmd("helptags " .. vim.fn.fnameescape(repo .. "/doc"))
for _, tag in ipairs({ "xyno-rust", "xyno-rust-api", "xyno-rust-setup", ":RustContext", ":RustRestart" }) do
  local ok, err = pcall(vim.cmd, "help " .. tag)
  check(":help " .. tag, ok, err)
end
vim.cmd("only")
'''),
    ...para('--', r'helptags is generated at test time for the repo’s doc directory (the line writes doc/tags '
        r'into the checkout, a file the repo’s .gitignore lists). Then each of five tags is looked '
        r'up with :help inside pcall: xyno-rust, xyno-rust-api, xyno-rust-setup, :RustContext and '
        r':RustRestart. A tag that does not exist raises E149, the check fails and prints the '
        r'error. Two of them are command tags, so the documentation of the user commands is checked '
        r'by name. :only closes the help window afterwards so the next steps start from a single '
        r'window.'),
    ...para('--', r'The comment above the scratch crate (line 50 of the file) says a stored choice round-trips, but the '
        r'code below it only runs show on the default; no choice is stored. The context storage is '
        r'covered by rust-context_spec.lua.'),
    ...para('--', r'The help file itself, doc/xyno-rust.txt, was added in the commit after the one that '
        r'introduced this smoke test (6947749, Add README, help file and CI workflow), so the five '
        r'tag checks are a contract that the help file had to fulfil.'),
    ...sec(r'the scratch crate'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 30-52', r'''
-- a scratch crate: :RustContext show reports the default, a stored choice round-trips
local dir = vim.fn.tempname()
vim.fn.mkdir(dir .. "/src", "p")
vim.fn.writefile({ '[package]', 'name = "smoke"', 'version = "0.1.0"', 'edition = "2021"' }, dir .. "/Cargo.toml")
vim.fn.writefile({ "fn main() {}" }, dir .. "/src/main.rs")
vim.cmd.edit(vim.fn.fnameescape(dir .. "/src/main.rs"))
local notes = {}
local orig = vim.notify
vim.notify = function(msg)
  notes[#notes + 1] = msg
end
vim.cmd("RustContext show")
check(":RustContext show", notes[#notes] == "Rust context: all features, host target", notes[#notes])
local rc = require("xyno_rust.rust_context")
check("rust_context.root", rc.root() == dir, tostring(rc.root()))
check("component() is a string", type(require("xyno_rust.lsp_status").component()) == "string")
vim.notify = orig
vim.fn.delete(dir, "rf")

if #failures > 0 then
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
'''),
    ...para('--', r'The last block builds a crate in a temporary directory: a Cargo.toml with package name '
        r'smoke, version, edition, and a src/main.rs with an empty main. It edits the file, '
        r'replaces vim.notify with a collector and runs :RustContext show. The expected '
        r'notification is exactly Rust context: all features, host target, the text of the default '
        r'context, which also exercises rust_context.root and rust_context.describe (the root logic '
        r'asks cargo locate-project when cargo is installed and otherwise walks up the text of the '
        r'manifests). Then it checks that rust_context.root returns the temp directory itself and '
        r'that lsp_status.component returns a string, which in a buffer without clients is the '
        r'empty string.'),
    ...para('--', r'The notify function is restored and the directory deleted before the verdict is read, and '
        r'the verdict is the last statement: if the list of failures is not empty, cquit 1 ends '
        r'Neovim with exit status 1, otherwise qa! ends it with 0. The CI step therefore fails on '
        r'any FAIL line.'),
    ...para('--', r'Because the scratch crate is created with tempname, the assertion rc.root() == dir '
        r'compares the temp path with whatever the module returns. On Linux the two are the same '
        r'string. The spec suite handles macOS /private/var and Windows short names in H.tmpdir '
        r'with a realpath; this smoke test does not, and it is only run on Linux in CI.'),
    ...sec(r'how it runs in CI'),
    ...para('--', r'In .github/workflows/ci.yml the smoke test is the last step. lazy.nvim is fetched as a '
        r'bare commit at a pinned SHA (85c7ff3, commented as v11.17.5) into the runner temp '
        r'directory, so there is no moving tag. Then XYNO_LAZY points at it and nvim runs the two '
        r'files. Neovim itself is the pinned v0.12.5 with a checksum check, the same binary that '
        r'ran the specs a step earlier.'),
    ...sec(r'what it does not prove'),
    ...para('--', r'It never starts a language server or opens a picker, so it says nothing about the '
        r'behaviour of the plugin with rust-analyzer or snacks.nvim.'),
    ...para('--', r'Keymaps are not enabled in opts = {}, so the opt-in keymaps are not covered here; '
        r'init_spec.lua covers them.'),
    ...para('--', r'Windows and macOS: not run.'),
    ...sec(r'design decisions'),
    ...pt('--', r'a black box', r'the file checks names and messages, never internal state, so it keeps working through '
        r'refactors of the modules.'),
    ...pt('--', r'collect failures, exit once', r'one run lists every broken thing, and the exit code is still honest.'),
    ...pt('--', r'lazy.nvim as the installer', r'it is the plugin manager the README shows first, so the smoke test installs it the same way.'),
    ...sec(r'history'),
    ...pt('--', r'7c1d2d9, 2026-10-22', r'the smoke test and its init arrive together with the specs and the runner.'),
    ...pt('--', r'6947749, 2026-10-22', r'the README, the help file and the CI workflow that runs this test follow.'),
  ],
);
