import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-crates.nvim/tests/init_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'init_spec.lua — the promises of setup(), checked by making them fail'),
    cm('--', r'six tests; the technique is to forbid a module from loading'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/xyno_crates/init.lua'),
    kv(r'language', r'Lua on tests/harness.lua'),
    kv(r'size', r'93 lines, 6 tests in 2 groups'),
    kv(r'needs', r'nothing external: no network, no cargo, no rust-analyzer'),
    kv(r'history', r'written for the plugin, added in 9d33ca7 (2026-10-22); xynovim had no counterpart'),
    ...sec(r'why this file exists'),
    ...para('--', r'init.lua is the only file of the plugin that was not extracted from xynovim, so it is the only file whose spec could not be taken from xynovim either. Its job is to say no politely, and a refusal is hard to test, because the thing you want to see is the absence of everything else: no command, no autocommand, no language client, one line of text. This spec shows how: remove the dependency from the world, call setup(), and look at what the world contains afterwards.'),
    blank,
    ...code('lua', r'tests/init_spec.lua · lines 1-5', r'''
-- xyno_crates.setup(): the one-line messages for a missing dependency, the modules
-- option, commands, and that no key is mapped by default. The modules start once per
-- process, so the opt-in keys are checked in init-keymaps_spec.lua.
local H = require("xyno_crates_test.helpers")
local C = require("xyno_crates")'''),
    ...sec(r'the trick: making require fail on purpose'),
    ...code('lua', r'tests/init_spec.lua · lines 7-35', r'''
--- Run fn with `blocked` modules unloadable; returns the notifications it produced.
local function without(blocked, fn)
  local notes = {}
  local orig = vim.notify
  vim.notify = function(msg, level)
    notes[#notes + 1] = { msg = msg, level = level }
  end
  local saved = {}
  for _, m in ipairs(blocked) do
    saved[m] = package.loaded[m]
    package.loaded[m] = nil
  end
  local searchers = package.loaders or package.searchers
  local block = function(name)
    if vim.tbl_contains(blocked, name) then
      return function()
        error("module '" .. name .. "' not found")
      end
    end
  end
  table.insert(searchers, 1, block)
  local ok, err = pcall(fn)
  table.remove(searchers, 1)
  for _, m in ipairs(blocked) do
    package.loaded[m] = saved[m] -- also nil: a failed require leaves a marker behind
  end
  vim.notify = orig
  return notes, ok, err
end'''),
    ...para('--', r'without(blocked, fn) runs fn while the named modules cannot be loaded, and returns every notification produced. Three steps do it. The modules are removed from package.loaded, so a cached success cannot answer the require. A searcher is inserted at position 1 of package.searchers (or package.loaders in a LuaJIT-style runtime, which is why the code reads both names): for a blocked name it returns a loader that raises "module not found", so require fails with the same kind of error a missing plugin gives. vim.notify is replaced by a collector, so the test sees the level as well as the text. Afterwards, everything is put back, and the comment on the restore line is worth reading: package.loaded gets the saved value back "also nil: a failed require leaves a marker behind", so the cleanup deliberately writes nil to wipe the failure marker. A test helper that does not restore that would poison every later test in the same process.'),
    blank,
    ...sec(r'the dependency tests'),
    ...code('lua', r'tests/init_spec.lua · lines 37-50', r'''
describe("setup without its dependencies", function()
  it("says which plugin is missing in one line, no Lua error, and starts nothing", function()
    local notes, ok = without({ "xyno_rust.crate_meta" }, function()
      C.setup({})
    end)
    H.ok(ok)
    H.eq(1, #notes)
    H.match(notes[1].msg, "needs xyno-rust.nvim", true)
    H.match(notes[1].msg, "xynorash/xyno-rust.nvim", true)
    H.not_ok(notes[1].msg:find("\n", 1, true), "one line")
    H.eq(vim.log.levels.ERROR, notes[1].level)
    H.eq(0, vim.fn.exists(":CrateAdd"))
    H.eq(0, vim.fn.exists(":CrateFeatures"))
  end)'''),
    ...para('--', r'The first test is the contract written as a series of assertions. The call does not raise (H.ok(ok)). Exactly one notification is produced. It contains "needs xyno-rust.nvim" and the GitHub path xynorash/xyno-rust.nvim, so the user can act on it. It contains no newline, which keeps the message to one line in :messages. The level is ERROR. And, last, both commands are absent, exists(":CrateAdd") is 0, which is the check that nothing started. Blocking only xyno_rust.crate_meta is enough, because the check stops at the first missing module; the test does not need to block all four.'),
    blank,
    ...code('lua', r'tests/init_spec.lua · lines 52-68', r'''
  it("names xyno-imports.nvim when only that one is missing", function()
    local notes, ok = without({ "xyno_imports.engine" }, function()
      C.setup({})
    end)
    H.ok(ok)
    H.eq(1, #notes)
    H.match(notes[1].msg, "needs xyno-imports.nvim", true)
    H.eq(0, vim.fn.exists(":CrateAdd"))
  end)

  it("does not need xyno-imports.nvim when the add and import modules are off", function()
    local notes, ok = without({ "xyno_imports.engine" }, function()
      C.setup({ modules = { add = false, import = false, features = false } })
    end)
    H.ok(ok)
    H.eq(0, #notes)
  end)'''),
    ...para('--', r'The second test blocks only xyno_imports.engine and expects the other plugin’s name. It protects the table in init.lua from a copy-paste error where every row says xyno-rust.nvim. The third test (lines 62-68) flips the situation: with add, import and features all switched off and the import engine blocked, setup() must produce zero notifications. That is the executable form of the needed rule in init.lua, "xyno-imports is only used by the add and import modules".'),
    blank,
    ...sec(r'the setup tests'),
    ...code('lua', r'tests/init_spec.lua · lines 71-93', r'''
describe("setup", function()
  it("starts nothing for a module that is switched off", function()
    C.setup({ modules = { add = false, features = false, import = false } })
    H.eq(0, vim.fn.exists(":CrateAdd"))
    H.eq(0, vim.fn.exists(":CrateFeatures"))
  end)

  it("registers both commands and maps no key by default", function()
    C.setup({})
    H.eq(2, vim.fn.exists(":CrateAdd"))
    H.eq(2, vim.fn.exists(":CrateFeatures"))
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "rust"
    H.eq("", vim.fn.maparg("<leader>rA", "n"))
    H.eq("", vim.fn.maparg("<leader>rG", "n"))
  end)

  it("serves the in-process code actions without a language server process", function()
    H.eq("xyno-crates", require("xyno_crates.crate_add").server_name)
    H.eq("xyno-features", require("xyno_crates.crate_features").client_name)
  end)
end)'''),
    ...para('--', r'Three observations. First, these tests run in the same process after the failing ones, and still find an unstarted plugin: a refused setup() returns before touching the modules, so it does not consume the "first call wins" guard. If init.lua ever moved the check after the module setup, a later test would see commands from an earlier one. Second, the key test creates a buffer, sets its filetype to rust and asserts maparg for both default keys is empty: "no key by default" is checked where it would matter, in a Rust buffer, not in the empty scratch buffer. Third, the last test pins two names that are part of the plugin’s public surface: the in-process servers are called xyno-crates and xyno-features, which are the names a user sees for these clients in vim.lsp.get_clients().'),
    blank,
    ...sec(r'what is not covered here'),
    ...pt('--', r'keymaps = true', r'it cannot be checked in this file, because the first successful setup() starts the modules for the rest of the process. init-keymaps_spec.lua exists for that, as its own file and therefore its own nvim.'),
    ...pt('--', r'the Neovim version check', r'nothing tests the "Neovim 0.12 or newer is required" branch; the whole suite requires 0.12 to run.'),
    ...pt('--', r'options merging', r'the deep merge of defaults is trusted to vim.tbl_deep_extend and is exercised only indirectly, by the modules table in the third test.'),
    ...sec(r'history'),
    ...para('--', r'One commit: 9d33ca7, "Add specs, a headless runner and a lazy.nvim smoke test", 2026-10-22. The smoke test repeats the one-line-message check against a real lazy.nvim load (tests/e2e/smoke.lua).'),
    blank,
  ],
);
