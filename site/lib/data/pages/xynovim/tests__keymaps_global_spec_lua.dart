import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/keymaps-global_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'keymaps-global_spec.lua — a keymap is a promise, so the suite scans the source for broken ones'),
    cm('--', r'descriptions, laziness, shadowing between Rust and non-Rust buffers, and a scanner that proves no key is defined twice'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/config/keymaps.lua and the keys of diffview, coverage, ninety-nine, harpoon, editing-ui, navigation and dap, plus the LazyVim keys the enabled extras should provide'),
    kv(r'language', r'Lua spec, 798 lines, 40 it() blocks, 12 describe() blocks, 400 second timeout'),
    kv(r'needs', r'rust-analyzer only for the tests that look at buffer-local Rust maps (they skip without it)'),
    kv(r'sibling', r'keymaps-rust_spec.lua tests what the Rust keys do; this file tests that keys exist, are unique, lazy and described'),
    kv(r'history', r'6 commits, 2026-10-13 to 2026-10-16'),
    ...sec(r'why this file exists'),
    ...para('--', r'A keymap fails silently. A plugin spec that changed its key table, a LazyVim extra that took the same lhs, a buffer map that shadows a global one: nothing prints an error, the key just does something else. The spec records the contract of the leader keys in three ways. It looks at the live editor with maparg. It checks that plugins that are driven by keys stay unloaded until the key is used. And it scans the repository sources to prove that no key is defined twice and that the descriptions in the sources are the descriptions that are live. The header lists what it covers.'),
    ...code('lua', r'tests/keymaps-global_spec.lua · lines 1-5', r'''
-- xyno-timeout: 400
-- Global keymaps of this repo (lua/config/keymaps.lua, diffview, coverage,
-- ninety-nine, harpoon, editing-ui, navigation, dap) and the LazyVim keys the
-- enabled extras are expected to provide. Needs rust-analyzer only for the
-- tests that look at buffer-local Rust maps (they skip without it).'''),
    ...sec(r'reading maps and lazy keys'),
    ...para('--', r'md(lhs, mode) is maparg with the dict form, so a test reads desc, buffer flag and callback. lazy_keys(name) reads a plugin spec from lazy.core.config and returns its key table, so a test can say that a key is a lazy key of that plugin. Having both views allows two claims at once: the key is declared with the plugin and the live map has the same description.'),
    ...code('lua', r'tests/keymaps-global_spec.lua · lines 8-24', r'''
local leader = vim.g.mapleader or " "

--- Map dictionary (maparg) for `lhs` ("<leader>" expands) in `mode`, {} if unmapped.
local function md(lhs, mode)
  return vim.fn.maparg(lhs, mode or "n", false, true)
end

local function plugin(name)
  return require("lazy.core.config").plugins[name]
end

--- lazy key specs of a plugin: { lhs, mode (string|table|nil), desc }.
local function lazy_keys(name)
  local p = plugin(name)
  H.ok(p, "plugin " .. name .. " is not in the spec")
  local out = {}
  for _, k in ipairs(p.keys or {}) do'''),
    ...sec(r'keys keep plugins asleep'),
    ...para('--', r'The first block checks that harpoon, nvim-coverage and 99 stay unloaded after startup. A key table that loads the plugin at startup would cost start time; the keys must be lazy keys. A later block checks that coverage keys are present with their descriptions while nvim-coverage stays unloaded.'),
    ...sec(r'the colliding <leader>r'),
    ...para('--', r'In Rust buffers the leader r group holds refactoring commands. In other filetypes a typo on this group could damage text: the field test found that pressing space r v in Cargo.toml turned name into nvme, because r and v were taken as Vim commands. The fix is a set of stubs on every unbound leader r key, with the description which_key_ignore, and the test is a reproduction: it opens Cargo.toml, puts the cursor on the name line, checks that there is no leader r leaf map (its comment says a leaf blocking in getcharstr made which-key skip its popup), presses leader r v and leader r r and requires that the buffer is unchanged and not modified, that two notifications were shown and the first says Rust buffers only, and that the same press in visual mode leaves the selection alone.'),
    ...code('lua', r'tests/keymaps-global_spec.lua · lines 465-489', r'''
  it("an unbound <leader>r<key> in Cargo.toml notifies instead of replacing a character (<Space>rv made `name` into `nvme`)", function()
    local dir = H.fixture("basic")
    H.open(dir .. "/Cargo.toml")
    local before = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local l = vim.fn.search("^name", "cw")
    H.ok(l > 0)
    vim.api.nvim_win_set_cursor(0, { l, 0 })
    -- per-key stubs, no `<leader>r` leaf: a leaf blocking in getcharstr() made which-key skip its popup
    H.eq(0, next(md("<leader>r", "n")) and 1 or 0, "no <leader>r leaf mapping")
    H.eq("which_key_ignore", md("<leader>rv", "n").desc)
    H.eq("which_key_ignore", md("<leader>rv", "x").desc)
    H.eq("which_key_ignore", md("<leader>r/", "n").desc)
    local cap = H.capture_notify()
    H.feed("<leader>rv")
    H.feed("<leader>rr")
    cap.restore()
    H.eq(before, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    H.not_ok(vim.bo.modified)
    H.eq(2, #cap.list)
    H.match(cap.list[1].msg, "Rust buffers only", true)
    -- a visual-mode press: the selection is not touched either
    H.feed("v<leader>rv")
    H.eq(before, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    H.feed("<Esc>")
  end)'''),
    ...sec(r'shadowing is a decision, not an accident'),
    ...para('--', r'Some keys are different in Rust buffers on purpose. In a Rust buffer leader d r is rustaceanvim Rust Debuggables, which shadows the global dap REPL toggle; in a non-Rust buffer it is the dap Toggle REPL. The test waits for the buffer-local map, requires Rust Debuggables in its description, and then looks up the global map in the full list of normal-mode maps to require that the global one is still Toggle REPL. Neighbouring tests do the same for leader c R (the config restores LazyVim Rename File as a buffer map after rust-analyzer attaches), for the insert-mode apostrophe (unpaired in Rust, untouched elsewhere) and for ctrl-S.'),
    ...code('lua', r'tests/keymaps-global_spec.lua · lines 695-709', r'''
  it("<leader>dr is rustaceanvim's 'Rust Debuggables' here (shadows the REPL toggle)", function()
    local m = H.wait_for(function()
      return bmap("<leader>dr", "n")
    end, 15000, "buffer-local <leader>dr")
    H.match(m.desc or "", "Rust Debuggables", true)
    -- the global one is the dap REPL toggle
    local g
    for _, k in ipairs(vim.api.nvim_get_keymap("n")) do
      if k.lhs == " dr" or k.lhs == "<Space>dr" then
        g = k
      end
    end
    H.ok(g, "global <leader>dr")
    H.eq("Toggle REPL", g.desc)
  end)'''),
    ...sec(r'the scanner that finds duplicates'),
    ...para('--', r'The uniqueness block does something unusual for a test: it parses the repository Lua sources. scan() lists every lua, after and plugin file, walks the lines and recognises a lazy key table entry that begins with a quoted string starting with a less-than sign. When the entry spans several lines, up to 30, it accumulates text until it finds a desc. It reads the modes either from a mode table or a single mode string, defaulting to normal, and records whether the entry has a filetype. For the Rust attach block of keymaps.lua it matches the map(...) calls with a mode list or a single mode and records them with buffer scope. The test then requires that no triple of scope, mode and lhs appears twice, naming both files in the failure message.'),
    ...code('lua', r'tests/keymaps-global_spec.lua · lines 552-621', r'''
describe("keymap uniqueness", function()
  local function modes_of(text)
    local mt = text:match("mode%s*=%s*(%b{})")
    local modes = {}
    if mt then
      for m in mt:gmatch('"(%a+)"') do
        modes[#modes + 1] = m
      end
    else
      modes[1] = text:match('mode%s*=%s*"(%a+)"') or "n"
    end
    return modes
  end

  --- Every keymap this repo defines, found in the sources:
  --- { file, scope, mode, lhs, desc, ft }.
  local function scan()
    local out = {}
    local files = vim.fn.globpath(H.repo .. "/lua", "**/*.lua", false, true)
    vim.list_extend(files, vim.fn.globpath(H.repo .. "/after", "**/*.lua", false, true))
    vim.list_extend(files, vim.fn.globpath(H.repo .. "/plugin", "**/*.lua", false, true))
    for _, f in ipairs(files) do
      local rel = f:gsub("\\", "/"):sub(#H.repo + 2)
      local lines = vim.fn.readfile(f)
      local i = 1
      while i <= #lines do
        -- lazy keys: `{ "<lhs>", rhs, mode = .., desc = ".." }`, possibly over several lines
        local lhs = lines[i]:match('^%s*{%s*"(<[^"]+)"') or lines[i]:match('^%s*"(<[^"]+)",')
        if lhs and not lines[i]:find("keymap") then
          local acc, j = lines[i], i
          while not acc:find('desc%s*=%s*"') and j < i + 30 and j < #lines do
            j = j + 1
            acc = acc .. "\n" .. lines[j]
          end
          local desc = acc:match('desc%s*=%s*"([^"]+)"')
          if desc then
            for _, m in ipairs(modes_of(acc)) do
              out[#out + 1] = { file = rel, scope = "global", mode = m, lhs = lhs, desc = desc, ft = acc:find("ft%s*=") ~= nil }
            end
          end
        end
        i = i + 1
      end
      -- map(mode, lhs, rhs, desc) of the Rust attach block: buffer scope
      if rel == "lua/config/keymaps.lua" then
        local text = table.concat(lines, "\n")
        for modespec, lhs in text:gmatch('map%(%s*(%b{}),%s*"([^"]+)"') do
          for m in modespec:gmatch('"(%a+)"') do
            out[#out + 1] = { file = rel, scope = "buffer", mode = m, lhs = lhs, desc = "(rust attach)" }
          end
        end
        for m, lhs in text:gmatch('map%(%s*"(%a+)",%s*"([^"]+)"') do
          out[#out + 1] = { file = rel, scope = "buffer", mode = m, lhs = lhs, desc = "(rust attach)" }
        end
      end
    end
    return out
  end

  it("no (scope, mode, lhs) is defined twice in the repo's sources", function()
    local seen, dup = {}, {}
    for _, e in ipairs(scan()) do
      local key = ("%s %s %s"):format(e.scope, e.mode, e.lhs)
      if seen[key] then
        dup[#dup + 1] = ("%s: %s (%s and %s)"):format(key, e.desc, seen[key].file, e.file)
      end
      seen[key] = e
    end
    H.eq({}, dup)
  end)'''),
    ...sec(r'sources and live maps must agree'),
    ...para('--', r'A second use of the scanner: every global lazy key of six plugin files, filtered to those without a filetype, is looked up with maparg after opening a Rust file. The description of the live map must equal the description in the source, so anything that overrides a key later changes the result. The test also requires that at least 25 keys were scanned, so a broken scanner cannot make the test pass by finding nothing.'),
    ...code('lua', r'tests/keymaps-global_spec.lua · lines 623-644', r'''
  it("every global lazy key of this repo is live with the desc its source gives (nothing overrides it)", function()
    H.open(H.fixture("standalone.rs"))
    local mine = {}
    for _, f in ipairs({ "diffview", "coverage", "ninety-nine", "harpoon", "navigation", "dap" }) do
      mine["lua/plugins/" .. f .. ".lua"] = true
    end
    local n, bad = 0, {}
    for _, e in ipairs(scan()) do
      if e.scope == "global" and not e.ft and mine[e.file] then
        local m = md(e.lhs, e.mode)
        n = n + 1
        if (m.desc or "") ~= e.desc then
          bad[#bad + 1] = ("%s %s: source %q, live %q"):format(e.mode, e.lhs, e.desc, m.desc)
        end
      end
    end
    H.ok(n >= 25, "scanned only " .. n .. " keys")
    H.eq({}, bad)
  end)
end)

-- ------------------------------------------------------------------ Rust buffers'''),
    ...sec(r'groups and extras'),
    ...para('--', r'Further blocks: Diffview keys (leader g v runs :DiffviewOpen; g F is :DiffviewFileHistory on the file, and on a selection in visual mode; g V opens origin/HEAD...HEAD preferring it over main and master, falls back to origin/main and then origin/master, and warns when none exists); the 99 keys, each described as 99: text, with leader 9 v v visual only; harpoon with its descriptions; leader a owned by claudecode, not harpoon; LazyVim extras (surround gsa and friends, flash, todo-comments, inc-rename, kulala in an .http buffer); and the colourscheme picker, which must be applicable to island-dark without error and without changing the scheme.'),
    ...sec(r'health is recorded, not asserted'),
    ...para('--', r'Two tests are informational. The which-key health check for leader r keys is marked env dependent, and the README claim that gc overlaps gcc, gco and gcO is not reproduced, so the test records the result and does not fail. The spec distinguishes facts it asserts from observations it only notes.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created with the suite.'),
    ...pt('--', r'98c9bb4, 3f868dd (2026-10-13)', r'field test fixes, among them "global leader-r catch-all" and "which-key key stubs".'),
    ...pt('--', r'25086fd (2026-10-14)', r'"leader-r which-key popup".'),
    ...pt('--', r'fc2062a (2026-10-14)', r'CI on a clean machine. 9641d08 (2026-10-16) :: Windows drive letter.'),
  ],
);
