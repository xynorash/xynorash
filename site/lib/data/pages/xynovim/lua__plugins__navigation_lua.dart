import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/navigation.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'navigation.lua — orientation: stripe, call tree, Rust surroundings, split/join'),
    cm('--', r'four small plugins tuned for reading and moving around code'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'tunes the navigation extras and adds satellite, call hierarchy keys and treesj'),
    kv(r'language', r'Lua, a lazy.nvim plugin spec list (four specs)'),
    kv(r'size', r'52 lines, 6 commits (b64aa27 to 0247401, 2026-10-09 to 2026-10-22)'),
    kv(r'roadmap', r'step 7'),
    kv(r'keys', r'<leader>cI, cO, cj; surround targets S O N D U'),
    ...sec(r'why this file exists'),
    ...para('--',
        r'The header says it: orientation and navigation add-ons (roadmap step 7). The extras for '
        r'sticky context, breadcrumbs, surround, doc stubs and rename preview are enabled in '
        r'lazyvim.json, and this file tunes them and adds the rest. It is a collection of four '
        r'unrelated plugins that share one job, helping a reader know where they are in a large Rust '
        r'file and move about it.'),
    ...sec(r'the error stripe: satellite.nvim'),
    ...code('lua', r'lua/plugins/navigation.lua · lines 5-15', r'''
  -- Error stripe: diagnostics, git hunks, search hits and marks on the
  -- scrollbar, inspired by the JetBrains right gutter.
  {
    "lewis6991/satellite.nvim",
    event = "VeryLazy",
    opts = {
      current_only = false,
      winblend = 60, -- the theme is transparent
      excluded_filetypes = { "neo-tree", "snacks_dashboard", "snacks_picker_list", "help", "lazy", "mason" },
    },
  },'''),
    blank,
    ...para('--',
        r'satellite.nvim draws a thin scrollbar on the right with marks for diagnostics, git hunks, '
        r'search hits and editor marks. The comment says it is inspired by the JetBrains right '
        r'gutter. It loads on VeryLazy so it does not delay the first screen.'),
    blank,
    ...pt('--', r'current_only = false',
        r'marks are drawn in every window, not only the focused one.'),
    ...pt('--', r'winblend = 60',
        r'the comment gives the reason: the theme is transparent. A fully opaque scrollbar window '
        r'would show a solid block against the island theme.'),
    ...pt('--', r'excluded_filetypes',
        r'neo-tree, snacks_dashboard, snacks_picker_list, help, lazy and mason: windows where a '
        r'scrollbar is noise.'),
    ...sec(r'call hierarchy as a tree'),
    ...code('lua', r'lua/plugins/navigation.lua · lines 17-25', r'''
  -- Persistent call hierarchy (same idea as Ctrl+Alt+H in the JetBrains IDEs): gai/gao are flat lists.
  -- auto_refresh=false: the lsp_* sources refresh on CursorHold/BufEnter, which blanked the tree.
  {
    "folke/trouble.nvim",
    keys = {
      { "<leader>cI", "<cmd>Trouble lsp_incoming_calls toggle focus=true auto_refresh=false<cr>", desc = "Incoming calls (tree)" },
      { "<leader>cO", "<cmd>Trouble lsp_outgoing_calls toggle focus=true auto_refresh=false<cr>", desc = "Outgoing calls (tree)" },
    },
  },'''),
    blank,
    ...para('--',
        r'gai and gao are LazyVim’s incoming and outgoing call lists and the comment calls them '
        r'flat. A persistent tree view needs the Trouble sources lsp_incoming_calls and '
        r'lsp_outgoing_calls. The keys <leader>cI and <leader>cO open them with focus, toggled.'),
    blank,
    ...para('--',
        r'The detail that makes this entry interesting is auto_refresh=false. The comment on line 18 '
        r'explains it: the lsp_* sources refresh on CursorHold and BufEnter, and that blanked the '
        r'tree. A call hierarchy that vanishes when the cursor idles is useless, so the refresh is '
        r'switched off per command. This was a field-test finding (commit 3f868dd, 2026-10-13, whose '
        r'message lists "call hierarchy auto_refresh").'),
    ...sec(r'Rust-flavoured surroundings'),
    ...code('lua', r'lua/plugins/navigation.lua · lines 27-43', r'''
  -- Rust-flavoured surroundings on top of the coding.mini-surround extra
  -- (gsa/gsd/gsr): e.g. `gsaiwS` wraps the word in `Some(...)`.
  {
    "nvim-mini/mini.surround",
    opts = {
      -- Two-step patterns: a balanced match first (a lazy `.-` stopped at the
      -- first `)`: `gsdO` on Ok(vec![f(1), g(2)]) left `vec![f(1, g(2)])`), then
      -- the empty captures mark where the wrapper ends and begins.
      custom_surroundings = {
        S = { input = { "Some%b()", "^Some%(().*()%)$" }, output = { left = "Some(", right = ")" } },
        O = { input = { "Ok%b()", "^Ok%(().*()%)$" }, output = { left = "Ok(", right = ")" } },
        N = { input = { "Box::new%b()", "^Box::new%(().*()%)$" }, output = { left = "Box::new(", right = ")" } },
        D = { input = { "dbg!%b()", "^dbg!%(().*()%)$" }, output = { left = "dbg!(", right = ")" } },
        U = { input = { "unsafe%s*%b{}", "^unsafe%s*{ ?().-() ?}$" }, output = { left = "unsafe { ", right = " }" } },
      },
    },
  },'''),
    blank,
    ...para('--',
        r'mini.surround already provides gsa (add), gsd (delete) and gsr (replace). The '
        r'custom_surroundings table registers five new target characters named after Rust '
        r'constructs: S for Some( ), O for Ok( ), N for Box::new( ), D for dbg!( ) and U for unsafe '
        r'{ }. The comment’s example: gsaiwS wraps the word under the cursor in Some(...).'),
    blank,
    ...para('--',
        r'Each entry has an input and an output. The output is the text added by gsa. The input is a '
        r'pair of Lua patterns, and the comment on lines 32 to 34 explains why a pair: a first '
        r'pattern finds a balanced match, and a second one with empty captures marks where the '
        r'wrapper ends and where it begins. Lines 33 and 34 name the bug that a lazy match caused: '
        r'gsdO on Ok(vec![f(1), g(2)]) left vec![f(1, g(2)]) because a lazy .- stopped at the first '
        r'closing parenthesis.'),
    blank,
    ...pt('--', r'Some%b()',
        r'%b() is Lua’s balanced match for parentheses, so nested calls are handled properly.'),
    ...pt('--', r'^Some%(().*()%)$',
        r'anchored on both ends, with the two empty captures () marking the positions of the inner '
        r'text. mini.surround uses these positions to know what to delete.'),
    ...pt('--', r'the unsafe entry',
        r'unsafe%s*%b{} allows any whitespace between the keyword and the brace, and the second '
        r'pattern ^unsafe%s*{ ?().-() ?}$ treats an optional space inside the braces as part of the '
        r'wrapper. The output adds spaces: left "unsafe { " and right " }".'),
    ...sec(r'split and join'),
    ...code('lua', r'lua/plugins/navigation.lua · lines 45-51', r'''
  -- Syntax-aware split/join of argument lists, struct literals, match arms...
  {
    "Wansmer/treesj",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    keys = { { "<leader>cj", "<cmd>TSJToggle<cr>", desc = "Split/join (treesitter)" } },
    opts = { use_default_keymaps = false, max_join_length = 160 },
  },'''),
    blank,
    ...para('--',
        r'treesj does syntax-aware split and join of argument lists, struct literals, match arms and '
        r'similar lists, using treesitter, bound here to <leader>cj. use_default_keymaps = false '
        r'stops the plugin from claiming its own keys, and max_join_length = 160 caps how long a '
        r'joined line may become so that a join never produces a line longer than 160 columns.'),
    ...sec(r'design decisions'),
    ...pt('--', r'one file, four plugins',
        r'none of them deserves a file, and each shares the same lazy.nvim pattern: declare keys or '
        r'an event so nothing loads at startup.'),
    ...pt('--', r'the surround patterns are tested by behaviour',
        r'the spec feeds real keystrokes (gsdO and the others) into a buffer, since an earlier '
        r'version of the patterns was wrong for nested calls.'),
    ...pt('--', r'satellite is cosmetic',
        r'a stripe for orientation, so it loads last (VeryLazy) and is excluded from windows where '
        r'it would not help.'),
    ...sec(r'how it is tested'),
    ...pt('--', r'tests/startup-and-options_spec.lua',
        r'line 817: satellite.nvim is VeryLazy, with current_only off, winblend 60 and the excluded '
        r'filetypes. Line 825: <leader>cI and <leader>cO toggle the Trouble call hierarchy trees. '
        r'Line 857: the custom surroundings S, O, N, D, U exist with the documented patterns.'),
    ...pt('--', r'same file, lines 870 and 897',
        r'gsa, gsr and gsd work with the Rust surroundings, and S, O, N, D, U delete the right '
        r'wrapper when the content has its own brackets. Line 887 feeds gsdO. This is the regression '
        r'test for the nested-bracket bug described in the comment.'),
    ...pt('--', r'tests/keymaps-global_spec.lua',
        r'lines 91 to 93 list <leader>cI and <leader>cj with their descriptions as global keys.'),
    ...sec(r'history'),
    ...pt('--', r'b64aa27 (2026-10-09, "wip-s7a")',
        r'first version.'),
    ...pt('--', r'0494b52 (2026-10-12, field test fixes)',
        r'nav/search changes.'),
    ...pt('--', r'98c9bb4 (2026-10-13, round 1)',
        r'the commit message lists "balanced surround".'),
    ...pt('--', r'3f868dd (2026-10-13, round 3)',
        r'"call hierarchy auto_refresh".'),
    ...pt('--', r'0247401 (2026-10-22)',
        r'two comments reworded: the stripe is now described as inspired by the JetBrains right '
        r'gutter, and the call hierarchy as the same idea as Ctrl+Alt+H in the JetBrains IDEs, where '
        r'both named a specific IDE before.'),
    ...sec(r'is it in xyno-plugins?'),
    ...para('--',
        r'No. These are upstream plugins tuned for the editor, and none of the Rust-specific plugins '
        r'in xyno-plugins duplicates them.'),
  ],
);
