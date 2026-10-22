import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/smoke_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'smoke_spec.lua — does the whole config start without a sound'),
    cm('--', r'six checks that a clean start prints nothing, sets no error and loads the plugin set'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'harness proof and first line of defence: the config starts clean in headless nvim'),
    kv(r'language', r'Lua spec, 39 lines, 6 it() blocks, 1 describe() blocks'),
    kv(r'needs', r'nothing external (the last test opens standalone.rs but only checks messages)'),
    kv(r'size', r'39 lines'),
    ...sec(r'why this file exists'),
    ...para('--', r'Before any feature is tested, one question has to be answered: did the editor start? A broken lazy.nvim spec, a plugin that fails to load or an option set to a bad value would show up as an error message or a missing colourscheme. smoke_spec asserts the absence of such symptoms. It also proves the harness: because it passes, the runner waited for VimEnter, loaded the config and had a working describe/it.'),
    ...code('lua', r'tests/smoke_spec.lua · lines 1-2', r'''
-- Harness proof: the full config starts clean in a headless nvim.
local H = require("xynotest.helpers")'''),
    ...sec(r'silence is a requirement'),
    ...para('--', r'The first two tests say that startup prints no messages (H.messages() trimmed is the empty string) and that vim.v.errmsg is empty. For a headless nvim started to run tests, any message is a defect: a deprecation warning or a plugin complaining is something the user would also see.'),
    ...code('lua', r'tests/smoke_spec.lua · lines 4-11', r'''
describe("startup", function()
  it("prints no messages", function()
    H.eq("", vim.trim(H.messages()))
  end)

  it("sets no error message", function()
    H.eq("", vim.v.errmsg)
  end)'''),
    ...sec(r'the theme is the one the config says'),
    ...para('--', r'After startup the colourscheme must be island-dark and background must be dark. If the theme failed to set the scheme the test would fail even though no message was printed. theme-island_spec.lua is where the theme itself is tested.'),
    ...code('lua', r'tests/smoke_spec.lua · lines 13-16', r'''
  it("uses the island-dark colourscheme on a dark background", function()
    H.eq("island-dark", vim.g.colors_name)
    H.eq("dark", vim.o.background)
  end)'''),
    ...sec(r'lazy.nvim loaded the plugin set'),
    ...para('--', r'stats().count must exceed 50 and the lazy spec must have no notifications. The number 50 is a floor, not an exact count: it detects a spec file that silently stopped being imported without needing an edit every time a plugin is added. spec.notifs is where lazy.nvim records problems found while parsing the specs (a bad spec returns there rather than printing), so asserting it is empty catches errors that never reach the message area.'),
    ...code('lua', r'tests/smoke_spec.lua · lines 18-25', r'''
  it("loaded lazy.nvim with the plugin set", function()
    local stats = require("lazy").stats()
    H.ok(stats.count > 50, "plugin count " .. stats.count)
  end)

  it("has no spec notifications from lazy.nvim", function()
    H.eq({}, require("lazy.core.config").spec.notifs)
  end)'''),
    ...sec(r'opening a file fires VeryLazy quietly'),
    ...para('--', r'The last test clears messages, opens the standalone.rs fixture, checks that the filetype is rust and that no messages appeared. On Windows it strips one known notice before comparing: rustaceanvim says that no project root was found and it starts rust-analyzer in detached/standalone mode. The comment says that on the Windows runner it arrives within the window and elsewhere later. So the Windows exception is a documented timing difference, not a hidden failure.'),
    ...code('lua', r'tests/smoke_spec.lua · lines 27-39', r'''
  it("opens a buffer and fires VeryLazy without messages", function()
    H.clear_messages()
    H.open(H.fixture("standalone.rs"))
    H.eq("rust", vim.bo.filetype)
    local msgs = vim.trim(H.messages())
    if vim.fn.has("win32") == 1 then
      -- rustaceanvim's own notice for a lone .rs file (no Cargo.toml above it);
      -- on the Windows runner it arrives within the window, elsewhere later
      msgs = vim.trim((msgs:gsub("rustaceanvim:%s*No project root found%.%s*Starting rust%-analyzer client in detached/standalone mode[^\n]*", "")))
    end
    H.eq("", msgs)
  end)
end)'''),
    ...sec(r'design notes'),
    blank,
    ...pt('--', r'It never uses Rust tooling', r'so it can run everywhere, including the Windows and macOS platforms workflow.'),
    ...pt('--', r'Floors, not equalities', r'the plugin count check is robust against growth of the plugin list.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'cf2b8e1 (2026-10-13)', r'created as the harness proof.'),
    ...pt('--', r'6524272 (2026-10-21)', r'"Windows/macOS run 39640256853 fixes", the only later commit that touches the file.'),
  ],
);
