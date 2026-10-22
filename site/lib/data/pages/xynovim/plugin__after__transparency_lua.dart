import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/plugin/after/transparency.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'transparency.lua — let the terminal show through, keep popups solid'),
    cm('--', 'a list of highlight groups, one function, one autocmd, one toggle'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'removes the background colour from the editor-surface highlight groups'),
    kv('language', 'Lua; tab-indented; sourced from plugin/after at startup'),
    kv('size', '88 lines'),
    kv('history', '5 commits: eabb22a (2026-09-02), f35b4f6, cf842d0, 4d45a21, e874f9f (2026-10-13)'),
    kv('groups', '31 names: 8 core, 5 neo-tree, 3 nvim-tree, 15 notify'),
    kv('tested by', 'tests/theme-island_spec.lua, describe “transparency”'),

    ...sec('why this file exists'),
    ...para('--',
        r'The editor is meant to sit on the terminal’s own background. A '
        r'colorscheme paints a background on Normal, the sign column, the '
        r'line numbers and so on, so a transparent look needs those '
        r'backgrounds removed after the scheme is loaded. This file does '
        r'exactly that and nothing else: for each group on a list it keeps '
        r'every attribute (colours, bold, italic) and sets bg to nil.'),
    ...para('--',
        r'It lives in plugin/after, which Neovim sources after the plugins '
        r'have been loaded, so the groups it touches already exist. The '
        r'name “after” is the whole reason for the directory; there is no '
        r'plugin spec for this file.'),

    ...sec('the function'),
    ...code('lua', 'plugin/after/transparency.lua · lines 1-11', r'''
-- Make highlight groups transparent while preserving their other attributes.
-- Applied immediately AND on every ColorScheme change, so a manual
-- `:colorscheme` mid-session keeps transparency too (re-sourcing this file is
-- safe: the augroup clears its old autocmd).
local function make_transparent(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	if ok and hl.bg ~= nil then
		hl.bg = nil
		vim.api.nvim_set_hl(0, name, hl)
	end
end'''),
    ...pt('--', 'nvim_get_hl with link = false',
        r'asks for the resolved attributes of the group, following links. '
        r'A group that is only a link to Normal would otherwise return a '
        r'table with just the link and nothing to edit.'),
    ...pt('--', 'pcall',
        r'the lookup is wrapped so that a failure for one name cannot stop the loop over the rest; the file does not say which failure it expects.'),
    ...pt('--', 'hl.bg ~= nil',
        r'only groups that actually paint a background are rewritten, so '
        r'the function does not create groups that were absent.'),
    ...pt('--', 'nvim_set_hl(0, name, hl)',
        r'writes the table back without the bg key, which keeps fg, bold '
        r'and the rest. This is what “preserving their other attributes” '
        r'in the first comment line means.'),

    ...sec('what is deliberately not on the list'),
    ...code('lua', 'plugin/after/transparency.lua · lines 13-17', r'''
-- Floats and the completion menu (NormalFloat, FloatBorder, Pmenu, Telescope,
-- which-key) are deliberately NOT here: they keep the theme's solid popup
-- background so they stay readable over code. CursorLineNr keeps its bg so the
-- cursor-row band has no gap in the gutter. Only the editor surface is made
-- transparent.'''),
    ...para('--',
        r'4d45a21 (2026-10-12, “Theme polish: solid floats, contrast lifts, '
        r'visible cursorline”) moved the file from “make everything '
        r'transparent” to “make the editor surface transparent”. The '
        r'diff removed NormalFloat, FloatBorder, Pmenu, CursorLineNr, '
        r'WhichKeyFloat and the Telescope groups from the list and added '
        r'the comment above. The reason is readability: a float over '
        r'code with no background of its own shows the code through the '
        r'text. CursorLineNr keeps its background so the cursor-row band '
        r'has no gap in the gutter.'),
    ...para('--',
        r'The spec asserts this as data. “keeps the solid popup and '
        r'cursor-row backgrounds” checks that NormalFloat, FloatBorder and '
        r'Pmenu have #2b2d30 and CursorLineNr has #242d42, the colours of the '
        r'island scheme (lua/island/palette.lua).'),

    ...sec('the list'),
    ...code('lua', 'plugin/after/transparency.lua · lines 18-33', r'''
local groups = {
	-- transparent background
	"Normal",
	"Terminal",
	"EndOfBuffer",
	"FoldColumn",
	"Folded",
	"SignColumn",
	"LineNr",
	"NormalNC",
	-- neotree
	"NeoTreeNormal",
	"NeoTreeNormalNC",
	"NeoTreeVertSplit",
	"NeoTreeWinSeparator",
	"NeoTreeEndOfBuffer",
	...
'''),
    ...para('--',
        r'Eight core groups (Normal, NormalNC, Terminal, EndOfBuffer, '
        r'the fold and sign columns, LineNr), then groups for the file '
        r'explorers and for nvim-notify. The explorer in use is neo-tree '
        r'(see lazyvim.json); the nvim-tree block is there for a plugin '
        r'this config does not install, and costs nothing because absent '
        r'groups are skipped. The fifteen Notify groups are the five '
        r'levels times body, title and border, so a notification does not '
        r'draw a box on a transparent screen.'),
    ...para('--',
        r'tests/theme-island_spec.lua repeats the same 31 names as its own '
        r'list and asserts that after the scheme loads none of them has a '
        r'background.'),

    ...sec('apply, and the autocmd that makes it durable'),
    ...code('lua', 'plugin/after/transparency.lua · lines 56-72', r'''
local function apply()
	-- vim.g.xynovim_transparent = false keeps the theme's solid backgrounds
	-- (toggle: <leader>uO)
	if vim.g.xynovim_transparent == false then
		return
	end
	for _, name in ipairs(groups) do
		make_transparent(name)
	end
end

vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("user_transparency", { clear = true }),
	callback = apply,
})

apply()'''),
    ...para('--',
        r'A colorscheme reset clears and re-sets highlight groups, so a '
        r'single call at startup would be undone by the next '
        r':colorscheme. The ColorScheme autocmd re-applies the list every '
        r'time. The augroup is created with clear = true, so sourcing the '
        r'file again replaces the autocmd and never stacks a second one; '
        r'the spec asserts that exactly one ColorScheme autocmd exists in '
        r'the group user_transparency. The first line of the file says the '
        r'same: re-sourcing is safe.'),
    ...pt('--', 'the opt-out',
        r'vim.g.xynovim_transparent = false makes apply() return at once, '
        r'so the theme keeps its solid backgrounds. It is checked inside '
        r'apply, not at load time, so changing it later and re-running the '
        r'colorscheme takes effect. The spec checks that Normal and '
        r'SignColumn get the scheme’s #1e1f22 and stay solid even after a '
        r'ColorScheme event.'),

    ...sec('the toggle'),
    ...code('lua', 'plugin/after/transparency.lua · lines 74-88', r'''
-- Toggle: off re-runs the colorscheme to bring the solid backgrounds back.
if _G.Snacks and Snacks.toggle then
	Snacks.toggle({
		name = "Transparent background",
		get = function()
			return vim.g.xynovim_transparent ~= false
		end,
		set = function(state)
			vim.g.xynovim_transparent = state
			if vim.g.colors_name then
				pcall(vim.cmd.colorscheme, vim.g.colors_name)
			end
		end,
	}):map("<leader>uO")
end'''),
    ...para('--',
        r'cf842d0 (2026-10-12, “Theme: Island Dark from RustRover scheme, '
        r'permanent”) added the opt-out variable and this Snacks toggle on '
        r'<leader>uO. get reads the variable, set writes it and then '
        r're-runs the current colorscheme, which is how turning '
        r'transparency off brings the solid backgrounds back: the '
        r'ColorScheme event fires, apply sees false and does nothing, and '
        r'the scheme’s own bg values stand. Turning it on again triggers '
        r'the same event and the groups are stripped. The if guard '
        r'checks that Snacks exists, since this file runs before every '
        r'plugin is ready; pcall around the colorscheme command prevents a '
        r'failing scheme from breaking the toggle.'),

    ...sec('history'),
    ...pt('--', 'eabb22a, 2026-09-02',
        r'first version, a script that ran once at startup.'),
    ...pt('--', 'f35b4f6, 2026-09-03',
        r'made event-driven: the ColorScheme autocmd and the clear = true '
        r'group were added in this commit, with the other startup work.'),
    ...pt('--', 'cf842d0, 2026-10-12',
        r'the permanent island theme: the opt-out variable and the toggle.'),
    ...pt('--', '4d45a21, 2026-10-12',
        r'floats, popup menu and cursor-line number leave the list.'),
    ...pt('--', 'e874f9f, 2026-10-13',
        r'Omarchy support removed (the file used to be re-sourced by a '
        r'theme hot-reload plugin that was deleted in the same commit); '
        r'only four lines changed in this file.'),

    ...sec('limits'),
    ...pt('--', 'a plugin that sets its own background later',
        r'the autocmd runs on ColorScheme, so a plugin that paints a '
        r'group on some other event would not be corrected.'),
    ...pt('--', 'only the listed groups',
        r'a new plugin with its own background groups needs a name added '
        r'to the list; nothing discovers them.'),
    ...pt('--', 'terminal dependent',
        r'transparency only looks right when the terminal itself supplies '
        r'a background; the island palette’s solid #1e1f22 is what shows '
        r'in the toggle-off state.'),

    blank,
    link('→ github.com/xynorash/xynovim', 'https://github.com/xynorash/xynovim'),
  ],
);
