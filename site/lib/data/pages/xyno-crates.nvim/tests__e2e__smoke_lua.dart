import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-crates.nvim/tests/e2e/smoke.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'smoke.lua — does the plugin work when lazy.nvim loads it?'),
    cm('--', r'the only test that goes through a real plugin manager'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'end-to-end smoke test, run after the specs in CI'),
    kv(r'language', r'Lua, executed with nvim --headless -u tests/e2e/init.lua -c "luafile tests/e2e/smoke.lua"'),
    kv(r'size', r'66 lines, 18 checks (some in loops) and a fault-injection block'),
    kv(r'needs', r'XYNO_LAZY (a lazy.nvim checkout); both dependency plugins next to the repo or via env'),
    kv(r'history', r'added in 9d33ca7 (2026-10-22) with the specs'),
    ...sec(r'why this file exists'),
    ...para('--', r'The specs load the plugin by putting its directory on the runtimepath and requiring modules directly. That is a faithful way to test the code and an unfaithful way to test the installation. A user reaches the plugin through lazy.nvim: a spec with dir, name, main, opts and a dependency list, after which lazy calls require("xyno_crates").setup(opts). A mistake in the repository layout (lua/xyno_crates/init.lua misplaced), in the help file (a tag missing from doc/), or in the main-module convention would pass every spec and still break a real install. The smoke test checks exactly the things a spec cannot see.'),
    blank,
    ...para('--', r'Its companion tests/e2e/init.lua, which is not paged separately because it is a plain lazy.nvim bootstrap, builds that situation: lazy loads this checkout with dir = repo, lazy = false, main = "xyno_crates", opts = {}, the two siblings as dependencies, and with install, checker and change detection switched off. The header of smoke.lua says what follows: "the plugin is loaded by lazy.nvim, setup() ran, every documented command exists, :help xyno-crates resolves, the in-process language servers are configured, no key is mapped, and a missing dependency gives one notification line."'),
    blank,
    ...code('lua', r'tests/e2e/smoke.lua · lines 1-11', r'''
-- End-to-end smoke test (see tests/e2e/init.lua): the plugin is loaded by lazy.nvim,
-- setup() ran, every documented command exists, :help xyno-crates resolves, the
-- in-process language servers are configured, no key is mapped, and a missing
-- dependency gives one notification line.
local failures = {}
local function check(name, ok, detail)
  io.stdout:write(("%s %s%s\n"):format(ok and "ok  " or "FAIL", name, (not ok and detail) and (": " .. tostring(detail)) or ""))
  if not ok then
    failures[#failures + 1] = name
  end
end'''),
    ...sec(r'the checks that follow the real install'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 13-24', r'''
check("lazy.nvim loaded xyno_crates", package.loaded["xyno_crates"] ~= nil)
for _, c in ipairs({ "CrateAdd", "CrateFeatures" }) do
  check("command :" .. c, vim.fn.exists(":" .. c) == 2)
end
for _, m in ipairs({ "crate_add", "crate_features", "crate_import" }) do
  check("require xyno_crates." .. m, (pcall(require, "xyno_crates." .. m)))
end
check("autocmd group xyno-crates-add", #vim.api.nvim_get_autocmds({ group = "xyno-crates-add" }) >= 4)
check("autocmd group xyno_crates_features", #vim.api.nvim_get_autocmds({ group = "xyno_crates_features" }) >= 1)
check("in-process server xyno-crates configured", vim.lsp.config["xyno-crates"] ~= nil)
check("no global <leader>rA by default", vim.fn.maparg("<leader>rA", "n") == "")
check("no global <leader>rG by default", vim.fn.maparg("<leader>rG", "n") == "")'''),
    ...para('--', r'Each check prints "ok  " or "FAIL" and collects the failures; nothing aborts early, so one run lists everything that is wrong. The checks are the post-conditions of setup(). Both commands exist (exists(":CrateAdd") == 2 means a user command). The three modules can be required. The autocommand group xyno-crates-add has at least four autocommands, which are the InsertLeave/TextChanged/BufWritePost/BufReadPost set, and xyno_crates_features has at least one. vim.lsp.config["xyno-crates"] exists, which proves the in-process server was configured through the Neovim 0.12 API. And the negative checks: neither <leader>rA nor <leader>rG is mapped globally, the promise made by keymaps = false.'),
    blank,
    ...code('lua', r'tests/e2e/smoke.lua · lines 26-32', r'''
local repo = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))))
vim.cmd("helptags " .. vim.fn.fnameescape(repo .. "/doc"))
for _, tag in ipairs({ "xyno-crates", "xyno-crates-setup", "xyno-crates-api", ":CrateAdd", ":CrateFeatures" }) do
  local ok, err = pcall(vim.cmd, "help " .. tag)
  check(":help " .. tag, ok, err)
end
vim.cmd("only")'''),
    ...para('--', r'The help file is verified in the strongest way available: generate the tags with :helptags on the doc directory, then run :help for five tags, xyno-crates, xyno-crates-setup, xyno-crates-api, :CrateAdd and :CrateFeatures. A tag missing from the help file or a malformed *tag* line fails here. doc/tags is generated, not committed (it is listed in .gitignore), so :helptags is run here first, and the check shows that the help file itself is well formed. vim.cmd("only") closes the help window afterwards.'),
    blank,
    ...sec(r'the fault-injection block'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 34-61', r'''
-- a missing dependency gives one notification line and no Lua error
local notes = {}
local orig = vim.notify
vim.notify = function(msg)
  notes[#notes + 1] = msg
end
local mods = { "xyno_rust.crate_meta", "xyno_rust.code_actions", "xyno_rust.fsutil", "xyno_rust.rust_restart", "xyno_imports.engine" }
local saved = {}
for _, k in ipairs(mods) do
  saved[k] = package.loaded[k]
  package.loaded[k] = nil
end
local saved_path = package.path
local saved_loaders = package.loaders
package.loaders = { function() return nil end }
package.path = ""
local rtp = vim.o.runtimepath
vim.o.runtimepath = ""
local ok = pcall(require("xyno_crates").setup, {})
vim.o.runtimepath = rtp
package.path = saved_path
package.loaders = saved_loaders
for _, k in ipairs(mods) do
  package.loaded[k] = saved[k]
end
vim.notify = orig
check("setup() without xyno-rust: no error", ok)
check("setup() without xyno-rust: one line", #notes == 1 and not notes[1]:find("\n"), vim.inspect(notes))'''),
    ...para('--', r'The last block repeats the dependency check from the real environment instead of from a spec. It replaces vim.notify with a collector, unloads the five modules the plugin requires, then empties package.loaders, package.path and the runtimepath so that nothing can be found, and calls setup() again under pcall. The assertions are two: no Lua error, and exactly one notification, one line long. Everything is restored in order. init_spec.lua tests the same promise with a package searcher that refuses the modules; this block repeats it after a real lazy.nvim load, with everything the loader could find removed. It comes after the help checks, which need the runtimepath.'),
    blank,
    ...para('--', r'At the end any failure calls cquit 1, so the CI step fails; otherwise qa!.'),
    blank,
    ...sec(r'limits'),
    ...pt('--', r'no behaviour', r'it never opens a Rust file or presses a key. The behavioural claims live in the specs; this file only guards installation.'),
    ...pt('--', r'lazy only', r'other managers are not tested. The layout is conventional, so they are expected to work, but nothing here proves it.'),
    ...pt('--', r'needs the neighbours', r'the dependency plugins must exist, as siblings or through XYNO_RUST_DIR and XYNO_IMPORTS_DIR; the CI job clones them first.'),
  ],
);
