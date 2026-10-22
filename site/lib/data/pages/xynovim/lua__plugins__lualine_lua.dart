import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/lualine.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'lua/plugins/lualine.lua — server readiness in the status line'),
    cm('--', r'14 lines that put rust-analyzer and clippy state next to the clock'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'lazy.nvim spec: add one component to lualine’s x section'),
    kv(r'language', r'Lua; one plugin spec with an opts function'),
    kv(r'size', r'14 lines, 1 commit (bdd0225, 2026-10-09)'),
    kv(r'reads', r'lua/config/lsp_status.lua (344 lines)'),
    kv(r'tested by', r'tests/server-supervision-statusline_spec.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'Rust has two kinds of slow feedback. rust-analyzer takes time to index a workspace, during which diagnostics and completions are incomplete. And clippy diagnostics, which in this configuration come from bacon-ls, arrive from a separate cargo run after you save. When the screen shows no errors it is useful to know whether that means "no errors" or "not finished yet". This file is the display half of the answer; the state tracking is done by lua/config/lsp_status.lua.'),
    ...code('lua', r'lua/plugins/lualine.lua · lines 1-14', r'''
-- Rust server readiness (rust-analyzer indexing / ready, bacon-ls clippy
-- running / stale) in the lualine x section; see config/lsp_status.lua.
return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    local status = require("config.lsp_status")
    table.insert(opts.sections.lualine_x, 1, {
      status.component,
      cond = function()
        return status.component() ~= ""
      end,
    })
  end,
}'''),
    ...sec(r'how it works'),
    ...para('--', r'The spec names lualine and supplies an opts function. lazy.nvim runs it with lualine’s options already assembled by LazyVim, and the function edits them in place. LazyVim defines opts.sections.lualine_x, the right hand section that holds things like the debug status, the lazy updates count and git diff. table.insert(list, 1, item) puts the new component at position one, so the readiness text appears at the left end of that section, closest to the middle of the bar and the file name. Everything LazyVim put there is kept, shifted one place right.'),
    ...para('--', r'The component is a table with two fields. The first element is a function, status.component, which lualine calls on every redraw of the status line to get a string. The second, cond, is lualine’s condition hook: if it returns false the whole component, including its separator, is not drawn. The condition here calls the same function and checks for an empty string. That means a buffer that has nothing to say gets no gap at all, instead of an empty pad with a separator.'),
    ...sec(r'what the string looks like'),
    ...para('--', r'status.component joins up to three parts with " | ": deps, rust_analyzer and bacon, in that order, each of which returns nil when it has nothing to report (for instance in a Lua buffer, where there is no rust-analyzer client). From reading lsp_status.lua, the strings include: "RA starting", "RA Indexing 42%", "RA loading", "RA ready", "RA ready (warn)", "RA error", "RA detached" (a lone script with no workspace), "RA stopped"; and for clippy "clippy running", "clippy failed", "clippy stale", "clippy 3E" (finished, with three errors on screen), "clippy ok", "clippy stopped". A Rust buffer therefore shows something like "RA ready | clippy ok", and the line disappears elsewhere. The spec asserts the stopped pair literally: "RA stopped | clippy stopped".'),
    ...para('--', r'The word "stale" is the interesting state. As the header of lsp_status.lua explains, it means the buffer’s text changed after the last finished clippy run started, so the clippy diagnostics you see predate your last edit. Edits are counted with nvim_buf_attach rather than b:changedtick, because a write also bumps the changedtick and the auto-save feature would then have left "stale" up for good.'),
    ...sec(r'why a function is called twice'),
    ...para('--', r'status.component() is evaluated in the cond and then again as the component text. On the status line these run for every redraw, so it matters that the function is cheap. The file lsp_status.lua is built for this: its header says it is purely event driven, with state updated by LspProgress, experimental/serverStatus, window/showMessage and TextChanged events, so the component only reads tables. There is one timer exception, for the "deps resolving" state after a Cargo.toml save, and the spec checks that no other timer exists. The cost of the double call is therefore two table walks per redraw, which is why the author could afford the simple cond.'),
    ...sec(r'where the logic lives now'),
    ...para('--', r'On 2026-10-22 the Rust tooling modules were extracted into standalone plugin repositories under ~/projects/xyno-plugins. lsp_status.lua is among them: xyno-rust.nvim contains lua/xyno_rust/lsp_status.lua, which I diffed against the copy in this repository. The only differences are renames: the module path (config.fsutil became xyno_rust.fsutil), the augroup (xyno_rust_lsp_status) and the buffer variable (xyno_rust_stopped instead of xynovim_stopped). The plugin’s README documents the replacement for this very file: with lualine, lualine_x = { require("xyno_rust.lsp_status").component }. This repository still contains its own config/lsp_status.lua and this spec still requires it, so the line above reads the local copy, not the plugin’s.'),
    ...sec(r'edge cases'),
    ...pt('--', r'no Rust in the buffer', r'both parts return nil, the joined string is empty, cond returns false, nothing is drawn.'),
    ...pt('--', r'a server that died', r'lsp_status reads a buffer variable that rust_restart.lua sets when a server exits, so the bar says "RA stopped" or "clippy stopped" even though the client is gone; a restart clears it on LspAttach.'),
    ...pt('--', r'opts.sections missing', r'the function indexes opts.sections.lualine_x without checking. It relies on LazyVim always defining it. If another spec removed that table the config would fail at startup with an index error, loudly rather than silently, which is the better failure for a status bar.'),
    ...pt('--', r'colour', r'the component sets no colour of its own. It inherits the colours of section x from the lualine theme (lua/lualine/themes/island-dark.lua), so state is carried by words, not by hue.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/server-supervision-statusline_spec.lua loads this file with dofile, calls its opts function on a fake options table whose lualine_x holds one entry, and checks that the entry is moved to position two, that item[1] is exactly status.component, and that cond() is false in a fresh scratch buffer and true once the buffer is flagged as having a stopped bacon_ls. If lualine is installed, it also checks that the running lualine configuration has the component at the front. The same spec covers the status strings themselves with fake LSP clients.'),
    ...sec(r'history'),
    ...pt('--', r'bdd0225 (2026-10-09)', r'"Roadmap step 11 wip: status, UX, health, CI, hygiene". The only commit that touches this file, created in the same work as lsp_status.lua and the health module. It has not changed since.'),
  ],
);
