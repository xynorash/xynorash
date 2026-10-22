import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-new.nvim/lua/xyno_new/init.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'lua/xyno_new/init.lua — the front door'),
    cm('--', r'setup(), five options, opt-in keymaps, and one honest error'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'entry point: configure, check the dependency, start the modules'),
    kv(r'language', r'Lua, 96 lines, no state beyond the defaults table'),
    kv(r'public', r'setup(opts), dashboard_keys(keys), defaults, default_keymaps'),
    kv(r'requires', r'Neovim 0.12+, xyno-rust.nvim (rust_context, fsutil)'),
    kv(r'history', r'added in 01f8e4c (2026-10-22); no counterpart in xynovim'),
    ...sec(r'why this file exists'),
    ...para('--', r'In xynovim the two modules, config.rust_new and config.egui_new, were started by lazy.nvim plugin specs and configured through vim.g.xynovim_* variables that the author set in options.lua. A standalone plugin needs a front door that other people can call with a table. That is all init.lua is: it turns an options table into the variables the modules already read, defines the commands, optionally maps keys, and refuses to start when the world is wrong.'),
    ...para('--', r'It is also the only file in the plugin that is new code rather than moved code. The README says so: setup() taking options is one of the listed differences from the original. There is no equivalent of it in xynovim’s history, which is why this page has no git archaeology to offer beyond the single commit that added it.'),
    ...sec(r'the defaults, and a design decision hiding in a comment'),
    ...code('lua', r'lua/xyno_new/init.lua · lines 7-13', r'''
M.defaults = {
  commands = true, -- :RustNewBin :RustNewLib :RustNewWorkspace :RustNewMember :EguiNew
  keymaps = false, -- false | true | { bin = lhs, lib = lhs, ... } (global, normal mode)
  projects_dir = nil, -- parent directory offered by the prompts (default ~/projects if it exists, else the cwd)
  egui_template = nil, -- { repo = "emilk/eframe_template", ref = "main", base_url = "https://github.com" }
  egui_build_after_new = nil, -- true: run `cargo build` in a snacks terminal after :EguiNew
}'''),
    ...para('--', r'Five options. commands is the master switch: with commands = false setup() defines nothing, because every module can also be required on its own (the header comment says so). keymaps is false on purpose; the plugin leaves leader mappings to the user unless asked. The other three are nil, not a value, because nil means “leave the variable alone”: see the setup body below.'),
    ...para('--', r'The projects_dir comment is a small specification. The prompts offer a parent directory; if you gave none, the default is ~/projects if that exists, else the current directory. The code that implements this is default_parent in egui.lua, shared by the Rust flows, so there is exactly one place where the rule lives.'),
    ...sec(r'keymaps as data'),
    ...code('lua', r'lua/xyno_new/init.lua · lines 15-30', r'''
--- Default keys of `keymaps = true`. An entry set to false in a table is skipped.
M.default_keymaps = {
  bin = "<leader>rnb",
  lib = "<leader>rni",
  workspace = "<leader>rnw",
  member = "<leader>rnm",
  egui = "<leader>rne",
}

local ACTIONS = {
  bin = { "<cmd>RustNewBin<cr>", "New Rust binary" },
  lib = { "<cmd>RustNewLib<cr>", "New Rust library" },
  workspace = { "<cmd>RustNewWorkspace<cr>", "New Rust workspace" },
  member = { "<cmd>RustNewMember<cr>", "New member in this workspace" },
  egui = { "<cmd>EguiNew<cr>", "New egui project" },
}'''),
    ...para('--', r'Two tables. default_keymaps maps an action name to a key, and ACTIONS maps the same names to the command line and a description. Keeping them separate is what makes the table form of the option work: a user can say keymaps = { bin = "<leader>zb", lib = false } and the loop looks up the action by name, not by key. Every mapping goes through <cmd>…<cr> rather than a Lua function, so the mapping shows the real command in :map and keeps working if somebody redefines it.'),
    ...para('--', r'The default keys share the prefix <leader>rn (r for Rust, n for new) and end in b, i, w, m, e for binary, library, workspace, member and egui. The README lists the lazy.nvim keys = {...} form of the same five mappings for people who prefer lazy-loading on keys.'),
    ...sec(r'checking the dependency without blowing up'),
    ...code('lua', r'lua/xyno_new/init.lua · lines 32-48', r'''
--- Modules of the plugin this one needs (xyno-rust.nvim).
local REQUIRES = { "xyno_rust.rust_context", "xyno_rust.fsutil" }

--- Whether xyno-rust.nvim is there; says so in one line when it is not.
local function check_dependencies()
  for _, mod in ipairs(REQUIRES) do
    if not pcall(require, mod) then
      vim.notify(
        "xyno-new.nvim needs xyno-rust.nvim (github.com/xynorash/xyno-rust.nvim), which is not installed",
        vim.log.levels.ERROR,
        { title = "xyno-new" }
      )
      return false
    end
  end
  return true
end'''),
    ...para('--', r'The dependency list is two module names, not one plugin name, because modules are what the code actually requires: xyno_rust.rust_context finds the Cargo workspace root for :RustNewMember, and xyno_rust.fsutil.slash normalises paths for the nesting check in rust.lua. pcall(require, mod) is the cheapest honest test: it works however the plugin was installed, with lazy.nvim, a package manager, or a runtimepath line.'),
    ...para('--', r'On failure there is exactly one notification at ERROR level with a title, and the function returns false. Not an error() call: the function reports through vim.notify and returns, so no Lua error is raised. tests/init_spec.lua checks exactly this contract, one notification, one line, ERROR level, no Lua error, none of the five commands defined.'),
    ...sec(r'setup()'),
    ...code('lua', r'lua/xyno_new/init.lua · lines 54-86', r'''
function M.setup(opts)
  opts = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  if vim.fn.has("nvim-0.12") ~= 1 then
    vim.notify("xyno-new.nvim needs Neovim 0.12 or newer", vim.log.levels.ERROR, { title = "xyno-new" })
    return false
  end
  if not check_dependencies() then
    return false
  end
  if opts.projects_dir ~= nil then
    vim.g.xyno_new_projects_dir = opts.projects_dir
  end
  if opts.egui_template ~= nil then
    vim.g.xyno_new_egui_template = opts.egui_template
  end
  if opts.egui_build_after_new ~= nil then
    vim.g.xyno_new_egui_build_after_new = opts.egui_build_after_new
  end
  if opts.commands then
    require("xyno_new.rust").setup()
    require("xyno_new.egui").setup()
  end
  if opts.keymaps then
    local keys = opts.keymaps == true and M.default_keymaps or opts.keymaps
    for name, lhs in pairs(keys) do
      local action = ACTIONS[name]
      if action and type(lhs) == "string" then
        vim.keymap.set("n", lhs, action[1], { desc = action[2] })
      end
    end
  end
  return true
end'''),
    ...para('--', r'Four things happen in order. First, vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts) merges over a copy, so calling setup twice with different options never leaks one call’s table into the next. Second, the version gate: vim.fn.has("nvim-0.12") must be 1. The gate turns a too-old Neovim into one error sentence instead of whatever the modules would hit later. Third, the dependency check. Fourth, the options become variables.'),
    ...para('--', r'The three options that become vim.g variables are written only when they are not nil. That is deliberate and tested (“without options the variables stay as they are”): a user who set vim.g.xyno_new_projects_dir in their own config before calling setup({}) keeps it. The README states both routes are supported.'),
    ...para('--', r'Commands come last. require("xyno_new.rust").setup() defines :RustNewBin, :RustNewLib, :RustNewWorkspace and :RustNewMember; egui.setup() defines :EguiNew. Each is a nvim_create_user_command with nargs = "?", which is why every command accepts an optional name. Calling setup() again simply redefines them, which the spec “is safe to call twice” confirms.'),
    ...para('--', r'The keymap loop ignores anything unusable: an unknown action name, or a value that is not a string (false skips one). It does not warn about unknown names. That is a trade-off: silent tolerance of a typo, in exchange for a table that can safely hold false to disable a default. The mapping is normal-mode, global, with a desc, so it is readable in :map output.'),
    ...sec(r'dashboard_keys'),
    ...code('lua', r'lua/xyno_new/init.lua · lines 88-96', r'''
--- Add the dashboard entries to a snacks.nvim `dashboard.preset.keys` list (in place) and
--- return it; see xyno_new.dashboard. Calling it twice adds nothing twice.
---@param keys? table[]
---@return table[]
function M.dashboard_keys(keys)
  return require("xyno_new.dashboard").keys(keys)
end

return M'''),
    ...para('--', r'Three lines of real code. The function is a thin public name for xyno_new.dashboard.keys, lazily required so that the dashboard module is not even loaded unless someone calls it. Requiring on demand is the plugin’s general style: nothing in this file loads rust.lua or egui.lua until commands = true.'),
    ...sec(r'what lazy.nvim does with it'),
    ...para('--', r'The README’s install block lists the five commands in cmd and passes opts = {}. lazy.nvim sees opts and calls require("xyno_new").setup({}) itself when the plugin loads. Because the commands only exist after setup(), the first use of a command through cmd works only because lazy.nvim forwards that first invocation after loading the plugin; the README says so explicitly. The e2e smoke test in tests/e2e/smoke.lua uses lazy = false and main = "xyno_new" to cover the other route.'),
    ...sec(r'edge cases handled'),
    ...pt('--', r'Neovim too old', r'one ERROR notification naming 0.12, return false, nothing defined.'),
    ...pt('--', r'xyno-rust.nvim missing', r'one ERROR notification naming the repository, return false, nothing defined.'),
    ...pt('--', r'opts = nil or {}', r'defaults apply; existing vim.g values survive.'),
    ...pt('--', r'setup() twice', r'commands redefined, keymaps re-set, no error.'),
    ...pt('--', r'unknown or false keymap entry', r'skipped without a message.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/init_spec.lua has seven cases in two groups. The first group covers defaults (commands defined, no keymap), commands = false, keymaps = true versus a table with false, the options becoming variables, variables left alone, and calling setup twice. The second makes xyno-rust.nvim disappear by clearing package.loaded and replacing package.loaders so only xyno_rust modules are refused, then asserts the single-notification contract. The smoke test repeats the happy path through lazy.nvim.'),
    ...sec(r'history'),
    ...para('--', r'01f8e4c, 2026-10-22: added together with the other three modules. The three commits of the repository were created in the same second. The real working history of the modules is in xynovim: egui_new.lua from ddc51eb (2026-10-15) and rust_new.lua from d163480 (2026-10-16).'),
  ],
);
