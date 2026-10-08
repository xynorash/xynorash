import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/.neoconf.json',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', '.neoconf.json — settings for a plugin this config no longer loads'),
    cm('//', 'a stock starter file, and a lesson in proving a file is dead'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'project-local settings read by neoconf.nvim'),
    kv('language', 'JSON'),
    kv('size', '15 lines'),
    kv('origin', 'LazyVim/starter, unchanged'),
    kv('effect here', 'none: nothing in this config reads it'),

    ...sec('what it is'),
    ...para('//',
        'neoconf.nvim is a plugin for keeping editor and language '
        'server settings in JSON files: a global one, and a '
        'project-local .neoconf.json like this one. The file '
        'arrived in the migration commit eabb22a on 2026-09-02, '
        'copied with the rest of the LazyVim starter, and has not '
        'been edited since. It is byte-identical to the file in '
        'the last commit of github.com/LazyVim/starter.'),
    ...code('json', '.neoconf.json · the whole file', r'''
{
  "neodev": {
    "library": {
      "enabled": true,
      "plugins": true
    }
  },
  "neoconf": {
    "plugins": {
      "lua_ls": {
        "enabled": true
      }
    }
  }
}'''),
    ...para('//',
        'Two blocks. The “neodev” block asks neodev.nvim, a helper '
        'that teaches the Lua language server about the Neovim API '
        'and installed plugins, to enable its library and include '
        'plugin sources. The “neoconf” block turns on neoconf’s own '
        'integration with lua_ls. Both exist so that editing '
        'Neovim configuration in Lua gets completion and type '
        'checking.'),

    ...sec('why it does nothing here'),
    ...para('//',
        'The interesting part is that neither plugin is part of '
        'this setup any more. Here is how that was checked, so the '
        'claim is reproducible and not a hunch.'),
    ...pt('//', 'the lockfile',
        'lazy-lock.json pins 58 plugins and neither neoconf.nvim '
        'nor neodev.nvim is among them. It does contain '
        'lazydev.nvim. lazy.nvim writes an entry for every '
        'installed plugin, so a plugin that is absent was never '
        'installed.'),
    ...pt('//', 'LazyVim itself',
        'in the LazyVim checkout pinned by the lockfile (release '
        '16.0.0), the only file under lua/ that mentions '
        'neoconf.nvim is the optional extra '
        'lua/lazyvim/plugins/extras/lsp/neoconf.lua. '
        'The extras enabled in lazyvim.json are editor.neo-tree '
        'and lang.rust, so that one is not imported.'),
    ...pt('//', 'what replaced it',
        'LazyVim’s changelog for 12.3.0 (2024-06-02) lists two '
        'entries: “use lazydev.nvim instead of neodev.nvim” and '
        '“moved neoconf.nvim to extras”. The Lua workspace '
        'library is now configured by the lazydev spec in '
        'lua/lazyvim/plugins/coding.lua.'),
    ...para('//',
        'The starter’s copy of this file was last touched on '
        '2023-02-27 (a rename from sumneko to lua_ls), more than '
        'a year before LazyVim moved neoconf out of its core. So '
        'the template still ships a configuration file for a '
        'plugin the template no longer installs. Copying the '
        'template, as this repository did, copies that too.'),

    ...sec('what would make it live'),
    ...para('//',
        'Run :LazyExtras and enable lsp.neoconf. That adds the '
        'extra’s spec (neoconf.nvim as a dependency of '
        'nvim-lspconfig, loaded on the :Neoconf command), '
        'lazyvim.json gains the extra’s module name, and the '
        'lockfile gains an entry on the next sync. Until then, '
        'deleting the file would change nothing about how the '
        'editor behaves. The repository keeps it, and its history '
        'does not say why. One practical effect of leaving stock '
        'files alone is that the repository stays byte-comparable '
        'to the starter, and that comparison is how the files '
        'that carry real decisions can be told apart from the '
        'ones that do not.'),

    ...sec('a repeatable test for dead config'),
    ...para('//',
        'The method generalises to any settings file in a '
        'framework-based config:'),
    ...pt('//', '1. find the consumer',
        'which plugin documents this file name?'),
    ...pt('//', '2. look for it in the lockfile',
        'a plugin that is not pinned is not installed.'),
    ...pt('//', '3. look for it in the framework',
        'grep the pinned framework checkout for the plugin name. '
        'If it only appears in an optional extra, check '
        'whether the extra is enabled.'),
    ...pt('//', '4. look at the changelog',
        'a framework that moved the plugin tells you when and why.'),

    ...sec('limits'),
    ...pt('//', 'inference, not observation',
        'no editor was launched with and without the file. The '
        'conclusion rests on the lockfile and on reading the '
        'framework source, which together are strong but not '
        'the same as a runtime trace.'),
    ...pt('//', 'LazyVim root detection',
        'the none-ls extra lists .neoconf.json among its root '
        'markers. That extra is also not enabled here, so it '
        'does not change the conclusion.'),

    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
