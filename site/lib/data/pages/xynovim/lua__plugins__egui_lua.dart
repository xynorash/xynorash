import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/egui.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'egui.lua — a button on the start screen'),
    cm('--', r'puts "New egui Project" on the snacks dashboard, before Quit'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'adds one entry to the snacks.nvim dashboard preset keys'),
    kv(r'language', r'Lua (lazy.nvim spec)'),
    kv(r'size', r'27 lines, 1 commit (ddc51eb, 2026-10-15)'),
    kv(r'key', r'e (the stock keys use f n g r c s x l q)'),
    kv(r'action', r':EguiNew, defined in lua/config/egui_new.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'The command :EguiNew works without this file. The point of the file is that the common way to start a project is to open the editor, look at the start screen and press a key. LazyVim’s start screen is snacks.nvim’s dashboard, and its preset keys are a list of tables. This spec inserts one more table into that list, from the plugin’s opts function.'),
    ...code('lua', r'lua/plugins/egui.lua · lines 1-4', r'''
-- "New egui Project" on the snacks dashboard (config/egui_new.lua, :EguiNew).
-- LazyVim's preset.keys list is extended in place, before "Quit"; the stock
-- keys use f n g r c s x l q, so `e` is free.
return {'''),
    ...sec(r'editing a list you do not own'),
    ...para('--', r'The spec returns an opts function that receives the already merged options and changes them in place. Three levels of the structure are created if missing (dashboard, preset, keys) so the function works whether or not anything has declared them yet. The function is written to be run any number of times and in any order relative to other specs that touch the same list.'),
    ...code('lua', r'lua/plugins/egui.lua · lines 8-25', r'''
      opts.dashboard = opts.dashboard or {}
      opts.dashboard.preset = opts.dashboard.preset or {}
      local keys = opts.dashboard.preset.keys or {}
      opts.dashboard.preset.keys = keys
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
      table.insert(keys, at, { icon = "󰏗 ", key = "e", desc = "New egui Project", action = ":EguiNew" })
    end,'''),
    ...pt('--', r'already there', r'if any existing entry already has the key e, the function returns without changing anything. This is the idempotence check. Notice that it tests the KEY and not the description, so a different tool that uses e is respected and nothing is shadowed.'),
    ...pt('--', r'where it goes', r'at the end of the list by default, or just before the entry whose desc is "Quit". The Quit item is searched by description, which is how the LazyVim preset names it. Putting new things before Quit keeps the screen ending in the expected place.'),
    ...pt('--', r'the entry', r'an icon (a Nerd Font glyph for a package), key "e", the description "New egui Project", and the action ":EguiNew". An action that is a string starting with a colon is run as an Ex command by snacks.'),
    ...para('--', r'The icon string ends with a space inside the quotes, in the source as in the rust-new entries; it is part of the string that snacks prints in the icon column.'),
    ...sec(r'ordering with rust-new.lua'),
    ...para('--', r'A second spec, lua/plugins/rust-new.lua, inserts three Rust entries into the same list. The two do not need to know about each other beyond one comment, and they stay correct in either order. If this file runs first, the list ends [..., New egui Project, Quit] and the Rust spec inserts its three before the egui entry. If the Rust spec runs first the three Rust entries sit before Quit, and this spec then inserts the egui entry before Quit, after them. Both give: Rust Binary, Rust Library, Rust Workspace, New egui Project, Quit.'),
    ...sec(r'in xyno-new.nvim'),
    ...para('--', r'The plugin version moved this logic to lua/xyno_new/dashboard.lua and made it opt-in: nothing happens unless the user calls require("xyno_new").dashboard_keys(keys) from their own snacks spec. The entry data (icon, key e, description, action) and the placement rule are the same. The function is exposed as M.keys(keys) and also creates the list if it was nil. The difference in outcome: in the plugin the start-screen button exists only if the user asks for it, whereas this spec always adds it.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/egui-new_spec.lua has a describe block "dashboard entry New egui Project" that reads the merged snacks.nvim options through lazy.nvim, checks the entry in the preset keys and the section layout, and renders the dashboard to look for the text. The rest of the spec covers the command.'),
  ],
);
