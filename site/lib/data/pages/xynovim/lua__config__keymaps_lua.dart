import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/keymaps.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'keymaps.lua — the Rust key layer, bound when rust-analyzer attaches'),
    cm('--', 'stubs everywhere, real maps per buffer, a few globals at the end'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'hook where LazyVim loads user keymaps; holds all <leader>r Rust maps'),
    kv('language', 'Lua'),
    kv('size', '221 lines (3 lines of comment until 2026-10-09)'),
    kv('history', '16 commits, 1c496fd (2026-08-17) to 25086fd (2026-10-14)'),
    kv('tested by', 'tests/keymaps-global_spec.lua, tests/keymaps-rust_spec.lua'),

    ...sec('why this file exists'),
    ...para('--',
        r'For its first month this file held nothing but LazyVim’s three '
        r'comment lines: all keymaps were LazyVim’s, plus the lazy keys '
        r'declared in plugin specs. Then the Rust workflow grew '
        r'rust-analyzer commands that rustaceanvim exposes but nothing '
        r'bound (extract variable, inline, structural search, expand macro, '
        r'view HIR). 452e92c and the commits after it on 2026-10-09 filled '
        r'the file; by 2026-10-14 it is the single place where every '
        r'<leader>r key is defined. The three header lines are still at the '
        r'top, unchanged.'),
    ...para('--',
        r'The prefix is free by design. The comment says <leader>r is '
        r'unclaimed because the editor.refactoring extra is not enabled '
        r'(lazyvim.json has no such extra).'),

    ...sec('every key is buffer-local, so unbound keys need stubs'),
    ...code('lua', 'lua/config/keymaps.lua · lines 5-18 (stubs)', r'''
-- Global <leader>r<key> stubs: the r* maps below are buffer-local (rust-analyzer attached), so
-- in Cargo.toml / Lua / markdown buffers (and for a key nothing binds) Vim parsed <Space>rv as
-- `l` + `rv`, replaced a character and auto-save wrote it. A real buffer-local map wins. These
-- are per-key stubs, not one `<leader>r` leaf blocking in getcharstr(): such a leaf made which-key
-- skip its popup when `Space r` was typed at normal speed. which_key_ignore keeps them out of it.
local function not_bound(key)
  return function()
    local what = vim.bo.filetype == "rust" and " is not bound" or ": Rust maps work in Rust buffers only"
    vim.notify("<leader>r" .. key .. what, vim.log.levels.INFO)
  end
end
for _, key in ipairs(vim.split("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{};:'\",.<>/?|~`", "")) do
  vim.keymap.set({ "n", "x" }, "<leader>r" .. key, not_bound(key), { desc = "which_key_ignore" })
end'''),
    ...para('--',
        r'25086fd (2026-10-14, “Final loop round 5”) added this loop. '
        r'The rust maps only exist in buffers where rust-analyzer is '
        r'attached. In Cargo.toml, Lua or markdown, <Space>rv did not hit '
        r'a map: Vim parsed it as l followed by rv, which replaced the '
        r'character under the cursor, and auto-save then wrote it. The '
        r'spec case names the real incident: <Space>rv made “name” into '
        r'“nvme” in a Cargo.toml.'),
    ...para('--',
        r'The fix binds every ASCII letter, digit and listed punctuation key after <leader>r, in normal and '
        r'visual mode, to a stub that only notifies. A real buffer-local '
        r'map wins over a global one, so Rust buffers are unaffected. In '
        r'Rust buffers a key nothing binds says “is not bound”; elsewhere '
        r'it says Rust maps work in Rust buffers only. The comment also '
        r'records two rejected designs: one <leader>r leaf blocking in '
        r'getcharstr() made which-key skip its popup when Space r was typed '
        r'at normal speed, so per-key stubs are used instead, with the '
        r'description which_key_ignore to keep them out of the popup.'),

    ...sec('the attach hook'),
    ...code('lua', 'lua/config/keymaps.lua · lines 20-58 (LspAttach)', r'''
-- rust-analyzer commands that rustaceanvim exposes but nothing bound.
-- Buffer-local, set on rust-analyzer attach (scheduled so we also win over
-- the lang.rust extra's own on_attach maps). <leader>r is free: the
-- editor.refactoring extra is not enabled.
-- lang.rust's on_attach rebinds <leader>cR to RustLsp codeAction, LazyVim's LSP keys bind it to
-- Snacks' rename (an fs rename that overwrote an existing destination). Ours asks first; it is set
-- again when another client (bacon-ls) attaches later, because LazyVim's keys follow every attach.
local function set_rename(buf)
  vim.keymap.set("n", "<leader>cR", function()
    require("config.rust_assist").rename_file()
  end, { buffer = buf, desc = "Rename File" })
end

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("xynovim_rust_keymaps", { clear = true }),
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client.name ~= "rust-analyzer" and #vim.lsp.get_clients({ bufnr = ev.buf, name = "rust-analyzer" }) > 0 then
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(ev.buf) then
          set_rename(ev.buf)
        end
      end)
    end
    if not (client and client.name == "rust-analyzer") then
      return
    end
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(ev.buf) then
        return
      end
      local function map(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { buffer = ev.buf, desc = desc })
      end
      local function rust(cmd)
        return function()
          vim.cmd.RustLsp(cmd)
        end
      end'''),
    ...para('--',
        r'Everything below hangs on one LspAttach autocmd in the augroup '
        r'xynovim_rust_keymaps (clear = true, so re-sourcing is safe). The '
        r'comment states two reasons for vim.schedule: the maps must win '
        r'over the lang.rust extra’s own on_attach maps, which run in '
        r'the same event. And only a rust-analyzer client triggers the '
        r'bulk of the maps; any other client attaching later in a buffer '
        r'that already has rust-analyzer only re-applies <leader>cR.'),
    ...pt('--', '<leader>cR (3f868dd)',
        r'the comment gives the history. lang.rust rebinds cR to RustLsp '
        r'codeAction; LazyVim’s LSP keys bind it to Snacks’ rename, an fs '
        r'rename that overwrote an existing destination. The repository’s '
        r'version asks first (config.rust_assist.rename_file) and is set '
        r'again whenever another client such as bacon-ls attaches, '
        r'because LazyVim’s keys follow every attach.'),
    ...pt('--', 'helpers',
        r'map() writes a buffer-local mapping with a description; rust() '
        r'runs a :RustLsp subcommand; assist(pattern) calls '
        r'vim.lsp.buf.code_action with apply = true and a filter on the '
        r'action title, so the first matching assist runs with no menu.'),

    ...sec('refactor keys'),
    ...code('lua', 'lua/config/keymaps.lua · lines 71-118 (refactor)', r'''
      -- Refactor
      map({ "n", "x" }, "<leader>ra", function()
        vim.lsp.buf.code_action({ context = { only = { "refactor" }, diagnostics = {} } })
      end, "Refactor actions")
      map({ "n", "x" }, "<leader>rv", assist("^Extract into variable"), "Extract variable")
      map({ "n", "x" }, "<leader>rf", assist("^Extract into function"), "Extract function")
      map({ "n", "x" }, "<leader>rc", assist("^Extract into constant"), "Extract constant")
      -- rust-analyzer offers Extract Module only for a selection, so visual only.
      map("x", "<leader>rM", assist("^Extract [Mm]odule"), "Extract module (visual)")
      -- Without a mapping `<leader>r` + `M` is cursor-right plus `r M`: it
      -- replaced the character under the cursor and auto-save wrote it.
      map("n", "<leader>rM", function()
        vim.notify("Extract module: select code first (visual mode)", vim.log.levels.INFO)
      end, "Extract module (visual only)")
      -- "Inline macro" (cursor on println!) expanded silently: not matched.
      -- "Inline into all callers" (cursor on the fn declaration) deletes the definition and
      -- rewrote every call site silently (`helper(1) as usize` became `1 + 1 as usize`: rust-analyzer
      -- does not parenthesise), so that variant asks first.
      map({ "n", "x" }, "<leader>ri", function()
        vim.lsp.buf.code_action({
          apply = true,
          filter = function(a)
            if a.title:find("^Inline [^m]") == nil then
              return false
            end
            if a.title:find("all callers", 1, true) then
              return vim.fn.confirm(a.title .. "? The definition is deleted.", "&Yes\n&No", 2) == 1
            end
            return true
          end,
        })
      end, "Inline")
      -- Own prompt (rustaceanvim's reads the query before Snacks answers).
      map("n", "<leader>rs", function()
        require("config.rust_assist").ssr()
      end, "Structural search & replace")
      map("x", "<leader>rs", function()
        require("config.rust_assist").ssr(true)
      end, "Structural search & replace (selection)")
      map("n", "<leader>rj", rust("joinLines"), "Join lines (semantic)")
      map("x", "<leader>rj", ":RustLsp joinLines<CR>", "Join lines (semantic)")
      -- own request: :RustLsp moveItem expanded `$name` in the moved item as snippet variables
      map("n", "<A-j>", function()
        require("config.rust_assist").move_item("Down")
      end, "Move item down")
      map("n", "<A-k>", function()
        require("config.rust_assist").move_item("Up")
      end, "Move item up")'''),
    ...para('--',
        r'ra, rv, rf and rc are thin: a refactor menu and three assists '
        r'selected by title prefix (extract into variable, function or '
        r'constant). The interesting ones are the guarded ones.'),
    ...pt('--', 'rM, visual only (8779a6e, a08e66c)',
        r'rust-analyzer offers Extract Module only for a selection. In normal '
        r'mode <leader>rM used to be cursor-right plus r M, which replaced '
        r'the character under the cursor and auto-save wrote it, so a '
        r'normal-mode map now just says to select code first.'),
    ...pt('--', 'ri, inline',
        r'the filter matches titles starting with “Inline ” followed by '
        r'anything but m, which leaves out “Inline macro” (on println! it '
        r'expanded silently). The “Inline into all callers” variant, '
        r'offered on a function declaration, deletes the definition and '
        r'rewrote every call site without parentheses (helper(1) as usize '
        r'became 1 + 1 as usize), so it alone asks for confirmation, '
        r'defaulting to No (3f868dd).'),
    ...pt('--', 'rs, structural search and replace',
        r'goes through config.rust_assist.ssr instead of rustaceanvim’s '
        r'prompt, which reads the query before Snacks answers (8779a6e). '
        r'A visual variant passes the selection.'),
    ...pt('--', 'A-j and A-k, move item',
        r'config.rust_assist.move_item. The comment: :RustLsp moveItem '
        r'expanded $name in the moved item as snippet variables (3f868dd).'),

    ...sec('inspect, explain, symbols'),
    ...code('lua', 'lua/config/keymaps.lua · lines 120-163 (inspect)', r'''
      -- Inspect
      map("n", "<leader>rm", rust("expandMacro"), "Expand macro (recursive)")
      map("n", "<leader>rh", function()
        vim.cmd.RustLsp({ "view", "hir" })
      end, "View HIR")
      map("n", "<leader>rH", function()
        vim.cmd.RustLsp({ "view", "mir" })
      end, "View MIR")
      map("n", "<leader>rS", function()
        require("config.rust_assist").syntax_tree()
      end, "Syntax tree")
      map("n", "<leader>rp", rust("parentModule"), "Parent module")
      map("n", "<leader>rt", rust("relatedTests"), "Related tests")
      map("n", "<leader>rC", rust("openCargo"), "Open Cargo.toml")
      map("n", "<leader>rd", function()
        require("config.rust_assist").open_docs()
      end, "Open docs (local rustup, else docs.rs)")
      map("n", "<leader>rE", function()
        require("config.rust_assist").open_docs()
      end, "Open docs (same as rd)")
      map("x", "<leader>rk", function()
        vim.cmd.RustLsp({ "hover", "range" })
      end, "Hover range (type of selection)")
      map("n", "<leader>rk", function()
        vim.notify("Hover range: select code first (visual mode)", vim.log.levels.INFO)
      end, "Hover range (visual only)")

      -- Explain the E-code of any diagnostic on the line (rustc --explain)
      map("n", "<leader>re", function()
        require("config.rust_assist").explain_error()
      end, "Explain error code")

      -- Symbols: workspace only vs. including dependencies
      map("n", "<leader>rw", function()
        require("config.rust_assist").workspace_symbol()
      end, "Workspace symbol")
      map("n", "<leader>rW", function()
        require("config.rust_assist").workspace_symbol(true)
      end, "Workspace symbol (+ dependencies, all kinds)")

      -- neotest cannot run doctests (nextest): plain cargo test --doc
      map("n", "<leader>tD", function()
        require("config.rust_tasks").doctests()
      end, "Doctests (cargo test --doc)")'''),
    ...para('--',
        r'Mostly one-line bindings to :RustLsp (expandMacro, view hir and '
        r'mir, parentModule, relatedTests, openCargo). Several were “keys '
        r'that did nothing” until 8779a6e: rd and rE open docs through '
        r'rust_assist (local rustup docs, else docs.rs), re explains the '
        r'E-code of a diagnostic on the line, rw and rW open workspace '
        r'symbol prompts (the second including dependencies and all kinds), '
        r'and rS shows the syntax tree. tD runs plain cargo test --doc '
        r'because, as the comment says, neotest cannot run doctests under '
        r'nextest.'),

    ...sec('a live toggle and navigation'),
    ...code('lua', 'lua/config/keymaps.lua · lines 165-189 (rT, ru, rl, rF, rX, rZ, rN)', r'''
      -- Flip references.excludeTests live (rust-analyzer re-pulls config on
      -- didChangeConfiguration, answered from client.settings).
      map("n", "<leader>rT", function()
        local c = vim.lsp.get_clients({ bufnr = ev.buf, name = "rust-analyzer" })[1]
        if not c then
          return
        end
        local refs = c.settings["rust-analyzer"].references
        refs.excludeTests = not refs.excludeTests
        c:notify("workspace/didChangeConfiguration", { settings = c.settings })
        vim.notify("find usages: tests " .. (refs.excludeTests and "excluded" or "included"))
      end, "Toggle tests in find usages")

      map("n", "<leader>ru", function()
        require("config.rust_nav").goto_super()
      end, "Go to super method (trait item)")
      map("n", "<leader>rl", function()
        require("config.rust_nav").local_usages()
      end, "Usages in file (R/W)")

      map("n", "<leader>rF", "<cmd>RustContext<cr>", "Cargo features / target (both diagnostic tiers)")
      map("n", "<leader>rX", "<cmd>RustTargets<cr>", "Cargo targets: run / test / bench")

      map("n", "<leader>rZ", "<cmd>RustTools<cr>", "Cargo tools (deny, audit, bloat, timings, ...)")
      map("n", "<leader>rN", "<cmd>RustRoutes<cr>", "HTTP routes (axum / actix / rocket)")'''),
    ...para('--',
        r'rT flips references.excludeTests in the client’s settings and '
        r'sends workspace/didChangeConfiguration; the setting set in '
        r'lua/plugins/rustaceanvim.lua is therefore a starting point, not '
        r'a constant. ru and rl call config.rust_nav (go to the trait item '
        r'of a method, and usages in the file). The last four open the '
        r'Rust commands defined by other modules: :RustContext (cargo '
        r'features and target for both diagnostic tiers), :RustTargets, '
        r':RustTools and :RustRoutes. Those commands belong to '
        r'config.rust_context, rust_tasks and rust_routes, each with its '
        r'own page.'),

    ...sec('server keys and the group name'),
    ...code('lua', 'lua/config/keymaps.lua · lines 191-203 (server, which-key)', r'''
      -- Server
      map("n", "<leader>rR", rust("reloadWorkspace"), "Reload workspace")
      map("n", "<leader>rP", rust("rebuildProcMacros"), "Rebuild proc macros")

      -- (code actions: <leader>ca)
      set_rename(ev.buf)

      pcall(function()
        require("which-key").add({ { "<leader>r", group = "rust", buffer = ev.buf } })
      end)
    end)
  end,
})'''),
    ...para('--',
        r'rR reloads the workspace and rP rebuilds proc macros. The '
        r'which-key group name “rust” is registered per buffer with pcall, '
        r'so a missing which-key does not break the attach.'),

    ...sec('global keys at the end'),
    ...code('lua', 'lua/config/keymaps.lua · lines 205-221 (undotree, local history, colourblind)', r'''
-- Safety net: built-in undotree (0.12) and the git-ref based local history.
vim.keymap.set("n", "<leader>uu", function()
  vim.cmd.packadd("nvim.undotree")
  require("undotree").open()
end, { desc = "Undotree" })
vim.keymap.set("n", "<leader>gH", "<cmd>LocalHistory<cr>", { desc = "Local history (file)" })

-- Okabe-Ito diagnostic colours (off by default; also :ColorblindDiagnostics).
Snacks.toggle({
  name = "Colourblind diagnostics",
  get = function()
    return require("config.ux").colorblind_enabled()
  end,
  set = function(state)
    require("config.ux").colorblind(state)
  end,
}):map("<leader>uB")'''),
    ...para('--',
        r'Three global maps that are not Rust specific: <leader>uu opens '
        r'the built-in undotree of Neovim 0.12 (loaded with packadd '
        r'nvim.undotree), <leader>gH opens :LocalHistory (the git-ref '
        r'based history from config.local_history, 8e212cf), and '
        r'<leader>uB is a Snacks toggle for the Okabe-Ito colourblind '
        r'diagnostic colours (config.ux, bdd0225).'),

    ...sec('how it is tested'),
    ...para('--',
        r'tests/keymaps-global_spec.lua covers the layer from several '
        r'sides. A duplicate scan asserts that no scope, mode and lhs is '
        r'defined twice in the repository’s sources. Another asserts that '
        r'every global lazy key of the repo is live with the description '
        r'its source gives. The Rust cases check that the <leader>r maps '
        r'are buffer-local and the group is named “rust”, that <leader>cR '
        r'becomes LazyVim’s “Rename File” as a buffer map after '
        r'rust-analyzer attaches, that an unbound <leader>r key in '
        r'Cargo.toml notifies instead of editing the buffer, and that in a '
        r'Rust buffer it says the key is unbound.'),

    ...sec('limits'),
    ...pt('--', 'it only knows rust-analyzer by name',
        r'the guard client.name == “rust-analyzer” is exact. A renamed '
        r'client would get none of the maps.'),
    ...pt('--', 'one big autocmd',
        r'about 110 lines of mappings live inside a vim.schedule inside '
        r'a callback, which makes the file hard to unit test directly; the '
        r'specs test the result, not the function.'),
    ...pt('--', 'maps are re-created on every attach',
        r'attaching in each new Rust buffer rebuilds the same closures; '
        r'cheap, but not cached.'),

    blank,
    link('→ github.com/xynorash/xynovim', 'https://github.com/xynorash/xynovim'),
  ],
);
