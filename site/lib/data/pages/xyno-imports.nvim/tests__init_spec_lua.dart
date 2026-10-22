import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-imports.nvim/tests/init_spec.lua',
  lines: [
    cm(r'''--''', r'''──────────────────────────────────────────'''),
    cm(r'''--''', r'''init_spec.lua — the front door, including the broken one'''),
    cm(r'''--''', r'''six cases: commands, keys, mode, and the missing dependency'''),
    cm(r'''--''', r'''──────────────────────────────────────────'''),
    blank,
    kv(r'''role''', r'''specs of xyno_imports.setup()'''),
    kv(r'''language''', r'''Lua, run by tests/run.lua'''),
    kv(r'''size''', r'''94 lines, 6 cases, one after_each'''),
    kv(r'''parser''', r'''one case needs the tree-sitter rust parser and skips without it'''),
    ...sec(r'''why this file exists'''),
    ...para(r'''--''', r'''init.lua is 38 lines and engine_spec.lua already tests the engine, so what is left to test is the contract with the person who installs the plugin: the commands appear, no key is taken unless asked, the options reach the engine, and a missing dependency produces a sentence instead of a traceback. These are the promises in the README, and each case maps to one of them. The file is the only spec for init.lua and was added with the other specs in 45d98cb.'''),
    blank,
    ...sec(r'''the shared teardown'''),
    ...para(r'''--''', r'''setup() has global effects: user commands, an autocommand group, buffer-local maps, and values on the engine. The after_each restores the default mode and debounce, clears the global override, wipes every buffer, and deletes the three commands, each in pcall so that a command that was never defined does not fail the cleanup. The saved values are captured at load time at the top of the file.'''),
    blank,
    ...code('lua', r'tests/init_spec.lua · lines 7-7, 9-17', r'''
local saved_mode, saved_debounce = E.default_mode, E.config.debounce
...
after_each(function()
  E.default_mode = saved_mode
  E.config.debounce = saved_debounce
  vim.g.xyno_auto_import = nil
  pcall(vim.cmd, "silent! %bwipeout!")
  for _, c in ipairs({ "ImportName", "ImportForget", "ImportOrganize" }) do
    pcall(vim.api.nvim_del_user_command, c)
  end
end)'''),

    ...sec(r'''commands and keys'''),
    ...para(r'''--''', r'''The first case calls setup with no options and asserts three commands exist (exists returns 2 for a user command), then opens a Rust buffer and asserts that neither default key is mapped. Because maparg is asked after the buffer exists, the test shows that opt-in is real, not merely that nothing was mapped before the FileType event. The case calls need_parser before creating the buffer, so it is skipped when no Rust parser is installed.'''),
    blank,
    ...code('lua', r'tests/init_spec.lua · lines 20-31, 33-38', r'''
  it("registers the three commands and sets no keymap by default", function()
    I.setup({})
    for _, c in ipairs({ "ImportName", "ImportForget", "ImportOrganize" }) do
      H.eq(2, vim.fn.exists(":" .. c), c)
    end
    H.need_parser("rust")
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "rust"
    H.eq("", vim.fn.maparg("<leader>rI", "n"))
    H.eq("", vim.fn.maparg("<leader>rO", "n"))
  end)
...
  it("commands = false registers none", function()
    I.setup({ commands = false })
    for _, c in ipairs({ "ImportName", "ImportForget", "ImportOrganize" }) do
      H.eq(0, vim.fn.exists(":" .. c), c)
    end
  end)'''),

    ...para(r'''--''', r'''Then the keys. keymaps = true maps both default keys, and the assertion checks the buffer flag of the mapping, so a global map would fail it. The table form maps only what it lists: import goes to <leader>ci, and organize = false skips the second action. The same case asserts that the default <leader>rI is not mapped, which a sloppy implementation falling back to defaults would break.'''),
    blank,
    ...code('lua', r'tests/init_spec.lua · lines 40-47, 49-57', r'''
  it("keymaps = true maps the default keys, buffer-local in Rust files", function()
    I.setup({ keymaps = true })
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "rust"
    H.eq(1, vim.fn.maparg("<leader>rI", "n", false, true).buffer)
    H.eq(1, vim.fn.maparg("<leader>rO", "n", false, true).buffer)
  end)
...
  it("a keymaps table maps only what it lists, false skips one", function()
    I.setup({ keymaps = { import = "<leader>ci", organize = false } })
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "rust"
    H.eq(1, vim.fn.maparg("<leader>ci", "n", false, true).buffer)
    H.eq("", vim.fn.maparg("<leader>rO", "n"))
    H.eq("", vim.fn.maparg("<leader>rI", "n"))
  end)'''),

    ...sec(r'''mode, config and the global'''),
    ...para(r'''--''', r'''One case covers four facts. The mode option reaches the engine. A config override is applied (debounce 55). A key the engine does not have (nonsense) is not created. And the global wins: vim.g.xyno_auto_import = "off" overrides the option, while an invalid value such as "bogus" falls back to the configured mode, single. The last assertion is the useful one, since it shows the global is validated and cannot put the engine into an undefined state.'''),
    blank,
    ...code('lua', r'tests/init_spec.lua · lines 59-68', r'''
  it("mode and config options reach the engine; vim.g.xyno_auto_import wins", function()
    I.setup({ mode = "single", config = { debounce = 55, nonsense = 1 } })
    H.eq("single", E.mode())
    H.eq(55, E.config.debounce)
    H.is_nil(E.config.nonsense)
    vim.g.xyno_auto_import = "off"
    H.eq("off", E.mode())
    vim.g.xyno_auto_import = "bogus"
    H.eq("single", E.mode())
  end)'''),

    ...sec(r'''the missing dependency'''),
    ...para(r'''--''', r'''The case that took the most thought is the last: without xyno-rust.nvim there is one notification line, no Lua error, and nothing started. To make require fail for real, the test captures notifications, saves the three xyno_rust modules out of package.loaded, replaces package.loaders with a single loader that returns nil, and empties the runtime path. Then it calls setup under pcall, restores everything, and asserts. Restoration happens before the assertions, so a failing case cannot poison the next one.'''),
    blank,
    ...code('lua', r'tests/init_spec.lua · lines 70-93', r'''
  it("without xyno-rust.nvim: one notification line, no Lua error, nothing started", function()
    local notes = H.capture_notify()
    local saved = {}
    for _, k in ipairs({ "xyno_rust.crate_meta", "xyno_rust.code_actions", "xyno_rust.fsutil" }) do
      saved[k] = package.loaded[k]
      package.loaded[k] = nil
    end
    local rtp, loaders = vim.o.runtimepath, package.loaders
    package.loaders = { function() return nil end }
    vim.o.runtimepath = ""
    local ok, err = pcall(I.setup, {})
    vim.o.runtimepath = rtp
    package.loaders = loaders
    for k, v in pairs(saved) do
      package.loaded[k] = v
    end
    H.ok(ok, tostring(err))
    notes.restore()
    H.eq(1, #notes.list)
    H.match(notes.list[1].msg, "xyno-rust.nvim", true)
    H.not_ok(notes.list[1].msg:find("\n"))
    H.eq(vim.log.levels.ERROR, notes.list[1].level)
    H.eq(0, vim.fn.exists(":ImportName"))
  end)'''),

    ...para(r'''--''', r'''The assertions are exact: pcall succeeded, one notification, its text mentions xyno-rust.nvim, it has no newline, its level is ERROR, and the command ImportName does not exist. That last line proves the early return happens before engine.setup, which is what keeps a plugin installed without its dependency from half-working. tests/e2e/smoke.lua repeats this case with lazy.nvim in the loop.'''),
    blank,
    ...sec(r'''limits'''),
    ...pt(r'''--''', r'''Mutation of globals''', r'''the module loader trick changes package.loaders and the runtime path for the duration of the case, and the case restores them afterwards.'''),
    ...pt(r'''--''', r'''No test for the version check''', r'''the 0.12 guard is not exercised; CI pins Neovim 0.12.5 so it cannot fire there.'''),
    ...pt(r'''--''', r'''Defaults are asserted by effect''', r'''the table M.defaults is not compared directly, so changing a default is caught only where it changes behaviour.'''),
    ...sec(r'''history'''),
    ...pt(r'''--''', r'''45d98cb 2026-10-22''', r'''"Add specs, a headless runner and a lazy.nvim smoke test": 94 lines, unchanged since.'''),
  ],
);
