import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/ux-menu-diagnostics-colourblind_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'ux-menu-diagnostics-colourblind_spec.lua — the small comforts: diagnostics without duplicates, a right-click menu, a palette for colour blindness'),
    cm('--', r'dedupe across namespaces, coalesced re-rendering, Okabe-Ito colours that survive a theme switch, Neovide, noice and the dashboard'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/config/ux.lua, lua/plugins/editing-ui.lua (noice, dashboard, which-key, virtual text format) and lua/plugins/lualine.lua'),
    kv(r'language', r'Lua spec, 855 lines, 53 it() blocks, 4 pending, 17 describe() blocks'),
    kv(r'history', r'6 commits, 2026-10-13 to 2026-10-16'),
    ...sec(r'why this file exists'),
    ...para('--', r'There is no single feature in this spec. It is the place for the interface choices that make the editor calm: one line of one diagnostic at the end of a line, one entry per problem, a context menu that offers the Rust actions, colours that a colour-blind user can tell apart, and the dashboard that fits a small terminal. Each is small, and each had a bug that was found by using the editor, so each has a test with the symptom in its name.'),
    ...code('lua', r'tests/ux-menu-diagnostics-colourblind_spec.lua · lines 1-5', r'''
-- lua/config/ux.lua (diagnostic virtual text, right-click menu, colourblind
-- palette, Neovide), lua/plugins/editing-ui.lua (noice, dashboard, which-key,
-- virtual text format) and lua/plugins/lualine.lua.
local H = require("xynotest.helpers")
'''),
    ...sec(r'virtual text: first line plus the source'),
    ...para('--', r'diagnostic_text returns the first non-empty line of a message and the source in brackets, the bare text when there is no source, an empty string for an empty message, and reduces a 14-line clippy message to its first line. It is the virtual_text.format of the lspconfig options, which a test checks.'),
    ...sec(r'one problem, one line'),
    ...para('--', r'The language servers overlap: rust-analyzer and clippy (through bacon-ls) both report E0308 on the same line, and both would be shown. The dedupe works across namespaces and keeps the better one. The first test sets the clippy diagnostic on the lower namespace id with the message error[E0308]: mismatched types plus context, and no code field, and the rust-analyzer diagnostic on the higher one with the code E0308 and the text mismatched types. The clippy one gets no virtual text and the other shows mismatched types [rust-analyzer]. The second test is a field finding: the rust-analyzer lint name unsafe_op_in_unsafe_fn and clippy warning[E0133] are one problem that was shown twice. The remaining tests of the group: the code is read from the first line when the field is absent on both; without a code the key is the first line minus the error: prefix, case and trailing punctuation; a warning: prefix is stripped too; and a code on the higher id beats the lower one without a code. And what is not deduped: different keys on one line, the same key in the same namespace, different lines, an invalid buffer.'),
    ...code('lua', r'tests/ux-menu-diagnostics-colourblind_spec.lua · lines 127-150', r'''
  it("shows rust-analyzer's (code) over clippy's for the same E-code on a line", function()
    local buf = track(scratch())
    local a, b = two_ns()
    -- the clippy tier has the LOWER namespace id but no `code`
    vim.diagnostic.set(a, buf, {
      diag(1, "error[E0308]: mismatched types\n  --> src/main.rs:2\n  expected `u32`", { source = "bacon-ls" }),
    })
    vim.diagnostic.set(b, buf, { diag(1, "mismatched types", { code = "E0308", source = "rust-analyzer" }) })
    H.is_nil(text_of(buf, a), "clippy duplicate has no virtual text")
    H.eq("mismatched types [rust-analyzer]", text_of(buf, b))
  end)

  it("rust-analyzer's lint name unsafe_op_in_unsafe_fn and clippy's warning[E0133] are one problem (field test: shown twice)", function()
    local buf = track(scratch())
    local a, b = two_ns()
    vim.diagnostic.set(a, buf, {
      diag(1, "warning[E0133]: dereference of raw pointer is unsafe and requires unsafe block\n  --> src/lib.rs:2", { source = "bacon-ls" }),
    })
    vim.diagnostic.set(b, buf, {
      diag(1, "unsafe operation in unsafe function", { code = "unsafe_op_in_unsafe_fn", source = "rust-analyzer" }),
    })
    H.is_nil(text_of(buf, a), "clippy duplicate has no virtual text")
    H.eq("unsafe operation in unsafe function [rust-analyzer]", text_of(buf, b))
  end)'''),
    ...sec(r'one re-render'),
    ...para('--', r'When a diagnostics namespace changes, the virtual text of the other namespaces must be recomputed, because dedupe depends on both. DiagnosticChanged therefore schedules a vim.diagnostic.show for the buffer. The test sets diagnostics in two namespaces three times and requires that no full render happened synchronously, that exactly one happens after the schedule, and that the flag is reset so a later change renders again. A gone buffer at schedule time is ignored.'),
    ...code('lua', r'tests/ux-menu-diagnostics-colourblind_spec.lua · lines 269-286', r'''
  it("schedules one vim.diagnostic.show(nil, buf), coalescing several changes", function()
    local buf = track(scratch())
    local a, b = two_ns()
    vim.diagnostic.set(a, buf, { diag(0, "one", { source = "s1" }) })
    vim.diagnostic.set(b, buf, { diag(0, "two", { source = "s2" }) })
    vim.diagnostic.set(a, buf, { diag(1, "three", { source = "s1" }) })
    H.eq(0, full_renders(buf), "nothing synchronous")
    H.wait_for(function()
      return full_renders(buf) > 0
    end, 10000, "the scheduled re-render")
    vim.wait(100)
    H.eq(1, full_renders(buf))
    -- the flag is reset: a later change renders again
    vim.diagnostic.set(a, buf, { diag(0, "four", { source = "s1" }) })
    H.wait_for(function()
      return full_renders(buf) == 2
    end, 10000, "second render")
  end)'''),
    ...sec(r'the right-click menu'),
    ...para('--', r'A MenuPopup autocmd builds PopUp.Rust in Rust buffers only, removing a stale one in a toml buffer and rebuilding instead of duplicating. The test lists the ten leaf entries (Rename, Find Usages, four Refactor extracts with Actions and Inline, Expand Macro, Run Target). Rename and Find Usages call Lua directly; the others go through ux.leader, which feeds the leader key suffix, ra, rv, rf, rc, rM, ri, rm, rX, in mode mt. One test clicks Expand Macro and checks that it feeds leader r m and runs the real mapping.'),
    ...code('lua', r'tests/ux-menu-diagnostics-colourblind_spec.lua · lines 354-397', r'''
  it("builds 10 leaf entries in a Rust buffer", function()
    local items = popup(track(rust_buf()))
    H.eq(1, #items)
    local names = menu_names(items[1].submenus, "Rust")
    table.sort(names)
    local want = {
      "Rust.Rename",
      "Rust.Find Usages",
      "Rust.Refactor.Actions ...",
      "Rust.Refactor.Extract Variable",
      "Rust.Refactor.Extract Function",
      "Rust.Refactor.Extract Constant",
      "Rust.Refactor.Extract Module",
      "Rust.Refactor.Inline",
      "Rust.Expand Macro",
      "Rust.Run Target ...",
    }
    table.sort(want)
    H.eq(want, names)
    H.eq(10, #leafs(items[1].submenus))
  end)

  it("Rename and Find Usages call lua directly, the others go through ux.leader", function()
    local items = popup(track(rust_buf()))
    local by = {}
    for _, it in ipairs(leafs(items[1].submenus)) do
      by[it.name:gsub("\\", "")] = it.mappings.n.rhs
    end
    H.match(by["Rename"], "lua vim.lsp.buf.rename()", true)
    H.match(by["Find Usages"], "lua Snacks.picker.lsp_references()", true)
    local suffix = {
      ["Actions ..."] = "ra",
      ["Extract Variable"] = "rv",
      ["Extract Function"] = "rf",
      ["Extract Constant"] = "rc",
      ["Extract Module"] = "rM",
      ["Inline"] = "ri",
      ["Expand Macro"] = "rm",
      ["Run Target ..."] = "rX",
    }
    for name, s in pairs(suffix) do
      H.match(by[name], "require('config.ux').leader('" .. s .. "')", true, name)
    end
  end)'''),
    ...sec(r'colourblind diagnostics'),
    ...para('--', r'The colour-blind mode is off by default. When on, diagnostics use Okabe-Ito colours: error #e06a0e, warning #f0e442, info #56b4e9, hint #009e73, ok #0072b2. The mode survives a colourscheme change (habamax) and highlight clear followed by tokyonight-moon, and turning it off re-runs the colourscheme and restores the island colours; error returns to #f75464. colorblind(nil) toggles, true and false set, the new state is returned; :ColorblindDiagnostics toggles and notifies; leader u B is a Snacks toggle on the same state; vim.g.xynovim_colorblind = true starts it on.'),
    ...code('lua', r'tests/ux-menu-diagnostics-colourblind_spec.lua · lines 483-515', r'''
  it("uses the Okabe-Ito colours when on", function()
    H.eq(true, ux.colorblind(true))
    H.eq(true, ux.colorblind_enabled())
    check_on()
    H.eq("#e06a0e", hexc(hl("DiagnosticError").fg))
    H.eq("#f0e442", hexc(hl("DiagnosticWarn").fg))
    H.eq("#56b4e9", hexc(hl("DiagnosticInfo").fg))
    H.eq("#009e73", hexc(hl("DiagnosticHint").fg))
    H.eq("#0072b2", hexc(hl("DiagnosticOk").fg))
  end)

  it("survives :colorscheme habamax", function()
    ux.colorblind(true)
    vim.cmd("colorscheme habamax")
    H.eq("habamax", vim.g.colors_name)
    check_on()
  end)

  it("survives `highlight clear` + :colorscheme tokyonight-moon", function()
    ux.colorblind(true)
    vim.cmd("highlight clear")
    vim.cmd("colorscheme tokyonight-moon")
    H.eq("tokyonight-moon", vim.g.colors_name)
    check_on()
  end)

  it("off re-runs the colourscheme and restores the island colours", function()
    ux.colorblind(true)
    H.eq("#e06a0e", hexc(hl("DiagnosticError").fg))
    H.eq(false, ux.colorblind(false))
    H.eq("island-dark", vim.g.colors_name)
    H.eq("#f75464", hexc(hl("DiagnosticError").fg))
  end)'''),
    ...sec(r'Neovide'),
    ...para('--', r'Without g:neovide the setup sets nothing. With it, animations are turned off (position, scroll, cursor trail and cursor animations all 0 or false) and opacity is 0.9.'),
    ...code('lua', r'tests/ux-menu-diagnostics-colourblind_spec.lua · lines 604-614', r'''
  it("sets no animations and 0.9 opacity with g:neovide", function()
    vim.g.neovide = true
    ux.setup()
    H.eq(0, vim.g.neovide_position_animation_length)
    H.eq(0, vim.g.neovide_scroll_animation_length)
    H.eq(0, vim.g.neovide_cursor_animation_length)
    H.eq(0, vim.g.neovide_cursor_trail_size)
    H.eq(false, vim.g.neovide_cursor_animate_in_insert_mode)
    H.eq(false, vim.g.neovide_cursor_animate_command_line)
    H.eq(0.9, vim.g.neovide_opacity)
  end)'''),
    ...sec(r'noice, floats and the dashboard'),
    ...para('--', r'noice enables lsp_doc_border; the showcmd handler is wrapped once and a second evaluation does not wrap it again; an empty showcmd removes the message. winborder is rounded and pumblend 0. The dashboard has four sections: header, keys for tall windows, keys for short ones and startup. The tall section is enabled from 2n + 11 rows where n is the number of preset entries (39 with the 14 of the time, the test title says), and the short one below; the test checks at 24 rows, one below the limit, at the limit and at 50. At 80x24 the last entry and the footer are visible in tmux.'),
    ...code('lua', r'tests/ux-menu-diagnostics-colourblind_spec.lua · lines 684-699', r'''
  it("enable the right keys section from 2n + 11 rows (n entries: 39 with today's 14) and above/below", function()
    local o = opts_of("snacks.nvim")
    local s = o.dashboard.sections
    local need = 2 * #o.dashboard.preset.keys + 11
    local lines = vim.o.lines
    local ok, err = pcall(function()
      for _, n in ipairs({ 24, need - 1, need, 50 }) do
        vim.o.lines = n
        local tall = n >= need
        H.eq(tall, s[2].enabled(), "tall section at " .. n)
        H.eq(not tall, s[3].enabled(), "short section at " .. n)
      end
    end)
    vim.o.lines = lines
    H.ok(ok, tostring(err))
  end)'''),
    ...sec(r'pickers'),
    ...para('--', r'The file and grep pickers exclude an anchored /target without needing a .gitignore. The rust kind filter of the document outline contains Object, for impl blocks, on top of the default. A window under 30 lines and 120 columns gets the preview-less select layout, because the preview overdrew the border at 80x24. The test takes the picker layout preset out of the plugin spec, calls it at four sizes and requires select, vertical, default and default for 80x24, 80x40, 160x24 and 160x50.'),
    ...code('lua', r'tests/ux-menu-diagnostics-colourblind_spec.lua · lines 793-813', r'''
  it("a window under 30 lines and 120 columns gets the preview-less select layout (80x24 border overdraw)", function()
    local opts = {}
    for _, spec in ipairs(dofile(H.repo .. "/lua/plugins/editing-ui.lua")) do
      if spec[1] == "folke/snacks.nvim" and type(spec.opts) == "function" then
        spec.opts({}, opts)
      end
    end
    local preset = opts.picker and opts.picker.layout and opts.picker.layout.preset
    H.eq("function", type(preset))
    local cols, lines = vim.o.columns, vim.o.lines
    local function at(c, l)
      vim.o.columns, vim.o.lines = c, l
      return preset()
    end
    local ok, a, b, c, d = pcall(function()
      return at(80, 24), at(80, 40), at(160, 24), at(160, 50)
    end)
    vim.o.columns, vim.o.lines = cols, lines
    H.ok(ok, tostring(a))
    H.eq({ "select", "vertical", "default", "default" }, { a, b, c, d })
  end)'''),
    ...sec(r'which-key and lualine'),
    ...para('--', r'which-key names leader 9 as 99 (agent) and registers the leader t (test) and leader a (ai) groups, whose popup was missing when typed fast. lualine_x starts with the lsp_status component and hides it when empty; the real component is empty in a non-Rust buffer.'),
    ...sec(r'what is elsewhere'),
    ...para('--', r'Four pending entries point to other places: unsafe underline highlighting (theme-island_spec.lua); cargo-machete findings not doubled and the cargo-deny wildcard line (git-lint-supply-chain_spec.lua); the leak of background=light in leader u C previews of light themes (a documented README limitation); and v:errmsg E31 when opening markdown (documented nvim undo_ftplugin behaviour).'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created. 98c9bb4, a3d33c8 (2026-10-13) and f31e013 (2026-10-14) :: field test rounds.'),
    ...pt('--', r'fc2062a (2026-10-14)', r'CI on a clean machine. d163480 (2026-10-16) :: "New Rust Binary, Library and Workspace entries on the dashboard"; this spec was touched by it (the dashboard test counts preset entries).'),
  ],
);
