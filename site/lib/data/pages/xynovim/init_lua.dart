import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/init.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'init.lua — two lines that hand the editor to lazy.nvim'),
    cm('--', 'the entire entry point, byte-identical to LazyVim’s starter'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'first file Neovim executes; delegates everything'),
    kv('language', 'Lua'),
    kv('size', '2 lines (one comment, one require)'),
    kv('origin', 'LazyVim/starter, unchanged'),
    kv('history', '2 commits: 6 lines at birth, 2 lines since 2026-09-02'),

    ...sec('what this file is'),
    ...para('--',
        'Neovim runs init.lua from its config directory before '
        'anything else. In this repository that file is the '
        'smallest thing that could possibly work: one comment and '
        'one require. All real work happens in lua/config/lazy.lua, '
        'which bootstraps the plugin manager and tells it to load '
        'LazyVim plus everything under lua/plugins/.'),
    ...code('lua', 'init.lua · the whole file', r'''
-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")'''),
    ...para('--',
        'The comment still says “your plugins” because it is the '
        'starter’s wording. Compared with the last commit of '
        'github.com/LazyVim/starter (803bc18, 2024-12-11) the '
        'file is identical, as are stylua.toml, '
        '.neoconf.json, .gitignore, LICENSE, lua/config/keymaps.lua '
        'and lua/config/autocmds.lua. Only lua/config/lazy.lua and '
        'lua/config/options.lua differ from the starter. Knowing '
        'which files are stock is useful: the diff between this '
        'repository and the starter is the real configuration, and '
        'it is small.'),

    ...sec('what used to be here'),
    ...para('--',
        'The first commit of this repository (1c496fd, 2026-08-17) '
        'was a from-scratch Windows config, written, in its own '
        'commit message, “inspired by ThePrimeagen’s init.lua (same '
        'infra choices, same leader convention)”. Its init.lua was '
        'six lines and spelled out the boot order by hand:'),
    plain('-- init.lua at 1c496fd (no longer in the tree)'),
    plain('vim.g.mapleader = " "'),
    plain('vim.g.maplocalleader = " "'),
    blank,
    plain('require("config.options")'),
    plain('require("config.lazy")'),
    plain('require("config.keymaps")'),
    blank,
    ...para('--',
        'The migration commit eabb22a (2026-09-02, “Migrate to '
        'LazyVim-based config (Linux/Omarchy)”) deleted four of '
        'those lines. Each responsibility did not vanish, it moved '
        'into a LazyVim hook:'),
    ...pt('--', 'leader keys',
        'now set by LazyVim’s own options file, which sets '
        'mapleader to a space and maplocalleader to a backslash. '
        'The old config set both to a space.'),
    ...pt('--', 'options',
        'lua/config/options.lua is still mine, but LazyVim '
        'requires it, not init.lua, and requires its own '
        'defaults file first so mine can override them.'),
    ...pt('--', 'keymaps',
        'lua/config/keymaps.lua is loaded by LazyVim on the '
        'VeryLazy event instead of at the end of init.lua.'),
    ...para('--',
        'The CHANGELOG entry for 1.0.0 calls this “a platform '
        'lineage switch, not an incremental edit”. init.lua is '
        'where the switch is most visible: a file that used to '
        'encode an ordering now encodes none, because the ordering '
        'belongs to the framework.'),

    ...sec('the boot sequence after the require'),
    ...para('--',
        'The order below is taken from the LazyVim source at the '
        'commit pinned in lazy-lock.json (c10948c, release 16.0.0) '
        'and from lazy.nvim at its pinned commit. It is worth knowing '
        'because it explains why each file in lua/config/ is '
        'allowed to be tiny.'),
    ...pt('--', '1. config.lazy runs',
        'lua/config/lazy.lua clones lazy.nvim if it is missing, '
        'prepends it to the runtime path and calls setup with the '
        'spec { LazyVim/LazyVim, import = "lazyvim.plugins" } and '
        '{ import = "plugins" }.'),
    ...pt('--', '2. LazyVim wakes up',
        'importing lazyvim.plugins runs a version gate first '
        '(LazyVim 16 refuses to start below Neovim 0.11.2) and then '
        'calls lazyvim.config.init().'),
    ...pt('--', '3. options load early',
        'init() loads lazyvim.config.options and then config.options '
        '(this repo’s file) before lazy has finished sourcing plugin '
        'specs, then reads lazyvim.json.'),
    ...pt('--', '4. VeryLazy',
        'after the UI is up, LazyVim loads keymaps (and autocmds, '
        'unless a file was passed on the command line, in which '
        'case autocmds were loaded at setup time), then format, '
        'news and root detection.'),
    ...para('--',
        'The consequence for this repo: anything that must exist '
        'before plugins are configured belongs in options.lua '
        '(the clipboard provider, the rust diagnostics switch), '
        'while keymaps and autocmds can wait for VeryLazy. That is '
        'exactly how the files are used.'),

    ...sec('why the leader must be set before lazy'),
    ...para('--',
        'The old init.lua set the leader before requiring lazy for '
        'a reason that is still true. lazy.nvim records '
        'vim.g.mapleader when it finishes setup, and on a spec '
        'reload its reloader warns “You need to set '
        'vim.g.mapleader BEFORE loading lazy” if the value has '
        'changed. Every plugin key in this repository starts with '
        'the leader (<leader>9s, <leader>a), so a late change would '
        'silently rebind all of them. Today the guarantee comes '
        'from LazyVim loading its options file during step 3, '
        'ahead of any plugin spec being applied.'),
    ...para('--',
        'It is also a hidden dependency: nothing in this repository '
        'sets the leader, so the repository relies on LazyVim’s '
        'default staying a space. A future LazyVim release that '
        'changed it would move every binding here.'),

    ...sec('small facts'),
    ...pt('--', 'file mode',
        'the migration commit flipped init.lua, keymaps.lua, '
        'lazy.lua and options.lua from mode 100644 to 100755 '
        '(git reports “mode change”). Neovim does not care.'),
    ...pt('--', 'what is not here',
        'no vim.loader.enable(), no options, no autocmds. '
        'lazy.nvim switches its own module cache on by default '
        '(performance.cache.enabled is true in the lazy.nvim '
        'version pinned by the lockfile), so no hand-written '
        'startup trick is needed at this level. The startup '
        'work that was done lives elsewhere: see '
        'lua/config/lazy.lua and CHANGELOG.md 1.3.0.'),
    ...pt('--', 'what would belong here',
        'only something that has to run before lazy.nvim exists, '
        'such as a guard against an unsupported Neovim. LazyVim '
        'already carries that guard itself.'),

    ...sec('what to take from it'),
    ...para('--',
        'A good entry point is boring. The interesting engineering '
        'in this repository (two-tier Rust diagnostics, a patched '
        'language server, a clipboard that follows you over SSH) '
        'sits in plugin specs and a few config modules where each '
        'decision has a comment and a measurement next to it. '
        'Keeping init.lua stock means that when LazyVim changes '
        'its template, there is nothing here to merge.'),
    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
