import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lazy-lock.json',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'lazy-lock.json — 61 commit hashes that define “works here”'),
    cm('//', 'written by lazy.nvim, read by every fresh install'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'exact git commit of every installed plugin'),
    kv('language', 'JSON, one plugin per line, written by lazy.nvim'),
    kv('size', '63 lines, 61 plugins'),
    kv('history', '17 commits, 2026-08-17 to 2026-10-13'),
    kv('last change', 'e874f9f (2026-10-13): the 18 Omarchy theme entries removed'),

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
  "SchemaStore.nvim": { "branch": "main", "commit": "31626d9d0a95418bf12a8b3f0e8f9f42e73e1f35" },
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
        'name, the key follows it. Several keys carry no .nvim suffix, '
        'for example harpoon, neogen, treesj and catppuccin.'),
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

    ...sec('what is in the 61'),
    ...para('//',
        'There is no theme plugin of this repository in the file: the '
        'island theme is Lua inside the repository itself (lua/island). '
        'Only catppuccin and tokyonight.nvim are left, because LazyVim '
        'ships them.'),
    ...pt('//', 'branches',
        '44 entries sit on main, 16 on master and one on harpoon2 '
        '(harpoon), which is an explicit branch setting in its spec.'),
    ...pt('//', 'the repository’s additions',
        'beyond LazyVim and its core: rustaceanvim and crates.nvim from the '
        'Rust extra, neo-tree, auto-save.nvim, harpoon, 99 and blink.compat, '
        'and since 2026-10-09 diffview, nvim-dap with nvim-dap-ui and '
        'virtual-text, neotest, nvim-coverage, overseer, kulala, '
        'claudecode, inc-rename, neogen, navic, treesitter-context, '
        'satellite, treesj, mini.surround and markdown-preview.'),
    ...pt('//', 'a dependency you can see',
        'telescope.nvim is in the lock even though LazyVim 16 uses '
        'snacks as its picker. It is here because lua/plugins/'
        'ninety-nine.lua lists telescope as a dependency and uses '
        'its model and provider pickers.'),

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
        'Islands Dark port replaced it.'),
    ...pt('//', 'eabb22a, 2026-09-02',
        'jumps to 57. The migration deleted 18 of the 30 entries '
        '(LuaSnip, nvim-cmp and its sources, toggleterm, '
        'undotree, fugitive, fidget, flutter-tools and others) '
        'and brought in LazyVim with everything it ships plus '
        'twenty theme plugins for the Omarchy switcher. Only 12 names survive from the old '
        'lock; 8 of them kept the very same commit.'),
    ...pt('//', '3ec11c4, 2026-09-03',
        'still 57, but 7 pins moved: aether, mason-lspconfig, '
        'neo-tree, nvim-lint, nvim-lspconfig, nvim-treesitter '
        'and rustaceanvim, in the commit that introduced '
        'bacon-ls. It shows that a sync was run alongside the '
        'change; the commit message does not say why.'),
    ...pt('//', '07993a4, 2026-09-03',
        '58. blink.compat, the one new plugin the 99 completion '
        'fix needed.'),
    ...pt('//', 'b81fd48, 2026-10-09',
        '67: roadmap step 2 added SchemaStore.nvim, markdown-preview, '
        'mason-nvim-dap, neotest, nvim-dap and the other debug and test '
        'dependencies; monokai-pro.nvim is dropped in the same commit.'),
    ...pt('//', '10cb8c8 and da5ede9, 2026-10-09',
        '68 (diffview, step 6), then 75 (step 7: inc-rename, mini.surround, '
        'neogen, nvim-navic, treesitter-context, satellite, treesj).'),
    ...pt('//', 'five “wip” commits, 2026-10-09',
        '76, 77, 77, 77 and 79 entries: claudecode.nvim, kulala.nvim and '
        'nvim-coverage arrive, and monokai-pro.nvim, dropped in b81fd48, comes back in the last of them.'),
    ...pt('//', 'e874f9f, 2026-10-13',
        '61. Remove Omarchy support deleted 18 theme entries (aether, '
        'ashen, bamboo, ethereal, everforest, flexoki, gruvbox, hackerman, '
        'kanagawa, lumon, matteblack, miasma, monokai-pro, nightfox, '
        'retro-82, rose-pine, vantablack, white) and nothing else of '
        'substance; which-key.nvim appears as a moved line.'),
    ...para('//',
        'The file has not changed since, through the 2026-10-22 commits '
        'that extracted the standalone plugins; those are not lazy.nvim '
        'dependencies of this configuration.'),

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
    ...pt('//', 'Mason packages',
        'mason.nvim is pinned, the tools it installs (codelldb '
        'from the Rust extra, and bacon-ls, which the spec requires at '
        '0.31.0 or newer) are not.'),
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
        'runs the editor to prove it works in the file itself. scripts/'
        'bootstrap.sh and tests/health-bootstrap-ci_spec.lua use a '
        'copy of the lockfile in a temp checkout, but the 61 hashes '
        'have been exercised only on the machine that wrote them.'),
    ...pt('//', 'hashes say nothing about intent',
        'to learn why a plugin is where it is you read the '
        'commit that moved it. Several commits that touch the file '
        'are titled only “wip”.'),

    blank,
    link('→ github.com/xynorash/xynovim', 'https://github.com/xynorash/xynovim'),
  ],
);
