import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-new.nvim/tests/dashboard_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'tests/dashboard_spec.lua — list surgery, specified'),
    cm('--', r'a stock dashboard in, four entries out, no snacks.nvim needed'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'tests', r'lua/xyno_new/dashboard.lua via xyno_new.dashboard_keys'),
    kv(r'size', r'104 lines, 7 cases'),
    kv(r'needs', r'nothing: the dashboard keys are plain tables'),
    kv(r'history', r'added in 1de2687 (2026-10-22)'),
    ...sec(r'the fixture'),
    ...code('lua', r'tests/dashboard_spec.lua · lines 3-29', r'''
local H = require("xyno_new_test.helpers")
local N = require("xyno_new")

local function stock()
  return {
    { icon = "s1", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
    { icon = "s2", key = "n", desc = "New File", action = ":ene | startinsert" },
    { icon = "s3", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
    { icon = "s4", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
    { icon = "s5", key = "L", desc = "Lazy", action = ":Lazy" },
    { icon = "s6", key = "q", desc = "Quit", action = ":qa" },
  }
end

local WANT = {
  { "b", "New Rust Binary", ":RustNewBin" },
  { "i", "New Rust Library", ":RustNewLib" },
  { "w", "New Rust Workspace", ":RustNewWorkspace" },
}

local function positions(keys)
  local pos = {}
  for i, k in ipairs(keys) do
    pos[k.desc] = i
  end
  return pos
end'''),
    ...para('--', r'stock() returns a fresh six-entry list every time, so one case cannot disturb another. The icons are placeholders s1 to s6, which is useful: the uniqueness check on icons then also guards against one of the plugin’s icons being equal to a stock one. The keys are the LazyVim-like f n g r L q (the list omits some of the keys of LazyVim’s stock dashboard). WANT holds the three Rust entries with key, description and action. positions() turns a list into a description-to-index map, used for order assertions.'),
    ...sec(r'the main case'),
    ...code('lua', r'tests/dashboard_spec.lua · lines 31-56', r'''
describe("dashboard_keys", function()
  it("three Rust entries and the egui entry: unique keys, distinct icons, in order, before Quit", function()
    local keys = N.dashboard_keys(stock())
    local seen, icons = {}, {}
    for _, k in ipairs(keys) do
      H.is_nil(seen[k.key], "duplicate dashboard key " .. tostring(k.key))
      seen[k.key] = true
      H.is_nil(icons[k.icon or ""], "duplicate icon for " .. tostring(k.desc))
      icons[k.icon or ""] = true
    end
    local pos = positions(keys)
    for n, w in ipairs(WANT) do
      local i = H.ok(pos[w[2]], w[2] .. " is in the list")
      H.eq(w[1], keys[i].key)
      H.eq(w[3], keys[i].action)
      H.ok(keys[i].icon and #keys[i].icon > 0)
      if n > 1 then
        H.eq(pos[WANT[n - 1][2]] + 1, i, "the three are consecutive")
      end
    end
    H.eq("e", keys[pos["New egui Project"]].key)
    H.eq(":EguiNew", keys[pos["New egui Project"]].action)
    H.eq(pos["New Rust Workspace"] + 1, pos["New egui Project"], "the egui entry follows the three")
    H.eq(pos["Quit"] - 1, pos["New egui Project"], "the egui entry stays right before Quit")
    H.eq(10, #keys)
  end)'''),
    ...para('--', r'One long case asserts the full contract. For every entry, keys must be unique and icons must be distinct (H.is_nil on the seen table, so a duplicate fails with its name). Then each wanted Rust entry must be present, with the right key and action, with a non-empty icon, and each must sit exactly one slot after its predecessor: the three are consecutive. The egui entry has key e and action :EguiNew, follows the workspace entry, and sits right before Quit. The total length is 10, which also catches an accidental double insertion.'),
    ...sec(r'order, idempotence, identity'),
    ...code('lua', r'tests/dashboard_spec.lua · lines 58-78', r'''
  it("the existing entries are unchanged and keep their order", function()
    local keys = N.dashboard_keys(stock())
    local order = {}
    for _, k in ipairs(keys) do
      order[#order + 1] = k.key
    end
    H.eq({ "f", "n", "g", "r", "L", "b", "i", "w", "e", "q" }, order)
  end)

  it("is idempotent", function()
    local keys = N.dashboard_keys(stock())
    local again = N.dashboard_keys(vim.deepcopy(keys))
    H.eq(keys, again)
    H.eq(keys, N.dashboard_keys(keys))
  end)

  it("edits the list in place and returns it", function()
    local keys = stock()
    H.ok(N.dashboard_keys(keys) == keys)
    H.eq(10, #keys)
  end)'''),
    ...para('--', r'The ordering case compares the full key sequence against f, n, g, r, L, b, i, w, e, q, so existing entries are unchanged and keep their order. The idempotence case calls the function on its own output twice: once on a deep copy and once on the list itself, and compares for equality both times. The identity case insists on the in-place contract: the returned table is the argument (== on tables is identity in Lua) and its length is 10.'),
    ...sec(r'the odd shapes'),
    ...code('lua', r'tests/dashboard_spec.lua · lines 80-104', r'''
  it("without Quit the entries go last; without an argument a new list comes back", function()
    local keys = N.dashboard_keys({ { key = "f", desc = "Find File", action = ":x" } })
    H.eq({ "f", "b", "i", "w", "e" }, vim.tbl_map(function(k)
      return k.key
    end, keys))
    local fresh = N.dashboard_keys()
    H.eq(4, #fresh)
  end)

  it("a key `e` already in use is respected: no egui entry, the Rust entries stay", function()
    local keys = stock()
    table.insert(keys, 1, { key = "e", desc = "Explorer", action = ":Ex" })
    N.dashboard_keys(keys)
    local pos = positions(keys)
    H.is_nil(pos["New egui Project"])
    H.ok(pos["New Rust Binary"])
    H.eq(pos["Quit"] - 3, pos["New Rust Binary"])
  end)

  it("the entries do not alias the module tables", function()
    local keys = N.dashboard_keys(stock())
    keys[6].desc = "changed"
    H.eq("New Rust Binary", require("xyno_new.dashboard").rust_entries[1].desc)
  end)
end)'''),
    ...para('--', r'Three robustness cases. Without Quit the entries go last, giving f, b, i, w, e. Without an argument a fresh list of four comes back. With a key e already in use by another entry, no egui entry is added, but the Rust entries still appear, three places before Quit: they are placed relative to Quit, since there is no egui entry to anchor on. The last case mutates a returned entry (keys[6].desc) and checks that the module’s own rust_entries[1] is unchanged: deep copies, not aliases.'),
    ...sec(r'what these tests can and cannot say'),
    ...para('--', r'They prove the list logic. They do not prove that snacks.nvim accepts the entries, that the icons render in a given font, or that the dashboard fits a short terminal. The README states that the terminal rendering was checked in xynovim’s own specs. The d163480 commit in xynovim also changed the layout thresholds of the dashboard for the larger entry count, which is configuration, not plugin, and so has no test here.'),
    ...sec(r'history'),
    ...para('--', r'Added in 1de2687 on 2026-10-22.'),
  ],
);
