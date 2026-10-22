import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-crates.nvim/lua/xyno_crates/init.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'init.lua — the front door: check the neighbours, then start the modules'),
    cm('--', r'one setup() that refuses politely instead of failing halfway'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'public entry point, require("xyno_crates").setup(opts)'),
    kv(r'language', r'Lua (Neovim 0.12+)'),
    kv(r'size', r'57 lines, the only file written for the plugin; the three modules are extractions'),
    kv(r'starts', r'xyno_crates.crate_add, crate_features, crate_import'),
    kv(r'depends on', r'xyno-rust.nvim (always), xyno-imports.nvim (add and import modules)'),
    kv(r'history', r'added in 5cd9905 (2026-10-22), unchanged in the two commits after it'),
    ...sec(r'why this file exists'),
    ...para('--', r'The three modules next to this file were not written for a plugin. They were written for a configuration: in xynovim each one was a file in lua/config/, started by a small lazy.nvim spec in lua/plugins/ (crate-add.lua calls config.crate_add.setup() from a one-shot User VeryLazy autocommand, crate-features.lua calls config.crate_features.setup() from the init function of an optional nvim-lspconfig spec), and the keys were hard-wired in the modules. Moving them into a plugin leaves three questions that a personal config never has to answer. What if the other half of the system is missing? What if the user wants the commands but not my keys? What if they want only the missing-feature fix and nothing else? init.lua is the answer to those three questions and nothing more: it has no logic about crates at all.'),
    blank,
    ...para('--', r'That is also why it is so short. Everything a Rust developer would call a feature lives in the modules, and each of them can still be required on its own, which the header comment says in its second line. setup() is a thin conductor: validate, decide which modules run, hand each the one or two options it understands.'),
    blank,
    ...sec(r'the options: opt-in everything that touches the user'),
    ...code('lua', r'lua/xyno_crates/init.lua · lines 1-17', r'''
-- xyno-crates.nvim: Cargo dependencies from inside Neovim. setup() checks the
-- dependencies and starts the modules; every module can also be required on its own
-- (xyno_crates.crate_add, xyno_crates.crate_features, xyno_crates.crate_import).
local M = {}

M.defaults = {
  commands = true, -- :CrateAdd :CrateFeatures
  keymaps = false, -- false | true | { add = lhs|false, fix = lhs|false } (buffer-local in Rust files; add also in Cargo.toml)
  modules = {
    add = true, -- xyno_crates.crate_add: unknown-crate hint, "Add crate X" action, :CrateAdd
    features = true, -- xyno_crates.crate_features: missing-feature action, :CrateFeatures
    import = true, -- xyno_crates.crate_import: import from crates that are not dependencies yet (needs xyno-imports.nvim)
  },
}

--- Default keys of `keymaps = true`. An entry set to false in a table is skipped.
M.default_keymaps = { add = "<leader>rA", fix = "<leader>rG" }'''),
    ...para('--', r'Three decisions are visible in these seventeen lines. First, commands = true is the only default that reaches the user: :CrateAdd and :CrateFeatures exist unless asked otherwise. A command appears in :command and does nothing until it is typed, which is why this is an acceptable default. Second, keymaps = false. The README states the reason: the original code in xynovim bound <leader>rA and <leader>rG itself, and in the plugin the keys are opt-in. The cost of asking for the keys is one line of config. Third, the modules table switches whole features off, so a user who only wants the code action for a missing derive feature can turn add and import off and never load the tree-sitter scan.'),
    blank,
    ...para('--', r'M.default_keymaps is a separate table on purpose, and it is public. init-keymaps_spec.lua reads C.default_keymaps.add and compares it with the string "<leader>rA", so the table and the documented key are checked against each other. The comment above it states the one rule of the table form: an entry set to false is skipped, which lets { add = "<leader>ca", fix = false } map only the first action.'),
    blank,
    ...sec(r'the dependency check'),
    ...code('lua', r'lua/xyno_crates/init.lua · lines 19-25', r'''
local REQUIRED = {
  { mod = "xyno_rust.crate_meta", plugin = "xyno-rust.nvim (xynorash/xyno-rust.nvim)" },
  { mod = "xyno_rust.code_actions", plugin = "xyno-rust.nvim (xynorash/xyno-rust.nvim)" },
  { mod = "xyno_rust.fsutil", plugin = "xyno-rust.nvim (xynorash/xyno-rust.nvim)" },
  { mod = "xyno_rust.rust_restart", plugin = "xyno-rust.nvim (xynorash/xyno-rust.nvim)" },
  { mod = "xyno_imports.engine", plugin = "xyno-imports.nvim (xynorash/xyno-imports.nvim)" },
}'''),
    ...para('--', r'The plugin cannot work without xyno-rust.nvim: crate_add, crate_features and crate_import all begin by requiring xyno_rust.crate_meta, the module that runs cargo metadata, reads the registry sources and talks to crates.io. The list names five modules, not two plugins, and that is deliberate. It checks the exact modules this plugin uses, so a stale copy of xyno-rust.nvim that predates one of them is reported by the same message as a missing plugin. Every row carries the plugin name and its GitHub path, because the message is the whole of the user interface here.'),
    blank,
    ...code('lua', r'lua/xyno_crates/init.lua · lines 27-44', r'''
--- Configure and start the plugin. The first call wins for the autocommands, the in-process
--- LSP servers and the keys (the modules start once per session).
---@param opts? { commands?: boolean, keymaps?: boolean|table<string, string|false>, modules?: table<string, boolean> }
function M.setup(opts)
  opts = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  if vim.fn.has("nvim-0.12") ~= 1 then
    vim.notify("xyno-crates: Neovim 0.12 or newer is required", vim.log.levels.ERROR)
    return
  end
  local m = opts.modules
  for _, dep in ipairs(REQUIRED) do
    -- xyno-imports is only used by the add and import modules
    local needed = dep.mod ~= "xyno_imports.engine" or m.add or m.import
    if needed and not pcall(require, dep.mod) then
      vim.notify("xyno-crates: needs " .. dep.plugin .. ", which is not installed", vim.log.levels.ERROR)
      return
    end
  end'''),
    ...para('--', r'Read the loop slowly, because three small choices make it behave. The version check comes first, with has("nvim-0.12"): the modules register their in-process language servers with vim.lsp.config and vim.lsp.enable, so, as far as the code shows, an older Neovim is turned away with one error line instead of a stack trace from a later call. The file does not say why 0.12 and not an earlier release; that part is not documented. Then each dependency is probed with pcall(require, dep.mod). A failed require is not an exception here, it is the answer. Finally the loop returns on the first miss, so the user sees one problem at a time and, more importantly, nothing has started: no autocommand, no command, no language client. That is the property the specs pin down.'),
    blank,
    ...para('--', r'The needed line is the interesting one. xyno-imports.nvim is the import engine that the import module plugs a source into, and crate_add reaches it too, through crate_import.add_and_import, when its code action runs. The author’s rule is stated in the comment: it is only used by the add and import modules. So a user who sets modules = { add = false, import = false } can run the feature fixer with xyno-rust.nvim alone. Short-circuit evaluation does the work: dep.mod ~= "xyno_imports.engine" is true for the four xyno_rust rows, which are always needed, and only the last row consults m.add and m.import.'),
    blank,
    ...sec(r'starting the modules'),
    ...code('lua', r'lua/xyno_crates/init.lua · lines 45-57', r'''
  local keys = opts.keymaps and (opts.keymaps == true and M.default_keymaps or opts.keymaps) or {}
  if m.add then
    require("xyno_crates.crate_add").setup({ commands = opts.commands, keymap = keys.add })
  end
  if m.features then
    require("xyno_crates.crate_features").setup({ commands = opts.commands, keymap = keys.fix })
  end
  if m.import then
    require("xyno_crates.crate_import").setup()
  end
end

return M'''),
    ...para('--', r'keys is computed once. keymaps = true selects M.default_keymaps; a table is used as given; false (or nil) becomes an empty table, so keys.add and keys.fix are simply nil. Each module then gets exactly its slice: crate_add receives keymap = keys.add, crate_features receives keymap = keys.fix, and both get the same commands switch. crate_import takes nothing, because its only job is to register a source with the import engine.'),
    blank,
    ...para('--', r'The doc comment above setup() makes a promise that is easy to miss: the first call wins. The modules guard their own setup with a local did_setup flag, and a second call returns early. That is a conscious trade. It means a plugin manager that evaluates opts twice, or a user who calls setup() again from a reloaded config, does not stack autocommands or leave a duplicate in-process language client. The cost is that changing keymaps after the first call has no effect until Neovim restarts, and the README says so in one sentence.'),
    blank,
    ...sec(r'what the specs check'),
    ...para('--', r'tests/init_spec.lua exercises exactly this file. Its first describe block blocks a module from loading with a fake package searcher and asserts the promised behaviour: one notification at ERROR level, naming the plugin and its GitHub path, containing no newline, and, the part that matters, vim.fn.exists(":CrateAdd") and exists(":CrateFeatures") both equal 0 afterwards. A second test blocks only xyno_imports.engine and expects the other plugin’s name. A third turns add, import and features off and expects no message at all with the engine blocked, which pins the needed rule. The remaining tests check that a switched-off module registers nothing, that the defaults register both commands with no key mapped, and that the in-process servers carry the names xyno-crates and xyno-features. tests/init-keymaps_spec.lua covers the keymaps = true path in a separate process, because the modules start only once per process.'),
    blank,
    ...sec(r'design notes and limits'),
    ...pt('--', r'no global state in this file', r'M.defaults is deep-copied before the merge, so a caller who mutates the returned options cannot change the defaults of the next call.'),
    ...pt('--', r'errors are notifications, not raises', r'setup() never throws for a missing dependency; it returns. The smoke test calls it with every runtime path emptied and asserts that pcall succeeds and exactly one line is produced.'),
    ...pt('--', r'lazy-loading is the user', r'setup() starts autocommands and in-process language clients, so it has to run when Rust files open. The README recommends ft = "rust" or event = "VeryLazy" for that reason, and adds that :CrateFeatures and the fix key work as soon as the plugin is loaded.'),
    ...pt('--', r'not validated here', r'unknown keys in opts are merged and ignored; a misspelt module name does nothing. The file keeps to the failures that would otherwise be confusing and leaves the rest alone.'),
    ...sec(r'history'),
    ...para('--', r'The file exists in one commit of the plugin repository: 5cd9905 on 2026-10-22, "Add the xyno_crates modules: crate add, crate features, crate import", the commit that also brought the three modules. The two commits after it, 9d33ca7 (specs, runner, smoke test) and dacc6a0 (README, help file, CI), did not touch it. In xynovim there is no counterpart: the equivalent wiring was lua/plugins/crate-add.lua and lua/plugins/crate-features.lua, which called each module’s setup() with no arguments and relied on keys fixed inside the module.'),
    blank,
  ],
);
