import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/editing-ui.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'editing-ui.lua — the small things the field test would not let go'),
    cm('--', r'diagnostics, taplo, snippets, noice, dashboard, pickers, outline, which-key'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'a set of option overrides for editing and UI details found in the field test'),
    kv(r'language', r'Lua, a lazy.nvim spec list of ten entries (nine plugins)'),
    kv(r'size', r'214 lines, 6 commits (99acd7e, 2026-10-13 to d163480, 2026-10-16)'),
    kv(r'plugins', r'nvim-lspconfig (twice), blink.cmp, noice, snacks, LazyVim, neotest, claudecode, kulala, which-key'),
    kv(r'helpers in lua/config', r'ux.diagnostic_text, ux.snippets_allowed, rust_assist.rename_file'),
    ...sec(r'why this file exists'),
    ...para('--',
        r'The header of the file is its own summary: editing and UI details from the field test: '
        r'diagnostic virtual text, the snippet source, the Cargo.toml schema, which-key group names. '
        r'The file is a place for fixes that are each too small for a file and each too specific for '
        r'the plugin they patch. Every block has a comment that describes what was seen first and '
        r'then what the setting does about it, and this page follows the same order.'),
    blank,
    ...para('--',
        r'The reading rule for the whole file: it is all option merging. lazy.nvim merges the opts '
        r'of several specs for the same plugin, so this file adds to LazyVim’s defaults without '
        r'copying them. Where a value has to replace a default, as with the dashboard sections, the '
        r'file uses an opts function and assigns the field.'),
    ...sec(r'diagnostics: the first line, with a source'),
    ...code('lua', r'lua/plugins/editing-ui.lua · lines 3-20', r'''
return {
  -- Virtual text: the first line plus [source] (config.ux.diagnostic_text);
  -- bacon-ls sends the whole rendered clippy message (about 14 lines).
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = {
        -- LazyVim's default is false: rust-analyzer's instant tier only showed
        -- after <Esc>
        update_in_insert = true,
        virtual_text = {
          -- the source is part of the format ("if_many" put it in front)
          source = false,
          format = function(d)
            return require("config.ux").diagnostic_text(d)
          end,
        },
      },'''),
    blank,
    ...pt('--', r'update_in_insert = true',
        r'the comment says LazyVim’s default is false and that rust-analyzer’s instant tier only '
        r'showed after Esc. In this setup the diagnostics of the fast tier are wanted while typing.'),
    ...pt('--', r'source = false',
        r'the source is not left to nvim’s own formatting. The format function includes it (comment: '
        r'"if_many" put it in front), so the position is decided by one function.'),
    ...pt('--', r'format = ux.diagnostic_text',
        r'the formatter lives in lua/config/ux.lua. The comment above the block states what it '
        r'shows: the first line plus [source]. bacon-ls sends the whole rendered clippy message, '
        r'about 14 lines, which on a single line of virtual text would hide the code.'),
    ...para('--',
        r'ux.diagnostic_text also does duplicate removal. From the code (lines 37 to 49 of ux.lua): '
        r'for a diagnostic it looks at the other diagnostics on the same line from a different '
        r'namespace with the same key; when one of the pair has a code and the other does not, the '
        r'one with the code is kept, and otherwise the lower namespace wins. It returns nil for the '
        r'loser, which hides the duplicate. That is why the spec uses a function instead of a format '
        r'string. The test at tests/ux-menu-diagnostics-colourblind_spec.lua line 231 says "is the '
        r'virtual_text.format of the lspconfig opts".'),
    ...sec(r'taplo: root and schema'),
    ...code('lua', r'lua/plugins/editing-ui.lua · lines 21-54', r'''
      servers = {
        taplo = {
          -- Cargo.toml itself is a root (a lone crate without .git used to
          -- give no root: "this document has been excluded").
          root_markers = { ".taplo.toml", "taplo.toml", "Cargo.toml", ".git" },
          -- not for Cargo.lock (also filetype toml): taplo answered "this document
          -- has been excluded" there
          root_dir = function(bufnr, on_dir)
            if vim.fs.basename(vim.api.nvim_buf_get_name(bufnr)) == "Cargo.lock" then
              return
            end
            local root = vim.fs.root(bufnr, { ".taplo.toml", "taplo.toml", "Cargo.toml", ".git" })
            if root then
              on_dir(root)
            end
          end,
          settings = {
            evenBetterToml = {
              schema = {
                -- taplo 0.10.0 cannot parse the current SchemaStore catalog,
                -- and its default catalog URL is a 404. The "failed to fetch
                -- catalog" line in lsp.log stays: taplo fetches at initialize,
                -- before it reads these settings (init_options did not
                -- reach it). The one schema that matters is associated by
                -- hand: key completion, hover and `edtion = ...` errors.
                associations = {
                  ["^(.*/)?Cargo\\.toml$"] = "https://json.schemastore.org/cargo.json",
                },
              },
            },
          },
        },
      },
    },'''),
    blank,
    ...para('--',
        r'taplo is the TOML language server and it serves Cargo.toml here. Three separate problems '
        r'are solved in this block, each with a comment.'),
    blank,
    ...pt('--', r'root_markers and root_dir',
        r'Cargo.toml itself is a root. Without it a lone crate without .git gave no root and taplo '
        r'answered "this document has been excluded". root_dir is a function so that a Cargo.lock, '
        r'which also has the toml filetype, is refused: it returns without calling on_dir, so no '
        r'server starts for it. Tests: "taplo: root markers and the Cargo.toml schema association" '
        r'and "taplo is not started for Cargo.lock", and a third one that roots a lone Cargo.toml '
        r'and reports a misspelled edtion key (14b, optional, needs network).'),
    ...pt('--', r'the schema association',
        r'the comment explains it in four lines. taplo 0.10.0 cannot parse the current SchemaStore '
        r'catalog, and its default catalog URL is a 404. The "failed to fetch catalog" line in '
        r'lsp.log stays because taplo fetches at initialize, before it reads the settings; '
        r'init_options did not reach it. The one schema that matters is associated by hand with the '
        r'pattern ^(.*/)?Cargo\.toml$ pointing at json.schemastore.org/cargo.json. The result is key '
        r'completion, hover and errors on mistakes like `edtion = ...`.'),
    ...para('--',
        r'The comment stops at what was tried: it does not say whether a newer taplo makes the block '
        r'obsolete, so neither does this page.'),
    ...sec(r'snippets: not after a dot, not in strings'),
    ...code('lua', r'lua/plugins/editing-ui.lua · lines 57-73', r'''
  -- Snippets: never after `.` (friendly-snippets' `if` outranked
  -- rust-analyzer's `.if` postfix and expanded to `ok.if condition {`) and
  -- never inside strings or comments.
  {
    "saghen/blink.cmp",
    opts = {
      sources = {
        providers = {
          snippets = {
            should_show_items = function(ctx)
              return require("config.ux").snippets_allowed(ctx)
            end,
          },
        },
      },
    },
  },'''),
    blank,
    ...para('--',
        r'The comment names the case: friendly-snippets’ if outranked rust-analyzer’s .if postfix '
        r'completion and expanded to `ok.if condition {`. Snippets are therefore suppressed after a '
        r'dot and inside strings or comments. The provider hook should_show_items receives the '
        r'completion context, and the decision is delegated to ux.snippets_allowed.'),
    blank,
    ...para('--',
        r'ux.snippets_allowed has two checks. The text before the cursor must not match '
        r'[^%.]%.[%w_]*$, which means a dot followed by an identifier fragment, with the character '
        r'before the dot not being another dot so that a range like 0..n is not mistaken for a '
        r'method call. Then the treesitter node at the cursor is climbed upward; the comment in '
        r'ux.lua at line 95 notes that a literal ends at its closing quote, so a cursor behind the '
        r'string is outside it. The test file tests/snippets-completion-injections_spec.lua line 277 '
        r'asserts that the provider has should_show_items wired to ux.snippets_allowed.'),
    ...sec(r'noice: borders and the stale pending key'),
    ...code('lua', r'lua/plugins/editing-ui.lua · lines 75-99', r'''
  {
    "folke/noice.nvim",
    opts = function(_, opts)
      -- noice renders hover and signature help itself, so winborder does not
      -- reach them; this preset gives those floats the rounded border too.
      opts.presets = opts.presets or {}
      opts.presets.lsp_doc_border = true

      -- The statusline "showcmd" component (pending keys) never cleared:
      -- noice drops an empty msg_showmode but only stores an empty
      -- msg_showcmd, and the status API reads the history, so the last
      -- pending key stayed in the statusline. Remove it like showmode does.
      local Msg = require("noice.ui.msg")
      if not Msg.xynovim_showcmd then
        Msg.xynovim_showcmd = true
        local on_showcmd = Msg.on_showcmd
        Msg.on_showcmd = function(event, content)
          on_showcmd(event, content)
          if vim.tbl_isempty(content) then
            require("noice.message.manager").remove(Msg.get(event))
          end
        end
      end
    end,
  },'''),
    blank,
    ...pt('--', r'lsp_doc_border',
        r'noice renders hover and signature help itself, so the global winborder setting does not '
        r'reach them. This preset gives those floats the same rounded border. Test: "turns on '
        r'presets.lsp_doc_border" (ux spec line 626) and "winborder is rounded and pumblend 0" (line '
        r'661).'),
    ...pt('--', r'the showcmd patch',
        r'the comment says the statusline showcmd component never cleared. noice drops an empty '
        r'msg_showmode but only stores an empty msg_showcmd, and the status API reads the history, '
        r'so the last pending key stayed visible in the statusline. The fix wraps Msg.on_showcmd: '
        r'after the original runs, an empty content removes the stored message.'),
    ...para('--',
        r'The wrapper is guarded by a flag on the module table (Msg.xynovim_showcmd), because an '
        r'opts function can run more than once and a second wrapping would nest the wrapper. The '
        r'tests are "wraps Msg.on_showcmd once, a second evaluation does not wrap again" and "an '
        r'empty showcmd removes the message, a non-empty one is stored" (lines 631 and 641).'),
    ...sec(r'dashboard and pickers at small sizes'),
    ...code('lua', r'lua/plugins/editing-ui.lua · lines 101-132', r'''
  -- Dashboard: the stock layout (6 header lines, a blank line between the entries) needs 2n + 11
  -- rows for n entries (39 for today's 14: measured, the footer is the last line to disappear;
  -- 36 for the stock 10 entries); at 80x24 the last entries and the footer were cut off. On a
  -- shorter window the entries sit on consecutive lines (n + 12 rows with the header: 26), and
  -- below that the header goes, so every entry and its key stay on screen down to about 18 rows.
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      local function entries()
        return #((opts.dashboard.preset or {}).keys or {})
      end
      local function tall()
        return vim.o.lines >= 2 * entries() + 11
      end
      opts.dashboard = opts.dashboard or {}
      opts.dashboard.sections = {
        {
          section = "header",
          enabled = function()
            return vim.o.lines >= entries() + 12
          end,
        },
        { section = "keys", gap = 1, padding = 1, enabled = tall },
        {
          section = "keys",
          gap = 0,
          padding = 1,
          enabled = function()
            return not tall()
          end,
        },
        { section = "startup" },'''),
    blank,
    ...para('--',
        r'This block is a measurement written down. The comment says: the stock layout needs 2n + 11 '
        r'rows for n entries, 39 for today’s 14 entries (measured; the footer is the last line to '
        r'disappear), 36 for the stock 10. At 80x24 the last entries and the footer were cut off.'),
    blank,
    ...para('--',
        r'The solution in the code has three tiers. The header section shows when the window has at '
        r'least n + 12 lines. The keys section comes in two variants and only one is enabled: with a '
        r'gap of 1 between entries when the window is tall (lines at least 2n + 11), and with a gap '
        r'of 0 otherwise. Below that the header goes. The comment sums it up: every entry and its '
        r'key stay on screen down to about 18 rows. The functions entries() and tall() read the '
        r'preset at call time, so the entry count from the New Rust Binary, Library and Workspace '
        r'dashboard items (added in d163480, 2026-10-16) is included automatically.'),
    ...code('lua', r'lua/plugins/editing-ui.lua · lines 133-153', r'''
      }
      -- Pickers: below 120 columns snacks uses its `vertical` layout, which asks for
      -- min_height = 30 and puts the preview in the lower 40%; at 80x24 the preview's
      -- last line overdrew the border row. A short window gets the preview-less
      -- `select` layout instead (snacks' `<A-p>` toggles the preview).
      opts.picker = opts.picker or {}
      -- Without a .gitignore (no git, or a fresh crate) the file picker listed all of
      -- target/ (313 of 318 items); anchored, so src/target/ stays.
      opts.picker.sources = vim.tbl_deep_extend("force", opts.picker.sources or {}, {
        files = { exclude = { "/target" } },
        grep = { exclude = { "/target" } },
      })
      opts.picker.layout = vim.tbl_deep_extend("force", opts.picker.layout or {}, {
        preset = function()
          if vim.o.columns >= 120 then
            return "default"
          end
          return vim.o.lines < 30 and "select" or "vertical"
        end,
      })
    end,'''),
    blank,
    ...para('--',
        r'The second half is about pickers. Below 120 columns snacks uses its vertical layout, which '
        r'asks for min_height = 30 with the preview in the lower 40%. At 80x24 the last preview line '
        r'overdrew the border row. So the layout preset is a function: the default layout at 120 '
        r'columns or more, the preview-less select layout below 30 lines, and vertical in between. '
        r'Alt-p toggles the preview in snacks.'),
    blank,
    ...para('--',
        r'The other picker fix is one line each for files and grep: exclude = { "/target" }. Without '
        r'a .gitignore (no git, or a fresh crate) the file picker listed all of target/ (313 of 318 '
        r'items). The pattern is anchored with the slash, so a directory called src/target stays '
        r'visible. The test: "the file and grep pickers exclude an anchored /target (no .gitignore '
        r'needed)" at line 762 of the ux spec.'),
    ...sec(r'the document outline and impl blocks'),
    ...code('lua', r'lua/plugins/editing-ui.lua · lines 156-168', r'''
  -- Document outline (<leader>cs / <leader>ss): rust-analyzer reports `impl Trait for X` as
  -- SymbolKind Object, which LazyVim's default kind filter drops, so the methods of every
  -- impl showed up at the top level without their owner.
  {
    "LazyVim/LazyVim",
    opts = function(_, opts)
      opts.kind_filter = opts.kind_filter or {}
      opts.kind_filter.rust = {
        "Class", "Constructor", "Enum", "Field", "Function", "Interface", "Method", "Module",
        "Namespace", "Object", "Package", "Property", "Struct", "Trait",
      }
    end,
  },'''),
    blank,
    ...para('--',
        r'rust-analyzer reports `impl Trait for X` as SymbolKind Object. LazyVim’s default kind '
        r'filter drops Object, so the methods of every impl appeared at the top level without their '
        r'owner. The fix sets the filter for the rust filetype to the default kinds plus Object (the '
        r'list in the code). The test at ux spec line 773 is "the rust kind filter of the document '
        r'outline contains Object (impl blocks) on top of the default".'),
    ...sec(r'the stubs that swallowed the which-key popup'),
    ...code('lua', r'lua/plugins/editing-ui.lua · lines 170-182', r'''
  -- <leader>9 is the 99 agent (ninety-nine.lua); it had no group name.
  -- LazyVim's extras declare empty-rhs `keys` stubs for the group prefixes (neotest
  -- <leader>t, claudecode <leader>a, kulala <leader>R). lazy.nvim turns each into a real
  -- no-op mapping that shadowed which-key's trigger: typed fast (`Space t` in one send-keys)
  -- no popup appeared (deleting the mapping brought it back). The stubs are switched off
  -- here, the groups are named through which-key's spec below.
  -- LazyVim's LSP keymaps bind <leader>cR to Snacks' rename (an fs rename that overwrote an
  -- existing destination) and re-apply it on every (dynamic) capability registration; the same
  -- key here replaces it (keys merge by lhs). keymaps.lua sets it on rust-analyzer attach too.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {'''),
    blank,
    ...para('--',
        r'This is the longest comment in the file, and it describes a bug with a precise mechanism. '
        r'LazyVim’s extras declare keys with an empty right-hand side as stubs for group prefixes: '
        r'neotest on <leader>t, claudecode on <leader>a, kulala on <leader>R. lazy.nvim turns each '
        r'one into a real no-op mapping, and that mapping shadowed which-key’s trigger. Typed fast '
        r'("Space t" in one send-keys) no popup appeared; deleting the mapping brought it back.'),
    blank,
    ...para('--',
        r'The fix is in two parts. The stubs are disabled with keys = { { "<leader>t", false } }, '
        r'and so on for a and R (the a one in both normal and visual mode). The groups are named '
        r'through which-key’s spec instead. The tests assert there is no stub mapping on <leader>a, '
        r'<leader>t and <leader>R, or if there is one, that its description is which-key’s trigger '
        r'(keymaps-global spec lines 326 to 333 and 458 to 460).'),
    ...code('lua', r'lua/plugins/editing-ui.lua · lines 199-213', r'''
  { "nvim-neotest/neotest", keys = { { "<leader>t", false } } },
  { "coder/claudecode.nvim", keys = { { "<leader>a", false, mode = { "n", "v" } } } },
  { "mistweaverco/kulala.nvim", keys = { { "<leader>R", false } } },
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>9", group = "99 (agent)" },
        { "<leader>t", group = "test" },
        { "<leader>a", group = "ai", mode = { "n", "v" } },
        { "<leader>R", group = "rest" },
        { "<leader>r", group = "rust", mode = { "n", "x" } },
      },
    },
  },'''),
    blank,
    ...para('--',
        r'Two details about the which-key block. <leader>r is the Rust group, defined for normal and '
        r'visual mode. <leader>9 is the 99 agent group; the comment at line 170 says it "had no '
        r'group name".'),
    ...sec(r'the rename that overwrote files'),
    ...code('lua', r'lua/plugins/editing-ui.lua · lines 176-198', r'''
  -- LazyVim's LSP keymaps bind <leader>cR to Snacks' rename (an fs rename that overwrote an
  -- existing destination) and re-apply it on every (dynamic) capability registration; the same
  -- key here replaces it (keys merge by lhs). keymaps.lua sets it on rust-analyzer attach too.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ["*"] = {
          keys = {
            {
              "<leader>cR",
              function()
                require("config.rust_assist").rename_file()
              end,
              desc = "Rename File",
              mode = { "n" },
              has = { "workspace/didRenameFiles", "workspace/willRenameFiles" },
            },
          },
        },
      },
    },
  },'''),
    blank,
    ...para('--',
        r'The last paragraph of the big comment has a separate story. LazyVim’s LSP keymaps bind '
        r'<leader>cR to Snacks’ rename, an fs rename that overwrote an existing destination, and '
        r're-apply it on every dynamic capability registration. Defining the same key under '
        r'servers["*"].keys replaces it, because keys merge by their left-hand side. The replacement '
        r'calls config.rust_assist.rename_file, and the has field restricts it to servers that '
        r'support workspace/didRenameFiles or willRenameFiles. The comment adds that keymaps.lua '
        r'sets the key on rust-analyzer attach as well.'),
    blank,
    ...para('--',
        r'Test: "<leader>cR becomes LazyVim’s ’Rename File’ as a buffer map after rust-analyzer '
        r'attaches" (keymaps-global spec line 667). A second test in rust-analyzer-config_spec line '
        r'609 uses the Snacks path to show that the mod edit from willRenameFiles still happens.'),
    ...sec(r'design decisions'),
    ...pt('--', r'merge, do not copy',
        r'every block adds only what differs from LazyVim, so upgrading LazyVim keeps its changes.'),
    ...pt('--', r'a helper module per behaviour',
        r'the formatting and snippet decisions live in lua/config/ux.lua so they can be unit-tested '
        r'without starting the plugin.'),
    ...pt('--', r'numbers in comments',
        r'the dashboard comment states the measured row counts, so the next person can see how the '
        r'formula was derived.'),
    ...sec(r'history'),
    ...pt('--', r'99acd7e (2026-10-13)',
        r'"Batch 4: editing and UI", the first commit: lifetime-safe quote, virtual text first line '
        r'and dedupe, snippet guard, rounded floats, the taplo Cargo schema, dashboard 80x24, '
        r'showcmd and more.'),
    ...pt('--', r'98c9bb4, a3d33c8, 3f868dd (2026-10-13)',
        r'three field-test rounds; round 2 lists "which-key groups, picker layout", round 3 lists '
        r'"which-key key stubs".'),
    ...pt('--', r'f31e013 (2026-10-14)',
        r'round 4: "picker target, outline impl blocks".'),
    ...pt('--', r'd163480 (2026-10-16)',
        r'New Rust Binary, Library and Workspace entries on the dashboard.'),
    ...sec(r'is it in xyno-plugins?'),
    ...para('--',
        r'No. This file configures upstream plugins. The helpers it calls are in lua/config/ux.lua '
        r'and lua/config/rust_assist.lua; neither is among the extracted plugins in '
        r'~/projects/xyno-plugins, and the :RustNew* commands that the dashboard entries launch are '
        r'in xyno-new.nvim.'),
  ],
);
