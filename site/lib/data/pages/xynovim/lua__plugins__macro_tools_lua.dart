import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/macro-tools.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'macro-tools.lua — start the macro tools after LazyVim is done'),
    cm('--', r'a one-shot VeryLazy hook, and the blink source for macro snippets'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'lazy.nvim plugin file: runs config.macro_tools.setup() and registers its blink source'),
    kv(r'language', r'Lua (autocmd + lazy.nvim spec)'),
    kv(r'size', r'20 lines, 1 commit (b9363cd, 2026-10-14)'),
    kv(r'trigger', r'User VeryLazy, once'),
    ...sec(r'why this file exists'),
    ...para('--', r'config/macro_tools.lua defines the commands :MacroExpand, :MacroFormatFix, :MacroSignature and :ProcMacroStatus, the insert-mode <C-k> popup, the hint diagnostics, and a blink source for select!, matches! and vec![x; n]. This file is what starts it. It has two parts: an autocmd, and a spec for blink.cmp. The comment at the top is also the table of contents of the feature.'),
    ...code('lua', r'lua/plugins/macro-tools.lua · lines 1-4', r'''
-- Macro call help, macro lens and proc-macro status (config/macro_tools.lua):
-- :MacroExpand, :MacroFormatFix, :MacroSignature, :ProcMacroStatus, the insert
-- mode <C-k> and the blink source for select!/matches!/vec![x; n]. Setup
-- waits for VeryLazy so the buffer-local maps win over LazyVim's.'''),
    ...sec(r'why VeryLazy'),
    ...para('--', r'The last words of the header carry the reason: setup waits for VeryLazy so the buffer-local maps win over LazyVim’s. The macro tools set buffer-local keys (<leader>rx, <leader>rq and, in insert mode, <C-k>) when a language server attaches. LazyVim sets its own LSP maps in the same situation, and <C-k> in insert mode is its signature help. If both ran at an arbitrary moment, whoever ran last would win. Running setup after LazyVim has finished starting up, on its VeryLazy event, orders the two; config/macro_tools.lua additionally delays its own mapping by 120 ms after every LspAttach, for the maps that LazyVim sets on each attach.'),
    ...code('lua', r'lua/plugins/macro-tools.lua · lines 5-12', r'''
vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("xynovim_macro_tools_load", { clear = true }),
  pattern = "VeryLazy",
  once = true,
  callback = function()
    require("config.macro_tools").setup()
  end,
})'''),
    ...pt('--', r'augroup', r'xynovim_macro_tools_load with clear = true, so re-sourcing the file does not stack handlers.'),
    ...pt('--', r'pattern = "VeryLazy"', r'a User event that LazyVim fires after the UI is up. once = true removes the autocmd after the first run.'),
    ...pt('--', r'callback', r'require("config.macro_tools").setup(). The require is inside the callback, so the module (2455 lines) is not loaded at all until the editor has started.'),
    ...sec(r'the blink spec'),
    ...para('--', r'The second part returns a spec for saghen/blink.cmp whose opts is a function. A function form is needed because the module has to change a list that already exists: it appends macro_tools to the default sources, and that cannot be written as a static table without replacing the default list.'),
    ...code('lua', r'lua/plugins/macro-tools.lua · lines 13-20', r'''
return {
  {
    "saghen/blink.cmp",
    opts = function(_, opts)
      return require("config.macro_tools").blink_opts(_, opts)
    end,
  },
}'''),
    ...para('--', r'blink_opts, in the module, registers the provider macro_tools (name Macro, module config.macro_tools, score_offset = -1) and inserts it in sources.default if that is a table and does not already contain it. The offset is negative: the snippets come after rust-analyzer’s own items, so a snippet never outranks a real completion. The function returns opts, which is the contract for a lazy.nvim opts function that does not return nil.'),
    ...para('--', r'One consequence of once = true: setup() runs exactly once per session, from the first VeryLazy event. The module itself is written to be called again safely (it clears its autocmd group first, so a second call replaces its handlers instead of stacking them), which matters for the specs that call setup() directly.'),
    ...sec(r'contrast with macro-attrs.lua'),
    ...para('--', r'The attribute completion plugin file uses init for its setup and per_filetype for its source, and adds no event hook. The macro tools need the hook because they own keymaps and autocmds, whereas the attribute source only owns one command and is called by blink.'),
    ...sec(r'in xyno-macros.nvim'),
    ...para('--', r'The plugin has no equivalent of this file. xyno_macros.setup(opts) calls both setup functions, key mapping is opt-in (keymaps = true), and xyno_macros.blink_opts registers both blink sources. The plugin README suggests loading with ft = "rust" or event = "VeryLazy".'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/macro-tools_spec.lua: "registers the provider and offers select!, matches!, vec![x; n]", "never offers anything after a dot", and in the live section "<C-k> and the other keys are buffer-local on a rust-analyzer buffer" and "keys and commands are registered and avoid the taken ones".'),
  ],
);
