import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/theme-island_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'theme-island_spec.lua — a colour scheme tested like a library'),
    cm('--', r'literal expected colours, contrast ratios computed by hand, a round trip through a JetBrains file, and transparency that survives a theme switch'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for colors/island-dark.lua, lua/island/{init,palette}.lua, the lualine theme, plugin/after transparency and unsafe highlight, and tools/icls2nvim.py'),
    kv(r'language', r'Lua spec, 892 lines, 44 it() blocks, 13 describe() blocks'),
    kv(r'method', r'expected colours are written out literally; the palette is read only where the test is about the palette'),
    kv(r'history', r'3 commits: b2fee5c (2026-10-13), 0b0eee8 (2026-10-14), 0da94f4 (2026-10-22)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The Island Dark theme is the face of this configuration, and a colour scheme is easy to break without any error: a changed palette, a highlight group that a plugin overwrites, a transparency toggle that forgets the popup background. The header makes the testing rule explicit: expected values are literals taken from the scheme, and the palette file is read only for tests about the palette itself. If the tests read the same palette the theme reads, they could never disagree with it.'),
    ...code('lua', r'tests/theme-island_spec.lua · lines 1-5', r'''
-- Island Dark theme: colors/island-dark.lua, lua/island/{init,palette}.lua, the lualine theme,
-- plugin/after/{transparency,unsafe-highlight}.lua and tools/icls2nvim.py.
-- Expected colours are written out literally (the scheme's values), the
-- palette is only read where the test is about the palette itself.
local H = require("xynotest.helpers")'''),
    ...sec(r'small tools'),
    ...para('--', r'Two helpers turn nvim highlight integers into #rrggbb strings, and the contrast helper implements the WCAG relative luminance formula (the linearisation of each channel, and weights 0.2126, 0.7152 and 0.0722) and the ratio of the lighter to the darker plus 0.05. near compares with a tolerance. With them a test can say that line numbers are about 3.5 to 1 without a library.'),
    ...code('lua', r'tests/theme-island_spec.lua · lines 7-45', r'''
-- ------------------------------------------------------------------ local helpers

local function hl(name, link)
  return vim.api.nvim_get_hl(0, { name = name, link = link or false })
end

--- nvim_get_hl colours are integers; compare as "#rrggbb"
local function hex(n)
  return n and string.format("#%06x", n) or nil
end

local function fg(name) return hex(hl(name).fg) end
local function bg(name) return hex(hl(name).bg) end
local function sp(name) return hex(hl(name).sp) end

local function lum(h)
  local ch = {}
  for i = 1, 3 do
    local c = tonumber(h:sub(2 * i, 2 * i + 1), 16) / 255
    ch[i] = c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
  end
  return 0.2126 * ch[1] + 0.7152 * ch[2] + 0.0722 * ch[3]
end

local function ratio(a, b)
  local x, y = lum(a), lum(b)
  if x < y then
    x, y = y, x
  end
  return (x + 0.05) / (y + 0.05)
end

local function near(expected, actual, tol, msg)
  H.ok(math.abs(expected - actual) <= tol, ("%s: expected ~%s, got %s"):format(msg or "value", expected, actual))
end

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")'''),
    ...sec(r'loading the scheme'),
    ...para('--', r'The load test reads colors/island-dark.lua and requires highlight clear, syntax reset, dark background, termguicolors, the colors_name global and setup(). Then it checks the behaviour behind the text: it creates a stray highlight group, sets a light background, disables termguicolors, clears the scheme name, reloads the scheme, and requires that the stray group is gone, the background is dark again, termguicolors is back, the name is island-dark and Normal has the foreground #bcbec4. A second test runs syntax reset only when syntax is on, and loading the scheme prints no messages.'),
    ...code('lua', r'tests/theme-island_spec.lua · lines 102-121', r'''
  it("colors/island-dark.lua clears highlights, resets syntax, sets the globals, then runs setup()", function()
    local src = read(H.repo .. "/colors/island-dark.lua")
    H.match(src, 'vim.cmd("highlight clear")', true)
    H.match(src, "syntax reset", true)
    H.match(src, 'vim.o.background = "dark"', true)
    H.match(src, "vim.o.termguicolors = true", true)
    H.match(src, 'vim.g.colors_name = "island-dark"', true)
    H.match(src, 'require("island").setup()', true)
    -- behaviour: a stray group disappears (highlight clear), the scheme's come back
    vim.api.nvim_set_hl(0, "XynoStray", { fg = "#123456" })
    vim.o.background = "light"
    vim.o.termguicolors = false
    vim.g.colors_name = nil
    reload_scheme()
    H.eq({}, hl("XynoStray"), "highlight clear removed the stray group")
    H.eq("dark", vim.o.background)
    H.ok(vim.o.termguicolors)
    H.eq("island-dark", vim.g.colors_name)
    H.eq("#bcbec4", fg("Normal"))
  end)'''),
    ...sec(r'the palette is generated'),
    ...para('--', r'palette.lua starts with GENERATED and DO NOT EDIT in its first 200 characters. The tests fix its identity: name Dark, 63 colours, 173 attributes, and three derived colours: BORDER #666870, SELECTION_BACKGROUND #2d416b and SELECTION_STRONG #2f5194. The counts are not decoration. When the palette is regenerated they change, and the author must look at what changed.'),
    ...code('lua', r'tests/theme-island_spec.lua · lines 156-172', r'''
  it("is generated: header, name, counts and derived colours", function()
    local src = read(H.repo .. "/lua/island/palette.lua")
    local head = src:sub(1, 200)
    H.match(head, "GENERATED", true)
    H.match(head, "DO NOT EDIT", true)
    local P = pal()
    H.eq("Dark", P.name)
    local n = 0
    for _ in pairs(P.colors) do n = n + 1 end
    H.eq(63, n, "colors")
    n = 0
    for _ in pairs(P.attrs) do n = n + 1 end
    H.eq(173, n, "attrs")
    H.eq("#666870", P.derived.BORDER)
    H.eq("#2d416b", P.derived.SELECTION_BACKGROUND)
    H.eq("#2f5194", P.derived.SELECTION_STRONG)
  end)'''),
    ...sec(r'the converter and its round trip'),
    ...para('--', r'tools/icls2nvim.py converts a JetBrains scheme into the palette. No scheme is committed (commit 0da94f4, 2026-10-22, "Remove tools/Dark.icls, keep only the generated palette"), so the tests need an input: H.write_icls builds a synthetic .icls from the committed palette, in the file format the converter reads. The round trip runs the converter on it and requires that colours, attributes, derived values and the name equal those of the committed palette, and that the palette is real (more than 100 attributes). Other tests: without an input file the converter prints a message, exits non-zero and writes nothing; it is stdlib only (it runs with -I -S, no site-packages); it accepts custom input and output arguments and creates the output directory; it resolves baseAttributes chains without looping on cycles and falls back to DEFAULT_ values; and it maps effect types 1 and 4 to underline, 2 to undercurl, 3 to strikethrough, 5 to underdotted and 0 to none.'),
    ...code('lua', r'tests/theme-island_spec.lua · lines 231-242', r'''
  it("round trip: a synthetic .icls rebuilt from lua/island/palette.lua converts back to the same colours and attributes", function()
    H.write_icls(work .. "/fixture.icls")
    local r = py({ H.repo .. "/tools/icls2nvim.py", work .. "/fixture.icls", work .. "/out.lua" })
    H.eq(0, r.code, r.stderr)
    local got, want = dofile(work .. "/out.lua"), dofile(H.repo .. "/lua/island/palette.lua")
    H.eq(want.colors, got.colors)
    H.eq(want.attrs, got.attrs)
    H.eq(want.derived, got.derived)
    H.eq(want.name, got.name)
    H.match(r.stdout, "fixture.icls", true)
    H.ok(vim.tbl_count(want.attrs) > 100, "a real palette, not an empty one")
  end)'''),
    ...sec(r'the colours'),
    ...para('--', r'Normal has the foreground #bcbec4, and no background because the config is transparent by default; the scheme solid #1e1f22 backs the terminal colours and appears as terminal_color_background and terminal_color_0. The remaining tests pin popups at #2b2d30, selection at #2d416b for Visual and PmenuSel, comment #82868c, doc comment #6f8f7a in italics, error virtual text #f86574 on #402929, and gutter and chrome groups.'),
    ...code('lua', r'tests/theme-island_spec.lua · lines 304-312', r'''
  it("Normal fg is #bcbec4, the scheme's solid bg #1e1f22 backs terminal colours; Normal bg is nil when transparent", function()
    H.eq("#bcbec4", fg("Normal"))
    H.is_nil(bg("Normal"), "transparent by default")
    -- the solid colour of the scheme
    H.eq("#1e1f22", pal().attrs.TEXT.bg)
    H.eq("#1e1f22", vim.g.terminal_color_background)
    H.eq("#1e1f22", vim.g.terminal_color_0)
  end)
'''),
    ...sec(r'contrast as an assertion'),
    ...para('--', r'Comment, doc comment and error virtual text must reach 4.5 to 1. The test also asserts that two source colours miss the target (#7a7e85 and #5f826b), which proves the lift step in the theme is necessary. The lift itself is local to init.lua, so the next test checks it through its results: it reimplements the mix towards white in 1 percent steps, finds the smallest step that reaches 4.5 on the float background for the error colour and on the base for the line-comment colour, and requires the scheme to use exactly that colour, and that one step less would miss the target. A colour that already meets the target stays unchanged.'),
    ...code('lua', r'tests/theme-island_spec.lua · lines 356-403', r'''
describe("contrast", function()
  before_each(reset)
  local base = "#1e1f22"

  it("comment, doc comment and error virtual text reach 4.5:1", function()
    H.ok(ratio(fg("Comment"), base) >= 4.5, "comment " .. ratio(fg("Comment"), base))
    H.ok(ratio(fg("@comment.documentation"), base) >= 4.5, "doc comment")
    H.ok(ratio(fg("DiagnosticVirtualTextError"), bg("DiagnosticVirtualTextError")) >= 4.5, "error virtual text on its own bg")
    -- the lift stops at the first 1% step that reaches the target: the unlifted scheme colours miss it
    H.ok(ratio("#7a7e85", base) < 4.5)
    H.ok(ratio("#5f826b", base) < 4.5)
  end)

  it("line numbers are ~3.5:1 and the cursorline band ~1.20:1", function()
    near(3.5, ratio(fg("LineNr"), base), 0.1, "line numbers")
    near(1.20, ratio(bg("CursorLine"), base), 0.02, "cursorline")
  end)

  it("lift() keeps a colour that already meets the target and mixes toward white in 1% steps otherwise", function()
    -- lift() is local to lua/island/init.lua: check it through its callers.
    -- DiagnosticFloatingError = lift(red, float_bg, 4.5)
    local red = pal().attrs.CONSOLE_ERROR_OUTPUT.fg
    -- Comment: the smallest t in 0..100 (percent mix towards white) that reaches the target
    local function mix(c, t)
      local f = {}
      for i = 1, 3 do
        local v = tonumber(c:sub(2 * i, 2 * i + 1), 16)
        f[i] = v + (255 - v) * t / 100 + 0.5
      end
      return string.format("#%02x%02x%02x", f[1], f[2], f[3])
    end
    local float_t = 0
    while ratio(mix(red, float_t), "#2b2d30") < 4.5 do
      float_t = float_t + 1
    end
    H.eq(mix(red, float_t), fg("DiagnosticFloatingError"))
    if float_t == 0 then
      H.eq(red, fg("DiagnosticFloatingError"), "unchanged when the target is already met")
    end
    local src = pal().attrs.DEFAULT_LINE_COMMENT.fg
    local t = 0
    while ratio(mix(src, t), base) < 4.5 do
      t = t + 1
    end
    H.ok(t > 0 and t <= 100)
    H.eq(mix(src, t), fg("Comment"))
    H.ok(ratio(mix(src, t - 1), base) < 4.5, "one step less would miss the target")
  end)'''),
    ...sec(r'groups, captures and terminal'),
    ...para('--', r'A coverage block checks that plugin highlight groups are defined and not empty, that treesitter captures resolve to non-empty highlights, that the LSP semantic groups exist (including the org.rust.* colours of the scheme), and that the terminal ANSI colours 0 to 15 and fg and bg are set. Rust semantic tokens use the scheme colours; the inactive cfg code is grey through DiagnosticUnnecessary and the disabled code is olive. The lualine theme defines all modes with the three sections and follows the active colourscheme: after :colorscheme habamax it returns the auto theme.'),
    ...sec(r'transparency'),
    ...para('--', r'Transparency strips the background from the editor surface groups on every ColorScheme event, in the augroup user_transparency. The test gives the groups a background, fires the event and requires that all backgrounds are gone while the foreground stays. Popups and the cursor row keep their solid backgrounds, vim.g.xynovim_transparent = false keeps everything solid, and leader u O toggles the option, re-runs the scheme, and survives a theme switch. The unsafe underline is wiped by highlight clear and restored on ColorScheme.'),
    ...code('lua', r'tests/theme-island_spec.lua · lines 634-645', r'''
  it("strips bg from the editor surface groups on every ColorScheme (augroup user_transparency)", function()
    H.eq(1, #vim.api.nvim_get_autocmds({ group = "user_transparency", event = "ColorScheme" }))
    H.eq({}, bg_left())
    -- give the groups a bg, a ColorScheme event removes it again
    for _, g in ipairs(transparent) do
      vim.api.nvim_set_hl(0, g, { fg = "#ffffff", bg = "#101010" })
    end
    H.eq(#transparent, #bg_left())
    vim.cmd("doautocmd ColorScheme")
    H.eq({}, bg_left())
    H.eq("#ffffff", fg("Normal"), "other attributes are kept")
  end)'''),
    ...sec(r'switching'),
    ...para('--', r'Switching to tokyonight and back works; after a light preview island-dark resets the background to dark; and setup() is idempotent: the test snapshots every highlight group with its attributes and the sixteen terminal colours, calls setup() twice more and requires identical snapshots.'),
    ...code('lua', r'tests/theme-island_spec.lua · lines 730-749', r'''
  it("setup() is idempotent: calling it twice leaves identical highlights", function()
    local function snapshot()
      local out = {}
      for name in pairs(vim.api.nvim_get_hl(0, {})) do
        out[name] = vim.api.nvim_get_hl(0, { name = name })
      end
      return out
    end
    require("island").setup()
    local first = snapshot()
    local terms = {}
    for i = 0, 15 do terms[i] = vim.g["terminal_color_" .. i] end
    require("island").setup()
    require("island").setup()
    local second = snapshot()
    H.eq(first, second)
    for i = 0, 15 do
      H.eq(terms[i], vim.g["terminal_color_" .. i])
    end
  end)'''),
    ...sec(r'numbers that must match the README'),
    ...para('--', r'The legibility test checks comments at 4.5, line numbers at about 3.5 (tolerance 0.1) and the git modified colour at about 7.2 on #1e1f22, as the README says. It also found an inconsistency, and it is handled openly: lua/island/init.lua carries a comment that says the modified colour is 6.0 to 1, while the measured value and the README say 7.2. The test does not fail on it. It prints DOC INCONSISTENCY with the explanation, since the measured number matches the README and only the code comment is stale. The colourscheme load time is printed, not asserted.'),
    ...code('lua', r'tests/theme-island_spec.lua · lines 767-785', r'''
  it("README legibility numbers reproduce: comments 4.5, line numbers 3.5, modified 7.2 (hint 6.0 is inconsistent)", function()
    local base = "#1e1f22"
    H.ok(ratio(fg("Comment"), base) >= 4.5)
    near(3.5, ratio(fg("LineNr"), base), 0.1, "line numbers")
    local modified = ratio(fg("GitSignsChange"), base)
    local hint = ratio(fg("DiagnosticHint"), base)
    print(("git modified %.2f:1, hint %.2f:1 on #1e1f22"):format(modified, hint))
    near(7.2, modified, 0.1, "git modified (README: 7.2:1)")
    -- lua/island/init.lua's comment says the same colour is 6.0:1; the README says 7.2:1.
    -- 6.0 is neither the modified colour nor the hint colour here: documentation inconsistency.
    local readme = H.docs_text()
    H.match(readme, "7.2:1", true)
    local init = read(H.repo .. "/lua/island/init.lua")
    local says_6 = init:find("(6.0:1)", 1, true) ~= nil
    if says_6 then
      -- flagged, not failed: the measured 7.2 matches the README, the code comment is stale
      print("DOC INCONSISTENCY: lua/island/init.lua says FILESTATUS_MODIFIED is 6.0:1, README and measurement say 7.2:1")
    end
  end)'''),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created with the suite.'),
    ...pt('--', r'0b0eee8 (2026-10-14)', r'README showcase, where the legibility numbers were stated.'),
    ...pt('--', r'0da94f4 (2026-10-22)', r'the committed .icls was removed, so H.write_icls and the round trip stand in for it.'),
  ],
);
