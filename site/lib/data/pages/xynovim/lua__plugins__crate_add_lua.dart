import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/crate-add.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'plugins/crate-add.lua — load :CrateAdd after the UI is up'),
    cm('--', r'twelve lines that start crate_add on VeryLazy'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'lazy.nvim spec file that boots config/crate_add.lua'),
    kv(r'language', r'Lua, an autocommand and an empty spec table'),
    kv(r'size', r'12 lines, 1 commit (b9363cd, 2026-10-14)'),
    kv(r'loads', r'require("config.crate_add").setup() once, on VeryLazy'),
    kv(r'also lives in', r'replaced by xyno-crates.nvim setup()'),
    ...sec(r'why this file exists'),
    ...para('--', r'Every file in lua/plugins/ is read by lazy.nvim as a plugin spec. config/crate_add.lua is not a plugin; it is a module of this configuration that owns a command, a key, an autocommand group and an in-process language server. Something has to call its setup(), and this file is that something.'),
    ...code('lua', r'lua/plugins/crate-add.lua · lines 1-12', r'''
-- :CrateAdd, <leader>rA and the unknown-crate hint (config/crate_add.lua).
-- Setup waits for VeryLazy so LazyVim's own keymaps and autocmds are in place
-- (a lazy.nvim virtual plugin would be one more entry in the plugin count).
vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("xynovim_crate_add_load", { clear = true }),
  pattern = "VeryLazy",
  once = true,
  callback = function()
    require("config.crate_add").setup()
  end,
})
return {}'''),
    ...sec(r'how it works'),
    ...para('--', r'The autocommand listens for the User event VeryLazy, which LazyVim fires after startup is done and the UI has had its first redraw. It runs once (once = true) in a named group with clear = true, so re-sourcing the file does not stack handlers. The callback requires config.crate_add and calls setup(). The file then returns an empty table, which is a valid spec that declares no plugins.'),
    ...sec(r'the two design decisions in the comment'),
    ...para('--', r'The first line names everything the module provides: the command :CrateAdd, the key <leader>rA and the hint for an unknown crate. The second and third lines give the reasons. Setup waits for VeryLazy so that LazyVim own keymaps and autocommands are already in place; crate_add registers an LSP config, autocommands and a buffer-local key, so it is started after startup rather than during it.'),
    ...para('--', r'The parenthesis says why this is not written as a lazy.nvim virtual plugin, a spec with a name and an init or config function: it would be one more entry in the plugin count. The count is not cosmetic here. tests/test-infra-readme-claims_spec.lua has a case that checks the README claim of N of M plugins loaded against the real plugin count, and lazy-lock.json must have an entry per plugin, so a virtual plugin would change numbers that the repository checks. A plain autocommand costs none of that.'),
    ...sec(r'a contrast inside the same group'),
    ...para('--', r'lua/plugins/crate-features.lua solves the same problem differently, with an init function on an optional nvim-lspconfig spec, and lua/plugins/import-engine.lua uses the same VeryLazy pattern as this file. All three files were added in the same commit (b9363cd), so the difference is part of the original design, and the file comments do not say more than what is quoted above.'),
    ...sec(r'in the standalone plugin'),
    ...para('--', r'In xyno-crates.nvim there is no equivalent file. The user calls require("xyno_crates").setup(opts) from their own lazy.nvim spec, for example with event = "VeryLazy" or ft = "rust". The README says a load only on the commands is not enough if the code actions and the hint are wanted while editing, because those come from in-process clients that start in setup().'),
    ...sec(r'history'),
    ...pt('--', r'b9363cd · 2026-10-14', r'added in the dependencies and macros commit; never changed'),
  ],
);
