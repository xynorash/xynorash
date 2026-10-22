import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/crate-features.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'plugins/crate-features.lua — start the feature fixer at startup'),
    cm('--', r'an optional lspconfig spec whose init calls setup()'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'lazy.nvim spec file that boots config/crate_features.lua'),
    kv(r'language', r'Lua, one spec table'),
    kv(r'size', r'10 lines, 1 commit (b9363cd, 2026-10-14)'),
    kv(r'loads', r'require("config.crate_features").setup() from init'),
    kv(r'also lives in', r'replaced by xyno-crates.nvim setup()'),
    ...sec(r'why this file exists'),
    ...para('--', r'config/crate_features.lua owns the missing-feature code action, the key <leader>rG and the command :CrateFeatures. This file is how its setup() gets called. It is the shortest of the three loader files in this group, and the only one that is a real spec instead of an autocommand.'),
    ...code('lua', r'lua/plugins/crate-features.lua · lines 1-10', r'''
-- Missing-feature code action ("Enable feature `derive` of `serde`"), <leader>rG
-- and :CrateFeatures (lua/config/crate_features.lua). Loaded from a plugin spec
-- (init runs at startup) so the module owns its commands and keys.
return {
  "neovim/nvim-lspconfig",
  optional = true,
  init = function()
    require("config.crate_features").setup()
  end,
}'''),
    ...sec(r'how it works'),
    ...para('--', r'The spec names neovim/nvim-lspconfig with optional = true. In lazy.nvim an optional spec adds options to a plugin only if some other spec already declares it, and does not install it by itself. Here nothing is added to lspconfig; the point is the init function. init functions of all specs run at startup, before any plugin is loaded, so setup() runs when Neovim starts, and the module defines :CrateFeatures and the FileType autocommand without waiting for anything.'),
    ...para('--', r'The spec adds no plugin of its own: it describes one that LazyVim already ships. The only reason the comment gives is that loading from a plugin spec, with init running at startup, lets the module own its commands and keys.'),
    ...sec(r'what a failure looks like'),
    ...para('--', r'If nvim-lspconfig were removed from the configuration, optional = true means the spec is ignored, and init would not run: :CrateFeatures and the key would silently disappear. That is a coupling this file makes: the loader depends on another plugin being declared. The other two loaders hang on an event instead and have no such dependency.'),
    ...sec(r'startup cost'),
    ...para('--', r'setup() itself is cheap. It creates the command, one autocommand group and a FileType autocommand, and attaches the in-process client to any Rust buffer that is already open. The source scanner, the Cargo.toml editor and the explorer are Lua code in the same module, but nothing in them runs until a diagnostic or a command asks.'),
    ...sec(r'in the standalone plugin'),
    ...para('--', r'xyno-crates.nvim has no such file; its setup() starts the features module when modules.features is on and takes the key from keymaps.fix. A difference worth knowing: the module in the plugin binds the fix key only if the user passed one, while this repository binds <leader>rG for every Rust buffer.'),
    ...sec(r'history'),
    ...pt('--', r'b9363cd · 2026-10-14', r'added in the dependencies and macros commit; never changed'),
  ],
);
