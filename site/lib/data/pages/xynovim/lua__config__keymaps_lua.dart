import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/keymaps.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'keymaps.lua — an empty file, on purpose'),
    cm('--', '22 lines of personal mappings traded for the framework’s'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'hook where LazyVim loads user keymaps'),
    kv('language', 'Lua'),
    kv('size', '3 lines, all comments'),
    kv('origin', 'LazyVim/starter, unchanged'),
    kv('history', '15 mappings at birth (1c496fd), emptied in eabb22a'),

    ...sec('what is in the file'),
    ...code('lua', 'lua/config/keymaps.lua · the whole file', r'''
-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here'''),
    ...para('--',
        'Nothing executes. The file is the starter’s placeholder and '
        'is identical to it. Its first comment is the useful one: '
        'LazyVim requires lua/config/keymaps.lua on the VeryLazy '
        'event, after its own keymaps file, so anything put here '
        'overrides the framework’s defaults. Keeping the file, '
        'empty, means the hook exists the day it is needed.'),
    ...para('--',
        'One detail from LazyVim’s own keymaps file at the pinned '
        'commit is worth knowing before adding anything: it '
        'defines its mappings through a safe_keymap_set helper and '
        'says, in capitals, not to use that helper in your own '
        'config but plain vim.keymap.set. The helper silently '
        'skips a key that a plugin has already claimed through a '
        'lazy keys table and makes mappings silent by default, '
        'both of which differ from plain vim.keymap.set.'),

    ...sec('what the file held before'),
    ...para('--',
        'The first commit (1c496fd, 2026-08-17) had a 22-line '
        'keymaps file in the style of ThePrimeagen’s config, 15 '
        'mappings in all. The migration to LazyVim (eabb22a, '
        '2026-09-02) replaced it with the stub above. The '
        'CHANGELOG’s “Removed” list for 1.0.0 names plugin specs '
        'and does not mention the keymaps, so the comparison below '
        'is an analysis of mine against LazyVim 16.0.0 as pinned '
        'in lazy-lock.json, not something the author wrote down.'),
    plain('-- a few lines of keymaps.lua at 1c496fd (not in the tree)'),
    plain('set("i", "jk", "<Esc>")'),
    plain('set("n", "<leader>pv", vim.cmd.Ex)'),
    plain(r'''set("v", "J", ":m '>+1<CR>gv=gv")'''),
    plain('set("n", "<C-d>", "<C-d>zz")'),
    plain('set("n", "<leader>y", [["+y]])'),
    plain('set("n", "<leader>w", "<cmd>w<CR>")'),
    blank,
    ...para('--',
        'Where each of the 15 went, checked against LazyVim’s '
        'keymaps and the neo-tree extra at the pinned commit:'),
    ...pt('--', '<C-h> <C-j> <C-k> <C-l> (4)',
        'window navigation. LazyVim maps exactly these four to '
        '<C-w>h/j/k/l. Deleting them lost nothing.'),
    ...pt('--', 'visual J and K (2)',
        'move the selection up or down. LazyVim does the same with '
        '<A-j> and <A-k>, in normal, insert and visual mode. The '
        'keys changed, the capability did not.'),
    ...pt('--', '<leader>y, <leader>Y (3)',
        'yank to the system clipboard. LazyVim sets the clipboard '
        'option to unnamedplus unless SSH_CONNECTION is set, so '
        'ordinary yanks already go there. The SSH case is the '
        'reason lua/config/remote_clipboard.lua exists.'),
    ...pt('--', '<leader>pv (1)',
        'opened netrw. The neo-tree extra maps <leader>e to an '
        'explorer rooted at the project root, which is the '
        'replacement.'),
    ...pt('--', '<leader>w and <leader>q (2)',
        'write and quit. LazyVim saves with <C-s> and quits all '
        'with <leader>qq. It also uses <leader>w as a prefix '
        '(<leader>wd closes a window, <leader>wm zooms one), so a '
        'bare <leader>w mapping would make Neovim wait for more '
        'keys.'),
    ...pt('--', 'jk to Esc (1)',
        'no counterpart. LazyVim’s keymaps file has no such '
        'mapping. This habit was dropped, not replaced.'),
    ...pt('--', '<C-d>zz and <C-u>zz (2)',
        'half-page scroll with the cursor re-centred. LazyVim has '
        'no counterpart, so scrolling is Neovim’s default again.'),
    ...para('--',
        'Tally: 4 identical, 2 re-keyed, 3 absorbed by an option, '
        '1 replaced by a plugin binding, 2 replaced by a different '
        'convention, 3 dropped. Twelve of fifteen survive in some '
        'form, which is the argument for adopting a framework '
        'rather than carrying a private copy of the same choices.'),

    ...sec('where keymaps live now'),
    ...para('--',
        'A grep of the whole tree finds no call to vim.keymap.set '
        'at all. Every mapping this repository defines sits in the '
        'keys table of a plugin spec:'),
    ...pt('--', 'lua/plugins/ninety-nine.lua',
        '11 keys under <leader>9 for the AI assistant.'),
    ...pt('--', 'lua/plugins/harpoon.lua',
        '6 keys: <leader>a, <C-e> and <M-1> to <M-4>.'),
    ...para('--',
        'That is not only tidiness. In lazy.nvim a keys table is '
        'also a lazy-loading trigger: the plugin loads the first '
        'time one of its keys is pressed. ninety-nine.lua says so '
        'in a comment (“Everything is reached through these '
        'keymaps, so lazy-load on them”), and CHANGELOG 1.3.0 '
        'credits this with part of the startup drop from 28.7 ms '
        'to about 18 ms. A global mapping written here would have '
        'to load its plugin eagerly or call require inside a '
        'closure, which is the harpoon mistake the same changelog '
        'entry describes. An empty keymaps.lua is therefore what '
        'a consistent use of lazy keys looks like.'),

    ...sec('limits'),
    ...pt('--', 'bindings are spread out',
        'to see every key this repository defines you read two '
        'plugin specs, and to see the rest you read LazyVim. '
        'There is no single list; the README shows only the 99 '
        'table.'),
    ...pt('--', 'one unrecorded habit',
        'jk for Escape was in the first config and is gone; the '
        'changelog does not record whether that was a decision '
        'or a side effect of the migration.'),

    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
