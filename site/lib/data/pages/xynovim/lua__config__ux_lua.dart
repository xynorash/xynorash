import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/ux.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'ux.lua — the small things that make the editor feel finished'),
    cm('--', r'diagnostic dedupe, a snippet guard, a right-click menu, a colourblind palette, Neovide'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'UI glue that does not fit one plugin: callbacks used by plugin specs plus setup()'),
    kv(r'language', r'Lua; diagnostics API, treesitter, menus, highlight groups'),
    kv(r'size', r'250 lines, 6 commits (bdd0225 on 2026-10-09 to f31e013 on 2026-10-14)'),
    kv(r'exports', r'leader · diagnostic_text · unclosed_paren · snippets_allowed · colorblind · colorblind_enabled · setup'),
    kv(r'used by', r'plugins/editing-ui.lua (virtual text, snippets provider), keymaps.lua (colourblind toggle), macro_tools.lua, options.lua'),
    kv(r'also lives in', r'nowhere: no xyno-* plugin carries it, it stays in the config'),
    ...sec(r'why this file exists'),
    ...para('--', r'The header lists three things: "right-click menu for Rust buffers, Neovide, and an opt-in colourblind-safe diagnostic palette". In practice the file holds more, because the first field tests of the editing experience produced two functions that plugin specs call back into: the formatter of diagnostic virtual text and the guard of the snippet completion source. None of these is large enough to deserve a file, and none belongs to one plugin, so they live together here under a name that says what they have in common: they are all about how the editor looks and feels, not about what it does.'),
    ...para('--', r'The file is called from three directions. options.lua requires it and calls setup() at startup. Plugin specs (lua/plugins/editing-ui.lua) point their options at the functions, for example virtual_text.format = function(d) return require("config.ux").diagnostic_text(d) end. And keymaps.lua uses the colourblind toggle for a key.'),
    ...sec(r'one problem, shown once: diagnostic virtual text'),
    ...code('lua', r'lua/config/ux.lua · lines 11-55', r'''
-- Diagnostic virtual text --------------------------------------------------

--- First line of a message.
local function head(message)
  return vim.split(message or "", "\n", { plain = true, trimempty = true })[1] or ""
end

--- What identifies a problem across the two tiers: the rustc error code
--- (rust-analyzer sets `code`, clippy's rendered message has `error[E0308]:`),
--- else the first line without its `error: ` prefix, case and end punctuation.
--- rust-analyzer names a lint-level problem by its lint (`code = "unsafe_op_in_unsafe_fn"`)
--- where clippy's rendering carries the error code (`warning[E0133]: ...`) and words it
--- differently, so the two never matched; known pairs.
local LINT_CODES = { unsafe_op_in_unsafe_fn = "E0133" }

local function same_key(d)
  local code = type(d.code) == "string" and (d.code:match("^E%d+$") or LINT_CODES[d.code])
    or head(d.message):match("^%a+%[(E%d+)%]")
  return code or (head(d.message):gsub("^%a+: ", ""):gsub("[%s%p]+$", ""):lower())
end

--- virtual_text.format: only the first line (clippy sends the whole rendered
--- cargo message, ~14 lines, on one nowrap line) followed by [source]. A
--- problem both tiers report on the same line (E0308 from rust-analyzer and
--- from clippy) is shown once: the diagnostic with a `code` (rust-analyzer's,
--- the more specific text), else the one from the earlier namespace.
function M.diagnostic_text(d)
  if d.bufnr and vim.api.nvim_buf_is_valid(d.bufnr) then
    local key = same_key(d)
    for _, o in ipairs(vim.diagnostic.get(d.bufnr, { lnum = d.lnum })) do
      if o.namespace ~= d.namespace and same_key(o) == key then
        local o_coded, d_coded = o.code ~= nil, d.code ~= nil
        if o_coded ~= d_coded then
          if o_coded then
            return nil
          end
        elseif o.namespace < d.namespace then
          return nil
        end
      end
    end
  end
  local text = head(d.message)
  return d.source and (text .. " [" .. d.source .. "]") or text
end'''),
    ...para('--', r'This setup runs two diagnostic tiers, rust-analyzer and bacon-ls with clippy (see rust_context.lua and lsp_status.lua), and they overlap. A type error is reported by both, so the line gets the same message twice, and clippy’s message is the whole rendered cargo output of about fourteen lines, which on a single non-wrapping virtual-text line is unreadable. diagnostic_text is the format function for virtual text and fixes both problems.'),
    ...para('--', r'First the shortening: head() keeps only the first non-empty line of the message, followed by the source in brackets. Then the dedupe: for a diagnostic d, it looks at every other diagnostic on the same line of the same buffer that came from a different namespace and asks whether it is the same problem. same_key defines "the same problem": the rustc error code when there is one (rust-analyzer sets the code field; clippy’s rendered message begins with error[E0308]: or warning[E0133]:, which the pattern ^%a+%[(E%d+)%] extracts), otherwise the first line stripped of its "error: " prefix, trailing punctuation and case. There is one hand-made table. The comment explains: rust-analyzer names a lint-level problem by its lint name (the example is unsafe_op_in_unsafe_fn) while clippy’s rendering carries the error code E0133 and words the text differently, "so the two never matched; known pairs". So the table LINT_CODES has one pair so far.'),
    ...para('--', r'When two diagnostics match, one has to lose, and both namespaces will be asked, so the rule must be symmetric or both would vanish or both would stay. The rule: the one with a code field wins, because it is rust-analyzer’s and "the more specific text"; if both or neither have one, the one from the earlier namespace (the smaller id) wins. The function returns nil for the loser, which tells Neovim not to render that virtual text. Because each diagnostic applies the same rule to the same pair, exactly one is shown.'),
    ...para('--', r'The trick of the last line is the pattern d.source and (text .. " [" .. d.source .. "]") or text, which appends the source only if there is one. Seeing [rust-analyzer] or [bacon-ls] behind a message tells which tier produced it.'),
    ...sec(r're-rendering when the other tier arrives later'),
    ...code('lua', r'lua/config/ux.lua · lines 192-215', r'''
function M.setup()
  local group = vim.api.nvim_create_augroup("xynovim_ux", { clear = true })
  vim.api.nvim_create_autocmd("MenuPopup", { group = group, callback = rust_menu })

  -- Virtual text is rendered per namespace, when that namespace changes; the
  -- duplicate check in diagnostic_text needs the other tier's diagnostics, so
  -- when one arrives (or goes) later, render the buffer's namespaces again.
  local redraw = {}
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    callback = function(args)
      local buf = args.buf
      if redraw[buf] then
        return
      end
      redraw[buf] = true
      vim.schedule(function()
        redraw[buf] = nil
        if vim.api.nvim_buf_is_valid(buf) then
          vim.diagnostic.show(nil, buf)
        end
      end)
    end,
  })'''),
    ...para('--', r'There is a timing problem hidden in the dedupe. Neovim renders virtual text per namespace at the moment that namespace’s diagnostics change. If rust-analyzer’s error arrives first, it is rendered, and when clippy’s duplicate arrives later it is rendered too (the dedupe sees rust-analyzer’s and drops it, fine). The comment states the rule: when a diagnostic of the other tier arrives or goes later, the already rendered namespaces are out of date. For example, if one tier’s line disappears, the other’s, which was hidden as a duplicate, would stay hidden until it is rendered again. The handler on DiagnosticChanged fixes that by re-showing all of the buffer’s namespaces on the next tick. The redraw table is a per-buffer guard, so a burst of events in one tick causes a single re-render, and vim.schedule keeps the call out of the event itself. The spec group is named for it: "DiagnosticChanged re-render (xynovim_ux)".'),
    ...sec(r'blink.cmp: when a snippet must not expand'),
    ...code('lua', r'lua/config/ux.lua · lines 57-112', r'''
-- Completion -----------------------------------------------------------------

--- blink.cmp snippets provider guard: false after a `.` (method position),
--- inside strings and comments and in expression positions (call arguments,
--- struct literals, macro token trees: Enter on `bench` expanded `#[bench] fn`
--- inside `call(a, b`).
--- Whether the innermost bracket still open between the start of the (error) node and the
--- cursor is a `(` or `[`.
function M.unclosed_paren(node, ctx)
  local srow, scol = node:start()
  if srow ~= ctx.cursor[1] - 1 then
    return false
  end
  local stack = {}
  for ch in ctx.line:sub(scol + 1, ctx.cursor[2]):gmatch("[%(%)%[%]{}]") do
    if ch == "(" or ch == "[" or ch == "{" then
      stack[#stack + 1] = ch
    else
      stack[#stack] = nil
    end
  end
  return stack[#stack] == "(" or stack[#stack] == "["
end

local EXPRESSION_NODES = { arguments = true, field_initializer_list = true, token_tree = true }

function M.snippets_allowed(ctx)
  local before = ctx.line:sub(1, ctx.cursor[2])
  if before:match("[^%.]%.[%w_]*$") then
    return false
  end
  local ok, node = pcall(vim.treesitter.get_node, {
    bufnr = ctx.bufnr,
    pos = { ctx.cursor[1] - 1, math.max(ctx.cursor[2] - 1, 0) },
  })
  while ok and node do
    local t = node:type()
    local _, _, erow, ecol = node:range()
    -- a literal ends at its closing quote: the cursor behind it is outside
    local behind = t:find("literal$") and erow == ctx.cursor[1] - 1 and ecol <= ctx.cursor[2]
    if (t:find("string") or t:find("comment")) and not behind then
      return false
    end
    if t == "block" then
      break -- statement position (a closure body inside call arguments)
    end
    if EXPRESSION_NODES[t] then
      return false
    end
    if t == "ERROR" and M.unclosed_paren(node, ctx) then
      return false -- `call(a, be` while typing: the parser has no `arguments` node yet
    end
    node = node:parent()
  end
  return true
end'''),
    ...para('--', r'Snippets such as bench expanding to a whole #[bench] fn are useful at statement position and harmful elsewhere. The doc comment names the incident: pressing Enter on bench inside call(a, b expanded a function declaration in the middle of an argument list. The guard decides, for the cursor position, whether the snippet source may offer items at all. It is wired to the snippets provider through should_show_items in plugins/editing-ui.lua (line 67), and macro_tools.lua uses the same function for its own completion source (line 1295).'),
    ...para('--', r'The tests, in order: if the text before the cursor ends in a dot followed by optional identifier characters, with a character that is not a dot in front (so a range such as 0..n is not mistaken for a method call), it is a method position: no snippets. Then the function asks treesitter for the node just before the cursor and walks up the tree. Inside a string or a comment: no, with one exception, computed in the behind variable: a literal ends at its closing quote, and a cursor behind it on the same line is outside the literal. A block node means statement position, so the walk stops there and snippets are allowed; the comment names the case: "a closure body inside call arguments". Reaching an arguments node, a struct field initialiser list or a macro token tree means an expression position: no. And one more case for code in the middle of typing: when the parser has an ERROR node because the call is not closed yet, there is no arguments node to find, so unclosed_paren scans the characters from the start of the error node to the cursor with a small stack and reports whether the innermost bracket still open is a parenthesis or a square bracket (a curly brace means a block, where snippets are fine).'),
    ...para('--', r'A small documentation slip is visible in the listing. The doc comment of snippets_allowed (five lines about the dot, strings and comments) is above the doc comment of unclosed_paren, so the two blocks of text run together and snippets_allowed has no comment directly on it. The code is not affected. The tree walk is wrapped in pcall because get_node raises when there is no parser for the buffer, in which case the loop is skipped and the answer is true: with no syntax information, the guard does not take snippets away.'),
    ...sec(r'the right-click menu'),
    ...code('lua', r'lua/config/ux.lua · lines 114-139', r'''
-- Right-click menu --------------------------------------------------------

-- { menu path, <leader> suffix | Lua expression }
local RUST_MENU = {
  { "Rust.Rename", "lua vim.lsp.buf.rename()" },
  { "Rust.Find\\ Usages", "lua Snacks.picker.lsp_references()" },
  { "Rust.Refactor.Actions\\ \\.\\.\\.", "ra" },
  { "Rust.Refactor.Extract\\ Variable", "rv" },
  { "Rust.Refactor.Extract\\ Function", "rf" },
  { "Rust.Refactor.Extract\\ Constant", "rc" },
  { "Rust.Refactor.Extract\\ Module", "rM" },
  { "Rust.Refactor.Inline", "ri" },
  { "Rust.Expand\\ Macro", "rm" },
  { "Rust.Run\\ Target\\ \\.\\.\\.", "rX" },
}

local function rust_menu()
  vim.cmd("silent! aunmenu PopUp.Rust")
  if vim.bo.filetype ~= "rust" then
    return
  end
  for _, item in ipairs(RUST_MENU) do
    local rhs = item[2]:find("^lua ") and item[2] or ("lua require('config.ux').leader('" .. item[2] .. "')")
    vim.cmd(("anoremenu PopUp.%s <Cmd>%s<CR>"):format(item[1], rhs))
  end
end'''),
    ...para('--', r'Neovim’s right-click menu is the PopUp menu, and the MenuPopup autocmd fires just before it is shown. The module uses that: on every popup it removes its own Rust submenu (silent! aunmenu) and, only for Rust buffers, rebuilds it from a table. So the menu entries appear only where they make sense, and no stale entry survives a change of buffer. Each row is a menu path (spaces and dots escaped with backslashes for the :menu syntax; the dots in the path mean submenus) and either a Lua expression or a <leader> suffix.'),
    ...para('--', r'Suffixes are not turned into commands of their own. The header of leader() says why: "Press <leader><suffix> as if typed, so menu entries reuse the real keymaps (keymaps.lua) instead of duplicating their logic". The function feeds the keys with nvim_feedkeys and the mode string "mt" (remap, typed), so the menu entry for Extract Variable is literally <leader>rv, with whatever the key does today. Adding a refactoring key therefore never requires touching the menu logic, and a mapping that changes later changes the menu with it. The two entries that start with lua call the API directly, because they are not on a leader key.'),
    ...code('lua', r'lua/config/ux.lua · lines 5-9', r'''
--- Press <leader><suffix> as if typed, so menu entries reuse the real keymaps
--- (keymaps.lua) instead of duplicating their logic.
function M.leader(suffix)
  vim.api.nvim_feedkeys(vim.keycode("<leader>") .. suffix, "mt", false)
end'''),
    ...sec(r'the colourblind palette'),
    ...code('lua', r'lua/config/ux.lua · lines 141-190', r'''
-- Colourblind-safe diagnostics ---------------------------------------------

-- Okabe-Ito: distinguishable under deuteranopia, protanopia and tritanopia.
local OKABE_ITO = {
  Error = "#E06A0E", -- vermillion, lifted from Okabe-Ito #D55E00 (4.26:1 on the theme background) to 4.5:1 and more
  Warn = "#F0E442", -- yellow
  Info = "#56B4E9", -- sky blue
  Hint = "#009E73", -- bluish green
  Ok = "#0072B2", -- blue
}

local enabled = false

local function apply_palette()
  for kind, color in pairs(OKABE_ITO) do
    -- fg for text/sign/float groups, sp for underlines; virtual text/lines
    -- lose their theme-tinted bg (it was derived from the old colour).
    for _, prefix in ipairs({ "Diagnostic", "DiagnosticSign", "DiagnosticFloating", "DiagnosticVirtualText", "DiagnosticVirtualLines" }) do
      local name = prefix .. kind
      local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
      hl.fg = tonumber(color:sub(2), 16)
      if prefix:find("Virtual") then
        hl.bg = nil
      end
      vim.api.nvim_set_hl(0, name, hl)
    end
    local ul = vim.api.nvim_get_hl(0, { name = "DiagnosticUnderline" .. kind, link = false })
    ul.sp = tonumber(color:sub(2), 16)
    vim.api.nvim_set_hl(0, "DiagnosticUnderline" .. kind, ul)
  end
end

function M.colorblind(on)
  if on == nil then
    on = not enabled
  end
  enabled = on
  if on then
    apply_palette()
  elseif vim.g.colors_name then
    -- Re-run the colorscheme to drop the overrides; its ColorScheme event
    -- re-applies transparency etc.
    pcall(vim.cmd.colorscheme, vim.g.colors_name)
  end
  return enabled
end

function M.colorblind_enabled()
  return enabled
end'''),
    ...para('--', r'The default colours of error, warning, info and hint are red, yellow, blue and cyan-ish, and the red/green confusion of the common forms of colour-vision deficiency makes some of them hard to tell apart. The opt-in palette uses the Okabe-Ito set, which was designed to remain distinguishable under deuteranopia, protanopia and tritanopia. One value was adjusted by hand and the comment gives the numbers: Error uses #E06A0E, "lifted from Okabe-Ito #D55E00 (4.26:1 on the theme background) to 4.5:1 and more". The original vermillion fell just short of the 4.5:1 contrast threshold on this theme, so it was brightened until it passes. (The ratio before is given in the comment; the ratio after is stated only as "4.5:1 and more".)'),
    ...para('--', r'apply_palette sets the colour on five groups per kind. For the text, sign, floating and virtual-text groups it replaces the foreground; for the underline group it sets the special colour (sp), since underlines are drawn with sp; and for the virtual text and virtual lines it also clears the background, because that background was derived from the old colour and would clash with the new one. It reads each group with link = false, so a group that is only a link to another is resolved before it is changed, and it writes back the whole table to keep other attributes such as bold.'),
    ...para('--', r'Turning it off is the interesting part. There is no stored copy of the original highlights, so colorblind(false) simply re-runs the current colour scheme, whose own definitions replace the overrides; the comment adds that the scheme’s ColorScheme event re-applies things such as transparency. The function toggles when called without an argument and returns the new state, which keymaps.lua uses for a toggle key (lines 216 and 219) and the :ColorblindDiagnostics command prints.'),
    ...code('lua', r'lua/config/ux.lua · lines 217-248', r'''
  -- Re-apply after every colorscheme load (a theme switch may
  -- `highlight clear` first).
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      if enabled then
        apply_palette()
      end
    end,
  })
  vim.api.nvim_create_user_command("ColorblindDiagnostics", function()
    vim.notify("colourblind diagnostics " .. (M.colorblind() and "on" or "off"))
  end, { desc = "Toggle the Okabe-Ito diagnostic palette" })

  -- Opt in permanently with `vim.g.xynovim_colorblind = true` (set before
  -- this runs, e.g. at the top of options.lua).
  if vim.g.xynovim_colorblind then
    enabled = true
  end

  -- Neovide: no animations (same choice as the Snacks scroll/animate settings
  -- and the cursor), and a translucent background like transparency.lua.
  if vim.g.neovide then
    vim.g.neovide_position_animation_length = 0
    vim.g.neovide_scroll_animation_length = 0
    vim.g.neovide_cursor_animation_length = 0
    vim.g.neovide_cursor_trail_size = 0
    vim.g.neovide_cursor_animate_in_insert_mode = false
    vim.g.neovide_cursor_animate_command_line = false
    vim.g.neovide_opacity = 0.9
  end
end'''),
    ...para('--', r'Because a theme switch can clear highlights first, the ColorScheme autocmd re-applies the palette whenever it is on. The permanent opt-in is a global, vim.g.xynovim_colorblind = true, which must be set before setup() runs (the comment suggests the top of options.lua); setup only sets the enabled flag, and the palette itself is applied by the ColorScheme event of the colour scheme that loads afterwards. A commit in the history, e874f9f (2026-10-13, "Remove Omarchy support"), changed the comment above this autocmd: it used to mention the Omarchy theme hot reload, which did a highlight clear first, and now only says a theme switch may.'),
    ...sec(r'Neovide'),
    ...para('--', r'The last block is for the Neovide GUI and runs only when vim.g.neovide is set. It turns off every animation (position, scroll, cursor, cursor trail, and cursor animation in insert mode and the command line), "same choice as the Snacks scroll/animate settings and the cursor", and sets the window opacity to 0.9, "a translucent background like transparency.lua". The code states a preference for a steady screen: the same one that other files in this config express with disabled scrolling animations (see the page for lua/plugins/snacks-animated-scrolling-off.lua).'),
    ...sec(r'design decisions and trade-offs'),
    ...pt('--', r'callbacks in the config, not in the plugin specs', r'the plugin spec files stay short declarations, and the logic can be unit-tested by requiring config.ux. The price is that the logic is far from the option it serves.'),
    ...pt('--', r'rule-based dedupe instead of removing a source', r'turning one of the two tiers off would be simpler but would lose clippy’s lints or rust-analyzer’s speed. The key-based dedupe keeps both and hides only the repeated line, on the display side, without touching the diagnostics themselves; the filter lives in the virtual-text formatter only.'),
    ...pt('--', r'a guard that defaults to "yes"', r'snippets_allowed returns true whenever it cannot find a reason to say no (no parser, a nil node). A snippet that appears in a place where it should not is annoying; a snippet that vanishes everywhere because of a parser error would be worse.'),
    ...pt('--', r'reuse the keymaps', r'the menu is data and one function. It adds no behaviour that the keys do not already have.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/ux-menu-diagnostics-colourblind_spec.lua (53 it() blocks and 4 pending entries) has a describe per behaviour: ux.diagnostic_text, the dedupe across namespaces, what is kept because it is not a duplicate, the DiagnosticChanged re-render, <leader>cd, the right-click menu "PopUp.Rust", ux.leader, colourblind diagnostics, Neovide settings, and the surrounding editing-ui specs (noice, floats, the dashboard, which-key, pickers, lualine_x). The snippet guard has its own tests in tests/snippets-completion-injections_spec.lua, which includes a test that the snippets provider has should_show_items wired to ux.snippets_allowed.'),
    ...sec(r'history'),
    ...pt('--', r'bdd0225 · 2026-10-09', r'Roadmap step 11 wip: status, UX, health, CI, hygiene. First version.'),
    ...pt('--', r'99acd7e · 2026-10-13', r'Batch 4: editing and UI: "virtual text first line + dedupe", "snippet guard", "rounded floats".'),
    ...pt('--', r'e874f9f · 2026-10-13', r'Remove Omarchy support: only a comment changed in this file.'),
    ...pt('--', r'98c9bb4 · 2026-10-13', r'Final loop round 1: "trouble_lualine", "statusline" and the other findings.'),
    ...pt('--', r'a3d33c8 · 2026-10-13', r'Final loop round 2: "lint dedupe" (the LINT_CODES table).'),
    ...pt('--', r'f31e013 · 2026-10-14', r'Final loop round 4: "no snippets in expressions" (EXPRESSION_NODES and unclosed_paren).'),
  ],
);
