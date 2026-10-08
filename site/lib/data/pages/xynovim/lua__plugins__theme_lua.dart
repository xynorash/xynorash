import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/theme.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'theme.lua — a symlink that carries the desktop theme in'),
    cm('--', 'the one file in lua/plugins/ that contains no Lua at all'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'points the editor at Omarchy’s current Neovim theme file'),
    kv('kind', 'a symbolic link (git mode 120000), tracked in the repo'),
    kv('target', '../../../../.local/state/omarchy/current/theme/neovim.lua'),
    kv('size', 'one line of stored content: the 57-character path above'),
    kv('history', '1 commit, eabb22a (2026-09-02); never changed'),
    ...sec('what kind of file this is'),
    ...para('--',
        r'Git stores a symbolic link as a small blob whose entire '
        r'content is the path it points to, and marks it with file '
        r'mode 120000 instead of 100644. Every other file in '
        r'lua/plugins/ is Lua source. This one is a pointer. Running '
        r'git show eabb22a:lua/plugins/theme.lua prints one line:'),
    blank,
    plain('  ../../../../.local/state/omarchy/current/theme/neovim.lua'),
    blank,
    ...para('--',
        r'There is therefore no source to excerpt and no function to '
        r'walk through. The interesting content of this page is the '
        r'contract the link sets up: what it points at, who reads '
        r'it, and what the reader expects to find.'),

    ...sec('where the link points'),
    ...para('--',
        r'A relative symlink is resolved from the directory that '
        r'contains it. Start at lua/plugins/ and apply the four '
        r'parent steps in the stored path:'),
    blank,
    cm('--', '  lua/plugins/        where the link lives'),
    cm('--', '  ..       -> lua/'),
    cm('--', '  ../..    -> the Neovim config root'),
    cm('--', '  ../../.. -> the directory above the config root'),
    cm('--', '  ../../../.. -> the home directory'),
    cm('--', '  then .local/state/omarchy/current/theme/neovim.lua'),
    blank,
    ...para('--',
        r'That arithmetic only lands on the home directory if the '
        r'config root is exactly two levels below it, which is what '
        r'the conventional location ~/.config/nvim gives. The rest of '
        r'the repo agrees that this is the layout: the hot-reload '
        r'spec builds its paths from vim.fn.stdpath("config"), and '
        r'Neovim looks for its configuration at that location. So, on '
        r'the author’s machine, the link resolves to '
        r'~/.local/state/omarchy/current/theme/neovim.lua. The word '
        r'current in that path suggests it is where Omarchy keeps '
        r'whichever theme is active now, though the repo does not say '
        r'so.'),

    ...sec('who reads it'),
    ...para('--',
        r'Two readers, one at startup and one on every theme change.'),
    ...pt('--', 'lazy.nvim at startup',
        r'lua/config/lazy.lua imports the whole plugins directory. '
        r'Every Lua file in it, this link included, is loaded as a '
        r'file of plugin specs.'),
    ...code('lua', 'lua/config/lazy.lua · the import', r'''
    -- import/override with your plugins
    { import = "plugins" },'''),
    ...pt('--', 'the hot-reload spec on each change',
        r'omarchy-theme-hotreload.lua clears package.loaded for the '
        r'module plugins.theme (which is this file) and requires it '
        r'again. Because the file is a link, the second require '
        r'reads whatever Omarchy now has at the other end.'),
    ...code('lua', 'lua/plugins/omarchy-theme-hotreload.lua · re-reading this file', r'''
          -- Unload the theme module
          package.loaded["plugins.theme"] = nil

          vim.schedule(function()
            local ok, theme_spec = pcall(require, "plugins.theme")'''),
    ...para('--',
        r'This is the entire reason it is a link and not a copy. '
        r'Nothing in the repo needs to know which theme is active. '
        r'Omarchy changes the file at the far end; the editor sees '
        r'the change on the next read; no script has to regenerate '
        r'anything inside the repo, and no theme state is ever '
        r'committed to it. The repo versions the pointer, and the '
        r'desktop owns the data.'),

    ...sec('what the other end has to contain'),
    ...para('--',
        r'The file at the end of the link is not in this repo, so I '
        r'cannot show it. But its shape can be read off the code that '
        r'consumes it, and off the comments in all-themes.lua. The '
        r'consumer treats the value it gets back as a list of '
        r'lazy.nvim specs and looks for two things.'),
    ...code('lua', 'lua/plugins/omarchy-theme-hotreload.lua · what the consumer looks for (trimmed)', r'''
          for _, spec in ipairs(theme_spec) do
            if spec[1] and spec[1] ~= "LazyVim/LazyVim" then
              theme_plugin_name = spec.name or spec[1]
              break
            end
          end
          ...
            if spec[1] == "LazyVim/LazyVim" and spec.opts and spec.opts.colorscheme then
              local colorscheme = spec.opts.colorscheme'''),
    ...pt('--', 'a theme plugin spec',
        r'the first entry whose first element is a plugin name other '
        r'than LazyVim/LazyVim. The spec’s name field, if it has '
        r'one, is the name the reload logic uses to find the plugin '
        r'in lazy.nvim’s registry.'),
    ...pt('--', 'a LazyVim spec with opts.colorscheme',
        r'the name of the colorscheme to apply. This is the standard '
        r'LazyVim way to set the active scheme, which is why a '
        r'generated file can simply declare it.'),
    blank,
    ...para('--',
        r'The origin of that file depends on the Omarchy version, per '
        r'the header comment of all-themes.lua. Omarchy 4 generates '
        r'most theme specs from a template named '
        r'default/themed/neovim.lua.tpl on top of the aether plugin, '
        r'and Omarchy 3.8 ships a neovim.lua per theme. Either way, '
        r'what lands at the end of this link is a spec file, and '
        r'all-themes.lua makes sure the plugins it refers to are '
        r'already installed.'),

    ...sec('what the link looks like where Omarchy is absent'),
    ...para('--',
        r'A relative link whose target does not exist is dangling. '
        r'When I inspected a clone of this repo to write these pages, '
        r'that was exactly the state it was in: the link is present '
        r'in the working tree and attempts to read it fail with “no '
        r'such file”, because the clone has no Omarchy state '
        r'directory. That is expected for any checkout outside the '
        r'author’s machine, and tools that walk the tree and read '
        r'every file (a line counter, a linter) will stumble on it.'),
    blank,
    ...para('--',
        r'What lazy.nvim does with a dangling file in an imported '
        r'directory I did not test, and the repo does not say. The '
        r'one thing the evidence does support is that the author’s '
        r'own machine always has the target, so the question never '
        r'arises there. If this config were ever to be bootstrapped '
        r'on a machine without Omarchy, this is the file to check '
        r'first.'),

    ...sec('history'),
    ...para('--',
        r'The link was created in eabb22a, the Linux migration of '
        r'2026-09-02, and has not changed since: it is the only '
        r'commit that touches it. The CHANGELOG entry for 1.0.0 '
        r'lists the neighbouring pieces of the theme machinery '
        r'(omarchy-theme-hotreload.lua, all-themes.lua, '
        r'plugin/after/transparency.lua) under “Omarchy desktop '
        r'integration” but does not mention theme.lua by name, so '
        r'this page rests on the code that reads it and on the '
        r'comments next to it, not on a stated rationale.'),

    ...sec('limits'),
    ...pt('--', 'it encodes a layout',
        r'the stored path assumes the config lives at ~/.config/nvim '
        r'and that Omarchy keeps its state under '
        r'~/.local/state/omarchy/current/theme. A change to either '
        r'breaks the link without any error in the repo.'),
    ...pt('--', 'its contents are unversioned',
        r'what the theme file says is decided by Omarchy at the time '
        r'you run the editor; the repo cannot reproduce a past '
        r'session’s theme.'),
    ...pt('--', 'there is nothing to test',
        r'no assertion in the repository covers the shape the '
        r'consumer expects. By my reading of the hot-reload code, a '
        r'theme file that omitted opts.colorscheme would leave the '
        r'editor with its highlights cleared and no colorscheme '
        r'applied.'),
    blank,
    ...para('--',
        r'The reusable idea is small: when one program owns a piece '
        r'of state and another needs to read it, reference it, do not '
        r'copy it. A one-line symlink replaces a sync script, a '
        r'generated file and a way for them to disagree.'),
    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
