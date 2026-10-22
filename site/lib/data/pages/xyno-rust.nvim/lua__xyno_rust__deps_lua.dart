import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/lua/xyno_rust/deps.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'deps.lua - one soft dependency, handled in nineteen lines'),
    cm('--', r'snacks.nvim is needed for pickers, never for loading'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'locate snacks.nvim or fail with one line'),
    kv(r'language', r'Lua'),
    kv(r'size', r'19 lines'),
    kv(r'callers', r'rust_context.pick, rust_tasks (targets, tools, terminals), rust_routes.pick'),
    kv(r'tested by', r'the "snacks.nvim is optional" block of tests/init_spec.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'In xynovim, the pickers and terminals simply used the global Snacks table, because the config always installed snacks.nvim. Once the modules became a plugin that assumption was a trap: a user who had not installed snacks would get an attempt to index a nil global the first time they pressed a key. The README says the opposite on purpose: snacks is required for :RustContext, :RustTargets, :RustTools and :RustRoutes, but it is not required to load the plugin. deps.lua is the single place where that promise is kept.'),
    ...sec(r'the whole file'),
    ...code('lua', r'lua/xyno_rust/deps.lua · lines 1-19', r'''
-- Optional plugins the pickers and terminals lean on. Nothing here raises: a
-- missing plugin is one line in the notification area.
local M = {}

--- The snacks.nvim table (picker, terminal), or nil after a one-line error.
function M.snacks()
  local s = rawget(_G, "Snacks")
  if type(s) ~= "table" then
    local ok, mod = pcall(require, "snacks")
    s = ok and type(mod) == "table" and mod or nil
  end
  if s and s.picker then
    return s
  end
  vim.notify("xyno-rust: snacks.nvim is required for pickers and terminals (folke/snacks.nvim)", vim.log.levels.ERROR)
  return nil
end

return M'''),
    ...sec(r'reading it'),
    ...pt('--', r'rawget(_G, "Snacks")', r'snacks.nvim publishes itself as a global when it is set up. Using rawget reads the global without going through any metatable on _G (for example one that warns about undefined globals).'),
    ...pt('--', r'pcall(require, "snacks")', r'if the global is not there yet (the plugin is lazy and has not been set up), requiring the module is tried inside pcall so a missing plugin cannot raise.'),
    ...pt('--', r's.picker', r'the check is for the part that is used, not for the name. A table called snacks that has no picker (an old version, or another module that happens to be called snacks) is treated like no snacks at all.'),
    ...pt('--', r'the error', r'vim.notify at ERROR level with the install hint "folke/snacks.nvim". The function then returns nil, and every caller does the same two lines: local Snacks = require("xyno_rust.deps").snacks(); if not Snacks then return end.'),
    ...sec(r'design decisions'),
    ...para('--', r'The function returns the dependency or nil rather than throwing, because the callers are keymap handlers and user commands. An error there appears as a stack trace in the message area; one clear line is a better experience and is what the init_spec asserts. The lookup is done on every call instead of being cached, which costs nothing and means that a user who installs snacks while Neovim is running does not need to restart.'),
    ...para('--', r'It is also worth noticing what is not here: no fallback to vim.ui.select. A picker with multi-select, preview and layout presets is part of what the commands do (the features picker relies on Tab multi-select, the routes picker on a file preview), so degrading silently to a weaker UI would change behaviour. Failing loudly with the name of the missing plugin was preferred.'),
    ...sec(r'history'),
    ...para('--', r'Added in c1c7958 on 2026-10-22 with the rest of the extraction. In xynovim there was no deps module; the commit message of the extraction lists the nine modules ported from xynovim, and deps is not among them, which matches: it exists only because of the plugin boundary. The README line "the picker and terminal calls checking that snacks.nvim is there" in the section "Extracted from xynovim" is this file.'),
  ],
);
