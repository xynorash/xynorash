import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/lazy.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'lazy.lua — bootstrap the plugin manager, hand it LazyVim'),
    cm('--', '72 lines: the LazyVim starter layout plus later edits of its own'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'installs lazy.nvim if missing and starts it'),
    kv('language', 'Lua'),
    kv('size', '72 lines'),
    kv('origin', 'LazyVim starter layout, edited'),
    kv('history', '10 commits, 1c496fd (2026-08-17) to ff1c8fa (2026-10-16)'),

    ...sec('why this file exists'),
    ...para('--',
        'Every plugin in this repository is managed by lazy.nvim, and '
        'lazy.nvim has to come from somewhere. This file is the bootstrap: '
        'if the plugin manager is not on disk it clones it, puts it on the '
        'runtime path, and then calls setup with a spec that names two '
        'sources of plugins, LazyVim and the lua/plugins directory of this '
        'repository. init.lua requires it and does nothing else.'),
    ...para('--',
        'The first version of the file (1c496fd, 2026-08-17) was 17 lines '
        'of hand-written bootstrap. eabb22a (2026-09-02, “Migrate to '
        'LazyVim-based config”) replaced it with the LazyVim starter file. '
        'Since then it has been edited in eight more commits. Several '
        'are defensive: they make a failure in the environment '
        'degrade instead of aborting the editor (the unwritable '
        'cache and the headless clone failure below).'),

    ...sec('the bootstrap, and what happens when it fails'),
    ...code('lua', 'lua/config/lazy.lua · lines 1-19', r'''
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    if #vim.api.nvim_list_uis() > 0 then
      vim.fn.getchar()
    end
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)'''),
    ...pt('--', 'where it installs',
        'stdpath("data") is the data directory, not the config directory, '
        'so lazy.nvim and all plugins live outside the repository. Only '
        'lazy-lock.json comes back into the repo, because lazy.nvim’s '
        'default lockfile path is stdpath("config") plus /lazy-lock.json.'),
    ...pt('--', '--filter=blob:none',
        'a blobless clone: history and trees now, file contents fetched on '
        'demand. A first launch downloads far less.'),
    ...pt('--', '--branch=stable',
        'the clone takes the stable branch at whatever commit it is on '
        'that day. The lockfile pins lazy.nvim afterwards, but the very '
        'first checkout on a new machine is not reproducible.'),
    ...pt('--', 'the failure message',
        'nvim_echo prints the git output in WarningMsg, then the code '
        'waits for a key before exiting, so the message does not flash '
        'and vanish as the screen is torn down.'),
    blank,
    ...para('--',
        'The getchar guard is the newest edit of this block. ff1c8fa '
        '(2026-10-16, “Windows and macOS: portability fixes”) wrapped '
        'vim.fn.getchar() in a check that at least one UI is attached. '
        'Without it, a headless run (a CI job, or the test runner that '
        'starts nvim with --headless) that fails to clone would block '
        'forever waiting for a keypress nobody can give. The diff is '
        'three lines: the if, the call, the end.'),

    ...sec('a cache directory that may not be writable'),
    ...code('lua', 'lua/config/lazy.lua · lines 21-28', r'''
-- vim.loader (lazy's module cache) creates stdpath("cache")/luac; an
-- unwritable XDG_CACHE_HOME raised E739 and init.lua aborted, leaving nvim
-- without any config. Without a writable cache dir run uncached.
local function writable_dir(dir)
  pcall(vim.fn.mkdir, dir, "p")
  return vim.fn.filewritable(dir) == 2
end
local cache_ok = writable_dir(vim.fn.stdpath("cache"))'''),
    ...para('--',
        'This block came in f31e013 (2026-10-14, “Final loop round 4: '
        'field test leftovers”), whose message lists “unwritable cache”. '
        'The comment is the whole story: lazy.nvim enables Neovim’s '
        'vim.loader, which writes compiled Lua under the cache directory. '
        'If that directory cannot be created, error E739 was raised from '
        'inside init.lua and Neovim started with no configuration at all, '
        'which is the worst possible failure for an editor config.'),
    ...para('--',
        'The fix is a small predicate. pcall(vim.fn.mkdir, dir, "p") tries '
        'to create the directory and swallows the error; '
        'vim.fn.filewritable(dir) == 2 then asks whether it is a '
        'writable directory (1 would mean a writable file). The answer '
        'is used once, further down, as the value of the cache option.'),

    ...sec('the spec'),
    ...code('lua', 'lua/config/lazy.lua · lines 30-45', r'''
require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    ...
    lazy = false,
    ...
    version = false, -- always use the latest git commit
    ...
  },
  install = { colorscheme = { "island-dark", "tokyonight", "habamax" } },'''),
    ...pt('--', 'two imports, in order',
        'LazyVim’s plugins first, then the user’s plugins directory. '
        'Overrides only work in one direction, so the order is fixed: a '
        'spec in lua/plugins can modify a LazyVim plugin, never the '
        'other way round.'),
    ...pt('--', 'lazy = false',
        'plugins from this repository load at startup unless a spec says '
        'otherwise, while LazyVim’s own plugins arrive already lazy. This '
        'single default is why CHANGELOG 1.3.0 exists: a custom spec '
        'that does not name an event, a command or keys is eager.'),
    ...pt('--', 'version = false',
        'follow the latest commit of each plugin’s default branch, not '
        'tagged releases. The starter’s comment gives the reason: many '
        'plugins have outdated releases that can break Neovim. That is '
        'only safe because lazy-lock.json records the exact commit of '
        'each plugin, so a bad update can be undone by restoring the '
        'lockfile and running :Lazy restore.'),
    ...pt('--', 'install.colorscheme',
        'the colorscheme lazy tries while it installs missing plugins on '
        'first launch, so the install screen is not drawn in default '
        'colours. The list now starts with island-dark, the permanent '
        'theme (lua/island, lua/plugins/island-theme.lua). Earlier it '
        'read tokyonight, habamax; the island entry first appears in cf842d0 '
        '(2026-10-12) and Omarchy support was removed in e874f9f '
        '(2026-10-13).'),

    ...sec('luarocks off, checker off'),
    ...code('lua', 'lua/config/lazy.lua · lines 46-57', r'''
  -- No plugin needs luarocks; without this `:checkhealth lazy` reports an
  -- ERROR for the missing hererocks/luarocks.
  rocks = { enabled = false },
  checker = {
    -- OFF: the periodic checker spawns background git fetches AND pulls
    -- lazy's whole management machinery (lazy.manage, view.commands,
    -- runner, task, process - ~6-10ms) into every startup. Update
    -- manually with :Lazy sync instead.
    enabled = false,
    notify = false,
  },'''),
    ...pt('--', 'rocks',
        'lazy.nvim looks for luarocks or hererocks to support plugins that '
        'declare rocks. None of the plugins here do, and the health '
        'check reports an ERROR when neither tool exists. Turning the '
        'feature off removes the false alarm. The line arrived in 99acd7e '
        '(2026-10-13).'),
    ...pt('--', 'checker',
        'changed in f35b4f6 (2026-09-03, CHANGELOG 1.3.0, “Zero '
        'background activity”). Two costs are named in the comment: '
        'background git fetches of every plugin repository, and loading '
        'lazy’s management modules into every session. The 6 to 10 ms '
        'figure is the author’s comment; the repository does not say '
        'how it was measured, and it sits inside the larger measured '
        'result of 28.7 ms down to about 18 ms for the whole commit.'),
    blank,
    ...para('--',
        'Turning the checker off changes the update workflow into '
        'something deliberate: nothing changes on disk until :Lazy sync '
        'runs, and each sync rewrites lazy-lock.json, so every plugin '
        'update is a visible diff in git.'),

    ...sec('the performance block'),
    ...code('lua', 'lua/config/lazy.lua · lines 58-72', r'''
  performance = {
    cache = { enabled = cache_ok },
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})'''),
    ...para('--',
        'cache = { enabled = cache_ok } is where the predicate from above '
        'lands: with a writable cache directory the module cache is on, '
        'otherwise Neovim runs uncached and slower but alive.'),
    ...para('--',
        'The disabled_plugins list removes Vim runtime plugins most people '
        'never use: editing inside gzip, tar and zip archives, the '
        ':TOhtml converter and :Tutor. Three more candidates stay '
        'commented out as the starter had them: matchit, matchparen '
        'and netrwPlugin. No measurement of the saving is recorded.'),

    ...sec('what the file does not set'),
    ...para('--',
        'There is no change_detection key, so lazy.nvim uses its default '
        '(enabled, with notifications). The very first lazy.lua passed '
        'change_detection = { notify = false }; the starter dropped '
        'that. The file used to carry a Neovim-theme hot reload that '
        'relied on this watcher, but that feature was removed together '
        'with Omarchy support in e874f9f, so nothing in the repository '
        'depends on change detection any more.'),

    ...sec('the Omarchy shim that used to live here'),
    ...para('--',
        'Until 2026-10-13 this file also held about 25 lines that '
        'replaced the global loadfile function: Omarchy managed '
        'lua/plugins/theme.lua as a symlink into its state directory, '
        'and the shim answered that file with an empty spec unless '
        'vim.g.xynovim_follow_omarchy was set, so that Island Dark '
        'stayed the theme. e874f9f (“Remove Omarchy support: Island '
        'Dark unconditional”) deleted the shim, the theme symlink, '
        'all-themes.lua and the hot-reload plugin, 312 lines removed '
        'against 31 added across 12 files. A file that once wrapped a '
        'global was a candidate for deletion as soon as its reason was '
        'gone, and it was deleted.'),

    ...sec('what changed over time'),
    ...pt('--', '1c496fd, 2026-08-17',
        '17 lines importing config.plugins with change_detection notify '
        'off. No error handling on the clone.'),
    ...pt('--', 'eabb22a, 2026-09-02',
        'replaced wholesale by the LazyVim starter file; the checker is '
        'enabled and silent.'),
    ...pt('--', 'f35b4f6, 2026-09-03',
        'checker switched off, with the comment above.'),
    ...pt('--', 'cf842d0, 2026-10-12',
        'island-dark first appears in the install colorscheme list.'),
    ...pt('--', '99acd7e, 2026-10-13',
        'rocks switched off.'),
    ...pt('--', 'e874f9f, 2026-10-13',
        'Omarchy shim removed (25 lines deleted from this file).'),
    ...pt('--', 'f31e013, 2026-10-14',
        'writable-cache predicate.'),
    ...pt('--', 'ff1c8fa, 2026-10-16',
        'getchar only when a UI exists.'),

    ...sec('limits'),
    ...pt('--', 'estimates, not receipts',
        'the 6 to 10 ms is a comment, not a benchmark in the repo; the '
        '28.7 to 18 ms total is the measured number to trust.'),
    ...pt('--', 'not tested directly',
        'the clone failure path and the unwritable cache path are '
        'environmental. tests/startup-and-options_spec.lua probes the '
        'lazy.nvim state after startup (stats, notifications, whether the '
        'manage and checker modules were loaded, which supports the '
        'checker-off decision); no spec was found that forces a failing clone.'),

    blank,
    link('→ github.com/xynorash/xynovim', 'https://github.com/xynorash/xynovim'),
  ],
);
