import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-new.nvim/tests/init_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'tests/init_spec.lua — the front door under test'),
    cm('--', r'seven cases: setup(), keymaps as data, options as variables, a missing dependency'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'tests', r'lua/xyno_new/init.lua'),
    kv(r'size', r'135 lines, 7 cases in 2 groups'),
    kv(r'needs', r'nothing external: no cargo, no network'),
    kv(r'pattern', r'before_each saves and clears state; after_each restores it'),
    ...sec(r'state hygiene first'),
    ...code('lua', r'tests/init_spec.lua · lines 1-28', r'''
-- xyno_new.setup(): commands, keymaps, options, and the check for xyno-rust.nvim.
local H = require("xyno_new_test.helpers")
local N = require("xyno_new")

local COMMANDS = { "RustNewBin", "RustNewLib", "RustNewWorkspace", "RustNewMember", "EguiNew" }

local saved = {}
before_each(function()
  for _, k in ipairs({ "xyno_new_projects_dir", "xyno_new_egui_template", "xyno_new_egui_build_after_new" }) do
    saved[k] = vim.g[k]
    vim.g[k] = nil
  end
  for _, c in ipairs(COMMANDS) do
    pcall(vim.api.nvim_del_user_command, c)
  end
end)

after_each(function()
  for k, v in pairs(saved) do
    vim.g[k] = v
  end
  for _, c in ipairs(COMMANDS) do
    pcall(vim.api.nvim_del_user_command, c)
  end
  for _, lhs in pairs(N.default_keymaps) do
    pcall(vim.keymap.del, "n", lhs)
  end
end)'''),
    ...para('--', r'Setup tests are about global state, so the file starts with the cleanup. Before each case the three vim.g variables the options write are saved and set to nil and the five commands are deleted (pcall, because the first run has nothing to delete). After each case the variables are restored, the commands are deleted again, and every default keymap is unset. Without this, the case that sets keymaps = true would leave mappings for the next case to trip over, and the case that checks “no keymap by default” would pass or fail by test order.'),
    ...para('--', r'The harness runs the tests of a file in one editor, in order, so the spec does its own cleanup; the runner’s one-process-per-file design limits any leftover state to one file.'),
    ...sec(r'what setup() promises'),
    ...code('lua', r'tests/init_spec.lua · lines 30-46', r'''
describe("setup", function()
  it("defines every command and sets no keymap", function()
    H.ok(N.setup())
    for _, c in ipairs(COMMANDS) do
      H.eq(2, vim.fn.exists(":" .. c), c)
    end
    for _, lhs in pairs(N.default_keymaps) do
      H.eq("", vim.fn.maparg(lhs, "n"), lhs)
    end
  end)

  it("commands = false defines none", function()
    H.ok(N.setup({ commands = false }))
    for _, c in ipairs(COMMANDS) do
      H.eq(0, vim.fn.exists(":" .. c), c)
    end
  end)'''),
    ...para('--', r'The first two cases pin the main contract: with no options every command exists (vim.fn.exists returns 2 for a user command) and no default keymap is mapped; with commands = false none exists, which is 0. Each assertion passes the command name or key as the message, so a failure says which one.'),
    ...code('lua', r'tests/init_spec.lua · lines 48-62', r'''
  it("keymaps = true maps the defaults, a table only the listed ones, false skips one", function()
    N.setup({ keymaps = true })
    for name, lhs in pairs(N.default_keymaps) do
      H.ok(vim.fn.maparg(lhs, "n") ~= "", name)
    end
    H.has(vim.fn.maparg(N.default_keymaps.bin, "n"), "RustNewBin")
    for _, lhs in pairs(N.default_keymaps) do
      pcall(vim.keymap.del, "n", lhs)
    end
    N.setup({ keymaps = { bin = "<leader>zb", lib = false } })
    H.has(vim.fn.maparg("<leader>zb", "n"), "RustNewBin")
    H.eq("", vim.fn.maparg(N.default_keymaps.lib, "n"))
    H.eq("", vim.fn.maparg(N.default_keymaps.egui, "n"))
    pcall(vim.keymap.del, "n", "<leader>zb")
  end)'''),
    ...para('--', r'The keymap case does three things. keymaps = true maps every default and the map for bin contains the command text RustNewBin: maparg returns the right-hand side, so the test sees that the action is wired, not just that a key exists. After removing them, a table form binds bin to a custom key and sets lib = false; the test then checks that the default lib key and the default egui key stay unmapped. The last assertion is subtle: a table maps only the listed actions, not the rest of the defaults.'),
    ...code('lua', r'tests/init_spec.lua · lines 64-83', r'''
  it("the options set the variables the modules read", function()
    N.setup({ projects_dir = "/some/where", egui_build_after_new = true, egui_template = { ref = "v1" } })
    H.eq("/some/where", vim.g.xyno_new_projects_dir)
    H.eq(true, vim.g.xyno_new_egui_build_after_new)
    H.eq({ ref = "v1" }, vim.g.xyno_new_egui_template)
    H.eq("/some/where", require("xyno_new.egui").default_parent())
  end)

  it("without options the variables stay as they are", function()
    vim.g.xyno_new_projects_dir = "/mine"
    N.setup({})
    H.eq("/mine", vim.g.xyno_new_projects_dir)
  end)

  it("is safe to call twice", function()
    H.ok(N.setup())
    H.ok(N.setup())
    H.eq(2, vim.fn.exists(":RustNewBin"))
  end)
end)'''),
    ...para('--', r'Options become variables only when given. The case with projects_dir, egui_build_after_new and egui_template checks the three vim.g values and, as a closing assertion, that egui.default_parent() reads the new directory, which proves the modules read the same variable init.lua wrote. The next case sets the variable first, calls setup({}), and checks that the variable survived. Calling setup twice returns true both times and the commands still exist.'),
    ...sec(r'the missing dependency'),
    ...code('lua', r'tests/init_spec.lua · lines 85-116', r'''
describe("xyno-rust.nvim missing", function()
  it("one error notification, no Lua error, no commands", function()
    local hidden = {}
    for _, m in ipairs({ "xyno_rust.rust_context", "xyno_rust.fsutil" }) do
      hidden[m] = package.loaded[m]
      package.loaded[m] = nil
    end
    -- LuaJIT's package.loaders: only a loader that refuses xyno_rust is left
    local saved_loaders = {}
    for i, f in ipairs(package.loaders) do
      saved_loaders[i] = f
    end
    local n = #package.loaders
    package.loaders[1] = function(name)
      if name:match("^xyno_rust") then
        return "\n\tno module '" .. name .. "'"
      end
    end
    for i = 2, n do
      package.loaders[i] = nil
    end
    package.loaders[2] = function(name)
      if not name:match("^xyno_rust") then
        for _, f in ipairs(saved_loaders) do
          local r = f(name)
          if type(r) == "function" then
            return r
          end
        end
      end
      return "\n\tno module"
    end'''),
    ...para('--', r'Making a Lua module disappear is awkward in LuaJIT. The test first removes xyno_rust.rust_context and xyno_rust.fsutil from package.loaded, saving them. Then it rewrites package.loaders (the LuaJIT name for package.searchers): the first loader is replaced by one that answers with a “no module” string for any name starting with xyno_rust, every other slot is cleared, and the second slot becomes a loader that consults the saved original loaders for every name that is not xyno_rust. The result is a require that behaves as if only that plugin were uninstalled.'),
    ...code('lua', r'tests/init_spec.lua · lines 117-135', r'''
    local cap = H.capture_notify()
    local ok, res = pcall(N.setup)
    for i = 1, n do
      package.loaders[i] = saved_loaders[i]
    end
    for m, v in pairs(hidden) do
      package.loaded[m] = v
    end
    H.ok(ok, "setup() must not raise")
    H.eq(false, res)
    H.eq(1, #cap.list, "exactly one notification")
    H.has(cap.list[1].msg, "xyno-rust.nvim")
    H.not_ok(cap.list[1].msg:find("\n", 1, true), "one line")
    H.eq(vim.log.levels.ERROR, cap.list[1].level)
    for _, c in ipairs(COMMANDS) do
      H.eq(0, vim.fn.exists(":" .. c), c)
    end
  end)
end)'''),
    ...para('--', r'Then the assertions. setup is called under pcall so that a raised error can be told apart from a returned false: ok must be true (no Lua error) and the result must be false. The notify function is captured by H.capture_notify; the case expects exactly one notification, containing xyno-rust.nvim, without a line break, at ERROR level. Finally none of the commands exists. The loaders and the package.loaded entries are restored before the assertions, so a failure cannot leave later tests running without the sibling plugin.'),
    ...sec(r'what is not tested here'),
    ...pt('--', r'Neovim older than 0.12', r'the version gate in setup() is not exercised; the test would need to fake vim.fn.has.'),
    ...pt('--', r'The lazy.nvim path', r'covered by tests/e2e/smoke.lua rather than here.'),
    ...pt('--', r'What the commands do', r'that is the job of rust-new_spec.lua and egui-new_spec.lua.'),
    ...sec(r'history'),
    ...para('--', r'Added in 1de2687 on 2026-10-22. It has no counterpart in xynovim, since the front door is new.'),
  ],
);
