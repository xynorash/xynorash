import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-macros.nvim/tests/init_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'init_spec.lua — the options of setup(): commands, keymaps, snippets, schema path'),
    cm('--', r'five tests, 86 lines'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'the spec of xyno_macros.setup()'),
    kv(r'language', r'Lua on the repo harness'),
    kv(r'size', r'86 lines, 5 tests in one describe group'),
    kv(r'history', r'added in 08b2e8f (2026-10-22), unchanged since'),
    ...sec(r'why this file exists'),
    ...para('--', r'The options of setup are the part of the plugin a user touches first, so they get their '
        r'own small spec, separate from the two large ones. It covers the opt-in design: no keys '
        r'without being asked, commands switchable, snippet guard replaceable, schemas found in the '
        r'plugin directory.'),
    ...code('lua', r'tests/init_spec.lua · lines 1-3', r'''
-- xyno_macros.setup(): options, opt-in keymaps, commands switch, snippet guard and the
-- one-line message when a dependency is missing.
local H = require("xyno_macros_test.helpers")
'''),
    ...para('--', r'That header is not fully accurate. It promises a test for the one-line message when a '
        r'dependency is missing, but none of the five tests does that; the check lives in '
        r'tests/e2e/smoke.lua, where it removes the modules and asserts a single-line notification. '
        r'The comment is a leftover of an earlier plan, and the behaviour is covered, only '
        r'elsewhere.'),
    ...sec(r'cleaning up between tests'),
    ...code('lua', r'tests/init_spec.lua · lines 5-15', r'''
local mt = require("xyno_macros.tools")

local ALL = { "MacroAttrs", "MacroExpand", "MacroFormatFix", "MacroSignature", "ProcMacroStatus" }

after_each(function()
  pcall(vim.cmd, "silent! %bwipeout!")
  for _, c in ipairs(ALL) do
    pcall(vim.api.nvim_del_user_command, c)
  end
  mt.config.snippets_allowed = nil
end)
'''),
    ...para('--', r'Every test wipes the buffers, deletes all five user commands in pcall and clears the '
        r'snippet option, so a test that failed half way cannot leave a command defined for the '
        r'next.'),
    ...sec(r'defaults and the switch'),
    ...code('lua', r'tests/init_spec.lua · lines 17-30', r'''
describe("setup", function()
  it("registers the five commands and sets no keymap by default", function()
    M.setup({})
    for _, c in ipairs(ALL) do
      H.eq(2, vim.fn.exists(":" .. c), c)
    end
    H.eq("", vim.fn.maparg("<leader>rx", "n"))
    H.eq("", vim.fn.maparg("<leader>rq", "n"))
  end)

  it("commands = false registers none", function()
    M.setup({ commands = false })
    for _, c in ipairs(ALL) do
      H.eq(0, vim.fn.exists(":" .. c), c)
'''),
    ...para('--', r'The first test asserts the default: after setup with no options, all five commands exist '
        r'(vim.fn.exists returns 2) and neither <leader>rx nor <leader>rq is mapped. The second '
        r'shows commands = false: none of them exist, which returns 0.'),
    ...sec(r'buffer-local keys'),
    ...code('lua', r'tests/init_spec.lua · lines 32-61', r'''
  end)

  it("keymaps = true maps buffer-local keys when a client is attached, a table maps only what it lists", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "rust"
    local ca = require("xyno_rust.code_actions")
    local orig = ca.clients
    ca.clients = function()
      return { {} }
    end
    local function keys_after(opts)
      M.setup(opts)
      vim.api.nvim_exec_autocmds("LspAttach", { buffer = buf, data = { client_id = 1 } })
      H.wait_for(function()
        return vim.fn.maparg("<leader>rx", "n", false, true).buffer == 1 or vim.fn.maparg("<C-s>", "i", false, true).buffer == 1
      end, 3000, "the buffer-local key")
    end
    local ok, err = pcall(function()
      keys_after({ keymaps = true })
      H.eq("Expand macro under cursor (lens)", vim.fn.maparg("<leader>rx", "n", false, true).desc)
      H.eq("Proc-macro status", vim.fn.maparg("<leader>rq", "n", false, true).desc)
      H.eq("Macro / signature help", vim.fn.maparg("<C-k>", "i", false, true).desc)
      H.eq(1, vim.fn.maparg("<leader>rx", "n", false, true).buffer, "buffer-local")
      vim.keymap.del("n", "<leader>rx", { buffer = buf })
      vim.keymap.del("n", "<leader>rq", { buffer = buf })
      vim.keymap.del("i", "<C-k>", { buffer = buf })
      keys_after({ keymaps = { signature = "<C-s>", expand = false } })
      H.eq("Macro / signature help", vim.fn.maparg("<C-s>", "i", false, true).desc)
      H.eq("", vim.fn.maparg("<leader>rx", "n"))
'''),
    ...para('--', r'This is the most careful test of the file. It creates a Rust buffer and temporarily '
        r'replaces the function that lists rust-analyzer clients, so the plugin believes a client '
        r'is attached. After setup with keymaps = true and a synthetic LspAttach event, it waits '
        r'for a buffer-local map to appear (the wait exists because the plugin applies keys 120 '
        r'milliseconds after attach) and asserts the three descriptions and that the map is '
        r'buffer-local. It deletes them and sets up again with a table that gives only the '
        r'signature key a new lhs and turns expand off; then it asserts the new key exists and that '
        r'neither the expand nor the unlisted status key is mapped. The original function is '
        r'restored in all cases and the first error is re-raised afterwards.'),
    ...sec(r'the snippet guard and the shipped schemas'),
    ...code('lua', r'tests/init_spec.lua · lines 63-72', r'''
    end)
    ca.clients = orig
    if not ok then
      error(err, 0)
    end
  end)

  it("snippets_allowed: the default refuses after a dot, the option replaces it", function()
    M.setup({})
    local buf = vim.api.nvim_create_buf(true, false)
'''),
    ...para('--', r'The snippet test shows the default refusing after a dot and the user function replacing '
        r'it. It calls setup twice to prove the second call replaces the first.'),
    ...code('lua', r'tests/init_spec.lua · lines 74-85', r'''
    H.eq(false, mt.snippets_allowed({ line = "    x.sel", cursor = { 1, 9 }, bufnr = buf }))
    M.setup({ snippets_allowed = function()
      return false
    end })
    H.eq(false, mt.snippets_allowed({ line = "    sel", cursor = { 1, 7 }, bufnr = buf }))
  end)

  it("the shipped schemas are read from the plugin directory", function()
    local shipped = require("xyno_macros.attrs").shipped()
    H.ok(shipped.serde and shipped.clap and shipped.tokio and shipped.sqlx, "serde, clap, tokio, sqlx")
    H.eq(H.repo .. "/data/macro_attrs/serde.json", shipped.serde.source)
  end)
'''),
    ...para('--', r'The last test reads the shipped schemas from the plugin directory and checks that serde, '
        r'clap, tokio and sqlx are present, and that the recorded source of the serde schema is the '
        r'path under the repository root. It is the test that stops a change to the data location '
        r'from silently emptying the completion.'),
    ...sec(r'history'),
    ...pt('--', r'08b2e8f', r'2026-10-22: the spec arrives with the others.'),
  ],
);
