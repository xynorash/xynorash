import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/telescope.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'telescope.lua — keep a dependency from loading at startup'),
    cm('--', r'lazy = true'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'marks telescope.nvim as lazy so it loads on first require'),
    kv(r'language', r'Lua, a lazy.nvim plugin spec'),
    kv(r'size', r'7 lines, 1 commit (0494b52, 2026-10-12)'),
    kv(r'related', r'lua/plugins/ninety-nine.lua (the only consumer)'),
    ...sec(r'why this file exists'),
    ...para('--',
        r'This editor does not use telescope as its picker. Pickers come from snacks.nvim. Telescope '
        r'is installed for one reason, given in the header of the file: it is only a dependency of '
        r'99, the AI agent plugin, whose model and provider pickers are telescope extensions.'),
    blank,
    ...para('--',
        r'That raises a startup-time question. A plugin that a spec merely lists as a dependency has '
        r'no event, no keys and no command of its own. lazy.nvim classifies such a plugin as a start '
        r'plugin and loads it when Neovim starts, even though nothing is going to use it until the '
        r'user asks 99 to pick a model. The comment says this in the file: with no event, keys or '
        r'cmd of its own it is a start plugin. The fix is one field.'),
    ...sec(r'the whole file'),
    ...code('lua', r'lua/plugins/telescope.lua · lines 1-7', r'''
-- telescope.nvim is only a dependency of 99 (model/provider pickers). With no
-- event/keys/cmd of its own lazy.nvim classifies it as a start plugin and loads
-- it at startup; lazy = true makes it load on first require (from 99's
-- telescope extension) instead.
return {
  { "nvim-telescope/telescope.nvim", lazy = true },
}'''),
    blank,
    ...para('--',
        r'lazy = true tells lazy.nvim not to load the plugin at startup. It loads the first time '
        r'something calls require on one of its modules. In this repo that something is '
        r'lua/plugins/ninety-nine.lua, which maps the model and provider selectors to '
        r'require("99.extensions.telescope").select_model() and select_provider(). The 99 extension '
        r'requires telescope when one of those keys is pressed, and that is when the plugin loads.'),
    blank,
    ...para('--',
        r'The spec is a list with one entry, a table with the plugin name and lazy = true. The outer '
        r'braces are there because the file returns a list of specs, a shape that allows a second '
        r'spec to be added without restructuring. Right now there is just one.'),
    ...sec(r'the other end of the arrangement'),
    ...para('--',
        r'ninety-nine.lua declares nvim-telescope/telescope.nvim in its dependencies (line 4) and '
        r'carries its own comment about avoiding eager loading of 99, telescope and blink.compat at '
        r'startup (line 9). The two files work together. 99 is lazy through its keys; the dependency '
        r'would defeat that unless telescope is lazy too, so telescope.lua is the piece that stops '
        r'the dependency from pulling itself into the startup path.'),
    ...sec(r'how it is tested'),
    ...pt('--', r'tests/agent-99-guard_spec.lua',
        r'line 76: "does not load 99, telescope or blink.compat at startup". It asserts that the '
        r'telescope module is not in package.loaded and that lazy.nvim does not mark telescope.nvim '
        r'as loaded.'),
    ...pt('--', r'same file, line 85',
        r'"depends on telescope.nvim and blink.compat 2.*", so the dependency is real and not left '
        r'over.'),
    ...pt('--', r'same file, line 97',
        r'after 99 loads, telescope is loaded with it ("telescope not loaded with 99" is the failure '
        r'message), which proves the lazy load still fires.'),
    ...pt('--', r'tests/startup-and-options_spec.lua',
        r'line 113 records whether telescope is loaded in its startup snapshot.'),
    ...sec(r'history'),
    ...pt('--', r'0494b52 (2026-10-12)',
        r'the only commit, "Field test fixes: sandbox hardening, local history, nav/search, debug; '
        r'docs". The file did not change after the extraction of the Rust plugins on 2026-10-22.'),
    ...sec(r'is it in xyno-plugins?'),
    ...para('--',
        r'No. Nothing in ~/projects/xyno-plugins uses telescope, so there is nothing to compare.'),
  ],
);
