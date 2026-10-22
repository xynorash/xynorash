import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-macros.nvim/lua/xyno_macros/init.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'init.lua — the front door of the plugin: check, configure, start'),
    cm('--', r'71 lines that decide when the two big modules may run'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'setup() and blink_opts(): validates the environment and wires attrs.lua and tools.lua'),
    kv(r'language', r'Lua (Neovim 0.12+)'),
    kv(r'size', r'71 lines'),
    kv(r'history', r'added in b9854b7 (2026-10-22, Add the xyno_macros modules)'),
    ...sec(r'why this file exists'),
    ...para('--', r'xyno-macros.nvim is two large modules, attrs.lua for completion inside attributes and '
        r'tools.lua for macro help, and both lean on helpers that were extracted into other '
        r'plugins: xyno-rust.nvim for cargo metadata, code actions, file helpers and the Rust '
        r'context, and xyno-imports.nvim for the import engine. In xynovim all of that sat in one '
        r'config directory and a missing module could not happen. Once split, it can. This file is '
        r'where the plugin learns to fail politely. It also hands the two blink.cmp sources to the '
        r'user’s completion config.'),
    ...code('lua', r'lua/xyno_macros/init.lua · lines 1-4', r'''
-- xyno-macros.nvim: macro help for Rust. setup() checks the dependencies, then starts
-- the attribute completion (xyno_macros.attrs) and the macro tools (xyno_macros.tools).
-- The two blink.cmp sources are registered by the user's blink config: M.blink_opts().
local M = {}
'''),
    ...sec(r'options'),
    ...code('lua', r'lua/xyno_macros/init.lua · lines 6-14', r'''
M.defaults = {
  commands = true, -- :MacroAttrs :MacroExpand :MacroFormatFix :MacroSignature :ProcMacroStatus
  keymaps = false, -- false | true | { expand = lhs|false, status = lhs|false, signature = lhs|false } (buffer-local in Rust buffers with rust-analyzer)
  snippets_allowed = nil, -- optional function(ctx) -> boolean: where select!/matches!/vec! snippets may appear
  attrs = {}, -- overrides of the attribute completion's tuning values (xyno_macros.attrs.config)
}

--- Default keys of `keymaps = true`.
M.default_keymaps = { expand = "<leader>rx", status = "<leader>rq", signature = "<C-k>" }
'''),
    ...para('--', r'The four options are the whole configuration. commands decides whether the five user '
        r'commands exist. keymaps is false by default, which is the first design decision visible '
        r'in the repository: the original configuration bound its keys itself, and the extracted '
        r'plugin makes them opt-in, so a plugin never takes a global key unasked. The default key '
        r'table is kept here, separately, so that keymaps = true has something to map. '
        r'snippets_allowed lets the user decide where the select!, matches! and vec! snippets '
        r'appear, and attrs passes tuning values to the attribute completion.'),
    ...sec(r'the dependency check'),
    ...code('lua', r'lua/xyno_macros/init.lua · lines 16-22', r'''
local REQUIRED = {
  { "xyno_rust.crate_meta", "xyno-rust.nvim (xynorash/xyno-rust.nvim)" },
  { "xyno_rust.code_actions", "xyno-rust.nvim (xynorash/xyno-rust.nvim)" },
  { "xyno_rust.fsutil", "xyno-rust.nvim (xynorash/xyno-rust.nvim)" },
  { "xyno_rust.rust_context", "xyno-rust.nvim (xynorash/xyno-rust.nvim)" },
  { "xyno_imports.engine", "xyno-imports.nvim (xynorash/xyno-imports.nvim)" },
}
'''),
    ...para('--', r'The list of required modules is a table of module name and human-readable provider. Five '
        r'modules from two plugins are needed. Listing modules, not plugins, means the check asks '
        r'the question that actually matters, can this code be required, and not whether some '
        r'plugin directory exists on the runtimepath.'),
    ...code('lua', r'lua/xyno_macros/init.lua · lines 24-37', r'''
--- Configure and start the plugin. Safe to call again (autocmd groups are cleared and redefined).
---@param opts? { commands?: boolean, keymaps?: boolean|table<string, string|false>, snippets_allowed?: fun(ctx: table): boolean, attrs?: table }
function M.setup(opts)
  opts = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  if vim.fn.has("nvim-0.12") ~= 1 then
    vim.notify("xyno-macros: Neovim 0.12 or newer is required", vim.log.levels.ERROR)
    return
  end
  for _, req in ipairs(REQUIRED) do
    if not pcall(require, req[1]) then
      vim.notify("xyno-macros: needs " .. req[2] .. ", which is not installed", vim.log.levels.ERROR)
      return
    end
  end
'''),
    ...para('--', r'setup() first merges the user’s options over a deep copy of the defaults, so the table in '
        r'M.defaults is never mutated. Then it checks the Neovim version with has("nvim-0.12") and '
        r'each module with pcall(require). A failure ends with one vim.notify line at ERROR level '
        r'and a plain return: no Lua error, no stack trace, nothing half-started. The end-to-end '
        r'smoke test verifies this in a way that is worth noting: it clears the loaded modules and '
        r'the module search path, calls setup, and asserts that exactly one single-line '
        r'notification was produced and that, for the imports case, it names xyno-imports.'),
    ...code('lua', r'lua/xyno_macros/init.lua · lines 38-50', r'''
  local attrs = require("xyno_macros.attrs")
  for k, v in pairs(opts.attrs) do
    if attrs.config[k] ~= nil then
      attrs.config[k] = v
    end
  end
  attrs.setup({ commands = opts.commands })
  require("xyno_macros.tools").setup({
    commands = opts.commands,
    keymaps = opts.keymaps,
    snippets_allowed = opts.snippets_allowed,
  })
end
'''),
    ...para('--', r'Only after the checks does anything start. The attrs options are applied by iterating the '
        r'user’s table and writing only keys that already exist in attrs.config, so a typo in an '
        r'option name is ignored instead of creating a stray field. attrs.setup registers '
        r':MacroAttrs; tools.setup registers the other four commands, the autocmds and the optional '
        r'keymaps. The doc comment says setup is safe to call again because autocmd groups are '
        r'cleared and redefined; that is true of the autocmds in tools.lua, which use a cleared '
        r'group named xyno_macros.'),
    ...sec(r'the blink.cmp seam'),
    ...code('lua', r'lua/xyno_macros/init.lua · lines 52-69', r'''
--- For blink.cmp: registers both sources (attribute / derive completion with priority over
--- rust-analyzer's path items inside attributes, and the macro snippets). Use it as a lazy.nvim
--- `opts` function of blink.cmp: `opts = function(_, o) return require("xyno_macros").blink_opts(o) end`
--- (also accepts the (_, opts) call shape).
function M.blink_opts(a, b)
  local opts = b or a
  opts.sources = opts.sources or {}
  opts.sources.providers = opts.sources.providers or {}
  opts.sources.providers.macro_attrs = {
    name = "MacroAttrs",
    module = "xyno_macros.attrs",
    -- above rust-analyzer's generic path items (core::, std::, ...) inside attributes
    score_offset = 100,
  }
  opts.sources.per_filetype = opts.sources.per_filetype or {}
  opts.sources.per_filetype.rust = { "macro_attrs", inherit_defaults = true }
  return require("xyno_macros.tools").blink_opts(nil, opts)
end
'''),
    ...para('--', r'The plugin does not reach into blink.cmp. It exposes a function the user calls from their '
        r'own blink spec: blink_opts takes the options table (it accepts both the (opts) and the '
        r'lazy.nvim (_, opts) call shapes), registers the provider macro_attrs with a score_offset '
        r'of 100 and makes it the Rust-specific source list with inherit_defaults, then delegates '
        r'to tools.blink_opts to add the second provider. The comment on the score offset says why: '
        r'attribute and derive completion must outrank rust-analyzer’s generic path items such as '
        r'core:: and std:: inside an attribute. The README’s consequence of this design is stated '
        r'openly: because the blink spec calls require("xyno_macros") when blink starts, the plugin '
        r'loads at startup and its commands exist before a Rust file is opened.'),
    ...sec(r'one duplication to know about'),
    ...para('--', r'The default key table appears twice, here on line 14 and again in tools.lua on line 22, '
        r'with the same three bindings. The copy in tools.lua is the one setup() actually uses when '
        r'keymaps = true, since init.lua passes the user’s value straight through; the copy here is '
        r'never read in the files of this repository. If the defaults were changed in only one '
        r'place they would silently disagree.'),
    ...sec(r'tested by'),
    ...para('--', r'tests/init_spec.lua covers the commands switch, the keymap options and the shipped-schema '
        r'path; tests/e2e/smoke.lua covers the missing-dependency messages and blink_opts.'),
    ...sec(r'history'),
    ...pt('--', r'b9854b7', r'2026-10-22, with attrs.lua and tools.lua. In xynovim the two modules were '
        r'config.macro_attrs and config.macro_tools and had no common setup; this file is new in '
        r'the extraction, together with the options and the dependency check.'),
  ],
);
