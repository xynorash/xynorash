import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lazy-lock.json',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'lazy-lock.json — 58 commit hashes that define “works here”'),
    cm('//', 'written by lazy.nvim, read by every fresh install'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'exact git commit of every installed plugin'),
    kv('language', 'JSON, one plugin per line, written by lazy.nvim'),
    kv('size', '60 lines, 58 plugins'),
    kv('history', '8 commits, 2026-08-17 to 2026-09-03'),
    kv('last change', '07993a4: added blink.compat'),

    ...sec('what pinning means here'),
    ...para('//',
        'Plugin managers can follow a branch, a release tag or an '
        'exact commit. This configuration follows the latest '
        'commit of each plugin (defaults.version is false in '
        'lua/config/lazy.lua, so no release tags are used) and '
        'then freezes the result in this file. The two choices '
        'work as a pair: floating makes updates cheap and always '
        'available, pinning makes them deliberate and reversible. '
        'Because the update checker is also switched off, nothing '
        'moves until :Lazy sync is run by hand, and when it does, '
        'the change shows up as a diff of this file.'),
    ...code('json', 'lazy-lock.json · a few entries', r'''
{
  "99": { "branch": "master", "commit": "c17422457027c913c76c75a921fca1e623d2678e" },
  "LazyVim": { "branch": "main", "commit": "c10948c50b18fae7f256433afdef09e432410480" },
  "aether": { "branch": "v3", "commit": "567efb778534e11ee1072d4fe27178f705a27d8a" },
  ...
  "harpoon": { "branch": "harpoon2", "commit": "87b1a3506211538f460786c23f98ec63ad9af4e5" },
  "lazy.nvim": { "branch": "main", "commit": "85c7ff3711b730b4030d03144f6db6375044ae82" },
  ...
  "rustaceanvim": { "branch": "main", "commit": "8fa1a98f514041132ab40088be53c130eb8d14c9" },
  ...
}'''),
    ...para('//',
        'Each entry is a plugin name, the branch that was checked '
        'out, and the full 40-character commit. That is all the '
        'file contains. It has no versions, no hashes of content '
        'and no dates: the commit is the identity.'),

    ...sec('who writes it, and why it looks so regular'),
    ...para('//',
        'Nobody edits this file by hand. In the lazy.nvim source at '
        'the pinned commit, lazy/manage/lock.lua rewrites it after '
        'operations such as clean and update. For every installed '
        'plugin that is not a local directory it records the '
        'branch and commit reported by git, sorts the names with '
        'a plain table sort, and writes one line per plugin with '
        'a fixed format string. Three visible traits follow from '
        'that code:'),
    ...pt('//', 'order',
        'names are sorted by byte value, which puts "99" and '
        '"LazyVim" before everything lowercase. That is why the '
        'first two entries look out of place.'),
    ...pt('//', 'keys are plugin names, not repositories',
        'the key is plugin.name. Where a spec sets an explicit '
        'name, the key follows it: "aether", "catppuccin" and '
        '"rose-pine" are explicit names in lua/plugins/all-themes.lua, '
        'while "tokyonight.nvim" is the repository name.'),
    ...pt('//', 'local plugins are skipped',
        'a plugin loaded from a local directory has no commit to '
        'record. The first version of this repository used two '
        '(harpoon and 99 from clones under ~/personal) and neither '
        'appeared in the lockfile. Now both are ordinary GitHub '
        'plugins and both are pinned.'),

    ...sec('where the lock does real work'),
    ...pt('//', 'a fresh machine',
        'on first launch lazy.nvim installs every missing plugin. '
        'In its startup code the install call is made with the '
        'lockfile option set, so a new installation lands on these '
        'exact commits and not on whatever the default branches '
        'hold that day.'),
    ...pt('//', ':Lazy restore',
        'is implemented as an update with the lockfile flag, that '
        'is, move every plugin to the recorded commit. After a '
        'bad :Lazy sync, git checkout of this file followed by '
        ':Lazy restore is the undo.'),
    ...pt('//', ':Lazy sync',
        'cleans, installs and updates, and rewrites the file. '
        'README.md and the comment in lua/config/lazy.lua both '
        'name it as the way to update.'),

    ...sec('what is in the 58'),
    ...para('//',
        'Counting from the file against lua/plugins/all-themes.lua:'),
    ...pt('//', '20 colorschemes',
        'more than a third of the lockfile. all-themes.lua '
        'declares 20 theme plugins so that every theme Omarchy '
        'can switch to is already installed and the hot reload in '
        'omarchy-theme-hotreload.lua never has to download one. '
        'Each of the 20 is pinned like any other plugin.'),
    ...pt('//', '38 everything else',
        'LazyVim and its core (snacks.nvim, blink.cmp, '
        'conform.nvim, nvim-lspconfig, mason, treesitter and '
        'textobjects, which-key, gitsigns, flash, trouble and so '
        'on), plus the plugins this repository adds: '
        'rustaceanvim and crates.nvim from the Rust extra, '
        'neo-tree, auto-save.nvim, harpoon, 99 and blink.compat.'),
    ...pt('//', 'branches',
        '44 entries sit on main, 12 on master, one on harpoon2 '
        '(harpoon) and one on v3 (aether). The last two are '
        'explicit branch settings in the plugin specs.'),
    ...pt('//', 'a dependency you can see',
        'telescope.nvim is in the lock even though LazyVim 16 uses '
        'snacks as its picker. It is here because lua/plugins/'
        'ninety-nine.lua lists telescope as a dependency and uses '
        'its model and provider pickers.'),
    ...para('//',
        'Two entries explain themselves through the code that '
        'created them. “aether” has a branch of v3 and a name of '
        '“aether” because the comment in all-themes.lua records '
        'that a bare spec built the cache into lazy/aether.nvim '
        'while Omarchy 4’s generated spec renamed it to '
        'lazy/aether, a directory that did not exist yet. That cost '
        'a network clone on first launch and a fallback to '
        'tokyonight until the editor restarted. The lock key is the '
        'visible trace of that fix.'),

    ...sec('how the file grew'),
    ...para('//',
        'Counting entries at each commit that touched the file:'),
    ...pt('//', '1c496fd, 2026-08-17',
        '28 entries. The from-scratch config: nvim-cmp stack, '
        'telescope, treesitter, conform, trouble and so on.'),
    ...pt('//', '3dacffb, 77d80a2, 28fab99',
        '29, 30 and 31 as auto-save.nvim, nvim-lightbulb and '
        'lualine.nvim were added, one commit each, on '
        '2026-08-17 and 18.'),
    ...pt('//', '99bdcbc, 2026-08-18',
        '30 again: the rose-pine plugin was removed when the '
        'Islands Dark port replaced it. It is back in the lock '
        'today, as one of the 20 Omarchy themes.'),
    ...pt('//', 'eabb22a, 2026-09-02',
        'jumps to 57. The migration deleted 18 of the 30 entries '
        '(LuaSnip, nvim-cmp and its sources, toggleterm, '
        'undotree, fugitive, fidget, flutter-tools and others) '
        'and brought in LazyVim with everything it ships plus '
        'the 20 themes. Only 12 names survive from the old '
        'lock; 7 of them kept the very same commit.'),
    ...pt('//', '3ec11c4, 2026-09-03',
        'still 57, but 7 pins moved: aether, mason-lspconfig, '
        'neo-tree, nvim-lint, nvim-lspconfig, nvim-treesitter '
        'and rustaceanvim, in the commit that introduced '
        'bacon-ls. It shows that a sync was run alongside the '
        'change; the commit message does not say why.'),
    ...pt('//', '07993a4, 2026-09-03',
        '58. blink.compat, the one new plugin the 99 completion '
        'fix needed.'),
    ...para('//',
        'No later commit touches the file, including the four '
        'that changed bacon-ls and the startup behaviour. That '
        'is the pin doing its job: the plugin set under test did '
        'not move while the measurements in CHANGELOG 1.3.0 and '
        '1.4.0 were taken.'),

    ...sec('what this file lets the rest of the repository claim'),
    ...para('//',
        'A statement like “the lang.rust extra disables '
        'rust-analyzer diagnostics when the global is set to '
        'bacon-ls” is only true of a particular LazyVim. The '
        'lockfile names that LazyVim (c10948c5, the release '
        'commit of 16.0.0 dated 2026-06-02) and lazy.nvim '
        '(85c7ff37, the 11.17.5 release commit dated 2025-11-06). '
        'The pages in this section that explain framework '
        'behaviour were checked against exactly those two '
        'commits, which is the sense in which the lockfile is '
        'documentation.'),

    ...sec('what it does not pin'),
    ...para('//',
        'The lock covers plugin source and nothing else. Outside '
        'it, and outside this repository, sit:'),
    ...pt('//', 'the bacon-ls binary',
        'a local build of upstream 0.30.0 plus a pull-request '
        'branch, installed with cargo into ~/.cargo/bin, found '
        'through a hard-coded path in lua/plugins/bacon-ls.lua.'),
    ...pt('//', 'Mason packages',
        'mason.nvim is pinned, the tools it installs (codelldb '
        'from the Rust extra, for instance) are not.'),
    ...pt('//', 'rust-analyzer, mold, clang',
        'expected on PATH or in pacman, per the README.'),
    ...pt('//', 'Neovim itself',
        'LazyVim 16 refuses to start below 0.11.2, and the '
        'changelog mentions behaviour of 0.12, but no exact '
        'version is recorded.'),
    ...pt('//', 'the claude CLI',
        'invoked by 99 with a model name set in '
        'lua/plugins/ninety-nine.lua.'),
    ...para('//',
        'So the lock gives reproducible plugins on an unpinned '
        'toolchain. For an editor configuration that is a sensible '
        'boundary, and the README’s Requires paragraph is where '
        'the rest is listed.'),

    ...sec('limits'),
    ...pt('//', 'no verification of the lock',
        'nothing installs the lockfile on a clean machine and '
        'runs the editor to prove it works. The 58 hashes have '
        'been exercised only on the machine that wrote them.'),
    ...pt('//', 'hashes say nothing about intent',
        'to learn why a plugin is where it is you read the '
        'commit that moved it. Of the 8 commits touching the '
        'file, 7 give no reason for individual pin changes.'),

    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
