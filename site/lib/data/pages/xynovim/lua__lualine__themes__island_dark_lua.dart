import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/lualine/themes/island-dark.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'lua/lualine/themes/island-dark.lua — the status line, same palette'),
    cm('--', r'35 lines: six modes, one inactive state, one escape hatch'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'lualine theme named island-dark'),
    kv(r'language', r'Lua; returns a theme table, or the auto theme'),
    kv(r'size', r'35 lines, 2 commits (2026-10-12)'),
    kv(r'colours', r'all from lua/island/palette.lua, none typed here'),
    kv(r'selected by', r'lua/plugins/island-theme.lua (options.theme)'),
    kv(r'tested by', r'tests/theme-island_spec.lua, lualine theme island-dark'),
    ...sec(r'why this file exists'),
    ...para('--', r'lualine looks for a theme by name in lua/lualine/themes/, which is a directory of the Neovim runtime path. Because the configuration directory is on that path, dropping a file called island-dark.lua there is all it takes to make "island-dark" a valid value for options.theme. No plugin is involved. The same idea is behind colors/island-dark.lua for the colourscheme itself.'),
    ...para('--', r'The file is short because everything about colour was decided elsewhere. Its header says so: every colour is from island/palette.lua.'),
    ...code('lua', r'lua/lualine/themes/island-dark.lua · lines 1-15', r'''
-- lualine theme for island-dark; every colour is from island/palette.lua.
local P = require("island.palette")
local A, C = P.attrs, P.colors

local bg, fg = A.TEXT.bg, A.TEXT.fg
local bar = C.DIFF_SEPARATORS_BACKGROUND
local mid = C.RIGHT_MARGIN_COLOR
local muted = A.BREADCRUMBS_DEFAULT.fg -- inactive text: the "disabled" grey #6f737a is 2.9:1 on the bar
local function mode(color)
  return {
    a = { fg = bg, bg = color, gui = "bold" },
    b = { fg = fg, bg = mid },
    c = { fg = A.BREADCRUMBS_DEFAULT.fg, bg = bar },
  }
end'''),
    ...sec(r'the three-section model'),
    ...para('--', r'lualine divides the bar into sections a, b and c on the left (and x, y and z on the right, which reuse the same three styles). A theme is, for each mode, a style per section. The local function mode(color) builds that for one accent colour, and it is the whole idea of the theme:'),
    blank,
    ...pt('--', r'a', r'the mode indicator. Dark background colour (the editor bg) as the text colour on a block of the mode’s accent, in bold. This is the loud part of the bar.'),
    ...pt('--', r'b', r'the secondary block. Normal text on the scheme’s right margin grey (#393b40), a step lighter than the bar.'),
    ...pt('--', r'c', r'the middle of the bar. A lighter grey text (BREADCRUMBS_DEFAULT, #9da0a8) on the bar colour DIFF_SEPARATORS_BACKGROUND (#2b2d30), the same colour as StatusLine in init.lua. Everything in the middle recedes.'),
    blank,
    ...para('--', r'The consequence is a bar with three tones of grey and one coloured block that changes with the mode. The bar background is the same colour as the floating windows, so the status line, popups and the tab line feel like one surface.'),
    ...sec(r'a fix recorded in a comment'),
    ...para('--', r'The inactive state shows the kind of trouble legibility checks find. The first version used the palette’s WHITESPACES grey, #6f737a, for inactive text. The second commit (4d45a21, "Theme polish") changed it to BREADCRUMBS_DEFAULT and left the reason in the comment on the muted line: the "disabled" grey is 2.9:1 on the bar, too dim for text. It is a one line change, but it shows the method: measure, then pick the nearest scheme colour that passes rather than invent one.'),
    ...sec(r'the mode table'),
    ...code('lua', r'lua/lualine/themes/island-dark.lua · lines 23-35', r'''
return {
  normal = mode(A.DEFAULT_FUNCTION_DECLARATION.fg),
  insert = mode(A.DEFAULT_STRING.fg),
  visual = mode(A.DEFAULT_CONSTANT.fg),
  replace = mode(A.CONSOLE_ERROR_OUTPUT.fg),
  command = mode(A.LOG_INFO_OUTPUT.fg),
  terminal = mode(A.DEFAULT_NUMBER.fg),
  inactive = {
    a = { fg = muted, bg = bar },
    b = { fg = muted, bg = bar },
    c = { fg = muted, bg = bar },
  },
}'''),
    ...para('--', r'Each mode takes its accent from the syntax colours, as the accents do in init.lua: normal is the function blue, insert the string green, visual the constant purple, replace the error red, command the log yellow, terminal the number teal. Since the colours are the code’s own, the status line reads as part of the same picture. An inactive window flattens everything to the bar colour with muted text.'),
    ...sec(r'following the active colourscheme'),
    ...code('lua', r'lua/lualine/themes/island-dark.lua · lines 17-21', r'''
-- after `:colorscheme <other>` lualine re-requires this theme: follow the new
-- colourscheme instead of keeping the island colours
if vim.g.colors_name and vim.g.colors_name ~= "island-dark" then
  return require("lualine.themes.auto")
end'''),
    ...para('--', r'This guard is the most interesting four lines. lualine is configured with options.theme = "island-dark", a fixed name, and when you later run :colorscheme tokyonight, lualine re-requires its theme module so it can refresh. Without a guard the module would return the island table again, and the bar would stay in island colours on a tokyonight screen. So the file checks vim.g.colors_name, the global every colourscheme sets, and if some other scheme is active it returns lualine’s own "auto" theme, which derives the bar from the active highlight groups.'),
    ...para('--', r'There is a nuance of the evaluation order. The guard runs after the locals are built (the palette is required and the helper is defined) but before the table is returned, so in the normal case, with island-dark active, it costs one global read and a string comparison. The nil check matters at startup: lualine may load before any colourscheme has set colors_name, in which case the condition is false and the island theme is used. The spec has a test for the switch, named "follows the active colourscheme after :colorscheme habamax (returns the auto theme)".'),
    ...sec(r'edge cases'),
    ...pt('--', r'the plugin spec', r'lua/plugins/island-theme.lua sets options.theme = "island-dark" for lualine. lua/plugins/lualine.lua separately adds the Rust server status component. They merge because LazyVim opts functions compose.'),
    ...pt('--', r'colours the table does not set', r'no mode-specific colour is given for the b and c sections; they are identical for every mode. That is deliberate in mode(): only the a block changes.'),
    ...sec(r'tests'),
    ...para('--', r'In tests/theme-island_spec.lua the describe block "lualine theme island-dark" has two tests. One checks that every mode is defined with the three sections and that the accent colours are the scheme’s mode colours. The other runs :colorscheme habamax and checks that the theme module now returns the auto theme.'),
    ...sec(r'history'),
    ...pt('--', r'cf842d0 (2026-10-12)', r'"Theme: Island Dark from RustRover scheme, permanent". The original 29 line theme: the mode helper, six accents and an inactive state using the WHITESPACES grey.'),
    ...pt('--', r'4d45a21 (2026-10-12)', r'"Theme polish: solid floats, contrast lifts, visible cursorline". Adds the 2.9:1 inactive text fix and the colours_name guard, six more lines in total.'),
  ],
);
