import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/autocmds.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'autocmds.lua — the empty hook, and where autocmds went instead'),
    cm('--', 'eight lines of comments; the real autocmds live next to their features'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'hook where LazyVim loads user autocmds'),
    kv('language', 'Lua'),
    kv('size', '8 lines, all comments'),
    kv('origin', 'LazyVim starter layout, added in the 1.0.0 migration'),
    kv('history', 'added in eabb22a (2026-09-02); never edited'),

    ...sec('what is in the file'),
    ...code('lua', 'lua/config/autocmds.lua · the whole file', r'''
-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")'''),
    ...para('--',
        'Nothing runs. Unlike lua/config/keymaps.lua there was no '
        'earlier version of this file: the Windows-lineage config '
        'had no autocmds file at all, so it appears for the first '
        'time with the starter layout in eabb22a. The comment is '
        'worth reading closely because the last two lines describe '
        'the whole extension model: add autocmds with '
        'nvim_create_autocmd, remove LazyVim’s by deleting their '
        'augroup by name.'),

    ...sec('when it is loaded'),
    ...para('--',
        'In LazyVim’s config module at the pinned commit, autocmds '
        'are loaded lazily when Neovim starts without a file '
        'argument (argc is 0), on the VeryLazy event. If a file '
        'was passed on the command line they are loaded '
        'immediately during setup; the source comment says '
        'autocmds can be loaded lazily only when no file is being '
        'opened. In both cases the '
        'order is LazyVim’s defaults first, then lua/config/'
        'autocmds.lua, and then a User event named LazyVimAutocmds '
        'fires for anything that wants to hook in.'),

    ...sec('what LazyVim already does'),
    ...para('--',
        'The defaults file creates nine augroups, every one named '
        'with the prefix lazyvim_ and created with clear = true. '
        'Those names are the public handle the comment above '
        'refers to:'),
    ...pt('--', 'lazyvim_checktime',
        'runs :checktime on FocusGained, TermClose and TermLeave '
        'so files changed by other programs are noticed.'),
    ...pt('--', 'lazyvim_highlight_yank',
        'flashes the yanked text.'),
    ...pt('--', 'lazyvim_resize_splits',
        'equalises splits when the terminal is resized.'),
    ...pt('--', 'lazyvim_last_loc',
        'reopens a file at the last cursor position.'),
    ...pt('--', 'lazyvim_close_with_q',
        'for help, quickfix, checkhealth and a list of similar '
        'filetypes, unlists the buffer and maps q to close it.'),
    ...pt('--', 'lazyvim_man_unlisted',
        'keeps inline man pages out of the buffer list.'),
    ...pt('--', 'lazyvim_wrap_spell',
        'turns on wrap and spell for text, markdown, gitcommit and '
        'a few similar filetypes. It is the group the comment '
        'uses as its example of something you could remove.'),
    ...pt('--', 'lazyvim_json_conceal',
        'sets conceallevel to 0 for json, jsonc and json5, which '
        'keeps the quotes in JSON files such as lazyvim.json '
        'visible.'),
    ...pt('--', 'lazyvim_auto_create_dir',
        'creates missing parent directories on BufWritePre.'),

    ...sec('where this repository puts its own autocmds'),
    ...para('--',
        'A search for nvim_create_autocmd now finds the calls in 17 files '
        'under lua, plugin and after, and this file contains none of them. '
        'Each sits next to the feature it serves. The heaviest users are '
        'lua/config/macro_tools.lua and lua/config/disk_guard.lua (six '
        'each), then rust_restart.lua and crate_add.lua (five), lsp_status.lua '
        'and import_engine.lua (four), and three each in ux.lua and '
        'local_history.lua. The older examples are still the clearest:'),
    ...pt('--', 'lua/plugins/auto-save.lua',
        'a User autocmd on AutoSaveWritePost in the group '
        'user_autosave_didsave, which re-sends textDocument/didSave to '
        'language servers after a noautocmd write.'),
    ...pt('--', 'plugin/after/transparency.lua',
        'a ColorScheme autocmd in the group user_transparency, so '
        'transparency is re-applied after any :colorscheme.'),
    ...pt('--', 'lua/config/keymaps.lua',
        'an LspAttach autocmd in the group xynovim_rust_keymaps that binds '
        'the <leader>r Rust maps per buffer.'),
    ...para('--',
        'The omarchy-theme-hotreload plugin that this page used to list '
        'was deleted on 2026-10-13 (e874f9f).'),
    ...para('--',
        'Two conventions show. The groups are named by the repository '
        '(user_ and xynovim_ prefixes, the way LazyVim’s are prefixed '
        'lazyvim_) and created with clear = true, so executing the code '
        'twice replaces the autocmd instead of stacking a second copy.'),
    ...para('--',
        'Why not put them in this file? Because each has a lifetime tied '
        'to something else. The didSave hook is only meaningful while '
        'auto-save is configured, so it is registered inside that '
        'plugin’s config function. Transparency has to be in place at '
        'startup. A VeryLazy file would register them later than needed '
        'and away from the code whose behaviour they change.'),

    ...sec('an interaction worth knowing'),
    ...para('--',
        'auto-save.lua writes with noautocmd = true. The '
        'CHANGELOG entry on the pre-migration diagnostics bug '
        'establishes what that means: no autocmds fire during '
        'the write at all (a plain noautocmd write sent zero LSP '
        'notifications). So LazyVim’s '
        'lazyvim_auto_create_dir, which hooks BufWritePre, does '
        'not run for an auto-save. For a file whose directory '
        'already exists that is invisible. It would matter only '
        'for a brand-new path, where a manual :w creates the '
        'directory and an auto-save would not. That is my '
        'inference from the two mechanisms, not something the '
        'repository records or tests.'),

    ...sec('limits'),
    ...pt('--', 'no tests, no record',
        'there is nothing to verify in an empty file; the claims '
        'above about LazyVim come from reading its source at the '
        'commit that lazy-lock.json pins and will drift when that '
        'pin moves.'),
    ...pt('--', 'unclear ownership',
        'with autocmds split across seventeen files there is '
        'no single place to list them; a grep is the index.'),

    blank,
    link('→ github.com/xynorash/xynovim', 'https://github.com/xynorash/xynovim'),
  ],
);
