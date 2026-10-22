import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/rust-new.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust-new.lua — three more buttons on the start screen'),
    cm('--', r'New Rust Binary, Library and Workspace, placed before the egui entry'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'adds three entries to the snacks.nvim dashboard preset keys'),
    kv(r'language', r'Lua (lazy.nvim spec)'),
    kv(r'size', r'38 lines, 1 commit (d163480, 2026-10-16)'),
    kv(r'keys', r'b (binary), i (library), w (workspace)'),
    kv(r'actions', r':RustNewBin, :RustNewLib, :RustNewWorkspace, from lua/config/rust_new.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'It is the sibling of egui.lua and follows the same shape for three entries instead of one. The comment names which keys are taken: LazyVim’s stock keys use f n p g r c s x l q and the egui entry uses e, which leaves b, i and w free for binary, library and workspace. And it states the placement rule, which is the interesting part of the file.'),
    ...code('lua', r'lua/plugins/rust-new.lua · lines 1-4', r'''
-- "New Rust Binary / Library / Workspace" on the snacks dashboard (config/rust_new.lua,
-- :RustNewBin, :RustNewLib, :RustNewWorkspace). LazyVim's stock keys use f n p g r c s x l q and
-- the egui entry e; b (binary), i (library) and w (workspace) are free. The three sit
-- before "New egui Project" (which stays right before Quit), else before Quit.'''),
    ...sec(r'the data'),
    ...para('--', r'The three entries are a local table at the top, not code inside the function, so adding a fourth later is one more line. Each has an icon (Nerd Font glyphs), a key, a description and an action that is an Ex command.'),
    ...code('lua', r'lua/plugins/rust-new.lua · lines 5-9', r'''
local ENTRIES = {
  { icon = " ", key = "b", desc = "New Rust Binary", action = ":RustNewBin" },
  { icon = " ", key = "i", desc = "New Rust Library", action = ":RustNewLib" },
  { icon = "󰙅 ", key = "w", desc = "New Rust Workspace", action = ":RustNewWorkspace" },
}'''),
    ...sec(r'the placement rule'),
    ...para('--', r'The rule is: right before "New egui Project", otherwise right before "Quit", otherwise at the end. That is implemented with one pass over the list and a variable at that starts at the end of the list. When an entry with the description "New egui Project" is seen, at is set to its index and the loop stops. When an entry called "Quit" is seen it sets at, but the loop goes on, so an egui entry later in the list still wins. The three entries are then inserted at at, at + 1, at + 2 in order, each a deep copy so the shared table is never inserted into the list itself.'),
    ...code('lua', r'lua/plugins/rust-new.lua · lines 14-36', r'''
    opts = function(_, opts)
      opts.dashboard = opts.dashboard or {}
      opts.dashboard.preset = opts.dashboard.preset or {}
      local keys = opts.dashboard.preset.keys or {}
      opts.dashboard.preset.keys = keys
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
      for n, e in ipairs(ENTRIES) do
        table.insert(keys, at + n - 1, vim.deepcopy(e))
      end
    end,'''),
    ...pt('--', r'idempotence', r'the function returns early if any entry already has the action :RustNewBin. It tests the action rather than the key, so someone binding b to something else does not stop the entries being added, but a second evaluation of the same spec does not duplicate them.'),
    ...pt('--', r'vim.deepcopy', r'dashboard entries are tables that snacks may mutate while rendering; copying means the module-level ENTRIES list stays pristine across re-evaluation.'),
    ...pt('--', r'table.insert(keys, at + n - 1, ...)', r'inserting at consecutive positions keeps the three in the order b, i, w.'),
    ...sec(r'relation to the config module'),
    ...para('--', r'The spec knows only three command names. Everything else (prompts, cargo, the manifest editing, clean-up) is in lua/config/rust_new.lua, and :RustNewMember, the fourth command, has no dashboard key: it makes sense only inside an existing workspace, so it is reached by command or from the file.'),
    ...sec(r'in xyno-new.nvim'),
    ...para('--', r'lua/xyno_new/dashboard.lua holds the entries as M.rust_entries and M.egui_entry, and one function, M.keys(keys), applies both rules. It adds the egui entry first, then the Rust entries, with the same ordering logic; it is idempotent and creates the list when called without one. It is opt-in through xyno_new.dashboard_keys, so the repository’s two spec files (this one and egui.lua) collapse into one function that the user calls from their own snacks config. A spec in the plugin, tests/dashboard_spec.lua, covers it.'),
    ...sec(r'how it is tested'),
    ...para('--', r'The last describe block of tests/rust-new_spec.lua, "dashboard entries New Rust Binary / Library / Workspace", reads the merged preset: the three entries have the keys b, i, w and the right actions, unique keys and distinct icons, are consecutive and come before the egui entry, which stays right before Quit, and the stock keys are unchanged. Two more checks cover the layout thresholds that depend on how many entries there are (the same commit changed lua/plugins/editing-ui.lua for that), and the dashboard is rendered in tmux at several window sizes.'),
  ],
);
