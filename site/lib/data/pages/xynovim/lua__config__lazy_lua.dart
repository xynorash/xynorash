import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/lazy.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'lazy.lua — bootstrap the plugin manager, hand it LazyVim'),
    cm('--', '57 lines, 7 of them mine: the update checker, switched off'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'installs lazy.nvim if missing and starts it'),
    kv('language', 'Lua'),
    kv('size', '57 lines'),
    kv('origin', 'LazyVim/starter, with one block edited'),
    kv('history', '3 versions: 1c496fd (17 lines), eabb22a, f35b4f6'),

    ...sec('why this file exists'),
    ...para('--',
        'Every plugin in this repository is managed by lazy.nvim, '
        'and lazy.nvim has to come from somewhere. This file is the '
        'bootstrap: if the plugin manager is not on disk it clones '
        'it, puts it on the runtime path, and then calls setup with '
        'a spec that names two sources of plugins, LazyVim and the '
        'lua/plugins directory of this repository. init.lua '
        'requires it and does nothing else.'),
    ...para('--',
        'Against LazyVim/starter (last commit 803bc18, 2024-12-11) '
        'the file differs in exactly one place, the checker block '
        'near the end. Everything else is the starter verbatim, so '
        'this page is mostly a tour of what the stock lines do and '
        'why the one edited block is the interesting part.'),

    ...sec('the bootstrap'),
    ...code('lua', 'lua/config/lazy.lua · bootstrap', r'''
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
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)'''),
    ...pt('--', 'where it installs',
        'stdpath("data") is the data directory, not the config '
        'directory, so lazy.nvim and all plugins live outside the '
        'repository. Only lazy-lock.json comes back into the repo, '
        'because lazy.nvim’s default lockfile path is '
        'stdpath("config") plus /lazy-lock.json.'),
    ...pt('--', '--filter=blob:none',
        'a blobless clone: history and trees now, file contents '
        'fetched on demand. A first launch downloads far less.'),
    ...pt('--', '--branch=stable',
        'lazy.nvim’s own stable branch, so a fresh machine starts '
        'from a release and not from the tip of main.'),
    ...pt('--', 'the failure path',
        'on a failed clone it prints the git output, waits for a '
        'key press and exits with status 1. The wait matters: '
        'without getchar the message would flash and vanish as the '
        'editor quit. The starter gained this in 79b3f27 '
        '(2024-07-03, “add error handling to initial clone”). '
        'The first version of this repository, written before the '
        'migration, ran vim.fn.system and ignored the result.'),
    ...pt('--', 'the vim.uv fallback',
        '(vim.uv or vim.loop) picks the new libuv alias when it '
        'exists. LazyVim 16 requires Neovim 0.11.2 or newer, so the '
        'fallback is dead weight here, kept because it is stock.'),

    ...sec('the spec: two sources, one order'),
    ...code('lua', 'lua/config/lazy.lua · spec', r'''
require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
  },'''),
    ...para('--',
        'The first entry installs LazyVim as a plugin and imports '
        'every spec under lazyvim.plugins, which is also where '
        'extras from lazyvim.json are pulled in. The second entry '
        'imports every Lua file in lua/plugins/ of this repository. '
        'lazy.nvim merges specs that name the same plugin: options '
        'from later specs are layered over earlier ones. That is '
        'the mechanism behind every small file in lua/plugins/. '
        'rustaceanvim.lua and bacon-ls.lua are written as overrides '
        'of specs that the lang.rust extra already declared, and '
        'they only need to say what is different.'),
    ...para('--',
        'The order is checked, not just conventional. After '
        'startup LazyVim inspects the list of imports and warns if '
        'lazyvim.plugins is not first, or if its extras come after '
        'the user’s plugins directory. Overrides only work in one '
        'direction, so the framework refuses to let the order '
        'drift silently.'),

    ...sec('defaults that explain the rest of the repository'),
    ...code('lua', 'lua/config/lazy.lua · defaults', r'''
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    ...
    lazy = false,
    ...
    version = false, -- always use the latest git commit
    ...
  },
  install = { colorscheme = { "tokyonight", "habamax" } },'''),
    ...pt('--', 'lazy = false',
        'plugins from this repository load at startup unless a '
        'spec says otherwise, while LazyVim’s own plugins arrive '
        'already lazy. This single default is why CHANGELOG 1.3.0 '
        'exists: a custom spec that does not name an event, a '
        'command or keys is eager. 99, telescope and blink.compat '
        'were eager until they were given keys tables, and harpoon '
        'was effectively eager because its keys function required '
        'the plugin while the spec was being built. Fixing those '
        'is part of the startup drop from 28.7 ms to about 18 ms; '
        'the changelog gives no per-item breakdown.'),
    ...pt('--', 'version = false',
        'follow the latest commit of each plugin’s default branch, '
        'not tagged releases. The starter’s comment gives the '
        'reason: many plugins have outdated releases that can '
        'break Neovim. Following commits is only safe because '
        'lazy-lock.json records exactly which commit each plugin '
        'is on, so a bad update can be undone by restoring the '
        'lockfile from git and running :Lazy restore.'),
    ...pt('--', 'install.colorscheme',
        'the colorscheme lazy tries while it installs missing '
        'plugins on first launch, so the install screen is not '
        'drawn in default colours. The final theme here is '
        'selected by Omarchy through lua/plugins/theme.lua, a '
        'symlink, and all of its candidates are declared in '
        'lua/plugins/all-themes.lua.'),

    ...sec('the one edit: the update checker, off'),
    ...code('lua', 'lua/config/lazy.lua · checker', r'''
  checker = {
    -- OFF: the periodic checker spawns background git fetches AND pulls
    -- lazy's whole management machinery (lazy.manage, view.commands,
    -- runner, task, process - ~6-10ms) into every startup. Update
    -- manually with :Lazy sync instead.
    enabled = false,
    notify = false,
  },'''),
    ...para('--',
        'The stock block, which the diff against the starter shows '
        'as the three lines this replaced, read:'),
    plain('    enabled = true, -- check for plugin updates periodically'),
    plain('    notify = false, -- notify on update'),
    plain('  }, -- automatically check for plugin updates'),
    blank,
    ...para('--',
        'Changed in f35b4f6 on 2026-09-03 (CHANGELOG 1.3.0, under '
        '“Zero background activity”). There are two separate costs '
        'in the comment, and lazy.nvim’s source confirms both. The '
        'checker, once enabled, runs at VeryLazy and then every '
        'hour by default (frequency 3600 seconds): it fetches every '
        'plugin repository in the background to see whether an '
        'update exists. And enabling it makes lazy load its '
        'management modules, lazy.manage, the view commands, the '
        'runner, tasks and process handling, in every session. '
        'The comment puts the latter at roughly 6 to 10 ms. That '
        'range is the author’s figure; the repository does not say '
        'how it was measured, and it sits inside the larger '
        'measured result of 28.7 ms down to about 18 ms for the '
        'whole commit.'),
    ...para('--',
        'Two details make the decision clean. First, lazy.nvim '
        'itself ships with the checker off. The starter turned it '
        'on, and this edit returns to the library’s own default, so '
        'the line is a correction of the template and not an '
        'exotic tweak. Second, turning it off changes the update '
        'workflow into something deliberate: nothing changes on '
        'disk until :Lazy sync runs (which cleans, installs and '
        'updates, then rewrites lazy-lock.json). Every plugin '
        'update is therefore a visible diff in the repository. '
        'That ties this file to lazy-lock.json.'),

    ...sec('runtime plugins removed'),
    ...code('lua', 'lua/config/lazy.lua · rtp', r'''
  performance = {
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
  },'''),
    ...para('--',
        'Neovim ships Vim runtime plugins that most people never '
        'use: editing inside gzip, tar and zip archives, the '
        ':TOhtml converter and :Tutor. Listing them makes lazy '
        'prevent them from being sourced. Three more candidates '
        'are left commented out by the starter, and they are '
        'worth a note because they stay on here: matchit and '
        'matchparen (bracket matching) and netrwPlugin, the '
        'built-in file explorer. The very first version of this '
        'repository leaned on netrw (the <leader>pv mapping and '
        'three netrw_ globals); today the explorer is neo-tree, '
        'but netrw stays loaded because the starter’s line '
        'stayed commented. No measurement of the saving is '
        'recorded.'),

    ...sec('what the file does not set, and who depends on it'),
    ...para('--',
        'There is no change_detection key, so lazy.nvim uses its '
        'default, which is enabled with notifications on. The '
        'very first lazy.lua of this repository was explicit '
        'about it: it passed change_detection = { notify = false }. '
        'The starter dropped that, and nothing here brings it '
        'back.'),
    ...para('--',
        'That default is load-bearing. In lazy.nvim’s source the '
        'reloader starts at VeryLazy when change detection is '
        'enabled and polls every two seconds, comparing the size '
        'and modification time of every file in the imported '
        'module directories, symlinks included. When anything '
        'differs it reloads the specs and fires a User event '
        'named LazyReload. lua/plugins/omarchy-theme-hotreload.lua '
        'listens for exactly that event, and lua/plugins/theme.lua '
        'is a symlink into Omarchy’s state directory. So the live '
        'theme switch works because lazy.nvim notices that a '
        'theme file changed. Disabling change detection here, '
        'a natural thing to do in a startup-trimming pass, would '
        'silently break theme hot reload.'),
    ...para('--',
        'The same code also prints a warning, “Config Change '
        'Detected. Reloading...”, when notify is true. By the '
        'source that would appear on every theme switch; whether '
        'it is visible in practice, or hidden by the way the '
        'notification is routed, is not recorded anywhere in the '
        'repository.'),

    ...sec('what changed over time'),
    ...pt('--', '2026-08-17, 1c496fd',
        '17 lines, tab indented, importing config.plugins and '
        'setting change_detection notify to false. No error '
        'handling on the clone.'),
    ...pt('--', '2026-09-02, eabb22a',
        'replaced wholesale by the LazyVim starter file '
        '(47 lines added, 11 removed) with the checker enabled and silent '
        '(notify false). The file mode also changed to 100755.'),
    ...pt('--', '2026-09-03, f35b4f6',
        'the checker switched off, with the comment above. '
        'Nothing has touched the file since.'),

    ...sec('limits'),
    ...pt('--', 'no pinned bootstrap',
        'the clone takes the stable branch at whatever commit it '
        'is on that day. The lockfile pins lazy.nvim as a plugin '
        'afterwards (it lists lazy.nvim), but the very first '
        'checkout on a new machine is not reproducible.'),
    ...pt('--', 'estimates, not receipts',
        'the 6 to 10 ms is a comment, not a benchmark in the '
        'repo; the 28.7 to 18 ms total is the measured number to '
        'trust.'),
    ...pt('--', 'an easy regression',
        'change_detection is the kind of setting that looks '
        'removable. A test that switches themes and asserts the '
        'colorscheme changed would protect it, and none exists.'),

    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
