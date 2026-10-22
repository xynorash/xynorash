import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/macro-attrs.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'macro-attrs.lua — plugs the attribute completion into blink.cmp'),
    cm('--', r'one lazy.nvim spec: a source for Rust buffers, with the defaults kept'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'lazy.nvim plugin spec: registers config.macro_attrs as a blink.cmp provider'),
    kv(r'language', r'Lua (lazy.nvim spec)'),
    kv(r'size', r'25 lines, 1 commit (b9363cd, 2026-10-14)'),
    kv(r'extends', r'saghen/blink.cmp (opts are merged by lazy.nvim, not replaced)'),
    ...sec(r'why this file exists'),
    ...para('--', r'lua/config/macro_attrs.lua knows how to complete inside #[serde(...)] and #[derive(...)], but a module is only code until something asks it. This spec is the something: it adds a source to blink.cmp, the completion engine of this configuration, for Rust buffers only. It is the whole of the integration, and the comment at the top says what it does and what it does not do.'),
    ...code('lua', r'lua/plugins/macro-attrs.lua · lines 1-5', r'''
-- Completion inside helper-attribute arguments (#[serde(...)], #[arg(...)],
-- #[tokio::main(...)], ...) and #[derive(...)], see config/macro_attrs.lua.
-- A blink.cmp source for Rust buffers; the default sources stay (rust-analyzer's own
-- completion is not replaced, this adds what it does not offer).
return {'''),
    ...sec(r'the spec, line by line'),
    ...pt('--', r'"saghen/blink.cmp"', r'the spec does not install anything. It names a plugin that another spec already declares, and lazy.nvim merges the two: opts tables are deep-merged, init functions are all run. That is how one more source gets added without copying the whole blink configuration.'),
    ...pt('--', r'init', r'runs early, before the plugin loads. It calls require("config.macro_attrs").setup(), which only registers the :MacroAttrs debugging command. It runs when lazy.nvim processes the spec, which does not depend on blink.cmp having loaded.'),
    ...pt('--', r'per_filetype', r'sources.per_filetype.rust is set to { "macro_attrs", inherit_defaults = true }. blink.cmp lets a filetype list its own sources; inherit_defaults = true keeps the default source list and adds this one. The comment says what that guarantees: rust-analyzer’s own completion is not replaced, this adds what it does not offer.'),
    ...pt('--', r'providers.macro_attrs', r'declares the source. name is the label shown in the menu, module is the Lua module that blink will require and call new() on (config.macro_attrs has M.new at the end, returning the source object).'),
    ...code('lua', r'lua/plugins/macro-attrs.lua · lines 5-24', r'''
return {
  "saghen/blink.cmp",
  init = function()
    require("config.macro_attrs").setup()
  end,
  opts = {
    sources = {
      per_filetype = {
        rust = { "macro_attrs", inherit_defaults = true },
      },
      providers = {
        macro_attrs = {
          name = "MacroAttrs",
          module = "config.macro_attrs",
          -- above rust-analyzer's generic path items (core::, std::, ...) inside attributes
          score_offset = 100,
        },
      },
    },
  },'''),
    ...sec(r'the score offset'),
    ...para('--', r'score_offset = 100 is the only tuning. Inside an attribute, rust-analyzer returns a lot of generic path items (core::, std::, and so on) that match anything typed. Without a boost, the keys of serde would rank below those. The comment says it exactly: above rust-analyzer’s generic path items inside attributes. The number is large on purpose, since blink adds the offset to the fuzzy score and the goal is to win inside attributes only; elsewhere the source returns no items at all, so the boost cannot disturb ordinary completion.'),
    ...para('--', r'Reading the file top to bottom, the order is: the module is required once in init (setup), the filetype table is declared in opts, and the provider is declared next to it. blink resolves module lazily, so config/macro_attrs.lua is only required when the first Rust buffer asks for completion.'),
    ...sec(r'what is not here'),
    ...para('--', r'No keymap, no filetype autocmd and no list of crates. The data lives in data/macro_attrs/*.json and in the project’s own .xynovim/macro_attrs directory; the source decides by itself, request by request, whether the cursor is inside an attribute it knows (it also answers the trigger-character question per request, so rust-analyzer’s triggers elsewhere are not suppressed).'),
    ...sec(r'in xyno-macros.nvim'),
    ...para('--', r'After the extraction on 2026-10-22 this file has no counterpart as a spec in the plugin. Its job is done by xyno_macros.blink_opts in lua/xyno_macros/init.lua, which a user calls from their own blink.cmp spec: opts = function(_, o) return require("xyno_macros").blink_opts(o) end. blink_opts registers the same provider (name MacroAttrs, module xyno_macros.attrs, score_offset 100), sets the same per_filetype entry, and then also registers the macro snippet source of the other module, so one call replaces both of this repository’s plugin files. The setup() call that this file puts in init is part of xyno_macros.setup().'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/macro-attrs_spec.lua checks the registration: "is registered for Rust buffers next to the default sources, above rust-analyzer’s items", and the longer end-to-end "opens the menu while typing inside #[serde( and accepting a key expands its snippet, re-opening the values", which uses the real blink.cmp completion list.'),
  ],
);
