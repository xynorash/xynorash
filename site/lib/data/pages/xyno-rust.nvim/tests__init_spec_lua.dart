import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/tests/init_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'tests/init_spec.lua — what setup() promises, written down as tests'),
    cm('--', r'commands, module switches, opt-in keymaps, and the one-line error without snacks.nvim'),
    cm('--', r'──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/xyno_rust/init.lua, the public entry point'),
    kv(r'language', r'Lua, run by tests/run.lua'),
    kv(r'size', r'133 lines, 9 tests in 3 describe blocks, 1 commit in this repo (7c1d2d9)'),
    kv(r'origin', r'written for this repository; xynovim had no setup() to test'),
    kv(r'needs', r'nothing external, except one test that only runs where snacks.nvim is absent'),
    ...sec(r'why this file exists'),
    ...para('--', r'Most of the other specs in tests/ were adapted from xynovim, where the Rust modules were loaded '
        r'by a plain configuration and nobody called a function named setup. When the code became a '
        r'plugin, init.lua was the one new piece of logic: a table of defaults, a version gate, a '
        r'switch per module, and an opt-in set of buffer-local keymaps. That is the surface other '
        r'people’s configuration touches, so it is the part where a silent change breaks a user '
        r'without breaking any older spec. init_spec.lua is written from scratch to pin it.'),
    ...para('--', r'It checks promises, not internals. Each test is one sentence from the README or the '
        r'vimdoc turned into an assertion: every documented command exists, commands = false '
        r'defines none, a module can be switched off, keymaps are off by default, a table maps only '
        r'what it lists, calling setup twice does not stack autocmds, and a missing optional plugin '
        r'costs one error line instead of a Lua traceback.'),
    ...sec(r'the code being pinned'),
    ...code('lua', r'lua/xyno_rust/init.lua · lines 3-16', r'''
local M = {}

M.defaults = {
  commands = true, -- :RustContext :RustTargets :RustTools :ActJob :RustNew :RustRoutes :RustRestart
  keymaps = false, -- false | true | { context = lhs, targets = lhs, ... } (buffer-local in Rust files)
  modules = {
    context = true, -- xyno_rust.rust_context: per-project features / target
    tasks = true, -- xyno_rust.rust_tasks: targets, tools, :RustNew, :ActJob
    routes = true, -- xyno_rust.rust_routes: HTTP route picker
    status = true, -- xyno_rust.lsp_status: readiness indicator (event driven)
    restart = true, -- xyno_rust.rust_restart: server supervision
  },
}

'''),
    ...code('lua', r'lua/xyno_rust/init.lua · lines 61-92', r'''
        local action = ACTIONS[name]
        if action and type(lhs) == "string" then
          vim.keymap.set("n", lhs, action[1], { buffer = ev.buf, desc = action[2] })
        end
      end
    end,
  })
  -- a Rust buffer that is already open
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "rust" then
      vim.api.nvim_exec_autocmds("FileType", { group = group, buffer = buf })
    end
  end
end

--- Configure and start the plugin. Safe to call again (autocmd groups are cleared and redefined).
---@param opts? { commands?: boolean, keymaps?: boolean|table<string, string|false>, modules?: table<string, boolean> }
function M.setup(opts)
  opts = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  if vim.fn.has("nvim-0.12") ~= 1 then
    vim.notify("xyno-rust: Neovim 0.12 or newer is required", vim.log.levels.ERROR)
    return
  end
  local sub = { commands = opts.commands }
  local m = opts.modules
  if m.context then
    require("xyno_rust.rust_context").setup(sub)
  end
  if m.tasks then
    require("xyno_rust.rust_tasks").setup(sub)
  end
  if m.routes then
'''),
    ...sec(r'the helpers at the top of the spec'),
    ...code('lua', r'tests/init_spec.lua · lines 1-25', r'''
-- xyno_rust.setup(): commands, module switches, keymaps and the missing-plugin messages.
local H = require("xyno_rust_test.helpers")
local rust = require("xyno_rust")

local COMMANDS = { "RustContext", "RustTargets", "RustTools", "ActJob", "RustNew", "RustRoutes", "RustRestart" }

local function clear_commands()
  for _, c in ipairs(COMMANDS) do
    pcall(vim.api.nvim_del_user_command, c)
  end
end

local function buf_map(buf, lhs)
  return vim.api.nvim_buf_call(buf, function()
    return vim.fn.maparg(lhs, "n", false, true)
  end)
end

local function rust_buf()
  local dir = H.tmpdir()
  vim.fn.writefile({ "fn main() {}" }, dir .. "/a.rs")
  vim.cmd.edit(vim.fn.fnameescape(dir .. "/a.rs"))
  vim.bo.filetype = "rust"
  return vim.api.nvim_get_current_buf()
end
'''),
    ...para('--', r'Three small helpers carry the whole file.'),
    ...pt('--', r'clear_commands', r'deletes the seven user commands with pcall(nvim_del_user_command). setup() is called many '
        r'times in one Neovim process, because the runner loads one spec file per process, not one '
        r'test. Without this reset a command defined by an earlier test would make a later exists() '
        r'check pass for the wrong reason.'),
    ...pt('--', r'buf_map', r'reads a mapping inside the right buffer with nvim_buf_call and maparg(lhs, "n", false, '
        r'true), which returns a dictionary. The fourth argument is what makes it possible to read '
        r'the buffer field and the desc of a mapping instead of a string.'),
    ...pt('--', r'rust_buf', r'writes a one-line a.rs into a fresh temp directory, edits it and sets the filetype to '
        r'rust by hand. The keymaps are attached by a FileType autocmd, so setting filetype is the '
        r'trigger, and no rust-analyzer or parser is involved.'),
    ...para('--', r'Note the list COMMANDS. It is duplicated here from the defaults comment in init.lua and '
        r'again in tests/e2e/smoke.lua, so the three places have to agree. If a command is added to '
        r'the plugin, the lists have to be updated together.'),
    ...sec(r'the setup block'),
    ...code('lua', r'tests/init_spec.lua · lines 27-70', r'''
describe("setup", function()
  before_each(clear_commands)
  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, "xyno_rust_keymaps")
    pcall(vim.cmd, "silent! %bwipeout!")
  end)

  it("defines every documented command", function()
    rust.setup()
    for _, c in ipairs(COMMANDS) do
      H.eq(2, vim.fn.exists(":" .. c), c)
    end
  end)

  it("defines no command with commands = false, and sets no key by default", function()
    rust.setup({ commands = false })
    for _, c in ipairs(COMMANDS) do
      H.eq(0, vim.fn.exists(":" .. c), c)
    end
    rust.setup({ commands = false, keymaps = false })
    H.eq(false, pcall(vim.api.nvim_get_autocmds, { group = "xyno_rust_keymaps" }))
  end)

  it("modules = { x = false } leaves that module out", function()
    rust.setup({ modules = { routes = false, restart = false } })
    H.eq(0, vim.fn.exists(":RustRoutes"))
    H.eq(0, vim.fn.exists(":RustRestart"))
    H.eq(2, vim.fn.exists(":RustContext"))
  end)

  it("registers the autocmd groups of the status and restart modules", function()
    rust.setup()
    H.ok(#vim.api.nvim_get_autocmds({ group = "xyno_rust_lsp_status" }) >= 3)
    H.ok(#vim.api.nvim_get_autocmds({ group = "xyno_rust_restart" }) >= 3)
  end)

  it("calling setup() twice does not duplicate autocmds", function()
    rust.setup()
    local n = #vim.api.nvim_get_autocmds({ group = "xyno_rust_restart" })
    rust.setup()
    H.eq(n, #vim.api.nvim_get_autocmds({ group = "xyno_rust_restart" }))
  end)
end)

'''),
    ...pt('--', r'defines every documented command', r'after setup() with no options, vim.fn.exists(":Name") is 2 for each of the seven names. '
        r'exists returns 2 for a user command, 3 for a function; the spec fixes the number rather '
        r'than just truthiness.'),
    ...pt('--', r'commands = false', r'the same loop expects 0. The second half then calls setup with commands = false and '
        r'keymaps = false and expects that nvim_get_autocmds on the group xyno_rust_keymaps raises, '
        r'because the group was never created. pcall returns false and the spec compares it to '
        r'false with H.eq.'),
    ...pt('--', r'modules = { routes = false, restart = false }', r'after this call :RustRoutes and :RustRestart do not exist but :RustContext does. This is '
        r'the test of the deep merge in setup(): vim.tbl_deep_extend("force", defaults, opts) keeps '
        r'the other modules true.'),
    ...pt('--', r'the autocmd groups', r'the status and restart modules each own a group (xyno_rust_lsp_status and '
        r'xyno_rust_restart) with at least three autocmds. The count is a lower bound on purpose, '
        r'so adding a fourth event does not break the spec.'),
    ...pt('--', r'calling setup() twice', r'records how many autocmds the restart group has, calls setup again and expects the same '
        r'number. The groups are created with clear = true, so a second call replaces them. '
        r'The spec compares the autocmd count before and after the second call.'),
    ...para('--', r'The after_each block deletes the keymaps augroup and runs silent! %bwipeout! so the '
        r'buffers and mappings of one test cannot leak into the next.'),
    ...sec(r'the keymaps block'),
    ...code('lua', r'tests/init_spec.lua · lines 72-110', r'''
  before_each(clear_commands)
  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, "xyno_rust_keymaps")
    pcall(vim.cmd, "silent! %bwipeout!")
  end)

  it("keymaps = true maps the defaults buffer-locally in Rust buffers only", function()
    rust.setup({ keymaps = true })
    local buf = rust_buf()
    for name, lhs in pairs(rust.default_keymaps) do
      local m = buf_map(buf, lhs)
      H.eq(1, m.buffer, name)
      H.ok(m.desc and m.desc ~= "", name .. " has a description")
    end
    H.eq("<cmd>rustcontext<cr>", buf_map(buf, rust.default_keymaps.context).rhs:lower())
    vim.cmd.enew()
    H.eq(0, buf_map(vim.api.nvim_get_current_buf(), rust.default_keymaps.context).buffer or 0)
  end)

  it("a table maps only the listed actions, with the keys given", function()
    rust.setup({ keymaps = { context = "<leader>zc", targets = false } })
    local buf = rust_buf()
    H.eq(1, buf_map(buf, "<leader>zc").buffer)
    H.eq(0, buf_map(buf, rust.default_keymaps.targets).buffer or 0)
    H.eq(0, buf_map(buf, rust.default_keymaps.context).buffer or 0)
  end)

  it("keymaps = false (the default) sets nothing", function()
    rust.setup()
    local buf = rust_buf()
    for _, lhs in pairs(rust.default_keymaps) do
      H.eq(0, buf_map(buf, lhs).buffer or 0, lhs)
    end
  end)
end)

describe("snacks.nvim is optional", function()
  it("a picker command without it is one error line, not a Lua error", function()
    local orig = rawget(_G, "Snacks")
'''),
    ...para('--', r'Keymaps are the part with the most ways to be wrong, so they get the most careful tests.'),
    ...pt('--', r'true maps the defaults, buffer-locally, in Rust buffers only', r'for every entry of rust.default_keymaps the test reads the mapping in the Rust buffer and '
        r'expects buffer = 1 and a non-empty desc, so every key carries a description. It checks '
        r'the right-hand side of the context key lowercased, to compare with the string '
        r'<cmd>rustcontext<cr> whatever case Neovim stored. Then it opens an unnamed buffer with '
        r'enew and expects no buffer-local mapping for the same key. This is the test that says the '
        r'keys never leak outside Rust files.'),
    ...pt('--', r'a table maps only the listed actions', r'with { context = "<leader>zc", targets = false }, the custom key is mapped, the default '
        r'key of targets is not, and the default key of context is not either. A table replaces the '
        r'default set; it does not add to it.'),
    ...pt('--', r'false, the default, sets nothing', r'every default key reads back as no buffer-local mapping.'),
    ...para('--', r'Two behaviours of init.lua are not tested here. The loop at the end of map_keys that '
        r'fires FileType for Rust buffers already loaded when setup runs is never reached, because '
        r'every test sets up first and creates the buffer afterwards. And the check that a value '
        r'must be a string, so that entries set to false are skipped, is exercised only through the '
        r'targets = false case.'),
    ...sec(r'snacks.nvim is optional'),
    ...code('lua', r'tests/init_spec.lua · lines 112-133', r'''
    local cap = H.capture_notify()
    local ok, err = pcall(function()
      -- (this spec runs where snacks.nvim is not installed; skip if it is)
      if pcall(require, "snacks") then
        require("xyno_rust_test.harness").skip("snacks.nvim is installed here")
      end
      local dir = H.fixture("basic")
      vim.cmd.cd(vim.fn.fnameescape(dir))
      vim.cmd.edit(vim.fn.fnameescape(dir .. "/src/lib.rs"))
      rust.setup()
      vim.cmd("RustTools")
    end)
    cap.restore()
    _G.Snacks = orig
    if not ok then
      error(err, 0)
    end
    local last = cap.list[#cap.list]
    H.eq(vim.log.levels.ERROR, last and last.level)
    H.eq("xyno-rust: snacks.nvim is required for pickers and terminals (folke/snacks.nvim)", last and last.msg)
  end)
end)
'''),
    ...para('--', r'This is the longest test and the one that protects a user who installed the plugin '
        r'without snacks.nvim. The pickers and terminals need snacks, but the plugin does not want '
        r'it as a hard dependency, so require("xyno_rust.deps").snacks() returns nil and notifies '
        r'one ERROR line. The test checks that the whole path through the :RustTools command ends '
        r'there.'),
    ...para('--', r'Steps, in the order of the code. Save and clear the global Snacks. Capture vim.notify. '
        r'Inside a pcall: if require("snacks") succeeds anywhere on the runtimepath, skip the test '
        r'with the reason snacks.nvim is installed here, since a real picker would open. Otherwise '
        r'change into the basic fixture, edit its src/lib.rs, call setup and run :RustTools. After '
        r'the pcall, restore both the notify function and the Snacks global, and only then rethrow '
        r'an error, if any, with error(err, 0).'),
    ...para('--', r'The order matters. Restoring first and rethrowing afterwards means a failed test cannot '
        r'leave the next one without its vim.notify. The skip is itself an error object, which is '
        r'why the same rethrow handles it correctly: the runner recognises the skip and prints SKIP.'),
    ...para('--', r'The assertion is exact: the last notification has level ERROR and the message xyno-rust: '
        r'snacks.nvim is required for pickers and terminals (folke/snacks.nvim). A change in the '
        r'wording of deps.lua fails this test, which is intended, since the message is the only '
        r'help the user gets.'),
    ...para('--', r'Why :RustTools? In rust_tasks.lua the tools picker finds the workspace root first, builds '
        r'its item list and only then asks for snacks (lines 197-231, M.tools), so the command runs the real '
        r'code up to the dependency check. Using a real fixture crate also proves the root lookup '
        r'works before the failure.'),
    ...sec(r'what a failure here means'),
    ...pt('--', r'a command test fails', r'the documented surface changed. Either the code lost a command or the docs and COMMANDS '
        r'list are out of date.'),
    ...pt('--', r'a keymap test fails', r'a user who opted in gets keys in the wrong buffers, or no description in which-key, or '
        r'loses a custom key.'),
    ...pt('--', r'the snacks test fails', r'someone replaced the one-line message with a plain require, and users without snacks see '
        r'a traceback.'),
    ...sec(r'history'),
    ...para('--', r'This file has one commit in the repository. It arrived in 7c1d2d9 (2026-10-22, Add specs, '
        r'a headless runner and a lazy.nvim smoke test) together with the other specs, the runner '
        r'and the fixtures. The code it tests arrived one step earlier in c1c7958 (Add the '
        r'xyno_rust modules), whose message names setup() with commands, module switches and opt-in '
        r'keymaps as the one new thing next to the extracted files.'),
    ...para('--', r'xynovim has no setup() and so no spec of this kind; the spec has no ancestor there. Its '
        r'only neighbours in the history are the module specs, which call the modules directly and '
        r'never go through setup.'),
  ],
);
