import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/stylua.toml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'stylua.toml — the formatter contract for every Lua file'),
    cm('#', 'three lines, and only two of them change anything'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'settings for StyLua, the Lua formatter'),
    kv('language', 'TOML'),
    kv('size', '3 lines, no trailing newline'),
    kv('origin', 'LazyVim/starter, unchanged'),
    kv('added', '2026-09-02 in the migration commit eabb22a'),

    ...sec('what it is'),
    ...para('#',
        'StyLua is an opinionated Lua formatter. It has no '
        'configuration of its own beyond a stylua.toml (or '
        '.stylua.toml) file, and this is that file. It was added '
        'in the migration commit eabb22a together with the rest of '
        'the LazyVim starter layout and has never been edited.'),
    ...code('toml', 'stylua.toml · the whole file', r'''
indent_type = "Spaces"
indent_width = 2
column_width = 120'''),

    ...sec('what each line really does'),
    ...para('#',
        'StyLua’s README lists its defaults: indent_type = "Tabs", '
        'indent_width = 4, column_width = 120. Compared with that '
        'table, this file changes two things and restates a third.'),
    ...pt('#', 'indent_type = "Spaces"',
        'overrides the default of tabs. This is the line that '
        'decides what a diff of any Lua file in this repository '
        'looks like.'),
    ...pt('#', 'indent_width = 2',
        'overrides the default of 4. With spaces, this is a real '
        'width. With tabs StyLua would treat it only as a '
        'heuristic for measuring line length.'),
    ...pt('#', 'column_width = 120',
        'is the default value written out. StyLua describes it as '
        'an approximate guide for wrapping, not a hard limit, so '
        'lines can land over it.'),
    ...para('#',
        'Everything not listed keeps the StyLua default, which is '
        'why the code in this repository always writes '
        'require("config.lazy") with parentheses and double quotes: '
        'call_parentheses defaults to Always and quote_style to '
        'AutoPreferDouble.'),

    ...sec('who reads it'),
    ...para('#',
        'Nothing in Neovim reads stylua.toml directly. The path is: '
        'LazyVim registers conform.nvim as its formatter and maps '
        'lua to stylua; conform’s stylua definition (at the commit '
        'in lazy-lock.json) runs the binary with '
        '--search-parent-directories and sets its working '
        'directory to the nearest folder containing .stylua.toml '
        'or stylua.toml. For a file anywhere in this config that '
        'folder is the repository root, so these three lines '
        'apply.'),
    ...para('#',
        'There is one more link, and it is switched off on '
        'purpose. lua/config/options.lua sets vim.g.autoformat to '
        'false, and LazyVim’s format function returns immediately '
        'unless autoformat is enabled or the caller passes force. '
        'So saving never invokes StyLua here. Formatting happens '
        'on request: the <leader>cf mapping in LazyVim forces it. '
        'One effect is that auto-save, which writes buffers about '
        'a second after typing stops, cannot reformat a file under '
        'the cursor.'),

    ...sec('how well the repository follows it'),
    ...para('#',
        'Counted on the tracked files, not assumed: of the 16 Lua '
        'files tracked in the repository (theme.lua is a symlink '
        'and is not counted), 11 contain no tab character, as the '
        'file demands. The other 5 are indented with tabs: '
        'lua/plugins/all-themes.lua, '
        'lua/plugins/disable-news-alert.lua, '
        'lua/plugins/omarchy-theme-hotreload.lua, '
        'lua/plugins/snacks-animated-scrolling-off.lua and '
        'plugin/after/transparency.lua.'),
    ...para('#',
        'Tabs are StyLua’s default indent. All five arrived in the '
        'migration commit eabb22a; CHANGELOG 1.0.0 lists three of '
        'them (omarchy-theme-hotreload, all-themes, transparency) '
        'under “Omarchy desktop integration” and the other two as '
        'small LazyVim tweaks. A plausible reading, which the repository '
        'does not state, is that they arrived formatted for the '
        'defaults. Later edits kept the tabs: the diff of f35b4f6 '
        'on transparency.lua and the hot-reload spec is tab '
        'indented line for line. Running StyLua over them would '
        'produce a large whitespace-only diff, which is a reason '
        'to leave them alone.'),
    ...para('#',
        'Line width is respected by the space-indented files: the '
        'widest, in lazy.lua, is exactly 120 columns and none of '
        'the eleven is wider.'),

    ...sec('limits'),
    ...pt('#', 'no CI check',
        'nothing runs stylua --check, so conformance is by habit. '
        'The five tab files show what that costs.'),
    ...pt('#', 'no trailing newline',
        'git records “No newline at end of file” for this file '
        'in the commit that added it. StyLua does not care, but '
        'it is why a naive line count says 2.'),
    ...pt('#', 'the binary is not pinned here',
        'the repository neither installs nor pins the stylua '
        'binary (the lockfile pins plugins, not executables), so '
        'the same three lines can format slightly differently '
        'across StyLua versions.'),

    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
