import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/import-engine.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'plugins/import-engine.lua — start imports and crate imports'),
    cm('--', r'one VeryLazy hook for two modules, in a fixed order'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'lazy.nvim spec file that boots the import layer'),
    kv(r'language', r'Lua, an autocommand and an empty spec table'),
    kv(r'size', r'14 lines, 1 commit (b9363cd, 2026-10-14)'),
    kv(r'loads', r'config.import_engine, then config.crate_import'),
    kv(r'also lives in', r'replaced by xyno-imports.nvim and xyno-crates.nvim setup()'),
    ...sec(r'why this file exists'),
    ...para('--', r'The import work is split in two modules. config/import_engine.lua finds unresolved names and asks rust-analyzer for the import. config/crate_import.lua is a source that plugs into the engine for names no dependency offers. This file is the single place that starts both, in the right order.'),
    ...code('lua', r'lua/plugins/import-engine.lua · lines 1-14', r'''
-- Auto-import, ranked disambiguation, organize imports (config/import_engine.lua).
-- Setup waits for VeryLazy, like the rest of the UI layer: keys and commands
-- need LazyVim's own maps in place to leave them alone.
vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("xynovim_import_engine_load", { clear = true }),
  pattern = "VeryLazy",
  once = true,
  callback = function()
    require("config.import_engine").setup()
    -- crates.io candidates for names no dependency offers (Add crate X and import)
    require("config.crate_import").setup()
  end,
})
return {}'''),
    ...sec(r'how it works'),
    ...para('--', r'It is the same pattern as crate-add.lua: an autocommand on the User event VeryLazy, once, in a cleared group, and an empty spec returned so lazy.nvim has nothing to install. The comment gives the reason in this file own words: keys and commands need LazyVim own maps in place to leave them alone. That refers to the free-key test in import_engine, which maps <leader>rI and <leader>rO only if nothing real is bound there yet.'),
    ...para('--', r'The order inside the callback is not decoration. import_engine.setup() creates the commands, the autocommands and the buffer-local keys. crate_import.setup() then calls register_source on the engine. The call order in the file is engine first, then the crate source, and crate_import.setup() itself requires config.import_engine when it registers.'),
    ...para('--', r'The second comment, crates.io candidates for names no dependency offers, with the example Add crate X and import, says what the second call buys: when rust-analyzer has nothing to offer, the engine asks the registered source, which proposes crates. Without this line the engine still works; it just never suggests a crate you do not have.'),
    ...sec(r'why not a lazy.nvim spec'),
    ...para('--', r'As with crate-add.lua, the reason is the plugin count that the repository tests against its README and lockfile: tests/test-infra-readme-claims_spec.lua compares the N of M plugins loaded claim with the real count. Because the loader returns an empty table, it adds no plugin.'),
    ...sec(r'what the spec covers'),
    ...para('--', r'tests/import-engine_spec.lua has a case, registers the commands and the keys (rI, rO) and loads a source, that checks both calls took effect. The crate_import spec group checks the source through the engine with stubbed crates.io.'),
    ...sec(r'in the standalone plugins'),
    ...para('--', r'After the extraction on 2026-10-22 the two calls belong to two plugins. xyno-imports.nvim has its own setup() that checks xyno-rust.nvim and starts the engine with mode, keymaps and commands options. xyno-crates.nvim has the setup that starts add, features and import, and registers the crates.io source only when its import module is on, after checking that xyno-imports.nvim is installed. The fixed order this file gives for free now has to be respected by the user: set up xyno-imports first, or let the crate plugin report that it is missing.'),
    ...sec(r'history'),
    ...pt('--', r'b9363cd · 2026-10-14', r'added in the dependencies and macros commit; never changed'),
  ],
);
