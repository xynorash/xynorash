import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-new.nvim/lua/xyno_new/dashboard.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'lua/xyno_new/dashboard.lua — four entries, placed with care'),
    cm('--', r'list surgery on snacks.nvim’s dashboard keys, idempotent by construction'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'insert New Rust Binary / Library / Workspace / egui into a keys list'),
    kv(r'language', r'Lua, 64 lines, pure list manipulation (no snacks needed)'),
    kv(r'public', r'keys(keys?), rust_entries, egui_entry'),
    kv(r'shape', r'opt-in: nothing runs unless xyno_new.dashboard_keys(keys) is called'),
    kv(r'origin', r'merged from two lazy.nvim plugin specs in xynovim'),
    ...sec(r'why this file exists'),
    ...para('--', r'In xynovim there were two small files in lua/plugins, egui.lua (added in ddc51eb, 2026-10-15) and rust-new.lua (added in d163480, 2026-10-16). Each was a lazy.nvim spec for folke/snacks.nvim whose opts function patched dashboard.preset.keys in place. The egui spec looked for an existing key e and inserted before Quit. The Rust spec looked for an existing action :RustNewBin and inserted before the egui entry, falling back to before Quit.'),
    ...para('--', r'Both are reproduced here as two local functions, add_egui and add_rust, and the two spec files collapsed into one module. What changed is the ownership. In a configuration, patching the dashboard is the point of the file. In a plugin it would be presumptuous, so the patch became a function the user calls from their own snacks opts.'),
    ...sec(r'the entries'),
    ...code('lua', r'lua/xyno_new/dashboard.lua · lines 1-6, 9-15', r'''
-- Entries for the preset keys of snacks.nvim's dashboard: "New Rust Binary" (b),
-- "New Rust Library" (i), "New Rust Workspace" (w) and "New egui Project" (e). Opt-in:
-- nothing calls this unless you do (xyno_new.dashboard_keys(keys)).
-- The stock keys of the LazyVim dashboard use f n p g r c s x l q; the four above are free.
-- "New egui Project" goes right before "Quit" (else last); the three Rust entries go right
-- before "New egui Project" (else before "Quit", else last).
...
M.rust_entries = {
  { icon = "\xef\x92\x89 ", key = "b", desc = "New Rust Binary", action = ":RustNewBin" },
  { icon = "\xef\x80\xaa ", key = "i", desc = "New Rust Library", action = ":RustNewLib" },
  { icon = "\xf3\xb0\x99\x85 ", key = "w", desc = "New Rust Workspace", action = ":RustNewWorkspace" },
}

M.egui_entry = { icon = "\xf3\xb0\x8f\x97 ", key = "e", desc = "New egui Project", action = ":EguiNew" }'''),
    ...para('--', r'The header comment states the layout rule in one breath and also records a fact about LazyVim’s stock dashboard: its keys use f n p g r c s x l q, so b, i, w and e are free. The comment is the reason these letters were chosen; the spec checks that no key repeats by building a six-entry list that imitates the stock one (its keys are f n g r L q) and asserting unique keys.'),
    ...para('--', r'The icons are written as UTF-8 byte escapes (\xef\x92\x89 and so on) instead of pasted glyphs. A Nerd Font glyph pasted into source is invisible in many editors, easy to damage in a copy, and unreadable in a diff. The escapes survive any tool, at the price of needing a Nerd Font to see anything useful on the dashboard. The tests insist on distinct, non-empty icons, so a copy-paste collision between two entries fails.'),
    ...para('--', r'Each entry is a plain table with icon, key, desc and action, which is the shape snacks.nvim expects in preset.keys. The action is the string :RustNewBin and so on, an Ex command, so the entry works without any Lua callback and is visible in the dashboard config as what it does.'),
    ...sec(r'placing the egui entry'),
    ...code('lua', r'lua/xyno_new/dashboard.lua · lines 17-31', r'''
local function add_egui(keys)
  for _, k in ipairs(keys) do
    if k.key == "e" then
      return
    end
  end
  local at = #keys + 1
  for i, k in ipairs(keys) do
    if k.desc == "Quit" then
      at = i
      break
    end
  end
  table.insert(keys, at, vim.deepcopy(M.egui_entry))
end'''),
    ...para('--', r'Two guards and a search. The first loop returns if any entry already uses the key e. That makes the function idempotent, and it is the reason the README can say an existing key e is respected: if you bound e to an explorer, the egui entry is simply not added, and the three Rust entries still are. The second loop finds the position of the entry whose description is Quit. Default position is the end of the list.'),
    ...para('--', r'The insertion is a vim.deepcopy of the module table. Without the copy, the dashboard would share a table with M.egui_entry, and a later edit of the dashboard entry (a user changing its icon) would mutate the plugin’s data. The spec “the entries do not alias the module tables” changes keys[6].desc and checks the original is untouched.'),
    ...sec(r'placing the Rust entries relative to egui'),
    ...code('lua', r'lua/xyno_new/dashboard.lua · lines 33-51', r'''
local function add_rust(keys)
  for _, k in ipairs(keys) do
    if k.action == ":RustNewBin" then
      return
    end
  end
  local at = #keys + 1
  for i, k in ipairs(keys) do
    if k.desc == "New egui Project" then
      at = i
      break
    elseif k.desc == "Quit" then
      at = i
    end
  end
  for n, e in ipairs(M.rust_entries) do
    table.insert(keys, at + n - 1, vim.deepcopy(e))
  end
end'''),
    ...para('--', r'This loop is subtler than it looks. It remembers the position of Quit, but if it meets New egui Project it takes that position and breaks. So the Rust three go right before the egui entry when it exists, and otherwise right before Quit, otherwise last. Without the break the loop would continue and a later Quit could override the egui position; with it, an egui entry wins.'),
    ...para('--', r'The order of add_egui first, add_rust second matters for the same reason, and keys() calls them in that order. Starting from a stock list ending in Quit, the result is …, b, i, w, e, Quit, as the spec “the existing entries are unchanged and keep their order” asserts: f n g r L b i w e q.'),
    ...para('--', r'The insertion uses table.insert(keys, at + n - 1, …) so the three entries land consecutively and in their declared order. One more detail: add_rust returns early when an entry with the action :RustNewBin already exists, so the guard is on the action, not on the key. A user who rebinds New Rust Binary to a different letter still does not get duplicates.'),
    ...sec(r'the public function'),
    ...code('lua', r'lua/xyno_new/dashboard.lua · lines 53-62', r'''
--- Insert the entries into `keys` (a list of snacks dashboard keys; a new list when nil)
--- and return it. Idempotent.
---@param keys? table[]
---@return table[]
function M.keys(keys)
  keys = keys or {}
  add_egui(keys)
  add_rust(keys)
  return keys
end'''),
    ...para('--', r'keys is optional, the list is edited in place and returned. In place matters because snacks.nvim hands you its own table inside an opts function: assigning a new table would be fine too, but editing in place makes the function usable in both styles, and the README example does both (it passes the list in and assigns the result back). A nil argument yields a fresh list with just the four entries, which the spec asserts.'),
    ...sec(r'edge cases'),
    ...pt('--', r'called twice', r'second call finds key e and the :RustNewBin action, adds nothing. Tested with deepcopy and with the same list.'),
    ...pt('--', r'no Quit entry', r'entries go last: f, b, i, w, e in the spec.'),
    ...pt('--', r'key e taken by something else', r'the egui entry is skipped, the Rust entries still go before Quit (three positions before it in the spec).'),
    ...pt('--', r'plugin not loaded when a key is pressed', r'the entries run Ex commands that only exist after setup(); the README tells you to list the commands in lazy.nvim’s cmd or use lazy = false.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/dashboard_spec.lua has seven cases against a stock six-entry list that mimics LazyVim’s keys. It needs no snacks.nvim at all, which is the payoff of keeping this module pure list manipulation: the heaviest dependency in the optional feature set is not required to test it. Inserting four entries into six gives ten, and the spec asserts the length, the order, uniqueness of keys and icons, idempotence by comparing the first result with a second call on a copy and on the same list, in-place return identity (rawequal via ==), and non-aliasing.'),
    ...para('--', r'The one thing the specs do not check is rendering in a real dashboard. The README says this openly: the tmux rendering was verified by the original specs in xynovim’s config, not here.'),
    ...sec(r'history'),
    ...para('--', r'Added to this repository in 01f8e4c on 2026-10-22. In xynovim the egui half came with ddc51eb on 2026-10-15 and the Rust half with d163480 on 2026-10-16. That same d163480 commit also edited lua/plugins/editing-ui.lua: the dashboard’s layout threshold had been a fixed 36 rows and became 2n + 11 for n entries (39 rows for the 14 entries xynovim then had), because adding entries pushed the footer off an 80x24 terminal. That is a concern of the author’s configuration and is not part of this plugin: if you add four entries to a dashboard on a short terminal, your own layout needs the same thought.'),
  ],
);
