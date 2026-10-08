import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/plugin/after/transparency.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'transparency.lua — backgrounds off, on every colorscheme change'),
    cm('--', 'forty highlight groups, one guarded function, one autocmd'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'removes the background colour from the highlight groups that paint one'),
    kv('language', 'Lua; tab-indented; sourced at startup and again by the theme hot-reload'),
    kv('size', '71 lines: 59 of code, 8 of comment, 4 blank'),
    kv('history', '2 commits: 2026-09-02 (59 lines) and 2026-09-03 (the fix that made it event-driven)'),
    kv('groups', '40 names: 17 core and telescope, 5 neo-tree, 3 nvim-tree, 15 notify'),
    ...sec('why this file exists'),
    ...para('--',
        r'Transparency only means something if something shows through, '
        r'and here that is the terminal’s own background (the repo does '
        r'not say how translucent it is). A colorscheme, however, '
        r'paints an opaque background on '
        r'Normal, on floating windows, on the sign column and on dozens '
        r'of other groups, and the terminal only shows '
        r'through where the editor chooses not to paint. This file '
        r'goes through a list of highlight groups and takes the '
        r'background colour off each. The README lists it as '
        r'“transparency (re-applied on every ColorScheme change)”, '
        r'next to the theme hot-reload.'),
    blank,
    ...para('--',
        r'The interesting part is not the stripping, which is five '
        r'lines. It is when the stripping happens. The first version '
        r'did it once, at startup, and the file lived with a bug that '
        r'the second version fixed by turning a one-shot script into '
        r'an event-driven one. That is the story of the rest of this '
        r'page.'),

    ...sec('the function'),
    ...code('lua', 'plugin/after/transparency.lua · make_transparent', r'''
-- Make highlight groups transparent while preserving their other attributes.
-- Applied immediately AND on every ColorScheme change, so a manual
-- `:colorscheme` mid-session keeps transparency too (the Omarchy hot-reload
-- re-sources this file, which is safe: the augroup clears its old autocmd).
local function make_transparent(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if ok and hl.bg ~= nil then
    hl.bg = nil
    vim.api.nvim_set_hl(0, name, hl)
  end
end'''),
    ...para('--',
        r'Walk through it line by line.'),
    ...pt('--', 'nvim_get_hl with link = false',
        r'asks for the group’s effective definition. Without that '
        r'option, a group that is only a link to another one comes '
        r'back as just the name of its target and has no bg to '
        r'remove. With it, a group such as a float that the scheme '
        r'links to Normal is resolved to the actual colours first, so '
        r'it can be stripped as well. The cost, which follows from '
        r'the API and is not mentioned in the repo, is that writing '
        r'the stripped definition back replaces the link with an '
        r'explicit definition.'),
    ...pt('--', 'pcall',
        r'a name that cannot be fetched produces an error value '
        r'instead of an exception, so a bad name in the list cannot '
        r'stop the rest.'),
    ...pt('--', 'hl.bg = nil, then nvim_set_hl',
        r'the edit is “preserving their other attributes” as the '
        r'header says: foreground, bold, italic and the rest are read '
        r'from the group and written back unchanged. Only the '
        r'background is dropped.'),
    ...pt('--', 'and hl.bg ~= nil',
        r'the guard, added on 2026-09-03. It only rewrites groups '
        r'that still have a background. See the next section.'),

    ...sec('the guard nobody wrote down'),
    ...para('--',
        r'The commit f35b4f6 changed two things in this function: it '
        r'changed if ok then to if ok and hl.bg ~= nil then, and it '
        r'rewrote the header comment. Neither the commit message nor '
        r'the CHANGELOG mentions the guard, so I can say what it '
        r'does but not what prompted it. What the code guarantees:'),
    ...pt('--', 'repeat calls become no-ops',
        r'after the first pass a group has no bg, so every later '
        r'call returns without calling nvim_set_hl, until a '
        r'colorscheme paints the background again. The function is '
        r'idempotent, which matters because this file now runs many '
        r'times per session.'),
    ...pt('--', 'absent groups are not created',
        r'for a name that no loaded plugin defines, I believe the fetch '
        r'returns an empty table (and the pcall covers the case where '
        r'it errors instead). Without the guard the function would '
        r'then call nvim_set_hl on that name with the empty table, '
        r'which defines the group. Defining a group nobody asked for '
        r'is a side effect to avoid; whether it actually caused '
        r'trouble here, the notes do not say.'),
    ...pt('--', 'groups that never had a background are left alone',
        r'including ones that are already transparent in the '
        r'colorscheme, so their definitions, links included, stay '
        r'exactly as the scheme wrote them.'),
    blank,
    ...para('--',
        r'I flag this as my reading of the code, not as the author’s '
        r'stated reason. It is a small example of a change whose '
        r'effect is easy to verify and whose motivation is not '
        r'recorded.'),

    ...sec('the list'),
    ...code('lua', 'plugin/after/transparency.lua · the groups (trimmed)', r'''
local groups = {
  -- transparent background
  "Normal",
  "NormalFloat",
  "FloatBorder",
  "Pmenu",
  "Terminal",
  "EndOfBuffer",
  ...
  "TelescopePromptTitle",
  -- neotree
  "NeoTreeNormal",
  "NeoTreeNormalNC",
  ...
  -- nvim-tree
  "NvimTreeNormal",
  ...
  -- notify
  "NotifyINFOBody",
  ...
}'''),
    ...para('--',
        r'The list has 40 names. The first comment covers the core UI '
        r'(Normal, NormalNC, floats, popup menu, folds, sign column, '
        r'line numbers, the end-of-buffer tildes, which-key’s float) '
        r'and the four Telescope groups. The rest are labelled by '
        r'plugin: five for neo-tree, three for nvim-tree, and fifteen '
        r'for notify, which is five severities (INFO, ERROR, WARN, '
        r'TRACE, DEBUG) times three parts (Body, Title, Border).'),
    blank,
    ...para('--',
        r'Compare the list with what is installed. lazy-lock.json '
        r'contains neo-tree.nvim (the neo-tree extra in lazyvim.json), '
        r'telescope.nvim (a dependency of 99) and which-key.nvim, so '
        r'those groups are live. It contains neither nvim-tree nor '
        r'nvim-notify, so 18 of the 40 names, the NvimTree and Notify '
        r'groups, name groups that nothing in this config defines. '
        r'They cost nothing, because of the guard above. The list '
        r'looks generic rather than tailored to this config, which '
        r'fits the tab-indentation hint that the file was imported '
        r'(an inference).'),
    blank,
    ...para('--',
        r'The reverse also holds. snacks.nvim is in the lock file (it '
        r'is the plugin that snacks-animated-scrolling-off.lua '
        r'configures), and no Snacks* group is in the list. Whether '
        r'snacks windows keep an '
        r'opaque background is something I cannot check from the '
        r'repo, and I do not claim either way. It is the obvious next '
        r'addition if one shows up.'),

    ...sec('the fix: from a script to an event'),
    ...code('lua', 'plugin/after/transparency.lua · apply and the autocmd', r'''
local function apply()
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
        r'The first version ended with a bare loop over the list. '
        r'It ran once, whenever Neovim sourced the file at startup. '
        r'That has two failure modes, and CHANGELOG 1.3.0 names the '
        r'one that hurt: “Transparency now survives manual :colorscheme '
        r'changes — re-applied on every ColorScheme event in a cleared '
        r'augroup (previously startup-only; only the Omarchy hot-reload '
        r'path re-sourced it).”'),
    ...pt('--', 'a later colorscheme repaints',
        r'run :colorscheme gruvbox and the scheme sets every '
        r'background again. A script that already ran has nothing '
        r'left to say. The only path that restored transparency was '
        r'the theme hot-reload, which sourced the file again by hand.'),
    ...pt('--', 'startup order',
        r'a one-shot only works if it runs after the colorscheme has '
        r'been applied, and this file did not control that order. '
        r'With the event hook it no longer matters: whichever order '
        r'they run in, the ColorScheme event fires after the colours '
        r'are set and the strip happens then.'),
    blank,
    ...para('--',
        r'Look at the shape of the fix. The ColorScheme event is '
        r'exactly the moment the thing being undone happens, so '
        r'attaching the repair to that event covers every path: a '
        r'manual command, the hot-reload, a plugin that switches '
        r'schemes, the startup colorscheme. The trailing apply() '
        r'covers the case where the file loads after the colorscheme '
        r'was already set.'),
    blank,
    ...para('--',
        r'The augroup is the other half. nvim_create_augroup with '
        r'clear = true empties the group each time it is created. The '
        r'hot-reload sources this file on every theme change, which '
        r'would otherwise register one more autocmd each time and run '
        r'apply an increasing number of times. With clear = true the '
        r'file is safe to source repeatedly, as the header comment '
        r'says. The same pattern is used in auto-save.lua.'),

    ...sec('how it runs alongside the hot-reload'),
    ...para('--',
        r'Two files, one effect. omarchy-theme-hotreload.lua applies '
        r'the new colorscheme, then deliberately sources this file, '
        r'and then fires ColorScheme itself. After 1.3.0 that gives '
        r'three chances to strip the same groups in one theme change: '
        r'the colorscheme command’s own event, the explicit source '
        r'(which runs apply() directly), and the hand-fired event. '
        r'Because of the guard, the second and third are no-ops. That '
        r'is the practical reason the guard matters: it is what makes '
        r'a redundant, belt-and-braces call free.'),
    blank,
    ...para('--',
        r'Why is the file in plugin/after/? The name of the directory '
        r'is a little misleading. As far as I can tell, Neovim '
        r'sources every Lua file under a plugin/ directory of the '
        r'configuration at startup, so this is simply an ordinary '
        r'startup file with an extra directory level; the real '
        r'“after” directory would be at after/plugin/ in the config. '
        r'The hot-reload file builds this exact path '
        r'(stdpath("config") .. "/plugin/after/transparency.lua"), '
        r'so the location is load-bearing for it. I have not run '
        r'Neovim against this repo to confirm the startup-order '
        r'details, and I mark it as my reading.'),

    ...sec('history'),
    cm('--', '  2026-09-02 23:42  eabb22a  59 lines. make_transparent with'),
    cm('--', '                             if ok then; the group list; a bare'),
    cm('--', '                             loop at the end. Startup only.'),
    cm('--', '  2026-09-03 19:54  f35b4f6  71 lines. guard (hl.bg ~= nil),'),
    cm('--', '                             apply(), the ColorScheme autocmd,'),
    cm('--', '                             the new header comment.'),
    blank,
    ...para('--',
        r'It is the same commit as the auto-save hook swap and the '
        r'bacon-ls tuning, and its message lists “re-apply '
        r'transparency on ColorScheme” as one clause among many. The '
        r'change adds 12 lines to a 59-line file and moves it from '
        r'a script to a small system with an invariant (idempotent, '
        r'safe to re-source) that the header comment partly states.'),

    ...sec('limits'),
    ...pt('--', 'a hand-kept list',
        r'a window or plugin whose group is not in the 40 keeps its '
        r'background. There is no automatic discovery of groups.'),
    ...pt('--', 'links become definitions',
        r'a group that was a link and has a bg is rewritten as a '
        r'standalone definition (by the API semantics above), so it '
        r'no longer follows a later change to its old target.'),
    ...pt('--', 'bg only',
        r'the code clears the bg key and nothing else. That is '
        r'enough with true-colour output; in a terminal mode that '
        r'uses cterm colours the cterm background would remain (only '
        r'relevant if termguicolors is off, which I did not check).'),
    ...pt('--', 'no measurement, no test',
        r'40 table lookups per colorscheme change is obviously cheap, '
        r'but the repo has no benchmark and no test for this file. '
        r'The verification for 1.3.0 is the changelog line.'),
    ...pt('--', 'the guard has no stated reason',
        r'see above. A one-line comment in the file would capture '
        r'it.'),
    blank,
    ...para('--',
        r'What to take from it: attach a repair to the event that '
        r'causes the damage and not to the moment you noticed it; make '
        r'the repair idempotent so nobody has to count how often it '
        r'runs; and clear the group before you re-register. The file '
        r'is 71 lines, and these three habits are most of the '
        r'difference between the 59-line version and the 71-line one.'),
    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
