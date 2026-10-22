import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/lua/xyno_rust/init.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'init.lua - the front door of xyno-rust.nvim'),
    cm('--', r'setup() wires five modules, optional commands, opt-in keymaps'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'plugin entry point: defaults, module switches, buffer-local keymaps'),
    kv(r'language', r'Lua (Neovim 0.12+)'),
    kv(r'size', r'106 lines, added in c1c7958 on 2026-10-22'),
    kv(r'public', r'setup(opts), defaults, default_keymaps'),
    kv(r'tested by', r'tests/init_spec.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'The code in this plugin was written inside a personal Neovim configuration, xynovim, where every module was loaded by hand from a central file and every key was mapped in a keymaps file. A plugin cannot assume that. It needs one function that a plugin manager can call as opts = {} and that turns the pieces on, and it needs to be polite: no global keymaps unless asked, no commands if the user wants to define their own. init.lua is that function and nothing else. Every substantive module (rust_context, rust_tasks, rust_routes, lsp_status, rust_restart) can still be required on its own, which is how the sibling plugins xyno-crates.nvim, xyno-imports.nvim and xyno-new.nvim use this repository as a library.'),
    ...sec(r'the defaults are the documentation'),
    ...code('lua', r'lua/xyno_rust/init.lua · lines 5-17', r'''
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

--- Default keys of `keymaps = true`. An entry set to false in a table is skipped.'''),
    ...para('--', r'Three switches, each with a comment. commands decides whether the user commands exist. keymaps is false, true, or a table. modules lets a user turn off a whole subsystem: someone who already has their own rust-analyzer supervision can set restart = false and keep the rest. Note the order of the keys in the comment of commands: the same seven names appear in the README table, in the help file and here, which is what the init_spec checks (see below).'),
    ...code('lua', r'lua/xyno_rust/init.lua · lines 19-28', r'''
  context = "<leader>rF",
  targets = "<leader>rX",
  tools = "<leader>rZ",
  routes = "<leader>rN",
  goto_super = "<leader>ru",
  local_usages = "<leader>rl",
  doctests = "<leader>tD",
}

local ACTIONS = {'''),
    ...para('--', r'The default keys are a plain table keyed by action name, not by key. That is what makes the table form of keymaps work: a user passes { context = "<leader>x" } and the lookup in ACTIONS finds the command by name; passing context = false skips it. All seven keys live under the leader r prefix except doctests, which sits in the test group (tD). The prefix is the one the author used in xynovim, which is why they are only a default of keymaps = true and not something the plugin imposes.'),
    ...sec(r'actions are data, not closures per key'),
    ...code('lua', r'lua/xyno_rust/init.lua · lines 30-50', r'''
  targets = { "<cmd>RustTargets<cr>", "Cargo targets: run / test / bench" },
  tools = { "<cmd>RustTools<cr>", "Cargo tools (deny, audit, bloat, timings, ...)" },
  routes = { "<cmd>RustRoutes<cr>", "HTTP routes (axum / actix / rocket)" },
  goto_super = {
    function()
      require("xyno_rust.rust_nav").goto_super()
    end,
    "Go to super method (trait item)",
  },
  local_usages = {
    function()
      require("xyno_rust.rust_nav").local_usages()
    end,
    "Usages in file (R/W)",
  },
  doctests = {
    function()
      require("xyno_rust.rust_tasks").doctests()
    end,
    "Doctests (cargo test --doc)",
  },'''),
    ...para('--', r'ACTIONS maps each name to a right-hand side and a description. Four of them are plain command strings; three are functions that require the module lazily, inside the function body. That detail is a start-up decision: pressing the key is the first moment rust_nav or rust_tasks is loaded, so setup() itself stays cheap even when it runs at VeryLazy. The description is passed as desc, so which-key and :map list the keys with a readable label.'),
    ...sec(r'buffer-local keys, and the buffer that is already open'),
    ...code('lua', r'lua/xyno_rust/init.lua · lines 52-69', r'''
local function map_keys(keymaps)
  local keys = keymaps == true and M.default_keymaps or keymaps
  local group = vim.api.nvim_create_augroup("xyno_rust_keymaps", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "rust",
    callback = function(ev)
      for name, lhs in pairs(keys) do
        local action = ACTIONS[name]
        if action and type(lhs) == "string" then
          vim.keymap.set("n", lhs, action[1], { buffer = ev.buf, desc = action[2] })
        end
      end
    end,
  })
  -- a Rust buffer that is already open
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do'''),
    ...para('--', r'The keys are mapped from a FileType autocommand with pattern = "rust" and buffer = ev.buf, so they exist only in Rust buffers and disappear with them. The tail of the function handles a case that bites lazy-loaded plugins: setup() may run after the first Rust buffer has already been created, and a FileType autocommand registered afterwards would never fire for it. The loop therefore walks the loaded buffers and re-fires FileType for the Rust ones, through the same augroup, so the callback does exactly the same work.'),
    ...para('--', r'The augroup is created with clear = true. That is what makes setup() safe to call twice: the second call replaces the autocommand instead of adding another one. A user who maps keys = true and later reloads their config will not end up with duplicated callbacks.'),
    ...sec(r'setup()'),
    ...code('lua', r'lua/xyno_rust/init.lua · lines 71-105', r'''
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
    require("xyno_rust.rust_routes").setup(sub)
  end
  if m.status then
    require("xyno_rust.lsp_status").setup()
  end
  if m.restart then
    require("xyno_rust.rust_restart").setup(sub)
  end
  if opts.keymaps then
    map_keys(opts.keymaps)
  end
end'''),
    ...pt('--', r'version gate', r'the Neovim 0.12 check happens inside setup() and reports through vim.notify at ERROR level, then returns. The plugin does not raise at require time, so a user on an older Neovim sees one message and an otherwise working editor.'),
    ...pt('--', r'deep merge', r'vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {}) copies the defaults first, so setup never mutates M.defaults; modules = { restart = false } merges into the table rather than replacing it.'),
    ...pt('--', r'sub options', r'the one value commands is handed to every module as { commands = ... }. Each module decides for itself how to honour it, which is why the setup functions of context, tasks and routes begin with the same guard (if opts and opts.commands == false then return end) and rust_restart checks it before defining its command.'),
    ...pt('--', r'lsp_status.setup()', r'takes no options at all: it has no commands, only autocommands, and it is the only module with nothing to switch off except through modules.status.'),
    ...pt('--', r'order', r'context, tasks, routes, status, restart. tasks and routes depend on context (they require it at the top of their files), so context goes first.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/init_spec.lua defines the contract in nine cases. "defines every documented command" and "defines no command with commands = false, and sets no key by default" pin the command list. "modules = { x = false } leaves that module out" pins the switches. "registers the autocmd groups of the status and restart modules" and "calling setup() twice does not duplicate autocmds" pin the re-entrancy. The keymaps describe block has three cases: keymaps = true maps buffer-locally in Rust buffers only, a table maps only the listed actions with the keys given, and false sets nothing. A last block, "snacks.nvim is optional", checks that a picker command without snacks is one error line and not a Lua error, which is the contract of deps.lua.'),
    ...sec(r'history'),
    ...para('--', r'The file was added in c1c7958 (2026-10-22, 09:20 +03:00) together with the other xyno_rust modules, with the message "Extracted from xynovim: ... plus setup() with commands, module switches and opt-in keymaps". Unlike the other modules it has no xynovim ancestor: in xynovim these modules were wired from the configuration itself, so this file is new code written for the extraction. The README section Extracted from xynovim lists what changed against the original modules: the namespace, setup() taking options, and the snacks checks.'),
  ],
);
