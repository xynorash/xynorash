import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/island/init.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'lua/island/init.lua — a JetBrains colour scheme, turned into Neovim'),
    cm('--', r'one setup() function that sets about a thousand highlight groups'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the Island Dark theme engine: palette in, highlight groups out'),
    kv(r'language', r'Lua (Neovim API: nvim_set_hl, vim.g.terminal_color_N)'),
    kv(r'size', r'1206 lines, 4 commits (2026-10-12 to 2026-10-22)'),
    kv(r'inputs', r'lua/island/palette.lua (generated); nothing else'),
    kv(r'entry', r'colors/island-dark.lua calls require("island").setup()'),
    kv(r'tested by', r'tests/theme-island_spec.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'xynovim is a LazyVim based Neovim configuration for Rust. On 2026-10-12 it got its own colour scheme, called Island Dark, and this file is where the scheme lives. The header comment says what it is: it maps a resolved JetBrains scheme onto Neovim highlight groups, using only colours that exist in the scheme. The scheme itself is not hand written. It comes from a JetBrains export (RustRover 2026.2.3.0.0, parent scheme Darcula, per the header of lua/island/palette.lua) that a converter, tools/icls2nvim.py, turned into a Lua table. The export is not distributed with the repository, so the generated palette is the only source of colour truth in the repo, and this file is the only reader of it besides the lualine theme.'),
    ...para('--', r'That split is the whole design. palette.lua is data and is never edited by hand. init.lua is policy: which scheme entry should colour which Neovim group. When a JetBrains attribute is missing for something Neovim has (a Rust trait, a lifetime, a coverage sign), the file does not invent a colour. It picks the closest scheme colour and says so in a comment, for example that traits use the struct colour because the scheme has no TRAIT entry.'),
    ...sec(r'the file at a glance'),
    ...para('--', r'There is one module table M, one exported function M.setup(), and everything inside setup() is a long run of tables that are then walked with pairs() and handed to nvim_set_hl. In order, by line range:'),
    blank,
    ...pt('--', r'1-114', r'header, helpers (at, lum, ratio, lift, fgof) and the colour roles'),
    ...pt('--', r'116-232', r'editor UI groups: Normal, floats, cursor, gutter, search, popup menu, statusline, diff mode, diagnostics'),
    ...pt('--', r'235-375', r'classic Vim syntax groups plus the nvim-treesitter captures'),
    ...pt('--', r'378-482', r'LSP semantic tokens, including rust-analyzer’s own legend'),
    ...pt('--', r'485-525', r'LSP and editor features: inlay hints, code lens, coverage, navic, flash'),
    ...pt('--', r'528-591', r'git: gitsigns and diffview'),
    ...pt('--', r'594-651', r'completion: blink.cmp kinds and menu'),
    ...pt('--', r'654-768', r'snacks.nvim: indent, notifier, input, dashboard, picker'),
    ...pt('--', r'771-1085', r'which-key, neo-tree, trouble, noice, mini.*, harpoon, neotest, DAP, satellite, render-markdown'),
    ...pt('--', r'1088-1178', r'todo-comments, lazy, mason, overseer, rainbow delimiters, crates'),
    ...pt('--', r'1180-1204', r'the sixteen terminal ANSI colours'),
    blank,
    ...sec(r'step one: turning a palette attribute into a highlight spec'),
    ...code('lua', r'lua/island/init.lua · lines 5-24', r'''
local M = {}

local P = require("island.palette")
local A, C, D = P.attrs, P.colors, P.derived

--- palette attribute -> nvim_set_hl spec (fg, bg, bold, italic, effect), with overrides
local function at(key, extra)
  local a = A[key] or {}
  local t = { fg = a.fg, bg = a.bg, bold = a.bold, italic = a.italic }
  if a.effect == "underline" then
    t.underline, t.sp = true, a.effect_color
  elseif a.effect == "undercurl" then
    t.undercurl, t.sp = true, a.effect_color
  elseif a.effect == "underdotted" then
    t.underdotted, t.sp = true, a.effect_color
  elseif a.effect == "strikethrough" then
    t.strikethrough = true
  end
  return vim.tbl_extend("force", t, extra or {})
end'''),
    ...para('--', r'The palette has three tables. colors holds the scheme’s named single colours (CARET_ROW_COLOR, LOOKUP_COLOR, INDENT_GUIDE, and so on). attrs holds the text attributes, each with an optional fg, bg, bold, italic, an effect and an effect_color, and for some entries a stripe colour used by the editor’s error stripe. derived holds three colours the scheme itself does not define but the theme needs (BORDER, SELECTION_BACKGROUND, SELECTION_STRONG).'),
    ...para('--', r'at() is the bridge from the attrs table to Neovim. JetBrains has one field, effect, where Neovim has four separate booleans, so the function expands it: underline, undercurl, underdotted and strikethrough. The effect colour becomes sp, Neovim’s special colour for underlines. A missing key is not an error: A[key] or {} means an unknown name produces an empty spec rather than crashing the whole theme. The second argument is the escape hatch, merged with tbl_extend("force"), and it is how the file overrides one field of a scheme entry. Comment is the typical user, which takes DEFAULT_LINE_COMMENT but swaps in a lifted foreground.'),
    ...para('--', r'The attribute names are worth reading once. Plain keys such as DEFAULT_KEYWORD and DEFAULT_STRING are JetBrains’ language independent defaults. Keys beginning with org.rust. come from the Rust plugin’s own colour page: MACRO, STRUCT, ENUM_VARIANT, SELF_PARAMETER, Q_OPERATOR and so on. Since this configuration is built around Rust, the Rust entries are used wherever they exist, and the generic ones fill the rest.'),
    ...sec(r'step two: lifting the colours that are too dim'),
    ...code('lua', r'lua/island/init.lua · lines 26-65', r'''
-- WCAG 2.x contrast helpers, used to lift the few scheme colours that fall
-- short of the legibility targets (see README, Theme: "Legibility lifts").
local function lum(hex)
  local ch = {}
  for i = 1, 3 do
    local c = tonumber(hex:sub(2 * i, 2 * i + 1), 16) / 255
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

--- `fg` mixed towards white in 1% steps until it reaches `target`:1 on `on`
--- (unchanged when it already does; keeps the hue as far as possible)
local function lift(fg, on, target)
  local f = {}
  for i = 1, 3 do
    f[i] = tonumber(fg:sub(2 * i, 2 * i + 1), 16)
  end
  local out = fg
  for t = 0, 100 do
    out = string.format(
      "#%02x%02x%02x",
      f[1] + (255 - f[1]) * t / 100 + 0.5,
      f[2] + (255 - f[2]) * t / 100 + 0.5,
      f[3] + (255 - f[3]) * t / 100 + 0.5
    )
    if ratio(out, on) >= target then
      break
    end
  end
  return out
end'''),
    ...para('--', r'A faithful port of an IDE scheme has one problem in a terminal editor: JetBrains tunes its colours for its own editor font and rendering, and a few of them are dim. This file does not accept that silently. It measures. lum() and ratio() are the standard WCAG 2.x relative luminance and contrast ratio, written out in twenty lines so that the theme needs no dependency. lift() then fixes a failing colour in the least destructive way it can: it mixes the colour towards white in one percent steps and stops at the first step that reaches the target ratio on the given background. If the colour already passes, the loop breaks at step zero and the colour comes back unchanged (rounded through the format string, which is why the test compares a passing colour for equality). Mixing towards white rather than raising a lightness channel keeps the hue as close as a simple rule can.'),
    ...para('--', r'The first branch of the loop is the important detail: t = 0 is tested before any mixing. So lift() is safe to apply to every colour you are unsure about, not just the ones you know fail. The cost is at most 101 iterations of cheap arithmetic, run a handful of times at theme load.'),
    ...sec(r'step three: naming the roles'),
    ...code('lua', r'lua/island/init.lua · lines 79-103', r'''
  -- Roles -----------------------------------------------------------------
  local bg, fg = A.TEXT.bg, A.TEXT.fg
  local float_bg = C.LOOKUP_COLOR -- popup/lookup background
  local line_bg = C.CARET_ROW_COLOR
  -- the scheme's caret row (#26282e) is only 1.12:1 on the background; its own
  -- darkest blue annotation colour (#242d42) reads as a band (1.20:1)
  local cl_bg = C.VCS_ANNOTATIONS_COLOR_4
  local sel_bg = D.SELECTION_BACKGROUND
  local border = D.BORDER
  local muted = C.WHITESPACES -- 6f737a, the scheme's "disabled" grey
  local dim = C.LINE_NUMBERS_COLOR
  local num = C.WHITESPACES -- line numbers: scheme #4b5059 is 2.0:1; its "whitespace" grey is 3.5:1
  local sub = fgof("BREADCRUMBS_DEFAULT") -- secondary text
  local bright = fgof("BREADCRUMBS_CURRENT")
  -- comments (#7a7e85, 4.0:1) and doc comments (#5f826b, 3.8:1) lifted to 4.5:1
  local comment_fg = lift(fgof("DEFAULT_LINE_COMMENT"), bg, 4.5)
  local doc_fg = lift(fgof("DEFAULT_DOC_COMMENT"), bg, 4.5)
  local guide, guide_sel = C.INDENT_GUIDE, C.SELECTED_INDENT_GUIDE
  local red, yellow = fgof("CONSOLE_ERROR_OUTPUT"), fgof("LOG_INFO_OUTPUT")
  local blue = fgof("DEFAULT_FUNCTION_DECLARATION")
  local green = fgof("DEFAULT_STRING")
  local orange = fgof("DEFAULT_KEYWORD")
  local purple = fgof("DEFAULT_CONSTANT")
  local cyan = fgof("DEFAULT_NUMBER")
  local gold = fgof("org.rust.MACRO")'''),
    ...para('--', r'This block is the design document of the theme, written as code. Rather than scatter palette lookups through a thousand lines, the file first decides what each role means once, and every plugin group below is written in terms of roles: bg, fg, float_bg, sel_bg, border, muted, sub, bright, and the accent colours red, yellow, blue, green, orange, purple, cyan and gold.'),
    blank,
    ...pt('--', r'the accents are borrowed from syntax', r'there is no "accent palette" in a JetBrains scheme, so the accents are the colours the scheme gives to code. Blue is the function declaration colour, green is the string colour, orange is the keyword colour, purple is the constant colour, cyan is the number colour, gold is the Rust macro colour. red and yellow come from the console error and log info outputs. A plugin that wants a "success green" therefore gets the same green as a string literal. The result is that the editor chrome and the code share one palette, which is the point of porting an IDE scheme.'),
    ...pt('--', r'cl_bg, the cursorline', r'the comments record a measured decision. The scheme’s own caret row colour is #26282e, only 1.12:1 against the #1e1f22 background, which is close to invisible. The darkest of its blue annotation colours, #242d42, reads as a band at 1.20:1, so that is used for CursorLine and the caret row stays for the other bands (ColorColumn, treesitter-context).'),
    ...pt('--', r'num versus dim', r'line numbers use the scheme’s whitespace grey (3.5:1) instead of its line number colour, which is 2.0:1 on the same background. dim, the original line number colour, is kept for the things that should recede: NonText, Whitespace, the sign column, ghost text.'),
    ...pt('--', r'comment_fg and doc_fg', r'both pass through lift() with a 4.5:1 target. The comment text says the scheme values are 4.0:1 and 3.8:1. So comments are slightly lighter than in RustRover, on purpose, and the original values stay in the palette. The spec pins both ends: it checks that the palette still holds #7a7e85 and that Comment is the lifted #82868c.'),
    blank,
    ...para('--', r'The remaining role lines (err_c, warn_c, the file status colours st_add, st_mod, st_del) pull the same kind of named value. One of them has a stale comment worth knowing about. At line 108 the comment says the file status blue is 6.0:1, but the spec measures GitSignsChange at 7.2:1 against #1e1f22 and the README says 7.2:1; the spec prints a note about the code comment being the stale one. The colour is right, the number in the comment is not.'),
    ...sec(r'the editor UI table'),
    ...code('lua', r'lua/island/init.lua · lines 115-129', r'''
  -- Editor UI -------------------------------------------------------------
  local ui = {
    Normal = { fg = fg, bg = bg },
    NormalNC = { fg = fg, bg = bg },
    NormalFloat = { fg = fg, bg = float_bg },
    FloatBorder = { fg = border, bg = float_bg },
    FloatTitle = { fg = bright, bg = float_bg, bold = true },
    FloatFooter = { fg = sub, bg = float_bg },
    Cursor = { fg = bg, bg = C.CARET_COLOR },
    lCursor = { link = "Cursor" },
    CursorIM = { link = "Cursor" },
    TermCursor = { link = "Cursor" },
    CursorLine = { bg = cl_bg },
    CursorColumn = { bg = line_bg },
    ColorColumn = { bg = line_bg },'''),
    ...para('--', r'Each table is a plain name to spec map, applied by a three line loop. Three details of how the table is written are worth stating. First, Normal gets a solid bg here and the file never tries to be transparent. Transparency is a separate concern that lives in plugin/after/transparency.lua, which strips backgrounds after the colourscheme has loaded, and the spec checks both states (Normal has the solid #1e1f22 when transparency is off). Second, floats are solid. NormalFloat takes LOOKUP_COLOR, #2b2d30, and the spec asserts that popups keep that background even with transparency on. The commit that introduced it is called "solid floats" for that reason. Third, links are used where a group is the same thing by definition: lCursor, CursorIM and TermCursor all link to Cursor, and StatusLineTerm links to StatusLine.'),
    ...code('lua', r'lua/island/init.lua · lines 229-232', r'''
  }
  for name, spec in pairs(ui) do
    set(name, spec)
  end'''),
    ...para('--', r'Because every group is set in isolation, the iteration order of pairs() does not matter. The one exception would be a link to a group defined later, and nvim_set_hl does not require the target to exist yet, so there is no ordering constraint to maintain.'),
    ...para('--', r'The diagnostics block at the end of this table shows the lift helper doing real work: DiagnosticVirtualTextError is red lifted to 4.5:1 on the ERROR_HINT background (#402929), and DiagnosticFloatingError is red lifted on the float background. The same red on the plain editor background is already fine, so DiagnosticError itself is not lifted. The lift target depends on what the text sits on, which is why lift takes the background as an argument.'),
    ...sec(r'classic groups, treesitter and the Rust specifics'),
    ...code('lua', r'lua/island/init.lua · lines 235-251', r'''
  local syn = {
    Comment = at("DEFAULT_LINE_COMMENT", { fg = comment_fg }),
    SpecialComment = at("DEFAULT_DOC_COMMENT_TAG"),
    Constant = at("DEFAULT_CONSTANT"),
    String = at("DEFAULT_STRING"),
    Character = at("DEFAULT_STRING"),
    Number = at("DEFAULT_NUMBER"),
    Float = at("DEFAULT_NUMBER"),
    Boolean = at("DEFAULT_KEYWORD"),
    Identifier = { fg = fg },
    Function = at("DEFAULT_FUNCTION_DECLARATION"),
    Statement = at("DEFAULT_KEYWORD"),
    Conditional = at("DEFAULT_KEYWORD"),
    Repeat = at("DEFAULT_KEYWORD"),
    Label = at("DEFAULT_KEYWORD"),
    Operator = at("DEFAULT_OPERATION_SIGN"),
    Keyword = at("DEFAULT_KEYWORD"),'''),
    ...para('--', r'The syn table has two halves in one literal: the old Vim groups (Comment, String, Statement, Type and the rest) so that anything without treesitter still looks right, and the @-prefixed capture names that nvim-treesitter and Neovim’s built in parser produce. Booleans are coloured like keywords, as in JetBrains. Identifiers, parameters and plain variables are the default text colour: a JetBrains scheme does not paint ordinary variables, and the theme follows.'),
    ...code('lua', r'lua/island/init.lua · lines 366-372', r'''
    -- Rust treesitter specifics
    ["@keyword.self.rust"] = at("org.rust.SELF_PARAMETER"),
    ["@variable.builtin.rust"] = at("org.rust.SELF_PARAMETER"),
    ["@punctuation.special.rust"] = at("org.rust.Q_OPERATOR"),
    -- Embedded code in docs / markdown
    ["@markup.raw.markdown_inline"] = { fg = fg, bg = A.DOC_CODE_INLINE.bg },
  }'''),
    ...para('--', r'The .rust suffixed captures use Neovim’s per language fallback: a group named @capture.lang wins over @capture for that language only. self (the Rust self parameter), and the question mark operator, get their JetBrains Rust colours, a pink for self and a bold gold for the ? operator, without disturbing other languages that share the generic capture names.'),
    ...sec(r'LSP semantic tokens: rust-analyzer’s vocabulary'),
    ...code('lua', r'lua/island/init.lua · lines 377-399', r'''
  -- LSP semantic tokens (generic; rust-analyzer's legend is the Rust plugin's) ----
  local lsp = {
    ["@lsp.type.namespace"] = { fg = fg },
    ["@lsp.type.type"] = at("org.rust.STRUCT"),
    ["@lsp.type.class"] = at("org.rust.STRUCT"),
    ["@lsp.type.struct"] = at("org.rust.STRUCT"),
    ["@lsp.type.union"] = at("org.rust.UNION"),
    ["@lsp.type.enum"] = at("org.rust.ENUM"),
    ["@lsp.type.enumMember"] = at("org.rust.ENUM_VARIANT"),
    ["@lsp.type.interface"] = at("org.rust.STRUCT"), -- traits: the scheme has no TRAIT entry
    ["@lsp.type.typeAlias"] = at("org.rust.TYPE_ALIAS"),
    ["@lsp.type.typeParameter"] = at("org.rust.TYPE_PARAMETER"),
    ["@lsp.type.parameter"] = { fg = fg },
    ["@lsp.type.variable"] = { fg = fg },
    ["@lsp.type.property"] = at("DEFAULT_INSTANCE_FIELD"),
    ["@lsp.type.function"] = at("org.rust.FUNCTION"),
    ["@lsp.type.method"] = at("org.rust.METHOD"),
    ["@lsp.type.macro"] = at("org.rust.MACRO"),
    ["@lsp.type.decorator"] = at("DEFAULT_METADATA"),
    ["@lsp.type.keyword"] = at("DEFAULT_KEYWORD"),
    ["@lsp.type.comment"] = at("DEFAULT_LINE_COMMENT", { fg = comment_fg }),
    ["@lsp.type.string"] = at("DEFAULT_STRING"),
    ["@lsp.type.number"] = at("DEFAULT_NUMBER"),'''),
    ...para('--', r'The comment on the first line is a pointer to the repository’s history. rust-analyzer’s extra token types are the Rust plugin’s business, in the sense that the Rust tooling modules were later extracted into standalone xyno-*.nvim repositories under ~/projects/xyno-plugins (xyno-rust.nvim and friends). The theme stays in this repository. There is no island or theme plugin among the nine extracted ones (clipboard, crates, guard, history, imports, macros, new, rust, sandbox), so Island Dark is not published as a separate repo; it ships as the colorscheme in this configuration.'),
    ...code('lua', r'lua/island/init.lua · lines 402-406', r'''
    -- rust-analyzer token types
    ["@lsp.type.lifetime.rust"] = at("org.rust.TYPE_PARAMETER"), -- no LIFETIME entry: type parameter colour
    ["@lsp.type.label.rust"] = at("org.rust.TYPE_PARAMETER"),
    ["@lsp.type.builtinType.rust"] = at("DEFAULT_KEYWORD"),
    ["@lsp.type.selfKeyword.rust"] = at("org.rust.SELF_PARAMETER"),'''),
    ...para('--', r'Here the "closest scheme colour" rule is applied visibly. Rust lifetimes have no entry in the JetBrains scheme, so they take the type parameter teal. The next lines map rust-analyzer’s punctuation tokens (brace, bracket, comma, semicolon, dot), operator families (arithmetic, bitwise, comparison, logical), escape sequences, format specifiers, attributes and derives. Most of these map to a handful of scheme entries, which is the intent: the scheme paints punctuation in the foreground colour and keeps contrast for names and keywords.'),
    ...code('lua', r'lua/island/init.lua · lines 443-448', r'''
    -- modifiers (a modifier group only adds attributes on top of the token's colour)
    ["@lsp.mod.mutable.rust"] = { underline = true, sp = A["org.rust.MUT_BINDING"].effect_color },
    ["@lsp.mod.deprecated"] = at("DEPRECATED_ATTRIBUTES"),
    ["@lsp.mod.documentation.rust"] = at("DEFAULT_DOC_COMMENT", { fg = doc_fg }),
    ["@lsp.mod.static.rust"] = at("org.rust.STATIC"),
    ["@lsp.mod.intraDocLink.rust"] = { fg = C.DOC_COMMENT_LINK, underline = true },'''),
    ...para('--', r'This is the line that most affects a day of Rust editing. In RustRover, mutable bindings are underlined. Here, mutability is a semantic token modifier, and a modifier group adds attributes on top of whatever colour the token already has, so { underline = true, sp = ... } underlines the variable without changing its colour. The same trick is used for unsafe code, but the unsafe underline is not set in this file at all.'),
    ...code('lua', r'lua/island/init.lua · lines 478-482', r'''
  -- unsafe: left to plugin/after/unsafe-highlight.lua (underline). The scheme's
  -- org.rust.UNSAFE_CODE background is a code-wide band and is not applied.
  set("RustUnsafeCode", at("org.rust.UNSAFE_CODE"))
  -- cfg-disabled code: rust-analyzer reports it as an "unnecessary" hint
  set("RustCfgDisabled", at("org.rust.CFG_DISABLED_CODE"))'''),
    ...para('--', r'A deliberate omission, with its reason in the comment. The scheme colours unsafe code with a reddish background (#4e2c28). That would paint whole unsafe functions in a band, so it is not applied; instead an underline comes from plugin/after/unsafe-highlight.lua (see that page). The scheme’s colour is still defined, as the group RustUnsafeCode, so nothing is lost for a tool that wants it. The same pattern applies to cfg-disabled code: the group exists in the scheme’s olive, but rust-analyzer actually reports such code as an unnecessary diagnostic, so the visible colour comes from DiagnosticUnnecessary, which the spec confirms.'),
    ...sec(r'plugin groups: the long tail'),
    ...para('--', r'From line 485 to 1178 the file is a catalogue. It is long because a colour scheme is only finished when the plugins you use do not fall back to strange defaults. Each block is a table named after what it covers, introduced by a comment, and followed by the same three line loop.'),
    blank,
    ...pt('--', r'feat (485-522)', r'LSP inlay hints, code lens, reference highlights, signature help, snippet tabstops, coverage signs, navic, treesitter-context, flash.nvim. Coverage signs use the scheme’s stripe colours, with a comment explaining that the editor’s coverage bands are too dim for a sign.'),
    ...pt('--', r'git (528-591)', r'gitsigns in all its variants (signs, staged signs, inline, preview, virtual lines) and the diffview panel. Diff backgrounds reuse the scheme’s NEXT_EDIT colours for added and removed lines.'),
    ...pt('--', r'blink.cmp (594-651)', r'kinds are built from a name to colour table and set in a loop with the BlinkCmpKind prefix, so every completion kind (Method, Function, Field, EnumMember, Snippet, and so on) reuses the matching Rust colour; the menu, docs and signature groups follow.'),
    ...pt('--', r'snacks (654-768)', r'around a hundred groups for the indent guides, notifier levels, input, dashboard and the whole picker. Tone is consistent: borders are the neutral border grey, titles and matches blue, labels and keys orange.'),
    ...pt('--', r'misc (771-1085)', r'which-key, neo-tree, trouble, noice, the mini.* family, harpoon, neotest, nvim-dap and dap-ui, satellite and render-markdown.'),
    ...pt('--', r'ui2 (1088-1178)', r'todo-comments, lazy.nvim, Mason, Overseer, bufferline fill, ghost text, rainbow delimiters, :checkhealth and crates.nvim.'),
    blank,
    ...code('lua', r'lua/island/init.lua · lines 770-785', r'''
  -- which-key, neo-tree, trouble, noice, mini, harpoon, neotest, dap ----------------------
  local accent = {
    Azure = blue,
    Blue = blue,
    Cyan = cyan,
    Green = green,
    Grey = muted,
    Orange = orange,
    Purple = purple,
    Red = red,
    Yellow = yellow,
  }
  for name, color in pairs(accent) do
    set("MiniIcons" .. name, { fg = color })
    set("WhichKeyIcon" .. name, { fg = color })
  end'''),
    ...para('--', r'Where plugins share a naming scheme the file generates the groups instead of listing them. mini.icons and which-key both use nine colour names, so one table fills both families. The heading groups for render-markdown are generated the same way, six colours looped over H1 to H6 with a matching background group. The generated forms keep the catalogue shorter and make a missing colour impossible to forget for one of the two families.'),
    ...sec(r'the terminal palette'),
    ...code('lua', r'lua/island/init.lua · lines 1180-1206', r'''
  -- Terminal ANSI palette (the scheme's own console colours) -------------------------------
  local ansi = {
    bg,
    red,
    green,
    yellow,
    blue,
    purple,
    cyan,
    fg,
    C.LINE_NUMBERS_COLOR,
    red,
    green,
    yellow,
    blue,
    purple,
    cyan,
    bright,
  }
  for i, color in ipairs(ansi) do
    vim.g["terminal_color_" .. (i - 1)] = color
  end
  vim.g.terminal_color_background = bg
  vim.g.terminal_color_foreground = fg
end

return M'''),
    ...para('--', r'The last block makes embedded terminals (the :terminal buffer, lazygit, the test runners) match the theme. Slots 0 to 7 are black, red, green, yellow, blue, magenta, cyan, white, and slots 8 to 15 are the bright variants. The scheme gives no separate bright colours, so the bright row repeats the normal accents and only changes black (to the dim grey) and white (to the brighter text). The consequence is that "bright red" and "red" are the same colour in a terminal buffer, which is a limit of this approach rather than a bug; programs that rely on that distinction will lose it.'),
    ...para('--', r'Note that these are vim.g globals and not highlight groups, which is why they are set at the very end: they only need to exist by the time a terminal is opened.'),
    ...sec(r'edge cases and failure modes'),
    ...pt('--', r'a missing palette key', r'at() and fgof() both fall back to an empty table, so a key that is absent from the palette gives an empty spec or a nil colour rather than an error. The cost is that a typo yields a silently uncoloured group, which is why the spec has a "group coverage" section that asserts the plugin groups are defined and non-empty.'),
    ...pt('--', r'setup() twice', r'the spec calls setup() twice and checks that the resulting highlights are identical. All writes are idempotent nvim_set_hl calls on the global namespace, and nothing accumulates, so reloading the theme is safe. This matters because colors/island-dark.lua runs "highlight clear" first and then setup() every time the colourscheme is loaded.'),
    ...pt('--', r'switching away', r'colorscheme changes elsewhere are handled outside this file. After a different :colorscheme the lualine theme returns the auto theme (see lualine/themes/island-dark.lua), and the unsafe underline is re-applied on the ColorScheme event.'),
    ...pt('--', r'nvim_set_hl on a link', r'groups whose spec is { link = "..." } are set with the same call; because a link spec carries no other keys, there is nothing to merge, and the later definition simply replaces the earlier one.'),
    ...sec(r'a detail to be aware of'),
    ...para('--', r'The git block defines six GitSignsStaged groups with blend = 40 next to a foreground colour only (lines 535-540). The specs have no bg, and the repo does not say what effect the blend is meant to have on the staged signs or test it, so the effect is not obvious from the code alone.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/theme-island_spec.lua is organised by the same concerns as the file. It checks that island-dark is the active colourscheme after startup and that :colorscheme island-dark prints no messages. It checks exact colour values: Normal fg #bcbec4 on #1e1f22, popups at #2b2d30, selection #2d416b, Comment #82868c (lifted from the scheme’s #7a7e85), doc comments #6f8f7a in italic, error virtual text #f86574 on #402929. It checks that the contrast claims reproduce: comments reach 4.5:1, line numbers are about 3.5:1, and the cursorline band is about 1.20:1. It tests lift() itself: a colour that already meets the target is kept, otherwise the result mixes towards white in one percent steps. It asserts that plugin groups and treesitter captures resolve to non-empty highlights, that the rust-analyzer semantic groups use the org.rust.* colours, and that the sixteen terminal colours and fg/bg are set. A last section starts a real rust-analyzer and checks that actual tokens resolve to scheme colours.'),
    ...sec(r'history'),
    ...pt('--', r'cf842d0 (2026-10-12)', r'"Theme: Island Dark from RustRover scheme, permanent". The first version: 1156 lines of init.lua and the 251 line palette arrive together with colors/island-dark.lua, the lualine theme, tools/icls2nvim.py and the original Dark.icls export in tools/. The README and CHANGELOG were updated in the same commit.'),
    ...pt('--', r'4d45a21 (2026-10-12)', r'"Theme polish: solid floats, contrast lifts, visible cursorline". This is the commit that introduced the contrast helpers and the cl_bg decision: 106 lines changed in this file.'),
    ...pt('--', r'0da94f4 (2026-10-22)', r'"Remove tools/Dark.icls, keep only the generated palette". The raw JetBrains export was deleted from the repository, which is why the header now says the export is not distributed and why the spec’s round trip test rebuilds a synthetic .icls from the palette instead.'),
    ...pt('--', r'f7b8cf0 (2026-10-22)', r'"Voice: first person, as Xynorash". A one line change to the header comment: "from the author’s own export" became "from my own export".'),
    ...sec(r'what to take from it'),
    ...para('--', r'The interesting move is not the number of groups, it is the discipline around them. The scheme is data and never edited; every role is named once; every deviation from the scheme (a lifted comment colour, a darker cursorline, a missing LIFETIME entry, the unsafe band left out) is recorded in a comment next to the line that makes it, and measured by a test. A thousand lines of highlight groups is a lot to keep honest, and this file keeps itself honest by writing down why.'),
  ],
);
