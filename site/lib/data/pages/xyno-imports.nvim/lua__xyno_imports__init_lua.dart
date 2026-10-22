import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-imports.nvim/lua/xyno_imports/init.lua',
  lines: [
    cm(r'''--''', r'''──────────────────────────────────────────'''),
    cm(r'''--''', r'''init.lua — setup(): check, merge, hand over'''),
    cm(r'''--''', r'''38 lines between your lazy.nvim spec and the engine'''),
    cm(r'''--''', r'''──────────────────────────────────────────'''),
    blank,
    kv(r'''role''', r'''public entry point: require("xyno_imports").setup(opts)'''),
    kv(r'''language''', r'''Lua'''),
    kv(r'''size''', r'''38 lines, one function, two tables'''),
    kv(r'''guards''', r'''Neovim 0.12+, and three xyno_rust modules that must load'''),
    kv(r'''tested by''', r'''tests/init_spec.lua, 6 cases'''),
    ...sec(r'''why this file exists'''),
    ...para(r'''--''', r'''In xynovim the engine was loaded by a plugin spec that waited for VeryLazy and then called require("config.import_engine").setup() with no arguments. It was configured by the global vim.g.xynovim_auto_import, and the engine bound its own keys. A standalone plugin needs a front door that takes options, says clearly what is missing, and does not leave half a plugin behind. This file is that door, and it was written for the extraction: it first appears in 0e6c052 on 2026-10-22, 38 lines, and has not changed since.'''),
    blank,
    ...sec(r'''the options and their defaults'''),
    ...para(r'''--''', r'''The defaults table doubles as documentation, with a comment per key. commands = true defines the three user commands. keymaps = false is the important one: the original mapped its keys itself, and in the plugin the keys are opt-in. mode is the policy for an unresolved name; config holds the engine tuning numbers.'''),
    blank,
    ...code('lua', r'lua/xyno_imports/init.lua · lines 5-10, 13-13', r'''
M.defaults = {
  commands = true, -- :ImportName :ImportForget :ImportOrganize
  keymaps = false, -- false | true | { import = lhs|false, organize = lhs|false } (buffer-local in Rust files)
  mode = "ask", -- "ask" | "single" | "off": what happens to an unresolved name (vim.g.xyno_auto_import overrides)
  config = {}, -- overrides of the engine's tuning values: debounce, max_names, retries, retry_ms, organize_rounds, max_lines, source_wait_ms
}
...
M.default_keymaps = { import = "<leader>rI", organize = "<leader>rO" }'''),

    ...para(r'''--''', r'''Note that the default keys are declared twice. engine.lua line 1596 has its own M.default_keymaps with the same two values and is the one that map_buffer actually reads; the copy here is documentation that the code does not use. If one changes, the other will not follow (a duplicate in the source, not a bug that shows today: both hold the same values).'''),
    blank,
    ...sec(r'''setup(): four decisions in order'''),
    ...para(r'''--''', r'''First, the options are merged with vim.tbl_deep_extend("force", ...) over a deep copy of the defaults, so calling setup twice, or editing the result, never mutates M.defaults. Second, the version check: has("nvim-0.12") must be 1, or one error line and a return. Third, the dependency check, which is the part with a story.'''),
    blank,
    ...code('lua', r'lua/xyno_imports/init.lua · lines 17-30', r'''
function M.setup(opts)
  opts = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  if vim.fn.has("nvim-0.12") ~= 1 then
    vim.notify("xyno-imports: Neovim 0.12 or newer is required", vim.log.levels.ERROR)
    return
  end
  for _, mod in ipairs({ "xyno_rust.crate_meta", "xyno_rust.code_actions", "xyno_rust.fsutil" }) do
    if not pcall(require, mod) then
      vim.notify("xyno-imports: needs xyno-rust.nvim (xynorash/xyno-rust.nvim), which is not installed", vim.log.levels.ERROR)
      return
    end
  end
  local engine = require("xyno_imports.engine")
  for k, v in pairs(opts.config) do'''),

    ...para(r'''--''', r'''The plugin needs three modules from xyno-rust.nvim: crate_meta for workspace roots and cargo metadata, code_actions for the LSP code action plumbing, and fsutil for the state file rename. The loop requires each under pcall and, if any fails, shows one notification that names the missing plugin and its repository and returns before anything is started. It is one line because a spec asserts it: no newline in the message, level ERROR, exactly one notification, and no :ImportName command defined afterwards.'''),
    blank,
    ...para(r'''--''', r'''Checking in setup() instead of at the top of engine.lua is the design. engine.lua requires the sibling modules at load time, so it would raise a Lua error with a traceback if required without them. By checking first, a user who forgot the dependency in their lazy.nvim spec gets a sentence instead of a stack.'''),
    blank,
    ...sec(r'''handing over to the engine'''),
    ...para(r'''--''', r'''Config overrides are copied only for keys the engine already has. A typo such as debonce is ignored instead of creating a dead field, which is what the init spec asserts with a nonsense key. The three behavioural options go to engine.setup as a table, and the engine decides what they mean.'''),
    blank,
    ...code('lua', r'lua/xyno_imports/init.lua · lines 29-34', r'''
  local engine = require("xyno_imports.engine")
  for k, v in pairs(opts.config) do
    if engine.config[k] ~= nil then
      engine.config[k] = v
    end
  end'''),

    ...sec(r'''using it from lazy.nvim'''),
    ...para(r'''--''', r'''Because setup() is the whole interface, the lazy.nvim spec in the README is short: opts = {} is enough, since lazy.nvim calls require("xyno_imports").setup(opts) for a plugin with opts. The module name xyno_imports comes from the directory under lua/, which is why the plugin repository is called xyno-imports.nvim and the module xyno_imports. A user who wants the picker on a key but no automatic imports would write mode = "off" and keymaps = true.'''),
    blank,
    ...code('lua', r'lua/xyno_imports/init.lua · lines 16-16', r'''
---@param opts? { commands?: boolean, keymaps?: boolean|table<string, string|false>, mode?: "ask"|"single"|"off", config?: table }'''),

    ...para(r'''--''', r'''The one-line type annotation above setup is the contract for editors with lua_ls: it lists the four keys, the three modes and the shape of the keymaps table, where false means skip this action. Nothing at runtime enforces it.'''),
    blank,
    ...sec(r'''trade-offs'''),
    ...pt(r'''--''', r'''No validation of mode''', r'''engine.setup ignores a mode it does not know and leaves the default as it was. There is no warning; vim.g.xyno_auto_import behaves the same way, falling back to the option, and the init spec checks that "bogus" falls back to the configured mode.'''),
    ...pt(r'''--''', r'''Safe to call again''', r'''the autocommand group is cleared and redefined by the engine. The commands are redefined too; the spec cleans them between cases.'''),
    ...pt(r'''--''', r'''No lazy module cache''', r'''the engine is required inside setup, after the checks, so a missing dependency does not stop require("xyno_imports") from loading.'''),
    ...sec(r'''how it is tested'''),
    ...para(r'''--''', r'''tests/init_spec.lua has six cases: the three commands exist and no key is mapped by default; commands = false registers none; keymaps = true maps both default keys buffer-locally; a keymaps table maps only what it lists; mode and config reach the engine with the global winning; and the missing-dependency case, which removes the three modules from package.loaded, empties the runtime path and the module loaders, and calls setup. tests/e2e/smoke.lua repeats that last case through lazy.nvim.'''),
    blank,
    ...sec(r'''history'''),
    ...pt(r'''--''', r'''0e6c052 2026-10-22''', r'''added with engine.lua: "Add the xyno_imports modules: auto-import, ranked choice, organize imports".'''),
    ...pt(r'''--''', r'''9373a52 2026-10-22''', r'''README, help file and CI describe these options; the defaults here are the source.'''),
  ],
);
